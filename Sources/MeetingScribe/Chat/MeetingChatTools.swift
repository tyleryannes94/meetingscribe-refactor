import Foundation
import VaultKit

/// Read-only Chat tools that surface meetings, transcripts, summaries, notes,
/// and voice notes. Owns no mutating state — every method either reads from
/// the in-memory `MeetingManager` or hits the filesystem-backed
/// `MeetingStore`/quick-notes store via the manager.
///
/// Tools owned by this class (call `tools` for the catalog Anthropic sees):
///   get_overview, list_meetings, get_meeting, get_transcript, get_notes,
///   get_summary, list_voice_notes, get_voice_note
@MainActor
final class MeetingChatTools {
    let manager: MeetingManager
    init(manager: MeetingManager) { self.manager = manager }

    // MARK: - Tool catalog

    var tools: [AnthropicClient.Tool] {
        [
            .init(
                name: "get_overview",
                description: "ALWAYS CALL THIS FIRST for any broad question about the user's meetings, action items, tasks, or recent activity. Returns a single compact digest: recent meetings (id/title/date), all open action items (title/owner/due/priority/meeting), and recent voice notes. One call answers most questions without needing other tools.",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "days": .object([
                            "type": .string("integer"),
                            "description": .string("How many days back to include meetings + voice notes. Default 14."),
                            "default": .int(14)
                        ])
                    ])
                ])
            ),
            .init(
                name: "list_meetings",
                description: "List the user's past meetings (most recent first). Returns id, title, start/end time, attendees, tags, and which artifacts exist (transcript, notes, summary).",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Max results. Default 50."),
                            "default": .int(50)
                        ]),
                        "tag": .object([
                            "type": .string("string"),
                            "description": .string("Optional exact tag name to filter on (e.g. 'Recharge', 'Skio').")
                        ])
                    ])
                ])
            ),
            .init(
                name: "get_meeting",
                description: "Full details for one meeting: metadata + transcript + notes + summary. Use after list_meetings to dive into a specific call.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id")]),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "get_transcript",
                description: "Just the speech-to-text transcript for one meeting.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id")]),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "get_notes",
                description: "Just the user's personal notes (notes.md) for one meeting.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id")]),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "get_summary",
                description: "AI-generated summary (with action items) for one meeting.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id")]),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "list_voice_notes",
                description: "List the user's freestanding voice notes (Note Transcriber + dictation). Returns id, title, createdAt, durationSeconds, snippet.",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "limit": .object(["type": .string("integer"), "default": .int(50)])
                    ])
                ])
            ),
            .init(
                name: "get_voice_note",
                description: "Full transcript + metadata for one voice note.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("id")]),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ])
                ])
            )
        ]
    }

    // MARK: - Tool dispatcher
    //
    // Returns nil if `name` isn't a tool we own — the façade `ChatTools`
    // uses that as a "not for me, try the next domain" signal.

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "get_overview":     return .success(getOverview(input))
        case "list_meetings":    return .success(listMeetings(input))
        case "get_meeting":      return getMeeting(input)
        case "get_transcript":   return getText(input, filename: "transcript.md")
        case "get_notes":        return getText(input, filename: "notes.md")
        case "get_summary":      return getText(input, filename: "summary.md")
        case "list_voice_notes": return .success(listVoiceNotes(input))
        case "get_voice_note":   return getVoiceNote(input)
        default:                 return nil
        }
    }

    // MARK: - Tool bodies

    /// One-shot digest: recent meetings + open action items + recent voice
    /// notes. Designed so a single tool call answers most broad questions —
    /// critical for small local models that struggle to chain many calls.
    private func getOverview(_ input: [String: JSONValue]) -> String {
        // Make sure action items have been extracted at least once (no-op if
        // already done) so chat-only sessions still see them.
        manager.backfillActionItemsIfNeeded()
        let days = input["days"]?.asInt ?? 14
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast

        let meetings = ChatToolHelpers.allMeetings(manager: manager)
            .filter { $0.startDate >= cutoff }
            .sorted { $0.startDate > $1.startDate }
        let meetingRows: [[String: Any]] = meetings.prefix(50).map { m in
            [
                "id": m.id,
                "title": m.displayTitle,
                "date": ChatToolHelpers.iso(m.startDate),
                "attendees": m.attendees
            ]
        }

        let openItems = manager.actionItems.items
            .filter { $0.status != .completed }
            .sorted { ($0.priority.weight, $1.meetingDate) > ($1.priority.weight, $0.meetingDate) }
        let itemRows: [[String: Any]] = openItems.prefix(100).map { a in
            [
                "id": a.id,
                "title": a.title,
                "owner": a.owner ?? "",
                "status": a.status.rawValue,
                "priority": a.priority.rawValue,
                "dueDate": a.dueDate.map(ChatToolHelpers.iso) ?? "",
                "meeting": a.meetingTitle
            ]
        }

        let notes = manager.quickNotes
            .filter { $0.createdAt >= cutoff }
            .prefix(20)
        let noteRows: [[String: Any]] = notes.map { n in
            ["id": n.id, "title": n.title, "createdAt": ChatToolHelpers.iso(n.createdAt), "snippet": n.snippet]
        }

        return ChatToolHelpers.jsonString([
            "windowDays": days,
            "meetingCount": meetingRows.count,
            "meetings": meetingRows,
            "openActionItemCount": itemRows.count,
            "openActionItems": itemRows,
            "voiceNotes": noteRows
        ])
    }

    private func listMeetings(_ input: [String: JSONValue]) -> String {
        let limit = input["limit"]?.asInt ?? 50
        let tagFilter = input["tag"]?.asString
        var rows: [[String: Any]] = []
        for m in ChatToolHelpers.allMeetings(manager: manager) {
            let tagNames = manager.tagStore.tags(for: m).map { $0.name }
            if let tf = tagFilter,
               !tagNames.contains(where: { $0.caseInsensitiveCompare(tf) == .orderedSame }) {
                continue
            }
            let primary = manager.tagStore.primaryTag(for: m)
            let dir = manager.store.directory(for: m, primaryTag: primary)
            let hasFile = { (name: String) -> Bool in
                guard let s = try? String(contentsOf: dir.appendingPathComponent(name),
                                          encoding: .utf8) else { return false }
                return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            rows.append([
                "id": m.id,
                "title": m.displayTitle,
                "startDate": ChatToolHelpers.iso(m.startDate),
                "endDate": ChatToolHelpers.iso(m.endDate),
                "durationMinutes": Int(m.endDate.timeIntervalSince(m.startDate) / 60),
                "attendees": m.attendees,
                "tags": tagNames,
                "calendar": m.calendarName as Any,
                "isImpromptu": m.isImpromptu,
                "hasTranscript": hasFile("transcript.md"),
                "hasNotes":      hasFile("notes.md"),
                "hasSummary":    hasFile("summary.md")
            ])
        }
        if rows.count > limit { rows = Array(rows.prefix(limit)) }
        return ChatToolHelpers.jsonString(["meetings": rows, "count": rows.count])
    }

    private func getMeeting(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["id"]?.asString,
              let m = ChatToolHelpers.allMeetings(manager: manager).first(where: { $0.id == id }) else {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("get_meeting", "meeting not found"))
        }
        let primary = manager.tagStore.primaryTag(for: m)
        let dir = manager.store.directory(for: m, primaryTag: primary)
        let read = { (n: String) -> String in
            (try? String(contentsOf: dir.appendingPathComponent(n), encoding: .utf8)) ?? ""
        }
        let dict: [String: Any] = [
            "id": m.id,
            "title": m.displayTitle,
            "userDescription": m.userDescription as Any,
            "startDate": ChatToolHelpers.iso(m.startDate),
            "endDate": ChatToolHelpers.iso(m.endDate),
            "attendees": m.attendees,
            "calendar": m.calendarName as Any,
            "calendarNotes": m.notes as Any,
            "conferenceURL": m.conferenceURL as Any,
            "tags": manager.tagStore.tags(for: m).map { $0.name },
            "isImpromptu": m.isImpromptu,
            "transcript": read("transcript.md"),
            "notes":      read("notes.md"),
            "summary":    read("summary.md")
        ]
        return .success(ChatToolHelpers.jsonString(dict))
    }

    private func getText(_ input: [String: JSONValue], filename: String) -> Result<String, Error> {
        guard let id = input["id"]?.asString,
              let m = ChatToolHelpers.allMeetings(manager: manager).first(where: { $0.id == id }) else {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("get_text", "meeting not found"))
        }
        let primary = manager.tagStore.primaryTag(for: m)
        let dir = manager.store.directory(for: m, primaryTag: primary)
        let s = (try? String(contentsOf: dir.appendingPathComponent(filename),
                             encoding: .utf8)) ?? ""
        return .success(ChatToolHelpers.jsonString(["text": s]))
    }

    private func listVoiceNotes(_ input: [String: JSONValue]) -> String {
        let limit = input["limit"]?.asInt ?? 50
        // Light refactor: was `var rows` in the old ChatTools.swift but never
        // mutated — Swift 6 strict-concurrency warned about it. Now a `let`.
        let rows: [[String: Any]] = manager.quickNotes.prefix(limit).map { n in
            return [
                "id": n.id,
                "title": n.title,
                "createdAt": ChatToolHelpers.iso(n.createdAt),
                "durationSeconds": n.durationSeconds,
                "snippet": n.snippet,
                "wasDictation": n.wasDictation
            ]
        }
        return ChatToolHelpers.jsonString(["voiceNotes": rows, "count": rows.count])
    }

    private func getVoiceNote(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let id = input["id"]?.asString,
              let n = manager.quickNotes.first(where: { $0.id == id }) else {
            return .failure(AnthropicClient.ClientError
                .toolExecutionFailed("get_voice_note", "voice note not found"))
        }
        let dict: [String: Any] = [
            "id": n.id,
            "title": n.title,
            "createdAt": ChatToolHelpers.iso(n.createdAt),
            "durationSeconds": n.durationSeconds,
            "wasDictation": n.wasDictation,
            "transcript": manager.readQuickNoteTranscript(n),
            "polished":   manager.readQuickNotePolished(n)
        ]
        return .success(ChatToolHelpers.jsonString(dict))
    }
}
