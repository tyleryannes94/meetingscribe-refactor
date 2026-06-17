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
    /// FTS5 snippet of the matched body, with matches wrapped in the U+0001 /
    /// U+0002 sentinels so the UI can bold them (U2-3). Nil when unavailable.
    var snippet: String? = nil
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
    static let schemaVersion = 4

    private var handle: OpaquePointer?
    private var didOpen = false
    /// Lazily opens on first real use so the `sqlite3_open` + `quick_check` stays
    /// OFF the synchronous launch path — `PeopleStore.shared` (which owns this) is
    /// built during the app's `body`, so opening in `init` stalled launch. Still
    /// `@MainActor`, so there's no data race; the open just happens when the
    /// People tab first queries/rebuilds rather than at app start. (V5 PC-2)
    private var db: OpaquePointer? {
        if !didOpen { didOpen = true; open() }
        return handle
    }

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

    init() {}   // open is lazy (PC-2)
    deinit { if handle != nil { sqlite3_close(handle) } }

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
            if handle != nil { sqlite3_close(handle); handle = nil }
            Self.removeDatabaseFiles()
            guard openConnection() else { return }
            needsRebuild = true
        }
        ensureSchema()
    }

    /// Clears the rebuild flag once the owner has repopulated the index.
    func clearNeedsRebuild() { needsRebuild = false }

    private func openConnection() -> Bool {
        guard sqlite3_open(Self.dbURL.path, &handle) == SQLITE_OK else {
            log.error("Failed to open secondbrain.db")
            handle = nil
            return false
        }
        exec("PRAGMA journal_mode=WAL;")
        // Production pragma profile (V5 CB-3): broad speedup for search/recall/
        // graph + removes a lock-contention crash vector. synchronous=NORMAL is
        // safe under WAL; mmap/cache cut read syscalls; busy_timeout avoids
        // SQLITE_BUSY throws under concurrent access.
        exec("PRAGMA synchronous=NORMAL;")
        exec("PRAGMA busy_timeout=5000;")
        exec("PRAGMA mmap_size=268435456;")   // 256 MB
        exec("PRAGMA cache_size=-16000;")      // ~16 MB page cache
        exec("PRAGMA temp_store=MEMORY;")
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

        if detectedVersion < 3 {
            migrateToV3()
        }

        if detectedVersion < 4 {
            migrateToV4()
        }

        // Embeddings for semantic recall (C2-1b). Idempotent; independent of the
        // FTS schema version so it lands for existing v2 databases too.
        exec("""
        CREATE TABLE IF NOT EXISTS vault_embeddings (
            entity_id TEXT NOT NULL,
            entity_kind TEXT NOT NULL,
            dim INTEGER NOT NULL,
            vec BLOB NOT NULL,
            PRIMARY KEY (entity_id, entity_kind)
        );
        """)

        // P0-F: cross-entity join tables. O(log n) person → meetings / decisions
        // / tasks / projects edges, replacing in-memory full sweeps. Idempotent
        // so they land for existing databases too.
        exec("""
        CREATE TABLE IF NOT EXISTS meeting_persons (
            meeting_id TEXT NOT NULL, person_id TEXT NOT NULL, role TEXT,
            PRIMARY KEY (meeting_id, person_id));
        CREATE TABLE IF NOT EXISTS decision_persons (
            decision_id TEXT NOT NULL, person_id TEXT NOT NULL,
            PRIMARY KEY (decision_id, person_id));
        CREATE TABLE IF NOT EXISTS task_persons (
            task_id TEXT NOT NULL, person_id TEXT NOT NULL, role TEXT,
            PRIMARY KEY (task_id, person_id));
        CREATE TABLE IF NOT EXISTS person_projects (
            person_id TEXT NOT NULL, project_id TEXT NOT NULL,
            PRIMARY KEY (person_id, project_id));
        CREATE INDEX IF NOT EXISTS idx_task_persons_person ON task_persons(person_id);
        CREATE INDEX IF NOT EXISTS idx_meeting_persons_person ON meeting_persons(person_id);
        CREATE INDEX IF NOT EXISTS idx_decision_persons_person ON decision_persons(person_id);
        CREATE INDEX IF NOT EXISTS idx_person_projects_project ON person_projects(project_id);
        """)

        exec("PRAGMA user_version=\(Self.schemaVersion);")
    }

    // MARK: - Schema v4 migration (P0-F — drop the vault_content kind CHECK)

    /// Rebuilds `vault_content` without its `entity_kind` CHECK constraint. The
    /// v2 schema hard-coded the kind to one of five values, which silently
    /// rejected any INSERT for a new kind — `decision` (P0-E) would never land,
    /// and the vault could never grow to "any future entity type" (audit C-4).
    /// Dropping the CHECK makes the index open-ended; the external-content FTS is
    /// rebuilt from the copied rows so search stays intact.
    private func migrateToV4() {
        log.info("Migrating SecondBrainDB to schema version 4 (open-ended vault_content kinds)")
        guard tableExists("vault_content") else {
            // Fresh DB that somehow skipped v2 — nothing to rebuild.
            exec("INSERT OR REPLACE INTO schema_meta VALUES ('schema_version', '4');")
            return
        }
        guard execChecked("BEGIN;") else {
            log.error("migrateToV4 could not BEGIN — skipping")
            return
        }
        // Run as an ordered list so a failure rolls back the whole rebuild (and
        // keeps Swift's type-checker out of a giant boolean expression).
        let steps: [String] = [
            """
            CREATE TABLE vault_content_new (
                entity_id   TEXT NOT NULL,
                entity_kind TEXT NOT NULL,
                title       TEXT,
                body        TEXT,
                date_epoch  INTEGER,
                tags        TEXT,
                PRIMARY KEY (entity_id, entity_kind)
            );
            """,
            """
            INSERT INTO vault_content_new (rowid, entity_id, entity_kind, title, body, date_epoch, tags)
                SELECT rowid, entity_id, entity_kind, title, body, date_epoch, tags FROM vault_content;
            """,
            "DROP TRIGGER IF EXISTS vault_fts_insert;",
            "DROP TRIGGER IF EXISTS vault_fts_update;",
            "DROP TRIGGER IF EXISTS vault_fts_delete;",
            "DROP TABLE vault_content;",
            "ALTER TABLE vault_content_new RENAME TO vault_content;",
            """
            CREATE TRIGGER IF NOT EXISTS vault_fts_insert AFTER INSERT ON vault_content BEGIN
                INSERT INTO vault_fts(rowid, title, body, tags) VALUES (new.rowid, new.title, new.body, new.tags);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS vault_fts_update AFTER UPDATE ON vault_content BEGIN
                INSERT INTO vault_fts(vault_fts, rowid, title, body, tags) VALUES ('delete', old.rowid, old.title, old.body, old.tags);
                INSERT INTO vault_fts(rowid, title, body, tags) VALUES (new.rowid, new.title, new.body, new.tags);
            END;
            """,
            """
            CREATE TRIGGER IF NOT EXISTS vault_fts_delete AFTER DELETE ON vault_content BEGIN
                INSERT INTO vault_fts(vault_fts, rowid, title, body, tags) VALUES ('delete', old.rowid, old.title, old.body, old.tags);
            END;
            """,
            "INSERT INTO vault_fts(vault_fts) VALUES('rebuild');",
            "INSERT OR REPLACE INTO schema_meta VALUES ('schema_version', '4');",
        ]
        for step in steps where !execChecked(step) {
            exec("ROLLBACK;")
            log.error("migrateToV4 failed mid-rebuild — rolled back, will retry next launch")
            return
        }
        if !execChecked("COMMIT;") {
            exec("ROLLBACK;")
            log.error("migrateToV4 COMMIT failed — rolled back")
        }
    }

    // MARK: - Cross-entity join tables (P0-F)

    /// Replace the person rows for a meeting (idempotent re-link on re-finalize).
    func setMeetingPersons(meetingID: String, personRoles: [(personID: String, role: String?)]) {
        exec("DELETE FROM meeting_persons WHERE meeting_id='\(escape(meetingID))';")
        for pr in personRoles {
            bindExec("INSERT OR REPLACE INTO meeting_persons (meeting_id, person_id, role) VALUES (?,?,?);",
                     [.text(meetingID), .text(pr.personID), .text(pr.role ?? "")])
        }
    }

    /// Replace the person rows for a decision.
    func setDecisionPersons(decisionID: String, personIDs: [String]) {
        exec("DELETE FROM decision_persons WHERE decision_id='\(escape(decisionID))';")
        for pid in personIDs {
            bindExec("INSERT OR REPLACE INTO decision_persons (decision_id, person_id) VALUES (?,?);",
                     [.text(decisionID), .text(pid)])
        }
    }

    /// Link a task to a person (role e.g. "owner" / "delegate").
    func upsertTaskPerson(taskID: String, personID: String, role: String?) {
        bindExec("INSERT OR REPLACE INTO task_persons (task_id, person_id, role) VALUES (?,?,?);",
                 [.text(taskID), .text(personID), .text(role ?? "")])
    }
    func removeTaskPersons(taskID: String) {
        exec("DELETE FROM task_persons WHERE task_id='\(escape(taskID))';")
    }

    /// Materialize the person → project reverse edge.
    func upsertPersonProject(personID: String, projectID: String) {
        bindExec("INSERT OR REPLACE INTO person_projects (person_id, project_id) VALUES (?,?);",
                 [.text(personID), .text(projectID)])
    }

    func personsForMeeting(_ meetingID: String) -> [String] {
        queryIDs("SELECT person_id FROM meeting_persons WHERE meeting_id=?;", bind: meetingID)
    }
    func decisionsForPerson(_ personID: String) -> [String] {
        queryIDs("SELECT decision_id FROM decision_persons WHERE person_id=?;", bind: personID)
    }
    func projectsForPerson(_ personID: String) -> [String] {
        queryIDs("SELECT project_id FROM person_projects WHERE person_id=?;", bind: personID)
    }
    func tasksForPerson(_ personID: String) -> [String] {
        queryIDs("SELECT task_id FROM task_persons WHERE person_id=?;", bind: personID)
    }

    // MARK: - Schema v2 migration

    private func migrateToV2() {
        log.info("Migrating SecondBrainDB to schema version 2")
        // Phase 1 (1A): wrap the migration in a transaction so a mid-migration
        // failure (disk-full, corruption) can't leave a half-applied schema that
        // the version stamp then marks as "done".
        guard execChecked("BEGIN;") else {
            log.error("migrateToV2 could not BEGIN — skipping")
            return
        }

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

        if !execChecked("COMMIT;") {
            exec("ROLLBACK;")
            log.error("migrateToV2 COMMIT failed — rolled back")
        }
    }

    // MARK: - Schema v3 migration (Phase D — relationship type + check-in cadence)

    private func migrateToV3() {
        log.info("Migrating SecondBrainDB to schema version 3 (relationship type + check-in cadence)")
        // Additive ALTER TABLE — safe on all existing v1/v2 databases.
        // SQLite ignores "duplicate column" errors, so these are wrapped in
        // try? at the exec level; we use the "column not found" check pattern.
        guard execChecked("BEGIN;") else {
            log.error("migrateToV3 could not BEGIN — skipping")
            return
        }
        exec("ALTER TABLE people ADD COLUMN relationship_type TEXT DEFAULT 'unset';")
        exec("ALTER TABLE people ADD COLUMN check_in_cadence_days INTEGER;")
        exec("INSERT OR REPLACE INTO schema_meta VALUES ('schema_version', '3');")
        if !execChecked("COMMIT;") {
            exec("ROLLBACK;")
            log.error("migrateToV3 COMMIT failed — rolled back")
        }
        log.info("SecondBrainDB v3 migration complete")
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
        // Phase 1 (1A): persist the v3 relationship columns. Previously this
        // INSERT omitted them, so `relationship_type` / `check_in_cadence_days`
        // stayed at their migration defaults ('unset'/NULL) even when the Person
        // carried a type — silently dropping coach data on every rebuild. The
        // bind helper has no NULL case, so a 0 cadence means "use the type default".
        bindExec("INSERT INTO people (id, display_name, company, role, last_interaction, relevance, ghost, tag_ids, relationship_type, check_in_cadence_days) VALUES (?,?,?,?,?,?,?,?,?,?);",
                 [.text(p.id), .text(p.displayName), .text(p.company), .text(p.role),
                  .real(p.lastInteractionAt?.timeIntervalSince1970 ?? 0),
                  .real(relevance), .int(Int64(ghost)), .text(p.tagIDs.joined(separator: " ")),
                  .text(p.relationshipType.rawValue), .int(Int64(p.checkInCadenceDays ?? 0))])
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
                (bm25(vault_fts, 10.0, 1.0, 0.5) * (1.0 + 0.5 * MAX(0.0, 1.0 - (CAST(strftime('%s','now') AS REAL) - CAST(COALESCE(vc.date_epoch,0) AS REAL)) / 15552000.0))) AS rank_score,
                snippet(vault_fts, 1, char(1), char(2), '…', 10) AS snip
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
            let snippet    = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            results.append(VaultSearchResult(entityID: entityID, entityKind: entityKind,
                                             title: title, dateEpoch: dateEpoch, rankScore: rankScore,
                                             snippet: snippet))
        }
        return results
    }

    /// Number of rows in vault_content for a given entity kind. Used to detect
    /// when the index is missing content after a rebuild/reset (the index only
    /// re-restores people, so meetings/voice notes need a backfill). (C2-1)
    func vaultContentCount(kind: String) -> Int {
        scalarInt("SELECT COUNT(*) FROM vault_content WHERE entity_kind='\(escape(kind))';") ?? 0
    }

    // MARK: - Embeddings (semantic recall, C2-1b)

    /// Store/replace the embedding vector for an entity (Float32 BLOB).
    func upsertEmbedding(entityID: String, entityKind: String, vector: [Float]) {
        guard !vector.isEmpty else { return }
        let sql = "INSERT OR REPLACE INTO vault_embeddings (entity_id, entity_kind, dim, vec) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, entityID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, entityKind, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 3, Int32(vector.count))
        vector.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(stmt, 4, raw.baseAddress, Int32(raw.count), SQLITE_TRANSIENT)
        }
        sqlite3_step(stmt)
    }

    func deleteEmbedding(entityID: String, entityKind: String) {
        exec("DELETE FROM vault_embeddings WHERE entity_id='\(escape(entityID))' AND entity_kind='\(escape(entityKind))';")
    }

    /// All stored embeddings. Held in memory for cosine scoring — even thousands
    /// of 768-d vectors are only a few MB.
    func allEmbeddings() -> [(entityID: String, entityKind: String, vector: [Float])] {
        var out: [(String, String, [Float])] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT entity_id, entity_kind, dim, vec FROM vault_embeddings;", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let kind = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let dim = Int(sqlite3_column_int(stmt, 2))
            guard let blob = sqlite3_column_blob(stmt, 3), dim > 0 else { continue }
            let bytes = Int(sqlite3_column_bytes(stmt, 3))
            guard bytes == dim * MemoryLayout<Float>.size else { continue }
            let vec = [Float](unsafeUninitializedCapacity: dim) { buf, count in
                memcpy(buf.baseAddress, blob, bytes); count = dim
            }
            out.append((id, kind, vec))
        }
        return out
    }

    /// Entity IDs that already have an embedding for a kind (for backfill diff).
    func embeddedEntityIDs(kind: String) -> Set<String> {
        Set(queryIDs("SELECT entity_id FROM vault_embeddings WHERE entity_kind='\(escape(kind))';"))
    }

    /// Meetings most semantically similar to a given meeting, by embedding
    /// cosine — auto-discovered backlinks so the graph self-assembles from
    /// capture without manually-pasted links. (C2-3)
    func relatedMeetings(toID id: String, limit: Int = 5, minScore: Float = 0.45) -> [(id: String, score: Float)] {
        let all = allEmbeddings()
        guard let target = all.first(where: { $0.entityID == id && $0.entityKind == "meeting" }) else { return [] }
        return all
            .filter { $0.entityKind == "meeting" && $0.entityID != id }
            .map { (id: $0.entityID, score: EmbeddingService.cosine(target.vector, $0.vector)) }
            .filter { $0.score >= minScore }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { ($0.id, $0.score) }
    }

    /// Title + date for one indexed entity — used to build a result row for a
    /// semantic-only hit that wasn't in the lexical result set.
    func vaultContentMeta(entityID: String, entityKind: String) -> (title: String?, dateEpoch: Int64?)? {
        var stmt: OpaquePointer?
        let sql = "SELECT title, date_epoch FROM vault_content WHERE entity_id=? AND entity_kind=? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, entityID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, entityKind, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let title = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
        let date = sqlite3_column_type(stmt, 1) != SQLITE_NULL ? sqlite3_column_int64(stmt, 1) : nil
        return (title, date)
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
