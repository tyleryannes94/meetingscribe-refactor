import Foundation

/// A named, persisted `TaskQuery` (5-1) — the audit's saved-views gap. `TaskQuery`
/// was always `Codable` and built for this; this is the plumbing + identity that
/// lets a filter become a one-click sidebar entry. Stored in
/// `<storageDir>/saved_task_views.json`. Three built-ins are seeded and can't be
/// deleted.
struct SavedTaskView: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    /// SF Symbol shown in the rail.
    var icon: String? = nil
    var query: TaskQuery
    var sortIndex: Double? = nil
    var isPinned: Bool = false
    /// Built-ins (My Open Tasks / Overdue / Due This Week) can't be deleted.
    var isBuiltIn: Bool = false

    static func seedBuiltIns() -> [SavedTaskView] {
        [
            SavedTaskView(id: "builtin.myopen", name: "My Open Tasks", icon: "circle",
                          query: TaskQuery(scope: .all,
                                           filters: .init(statuses: [.open, .inProgress], includeCompleted: false)),
                          sortIndex: 0, isBuiltIn: true),
            SavedTaskView(id: "builtin.overdue", name: "Overdue", icon: "exclamationmark.circle.fill",
                          query: TaskQuery(scope: .all,
                                           filters: .init(overdue: true, includeCompleted: false)),
                          sortIndex: 1, isBuiltIn: true),
            SavedTaskView(id: "builtin.thisweek", name: "Due This Week", icon: "calendar.badge.clock",
                          query: TaskQuery(scope: .all,
                                           filters: .init(dueWithinDays: 7, includeCompleted: false)),
                          sortIndex: 2, isBuiltIn: true),
        ]
    }
}
