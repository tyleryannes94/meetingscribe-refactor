import Foundation

/// A time-boxed cycle of work within a project (6-1) — the Linear/Jira "sprint".
/// Stored inside its `Project` (so it travels with the project file); a task
/// points at one via `ActionItem.sprintID`.
struct Sprint: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var startDate: Date
    var endDate: Date
    var status: Status = .active

    enum Status: String, Codable, CaseIterable, Identifiable, Sendable {
        case planned, active, completed
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    /// A sensible default two-week cycle starting today.
    static func twoWeek(name: String, now: Date = Date()) -> Sprint {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 14, to: start) ?? start
        return Sprint(name: name.isEmpty ? "Sprint" : name, startDate: start, endDate: end)
    }
}
