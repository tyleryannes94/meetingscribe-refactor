import Foundation

/// A single, freestanding voice note — recorded outside any calendar meeting.
/// Files live at: <storageDir>/QuickNotes/<slug>/
///   ├── note.json
///   ├── audio.m4a
///   └── transcript.md
struct QuickNote: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var createdAt: Date
    var durationSeconds: Double
    /// First ~150 chars of transcript for the list preview.
    var snippet: String
    /// True if this note was created by a hotkey-driven "Whispr Flow"-style
    /// dictation (vs. a manual "New Note" in the UI).
    var wasDictation: Bool

    var slug: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let datePart = f.string(from: createdAt)
        let safe = title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = String(safe.prefix(40))
        return "\(datePart)-\(truncated.isEmpty ? "Note" : truncated)"
    }
}
