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
    // Resizable, persisted Tasks sidebar width (TK-8 — was a fixed 230).
    @AppStorage("tasks.railWidth") var railWidth: Double = 230
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
    // Calendar view: the month currently displayed (VD-1).
    @State var calendarMonth = Date()
    // Keyboard navigation cursor for the list (UX-1).
    @State var focusedTaskID: String?

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
    /// Waiting-on lifecycle (P2-6): scopes the list to delegated tasks
    /// (commitments you're waiting on others for).
    static let waitingSentinel = "__waiting__"

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
        case none, meeting, priority, status, dueDate
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "Flat list"
            case .meeting: return "Meeting"
            case .priority: return "Priority"
            case .status: return "Status"
            case .dueDate: return "Due date"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ProjectRail(store: store,
                        meetings: manager.pastMeetings)
                .environmentObject(env)
                .frame(width: CGFloat(railWidth))
            // Draggable divider — resizes + persists the sidebar width. (TK-8)
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
            Group {
                // A0-2: route on the typed `TasksRoute` projection instead of
                // sentinel-string comparisons. Guards that fail (a task/initiative
                // id that no longer exists) fall through to `taskDatabasePane`.
                switch env.route {
                case .task(let tid) where store.items.contains(where: { $0.id == tid }):
                    TaskPageView(store: store, itemID: tid,
                                 breadcrumb: taskBreadcrumb,
                                 onClose: { env.selectedTaskID = nil })
                case .initiative(let iid) where store.initiative(id: iid) != nil:
                    InitiativePage(store: store, initiativeID: iid,
                                   onOpenProject: { pid in
                                       env.selectedInitiativeID = nil; env.selectedProjectID = pid
                                   })
                case .triage:
                    TriageInboxView(store: store) { mid in
                        env.selectedMeetingID = mid
                        env.selectedProjectID = nil
                    }
                case .home:
                    tasksDashboard
                case .today:
                    todayPane
                case .meeting(let mid) where manager.pastMeetings.contains(where: { $0.id == mid }):
                    // D1-4: one canonical meeting surface. Instead of the parallel
                    // MeetingNotesPage, route to the Meetings-tab detail.
                    Color.clear.onAppear {
                        if let m = manager.pastMeetings.first(where: { $0.id == mid }) {
                            router.openMeeting(m)
                        }
                        env.selectedMeetingID = nil
                    }
                default:
                    taskDatabasePane
                }
            }
        }
        .background(NDS.bg)
        .onAppear {
            manager.refreshPastMeetings()
            manager.backfillActionItemsIfNeeded()
            consumePendingTask()
        }
        .onChange(of: router.pendingTaskID) { _, _ in consumePendingTask() }
        .onChange(of: env.selectedProjectID) { _, _ in
            env.selectedTaskID = nil
            // Restore the project's last-used view (NP-3).
            if let pid = realSelectedProjectID,
               let saved = AppSettings.shared.savedTaskViewMode(forProject: pid),
               let mode = ViewMode(rawValue: saved) {
                vm.viewMode = mode
            }
        }
        .onChange(of: vm.viewMode) { _, mode in
            if let pid = realSelectedProjectID {
                AppSettings.shared.setSavedTaskViewMode(mode.rawValue, forProject: pid)
            }
        }
        .onChange(of: env.selectedMeetingID) { _, _ in env.selectedTaskID = nil }
        .onChange(of: env.selectedInitiativeID) { _, v in
            if v != nil { env.selectedTaskID = nil; env.selectedMeetingID = nil }
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
    }

    /// Opens a task deep-linked from outside the Tasks tab (e.g. the home-page
    /// Kanban). Shows "All tasks" so the item is in scope, selects it, and clears
    /// the one-shot channel.
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
