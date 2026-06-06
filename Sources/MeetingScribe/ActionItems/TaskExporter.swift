import Foundation

/// Exports tasks to a portable, spreadsheet-friendly CSV (PM-20). Pure and
/// testable — the file write / save panel lives in the UI layer. Keeps the
/// local-first promise (your data leaves in an open format) and removes lock-in.
enum TaskExporter {

    static func csv(_ items: [ActionItem],
                    projectName: (String) -> String? = { _ in nil },
                    labelName: (String) -> String? = { _ in nil }) -> String {
        let iso = ISO8601DateFormatter()
        func date(_ d: Date?) -> String { d.map { iso.string(from: $0) } ?? "" }

        let header = ["Title", "Status", "Priority", "Owner", "Project", "Due",
                      "Start", "Created", "Completed", "Estimate", "Labels", "Meeting"]
        var rows = [header.joined(separator: ",")]
        for it in items {
            let project = it.projectID.flatMap(projectName) ?? ""
            let labels = (it.labelIDs ?? []).compactMap(labelName).joined(separator: "; ")
            let cols = [
                it.title, it.status.label, it.priority.label, it.owner ?? "",
                project, date(it.dueDate), date(it.startDate), date(it.createdAt),
                date(it.completedAt), it.estimate.map { String(Int($0)) } ?? "",
                labels, it.meetingTitle
            ].map(escape)
            rows.append(cols.joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// RFC-4180 field escaping: wrap in quotes (doubling inner quotes) when the
    /// field contains a comma, quote, or newline.
    private static func escape(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
