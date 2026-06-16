import Foundation
import Observation

/// Owns the **view state** of the Tasks tab — filter, sort, search, grouping,
/// edit cursor, push-in-flight set — and the single canonical filter / sort /
/// group implementation that every view mode (list, table, board, calendar,
/// gallery) reads from.
///
/// A0-1 (audit E2-1): previously this class was dead code — a *second*,
/// diverged copy of the filter logic and enums that lived alongside the live
/// implementation inside `ActionItemsView`'s extensions. The migration adopts
/// the live logic here (it is the richer one — it honors `ownerScope` and the
/// triage exclusion), deletes the duplicate, and wires `ActionItemsView` to a
/// single `@State` instance of this type. The enums stay defined on
/// `ActionItemsView` (they are referenced externally as `ActionItemsView.X`
/// and carry the full case set); this class references them by typealias so
/// there is exactly one definition of each.
@available(macOS 14.0, *)
@MainActor
@Observable
final class ActionItemsViewModel {

    // MARK: - Enums (single definition lives on ActionItemsView)

    typealias Filter = ActionItemsView.Filter
    typealias PriorityFilter = ActionItemsView.PriorityFilter
    typealias OwnerScope = ActionItemsView.OwnerScope
    typealias GroupBy = ActionItemsView.GroupBy
    typealias ViewMode = ActionItemsView.ViewMode
    typealias TableSort = ActionItemsView.TableSort

    // MARK: - View state (was ~11 @State vars on ActionItemsView)

    var filter: Filter = .all
    var priorityFilter: PriorityFilter = .any
    var ownerScope: OwnerScope = .anyone
    var search: String = ""
    var groupBy: GroupBy = .none
    var viewMode: ViewMode = .list
    var tableSort: TableSort = .priority
    var tableSortAscending: Bool = false

    var pushingIDs: Set<String> = []
    var lastError: String?
    var editingID: String?

    // MARK: - Filtering (canonical implementation — A0-1)

    /// Live tasks narrowed by the status / priority / owner / search facets,
    /// then sorted. The single source of truth for "what tasks are visible",
    /// consumed by every view mode through `ActionItemsView`. `myNameAliases`
    /// is injected so the "mine" owner scope stays a pure function.
    func filtered(_ items: [ActionItem], myNameAliases: Set<String>, now: Date = Date()) -> [ActionItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return items
            // Meeting-extracted action items wait in the Triage inbox until the
            // user accepts them — they are NOT auto-added to the task database.
            .filter { !$0.needsTriage }
            .filter { item in
                switch filter {
                case .all: return true
                case .open: return item.status == .open
                case .inProgress: return item.status == .inProgress
                case .completed: return item.status == .completed
                case .upcoming:
                    guard let due = item.dueDate, item.status != .completed else { return false }
                    let weekOut = cal.date(byAdding: .day, value: 7, to: today) ?? today
                    return due >= today && due <= weekOut
                case .thisWeek:
                    // P0-5: "This Week" means due within the current calendar week
                    // — NOT created this week. A task with no due date is not "this
                    // week" no matter when it was captured.
                    guard item.status != .completed, let due = item.dueDate else { return false }
                    let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
                    let endOfWeek = cal.date(byAdding: .day, value: 7, to: startOfWeek) ?? today
                    return due >= startOfWeek && due < endOfWeek
                case .overdue:
                    guard let due = item.dueDate else { return false }
                    return due < today && item.status != .completed
                }
            }
            .filter { item in
                switch priorityFilter {
                case .any: return true
                case .low: return item.priority == .low
                case .medium: return item.priority == .medium
                case .high: return item.priority == .high
                case .urgent: return item.priority == .urgent
                }
            }
            .filter { item in
                switch ownerScope {
                case .anyone: return true
                case .mine: return Self.isMine(item, myNameAliases: myNameAliases)
                case .delegated: return item.delegated == true
                }
            }
            .filter { item in
                guard !search.isEmpty else { return true }
                let q = search.lowercased()
                return item.title.lowercased().contains(q)
                    || (item.owner ?? "").lowercased().contains(q)
                    || item.meetingTitle.lowercased().contains(q)
            }
            .sorted(by: Self.defaultSort)
    }

    /// A task counts as "mine" when its owner matches one of my name aliases, or
    /// it's unassigned (my own captured task). Drives the "My open" quick view.
    static func isMine(_ item: ActionItem, myNameAliases: Set<String>) -> Bool {
        let owner = (item.owner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if owner.isEmpty { return true }
        return myNameAliases.contains(owner.lowercased())
    }

    static func defaultSort(_ a: ActionItem, _ b: ActionItem) -> Bool {
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
        return a.meetingDate > b.meetingDate
    }

    // MARK: - Grouping (canonical implementation — A0-1)

    /// String key an item groups under for the current `groupBy` mode. Covers
    /// the store-free modes; `ActionItemsView.groupKey(for:)` overrides the
    /// project/initiative/label modes that need name resolution (5-5).
    func groupKey(for item: ActionItem, now: Date = Date()) -> String {
        switch groupBy {
        case .none: return ""
        case .meeting: return item.meetingTitle
        case .priority: return item.priority.label
        case .status: return item.status.label
        case .owner: return item.owner?.isEmpty == false ? item.owner! : "Unassigned"
        case .project: return item.projectID ?? "No project"
        case .initiative: return item.projectID ?? "No initiative"
        case .label: return item.labelIDs?.first ?? "No label"
        case .sprint: return item.sprintID ?? "No sprint"
        case .dueDate:
            guard let d = item.dueDate else { return "No due date" }
            let cal = Calendar.current
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDateInTomorrow(d) { return "Tomorrow" }
            if cal.isDateInYesterday(d) { return "Yesterday" }
            if d < now { return "Overdue" }
            let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
            return f.string(from: d)
        }
    }

    /// Buckets `items` by `groupKey`.
    func grouped(_ items: [ActionItem]) -> [String: [ActionItem]] {
        Dictionary(grouping: items, by: { groupKey(for: $0) })
    }

    /// Ordered group keys for `items` — fixed priority/status order, otherwise alphabetical.
    func groupedKeys(_ items: [ActionItem]) -> [String] {
        let keys = Array(grouped(items).keys)
        switch groupBy {
        case .priority:
            let order = ["Urgent", "High", "Medium", "Low"]
            return order.filter { keys.contains($0) }
        case .status:
            let order = ["In Progress", "Open", "Completed"]
            return order.filter { keys.contains($0) }
        default:
            return keys.sorted()
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
