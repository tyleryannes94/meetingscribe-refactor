import Foundation
import VaultKit

/// One reviewed, not-yet-applied fix the organizer proposes for the user's
/// tasks. Transient (never persisted) — it lives only for the duration of the
/// review sheet. Produced by `TaskOrganizer` (instant deterministic pass + a
/// single structured-JSON model call); applied to the store on user signoff.
struct TaskSuggestion: Identifiable, Hashable {
    let id: UUID
    enum Kind: Hashable {
        /// Move an overdue/misdated task to `newDate`.
        case reschedule(taskID: String, taskTitle: String, newDate: Date)
        /// Change a task's priority.
        case reprioritize(taskID: String, taskTitle: String, priority: ActionItem.Priority)
        /// Assign one or more tasks to a project. `existingProjectID == nil`
        /// means "create a new project named `projectName`, then assign".
        case assignProject(taskIDs: [String], taskTitles: [String], projectName: String, existingProjectID: String?)
        /// Tag one or more tasks (creating the tag if needed).
        case addTag(taskIDs: [String], taskTitles: [String], tag: String)
    }
    var kind: Kind
    var reason: String
    var applied: Bool = false
    var dismissed: Bool = false

    init(kind: Kind, reason: String) {
        self.id = UUID(); self.kind = kind; self.reason = reason
    }
}
