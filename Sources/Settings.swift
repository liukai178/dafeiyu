import SwiftUI
import AppKit
import Speech
import AVFoundation
import ApplicationServices

enum SettingsTab: String, CaseIterable, Identifiable {
    case model, persona, tasks, memory, skills, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .model: return "对话"
        case .persona: return "性格"
        case .tasks: return "自动化"
        case .memory: return "记忆"
        case .skills: return "技能"
        case .about: return "关于"
        }
    }
    var icon: String {
        switch self {
        case .model: return "bubble.left.and.bubble.right"
        case .persona: return "face.smiling"
        case .tasks: return "clock.arrow.circlepath"
        case .memory: return "brain"
        case .skills: return "sparkles"
        case .about: return "fish"
        }
    }
}

extension Color {
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Model

final class SettingsModel: ObservableObject {
    @Published var tab: SettingsTab = .model
    @Published var apiKeyDraft = ""
    @Published var modelName = "deepseek-chat"
    @Published var baseURL = "https://api.deepseek.com"
    @Published var temperature = 0.95
    @Published var voiceReplies = true
    @Published var autoMemory = true
    @Published var hotkeyEnabled = true
    @Published var idleSleepSeconds = 120
    @Published var persona = Persona.tsundere
    @Published var status: String?
    @Published var testing = false
    @Published var tasks: [TaskSpec] = []
    @Published var memories: [MemoryItem] = []
    @Published var skills: [Skill] = []
    @Published var showAddTask = false
    @Published var editingSkill: Skill?
    @Published var editingIsNew = false

    init() { reload() }

    func reload() {
        let c = Store.shared.config
        modelName = c.model
        baseURL = c.baseURL
        temperature = c.temperature
        voiceReplies = c.voiceReplies
        autoMemory = c.autoMemory
        hotkeyEnabled = c.hotkeyEnabled
        idleSleepSeconds = c.idleSleepSeconds
        persona = c.persona
        tasks = Store.shared.tasks
        memories = Store.shared.memories
        skills = Store.shared.skills
    }

    func saveConnection() {
        if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = Store.shared.setAPIKey(apiKeyDraft)
            apiKeyDraft = ""
        }
        Store.shared.updateConfig {
            $0.model = modelName
            $0.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.temperature = temperature
            $0.voiceReplies = voiceReplies
            $0.autoMemory = autoMemory
            $0.hotkeyEnabled = hotkeyEnabled
            $0.idleSleepSeconds = idleSleepSeconds
        }
        if hotkeyEnabled {
            HotKeyCenter.shared.registerVoice()
        } else {
            HotKeyCenter.shared.unregisterVoice()
        }
        status = "已保存"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.status == "已保存" { self?.status = nil }
        }
    }

    func testConnection() {
        guard !testing else { return }
        testing = true
        status = "正在连接…"
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (Store.shared.apiKey ?? "") : apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseURL
        let model = modelName
        DispatchQueue.global(qos: .utility).async {
            let client = DeepSeekClient(apiKey: key, baseURL: base, model: model)
            let result = client.testConnection()
            DispatchQueue.main.async {
                self.testing = false
                switch result {
                case .success:
                    self.status = "连接成功 ✓"
                case .failure(let error):
                    self.status = "失败：\(error.message)"
                }
            }
        }
    }

    func savePersona() {
        Store.shared.updateConfig { $0.persona = self.persona }
        NotificationCenter.default.post(name: .personaChanged, object: nil)
        status = "性格已更新"
    }

    func applyPreset(_ preset: Persona) {
        persona = preset
        savePersona()
    }

    func resetPersona() {
        persona = .tsundere
        savePersona()
    }

    func reloadTasks() { tasks = Store.shared.tasks }
    func reloadMemories() { memories = Store.shared.memories }
    func reloadSkills() { skills = Store.shared.skills }

    func addTask(_ task: TaskSpec) {
        var t = task
        t.nextRun = Scheduler.nextRunDate(for: t, after: Date())
        Store.shared.upsertTask(t)
        Scheduler.shared.kick()
        reloadTasks()
    }

    func toggleTask(_ task: TaskSpec) {
        var t = task
        t.enabled.toggle()
        t.nextRun = t.enabled ? Scheduler.nextRunDate(for: t, after: Date()) : nil
        Store.shared.upsertTask(t)
        reloadTasks()
    }

    func deleteTask(_ task: TaskSpec) {
        Store.shared.deleteTask(id: task.id)
        reloadTasks()
    }

    func runTaskNow(_ task: TaskSpec) {
        Scheduler.shared.runNow(task)
        status = "已触发「\(task.title)」"
    }
}

// MARK: - Controller

final class SettingsController: NSObject, NSWindowDelegate {
    static let shared = SettingsController()

    private var window: NSWindow?
    private let model = SettingsModel()
    private(set) var currentTab: SettingsTab = .model

    func show(tab: SettingsTab) {
        currentTab = tab
        model.tab = tab
        model.reload()
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "大肥鱼"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.level = .normal
            w.collectionBehavior = [.moveToActiveSpace]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.backgroundColor = NSColor(calibratedRed: 0.985, green: 0.965, blue: 0.94, alpha: 1)
            w.contentView = NSHostingView(rootView: SettingsRoot(model: model))
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showWindow(_ sender: Any?) {
        show(tab: currentTab)
    }
}

// MARK: - Root

struct SettingsRoot: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 152)
            ZStack {
                Color(hex: "#FBF6EF")
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ScrollView(.vertical, showsIndicators: true) {
                        Group {
                            switch model.tab {
                            case .model: ConnectionPane(model: model)
                            case .persona: PersonaPane(model: model)
                            case .tasks: TasksPane(model: model)
                            case .memory: MemoryPane(model: model)
                            case .skills: SkillsPane(model: model)
                            case .about: AboutPane(model: model)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(10)
        }
        .frame(width: 680, height: 540)
        .background(Color(hex: "#F3E9DD"))
        .preferredColorScheme(.light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "fish.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.accentFallback)
                Text("大肥鱼")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
            }
            .padding(.leading, 16)
            .padding(.top, 40)
            .padding(.bottom, 14)

            ForEach(SettingsTab.allCases) { tab in
                Button {
                    model.tab = tab
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 16)
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.tab == tab ? Color.white.opacity(0.85) : Color.clear)
                    )
                    .foregroundColor(model.tab == tab ? Theme.ink : Theme.ink.opacity(0.55))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
            Text("⌥Space 语音")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(Theme.ink.opacity(0.35))
                .padding(.leading, 18)
                .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity)
        .background(Color(hex: "#F3E9DD"))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.tab.title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Theme.ink.opacity(0.45))
            }
            Spacer()
            if let status = model.status {
                Text(status)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(status.contains("失败") ? Color.red.opacity(0.75) : Color(hex: "#4B8B62"))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        switch model.tab {
        case .model: return "DeepSeek、语音与休眠"
        case .persona: return "形象、性格与实时调教"
        case .tasks: return "定时任务与自动化"
        case .memory: return "她记得的事"
        case .skills: return "可复用的工作流"
        case .about: return "权限、数据与版本"
        }
    }
}

// MARK: - Shared bits

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.ink.opacity(0.45))
            .padding(.top, 4)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: "#EADCCB"), lineWidth: 1)
            )
    }
}

private struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(Theme.ink.opacity(0.6))
    }
}

private func saveButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Capsule().fill(Theme.accentFallback))
    }
    .buttonStyle(.plain)
}

// MARK: - Connection

private struct ConnectionPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "DEEPSEEK")
            Card {
                HStack {
                    FieldLabel(text: "API KEY")
                    Spacer()
                    Text(Store.shared.maskedKey)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.ink.opacity(0.45))
                }
                SecureField("sk-…（留空则不修改）", text: $model.apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                HStack(spacing: 10) {
                    FieldLabel(text: "模型")
                    Picker("", selection: $model.modelName) {
                        Text("deepseek-chat").tag("deepseek-chat")
                        Text("deepseek-reasoner").tag("deepseek-reasoner")
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    Spacer()
                    if model.testing {
                        ProgressView().controlSize(.small)
                    }
                    Button("测试连接") { model.testConnection() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.accentFallback)
                }

                HStack(spacing: 8) {
                    FieldLabel(text: "API 地址")
                    TextField("https://api.deepseek.com", text: $model.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }
            }

            SectionTitle(text: "体验")
            Card {
                Toggle("语音回复（用系统中文语音念出来）", isOn: $model.voiceReplies)
                    .font(.system(size: 12, design: .rounded))
                Toggle("自动记忆（在对话里提到的事）", isOn: $model.autoMemory)
                    .font(.system(size: 12, design: .rounded))
                Toggle("启用快捷键 ⌥Space 语音输入", isOn: $model.hotkeyEnabled)
                    .font(.system(size: 12, design: .rounded))
                HStack {
                    FieldLabel(text: "多久没操作就睡觉")
                    Slider(value: Binding(
                        get: { Double(model.idleSleepSeconds) },
                        set: { model.idleSleepSeconds = Int($0) }
                    ), in: 30...600, step: 30)
                    .tint(Theme.accentFallback)
                    Text("\(model.idleSleepSeconds) 秒")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.ink.opacity(0.5))
                        .frame(width: 48, alignment: .trailing)
                }
            }

            HStack {
                Spacer()
                saveButton("保存设置") { model.saveConnection() }
            }
        }
    }
}

// MARK: - Persona

private struct PersonaPane: View {
    @ObservedObject var model: SettingsModel

    private let presets: [(String, String, Color)] = [
        ("tsundere", "傲娇", Color(hex: "#FF9E6D")),
        ("gentle", "温柔", Color(hex: "#9AD0FF")),
        ("genki", "元气", Color(hex: "#FFD166")),
        ("lazy", "咸鱼", Color(hex: "#B8E0D2"))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "预设")
            HStack(spacing: 8) {
                ForEach(presets, id: \.0) { preset in
                    Button {
                        model.applyPreset(Persona.preset(preset.0))
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(preset.2).frame(width: 8, height: 8)
                            Text(preset.1)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.ink.opacity(model.persona.presetID == preset.0 ? 0.9 : 0.5))
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(
                            Capsule().fill(model.persona.presetID == preset.0
                                          ? Color.white.opacity(0.9) : Color.white.opacity(0.35))
                        )
                        .overlay(
                            Capsule().stroke(preset.2.opacity(model.persona.presetID == preset.0 ? 0.8 : 0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            Card {
                HStack(spacing: 10) {
                    FieldLabel(text: "名字")
                    TextField("肥鱼", text: $model.persona.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    FieldLabel(text: "配饰")
                    Picker("", selection: $model.persona.accessory) {
                        Text("蝴蝶结").tag("bow")
                        Text("小花").tag("flower")
                        Text("无").tag("none")
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    Spacer()
                }

                HStack(spacing: 10) {
                    FieldLabel(text: "配色")
                    Text("身体").font(.system(size: 10, design: .rounded)).foregroundColor(Theme.ink.opacity(0.45))
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: model.persona.bodyHex) },
                        set: { model.persona.bodyHex = $0.hexString }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Text("强调").font(.system(size: 10, design: .rounded)).foregroundColor(Theme.ink.opacity(0.45))
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: model.persona.accentHex) },
                        set: { model.persona.accentHex = $0.hexString }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Spacer()
                }

                FieldLabel(text: "性格")
                editor($model.persona.personality, height: 54)
                FieldLabel(text: "说话方式")
                editor($model.persona.speechStyle, height: 44)

                FieldLabel(text: "实时调教（优先级最高，例如：以后别叫我主人，叫老板；生气时也别骂人）")
                editor($model.persona.tuneNote, height: 44)

                HStack {
                    FieldLabel(text: "语音音高")
                    Slider(value: $model.persona.voicePitch, in: 0.8...1.8)
                        .tint(Theme.accentFallback)
                        .frame(width: 120)
                    Text(String(format: "%.2f", model.persona.voicePitch))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.ink.opacity(0.4))
                    Spacer()
                    Button("恢复默认傲娇") { model.resetPersona() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.ink.opacity(0.5))
                    saveButton("应用") { model.savePersona() }
                }
            }
            Text("提示：也可以在聊天里直接说“以后说话温柔点”，肥鱼会自己改。")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(Theme.ink.opacity(0.35))
        }
    }

    private func editor(_ text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(Theme.ink)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(hex: "#E7D8C7"), lineWidth: 1)
            )
    }
}

// MARK: - Tasks

private struct TasksPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "定时任务")
                Spacer()
                Button {
                    model.showAddTask = true
                } label: {
                    Label("新建", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.accentFallback)
            }

            if model.tasks.isEmpty {
                Card {
                    Text("还没有任务。可以让肥鱼“每天早上 9 点汇报天气”，或点右上角新建。")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Theme.ink.opacity(0.45))
                }
            } else {
                ForEach(model.tasks) { task in
                    taskRow(task)
                }
            }

            Text("任务到点会静默执行，结果用气泡和系统通知告诉你；电脑睡眠时暂停，唤醒后补跑。")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(Theme.ink.opacity(0.35))
        }
        .sheet(isPresented: $model.showAddTask) {
            AddTaskSheet(model: model)
        }
    }

    private func taskRow(_ task: TaskSpec) -> some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.ink)
                        Text(task.scheduleText)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(Theme.accentFallback)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accentFallback.opacity(0.1)))
                    }
                    Text(task.prompt)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.ink.opacity(0.5))
                        .lineLimit(2)
                    if let next = task.nextRun {
                        Text("下次：\(ToolExecutor.formatDate(next))")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(Theme.ink.opacity(0.35))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 10) {
                        Button(task.enabled ? "停用" : "启用") { model.toggleTask(task) }
                        Button("测试") { model.runTaskNow(task) }
                        Button("删除") { model.deleteTask(task) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.ink.opacity(0.55))
                }
            }
        }
    }
}

private struct AddTaskSheet: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var prompt = ""
    @State private var kind: ScheduleKind = .daily
    @State private var time = "09:00"
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var interval = 60
    @State private var onceAt = Date().addingTimeInterval(3600)
    @State private var notify = true
    @State private var speak = false

    private let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建定时任务")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.ink)

            TextField("任务名，例如：早间简报", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("到点要做什么，例如：汇总今天的日程和天气", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack {
                Picker("", selection: $kind) {
                    ForEach(ScheduleKind.allCases) { k in
                        Text(k.title).tag(k)
                    }
                }
                .labelsHidden()
                .frame(width: 100)

                switch kind {
                case .once:
                    DatePicker("", selection: $onceAt, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                case .interval:
                    TextField("分钟", value: $interval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("分钟一次").font(.system(size: 11)).foregroundColor(.secondary)
                case .weekly:
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { day in
                            Button(weekdayNames[day - 1]) {
                                if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(weekdays.contains(day)
                                                      ? Theme.accentFallback.opacity(0.8) : Color.black.opacity(0.06)))
                            .foregroundColor(weekdays.contains(day) ? .white : Theme.ink.opacity(0.6))
                        }
                    }
                default:
                    EmptyView()
                }

                if kind != .once && kind != .interval {
                    TextField("09:00", text: $time)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                }
                Spacer()
            }

            HStack(spacing: 14) {
                Toggle("系统通知", isOn: $notify)
                Toggle("语音播报", isOn: $speak)
            }
            .font(.system(size: 11, design: .rounded))

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                Button("创建") { create() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentFallback)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                              || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 460)
        .background(Color(hex: "#FBF6EF"))
    }

    private func create() {
        var task = TaskSpec(title: title, prompt: prompt, kind: kind)
        task.time = time
        task.weekdays = weekdays.sorted()
        task.intervalMinutes = max(1, interval)
        task.onceAt = kind == .once ? onceAt : nil
        task.notify = notify
        task.speak = speak
        model.addTask(task)
        dismiss()
    }
}

// MARK: - Memory

private struct MemoryPane: View {
    @ObservedObject var model: SettingsModel
    @State private var newMemory = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "新增")
            HStack {
                TextField("让她记住一件事，例如：我对花生过敏", text: $newMemory)
                    .textFieldStyle(.roundedBorder)
                Button("记住") {
                    Store.shared.addMemory(text: newMemory)
                    newMemory = ""
                    model.reloadMemories()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.accentFallback)
            }

            HStack {
                SectionTitle(text: "已记住（\(model.memories.count)）")
                Spacer()
                Button("全部清空") {
                    let ok = Safety.confirm(title: "清空所有记忆？", detail: "这会删除肥鱼记住的全部内容，且无法恢复。")
                    if ok {
                        Store.shared.clearMemories()
                        model.reloadMemories()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.red.opacity(0.6))
            }

            if model.memories.isEmpty {
                Card {
                    Text("她还没记住什么。聊天时说“记住……”就会出现在这里。")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Theme.ink.opacity(0.45))
                }
            } else {
                ForEach(model.memories) { memory in
                    HStack(alignment: .top, spacing: 8) {
                        Text(memory.text)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(Theme.ink)
                        Spacer()
                        Button {
                            Store.shared.removeMemory(id: memory.id)
                            model.reloadMemories()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Theme.ink.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.6)))
                }
            }
        }
    }
}

// MARK: - Skills

private struct SkillsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "技能")
                Spacer()
                Button("打开文件夹") { Store.shared.openDataFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(Theme.ink.opacity(0.45))
                Button {
                    model.editingSkill = Skill(id: "", name: "", summary: "", body: "", builtin: false)
                    model.editingIsNew = true
                } label: {
                    Label("新建", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.accentFallback)
            }

            ForEach(model.skills) { skill in
                Button {
                    model.editingSkill = skill
                    model.editingIsNew = false
                } label: {
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(skill.name)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(Theme.ink)
                                    if skill.builtin {
                                        Text("内置")
                                            .font(.system(size: 9, design: .rounded))
                                            .foregroundColor(Theme.accentFallback)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Theme.accentFallback.opacity(0.1)))
                                    }
                                }
                                Text(skill.summary)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(Theme.ink.opacity(0.5))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.ink.opacity(0.2))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $model.editingSkill) { skill in
            SkillEditor(skill: skill, isNew: model.editingIsNew) {
                model.reloadSkills()
            }
        }
    }
}

private struct SkillEditor: View {
    let skill: Skill
    let isNew: Bool
    var onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var summary = ""
    @State private var bodyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isNew ? "新建技能" : "编辑技能")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Theme.ink)
            TextField("名称", text: $name).textFieldStyle(.roundedBorder)
            TextField("一句话描述（会出现在提示词里）", text: $summary).textFieldStyle(.roundedBorder)
            TextEditor(text: $bodyText)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 240)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#E7D8C7"), lineWidth: 1))
            HStack {
                if !isNew {
                    Button("删除") {
                        Store.shared.deleteSkill(id: skill.id)
                        onClose()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.6))
                }
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(.plain)
                Button("保存") {
                    Store.shared.saveSkill(id: isNew ? name : skill.id, name: name, summary: summary, body: bodyText)
                    onClose()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentFallback)
            }
        }
        .padding(20)
        .frame(width: 500)
        .background(Color(hex: "#FBF6EF"))
        .onAppear {
            name = skill.name
            summary = skill.summary
            bodyText = skill.body
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "fish.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(Theme.accentFallback)
                VStack(alignment: .leading, spacing: 2) {
                    Text("大肥鱼")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.ink)
                    Text("版本 1.0.0 · Swift 原生桌宠")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.ink.opacity(0.45))
                }
                Spacer()
            }

            SectionTitle(text: "权限")
            Card {
                permissionRow("麦克风", status: micStatus)
                permissionRow("语音识别", status: speechStatus)
                permissionRow("辅助功能（控制其他 App）", status: AXIsProcessTrusted() ? "已允许" : "未允许")
                permissionRow("屏幕录制（截图）", status: CGPreflightScreenCaptureAccess() ? "已允许" : "未允许")
                Button("打开 隐私与安全性 设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(Theme.accentFallback)
            }

            SectionTitle(text: "快捷键")
            Card {
                HStack {
                    Text("⌥ Space").font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text("语音输入 / 结束").font(.system(size: 11, design: .rounded)).foregroundColor(Theme.ink.opacity(0.5))
                    Spacer()
                    Text("Esc").font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text("取消").font(.system(size: 11, design: .rounded)).foregroundColor(Theme.ink.opacity(0.5))
                }
            }

            SectionTitle(text: "数据")
            Card {
                Text(Store.shared.root.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.ink.opacity(0.5))
                    .lineLimit(2)
                HStack {
                    Button("打开数据目录") { Store.shared.openDataFolder() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(Theme.accentFallback)
                    Spacer()
                    Button("退出大肥鱼") { NSApp.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.red.opacity(0.55))
                }
            }

            Text("所有操作都在本机执行；只有对话内容会发送给 DeepSeek。破坏性操作一律先弹窗确认。")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(Theme.ink.opacity(0.35))
        }
    }

    private func permissionRow(_ name: String, status: String) -> some View {
        HStack {
            Text(name).font(.system(size: 11, design: .rounded)).foregroundColor(Theme.ink.opacity(0.65))
            Spacer()
            Text(status)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(status.contains("已允许") || status.contains("已授权")
                                 ? Color(hex: "#4B8B62") : Theme.ink.opacity(0.35))
        }
    }

    private var micStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "已允许"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        case .notDetermined: return "未询问"
        @unknown default: return "未知"
        }
    }

    private var speechStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return "已允许"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        case .notDetermined: return "未询问"
        @unknown default: return "未知"
        }
    }
}
