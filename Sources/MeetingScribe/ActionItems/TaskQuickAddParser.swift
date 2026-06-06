import Foundation

/// Result of parsing a one-line quick-add string (P3-2 / UX-7).
struct ParsedQuickAdd: Equatable {
    var title: String
    var dueDate: Date?
    var priority: ActionItem.Priority?
    var labelNames: [String]
}

/// Parses a single capture line like
///   "Email Sarah friday !high #marketing"
/// into a title plus structured fields, the way Things/Todoist/Linear do — so a
/// fully-specified task is one typed line instead of a trip through menus and a
/// calendar popover.
///
/// Recognizes:
///   • `!urgent` / `!high` / `!medium` / `!low`, and `!p1`…`!p4`  → priority
///   • `#label`                                                   → labels
///   • a natural-language date ("friday", "tomorrow 3pm", "6/12") → due date
/// All recognized tokens are stripped from the saved title.
enum TaskQuickAddParser {

    static func parse(_ raw: String, now: Date = Date()) -> ParsedQuickAdd {
        var text = " " + raw + " "
        var priority: ActionItem.Priority?
        var labels: [String] = []

        // Priority tokens (case-insensitive). Longer/explicit names first.
        let priorityMap: [(token: String, value: ActionItem.Priority)] = [
            ("!urgent", .urgent), ("!high", .high), ("!medium", .medium), ("!med", .medium), ("!low", .low),
            ("!p1", .urgent), ("!p2", .high), ("!p3", .medium), ("!p4", .low)
        ]
        for (token, value) in priorityMap {
            if let range = text.range(of: token, options: [.caseInsensitive]) {
                priority = value
                text.replaceSubrange(range, with: " ")
                break
            }
        }

        // Labels: #word (letters/digits/_/-). Collect and strip.
        if let regex = try? NSRegularExpression(pattern: "#([A-Za-z0-9_\\-]+)") {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() where m.numberOfRanges > 1 {
                labels.insert(ns.substring(with: m.range(at: 1)), at: 0)
            }
            text = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }

        // Due date: first NSDataDetector date match (handles "tomorrow",
        // "friday 3pm", "6/12", "next monday", …). Stripped from the title.
        var dueDate: Date?
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let ns = text as NSString
            if let m = detector.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
               let date = m.date {
                dueDate = date
                if let r = Range(m.range, in: text) { text.removeSubrange(r) }
            }
        }

        // Collapse whitespace left behind by stripped tokens.
        let title = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedQuickAdd(title: title, dueDate: dueDate, priority: priority, labelNames: labels)
    }
}
