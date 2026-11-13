import SwiftUI
import AppKit

enum SnapshotTool {

    @MainActor
    static func icon(path: String) -> Int32 {
        let state = PetState()
        state.persona = .tsundere
        state.snapshotMode = true
        state.mood = .happy
        let content = ZStack {
            RoundedRectangle(cornerRadius: 220, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#FFF6E9"), Color(hex: "#FFDCC9")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 220, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 10)
            PetView(state: state)
                .scaleEffect(3.35)
                .offset(y: 18)
        }
        .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return 1 }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return 1 }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("icon saved \(path)")
            return 0
        } catch {
            return 1
        }
    }

    @MainActor
    static func run(path: String, moodName: String) -> Int32 {
        let state = PetState()
        state.persona = Store.shared.config.persona
        state.mood = Mood(rawValue: moodName) ?? .idle
        state.idle = false
        state.hovered = false
        state.snapshotMode = true

        let view = PetView(state: state)
            .frame(width: 240, height: 240)
            .background(
                LinearGradient(colors: [Color(hex: "#FFF7EC"), Color(hex: "#F3E7DA")],
                               startPoint: .top, endPoint: .bottom)
            )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            return 1
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("png encode failed\n".utf8))
            return 1
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("saved \(path) \(cg.width)x\(cg.height)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
            return 1
        }
    }
}
