import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

enum Theme {
    static let ink = Color(hex: "#4A2C26")
    static let deepInk = Color(hex: "#33201C")
    static let cream = Color(hex: "#FFF8EF")
    static let card = Color(hex: "#FFFDF9")
    static let accentFallback = Color(hex: "#FF6F91")
    static let shadow = Color.black.opacity(0.16)

    static let bubbleFill = Color(hex: "#FFFDF8").opacity(0.97)
    static let bubbleStroke = Color(hex: "#F0C9B8").opacity(0.85)

    static func roundedFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Persona {
    var bodyColor: Color { Color(hex: bodyHex) }
    var bellyColor: Color { Color(hex: bellyHex) }
    var accentColor: Color { Color(hex: accentHex) }
    var finColor: Color { Color(hex: finHex) }
}

// 轻量震动反馈
enum Haptics {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    static func soft() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
