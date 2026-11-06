import AppKit
import Carbon.HIToolbox

final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func reload() {
        release()
        let s = AppSettings.shared
        guard s.hotkeyEnabled else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var handler: EventHandlerRef?
        let installed = InstallEventHandler(GetApplicationEventTarget(), nookHotkeyHandler, 1, &spec, nil, &handler)
        guard installed == noErr else { return }
        handlerRef = handler

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.fourCharCode("Nook"), id: 1)
        let status = RegisterEventHotKey(s.hotkeyKeyCode, s.hotkeyModifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { hotKeyRef = ref }
    }

    private func release() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    static func fourCharCode(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for ch in s.utf8.prefix(4) { result = (result << 8) + UInt32(ch) }
        return result
    }

    /// Human readable description for the settings UI.
    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        parts.append(Self.keyName(keyCode))
        return parts.joined()
    }

    static func keyName(_ keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 41: ";", 45: "N", 46: "M", 47: ",",
            43: "/", 50: "`", 27: "↩", 49: "Space"
        ]
        return map[keyCode] ?? "N"
    }

    static let selectableKeys: [UInt32] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15,
                                          16, 17, 31, 32, 34, 35, 37, 38, 40, 41, 43, 45, 46, 50]
}

private func nookHotkeyHandler(callRef: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .nookHotkeyToggled, object: nil)
    }
    return noErr
}
