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
            )
        ]
    }

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "create_brain_dump_session": return create(input)
        case "list_brain_dump_sessions":  return list(input)
        case "add_to_brain_dump_session": return append(input)
        default:                          return nil
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
