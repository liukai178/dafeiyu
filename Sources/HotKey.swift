import Foundation
import Carbon

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onVoice: (() -> Void)?
    var onEscape: (() -> Void)?

    private var handlerRef: EventHandlerRef?
    private var voiceRef: EventHotKeyRef?
    private var escapeRef: EventHotKeyRef?
    private let signature: OSType = 0x4446_5955 // 'DFYU'

    private init() {
        installHandler()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                center.handle(id: hkID.id)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    private func handle(id: UInt32) {
        switch id {
        case 1: DispatchQueue.main.async { self.onVoice?() }
        case 2: DispatchQueue.main.async { self.onEscape?() }
        default: break
        }
    }

    func registerVoice() {
        guard voiceRef == nil else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        voiceRef = ref
    }

    func unregisterVoice() {
        if let ref = voiceRef {
            UnregisterEventHotKey(ref)
            voiceRef = nil
        }
    }

    func setEscapeEnabled(_ enabled: Bool) {
        if enabled {
            guard escapeRef == nil else { return }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: 2)
            RegisterEventHotKey(
                UInt32(kVK_Escape),
                0,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            escapeRef = ref
        } else if let ref = escapeRef {
            UnregisterEventHotKey(ref)
            escapeRef = nil
        }
    }

    func unregisterAll() {
        unregisterVoice()
        setEscapeEnabled(false)
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }
}
