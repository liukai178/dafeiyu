import Foundation
import Security
import AppKit

// MARK: - Keychain

enum Keychain {
    static let service = "com.liukai.dafeiyu"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return true }
        var add = query
        add.merge(attrs) { _, new in new }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Store

final class Store: @unchecked Sendable {
    static let shared = Store()

    let root: URL
    private let lock = NSLock()
    private var _config = AppConfig()
    private var _memories: [MemoryItem] = []
    private var _tasks: [TaskSpec] = []
    private var _history: [ChatTurn] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static var defaultRoot: URL {
        if let p = ProcessInfo.processInfo.environment["DAFEIYU_HOME"], !p.isEmpty {
            return URL(fileURLWithPath: p)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DaFeiYu", isDirectory: true)
    }

    init() {
        root = Store.defaultRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("skills"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("logs"), withIntermediateDirectories: true)
        loadAll()
        ensureDefaultSkills()
    }

    private func loadAll() {
        if let c = read(AppConfig.self, "config.json") { _config = c }
        _memories = read([MemoryItem].self, "memory.json") ?? []
        _tasks = read([TaskSpec].self, "tasks.json") ?? []
        _history = read([ChatTurn].self, "chat_history.json") ?? []
        seedTasksIfNeeded()
    }

    private func seedTasksIfNeeded() {
        guard _tasks.isEmpty, !FileManager.default.fileExists(atPath: root.appendingPathComponent(".seeded").path) else { return }
        _tasks = []
        write(_tasks, "tasks.json")
        FileManager.default.createFile(atPath: root.appendingPathComponent(".seeded").path, contents: Data())
    }

    // MARK: Codable IO

    private func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        let target = url(name)
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            NSLog("DaFeiYu store write failed \(name): \(error)")
        }
    }

    // MARK: Config

    var config: AppConfig {
        get { lock.lock(); defer { lock.unlock() }; return _config }
        set {
            lock.lock(); _config = newValue; lock.unlock()
            write(newValue, "config.json")
        }
    }

    func updateConfig(_ mutate: (inout AppConfig) -> Void) {
        lock.lock()
        var c = _config
        mutate(&c)
        _config = c
        lock.unlock()
        write(c, "config.json")
    }

    // MARK: API key

    private var keyFileURLs: [URL] {
        [root.appendingPathComponent("deepseek.key"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dafeiyu.key")]
    }

    var apiKey: String? {
        if let k = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !k.isEmpty { return k }
        if let k = Keychain.read("deepseek-api-key"), !k.isEmpty { return k }
        for f in keyFileURLs {
            if let k = try? String(contentsOf: f, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
                return k
            }
        }
        return nil
    }

    @discardableResult
    func setAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete("deepseek-api-key")
            for f in keyFileURLs { try? FileManager.default.removeItem(at: f) }
            return true
        }
        let ok = Keychain.write(trimmed, account: "deepseek-api-key")
        // 同时给一个纯文本兜底，方便用户/自动化工具替换（权限 600）
        if let f = keyFileURLs.first {
            try? trimmed.write(to: f, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
        }
        return ok
    }

    var maskedKey: String {
        guard let k = apiKey, !k.isEmpty else { return "未配置" }
        if k.count <= 10 { return "••••••" }
        return "\(k.prefix(6))…\(k.suffix(4))"
    }

    // MARK: Memory

    var memories: [MemoryItem] {
        lock.lock(); defer { lock.unlock() }
        return _memories.sorted { $0.createdAt > $1.createdAt }
    }

    func addMemory(text: String, tags: [String] = []) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lock.lock()
        if let idx = _memories.firstIndex(where: { $0.text == t }) {
            _memories[idx].hits += 1
            _memories[idx].lastUsed = Date()
        } else {
            _memories.append(MemoryItem(text: t, tags: tags))
            if _memories.count > 300 {
                _memories.sort { $0.lastUsed < $1.lastUsed }
                _memories.removeFirst(_memories.count - 300)
            }
        }
        let snapshot = _memories
        lock.unlock()
        write(snapshot, "memory.json")
    }

    func removeMemory(id: String) {
        lock.lock()
        _memories.removeAll { $0.id == id }
        let snapshot = _memories
        lock.unlock()
        write(snapshot, "memory.json")
    }

    func clearMemories() {
        lock.lock(); _memories = []; lock.unlock()
        write([MemoryItem](), "memory.json")
    }

    func searchMemories(_ query: String, limit: Int = 6) -> [MemoryItem] {
        lock.lock()
        let items = _memories
        lock.unlock()
        let q = query.lowercased()
        let tokens = q.split(whereSeparator: { " ，,。.！!？?、;；:：\n\t".contains($0) })
            .map(String.init).filter { $0.count >= 2 }
        func score(_ m: MemoryItem) -> Double {
            let text = (m.text + " " + m.tags.joined(separator: " ")).lowercased()
            var s = 0.0
            for t in tokens where text.contains(t) { s += 2 }
            if !q.isEmpty, text.contains(q) { s += 3 }
            let days = max(0, Date().timeIntervalSince(m.lastUsed) / 86400)
            s += max(0, 1.2 - days * 0.02)
            s += min(1.0, Double(m.hits) * 0.1)
            return s
        }
        return items.map { ($0, score($0)) }
            .filter { $0.1 > 0.5 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: Tasks

    var tasks: [TaskSpec] {
        lock.lock(); defer { lock.unlock() }
        return _tasks.sorted { ($0.nextRun ?? .distantFuture) < ($1.nextRun ?? .distantFuture) }
    }

    func task(id: String) -> TaskSpec? {
        lock.lock(); defer { lock.unlock() }
        return _tasks.first { $0.id == id }
    }

    func upsertTask(_ task: TaskSpec) {
        lock.lock()
        if let i = _tasks.firstIndex(where: { $0.id == task.id }) { _tasks[i] = task } else { _tasks.append(task) }
        let snapshot = _tasks
        lock.unlock()
        write(snapshot, "tasks.json")
    }

    func deleteTask(id: String) {
        lock.lock()
        _tasks.removeAll { $0.id == id }
        let snapshot = _tasks
        lock.unlock()
        write(snapshot, "tasks.json")
    }

    func recordTaskRun(id: String, at date: Date, result: String, next: Date?) {
        lock.lock()
        if let i = _tasks.firstIndex(where: { $0.id == id }) {
            _tasks[i].lastRun = date
            _tasks[i].lastResult = String(result.prefix(4000))
            _tasks[i].nextRun = next
            if _tasks[i].kind == .once { _tasks[i].enabled = false }
        }
        let snapshot = _tasks
        lock.unlock()
        write(snapshot, "tasks.json")
    }

    // MARK: History

    var history: [ChatTurn] {
        lock.lock(); defer { lock.unlock() }
        return _history
    }

    func appendHistory(_ turn: ChatTurn) {
        lock.lock()
        _history.append(turn)
        if _history.count > 60 { _history.removeFirst(_history.count - 60) }
        let snapshot = _history
        lock.unlock()
        write(snapshot, "chat_history.json")
    }

    func clearHistory() {
        lock.lock(); _history = []; lock.unlock()
        write([ChatTurn](), "chat_history.json")
    }

    // MARK: Skills

    private func parseSkill(id: String, builtin: Bool) -> Skill? {
        let f = root.appendingPathComponent("skills/\(id).md")
        guard let raw = try? String(contentsOf: f, encoding: .utf8) else { return nil }
        var name = id
        var summary = ""
        var body = raw
        if raw.hasPrefix("---") {
            let parts = raw.components(separatedBy: "---")
            if parts.count >= 3 {
                let front = parts[1]
                body = parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
                for line in front.components(separatedBy: .newlines) {
                    let kv = line.split(separator: ":", maxSplits: 1).map(String.init)
                    guard kv.count == 2 else { continue }
                    let k = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
                    let v = kv[1].trimmingCharacters(in: .whitespaces)
                    if k == "name" { name = v }
                    if k == "description" || k == "summary" { summary = v }
                }
            }
        }
        return Skill(id: id, name: name, summary: summary.isEmpty ? "自定义技能" : summary, body: body, builtin: builtin)
    }

    var skills: [Skill] {
        let fm = FileManager.default
        let dir = root.appendingPathComponent("skills")
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [Skill] = []
        for f in files where f.pathExtension.lowercased() == "md" {
            let id = f.deletingPathExtension().lastPathComponent
            let builtin = DefaultSkills.all.contains { $0.id == id }
            if let s = parseSkill(id: id, builtin: builtin) { out.append(s) }
        }
        return out.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func skill(named name: String) -> Skill? {
        let all = skills
        let key = name.lowercased()
        return all.first { $0.id.lowercased() == key || $0.name.lowercased() == key }
    }

    func saveSkill(id: String, name: String, summary: String, body: String) {
        let safe = id.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty else { return }
        let content = "---\nname: \(name)\ndescription: \(summary)\n---\n\n\(body)\n"
        try? content.write(to: root.appendingPathComponent("skills/\(safe).md"), atomically: true, encoding: .utf8)
    }

    func deleteSkill(id: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent("skills/\(id).md"))
    }

    private func ensureDefaultSkills() {
        for s in DefaultSkills.all {
            let f = root.appendingPathComponent("skills/\(s.id).md")
            if !FileManager.default.fileExists(atPath: f.path) {
                let content = "---\nname: \(s.name)\ndescription: \(s.summary)\n---\n\n\(s.body)\n"
                try? content.write(to: f, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: Audit

    func audit(_ line: String) {
        let f = root.appendingPathComponent("logs/audit.log")
        let df = ISO8601DateFormatter()
        let text = "[\(df.string(from: Date()))] \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: f) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: f)
        }
    }

    // MARK: Misc

    func openDataFolder() {
        NSWorkspace.shared.open(root)
    }

    var isConfigured: Bool { apiKey != nil }
}

// MARK: - Default skills

struct DefaultSkillDef {
    let id: String
    let name: String
    let summary: String
    let body: String
}

enum DefaultSkills {
    static let all: [DefaultSkillDef] = [
        DefaultSkillDef(
            id: "daily-brief",
            name: "每日简报",
            summary: "汇总今天日历、提醒事项和天气，给出一份三行以内的晨间播报",
            body: """
        当用户要求“今天有什么安排 / 早报 / 每日简报”时：
        1. 用 run_shell 执行 `osascript -e 'tell application "Calendar" to ...'` 读取今天日程（失败就跳过并说明）。
        2. 用 `osascript` 读取 Reminders 的未完成提醒。
        3. 用 `curl -s 'https://wttr.in/?format=3&lang=zh'` 获取天气（失败就跳过）。
        4. 把结果压缩成不超过 5 行的口播式简报，先讲最要紧的一件事，再补充其余。
        5. 日期一律用“今天 / 明天 / 周三”这样的相对说法，不要念 ISO 时间戳。
        """
        ),
        DefaultSkillDef(
            id: "file-tidy",
            name: "整理文件夹",
            summary: "按类型归档桌面或下载目录，先预览方案、经确认后才移动文件",
            body: """
        整理文件时必须先预览、后执行：
        1. 用 list_directory 查看目标目录（默认 ~/Downloads），统计文件类型和数量。
        2. 给出归档方案（图片/文档/压缩包/安装包/其他），说明将创建哪些子目录、各移动多少文件。
        3. 只有用户明确同意后才执行 mv；绝不删除文件，遇到重名自动追加序号。
        4. 不碰隐藏文件、不碰正在下载中的 .crdownload/.part 文件、不移动用户正在编辑的文件。
        5. 完成后汇报移动了多少个文件，并给出撤销所需的目录清单。
        """
        ),
        DefaultSkillDef(
            id: "focus-coach",
            name: "专注陪跑",
            summary: "用番茄钟陪用户专注，期间少打扰，结束时轻声提醒休息",
            body: """
        当用户说“陪我专注 / 番茄钟 / 我要开始干活”：
        1. 问一句目标（只问一次），然后设定 25 分钟（或用户指定时长）。
        2. 用 create_task 建一个仅一次的任务，到点提醒；不要在专注期间主动闲聊。
        3. 开始时说一句很短的打气话，结束时提醒起身、喝水、看远处。
        4. 如果用户中途说累了，就缩短剩余时间，不指责。
        """
        )
    ]
}
