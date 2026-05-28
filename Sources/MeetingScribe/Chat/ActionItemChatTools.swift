import Foundation
import VaultKit

/// Chat tools that read/mutate the user's action items, project board, and
/// the Notion mirror of action items.
///
/// Tools owned by this class:
///   list_action_items, set_action_status, set_action_priority,
///   set_action_due_date, push_action_item_to_notion, create_task,
///   list_projects
///
/// Notion push lives here (not in `IntegrationChatTools`) because the API
/// surface is action-item-centric — you pass an action-item id and the call
/// mutates the action item record with the resulting Notion page id/url.
@MainActor
final class ActionItemChatTools {
    let manager: MeetingManager
    init(manager: MeetingManager) { self.manager = manager }

    // MARK: - Tool catalog

    var tools: [AnthropicClient.Tool] {
        [
            .init(
                name: "list_action_items",
                description: "List action items extracted from meeting summaries. Filter by status (open/in_progress/completed) and/or meeting_id.",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "status": .object([
                            "type": .string("string"),
                            "description": .string("Filter by status. Values: open, in_progress, completed.")
                        ]),
                        "meeting_id": .object([
                            "type": .string("string"),
                            "description": .string("Limit to one meeting's action items.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "default": .int(100)
                        ])
                    ])
                ])
            ),
            .init(
                name: "set_action_status",
                description: "Set an action item's status. Values: open, in_progress, completed.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id"), .string("status")]),
                    "properties": .object([
                        "id": .object(["type": .string("string")]),
                        "status": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "set_action_priority",
                description: "Set an action item's priority. Values: low, medium, high, urgent.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id"), .string("priority")]),
                    "properties": .object([
                        "id": .object(["type": .string("string")]),
                        "priority": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "set_action_due_date",
                description: "Set or clear an action item's due date. Pass `due_date` as ISO8601 (e.g. 2026-05-22) or null to clear.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id")]),
                    "properties": .object([
                        "id": .object(["type": .string("string")]),
                        "due_date": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "push_action_item_to_notion",
                description: "Push an action item to the configured Notion database. Returns the new Notion page URL. Notion API key + database ID must be configured in Settings.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id")]),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "create_task",
                description: "Create a new task in the user's workspace. Optionally tie it to a project (project_id), set priority (low/medium/high/urgent), and a due date (ISO8601 like 2026-05-30).",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("title")]),
                    "properties": .object([
                        "title": .object(["type": .string("string")]),
                        "project_id": .object(["type": .string("string")]),
                        "priority": .object(["type": .string("string")]),
                        "due_date": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "list_projects",
                description: "List the workspace's projects (pages) and initiatives, with ids — useful before creating a task under a project.",
                input_schema: .object(["type": .string("object"), "properties": .object([:])])
            )
        ]
    }

    // MARK: - Tool dispatcher

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "list_action_items":        return .success(listActionItems(input))
        case "set_action_status":        return setActionStatus(input)
        case "set_action_priority":      return setActionPriority(input)
        case "set_action_due_date":      return setActionDueDate(input)
        case "push_action_item_to_notion": return await pushActionToNotion(input)
        case "create_task":              return .success(createTask(input))
        case "list_projects":            return .success(listProjects())
        default:                         return nil
        }
    }

    // MARK: - List

    private func listActionItems(_ input: [String: JSONValue]) -> String {
        let statusFilter = input["status"]?.asString
        let meetingFilter = input["meeting_id"]?.asString
        let limit = input["limit"]?.asInt ?? 100
        var rows: [[String: Any]] = []
        for item in manager.actionItems.items {
            if let s = statusFilter, !s.isEmpty,
               ChatToolHelpers.normalize(s) != ChatToolHelpers.normalize(item.status.rawValue) { continue }
            if let m = meetingFilter, !m.isEmpty, item.meetingID != m { continue }
            rows.append([
                "id": item.id,
                "title": item.title,
                "owner": item.owner ?? "",
                "status": item.status.rawValue,
                "priority": item.priority.rawValue,
                "dueDate": item.dueDate.map(ChatToolHelpers.iso) ?? "",
                "meetingId": item.meetingID,
                "meetingTitle": item.meetingTitle,
                "meetingDate": ChatToolHelpers.iso(item.meetingDate),
                "notionPageId": item.notionPageID ?? "",
                "notionUrl": item.notionURL ?? "",
                "notes": item.notes ?? ""
            ])
            if rows.count >= limit { break }
        }
        return ChatToolHelpers.jsonString(["count": rows.count, "actionItems": rows])
    }

    // MARK: - Mutations

    private func setActionStatus(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["id"]?.asString,
              let raw = input["status"]?.asString else {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("set_action_status", "id + status required"))
        }
        let mapped: ActionItem.Status
        switch ChatToolHelpers.normalize(raw) {
        case "open": mapped = .open
        case "in_progress", "inprogress", "in-progress": mapped = .inProgress
        case "completed", "done": mapped = .completed
        default:
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("set_action_status",
                                     "Unknown status \(raw). Use open / in_progress / completed."))
        }
        manager.actionItems.setStatus(id, status: mapped)
        return .success(ChatToolHelpers.jsonString(["ok": true, "id": id, "status": mapped.rawValue]))
    }

    private func setActionPriority(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["id"]?.asString,
              let raw = input["priority"]?.asString else {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("set_action_priority", "id + priority required"))
        }
        let mapped: ActionItem.Priority
        switch ChatToolHelpers.normalize(raw) {
        case "low": mapped = .low
        case "medium", "med": mapped = .medium
        case "high": mapped = .high
        case "urgent", "critical": mapped = .urgent
        default:
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("set_action_priority",
                                     "Unknown priority \(raw). Use low / medium / high / urgent."))
        }
        manager.actionItems.setPriority(id, priority: mapped)
        return .success(ChatToolHelpers.jsonString(["ok": true, "id": id, "priority": mapped.rawValue]))
    }

    private func setActionDueDate(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["id"]?.asString else {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("set_action_due_date", "id required"))
        }
        if case .null = input["due_date"] ?? .null {
            manager.actionItems.setDueDate(id, dueDate: nil)
            return .success(ChatToolHelpers.jsonString(["ok": true, "id": id, "due_date": NSNull()]))
        }
        guard let s = input["due_date"]?.asString else {
            manager.actionItems.setDueDate(id, dueDate: nil)
            return .success(ChatToolHelpers.jsonString(["ok": true, "id": id, "due_date": NSNull()]))
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) {
            manager.actionItems.setDueDate(id, dueDate: d)
            return .success(ChatToolHelpers.jsonString(["ok": true, "id": id, "due_date": ChatToolHelpers.iso(d)]))
        }
        // Try yyyy-MM-dd as a fallback.
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        if let d = df.date(from: s) {
            manager.actionItems.setDueDate(id, dueDate: d)
            return .success(ChatToolHelpers.jsonString(["ok": true, "id": id, "due_date": ChatToolHelpers.iso(d)]))
        }
        return .failure(AnthropicClient.ClientError
            .toolExecutionFailed("set_action_due_date",
                                 "Could not parse due_date '\(s)'. Use ISO8601 (e.g. 2026-05-22)."))
    }

    // MARK: - Notion push

    private func pushActionToNotion(_ input: [String: JSONValue]) async -> Result<String, Error> {
        guard let id = input["id"]?.asString,
              let item = manager.actionItems.items.first(where: { $0.id == id }) else {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("push_action_item_to_notion", "id not found"))
        }
        do {
            if item.notionPageID != nil {
                try await NotionActionItemService.update(item)
                return .success(ChatToolHelpers.jsonString([
                    "ok": true,
                    "id": id,
                    "notionPageId": item.notionPageID ?? "",
                    "notionUrl": item.notionURL ?? "",
                    "action": "updated"
                ]))
            } else {
                let result = try await NotionActionItemService.push(item)
                manager.actionItems.setNotion(id, pageID: result.id, url: result.url)
                return .success(ChatToolHelpers.jsonString([
                    "ok": true,
                    "id": id,
                    "notionPageId": result.id,
                    "notionUrl": result.url,
                    "action": "created"
                ]))
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Tasks / projects (create + list)

    private func createTask(_ input: [String: JSONValue]) -> String {
        let title = input["title"]?.asString ?? "New task"
        let projectID = input["project_id"]?.asString
        let priority = ActionItem.Priority(rawValue: ChatToolHelpers.normalize(input["priority"]?.asString ?? "")) ?? .medium
        let item = manager.actionItems.createTask(title: title, projectID: projectID, priority: priority)
        if let due = input["due_date"]?.asString, let d = ChatToolHelpers.parseDate(due) {
            manager.actionItems.setDueDate(item.id, dueDate: d)
        }
        return ChatToolHelpers.jsonString(["ok": true, "id": item.id, "title": item.title,
                                           "projectId": projectID ?? ""])
    }

    private func listProjects() -> String {
        let projects = manager.actionItems.projects.map { p in
            ["id": p.id, "name": p.name, "initiativeId": p.initiativeID ?? "",
             "openTasks": manager.actionItems.openCount(forProject: p.id)] as [String: Any]
        }
        let initiatives = manager.actionItems.initiatives.map { i in
            ["id": i.id, "name": i.name] as [String: Any]
        }
        return ChatToolHelpers.jsonString(["projects": projects, "initiatives": initiatives])
    }
}
