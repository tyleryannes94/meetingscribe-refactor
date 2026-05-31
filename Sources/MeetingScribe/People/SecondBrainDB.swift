import Foundation
import SQLite3
import OSLog

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Result type returned by the unified FTS search across all entity kinds.
struct VaultSearchResult {
    let entityID: String
    let entityKind: String
    let title: String?
    let dateEpoch: Int64?
    let rankScore: Double
}

/// SQLite + FTS5 query/index layer for the second brain (audit §6.1).
///
/// The JSON files under `people/` + `encounters/` remain the **canonical,
/// human-readable archive** (Finder/Obsidian-readable). This DB at
/// `~/Library/Application Support/MeetingScribe/secondbrain.db` is a
/// **derived index** rebuilt from that JSON, providing fast full-text
/// search ("purple party 2026" → people, sub-10ms) and scalable
/// tag/event queries without loading every JSON file.
///
/// Schema versions
/// ---------------
/// v1 – people + encounters_idx + search_index (FTS5, people only)
/// v2 – adds vault_content + vault_fts (unified FTS, all entity kinds)
///       + schema_meta; existing v1 tables are kept as-is.
@available(macOS 14.0, *)
@MainActor
final class SecondBrainDB {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "SecondBrainDB")
    static let schemaVersion = 2

    private var db: OpaquePointer?

    /// True when the database failed `quick_check` on open and was deleted +
    /// recreated empty. The owner (PeopleStore) repopulates it from the
    /// canonical JSON via `rebuild()`. (E3-4)
    private(set) var needsRebuild = false

    static var dbURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MeetingScribe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("secondbrain.db")
    }

    init() { open() }
    deinit { if db != nil { sqlite3_close(db) } }

    private func open() {
        guard openConnection() else { return }
        // E3-4: validate the derived index on open. A truncated/corrupt db
        // (power loss during a WAL checkpoint, disk-full) would otherwise
        // silently return empty results and the People graph — which the whole
        // product is built on — would go dark with no signal. The db is
        // derived from canonical JSON, so on failure we delete it, recreate an
        // empty schema, and flag the owner to rebuild.
        if !quickCheck() {
            log.error("secondbrain.db failed quick_check — deleting and rebuilding from canonical JSON")
            if db != nil { sqlite3_close(db); db = nil }
            Self.removeDatabaseFiles()
            guard openConnection() else { return }
            needsRebuild = true
        }
        ensureSchema()
    }

    /// Clears the rebuild flag once the owner has repopulated the index.
    func clearNeedsRebuild() { needsRebuild = false }

    private func openConnection() -> Bool {
        guard sqlite3_open(Self.dbURL.path, &db) == SQLITE_OK else {
            log.error("Failed to open secondbrain.db")
            db = nil
            return false
        }
        exec("PRAGMA journal_mode=WAL;")
        return true
    }

    /// `PRAGMA quick_check` — true iff SQLite reports the file is "ok". A
    /// failure to even prepare the statement is treated as corrupt.
    private func quickCheck() -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check;", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else {
            return false
        }
        return String(cString: c) == "ok"
    }

    /// Removes the main db file plus its WAL/SHM sidecars so a fresh,
    /// non-corrupt database is created on the next open.
    private static func removeDatabaseFiles() {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: dbURL.path + suffix))
        }
    }

    private func ensureSchema() {
        // Detect the stored schema version from schema_meta (v2+) or user_version (v1).
        let detectedVersion: Int
        if tableExists("schema_meta") {
            detectedVersion = scalarInt("SELECT value FROM schema_meta WHERE key='schema_version';") ?? 1
        } else {
            detectedVersion = scalarInt("PRAGMA user_version;") ?? 0
        }

        if detectedVersion < 1 {
            // Fresh database — create v1 tables so the v2 migration path below also runs.
            exec("""
            CREATE TABLE IF NOT EXISTS people (
                id TEXT PRIMARY KEY, display_name TEXT, company TEXT, role TEXT,
                last_interaction REAL, relevance REAL, ghost INTEGER, tag_ids TEXT
            );
            """)
            exec("""
            CREATE TABLE IF NOT EXISTS encounters_idx (
                id TEXT PRIMARY KEY, person_id TEXT, event_tag_id TEXT, date REAL
            );
            """)
            exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
                entity_kind, entity_id, primary_text, secondary_text, body, tags, date_iso
            );
            """)
        } else {
            // Ensure legacy tables are present even when upgrading from v1.
            exec("""
            CREATE TABLE IF NOT EXISTS people (
                id TEXT PRIMARY KEY, display_name TEXT, company TEXT, role TEXT,
                last_interaction REAL, relevance REAL, ghost INTEGER, tag_ids TEXT
            );
            """)
            exec("""
            CREATE TABLE IF NOT EXISTS encounters_idx (
                id TEXT PRIMARY KEY, person_id TEXT, event_tag_id TEXT, date REAL
            );
            """)
            exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
                entity_kind, entity_id, primary_text, secondary_text, body, tags, date_iso
            );
            """)
        }

        if detectedVersion < 2 {
            migrateToV2()
        }

        exec("PRAGMA user_version=\(Self.schemaVersion);")
    }

    // MARK: - Schema v2 migration

    private func migrateToV2() {
        log.info("Migrating SecondBrainDB to schema version 2")

        exec("""
        CREATE TABLE IF NOT EXISTS vault_content (
            entity_id     TEXT NOT NULL,
            entity_kind   TEXT NOT NULL CHECK(entity_kind IN ('person','meeting','encounter','action_item','voice_note')),
            title         TEXT,
            body          TEXT,
            date_epoch    INTEGER,
            tags          TEXT,
            PRIMARY KEY (entity_id, entity_kind)
        );
        """)

        exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS vault_fts USING fts5(
            title, body, tags,
            content='vault_content',
            content_rowid='rowid',
            tokenize='porter unicode61 remove_diacritics 1'
        );
        """)

        exec("""
        CREATE TRIGGER IF NOT EXISTS vault_fts_insert AFTER INSERT ON vault_content BEGIN
            INSERT INTO vault_fts(rowid, title, body, tags) VALUES (new.rowid, new.title, new.body, new.tags);
        END;
        """)

        exec("""
        CREATE TRIGGER IF NOT EXISTS vault_fts_update AFTER UPDATE ON vault_content BEGIN
            INSERT INTO vault_fts(vault_fts, rowid, title, body, tags) VALUES ('delete', old.rowid, old.title, old.body, old.tags);
            INSERT INTO vault_fts(rowid, title, body, tags) VALUES (new.rowid, new.title, new.body, new.tags);
        END;
        """)

        exec("""
        CREATE TRIGGER IF NOT EXISTS vault_fts_delete AFTER DELETE ON vault_content BEGIN
            INSERT INTO vault_fts(vault_fts, rowid, title, body, tags) VALUES ('delete', old.rowid, old.title, old.body, old.tags);
        END;
        """)

        exec("CREATE TABLE IF NOT EXISTS schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);")
        exec("INSERT OR REPLACE INTO schema_meta VALUES ('schema_version', '2');")
    }

    // MARK: - Rebuild / sync

    /// Full rebuild from the canonical in-memory snapshot. `tagName` resolves a
    /// people-tag id to its display name so tags are searchable by name.
    func rebuild(people: [Person], encounters: [Encounter], tagName: (String) -> String?) {
        // E3-4: roll back on any failed step so a mid-rebuild error (disk-full,
        // corruption) can't leave a committed, half-populated index.
        guard execChecked("BEGIN;") else { return }
        let cleared = execChecked("DELETE FROM people;")
            && execChecked("DELETE FROM encounters_idx;")
            && execChecked("DELETE FROM search_index;")
            && execChecked("DELETE FROM vault_content WHERE entity_kind='person';")
        guard cleared else {
            exec("ROLLBACK;")
            log.error("rebuild failed during clear — rolled back")
            return
        }
        let counts = Dictionary(encounters.map { ($0.personID, 1) }, uniquingKeysWith: +)
        for p in people { insertPerson(p, encounterCount: counts[p.id] ?? 0, tagName: tagName) }
        for e in encounters { insertEncounter(e) }
        if !execChecked("COMMIT;") {
            exec("ROLLBACK;")
            log.error("rebuild COMMIT failed — rolled back")
        }
    }

    func upsertPerson(_ p: Person, encounterCount: Int, tagName: (String) -> String?) {
        exec("DELETE FROM people WHERE id='\(escape(p.id))';")
        exec("DELETE FROM search_index WHERE entity_kind='person' AND entity_id='\(escape(p.id))';")
        exec("DELETE FROM vault_content WHERE entity_id='\(escape(p.id))' AND entity_kind='person';")
        insertPerson(p, encounterCount: encounterCount, tagName: tagName)
    }

    func deletePerson(_ id: String) {
        exec("DELETE FROM people WHERE id='\(escape(id))';")
        exec("DELETE FROM search_index WHERE entity_kind='person' AND entity_id='\(escape(id))';")
        exec("DELETE FROM encounters_idx WHERE person_id='\(escape(id))';")
        exec("DELETE FROM vault_content WHERE entity_id='\(escape(id))' AND entity_kind='person';")
    }

    private func insertPerson(_ p: Person, encounterCount: Int, tagName: (String) -> String?) {
        let tagNames = p.tagIDs.compactMap(tagName).joined(separator: " ")
        let relevance = p.relevanceScore(encounterCount: encounterCount)
        let ghost = p.isGhost(encounterCount: encounterCount) ? 1 : 0
        bindExec("INSERT INTO people (id, display_name, company, role, last_interaction, relevance, ghost, tag_ids) VALUES (?,?,?,?,?,?,?,?);",
                 [.text(p.id), .text(p.displayName), .text(p.company), .text(p.role),
                  .real(p.lastInteractionAt?.timeIntervalSince1970 ?? 0),
                  .real(relevance), .int(Int64(ghost)), .text(p.tagIDs.joined(separator: " "))])
        let secondary = (p.emails + p.phones + [p.company, p.role]).joined(separator: " ")
        bindExec("INSERT INTO search_index (entity_kind, entity_id, primary_text, secondary_text, body, tags, date_iso) VALUES ('person',?,?,?,?,?,?);",
                 [.text(p.id), .text(p.displayName), .text(secondary),
                  .text(p.bio + " " + p.favorites.joined(separator: " ") + " " + p.memories.map(\.text).joined(separator: " ")),
                  .text(tagNames), .text(iso(p.lastInteractionAt))])

        // Also insert into the unified vault_content / vault_fts.
        let bodyText = [secondary,
                        p.bio,
                        p.favorites.joined(separator: " "),
                        p.memories.map(\.text).joined(separator: " ")].joined(separator: " ")
        let epochVal: Int64 = p.lastInteractionAt.map { Int64($0.timeIntervalSince1970) } ?? 0
        bindExec("""
            INSERT OR REPLACE INTO vault_content (entity_id, entity_kind, title, body, date_epoch, tags)
            VALUES (?, 'person', ?, ?, ?, ?);
            """,
                 [.text(p.id), .text(p.displayName), .text(bodyText),
                  .int(epochVal), .text(tagNames)])
    }

    private func insertEncounter(_ e: Encounter) {
        bindExec("INSERT INTO encounters_idx (id, person_id, event_tag_id, date) VALUES (?,?,?,?);",
                 [.text(e.id), .text(e.personID), .text(e.eventTagID ?? ""), .real(e.date.timeIntervalSince1970)])
    }

    // MARK: - Vault content upsert (generic, for meetings / action_items / voice_notes)

    /// Insert or replace a row in `vault_content` for any entity kind.
    /// The FTS triggers keep `vault_fts` in sync automatically.
    func upsertVaultContent(entityID: String, entityKind: String, title: String?,
                            body: String?, dateEpoch: Int64?, tags: String?) {
        bindExec("""
            INSERT OR REPLACE INTO vault_content (entity_id, entity_kind, title, body, date_epoch, tags)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
                 [.text(entityID), .text(entityKind),
                  .text(title ?? ""), .text(body ?? ""),
                  .int(dateEpoch ?? 0), .text(tags ?? "")])
    }

    /// Delete a row from `vault_content` (FTS trigger handles vault_fts cleanup).
    func deleteVaultContent(entityID: String, entityKind: String) {
        exec("DELETE FROM vault_content WHERE entity_id='\(escape(entityID))' AND entity_kind='\(escape(entityKind))';")
    }

    // MARK: - Queries

    /// Full-text search → person ids ranked by FTS5 relevance (best first).
    func searchPersonIDs(_ query: String) -> [String] {
        let q = ftsQuery(query)
        guard !q.isEmpty else { return [] }
        return queryIDs("SELECT entity_id FROM search_index WHERE entity_kind='person' AND search_index MATCH ? ORDER BY rank;",
                        bind: q)
    }

    /// People ids carrying a tag OR with an encounter under that tag.
    func personIDs(forTagID tagID: String) -> [String] {
        var ids = Set(queryIDs("SELECT id FROM people WHERE (' '||tag_ids||' ') LIKE ?;", bind: "% \(tagID) %"))
        ids.formUnion(queryIDs("SELECT DISTINCT person_id FROM encounters_idx WHERE event_tag_id=?;", bind: tagID))
        return Array(ids)
    }

    /// Unified recency-boosted FTS search across all entity kinds.
    ///
    /// Uses bm25 with column weights (title×10, body×1, tags×0.5) combined
    /// with a linear recency factor that decays to zero at ~180 days.
    func searchAll(query: String, limit: Int = 50) -> [VaultSearchResult] {
        let q = ftsQuery(query)
        guard !q.isEmpty else { return [] }
        let sql = """
            SELECT vc.entity_id, vc.entity_kind, vc.title, vc.date_epoch,
                (bm25(vault_fts, 10.0, 1.0, 0.5) * (1.0 + 0.5 * MAX(0.0, 1.0 - (CAST(strftime('%s','now') AS REAL) - CAST(COALESCE(vc.date_epoch,0) AS REAL)) / 15552000.0))) AS rank_score
            FROM vault_fts
            JOIN vault_content vc ON vault_fts.rowid = vc.rowid
            WHERE vault_fts MATCH ?
            ORDER BY rank_score DESC LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("searchAll prepare failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, q, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(limit))
        var results: [VaultSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entityID   = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let entityKind = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let title      = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let dateEpoch  = sqlite3_column_type(stmt, 3) != SQLITE_NULL ? sqlite3_column_int64(stmt, 3) : nil
            let rankScore  = sqlite3_column_double(stmt, 4)
            results.append(VaultSearchResult(entityID: entityID, entityKind: entityKind,
                                             title: title, dateEpoch: dateEpoch, rankScore: rankScore))
        }
        return results
    }

    // MARK: - SQLite plumbing

    private enum Value { case text(String), int(Int64), real(Double) }

    private func bindExec(_ sql: String, _ values: [Value]) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("prepare failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int64(stmt, idx, n)
            case .real(let d): sqlite3_bind_double(stmt, idx, d)
            }
        }
        if sqlite3_step(stmt) != SQLITE_DONE {
            log.error("step failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
        }
    }

    private func queryIDs(_ sql: String, bind: String? = nil) -> [String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        if let bind { sqlite3_bind_text(stmt, 1, bind, -1, SQLITE_TRANSIENT) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { out.append(String(cString: c)) }
        }
        return out
    }

    private func scalarInt(_ sql: String) -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : nil
    }

    private func exec(_ sql: String) {
        _ = execChecked(sql)
    }

    /// Like `exec` but returns whether the statement succeeded, so a
    /// transaction can roll back on the first failure.
    @discardableResult
    private func execChecked(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let err {
                log.error("exec failed: \(String(cString: err), privacy: .public)")
                sqlite3_free(err)
            }
            return false
        }
        return true
    }

    private func tableExists(_ name: String) -> Bool {
        let sql = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int64(stmt, 0) > 0
    }

    // MARK: - Helpers

    /// Turns a user query into a safe FTS5 prefix query: tokenize, drop FTS
    /// operator chars, append `*` for prefix matching ("purp" → "purp*").
    private func ftsQuery(_ raw: String) -> String {
        let cleaned = raw.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        return cleaned.map { "\($0)*" }.joined(separator: " ")
    }

    private func escape(_ s: String) -> String { s.replacingOccurrences(of: "'", with: "''") }

    private func iso(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = ISO8601DateFormatter()
        return f.string(from: date)
    }
}
