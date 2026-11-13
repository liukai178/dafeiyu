import SwiftUI
import AppKit

// MARK: - Panels

class TransparentPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        isRestorable = false
    }
}

final class PetPanel: TransparentPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(size: NSSize(width: 240, height: 240))
        acceptsMouseMovedEvents = true
    }
}

final class BubblePanel: TransparentPanel {
    private let host: NSHostingView<BubbleRoot>
    private var bubbleWidth: CGFloat = 200
    private(set) var bubbleHeight: CGFloat = 40

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        host = NSHostingView(rootView: BubbleRoot(text: "", width: 200, accent: Theme.accentFallback))
        super.init(size: NSSize(width: 200, height: 40))
        ignoresMouseEvents = true
        contentView = host
    }

    func update(text: String, accent: Color) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let measured = BubblePanel.measure(text)
        bubbleWidth = measured.width
        bubbleHeight = measured.height
        host.rootView = BubbleRoot(text: text, width: bubbleWidth, accent: accent)
        host.frame = NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight + 9)
        setContentSize(NSSize(width: bubbleWidth, height: bubbleHeight + 9))
        contentView?.frame = NSRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight + 9)
    }

    static func measure(_ text: String) -> (width: CGFloat, height: CGFloat) {
        let font = NSFont.systemFont(ofSize: 13)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxTextWidth: CGFloat = 232
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let textWidth = ceil(rect.width)
        let width = min(max(96, textWidth + 30), maxTextWidth + 30)
        let height = ceil(rect.height) + 21
        return (width, max(36, height))
    }
}

final class InputModel: ObservableObject {
    @Published var text: String = ""
    @Published var focusRequest: Int = 0
}

final class InputPanel: TransparentPanel {
    private let host: TrackingHostingView<InputBar>
    let model: InputModel
    var onHover: ((Bool) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(state: PetState, model: InputModel,
         onSubmit: @escaping (String) -> Void,
         onMic: @escaping () -> Void,
         onClose: @escaping () -> Void,
         onActivate: @escaping () -> Void) {
        self.model = model
        host = TrackingHostingView(rootView: InputBar(
            state: state, model: model,
            onSubmit: onSubmit, onMic: onMic, onClose: onClose, onActivate: onActivate
        ))
        super.init(size: NSSize(width: 306, height: 46))
        contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 306, height: 46)
        host.onHover = { [weak self] hovering in self?.onHover?(hovering) }
    }

    func refresh(state: PetState,
                 onSubmit: @escaping (String) -> Void,
                 onMic: @escaping () -> Void,
                 onClose: @escaping () -> Void,
                 onActivate: @escaping () -> Void) {
        host.rootView = InputBar(
            state: state, model: model,
            onSubmit: onSubmit, onMic: onMic, onClose: onClose, onActivate: onActivate
        )
    }

    func focusField() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        if let field = Self.findTextField(in: contentView) {
            makeFirstResponder(field)
        }
    }

    private static func findTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let tf = view as? NSTextField { return tf }
        for sub in view.subviews {
            if let found = findTextField(in: sub) { return found }
        }
        return nil
    }
}

final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

// MARK: - Bubble

struct BubbleRoot: View {
    let text: String
    let width: CGFloat
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(Theme.ink)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Theme.bubbleFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Theme.bubbleStroke, lineWidth: 1)
                )
            BubbleTail()
                .fill(Theme.bubbleFill)
                .frame(width: 16, height: 9)
                .overlay(
                    BubbleTail().stroke(Theme.bubbleStroke, lineWidth: 1)
                        .frame(width: 16, height: 9)
                )
                .offset(y: -1)
        }
        .frame(width: width)
        .shadow(color: Color.black.opacity(0.10), radius: 7, y: 3)
        .padding(.bottom, 4)
    }
}

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.width / 2, y: rect.height),
                       control: CGPoint(x: rect.width * 0.32, y: rect.height * 0.72))
        p.addQuadCurve(to: CGPoint(x: rect.width, y: 0),
                       control: CGPoint(x: rect.width * 0.68, y: rect.height * 0.72))
        p.closeSubpath()
        return p
    }
}

// MARK: - Input bar

struct InputBar: View {
    @ObservedObject var state: PetState
    @ObservedObject var model: InputModel
    var onSubmit: (String) -> Void
    var onMic: () -> Void
    var onClose: () -> Void
    var onActivate: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "fish.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(state.persona.accentColor)

            ZStack(alignment: .leading) {
                if model.text.isEmpty {
                    Text("和肥鱼说点什么…")
                        .font(.system(size: 13.5, weight: .regular, design: .rounded))
                        .foregroundColor(Theme.ink.opacity(0.35))
                        .allowsHitTesting(false)
                }
                TextField("", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                    .foregroundColor(Theme.ink)
                    .focused($focused)
                    .onSubmit { submit() }
                    .onExitCommand { close() }
                    .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)

            Button(action: onMic) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(state.persona.accentColor.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("语音输入（⌥Space）")

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? Theme.ink.opacity(0.2) : state.persona.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 42)
        .background(
            Capsule(style: .continuous)
                .fill(Color(hex: "#FFFDF8").opacity(0.98))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(state.persona.accentColor.opacity(focused ? 0.5 : 0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
        .padding(2)
        .contentShape(Capsule())
        .onTapGesture { onActivate() }
        .onChange(of: model.focusRequest) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onChange(of: state.inputVisible) { _, visible in
            if !visible { focused = false }
        }
    }

    private func submit() {
        let value = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        model.text = ""
        onSubmit(value)
    }

    private func close() {
        model.text = ""
        onClose()
    }
}
