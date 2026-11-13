import AppKit

let arguments = CommandLine.arguments
if let idx = arguments.firstIndex(of: "--icon"), idx + 1 < arguments.count {
    let path = arguments[idx + 1]
    exit(MainActor.assumeIsolated { SnapshotTool.icon(path: path) })
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
