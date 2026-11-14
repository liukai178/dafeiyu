import AppKit
import SwiftUI
import Combine
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = PetState()
    let inputModel = InputModel()

    private var petPanel: PetPanel!
    private var bubblePanel: BubblePanel!
    private var answerPanel: AnswerPanel!
    private var inputPanel: InputPanel!
    private var statusItem: NSStatusItem!
    private var togglePetItem: NSMenuItem!
    private var cancellables = Set<AnyCancellable>()

    private var inputHovered = false
    private var inputShowWork: DispatchWorkItem?
    private var inputHideWork: DispatchWorkItem?
    private var idleTimer: Timer?
    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var lastInteraction = Date()
    private var lastAskWasVoice = false
    private var askWatchdog: DispatchWorkItem?

    private var petHidden = false
    private let originKey = "DaFeiYu.petOrigin"

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        state.persona = Store.shared.config.persona

        setupMainMenu()
        setupStatusItem()
        setupPanels()
        setupObservers()
        setupHotkeys()
        setupPowerObservers()
        setupSpeech()
        setupAgent()
        startIdleMonitor()
        Scheduler.shared.start()
        layoutPanels()
        greet()
        if let idx = CommandLine.arguments.firstIndex(of: "--chat-test"),
           idx + 1 < CommandLine.arguments.count {
            let question = CommandLine.arguments[idx + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.ask(question, viaVoice: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 24) { [weak self] in
                guard let self else { return }
                print("CHAT_RESULT: \(self.state.bubbleText)")
                print("CHAT_THINKING: \(self.state.thinking)")
                self.showAnswer()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.snapshot(view: self.answerPanel.contentView, path: "/tmp/answer.png")
                    self.snapshot(view: self.bubblePanel.contentView, path: "/tmp/bubble-reply.png")
                    self.snapshot(view: self.petPanel.contentView, path: "/tmp/pet-reply.png")
                    NSApp.terminate(nil)
                }
            }
        }
        if let idx = CommandLine.arguments.firstIndex(of: "--ui-snapshot"),
           idx + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[idx + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.captureUI(to: dir)
            }
        }
        NSLog("DaFeiYu launched, data=\(Store.shared.root.path)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveOrigin()
        idleTimer?.invalidate()
        SpeechController.shared.cancel()
        SpeechController.shared.stopSpeaking()
        HotKeyCenter.shared.unregisterAll()
    }

    // MARK: - Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出大肥鱼", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: "大肥鱼")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(makeItem("和肥鱼说话", #selector(openChatAction)))
        menu.addItem(makeItem("语音输入  ⌥Space", #selector(voiceAction)))
        menu.addItem(.separator())
        menu.addItem(makeItem("设置…", #selector(openSettings)))
        menu.addItem(makeItem("任务与自动化…", #selector(openTasks)))
        menu.addItem(makeItem("记忆…", #selector(openMemory)))
        menu.addItem(.separator())
        togglePetItem = makeItem("隐藏肥鱼", #selector(togglePetVisibility))
        menu.addItem(togglePetItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func setupPanels() {
        petPanel = PetPanel()
        let petHost = NSHostingView(rootView: PetView(state: state))
        petHost.frame = NSRect(x: 0, y: 0, width: 280, height: 320)
        petPanel.contentView = petHost

        let saved = UserDefaults.standard.string(forKey: originKey).map(NSPointFromString)
        petPanel.setFrameOrigin(clampOrigin(saved ?? defaultOrigin()))
        petPanel.orderFrontRegardless()

        bubblePanel = BubblePanel(onTap: { [weak self] in self?.showAnswer() })
        answerPanel = AnswerPanel()

        inputPanel = InputPanel(
            state: state,
            model: inputModel,
            onSubmit: { [weak self] text in
                self?.inputModel.text = ""
                self?.hideInput()
                self?.ask(text, viaVoice: false)
            },
            onMic: { [weak self] in
                self?.hideInput()
                self?.startVoice()
            },
            onClose: { [weak self] in
                self?.hideInput()
            },
            onActivate: { [weak self] in
                self?.activateInput()
            }
        )
        inputPanel.onHover = { [weak self] hovering in
            guard let self else { return }
            self.inputHovered = hovering
            if hovering {
                self.inputHideWork?.cancel()
            } else {
                self.scheduleHideInput()
            }
        }
    }

    private func setupObservers() {
        state.$bubbleText
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshBubble() }
            .store(in: &cancellables)
        state.$bubbleVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshBubble() }
            .store(in: &cancellables)
        state.$inputVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshInputVisibility() }
            .store(in: &cancellables)
        state.$persona
            .receive(on: RunLoop.main)
            .sink { [weak self] persona in
                guard let self else { return }
                self.refreshBubble()
                self.inputPanel?.refresh(
                    state: self.state,
                    onSubmit: { [weak self] text in
                        self?.inputModel.text = ""
                        self?.hideInput()
                        self?.ask(text, viaVoice: false)
                    },
                    onMic: { [weak self] in self?.hideInput(); self?.startVoice() },
                    onClose: { [weak self] in self?.hideInput() },
                    onActivate: { [weak self] in self?.activateInput() }
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: PetEvent.hover, object: nil, queue: .main
        ) { [weak self] note in
            self?.handlePetHover(note.object as? Bool ?? false)
        }
        NotificationCenter.default.addObserver(
            forName: PetEvent.tap, object: nil, queue: .main
        ) { [weak self] _ in self?.handlePetTap() }
        NotificationCenter.default.addObserver(
            forName: PetEvent.doubleTap, object: nil, queue: .main
        ) { [weak self] _ in self?.openChat() }
        NotificationCenter.default.addObserver(
            forName: PetEvent.openChat, object: nil, queue: .main
        ) { [weak self] _ in self?.openChat() }
        NotificationCenter.default.addObserver(
            forName: PetEvent.dragBegan, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.dragStartOrigin = self.petPanel.frame.origin
            self.dragStartMouse = NSEvent.mouseLocation
            self.inputHideWork?.cancel()
        }
        NotificationCenter.default.addObserver(
            forName: PetEvent.dragChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let startOrigin = self.dragStartOrigin,
                  let startMouse = self.dragStartMouse else { return }
            let mouse = NSEvent.mouseLocation
            let origin = NSPoint(x: startOrigin.x + (mouse.x - startMouse.x),
                                 y: startOrigin.y + (mouse.y - startMouse.y))
            self.petPanel.setFrameOrigin(self.clampOrigin(origin))
            self.layoutPanels()
            self.lastInteraction = Date()
        }
        NotificationCenter.default.addObserver(
            forName: PetEvent.dragEnded, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dragStartOrigin = nil
            self?.dragStartMouse = nil
            self?.saveOrigin()
            self?.layoutPanels()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: inputPanel, queue: .main
        ) { [weak self] _ in self?.inputHideWork?.cancel() }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: inputPanel, queue: .main
        ) { [weak self] _ in self?.scheduleHideInput() }
        NotificationCenter.default.addObserver(
            forName: .personaChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.state.persona = Store.shared.config.persona
            self.refreshBubble()
        }
        NotificationCenter.default.addObserver(
            forName: .taskFinished, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let info = note.userInfo,
                  let title = info["title"] as? String,
                  let text = info["text"] as? String else { return }
            self.state.showBubble("【\(title)】\(text)", autoHide: 30)
            self.state.setMood(.happy, revertAfter: 4)
            if (info["speak"] as? Bool) == true || Store.shared.config.voiceReplies {
                SpeechController.shared.speak(text, persona: self.state.persona, mood: .happy)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.layoutPanels() }
    }

    private func setupHotkeys() {
        HotKeyCenter.shared.onVoice = { [weak self] in self?.toggleVoice() }
        HotKeyCenter.shared.onEscape = { [weak self] in self?.cancelVoice() }
        if Store.shared.config.hotkeyEnabled {
            HotKeyCenter.shared.registerVoice()
        }
    }

    private func setupPowerObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.enterSystemSleep()
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.leaveSystemSleep()
            }
        }
        nc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.enterSystemSleep()
        }
        nc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.leaveSystemSleep()
        }
    }

    private func setupAgent() {
        let agent = AgentController.shared
        agent.onStart = { [weak self] in
            guard let self else { return }
            self.state.thinking = true
            self.state.setMood(.thinking)
            self.state.bubbleText = ""
            self.state.bubbleVisible = true
        }
        agent.onPartial = { [weak self] text in
            guard let self else { return }
            self.state.bubbleText = text
            self.state.bubbleVisible = true
        }
        agent.onStatus = { [weak self] status in
            guard let self else { return }
            self.state.toolNote = status
            if let status, !status.isEmpty {
                self.state.showBubble(status, autoHide: nil)
            }
        }
        agent.onFinish = { [weak self] text in
            guard let self else { return }
            self.finishChat(text: text, viaVoice: self.lastAskWasVoice)
        }
        agent.onError = { [weak self] message in
            guard let self else { return }
            self.askWatchdog?.cancel()
            Store.shared.audit("chat error: \(message.prefix(160))")
            self.state.thinking = false
            self.state.toolNote = nil
            self.state.showBubble("唔……\(message)", autoHide: 9)
            self.state.setMood(.pouty, revertAfter: 3)
        }
    }

    private func setupSpeech() {
        let speech = SpeechController.shared
        speech.onPartial = { [weak self] text in
            guard let self else { return }
            self.lastInteraction = Date()
            self.state.partialText = text
            if !text.isEmpty {
                self.state.bubbleText = text
                self.state.bubbleVisible = true
            }
        }
        speech.onFinal = { [weak self] text in
            guard let self else { return }
            self.finishListening()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                self.state.showBubble("唔…没听清，再说一次？", autoHide: 4)
                self.state.setMood(.pouty, revertAfter: 2)
            } else {
                self.ask(trimmed, viaVoice: true)
            }
        }
        speech.onError = { [weak self] message in
            guard let self else { return }
            self.finishListening()
            self.state.showBubble(message, autoHide: 6)
            self.showInput(focus: true)
        }
        speech.onLevel = { [weak self] level in
            self?.state.voiceLevel = level
        }
        speech.onSpeakStart = { [weak self] in
            guard let self else { return }
            self.state.speaking = true
            self.state.setMood(.speaking)
        }
        speech.onSpeakEnd = { [weak self] in
            guard let self else { return }
            self.state.speaking = false
            if self.state.mood == .speaking { self.state.setMood(.idle) }
        }
    }

    private func startIdleMonitor() {
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    // MARK: - Debug snapshot

    private func captureUI(to dir: String) {
        state.persona = Store.shared.config.persona
        state.setMood(.idle)
        state.showBubble("哼，总算开机了。今天也要好好干活，别摸鱼。", autoHide: nil)
        showInput(focus: false)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.snapshot(view: self.petPanel.contentView, path: dir + "/pet-window.png")
            self.snapshot(view: self.bubblePanel.contentView, path: dir + "/bubble.png")
            self.snapshot(view: self.inputPanel.contentView, path: dir + "/input.png")
            SettingsController.shared.show(tab: .persona)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if let window = NSApp.windows.first(where: { $0.title == "大肥鱼" && $0.contentView?.frame.width ?? 0 > 400 }) {
                    self.snapshot(view: window.contentView, path: dir + "/settings.png")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func snapshot(view: NSView?, path: String) {
        guard let view, view.bounds.width > 1, view.bounds.height > 1 else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Greeting

    private func greet() {
        let configured = Store.shared.isConfigured
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            if configured {
                self.state.showBubble("哼，总算开机了。有事就说，我听着呢。", autoHide: 7)
                self.state.setMood(.happy, revertAfter: 3)
            } else {
                self.state.showBubble("我是肥鱼。先去设置里填上 DeepSeek API Key，不然我只能哼给你听。", autoHide: 14)
                self.state.setMood(.pouty, revertAfter: 4)
                SettingsController.shared.show(tab: .model)
            }
        }
    }

    // MARK: - Layout

    private func defaultOrigin() -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return NSPoint(x: 100, y: 100) }
        let vf = screen.visibleFrame
        return NSPoint(x: vf.maxX - 280 - 26, y: vf.minY + 16)
    }

    private func clampOrigin(_ origin: NSPoint) -> NSPoint {
        let size = NSSize(width: 280, height: 320)
        let frame = NSRect(origin: origin, size: size)
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let x = min(max(origin.x, vf.minX - 40), vf.maxX - size.width + 40)
        let y = min(max(origin.y, vf.minY - 20), vf.maxY - size.height + 20)
        return NSPoint(x: x, y: y)
    }

    private func saveOrigin() {
        guard let petPanel else { return }
        UserDefaults.standard.set(NSStringFromPoint(petPanel.frame.origin), forKey: originKey)
    }

    func layoutPanels() {
        guard let petPanel, let inputPanel, let bubblePanel else { return }
        let pf = petPanel.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(pf) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame

        let iw: CGFloat = 306, ih: CGFloat = 46
        var ix = pf.maxX - iw
        ix = min(max(ix, vf.minX + 8), vf.maxX - iw - 8)
        var iy = pf.maxY + 6
        iy = min(iy, vf.maxY - ih - 8)
        inputPanel.setFrameOrigin(NSPoint(x: ix, y: iy))

        let bw = bubblePanel.frame.width
        let bh = bubblePanel.frame.height
        var bx = pf.midX - bw / 2
        bx = min(max(bx, vf.minX + 8), vf.maxX - bw - 8)
        let anchorY = state.inputVisible ? inputPanel.frame.maxY : pf.maxY
        var by = anchorY + 6
        by = min(by, vf.maxY - bh - 6)
        bubblePanel.setFrameOrigin(NSPoint(x: bx, y: by))

        if answerPanel != nil && answerPanel.isVisible {
            let aw: CGFloat = 420, ah: CGFloat = 400
            var ax = pf.minX - aw - 12
            if ax < vf.minX + 8 {
                ax = min(max(pf.midX - aw / 2, vf.minX + 8), vf.maxX - aw - 8)
            }
            var ay = pf.midY - ah / 2
            ay = min(max(ay, vf.minY + 8), vf.maxY - ah - 8)
            answerPanel.setFrameOrigin(NSPoint(x: ax, y: ay))
        }
    }

    func showAnswer() {
        let text = state.bubbleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        answerPanel.show(text: text, accent: state.persona.accentColor) { [weak self] in
            self?.answerPanel.orderOut(nil)
        }
        layoutPanels()
    }

    // MARK: - Bubble / input

    private func refreshBubble() {
        guard let bubblePanel else { return }
        if state.bubbleVisible && !state.bubbleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bubblePanel.update(text: state.bubbleText, accent: state.persona.accentColor)
            if !petHidden {
                bubblePanel.orderFrontRegardless()
            }
            if answerPanel.isVisible {
                answerPanel.update(text: state.bubbleText, accent: state.persona.accentColor)
            }
        } else {
            bubblePanel.orderOut(nil)
        }
        layoutPanels()
    }

    private func refreshInputVisibility() {
        guard let inputPanel else { return }
        if state.inputVisible {
            inputPanel.orderFrontRegardless()
            layoutPanels()
        } else {
            inputPanel.orderOut(nil)
            layoutPanels()
        }
    }

    private func handlePetHover(_ hovering: Bool) {
        lastInteraction = Date()
        if hovering {
            inputHideWork?.cancel()
            scheduleShowInput()
        } else {
            scheduleHideInput()
        }
    }

    private func scheduleShowInput() {
        inputShowWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.petHidden else { return }
            self.showInput(focus: false)
        }
        inputShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func scheduleHideInput() {
        inputHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.inputHovered || self.inputPanel.isKeyWindow { return }
            self.hideInput()
        }
        inputHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    func showInput(focus: Bool) {
        guard !petHidden else { return }
        if !state.inputVisible {
            state.inputVisible = true
        }
        inputPanel.orderFrontRegardless()
        layoutPanels()
        if focus {
            activateInput()
        }
    }

    func hideInput() {
        inputShowWork?.cancel()
        state.inputVisible = false
        inputModel.text = ""
        if inputPanel.isKeyWindow {
            inputPanel.orderOut(nil)
        }
    }

    func activateInput() {
        guard !petHidden else { return }
        NSApp.activate(ignoringOtherApps: true)
        showInput(focus: false)
        inputPanel.makeKeyAndOrderFront(nil)
        inputModel.focusRequest += 1
        lastInteraction = Date()
    }

    func openChat() {
        showInput(focus: true)
    }

    // MARK: - Actions

    @objc private func openChatAction() { openChat() }

    @objc private func voiceAction() { toggleVoice() }

    @objc private func openSettings() { SettingsController.shared.show(tab: .model) }

    @objc private func openTasks() { SettingsController.shared.show(tab: .tasks) }

    @objc private func openMemory() { SettingsController.shared.show(tab: .memory) }

    @objc private func togglePetVisibility() {
        petHidden.toggle()
        togglePetItem.title = petHidden ? "显示肥鱼" : "隐藏肥鱼"
        if petHidden {
            petPanel.orderOut(nil)
            bubblePanel.orderOut(nil)
            answerPanel.orderOut(nil)
            hideInput()
        } else {
            petPanel.orderFrontRegardless()
            refreshBubble()
        }
    }

    func hidePet() { if !petHidden { togglePetVisibility() } }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Chat

    func ask(_ text: String, viaVoice: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastInteraction = Date()
        hideInput()
        guard Store.shared.isConfigured else {
            state.showBubble("还没填 DeepSeek API Key 呢，去设置里填一下，我才能好好说话。", autoHide: 8)
            SettingsController.shared.show(tab: .model)
            return
        }
        lastAskWasVoice = viaVoice
        Store.shared.appendHistory(ChatTurn(role: "user", text: trimmed, viaVoice: viaVoice))
        Store.shared.audit("chat user: \(trimmed.prefix(120))")
        askWatchdog?.cancel()
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.state.thinking else { return }
            AgentController.shared.cancel()
            self.state.thinking = false
            self.state.setMood(.pouty, revertAfter: 3)
            self.state.showBubble("这次想太久了，卡住啦……再试一次？", autoHide: 8)
            Store.shared.audit("chat watchdog timeout")
        }
        askWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 80, execute: watchdog)
        state.thinking = true
        state.setMood(.thinking)
        state.bubbleText = "……"
        state.bubbleVisible = true
        AgentController.shared.send(text: trimmed, viaVoice: viaVoice)
    }

    func finishChat(text: String, viaVoice: Bool) {
        askWatchdog?.cancel()
        Store.shared.audit("chat assistant: \(text.prefix(120))")
        state.thinking = false
        state.toolNote = nil
        state.bubbleText = text
        state.bubbleVisible = true
        state.showBubble(text, autoHide: 15)
        state.setMood(.happy, revertAfter: 2.5)
        Store.shared.appendHistory(ChatTurn(role: "assistant", text: text))
        if Store.shared.config.voiceReplies || viaVoice {
            SpeechController.shared.speak(text, persona: state.persona, mood: state.mood)
        }
    }

    // MARK: - Voice

    func startVoice() {
        guard !state.listening else { return }
        if state.thinking {
            state.showBubble("等我把这句想完。", autoHide: 3)
            return
        }
        SpeechController.shared.stopSpeaking()
        state.partialText = ""
        state.listening = true
        state.setMood(.listening)
        state.showBubble("我在听…说完自动发送，按 Esc 取消。", autoHide: nil)
        HotKeyCenter.shared.setEscapeEnabled(true)
        SpeechController.shared.start()
        lastInteraction = Date()
    }

    func finishListening() {
        state.listening = false
        state.setMood(.idle)
        HotKeyCenter.shared.setEscapeEnabled(false)
        SpeechController.shared.stopAudioOnly()
    }

    func toggleVoice() {
        if state.listening {
            SpeechController.shared.finish()
        } else {
            startVoice()
        }
    }

    func cancelVoice() {
        guard state.listening else { return }
        SpeechController.shared.cancel()
        finishListening()
        state.showBubble("好，不听了。", autoHide: 2.5)
    }

    // MARK: - Idle / sleep

    private func checkIdle() {
        guard !state.systemAsleep else { return }
        if state.thinking || state.listening || state.inputVisible || state.hovered {
            if state.idle { wakeFromIdle() }
            return
        }
        let anyInput = CGEventType(rawValue: ~0)!
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let threshold = max(30, Store.shared.config.idleSleepSeconds)
        if seconds > Double(threshold) {
            if !state.idle {
                state.idle = true
                state.setMood(.sleepy)
                state.bubbleVisible = false
            }
        } else if state.idle {
            wakeFromIdle()
        }
    }

    private func wakeFromIdle() {
        state.idle = false
        if state.mood == .sleepy { state.setMood(.idle) }
    }

    private func enterSystemSleep() {
        state.systemAsleep = true
        state.idle = true
        state.setMood(.sleepy)
        state.bubbleVisible = false
        SpeechController.shared.cancel()
        SpeechController.shared.stopSpeaking()
        if state.listening { finishListening() }
        Scheduler.shared.setPaused(true)
    }

    private func leaveSystemSleep() {
        state.systemAsleep = false
        state.idle = false
        state.setMood(.idle)
        Scheduler.shared.setPaused(false)
        lastInteraction = Date()
    }

    private func handlePetTap() {
        lastInteraction = Date()
        guard !state.listening else { return }
        if state.busy { return }
        state.setMood(.shy, revertAfter: 1.4)
        let lines = [
            "哼，戳我干嘛。",
            "别、别老摸头啦……",
            "在呢在呢，说。",
            "你今天的活儿干完了吗？",
            "再戳就要收费了。"
        ]
        state.showBubble(lines.randomElement() ?? "嗯？", autoHide: 3)
    }
}
