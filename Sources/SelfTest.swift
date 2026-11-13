import Foundation

enum SelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("✓ \(name)")
            } else {
                failures += 1
                print("✗ \(name) \(detail)")
            }
        }

        // 1. 日程计算
        var daily = TaskSpec(title: "daily", prompt: "x", kind: .daily)
        daily.time = "09:00"
        let base = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 10, minute: 0))!
        let nextDaily = Scheduler.nextRunDate(for: daily, after: base)
        check("daily next run tomorrow", nextDaily != nil, "\(String(describing: nextDaily))")
        var weekday = TaskSpec(title: "weekday", prompt: "x", kind: .weekdays)
        weekday.time = "09:00"
        let saturday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 10, minute: 0))!
        let nextWeekday = Scheduler.nextRunDate(for: weekday, after: saturday)
        check("weekdays skip weekend", nextWeekday != nil && Calendar.current.component(.weekday, from: nextWeekday!) == 2,
              "\(String(describing: nextWeekday))")

        // 2. 危险命令识别
        check("rm -rf requires confirmation", Safety.assess("rm -rf ~/Downloads/x").needsConfirmation)
        check("echo is safe", !Safety.assess("echo hello").needsConfirmation)
        check("diskutil requires confirmation", Safety.assess("diskutil eraseDisk APFS X /dev/disk2").needsConfirmation)

        // 3. 记忆
        Store.shared.addMemory(text: "主人叫 Kai，做后端开发", tags: ["身份"])
        let found = Store.shared.searchMemories("Kai 做什么")
        check("memory search", found.contains { $0.text.contains("Kai") })
        let skills = Store.shared.skills
        check("default skills installed", !skills.isEmpty, "\(skills.count)")

        // 4. 工具
        let echo = ToolExecutor.run(name: "run_shell", args: ["command": "echo hello-from-selftest"])
        check("run_shell", echo.contains("hello-from-selftest"), echo)
        let info = ToolExecutor.run(name: "system_info", args: [:])
        check("system_info", info.contains("macOS"), info)
        let mem = ToolExecutor.run(name: "memory_save", args: ["text": "测试记忆条目"])
        check("memory_save tool", mem.contains("记住"))

        // 5. DeepSeek 流式 + 工具循环（需要本地 mock 服务）
        let baseURL = ProcessInfo.processInfo.environment["MOCK_DEEPSEEK_URL"] ?? ""
        if !baseURL.isEmpty {
            var config = Store.shared.config
            config.baseURL = baseURL
            config.model = "deepseek-chat"
            config.temperature = 0.7
            Store.shared.config = config
            Store.shared.setAPIKey("mock-key")

            var done = false
            var output = ""
            AgentController.shared.onStart = {}
            AgentController.shared.onPartial = { _ in }
            AgentController.shared.onStatus = { _ in }
            AgentController.shared.onFinish = { text in output = text; done = true }
            AgentController.shared.onError = { message in output = "ERR: " + message; done = true }
            AgentController.shared.send(text: "帮我跑个测试", viaVoice: false)

            let deadline = Date().addingTimeInterval(25)
            while !done && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            check("agent loop with tool call", done && output.contains("hello-from-mock"), output)
        } else {
            print("• 跳过 DeepSeek mock 测试（MOCK_DEEPSEEK_URL 未设置）")
        }

        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }
}
