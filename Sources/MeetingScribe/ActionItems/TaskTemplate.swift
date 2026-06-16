import Foundation

/// A reusable task blueprint (5-4): pre-filled title, priority, labels, subtasks,
/// estimate, recurrence, and optional context/project. Persisted to
/// `<storageDir>/task_templates.json`. Spawning a task from one is a single click
/// instead of re-typing a recurring chore's full shape every time.
struct TaskTemplate: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var defaultTitle: String = ""
    var defaultPriority: ActionItem.Priority = .medium
    var defaultLabelIDs: [String] = []
    var defaultEstimate: Double? = nil
    var defaultSubtasks: [String] = []
    var defaultRecurrence: RecurrenceRule? = nil
    var contextID: String? = nil
    var projectID: String? = nil
}
