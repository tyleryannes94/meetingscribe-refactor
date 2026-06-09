import Foundation

/// One row parsed from an imported CSV (PM-20).
struct ParsedImportRow: Equatable {
    var title: String
    var status: ActionItem.Status?
    var priority: ActionItem.Priority?
    var owner: String?
    var dueDate: Date?
}

/// Parses a CSV (e.g. exported from Todoist/Asana/Notion, or our own export)
/// into rows ready to become tasks. Pure and testable — the file pick / task
/// creation lives in the UI layer. Maps common column names; tolerant of quoted
/// fields and missing columns.
enum TaskCSVImporter {

    static func parse(_ csv: String) -> [ParsedImportRow] {
        let lines = csv.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return [] }

        let header = parseLine(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func col(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
        let titleI = col(["title", "task", "name"])
        let statusI = col(["status"])
        let prioI = col(["priority"])
        let ownerI = col(["owner", "assignee"])
        let dueI = col(["due", "due date"])

        // With a recognizable header, skip it; otherwise treat the first column
        // of every line as the title.
        let dataLines = titleI != nil ? Array(lines.dropFirst()) : lines
        let tIdx = titleI ?? 0

        var rows: [ParsedImportRow] = []
        for line in dataLines {
            let f = parseLine(line)
            guard tIdx < f.count else { continue }
            let title = f[tIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            var row = ParsedImportRow(title: title)
            if let i = statusI, i < f.count { row.status = parseStatus(f[i]) }
            if let i = prioI, i < f.count { row.priority = parsePriority(f[i]) }
            if let i = ownerI, i < f.count {
                let o = f[i].trimmingCharacters(in: .whitespaces); row.owner = o.isEmpty ? nil : o
            }
            if let i = dueI, i < f.count { row.dueDate = parseDate(f[i]) }
            rows.append(row)
        }
        return rows
    }

    /// RFC-4180 single-line field split (handles quoted fields + doubled quotes).
    static func parseLine(_ line: String) -> [String] {
        var fields: [String] = []
        var cur = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { cur.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { cur.append(c) }
            } else {
                if c == "\"" { inQuotes = true }
                else if c == "," { fields.append(cur); cur = "" }
                else { cur.append(c) }
            }
            i += 1
        }
        fields.append(cur)
        return fields
    }

    private static func parseStatus(_ s: String) -> ActionItem.Status? {
        switch s.lowercased().trimmingCharacters(in: .whitespaces) {
        case "open", "todo", "to do", "not started", "backlog": return .open
        case "in progress", "inprogress", "doing", "started": return .inProgress
        case "completed", "complete", "done", "closed": return .completed
        default: return nil
        }
    }
    private static func parsePriority(_ s: String) -> ActionItem.Priority? {
        switch s.lowercased().trimmingCharacters(in: .whitespaces) {
        case "low", "p4": return .low
        case "medium", "med", "normal", "p3": return .medium
        case "high", "p2": return .high
        case "urgent", "critical", "p1": return .urgent
        default: return nil
        }
    }
    private static func parseDate(_ s: String) -> Date? {
        let body = s.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: body) { return d }
        for fmt in ["yyyy-MM-dd", "M/d/yyyy", "M/d/yy", "MMM d, yyyy", "MMMM d, yyyy"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            if let d = df.date(from: body) { return d }
        }
        return nil
    }
}
