import Foundation
import Carbon.HIToolbox
import AppKit
import OSLog

/// Registers a system-wide hotkey via Carbon's RegisterEventHotKey API.
/// On macOS this is the standard way to grab a global shortcut without
/// needing accessibility access. Only one keycode+modifiers combination is
/// active at a time per instance.
final class GlobalHotkey {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Hotkey")

    /// Closure invoked on each press of the registered hotkey (main thread).
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    /// Unique id per instance so multiple hotkeys (dictation + swap) can be
    /// registered simultaneously without colliding in the callback map.
    private let id: UInt32
    private static var nextID: UInt32 = 1
    private static var instances: [UInt32: GlobalHotkey] = [:] // id → instance, for the C callback
    /// The keyboard event handler is installed exactly ONCE for the whole
    /// process. Installing it per-instance would fire every handler for every
    /// hotkey press → double triggers.
    private static var handlerInstalled = false

    init() {
        id = Self.nextID
        Self.nextID += 1
    }

    deinit { unregister() }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        Self.installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4D544D54), id: id) // 'MTMT'
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            log.error("RegisterEventHotKey failed: \(status)")
            return
        }
        hotKeyRef = ref
        Self.instances[id] = self
        log.info("Hotkey registered: id=\(self.id) keyCode=\(keyCode) mods=\(modifiers)")
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        Self.instances[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
    }

    private static let handler: EventHandlerUPP = { _, eventRef, _ in
        guard let eventRef else { return noErr }
        var hkID = EventHotKeyID()
        let s = GetEventParameter(eventRef,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil,
                                  MemoryLayout<EventHotKeyID>.size,
                                  nil,
                                  &hkID)
        guard s == noErr, let instance = instances[hkID.id] else { return noErr }
        DispatchQueue.main.async { instance.onTrigger?() }
        return noErr
    }
}

/// Convenience helpers for translating Carbon keycodes/modifiers to display
/// strings — used by the Settings UI.
enum HotkeyDisplay {
    static func modifierString(_ mods: UInt32) -> String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey)  != 0 { s += "⌥" }
        if mods & UInt32(shiftKey)   != 0 { s += "⇧" }
        if mods & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    /// Best-effort mapping of common keycodes to printable names.
    static func keyName(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_F1: return "F1"; case kVK_F2: return "F2"; case kVK_F3: return "F3"
        case kVK_F4: return "F4"; case kVK_F5: return "F5"; case kVK_F6: return "F6"
        case kVK_F7: return "F7"; case kVK_F8: return "F8"; case kVK_F9: return "F9"
        case kVK_F10: return "F10"; case kVK_F11: return "F11"; case kVK_F12: return "F12"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_Tab: return "Tab"
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"; case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"; case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"; case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"; case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"; case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"; case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"; case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"; case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        default: return "Key(\(keyCode))"
        }
    }
}
