import Foundation
import SwiftUI
import VaultKit
import OSLog

/// Persists ActionItem state to `<storageDir>/action_items.json` and
/// publishes it for SwiftUI. Single source of truth; the Action Items tab,
/// Today widget, ChatTools, and MCP server all read from here.
@MainActor
final class ActionItemStore: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "ActionItems")

    /// Live tasks (deletedAt == nil). Every existing consumer binds to this and
    /// continues to see only non-deleted items.
    @Published private(set) var items: [ActionItem] = [] {
        didSet { rebuildItemIndex() }
    }

    /// O(1) `id → index` map into `items`, rebuilt whenever `items` changes
    /// (A0-4 / E1-2). Replaces the O(n) `items.firstIndex(where:)` scans that
    /// ran on every single-task mutation. Maintained via `items.didSet` so it
    /// can never drift out of sync with the array, no matter which mutation
    /// path (append, subscript-set, remove, wholesale assignment) ran.
    private var itemIndex: [String: Int] = [:]

    private func rebuildItemIndex() {
        itemIndex.removeAll(keepingCapacity: true)
        itemIndex.reserveCapacity(items.count)
        for (i, it) in items.enumerated() { itemIndex[it.id] = i }
    }
    /// Soft-deleted tasks awaiting restore or purge (P0-3). Persisted in the
    /// same action_items.json so Trash survives relaunch; partitioned off
    /// `items` by `deletedAt` on load.
    @Published private(set) var trashedItems: [ActionItem] = []
    @Published private(set) var projects: [Project] = []
    @Published private(set) var labels: [TaskLabel] = []
    @Published private(set) var sections: [ProjectSection] = []
    @Published private(set) var initiatives: [Initiative] = []
    /// Top-level life contexts (Work / Personal / …) — the #1 workspace
    /// partition (1-1). Seeded with two defaults on first launch.
    @Published private(set) var contexts: [WorkspaceContext] = []

    /// How long a soft-deleted task lingers in Trash before automatic purge.
    static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    /// Handle to the off-main initial decode, so callers (and tests) can await
    /// the first load before relying on the published arrays.
    private var loadTask: Task<Void, Never>?

    private var fileURL: URL {
        AppSettings.shared.storageDir.appendingPathComponent("action_items.json")
    }
    private var projectsURL: URL {
        AppSettings.shared.storageDir.appendingPathComponent("projects.json")
    }
    private var labelsURL: URL {
        AppSettings.shared.storageDir.appendingPathComponent("task_labels.json")
    }
    private var sectionsURL: URL {
        AppSettings.shared.storageDir.appendingPathComponent("project_sections.json")
    }
    private var initiativesURL: URL {
        AppSettings.shared.storageDir.appendingPathComponent("initiatives.json")
    }
    private var contextsURL: URL {
        AppSettings.shared.storageDir.appendingPathComponent("contexts.json")
    }

    init() {
        // Load OFF the main thread. Each `Data(contentsOf:)` below blocks, and
        // on a machine where every file open is intercepted by a scanner this
        // stalled app launch ("failing to open"). Read + decode on a background
        // task, then publish the arrays back on the main actor.
        let itemsURL = fileURL, projURL = projectsURL, lblURL = labelsURL
        let secURL = sectionsURL, initURL = initiativesURL, ctxURL = contextsURL
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            let allItems: [ActionItem]     = Self.decodeArray(itemsURL, version: Self.actionItemSchemaVersion,
                                                              migrate: TaskSchemaMigrations.actionItems)
            let projects: [Project]        = Self.decodeArray(projURL, version: Self.projectSchemaVersion,
                                                              migrate: TaskSchemaMigrations.projects)
            let labels: [TaskLabel]        = Self.decodeArray(lblURL, version: Self.labelSchemaVersion,
                                                              migrate: TaskSchemaMigrations.labels)
            let sections: [ProjectSection] = Self.decodeArray(secURL, version: Self.sectionSchemaVersion,
                                                              migrate: TaskSchemaMigrations.sections)
            let initiatives: [Initiative]  = Self.decodeArray(initURL, version: Self.initiativeSchemaVersion,
                                                              migrate: TaskSchemaMigrations.initiatives)
            let fileExists = (try? ctxURL.checkResourceIsReachable()) ?? false
            let contexts: [WorkspaceContext] = Self.decodeArray(ctxURL, version: Self.contextSchemaVersion)
            // Partition tasks into live vs. trashed by the soft-delete tombstone.
            let live    = allItems.filter { $0.deletedAt == nil }
            let trashed = allItems.filter { $0.deletedAt != nil }
            await MainActor.run {
                guard let self else { return }
                self.items = live
                self.trashedItems = trashed
                self.projects = projects
                self.labels = labels
                self.sections = sections
                self.initiatives = initiatives
                // First launch (no contexts.json yet) seeds Work + Personal (1-1).
                if !fileExists && contexts.isEmpty {
                    self.contexts = WorkspaceContext.seedDefaults()
                    self.saveContexts()
                } else {
                    self.contexts = contexts
                }
                // Bound the Trash on launch (drops items past the retention
                // window; only writes if something was actually purged).
                self.purgeExpiredTrash()
            }
        }
    }

    /// Awaits the off-main initial decode. Useful for tests (mutate
    /// deterministically after load) and for any caller that must not race the
    /// first publish. No-op once the load has completed.
    func awaitInitialLoad() async {
        await loadTask?.value
    }

    /// Off-main read + decode of one schema-enveloped JSON array. Returns [] on
    /// any failure — matches the old per-loader behavior. When the on-disk
    /// version is older than `version`, the file is backed up and `migrate`
    /// transforms the payload (P0-5 / BE-18); with no version skew `migrate` is
    /// never invoked, so today's pinned-at-1 files decode exactly as before.
    nonisolated private static func decodeArray<T: Codable>(
        _ url: URL, version: Int,
        migrate: ((_ payload: [T], _ from: Int, _ to: Int) -> [T])? = nil
    ) -> [T] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let wrapped: (([T], Int, Int) -> [T])? = migrate.map { m in
            { payload, from, to in
                TaskSchemaMigrations.backupBeforeMigration(url, from: from, to: to)
                return m(payload, from, to)
            }
        }
        guard let arr: [T] = try? SchemaEnvelope.decode(
            [T].self, from: data,
            currentVersion: version,
            decoder: SharedCoders.decoder(),
            migrate: wrapped)
        else { return [] }
        return arr
    }

    // MARK: - Read

    /// Items belonging to a specific meeting.
    func items(for meetingID: String) -> [ActionItem] {
        items.filter { $0.meetingID == meetingID }
            .sorted { ($0.priority.weight, $0.createdAt) > ($1.priority.weight, $1.createdAt) }
    }

    /// Items linked to a project.
    func items(forProject projectID: String) -> [ActionItem] {
        items.filter { $0.projectID == projectID }
            .sorted { ($0.priority.weight, $0.createdAt) > ($1.priority.weight, $1.createdAt) }
    }

    func project(for item: ActionItem) -> Project? {
        guard let pid = item.projectID else { return nil }
        return projects.first { $0.id == pid }
    }

    func project(id: String) -> Project? {
        projects.first { $0.id == id }
    }

    /// Count of open items per project — used for the project list badges.
    func openCount(forProject projectID: String) -> Int {
        items.filter { $0.projectID == projectID && $0.status != .completed }.count
    }

    /// (done, total) live tasks for a project — drives a % complete indicator (VD-7).
    func completion(forProject projectID: String) -> (done: Int, total: Int) {
        let scoped = items.filter { $0.projectID == projectID }
        return (scoped.filter { $0.status == .completed }.count, scoped.count)
    }

    /// (done, total) across all of an initiative's projects (VD-7).
    func completion(forInitiative initiativeID: String) -> (done: Int, total: Int) {
        let pids = Set(projects.filter { $0.initiativeID == initiativeID }.map { $0.id })
        let scoped = items.filter { $0.projectID.map { pids.contains($0) } ?? false }
        return (scoped.filter { $0.status == .completed }.count, scoped.count)
    }

    /// Items whose source meeting was today or yesterday (any status).
    func todayAndYesterday(now: Date = Date()) -> [ActionItem] {
        let cal = Calendar.current
        // Exclude items still awaiting triage — meeting-extracted action items
        // only become "current tasks" once accepted in the Triage inbox.
        return items.filter { item in
            guard !item.needsTriage else { return false }
            return cal.isDateInToday(item.meetingDate) || cal.isDateInYesterday(item.meetingDate)
        }
        .sorted(by: defaultSort)
    }

    func openItems() -> [ActionItem] {
        items.filter { $0.status != .completed }.sorted(by: defaultSort)
    }

    /// Run a structured query over the live tasks (BE-7). The single composable
    /// read path that views, badges, saved views (Phase 2), and the agent API
    /// (Phase 6) converge on, replacing scattered bespoke filter/sort chains.
    func tasks(matching query: TaskQuery, now: Date = Date()) -> [ActionItem] {
        TaskQueryEngine.evaluate(query, over: items, now: now)
    }

    private func defaultSort(_ a: ActionItem, _ b: ActionItem) -> Bool {
        // Completed sinks to the bottom.
        if a.status == .completed && b.status != .completed { return false }
        if b.status == .completed && a.status != .completed { return true }
        // Then by due date (soonest first; nil last).
        switch (a.dueDate, b.dueDate) {
        case (let x?, let y?): if x != y { return x < y }
        case (nil, _?): return false
        case (_?, nil): return true
        default: break
        }
        // Then by priority.
        if a.priority.weight != b.priority.weight {
            return a.priority.weight > b.priority.weight
        }
        // Then by meeting recency.
        return a.meetingDate > b.meetingDate
    }

    // MARK: - Write

    /// Add a new item or update an existing one (matched by id).
    func upsert(_ item: ActionItem) {
        var updated = item
        updated.updatedAt = Date()
        if let idx = itemIndex[item.id] {
            items[idx] = updated
        } else {
            items.append(updated)
        }
        save()
    }

    /// Creates a brand-new manual task (not tied to any meeting). Optionally
    /// pre-assigned to a project / section and given a status.
    @discardableResult
    func createTask(title: String,
                    projectID: String? = nil,
                    sectionID: String? = nil,
                    status: ActionItem.Status = .open,
                    priority: ActionItem.Priority = .medium) -> ActionItem {
        let now = Date()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = ActionItem(
            id: UUID().uuidString,
            meetingID: "",                 // empty ⇒ isManual
            meetingTitle: "",
            meetingDate: now,
            title: trimmed.isEmpty ? "Untitled task" : trimmed,
            owner: nil,
            notes: nil,
            status: status,
            priority: priority,
            dueDate: nil,
            projectID: projectID,
            startDate: nil,
            labelIDs: nil,
            subtasks: nil,
            sectionID: sectionID,
            sortIndex: nextSortIndex(forStatus: status, projectID: projectID),
            source: "local",
            externalID: nil,
            externalURL: nil,
            notionPageID: nil,
            notionURL: nil,
            createdAt: now,
            updatedAt: now)
        items.append(item)
        save()
        TaskChangeLog.shared.record(.create, entity: .task, id: item.id,
                                    summary: "Created “\(item.title)”")
        return item
    }

    // MARK: - Push from a meeting (cross-tab integration)

    /// A lightweight task spec so a caller (a meeting's notes / action items,
    /// the chat rail, etc.) can push work into Tasks without building a full
    /// `ActionItem`.
    struct TaskDraft {
        var title: String
        var owner: String? = nil
        var dueDate: Date? = nil
        var notes: String? = nil
        var priority: ActionItem.Priority = .medium
    }

    /// `source` tag for tasks the user explicitly pushed from a meeting. Kept
    /// distinct from extracted (`nil`) and manual (`"local"`) so
    /// `reconcileExtracted` never deletes a pushed task when its meeting is
    /// re-transcribed.
    static let pushedSource = "push"

    /// Create meeting-linked tasks from a batch of drafts — the engine behind
    /// "Push to Tasks" on a call's notes / action items. Deduped by signature
    /// (meeting + normalized title) against both live and trashed items, so
    /// re-pushing the same line is a no-op. Returns only the newly-created
    /// tasks (empty when everything was already present).
    @discardableResult
    func addTasks(_ drafts: [TaskDraft],
                  fromMeetingID meetingID: String,
                  meetingTitle: String,
                  meetingDate: Date,
                  projectID: String? = nil) -> [ActionItem] {
        let live = Set(items.filter { $0.meetingID == meetingID }.map { $0.signature })
        let trashed = Set(trashedItems.filter { $0.meetingID == meetingID }.map { $0.signature })
        var seen = Set<String>()
        var created: [ActionItem] = []
        let now = Date()
        for draft in drafts {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let signature = "\(meetingID)::\(title.lowercased())"
            guard !live.contains(signature), !trashed.contains(signature),
                  seen.insert(signature).inserted else { continue }
            var item = ActionItem(
                id: UUID().uuidString,
                meetingID: meetingID,
                meetingTitle: meetingTitle,
                meetingDate: meetingDate,
                title: title,
                owner: draft.owner,
                notes: draft.notes,
                status: .open,
                priority: draft.priority,
                dueDate: draft.dueDate,
                projectID: projectID,
                startDate: nil,
                labelIDs: nil,
                subtasks: nil,
                sectionID: nil,
                sortIndex: nextSortIndex(forStatus: .open, projectID: projectID),
                source: Self.pushedSource,
                externalID: nil,
                externalURL: nil,
                notionPageID: nil,
                notionURL: nil,
                createdAt: now,
                updatedAt: now)
            // Pushed tasks are user-authored → confirmed, never in triage.
            item.confirmedAt = now
            items.append(item)
            created.append(item)
        }
        if let first = created.first {
            save()
            TaskChangeLog.shared.record(.create, entity: .task, id: first.id,
                summary: created.count == 1
                    ? "Pushed “\(first.title)” to Tasks"
                    : "Pushed \(created.count) tasks from “\(meetingTitle)”")
        }
        return created
    }

    // MARK: - Triage inbox & smart views (redesign §5B / §5C)

    /// Meeting-extracted items still awaiting review — the Triage inbox source.
    /// Soonest-due first, then newest. Excludes confirmed, completed, trashed.
    var pendingTriage: [ActionItem] {
        items.filter { $0.needsTriage }
            .sorted { a, b in
                let da = a.dueDate ?? .distantFuture, db = b.dueDate ?? .distantFuture
                return da != db ? da < db : a.createdAt > b.createdAt   // soonest-due, then newest
            }
    }

    /// Confirm one or more items out of triage (optionally filing them under a
    /// project). Idempotent — already-confirmed items keep their timestamp.
    func confirm(ids: [String], projectID: String? = nil) {
        guard !ids.isEmpty else { return }
        let now = Date()
        var changed = false
        let idSet = Set(ids)
        for i in items.indices where idSet.contains(items[i].id) {
            if items[i].confirmedAt == nil { items[i].confirmedAt = now; changed = true }
            if let projectID { items[i].projectID = projectID; changed = true }
            if changed { items[i].updatedAt = now }
        }
        if changed { save() }
    }

    func confirm(_ id: String, projectID: String? = nil) { confirm(ids: [id], projectID: projectID) }

    /// Confirm every item currently in the triage inbox. Returns the count moved.
    @discardableResult
    func confirmAllTriage() -> Int {
        let ids = pendingTriage.map(\.id)
        confirm(ids: ids)
        return ids.count
    }

    /// Tasks that belong in the regular workspace: active, not awaiting triage.
    private var workspaceTasks: [ActionItem] { items.filter { !$0.needsTriage } }

    /// Overdue: due before today and not completed.
    var overdueTasks: [ActionItem] {
        let start = Calendar.current.startOfDay(for: Date())
        return workspaceTasks.filter {
            $0.status != .completed && ($0.dueDate.map { $0 < start } ?? false)
        }
    }

    /// My day: due today (and not completed).
    var myDayTasks: [ActionItem] {
        workspaceTasks.filter {
            $0.status != .completed && ($0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false)
        }
    }

    /// This week: due within the current calendar week (and not completed).
    var thisWeekTasks: [ActionItem] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return workspaceTasks.filter {
            $0.status != .completed && ($0.dueDate.map { week.contains($0) } ?? false)
        }
    }

    /// Split freeform note text into one task draft per non-empty line,
    /// stripping common markdown bullet / checkbox / numbering prefixes so
    /// "Push notes to Tasks" yields clean task titles.
    static func draftsFromNotes(_ text: String) -> [TaskDraft] {
        text.components(separatedBy: .newlines).compactMap { raw in
            var s = raw.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return nil }
            if let r = s.range(of: #"^([-*•]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+|#{1,6}\s+)"#,
                               options: .regularExpression) {
                s.removeSubrange(r)
            }
            s = s.trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? nil : TaskDraft(title: s)
        }
    }

    /// Creates a task from a one-line natural-language capture (P3-2): parses
    /// `!priority`, `#label`, and a date out of the string, applies them, and
    /// creates/links labels by name. Returns the freshly stored task.
    @discardableResult
    func createTask(parsing raw: String, projectID: String? = nil,
                    sectionID: String? = nil, now: Date = Date()) -> ActionItem {
        let parsed = TaskQuickAddParser.parse(raw, now: now)
        let fallback = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parsed.title.isEmpty ? fallback : parsed.title
        // +Project (2-3): when the caller didn't pin a project, fuzzy-match the
        // typed name against existing projects so the task self-routes.
        let resolvedProjectID = projectID ?? parsed.projectQuery.flatMap { fuzzyProjectID(matching: $0) }
        let created = createTask(title: title, projectID: resolvedProjectID, sectionID: sectionID,
                                 priority: parsed.priority ?? .medium)
        if let due = parsed.dueDate { setDueDate(created.id, dueDate: due) }
        for name in parsed.labelNames {
            let label = labels.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                ?? createLabel(name: name)
            toggleLabel(created.id, labelID: label.id)
        }
        // P2-8: @name / >name addresses the task to a real Person. Exact identity
        // match first, then a first-name / prefix match for the quick "@jane" case.
        if let token = parsed.ownerToken {
            let lc = token.lowercased()
            let people = PeopleStore.shared.people
            let match = PersonResolver.resolve(token, in: people).flatMap { id in people.first { $0.id == id } }
                ?? people.first { $0.displayName.lowercased().hasPrefix(lc) }
                ?? people.first { ($0.displayName.split(separator: " ").first.map(String.init)?.lowercased() ?? "") == lc }
            if let m = match {
                setOwnerPerson(created.id, personID: m.id, ownerName: m.displayName)
            } else {
                setOwner(created.id, owner: token)   // keep the typed name even if unresolved
            }
            if parsed.delegated { update(created.id) { $0.delegated = true } }
        }
        return items.first { $0.id == created.id } ?? created
    }

    /// Merges a batch of tasks imported from an external system (Linear /
    /// Notion), deduped by (source, externalID) — or by notionPageID for
    /// items we previously pushed. Local-only fields (projectID, sectionID,
    /// labels, subtasks, sortIndex) are preserved on update. Project names are
    /// mirrored into local Projects. Returns the count of newly-created tasks.
    @discardableResult
    func mergeExternal(source: String, tasks: [ExternalTask], assignProjectID: String? = nil) -> Int {
        var created = 0
        for t in tasks {
            let projectID: String? = assignProjectID ?? t.projectName.flatMap { resolveProjectID(named: $0) }
            if let idx = items.firstIndex(where: {
                ($0.source == source && $0.externalID == t.externalID)
                || ($0.notionPageID != nil && $0.notionPageID == t.externalID)
            }) {
                var it = items[idx]
                it.title = t.title
                if let n = t.notes { it.notes = n }
                it.status = t.status
                it.priority = t.priority
                it.dueDate = t.dueDate
                if let o = t.owner { it.owner = o }
                it.externalURL = t.externalURL
                if it.source == nil || it.source == "local" || it.source == "meeting" {
                    // adopt the external source so future syncs match by it
                    it.source = source
                    it.externalID = t.externalID
                }
                // A project-scoped import re-homes the task; otherwise keep
                // an existing project assignment.
                if let forced = assignProjectID { it.projectID = forced }
                else if it.projectID == nil { it.projectID = projectID }
                it.updatedAt = Date()
                items[idx] = it
            } else {
                let now = Date()
                let it = ActionItem(
                    id: UUID().uuidString, meetingID: "", meetingTitle: "", meetingDate: now,
                    title: t.title, owner: t.owner, notes: t.notes,
                    status: t.status, priority: t.priority, dueDate: t.dueDate,
                    projectID: projectID, startDate: nil, labelIDs: nil, subtasks: nil,
                    sectionID: nil, sortIndex: nil, source: source,
                    externalID: t.externalID, externalURL: t.externalURL,
                    notionPageID: nil, notionURL: nil, createdAt: now, updatedAt: now)
                items.append(it)
                created += 1
            }
        }
        save(); saveProjects()
        if !tasks.isEmpty {
            TaskChangeLog.shared.record(.merge, entity: .task, id: source,
                                        summary: "Imported \(created) new task(s) from \(source)")
        }
        return created
    }

    /// Fuzzy-resolves a typed `+Project` token to an existing project id (2-3):
    /// exact (case-insensitive) → prefix → substring. Returns nil if nothing
    /// reasonable matches (the task just stays unfiled).
    func fuzzyProjectID(matching query: String) -> String? {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        if let exact = projects.first(where: { $0.name.lowercased() == q }) { return exact.id }
        if let prefix = projects.first(where: { $0.name.lowercased().hasPrefix(q) }) { return prefix.id }
        if let contains = projects.first(where: { $0.name.lowercased().contains(q) }) { return contains.id }
        return nil
    }

    /// Finds a project by exact name, creating one if needed (no extra save —
    /// the caller saves once at the end of the batch).
    private func resolveProjectID(named name: String) -> String {
        if let p = projects.first(where: { $0.name == name }) { return p.id }
        let p = Project(name: name)
        projects.append(p)
        return p.id
    }

    /// Smallest sort weight for the head of a status column (so a new task
    /// lands at the top). Items sort ascending by sortIndex.
    func nextSortIndex(forStatus status: ActionItem.Status, projectID: String?) -> Double {
        let peers = items.filter {
            $0.status == status && (projectID == nil || $0.projectID == projectID)
        }
        let minIdx = peers.compactMap { $0.sortIndex }.min() ?? 0
        return minIdx - 1
    }

    func setStartDate(_ id: String, startDate: Date?) {
        update(id) { $0.startDate = startDate }
    }
    func setSortIndex(_ id: String, sortIndex: Double) {
        update(id) { $0.sortIndex = sortIndex }
    }

    // MARK: - Subtasks

    func addSubtask(_ id: String, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        update(id) { $0.subtasks = ($0.subtasks ?? []) + [Subtask(title: t)] }
    }
    func toggleSubtask(_ id: String, subtaskID: String) {
        update(id) { item in
            guard var subs = item.subtasks,
                  let i = subs.firstIndex(where: { $0.id == subtaskID }) else { return }
            subs[i].done.toggle()
            item.subtasks = subs
        }
    }
    func setSubtaskTitle(_ id: String, subtaskID: String, title: String) {
        update(id) { item in
            guard var subs = item.subtasks,
                  let i = subs.firstIndex(where: { $0.id == subtaskID }) else { return }
            subs[i].title = title
            item.subtasks = subs
        }
    }
    func deleteSubtask(_ id: String, subtaskID: String) {
        update(id) { item in
            item.subtasks = (item.subtasks ?? []).filter { $0.id != subtaskID }
        }
    }

    // MARK: - Labels

    @discardableResult
    func createLabel(name: String, colorHex: String? = nil) -> TaskLabel {
        let color = colorHex ?? TaskLabel.palette[labels.count % TaskLabel.palette.count]
        let label = TaskLabel(name: name.isEmpty ? "Label" : name, colorHex: color)
        labels.append(label)
        saveLabels()
        return label
    }
    func renameLabel(_ id: String, name: String) {
        guard let i = labels.firstIndex(where: { $0.id == id }) else { return }
        labels[i].name = name; saveLabels()
    }
    func setLabelColor(_ id: String, colorHex: String) {
        guard let i = labels.firstIndex(where: { $0.id == id }) else { return }
        labels[i].colorHex = colorHex; saveLabels()
    }
    func deleteLabel(_ id: String) {
        labels.removeAll { $0.id == id }
        for i in items.indices {
            if let ids = items[i].labelIDs, ids.contains(id) {
                items[i].labelIDs = ids.filter { $0 != id }
                items[i].updatedAt = Date()
            }
        }
        saveLabels(); save()
    }
    func label(id: String) -> TaskLabel? { labels.first { $0.id == id } }
    func labels(for item: ActionItem) -> [TaskLabel] {
        item.labels.compactMap { id in labels.first { $0.id == id } }
    }
    func toggleLabel(_ id: String, labelID: String) {
        update(id) { item in
            var ids = item.labelIDs ?? []
            if let idx = ids.firstIndex(of: labelID) { ids.remove(at: idx) } else { ids.append(labelID) }
            item.labelIDs = ids
        }
    }

    // MARK: - Sections

    func sections(forProject projectID: String) -> [ProjectSection] {
        sections.filter { $0.projectID == projectID }.sorted { $0.sortIndex < $1.sortIndex }
    }
    @discardableResult
    func createSection(projectID: String, name: String) -> ProjectSection {
        let nextIdx = (sections(forProject: projectID).last?.sortIndex ?? 0) + 1
        let s = ProjectSection(projectID: projectID,
                               name: name.isEmpty ? "New section" : name,
                               sortIndex: nextIdx)
        sections.append(s)
        saveSections()
        return s
    }
    func renameSection(_ id: String, name: String) {
        guard let i = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[i].name = name; saveSections()
    }
    func deleteSection(_ id: String) {
        sections.removeAll { $0.id == id }
        for i in items.indices where items[i].sectionID == id {
            items[i].sectionID = nil
            items[i].updatedAt = Date()
        }
        saveSections(); save()
    }
    func setSection(_ id: String, sectionID: String?) {
        update(id) { $0.sectionID = sectionID }
    }

    // MARK: - Initiatives (top tier)

    func initiative(id: String) -> Initiative? { initiatives.first { $0.id == id } }

    /// Initiatives in display order. Archived ones are hidden by default (P0-4)
    /// so the rail leads with active work; pass `includeArchived: true` for the
    /// "Show archived" affordance.
    func sortedInitiatives(includeArchived: Bool = false) -> [Initiative] {
        initiatives
            .filter { includeArchived || $0.status == .active }
            .sorted {
                let a = $0.sortIndex ?? Double($0.createdAt.timeIntervalSince1970)
                let b = $1.sortIndex ?? Double($1.createdAt.timeIntervalSince1970)
                return a < b
            }
    }

    /// Archived initiatives only, in display order (P0-4 "Show archived").
    func archivedInitiatives() -> [Initiative] {
        sortedInitiatives(includeArchived: true).filter { $0.status == .archived }
    }

    @discardableResult
    func createInitiative(name: String, icon: String? = "flag.fill") -> Initiative {
        let next = (sortedInitiatives().last?.sortIndex ?? 0) + 1
        let i = Initiative(name: name.isEmpty ? "Untitled initiative" : name, icon: icon, sortIndex: next)
        initiatives.append(i)
        saveInitiatives()
        return i
    }
    func renameInitiative(_ id: String, name: String) { updateInitiative(id) { $0.name = name } }
    func setInitiativeIcon(_ id: String, icon: String?) { updateInitiative(id) { $0.icon = icon } }
    func setInitiativeBody(_ id: String, body: String) { updateInitiative(id) { $0.body = body } }
    func setInitiativeStatus(_ id: String, status: Initiative.Status) { updateInitiative(id) { $0.status = status } }
    func deleteInitiative(_ id: String) {
        initiatives.removeAll { $0.id == id }
        for i in projects.indices where projects[i].initiativeID == id {
            projects[i].initiativeID = nil
            projects[i].updatedAt = Date()
        }
        saveInitiatives(); saveProjects()
    }
    private func updateInitiative(_ id: String, mutate: (inout Initiative) -> Void) {
        guard let idx = initiatives.firstIndex(where: { $0.id == id }) else { return }
        var copy = initiatives[idx]; mutate(&copy); copy.updatedAt = Date()
        initiatives[idx] = copy; saveInitiatives()
    }

    /// Top-level projects (parentID == nil) belonging to an initiative.
    func projects(forInitiative initiativeID: String) -> [Project] {
        childProjects(of: nil).filter { $0.initiativeID == initiativeID }
    }
    /// Top-level projects with no initiative. Archived pages are hidden by
    /// default (P0-4); pass `includeArchived: true` for "Show archived".
    func standaloneTopProjects(includeArchived: Bool = false) -> [Project] {
        childProjects(of: nil).filter {
            $0.initiativeID == nil && (includeArchived || $0.status == .active)
        }
    }

    /// Archived top-level standalone pages only (P0-4 "Show archived").
    func archivedTopProjects() -> [Project] {
        standaloneTopProjects(includeArchived: true).filter { $0.status == .archived }
    }
    func setProjectInitiative(_ id: String, initiativeID: String?) {
        updateProject(id) { $0.initiativeID = initiativeID }
    }
    /// Open task count across an initiative's projects (and their sub-pages).
    func openCount(forInitiative initiativeID: String) -> Int {
        let projectIDs = Set(projects.filter { $0.initiativeID == initiativeID }.map { $0.id })
        return items.filter { ($0.projectID.map { projectIDs.contains($0) } ?? false) && $0.status != .completed }.count
    }

    // MARK: - Workspace contexts (Work / Personal / …) — 1-1

    func context(id: String) -> WorkspaceContext? { contexts.first { $0.id == id } }

    /// Contexts in display order (by sortIndex, then creation).
    func sortedContexts() -> [WorkspaceContext] {
        contexts.sorted {
            let a = $0.sortIndex ?? Double($0.createdAt.timeIntervalSince1970)
            let b = $1.sortIndex ?? Double($1.createdAt.timeIntervalSince1970)
            return a < b
        }
    }

    @discardableResult
    func createContext(name: String, colorHex: String? = nil) -> WorkspaceContext {
        let next = (sortedContexts().last?.sortIndex ?? 0) + 1
        let palette = ["#4F8DFD", "#34C759", "#FF9500", "#AF52DE", "#FF2D55", "#5AC8FA"]
        let c = WorkspaceContext(name: name.isEmpty ? "New context" : name,
                                 colorHex: colorHex ?? palette[contexts.count % palette.count],
                                 sortIndex: next)
        contexts.append(c)
        saveContexts()
        return c
    }

    func renameContext(_ id: String, name: String) {
        guard let i = contexts.firstIndex(where: { $0.id == id }) else { return }
        contexts[i].name = name; saveContexts()
    }
    func setContextColor(_ id: String, colorHex: String) {
        guard let i = contexts.firstIndex(where: { $0.id == id }) else { return }
        contexts[i].colorHex = colorHex; saveContexts()
    }

    /// Removes a context and detaches everything that pointed at it (initiatives
    /// and any directly-tagged tasks) so nothing references a dead id.
    func deleteContext(_ id: String) {
        contexts.removeAll { $0.id == id }
        var changedInit = false
        for i in initiatives.indices where initiatives[i].contextID == id {
            initiatives[i].contextID = nil; initiatives[i].updatedAt = Date(); changedInit = true
        }
        var changedItems = false
        for i in items.indices where items[i].contextID == id {
            items[i].contextID = nil; items[i].updatedAt = Date(); changedItems = true
        }
        saveContexts()
        if changedInit { saveInitiatives() }
        if changedItems { save() }
    }

    /// Set (or clear) a task's direct context override.
    func setContext(_ itemID: String, contextID: String?) {
        update(itemID) { $0.contextID = contextID }
    }
    /// Set (or clear) an initiative's context — tasks inherit it via their project.
    func setInitiativeContext(_ initiativeID: String, contextID: String?) {
        updateInitiative(initiativeID) { $0.contextID = contextID }
    }

    /// The context a task effectively belongs to: its own override if set, else
    /// inherited from its project's initiative (1-1 / 1-5).
    func effectiveContextID(for item: ActionItem) -> String? {
        if let direct = item.contextID { return direct }
        guard let pid = item.projectID,
              let iid = projects.first(where: { $0.id == pid })?.initiativeID else { return nil }
        return initiatives.first { $0.id == iid }?.contextID
    }

    /// SwiftUI color for a task's effective context, or nil when uncontextualized
    /// — drives the row left-bar and Kanban card stripe (1-5).
    func contextColor(for item: ActionItem) -> Color? {
        guard let cid = effectiveContextID(for: item),
              let hex = context(id: cid)?.colorHex else { return nil }
        return Color(hex: hex)
    }
    /// SwiftUI color for a context id (used by the sidebar switcher pills).
    func contextColor(id: String) -> Color? {
        guard let hex = context(id: id)?.colorHex else { return nil }
        return Color(hex: hex)
    }

    // MARK: - Project ↔ meeting links

    func meetingIDs(forProject id: String) -> [String] {
        projects.first { $0.id == id }?.meetingIDs ?? []
    }
    func linkMeeting(_ meetingID: String, toProject id: String) {
        updateProject(id) { p in
            var ids = p.meetingIDs ?? []
            if !ids.contains(meetingID) { ids.append(meetingID) }
            p.meetingIDs = ids
        }
    }
    func unlinkMeeting(_ meetingID: String, fromProject id: String) {
        updateProject(id) { p in
            p.meetingIDs = (p.meetingIDs ?? []).filter { $0 != meetingID }
        }
    }
    func setProjectLinearID(_ id: String, linearProjectID: String?) {
        updateProject(id) { $0.linearProjectID = linearProjectID }
    }

    /// Bulk-merge a freshly-extracted batch for a meeting. Existing items
    /// with the same signature keep their user-edited fields (status,
    /// priority, dueDate, notes, notionPageID) — only the meeting metadata
    /// gets refreshed. New signatures get appended. Items previously
    /// extracted for this meeting that NO LONGER appear in the batch are
    /// kept (we don't want to nuke user-added items) unless their notes are
    /// empty and they're still in the .open state.
    func reconcileExtracted(_ extracted: [ActionItem], for meetingID: String) {
        var bySignature: [String: ActionItem] = [:]
        // Only reconcile EXTRACTED items. Tasks the user pushed from this
        // meeting (source == pushedSource) are user-authored, not extractor
        // output, so they must survive a re-extract untouched.
        for i in items where i.meetingID == meetingID && i.source != Self.pushedSource {
            bySignature[i.signature] = i
        }
        // Respect deletions: if the user trashed an extracted task, don't let a
        // re-extract resurrect it as a fresh live duplicate.
        let trashedSignatures = Set(trashedItems.filter { $0.meetingID == meetingID }.map { $0.signature })

        // Preserve everything from other meetings AND pushed tasks from this one.
        var nextItems: [ActionItem] = items.filter {
            $0.meetingID != meetingID || $0.source == Self.pushedSource
        }
        var seenSignatures = Set<String>()

        for ext in extracted {
            seenSignatures.insert(ext.signature)
            if trashedSignatures.contains(ext.signature) { continue }
            if var existing = bySignature[ext.signature] {
                // Preserve user-edited fields; refresh meeting metadata.
                existing.meetingTitle = ext.meetingTitle
                existing.meetingDate = ext.meetingDate
                existing.owner = existing.owner ?? ext.owner
                if existing.dueDate == nil { existing.dueDate = ext.dueDate }
                existing.updatedAt = Date()
                nextItems.append(existing)
            } else {
                nextItems.append(ext)
            }
        }

        // Keep stale items only if user touched them (non-default status
        // OR non-empty notes OR pushed to Notion).
        let stale = bySignature.values.filter { !seenSignatures.contains($0.signature) }
        for s in stale {
            let userTouched = s.status != .open
                || (s.notes?.isEmpty == false)
                || s.notionPageID != nil
                || s.priority != .medium
                || s.dueDate != nil
                || s.confirmedAt != nil          // confirmed out of triage → keep
            if userTouched { nextItems.append(s) }
        }

        items = nextItems
        save()
    }

    /// Soft-delete a task: move it to Trash (recoverable) rather than destroying
    /// it (P0-3). Replaces the old hard remove so a misclick — from a row menu,
    /// the task page, a board card, or a bulk action — is never unrecoverable.
    func delete(_ id: String) {
        moveToTrash(ids: [id])
    }

    /// Soft-delete several tasks in one write (bulk delete). Returns the ids that
    /// were actually trashed, so callers can offer a single "Undo".
    @discardableResult
    func delete(ids: [String]) -> [String] {
        moveToTrash(ids: ids)
    }

    @discardableResult
    private func moveToTrash(ids: [String]) -> [String] {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return [] }
        let now = Date()
        var moved: [String] = []
        // Iterate back-to-front so removals don't shift unseen indices.
        for idx in items.indices.reversed() where idSet.contains(items[idx].id) {
            var it = items.remove(at: idx)
            it.deletedAt = now
            it.updatedAt = now
            trashedItems.append(it)
            moved.append(it.id)
        }
        guard !moved.isEmpty else { return [] }
        save()
        for mid in moved {
            TaskChangeLog.shared.record(.delete, entity: .task, id: mid, summary: "Moved to Trash")
        }
        return moved
    }

    /// Restore a single trashed task back to the live list (the toast "Undo").
    @discardableResult
    func restore(_ id: String) -> Bool {
        !restore(ids: [id]).isEmpty
    }

    /// Restore several trashed tasks at once (bulk undo). Returns restored ids.
    @discardableResult
    func restore(ids: [String]) -> [String] {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return [] }
        let now = Date()
        var restored: [String] = []
        for idx in trashedItems.indices.reversed() where idSet.contains(trashedItems[idx].id) {
            var it = trashedItems.remove(at: idx)
            it.deletedAt = nil
            it.updatedAt = now
            items.append(it)
            restored.append(it.id)
        }
        guard !restored.isEmpty else { return [] }
        save()
        for rid in restored {
            TaskChangeLog.shared.record(.restore, entity: .task, id: rid, summary: "Restored from Trash")
        }
        return restored
    }

    /// Permanently remove one task from Trash (irreversible).
    func purge(_ id: String) {
        let before = trashedItems.count
        trashedItems.removeAll { $0.id == id }
        if trashedItems.count != before { save() }
    }

    /// Permanently empty the whole Trash (irreversible).
    func emptyTrash() {
        guard !trashedItems.isEmpty else { return }
        trashedItems.removeAll()
        save()
    }

    /// Drop trashed tasks whose tombstone is older than the retention window.
    /// Called on launch; safe to call anytime. Only persists if it changed.
    func purgeExpiredTrash(olderThan retention: TimeInterval = ActionItemStore.trashRetention,
                           now: Date = Date()) {
        let before = trashedItems.count
        trashedItems.removeAll { t in
            guard let deleted = t.deletedAt else { return false }
            return now.timeIntervalSince(deleted) > retention
        }
        if trashedItems.count != before { save() }
    }

    func setStatus(_ id: String, status: ActionItem.Status) {
        let wasCompleted = itemIndex[id].map { items[$0].status } == .completed
        update(id) {
            let was = $0.status == .completed
            $0.status = status
            // Stamp a real completion time (P2-4) — distinct from updatedAt,
            // which any edit bumps. Set on the open→completed transition, cleared
            // when reopened; re-completing keeps the original timestamp.
            if status == .completed {
                if !was { $0.completedAt = Date() }
            } else {
                $0.completedAt = nil
            }
        }
        // Spawn the next occurrence of a recurring task on first completion (P2-5).
        if status == .completed, !wasCompleted,
           let done = itemIndex[id].map({ items[$0] }), let rule = done.recurrence {
            spawnNextOccurrence(of: done, rule: rule)
        }
    }

    /// Set or clear a task's repeat rule (P2-5).
    func setRecurrence(_ id: String, _ rule: RecurrenceRule?) {
        update(id) { $0.recurrence = rule }
    }

    /// Creates the next instance of a recurring task when the current one is
    /// completed: a fresh open copy with the due (and start) dates rolled
    /// forward, subtasks reset, and external links cleared. The completed
    /// instance stays as history; instances share a `seriesID`.
    private func spawnNextOccurrence(of item: ActionItem, rule: RecurrenceRule) {
        let base = item.dueDate ?? item.startDate ?? Date()
        guard let nextDue = rule.next(after: base) else { return }
        var copy = item
        copy.id = UUID().uuidString
        copy.status = .open
        copy.completedAt = nil
        copy.dueDate = nextDue
        if let start = item.startDate, let due = item.dueDate {
            // Preserve the start→due offset on the new instance.
            copy.startDate = nextDue.addingTimeInterval(-due.timeIntervalSince(start))
        }
        copy.subtasks = item.subtasks?.map { var s = $0; s.done = false; return s }
        copy.seriesID = item.seriesID ?? item.id
        copy.notionPageID = nil; copy.notionURL = nil
        copy.externalID = nil; copy.externalURL = nil
        copy.createdAt = Date(); copy.updatedAt = Date()
        items.append(copy)
        save()
        TaskChangeLog.shared.record(.create, entity: .task, id: copy.id,
                                    summary: "Recurring: next “\(copy.title)”")
    }
    func setPriority(_ id: String, priority: ActionItem.Priority) {
        update(id) { $0.priority = priority }
    }
    func setDueDate(_ id: String, dueDate: Date?) {
        update(id) { $0.dueDate = dueDate }
    }
    func setEstimate(_ id: String, _ value: Double?) {
        update(id) { $0.estimate = value }
    }
    func setTitle(_ id: String, title: String) {
        update(id) { $0.title = title }
    }
    func setNotes(_ id: String, notes: String?) {
        update(id) { $0.notes = notes }
    }
    func setOwner(_ id: String, owner: String?) {
        update(id) { $0.owner = owner }
    }
    /// Set (or clear) the hard Person link plus the display name in one write.
    func setOwnerPerson(_ id: String, personID: String?, ownerName: String?) {
        update(id) {
            $0.ownerPersonID = personID
            $0.owner = ownerName
        }
    }
    /// Items hard-linked to a given person.
    func items(forPerson personID: String) -> [ActionItem] {
        items.filter { $0.ownerPersonID == personID }
    }
    func setNotion(_ id: String, pageID: String?, url: String?) {
        update(id) {
            $0.notionPageID = pageID
            $0.notionURL = url
        }
    }
    /// Records that this item was pushed to Linear. Mirrors `setNotion` but
    /// uses the generic external fields, so the imported-vs-pushed dedup model
    /// in `mergeExternal` keys on `(source, externalID)` as usual.
    func setLinear(_ id: String, issueID: String?, url: String?) {
        update(id) {
            $0.source = "linear"
            $0.externalID = issueID
            $0.externalURL = url
        }
    }
    func setProject(_ id: String, projectID: String?) {
        update(id) { $0.projectID = projectID }
    }

    // MARK: - Dependencies (PM-2)

    /// Add or remove `blockerID` as a blocker of `id`. Guards self-links and
    /// cycles (won't add an edge that would make the blocked-by graph circular).
    func toggleBlocker(_ id: String, blockerID: String) {
        guard id != blockerID else { return }
        let alreadyLinked = (itemIndex[id].flatMap { items[$0].blockedByIDs } ?? []).contains(blockerID)
        // Only run the cycle guard when adding a new edge.
        if !alreadyLinked && reachableViaBlockers(from: blockerID, target: id) { return }
        update(id) {
            var ids = $0.blockedByIDs ?? []
            if let idx = ids.firstIndex(of: blockerID) { ids.remove(at: idx) } else { ids.append(blockerID) }
            $0.blockedByIDs = ids.isEmpty ? nil : ids
        }
    }

    /// A task is blocked when it has at least one blocker that still exists and
    /// isn't completed.
    func isBlocked(_ item: ActionItem) -> Bool {
        guard let ids = item.blockedByIDs, !ids.isEmpty else { return false }
        return ids.contains { bid in
            itemIndex[bid].map { items[$0].status != .completed } ?? false
        }
    }

    /// The live blocker tasks for an item, in declared order.
    func blockers(for item: ActionItem) -> [ActionItem] {
        (item.blockedByIDs ?? []).compactMap { bid in itemIndex[bid].map { items[$0] } }
    }

    /// True if `target` is reachable by following `start`'s blockedBy chain.
    private func reachableViaBlockers(from start: String, target: String) -> Bool {
        var visited = Set<String>()
        var stack = [start]
        while let cur = stack.popLast() {
            if cur == target { return true }
            guard visited.insert(cur).inserted else { continue }
            if let i = itemIndex[cur] { stack.append(contentsOf: items[i].blockedByIDs ?? []) }
        }
        return false
    }

    private func update(_ id: String, mutate: (inout ActionItem) -> Void) {
        guard let idx = itemIndex[id] else { return }
        var copy = items[idx]
        mutate(&copy)
        copy.updatedAt = Date()
        items[idx] = copy
        save()
        TaskChangeLog.shared.record(.update, entity: .task, id: id,
                                    summary: "Updated “\(copy.title)”")
    }

    // MARK: - Projects

    @discardableResult
    func createProject(name: String, icon: String? = "doc.text", parentID: String? = nil) -> Project {
        let next = (childProjects(of: parentID).last?.sortIndex ?? 0) + 1
        let p = Project(name: name.isEmpty ? "Untitled" : name, icon: icon,
                        parentID: parentID, sortIndex: next)
        projects.append(p)
        saveProjects()
        return p
    }

    /// Direct child pages of a parent (nil = top-level), ordered.
    func childProjects(of parentID: String?) -> [Project] {
        projects.filter { $0.parentID == parentID }
            .sorted {
                let a = $0.sortIndex ?? Double($0.createdAt.timeIntervalSince1970)
                let b = $1.sortIndex ?? Double($1.createdAt.timeIntervalSince1970)
                return a < b
            }
    }

    func setProjectParent(_ id: String, parentID: String?) {
        // Guard against cycles (can't reparent under self or a descendant).
        guard id != parentID else { return }
        if let parentID, isDescendant(parentID, of: id) { return }
        updateProject(id) { $0.parentID = parentID }
    }

    private func isDescendant(_ candidate: String, of ancestor: String) -> Bool {
        var cur: String? = candidate
        var hops = 0
        while let c = cur, hops < 100 {
            if c == ancestor { return true }
            cur = projects.first { $0.id == c }?.parentID
            hops += 1
        }
        return false
    }

    /// Deleting a page reparents its children to its parent (so they aren't
    /// orphaned) and unlinks its tasks.
    func deleteProjectKeepingChildren(_ id: String) {
        let parent = projects.first { $0.id == id }?.parentID
        for i in projects.indices where projects[i].parentID == id {
            projects[i].parentID = parent
        }
        deleteProject(id)
    }

    func upsertProject(_ project: Project) {
        var p = project
        p.updatedAt = Date()
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = p
        } else {
            projects.append(p)
        }
        saveProjects()
    }

    func deleteProject(_ id: String) {
        projects.removeAll { $0.id == id }
        // Unlink any items that pointed at it.
        for i in items.indices where items[i].projectID == id {
            items[i].projectID = nil
            items[i].updatedAt = Date()
        }
        saveProjects()
        save()
    }

    // MARK: - Undoable deletes for projects / sections / initiatives (P0-3)
    //
    // These secondary entities aren't soft-deleted into a Trash array (only
    // tasks are); instead each delete returns a closure that reinstates the
    // entity AND the links it severed, so callers can offer an "Undo" toast —
    // the same safety net the People/Tags tabs use. Returns nil if the id is
    // already gone (caller skips the toast).

    /// Delete a project and return a closure that restores it and re-links the
    /// tasks it detached.
    func deleteProjectWithUndo(_ id: String) -> (() -> Void)? {
        guard let snapshot = projects.first(where: { $0.id == id }) else { return nil }
        let relinkItemIDs = items.filter { $0.projectID == id }.map(\.id)
        deleteProject(id)
        return { [weak self] in
            guard let self else { return }
            self.upsertProject(snapshot)
            for iid in relinkItemIDs { self.setProject(iid, projectID: id) }
        }
    }

    /// Delete a page (reparenting its children) and return a restore closure
    /// that puts the page back and re-attaches both its children and its tasks.
    func deleteProjectKeepingChildrenWithUndo(_ id: String) -> (() -> Void)? {
        guard let snapshot = projects.first(where: { $0.id == id }) else { return nil }
        let childIDs = projects.filter { $0.parentID == id }.map(\.id)
        let relinkItemIDs = items.filter { $0.projectID == id }.map(\.id)
        deleteProjectKeepingChildren(id)
        return { [weak self] in
            guard let self else { return }
            self.upsertProject(snapshot)
            for cid in childIDs { self.setProjectParent(cid, parentID: id) }
            for iid in relinkItemIDs { self.setProject(iid, projectID: id) }
        }
    }

    /// Delete an initiative and return a closure that restores it and re-links
    /// the projects it detached.
    func deleteInitiativeWithUndo(_ id: String) -> (() -> Void)? {
        guard let snapshot = initiatives.first(where: { $0.id == id }) else { return nil }
        let relinkProjectIDs = projects.filter { $0.initiativeID == id }.map(\.id)
        deleteInitiative(id)
        return { [weak self] in
            guard let self else { return }
            self.initiatives.append(snapshot)
            self.saveInitiatives()
            for pid in relinkProjectIDs { self.setProjectInitiative(pid, initiativeID: id) }
        }
    }

    /// Delete a section and return a closure that restores it and re-files the
    /// tasks it detached.
    func deleteSectionWithUndo(_ id: String) -> (() -> Void)? {
        guard let snapshot = sections.first(where: { $0.id == id }) else { return nil }
        let refileItemIDs = items.filter { $0.sectionID == id }.map(\.id)
        deleteSection(id)
        return { [weak self] in
            guard let self else { return }
            self.sections.append(snapshot)
            self.saveSections()
            for iid in refileItemIDs { self.setSection(iid, sectionID: id) }
        }
    }

    /// True if this page should render a task database (explicit flag, or
    /// inferred from having tasks for back-compat).
    func pageHasDatabase(_ project: Project) -> Bool {
        if let enabled = project.databaseEnabled { return enabled }
        return items.contains { $0.projectID == project.id }
    }

    func setProjectDatabaseEnabled(_ id: String, _ enabled: Bool) {
        updateProject(id) { $0.databaseEnabled = enabled }
    }

    func setProjectName(_ id: String, name: String) { updateProject(id) { $0.name = name } }
    func setProjectBody(_ id: String, body: String) { updateProject(id) { $0.body = body } }
    func setProjectIcon(_ id: String, icon: String?) { updateProject(id) { $0.icon = icon } }
    func setProjectStatus(_ id: String, status: Project.Status) { updateProject(id) { $0.status = status } }
    func setProjectTargetDate(_ id: String, _ date: Date?) { updateProject(id) { $0.targetDate = date } }

    // MARK: - Custom database properties (NP-1)

    func propertyDefs(forProject id: String) -> [PropertyDefinition] {
        projects.first { $0.id == id }?.propertyDefs ?? []
    }
    @discardableResult
    func addProperty(toProject id: String, name: String, type: PropertyType) -> PropertyDefinition {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let def = PropertyDefinition(name: trimmed.isEmpty ? "Property" : trimmed, type: type)
        updateProject(id) { $0.propertyDefs = ($0.propertyDefs ?? []) + [def] }
        return def
    }
    func renameProperty(_ propID: String, inProject id: String, name: String) {
        updateProject(id) {
            guard var defs = $0.propertyDefs, let i = defs.firstIndex(where: { $0.id == propID }) else { return }
            defs[i].name = name; $0.propertyDefs = defs
        }
    }
    func setPropertyOptions(_ propID: String, inProject id: String, options: [String]) {
        updateProject(id) {
            guard var defs = $0.propertyDefs, let i = defs.firstIndex(where: { $0.id == propID }) else { return }
            defs[i].options = options; $0.propertyDefs = defs
        }
    }
    func deleteProperty(_ propID: String, fromProject id: String) {
        updateProject(id) { $0.propertyDefs = ($0.propertyDefs ?? []).filter { $0.id != propID } }
        var changed = false
        for i in items.indices where items[i].projectID == id {
            if items[i].properties?[propID] != nil {
                items[i].properties?.removeValue(forKey: propID)
                items[i].updatedAt = Date()
                changed = true
            }
        }
        if changed { save() }
    }
    func setPropertyValue(_ taskID: String, propID: String, _ value: PropertyValue?) {
        update(taskID) {
            var p = $0.properties ?? [:]
            if let value { p[propID] = value } else { p.removeValue(forKey: propID) }
            $0.properties = p.isEmpty ? nil : p
        }
    }

    private func updateProject(_ id: String, mutate: (inout Project) -> Void) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        var copy = projects[idx]
        mutate(&copy)
        copy.updatedAt = Date()
        projects[idx] = copy
        saveProjects()
    }

    // MARK: - Persistence
    //
    // All six files now go through `SchemaEnvelope` (audit 2.3) so future
    // field renames / type changes can land without breaking existing
    // installs. Reads accept both legacy raw-array payloads and the new
    // versioned envelope; writes always use the envelope. The on-disk
    // MCP server (which reads action_items.json directly) still works
    // because SchemaEnvelope.decode falls through to the legacy shape.

    private static let actionItemSchemaVersion = 1
    private static let projectSchemaVersion = 1
    private static let labelSchemaVersion = 1
    private static let sectionSchemaVersion = 1
    private static let initiativeSchemaVersion = 1
    private static let contextSchemaVersion = 1

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let arr: [ActionItem] = try? SchemaEnvelope.decode(
            [ActionItem].self, from: data,
            currentVersion: Self.actionItemSchemaVersion,
            decoder: SharedCoders.decoder(),
            migrate: TaskSchemaMigrations.actionItems
        ) {
            items = arr.filter { $0.deletedAt == nil }
            trashedItems = arr.filter { $0.deletedAt != nil }
        }
    }

    /// Persists live + trashed tasks together (one file, partitioned on load by
    /// the soft-delete tombstone) so Trash survives relaunch and the on-disk
    /// MCP file contract is unchanged apart from the optional `deletedAt` field.
    private func save() {
        writeEnvelope(items + trashedItems, to: fileURL,
                      version: Self.actionItemSchemaVersion,
                      tag: "ActionItemStore.save")
    }

    private func loadProjects() {
        guard let data = try? Data(contentsOf: projectsURL) else { return }
        if let arr: [Project] = try? SchemaEnvelope.decode(
            [Project].self, from: data,
            currentVersion: Self.projectSchemaVersion,
            decoder: SharedCoders.decoder()
        ) {
            projects = arr
        }
    }

    private func saveProjects() {
        writeEnvelope(projects, to: projectsURL,
                      version: Self.projectSchemaVersion,
                      tag: "ActionItemStore.saveProjects")
    }

    private func loadLabels() {
        guard let data = try? Data(contentsOf: labelsURL) else { return }
        if let arr: [TaskLabel] = try? SchemaEnvelope.decode(
            [TaskLabel].self, from: data,
            currentVersion: Self.labelSchemaVersion,
            decoder: SharedCoders.decoder()
        ) {
            labels = arr
        }
    }

    private func saveLabels() {
        writeEnvelope(labels, to: labelsURL,
                      version: Self.labelSchemaVersion,
                      tag: "ActionItemStore.saveLabels")
    }

    private func loadSections() {
        guard let data = try? Data(contentsOf: sectionsURL) else { return }
        if let arr: [ProjectSection] = try? SchemaEnvelope.decode(
            [ProjectSection].self, from: data,
            currentVersion: Self.sectionSchemaVersion,
            decoder: SharedCoders.decoder()
        ) {
            sections = arr
        }
    }

    private func saveSections() {
        writeEnvelope(sections, to: sectionsURL,
                      version: Self.sectionSchemaVersion,
                      tag: "ActionItemStore.saveSections")
    }

    private func loadInitiatives() {
        guard let data = try? Data(contentsOf: initiativesURL) else { return }
        if let arr: [Initiative] = try? SchemaEnvelope.decode(
            [Initiative].self, from: data,
            currentVersion: Self.initiativeSchemaVersion,
            decoder: SharedCoders.decoder()
        ) {
            initiatives = arr
        }
    }
    private func saveInitiatives() {
        writeEnvelope(initiatives, to: initiativesURL,
                      version: Self.initiativeSchemaVersion,
                      tag: "ActionItemStore.saveInitiatives")
    }
    private func saveContexts() {
        writeEnvelope(contexts, to: contextsURL,
                      version: Self.contextSchemaVersion,
                      tag: "ActionItemStore.saveContexts")
    }

    /// One helper to rule them all — every persisted store routes through
    /// here so the envelope shape, encoder, and error reporting stay
    /// consistent.
    private func writeEnvelope<T: Codable>(_ payload: T, to url: URL,
                                           version: Int, tag: String) {
        do {
            // Encode on the main actor (cheap for these small files), then hand
            // the bytes to the coordinator, which writes off-main, coalesced and
            // debounced (P0-1). Removes the synchronous full-file disk write that
            // ran on the UI thread on every single mutation.
            let env = SchemaEnvelope(version: version, data: payload)
            let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(env)
            TaskPersistenceCoordinator.shared.write(data, to: url)
        } catch {
            log.error("\(tag, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage,
                                        context: ["phase": tag, "path": url.path])
        }
    }
}
