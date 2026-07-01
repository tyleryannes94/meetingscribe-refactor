import SwiftUI

/// Shared selection state for the Tasks tab (A0-3 / E2-4). Replaces the
/// three-`@Binding` prop-drilling (`selectedProjectID`, `selectedMeetingID`,
/// `selectedInitiativeID`) that was threaded through `ProjectRail`,
/// `PageTreeNode`, and `InitiativeNode` with a single `@EnvironmentObject`.
///
/// Storage stays as the same independent optionals the tab always used, so
/// behavior is unchanged; `route` (see `TasksRoute`) is the typed projection the
/// router switches over. `selectedTaskID` is an overlay — when set, the task
/// page shows on top of whatever list context the other fields describe.
@available(macOS 14.0, *)
@MainActor
final class TasksEnvironment: ObservableObject {
    /// "__home__" = dashboard; nil = All tasks; "__none__" = No project;
    /// "__triage__"/"__waiting__"/"__person__…" = smart buckets; else a project id.
    /// Selecting any of these exits the Brain Dump page (they're mutually
    /// exclusive tabs in the Tasks pane).
    @Published var selectedProjectID: String? { didSet { if selectedProjectID != nil { showingBrainDump = false } } }
    /// When set, the right pane routes to that meeting (and then clears).
    @Published var selectedMeetingID: String? { didSet { if selectedMeetingID != nil { showingBrainDump = false } } }
    /// When set, the right pane shows that initiative's page.
    @Published var selectedInitiativeID: String? { didSet { if selectedInitiativeID != nil { showingBrainDump = false } } }
    /// When set, the right pane shows that task as a full page (overlay).
    @Published var selectedTaskID: String? { didSet { if selectedTaskID != nil { showingBrainDump = false } } }
    /// Active workspace context filter (1-2). nil = "All" (span every context).
    /// Scopes the sidebar initiative tree and the main task list live.
    @Published var activeContextID: String?

    /// When true the Tasks pane shows the embedded Brain Dump surface (a
    /// first-class page *within* Tasks). Entering it clears the task selection so
    /// no other sidebar row stays highlighted; any task selection exits it.
    @Published var showingBrainDump = false {
        didSet {
            if showingBrainDump {
                selectedTaskID = nil; selectedMeetingID = nil; selectedInitiativeID = nil
            }
        }
    }

    /// Default landing is the Today smart view (1-3) — not the old aimless
    /// "All tasks" — so opening Tasks leads with what's due now.
    init(selectedProjectID: String? = ActionItemsView.todaySentinel) {
        self.selectedProjectID = selectedProjectID
    }

    /// Navigate to a typed route (3-6 breadcrumbs, 3-8 history). Clears the
    /// other selection fields so the route is unambiguous.
    func go(_ route: TasksRoute) {
        showingBrainDump = false
        selectedTaskID = nil; selectedMeetingID = nil
        selectedInitiativeID = nil; selectedProjectID = nil
        switch route {
        case .task(let id): selectedTaskID = id
        case .initiative(let id): selectedInitiativeID = id
        case .meeting(let id): selectedMeetingID = id
        default: selectedProjectID = route.projectSelection
        }
    }

    /// Typed projection of the current selection (A0-2). The router and later
    /// phases switch over this instead of comparing sentinel strings.
    var route: TasksRoute {
        if let tid = selectedTaskID { return .task(tid) }
        if let iid = selectedInitiativeID { return .initiative(iid) }
        if let mid = selectedMeetingID { return .meeting(mid) }
        guard let pid = selectedProjectID else { return .allTasks }
        switch pid {
        case ActionItemsView.homeSentinel:      return .home
        case ActionItemsView.todaySentinel:     return .today
        case ActionItemsView.triageSentinel:    return .triage
        case ActionItemsView.noProjectSentinel: return .noProject
        case ActionItemsView.waitingSentinel:   return .waitingOn
        case ActionItemsView.recurringSentinel: return .recurring
        case ActionItemsView.myTasksSentinel:   return .myTasks
        case ActionItemsView.fromMeetingsSentinel: return .fromMeetings
        default:
            if pid.hasPrefix(ActionItemsView.personSentinelPrefix) {
                return .person(String(pid.dropFirst(ActionItemsView.personSentinelPrefix.count)))
            }
            if pid.hasPrefix(ActionItemsView.savedViewSentinelPrefix) {
                return .savedView(String(pid.dropFirst(ActionItemsView.savedViewSentinelPrefix.count)))
            }
            return .project(pid)
        }
    }
}
