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

    @State var filter: Filter = .all
    @State var priorityFilter: PriorityFilter = .any
    /// Whether to show everyone's tasks or just the current user's (P2-2).
    @State var ownerScope: OwnerScope = .anyone
    @State var search: String = ""
    @State var pushingIDs: Set<String> = []
    @State var lastError: String?
    @State var editingID: String?
    @State var groupBy: GroupBy = .none
    @State var viewMode: ViewMode = .list
    /// "__home__" = dashboard; nil = All tasks; "__none__" = No project; else a project id.
    // Default to nil (All Tasks) so the first click into Tasks shows every
    // open item immediately, not the dashboard. Dashboard is one click away.
    @State var selectedProjectID: String? = nil
    /// When set, the right pane shows that meeting's notes page instead of
    /// the task database.
    @State var selectedMeetingID: String?
    /// When set, the right pane shows that task as a full Notion-style page.
    @State var selectedTaskID: String?
    /// When set, the right pane shows that initiative's page.
    @State var selectedInitiativeID: String?
    @State var addingSection = false
    @State var newSectionName = ""
    @State var renameSectionID: String?
    @State var renameSectionDraft = ""
    /// Table sort state.
    @State var tableSort: TableSort = .priority
    @State var tableSortAscending = false

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
    static let triageSentinel = "__triage__"
    /// People facet (P2-2): a person scope is encoded into `selectedProjectID`
    /// as `"__person__<personID>"` so it shares the single left-column
    /// selection model — any other rail tap that sets `selectedProjectID`
    /// naturally clears the person scope.
    static let personSentinelPrefix = "__person__"
    static func personSentinel(_ id: String) -> String { personSentinelPrefix + id }
    /// Waiting-on lifecycle (P2-6): scopes the list to delegated tasks
    /// (commitments you're waiting on others for).
    static let waitingSentinel = "__waiting__"

    /// The person id currently scoping the task list, if a People-facet row is
    /// selected in the rail (P2-2). Decoded from `selectedProjectID`.
    var selectedPersonID: String? {
        guard let pid = selectedProjectID, pid.hasPrefix(Self.personSentinelPrefix) else { return nil }
        return String(pid.dropFirst(Self.personSentinelPrefix.count))
    }
    /// True when the rail's "Waiting on" bucket is selected (P2-6).
    var isWaitingScope: Bool { selectedProjectID == Self.waitingSentinel }

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
                        meetings: manager.pastMeetings,
                        selectedProjectID: $selectedProjectID,
                        selectedMeetingID: $selectedMeetingID,
                        selectedInitiativeID: $selectedInitiativeID)
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
                if let tid = selectedTaskID, store.items.contains(where: { $0.id == tid }) {
                    TaskPageView(store: store, itemID: tid,
                                 breadcrumb: taskBreadcrumb,
                                 onClose: { selectedTaskID = nil })
                } else if let iid = selectedInitiativeID, store.initiative(id: iid) != nil {
                    InitiativePage(store: store, initiativeID: iid,
                                   onOpenProject: { pid in
                                       selectedInitiativeID = nil; selectedProjectID = pid
                                   })
                } else if selectedProjectID == Self.triageSentinel && selectedMeetingID == nil {
                    TriageInboxView(store: store) { mid in
                        selectedMeetingID = mid
                        selectedProjectID = nil
                    }
                } else if selectedProjectID == Self.homeSentinel && selectedMeetingID == nil {
                    tasksDashboard
                } else if let mid = selectedMeetingID,
                   let m = manager.pastMeetings.first(where: { $0.id == mid }) {
                    // D1-4: one canonical meeting surface. Instead of the parallel
                    // MeetingNotesPage, route to the Meetings-tab detail.
                    Color.clear.onAppear {
                        router.openMeeting(m)
                        selectedMeetingID = nil
                    }
                } else {
                    taskDatabasePane
                }
            }
        }
        .background(NDS.bg)
        .onAppear {
            manager.refreshPastMeetings()
            manager.backfillActionItemsIfNeeded()
        }
        .onChange(of: selectedProjectID) { _, _ in
            selectedTaskID = nil
            // Restore the project's last-used view (NP-3).
            if let pid = realSelectedProjectID,
               let saved = AppSettings.shared.savedTaskViewMode(forProject: pid),
               let mode = ViewMode(rawValue: saved) {
                viewMode = mode
            }
        }
        .onChange(of: viewMode) { _, mode in
            if let pid = realSelectedProjectID {
                AppSettings.shared.setSavedTaskViewMode(mode.rawValue, forProject: pid)
            }
        }
        .onChange(of: selectedMeetingID) { _, _ in selectedTaskID = nil }
        .onChange(of: selectedInitiativeID) { _, v in
            if v != nil { selectedTaskID = nil; selectedMeetingID = nil }
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

    var taskBreadcrumb: String {
        if let pid = realSelectedProjectID, let p = store.project(id: pid) { return p.name }
        return "All tasks"
    }
    /// The selected project id, but only when it's a real, existing project
    /// (not "All tasks" or the "No project" sentinel).
    var realSelectedProjectID: String? {
        guard let pid = selectedProjectID, pid != Self.noProjectSentinel,
              store.project(id: pid) != nil else { return nil }
        return pid
    }

    @ViewBuilder
    var content: some View {
        switch viewMode {
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
