import SwiftUI
import AppKit

// MARK: - Root pet view

struct PetView: View {
    @ObservedObject var state: PetState
    @State private var dragging = false

    private var interval: Double {
        if state.idle || state.mood == .sleepy { return 0.75 }       // ~1.3 fps
        if state.listening || state.speaking { return 0.12 }         // ~8 fps（口型/波形）
        return 0.3                                                   // ~3.3 fps 环境动画
    }

    var body: some View {
        Group {
            if state.systemAsleep {
                PetCanvas(state: state, t: 0)
            } else {
                TimelineView(.periodic(from: .now, by: interval)) { context in
                    PetCanvas(
                        state: state,
                        t: context.date.timeIntervalSinceReferenceDate
                    )
                }
            }
        }
        .frame(width: 240, height: 240)
        .contentShape(Rectangle())
        .onHover { hovering in
            if state.hovered != hovering {
                state.hovered = hovering
                PetRuntime.shared.hover(hovering)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    if !dragging {
                        dragging = true
                        PetRuntime.shared.dragBegan()
                    }
                    PetRuntime.shared.dragChanged(value.translation)
                }
                .onEnded { _ in
                    dragging = false
                    PetRuntime.shared.dragEnded()
                }
        )
        .onTapGesture(count: 2) {
            PetRuntime.shared.doubleTap()
        }
        .onTapGesture {
            tapPet()
        }
        .contextMenu {
            Button("和肥鱼说话") { PetRuntime.shared.openChat() }
            Button("设置…") { SettingsController.shared.showWindow(nil) }
            Divider()
            Button("隐藏肥鱼") { (NSApp.delegate as? AppDelegate)?.hidePet() }
            Button("退出") { NSApp.terminate(nil) }
        }
    }

    private func tapPet() {
        Haptics.soft()
        state.pressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                state.pressed = false
            }
        }
        PetRuntime.shared.tap()
    }
}

// MARK: - Canvas

private struct PetCanvas: View {
    @ObservedObject var state: PetState
    let t: Double

    private var persona: Persona { state.persona }

    private var bob: CGFloat {
        if state.systemAsleep { return 0 }
        if state.mood == .sleepy { return CGFloat(sin(t * 2 * .pi / 4.2)) * 1.2 }
        return CGFloat(sin(t * 2 * .pi / 3.6)) * 2.2
    }

    private var breath: CGFloat {
        guard !state.systemAsleep else { return 1 }
        return 1 + CGFloat(sin(t * 2 * .pi / 3.6)) * 0.006
    }

    private var tailAngle: Double {
        if state.mood == .sleepy || state.systemAsleep { return sin(t * 0.6) * 2 }
        let speed = state.mood == .happy ? 1.0 : 0.55
        let amount = state.mood == .happy ? 11.0 : 7.0
        return sin(t * 2 * .pi * speed) * amount
    }

    private var squishX: CGFloat { state.pressed ? 1.055 : (state.hovered ? 1.015 : 1) }
    private var squishY: CGFloat { state.pressed ? 0.945 : (state.hovered ? 0.995 : 1) }

    var body: some View {
        ZStack {
            // 地面阴影
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(state.systemAsleep ? 0.05 : 0.13), Color.black.opacity(0)],
                        center: .center, startRadius: 2, endRadius: 58
                    )
                )
                .frame(width: 120, height: 18)
                .position(x: 132, y: 212)

            if state.listening || state.thinking {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [persona.accentColor.opacity(0.22), persona.accentColor.opacity(0)],
                            center: .center, startRadius: 30, endRadius: 100
                        )
                    )
                    .frame(width: 210, height: 210)
                    .position(x: 132, y: 138)
                    .scaleEffect(state.listening ? 1 + CGFloat(sin(t * 3.4)) * 0.025 : 1)
            }

            Group {
                FishTail(colors: [persona.accentColor, persona.finColor])
                    .frame(width: 100, height: 102)
                    .rotationEffect(.degrees(tailAngle), anchor: .trailing)
                    .position(x: 58, y: 142)

                FishBodyShape()
                    .fill(
                        LinearGradient(
                            colors: [persona.finColor.opacity(0.98), persona.bodyColor, persona.bodyColor.opacity(0.94)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        FishBodyShape()
                            .stroke(Color(hex: "#D9764E").opacity(0.28), lineWidth: 1)
                    )
                    .frame(width: 146, height: 122)
                    .position(x: 134, y: 139)

                // 肚皮
                Ellipse()
                    .fill(persona.bellyColor.opacity(0.92))
                    .frame(width: 92, height: 56)
                    .position(x: 140, y: 165)

                // 胸鳍
                PectoralFin(colors: [persona.finColor, persona.accentColor])
                    .frame(width: 30, height: 16)
                    .rotationEffect(.degrees(28 + sin(t * 2.1) * 4), anchor: .leading)
                    .position(x: 86, y: 182)

                FishFace(state: state, t: t)
                    .frame(width: 146, height: 122)
                    .position(x: 134, y: 139)

                if state.persona.outfit == "scarf" {
                    Scarf(color: persona.accentColor)
                        .frame(width: 104, height: 40)
                        .position(x: 134, y: 188)
                }

                Accessory(kind: persona.accessory, color: persona.accentColor)
                    .frame(width: 48, height: 30)
                    .rotationEffect(.degrees(-8))
                    .position(x: 114, y: 86)

                BubbleDeco(state: state, t: t, color: persona.accentColor)
                    .frame(width: 240, height: 240)
            }
            .scaleEffect(x: squishX, y: squishY, anchor: .bottom)
            .scaleEffect(state.hovered ? 1.012 : 1)
            .offset(y: bob)
            .scaleEffect(x: 1, y: breath, anchor: .bottom)
        }
        .frame(width: 240, height: 240)
        .opacity(state.systemAsleep ? 0.85 : 1)
        .animation(.easeOut(duration: 0.18), value: state.pressed)
        .animation(.easeOut(duration: 0.2), value: state.hovered)
    }
}

// MARK: - Shapes

struct FishBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0.03 * w, y: 0.57 * h))
        p.addCurve(to: CGPoint(x: 0.50 * w, y: 0.02 * h),
                   control1: CGPoint(x: 0.03 * w, y: 0.20 * h),
                   control2: CGPoint(x: 0.22 * w, y: 0.02 * h))
        p.addCurve(to: CGPoint(x: 0.97 * w, y: 0.52 * h),
                   control1: CGPoint(x: 0.80 * w, y: 0.02 * h),
                   control2: CGPoint(x: 0.97 * w, y: 0.22 * h))
        p.addCurve(to: CGPoint(x: 0.52 * w, y: 0.98 * h),
                   control1: CGPoint(x: 0.97 * w, y: 0.84 * h),
                   control2: CGPoint(x: 0.80 * w, y: 0.98 * h))
        p.addCurve(to: CGPoint(x: 0.03 * w, y: 0.57 * h),
                   control1: CGPoint(x: 0.20 * w, y: 0.98 * h),
                   control2: CGPoint(x: 0.03 * w, y: 0.84 * h))
        p.closeSubpath()
        return p
    }
}

struct FishTail: View {
    let colors: [Color]
    var body: some View {
        TailShape()
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .overlay(
                TailShape().stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
    }
}

struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0.99 * w, y: 0.50 * h))
        p.addCurve(to: CGPoint(x: 0.12 * w, y: 0.06 * h),
                   control1: CGPoint(x: 0.74 * w, y: 0.22 * h),
                   control2: CGPoint(x: 0.36 * w, y: 0.02 * h))
        p.addCurve(to: CGPoint(x: 0.40 * w, y: 0.46 * h),
                   control1: CGPoint(x: 0.24 * w, y: 0.22 * h),
                   control2: CGPoint(x: 0.32 * w, y: 0.34 * h))
        p.addCurve(to: CGPoint(x: 0.10 * w, y: 0.94 * h),
                   control1: CGPoint(x: 0.26 * w, y: 0.60 * h),
                   control2: CGPoint(x: 0.18 * w, y: 0.78 * h))
        p.addCurve(to: CGPoint(x: 0.99 * w, y: 0.54 * h),
                   control1: CGPoint(x: 0.40 * w, y: 0.94 * h),
                   control2: CGPoint(x: 0.76 * w, y: 0.76 * h))
        p.closeSubpath()
        return p
    }
}

struct TopFin: View {
    let colors: [Color]
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 2, y: 40))
            p.addCurve(to: CGPoint(x: 26, y: 3),
                       control1: CGPoint(x: 8, y: 26), control2: CGPoint(x: 12, y: 6))
            p.addCurve(to: CGPoint(x: 52, y: 39),
                       control1: CGPoint(x: 42, y: 8), control2: CGPoint(x: 50, y: 24))
            p.addCurve(to: CGPoint(x: 2, y: 40),
                       control1: CGPoint(x: 34, y: 32), control2: CGPoint(x: 18, y: 34))
            p.closeSubpath()
        }
        .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
        .overlay(
            Path { p in
                p.move(to: CGPoint(x: 12, y: 30))
                p.addQuadCurve(to: CGPoint(x: 26, y: 9), control: CGPoint(x: 20, y: 18))
                p.move(to: CGPoint(x: 30, y: 10))
                p.addQuadCurve(to: CGPoint(x: 42, y: 30), control: CGPoint(x: 38, y: 18))
            }
            .stroke(Color.white.opacity(0.28), lineWidth: 1.2)
        )
    }
}

struct PectoralFin: View {
    let colors: [Color]
    var body: some View {
        Ellipse()
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .overlay(Ellipse().stroke(Color.white.opacity(0.25), lineWidth: 1))
            .overlay(
                Path { p in
                    p.move(to: CGPoint(x: 8, y: 12))
                    p.addQuadCurve(to: CGPoint(x: 26, y: 9), control: CGPoint(x: 17, y: 5))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
    }
}

// MARK: - Face

private struct FishFace: View {
    @ObservedObject var state: PetState
    let t: Double

    private var persona: Persona { state.persona }

    private var blink: Bool {
        guard !state.snapshotMode, [.idle, .happy, .pouty, .speaking, .working].contains(state.mood) else { return false }
        let phase = t.truncatingRemainder(dividingBy: 4.3)
        return phase < 0.11 || (phase > 0.24 && phase < 0.33)
    }

    private var eyeStyle: EyeStyle {
        switch state.mood {
        case .happy: return .crescent
        case .sleepy: return .closed
        case .surprised: return .open(1.12)
        case .shy: return .open(0.55)
        case .thinking: return .open(0.95)
        case .listening: return .open(1.05)
        case .working: return .open(0.82)
        case .pouty: return .open(0.88)
        default:
            if blink { return .closed }
            return .open(1)
        }
    }

    private var look: CGSize {
        switch state.mood {
        case .thinking: return CGSize(width: 2.4, height: -2.2)
        case .shy: return CGSize(width: -2.6, height: 0.6)
        case .listening: return CGSize(width: 0.6, height: -0.8)
        case .sleepy: return .zero
        default:
            return CGSize(width: sin(t * 0.41) * 1.5, height: cos(t * 0.33) * 0.9)
        }
    }

    private var blushOpacity: Double {
        switch state.mood {
        case .shy: return 0.55
        case .happy: return 0.38
        case .pouty: return 0.34
        case .listening: return 0.28
        case .sleepy: return 0.12
        default: return 0.22
        }
    }

    var body: some View {
        ZStack {
            // 腮红
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [persona.accentColor.opacity(blushOpacity), persona.accentColor.opacity(0)],
                        center: .center, startRadius: 1, endRadius: 9
                    )
                )
                .frame(width: 20, height: 11)
                .position(x: 78, y: 68)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [persona.accentColor.opacity(blushOpacity), persona.accentColor.opacity(0)],
                        center: .center, startRadius: 1, endRadius: 8
                    )
                )
                .frame(width: 17, height: 10)
                .position(x: 124, y: 65)

            // 眼睛
            EyeView(style: eyeStyle, look: look, mirrored: false)
                .frame(width: 27, height: 29)
                .position(x: 91, y: 45)
            EyeView(style: eyeStyle, look: look, mirrored: true)
                .frame(width: 25, height: 27)
                .position(x: 121, y: 42)

            // 眉毛（傲娇时才有）
            if state.mood == .pouty || state.mood == .working || state.mood == .surprised {
                Brow(mood: state.mood)
                    .stroke(Theme.deepInk.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 15, height: 5)
                    .rotationEffect(.degrees(state.mood == .surprised ? -4 : 16))
                    .position(x: 91, y: 26)
                Brow(mood: state.mood)
                    .stroke(Theme.deepInk.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 14, height: 5)
                    .rotationEffect(.degrees(state.mood == .surprised ? 4 : -16))
                    .position(x: 121, y: 23)
            }

            // 嘴
            Mouth(mood: state.mood, t: t)
                .position(x: 106, y: 71)

            // 小胡须
            Path { p in
                p.move(to: CGPoint(x: 124, y: 72))
                p.addQuadCurve(to: CGPoint(x: 134, y: 67), control: CGPoint(x: 130, y: 72))
                p.move(to: CGPoint(x: 124, y: 78))
                p.addQuadCurve(to: CGPoint(x: 133, y: 80), control: CGPoint(x: 129, y: 81))
            }
            .stroke(Theme.deepInk.opacity(0.35), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }
}

private enum EyeStyle: Equatable {
    case open(Double)
    case closed
    case crescent
}

private struct EyeView: View {
    let style: EyeStyle
    let look: CGSize
    let mirrored: Bool

    var body: some View {
        ZStack {
            switch style {
            case .crescent:
                Path { p in
                    p.move(to: CGPoint(x: 3, y: 17))
                    p.addQuadCurve(to: CGPoint(x: 24, y: 17), control: CGPoint(x: 13.5, y: 0))
                }
                .stroke(Theme.deepInk, style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
            case .closed:
                Path { p in
                    p.move(to: CGPoint(x: 3, y: 13))
                    p.addQuadCurve(to: CGPoint(x: 24, y: 13), control: CGPoint(x: 13.5, y: 24))
                }
                .stroke(Theme.deepInk, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            case .open(let amount):
                let h = max(6, 28 * amount)
                ZStack {
                    Ellipse()
                        .fill(
                            LinearGradient(colors: [Color(hex: "#5A372C"), Theme.deepInk],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    Ellipse()
                        .fill(Color.white.opacity(0.96))
                        .frame(width: 7.5, height: 7.5)
                        .offset(x: -4 + look.width * 0.4, y: -5 + look.height * 0.4)
                    Circle()
                        .fill(Color.white.opacity(0.65))
                        .frame(width: 3.2, height: 3.2)
                        .offset(x: 4 + look.width * 0.3, y: 5 + look.height * 0.3)
                    Ellipse()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
                .frame(width: 27, height: h)
                .clipShape(Ellipse())

            }
        }
    }
}

private struct Brow: Shape {
    let mood: Mood
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = mood == .surprised ? rect.height * 0.7 : rect.height * 0.4
        p.move(to: CGPoint(x: 1, y: y))
        p.addQuadCurve(to: CGPoint(x: rect.width - 1, y: y),
                       control: CGPoint(x: rect.width / 2, y: mood == .surprised ? y - 2 : y + 1))
        return p
    }
}

private struct Mouth: View {
    let mood: Mood
    let t: Double

    var body: some View {
        Group {
            switch mood {
            case .happy:
                Smile(width: 18, curve: 7)
                    .stroke(Theme.deepInk, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            case .sleepy:
                Ellipse().fill(Theme.deepInk.opacity(0.8)).frame(width: 5, height: 6)
            case .surprised:
                Ellipse().fill(Color(hex: "#7E3B3E")).frame(width: 8, height: 10)
                    .overlay(Ellipse().stroke(Theme.deepInk.opacity(0.5), lineWidth: 1))
            case .shy:
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 3))
                    p.addQuadCurve(to: CGPoint(x: 5, y: 5), control: CGPoint(x: 2.5, y: 0))
                    p.addQuadCurve(to: CGPoint(x: 11, y: 3), control: CGPoint(x: 8.5, y: 6))
                }
                .stroke(Theme.deepInk.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            case .speaking:
                let open = 0.5 + 0.5 * sin(t * 13)
                ZStack {
                    Ellipse()
                        .fill(Color(hex: "#7E3B3E"))
                        .frame(width: 12, height: 4 + 8 * open)
                    Ellipse()
                        .fill(Color(hex: "#FF8E9E"))
                        .frame(width: 7, height: 2.5 + 2 * open)
                        .offset(y: 2 + 2 * open)
                }
                .overlay(Ellipse().stroke(Theme.deepInk.opacity(0.45), lineWidth: 1))
            case .listening:
                Ellipse().fill(Color(hex: "#7E3B3E")).frame(width: 7, height: 6)
            case .thinking, .working:
                Smile(width: 10, curve: 1)
                    .stroke(Theme.deepInk.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            default:
                CatMouth()
                    .stroke(Theme.deepInk.opacity(0.9), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
        }
        .frame(width: 20, height: 16)
    }
}

private struct Smile: Shape {
    let width: CGFloat
    let curve: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY
        p.move(to: CGPoint(x: rect.midX - width / 2, y: y - curve * 0.3))
        p.addQuadCurve(to: CGPoint(x: rect.midX + width / 2, y: y - curve * 0.3),
                       control: CGPoint(x: rect.midX, y: y + curve))
        return p
    }
}

private struct CatMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        let y = rect.midY + 1
        p.move(to: CGPoint(x: cx - 6, y: y - 2))
        p.addQuadCurve(to: CGPoint(x: cx, y: y + 1), control: CGPoint(x: cx - 3, y: y + 4))
        p.addQuadCurve(to: CGPoint(x: cx + 6, y: y - 2), control: CGPoint(x: cx + 3, y: y + 4))
        return p
    }
}

// MARK: - Accessories

private struct Accessory: View {
    let kind: String
    let color: Color

    var body: some View {
        switch kind {
        case "flower":
            ZStack {
                ForEach(0..<5) { i in
                    Ellipse()
                        .fill(color.opacity(0.95))
                        .frame(width: 13, height: 9)
                        .offset(x: 8)
                        .rotationEffect(.degrees(Double(i) * 72))
                }
                Circle().fill(Color(hex: "#FFE08A")).frame(width: 7, height: 7)
            }
            .shadow(color: color.opacity(0.3), radius: 2, y: 1)
        case "none":
            EmptyView()
        default:
            Bow(color: color)
        }
    }
}

private struct Bow: View {
    let color: Color
    var body: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .frame(width: 19, height: 15)
                .rotationEffect(.degrees(-18))
                .offset(x: -10)
            Ellipse()
                .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .frame(width: 19, height: 15)
                .rotationEffect(.degrees(18))
                .offset(x: 10)
            Circle()
                .fill(Color(hex: "#FFF3E4"))
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(color.opacity(0.6), lineWidth: 1))
        }
        .shadow(color: color.opacity(0.35), radius: 3, y: 1)
    }
}

private struct Scarf: View {
    let color: Color
    var body: some View {
        ZStack {
            Capsule()
                .fill(color.opacity(0.92))
                .frame(width: 100, height: 20)
                .rotationEffect(.degrees(-5))
            Capsule()
                .fill(color.opacity(0.75))
                .frame(width: 16, height: 26)
                .rotationEffect(.degrees(18))
                .offset(x: 44, y: 14)
        }
    }
}

// MARK: - Decorations

private struct BubbleDeco: View {
    @ObservedObject var state: PetState
    let t: Double
    let color: Color

    var body: some View {
        ZStack {
            if !state.systemAsleep && state.mood != .sleepy {
                ForEach(0..<3) { i in
                    let phase = (t * 0.33 + Double(i) * 0.31).truncatingRemainder(dividingBy: 1)
                    let size = 4.0 + Double(i) * 2.2
                    Circle()
                        .stroke(color.opacity(0.4 * (1 - phase)), lineWidth: 1.1)
                        .frame(width: size, height: size)
                        .position(x: 207 + phase * 8, y: 128 - phase * 62)
                }
            }

            if state.mood == .sleepy || state.systemAsleep {
                ForEach(0..<3) { i in
                    let phase = (t * 0.18 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                    Text("z")
                        .font(.system(size: 10 + CGFloat(i) * 3, weight: .semibold, design: .rounded))
                        .foregroundColor(color.opacity(0.55 * (1 - phase)))
                        .position(x: 204 + phase * 10, y: 108 - phase * 34)
                }
            }

            if state.listening {
                Circle()
                    .stroke(color.opacity(0.45), lineWidth: 1.6)
                    .frame(width: 196, height: 196)
                    .scaleEffect(1 + CGFloat(sin(t * 3.4)) * 0.035)
                    .position(x: 132, y: 140)
            }

            if state.thinking {
                ForEach(0..<3) { i in
                    let pulse = (sin(t * 5 - Double(i) * 0.7) + 1) / 2
                    Circle()
                        .fill(Theme.deepInk.opacity(0.25 + pulse * 0.45))
                        .frame(width: 5, height: 5)
                        .position(x: 190 + Double(i) * 10, y: 86 - CGFloat(i) * 2)
                }
            }

            if state.mood == .working {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(color.opacity(0.8))
                    .rotationEffect(.degrees(t * 90))
                    .position(x: 206, y: 96)
            }

            if state.mood == .surprised {
                Text("!")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(color)
                    .position(x: 202, y: 92)
            }

            if state.speaking {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(color.opacity(0.5))
                        .frame(width: 2, height: 4 + CGFloat(abs(sin(t * 9 + Double(i)))) * 6)
                        .position(x: 214, y: 150 + Double(i) * 6)
                }
            }
        }
    }
}
