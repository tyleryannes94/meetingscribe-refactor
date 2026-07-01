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
        /// Give a project a target/deadline date (it has open work but no date).
        case setProjectDeadline(projectID: String, projectName: String, date: Date)
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
        case let .setProjectDeadline(pid, _, _): return [pid]
        }
    }

    /// A stable identity for this proposal (kind + target), used to remember what
    /// the user has already dismissed so re-runs don't re-suggest the same thing.
    var rejectionSignature: String {
        switch kind {
        case let .reschedule(id, _, _):        return "reschedule:\(id)"
        case let .reprioritize(id, _, p):      return "reprioritize:\(id):\(p.rawValue)"
        case let .assignProject(ids, _, _, _): return "project:\(ids.sorted().joined(separator: ","))"
        case let .addTag(ids, _, tag):         return "tag:\(tag):\(ids.sorted().joined(separator: ","))"
        case let .split(id, _, _):             return "split:\(id)"
        case let .setProjectDeadline(pid, _, _): return "projdeadline:\(pid)"
        }
    }
}

// MARK: - Codable (persist the last run so results survive modal close + restart)

extension TaskSuggestion: Codable {
    enum CodingKeys: String, CodingKey { case id, kind, reason, applied, dismissed, deselectedTaskIDs }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.reason = try c.decode(String.self, forKey: .reason)
        self.applied = try c.decodeIfPresent(Bool.self, forKey: .applied) ?? false
        self.dismissed = try c.decodeIfPresent(Bool.self, forKey: .dismissed) ?? false
        self.deselectedTaskIDs = try c.decodeIfPresent(Set<String>.self, forKey: .deselectedTaskIDs) ?? []
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind)
        try c.encode(reason, forKey: .reason); try c.encode(applied, forKey: .applied)
        try c.encode(dismissed, forKey: .dismissed); try c.encode(deselectedTaskIDs, forKey: .deselectedTaskIDs)
    }
}

extension TaskSuggestion.Kind: Codable {
    private enum K: String, Codable { case reschedule, reprioritize, assignProject, addTag, split, setProjectDeadline }
    private enum CK: String, CodingKey { case t, taskID, taskTitle, newDate, priority, taskIDs, taskTitles, projectName, existingProjectID, tag, parts, projectID, date }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CK.self)
        switch self {
        case let .reschedule(id, title, d):
            try c.encode(K.reschedule, forKey: .t); try c.encode(id, forKey: .taskID)
            try c.encode(title, forKey: .taskTitle); try c.encode(d, forKey: .newDate)
        case let .reprioritize(id, title, p):
            try c.encode(K.reprioritize, forKey: .t); try c.encode(id, forKey: .taskID)
            try c.encode(title, forKey: .taskTitle); try c.encode(p, forKey: .priority)
        case let .assignProject(ids, titles, name, existing):
            try c.encode(K.assignProject, forKey: .t); try c.encode(ids, forKey: .taskIDs)
            try c.encode(titles, forKey: .taskTitles); try c.encode(name, forKey: .projectName)
            try c.encodeIfPresent(existing, forKey: .existingProjectID)
        case let .addTag(ids, titles, tag):
            try c.encode(K.addTag, forKey: .t); try c.encode(ids, forKey: .taskIDs)
            try c.encode(titles, forKey: .taskTitles); try c.encode(tag, forKey: .tag)
        case let .split(id, title, parts):
            try c.encode(K.split, forKey: .t); try c.encode(id, forKey: .taskID)
            try c.encode(title, forKey: .taskTitle); try c.encode(parts, forKey: .parts)
        case let .setProjectDeadline(pid, name, d):
            try c.encode(K.setProjectDeadline, forKey: .t); try c.encode(pid, forKey: .projectID)
            try c.encode(name, forKey: .projectName); try c.encode(d, forKey: .date)
        }
    }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CK.self)
        switch try c.decode(K.self, forKey: .t) {
        case .reschedule:
            self = .reschedule(taskID: try c.decode(String.self, forKey: .taskID),
                               taskTitle: try c.decode(String.self, forKey: .taskTitle),
                               newDate: try c.decode(Date.self, forKey: .newDate))
        case .reprioritize:
            self = .reprioritize(taskID: try c.decode(String.self, forKey: .taskID),
                                 taskTitle: try c.decode(String.self, forKey: .taskTitle),
                                 priority: try c.decode(ActionItem.Priority.self, forKey: .priority))
        case .assignProject:
            self = .assignProject(taskIDs: try c.decode([String].self, forKey: .taskIDs),
                                  taskTitles: try c.decode([String].self, forKey: .taskTitles),
                                  projectName: try c.decode(String.self, forKey: .projectName),
                                  existingProjectID: try c.decodeIfPresent(String.self, forKey: .existingProjectID))
        case .addTag:
            self = .addTag(taskIDs: try c.decode([String].self, forKey: .taskIDs),
                           taskTitles: try c.decode([String].self, forKey: .taskTitles),
                           tag: try c.decode(String.self, forKey: .tag))
        case .split:
            self = .split(taskID: try c.decode(String.self, forKey: .taskID),
                          taskTitle: try c.decode(String.self, forKey: .taskTitle),
                          parts: try c.decode([String].self, forKey: .parts))
        case .setProjectDeadline:
            self = .setProjectDeadline(projectID: try c.decode(String.self, forKey: .projectID),
                                       projectName: try c.decode(String.self, forKey: .projectName),
                                       date: try c.decode(Date.self, forKey: .date))
        }
    }
}
