import AppIntents
import Foundation

// Phase 2 (1G/2D) — native capture verbs for Siri / Shortcuts / Spotlight that
// work WITHOUT foregrounding the app. App Intents run outside the app's normal
// lifecycle, so rather than reach into a running MeetingManager these drop a
// JSON envelope into the vault `_inbox/` — the exact channel `iCloudInboxWatcher`
// already ingests (types: quick-note, action-item, add-person, voice-note). That
// means capture survives even if the app isn't running: the watcher picks it up
// on next launch.

/// Writes an inbox envelope to `<vault>/_inbox/<id>.json`, resolving the vault
/// the same way the app does (`AppSettings.shared.storageDir`) so the running
/// watcher finds it. Values are all strings — the watcher's `InboxEnvelope`
/// decodes the present keys and leaves the rest nil.
@MainActor
func dropInboxEnvelope(_ fields: [String: String]) throws {
    let root = AppSettings.shared.storageDir.appendingPathComponent("_inbox", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let id = fields["id"] ?? UUID().uuidString
    let url = root.appendingPathComponent("\(id).json")
    let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    try data.write(to: url, options: .atomic)
}

private func isoNow() -> String {
    let f = ISO8601DateFormatter()
    return f.string(from: Date())
}

/// Capture a quick note into the vault inbox — the running app turns it into a
/// Quick Note. Works hands-free from Shortcuts / Siri.
@available(macOS 13.0, *)
struct CaptureQuickNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Quick Note"
    static var description = IntentDescription("Save a quick note to MeetingScribe without opening it.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Note")
    var note: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Say or type something to capture.")
        }
        try dropInboxEnvelope([
            "type": "quick-note",
            "id": UUID().uuidString,
            "created": isoNow(),
            "body": trimmed,
        ])
        return .result(dialog: "Captured your note.")
    }
}

/// Add an action item to the vault inbox — the running app files it into Tasks.
@available(macOS 13.0, *)
struct AddActionItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Action Item"
    static var description = IntentDescription("Add a task to MeetingScribe without opening it.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Task")
    var task: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Give the task a description and try again.")
        }
        try dropInboxEnvelope([
            "type": "action-item",
            "id": UUID().uuidString,
            "created": isoNow(),
            "title": trimmed,
        ])
        return .result(dialog: "Added “\(trimmed)” to your tasks.")
    }
}
