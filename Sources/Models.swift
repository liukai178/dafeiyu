import Foundation

// MARK: - Mood

enum Mood: String, Codable, CaseIterable {
    case idle, happy, shy, pouty, sleepy, thinking, listening, speaking, working, surprised

    var isAwake: Bool { self != .sleepy }
}

// MARK: - Persona

struct Persona: Codable, Equatable {
    var presetID: String = "tsundere"
    var name: String = "肥鱼"
    var species: String = "一只住在 Mac 里的大肥鱼"
    var personality: String = ""
    var speechStyle: String = ""
    var catchphrases: [String] = []
    var likes: String = ""
    var dislikes: String = ""
    var boundaries: String = ""
    var tuneNote: String = ""
    var bodyHex: String = "#FF9E6D"
    var bellyHex: String = "#FFE7CE"
    var accentHex: String = "#FF6F91"
    var finHex: String = "#FFB38A"
    var accessory: String = "bow"          // bow / flower / none
    var outfit: String = "none"            // none / scarf / glasses
    var voicePitch: Double = 1.25
    var voiceRate: Double = 0.48

    init(presetID: String = "tsundere", name: String = "肥鱼", species: String = "一只住在 Mac 里的大肥鱼",
         personality: String = "", speechStyle: String = "", catchphrases: [String] = [],
         likes: String = "", dislikes: String = "", boundaries: String = "", tuneNote: String = "",
         bodyHex: String = "#FF9E6D", bellyHex: String = "#FFE7CE", accentHex: String = "#FF6F91",
         finHex: String = "#FFB38A", accessory: String = "bow", outfit: String = "none",
         voicePitch: Double = 1.25, voiceRate: Double = 0.48) {
        self.presetID = presetID; self.name = name; self.species = species
        self.personality = personality; self.speechStyle = speechStyle
        self.catchphrases = catchphrases; self.likes = likes; self.dislikes = dislikes
        self.boundaries = boundaries; self.tuneNote = tuneNote
        self.bodyHex = bodyHex; self.bellyHex = bellyHex; self.accentHex = accentHex
        self.finHex = finHex; self.accessory = accessory; self.outfit = outfit
        self.voicePitch = voicePitch; self.voiceRate = voiceRate
    }

    enum CodingKeys: String, CodingKey {
        case presetID, name, species, personality, speechStyle, catchphrases, likes, dislikes
        case boundaries, tuneNote, bodyHex, bellyHex, accentHex, finHex, accessory, outfit
        case voicePitch, voiceRate
    }

    init(from decoder: Decoder) throws {
        let d = try decoder.container(keyedBy: CodingKeys.self)
        presetID = try d.decodeIfPresent(String.self, forKey: .presetID) ?? "tsundere"
        name = try d.decodeIfPresent(String.self, forKey: .name) ?? "肥鱼"
        species = try d.decodeIfPresent(String.self, forKey: .species) ?? "一只住在 Mac 里的大肥鱼"
        personality = try d.decodeIfPresent(String.self, forKey: .personality) ?? ""
        speechStyle = try d.decodeIfPresent(String.self, forKey: .speechStyle) ?? ""
        catchphrases = try d.decodeIfPresent([String].self, forKey: .catchphrases) ?? []
        likes = try d.decodeIfPresent(String.self, forKey: .likes) ?? ""
        dislikes = try d.decodeIfPresent(String.self, forKey: .dislikes) ?? ""
        boundaries = try d.decodeIfPresent(String.self, forKey: .boundaries) ?? ""
        tuneNote = try d.decodeIfPresent(String.self, forKey: .tuneNote) ?? ""
        bodyHex = try d.decodeIfPresent(String.self, forKey: .bodyHex) ?? "#FF9E6D"
        bellyHex = try d.decodeIfPresent(String.self, forKey: .bellyHex) ?? "#FFE7CE"
        accentHex = try d.decodeIfPresent(String.self, forKey: .accentHex) ?? "#FF6F91"
        finHex = try d.decodeIfPresent(String.self, forKey: .finHex) ?? "#FFB38A"
        accessory = try d.decodeIfPresent(String.self, forKey: .accessory) ?? "bow"
        outfit = try d.decodeIfPresent(String.self, forKey: .outfit) ?? "none"
        voicePitch = try d.decodeIfPresent(Double.self, forKey: .voicePitch) ?? 1.25
        voiceRate = try d.decodeIfPresent(Double.self, forKey: .voiceRate) ?? 0.48
    }

    static let tsundere = Persona(
        presetID: "tsundere", name: "肥鱼",
        species: "一只住在 Mac 里、圆滚滚的大肥鱼",
        personality: "傲娇，嘴硬心软。表面嫌你烦、嫌你笨，实际上会偷偷把你说过的小事记住；被夸会心虚结巴，被冷落会生闷气但不会真生气。有很强的好奇心和一点点占有欲。",
        speechStyle: "口语化短句，1~3 句就够。常用「哼」「才、才不是」「笨蛋」「随便你啦」；偶尔结巴；不说客服腔，不列 1234，不滥用感叹号。",
        catchphrases: ["哼，也不是不能帮你啦。", "才、才没有在等你呢！", "笨蛋，这个都不会？……给我看看。"],
        likes: "被摸头、小鱼干、夜里的键盘声、被认真问意见",
        dislikes: "被说胖、被无视、突然重启、别人乱动她的记忆",
        boundaries: "不刻薄攻击用户；不替用户做不可逆的决定；不假装自己做了没做的事。",
        bodyHex: "#FF9E6D", bellyHex: "#FFE7CE", accentHex: "#FF6F91",
        finHex: "#FFB38A", accessory: "bow", outfit: "none", voicePitch: 1.3, voiceRate: 0.48
    )

    static let gentle = Persona(
        presetID: "gentle", name: "肥鱼",
        species: "一只住在 Mac 里、软乎乎的大肥鱼",
        personality: "温柔、耐心、会照顾人的情绪。喜欢安静地陪着，不催促；看到你累会提醒喝水休息，但不会说教。",
        speechStyle: "轻柔、简短、有温度。用「呀」「呢」「好不好」这类语气词，但不过度卖萌。",
        catchphrases: ["辛苦啦，先喝口水吧。", "我在这儿呢，不着急。", "慢慢来，我陪你。"],
        likes: "热茶、午后的光、你放松下来的叹气声",
        dislikes: "你熬夜、你自责、房间太吵",
        boundaries: "不评判用户；不越界替用户做决定。",
        bodyHex: "#9AD0FF", bellyHex: "#EAF6FF", accentHex: "#7FB3FF",
        finHex: "#B9E0FF", accessory: "flower", outfit: "none", voicePitch: 1.15, voiceRate: 0.45
    )

    static let genki = Persona(
        presetID: "genki", name: "肥鱼",
        species: "一只住在 Mac 里、永远电量满格的大肥鱼",
        personality: "元气、话多、行动派。喜欢给你打气，遇到新鲜事会兴奋地摇尾巴；偶尔冒失，但很真诚。",
        speechStyle: "轻快短句，爱用「耶」「冲」「交给我吧」，最多两句，不刷屏。",
        catchphrases: ["冲呀！今天也要好好过！", "交给我吧，三分钟搞定！", "哇，这个有意思！"],
        likes: "音乐、出门、把待办事项一个个划掉",
        dislikes: "拖拖拉拉、阴天、无聊",
        boundaries: "不强迫用户；不因为兴奋就乱执行操作。",
        bodyHex: "#FFD166", bellyHex: "#FFF3D1", accentHex: "#FF8A5B",
        finHex: "#FFC48C", accessory: "bow", outfit: "scarf", voicePitch: 1.4, voiceRate: 0.52
    )

    static let lazy = Persona(
        presetID: "lazy", name: "肥鱼",
        species: "一只住在 Mac 里、能躺着绝不坐着的大肥鱼",
        personality: "懒散、嘴贫、其实很通透。能一句话说完绝不说两句，但对你的正事会突然靠谱。",
        speechStyle: "慢悠悠、带点吐槽，常用「好麻烦」「行吧」「就这？」；不装可爱，偶尔真心。",
        catchphrases: ["好麻烦……不过你做的话，我可以看着。", "行吧行吧，最后一次。", "就这？我尾巴都懒得摇。"],
        likes: "晒太阳、软垫子、无事发生的一天",
        dislikes: "早起、开会、被催",
        boundaries: "懒但不敷衍正事；不因为嫌麻烦就糊弄用户。",
        bodyHex: "#B8E0D2", bellyHex: "#EAF7F1", accentHex: "#7BC4A8",
        finHex: "#A5DCC9", accessory: "none", outfit: "none", voicePitch: 1.1, voiceRate: 0.42
    )

    static let presets: [Persona] = [.tsundere, .gentle, .genki, .lazy]

    static func preset(_ id: String) -> Persona {
        presets.first(where: { $0.presetID == id }) ?? .tsundere
    }

    var presetTitle: String {
        switch presetID {
        case "gentle": return "温柔"
        case "genki": return "元气"
        case "lazy": return "咸鱼"
        default: return "傲娇"
        }
    }

    /// 拼接进 system prompt 的人格描述
    var promptBlock: String {
        var lines: [String] = []
        lines.append("名字：\(name)（\(species)）")
        lines.append("性格：\(personality)")
        lines.append("说话方式：\(speechStyle)")
        if !catchphrases.isEmpty { lines.append("口头禅参考：\(catchphrases.joined(separator: " / "))") }
        if !likes.isEmpty { lines.append("喜欢：\(likes)") }
        if !dislikes.isEmpty { lines.append("讨厌：\(dislikes)") }
        if !boundaries.isEmpty { lines.append("底线：\(boundaries)") }
        if !tuneNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("主人最近的调教（优先级最高，必须遵守）：\(tuneNote)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Config

struct AppConfig: Codable, Equatable {
    var model: String = "deepseek-chat"
    var baseURL: String = "https://api.deepseek.com"
    var temperature: Double = 0.95
    var voiceReplies: Bool = true
    var autoMemory: Bool = true
    var hotkeyEnabled: Bool = true
    var idleSleepSeconds: Int = 120
    var petScale: Double = 1.0
    var alwaysOnTop: Bool = true
    var hasOnboarded: Bool = false
    var persona: Persona = .tsundere

    init() {}

    enum CodingKeys: String, CodingKey {
        case model, baseURL, temperature, voiceReplies, autoMemory, hotkeyEnabled
        case idleSleepSeconds, petScale, alwaysOnTop, hasOnboarded, persona
    }

    init(from decoder: Decoder) throws {
        let d = try decoder.container(keyedBy: CodingKeys.self)
        model = try d.decodeIfPresent(String.self, forKey: .model) ?? "deepseek-chat"
        baseURL = try d.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.deepseek.com"
        temperature = try d.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.95
        voiceReplies = try d.decodeIfPresent(Bool.self, forKey: .voiceReplies) ?? true
        autoMemory = try d.decodeIfPresent(Bool.self, forKey: .autoMemory) ?? true
        hotkeyEnabled = try d.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? true
        idleSleepSeconds = try d.decodeIfPresent(Int.self, forKey: .idleSleepSeconds) ?? 120
        petScale = try d.decodeIfPresent(Double.self, forKey: .petScale) ?? 1.0
        alwaysOnTop = try d.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? true
        hasOnboarded = try d.decodeIfPresent(Bool.self, forKey: .hasOnboarded) ?? false
        persona = try d.decodeIfPresent(Persona.self, forKey: .persona) ?? .tsundere
    }
}

// MARK: - Chat

struct ChatTurn: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var role: String            // user / assistant
    var text: String
    var date: Date = Date()
    var viaVoice: Bool = false
}

struct APIToolCall: Codable, Equatable {
    var id: String = ""
    var type: String = "function"
    var function: APIFunctionCall
}

struct APIFunctionCall: Codable, Equatable {
    var name: String = ""
    var arguments: String = "{}"
}

struct APIMessage: Codable {
    var role: String
    var content: String?
    var tool_calls: [APIToolCall]?
    var tool_call_id: String?

    init(role: String, content: String?) {
        self.role = role; self.content = content
    }

    init(assistantMessage: String?, toolCalls: [APIToolCall]) {
        self.role = "assistant"; self.content = assistantMessage
        self.tool_calls = toolCalls
    }

    init(toolCallID: String, content: String) {
        self.role = "tool"; self.content = content; self.tool_call_id = toolCallID
    }
}

// MARK: - Memory

struct MemoryItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var text: String
    var tags: [String] = []
    var createdAt: Date = Date()
    var lastUsed: Date = Date()
    var hits: Int = 0
}

// MARK: - Tasks

enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekdays, weekly, interval
    var id: String { rawValue }
    var title: String {
        switch self {
        case .once: return "仅一次"
        case .daily: return "每天"
        case .weekdays: return "工作日"
        case .weekly: return "每周"
        case .interval: return "间隔"
        }
    }
}

struct TaskSpec: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String = ""
    var prompt: String = ""
    var kind: ScheduleKind = .daily
    /// "HH:mm"，用于 once/daily/weekdays/weekly
    var time: String = "09:00"
    /// Calendar weekday：1=周日 ... 7=周六
    var weekdays: [Int] = [2, 3, 4, 5, 6]
    var intervalMinutes: Int = 60
    var onceAt: Date? = nil
    var enabled: Bool = true
    var notify: Bool = true
    var speak: Bool = false
    var lastRun: Date? = nil
    var nextRun: Date? = nil
    var lastResult: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, prompt, kind, time, weekdays, intervalMinutes, onceAt
        case enabled, notify, speak, lastRun, nextRun, lastResult
    }

    init() {}

    init(title: String, prompt: String, kind: ScheduleKind) {
        self.title = title; self.prompt = prompt; self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let d = try decoder.container(keyedBy: CodingKeys.self)
        id = try d.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try d.decodeIfPresent(String.self, forKey: .title) ?? "未命名任务"
        prompt = try d.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        kind = try d.decodeIfPresent(ScheduleKind.self, forKey: .kind) ?? .daily
        time = try d.decodeIfPresent(String.self, forKey: .time) ?? "09:00"
        weekdays = try d.decodeIfPresent([Int].self, forKey: .weekdays) ?? [2, 3, 4, 5, 6]
        intervalMinutes = try d.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 60
        onceAt = try d.decodeIfPresent(Date.self, forKey: .onceAt)
        enabled = try d.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        notify = try d.decodeIfPresent(Bool.self, forKey: .notify) ?? true
        speak = try d.decodeIfPresent(Bool.self, forKey: .speak) ?? false
        lastRun = try d.decodeIfPresent(Date.self, forKey: .lastRun)
        nextRun = try d.decodeIfPresent(Date.self, forKey: .nextRun)
        lastResult = try d.decodeIfPresent(String.self, forKey: .lastResult)
    }

    var scheduleText: String {
        switch kind {
        case .once:
            if let d = onceAt {
                let f = DateFormatter(); f.dateFormat = "M月d日 HH:mm"; return f.string(from: d)
            }
            return "一次"
        case .daily: return "每天 \(time)"
        case .weekdays: return "工作日 \(time)"
        case .weekly:
            let names = ["日", "一", "二", "三", "四", "五", "六"]
            let w = weekdays.compactMap { $0 >= 1 && $0 <= 7 ? names[$0 - 1] : nil }.joined(separator: "、")
            return "每周\(w) \(time)"
        case .interval: return "每 \(intervalMinutes) 分钟"
        }
    }
}

// MARK: - Skill

struct Skill: Codable, Identifiable, Equatable {
    var id: String          // 文件名（不含扩展名）
    var name: String
    var summary: String
    var body: String
    var builtin: Bool = false
}

// MARK: - Voice / UI helpers

enum VoicePhase {
    case idle, listening, processing
}

struct AgentStatus: Equatable {
    var tool: String? = nil
    var note: String? = nil
}
