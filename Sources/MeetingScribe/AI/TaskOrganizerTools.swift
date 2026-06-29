import Foundation
import VaultKit

/// One reviewed, not-yet-applied fix the organizer proposes for the user's
/// tasks. Transient (never persisted) — it lives only for the duration of the
/// review sheet.
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

/// Tool catalog + dispatcher for `TaskOrganizer`. Each tool RECORDS a suggestion
/// (via `onSuggestion`) rather than mutating the store — the user applies them.
@MainActor
final class TaskOrganizerTools {
    let store: ActionItemStore
    let onSuggestion: (TaskSuggestion) -> Void

    init(store: ActionItemStore, onSuggestion: @escaping (TaskSuggestion) -> Void) {
        self.store = store
        self.onSuggestion = onSuggestion
    }

    static var catalog: [AnthropicClient.Tool] {
        [
            .init(name: "reschedule_task",
                  description: "Propose a new due date for a task (e.g. move an overdue item to today or a near-future weekday).",
                  input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("task_id"), .string("date"), .string("reason")]),
                    "properties": .object([
                        "task_id": .object(["type": .string("string")]),
                        "date": .object(["type": .string("string"), "description": .string("YYYY-MM-DD")]),
                        "reason": .object(["type": .string("string")])
                    ])
                  ])),
            .init(name: "change_priority",
                  description: "Propose a different priority for a task.",
                  input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("task_id"), .string("priority"), .string("reason")]),
                    "properties": .object([
                        "task_id": .object(["type": .string("string")]),
                        "priority": .object(["type": .string("string"), "description": .string("low | medium | high | urgent")]),
                        "reason": .object(["type": .string("string")])
                    ])
                  ])),
            .init(name: "group_into_project",
                  description: "Propose assigning one or more tasks to a project. Use an existing project name when one fits, otherwise a short new project name (it will be created on apply).",
                  input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("task_ids"), .string("project_name"), .string("reason")]),
                    "properties": .object([
                        "task_ids": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                        "project_name": .object(["type": .string("string")]),
                        "reason": .object(["type": .string("string")])
                    ])
                  ])),
            .init(name: "apply_tag",
                  description: "Propose tagging one or more tasks with a short reusable tag (created if it doesn't exist).",
                  input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("task_ids"), .string("tag"), .string("reason")]),
                    "properties": .object([
                        "task_ids": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                        "tag": .object(["type": .string("string")]),
                        "reason": .object(["type": .string("string")])
                    ])
                  ]))
        ]
    }

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "reschedule_task":    return reschedule(input)
        case "change_priority":    return reprioritize(input)
        case "group_into_project": return groupIntoProject(input)
        case "apply_tag":          return applyTag(input)
        default:                   return nil
        }
    }

    // MARK: - Handlers

    private func reschedule(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["task_id"]?.asString, let task = task(id) else {
            return ack(false, "task not found")
        }
        guard let date = Self.parseDate(input["date"]?.asString) else {
            return ack(false, "bad date")
        }
        onSuggestion(.init(kind: .reschedule(taskID: id, taskTitle: task.title, newDate: date),
                           reason: input["reason"]?.asString ?? ""))
        return ack(true, "rescheduled")
    }

    private func reprioritize(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["task_id"]?.asString, let task = task(id) else {
            return ack(false, "task not found")
        }
        guard let p = ActionItem.Priority(rawValue: (input["priority"]?.asString ?? "").lowercased()) else {
            return ack(false, "bad priority")
        }
        onSuggestion(.init(kind: .reprioritize(taskID: id, taskTitle: task.title, priority: p),
                           reason: input["reason"]?.asString ?? ""))
        return ack(true, "reprioritized")
    }

    private func groupIntoProject(_ input: [String: JSONValue]) -> Result<String, Error> {
        let ids = stringArray(input["task_ids"]).filter { task($0) != nil }
        guard !ids.isEmpty, let name = input["project_name"]?.asString?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty else { return ack(false, "need task_ids + project_name") }
        let existing = store.projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let titles = ids.compactMap { task($0)?.title }
        onSuggestion(.init(kind: .assignProject(taskIDs: ids, taskTitles: titles,
                                                projectName: existing?.name ?? name,
                                                existingProjectID: existing?.id),
                           reason: input["reason"]?.asString ?? ""))
        return ack(true, existing == nil ? "new project" : "existing project")
    }

    private func applyTag(_ input: [String: JSONValue]) -> Result<String, Error> {
        let ids = stringArray(input["task_ids"]).filter { task($0) != nil }
        guard !ids.isEmpty, let tag = input["tag"]?.asString?.trimmingCharacters(in: .whitespaces),
              !tag.isEmpty else { return ack(false, "need task_ids + tag") }
        let titles = ids.compactMap { task($0)?.title }
        onSuggestion(.init(kind: .addTag(taskIDs: ids, taskTitles: titles, tag: tag),
                           reason: input["reason"]?.asString ?? ""))
        return ack(true, "tagged")
    }

    // MARK: - Helpers

    private func task(_ id: String) -> ActionItem? {
        store.items.first { $0.id == id && $0.deletedAt == nil }
    }

    private func stringArray(_ v: JSONValue?) -> [String] {
        guard case let .array(items) = (v ?? .null) else { return [] }
        return items.compactMap { $0.asString }
    }

    private func ack(_ ok: Bool, _ note: String) -> Result<String, Error> {
        .success("{\"ok\":\(ok),\"note\":\"\(note)\"}")
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
