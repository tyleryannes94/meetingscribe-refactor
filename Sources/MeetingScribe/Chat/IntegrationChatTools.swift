import Foundation
import VaultKit

/// Chat tools that talk to external services the user has connected:
/// Linear, Google Drive, and the unified task-sync pump that pulls from
/// Linear + Notion at once.
///
/// Tools owned by this class:
///   sync_external_tasks, linear_list_projects, linear_list_teams,
///   linear_create_issue, export_meeting_to_drive
///
/// Each integration tool fails with a clear message if its credential
/// isn't configured (Settings → Integrations), so the model can tell
/// the user to set it up instead of hallucinating success.
@MainActor
final class IntegrationChatTools {
    let manager: MeetingManager
    init(manager: MeetingManager) { self.manager = manager }

    // MARK: - Tool catalog

    var tools: [AnthropicClient.Tool] {
        [
            .init(
                name: "sync_external_tasks",
                description: "Pull issues/tasks from connected Linear and Notion into the workspace's Tasks. Use when the user asks to refresh or import from Linear/Notion.",
                input_schema: .object(["type": .string("object"), "properties": .object([:])])
            ),
            .init(
                name: "linear_list_projects",
                description: "List the user's Linear projects (id + name). Requires a Linear key configured in Integrations.",
                input_schema: .object(["type": .string("object"), "properties": .object([:])])
            ),
            .init(
                name: "linear_list_teams",
                description: "List Linear teams (id/key/name). Needed to pick a team_id before creating a Linear issue.",
                input_schema: .object(["type": .string("object"), "properties": .object([:])])
            ),
            .init(
                name: "linear_create_issue",
                description: "Create an issue in Linear. Requires team_id (from linear_list_teams). Optional description and project_id (from linear_list_projects). Returns the new issue's identifier + URL.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("team_id"), .string("title")]),
                    "properties": .object([
                        "team_id": .object(["type": .string("string")]),
                        "title": .object(["type": .string("string")]),
                        "description": .object(["type": .string("string")]),
                        "project_id": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "export_meeting_to_drive",
                description: "Export a meeting's summary, notes, and transcript to the user's Google Drive folder as markdown. Requires Google Drive connected in Integrations. Returns the Drive file URL.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("meeting_id")]),
                    "properties": .object([
                        "meeting_id": .object(["type": .string("string")])
                    ])
                ])
            )
        ]
    }

    // MARK: - Tool dispatcher

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "sync_external_tasks":  return await syncExternalTasks()
        case "linear_list_projects": return await linearListProjects()
        case "linear_list_teams":    return await linearListTeams()
        case "linear_create_issue":  return await linearCreateIssue(input)
        case "export_meeting_to_drive": return await exportMeetingToDrive(input)
        default:                     return nil
        }
    }

    // MARK: - Tasks pump

    private func syncExternalTasks() async -> Result<String, Error> {
        await manager.syncExternalTasks()
        if let err = manager.lastTaskSyncError {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("sync_external_tasks", err))
        }
        return .success(ChatToolHelpers.jsonString(["ok": true, "summary": manager.lastTaskSyncSummary ?? "Synced."]))
    }

    // MARK: - Linear

    private func linearListProjects() async -> Result<String, Error> {
        guard let key = AppSettings.shared.linearAPIKey, !key.isEmpty else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("linear_list_projects", "No Linear key. Configure it in Integrations."))
        }
        do {
            let projects = try await TaskSyncService.fetchLinearProjects(apiKey: key)
            return .success(ChatToolHelpers.jsonString(["projects": projects.map { ["id": $0.id, "name": $0.name] }]))
        } catch { return .failure(error) }
    }

    private func linearListTeams() async -> Result<String, Error> {
        guard let key = AppSettings.shared.linearAPIKey, !key.isEmpty else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("linear_list_teams", "No Linear key. Configure it in Integrations."))
        }
        do {
            let teams = try await TaskSyncService.fetchLinearTeams(apiKey: key)
            return .success(ChatToolHelpers.jsonString(["teams": teams.map { ["id": $0.id, "key": $0.key, "name": $0.name] }]))
        } catch { return .failure(error) }
    }

    private func linearCreateIssue(_ input: [String: JSONValue]) async -> Result<String, Error> {
        guard let key = AppSettings.shared.linearAPIKey, !key.isEmpty else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("linear_create_issue", "No Linear key. Configure it in Integrations."))
        }
        guard let team = input["team_id"]?.asString, let title = input["title"]?.asString else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("linear_create_issue", "team_id and title required (call linear_list_teams first)."))
        }
        do {
            let r = try await TaskSyncService.createLinearIssue(
                apiKey: key, teamID: team, title: title,
                description: input["description"]?.asString,
                projectID: input["project_id"]?.asString)
            return .success(ChatToolHelpers.jsonString(["ok": true, "identifier": r.identifier, "url": r.url, "id": r.id]))
        } catch { return .failure(error) }
    }

    // MARK: - Google Drive export

    private func exportMeetingToDrive(_ input: [String: JSONValue]) async -> Result<String, Error> {
        guard let id = input["meeting_id"]?.asString,
              let m = ChatToolHelpers.allMeetings(manager: manager).first(where: { $0.id == id }) else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("export_meeting_to_drive", "meeting_id not found"))
        }
        guard GoogleDriveService.shared.isConnected else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("export_meeting_to_drive", "Google Drive isn't connected. Connect it in Integrations."))
        }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d 'at' h:mm a"
        let doc = MeetingExporter.combinedMarkdown(
            title: m.displayTitle, dateString: f.string(from: m.startDate),
            attendees: m.attendees,
            summary: manager.summaryMarkdown(for: m),
            notes: manager.userNotes(for: m),
            transcript: manager.transcriptMarkdown(for: m))
        do {
            let url = try await GoogleDriveService.shared.exportMarkdown(filename: m.slug, content: doc)
            return .success(ChatToolHelpers.jsonString(["ok": true, "url": url, "meeting": m.displayTitle]))
        } catch { return .failure(error) }
    }
}
