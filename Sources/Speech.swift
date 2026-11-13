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
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isListening = false
    private(set) var isSpeaking = false

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
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.transcript = text
                DispatchQueue.main.async { self.onPartial?(text) }
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

    func finish() {
        guard isListening else { return }
        isListening = false
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

    func speak(_ text: String, persona: Persona) {
        stopSpeaking()
        let clean = SpeechController.cleanForSpeech(text)
        guard !clean.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.pitchMultiplier = Float(min(2.0, max(0.5, persona.voicePitch)))
        utterance.rate = Float(min(0.6, max(0.35, persona.voiceRate)))
        utterance.preUtteranceDelay = 0.02
        isSpeaking = true
        onSpeakStart?()
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if isSpeaking {
            isSpeaking = false
            onSpeakEnd?()
        }
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
        isSpeaking = false
        DispatchQueue.main.async { self.onSpeakEnd?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        DispatchQueue.main.async { self.onSpeakEnd?() }
    }
}
