import Foundation

final class AgentController {
    static let shared = AgentController()

    var onStart: (() -> Void)?
    var onPartial: ((String) -> Void)?
    var onStatus: ((String?) -> Void)?
    var onFinish: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var busy = false
    private var token = 0
    private var startedAt: Date?
    private var client: DeepSeekClient?
    private let queue = DispatchQueue(label: "com.liukai.dafeiyu.agent", qos: .userInitiated)

    // MARK: - Public

    func send(text: String, viaVoice: Bool) {
        if busy {
            if let startedAt, Date().timeIntervalSince(startedAt) < 55 {
                onError?("等我把上一句想完。")
                return
            }
            cancel()
        }
        busy = true
        startedAt = Date()
        token += 1
        let current = token
        DispatchQueue.main.async { self.onStart?() }
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.runLoop(userText: text, ui: true, token: current)
            DispatchQueue.main.async {
                guard self.token == current else { return }
                self.busy = false
                self.client = nil
                self.startedAt = nil
                switch result {
                case .success(let reply):
                    self.onFinish?(reply)
                    self.extractMemoriesIfNeeded()
                case .failure(let error):
                    self.onError?(error.message)
                }
            }
        }
    }

    func runAutomation(_ task: TaskSpec, completion: @escaping (Result<String, DeepSeekError>) -> Void) {
        if busy {
            if let startedAt, Date().timeIntervalSince(startedAt) < 55 {
                completion(.failure(DeepSeekError(message: "正在忙别的")))
                return
            }
            cancel()
        }
        busy = true
        startedAt = Date()
        token += 1
        let current = token
        queue.async { [weak self] in
            guard let self else { return }
            let prompt = """
            【定时任务】\(task.title)
            \(task.prompt)

            现在是任务触发时间，请直接动手完成，不要反问。最后用一两句话汇报结果。
            """
            let result = self.runLoop(userText: prompt, ui: false, token: current)
            DispatchQueue.main.async {
                self.busy = false
                self.client = nil
                self.startedAt = nil
                completion(result)
            }
        }
    }

    func cancel() {
        token += 1
        client?.cancel()
        busy = false
        startedAt = nil
    }

    // MARK: - Loop

    private func runLoop(userText: String, ui: Bool, token: Int) -> Result<String, DeepSeekError> {
        let config = Store.shared.config
        guard let key = Store.shared.apiKey, !key.isEmpty else {
            return .failure(DeepSeekError(message: "还没有配置 DeepSeek API Key，去设置里填一下吧。"))
        }
        let client = DeepSeekClient(apiKey: key, baseURL: config.baseURL, model: config.model)
        self.client = client

        var messages: [APIMessage] = [
            APIMessage(role: "system", content: buildSystemPrompt(for: userText))
        ]
        var history = Store.shared.history
        if history.last?.role == "user" && history.last?.text == userText {
            history.removeLast()
        }
        for turn in history.suffix(14) {
            messages.append(APIMessage(
                role: turn.role == "assistant" ? "assistant" : "user",
                content: turn.text
            ))
        }
        messages.append(APIMessage(role: "user", content: userText))

        let tools = config.model.contains("reasoner") ? [] : ToolDefinitions.all
        var lastContent = ""

        for round in 0..<6 {
            if token != self.token {
                return .failure(DeepSeekError(message: "已取消"))
            }
            var streamed = ""
            var lastEmit = Date.distantPast
            let result = client.streamChat(
                messages: messages,
                tools: tools,
                temperature: config.temperature
            ) { delta in
                streamed += delta
                guard ui else { return }
                let now = Date()
                guard now.timeIntervalSince(lastEmit) > 0.05 else { return }
                lastEmit = now
                let snapshot = streamed
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.token == token else { return }
                    self.onPartial?(snapshot)
                }
            }

            let message: APIMessage
            switch result {
            case .failure(let error):
                if ui { DispatchQueue.main.async { self.onStatus?(nil) } }
                return .failure(error)
            case .success(let value):
                message = value
            }

            if let content = message.content, !content.isEmpty {
                lastContent = content
            }
            guard let calls = message.tool_calls, !calls.isEmpty else {
                if ui { DispatchQueue.main.async { self.onStatus?(nil) } }
                return .success(lastContent.isEmpty ? "弄好了。" : lastContent)
            }

            messages.append(APIMessage(assistantMessage: message.content, toolCalls: calls))

            for call in calls {
                if token != self.token {
                    return .failure(DeepSeekError(message: "已取消"))
                }
                let args = Self.parseArguments(call.function.arguments)
                let label = Self.friendlyName(call.function.name)
                if ui {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.token == token else { return }
                        self.onStatus?("正在\(label)…")
                    }
                }
                let output = ToolExecutor.run(name: call.function.name, args: args)
                messages.append(APIMessage(
                    toolCallID: call.id,
                    content: String(output.prefix(7000))
                ))
            }
            if ui { DispatchQueue.main.async { self.onStatus?(nil) } }
            _ = round
        }

        if ui { DispatchQueue.main.async { self.onStatus?(nil) } }
        return .success(lastContent.isEmpty ? "忙完了，不过没整理出结果。" : lastContent)
    }

    // MARK: - Prompt

    private func buildSystemPrompt(for userText: String) -> String {
        let persona = Store.shared.config.persona
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        var memory = Store.shared.searchMemories(userText, limit: 5)
        if memory.isEmpty { memory = Array(Store.shared.memories.prefix(4)) }
        let memoryBlock = memory.isEmpty
            ? "（暂无相关记忆；用户说“记住”时用 memory_save）"
            : memory.map { "- \($0.text)" }.joined(separator: "\n")
        let skillList = Store.shared.skills
        let skillBlock = skillList.isEmpty
            ? "（暂无技能）"
            : skillList.map { "- \($0.name)（\($0.id)）：\($0.summary)" }.joined(separator: "\n")
        let tasks = Store.shared.tasks.prefix(8).map { "- \($0.title)：\($0.scheduleText)" }.joined(separator: "\n")

        return """
        你是「\(persona.name)」，\(persona.species)。你住在主人（\(NSFullUserName())）的 Mac 里，是一个有情绪、有记忆的桌宠，不是客服机器人。

        \(persona.promptBlock)

        【说话规则】
        - 日常聊天只回 1~3 句，短、口语化，像发微信；不要 Markdown、不要编号列表、不要总结段落。
        - 有活人感：会吐槽、会嘴硬、会好奇；被夸会结巴，被冷落会别扭，但不会刻薄或 PUA。
        - 不重复用户的话，不假装执行了没做的事；工具失败就承认，并给替代方案。
        - 语音对话时更像说话，句子更短。用户认真问事情时，收起玩笑直接回答。

        【能力与边界】
        - 你可以操作这台 Mac：shell、AppleScript、读写文件、打开 App/网页、剪贴板、截图、系统音量、快捷指令。
        - 你拥有用户授予的权限，但任何删除、覆盖、磁盘、系统级、sudo 操作必须由工具弹窗让用户确认；不要尝试绕过确认。
        - 不输出 API Key、密码、token；不把用户隐私主动发到外部网站。
        - 不确定的事实先查（fetch_url / 工具），不要编。做不到就直说。

        【工作方式】
        - 需要事实或操作时直接调用工具，不要先问“要不要我帮你”。
        - 一次只做必要的事；拿到结果后用一句人话汇报，不要贴大段日志（除非用户要求）。
        - 用户说“记住…”用 memory_save；说“以后…/你要…”这类偏好用 tune_persona 的 tune_note。
        - 用户要定时/每天/提醒类需求，用 create_task；时间写成 HH:mm，once 用 once_at。
        - 有匹配技能时先 load_skill，再按技能步骤执行。

        【记忆】
        \(memoryBlock)

        【技能】
        \(skillBlock)

        【现有定时任务】
        \(tasks.isEmpty ? "（无）" : tasks)

        【环境】
        当前时间：\(df.string(from: Date()))
        系统：macOS \(ProcessInfo.processInfo.operatingSystemVersionString)，用户：\(NSUserName())
        """
    }

    // MARK: - Auto memory

    private func extractMemoriesIfNeeded() {
        let config = Store.shared.config
        guard config.autoMemory else { return }
        guard let key = Store.shared.apiKey, !key.isEmpty else { return }
        let history = Store.shared.history
        let userCount = history.filter { $0.role == "user" }.count
        guard userCount > 0, userCount % 3 == 0 else { return }
        let recent = history.suffix(8).map { turn in
            "\(turn.role == "user" ? "用户" : "肥鱼")：\(turn.text)"
        }.joined(separator: "\n")
        DispatchQueue.global(qos: .utility).async {
            let client = DeepSeekClient(apiKey: key, baseURL: config.baseURL, model: config.model)
            let prompt = """
            从下面这段对话里提取关于“用户本人”的、长期稳定的事实（身份、偏好、习惯、重要关系、正在进行的目标）。
            不要提取一次性的琐事，不要提取肥鱼自己的设定，不要杜撰。
            只输出 JSON 数组，最多 2 条，每条是一句完整中文事实；没有就输出 []。
            对话：
            \(recent)
            """
            let result = client.complete(
                messages: [APIMessage(role: "user", content: prompt)],
                temperature: 0.1,
                maxTokens: 300
            )
            if case .success(let text) = result {
                for item in Self.parseMemoryArray(text) {
                    Store.shared.addMemory(text: item, tags: ["自动记忆"])
                }
            }
        }
    }

    private static func parseMemoryArray(_ text: String) -> [String] {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = s.firstIndex(of: "["), let end = s.lastIndex(of: "]") {
            s = String(s[start...end])
        }
        guard let data = s.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .map { $0 }
    }

    private static func parseArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func friendlyName(_ tool: String) -> String {
        switch tool {
        case "run_shell": return "执行命令"
        case "run_applescript": return "操作 App"
        case "open_app": return "打开应用"
        case "open_url": return "打开网页"
        case "read_file": return "读文件"
        case "write_file": return "写文件"
        case "list_directory": return "看目录"
        case "clipboard": return "处理剪贴板"
        case "notify": return "发通知"
        case "screenshot": return "截图"
        case "system_info": return "看系统状态"
        case "fetch_url": return "查网页"
        case "create_task": return "设定时任务"
        case "list_tasks": return "看任务列表"
        case "delete_task": return "删任务"
        case "memory_save": return "记事情"
        case "memory_search": return "翻记忆"
        case "memory_forget": return "忘掉事情"
        case "list_skills", "load_skill", "save_skill": return "查技能"
        case "tune_persona": return "调整自己"
        case "system_control": return "调系统"
        case "run_shortcut": return "跑快捷指令"
        default: return "干活"
        }
    }
}

// MARK: - Scheduler

final class Scheduler {
    static let shared = Scheduler()

    private var timer: Timer?
    private var paused = true
    private var running = false

    func start() {
        paused = false
        if timer == nil {
            let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                self?.tick()
            }
            t.tolerance = 12
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        tick()
    }

    func setPaused(_ value: Bool) {
        paused = value
        if !value { tick() }
    }

    func kick() {
        DispatchQueue.main.async { self.tick() }
    }

    func runNow(_ task: TaskSpec) {
        guard !running else {
            Notifier.post(title: "大肥鱼", body: "上一个任务还没跑完，稍等。")
            return
        }
        run(task)
    }

    private func tick() {
        guard !paused, !running else { return }
        let now = Date()
        for task in Store.shared.tasks where task.enabled {
            var updated = task
            if updated.nextRun == nil {
                updated.nextRun = Scheduler.nextRunDate(for: updated, after: now)
                Store.shared.upsertTask(updated)
                continue
            }
            if let next = updated.nextRun, next <= now {
                run(updated)
                return
            }
        }
    }

    private func run(_ task: TaskSpec) {
        running = true
        AgentController.shared.runAutomation(task) { [weak self] result in
            guard let self else { return }
            self.running = false
            let now = Date()
            var next = Scheduler.nextRunDate(for: task, after: now.addingTimeInterval(45))
            let text: String
            var failedToStart = false
            switch result {
            case .success(let value):
                text = value
            case .failure(let error):
                text = "任务失败：\(error.message)"
                if error.message.contains("正在忙") {
                    failedToStart = true
                    next = now.addingTimeInterval(300)
                }
            }
            if failedToStart {
                var retry = task
                retry.nextRun = next
                Store.shared.upsertTask(retry)
            } else {
                Store.shared.recordTaskRun(id: task.id, at: now, result: text, next: next)
            }
            if task.notify {
                Notifier.post(title: "大肥鱼 · \(task.title)", body: String(text.prefix(180)))
            }
            NotificationCenter.default.post(
                name: .taskFinished,
                object: nil,
                userInfo: ["title": task.title, "text": text, "speak": task.speak]
            )
            self.tick()
        }
    }

    static func nextRunDate(for task: TaskSpec, after date: Date) -> Date? {
        let cal = Calendar.current
        switch task.kind {
        case .once:
            guard let at = task.onceAt else { return nil }
            return at > date ? at : nil
        case .interval:
            return date.addingTimeInterval(TimeInterval(max(1, task.intervalMinutes) * 60))
        case .daily, .weekdays, .weekly:
            let parts = task.time.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
                return nil
            }
            for offset in 0...14 {
                guard let day = cal.date(byAdding: .day, value: offset, to: date),
                      let candidate = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day),
                      candidate > date else { continue }
                if task.kind == .daily { return candidate }
                let weekday = cal.component(.weekday, from: candidate)
                if task.kind == .weekdays, (2...6).contains(weekday) { return candidate }
                if task.kind == .weekly, task.weekdays.contains(weekday) { return candidate }
            }
            return nil
        }
    }
}
