import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A click-to-record control for capturing ANY keyboard shortcut. Click it,
/// then press the key combo you want — it captures the keycode + modifiers
/// and writes them to the bound values. Esc cancels; Delete/Backspace while
/// recording clears to "unset".
///
/// Carbon keycodes (NSEvent.keyCode) map 1:1 to the `RegisterEventHotKey`
/// keycodes used by GlobalHotkey, and we translate NSEvent.modifierFlags to
/// the Carbon modifier mask (cmdKey/optionKey/controlKey/shiftKey).
@available(macOS 14.0, *)
struct HotkeyRecorder: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…  (Esc cancels)" : display)
                .font(.body.monospaced())
                .frame(minWidth: 120)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(recording ? Color.accentColor.opacity(0.18)
                                      : Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(recording ? Color.accentColor : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Click, then press any key combination to set this shortcut.")
        .onDisappear { stop() }
    }

    private var display: String {
        let mods = HotkeyDisplay.modifierString(modifiers)
        return mods + HotkeyDisplay.keyName(keyCode)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels without changing the binding.
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            keyCode = UInt32(event.keyCode)
            modifiers = Self.carbonModifiers(from: event.modifierFlags)
            stop()
            return nil // consume the event so it doesn't type into the field
        }
    }

    private func stop() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }
}
