import SwiftUI
import AppKit
/// Full task-manager tab — every action item across every meeting, with
/// inline status / priority / due-date editing and one-click push to
/// Notion. Designed to feel like Asana/Linear/Notion: dense table, hover
/// reveal of actions, filters along the top, summary stats.
@available(macOS 14.0, *)
struct ActionItemsView: View {
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var router: WorkspaceRouter
    @ObservedObject var store: ActionItemStore

    /// Single owner of filter / sort / view / group state and the canonical
    /// filter implementation (A0-1). Replaces ~11 parallel `@State` vars and a
    /// diverged dead copy of the filter logic.
    @State var vm = ActionItemsViewModel()
    /// Shared selection state (A0-3): project / meeting / initiative / task. Was
    /// four `@State` optionals threaded as bindings through the sidebar; now a
    /// single environment object so `ProjectRail` & nodes drop their prop
    /// drilling. `env.route` (A0-2) is the typed projection the router uses.
    @StateObject var env = TasksEnvironment()
    @State var addingSection = false
    @State var newSectionName = ""
    @State var renameSectionID: String?
    @State var renameSectionDraft = ""
    // Multi-select + bulk actions (TK-3/TK-4).
    @State var taskSelectMode = false
    @State var taskSelection: Set<String> = []
    // Anchor for shift-click range selection (2-6).
    @State var lastSelectedTaskID: String?
    // Resizable, persisted Tasks sidebar width (TK-8 — was a fixed 230).
    @AppStorage("tasks.railWidth") var railWidth: Double = 230
    // Persisted Tasks selection across relaunches / multiple windows (3-10).
    // Empty string = nil; only restored when something was actually saved.
    @SceneStorage("tasks.sel.project") var sceneProject: String = ""
    @SceneStorage("tasks.sel.task") var sceneTask: String = ""
    @SceneStorage("tasks.sel.initiative") var sceneInitiative: String = ""
    @State var didRestoreScene = false
    @State var railDragStart: Double?
    // Trash sheet (P0-3): restore or permanently remove soft-deleted tasks.
    @State var showTrash = false
    // Natural-language quick-add popover (P3-2).
    @State var quickAdding = false
    @State var quickAddText = ""
    // Keeps the quick-add field focused across rapid back-to-back entries (P0-1).
    @FocusState var quickAddFocused: Bool
    // Insights sheet (PM-12).
    @State var showInsights = false
    // Keyboard shortcuts cheat-sheet (UX-22).
    @State var showShortcuts = false
    // ⌘K jump palette (3-1).
    @State var showJumpPalette = false
    // Calendar view: the month currently displayed (VD-1).
    @State var calendarMonth = Date()
    // Keyboard navigation cursor for the list (UX-1).
    @State var focusedTaskID: String?
    // Keyboard quick-edit popover anchored on the focused row (2-4): d/e/m.
    @State var kbEditID: String?
    @State var kbEditKind: KbEdit?
    enum KbEdit { case date, estimate, move }
    // Initiative roll-up quick-add (3-2).
    @State var initiativeAddText = ""
    @State var initiativeAddProjectID: String?
    // Save-current-filter-as-view popover (5-1).
    @State var savingView = false
    @State var newViewName = ""
    // Table view (5-8): hidden columns (CSV persisted) + inline title editing.
    @AppStorage("tasks.table.hiddenColumns") var tableHiddenColumnsCSV = ""
    @State var tableEditingTitleID: String?
    @State var tableTitleDraft = ""
    // Tasks pinned into "Today" regardless of due date (5-2).
    @AppStorage(PinnedToday.key) var pinnedTodayCSV = ""

    enum ViewMode: String, CaseIterable, Identifiable {
        case list, table, board, calendar, gallery
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .list: return "list.bullet"
            case .table: return "tablecells"
            case .board: return "rectangle.split.3x1"
            case .calendar: return "calendar"
            case .gallery: return "square.grid.2x2"
            }
        }
    }
    static let noProjectSentinel = "__none__"
    static let homeSentinel = "__home__"
    static let todaySentinel = "__today__"
    static let triageSentinel = "__triage__"
    /// People facet (P2-2): a person scope is encoded into `env.selectedProjectID`
    /// as `"__person__<personID>"` so it shares the single left-column
    /// selection model — any other rail tap that sets `env.selectedProjectID`
    /// naturally clears the person scope.
    static let personSentinelPrefix = "__person__"
    static func personSentinel(_ id: String) -> String { personSentinelPrefix + id }
    /// Saved-view scope (5-1), encoded into the single rail selection like People.
    static let savedViewSentinelPrefix = "__savedview__"
    static func savedViewSentinel(_ id: String) -> String { savedViewSentinelPrefix + id }
    /// Waiting-on lifecycle (P2-6): scopes the list to delegated tasks
    /// (commitments you're waiting on others for).
    static let waitingSentinel = "__waiting__"
    /// Recurring smart list (5-3): tasks that carry a repeat rule.
    static let recurringSentinel = "__recurring__"
    /// My Tasks (5-2): the current user's tasks bucketed by date.
    static let myTasksSentinel = "__mytasks__"
    /// T12 / 04 §4.3: review queue for tasks whose `owner` text didn't resolve
    /// to a Person — fix the link inline, or add the person.
    static let unassignedOwnersSentinel = "__unassigned_owners__"

    /// True when the rail's "Unassigned owners" review bucket is selected (T12).
    var isUnassignedOwnersScope: Bool { env.selectedProjectID == Self.unassignedOwnersSentinel }

    /// The person id currently scoping the task list, if a People-facet row is
    /// selected in the rail (P2-2). Decoded from `env.selectedProjectID`.
    var selectedPersonID: String? {
        guard let pid = env.selectedProjectID, pid.hasPrefix(Self.personSentinelPrefix) else { return nil }
        return String(pid.dropFirst(Self.personSentinelPrefix.count))
    }
    /// True when the rail's "Waiting on" bucket is selected (P2-6).
    var isWaitingScope: Bool { env.selectedProjectID == Self.waitingSentinel }

    enum Filter: String, CaseIterable, Identifiable {
        case all, thisWeek, open, inProgress, completed, upcoming, overdue
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:        return "All"
            case .thisWeek:   return "This Week"
            case .open:       return "Open"
            case .inProgress: return "In Progress"
            case .completed:  return "Done"
            case .upcoming:   return "Upcoming"
            case .overdue:    return "Overdue"
            }
        }
        var systemImage: String {
            switch self {
            case .all:        return "tray.full"
            case .thisWeek:   return "calendar.badge.clock"
            case .open:       return "circle"
            case .inProgress: return "arrow.triangle.2.circlepath"
            case .completed:  return "checkmark.circle.fill"
            case .upcoming:   return "clock"
            case .overdue:    return "exclamationmark.circle.fill"
            }
        }
    }
    enum PriorityFilter: String, CaseIterable, Identifiable {
        case any, low, medium, high, urgent
        var id: String { rawValue }
        var label: String { self == .any ? "Any priority" : self.rawValue.capitalized }
    }
    enum TableSort: String, CaseIterable, Identifiable {
        case task, project, owner, priority, due
        var id: String { rawValue }
    }
    enum OwnerScope: String, CaseIterable, Identifiable {
        case anyone, mine, delegated
        var id: String { rawValue }
    }
    enum GroupBy: String, CaseIterable, Identifiable {
        case none, meeting, priority, status, dueDate, owner, project, initiative, label, sprint
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "Flat list"
            case .meeting: return "Meeting"
            case .priority: return "Priority"
            case .status: return "Status"
            case .dueDate: return "Due date"
            case .owner: return "Owner"
            case .project: return "Project"
            case .initiative: return "Initiative"
            case .label: return "Label"
            case .sprint: return "Sprint"
            }
        }
    }

    var body: some View {
        // The Tasks tab lives inside the app's custom rail + keep-alive tab host
        // (MainWindow), under a native window toolbar — so it uses a plain
        // HStack + drag divider, NOT a NavigationSplitView (which fights the
        // window toolbar's safe area and clipped the content's top). `detailPane`
        // is extracted to keep this body under SwiftUI's type-check budget.
        HStack(spacing: 0) {
            ProjectRail(store: store, meetings: manager.pastMeetings)
                .environmentObject(env)
                .frame(width: CGFloat(railWidth))
            // Draggable divider — resizes + persists the sidebar width.
            Divider().overlay(NDS.divider)
                .background(Color.clear.frame(width: 6).contentShape(Rectangle()))
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            let start = railDragStart ?? railWidth
                            if railDragStart == nil { railDragStart = railWidth }
                            railWidth = min(360, max(180, start + Double(v.translation.width)))
                        }
                        .onEnded { _ in railDragStart = nil }
                )
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
            detailPane
        }
        .background(NDS.bg)
        .onAppear {
            manager.refreshPastMeetings()
            manager.backfillActionItemsIfNeeded()
            restoreSceneSelection()
            consumePendingTask()
            consumePendingTasksRoute()
        }
        .onChange(of: router.pendingTaskID) { _, _ in consumePendingTask() }
        .onChange(of: router.pendingTasksRoute) { _, _ in consumePendingTasksRoute() }
        .onChange(of: env.selectedProjectID) { _, _ in
            env.selectedTaskID = nil
            // Restore the project's last-used view (NP-3) + group-by (5-5).
            if let pid = realSelectedProjectID,
               let saved = AppSettings.shared.savedTaskViewMode(forProject: pid),
               let mode = ViewMode(rawValue: saved) {
                vm.viewMode = mode
            }
            if let raw = AppSettings.shared.taskGroupBy(forRoute: groupByRouteKey),
               let g = GroupBy(rawValue: raw) { vm.groupBy = g }
        }
        .onChange(of: vm.viewMode) { _, mode in
            if let pid = realSelectedProjectID {
                AppSettings.shared.setSavedTaskViewMode(mode.rawValue, forProject: pid)
            }
        }
        .onChange(of: vm.groupBy) { _, g in
            AppSettings.shared.setTaskGroupBy(g.rawValue, forRoute: groupByRouteKey)
        }
        .onChange(of: env.selectedMeetingID) { _, _ in env.selectedTaskID = nil }
        .onChange(of: env.selectedInitiativeID) { _, v in
            if v != nil { env.selectedTaskID = nil; env.selectedMeetingID = nil }
            sceneInitiative = v ?? ""
        }
        // Persist Tasks selection across relaunch / new windows (3-10).
        .onChange(of: env.selectedProjectID) { _, v in sceneProject = v ?? ""; pushRouterTasksSelection() }
        .onChange(of: env.selectedTaskID) { _, v in sceneTask = v ?? ""; pushRouterTasksSelection() }
        .onChange(of: env.selectedMeetingID) { _, _ in pushRouterTasksSelection() }
        .onChange(of: env.selectedInitiativeID) { _, _ in pushRouterTasksSelection() }
        // Restore Tasks selection when global back/forward steps to a Tasks state (3-8).
        .onChange(of: router.tasksRestore) { _, snap in
            guard let snap else { return }
            env.selectedProjectID = snap.project
            env.selectedTaskID = snap.task
            env.selectedInitiativeID = snap.initiative
            env.selectedMeetingID = snap.meeting
            router.consumeTasksRestore()
        }
        .sheet(isPresented: $showTrash) {
            TaskTrashView(store: store)
        }
        .sheet(isPresented: $showInsights) {
            TaskInsightsView(store: store)
        }
        .sheet(isPresented: $showShortcuts) {
            TaskShortcutsView()
        }
        .sheet(isPresented: $showJumpPalette) {
            TasksJumpPalette(store: store, isPresented: $showJumpPalette, onSelect: { env.go($0) })
        }
        .background {
            // Invisible ⌘K hotkey (3-1).
            Button("") { showJumpPalette = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
    }

    /// Opens a task deep-linked from outside the Tasks tab (e.g. the home-page
    /// Kanban). Shows "All tasks" so the item is in scope, selects it, and clears
    /// the one-shot channel.
    /// Restores the Tasks selection saved by `@SceneStorage` (3-10), once per
    /// view lifetime, only when something was actually persisted (so a fresh
    /// scene still lands on the Today default).
    func restoreSceneSelection() {
        guard !didRestoreScene else { return }
        didRestoreScene = true
        guard !sceneProject.isEmpty || !sceneTask.isEmpty || !sceneInitiative.isEmpty else {
            // First-time landing with no persisted scene state: honor the
            // user's "Default smart view" preference (UX-Q1) so the tab opens
            // on, say, "My Open Tasks" instead of the firehose All view.
            if env.selectedProjectID == nil,
               let id = AppSettings.shared.defaultSmartViewID,
               store.savedView(id: id) != nil {
                env.selectedProjectID = Self.savedViewSentinel(id)
            }
            return
        }
        if !sceneProject.isEmpty { env.selectedProjectID = sceneProject }
        if !sceneInitiative.isEmpty { env.selectedInitiativeID = sceneInitiative }
        if !sceneTask.isEmpty, store.items.contains(where: { $0.id == sceneTask }) {
            env.selectedTaskID = sceneTask
        }
    }

    /// Mirror the Tasks pane selection into the router so global back/forward
    /// can restore it (3-8).
    /// Per-route key for remembering group-by (5-5).
    var groupByRouteKey: String { env.selectedProjectID ?? "all" }

    func pushRouterTasksSelection() {
        router.setTasksSelection(project: env.selectedProjectID, task: env.selectedTaskID,
                                 initiative: env.selectedInitiativeID, meeting: env.selectedMeetingID)
    }

    /// Lands the Tasks pane on a deep-linked rail sentinel (4-7), e.g. triage.
    func consumePendingTasksRoute() {
        guard let sentinel = router.pendingTasksRoute else { return }
        env.selectedTaskID = nil
        env.selectedMeetingID = nil
        env.selectedInitiativeID = nil
        env.selectedProjectID = sentinel
        router.pendingTasksRoute = nil
    }

    func consumePendingTask() {
        guard let tid = router.pendingTaskID, store.items.contains(where: { $0.id == tid }) else { return }
        env.selectedProjectID = nil
        env.selectedMeetingID = nil
        env.selectedInitiativeID = nil
        env.selectedTaskID = tid
        router.pendingTaskID = nil
    }

    var taskBreadcrumb: String {
        if let pid = realSelectedProjectID, let p = store.project(id: pid) { return p.name }
        return "All tasks"
    }
    /// The selected project id, but only when it's a real, existing project
    /// (not "All tasks" or the "No project" sentinel).
    var realSelectedProjectID: String? {
        guard let pid = env.selectedProjectID, pid != Self.noProjectSentinel,
              store.project(id: pid) != nil else { return nil }
        return pid
    }

    @ViewBuilder
    var content: some View {
        switch vm.viewMode {
        case .list:
            if let pid = realSelectedProjectID {
                sectionedListBody(projectID: pid)
            } else if projectFiltered.isEmpty {
                emptyState
            } else {
                listBody
            }
        case .table:
            if projectFiltered.isEmpty { emptyState } else { tableBody }
        case .board:
            boardBody
        case .calendar:
            calendarBody
        case .gallery:
            if projectFiltered.isEmpty { emptyState } else { galleryBody }
        }
    }
}
