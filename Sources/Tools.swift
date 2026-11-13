import Foundation
import AppKit

// MARK: - Notifications names

extension Notification.Name {
    static let personaChanged = Notification.Name("dafeiyu.personaChanged")
    static let taskFinished = Notification.Name("dafeiyu.taskFinished")
    static let openSettingsTab = Notification.Name("dafeiyu.openSettingsTab")
}

// MARK: - Safety

enum Safety {
    struct Assessment {
        let needsConfirmation: Bool
        let reason: String
    }

    private static let rules: [(pattern: String, reason: String)] = [
        ("rm -rf", "会递归删除文件，且无法恢复"),
        ("rm -fr", "会递归删除文件，且无法恢复"),
        ("rm -r ", "会递归删除文件"),
        ("diskutil", "磁盘分区/抹除操作，可能丢失数据"),
        ("dd if=", "裸写磁盘，可能破坏数据"),
        ("mkfs", "格式化磁盘，会丢失数据"),
        ("sudo ", "需要管理员权限，可能修改系统"),
        ("shutdown", "会关机或重启"),
        ("reboot", "会重启电脑"),
        ("halt", "会关机"),
        ("killall", "会强制结束进程"),
        ("pkill -9", "会强制结束进程"),
        ("launchctl unload", "会停止系统服务"),
        ("launchctl disable", "会停用系统服务"),
        ("defaults delete", "会删除应用偏好设置"),
        ("csrutil", "涉及系统完整性保护"),
        ("nvram", "会修改固件变量"),
        ("spctl --master-disable", "会关闭系统安全策略"),
        ("chmod -R 777 /", "会放开系统权限"),
        ("security ", "涉及钥匙串/证书"),
        ("| sh", "会把网络内容直接当脚本执行"),
        ("| bash", "会把网络内容直接当脚本执行"),
        ("| zsh", "会把网络内容直接当脚本执行"),
        ("> /dev/disk", "会直接写磁盘设备"),
        (">/dev/disk", "会直接写磁盘设备"),
        ("mv /System", "会移动系统文件"),
        ("mv /Library", "会移动系统文件")
    ]

    static func assess(_ command: String) -> Assessment {
        let lower = command.lowercased()
        for rule in rules where lower.contains(rule.pattern) {
            return Assessment(needsConfirmation: true, reason: rule.reason)
        }
        if lower.contains("find /") && lower.contains("-delete") {
            return Assessment(needsConfirmation: true, reason: "会批量删除文件")
        }
        return Assessment(needsConfirmation: false, reason: "")
    }

    @discardableResult
    static func confirm(title: String, detail: String) -> Bool {
        if Thread.isMainThread {
            return present(title: title, detail: detail)
        }
        var allowed = false
        DispatchQueue.main.sync {
            allowed = present(title: title, detail: detail)
        }
        return allowed
    }

    private static func present(title: String, detail: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "允许执行")
        return alert.runModal() == .alertSecondButtonReturn
    }
}

// MARK: - Tool definitions

enum ToolDefinitions {
    static var all: [[String: Any]] {
        [
            tool("run_shell",
                 "在本机执行 shell 命令（zsh），返回 exit code 和输出。默认拥有权限，但破坏性命令会弹窗让用户确认。",
                 ["command": prop("string", "要执行的命令"),
                  "cwd": prop("string", "工作目录，可省略")],
                 ["command"]),
            tool("run_applescript",
                 "执行 AppleScript，用于控制 Finder、Safari、Music、System Events 等 App。",
                 ["script": prop("string", "要执行的 AppleScript 源码")],
                 ["script"]),
            tool("open_app",
                 "通过应用名打开 Mac 应用，例如 Safari、Finder、微信。",
                 ["name": prop("string", "应用名称")],
                 ["name"]),
            tool("open_url",
                 "在默认浏览器打开 http/https 链接。",
                 ["url": prop("string", "完整 URL")],
                 ["url"]),
            tool("read_file",
                 "读取文本文件内容（最多 2 万字符）。",
                 ["path": prop("string", "文件路径，支持 ~")],
                 ["path"]),
            tool("write_file",
                 "新建或覆盖写入文本文件（会自动创建父目录）。",
                 ["path": prop("string", "文件路径，支持 ~"),
                  "content": prop("string", "写入内容"),
                  "append": prop("boolean", "true 表示追加而不是覆盖")],
                 ["path", "content"]),
            tool("list_directory",
                 "列出目录内容（文件名、类型、大小）。",
                 ["path": prop("string", "目录路径，支持 ~")],
                 ["path"]),
            tool("clipboard",
                 "读取或设置系统剪贴板。",
                 ["action": prop("string", "get 或 set", ["get", "set"]),
                  "text": prop("string", "action=set 时必填")],
                 ["action"]),
            tool("notify",
                 "发送一条 macOS 系统通知。",
                 ["title": prop("string", "标题"),
                  "body": prop("string", "内容")],
                 ["title", "body"]),
            tool("screenshot",
                 "截取整个屏幕并保存为 PNG（需要屏幕录制权限）。",
                 ["path": prop("string", "保存路径，省略则保存到桌面")],
                 []),
            tool("system_info",
                 "读取当前时间、系统版本、用户、电量等基础信息。",
                 [:],
                 []),
            tool("fetch_url",
                 "抓取一个网页或 API 的文本内容（只读，自动去掉 HTML 标签）。",
                 ["url": prop("string", "http/https 地址")],
                 ["url"]),
            tool("create_task",
                 "创建一个定时/自动化任务。到点后会把 prompt 交给肥鱼自动执行。",
                 ["title": prop("string", "任务名"),
                  "prompt": prop("string", "到点要让肥鱼做的事，写清楚"),
                  "kind": prop("string", "once/daily/weekdays/weekly/interval", ["once", "daily", "weekdays", "weekly", "interval"]),
                  "time": prop("string", "HH:mm，daily/weekdays/weekly 必填"),
                  "weekdays": prop("array", "weekly 用，整数数组，1=周日 … 7=周六"),
                  "interval_minutes": prop("integer", "interval 用，间隔分钟数"),
                  "once_at": prop("string", "once 用，ISO8601 或 yyyy-MM-dd HH:mm")],
                 ["title", "prompt"]),
            tool("list_tasks", "列出所有定时任务及其下次运行时间。", [:], []),
            tool("delete_task", "删除一个定时任务。",
                 ["id": prop("string", "任务 id，可省略"),
                  "title": prop("string", "或按标题模糊匹配")],
                 []),
            tool("memory_save",
                 "把值得长期记住的用户信息写入记忆。",
                 ["text": prop("string", "一句完整的事实，例如：主人叫 Kai，做后端开发"),
                  "tags": prop("array", "可选标签字符串数组")],
                 ["text"]),
            tool("memory_search",
                 "搜索长期记忆。",
                 ["query": prop("string", "关键词"),
                  "limit": prop("integer", "最多返回几条，默认 6")],
                 ["query"]),
            tool("memory_forget",
                 "忘掉一条记忆。",
                 ["id": prop("string", "记忆 id")],
                 ["id"]),
            tool("list_skills",
                 "列出可用技能（skills）目录。",
                 [:], []),
            tool("load_skill",
                 "读取某个技能的完整说明并照着执行。",
                 ["name": prop("string", "技能名或 id")],
                 ["name"]),
            tool("save_skill",
                 "新建或更新一个技能（Markdown）。",
                 ["name": prop("string", "技能名"),
                  "summary": prop("string", "一句话描述"),
                  "body": prop("string", "技能正文/步骤")],
                 ["name", "summary", "body"]),
            tool("tune_persona",
                 "实时修改肥鱼的性格、说话方式、外观。用户说“以后说话温柔点/换个颜色”等时调用。",
                 ["personality": prop("string", "新的性格描述"),
                  "speech_style": prop("string", "新的说话方式"),
                  "tune_note": prop("string", "追加一条调教指令"),
                  "catchphrases": prop("array", "新的口头禅数组"),
                  "likes": prop("string", "喜欢的事"),
                  "dislikes": prop("string", "讨厌的事"),
                  "name": prop("string", "新名字"),
                  "accent_hex": prop("string", "强调色 #RRGGBB"),
                  "accessory": prop("string", "bow / flower / none", ["bow", "flower", "none"]),
                  "voice_pitch": prop("number", "语音音高 0.5~2.0"),
                  "voice_rate": prop("number", "语速 0.35~0.6")],
                 []),
            tool("system_control",
                 "系统小控制：音量、静音、锁定屏幕、睡眠显示器、深色模式。",
                 ["action": prop("string", "volume/mute/lock/sleep_display/dark_mode", ["volume", "mute", "lock", "sleep_display", "dark_mode"]),
                  "value": prop("integer", "volume 用，0-100；mute 用 1/0")],
                 ["action"]),
            tool("run_shortcut",
                 "运行 macOS 快捷指令（Shortcuts）里的某个快捷指令。",
                 ["name": prop("string", "快捷指令名称")],
                 ["name"])
        ]
    }

    private static func prop(_ type: String, _ description: String, _ values: [String]? = nil) -> [String: Any] {
        var p: [String: Any] = ["type": type, "description": description]
        if let values { p["enum"] = values }
        if type == "array" { p["items"] = ["type": "string"] }
        return p
    }

    private static func tool(_ name: String, _ description: String,
                             _ properties: [String: Any], _ required: [String]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required
                ]
            ]
        ]
    }
}

// MARK: - Tool executor

enum ToolExecutor {
    static func run(name: String, args: [String: Any]) -> String {
        Store.shared.audit("tool \(name) \(truncate(jsonString(args), 400))")

        switch name {
        case "run_shell": return runShellTool(args)
        case "run_applescript": return runAppleScriptTool(args)
        case "open_app": return openAppTool(args)
        case "open_url": return openURLTool(args)
        case "read_file": return readFileTool(args)
        case "write_file": return writeFileTool(args)
        case "list_directory": return listDirectoryTool(args)
        case "clipboard": return clipboardTool(args)
        case "notify": return notifyTool(args)
        case "screenshot": return screenshotTool(args)
        case "system_info": return systemInfoTool()
        case "fetch_url": return fetchURLTool(args)
        case "create_task": return createTaskTool(args)
        case "list_tasks": return listTasksTool()
        case "delete_task": return deleteTaskTool(args)
        case "memory_save": return memorySaveTool(args)
        case "memory_search": return memorySearchTool(args)
        case "memory_forget": return memoryForgetTool(args)
        case "list_skills": return listSkillsTool()
        case "load_skill": return loadSkillTool(args)
        case "save_skill": return saveSkillTool(args)
        case "tune_persona": return tunePersonaTool(args)
        case "system_control": return systemControlTool(args)
        case "run_shortcut": return runShortcutTool(args)
        default:
            return "错误：未知工具 \(name)"
        }
    }

    // MARK: Shell / AppleScript

    private static func runShellTool(_ args: [String: Any]) -> String {
        guard let command = args["command"] as? String, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "错误：缺少 command 参数"
        }
        let risk = Safety.assess(command)
        if risk.needsConfirmation {
            let allowed = Safety.confirm(
                title: "肥鱼想执行一条可能修改系统的命令",
                detail: "风险：\(risk.reason)\n\n\(truncate(command, 600))\n\n只在你清楚后果时允许。"
            )
            guard allowed else {
                Store.shared.audit("denied shell: \(command)")
                return "用户拒绝执行这条命令。不要换个方式偷偷执行。"
            }
        }
        let cwd = (args["cwd"] as? String).flatMap { $0.isEmpty ? nil : expand($0) }
        let result = exec("/bin/zsh", ["-lc", command], cwd: cwd, timeout: 60)
        var out = "exit=\(result.code)\n\(result.output)"
        if result.timedOut { out += "\n（执行超时，已终止）" }
        return truncate(out, 8000)
    }

    private static func runAppleScriptTool(_ args: [String: Any]) -> String {
        guard let script = args["script"] as? String, !script.isEmpty else {
            return "错误：缺少 script 参数"
        }
        let lower = script.lowercased()
        if lower.contains("delete") || lower.contains("do shell script") || lower.contains("erase") {
            let allowed = Safety.confirm(
                title: "肥鱼想运行一段能修改文件的 AppleScript",
                detail: truncate(script, 700)
            )
            guard allowed else { return "用户拒绝执行这段 AppleScript。" }
        }
        let result = exec("/usr/bin/osascript", ["-e", script], timeout: 45)
        return truncate("exit=\(result.code)\n\(result.output)", 6000)
    }

    private static func openAppTool(_ args: [String: Any]) -> String {
        guard let name = args["name"] as? String, !name.isEmpty else { return "错误：缺少 name" }
        let result = exec("/usr/bin/open", ["-a", name], timeout: 15)
        if result.code == 0 { return "已打开 \(name)" }
        return "打开失败：\(result.output)"
    }

    private static func openURLTool(_ args: [String: Any]) -> String {
        guard let raw = args["url"] as? String, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return "错误：需要 http/https 链接"
        }
        NSWorkspace.shared.open(url)
        return "已在浏览器打开 \(raw)"
    }

    // MARK: Files

    private static func readFileTool(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "错误：缺少 path" }
        let full = expand(path)
        guard let data = FileManager.default.contents(atPath: full) else {
            return "读不到文件：\(full)"
        }
        if data.contains(0) { return "这是二进制文件，读不了。" }
        guard let text = String(data: data, encoding: .utf8) else {
            return "文件不是 UTF-8 文本。"
        }
        return truncate(text, 20000)
    }

    private static func writeFileTool(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String, let content = args["content"] as? String else {
            return "错误：缺少 path 或 content"
        }
        let full = expand(path)
        let protected = ["/System/", "/Library/", "/usr/", "/bin/", "/sbin/", "/etc/", "/private/etc/"]
        if protected.contains(where: { full.hasPrefix($0) }) {
            let ok = Safety.confirm(title: "肥鱼想写入系统目录", detail: full)
            guard ok else { return "用户拒绝写入 \(full)" }
        }
        let url = URL(fileURLWithPath: full)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let append = (args["append"] as? Bool) ?? false
            if append, FileManager.default.fileExists(atPath: full) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(Data(content.utf8))
                try handle.close()
            } else {
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
            return "已写入 \(full)（\(content.count) 字符）"
        } catch {
            return "写入失败：\(error.localizedDescription)"
        }
    }

    private static func listDirectoryTool(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "错误：缺少 path" }
        let full = expand(path)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: full),
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "列不出目录：\(full)"
        }
        let lines = items.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(200).map { url -> String in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = values?.isDirectory ?? false
            let size = values?.fileSize ?? 0
            return isDir ? "📁 \(url.lastPathComponent)/" : "📄 \(url.lastPathComponent) (\(size) B)"
        }
        return "\(full)（\(items.count) 项）\n" + lines.joined(separator: "\n")
    }

    // MARK: Clipboard / notify / screenshot

    private static func clipboardTool(_ args: [String: Any]) -> String {
        guard let action = args["action"] as? String else { return "错误：缺少 action" }
        if action == "get" {
            let value = onMain { NSPasteboard.general.string(forType: .string) ?? "" }
            return value.isEmpty ? "剪贴板是空的。" : truncate(value, 4000)
        }
        guard let text = args["text"] as? String else { return "错误：action=set 需要 text" }
        onMain {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return "已写入剪贴板（\(text.count) 字符）"
    }

    private static func notifyTool(_ args: [String: Any]) -> String {
        let title = args["title"] as? String ?? "大肥鱼"
        let body = args["body"] as? String ?? ""
        Notifier.post(title: title, body: body)
        return "通知已发送"
    }

    private static func screenshotTool(_ args: [String: Any]) -> String {
        let path: String
        if let p = args["path"] as? String, !p.isEmpty {
            path = expand(p)
        } else {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd-HHmmss"
            path = NSHomeDirectory() + "/Desktop/肥鱼截图-\(df.string(from: Date())).png"
        }
        let result = exec("/usr/sbin/screencapture", ["-x", path], timeout: 20)
        if result.code == 0, FileManager.default.fileExists(atPath: path) {
            return "截图已保存：\(path)"
        }
        return "截图失败（可能需要 屏幕录制 权限）：\(result.output)"
    }

    // MARK: System / network

    private static func systemInfoTool() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd EEEE HH:mm:ss"
        let info = ProcessInfo.processInfo
        let uptimeHours = Int(info.systemUptime / 3600)
        let battery = exec("/usr/bin/pmset", ["-g", "batt"], timeout: 5).output
            .replacingOccurrences(of: "\n", with: " ")
        return """
        时间：\(df.string(from: Date()))
        用户：\(NSUserName())（\(NSFullUserName())）
        主机：\(Host.current().localizedName ?? "Mac")
        系统：macOS \(info.operatingSystemVersionString)
        已运行：约 \(uptimeHours) 小时
        电量：\(battery.isEmpty ? "未知（可能是台式机）" : truncate(battery, 200))
        """
    }

    private static func fetchURLTool(_ args: [String: Any]) -> String {
        guard let raw = args["url"] as? String, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return "错误：需要 http/https 链接"
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh) DaFeiYu/1.0", forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        var text = ""
        var failure: String?
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { sem.signal() }
            if let error { failure = error.localizedDescription; return }
            guard let data, data.count > 0 else { failure = "没有内容"; return }
            let html = String(data: data, encoding: .utf8) ?? ""
            text = stripHTML(html)
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 25)
        if let failure { return "抓取失败：\(failure)" }
        if text.isEmpty { return "页面没有可读文本。" }
        return truncate(text, 8000)
    }

    // MARK: Tasks

    private static func createTaskTool(_ args: [String: Any]) -> String {
        guard let title = args["title"] as? String, let prompt = args["prompt"] as? String else {
            return "错误：需要 title 和 prompt"
        }
        var task = TaskSpec(title: title, prompt: prompt, kind: .daily)
        if let kindRaw = args["kind"] as? String, let kind = ScheduleKind(rawValue: kindRaw) {
            task.kind = kind
        }
        if let time = args["time"] as? String { task.time = time }
        if let rawDays = args["weekdays"] as? [Any] {
            let days = rawDays.compactMap { ($0 as? NSNumber)?.intValue }
            if !days.isEmpty { task.weekdays = days }
        } else if let weekdays = args["weekdays"] as? [Int], !weekdays.isEmpty {
            task.weekdays = weekdays
        }
        if let interval = args["interval_minutes"] as? Int { task.intervalMinutes = max(1, interval) }
        if let value = args["once_at"] as? String { task.onceAt = parseDate(value) }
        if task.kind == .once && task.onceAt == nil {
            return "错误：once 任务需要 once_at（例如 2026-11-15 09:00）"
        }
        task.nextRun = Scheduler.nextRunDate(for: task, after: Date())
        Store.shared.upsertTask(task)
        Scheduler.shared.kick()
        return "已创建任务「\(task.title)」（\(task.scheduleText)），下次运行：\(task.nextRun.map(formatDate) ?? "未定")"
    }

    private static func listTasksTool() -> String {
        let tasks = Store.shared.tasks
        guard !tasks.isEmpty else { return "现在没有定时任务。" }
        return tasks.map { t in
            "\(t.id.prefix(8)) | \(t.title) | \(t.scheduleText) | \(t.enabled ? "启用" : "停用") | 下次：\(t.nextRun.map(formatDate) ?? "-")"
        }.joined(separator: "\n")
    }

    private static func deleteTaskTool(_ args: [String: Any]) -> String {
        let tasks = Store.shared.tasks
        var target: TaskSpec?
        if let id = args["id"] as? String {
            target = tasks.first { $0.id.hasPrefix(id) }
        } else if let title = args["title"] as? String {
            target = tasks.first { $0.title.contains(title) }
        }
        guard let task = target else { return "没找到要删除的任务。" }
        Store.shared.deleteTask(id: task.id)
        return "已删除任务「\(task.title)」"
    }

    // MARK: Memory

    private static func memorySaveTool(_ args: [String: Any]) -> String {
        guard let text = args["text"] as? String, !text.isEmpty else { return "错误：需要 text" }
        var tags: [String] = []
        if let arr = args["tags"] as? [Any] { tags = arr.compactMap { $0 as? String } }
        if let s = args["tags"] as? String { tags = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        Store.shared.addMemory(text: text, tags: tags)
        return "记住了：\(text)"
    }

    private static func memorySearchTool(_ args: [String: Any]) -> String {
        guard let query = args["query"] as? String else { return "错误：需要 query" }
        let limit = (args["limit"] as? Int) ?? 6
        let results = Store.shared.searchMemories(query, limit: limit)
        if results.isEmpty {
            let recent = Store.shared.memories.prefix(5)
            if recent.isEmpty { return "还没有任何记忆。" }
            return "没搜到直接相关的，最近的记忆：\n" + recent.map { "- \($0.text)" }.joined(separator: "\n")
        }
        return results.map { "- [\($0.id.prefix(6))] \($0.text)" }.joined(separator: "\n")
    }

    private static func memoryForgetTool(_ args: [String: Any]) -> String {
        guard let id = args["id"] as? String else { return "错误：需要 id" }
        let match = Store.shared.memories.first { $0.id.hasPrefix(id) }
        guard let memory = match else { return "没找到这条记忆。" }
        Store.shared.removeMemory(id: memory.id)
        return "忘掉了：\(memory.text)"
    }

    // MARK: Skills

    private static func listSkillsTool() -> String {
        let skills = Store.shared.skills
        guard !skills.isEmpty else { return "还没有技能。" }
        return skills.map { "- \($0.name)（\($0.id)）：\($0.summary)" }.joined(separator: "\n")
    }

    private static func loadSkillTool(_ args: [String: Any]) -> String {
        guard let name = args["name"] as? String else { return "错误：需要 name" }
        guard let skill = Store.shared.skill(named: name) else { return "没有这个技能：\(name)" }
        return "# 技能：\(skill.name)\n\(skill.body)"
    }

    private static func saveSkillTool(_ args: [String: Any]) -> String {
        guard let name = args["name"] as? String, let body = args["body"] as? String else {
            return "错误：需要 name 和 body"
        }
        let summary = args["summary"] as? String ?? ""
        let id = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        Store.shared.saveSkill(id: id, name: name, summary: summary, body: body)
        return "已保存技能「\(name)」。"
    }

    // MARK: Persona

    private static func tunePersonaTool(_ args: [String: Any]) -> String {
        var persona = Store.shared.config.persona
        var changed: [String] = []
        if let v = args["name"] as? String, !v.isEmpty { persona.name = v; changed.append("名字") }
        if let v = args["personality"] as? String, !v.isEmpty { persona.personality = v; changed.append("性格") }
        if let v = args["speech_style"] as? String, !v.isEmpty { persona.speechStyle = v; changed.append("说话方式") }
        if let v = args["likes"] as? String, !v.isEmpty { persona.likes = v; changed.append("喜好") }
        if let v = args["dislikes"] as? String, !v.isEmpty { persona.dislikes = v; changed.append("讨厌") }
        if let v = args["catchphrases"] as? [String], !v.isEmpty { persona.catchphrases = v; changed.append("口头禅") }
        if let v = args["accent_hex"] as? String, v.hasPrefix("#") { persona.accentHex = v; changed.append("强调色") }
        if let v = args["body_hex"] as? String, v.hasPrefix("#") { persona.bodyHex = v; changed.append("身体颜色") }
        if let v = args["accessory"] as? String { persona.accessory = v; changed.append("配饰") }
        if let v = args["voice_pitch"] as? Double { persona.voicePitch = min(2, max(0.5, v)); changed.append("音高") }
        if let v = args["voice_rate"] as? Double { persona.voiceRate = min(0.6, max(0.35, v)); changed.append("语速") }
        if let note = args["tune_note"] as? String, !note.isEmpty {
            persona.tuneNote = [persona.tuneNote, note]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "；")
            changed.append("调教笔记")
        }
        if changed.isEmpty {
            return "没有收到要修改的内容。可以告诉我要改性格、语气、配色还是口头禅。"
        }
        Store.shared.updateConfig { $0.persona = persona }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .personaChanged, object: nil)
        }
        return "已更新：\(changed.joined(separator: "、"))。新设定会立刻生效。"
    }

    // MARK: System control

    private static func systemControlTool(_ args: [String: Any]) -> String {
        guard let action = args["action"] as? String else { return "错误：缺少 action" }
        switch action {
        case "volume":
            let value = min(100, max(0, (args["value"] as? Int) ?? 50))
            let r = exec("/usr/bin/osascript", ["-e", "set volume output volume \(value)"], timeout: 10)
            return r.code == 0 ? "音量已调到 \(value)" : "调节失败：\(r.output)"
        case "mute":
            let muted = ((args["value"] as? Int) ?? 1) != 0
            let r = exec("/usr/bin/osascript", ["-e", "set volume output muted \(muted ? "true" : "false")"], timeout: 10)
            return r.code == 0 ? (muted ? "已静音" : "已取消静音") : "操作失败：\(r.output)"
        case "sleep_display":
            let r = exec("/usr/bin/pmset", ["displaysleepnow"], timeout: 10)
            return r.code == 0 ? "显示器已睡眠" : "失败：\(r.output)"
        case "lock":
            let path = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
            if FileManager.default.fileExists(atPath: path) {
                let r = exec(path, ["-suspend"], timeout: 10)
                return r.code == 0 ? "已锁定屏幕" : "锁定失败：\(r.output)"
            }
            return "这个系统版本不支持直接锁屏，可以用 ⌃⌘Q。"
        case "dark_mode":
            let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
            let r = exec("/usr/bin/osascript", ["-e", script], timeout: 10)
            return r.code == 0 ? "已切换深色模式" : "切换失败（可能需要在 隐私与安全性 → 自动化 里授权）：\(r.output)"
        default:
            return "不支持的操作：\(action)"
        }
    }

    private static func runShortcutTool(_ args: [String: Any]) -> String {
        guard let name = args["name"] as? String, !name.isEmpty else { return "错误：缺少 name" }
        let r = exec("/usr/bin/shortcuts", ["run", name], timeout: 120)
        if r.code == 0 {
            return "快捷指令「\(name)」已运行。\n\(truncate(r.output, 4000))"
        }
        return "运行失败：\(truncate(r.output, 2000))"
    }

    // MARK: Helpers

    static func exec(_ path: String, _ arguments: [String],
                     cwd: String? = nil, timeout: TimeInterval = 45) -> (code: Int32, output: String, timedOut: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "启动失败：\(error.localizedDescription)", false)
        }
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning && Date() < deadline {
            usleep(40_000)
        }
        if process.isRunning {
            timedOut = true
            process.terminate()
            usleep(200_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output, timedOut)
    }

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func jsonString(_ args: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: args),
              let text = String(data: data, encoding: .utf8) else { return "\(args)" }
        return text
    }

    static func truncate(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "\n…（已截断）" : text
    }

    static func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M月d日 HH:mm"
        return df.string(from: date)
    }

    static func parseDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: text) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: text) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm", "MM-dd HH:mm"] {
            df.dateFormat = format
            if let d = df.date(from: text) { return d }
        }
        return nil
    }

    static func stripHTML(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#39;", with: "'")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        var value: T!
        DispatchQueue.main.sync { value = body() }
        return value
    }
}

// MARK: - Notifier

enum Notifier {
    static func post(title: String, body: String) {
        let safeTitle = escapeAppleScript(title)
        let safeBody = escapeAppleScript(body)
        let script = "display notification \"\(safeBody)\" with title \"\(safeTitle)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    static func escapeAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
