import Foundation
import Speech
import AVFoundation
import AppKit

final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechController()

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onSpeakStart: (() -> Void)?
    var onSpeakEnd: (() -> Void)?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var transcript = ""
    private var finished = true
    private var levelGate = Date.distantPast
    private var silenceWork: DispatchWorkItem?
    private var maxListenWork: DispatchWorkItem?
    private let synthesizer = AVSpeechSynthesizer()
    private var pendingUtterances = 0
    private(set) var isListening = false
    private(set) var isSpeaking = false

    /// 系统里最像“萌妹子”的中文女声；优先婷婷，其次 Siri 雨舒等。
    private lazy var preferredVoice: AVSpeechSynthesisVoice? = {
        // 明确指定“婷婷”，系统里最自然的中文女声；Siri 雨舒做备选。
        for identifier in [
            "com.apple.voice.compact.zh-CN.Tingting",
            "com.apple.ttsbundle.siri_yushu_zh-CN_compact"
        ] {
            if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
                return voice
            }
        }
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "zh-CN" || $0.language.hasPrefix("zh-CN") }
        for name in ["Tingting", "Yu-shu", "Shelley", "Sandy", "Flo", "Meijia"] {
            let matches = voices.filter { $0.name.hasPrefix(name) }
            if let best = matches.max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
                return best
            }
        }
        return voices.first ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Listening

    func start() {
        guard !isListening else { return }
        requestPermission { [weak self] granted, message in
            guard let self else { return }
            guard granted else {
                self.onError?(message ?? "没有麦克风/语音识别权限")
                return
            }
            self.beginRecognition()
        }
    }

    private func requestPermission(_ completion: @escaping (Bool, String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                let msg = status == .denied ? "语音识别权限被拒绝了。去 系统设置 → 隐私与安全性 → 语音识别 打开。" : "语音识别暂时不可用。"
                DispatchQueue.main.async { completion(false, msg) }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted, granted ? nil : "麦克风权限被拒绝了。去 系统设置 → 隐私与安全性 → 麦克风 打开。")
                }
            }
        }
    }

    private func beginRecognition() {
        guard !isListening else { return }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer() else {
            onError?("这台设备暂时用不了语音识别。")
            return
        }
        guard rec.isAvailable else {
            onError?("语音识别服务还没准备好，稍等一下再试。")
            return
        }
        recognizer = rec
        transcript = ""
        finished = false

        let engine = AVAudioEngine()
        self.engine = engine
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            onError?("没找到可用的麦克风。")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            self?.computeLevel(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            onError?("麦克风启动失败：\(error.localizedDescription)")
            cleanupAudio()
            return
        }

        isListening = true
        maxListenWork?.cancel()
        let maxWork = DispatchWorkItem { [weak self] in
            guard let self, self.isListening else { return }
            if self.transcript.isEmpty { self.cancel() } else { self.finish() }
        }
        maxListenWork = maxWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: maxWork)

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.transcript = text
                DispatchQueue.main.async {
                    self.onPartial?(text)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.scheduleSilenceFinish()
                    }
                }
                if result.isFinal {
                    self.deliverFinal(text)
                }
            }
            if let error, self.isListening {
                // 静音过久等情况：如果已经有文字就当作完成，否则报错
                if !self.transcript.isEmpty {
                    self.deliverFinal(self.transcript)
                } else {
                    self.isListening = false
                    self.cleanupAudio()
                    DispatchQueue.main.async { self.onError?("没听到声音：\(error.localizedDescription)") }
                }
            }
        }
    }

    private func scheduleSilenceFinish() {
        guard isListening else { return }
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isListening else { return }
            self.finish()
        }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    func finish() {
        guard isListening else { return }
        isListening = false
        silenceWork?.cancel()
        maxListenWork?.cancel()
        request?.endAudio()
        stopEngine()
        let text = transcript
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.deliverFinal(text)
        }
    }

    func cancel() {
        isListening = false
        finished = true
        silenceWork?.cancel()
        maxListenWork?.cancel()
        cleanupAudio()
    }

    /// 停止录音但保留已识别的文字（由 final 回调处理）
    func stopAudioOnly() {
        isListening = false
        stopEngine()
    }

    private func stopEngine() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        request = nil
        task?.cancel()
        task = nil
    }

    private func cleanupAudio() {
        silenceWork?.cancel()
        maxListenWork?.cancel()
        stopEngine()
        transcript = ""
    }

    private func deliverFinal(_ text: String) {
        guard !finished else { return }
        finished = true
        cleanupAudio()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async { self.onFinal?(trimmed) }
    }

    private func computeLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        var count = 0
        var i = 0
        while i < n {
            let v = channel[i]
            sum += v * v
            count += 1
            i += 4
        }
        guard count > 0 else { return }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 0.00001))
        let level = Double(min(1, max(0, (db + 55) / 55)))
        let now = Date()
        guard now.timeIntervalSince(levelGate) > 0.08 else { return }
        levelGate = now
        DispatchQueue.main.async { self.onLevel?(level) }
    }

    // MARK: - Speaking

    func speak(_ text: String, persona: Persona, mood: Mood = .idle) {
        stopSpeaking()
        let clean = SpeechController.cleanForSpeech(text)
        guard !clean.isEmpty else { return }
        let chunks = SpeechController.chunks(clean)
        guard !chunks.isEmpty else { return }

        isSpeaking = true
        pendingUtterances = chunks.count
        Store.shared.audit("tts voice=\(preferredVoice?.name ?? "nil") id=\(preferredVoice?.identifier ?? "-") chunks=\(chunks.count)")
        onSpeakStart?()

        for (index, chunk) in chunks.enumerated() {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = preferredVoice ?? AVSpeechSynthesisVoice(language: "zh-CN")
            let prosody = SpeechController.prosody(for: chunk, mood: mood, index: index)
            utterance.pitchMultiplier = Float(min(1.9, max(0.65, persona.voicePitch + prosody.pitch)))
            utterance.rate = Float(min(0.62, max(0.34, persona.voiceRate + prosody.rate)))
            utterance.volume = 0.96
            utterance.preUtteranceDelay = index == 0 ? 0.02 : 0.06
            utterance.postUtteranceDelay = prosody.pause
            synthesizer.speak(utterance)
        }
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        pendingUtterances = 0
        if isSpeaking {
            isSpeaking = false
            onSpeakEnd?()
        }
    }

    private struct Prosody {
        var pitch: Double = 0
        var rate: Double = 0
        var pause: Double = 0.02
    }

    private static func prosody(for chunk: String, mood: Mood, index: Int) -> Prosody {
        var p = Prosody()
        if chunk.contains("！") || chunk.contains("!") {
            p.pitch += 0.06; p.rate += 0.012
        }
        if chunk.contains("？") || chunk.contains("?") {
            p.pitch += 0.04; p.rate -= 0.004
        }
        if chunk.contains("…") || chunk.contains("...") {
            p.pitch -= 0.02; p.rate -= 0.03; p.pause += 0.08
        }
        if chunk.contains("，") || chunk.contains(",") {
            p.pause += 0.03
        }
        let soft = ["呜", "对不起", "别", "难过", "累", "哭", "疼"]
        let sharp = ["哼", "才不", "笨蛋", "讨厌", "随便", "略"]
        if soft.contains(where: { chunk.contains($0) }) {
            p.pitch -= 0.04; p.rate -= 0.03
        }
        if sharp.contains(where: { chunk.contains($0) }) {
            p.pitch += 0.045; p.rate += 0.015
        }
        switch mood {
        case .happy: p.pitch += 0.05; p.rate += 0.01
        case .shy: p.pitch -= 0.025; p.rate -= 0.015
        case .pouty: p.pitch += 0.035
        case .sleepy: p.pitch -= 0.08; p.rate -= 0.05
        case .surprised: p.pitch += 0.06
        default: break
        }
        // 轻微的逐句起伏，避免像播报
        p.pitch += sin(Double(index) * 1.7) * 0.012
        return p
    }

    /// 按标点切成短句；太长的再按逗号切，念起来更像活人。
    static func chunks(_ text: String) -> [String] {
        var raw: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if "。！？!?；;\n".contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { raw.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { raw.append(tail) }

        var out: [String] = []
        for piece in raw {
            if piece.count <= 46 {
                out.append(piece)
            } else {
                var buffer = ""
                for ch in piece {
                    buffer.append(ch)
                    if "，,、".contains(ch) && buffer.count >= 24 {
                        out.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                        buffer = ""
                    }
                }
                if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return out.filter { !$0.isEmpty }
    }

    static func cleanForSpeech(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: "代码就不念了。", options: .regularExpression)
        s = s.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*\\*([^*]*)\\*\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "#+\\s*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "[\\u{1F300}-\\u{1FAFF}\\u{2600}-\\u{27BF}]", with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        pendingUtterances = max(0, pendingUtterances - 1)
        guard pendingUtterances == 0 else { return }
        isSpeaking = false
        DispatchQueue.main.async { self.onSpeakEnd?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        pendingUtterances = 0
        isSpeaking = false
        DispatchQueue.main.async { self.onSpeakEnd?() }
    }
}
