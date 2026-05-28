import SwiftUI
import AppKit
/// Full task-manager tab — every action item across every meeting, with
/// inline status / priority / due-date editing and one-click push to
/// Notion. Designed to feel like Asana/Linear/Notion: dense table, hover
/// reveal of actions, filters along the top, summary stats.
@available(macOS 14.0, *)
struct ActionItemsView: View {
    @EnvironmentObject var manager: MeetingManager
    @ObservedObject var store: ActionItemStore

    @State var filter: Filter = .all
    @State var priorityFilter: PriorityFilter = .any
    @State var search: String = ""
    @State var pushingIDs: Set<String> = []
    @State var lastError: String?
    @State var editingID: String?
    @State var groupBy: GroupBy = .none
    @State var viewMode: ViewMode = .list
    /// "__home__" = dashboard; nil = All tasks; "__none__" = No project; else a project id.
    @State var selectedProjectID: String? = ActionItemsView.homeSentinel
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

    enum ViewMode: String, CaseIterable, Identifiable {
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
    static let noProjectSentinel = "__none__"
    static let homeSentinel = "__home__"

    enum Filter: String, CaseIterable, Identifiable {
        case all, open, inProgress, completed, upcoming, overdue
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .open: return "Open"
            case .inProgress: return "In Progress"
            case .completed: return "Done"
            case .upcoming: return "Upcoming"
            case .overdue: return "Overdue"
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
                .frame(width: 230)
            Divider().overlay(NDS.divider)
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
                } else if selectedProjectID == Self.homeSentinel && selectedMeetingID == nil {
                    tasksDashboard
                } else if let mid = selectedMeetingID,
                   let m = manager.pastMeetings.first(where: { $0.id == mid }) {
                    MeetingNotesPage(meeting: m, store: store)
                        .environmentObject(manager)
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
        .onChange(of: selectedProjectID) { _, _ in selectedTaskID = nil }
        .onChange(of: selectedMeetingID) { _, _ in selectedTaskID = nil }
        .onChange(of: selectedInitiativeID) { _, v in
            if v != nil { selectedTaskID = nil; selectedMeetingID = nil }
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
        }
    }
}
