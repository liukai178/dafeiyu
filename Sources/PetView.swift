import SwiftUI
import AppKit

// MARK: - Root

struct PetView: View {
    @ObservedObject var state: PetState
    @State private var dragging = false

    private var interval: Double {
        if state.idle || state.mood == .sleepy { return 0.8 }
        if state.listening || state.speaking { return 0.12 }
        return 0.4
    }

    var body: some View {
        Group {
            if state.systemAsleep {
                PetCanvas(state: state, t: 0)
            } else {
                TimelineView(.periodic(from: .now, by: interval)) { context in
                    PetCanvas(state: state, t: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: 280, height: 320)
        .contentShape(Rectangle())
        .onHover { hovering in
            if state.hovered != hovering {
                state.hovered = hovering
                PetRuntime.shared.hover(hovering)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { _ in
                    if !dragging {
                        dragging = true
                        PetRuntime.shared.dragBegan()
                    }
                    PetRuntime.shared.dragChanged(.zero)
                }
                .onEnded { _ in
                    dragging = false
                    PetRuntime.shared.dragEnded()
                }
        )
        .onTapGesture(count: 2) { PetRuntime.shared.doubleTap() }
        .onTapGesture { tapPet() }
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

    private var p: Persona { state.persona }
    private var hair: Color { p.bodyColor }
    private var hairLight: Color { p.finColor }
    private var accent: Color { p.accentColor }
    private let skin = Color(hex: "#FFE9DC")
    private let skinShade = Color(hex: "#F6C9B7")
    private let navy = Color(hex: "#27315F")
    private let navyLight = Color(hex: "#3A4B93")
    private let cream = Color(hex: "#FFFDF8")
    private let apron = Color(hex: "#FFF9F2")
    private let mouthColor = Color(hex: "#8E3F49")

    private var asleep: Bool { state.systemAsleep }
    private var sleepy: Bool { state.mood == .sleepy || asleep }

    private var bob: CGFloat {
        if asleep { return 0 }
        if sleepy { return CGFloat(sin(t * 2 * .pi / 4.2)) * 1.2 }
        return CGFloat(sin(t * 2 * .pi / 3.8)) * 1.8
    }

    private var headTilt: Double {
        if sleepy { return 5 + sin(t * 0.7) * 1.2 }
        var tilt = sin(t * 2 * .pi / 5.1) * 1.4
        if state.hovered { tilt -= 3.2 }
        if state.mood == .shy { tilt += 3 }
        if state.speaking { tilt += sin(t * 8) * 1.2 }
        return tilt
    }

    private var tailAngle: Double {
        if sleepy { return sin(t * 0.7) * 3 }
        let amp = state.mood == .happy ? 13.0 : 8.0
        return sin(t * 2 * .pi * 0.55) * amp
    }

    private var hairSway: Double {
        if asleep { return 0 }
        return sin(t * 2 * .pi / 4.6) * 2.2
    }

    var body: some View {
        ZStack {
            groundShadow

            if state.listening || state.thinking {
                Circle()
                    .fill(RadialGradient(
                        colors: [accent.opacity(0.20), accent.opacity(0)],
                        center: .center, startRadius: 40, endRadius: 140))
                    .frame(width: 300, height: 300)
                    .position(x: 140, y: 180)
                    .scaleEffect(state.listening ? 1 + CGFloat(sin(t * 3.4)) * 0.02 : 1)
            }

            tailView

            backHair

            bodyGroup

            headGroup

            propsGroup

            decoGroup
        }
        .frame(width: 280, height: 320)
        .scaleEffect(x: state.pressed ? 1.045 : (state.hovered ? 1.015 : 1),
                     y: state.pressed ? 0.955 : (state.hovered ? 0.995 : 1),
                     anchor: .bottom)
        .offset(y: bob)
        .opacity(asleep ? 0.86 : 1)
        .animation(.easeOut(duration: 0.18), value: state.pressed)
        .animation(.easeOut(duration: 0.2), value: state.hovered)
    }

    // MARK: Shadow

    private var groundShadow: some View {
        Ellipse()
            .fill(RadialGradient(
                colors: [Color.black.opacity(asleep ? 0.05 : 0.12), Color.black.opacity(0)],
                center: .center, startRadius: 2, endRadius: 72))
            .frame(width: 158, height: 20)
            .position(x: 140, y: 308)
    }

    // MARK: Tail

    private var tailView: some View {
        TailShape()
            .fill(LinearGradient(colors: [navy.opacity(0.95), hair, hairLight],
                                 startPoint: .leading, endPoint: .trailing))
            .overlay(TailShape().stroke(Color.white.opacity(0.18), lineWidth: 1.2))
            .frame(width: 104, height: 84)
            .rotationEffect(.degrees(tailAngle), anchor: .leading)
            .position(x: 226, y: 274)
    }

    // MARK: Hair back

    private var backHair: some View {
        ZStack {
            PathShape(path: backHairPath)
                .fill(LinearGradient(colors: [hair.opacity(0.92), hair, hairLight.opacity(0.95)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(PathShape(path: backHairPath).stroke(Color.black.opacity(0.06), lineWidth: 1))
            PathShape(path: backHairStrand1).stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            PathShape(path: backHairStrand2).stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        .frame(width: 280, height: 320)
    }

    // MARK: Body

    private var bodyGroup: some View {
        ZStack {
            // neck
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(skinShade)
                .frame(width: 26, height: 30)
                .position(x: 140, y: 202)

            // skirt
            PathShape(path: skirtPath)
                .fill(LinearGradient(colors: [navyLight, navy], startPoint: .top, endPoint: .bottom))

            // skirt trim
            PathShape(path: skirtTrimPath).fill(cream)
            ForEach(0..<9) { i in
                Circle().fill(cream)
                    .frame(width: 10, height: 10)
                    .position(x: 84 + CGFloat(i) * 14, y: 300)
            }

            // apron
            PathShape(path: apronPath)
                .fill(LinearGradient(colors: [apron, cream.opacity(0.96)], startPoint: .top, endPoint: .bottom))
                .overlay(PathShape(path: apronPath).stroke(Color(hex: "#E8D9CB").opacity(0.55), lineWidth: 1))
            ForEach(0..<5) { i in
                Circle().fill(apron)
                    .frame(width: 15, height: 15)
                    .position(x: 108 + CGFloat(i) * 16, y: 296)
            }

            // apron straps
            Path { path in
                path.move(to: CGPoint(x: 120, y: 232)); path.addLine(to: CGPoint(x: 110, y: 208))
                path.move(to: CGPoint(x: 160, y: 232)); path.addLine(to: CGPoint(x: 170, y: 208))
            }
            .stroke(cream, style: StrokeStyle(lineWidth: 4, lineCap: .round))

            // bodice
            PathShape(path: bodicePath)
                .fill(LinearGradient(colors: [navyLight, navy], startPoint: .top, endPoint: .bottom))

            // collar
            PathShape(path: collarPath).fill(cream)
            PathShape(path: collarInnerPath).stroke(navy, lineWidth: 2)

            // chest bow
            chestBow

            // sleeves
            Circle().fill(LinearGradient(colors: [navyLight, navy], startPoint: .top, endPoint: .bottom))
                .frame(width: 40, height: 40)
                .position(x: 100, y: 222)
            Circle().fill(LinearGradient(colors: [navyLight, navy], startPoint: .top, endPoint: .bottom))
                .frame(width: 40, height: 40)
                .position(x: 180, y: 222)

            // shoes
            Ellipse().fill(navy).frame(width: 28, height: 12).position(x: 120, y: 303)
            Ellipse().fill(navy).frame(width: 28, height: 12).position(x: 160, y: 303)
            Ellipse().fill(cream.opacity(0.9)).frame(width: 22, height: 4).position(x: 120, y: 297)
            Ellipse().fill(cream.opacity(0.9)).frame(width: 22, height: 4).position(x: 160, y: 297)

            // apron whale
            PathShape(path: miniWhalePath)
                .fill(Color(hex: "#4D6BFF").opacity(0.65))
        }
        .frame(width: 280, height: 320)
    }

    private var chestBow: some View {
        ZStack {
            Ellipse().fill(accent).frame(width: 22, height: 15).rotationEffect(.degrees(-20)).offset(x: -11, y: 0)
            Ellipse().fill(accent.opacity(0.92)).frame(width: 22, height: 15).rotationEffect(.degrees(20)).offset(x: 11, y: 0)
            Circle().fill(cream).frame(width: 8, height: 8)
        }
        .position(x: 140, y: 231)
    }

    // MARK: Props

    private var propsGroup: some View {
        ZStack {
            // rice bowl
            PathShape(path: bowlPath)
                .fill(LinearGradient(colors: [cream, Color(hex: "#EDE3D8")], startPoint: .top, endPoint: .bottom))
                .overlay(PathShape(path: bowlPath).stroke(Color(hex: "#4D6BFF").opacity(0.45), lineWidth: 1.4))
            Ellipse().fill(Color(hex: "#4D6BFF").opacity(0.22)).frame(width: 60, height: 10).position(x: 44, y: 194)
            Ellipse().stroke(Color(hex: "#4D6BFF").opacity(0.55), lineWidth: 2).frame(width: 62, height: 10).position(x: 44, y: 194)

            // rice
            ForEach(0..<7) { i in
                let a = Double(i) * 0.9
                Circle().fill(cream)
                    .frame(width: 18, height: 18)
                    .position(x: 30 + CGFloat(i % 3) * 14, y: 188 - CGFloat(sin(a)) * 3)
            }
            Circle().fill(cream).frame(width: 24, height: 16).position(x: 44, y: 184)
            Circle().fill(cream.opacity(0.9)).frame(width: 30, height: 11).position(x: 44, y: 179)

            // whale on bowl
            PathShape(path: bowlWhalePath).fill(Color(hex: "#4D6BFF").opacity(0.55))

            // steam
            SteamView(t: t, color: cream)
                .opacity(sleepy ? 0.25 : 0.7)

            // left forearm + hand (over hair and bowl rim)
            Path { path in
                path.move(to: CGPoint(x: 92, y: 226))
                path.addQuadCurve(to: CGPoint(x: 76, y: 216), control: CGPoint(x: 84, y: 224))
            }
            .stroke(skin, style: StrokeStyle(lineWidth: 13, lineCap: .round))
            Circle().fill(skin).frame(width: 16, height: 16).position(x: 74, y: 214)
            Path { path in
                path.move(to: CGPoint(x: 70, y: 209)); path.addQuadCurve(to: CGPoint(x: 79, y: 207), control: CGPoint(x: 75, y: 204))
            }.stroke(skinShade.opacity(0.5), lineWidth: 1)

            // chopsticks
            Path { path in
                path.move(to: CGPoint(x: 222, y: 203)); path.addLine(to: CGPoint(x: 250, y: 160))
                path.move(to: CGPoint(x: 226, y: 207)); path.addLine(to: CGPoint(x: 254, y: 165))
            }
            .stroke(Color(hex: "#8B5A3C"), style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // right forearm + hand
            Path { path in
                path.move(to: CGPoint(x: 186, y: 226))
                path.addQuadCurve(to: CGPoint(x: 214, y: 207), control: CGPoint(x: 202, y: 219))
            }
            .stroke(skin, style: StrokeStyle(lineWidth: 13, lineCap: .round))
            Circle().fill(skin).frame(width: 17, height: 17).position(x: 217, y: 205)
            Path { path in
                path.move(to: CGPoint(x: 211, y: 200)); path.addQuadCurve(to: CGPoint(x: 220, y: 197), control: CGPoint(x: 215, y: 195))
            }.stroke(skinShade.opacity(0.5), lineWidth: 1)
        }
        .frame(width: 280, height: 320)
    }

    // MARK: Head

    private var headGroup: some View {
        ZStack {
            // ears
            Ellipse().fill(skin).frame(width: 16, height: 26).position(x: 66, y: 138)
            Ellipse().fill(skin).frame(width: 16, height: 26).position(x: 214, y: 138)

            PathShape(path: facePath)
                .fill(LinearGradient(colors: [skin, Color(hex: "#FFDFD0")], startPoint: .top, endPoint: .bottom))
                .overlay(PathShape(path: facePath).stroke(skinShade.opacity(0.35), lineWidth: 1))

            face

            bangs

            sideLocks

            headband
        }
        .frame(width: 280, height: 320)
        .rotationEffect(.degrees(headTilt), anchor: UnitPoint(x: 0.5, y: 0.65))
    }

    private var face: some View {
        ZStack {
            // blush
            Ellipse()
                .fill(RadialGradient(colors: [Color(hex: "#FF9FB0").opacity(blushOpacity), Color(hex: "#FF9FB0").opacity(0)],
                                     center: .center, startRadius: 1, endRadius: 14))
                .frame(width: 30, height: 16)
                .position(x: 90, y: 168)
            Ellipse()
                .fill(RadialGradient(colors: [Color(hex: "#FF9FB0").opacity(blushOpacity), Color(hex: "#FF9FB0").opacity(0)],
                                     center: .center, startRadius: 1, endRadius: 13))
                .frame(width: 27, height: 15)
                .position(x: 190, y: 168)

            // eyes
            GirlEye(style: eyeStyle, look: eyeLook, mirrored: false, irisLight: Color(hex: "#8FE3FF"), irisDark: Color(hex: "#2747CC"), skin: skin)
                .frame(width: 40, height: 48)
                .position(x: 110, y: 140)
            GirlEye(style: eyeStyle, look: eyeLook, mirrored: true, irisLight: Color(hex: "#8FE3FF"), irisDark: Color(hex: "#2747CC"), skin: skin)
                .frame(width: 40, height: 48)
                .position(x: 170, y: 140)

            brows

            // nose
            Path { path in
                path.move(to: CGPoint(x: 138, y: 158))
                path.addQuadCurve(to: CGPoint(x: 143, y: 160), control: CGPoint(x: 141, y: 162))
            }
            .stroke(skinShade.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

            mouth
        }
        .frame(width: 280, height: 320)
    }

    private var brows: some View {
        ZStack {
            Capsule()
                .fill(hair.opacity(0.75))
                .frame(width: 22, height: 2.6)
                .rotationEffect(.degrees(browAngleLeft))
                .position(x: 110, y: 112)
            Capsule()
                .fill(hair.opacity(0.75))
                .frame(width: 20, height: 2.4)
                .rotationEffect(.degrees(browAngleRight))
                .position(x: 170, y: 112)
        }
    }

    private var browAngleLeft: Double {
        switch state.mood {
        case .pouty, .working: return 14
        case .surprised: return -8
        case .shy: return -10
        default: return -4
        }
    }

    private var browAngleRight: Double {
        switch state.mood {
        case .pouty, .working: return -14
        case .surprised: return 8
        case .shy: return 10
        default: return 4
        }
    }

    private var mouth: some View {
        Group {
            switch state.mood {
            case .happy:
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 128, y: 174))
                        path.addQuadCurve(to: CGPoint(x: 152, y: 174), control: CGPoint(x: 140, y: 194))
                        path.closeSubpath()
                    }
                    .fill(mouthColor)
                    Ellipse().fill(Color(hex: "#FF9AA9")).frame(width: 12, height: 5).position(x: 140, y: 187)
                }
            case .speaking:
                let open = 0.45 + 0.55 * abs(sin(t * 13))
                ZStack {
                    Ellipse().fill(mouthColor).frame(width: 18, height: 5 + 13 * open)
                    Ellipse().fill(Color(hex: "#FF9AA9")).frame(width: 10, height: 3 + 4 * open)
                        .offset(y: 3 + 3 * open)
                }
                .position(x: 140, y: 180)
            case .surprised:
                Ellipse().fill(mouthColor).frame(width: 14, height: 17).position(x: 140, y: 180)
            case .sleepy:
                Ellipse().fill(mouthColor.opacity(0.85)).frame(width: 9, height: 10).position(x: 140, y: 181)
            case .shy:
                Path { path in
                    path.move(to: CGPoint(x: 130, y: 181))
                    path.addQuadCurve(to: CGPoint(x: 137, y: 183), control: CGPoint(x: 133.5, y: 178))
                    path.addQuadCurve(to: CGPoint(x: 144, y: 181), control: CGPoint(x: 140.5, y: 185))
                    path.addQuadCurve(to: CGPoint(x: 151, y: 183), control: CGPoint(x: 147.5, y: 178))
                }
                .stroke(mouthColor, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            case .pouty:
                ZStack {
                    Ellipse().fill(accent.opacity(0.18)).frame(width: 18, height: 9).position(x: 140, y: 184)
                    Path { path in
                        path.move(to: CGPoint(x: 132, y: 182))
                        path.addQuadCurve(to: CGPoint(x: 148, y: 182), control: CGPoint(x: 140, y: 175))
                    }.stroke(mouthColor, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
            case .listening:
                Ellipse().fill(mouthColor.opacity(0.9)).frame(width: 9, height: 8).position(x: 140, y: 181)
            case .thinking, .working:
                Capsule().fill(mouthColor.opacity(0.8)).frame(width: 13, height: 2.4).position(x: 140, y: 181)
            default:
                Path { path in
                    path.move(to: CGPoint(x: 132, y: 179))
                    path.addQuadCurve(to: CGPoint(x: 140, y: 182), control: CGPoint(x: 136, y: 186))
                    path.addQuadCurve(to: CGPoint(x: 148, y: 179), control: CGPoint(x: 144, y: 186))
                }
                .stroke(mouthColor, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }
        }
        .frame(width: 280, height: 320)
    }

    // MARK: Hair front

    private var bangs: some View {
        ZStack {
            PathShape(path: bangsPath)
                .fill(LinearGradient(colors: [hair.opacity(0.9), hair, hairLight],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(PathShape(path: bangsPath).stroke(Color.black.opacity(0.05), lineWidth: 1))
            PathShape(path: bangsHighlight)
                .stroke(Color.white.opacity(0.13), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            PathShape(path: bangsStrand)
                .stroke(hair.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 280, height: 320)
    }

    private var sideLocks: some View {
        ZStack {
            SideLockShape()
                .fill(LinearGradient(colors: [hair, hairLight], startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 172)
                .rotationEffect(.degrees(hairSway), anchor: UnitPoint(x: 0.75, y: 0.05))
                .position(x: 66, y: 156)
            SideLockShape()
                .fill(LinearGradient(colors: [hair, hairLight], startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 172)
                .scaleEffect(x: -1, y: 1)
                .rotationEffect(.degrees(-hairSway), anchor: UnitPoint(x: 0.75, y: 0.05))
                .position(x: 214, y: 156)
        }
        .frame(width: 280, height: 320)
    }

    private var headband: some View {
        ZStack {
            Path { path in
                path.addArc(center: CGPoint(x: 140, y: 126), radius: 78,
                            startAngle: .degrees(218), endAngle: .degrees(322), clockwise: false)
            }
            .stroke(cream, style: StrokeStyle(lineWidth: 12, lineCap: .round))
            .shadow(color: Color.black.opacity(0.05), radius: 1, y: 1)

            ForEach(0..<9) { i in
                let angle = Double(216 + i * 13) * .pi / 180
                Circle().fill(cream)
                    .frame(width: 8, height: 8)
                    .position(x: 140 + cos(angle) * 74, y: 126 + sin(angle) * 74)
            }

            if p.accessory == "flower" {
                Flower(color: accent)
                    .frame(width: 30, height: 30)
                    .position(x: 198, y: 74)
            } else if p.accessory != "none" {
                BowAccessory(color: accent)
                    .frame(width: 38, height: 26)
                    .rotationEffect(.degrees(-12))
                    .position(x: 198, y: 74)
            }
        }
        .frame(width: 280, height: 320)
    }

    private var ahoge: some View {
        Path { path in
            path.move(to: CGPoint(x: 140, y: 48))
            path.addCurve(to: CGPoint(x: 137, y: 26),
                          control1: CGPoint(x: 136, y: 36), control2: CGPoint(x: 131, y: 30))
            path.addCurve(to: CGPoint(x: 150, y: 30),
                          control1: CGPoint(x: 146, y: 20), control2: CGPoint(x: 154, y: 24))
        }
        .stroke(hair, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        .frame(width: 280, height: 320)
    }

    // MARK: Deco

    private var decoGroup: some View {
        ZStack {
            if state.mood == .happy {
                ForEach(0..<4) { i in
                    Sparkle()
                        .fill(accent.opacity(0.75))
                        .frame(width: 9, height: 9)
                        .position(x: 48 + CGFloat(i % 2) * 190, y: 70 + CGFloat(i / 2) * 190)
                        .opacity(0.4 + 0.6 * abs(sin(t * 2 + Double(i))))
                }
            }

            if state.mood == .shy {
                ForEach(0..<2) { i in
                    HeartShape()
                        .fill(accent.opacity(0.6))
                        .frame(width: 12, height: 11)
                        .position(x: 214 + CGFloat(i) * 14, y: 100 - CGFloat(sin(t * 2 + Double(i))) * 8)
                }
            }

            if sleepy {
                ForEach(0..<3) { i in
                    let phase = (t * 0.16 + Double(i) * 0.32).truncatingRemainder(dividingBy: 1)
                    Text("z")
                        .font(.system(size: 11 + CGFloat(i) * 3, weight: .semibold, design: .rounded))
                        .foregroundColor(accent.opacity(0.55 * (1 - phase)))
                        .position(x: 214 + phase * 8, y: 92 - phase * 34)
                }
            }

            if state.listening {
                Ellipse()
                    .stroke(accent.opacity(0.4), lineWidth: 1.8)
                    .frame(width: 210, height: 286)
                    .scaleEffect(1 + CGFloat(sin(t * 3.4)) * 0.03)
                    .position(x: 140, y: 178)
            }

            if state.thinking {
                ForEach(0..<3) { i in
                    let pulse = (sin(t * 5 - Double(i) * 0.7) + 1) / 2
                    Circle().fill(navy.opacity(0.2 + pulse * 0.4))
                        .frame(width: 5, height: 5)
                        .position(x: 200 + Double(i) * 10, y: 88)
                }
            }

            if state.mood == .working {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(accent.opacity(0.8))
                    .rotationEffect(.degrees(t * 90))
                    .position(x: 220, y: 92)
            }

            if state.mood == .surprised {
                Text("!")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(accent)
                    .position(x: 216, y: 92)
            }

            if state.speaking {
                ForEach(0..<3) { i in
                    Capsule().fill(accent.opacity(0.55))
                        .frame(width: 2.4, height: 5 + CGFloat(abs(sin(t * 9 + Double(i)))) * 7)
                        .position(x: 196, y: 178 + Double(i) * 7)
                }
            }
        }
        .frame(width: 280, height: 320)
    }

    // MARK: Mood derived

    private var blushOpacity: Double {
        switch state.mood {
        case .shy: return 0.52
        case .happy: return 0.36
        case .pouty: return 0.3
        case .listening: return 0.26
        case .sleepy: return 0.12
        default: return 0.2
        }
    }

    private var eyeStyle: EyeStyle {
        switch state.mood {
        case .happy: return .happy
        case .sleepy: return .closed
        case .surprised: return .open(1.14)
        case .shy: return .open(0.58)
        case .thinking: return .open(0.98)
        case .listening: return .open(1.05)
        case .working: return .open(0.88)
        case .pouty: return .open(0.92)
        default:
            if blink && !state.snapshotMode { return .closed }
            return .open(1)
        }
    }

    private var blink: Bool {
        guard [.idle, .pouty, .speaking, .working].contains(state.mood) else { return false }
        let phase = t.truncatingRemainder(dividingBy: 4.3)
        return phase < 0.1 || (phase > 0.22 && phase < 0.3)
    }

    private var eyeLook: CGSize {
        if state.hovered { return CGSize(width: -2.6, height: 0.8) }
        switch state.mood {
        case .thinking: return CGSize(width: 2.8, height: -2.4)
        case .shy: return CGSize(width: -3, height: 0.6)
        case .listening: return CGSize(width: 0.5, height: -1)
        case .sleepy: return .zero
        default:
            return CGSize(width: sin(t * 0.37) * 1.6, height: cos(t * 0.29) * 1.0)
        }
    }
}

// MARK: - Paths

private struct PathShape: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path { path }
}

private struct FacePathShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 140, y: 48))
        p.addCurve(to: CGPoint(x: 216, y: 128), control1: CGPoint(x: 188, y: 48), control2: CGPoint(x: 216, y: 82))
        p.addCurve(to: CGPoint(x: 140, y: 208), control1: CGPoint(x: 216, y: 172), control2: CGPoint(x: 188, y: 204))
        p.addCurve(to: CGPoint(x: 64, y: 128), control1: CGPoint(x: 92, y: 204), control2: CGPoint(x: 64, y: 172))
        p.addCurve(to: CGPoint(x: 140, y: 48), control1: CGPoint(x: 64, y: 82), control2: CGPoint(x: 92, y: 48))
        return p
    }
}

private struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 44))
        p.addCurve(to: CGPoint(x: 72, y: 6), control1: CGPoint(x: 18, y: 42), control2: CGPoint(x: 50, y: 18))
        p.addCurve(to: CGPoint(x: 56, y: 46), control1: CGPoint(x: 66, y: 22), control2: CGPoint(x: 60, y: 36))
        p.addCurve(to: CGPoint(x: 98, y: 56), control1: CGPoint(x: 74, y: 42), control2: CGPoint(x: 90, y: 48))
        p.addCurve(to: CGPoint(x: 56, y: 58), control1: CGPoint(x: 82, y: 62), control2: CGPoint(x: 66, y: 60))
        p.addCurve(to: CGPoint(x: 56, y: 86), control1: CGPoint(x: 58, y: 66), control2: CGPoint(x: 58, y: 76))
        p.addCurve(to: CGPoint(x: 4, y: 52), control1: CGPoint(x: 36, y: 76), control2: CGPoint(x: 18, y: 62))
        p.closeSubpath()
        return p
    }
}

private struct SideLockShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 36, y: 4))
        p.addCurve(to: CGPoint(x: 38, y: 96), control1: CGPoint(x: 22, y: 34), control2: CGPoint(x: 30, y: 66))
        p.addCurve(to: CGPoint(x: 28, y: 160), control1: CGPoint(x: 44, y: 122), control2: CGPoint(x: 36, y: 144))
        p.addCurve(to: CGPoint(x: 12, y: 112), control1: CGPoint(x: 18, y: 146), control2: CGPoint(x: 12, y: 130))
        p.addCurve(to: CGPoint(x: 6, y: 34), control1: CGPoint(x: 10, y: 86), control2: CGPoint(x: 4, y: 58))
        p.addCurve(to: CGPoint(x: 36, y: 4), control1: CGPoint(x: 10, y: 14), control2: CGPoint(x: 22, y: 4))
        p.closeSubpath()
        return p
    }
}

// MARK: - Computed paths

private extension PetCanvas {
    var backHairPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 140, y: 26))
        p.addCurve(to: CGPoint(x: 234, y: 130), control1: CGPoint(x: 198, y: 26), control2: CGPoint(x: 234, y: 70))
        p.addCurve(to: CGPoint(x: 208, y: 272), control1: CGPoint(x: 234, y: 190), control2: CGPoint(x: 226, y: 238))
        p.addCurve(to: CGPoint(x: 186, y: 264), control1: CGPoint(x: 202, y: 286), control2: CGPoint(x: 190, y: 282))
        p.addCurve(to: CGPoint(x: 164, y: 270), control1: CGPoint(x: 182, y: 284), control2: CGPoint(x: 170, y: 288))
        p.addCurve(to: CGPoint(x: 140, y: 268), control1: CGPoint(x: 156, y: 288), control2: CGPoint(x: 146, y: 288))
        p.addCurve(to: CGPoint(x: 116, y: 270), control1: CGPoint(x: 134, y: 288), control2: CGPoint(x: 124, y: 288))
        p.addCurve(to: CGPoint(x: 94, y: 264), control1: CGPoint(x: 110, y: 288), control2: CGPoint(x: 98, y: 284))
        p.addCurve(to: CGPoint(x: 72, y: 272), control1: CGPoint(x: 90, y: 282), control2: CGPoint(x: 78, y: 286))
        p.addCurve(to: CGPoint(x: 46, y: 130), control1: CGPoint(x: 54, y: 238), control2: CGPoint(x: 46, y: 190))
        p.addCurve(to: CGPoint(x: 140, y: 26), control1: CGPoint(x: 46, y: 70), control2: CGPoint(x: 82, y: 26))
        p.closeSubpath()
        return p
    }

    var backHairStrand1: Path {
        var p = Path()
        p.move(to: CGPoint(x: 78, y: 96))
        p.addCurve(to: CGPoint(x: 72, y: 226), control1: CGPoint(x: 58, y: 140), control2: CGPoint(x: 66, y: 190))
        return p
    }

    var backHairStrand2: Path {
        var p = Path()
        p.move(to: CGPoint(x: 204, y: 92))
        p.addCurve(to: CGPoint(x: 210, y: 220), control1: CGPoint(x: 222, y: 136), control2: CGPoint(x: 216, y: 186))
        return p
    }

    var facePath: Path { FacePathShape().path(in: CGRect(x: 0, y: 0, width: 280, height: 320)) }

    var bangsPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 60, y: 110))
        p.addCurve(to: CGPoint(x: 140, y: 40), control1: CGPoint(x: 58, y: 66), control2: CGPoint(x: 92, y: 40))
        p.addCurve(to: CGPoint(x: 220, y: 110), control1: CGPoint(x: 188, y: 40), control2: CGPoint(x: 222, y: 66))
        p.addCurve(to: CGPoint(x: 196, y: 110), control1: CGPoint(x: 210, y: 96), control2: CGPoint(x: 202, y: 90))
        p.addCurve(to: CGPoint(x: 176, y: 108), control1: CGPoint(x: 190, y: 90), control2: CGPoint(x: 182, y: 84))
        p.addCurve(to: CGPoint(x: 156, y: 108), control1: CGPoint(x: 170, y: 88), control2: CGPoint(x: 162, y: 84))
        p.addCurve(to: CGPoint(x: 138, y: 106), control1: CGPoint(x: 150, y: 86), control2: CGPoint(x: 144, y: 84))
        p.addCurve(to: CGPoint(x: 118, y: 108), control1: CGPoint(x: 132, y: 84), control2: CGPoint(x: 124, y: 88))
        p.addCurve(to: CGPoint(x: 98, y: 110), control1: CGPoint(x: 112, y: 86), control2: CGPoint(x: 104, y: 90))
        p.addCurve(to: CGPoint(x: 78, y: 110), control1: CGPoint(x: 92, y: 92), control2: CGPoint(x: 84, y: 96))
        p.addCurve(to: CGPoint(x: 60, y: 110), control1: CGPoint(x: 74, y: 98), control2: CGPoint(x: 66, y: 102))
        p.closeSubpath()
        return p
    }

    var bangsHighlight: Path {
        var p = Path()
        p.move(to: CGPoint(x: 92, y: 80))
        p.addCurve(to: CGPoint(x: 150, y: 56), control1: CGPoint(x: 110, y: 64), control2: CGPoint(x: 130, y: 58))
        return p
    }

    var bangsStrand: Path {
        var p = Path()
        p.move(to: CGPoint(x: 154, y: 56))
        p.addCurve(to: CGPoint(x: 160, y: 100), control1: CGPoint(x: 156, y: 72), control2: CGPoint(x: 158, y: 88))
        return p
    }

    var skirtPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 114, y: 250))
        p.addCurve(to: CGPoint(x: 78, y: 302), control1: CGPoint(x: 100, y: 262), control2: CGPoint(x: 84, y: 286))
        p.addLine(to: CGPoint(x: 202, y: 302))
        p.addCurve(to: CGPoint(x: 166, y: 250), control1: CGPoint(x: 196, y: 286), control2: CGPoint(x: 180, y: 262))
        p.closeSubpath()
        return p
    }

    var skirtTrimPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 79, y: 298))
        p.addCurve(to: CGPoint(x: 201, y: 298), control1: CGPoint(x: 110, y: 306), control2: CGPoint(x: 170, y: 306))
        p.addLine(to: CGPoint(x: 202, y: 302))
        p.addLine(to: CGPoint(x: 78, y: 302))
        p.closeSubpath()
        return p
    }

    var apronPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 118, y: 236))
        p.addLine(to: CGPoint(x: 162, y: 236))
        p.addCurve(to: CGPoint(x: 176, y: 294), control1: CGPoint(x: 168, y: 258), control2: CGPoint(x: 174, y: 280))
        p.addCurve(to: CGPoint(x: 140, y: 300), control1: CGPoint(x: 166, y: 298), control2: CGPoint(x: 152, y: 300))
        p.addCurve(to: CGPoint(x: 104, y: 294), control1: CGPoint(x: 128, y: 300), control2: CGPoint(x: 114, y: 298))
        p.addCurve(to: CGPoint(x: 118, y: 236), control1: CGPoint(x: 106, y: 280), control2: CGPoint(x: 112, y: 258))
        p.closeSubpath()
        return p
    }

    var bodicePath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 108, y: 210))
        p.addCurve(to: CGPoint(x: 132, y: 203), control1: CGPoint(x: 116, y: 205), control2: CGPoint(x: 124, y: 203))
        p.addLine(to: CGPoint(x: 148, y: 203))
        p.addCurve(to: CGPoint(x: 172, y: 210), control1: CGPoint(x: 156, y: 203), control2: CGPoint(x: 164, y: 205))
        p.addLine(to: CGPoint(x: 166, y: 256))
        p.addLine(to: CGPoint(x: 114, y: 256))
        p.closeSubpath()
        return p
    }

    var collarPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 124, y: 204))
        p.addLine(to: CGPoint(x: 140, y: 228))
        p.addLine(to: CGPoint(x: 156, y: 204))
        p.addLine(to: CGPoint(x: 164, y: 208))
        p.addLine(to: CGPoint(x: 140, y: 240))
        p.addLine(to: CGPoint(x: 116, y: 208))
        p.closeSubpath()
        return p
    }

    var collarInnerPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 126, y: 206))
        p.addLine(to: CGPoint(x: 140, y: 232))
        p.addLine(to: CGPoint(x: 154, y: 206))
        return p
    }

    var bowlPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 12, y: 192))
        p.addCurve(to: CGPoint(x: 44, y: 226), control1: CGPoint(x: 12, y: 216), control2: CGPoint(x: 26, y: 226))
        p.addCurve(to: CGPoint(x: 76, y: 192), control1: CGPoint(x: 62, y: 226), control2: CGPoint(x: 76, y: 216))
        p.closeSubpath()
        return p
    }

    var bowlWhalePath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 30, y: 206))
        p.addQuadCurve(to: CGPoint(x: 46, y: 205), control: CGPoint(x: 38, y: 200))
        p.addQuadCurve(to: CGPoint(x: 60, y: 208), control: CGPoint(x: 52, y: 212))
        p.addLine(to: CGPoint(x: 56, y: 199))
        p.addQuadCurve(to: CGPoint(x: 52, y: 203), control: CGPoint(x: 55, y: 196))
        p.addQuadCurve(to: CGPoint(x: 48, y: 210), control: CGPoint(x: 52, y: 209))
        p.addQuadCurve(to: CGPoint(x: 32, y: 210), control: CGPoint(x: 40, y: 213))
        p.closeSubpath()
        return p
    }

    var miniWhalePath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 126, y: 280))
        p.addQuadCurve(to: CGPoint(x: 142, y: 277), control: CGPoint(x: 134, y: 272))
        p.addQuadCurve(to: CGPoint(x: 156, y: 281), control: CGPoint(x: 150, y: 284))
        p.addLine(to: CGPoint(x: 151, y: 270))
        p.addQuadCurve(to: CGPoint(x: 146, y: 277), control: CGPoint(x: 150, y: 267))
        p.addQuadCurve(to: CGPoint(x: 140, y: 284), control: CGPoint(x: 146, y: 283))
        p.addQuadCurve(to: CGPoint(x: 126, y: 283), control: CGPoint(x: 132, y: 286))
        p.closeSubpath()
        return p
    }
}

// MARK: - Eye

private enum EyeStyle: Equatable {
    case open(Double)
    case closed
    case happy
}

private struct GirlEye: View {
    let style: EyeStyle
    let look: CGSize
    let mirrored: Bool
    let irisLight: Color
    let irisDark: Color
    let skin: Color

    var body: some View {
        ZStack {
            switch style {
            case .happy:
                LashArc()
                    .stroke(Color(hex: "#232A56"), style: StrokeStyle(lineWidth: 4.6, lineCap: .round))
                Path { p in
                    p.move(to: CGPoint(x: 3, y: 21))
                    p.addQuadCurve(to: CGPoint(x: 37, y: 21), control: CGPoint(x: 20, y: 5))
                }
                .stroke(Color(hex: "#232A56"), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
            case .closed:
                Path { p in
                    p.move(to: CGPoint(x: 4, y: 18))
                    p.addQuadCurve(to: CGPoint(x: 36, y: 18), control: CGPoint(x: 20, y: 28))
                }
                .stroke(Color(hex: "#232A56"), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            case .open(let amount):
                openEye(amount: amount)
            }
        }
        .frame(width: 40, height: 48)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
    }

    private func openEye(amount: Double) -> some View {
        ZStack {
            Ellipse()
                .fill(Color(hex: "#FFFDF8"))
                .frame(width: 38, height: 46)

            Ellipse()
                .fill(RadialGradient(colors: [irisLight, irisDark],
                                     center: UnitPoint(x: 0.42, y: 0.3),
                                     startRadius: 2, endRadius: 18))
                .frame(width: 29, height: 34)
                .offset(x: look.width * 0.6, y: look.height * 0.6)

            Ellipse()
                .fill(Color(hex: "#151C4A"))
                .frame(width: 12, height: 16)
                .offset(x: look.width * 0.7, y: look.height * 0.7)

            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 9, height: 9)
                .offset(x: -5 + look.width * 0.6, y: -7 + look.height * 0.6)
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 4, height: 4)
                .offset(x: 6 + look.width * 0.6, y: 8 + look.height * 0.6)
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 3, height: 3)
                .offset(x: 2 + look.width * 0.5, y: -2 + look.height * 0.5)

            // upper lash
            Path { p in
                p.move(to: CGPoint(x: 2, y: 18))
                p.addCurve(to: CGPoint(x: 38, y: 16), control1: CGPoint(x: 10, y: 2), control2: CGPoint(x: 30, y: 2))
            }
            .stroke(Color(hex: "#232A56"), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))

            // outer lash flick
            Path { p in
                p.move(to: CGPoint(x: 37, y: 15))
                p.addLine(to: CGPoint(x: 43, y: 8))
            }
            .stroke(Color(hex: "#232A56"), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

            // lower lid
            Path { p in
                p.move(to: CGPoint(x: 8, y: 40))
                p.addQuadCurve(to: CGPoint(x: 32, y: 40), control: CGPoint(x: 20, y: 45))
            }
            .stroke(Color(hex: "#6B4A57").opacity(0.35), lineWidth: 1.4)

            // eyelid for half-open
            if amount < 0.98 {
                Rectangle()
                    .fill(skin)
                    .frame(width: 40, height: 46 * (1 - amount))
                    .frame(maxHeight: .infinity, alignment: .top)
                Capsule()
                    .fill(Color(hex: "#232A56"))
                    .frame(width: 34, height: 2.6)
                    .offset(y: -23 + 23 * (1 - amount))
            }
        }
        .frame(width: 40, height: 48)
        .mask(Ellipse().frame(width: 40, height: 48))
        .overlay(
            Ellipse()
                .stroke(Color(hex: "#232A56").opacity(0.12), lineWidth: 1)
                .frame(width: 40, height: 48)
        )
    }
}

private struct LashArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: 27))
        p.addQuadCurve(to: CGPoint(x: 37, y: 27), control: CGPoint(x: 20, y: 13))
        return p
    }
}

// MARK: - Accessories

private struct BowAccessory: View {
    let color: Color
    var body: some View {
        ZStack {
            Ellipse().fill(color).frame(width: 17, height: 13).rotationEffect(.degrees(-22)).offset(x: -8)
            Ellipse().fill(color.opacity(0.9)).frame(width: 17, height: 13).rotationEffect(.degrees(22)).offset(x: 8)
            Circle().fill(Color(hex: "#FFFDF8")).frame(width: 6, height: 6)
            Sparkle().fill(Color.white.opacity(0.85)).frame(width: 5, height: 5).offset(x: 10, y: -7)
        }
        .shadow(color: color.opacity(0.25), radius: 2, y: 1)
    }
}

private struct Flower: View {
    let color: Color
    var body: some View {
        ZStack {
            ForEach(0..<5) { i in
                Ellipse().fill(color).frame(width: 12, height: 9)
                    .offset(x: 7)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(Color(hex: "#FFE08A")).frame(width: 6, height: 6)
        }
    }
}

private struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: CGPoint(x: c.x, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.width, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: rect.height), control: c)
        p.addQuadCurve(to: CGPoint(x: 0, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: 0), control: c)
        return p
    }
}

private struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w / 2, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.32),
                   control1: CGPoint(x: w * 0.15, y: h * 0.8),
                   control2: CGPoint(x: 0, y: h * 0.6))
        p.addCurve(to: CGPoint(x: w / 2, y: h * 0.22),
                   control1: CGPoint(x: 0, y: 0),
                   control2: CGPoint(x: w * 0.36, y: 0))
        p.addCurve(to: CGPoint(x: w, y: h * 0.32),
                   control1: CGPoint(x: w * 0.64, y: 0),
                   control2: CGPoint(x: w, y: 0))
        p.addCurve(to: CGPoint(x: w / 2, y: h),
                   control1: CGPoint(x: w, y: h * 0.6),
                   control2: CGPoint(x: w * 0.85, y: h * 0.8))
        p.closeSubpath()
        return p
    }
}

private struct SteamView: View {
    let t: Double
    let color: Color
    var body: some View {
        ZStack {
            ForEach(0..<2) { i in
                Path { p in
                    let x = 36 + Double(i) * 14
                    p.move(to: CGPoint(x: x, y: 172))
                    p.addCurve(to: CGPoint(x: x + 2, y: 150),
                               control1: CGPoint(x: x - 8, y: 164),
                               control2: CGPoint(x: x + 10, y: 158))
                    p.addCurve(to: CGPoint(x: x - 2, y: 132),
                               control1: CGPoint(x: x - 4, y: 144),
                               control2: CGPoint(x: x + 6, y: 138))
                }
                .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .offset(y: CGFloat(sin(t * 1.4 + Double(i))) * 2)
            }
        }
        .frame(width: 280, height: 320)
    }
}
