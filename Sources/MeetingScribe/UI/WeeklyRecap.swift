import Foundation

/// Generates a "Weekly review" note (P2-3) from the last 7 days — meetings,
/// decisions, and open commitments — into `<vault>/Weekly/<YYYY-Www>.md`,
/// turning the previously-blank weekly-review template into a real ritual.
@available(macOS 14.0, *)
enum WeeklyRecap {
    @MainActor
    @discardableResult
    static func generate(manager: MeetingManager) -> URL? {
        let cal = Calendar.current
        let now = Date()
        let weekStart = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)) ?? now

        let meetings = manager.pastMeetings
            .filter { $0.startDate >= weekStart }
            .sorted { $0.startDate < $1.startDate }
        let decisions = manager.decisions.decisions.filter { $0.date >= weekStart }
        let open = manager.actionItems.items.filter { $0.status != .completed }

        let weekFmt = DateFormatter(); weekFmt.dateFormat = "YYYY-'W'ww"
        let label = weekFmt.string(from: now)
        let df = DateFormatter(); df.dateStyle = .medium

        var lines = ["# Weekly review — \(label)", "",
                     "_\(df.string(from: weekStart)) – \(df.string(from: now))_", ""]
        lines.append("## Meetings (\(meetings.count))")
        lines += meetings.isEmpty ? ["- _(none)_"]
                                  : meetings.map { "- \(df.string(from: $0.startDate)) — [[\($0.slug)]]" }
        lines.append("")
        lines.append("## Decisions (\(decisions.count))")
        lines += decisions.isEmpty ? ["- _(none)_"]
                                   : decisions.map { "- \($0.text)  _(\($0.sourceLabel))_" }
        lines.append("")
        lines.append("## Open commitments (\(open.count))")
        lines += open.isEmpty ? ["- _(none)_"]
                              : open.prefix(20).map { "- [ ] \($0.title)\($0.owner.map { " — \($0)" } ?? "")" }
        let md = lines.joined(separator: "\n") + "\n"

        let dir = AppSettings.shared.storageDir.appendingPathComponent("Weekly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(label).md")
        do { try md.write(to: url, atomically: true, encoding: .utf8); return url }
        catch { return nil }
    }
}
