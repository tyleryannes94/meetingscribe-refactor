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
                description: "Search decisions (both auto-captured from meetings and logged by hand on a project/feature) by topic, person, project, or status. Use for 'Why did we decide to use X?', 'What decisions were made on the <feature> project?', or 'List open decisions to make'. Returns each decision's text, rationale (the WHY), status (open=to make, resolved=made, superseded), date, people, and a clickable meetingscribe:// backlink to its project or meeting.",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Topic or keywords to search for. Leave empty to list recent decisions.")
                        ]),
                        "projectName": .object([
                            "type": .string("string"),
                            "description": .string("Optional project/feature name to scope to (fuzzy-matched). Use this for 'decisions on the <feature> project'.")
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
            ),
            .init(
                name: "search_reference_materials",
                description: "Find reference documents pinned to projects/features — scoping docs, design files, competitor analyses (web links or local files). Use for 'show me the design doc for <feature>' or 'what competitor analysis do we have for <feature>'. Returns each doc's title, kind, project, and a clickable link (the raw URL for web docs, or a meetingscribe://documentRef/ link that opens a local file).",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Keywords to match in the document title. Leave empty to list all materials for a project.")
                        ]),
                        "projectName": .object([
                            "type": .string("string"),
                            "description": .string("Optional project/feature name to scope to (fuzzy-matched).")
                        ])
                    ])
                ])
            )
        ]
    }

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "search_decisions": return .success(await searchDecisions(input))
        case "search_reference_materials": return .success(searchReferenceMaterials(input))
        default: return nil
        }
    }

    /// Fuzzy-resolve a project/feature name to its id (case-insensitive contains,
    /// preferring exact matches), so the model can pass a name not an id.
    private func resolveProjectID(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let lower = name.lowercased()
        let projects = manager.actionItems.projects
        if let exact = projects.first(where: { $0.name.lowercased() == lower }) { return exact.id }
        return projects.first(where: { $0.name.lowercased().contains(lower) })?.id
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
        if let projectID = resolveProjectID(input["projectName"]?.asString) ?? input["projectID"]?.asString {
            ordered = ordered.filter { $0.projectID == projectID }
        }

        let projectsByID = Dictionary(manager.actionItems.projects.map { ($0.id, $0.name) },
                                      uniquingKeysWith: { a, _ in a })
        let top = ordered.prefix(8).map { d -> [String: Any] in
            // Prefer a project backlink (where the decision lives now), else the
            // source meeting; always include a direct decision link too.
            let backlink: String
            if let pid = d.projectID { backlink = "meetingscribe://project/\(pid)" }
            else if let mid = d.meetingID { backlink = "meetingscribe://meeting/\(mid)" }
            else { backlink = "meetingscribe://decision/\(d.id)" }
            return [
                "text": d.text,
                "rationale": d.rationale ?? "",
                "status": d.status.label,   // To make / Made / Superseded
                "source": d.sourceLabel,
                "project": d.projectID.flatMap { projectsByID[$0] } ?? "",
                "date": ISO8601DateFormatter().string(from: d.date),
                "personIDs": d.personIDs,
                "backlink": backlink,
            ]
        }
        return ChatToolHelpers.jsonString(["decisions": top])
    }

    private func searchReferenceMaterials(_ input: [String: JSONValue]) -> String {
        let query = (input["query"]?.asString ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scopedProjectID = resolveProjectID(input["projectName"]?.asString)

        let projects = manager.actionItems.projects.filter { scopedProjectID == nil || $0.id == scopedProjectID }
        var out: [[String: Any]] = []
        for project in projects {
            for doc in (project.documents ?? []) where query.isEmpty || doc.title.lowercased().contains(query) {
                let link: String
                switch doc.payload {
                case .url(let s): link = s
                case .localFile: link = "meetingscribe://documentRef/\(project.id)::\(doc.id)"
                }
                out.append([
                    "title": doc.title,
                    "kind": doc.kind.label,
                    "project": project.name,
                    "location": doc.locationLabel,
                    "link": link,
                ])
            }
        }
        return ChatToolHelpers.jsonString(["materials": Array(out.prefix(12))])
    }
}

extension DecisionChatTools: ChatToolHandler {}
