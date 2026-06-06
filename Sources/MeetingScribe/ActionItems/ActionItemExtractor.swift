import Foundation

/// Pulls structured `ActionItem`s out of a meeting's `summary.md`.
///
/// The summary prompt (`OllamaService.buildPrompt`) instructs the model to
/// emit a strict format we can parse without an LLM:
///
///     ## Action Items
///     - [ ] <owner> — <action> (due: <date or "unspecified">)
///     - [x] <owner> — <already done action> (due: …)
///
/// We accept some forgiveness:
///   • `- [ ]` and `- [x]` checkbox prefixes (optional).
///   • Bare bullets (`-`, `*`) without the checkbox.
///   • Either em-dash `—` or hyphen `-` as the owner separator.
///   • Missing owner (item starts with the action text).
///   • Missing due clause (we leave `dueDate` nil).
///
/// Output ActionItems are pre-stamped with the meeting metadata and stable
/// UUIDs; the store de-dupes by `signature` so re-extracts don't blow
/// away user edits.
enum ActionItemExtractor {

    static func extract(from summary: String, meeting: Meeting) -> [ActionItem] {
        guard let actionSection = isolateActionItemsSection(in: summary) else { return [] }
        let lines = actionSection.components(separatedBy: .newlines)
        var items: [ActionItem] = []
        for raw in lines {
            guard let parsed = parseLine(raw) else { continue }
            // Skip the "None." sentinel.
            if parsed.text.lowercased() == "none." || parsed.text.lowercased() == "none" { continue }
            // Keep action items that are MINE (owned by "Me"/the user, or where
            // the action text addresses the user). Items owned by *others* are
            // dropped — unless the user opts in to capturing them as
            // "delegated / waiting-on" tasks (PM-19), in which case we keep them
            // tagged so a "Delegated" view can surface them.
            let mine = isMine(owner: parsed.owner, text: parsed.text)
            if !mine && !AppSettings.shared.captureDelegatedTasks { continue }
            let item = ActionItem(
                id: UUID().uuidString,
                meetingID: meeting.id,
                meetingTitle: meeting.displayTitle,
                meetingDate: meeting.startDate,
                title: parsed.text,
                owner: parsed.owner,
                notes: nil,
                status: parsed.completed ? .completed : .open,
                priority: .medium,
                dueDate: parsed.dueDate,
                notionPageID: nil,
                notionURL: nil,
                delegated: mine ? nil : true,
                createdAt: Date(),
                updatedAt: Date()
            )
            items.append(item)
        }
        return items
    }

    /// True if the action item belongs to the user. Owned by Me/Tyler, OR the
    /// action text directly addresses the user by name (e.g. "Tyler to send…",
    /// "Tyler, can you…"). Items owned by other named participants, or with no
    /// owner and no mention of the user, are treated as not-mine.
    private static func isMine(owner: String?, text: String) -> Bool {
        // Profile-driven (U1-2): the set of tokens that mean "the user" comes
        // from AppSettings.userName + aliases, not a hardcoded "tyler".
        let aliases = AppSettings.shared.myNameAliases
        if let o = owner?.lowercased().trimmingCharacters(in: .whitespaces), !o.isEmpty {
            // Owner like "Me", the user's name, "Me (Name)", "First Last".
            if aliases.contains(o) { return true }
            for alias in aliases where o.hasPrefix(alias + " ") || o.contains("(\(alias))") {
                return true
            }
            // Owner is someone else → not mine.
            return false
        }
        // No owner parsed — only mine if the action explicitly names me.
        let lower = text.lowercased()
        if lower.hasPrefix("i ") { return true }
        // Match the user's actual name tokens (not the generic pronouns, which
        // would match far too eagerly mid-sentence).
        for name in AppSettings.shared.myNameTokens {
            if lower.hasPrefix(name + " ") || lower.hasPrefix(name + ",")
                || lower.contains(" \(name) ") { return true }
        }
        return false
    }

    /// Returns the text between `## Action Items` and the next `## ` heading
    /// (or EOF). Case-insensitive on the heading. Returns nil if no section.
    private static func isolateActionItemsSection(in markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        var start: Int?
        for (i, l) in lines.enumerated() {
            let trimmed = l.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("## action items") {
                start = i + 1
                break
            }
        }
        guard let s = start else { return nil }
        var end = lines.count
        for j in s..<lines.count {
            let t = lines[j].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("## ") || t.hasPrefix("# ") { end = j; break }
        }
        return lines[s..<end].joined(separator: "\n")
    }

    /// One parsed bullet line.
    private struct ParsedLine {
        let owner: String?
        let text: String
        let dueDate: Date?
        let completed: Bool
    }

    /// Parses a single bullet of the form
    ///   `- [x] Alice — review the doc (due: 2026-05-22)`
    /// Returns nil if the line isn't a bullet.
    private static func parseLine(_ raw: String) -> ParsedLine? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        // Require bullet prefix.
        let bulletChars: [Character] = ["-", "*", "•"]
        guard let first = line.first, bulletChars.contains(first) else { return nil }
        line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)

        // Optional checkbox.
        var completed = false
        if line.hasPrefix("[x]") || line.hasPrefix("[X]") {
            completed = true
            line = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("[ ]") {
            line = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        guard !line.isEmpty else { return nil }

        // Optional due clause at the end: `(due: …)`.
        var dueDate: Date?
        if let dueRange = line.range(of: #"\(\s*due\s*:\s*[^)]*\)"#,
                                     options: [.regularExpression, .caseInsensitive]) {
            let clause = String(line[dueRange])
            line.removeSubrange(dueRange)
            line = line.trimmingCharacters(in: .whitespaces)
            dueDate = parseDueClause(clause)
        }

        // Owner — text before " — " or " - " separator (em-dash preferred).
        var owner: String?
        var text = line
        if let r = line.range(of: " — ") {
            owner = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            text = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if let r = line.range(of: " - ") {
            owner = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            text = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if let r = line.range(of: ": ") {
            // "Alice: review the doc"
            owner = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            text = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Owner sanity: should be short. If it's super long, the model
        // probably didn't include an owner — treat the whole thing as text.
        if let o = owner, o.count > 40 {
            owner = nil
            text = line
        }
        if owner?.isEmpty == true { owner = nil }
        guard !text.isEmpty else { return nil }
        return ParsedLine(owner: owner, text: text, dueDate: dueDate, completed: completed)
    }

    /// Parses the contents of `(due: …)`. Tries a few common formats; falls
    /// back to nil for anything it can't recognize (incl. "unspecified",
    /// "TBD", "EOW", etc — the user can pick a real date in the UI).
    private static func parseDueClause(_ clause: String) -> Date? {
        // Pull the inner text out of "(due: <inner>)".
        guard let inner = clause.range(of: #"due\s*:\s*"#,
                                       options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        var body = String(clause[inner.upperBound...])
        if body.hasSuffix(")") { body.removeLast() }
        body = body.trimmingCharacters(in: .whitespaces)
        if body.isEmpty || body.caseInsensitiveCompare("unspecified") == .orderedSame
            || body.caseInsensitiveCompare("tbd") == .orderedSame
            || body.caseInsensitiveCompare("none") == .orderedSame {
            return nil
        }
        let formats = [
            "yyyy-MM-dd",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "M/d/yyyy",
            "M/d/yy",
            "yyyy-MM-dd HH:mm"
        ]
        for f in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f
            if let d = df.date(from: body) { return d }
        }
        // Relative ("tomorrow", "next Friday"). Use DataDetector as a
        // best-effort fallback.
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = det.matches(in: body,
                                      range: NSRange(body.startIndex..., in: body))
            if let m = matches.first, let d = m.date { return d }
        }
        return nil
    }
}
