import Foundation

/// Typed destination for the Tasks tab's main pane (A0-2 / E2-2). Replaces the
/// scattered `selectedProjectID == "__home__"` sentinel-string comparisons with
/// an exhaustive enum, so adding a new surface (Today, Saved Views, …) is a
/// compile-checked change rather than a stringly-typed one.
///
/// The Tasks tab still stores selection as a small set of optionals on
/// `TasksEnvironment` (independent, exactly as before); `route` is the typed
/// projection the router and later phases switch over. The raw-string bridges
/// below keep interop with the existing sentinel constants on `ActionItemsView`
/// so the migration is additive.
@available(macOS 14.0, *)
enum TasksRoute: Hashable {
    case home
    case today
    case triage
    case allTasks
    case noProject
    case waitingOn
    case project(String)
    case initiative(String)
    case person(String)
    case meeting(String)
    case task(String)
    case savedView(String)
    case recurring
    case myTasks

    /// The `selectedProjectID` sentinel/value this route corresponds to, for the
    /// list-context routes that are encoded there. Returns `nil` for "All tasks"
    /// and for routes not carried by `selectedProjectID` (task/meeting/initiative).
    var projectSelection: String? {
        switch self {
        case .home:        return ActionItemsView.homeSentinel
        case .triage:      return ActionItemsView.triageSentinel
        case .noProject:   return ActionItemsView.noProjectSentinel
        case .waitingOn:   return ActionItemsView.waitingSentinel
        case .person(let id): return ActionItemsView.personSentinel(id)
        case .savedView(let id): return ActionItemsView.savedViewSentinel(id)
        case .project(let id): return id
        case .today:       return ActionItemsView.todaySentinel
        case .recurring:   return ActionItemsView.recurringSentinel
        case .myTasks:     return ActionItemsView.myTasksSentinel
        case .allTasks, .initiative, .meeting, .task: return nil
        }
    }
}
