import Foundation

/// Appends each finalized meeting into a per-day note at
/// `<vault>/Daily/YYYY-MM-DD.md` — a persisted, linkable temporal spine that
/// Obsidian "periodic notes" users expect (C2-4 / C3-3).
///
/// The app-managed meeting list lives between HTML-comment guards so anything
/// the user free-writes outside the block is preserved across regenerations.
/// Adding a meeting is idempotent (matched by its wikilink), so re-finalizing
/// or re-transcribing never duplicates a line.
enum DailyNoteWriter {
    private static let begin = "<!-- meetingscribe:meetings:begin -->"
    private static let end   = "<!-- meetingscribe:meetings:end -->"

    static func appendMeeting(_ meeting: Meeting, storageDir: URL) {
        let cal = Calendar.current
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        let dateStr = dayFmt.string(from: cal.startOfDay(for: meeting.startDate))

        let dir = storageDir.appendingPathComponent("Daily", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(dateStr).md")

        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if content.isEmpty {
            content = "# \(dateStr)\n\n## Meetings\n\(begin)\n\(end)\n"
        } else if !content.contains(begin) {
            // Existing free-form daily note — append the managed block.
            content += "\n## Meetings\n\(begin)\n\(end)\n"
        }

        // Wikilink resolves to the meeting's <slug>.md in the vault (Obsidian).
        let link = "[[\(meeting.slug)]]"
        guard !content.contains(link) else { return }   // already listed

        let timeFmt = DateFormatter(); timeFmt.dateFormat = "HH:mm"
        let line = "- \(timeFmt.string(from: meeting.startDate)) \(link) — \(meeting.displayTitle)"

        if let r = content.range(of: end) {
            content.replaceSubrange(r, with: "\(line)\n\(end)")
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
