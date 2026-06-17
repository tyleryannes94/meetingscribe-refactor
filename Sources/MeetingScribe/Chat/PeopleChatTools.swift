import Foundation
import VaultKit

/// Chat tools that expose the second-brain People graph. The chat already
/// knew about meetings, action items, and chat-folder files — but it had no
/// way to answer "summarize my last few texts with Horst" or "what have I
/// been working on with Jane?" because per-person data lives in
/// PeopleStore + MessagesAnalyzer, not MeetingStore.
///
/// Tools exposed (mirrors MeetingChatTools naming style so the model's mental
/// model is uniform):
///
///   • list_people            — find a person by name / email / phone
///   • get_person             — full profile + linked meetings + memories
///   • get_person_messages    — iMessage / SMS stats + recent snippets
///                              (requires Full Disk Access on the app)
///   • list_person_meetings   — meetings where this person was an attendee
///                              or was mentioned in the transcript
///
/// All reads are local — MessagesAnalyzer opens ~/Library/Messages/chat.db
/// read-only and nothing leaves the machine.
@MainActor
final class PeopleChatTools {
    let manager: MeetingManager
    init(manager: MeetingManager) { self.manager = manager }

    // MARK: - Tool catalog

    var tools: [AnthropicClient.Tool] {
        [
            .init(
                name: "list_people",
                description: "Look up people in the user's second brain by name, email, or phone. Use this FIRST whenever the user asks anything about a specific person ('texts with Horst', 'meetings with Jane', 'what's Bob's number'). Returns id, displayName, company, role, primary email/phone, last interaction date, and counts of linked meetings/memories.",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Free-text search across name, company, role, and email. Substring match, case-insensitive.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Max results. Default 20."),
                            "default": .int(20)
                        ])
                    ])
                ])
            ),
            .init(
                name: "get_person",
                description: "Full profile for one person: contact info, bio, favorites, tagged memories, importedFrom provenance, and the IDs of meetings they're linked to. Prefer passing the UUID from list_people, but a display name, email, or phone number is also accepted as a fallback.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id")]),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Person UUID from list_people, OR display name / email / phone — the lookup is tolerant.")
                        ])
                    ])
                ])
            ),
            .init(
                name: "get_person_messages",
                description: "iMessage / SMS conversation stats and recent message snippets for one person. Returns total/sent/received counts, first/last message dates, 30/90-day activity, the matched phone/email handles, and up to N recent snippets (label + date + text). Use this for any 'what did X text me', 'summarize my texts with X', or 'when did I last hear from X' question. Requires Full Disk Access — if the user hasn't granted it, returns a clear error explaining how. The `id` argument accepts a UUID from list_people OR a display name / email / phone.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id")]),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Person UUID from list_people, OR display name / email / phone — the lookup is tolerant.")
                        ]),
                        "snippetLimit": .object([
                            "type": .string("integer"),
                            "description": .string("Max recent message snippets to return. Default 20. Larger values slow the chat (the model has to re-read every snippet) — only ask for more when the user explicitly wants a long history."),
                            "default": .int(20)
                        ])
                    ])
                ])
            ),
            .init(
                name: "list_person_meetings",
                description: "List meetings linked to a person — both calls they attended (by name match on attendees) and calls whose transcript mentioned them (Phase B auto-extraction). Returns id, title, date, attendees, and which artifacts exist. The `id` argument accepts a UUID from list_people OR a display name / email / phone.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id")]),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Person UUID from list_people, OR display name / email / phone — the lookup is tolerant.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "default": .int(50)
                        ])
                    ])
                ])
            ),
            .init(
                name: "attach_note_to_person",
                description: "Save a piece of text — typically YOUR OWN analysis output (relationship summary, sentiment analysis, topics, custom report) — onto a person's record so the user can find it later. The note appears in the 'Notes' section of the Person detail view and is indexed for search. Use this whenever the user says 'save this', 'attach this to <person>', 'keep this analysis', or similar. Echo back the note id you receive so the user can confirm.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id"), .string("title"), .string("body")]),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Person UUID from list_people, OR display name / email / phone — the lookup is tolerant.")
                        ]),
                        "title": .object([
                            "type": .string("string"),
                            "description": .string("Short title for the note (5-8 words). Shown as the note's headline.")
                        ]),
                        "body": .object([
                            "type": .string("string"),
                            "description": .string("Full note body. Markdown allowed. This is what the user actually wants to keep — the analysis, summary, or report content.")
                        ]),
                        "kind": .object([
                            "type": .string("string"),
                            "description": .string("Short tag for the note's category. Common values: 'summary', 'sentiment', 'topics', 'style', 'custom'. Default 'custom'.")
                        ])
                    ])
                ])
            ),
            .init(
                name: "ask_about_person_messages",
                description: "Answer a free-text QUESTION about a person's past iMessages/SMS — e.g. 'what did they say about the launch date?', 'have they mentioned a new job?', 'when did they say they'd send the contract?'. Loads the conversation history and answers ONLY from what the messages actually say, quoting the relevant message + date when useful. Use this instead of get_person_messages when the user asks a specific question rather than wanting raw stats/snippets. Requires Full Disk Access. The `id` accepts a UUID / name / email / phone.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id"), .string("question")]),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Person UUID from list_people, OR display name / email / phone — the lookup is tolerant.")
                        ]),
                        "question": .object([
                            "type": .string("string"),
                            "description": .string("The natural-language question to answer from the person's message history.")
                        ])
                    ])
                ])
            )
        ]
    }

    // MARK: - Dispatch

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "list_people":             return .success(listPeople(input))
        case "get_person":              return getPerson(input)
        case "get_person_messages":     return getPersonMessages(input)
        case "ask_about_person_messages": return await askAboutPersonMessages(input)
        case "list_person_meetings":    return .success(listPersonMeetings(input))
        case "attach_note_to_person":   return attachNoteToPerson(input)
        default:                        return nil
        }
    }

    /// Local copy of PeopleStore's `Person.matches(_:)` — that one is
    /// `fileprivate` to PeopleStore.swift, so we can't reach it from
    /// outside that file. Cheap to inline; identical predicate.
    /// `q` is expected to already be lowercased.
    private func personMatches(_ p: Person, query q: String) -> Bool {
        if p.displayName.lowercased().contains(q) { return true }
        if p.company.lowercased().contains(q) { return true }
        if p.role.lowercased().contains(q) { return true }
        if p.emails.contains(where: { $0.lowercased().contains(q) }) { return true }
        if p.phones.contains(where: { $0.contains(q) }) { return true }
        return false
    }

    /// Tolerant person lookup. Small models (qwen2.5:7b, llama, etc.)
    /// will frequently pass `"Horst"` or `"horst@example.com"` instead
    /// of the actual UUID from list_people, even though the system
    /// prompt tells them otherwise. Rather than letting the tool fail
    /// with "person not found" — which causes the model to spiral
    /// instead of recovering — we resolve in this order:
    ///
    ///   1. Exact UUID match (`PeopleStore.person(by:)`)
    ///   2. Exact displayName match (case-insensitive)
    ///   3. Exact email or phone match (case-insensitive)
    ///   4. Substring displayName match, but only if it picks out a
    ///      single person — multiple matches stay ambiguous and we
    ///      return nil so the caller can prompt for disambiguation.
    ///
    /// Returns the resolved Person or nil if nothing plausible matched.
    private func resolvePerson(_ idOrName: String) -> Person? {
        let store = PeopleStore.shared
        let trimmed = idOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Exact UUID.
        if let p = store.person(by: trimmed) { return p }

        let lower = trimmed.lowercased()

        // 2. Exact displayName.
        if let p = store.people.first(where: {
            $0.displayName.lowercased() == lower
        }) { return p }

        // 3. Exact email / phone.
        if let p = store.people.first(where: {
            $0.emails.contains { $0.lowercased() == lower }
                || $0.phones.contains { $0 == trimmed }
        }) { return p }

        // 4. Single-substring displayName match.
        let nameMatches = store.people.filter {
            $0.displayName.lowercased().contains(lower)
        }
        if nameMatches.count == 1 { return nameMatches[0] }
        return nil
    }

    /// Standard error response when `resolvePerson` couldn't find a
    /// unique match. Includes the offending input so the model has
    /// something to course-correct on instead of looping with the
    /// same wrong identifier.
    private func personNotFoundError(_ tool: String, input: String) -> Error {
        AnthropicClient.ClientError.toolExecutionFailed(
            tool,
            "no person matched `\(input)` (tried as id, name, email, phone). " +
            "Call list_people first to get the exact id.")
    }

    // MARK: - Tool bodies

    private func listPeople(_ input: [String: JSONValue]) -> String {
        let query = input["query"]?.asString?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let limit = input["limit"]?.asInt ?? 20
        let store = PeopleStore.shared
        let matched: [Person]
        if query.isEmpty {
            // Default ordering: most-recent interaction first.
            matched = store.people.sorted {
                ($0.lastInteractionAt ?? .distantPast)
                    > ($1.lastInteractionAt ?? .distantPast)
            }
        } else {
            matched = store.people.filter { personMatches($0, query: query) }
        }

        let rows: [[String: Any]] = matched.prefix(limit).map { p in
            [
                "id": p.id,
                "displayName": p.displayName,
                "company": p.company,
                "role": p.role,
                "primaryEmail": p.primaryEmail,
                "primaryPhone": p.primaryPhone,
                "lastInteractionAt": p.lastInteractionAt.map(ChatToolHelpers.iso) ?? "",
                "meetingMentionCount": p.meetingMentions.count,
                "memoryCount": p.memories.count,
                "importSources": Array(p.importSources)
            ]
        }
        return ChatToolHelpers.jsonString([
            "query": query,
            "count": rows.count,
            "totalCandidates": matched.count,
            "people": rows
        ])
    }

    private func getPerson(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["id"]?.asString else {
            return .failure(personNotFoundError("get_person", input: "(missing id)"))
        }
        guard let p = resolvePerson(id) else {
            return .failure(personNotFoundError("get_person", input: id))
        }
        let memoryRows: [[String: Any]] = p.memories.map { m in
            [
                "text": m.text,
                "occurredOn": m.occurredOn.map(ChatToolHelpers.iso) ?? "",
                "createdAt": ChatToolHelpers.iso(m.createdAt)
            ]
        }
        let relationshipRows: [[String: Any]] = p.relationships.map { r in
            let other = PeopleStore.shared.person(by: r.toPersonID)
            return [
                "label": r.label,
                "toPersonID": r.toPersonID,
                "toDisplayName": other?.displayName ?? ""
            ]
        }
        let tagNames = p.tagIDs
            .compactMap { PeopleTagStore.shared.tag(by: $0)?.name }
            .sorted()

        let dict: [String: Any] = [
            "id": p.id,
            "displayName": p.displayName,
            "company": p.company,
            "role": p.role,
            "emails": p.emails,
            "phones": p.phones,
            "addresses": p.addresses,
            "bio": p.bio,
            "favorites": p.favorites,
            "memories": memoryRows,
            "relationships": relationshipRows,
            "tags": tagNames,
            "birthday": p.birthday.map(ChatToolHelpers.iso) ?? "",
            "createdAt": ChatToolHelpers.iso(p.createdAt),
            "updatedAt": ChatToolHelpers.iso(p.updatedAt),
            "lastInteractionAt": p.lastInteractionAt.map(ChatToolHelpers.iso) ?? "",
            "meetingMentionIDs": Array(p.meetingMentions),
            "importSources": Array(p.importSources)
        ]
        return .success(ChatToolHelpers.jsonString(dict))
    }

    private func getPersonMessages(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["id"]?.asString else {
            return .failure(personNotFoundError("get_person_messages", input: "(missing id)"))
        }
        guard let p = resolvePerson(id) else {
            return .failure(personNotFoundError("get_person_messages", input: id))
        }
        let snippetLimit = input["snippetLimit"]?.asInt ?? 20

        do {
            let result = try MessagesAnalyzer.analyze(person: p, recentLimit: snippetLimit)
            let snippets: [[String: Any]] = result.recent.map { s in
                [
                    "fromMe": s.fromMe,
                    "label": s.fromMe ? "Me" : p.displayName,
                    "date": ChatToolHelpers.iso(s.date),
                    "text": s.text
                ]
            }
            let dict: [String: Any] = [
                "personId": p.id,
                "personDisplayName": p.displayName,
                "total": result.stats.total,
                "sent": result.stats.sent,
                "received": result.stats.received,
                "firstDate": result.stats.firstDate.map(ChatToolHelpers.iso) ?? "",
                "lastDate": result.stats.lastDate.map(ChatToolHelpers.iso) ?? "",
                "last30Days": result.stats.last30,
                "last90Days": result.stats.last90,
                "matchedHandles": result.stats.matchedHandles,
                "snippetCount": snippets.count,
                "snippets": snippets
            ]
            return .success(ChatToolHelpers.jsonString(dict))
        } catch {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("get_person_messages",
                                     error.localizedDescription))
        }
    }

    /// Answer a natural-language question about a person's iMessage history,
    /// grounded only in their actual messages (local Ollama). Loads a wide
    /// window so questions about older texts work, capped for the model's ctx.
    private func askAboutPersonMessages(_ input: [String: JSONValue]) async -> Result<String, Error> {
        guard let id = input["id"]?.asString else {
            return .failure(personNotFoundError("ask_about_person_messages", input: "(missing id)"))
        }
        guard let p = resolvePerson(id) else {
            return .failure(personNotFoundError("ask_about_person_messages", input: id))
        }
        guard let question = input["question"]?.asString,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("ask_about_person_messages", "missing `question`."))
        }
        do {
            let result = try MessagesAnalyzer.analyze(person: p, recentLimit: 4000)
            guard !result.recent.isEmpty else {
                return .success(ChatToolHelpers.jsonString([
                    "personId": p.id, "answer": "No messages found with \(p.displayName).", "messageCount": 0
                ]))
            }
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let transcript = result.recent
                .map { "[\(df.string(from: $0.date))] \($0.fromMe ? "Me" : p.displayName): \($0.text)" }
                .joined(separator: "\n")
            let capped = String(transcript.suffix(24_000))
            let prompt = """
            Answer the question using ONLY the iMessage history below between Me and \(p.displayName). \
            Quote the relevant message(s) with their date when helpful. If the messages do not contain \
            the answer, say so plainly — do not guess or invent.

            Question: \(question)

            Messages (each line is "[date] sender: text"):
            \(capped)
            """
            let answer = try await OllamaService().generate(prompt: prompt, temperature: 0.1, numCtx: 16_384)
            return .success(ChatToolHelpers.jsonString([
                "personId": p.id,
                "personDisplayName": p.displayName,
                "question": question,
                "answer": answer,
                "messageCount": result.stats.total,
                "dateRange": "\(result.stats.firstDate.map(ChatToolHelpers.iso) ?? "?") to \(result.stats.lastDate.map(ChatToolHelpers.iso) ?? "?")"
            ]))
        } catch {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("ask_about_person_messages", error.localizedDescription))
        }
    }

    private func attachNoteToPerson(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["id"]?.asString else {
            return .failure(personNotFoundError("attach_note_to_person", input: "(missing id)"))
        }
        guard let p = resolvePerson(id) else {
            return .failure(personNotFoundError("attach_note_to_person", input: id))
        }
        guard let body = input["body"]?.asString,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("attach_note_to_person",
                                     "body is required and cannot be empty"))
        }
        let title = input["title"]?.asString ?? "Note"
        let kind  = input["kind"]?.asString ?? "custom"
        guard let saved = PeopleStore.shared.addAttachedNote(
                to: p.id, title: title, body: body, kind: kind) else {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("attach_note_to_person",
                                     "couldn't save note (person disappeared mid-write?)"))
        }
        return .success(ChatToolHelpers.jsonString([
            "personId": p.id,
            "personDisplayName": p.displayName,
            "noteId": saved.id,
            "title": saved.title,
            "kind": saved.kind,
            "createdAt": ChatToolHelpers.iso(saved.createdAt),
            "bodyLength": saved.body.count
        ]))
    }

    private func listPersonMeetings(_ input: [String: JSONValue]) -> String {
        guard let id = input["id"]?.asString,
              let p = resolvePerson(id) else {
            let inputStr = input["id"]?.asString ?? "(missing id)"
            return ChatToolHelpers.jsonString([
                "meetings": [], "count": 0,
                "error": "no person matched `\(inputStr)` (tried as id, name, email, phone). Call list_people first."
            ])
        }
        let limit = input["limit"]?.asInt ?? 50
        let needle = p.displayName.lowercased()
        let mentioned = p.meetingMentions

        let all = ChatToolHelpers.allMeetings(manager: manager)
        // A meeting counts as "linked" if (a) its transcript mentioned the
        // person (canonical Phase B link) OR (b) the person's name appears
        // in the attendee list (covers cases where auto-extraction hasn't
        // run yet but the calendar event named them).
        var seen = Set<String>()
        var rows: [[String: Any]] = []
        for m in all {
            let attendeeMatch = m.attendees.contains {
                $0.lowercased().contains(needle)
            }
            let mentionMatch = mentioned.contains(m.id)
            guard attendeeMatch || mentionMatch else { continue }
            guard seen.insert(m.id).inserted else { continue }
            rows.append([
                "id": m.id,
                "title": m.displayTitle,
                "startDate": ChatToolHelpers.iso(m.startDate),
                "attendees": m.attendees,
                "isImpromptu": m.isImpromptu,
                "viaAttendeeMatch": attendeeMatch,
                "viaTranscriptMention": mentionMatch
            ])
            if rows.count >= limit { break }
        }
        return ChatToolHelpers.jsonString([
            "personId": p.id,
            "personDisplayName": p.displayName,
            "count": rows.count,
            "meetings": rows
        ])
    }
}
