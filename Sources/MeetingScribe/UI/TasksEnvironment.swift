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
    @Published var selectedProjectID: String?
    /// When set, the right pane routes to that meeting (and then clears).
    @Published var selectedMeetingID: String?
    /// When set, the right pane shows that initiative's page.
    @Published var selectedInitiativeID: String?
    /// When set, the right pane shows that task as a full page (overlay).
    @Published var selectedTaskID: String?
    /// Active workspace context filter (1-2). nil = "All" (span every context).
    /// Scopes the sidebar initiative tree and the main task list live.
    @Published var activeContextID: String?

    /// Default landing is the Today smart view (1-3) — not the old aimless
    /// "All tasks" — so opening Tasks leads with what's due now.
    init(selectedProjectID: String? = ActionItemsView.todaySentinel) {
        self.selectedProjectID = selectedProjectID
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
        default:
            if pid.hasPrefix(ActionItemsView.personSentinelPrefix) {
                return .person(String(pid.dropFirst(ActionItemsView.personSentinelPrefix.count)))
            }
            return .project(pid)
        }
    }
}
