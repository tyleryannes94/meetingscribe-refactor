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

/// Vault containment guard (E4-1). Returns the standardized URL only when it
/// resolves to a path inside `storageDir`; returns nil if it escapes the vault.
/// `standardizedFileURL` collapses `..` components, so a corrupt or hostile
/// `relativeFolderPath` (e.g. `../../../etc`) carried in a meeting.json can't
/// steer a write outside the vault. Prefix is matched on a path-component
/// boundary so a sibling like `<vault>-evil` can't masquerade as inside.
func resolveInsideVault(_ url: URL) -> URL? {
    let base = storageDir.standardizedFileURL
    let resolved = url.standardizedFileURL
    if resolved.path == base.path { return resolved }
    let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
    return resolved.path.hasPrefix(prefix) ? resolved : nil
}

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
        // E4-1: reject a stored path that escapes the vault before trusting it.
        if let safe = resolveInsideVault(url),
           FileManager.default.fileExists(atPath: safe.path) { return safe }
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

let actionItemSchemaVersion = 1

func actionItemsURL() -> URL { storageDir.appendingPathComponent("action_items.json") }

/// Decode-only envelope so DTOs that are Decodable-but-not-Encodable still work
/// (SchemaEnvelope itself requires Codable). Mirrors the on-disk `{data: …}`.
private struct DTOEnvelope<T: Decodable>: Decodable { let data: T }

func loadActionItemsFromDisk() -> [ActionItemDTO] {
    guard let data = try? Data(contentsOf: actionItemsURL()) else { return [] }
    // The app now writes a SchemaEnvelope ({schemaVersion, data:[...]}). Decode
    // envelope-or-legacy-array so this reader keeps working either way. (The
    // previous bare-array decode silently returned [] against enveloped files.)
    let dec = SharedCoders.decoder()
    if let env = try? dec.decode(DTOEnvelope<[ActionItemDTO]>.self, from: data) { return env.data }
    return (try? dec.decode([ActionItemDTO].self, from: data)) ?? []
}

// MARK: - Write support (raw-JSON patching)
//
// Write tools mutate the SAME on-disk files the app reads. To stay safe we
// NEVER decode-and-re-encode existing records through the (lossy) DTOs — that
// would strip fields the DTO doesn't model (subtasks, relationships, attached
// notes, photos…). Instead we patch the raw JSON: append a fully-formed new
// record, or patch specific keys on one record by id, leaving every other
// record byte-for-byte intact. So pre-existing data is never at risk.
//
// Limitation: if the app is running it holds these stores in memory and may
// rewrite a file from memory (e.g. on an in-app edit), which would drop an
// MCP-added record until the next launch. Pre-existing data is unaffected;
// only the just-added record could fail to stick. We post `vaultChanged` after
// every write so a future app build can reload on it.

enum MCPWriteError: Error { case io(String), notFound(String), badInput(String) }

/// ISO8601 string for now.
func isoNow() -> String { iso(Date()) }

/// Normalize a user-supplied date string to ISO8601, or nil if it can't be
/// parsed. Accepts full ISO8601 or a plain `yyyy-MM-dd` (interpreted as UTC
/// midnight). Returning nil lets callers OMIT the field rather than write an
/// unparseable date that would break the app's decoder for the whole record.
func normalizeISO8601(_ s: String) -> String? {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let isoF = ISO8601DateFormatter()
    if let d = isoF.date(from: trimmed) { return isoF.string(from: d) }
    let ymd = DateFormatter()
    ymd.calendar = Calendar(identifier: .gregorian)
    ymd.locale = Locale(identifier: "en_US_POSIX")
    ymd.timeZone = TimeZone(identifier: "UTC")
    ymd.dateFormat = "yyyy-MM-dd"
    if let d = ymd.date(from: trimmed) { return isoF.string(from: d) }
    return nil
}

/// Load `action_items.json` as raw JSON: (schemaVersion, array-of-record-dicts),
/// tolerating both the envelope and the legacy bare-array shape.
func loadActionItemsRaw() -> (version: Int, items: [[String: Any]]) {
    guard let data = try? Data(contentsOf: actionItemsURL()),
          let top = try? JSONSerialization.jsonObject(with: data) else {
        return (actionItemSchemaVersion, [])
    }
    if let dict = top as? [String: Any], let arr = dict["data"] as? [[String: Any]] {
        return (dict["schemaVersion"] as? Int ?? actionItemSchemaVersion, arr)
    }
    if let arr = top as? [[String: Any]] { return (actionItemSchemaVersion, arr) }
    return (actionItemSchemaVersion, [])
}

func writeActionItemsRaw(_ items: [[String: Any]]) throws {
    let env: [String: Any] = ["schemaVersion": actionItemSchemaVersion, "data": items]
    guard JSONSerialization.isValidJSONObject(env) else {
        throw MCPWriteError.io("action_items envelope is not valid JSON")
    }
    let data = try JSONSerialization.data(withJSONObject: env, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: actionItemsURL(), options: .atomic)
}

/// Find a person's on-disk directory by id (the slug embeds the display name,
/// which can change, so resolve by the stored id like directoryForMeeting).
func directoryForPerson(id: String) -> URL? {
    let root = peopleRoot()
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(at: root,
                                                  includingPropertiesForKeys: [.isDirectoryKey],
                                                  options: [.skipsHiddenFiles]) else { return nil }
    for dir in dirs {
        guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        let url = dir.appendingPathComponent("person.json")
        guard let data = try? Data(contentsOf: url),
              let top = try? JSONSerialization.jsonObject(with: data) else { continue }
        let payload = (top as? [String: Any]).flatMap { $0["data"] as? [String: Any] } ?? (top as? [String: Any])
        if payload?["id"] as? String == id { return dir }
    }
    return nil
}

/// Compute the people/<slug>/ name the app uses: sanitized display name +
/// "-" + first 8 chars of the id. Mirrors Person.slug.
func personSlug(displayName: String, id: String) -> String {
    let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
    let safe = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: invalid).joined(separator: "-")
    let name = safe.isEmpty ? "person" : String(safe.prefix(40))
    return "\(name)-\(id.prefix(8))"
}

func writePersonEnvelope(_ payload: [String: Any], to dir: URL) throws {
    // E4-1: never write a person record outside the vault.
    guard resolveInsideVault(dir) != nil else {
        throw MCPWriteError.io("refusing to write outside the vault: \(dir.path)")
    }
    let env: [String: Any] = ["schemaVersion": peopleSchemaVersion, "data": payload]
    guard JSONSerialization.isValidJSONObject(env) else {
        throw MCPWriteError.io("person envelope is not valid JSON")
    }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: env, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: dir.appendingPathComponent("person.json"), options: .atomic)
}

func signalVaultChanged() { DarwinNotifier.post(DarwinNotifier.vaultChanged) }

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
    ]),
    // MARK: write tools
    .object([
        "name": "create_action_item",
        "description": "Create a new task / action item in MeetingScribe. Use for to-dos the user asks you to capture. Optionally link it to a meeting via meeting_id (from list_meetings). Returns the new id.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["title"]),
            "properties": .object([
                "title": .object(["type": "string", "description": "What needs doing."]),
                "owner": .object(["type": "string", "description": "Who owns it (optional)."]),
                "status": .object(["type": "string", "description": "open / in_progress / completed. Default open."]),
                "priority": .object(["type": "string", "description": "low / medium / high / urgent. Default medium."]),
                "due_date": .object(["type": "string", "description": "Due date, ISO8601 or yyyy-MM-dd (optional)."]),
                "notes": .object(["type": "string", "description": "Extra detail (optional)."]),
                "meeting_id": .object(["type": "string", "description": "Link to a meeting (optional, from list_meetings)."])
            ])
        ])
    ]),
    .object([
        "name": "update_action_item",
        "description": "Update an existing action item by id (from list_action_items). Pass only the fields to change. Commonly used to mark a task completed (status=completed).",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object([
                "id": .object(["type": "string", "description": "Action item id from list_action_items."]),
                "title": .object(["type": "string"]),
                "status": .object(["type": "string", "description": "open / in_progress / completed."]),
                "priority": .object(["type": "string", "description": "low / medium / high / urgent."]),
                "owner": .object(["type": "string"]),
                "due_date": .object(["type": "string", "description": "ISO8601 or yyyy-MM-dd; empty string clears it."]),
                "notes": .object(["type": "string"])
            ])
        ])
    ]),
    .object([
        "name": "add_person",
        "description": "Add a new person to the user's second brain (CRM). Use when the user mentions someone not already in list_people. Returns the new id. To add facts to an existing person, use add_memory instead.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["display_name"]),
            "properties": .object([
                "display_name": .object(["type": "string", "description": "Full name."]),
                "company": .object(["type": "string"]),
                "role": .object(["type": "string"]),
                "email": .object(["type": "string", "description": "Email address (optional)."]),
                "phone": .object(["type": "string", "description": "Phone number (optional)."]),
                "bio": .object(["type": "string", "description": "Short freeform bio / context (optional)."])
            ])
        ])
    ]),
    .object([
        "name": "add_memory",
        "description": "Attach a memory (a durable fact or note) to a person in the second brain. The `id` accepts a UUID from list_people OR a display name / email / phone. Memories show newest-first on the person's profile.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id", "text"]),
            "properties": .object([
                "id": .object(["type": "string", "description": "Person id, name, email, or phone."]),
                "text": .object(["type": "string", "description": "The fact to remember."]),
                "occurred_on": .object(["type": "string", "description": "When it happened, ISO8601 or yyyy-MM-dd (optional)."])
            ])
        ])
    ]),
    .object([
        "name": "create_meeting_note",
        "description": "Append a note to a meeting's personal notes (notes.md). Never overwrites existing notes — appends with a dated header. Pass the meeting `id` from list_meetings.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id", "text"]),
            "properties": .object([
                "id": .object(["type": "string", "description": "Meeting id from list_meetings."]),
                "text": .object(["type": "string", "description": "Note text (markdown ok)."])
            ])
        ])
    ]),
    // Phase 4 — People relationship tools
    .object([
        "name": "list_encounters",
        "description": "Get the encounter/check-in history for a specific person — when you last met, call type, mood, and any notes. Use this to understand the relationship's health over time.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object([
                "id": .object(["type": "string", "description": "Person UUID, name, email, or phone."]),
                "limit": .object(["type": "integer", "default": 20])
            ])
        ])
    ]),
    .object([
        "name": "log_encounter",
        "description": "Log a check-in or encounter with a person. Use when the user says they just met, called, or messaged someone. Automatically updates the person's last-interaction date.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id", "kind"]),
            "properties": .object([
                "id": .object(["type": "string", "description": "Person UUID, name, email, or phone."]),
                "kind": .object(["type": "string", "description": "Type: Call, Coffee / Meal, Video Call, Message, Met Up, or Milestone."]),
                "notes": .object(["type": "string", "description": "Optional freeform notes about the encounter."]),
                "date": .object(["type": "string", "description": "ISO8601 date (defaults to now)."])
            ])
        ])
    ]),
    .object([
        "name": "get_check_in_status",
        "description": "Get the check-in health for a person: last encounter date, days since last contact, target cadence, and whether they are overdue.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object([
                "id": .object(["type": "string", "description": "Person UUID, name, email, or phone."])
            ])
        ])
    ]),
    .object([
        "name": "list_overdue_check_ins",
        "description": "List all people with typed relationships (partner, family, friend) who are overdue for a check-in, sorted by most overdue first.",
        "inputSchema": .object([
            "type": "object",
            "properties": .object([
                "limit": .object(["type": "integer", "default": 10])
            ])
        ])
    ]),
    .object([
        "name": "get_coaching_context",
        "description": "Get a comprehensive relationship coaching context for a person: relationship type, encounter frequency, birthday countdown, recommended framework, and health score. Use this to proactively coach the user on their relationship.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id"]),
            "properties": .object([
                "id": .object(["type": "string", "description": "Person UUID, name, email, or phone."])
            ])
        ])
    ]),
    .object([
        "name": "attach_note_to_person",
        "description": "Save a piece of text — typically an analysis output (relationship summary, coaching insight, sentiment analysis) — onto a person's record so the user can find it later. The note appears in the Notes section of the Person detail view.",
        "inputSchema": .object([
            "type": "object",
            "required": .array(["id", "title", "body"]),
            "properties": .object([
                "id": .object(["type": "string", "description": "Person UUID, name, email, or phone."]),
                "title": .object(["type": "string", "description": "Short title for the note."]),
                "body": .object(["type": "string", "description": "The note content (markdown ok)."]),
                "kind": .object(["type": "string", "description": "Category: summary, sentiment, coaching, custom. Default: custom."])
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

// MARK: - Write tools

/// Map a user-supplied status/priority onto the app's exact raw values.
func normalizeStatus(_ s: String?) -> String {
    switch (s ?? "open").lowercased().replacingOccurrences(of: "-", with: "_") {
    case "in_progress", "inprogress", "doing", "started": return "inProgress"
    case "completed", "complete", "done": return "completed"
    default: return "open"
    }
}
func normalizePriority(_ s: String?) -> String {
    switch (s ?? "medium").lowercased() {
    case "low": return "low"
    case "high": return "high"
    case "urgent", "critical": return "urgent"
    default: return "medium"
    }
}

func tool_createActionItem(args: [String: Any]) -> JSONValue {
    guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !title.isEmpty else {
        return .object(["error": .string("`title` is required")])
    }
    let id = UUID().uuidString
    let now = isoNow()
    var item: [String: Any] = [
        "id": id,
        "meetingID": (args["meeting_id"] as? String) ?? "",
        "meetingTitle": (args["meeting_title"] as? String) ?? "",
        "meetingDate": now,
        "title": title,
        "status": normalizeStatus(args["status"] as? String),
        "priority": normalizePriority(args["priority"] as? String),
        "source": "mcp",
        "createdAt": now,
        "updatedAt": now
    ]
    if let owner = args["owner"] as? String, !owner.isEmpty { item["owner"] = owner }
    if let notes = args["notes"] as? String, !notes.isEmpty { item["notes"] = notes }
    var dueWarning: String?
    if let due = args["due_date"] as? String, !due.isEmpty {
        if let isoDue = normalizeISO8601(due) { item["dueDate"] = isoDue }
        else { dueWarning = "ignored unparseable due_date `\(due)` (use ISO8601 or yyyy-MM-dd)" }
    }
    // If a meeting_id was given but no title, denormalize the meeting title/date
    // so the task shows correct context in the app's Tasks view.
    if let mid = args["meeting_id"] as? String, !mid.isEmpty, let m = meeting(byID: mid) {
        item["meetingTitle"] = m.userTitle ?? m.title
        item["meetingDate"] = iso(m.startDate)
    }
    do {
        var (_, items) = loadActionItemsRaw()
        items.append(item)
        try writeActionItemsRaw(items)
        signalVaultChanged()
        var result: [String: JSONValue] = ["ok": .bool(true), "id": .string(id),
                                           "title": .string(title)]
        if let w = dueWarning { result["warning"] = .string(w) }
        return .object(result)
    } catch {
        return .object(["error": .string("failed to write action item: \(error)")])
    }
}

func tool_updateActionItem(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, !id.isEmpty else {
        return .object(["error": .string("`id` is required (from list_action_items)")])
    }
    do {
        var (_, items) = loadActionItemsRaw()
        guard let idx = items.firstIndex(where: { ($0["id"] as? String) == id }) else {
            return .object(["error": .string("no action item with id `\(id)`")])
        }
        var item = items[idx]
        var changed: [String] = []
        if let t = args["title"] as? String, !t.isEmpty { item["title"] = t; changed.append("title") }
        if let s = args["status"] as? String { item["status"] = normalizeStatus(s); changed.append("status") }
        if let p = args["priority"] as? String { item["priority"] = normalizePriority(p); changed.append("priority") }
        if let o = args["owner"] as? String { item["owner"] = o; changed.append("owner") }
        if let n = args["notes"] as? String { item["notes"] = n; changed.append("notes") }
        if let due = args["due_date"] as? String {
            if due.isEmpty { item.removeValue(forKey: "dueDate"); changed.append("dueDate") }
            else if let isoDue = normalizeISO8601(due) { item["dueDate"] = isoDue; changed.append("dueDate") }
            else { return .object(["error": .string("unparseable due_date `\(due)`")]) }
        }
        guard !changed.isEmpty else {
            return .object(["error": .string("nothing to update — pass title/status/priority/owner/notes/due_date")])
        }
        item["updatedAt"] = isoNow()
        items[idx] = item
        try writeActionItemsRaw(items)
        signalVaultChanged()
        return .object(["ok": .bool(true), "id": .string(id),
                        "updated": .array(changed.map { .string($0) })])
    } catch {
        return .object(["error": .string("failed to update action item: \(error)")])
    }
}

func tool_addPerson(args: [String: Any]) -> JSONValue {
    guard let name = (args["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !name.isEmpty else {
        return .object(["error": .string("`display_name` is required")])
    }
    // Guard against obvious duplicates by exact name (case-insensitive).
    if let existing = loadAllPeople().first(where: { $0.displayName.lowercased() == name.lowercased() }) {
        return .object(["error": .string("a person named `\(name)` already exists (id \(existing.id)). Use add_memory to add to them, or pass a more specific name.")])
    }
    let id = UUID().uuidString
    let now = isoNow()
    func strArr(_ key: String) -> [Any] {
        if let a = args[key] as? [String] { return a.filter { !$0.isEmpty } }
        if let s = args[key] as? String, !s.isEmpty { return [s] }
        return []
    }
    // Write a COMPLETE payload (all arrays/strings present) so the app's
    // decoder never trips over a missing key regardless of how strictly it
    // decodes.
    let payload: [String: Any] = [
        "id": id,
        "displayName": name,
        "company": (args["company"] as? String) ?? "",
        "role": (args["role"] as? String) ?? "",
        "emails": strArr("email"),
        "phones": strArr("phone"),
        "addresses": [],
        "bio": (args["bio"] as? String) ?? "",
        "favorites": [],
        "memories": [],
        "relationships": [],
        "attachedNotes": [],
        "photoRelativePaths": [],
        "tagIDs": [],
        "meetingMentions": [],
        "importSources": ["mcp"],
        "createdAt": now,
        "updatedAt": now
    ]
    let dir = peopleRoot().appendingPathComponent(personSlug(displayName: name, id: id), isDirectory: true)
    do {
        try writePersonEnvelope(payload, to: dir)
        signalVaultChanged()
        return .object(["ok": .bool(true), "id": .string(id), "displayName": .string(name),
                        "folder": .string(dir.path)])
    } catch {
        return .object(["error": .string("failed to create person: \(error)")])
    }
}

func tool_addMemory(args: [String: Any]) -> JSONValue {
    guard let idOrName = args["id"] as? String, let p = resolvePerson(idOrName) else {
        let raw = (args["id"] as? String) ?? "(missing)"
        return .object(["error": .string("no person matched `\(raw)`. Call list_people first or use add_person.")])
    }
    guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !text.isEmpty else {
        return .object(["error": .string("`text` is required")])
    }
    guard let dir = directoryForPerson(id: p.id) else {
        return .object(["error": .string("couldn't locate person folder for `\(p.displayName)`")])
    }
    let url = dir.appendingPathComponent("person.json")
    guard let data = try? Data(contentsOf: url),
          let top = try? JSONSerialization.jsonObject(with: data) else {
        return .object(["error": .string("couldn't read person.json")])
    }
    // Recover the raw payload (envelope or legacy bare) WITHOUT decoding through
    // a DTO, so every existing field is preserved untouched.
    let isEnvelope = (top as? [String: Any])?["data"] is [String: Any]
    var payload = isEnvelope
        ? ((top as? [String: Any])?["data"] as? [String: Any]) ?? [:]
        : (top as? [String: Any]) ?? [:]
    guard !payload.isEmpty else {
        return .object(["error": .string("person.json had an unexpected shape")])
    }
    var memory: [String: Any] = [
        "id": UUID().uuidString,
        "text": text,
        "createdAt": isoNow()
    ]
    if let occurred = args["occurred_on"] as? String, !occurred.isEmpty,
       let isoOcc = normalizeISO8601(occurred) {
        memory["occurredOn"] = isoOcc
    }
    var memories = (payload["memories"] as? [[String: Any]]) ?? []
    memories.insert(memory, at: 0)   // newest first, matching the app
    payload["memories"] = memories
    payload["updatedAt"] = isoNow()
    do {
        try writePersonEnvelope(payload, to: dir)
        signalVaultChanged()
        return .object(["ok": .bool(true), "personId": .string(p.id),
                        "displayName": .string(p.displayName),
                        "memoryCount": .int(memories.count)])
    } catch {
        return .object(["error": .string("failed to add memory: \(error)")])
    }
}

func tool_createMeetingNote(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let m = meeting(byID: id) else {
        return .object(["error": .string("meeting not found — pass an `id` from list_meetings")])
    }
    guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !text.isEmpty else {
        return .object(["error": .string("`text` is required")])
    }
    let dir = directoryForMeeting(m)
    // E4-1: refuse to write if the resolved meeting folder escapes the vault.
    guard resolveInsideVault(dir) != nil else {
        return .object(["error": .string("refusing to write outside the vault")])
    }
    let url = dir.appendingPathComponent("notes.md")
    let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    // Append (never overwrite) so we can't destroy notes the user already
    // wrote. A dated header marks the Claude-added block.
    let header = "\n\n---\n_Added by Claude · \(isoNow())_\n\n"
    let combined = existing.isEmpty ? text : existing + header + text
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try combined.write(to: url, atomically: true, encoding: .utf8)
        signalVaultChanged()
        return .object(["ok": .bool(true), "meetingId": .string(m.id),
                        "appended": .bool(!existing.isEmpty), "folder": .string(dir.path)])
    } catch {
        return .object(["error": .string("failed to write note: \(error)")])
    }
}

// MARK: - Phase 4 People tools

func encountersDir() -> URL { storageDir.appendingPathComponent("encounters", isDirectory: true) }

/// Load all encounter JSON files for a given person ID. Falls back to
/// an empty array if the directory doesn't exist (new vault).
func loadEncounters(forPersonID personID: String) -> [[String: Any]] {
    let dir = encountersDir()
    guard let files = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                    includingPropertiesForKeys: nil,
                                                                    options: [.skipsHiddenFiles]) else {
        return []
    }
    var result: [[String: Any]] = []
    for f in files where f.pathExtension == "json" {
        guard let data = try? Data(contentsOf: f),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        // Encounter may be wrapped in SchemaEnvelope {version, data: {...}}
        let enc: [String: Any]
        if let inner = obj["data"] as? [String: Any] { enc = inner }
        else { enc = obj }
        guard let pid = enc["personID"] as? String, pid == personID else { continue }
        result.append(enc)
    }
    result.sort {
        let d0 = ($0["date"] as? String) ?? ""
        let d1 = ($1["date"] as? String) ?? ""
        return d0 > d1
    }
    return result
}

func tool_listEncounters(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let p = resolvePerson(id) else {
        let raw = (args["id"] as? String) ?? "(missing)"
        return .object(["error": .string("no person matched `\(raw)`. Call list_people first.")])
    }
    let limit = (args["limit"] as? Int) ?? 20
    let encs = loadEncounters(forPersonID: p.id).prefix(limit)
    let rows: [JSONValue] = encs.map { enc in
        .object([
            "id":        .string((enc["id"] as? String) ?? ""),
            "date":      .string((enc["date"] as? String) ?? ""),
            "kind":      .string((enc["eventName"] as? String) ?? ""),
            "notes":     .string((enc["notes"] as? String) ?? ""),
            "location":  .string((enc["location"] as? String) ?? "")
        ])
    }
    return .object([
        "personID":   .string(p.id),
        "personName": .string(p.displayName),
        "count":      .int(rows.count),
        "encounters": .array(rows)
    ])
}

func tool_logEncounter(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let p = resolvePerson(id) else {
        let raw = (args["id"] as? String) ?? "(missing)"
        return .object(["error": .string("no person matched `\(raw)`. Call list_people first.")])
    }
    let kind  = (args["kind"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Check-in"
    let notes = (args["notes"] as? String) ?? ""
    let date: Date
    if let dateStr = args["date"] as? String, let parsed = isoDate(dateStr) {
        date = parsed
    } else {
        date = Date()
    }
    let encID = UUID().uuidString
    let enc: [String: Any] = [
        "id": encID,
        "personID": p.id,
        "eventName": kind,
        "date": iso(date),
        "notes": notes,
        "createdAt": iso(Date())
    ]
    let envelope: [String: Any] = ["version": 1, "data": enc]
    let encURL = encountersDir().appendingPathComponent("\(encID).json")
    try? FileManager.default.createDirectory(at: encountersDir(), withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: encURL, options: .atomic)
    }
    // The running app will detect the new encounter file via its vault watcher
    // and update lastInteractionAt / the search index on next access.
    return .object([
        "ok":           .bool(true),
        "encounterId":  .string(encID),
        "personID":     .string(p.id),
        "personName":   .string(p.displayName),
        "kind":         .string(kind),
        "date":         .string(iso(date))
    ])
}

/// Default check-in cadence in days for a given relationship type raw value.
func defaultCadence(for relationshipTypeRaw: String?) -> Int {
    switch relationshipTypeRaw {
    case "romantic_partner": return 1
    case "family_member":    return 7
    case "close_friend":     return 14
    case "friend":           return 21
    case "colleague":        return 30
    case "acquaintance":     return 60
    default:                 return 14
    }
}

func tool_getCheckInStatus(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let p = resolvePerson(id) else {
        let raw = (args["id"] as? String) ?? "(missing)"
        return .object(["error": .string("no person matched `\(raw)`. Call list_people first.")])
    }
    let encs = loadEncounters(forPersonID: p.id)
    let lastEncDate: Date? = encs.compactMap { enc -> Date? in
        guard let s = enc["date"] as? String else { return nil }
        return isoDate(s)
    }.max()
    let lastDate = lastEncDate ?? p.lastInteractionAt ?? p.createdAt
    let cadence = p.checkInCadenceDays ?? defaultCadence(for: p.relationshipType)
    let daysSince = Int(Date().timeIntervalSince(lastDate) / 86400)
    let isOverdue = daysSince > cadence
    let overdueDays = max(0, daysSince - cadence)
    return .object([
        "personID":          .string(p.id),
        "personName":        .string(p.displayName),
        "relationshipType":  .string(p.relationshipType ?? "unset"),
        "cadenceDays":       .int(cadence),
        "lastEncounterDate": .string(iso(lastDate)),
        "daysSinceLast":     .int(daysSince),
        "isOverdue":         .bool(isOverdue),
        "overdueDays":       .int(overdueDays),
        "encounterCount":    .int(encs.count)
    ])
}

func tool_listOverdueCheckIns(args: [String: Any]) -> JSONValue {
    let limit = (args["limit"] as? Int) ?? 10
    let people = loadAllPeople()
    var rows: [(PersonDTO, Int)] = []
    for p in people {
        guard let rt = p.relationshipType, rt != "unset", !rt.isEmpty else { continue }
        let encs = loadEncounters(forPersonID: p.id)
        let lastDate: Date = encs.compactMap { enc -> Date? in
            guard let s = enc["date"] as? String else { return nil }
            return isoDate(s)
        }.sorted(by: >).first ?? p.lastInteractionAt ?? p.createdAt
        let cadence = p.checkInCadenceDays ?? defaultCadence(for: rt)
        let daysSince = Int(Date().timeIntervalSince(lastDate) / 86400)
        let overdue = daysSince - cadence
        if overdue > 0 { rows.append((p, overdue)) }
    }
    rows.sort { $0.1 > $1.1 }
    let result: [JSONValue] = rows.prefix(limit).map { (p, overdue) in
        .object([
            "personID":         .string(p.id),
            "personName":       .string(p.displayName),
            "relationshipType": .string(p.relationshipType ?? "unset"),
            "overdueDays":      .int(overdue)
        ])
    }
    return .object(["overdueCount": .int(rows.count), "people": .array(result)])
}

func tool_getCoachingContext(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let p = resolvePerson(id) else {
        let raw = (args["id"] as? String) ?? "(missing)"
        return .object(["error": .string("no person matched `\(raw)`. Call list_people first.")])
    }
    let encs = loadEncounters(forPersonID: p.id)
    let encCount = encs.count
    let dates: [Date] = encs.compactMap { enc -> Date? in
        guard let s = enc["date"] as? String else { return nil }
        return isoDate(s)
    }.sorted(by: >)
    let medianGapDays: Int
    if dates.count >= 2 {
        var gaps = (0..<(dates.count - 1)).map { i in
            Int(dates[i].timeIntervalSince(dates[i+1]) / 86400)
        }
        gaps.sort()
        medianGapDays = gaps[gaps.count / 2]
    } else {
        medianGapDays = 0
    }
    let lastDate = dates.first ?? p.lastInteractionAt ?? p.createdAt
    let daysSinceLast = Int(Date().timeIntervalSince(lastDate) / 86400)
    let cadence = p.checkInCadenceDays ?? defaultCadence(for: p.relationshipType)
    let isOverdue = daysSinceLast > cadence
    var birthdayDaysUntil: Int? = nil
    if let bday = p.birthday {
        let cal = Calendar.current
        var bdComp = cal.dateComponents([.month, .day], from: bday)
        let now = Date()
        bdComp.year = cal.component(.year, from: now)
        if let thisYear = cal.date(from: bdComp) {
            let diff = Int(thisYear.timeIntervalSince(now) / 86400)
            birthdayDaysUntil = diff >= 0 ? diff : Int((thisYear.addingTimeInterval(365 * 86400)).timeIntervalSince(now) / 86400)
        }
    }
    let framework: String
    switch p.relationshipType {
    case "romantic_partner": framework = "Gottman Method — focus on bids for connection, love languages, and repair"
    case "family_member":    framework = "NVC (Non-Violent Communication) — needs, feelings, and empathic listening"
    case "close_friend":     framework = "Love Languages + intentional time — quality time and acts of appreciation"
    default:                 framework = "Active listening and consistent follow-through"
    }
    var result: [String: JSONValue] = [
        "personID":             .string(p.id),
        "personName":           .string(p.displayName),
        "relationshipType":     .string(p.relationshipType ?? "unset"),
        "cadenceDays":          .int(cadence),
        "daysSinceLast":        .int(daysSinceLast),
        "isOverdue":            .bool(isOverdue),
        "encounterCount":       .int(encCount),
        "medianGapDays":        .int(medianGapDays),
        "recommendedFramework": .string(framework)
    ]
    if let bdDays = birthdayDaysUntil {
        result["birthdayDaysUntil"] = .int(bdDays)
    }
    return .object(result)
}

func tool_attachNoteToPerson(args: [String: Any]) -> JSONValue {
    guard let id = args["id"] as? String, let p = resolvePerson(id) else {
        let raw = (args["id"] as? String) ?? "(missing)"
        return .object(["error": .string("no person matched `\(raw)`. Call list_people first.")])
    }
    guard let body = (args["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !body.isEmpty else {
        return .object(["error": .string("body is required and cannot be empty")])
    }
    let title = (args["title"] as? String) ?? "Note"
    let kind  = (args["kind"] as? String) ?? "custom"
    let noteID = UUID().uuidString
    let note: [String: Any] = [
        "id": noteID,
        "title": title,
        "body": body,
        "kind": kind,
        "createdAt": iso(Date())
    ]
    // Patch the person.json — append to attachedNotes array using raw JSON.
    let personDir = storageDir.appendingPathComponent("people", isDirectory: true)
    // Find the person's directory by scanning for matching person.json files.
    if let contents = try? FileManager.default.contentsOfDirectory(
        at: personDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
        for dir in contents where dir.hasDirectoryPath {
            let jsonURL = dir.appendingPathComponent("person.json")
            guard var raw = try? JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any] else { continue }
            let stored: [String: Any]
            if let inner = raw["data"] as? [String: Any] { stored = inner }
            else { stored = raw }
            guard (stored["id"] as? String) == p.id else { continue }
            // Patch via raw JSON to avoid round-tripping through Codable (which
            // would strip unknown future fields).
            var patchTarget = (raw["data"] as? [String: Any]) ?? raw
            var notes = (patchTarget["attachedNotes"] as? [[String: Any]]) ?? []
            notes.insert(note, at: 0)
            patchTarget["attachedNotes"] = notes
            if raw["data"] != nil { raw["data"] = patchTarget } else { raw = patchTarget }
            if let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: jsonURL, options: .atomic)
            }
            break
        }
    }
    return .object([
        "ok":         .bool(true),
        "noteId":     .string(noteID),
        "personID":   .string(p.id),
        "personName": .string(p.displayName),
        "title":      .string(title),
        "kind":       .string(kind)
    ])
}

/// ISO8601 date parser for raw strings in the MCP (no Codable context available).
func isoDate(_ string: String) -> Date? {
    let df = ISO8601DateFormatter()
    df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = df.date(from: string) { return d }
    df.formatOptions = [.withInternetDateTime]
    return df.date(from: string)
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
    case "create_action_item":    return tool_createActionItem(args: args)
    case "update_action_item":    return tool_updateActionItem(args: args)
    case "add_person":            return tool_addPerson(args: args)
    case "add_memory":            return tool_addMemory(args: args)
    case "create_meeting_note":   return tool_createMeetingNote(args: args)
    // Phase 4 — People relationship tools
    case "list_encounters":       return tool_listEncounters(args: args)
    case "log_encounter":         return tool_logEncounter(args: args)
    case "get_check_in_status":   return tool_getCheckInStatus(args: args)
    case "list_overdue_check_ins": return tool_listOverdueCheckIns(args: args)
    case "get_coaching_context":  return tool_getCoachingContext(args: args)
    case "attach_note_to_person": return tool_attachNoteToPerson(args: args)
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
