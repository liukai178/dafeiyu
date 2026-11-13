import Foundation
import SwiftUI
import Combine


final class PetState: ObservableObject {
    @Published var mood: Mood = .idle
    @Published var bubbleText: String = ""
    @Published var bubbleVisible: Bool = false
    @Published var inputVisible: Bool = false
    @Published var listening: Bool = false
    @Published var thinking: Bool = false
    @Published var speaking: Bool = false
    @Published var partialText: String = ""
    @Published var hovered: Bool = false
    @Published var pressed: Bool = false
    @Published var idle: Bool = false
    @Published var systemAsleep: Bool = false
    @Published var toolNote: String? = nil
    @Published var persona: Persona = .tsundere
    @Published var voiceLevel: Double = 0
    @Published var needsSetup: Bool = false
    var snapshotMode = false

    private var moodToken = 0
    private var bubbleToken = 0

    var busy: Bool { thinking || listening || speaking }

    func setMood(_ m: Mood, revertAfter: TimeInterval? = nil) {
        moodToken += 1
        let token = moodToken
        if mood != m { mood = m }
        guard let delay = revertAfter else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.moodToken == token else { return }
            if !self.busy { self.mood = .idle }
        }
    }

    func showBubble(_ text: String, autoHide: TimeInterval? = 6) {
        bubbleToken += 1
        let token = bubbleToken
        bubbleText = text
        bubbleVisible = !text.isEmpty
        guard let delay = autoHide else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.bubbleToken == token else { return }
            if !self.busy { self.bubbleVisible = false }
        }
    }

    func appendBubble(_ chunk: String) {
        bubbleToken += 1
        bubbleVisible = true
        bubbleText += chunk
    }

    func hideBubble() {
        bubbleToken += 1
        bubbleVisible = false
    }
}

enum PetEvent {
    static let hover = Notification.Name("dafeiyu.pet.hover")
    static let tap = Notification.Name("dafeiyu.pet.tap")
    static let doubleTap = Notification.Name("dafeiyu.pet.doubleTap")
    static let dragBegan = Notification.Name("dafeiyu.pet.dragBegan")
    static let dragChanged = Notification.Name("dafeiyu.pet.dragChanged")
    static let dragEnded = Notification.Name("dafeiyu.pet.dragEnded")
    static let menu = Notification.Name("dafeiyu.pet.menu")
    static let openChat = Notification.Name("dafeiyu.openChat")
}

final class PetRuntime {
    static let shared = PetRuntime()
    private init() {}

    func hover(_ h: Bool) { NotificationCenter.default.post(name: PetEvent.hover, object: h) }
    func tap() { NotificationCenter.default.post(name: PetEvent.tap, object: nil) }
    func doubleTap() { NotificationCenter.default.post(name: PetEvent.doubleTap, object: nil) }
    func dragBegan() { NotificationCenter.default.post(name: PetEvent.dragBegan, object: nil) }
    func dragChanged(_ t: CGSize) { NotificationCenter.default.post(name: PetEvent.dragChanged, object: t) }
    func dragEnded() { NotificationCenter.default.post(name: PetEvent.dragEnded, object: nil) }
    func openMenu() { NotificationCenter.default.post(name: PetEvent.menu, object: nil) }
    func openChat() { NotificationCenter.default.post(name: PetEvent.openChat, object: nil) }
}
