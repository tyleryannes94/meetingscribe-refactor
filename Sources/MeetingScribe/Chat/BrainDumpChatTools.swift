import Foundation
import VaultKit

/// Brain Dump tools exposed to the in-app chat. Lets the user say "drop this
/// into a new brain dump" in chat and have the session appear on the Brain
/// Dump page (TopLevelSection.brainDump) ready to plan.
///
/// Network-touching tools (`fetch_url`, `web_search`) are NOT exposed here —
/// those go through the dedicated Brain Dump planner so the
/// `assertGenericOutboundAllowed` egress gate is enforced at a single seam.
@MainActor
final class BrainDumpChatTools {
    let manager: MeetingManager
    let store: BrainDumpStore

    init(manager: MeetingManager, store: BrainDumpStore) {
        self.manager = manager
        self.store = store
    }

    var tools: [AnthropicClient.Tool] {
        [
            .init(
                name: "create_brain_dump_session",
                description: "Create a new Brain Dump session with an initial body. Returns the session id and a deep link.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("body")]),
                    "properties": .object([
                        "title": .object(["type": .string("string")]),
                        "body": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "list_brain_dump_sessions",
                description: "List recent Brain Dump sessions with id, title, state, draft and source counts.",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "limit": .object(["type": .string("integer"), "default": .int(10)])
                    ])
                ])
            ),
            .init(
                name: "add_to_brain_dump_session",
                description: "Append text to an existing Brain Dump session's body.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id"), .string("text")]),
                    "properties": .object([
                        "id": .object(["type": .string("string")]),
                        "text": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "organize_brain_dump_into_tasks",
                description: "Take a free-text brain dump and run the local planner on it: it proposes organized tasks (each with a priority, best-fit project, tags, and dedup against existing tasks — subtask/merge/link). Returns the proposed tasks for the user to review and accept in the Tasks › Brain Dump surface. Use this when the user dumps a bunch of thoughts/to-dos and wants them turned into organized tasks.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("body")]),
                    "properties": .object([
                        "title": .object(["type": .string("string")]),
                        "body": .object(["type": .string("string"), "description": .string("The full brain-dump text to organize.")])
                    ])
                ])
            )
        ]
    }

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "create_brain_dump_session": return create(input)
        case "list_brain_dump_sessions":  return list(input)
        case "add_to_brain_dump_session": return append(input)
        case "organize_brain_dump_into_tasks": return await organize(input)
        default:                          return nil
        }
    }

    /// Create a session from `body`, run the planner, and summarize the proposed
    /// tasks. The session lands in `.reviewing`, so the user opens Tasks › Brain
    /// Dump (deep link returned) to accept/reject.
    private func organize(_ input: [String: JSONValue]) async -> Result<String, Error> {
        let body = (input["body"]?.asString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return .failure(BrainDumpToolError.badInput("organize needs a non-empty body"))
        }
        let title = input["title"]?.asString
        let session = store.createSession(title: title, body: body)
        let actionItems = manager.actionItems
        do {
            let reasoning = try await BrainDumpPlanner().plan(
                sessionID: session.id,
                store: store,
                actionItems: actionItems,
                contexts: actionItems.contexts,
                progress: { _ in }
            )
            let drafts = store.session(session.id)?.drafts ?? []
            let taskRows: [String] = drafts.compactMap { draft in
                guard case let .task(t) = draft else { return nil }
                let project = t.suggestedProjectName ?? "none"
                let tags = (t.suggestedLabelNames ?? []).joined(separator: ", ")
                let rel = t.relation.map { "\($0.kind.rawValue) “\($0.existingTaskTitle)”" } ?? "new"
                return """
                {"title":"\(escape(t.title))","priority":"\(t.priorityRaw)","project":"\(escape(project))","tags":"\(escape(tags))","relation":"\(escape(rel))"}
                """
            }
            return .success("""
            {"ok":true,"id":"\(session.id)","deep_link":"meetingscribe://brain-dump/\(session.id)","proposed_tasks":[\(taskRows.joined(separator: ","))],"reasoning":"\(escape(reasoning ?? ""))","note":"Open Tasks › Brain Dump to review and accept these."}
            """)
        } catch {
            return .success("""
            {"ok":false,"id":"\(session.id)","error":"\(escape(error.localizedDescription))","note":"The brain dump was saved; the user can open Tasks › Brain Dump and press Plan with AI to retry."}
            """)
        }
    }

    private func create(_ input: [String: JSONValue]) -> Result<String, Error> {
        let body = input["body"]?.asString ?? ""
        let title = input["title"]?.asString
        let session = store.createSession(title: title, body: body)
        return .success("""
        {"ok":true,"id":"\(session.id)","deep_link":"meetingscribe://brain-dump/\(session.id)"}
        """)
    }

    private func list(_ input: [String: JSONValue]) -> Result<String, Error> {
        let limit = input["limit"]?.asInt ?? 10
        let rows = store.recentSessions(limit: limit).map { s -> String in
            let pending = s.pendingDrafts.count
            let accepted = s.acceptedDrafts.count
            return """
            {"id":"\(s.id)","title":"\(escape(s.displayTitle))","state":"\(s.state.rawValue)","sources":\(s.sources.count),"pending":\(pending),"accepted":\(accepted)}
            """
        }
        return .success("""
        {"sessions":[\(rows.joined(separator: ","))]}
        """)
    }

    private func append(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["id"]?.asString,
              let text = input["text"]?.asString else {
            return .failure(BrainDumpToolError.badInput("id + text required"))
        }
        guard let existing = store.session(id) else {
            return .failure(BrainDumpToolError.badInput("session not found"))
        }
        let separator = existing.body.isEmpty ? "" : "\n\n"
        store.updateBody(id, existing.body + separator + text)
        return .success("""
        {"ok":true,"id":"\(id)"}
        """)
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
