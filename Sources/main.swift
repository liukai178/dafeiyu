import AppKit

let arguments = CommandLine.arguments
if let idx = arguments.firstIndex(of: "--icon"), idx + 1 < arguments.count {
    let path = arguments[idx + 1]
    exit(MainActor.assumeIsolated { SnapshotTool.icon(path: path) })
}

if let idx = arguments.firstIndex(of: "--ask"), idx + 1 < arguments.count {
    let question = arguments[idx + 1]
    var done = false
    var output = ""
    AgentController.shared.onStart = {}
    AgentController.shared.onPartial = { _ in }
    AgentController.shared.onStatus = { _ in }
    AgentController.shared.onFinish = { text in output = text; done = true }
    AgentController.shared.onError = { message in output = "ERR: " + message; done = true }
    AgentController.shared.send(text: question, viaVoice: false)
    let deadline = Date().addingTimeInterval(60)
    while !done && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    print(output)
    exit(output.hasPrefix("ERR:") ? 1 : 0)
}

if arguments.contains("--selftest") {
    exit(MainActor.assumeIsolated { SelfTest.run() })
}
if let idx = arguments.firstIndex(of: "--snapshot"), idx + 1 < arguments.count {
    let path = arguments[idx + 1]
    let mood = idx + 2 < arguments.count ? arguments[idx + 2] : "idle"
    exit(MainActor.assumeIsolated { SnapshotTool.run(path: path, moodName: mood) })
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
