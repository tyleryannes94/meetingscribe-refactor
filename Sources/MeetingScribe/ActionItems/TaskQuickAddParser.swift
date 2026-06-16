import Foundation

/// Result of parsing a one-line quick-add string (P3-2 / UX-7).
struct ParsedQuickAdd: Equatable {
    var title: String
    var dueDate: Date?
    var priority: ActionItem.Priority?
    var labelNames: [String]
    /// Person-addressed capture (P2-8): the bare name token from `@name`
    /// (assign to) or `>name` (waiting on / delegated). The caller resolves it
    /// to a Person via PersonResolver. Nil when no token was typed.
    var ownerToken: String? = nil
    /// True when the owner was given with `>` (you're waiting on them).
    var delegated: Bool = false
    /// Project name token from `+Project` / `+"Multi Word"` (2-3). The caller
    /// fuzzy-matches it against existing projects and sets `projectID`. Nil when
    /// none typed. (`@` stays reserved for person assignment from P2-8.)
    var projectQuery: String? = nil
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

        // Owner token (P2-8): @name (assign) or >name (waiting on). Single word
        // token of letters/digits/._-. First match wins; stripped from the title.
        var ownerToken: String?
        var delegated = false
        if let regex = try? NSRegularExpression(pattern: "(?:^|\\s)([@>])([A-Za-z0-9._\\-]+)") {
            let ns = text as NSString
            if let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges > 2 {
                delegated = ns.substring(with: m.range(at: 1)) == ">"
                ownerToken = ns.substring(with: m.range(at: 2))
                if let r = Range(m.range, in: text) { text.replaceSubrange(r, with: " ") }
            }
        }

        // Project token (2-3): +Word or +"Multi Word". First match wins; stripped.
        var projectQuery: String?
        if let regex = try? NSRegularExpression(pattern: "(?:^|\\s)\\+(?:\"([^\"]+)\"|([A-Za-z0-9._\\-]+))") {
            let ns = text as NSString
            if let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                let quoted = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : nil
                let bare = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : nil
                projectQuery = quoted ?? bare
                if let r = Range(m.range, in: text) { text.replaceSubrange(r, with: " ") }
            }
        }

        // Explicit due: shorthand (2-3) — due:today / tomorrow / friday /
        // next-week / +3d. Parsed before NSDataDetector so the keyword form wins;
        // bare natural-language dates still fall through to the detector below.
        var dueDate: Date?
        if let regex = try? NSRegularExpression(pattern: "(?:^|\\s)due:([A-Za-z0-9+\\-]+)", options: [.caseInsensitive]) {
            let ns = text as NSString
            if let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges > 1 {
                let token = ns.substring(with: m.range(at: 1))
                if let d = dueShorthand(token, now: now) {
                    dueDate = d
                    if let r = Range(m.range, in: text) { text.replaceSubrange(r, with: " ") }
                }
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
        // Only runs when an explicit `due:` token didn't already set the date.
        if dueDate == nil, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
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

        return ParsedQuickAdd(title: title, dueDate: dueDate, priority: priority,
                              labelNames: labels, ownerToken: ownerToken, delegated: delegated,
                              projectQuery: projectQuery)
    }

    /// Resolves a `due:` keyword to a concrete date (2-3): `today`, `tomorrow`,
    /// `next-week`/`nextweek`, `+Nd`, or a weekday name → its next occurrence.
    static func dueShorthand(_ raw: String, now: Date) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let token = raw.lowercased()
        switch token {
        case "today": return today
        case "tomorrow", "tmr", "tom": return cal.date(byAdding: .day, value: 1, to: today)
        case "next-week", "nextweek": return cal.date(byAdding: .day, value: 7, to: today)
        default: break
        }
        // +Nd → N days out.
        if token.hasPrefix("+"), token.hasSuffix("d"),
           let n = Int(token.dropFirst().dropLast()) {
            return cal.date(byAdding: .day, value: n, to: today)
        }
        // Weekday name → next occurrence (today counts if it matches).
        let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
                        "thursday": 5, "friday": 6, "saturday": 7,
                        "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
        if let target = weekdays[token] {
            let cur = cal.component(.weekday, from: today)
            let delta = (target - cur + 7) % 7
            return cal.date(byAdding: .day, value: delta, to: today)
        }
        return nil
    }
}
