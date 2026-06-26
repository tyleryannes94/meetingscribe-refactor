import Foundation
import VaultKit

/// Chat tools over the Decision Ledger (4-C / 4-G). Answers "Why did we decide
/// X?" by hybrid-searching the vault (decisions are FTS + embedding indexed since
/// P0-E/1-B) and returning the rationale, the people involved, status, and a
/// meeting backlink — so AI answers about decisions are grounded and citable.
@MainActor
final class DecisionChatTools {
    let manager: MeetingManager
    init(manager: MeetingManager) { self.manager = manager }

    var tools: [AnthropicClient.Tool] {
        [
            .init(
                name: "search_decisions",
                description: "Search the cross-meeting Decision Ledger by topic, person, project, or status. Use for questions like 'Why did we decide to use X?', 'What did we decide about the budget?', or 'List open decisions'. Returns each decision's text, its rationale (the WHY), the people involved, status, date, and a meetingscribe:// backlink.",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Topic or keywords to search for. Leave empty to list recent decisions.")
                        ]),
                        "personID": .object([
                            "type": .string("string"),
                            "description": .string("Optional Person id to filter to decisions involving them.")
                        ]),
                        "status": .object([
                            "type": .string("string"),
                            "description": .string("Optional status filter: open, superseded, or resolved.")
                        ])
                    ])
                ])
            )
        ]
    }

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "search_decisions": return .success(await searchDecisions(input))
        default: return nil
        }
    }

    private func searchDecisions(_ input: [String: JSONValue]) async -> String {
        let query = (input["query"]?.asString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let personID = input["personID"]?.asString
        let statusFilter = input["status"]?.asString.flatMap { DecisionStatus(rawValue: $0) }

        var ordered: [Decision]
        if query.isEmpty {
            ordered = manager.decisions.decisions.sorted { $0.date > $1.date }
        } else {
            // Semantic + lexical hybrid recall over the vault, decisions only.
            let hits = await PeopleStore.shared.searchVaultHybrid(query, limit: 20)
            let byID = Dictionary(manager.decisions.decisions.map { ($0.id, $0) },
                                  uniquingKeysWith: { a, _ in a })
            ordered = hits.filter { $0.entityKind == "decision" }.compactMap { byID[$0.entityID] }
            if ordered.isEmpty {   // fallback to a plain substring scan
                let q = query.lowercased()
                ordered = manager.decisions.decisions.filter {
                    $0.text.lowercased().contains(q) || ($0.rationale ?? "").lowercased().contains(q)
                }
            }
        }

        if let personID { ordered = ordered.filter { $0.personIDs.contains(personID) } }
        if let statusFilter { ordered = ordered.filter { $0.status == statusFilter } }

        let top = ordered.prefix(5).map { d -> [String: Any] in
            [
                "text": d.text,
                "rationale": d.rationale ?? "",
                "meetingTitle": d.sourceLabel,
                "date": ISO8601DateFormatter().string(from: d.date),
                "personIDs": d.personIDs,
                "status": d.status.rawValue,
                "backlink": d.meetingID.map { "meetingscribe://meeting/\($0)" } ?? "",
            ]
        }
        return ChatToolHelpers.jsonString(["decisions": top])
    }
}

extension DecisionChatTools: ChatToolHandler {}
