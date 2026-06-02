# E2 — SQLite Migration Correctness (v2 Audit)

**Lens:** Is the v3 schema migration safe for existing users? Any edge cases?

---

## Full-App Audit Through Migration Lens

### 1. Is there a v3 migration? What version is the current schema?

Yes. `SecondBrainDB.schemaVersion = 3` (`SecondBrainDB.swift:34`). The `ensureSchema()` method detects the stored version and runs `migrateToV2()` then `migrateToV3()` in sequence as needed (`SecondBrainDB.swift:173–179`).

### 2. Migration approach: `ALTER TABLE ADD COLUMN` (safe) or DROP/recreate (dangerous)?

`migrateToV3()` (`SecondBrainDB.swift:247–256`) uses pure additive `ALTER TABLE`:

```sql
ALTER TABLE people ADD COLUMN relationship_type TEXT DEFAULT 'unset';
ALTER TABLE people ADD COLUMN check_in_cadence_days INTEGER;
INSERT OR REPLACE INTO schema_meta VALUES ('schema_version', '3');
```

This is the safe path. Existing 50-person stores upgrade non-destructively. All existing rows get `relationship_type = 'unset'` and `check_in_cadence_days = NULL` automatically from the DEFAULT clause — exactly what the Swift model expects.

### 3. What happens to existing users with 50 people on update to Phase D?

**Positive:** The `Person` tolerant decoder (`Person.swift:319–320`) reads `relationshipType` with `decodeIfPresent(...) ?? .unset`, so any `person.json` without the field decodes gracefully. The SQLite `people` table gets both columns added with sensible defaults. All 50 existing rows are valid immediately after migration.

**No data loss path:** The JSON store (`PeopleStore.swift:23–24` — `personSchemaVersion = 1`) has not been bumped and has no `migrate:` closure. But since `Person`'s tolerant decoder fills in defaults, this is fine for reads. On first write-back after Phase D, the JSON gains the new fields.

### 4. Is there a migration rollback plan? What if v3 migration fails halfway?

**Critical gap — no transaction wrapper around `migrateToV3()`.**

The three statements in `migrateToV3()` execute bare via `exec()` with no surrounding `BEGIN`/`COMMIT`. If the first `ALTER TABLE` succeeds but the app crashes before `INSERT OR REPLACE INTO schema_meta` completes, the DB has `relationship_type` column present but `schema_version` still at `2`. On next launch `detectedVersion < 3` is still true, so `migrateToV3()` runs again. SQLite will fail the duplicate `ALTER TABLE` with `SQLITE_ERROR: duplicate column name`. The code comment at `SecondBrainDB.swift:250–251` claims "SQLite ignores duplicate column errors, so these are wrapped in try?", but `exec()` does NOT suppress errors — it calls `execChecked()` which logs the error and returns `false`, but `exec()` discards that return value. The `ALTER TABLE` failure is therefore silently swallowed and migration continues to the `schema_meta` update — so the second run is effectively a no-op. This means the partial-migration scenario is accidentally safe, but it relies on silent error-swallowing rather than an explicit transaction + rollback.

The comment is also technically wrong: SQLite does **not** ignore duplicate column errors; the code just discards the error code.

**There is no explicit rollback path** for the migration. Contrast this with `rebuild()` which correctly wraps its work in `BEGIN`/`COMMIT`/`ROLLBACK` (`SecondBrainDB.swift:265–280`).

### 5. Does the JSON-based people store need migration? Does the tolerant decoder handle it?

No schema migration is needed in the JSON layer. The tolerant decoder in `Person.swift:295–320` covers every post-Phase-A field with `decodeIfPresent(...) ?? default`. `relationshipType` maps to `.unset` when absent; `checkInCadenceDays` maps to `nil`. `PersonSchemaVersion` is still `1` and `SchemaEnvelope.decode` is called without a `migrate:` closure (`PeopleStore.swift:396–399`), which is correct — the tolerant init handles it.

**No migration needed for JSON. Tolerant decoder is correct.**

### 6. Are there any tests for the migration path?

**No.** The test suite (`Tests/MeetingScribeTests/`) contains 12 test files. `VaultMigrationManagerTests.swift` covers only the file-layout migration (tag→date folder), not `SecondBrainDB` schema migrations. There are zero tests for:
- v0 → v1 → v2 → v3 upgrade path
- v1 → v3 direct upgrade (skipping v2)
- `migrateToV3()` idempotency / duplicate-column resilience
- `insertPerson()` writing (or not writing) the new columns

### 7. WAL mode and concurrent-write protection?

WAL is enabled immediately on `openConnection()` (`SecondBrainDB.swift:90`): `PRAGMA journal_mode=WAL;`. `busy_timeout=5000` is set to handle lock contention (`SecondBrainDB.swift:96`). `SecondBrainDB` is `@MainActor final class`, so all writes serialize on the main actor. The MCP server process opens `secondbrain.db` as `SQLITE_OPEN_READONLY` (`MeetingScribeMCP/main.swift:464`), so there is no concurrent writer from the MCP side. Under WAL mode, a read-only MCP process and a writing main-app process can coexist without blocking each other.

**Concurrent-write protection is adequate.**

---

## Additional Issues Found

### E2-BUG-1: `insertPerson()` never writes the new v3 columns
**Severity: High** — `insertPerson()` (`SecondBrainDB.swift:298–324`) constructs:

```sql
INSERT INTO people (id, display_name, company, role, last_interaction, relevance, ghost, tag_ids) VALUES (?,?,?,?,?,?,?,?)
```

The `relationship_type` and `check_in_cadence_days` columns are never populated by the INSERT statement. This means after a `rebuild()`, every row gets the DEFAULT values (`'unset'` and `NULL`) regardless of what the `Person` model actually contains. A user who sets someone as `romanticPartner` will have that written to `person.json` and displayed correctly in UI, but the SQLite index is permanently wrong — any future SQL query on `relationship_type` in `people` would always return `'unset'`. This is a silent data divergence between the JSON canon and the derived index.

### E2-BUG-2: Version detection for v1 databases depends on unset `PRAGMA user_version`
A v1 database (before `schema_meta` was introduced in v2) will have `user_version = 0` unless the previous v1 code explicitly set it. The `ensureSchema()` code checks `PRAGMA user_version` as the fallback, interpreting `0` as "fresh/v0" and triggering both `migrateToV2()` and `migrateToV3()`. If a real v1 database has `user_version = 0`, the v2 migration attempts `CREATE TABLE IF NOT EXISTS vault_content` etc., which is idempotent and safe. The path is survivable but implicitly depends on the assumption that legacy v1 DBs never explicitly set `user_version = 1`.

### E2-BUG-3: `migrateToV2()` has no transaction either
Same structural issue: `migrateToV2()` (`SecondBrainDB.swift:198–243`) creates four tables and three triggers across many `exec()` calls with no enclosing `BEGIN`/`COMMIT`. A power loss mid-v2-migration could leave `vault_fts` created but `vault_content` missing, causing the FTS triggers to reference a nonexistent content table. Recovery relies on the `quick_check` path at next open, which deletes and rebuilds — acceptable but unintended.

---

## Existing-Plan Items I Rank Highest

1. **E3-4 (quick_check + rebuild on corrupt DB)** — Already implemented correctly. The delete+recreate fallback prevents a corrupt index from silently darkening the People graph.
2. **C2-1b (vault_embeddings table)** — Added outside schema version gating (`SecondBrainDB.swift:181–191`). Idempotent and correct.
3. **Phase D tolerant decoder** — `Person.swift:318–320` is the right pattern; correctly handles forward/backward compat with `.unset` default.

---

## Net-New Recommendations

### E2-R1 — Wrap `migrateToV2()` and `migrateToV3()` in explicit transactions
**What:** Add `exec("BEGIN;")` / `exec("COMMIT;")` (with `exec("ROLLBACK;")` on any `execChecked` failure) around every migration function, mirroring the pattern already used in `rebuild()`.
**Why:** Today the migrations rely on accident (silent error-swallowing for duplicate columns). An explicit transaction guarantees all-or-nothing semantics and makes the intent auditable. The comment at `SecondBrainDB.swift:250` claims safety via "SQLite ignores duplicate column errors" which is factually wrong — errors are swallowed by `exec()` discarding the return value, not by SQLite.
**User value:** Prevents partially-migrated schemas after power loss or app crash during first launch.
**Effort:** S (< 1 hour).
**Impact:** High.
**Deps:** None.

### E2-R2 — Write `relationship_type` and `check_in_cadence_days` in `insertPerson()`
**What:** Extend the `INSERT INTO people (...)` statement in `insertPerson()` (`SecondBrainDB.swift:302–305`) to include both new columns bound from `p.relationshipType.rawValue` and `p.checkInCadenceDays`.
**Why:** Currently the SQLite index diverges from the JSON canon on every rebuild — the people table always shows `'unset'` even for users who have set a relationship type. This silently defeats the purpose of the v3 migration for any SQL-level query.
**User value:** Enables correct SQL-level filtering and sorting by relationship type (e.g., future "show only family" queries).
**Effort:** S.
**Impact:** High — without this, the v3 columns are dead weight in the derived index.
**Deps:** None.

### E2-R3 — Add `SecondBrainDB` migration unit tests
**What:** A new `SecondBrainDBMigrationTests.swift` covering:
1. Fresh DB gets all three schema versions applied.
2. v1 DB (no `schema_meta`, `user_version=0`) gets v2+v3 applied without data loss.
3. v2 DB gets only v3 applied; existing rows retain their data.
4. Idempotency: calling `ensureSchema()` twice on a v3 DB is a no-op.
5. After `rebuild()`, `relationship_type` column reflects `Person.relationshipType.rawValue`.
**Why:** There are zero migration tests. The file-layout migration has 3 tests; the SQLite migration — which is more consequential for data safety — has none.
**Effort:** M (1 day, including test harness for a temp-file DB).
**Impact:** High — catches regressions as the schema continues to evolve.
**Deps:** `SecondBrainDB` needs to be testable in isolation; currently `@MainActor` and `@available(macOS 14.0, *)` — both compatible with `XCTestCase` on macOS.

### E2-R4 — Bump `personSchemaVersion` and use `migrate:` closure when fields become non-optional
**What:** As a forward policy: when any `Person` field becomes load-bearing and non-optional in a future phase, bump `PeopleStore.personSchemaVersion` from `1` to `2` and supply a `migrate:` closure in the `SchemaEnvelope.decode` call at `PeopleStore.swift:396`.
**Why:** `SchemaEnvelope` was designed for this pattern but the `migrate:` parameter is never used. If a future phase makes a field required without a tolerant default, all old `person.json` files will silently decode to empty/wrong values.
**User value:** Insurance against silent data loss on future schema additions.
**Effort:** S (when applicable).
**Impact:** Medium (preventive).
**Deps:** None.

### E2-R5 — Add index on `people.relationship_type` after E2-R2 lands
**What:** Add `CREATE INDEX IF NOT EXISTS idx_people_rel_type ON people(relationship_type);` at the end of `migrateToV3()` (or a v4 migration once E2-R2 is shipped).
**Why:** `list_overdue_check_ins` and relationship-type filtering currently happen in Swift after loading all people from JSON. As the graph scales, SQL-level filtering with an index will be significantly faster.
**User value:** Sub-millisecond relationship-type filtering at scale.
**Effort:** S.
**Impact:** Medium.
**Deps:** E2-R2 (columns must be populated before indexing pays off).

### E2-R6 — Expose `schema_version` in diagnostics payload
**What:** Surface `SecondBrainDB.schemaVersion` and whether a migration ran at last launch in the app's diagnostic/about panel and any crash reports.
**Why:** When users report "no people showing" or blank People graph bugs, there is currently no way to tell remotely whether they are on v1/v2/v3. A `schema_version: 3` line in the diagnostics payload would cut triage time dramatically.
**Effort:** S.
**Impact:** Medium (developer ergonomics).
**Deps:** None.

---

## Top 3 Picks

1. **E2-R2** — `insertPerson()` not writing the v3 columns is a silent data-divergence bug that defeats the entire purpose of the v3 migration. Fix is a one-line SQL change.
2. **E2-R1** — Transactional migration guards eliminate the partial-migration risk class that the current code accidentally survives via error-swallowing.
3. **E2-R3** — Migration tests are the only way to catch regressions as the schema continues to grow past v3.

## Single Highest-Priority Recommendation

**E2-R2** — Fix `insertPerson()` (`SecondBrainDB.swift:302–305`) to write `relationship_type` and `check_in_cadence_days` into the SQLite `people` table on every insert. The v3 migration correctly adds the columns, but every `rebuild()` and `upsertPerson()` call overwrites them with the DEFAULT (`'unset'`, `NULL`) because the INSERT statement never mentions them. Any user who has set a relationship type gets the correct value in their `person.json` and in the SwiftUI layer, but the SQLite derived index is permanently stale — silently undermining Phase D's querying potential and any future SQL-level relationship-type features.
