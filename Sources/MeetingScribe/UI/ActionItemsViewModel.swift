import Foundation
import Observation

/// Owns the **view state** of the Tasks tab — filter, sort, search, grouping,
/// edit cursor, push-in-flight set, etc. Extracted from `ActionItemsView`
/// (2,518 lines) in Batch 7 (audit 6.1).
///
/// The big view file becomes a thin renderer over an `@StateObject` of this
/// class: filters/sorts move out of `@State`, group-by switching is a single
/// derived property rather than an inline closure, and any future split into
/// per-view files (table / board / list) consumes the same source of truth.
@available(macOS 14.0, *)
@MainActor
@Observable
final class ActionItemsViewModel {

    // MARK: - Enums (lift out the inline types so per-view files can share)

    enum Filter: String, CaseIterable, Identifiable, Hashable {
        case all, open, inProgress, completed, upcoming, overdue
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .open: return "Open"
            case .inProgress: return "In Progress"
            case .completed: return "Completed"
            case .upcoming: return "Upcoming"
            case .overdue: return "Overdue"
            }
        }
    }

    enum PriorityFilter: String, CaseIterable, Identifiable, Hashable {
        case any, low, medium, high, urgent
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: return "Any"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .urgent: return "Urgent"
            }
        }
    }

    enum GroupBy: String, CaseIterable, Identifiable, Hashable {
        case none, project, owner, priority, dueDay
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "None"
            case .project: return "Project"
            case .owner: return "Owner"
            case .priority: return "Priority"
            case .dueDay: return "Due day"
            }
        }
    }

    enum ViewMode: String, CaseIterable, Identifiable, Hashable {
        case list, table, board
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .list: return "list.bullet"
            case .table: return "tablecells"
            case .board: return "rectangle.split.3x1"
            }
        }
    }

    enum TableSort: String, CaseIterable, Identifiable, Hashable {
        case priority, due, status, owner, meeting
        var id: String { rawValue }
    }

    static let noProjectSentinel = "__none__"
    static let homeSentinel = "__home__"

    // MARK: - Published view state

    var filter: Filter = .all
    var priorityFilter: PriorityFilter = .any
    var search: String = ""
    var groupBy: GroupBy = .none
    var viewMode: ViewMode = .list
    var tableSort: TableSort = .priority
    var tableSortAscending: Bool = false

    var pushingIDs: Set<String> = []
    var lastError: String?
    var editingID: String?

    /// "__home__" = dashboard; nil = All tasks; "__none__" = No project; else a project id.
    var selectedProjectID: String? = ActionItemsViewModel.homeSentinel
    var selectedMeetingID: String?
    var selectedTaskID: String?
    var selectedInitiativeID: String?
    var addingSection: Bool = false
    var newSectionName: String = ""
    var renameSectionID: String?
    var renameSectionDraft: String = ""

    // MARK: - Filtering / sorting (pure functions over store state)

    /// Returns the `items` filtered + sorted according to the current view
    /// state. Views should call this from `body` over the live items list
    /// supplied by `ActionItemStore`.
    func filteredSorted(items: [ActionItem], now: Date = Date()) -> [ActionItem] {
        var working = items

        // Search
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            working = working.filter { item in
                item.title.lowercased().contains(q) ||
                (item.owner?.lowercased().contains(q) ?? false) ||
                item.meetingTitle.lowercased().contains(q) ||
                (item.notes?.lowercased().contains(q) ?? false)
            }
        }

        // Status filter
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        switch filter {
        case .all: break
        case .open: working = working.filter { $0.status == .open }
        case .inProgress: working = working.filter { $0.status == .inProgress }
        case .completed: working = working.filter { $0.status == .completed }
        case .upcoming: working = working.filter {
            ($0.dueDate ?? .distantPast) > now &&
            ($0.dueDate ?? .distantPast) <= endOfToday.addingTimeInterval(7 * 86400)
        }
        case .overdue: working = working.filter {
            ($0.dueDate ?? .distantFuture) < now && $0.status != .completed
        }
        }

        // Priority filter
        if priorityFilter != .any {
            let p: ActionItem.Priority
            switch priorityFilter {
            case .low: p = .low
            case .medium: p = .medium
            case .high: p = .high
            case .urgent: p = .urgent
            case .any: p = .medium // unreachable
            }
            working = working.filter { $0.priority == p }
        }

        // Sort (table mode honors explicit choice; everything else uses default)
        if viewMode == .table {
            working = applyTableSort(working)
        } else {
            working.sort(by: defaultSort)
        }
        return working
    }

    private func applyTableSort(_ items: [ActionItem]) -> [ActionItem] {
        let asc = tableSortAscending
        switch tableSort {
        case .priority:
            return items.sorted { a, b in
                asc ? a.priority.weight < b.priority.weight
                    : a.priority.weight > b.priority.weight
            }
        case .due:
            return items.sorted { a, b in
                let ad = a.dueDate ?? .distantFuture
                let bd = b.dueDate ?? .distantFuture
                return asc ? ad < bd : ad > bd
            }
        case .status:
            return items.sorted { a, b in
                asc ? a.status.rawValue < b.status.rawValue
                    : a.status.rawValue > b.status.rawValue
            }
        case .owner:
            return items.sorted { a, b in
                let ao = a.owner ?? ""
                let bo = b.owner ?? ""
                return asc ? ao < bo : ao > bo
            }
        case .meeting:
            return items.sorted { a, b in
                asc ? a.meetingTitle < b.meetingTitle : a.meetingTitle > b.meetingTitle
            }
        }
    }

    private func defaultSort(_ a: ActionItem, _ b: ActionItem) -> Bool {
        if a.status == .completed && b.status != .completed { return false }
        if b.status == .completed && a.status != .completed { return true }
        switch (a.dueDate, b.dueDate) {
        case (let x?, let y?): if x != y { return x < y }
        case (nil, _?): return false
        case (_?, nil): return true
        default: break
        }
        if a.priority.weight != b.priority.weight {
            return a.priority.weight > b.priority.weight
        }
        return a.createdAt > b.createdAt
    }

    // MARK: - Grouping

    struct Group: Identifiable {
        let id: String
        let title: String
        let items: [ActionItem]
    }

    /// Groups the supplied list according to `groupBy`. `none` returns a single
    /// untitled group; other modes produce named buckets sorted by group label.
    func groupItems(_ items: [ActionItem]) -> [Group] {
        switch groupBy {
        case .none:
            return [Group(id: "all", title: "", items: items)]
        case .project:
            // Caller supplies the project name → id mapping via `projectName`.
            return bucket(items, by: { $0.projectID ?? Self.noProjectSentinel }) { key, value in
                // UI layer can swap in the friendly project name from
                // ActionItemStore.project(id:) — we use the id as the title here.
                Group(id: key, title: key, items: value)
            }
        case .owner:
            return bucket(items, by: { $0.owner ?? "Unassigned" }) { key, value in
                Group(id: key, title: key, items: value)
            }
        case .priority:
            return bucket(items, by: { $0.priority.rawValue }) { key, value in
                Group(id: key, title: key.capitalized, items: value)
            }
        case .dueDay:
            let f = DateFormatter()
            f.dateStyle = .medium
            return bucket(items, by: { item -> String in
                guard let d = item.dueDate else { return "No date" }
                return f.string(from: d)
            }) { key, value in
                Group(id: key, title: key, items: value)
            }
        }
    }

    /// Group `items` by a key extractor, then build one `Group` per bucket
    /// in sorted-key order. Straightforward replacement for the previous
    /// over-engineered curried helper.
    private func bucket<Key: Hashable & Comparable>(
        _ items: [ActionItem],
        by extract: (ActionItem) -> Key,
        build: (Key, [ActionItem]) -> Group
    ) -> [Group] {
        let dict = Dictionary(grouping: items, by: extract)
        return dict.keys.sorted().map { key in
            build(key, dict[key] ?? [])
        }
    }

    // MARK: - Counts (used by sidebar badges)

    func openCount(in items: [ActionItem]) -> Int {
        items.filter { $0.status != .completed }.count
    }

    func overdueCount(in items: [ActionItem], now: Date = Date()) -> Int {
        items.filter { ($0.dueDate ?? .distantFuture) < now && $0.status != .completed }.count
    }
}
