// MeetingScribeMCP — a minimal Model Context Protocol (MCP) server.
//
// Speaks newline-delimited JSON-RPC 2.0 over stdin/stdout. Exposes
// MeetingScribe's local artifacts (meetings, voice notes, transcripts, notes,
// summaries) as MCP tools that Claude Desktop / Claude Code can call.
//
// Performance (audit 1.5):
//   - On every tool call, the server previously walked every meeting
//     directory and decoded each meeting.json. Now it reads the cached
//     `.meeting-index.json` the app maintains. Falls back to a disk walk
//     only when the index is missing.
//   - Shared `JSONValue` / DTOs from `MeetingScribeShared` eliminate the
//     historical drift-prone reimplementations (audit 9.2).
import Foundation
import VaultKit
import SQLite3

// MARK: - Storage paths

let storageDir: URL = {
    if let path = ProcessInfo.processInfo.environment["MEETINGSCRIBE_STORAGE"], !path.isEmpty {
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return docs.appendingPathComponent("MeetingNotes", isDirectory: true)
}()

let reservedFolders: Set<String> = ["models", "QuickNotes", "logs", "diagnostics"]

// MARK: - Index-first meeting lookup

/// Versioned index file shape mirrored from the app's `MeetingStore.IndexFile`.
/// Tolerant of the legacy raw-array shape too.
struct IndexFile: Decodable {
    var schemaVersion: Int?
    var generatedAt: Date?
    var meetings: [MeetingDTO]
}

func loadIndex() -> [MeetingDTO]? {
    let url = storageDir.appendingPathComponent(".meeting-index.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    let dec = SharedCoders.decoder()
    if let env = try? dec.decode(IndexFile.self, from: data) { return env.meetings }
    return try? dec.decode([MeetingDTO].self, from: data)
}

/// Lazy resolution: try the index first, fall back to a one-time disk walk
/// (and cache the result for subsequent calls in this server's lifetime).
private var diskScanCache: [MeetingDTO]?

func allMeetings() -> [MeetingDTO] {
    if let indexed = loadIndex() { return indexed }
    if let cached = diskScanCache { return cached }
    let scanned = scanDiskForMeetings()
    diskScanCache = scanned
    return scanned
}

/// Disk fallback. Walks each meeting dir, decodes via SchemaEnvelope so the
/// new versioned shape AND legacy raw payload both work.
func scanDiskForMeetings() -> [MeetingDTO] {
    let fm = FileManager.default
    let top = (try? fm.contentsOfDirectory(at: storageDir,
                                            includingPropertiesForKeys: [.isDirectoryKey],
                                            options: [.skipsHiddenFiles])) ?? []
    var out: [MeetingDTO] = []
    for u in top {
        guard (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        if reservedFolders.contains(u.lastPathComponent) { continue }
        if let m = readMeetingJSON(at: u) {
            out.append(m)
            continue
        }
        let inner = (try? fm.contentsOfDirectory(at: u,
                                                  includingPropertiesForKeys: [.isDirectoryKey],
                                                  options: [.skipsHiddenFiles])) ?? []
        for sub in inner {
            guard (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let m = readMeetingJSON(at: sub) { out.append(m) }
        }
    }
    return out
}

/// Decode a meeting.json (either versioned envelope or legacy raw payload).
func readMeetingJSON(at dir: URL) -> MeetingDTO? {
    let url = dir.appendingPathComponent("meeting.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? SchemaEnvelope.decode(MeetingDTO.self,
                                      from: data,
                                      currentVersion: 2,
                                      decoder: SharedCoders.decoder())
}

/// Resolve a meeting's on-disk directory. Prefers the persisted
/// `relativeFolderPath` field (O(1)); falls back to a one-time walk.
func directoryForMeeting(_ m: MeetingDTO) -> URL {
    if let rel = m.relativeFolderPath, !rel.isEmpty {
        let url = storageDir.appendingPathComponent(rel, isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) { return url }
    }
    // Walk fallback.
    let fm = FileManager.default
    let top = (try? fm.contentsOfDirectory(at: storageDir,
                                            includingPropertiesForKeys: [.isDirectoryKey],
                                            options: [.skipsHiddenFiles])) ?? []
    for u in top {
        guard (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        if reservedFolders.contains(u.lastPathComponent) { continue }
        if readMeetingJSON(at: u)?.id == m.id { return u }
        let inner = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []
        for sub in inner {
            guard (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if readMeetingJSON(at: sub)?.id == m.id { return sub }
        }
    }
    return storageDir.appendingPathComponent("Untagged").appendingPathComponent(m.id)
}

func meeting(byID id: String) -> MeetingDTO? {
    allMeetings().first { $0.id == id }
}

// MARK: - Voice notes

func quickNoteDirectories() -> [URL] {
    let qDir = storageDir.appendingPathComponent("QuickNotes")
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(at: qDir,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
    return contents.filter {
        (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
        fm.fileExists(atPath: $0.appendingPathComponent("note.json").path)
    }
}

func readQuickNote(at dir: URL) -> QuickNoteDTO? {
    let url = dir.appendingPathComponent("note.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? SharedCoders.decoder().decode(QuickNoteDTO.self, from: data)
}

func directoryForQuickNote(id: String) -> URL? {
    quickNoteDirectories().first { readQuickNote(at: $0)?.id == id }
}

// MARK: - Tags

func loadTags() -> TagFileDTO? {
    let url = storageDir.appendingPathComponent("tags.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? SharedCoders.decoder().decode(TagFileDTO.self, from: data)
}

func tagNames(forMeetingID id: String, seriesID: String?, tags: TagFileDTO?) -> [String] {
    guard let tags else { return [] }
    let nameByID = Dictionary(uniqueKeysWithValues: tags.tags.map { ($0.id, $0.name) })
    var ids = tags.meetingTags[id] ?? []
    if let s = seriesID, let extra = tags.seriesTags[s] { ids += extra }
    var seen = Set<String>(); var names: [String] = []
    for tagID in ids where seen.insert(tagID).inserted {
        if let n = nameByID[tagID] { names.append(n) }
    }
    return names
}

// MARK: - File helpers

func readText(_ name: String, in dir: URL) -> String {
    let url = dir.appendingPathComponent(name)
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

// MARK: - Action items (read-only from disk)

func loadActionItemsFromDisk() -> [ActionItemDTO] {
    let url = storageDir.appendingPathComponent("action_items.json")
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? SharedCoders.decoder().decode([ActionItemDTO].self, from: data)) ?? []
}

// MARK: - People graph (Phase B/C second brain)
//
// Mirrors the in-app PeopleStore's on-disk layout:
//   <storage>/people/<slug>/person.json   (SchemaEnvelope-wrapped)
// Read-only. We don't write back. `peopleSchemaVersion` matches
// PeopleStore.personSchemaVersion in the main app.

let peopleSchemaVersion = 1

func peopleRoot() -> URL {
    storageDir.appendingPathComponent("people", isDirectory: true)
}

func loadAllPeople() -> [PersonDTO] {
    let root = peopleRoot()
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(at: root,
                                                  includingPropertiesForKeys: [.isDirectoryKey],
                                                  options: [.skipsHiddenFiles]) else {
        return []
    }
    var out: [PersonDTO] = []
    for dir in dirs {
        guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        let url = dir.appendingPathComponent("person.json")
        guard let data = try? Data(contentsOf: url) else { continue }
        if let p = try? SchemaEnvelope.decode(PersonDTO.self,
                                              from: data,
                                              currentVersion: peopleSchemaVersion,
                                              decoder: SharedCoders.decoder()) {
            out.append(p)
        }
    }
    return out
}

func person(byID id: String) -> PersonDTO? {
    loadAllPeople().first { $0.id == id }
}

/// Tolerant person lookup — mirrors PeopleChatTools.resolvePerson in the
/// main app. Small models often pass a name/email/phone instead of the
/// UUID. We resolve in order: UUID → exact name → exact email/phone →
/// single substring name match. Returns nil if nothing plausible matched.
func resolvePerson(_ idOrName: String) -> PersonDTO? {
    let trimmed = idOrName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let people = loadAllPeople()

    if let p = people.first(where: { $0.id == trimmed }) { return p }

    let lower = trimmed.lowercased()
    if let p = people.first(where: {
        $0.displayName.lowercased() == lower
    }) { return p }

    if let p = people.first(where: {
        $0.emails.contains(where: { $0.lowercased() == lower })
            || $0.phones.contains(where: { $0 == trimmed })
    }) { return p }

    let nameMatches = people.filter { $0.displayName.lowercased().contains(lower) }
    if nameMatches.count == 1 { return nameMatches[0] }
    return nil
}

func personMatches(_ p: PersonDTO, query q: String) -> Bool {
    if q.isEmpty { return true }
    if p.displayName.lowercased().contains(q) { return true }
    if p.company.lowercased().contains(q) { return true }
    if p.role.lowercased().contains(q) { return true }
    if p.emails.contains(where: { $0.lowercased().contains(q) }) { return true }
    if p.phones.contains(where: { $0.contains(q) }) { return true }
    return false
}

// MARK: - iMessage / SMS analysis (mirrors MessagesAnalyzer in main app)
//
// Opens ~/Library/Messages/chat.db read-only and runs the same handle-match
// + 1:1-chat-filter query the in-app MessagesAnalyzer uses, returning total
// counts, first/last dates, 30/90-day activity, and recent message snippets.
// Requires Full Disk Access (granted to the calling process — the MCP
// server inherits the app's TCC entitlements when launched from the
// bundle).

struct MessageStats {
    var total = 0
    var sent = 0
    var received = 0
    var firstDate: Date?
    var lastDate: Date?
    var last30 = 0
    var last90 = 0
    var matchedHandles: [String] = []
}

struct MessageSnippet {
    let fromMe: Bool
    let date: Date
    let text: String
}

enum MessageAnalysisError: Error {
    case needsFullDiskAccess
    case noHandles
    case sqlite(String)

    var message: String {
        switch self {
        case .needsFullDiskAccess:
            return "Can't read Messages. Grant Full Disk Access to MeetingScribe (or the MCP host process) in System Settings → Privacy & Security → Full Disk Access."
        case .noHandles:
            return "No phone number or email on this person matches a Messages conversation."
        case .sqlite(let m): return "Messages database error: \(m)"
        }
    }
}

func chatDBURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Messages/chat.db")
}

/// Last-10-digits comparison so "+1 (555) 123-4567" == "5551234567".
func normalizePhone(_ s: String) -> String {
    String(s.filter(\.isNumber).suffix(10))
}

func normalizeEmail(_ s: String) -> String {
    s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
}

/// chat.db stores dates as ns (modern) or s (legacy) since the 2001 ref date.
func appleDateToSwift(_ raw: Int64) -> Date {
    let seconds = raw > 1_000_000_000_000 ? Double(raw) / 1_000_000_000 : Double(raw)
    return Date(timeIntervalSinceReferenceDate: seconds)
}

func analyzeMessages(person p: PersonDTO, recentLimit: Int) throws -> (stats: MessageStats, recent: [MessageSnippet]) {
    let url = chatDBURL()
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw MessageAnalysisError.needsFullDiskAccess
    }
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, db != nil else {
        if db != nil { sqlite3_close(db) }
        throw MessageAnalysisError.needsFullDiskAccess
    }
    defer { sqlite3_close(db) }

    let emails = Set(p.emails.map(normalizeEmail).filter { !$0.isEmpty })
    let phones = Set(p.phones.map(normalizePhone).filter { $0.count >= 7 })
    guard !emails.isEmpty || !phones.isEmpty else {
        throw MessageAnalysisError.noHandles
    }

    // Walk all handles, keep ROWIDs that match this person's contact info.
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT ROWID, id FROM handle;", -1, &stmt, nil) == SQLITE_OK else {
        throw MessageAnalysisError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
    var handleIDs: [Int64] = []
    var matchedHandleStrings: [String] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        let rowID = sqlite3_column_int64(stmt, 0)
        guard let c = sqlite3_column_text(stmt, 1) else { continue }
        let handle = String(cString: c)
        if handle.contains("@") {
            if emails.contains(normalizeEmail(handle)) {
                handleIDs.append(rowID)
                matchedHandleStrings.append(handle)
            }
        } else {
            if phones.contains(normalizePhone(handle)) {
                handleIDs.append(rowID)
                matchedHandleStrings.append(handle)
            }
        }
    }
    sqlite3_finalize(stmt)
    guard !handleIDs.isEmpty else { throw MessageAnalysisError.noHandles }

    // Two scoped queries instead of one full table scan — see the
    // matching PERF comment in MessagesAnalyzer.swift. Mirrors the
    // in-app analyzer's behaviour so the numbers stay consistent
    // across the chat and Claude Desktop surfaces.
    let idList = handleIDs.map(String.init).joined(separator: ",")
    let nowSec = Date().timeIntervalSinceReferenceDate
    let cutoff30Ns = Int64((nowSec - 30 * 86400) * 1_000_000_000)
    let cutoff90Ns = Int64((nowSec - 90 * 86400) * 1_000_000_000)

    let chatFilter = """
    WHERE cmj.chat_id IN (
        SELECT chj.chat_id FROM chat_handle_join chj
        WHERE chj.handle_id IN (\(idList))
        AND chj.chat_id IN (
            SELECT chat_id FROM chat_handle_join GROUP BY chat_id HAVING COUNT(*) = 1
        )
    )
    """

    // --- 1) Aggregate stats ---
    let statsSQL = """
    SELECT
        COUNT(*)                                  AS total,
        COALESCE(SUM(m.is_from_me), 0)            AS sent,
        MIN(m.date)                               AS first_date,
        MAX(m.date)                               AS last_date,
        COALESCE(SUM(CASE WHEN m.date >= \(cutoff30Ns) THEN 1 ELSE 0 END), 0) AS last30,
        COALESCE(SUM(CASE WHEN m.date >= \(cutoff90Ns) THEN 1 ELSE 0 END), 0) AS last90
    FROM message m
    JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
    \(chatFilter);
    """
    var stats = MessageStats(matchedHandles: Array(Set(matchedHandleStrings)))
    var s1: OpaquePointer?
    guard sqlite3_prepare_v2(db, statsSQL, -1, &s1, nil) == SQLITE_OK else {
        throw MessageAnalysisError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
    if sqlite3_step(s1) == SQLITE_ROW {
        stats.total    = Int(sqlite3_column_int64(s1, 0))
        stats.sent     = Int(sqlite3_column_int64(s1, 1))
        stats.received = stats.total - stats.sent
        let firstRaw   = sqlite3_column_int64(s1, 2)
        let lastRaw    = sqlite3_column_int64(s1, 3)
        if firstRaw != 0 { stats.firstDate = appleDateToSwift(firstRaw) }
        if lastRaw  != 0 { stats.lastDate  = appleDateToSwift(lastRaw) }
        stats.last30   = Int(sqlite3_column_int64(s1, 4))
        stats.last90   = Int(sqlite3_column_int64(s1, 5))
    }
    sqlite3_finalize(s1)

    // --- 2) Recent snippets only ---
    let snippetSQL = """
    SELECT m.is_from_me, m.date, m.text, m.attributedBody,
           m.cache_has_attachments, m.associated_message_type
    FROM message m
    JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
    \(chatFilter)
    ORDER BY m.date DESC
    LIMIT \(max(1, recentLimit));
    """
    var s2: OpaquePointer?
    guard sqlite3_prepare_v2(db, snippetSQL, -1, &s2, nil) == SQLITE_OK else {
        throw MessageAnalysisError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(s2) }

    var snippetsDesc: [MessageSnippet] = []
    while sqlite3_step(s2) == SQLITE_ROW {
        let fromMe = sqlite3_column_int(s2, 0) == 1
        let date = appleDateToSwift(sqlite3_column_int64(s2, 1))
        var text = ""
        if let c = sqlite3_column_text(s2, 2) { text = String(cString: c) }

        if text.isEmpty, let bodyPtr = sqlite3_column_blob(s2, 3) {
            let bodyLen = Int(sqlite3_column_bytes(s2, 3))
            if bodyLen > 0 {
                let bodyData = Data(bytes: bodyPtr, count: bodyLen)
                if let recovered = extractTextFromAttributedBody(bodyData) {
                    text = recovered
                }
            }
        }

        let hasAttach = sqlite3_column_int(s2, 4) == 1
        let assocType = Int(sqlite3_column_int(s2, 5))
        if text.isEmpty {
            if assocType != 0 { text = "[reaction/tapback]" }
            else if hasAttach { text = "[image/attachment]" }
            else { text = "[message]" }
        }

        snippetsDesc.append(MessageSnippet(fromMe: fromMe, date: date, text: text))
    }
    return (stats, Array(snippetsDesc.reversed()))
}

/// Recover the underlying UTF-8 string from a Messages `attributedBody`
/// typedstream blob. Mirrors MessagesAnalyzer.extractText(fromAttributedBody:)
/// in the main app — see there for the full rationale, including why
/// the old "find any plausible length byte" approach returned "+" for
/// every message.
func extractTextFromAttributedBody(_ data: Data) -> String? {
    let marker = Array("NSString".utf8)
    let bytes = [UInt8](data)
    guard bytes.count > marker.count + 6,
          let markerStart = indexOfBytes(marker, in: bytes) else {
        return nil
    }
    let afterMarker = markerStart + marker.count
    let scanEnd = min(bytes.count, afterMarker + 40)
    var lastPlus: Int?
    for i in afterMarker..<scanEnd where bytes[i] == 0x2b {
        lastPlus = i
    }
    guard let plus = lastPlus, plus + 1 < bytes.count else { return nil }

    var idx = plus + 1
    let lengthByte = bytes[idx]
    idx += 1
    let length: Int
    switch lengthByte {
    case 0x00...0x7F:
        length = Int(lengthByte)
    case 0x81:
        guard idx + 2 <= bytes.count else { return nil }
        length = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
        idx += 2
    case 0x82:
        guard idx + 4 <= bytes.count else { return nil }
        length = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
               | (Int(bytes[idx + 2]) << 16) | (Int(bytes[idx + 3]) << 24)
        idx += 4
    default:
        return nil
    }
    guard length > 0, length < 65_536, idx + length <= bytes.count else { return nil }
    return String(bytes: bytes[idx..<idx + length], encoding: .utf8)
}

func indexOfBytes(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
    guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
    let last = haystack.count - needle.count
    for i in 0...last {
        if haystack[i..<i + needle.count].elementsEqual(needle) { return i }
    }
    return nil
}

// MARK: - Tools

let toolList: [JSONValue] = [
    .object([
        "name": "list_meetings",
        "description": "List past calls captured by MeetingScribe. Returns each meeting's id, title, time, tags, and whether it has a transcript/notes/summary.",
        "inputSchema": .object([
            "type": "object",
            "properties": .object([
                "limit": .object([
                    "type": "integer",
                    "description": "Max results. Default 100.",
                    "default": 100
                ]),
                "tag": .object([
                    "type": "string",
                    "description": "Optional: only return meetings tagged with this exact tag name."
                ])
            ])
        ])
    ]),
    .object([
        "name": "get_meeting",
        "description": "Get full details for one meeting: metadata, tags, transcript, my-notes, and summary.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object([
                "id": .object([
                    "type": "string",
                    "description": "Meeting id (from list_meetings)."
                ])
            ])
        ])
    ]),
    .object([
        "name": "get_transcript",
        "description": "Just the speech-to-text transcript for one meeting.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object(["id": .object(["type": "string"])])
        ])
    ]),
    .object([
        "name": "get_notes",
        "description": "Just my personal notes for one meeting.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object(["id": .object(["type": "string"])])
        ])
    ]),
    .object([
        "name": "get_summary",
        "description": "Just the AI-generated summary (with action items) for one meeting.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object(["id": .object(["type": "string"])])
        ])
    ]),
    .object([
        "name": "list_voice_notes",
        "description": "List all freestanding voice notes (Note Transcriber) with timestamps and snippets.",
        "inputSchema": .object([
            "type": "object",
            "properties": .object([
                "limit": .object(["type": "integer", "default": 100])
            ])
        ])
    ]),
    .object([
        "name": "get_voice_note",
        "description": "Get full transcript + metadata for one voice note.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object(["id": .object(["type": "string"])])
        ])
    ]),
    .object([
        "name": "list_people",
        "description": "Look up people in the user's second brain by name, email, or phone. ALWAYS call this first when the user asks about a specific person. Returns id, displayName, company, role, primary email/phone, last interaction, and counts of linked meetings/memories.",
        "inputSchema": .object([
            "type": "object",
            "properties": .object([
                "query": .object([
                    "type": "string",
                    "description": "Free-text search across name, company, role, and email. Substring match, case-insensitive."
                ]),
                "limit": .object([
                    "type": "integer",
                    "default": 20
                ])
            ])
        ])
    ]),
    .object([
        "name": "get_person",
        "description": "Full profile for one person: contact info, bio, memories, relationships, linked meeting IDs. The `id` argument accepts a UUID from list_people OR a display name / email / phone — the lookup is tolerant.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object(["id": .object(["type": "string"])])
        ])
    ]),
    .object([
        "name": "get_person_messages",
        "description": "iMessage / SMS conversation stats and recent message snippets for one person. Returns total/sent/received counts, first/last dates, 30/90-day activity, matched handles, and recent snippets. Requires Full Disk Access — if it errors, surface the message so the user knows what to enable. The `id` argument accepts a UUID from list_people OR a display name / email / phone.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object([
                "id": .object(["type": "string"]),
                "snippetLimit": .object([
                    "type": "integer",
                    "default": 20
                ])
            ])
        ])
    ]),
    .object([
        "name": "list_person_meetings",
        "description": "List meetings linked to a person — both calls they attended and calls whose transcript mentioned them. The `id` argument accepts a UUID from list_people OR a display name / email / phone.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object([
                "id": .object(["type": "string"]),
                "limit": .object(["type": "integer", "default": 50])
            ])
        ])
    ]),
    .object([
        "name": "list_action_items",
        "description": "List action items the MeetingScribe app has extracted from past meeting summaries. Filter by status (open/in_progress/completed) and/or meeting_id.",
        "inputSchema": .object([
            "type": "object",
            "properties": .object([
                "status": .object([
                    "type": "string",
                    "description": "Filter by status: open / in_progress / completed."
                ]),
                "meeting_id": .object([
                    "type": "string",
                    "description": "Limit to one meeting's action items."
                ]),
                "limit": .object([
                    "type": "integer",
                    "default": 200
                ])
            ])
        ])
    ])
]

func tool_listMeetings(args: [String: Any]) -> JSONValue {
    let limit = (args["limit"] as? Int) ?? 100
    let filterTag = args["tag"] as? String
    let tagFile = loadTags()

    var rows: [JSONValue] = []
    for m in allMeetings() {
        let dir = directoryForMeeting(m)
        let tags = tagNames(forMeetingID: m.id, seriesID: m.seriesID, tags: tagFile)
        if let f = filterTag, !tags.contains(where: { $0.caseInsensitiveCompare(f) == .orderedSame }) {
            continue
        }
        let hasTranscript = !readText("transcript.md", in: dir).isEmpty
        let hasNotes = !readText("notes.md", in: dir).isEmpty
        let hasSummary = !readText("summary.md", in: dir).isEmpty
        rows.append(.object([
            "id": .string(m.id),
            "title": .string(m.userTitle ?? m.title),
            "startDate": .string(iso(m.startDate)),
            "endDate": .string(iso(m.endDate)),
            "durationMinutes": .int(Int(m.endDate.timeIntervalSince(m.startDate) / 60)),
            "attendees": .array(m.attendees.map { .string($0) }),
            "tags": .array(tags.map { .string($0) }),
            "calendar": m.calendarName.map(JSONValue.string) ?? .null,
            "isImpromptu": .bool(m.isImpromptu ?? false),
            "hasTranscript": .bool(hasTranscript),
            "hasNotes": .bool(hasNotes),
            "hasSummary": .bool(hasSummary),
            "folder": .string(dir.path)
        ]))
    }
    rows.sort { lhs, rhs in
        guard case .object(let l) = lhs, case .object(let r) = rhs,
              case .string(let ls) = l["startDate"] ?? .null,
              case .string(let rs) = r["startDate"] ?? .null else { return false }
        return ls > rs
    }
    if rows.count > limit { rows = Array(rows.prefix(limit)) }
    return .object(["meetings": .array(rows), "count": .int(rows.count)])
}

func tool_getMeeting(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let m = meeting(byID: id) else {
        return .object(["error": .string("meeting not found")])
    }
    let dir = directoryForMeeting(m)
    let tags = tagNames(forMeetingID: m.id, seriesID: m.seriesID, tags: loadTags())
    var obj: [String: JSONValue] = [
        "id": .string(m.id),
        "title": .string(m.userTitle ?? m.title),
        "userDescription": m.userDescription.map(JSONValue.string) ?? .null,
        "startDate": .string(iso(m.startDate)),
        "endDate": .string(iso(m.endDate)),
        "attendees": .array(m.attendees.map { .string($0) }),
        "calendar": m.calendarName.map(JSONValue.string) ?? .null,
        "calendarNotes": m.notes.map(JSONValue.string) ?? .null,
        "conferenceURL": m.conferenceURL.map(JSONValue.string) ?? .null,
        "tags": .array(tags.map { .string($0) }),
        "isImpromptu": .bool(m.isImpromptu ?? false),
        "transcript": .string(readText("transcript.md", in: dir)),
        "notes": .string(readText("notes.md", in: dir)),
        "summary": .string(readText("summary.md", in: dir)),
        "folder": .string(dir.path)
    ]
    if let health = m.health {
        obj["health"] = .object([
            "status": .string(health.status.rawValue),
            "warnings": .array(health.warnings.map { .string($0) }),
            "recordedSeconds": .double(health.recordedSeconds)
        ])
    }
    return .object(obj)
}

func tool_getText(args: [String: Any], filename: String) -> JSONValue {
    guard let id = args["id"] as? String, let m = meeting(byID: id) else {
        return .object(["error": .string("meeting not found")])
    }
    return .object(["text": .string(readText(filename, in: directoryForMeeting(m)))])
}

func tool_listVoiceNotes(args: [String: Any]) -> JSONValue {
    let limit = (args["limit"] as? Int) ?? 100
    var rows: [JSONValue] = []
    for dir in quickNoteDirectories() {
        guard let n = readQuickNote(at: dir) else { continue }
        rows.append(.object([
            "id": .string(n.id),
            "title": .string(n.title),
            "createdAt": .string(iso(n.createdAt)),
            "durationSeconds": .double(n.durationSeconds),
            "snippet": .string(n.snippet),
            "wasDictation": .bool(n.wasDictation),
            "folder": .string(dir.path)
        ]))
    }
    rows.sort { lhs, rhs in
        guard case .object(let l) = lhs, case .object(let r) = rhs,
              case .string(let ls) = l["createdAt"] ?? .null,
              case .string(let rs) = r["createdAt"] ?? .null else { return false }
        return ls > rs
    }
    if rows.count > limit { rows = Array(rows.prefix(limit)) }
    return .object(["voiceNotes": .array(rows), "count": .int(rows.count)])
}

func tool_getVoiceNote(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let dir = directoryForQuickNote(id: id),
          let n = readQuickNote(at: dir) else {
        return .object(["error": .string("voice note not found")])
    }
    return .object([
        "id": .string(n.id),
        "title": .string(n.title),
        "createdAt": .string(iso(n.createdAt)),
        "durationSeconds": .double(n.durationSeconds),
        "wasDictation": .bool(n.wasDictation),
        "transcript": .string(readText("transcript.md", in: dir)),
        "audioPath": .string(dir.appendingPathComponent("audio.m4a").path),
        "folder": .string(dir.path)
    ])
}

func tool_listActionItems(args: [String: Any]) -> JSONValue {
    let status = (args["status"] as? String)?.lowercased()
    let meetingID = args["meeting_id"] as? String
    let limit = (args["limit"] as? Int) ?? 200
    var rows: [JSONValue] = []
    for item in loadActionItemsFromDisk() {
        if let s = status, !s.isEmpty {
            let normalized = item.status.lowercased()
            if normalized != s && !(s == "in_progress" && (normalized == "inprogress" || normalized == "in-progress")) {
                continue
            }
        }
        if let m = meetingID, !m.isEmpty, item.meetingID != m { continue }
        let iso = ISO8601DateFormatter()
        rows.append(.object([
            "id": .string(item.id),
            "title": .string(item.title),
            "owner": .string(item.owner ?? ""),
            "status": .string(item.status),
            "priority": .string(item.priority),
            "dueDate": .string(item.dueDate.map { iso.string(from: $0) } ?? ""),
            "meetingId": .string(item.meetingID),
            "meetingTitle": .string(item.meetingTitle),
            "meetingDate": .string(iso.string(from: item.meetingDate)),
            "notionPageId": .string(item.notionPageID ?? ""),
            "notionUrl": .string(item.notionURL ?? ""),
            "notes": .string(item.notes ?? "")
        ]))
        if rows.count >= limit { break }
    }
    return .object(["count": .int(rows.count), "actionItems": .array(rows)])
}

func tool_listPeople(args: [String: Any]) -> JSONValue {
    let q = ((args["query"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let limit = (args["limit"] as? Int) ?? 20
    let all = loadAllPeople()
    let matched: [PersonDTO]
    if q.isEmpty {
        matched = all.sorted {
            ($0.lastInteractionAt ?? .distantPast) > ($1.lastInteractionAt ?? .distantPast)
        }
    } else {
        matched = all.filter { personMatches($0, query: q) }
    }
    let rows: [JSONValue] = matched.prefix(limit).map { p in
        .object([
            "id": .string(p.id),
            "displayName": .string(p.displayName),
            "company": .string(p.company),
            "role": .string(p.role),
            "primaryEmail": .string(p.emails.first ?? ""),
            "primaryPhone": .string(p.phones.first ?? ""),
            "lastInteractionAt": .string(p.lastInteractionAt.map(iso) ?? ""),
            "meetingMentionCount": .int(p.meetingMentions.count),
            "memoryCount": .int(p.memories.count),
            "importSources": .array(p.importSources.map { .string($0) })
        ])
    }
    return .object([
        "query": .string(q),
        "count": .int(rows.count),
        "totalCandidates": .int(matched.count),
        "people": .array(rows)
    ])
}

func tool_getPerson(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let p = resolvePerson(id) else {
        let raw = (args["id"] as? String) ?? "(missing)"
        return .object(["error": .string(
            "no person matched `\(raw)` (tried as id, name, email, phone). Call list_people first to get the exact id.")])
    }
    let memories: [JSONValue] = p.memories.map { m in
        .object([
            "text": .string(m.text),
            "occurredOn": .string(m.occurredOn.map(iso) ?? ""),
            "createdAt": .string(iso(m.createdAt))
        ])
    }
    let relationships: [JSONValue] = p.relationships.map { r in
        let other = person(byID: r.toPersonID)
        return .object([
            "label": .string(r.label),
            "toPersonID": .string(r.toPersonID),
            "toDisplayName": .string(other?.displayName ?? "")
        ])
    }
    return .object([
        "id": .string(p.id),
        "displayName": .string(p.displayName),
        "company": .string(p.company),
        "role": .string(p.role),
        "emails": .array(p.emails.map { .string($0) }),
        "phones": .array(p.phones.map { .string($0) }),
        "addresses": .array(p.addresses.map { .string($0) }),
        "bio": .string(p.bio),
        "favorites": .array(p.favorites.map { .string($0) }),
        "memories": .array(memories),
        "relationships": .array(relationships),
        "birthday": .string(p.birthday.map(iso) ?? ""),
        "createdAt": .string(iso(p.createdAt)),
        "updatedAt": .string(iso(p.updatedAt)),
        "lastInteractionAt": .string(p.lastInteractionAt.map(iso) ?? ""),
        "meetingMentionIDs": .array(p.meetingMentions.map { .string($0) }),
        "importSources": .array(p.importSources.map { .string($0) })
    ])
}

func tool_getPersonMessages(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let p = resolvePerson(id) else {
        let raw = (args["id"] as? String) ?? "(missing)"
        return .object(["error": .string(
            "no person matched `\(raw)` (tried as id, name, email, phone). Call list_people first to get the exact id.")])
    }
    let snippetLimit = (args["snippetLimit"] as? Int) ?? 20
    do {
        let (stats, recent) = try analyzeMessages(person: p, recentLimit: snippetLimit)
        let snippets: [JSONValue] = recent.map { s in
            .object([
                "fromMe": .bool(s.fromMe),
                "label": .string(s.fromMe ? "Me" : p.displayName),
                "date": .string(iso(s.date)),
                "text": .string(s.text)
            ])
        }
        return .object([
            "personId": .string(p.id),
            "personDisplayName": .string(p.displayName),
            "total": .int(stats.total),
            "sent": .int(stats.sent),
            "received": .int(stats.received),
            "firstDate": .string(stats.firstDate.map(iso) ?? ""),
            "lastDate": .string(stats.lastDate.map(iso) ?? ""),
            "last30Days": .int(stats.last30),
            "last90Days": .int(stats.last90),
            "matchedHandles": .array(stats.matchedHandles.map { .string($0) }),
            "snippetCount": .int(snippets.count),
            "snippets": .array(snippets)
        ])
    } catch let e as MessageAnalysisError {
        return .object(["error": .string(e.message)])
    } catch {
        return .object(["error": .string(error.localizedDescription)])
    }
}

func tool_listPersonMeetings(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let p = resolvePerson(id) else {
        let raw = (args["id"] as? String) ?? "(missing)"
        return .object(["error": .string(
            "no person matched `\(raw)` (tried as id, name, email, phone). Call list_people first to get the exact id.")])
    }
    let limit = (args["limit"] as? Int) ?? 50
    let needle = p.displayName.lowercased()
    let mentioned = Set(p.meetingMentions)

    var rows: [JSONValue] = []
    var seen = Set<String>()
    for m in allMeetings() {
        let attendeeMatch = m.attendees.contains { $0.lowercased().contains(needle) }
        let mentionMatch = mentioned.contains(m.id)
        guard attendeeMatch || mentionMatch else { continue }
        guard seen.insert(m.id).inserted else { continue }
        rows.append(.object([
            "id": .string(m.id),
            "title": .string(m.userTitle ?? m.title),
            "startDate": .string(iso(m.startDate)),
            "attendees": .array(m.attendees.map { .string($0) }),
            "isImpromptu": .bool(m.isImpromptu ?? false),
            "viaAttendeeMatch": .bool(attendeeMatch),
            "viaTranscriptMention": .bool(mentionMatch)
        ]))
        if rows.count >= limit { break }
    }
    return .object([
        "personId": .string(p.id),
        "personDisplayName": .string(p.displayName),
        "count": .int(rows.count),
        "meetings": .array(rows)
    ])
}

func runTool(name: String, args: [String: Any]) -> JSONValue {
    switch name {
    case "list_meetings":         return tool_listMeetings(args: args)
    case "get_meeting":           return tool_getMeeting(args: args)
    case "get_transcript":        return tool_getText(args: args, filename: "transcript.md")
    case "get_notes":             return tool_getText(args: args, filename: "notes.md")
    case "get_summary":           return tool_getText(args: args, filename: "summary.md")
    case "list_voice_notes":      return tool_listVoiceNotes(args: args)
    case "get_voice_note":        return tool_getVoiceNote(args: args)
    case "list_action_items":     return tool_listActionItems(args: args)
    case "list_people":           return tool_listPeople(args: args)
    case "get_person":            return tool_getPerson(args: args)
    case "get_person_messages":   return tool_getPersonMessages(args: args)
    case "list_person_meetings":  return tool_listPersonMeetings(args: args)
    default: return .object(["error": .string("unknown tool: \(name)")])
    }
}

// MARK: - JSON-RPC loop

func writeResponse(id: Any?, result: JSONValue? = nil, error: (code: Int, message: String)? = nil) {
    var resp: [String: JSONValue] = ["jsonrpc": .string("2.0")]
    if let id {
        if let i = id as? Int { resp["id"] = .int(i) }
        else if let s = id as? String { resp["id"] = .string(s) }
        else { resp["id"] = .null }
    } else {
        resp["id"] = .null
    }
    if let result { resp["result"] = result }
    if let error {
        resp["error"] = .object([
            "code": .int(error.code),
            "message": .string(error.message)
        ])
    }
    let line = JSONValue.object(resp).compactJSON()
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func jsonContentResult(_ value: JSONValue) -> JSONValue {
    .object([
        "content": .array([
            .object([
                "type": .string("text"),
                "text": .string(value.prettyJSON())
            ])
        ])
    ])
}

let serverInfo: JSONValue = .object([
    "protocolVersion": .string("2024-11-05"),
    "capabilities": .object(["tools": .object([:])]),
    "serverInfo": .object([
        "name": .string("meetingscribe"),
        "version": .string("0.1.0")
    ])
])

func handle(line: String) {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
    }
    let id = obj["id"]
    let method = obj["method"] as? String ?? ""
    let params = obj["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        writeResponse(id: id, result: serverInfo)
    case "initialized", "notifications/initialized":
        return
    case "tools/list":
        writeResponse(id: id, result: .object(["tools": .array(toolList)]))
    case "tools/call":
        guard let name = params["name"] as? String else {
            writeResponse(id: id, error: (code: -32602, message: "Missing tool name"))
            return
        }
        let args = (params["arguments"] as? [String: Any]) ?? [:]
        let result = runTool(name: name, args: args)
        writeResponse(id: id, result: jsonContentResult(result))
    case "shutdown":
        writeResponse(id: id, result: .null)
        exit(0)
    case "ping":
        writeResponse(id: id, result: .object([:]))
    default:
        if id != nil {
            writeResponse(id: id, error: (code: -32601, message: "Method not found: \(method)"))
        }
    }
}

// MARK: - Main loop

setbuf(stdout, nil)
while let line = readLine(strippingNewline: true) {
    if line.isEmpty { continue }
    handle(line: line)
}
