import Foundation

/// A composable, value-type description of "which tasks, in what order" (P1 /
/// BE-7).
///
/// Today every view, badge, and agent hand-rolls its own `filter`+`sorted`
/// chain over `ActionItemStore.items`, and the logic has already drifted between
/// files. `TaskQuery` makes the intent declarative and reusable: one engine
/// (`TaskQueryEngine`) evaluates it, saved views (Phase 2) persist it, and the
/// agent/MCP API (Phase 6) accepts it. Pure data — trivially testable and
/// `Codable`, so it can later compile to SQL once storage moves to SQLite.
struct TaskQuery: Codable, Hashable, Sendable {

    /// What population of tasks to consider before field filters apply.
    enum Scope: Codable, Hashable, Sendable {
        case all
        case project(String)
        /// Tasks with no project (the "No project" bucket).
        case noProject
        /// Tasks across an explicit set of project ids (e.g. an initiative's
        /// projects — the caller resolves membership so the engine stays pure).
        case anyProjects(Set<String>)
        /// All tasks under an initiative (3-3). `ActionItemStore.tasks(matching:)`
        /// pre-resolves this to `.anyProjects(initiative's projects)` before the
        /// engine runs, so the engine itself stays pure.
        case initiative(String)
        case person(String)
        case meeting(String)
        /// Tasks whose effective workspace context is this one (1-1). The store
        /// denormalizes each task's `contextID` (from its project's initiative)
        /// so the engine stays a pure match.
        case context(String)
    }

    /// Field-level predicates. `nil` = "don't constrain on this field".
    struct Filters: Codable, Hashable, Sendable {
        var statuses: Set<ActionItem.Status>?
        var priorities: Set<ActionItem.Priority>?
        /// Item must carry *all* of these labels.
        var labelIDs: Set<String>?
        var ownerPersonID: String?
        /// Overdue = has a due date in the past and isn't completed.
        var overdue: Bool?
        /// Due between now and now + N days (inclusive), not completed.
        var dueWithinDays: Int?
        /// Completed within the last N days (uses `completedAt`) — powers
        /// "done today / this week".
        var completedWithinDays: Int?
        /// Case-insensitive substring across title / notes / owner.
        var search: String?
        /// When false, completed tasks are excluded regardless of `statuses`.
        var includeCompleted: Bool

        init(statuses: Set<ActionItem.Status>? = nil,
             priorities: Set<ActionItem.Priority>? = nil,
             labelIDs: Set<String>? = nil,
             ownerPersonID: String? = nil,
             overdue: Bool? = nil,
             dueWithinDays: Int? = nil,
             completedWithinDays: Int? = nil,
             search: String? = nil,
             includeCompleted: Bool = true) {
            self.statuses = statuses
            self.priorities = priorities
            self.labelIDs = labelIDs
            self.ownerPersonID = ownerPersonID
            self.overdue = overdue
            self.dueWithinDays = dueWithinDays
            self.completedWithinDays = completedWithinDays
            self.search = search
            self.includeCompleted = includeCompleted
        }
    }

    enum SortKey: String, Codable, Hashable, Sendable {
        case smart      // completed last, then due, then priority, then recency
        case priority
        case due
        case created
        case updated
        case title
        case manual     // sortIndex (board ordering)
    }

    var scope: Scope = .all
    var filters = Filters()
    var sort: SortKey = .smart
    var ascending = false
    var limit: Int?

    init(scope: Scope = .all, filters: Filters = Filters(),
         sort: SortKey = .smart, ascending: Bool = false, limit: Int? = nil) {
        self.scope = scope
        self.filters = filters
        self.sort = sort
        self.ascending = ascending
        self.limit = limit
    }
}

/// Pure evaluator for a `TaskQuery`. One code path for every view, badge, and
/// agent so filter/sort logic stops drifting across files.
enum TaskQueryEngine {

    static func evaluate(_ query: TaskQuery, over items: [ActionItem],
                         now: Date = Date()) -> [ActionItem] {
        var result = items.filter { matches($0, query, now: now) }
        if query.sort == .smart {
            // The composite "useful default" order; the ascending flag doesn't
            // apply (it isn't a single axis).
            result.sort { smartLess($0, $1) }
        } else {
            // `ascendingLess` is the natural ascending comparator for the key;
            // descending just swaps the operands.
            result.sort { a, b in
                query.ascending ? ascendingLess(a, b, query.sort)
                                 : ascendingLess(b, a, query.sort)
            }
        }
        if let limit = query.limit, result.count > limit {
            result = Array(result.prefix(limit))
        }
        return result
    }

    // MARK: Filtering

    static func matches(_ item: ActionItem, _ query: TaskQuery, now: Date) -> Bool {
        // Soft-deleted tasks are never returned (defence in depth — the store
        // already keeps them in a separate array).
        if item.isTrashed { return false }

        // Scope
        switch query.scope {
        case .all: break
        case .project(let id): if item.projectID != id { return false }
        case .noProject: if item.projectID != nil { return false }
        case .anyProjects(let ids):
            guard let pid = item.projectID, ids.contains(pid) else { return false }
        case .person(let id): if item.ownerPersonID != id { return false }
        case .meeting(let id): if item.meetingID != id { return false }
        case .context(let id): if item.contextID != id { return false }
        case .initiative:
            // Pre-resolved to `.anyProjects` by ActionItemStore.tasks(matching:);
            // if it ever reaches the pure engine unresolved, match nothing rather
            // than silently returning everything.
            return false
        }

        let f = query.filters
        if !f.includeCompleted, item.status == .completed { return false }
        if let statuses = f.statuses, !statuses.contains(item.status) { return false }
        if let priorities = f.priorities, !priorities.contains(item.priority) { return false }
        if let labels = f.labelIDs {
            let itemLabels = Set(item.labels)
            if !labels.isSubset(of: itemLabels) { return false }
        }
        if let owner = f.ownerPersonID, item.ownerPersonID != owner { return false }
        if f.overdue == true {
            guard let due = item.dueDate, due < now, item.status != .completed else { return false }
        }
        if let days = f.dueWithinDays {
            guard let due = item.dueDate, item.status != .completed else { return false }
            let horizon = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
            if due < now || due > horizon { return false }
        }
        if let days = f.completedWithinDays {
            guard let done = item.completedAt else { return false }
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
            if done < cutoff { return false }
        }
        if let raw = f.search?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let needle = raw.lowercased()
            let haystack = [item.title, item.notes ?? "", item.owner ?? ""].joined(separator: " ").lowercased()
            if !haystack.contains(needle) { return false }
        }
        return true
    }

    // MARK: Sorting

    /// The composite default order: completed sinks, then soonest due (nil
    /// last), then higher priority, then more-recently updated.
    static func smartLess(_ a: ActionItem, _ b: ActionItem) -> Bool {
        if a.status == .completed && b.status != .completed { return false }
        if b.status == .completed && a.status != .completed { return true }
        switch (a.dueDate, b.dueDate) {
        case (let x?, let y?): if x != y { return x < y }
        case (nil, _?): return false
        case (_?, nil): return true
        default: break
        }
        if a.priority.weight != b.priority.weight { return a.priority.weight > b.priority.weight }
        return a.updatedAt > b.updatedAt
    }

    /// `true` iff `a` precedes `b` in the *natural ascending* order for `key`.
    /// `evaluate` swaps the operands to get descending, so one definition drives
    /// both directions consistently across every key.
    static func ascendingLess(_ a: ActionItem, _ b: ActionItem, _ key: TaskQuery.SortKey) -> Bool {
        switch key {
        case .smart:
            return smartLess(a, b)   // not reached (handled in evaluate)
        case .priority:
            if a.priority.weight != b.priority.weight { return a.priority.weight < b.priority.weight }
            return a.updatedAt < b.updatedAt
        case .due:
            switch (a.dueDate, b.dueDate) {
            case (let x?, let y?): if x != y { return x < y }
            case (nil, _?): return false   // no due date sorts last in ascending
            case (_?, nil): return true
            default: break
            }
            return a.updatedAt < b.updatedAt
        case .created: return a.createdAt < b.createdAt
        case .updated: return a.updatedAt < b.updatedAt
        case .title:
            let cmp = a.title.localizedCaseInsensitiveCompare(b.title)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return a.id < b.id
        case .manual:
            let ai = a.sortIndex ?? .greatestFiniteMagnitude
            let bi = b.sortIndex ?? .greatestFiniteMagnitude
            if ai != bi { return ai < bi }
            return a.updatedAt < b.updatedAt
        }
    }
}
