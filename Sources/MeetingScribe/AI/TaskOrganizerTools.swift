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
        /// Break one compound task into subtasks (the parent keeps its title;
        /// each part becomes a checklist subtask).
        case split(taskID: String, taskTitle: String, parts: [String])
    }
    var kind: Kind
    var reason: String
    var applied: Bool = false
    var dismissed: Bool = false
    /// For multi-task kinds (tag / move-to-project): task IDs the user has
    /// unchecked in the card, so a recommendation can be applied to only the
    /// subset that actually fits. Single-task kinds ignore this.
    var deselectedTaskIDs: Set<String> = []

    init(kind: Kind, reason: String) {
        self.id = UUID(); self.kind = kind; self.reason = reason
    }

    /// (id, title) pairs for the affected tasks — only multi-task kinds (the
    /// ones that get a checkbox list in the card). Empty otherwise.
    var taskList: [(id: String, title: String)] {
        switch kind {
        case let .assignProject(ids, titles, _, _): return zip(ids, titles).map { ($0, $1) }
        case let .addTag(ids, titles, _):           return zip(ids, titles).map { ($0, $1) }
        default: return []
        }
    }

    /// The task IDs this suggestion will actually act on when applied — the full
    /// set minus anything the user unchecked.
    var activeTaskIDs: [String] {
        switch kind {
        case let .assignProject(ids, _, _, _): return ids.filter { !deselectedTaskIDs.contains($0) }
        case let .addTag(ids, _, _):           return ids.filter { !deselectedTaskIDs.contains($0) }
        case let .reschedule(id, _, _):        return [id]
        case let .reprioritize(id, _, _):      return [id]
        case let .split(id, _, _):             return [id]
        }
    }
}
