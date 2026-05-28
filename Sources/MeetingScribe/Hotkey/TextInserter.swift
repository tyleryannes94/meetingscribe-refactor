import Foundation
import AppKit
import Carbon.HIToolbox

/// Pastes text into whatever app is currently focused. Uses the clipboard and
/// a synthesized ⌘V, which works in 99% of apps without requiring AX access.
/// Original clipboard contents are restored afterward.
enum TextInserter {
    /// Replaces the last-inserted run of text with `text`: sends `deleteCount`
    /// backspaces (deleting the previously-inserted characters, assuming the
    /// cursor is still right after them), then pastes the replacement. Used by
    /// the dictation "swap version" hotkey to toggle raw ↔ polished in place.
    static func replaceLastInserted(deleteCount: Int, with text: String) {
        guard deleteCount > 0 else { insertAtCursor(text); return }
        let src = CGEventSource(stateID: .combinedSessionState)
        // kVK_Delete (Backspace) = 51.
        for _ in 0..<deleteCount {
            CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: false)?.post(tap: .cghidEventTap)
        }
        // Let the deletions land before pasting the replacement.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            insertAtCursor(text)
        }
    }

    static func insertAtCursor(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types {
                if let d = item.data(forType: t) { dict[t] = d }
            }
            return dict
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Send ⌘V via Quartz event tap. A short delay lets the pasteboard settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendCommandV()
            // Restore the original clipboard a beat later, so the paste actually picks
            // up our string first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                for item in savedItems {
                    let pi = NSPasteboardItem()
                    for (t, d) in item { pi.setData(d, forType: t) }
                    pasteboard.writeObjects([pi])
                }
            }
        }
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        // V keycode = 9
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }
}
