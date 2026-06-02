# E2 — Data Model: Relationship Types, Check-in Cadence, Content Library
**Lens:** Swift/SQLite data modeling — schema changes for relationship types (partner/family/friend), check-in cadence, content library per type; migration from current Person model; SQLite/FTS5 changes needed.
**Auditor:** E2 Data Model subagent (25-agent audit, 2026-06-02)

---

## 1. Current-State Schema Audit

### 1.1 Where Person data lives

Person data is stored as **JSON**, not rows in SQLite. The canonical record is:

```
<storageDir>/people/<slug>/person.json   — SchemaEnvelope-wrapped Codable
<storageDir>/people/<slug>/person.md    — human-readable mirror, regenerated on write
<storageDir>/_people-cache.json          — debounced single-file snapshot for fast launch
```

Source: `PeopleStore.swift:27–29` (folder constants), `PeopleStore.swift:554–556` (write path), `PeopleStore.swift:368` (cache path).

SQLite (`secondbrain.db`) is a **derived index only**, not canonical. It is deletable and fully rebuilable from JSON. The `people` table (SecondBrainDB.swift:138–142) stores only:

```sql
CREATE TABLE people (
    id TEXT PRIMARY KEY,
    display_name TEXT,
    company TEXT,
    role TEXT,
    last_interaction REAL,
    relevance REAL,
    ghost INTEGER,
    tag_ids TEXT   -- space-joined IDs, not names
);
```

The `encounters_idx` table (SecondBrainDB.swift:144–146):

```sql
CREATE TABLE encounters_idx (
    id TEXT PRIMARY KEY,
    person_id TEXT,
    event_tag_id TEXT,
    date REAL
);
```

The unified FTS index is `vault_content` + `vault_fts` (v2 schema, SecondBrainDB.swift:197–238). For persons, the `body` column is populated with: emails + phones + company + role + bio + favorites + memories (SecondBrainDB.swift:289–306). **`relationship_type` is absent.**

Schema version is currently `2` (`SecondBrainDB.swift:34`), tracked in `schema_meta` table. The JSON schema is version `1` (`PeopleStore.swift:23–24`).

---

### 1.2 Current Person model — fields present and absent

`Sources/MeetingScribe/People/Person.swift` (lines 77–184), full field inventory:

**Present:** `id`, `displayName`, `company`, `role`, `emails[]`, `phones[]`, `bio`, `tagIDs: Set<String>`, `createdAt`, `updatedAt`, `lastInteractionAt`, `meetingMentions: Set<String>`, `birthday`, `addresses[]`, `favorites[]`, `memories: [Memory]`, `photoRelativePaths[]`, `contactIdentifier`, `importSources: Set<String>`, `relationships: [Relationship]`, `attachedNotes: [AttachedNote]`.

**Absent — all of these must be added for relationship type paths:**

| Field needed | Type | Notes |
|---|---|---|
| `relationshipType` | `RelationshipType` enum | partner / family / closeFriend / friend / colleague / acquaintance |
| `checkInCadenceDays` | `Int?` | Overrides inferred cadence; nil = auto-infer from encounter history |
| `loveLanguage` | `[LoveLanguage]` | words / acts / gifts / time / touch — multi-select, ordered |
| `attachmentStyle` | `AttachmentStyle?` | secure / anxious / avoidant / disorganized |
| `communicationStyle` | `String?` | Freeform or preset (direct, assertive, passive, etc.) |
| `relationshipGoals` | `[String]` | e.g. "see more often", "repair trust", "deepen emotional intimacy" |
| `contentLibraryItems` | `[ContentLibraryItem]` | Exercises, prompts, reflections — per-person, completed vs pending |
| `lastCheckInAt` | `Date?` | Most recent structured check-in (distinct from any encounter) |
| `checkInTemplateID` | `String?` | Which template governs the next check-in |

The `VaultKit.Person` struct (`Sources/VaultKit/Person.swift:9–47`) is a lean Foundation-only mirror; none of these fields are present there either.

---

### 1.3 Current Encounter model — fields present and absent

**App-side Encounter** (`Sources/MeetingScribe/People/Encounter.swift:7–46`):

```swift
var id: String
var personID: String
var eventTagID: String?      // ties to MeetingTag
var eventName: String         // required; this drives tag proliferation (D4 finding)
var date: Date
var location: String?
var notes: String
var meetingID: String?
var voiceNoteID: String?
var createdAt: Date
```

**Absent:** no `kind` (coffee/call/text/birthday/quality-time/shared-activity), no `qualityRating` (Int 1–5), no `durationMinutes`, no `initiatedBy` (self/them/mutual), no `templateID`, no `checkInResponseBlob` (JSON of template field answers).

**VaultKit Encounter** (`Sources/VaultKit/Encounter.swift:7–38`) has a `Kind` enum (`meeting/call/email/message/note`) and `title/summary` but is never surfaced in the app UI (`D4-checkins.md:16–28`). The two models diverge and need consolidation.

---

### 1.4 PersonDTO and MCP surface

`SharedModels.swift:186–277` — `PersonDTO` mirrors the old subset of `Person`. It has no `relationshipType`, no `checkInCadenceDays`, no `loveLanguage`, no `attachmentStyle`. The MCP server reads `PersonDTO` directly (`main.swift:325–327` references `peopleSchemaVersion = 1`). Every new field on `Person` must also land in `PersonDTO` or MCP tools will silently omit them.

---

## 2. Existing Plan Items — Endorsements

**PPL-1 (inline field editing):** endorsing at P0. Any field-level inline editing introduced for relationship-type onboarding will conflict with the current modal-only `AddPersonSheet` pattern. PPL-1 must land before or alongside relationship type UI.

**FTS5 v2 unified search (HANDOFF.md Phase 1):** endorsing. The `vault_fts` infrastructure is already the right place to index relationship type and cadence text. It just needs to be populated with relationship type data once that field lands on `Person`.

**PPL-2 multi-value contact fields:** endorse for Medium effort parallel to relationship type — it cleans up the data model before we add more fields to it.

---

## 3. NET-NEW Recommendations

### E2-1 — Add `RelationshipType` enum + `checkInCadenceDays` to Person (S effort)

**What:** Add a `RelationshipType` enum directly to `Person.swift` (and `PersonDTO` in `SharedModels.swift`). Safe, backward-compatible — the tolerant `init(from:)` decoder pattern (already used at Person.swift:199–222) handles nil via default.

```swift
// Person.swift — add alongside existing fields
enum RelationshipType: String, Codable, CaseIterable, Sendable {
    case partner, familyMember, closeFriend, friend, colleague, acquaintance
}

// On Person struct:
var relationshipType: RelationshipType? = nil
var checkInCadenceDays: Int? = nil         // nil = auto-infer
var lastCheckInAt: Date? = nil             // most recent structured check-in
```

**Migration:** zero-migration — existing `person.json` files decode with `nil` for all three fields (the tolerant decoder pattern at Person.swift:199 already handles unknown keys gracefully). No `personSchemaVersion` bump needed for nil-defaulted optional fields, but bump it to `2` anyway to make the boundary auditable.

**SQLite impact:** add `relationship_type TEXT` and `checkin_cadence_days INTEGER` to the `people` table via `migrateToV3()` in `SecondBrainDB.ensureSchema()`. Existing rows get NULL (SQLite's `ALTER TABLE ADD COLUMN` is zero-cost without a table rebuild). Update `schemaVersion` to `3`.

**FTS5 impact:** add `relationship_type` to the `body` text fed into `vault_content` at `SecondBrainDB.swift:289–306`. This makes `search("partner")` or `search("family")` find the right people immediately.

**Effort:** S (hours). The pattern is identical to every other optional field already on `Person`.

---

### E2-2 — Extend Encounter with `kind`, `qualityRating`, `templateID`, `checkInResponses` (M effort)

**What:** The app-side `Encounter` struct at `MeetingScribe/People/Encounter.swift:7` needs four new fields:

```swift
enum EncounterKind: String, Codable, CaseIterable, Sendable {
    case coffeeOrMeal, call, videoCall, textThread, inPerson, sharedActivity,
         birthday, checkIn, custom
}

// On Encounter:
var kind: EncounterKind = .custom              // nil-safe default for old records
var qualityRating: Int? = nil                  // 1–5; nil = not rated
var templateID: String? = nil                  // which check-in template was used
var checkInResponses: [String: String]? = nil  // templateFieldID → freeform answer
var durationMinutes: Int? = nil
var initiatedBy: InitiatedBy? = nil            // self / them / mutual
```

**Why:** Without `kind`, the app cannot distinguish "had coffee" from "sent a birthday text" from "completed a Gottman 36-questions exercise." The `qualityRating` field is the data backbone for the emotional quality tracking the content layer needs (see P3-content.md). `checkInResponses` stores structured answers to per-type templates without a separate table — keeping encounters self-contained JSON files.

**Migration:** tolerant decoder, same pattern. Bump `encounterSchemaVersion` to `2` in `PeopleStore.swift:24`. The `encounters_idx` SQLite table needs `kind TEXT, quality_rating INTEGER` columns via `ALTER TABLE ADD COLUMN` in `migrateToV3()`.

**FTS5 impact:** include `kind` display string and check-in responses in the `body` fed to `vault_content` for encounter entities, so `search("birthday call")` or `search("Gottman")` surface the right encounters.

**Effort:** M (one day). The model change is small; the bigger lift is updating `AddEncounterSheet` to surface the kind picker and quality rating.

---

### E2-3 — Add psychological profile fields to Person via a sub-struct (M effort)

**What:** Add a `RelationshipProfile` sub-struct (Codable, nil-defaulted) to `Person`, rather than scattering individual fields:

```swift
struct RelationshipProfile: Codable, Hashable, Sendable {
    var loveLanguages: [LoveLanguage] = []       // ordered preference list
    var attachmentStyle: AttachmentStyle? = nil
    var communicationStyle: String? = nil        // freeform or preset
    var conflictStyle: String? = nil             // e.g. "avoidant", "collaborative"
    var relationshipGoals: [String] = []         // user-written intentions
    var sharedValues: [String] = []
    var lastReflectedAt: Date? = nil             // last time user edited this profile
}

// On Person:
var relationshipProfile: RelationshipProfile? = nil
```

**Why a sub-struct:** Avoids ballooning `Person`'s flat field count (already 20+ fields). The sub-struct decodes from `nil` for all existing records. It is the data that powers per-type content recommendations (P3 content library), Gottman assessment prompts, and the "understand them better" section of the check-in flow.

**SQLite impact:** none needed for the derived index. The `people` table is already used only for fast filtering/sorting by indexed scalar fields. The profile sub-struct is JSON in `person.json` and gets included in the `body` text fed to `vault_fts` (love languages + goals = searchable). No new table.

**DTO impact:** add `RelationshipProfileDTO` to `SharedModels.swift` and include it on `PersonDTO` so MCP can read/write these fields.

**Effort:** M. Sub-struct is S; the effort is writing sensible enum cases for `LoveLanguage`, `AttachmentStyle` and wiring them into `AddPersonSheet` and `PersonDetailView`.

---

### E2-4 — Add a `check_in_templates` table to SQLite (M effort)

**What:** Check-in templates are content (not derived from JSON files), so they belong in SQLite itself — not as JSON files under `people/`. Add to `SecondBrainDB`:

```sql
CREATE TABLE check_in_templates (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    relationship_type TEXT,           -- NULL = universal; else partner/family/closeFriend/etc.
    fields_json TEXT NOT NULL,        -- JSON array of {id, prompt, kind(text/rating/yesno)}
    created_at INTEGER NOT NULL,
    is_builtin INTEGER NOT NULL DEFAULT 0
);
```

Built-in templates ship with the app (inserted at schema v3 migration time with `is_builtin=1`) and are keyed to `relationship_type`. User-created templates have `is_builtin=0` and can override built-in ones for a given type.

**Why SQLite (not JSON):** Templates are small, structured, queried by `relationship_type`, and never need to be human-readable in Finder. They are app content, not user archive. SQLite is the right store.

**FTS5 impact:** none — templates are navigated by `relationship_type`, not searched.

**Effort:** M. Table DDL + migration is S; the effort is defining the initial template content for each relationship type (partner / family / close friend) and the Swift `CheckInTemplate` struct + store layer.

---

### E2-5 — Add `relationship_type` and `checkin_cadence_days` columns to `people` SQLite table + migrateToV3() (S effort)

**What:** Concretely, the `SecondBrainDB.ensureSchema()` migration chain needs a `migrateToV3()` block:

```swift
private func migrateToV3() {
    log.info("Migrating SecondBrainDB to schema version 3")
    exec("ALTER TABLE people ADD COLUMN relationship_type TEXT;")
    exec("ALTER TABLE people ADD COLUMN checkin_cadence_days INTEGER;")
    exec("ALTER TABLE people ADD COLUMN last_checkin_at REAL;")
    exec("ALTER TABLE encounters_idx ADD COLUMN kind TEXT;")
    exec("ALTER TABLE encounters_idx ADD COLUMN quality_rating INTEGER;")
    exec("""
    CREATE TABLE IF NOT EXISTS check_in_templates (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, relationship_type TEXT,
        fields_json TEXT NOT NULL, created_at INTEGER NOT NULL, is_builtin INTEGER NOT NULL DEFAULT 0
    );
    """)
    insertBuiltinTemplates()
    exec("INSERT OR REPLACE INTO schema_meta VALUES ('schema_version', '3');")
}
```

And `SecondBrainDB.schemaVersion` bumped to `3` (SecondBrainDB.swift:34).

Update `insertPerson()` (SecondBrainDB.swift:281–307) to bind `relationship_type` and `checkin_cadence_days` in the `INSERT INTO people` statement.

**Effort:** S (1–2 hours). This is pure SQLite plumbing; the hardest part is the `insertBuiltinTemplates()` content.

---

### E2-6 — Filter `people` table by `relationship_type` for typed queries (S effort)

**What:** Add a targeted query method to `SecondBrainDB`:

```swift
func personIDs(ofType type: String) -> [String] {
    queryIDs("SELECT id FROM people WHERE relationship_type=?;", bind: type)
}

func personIDsNeedingCheckIn(maxDaysOverdue: Int) -> [String] {
    // people where now() - last_interaction > checkin_cadence_days (or 30 default)
    let sql = """
    SELECT id FROM people WHERE
      (last_checkin_at IS NULL OR
       CAST(strftime('%s','now') AS INTEGER) - CAST(last_checkin_at AS INTEGER)
       > COALESCE(checkin_cadence_days, 30) * 86400)
    AND ghost = 0 ORDER BY last_interaction ASC LIMIT 20;
    """
    return queryIDs(sql)
}
```

This replaces the current `SuggestedPeopleView` cadence inference (which runs in-memory over all encounters, `SuggestedPeopleView.swift:96–109`) with a sub-millisecond SQLite query. The Today "stay in touch" strip gets the right people by type in O(1) instead of O(encounters).

**FTS5 impact:** add `relationship_type` to the `tags` column in `vault_content` for persons, so a search for "partner" or "family" also hits the unified FTS index without needing a separate query.

**Effort:** S.

---

### E2-7 — Bump `PersonDTO` in SharedModels.swift to expose new fields to MCP (S effort)

**What:** `PersonDTO` (`SharedModels.swift:186–277`) must gain:

```swift
public let relationshipType: String?           // raw value of RelationshipType enum
public let checkInCadenceDays: Int?
public let lastCheckInAt: Date?
public let loveLanguages: [String]             // raw values
public let attachmentStyle: String?
public let relationshipGoals: [String]
```

Add these with `(try? c.decodeIfPresent(...)) ?? nil` in the tolerant `init(from:)` — exactly the existing pattern at SharedModels.swift:216–256.

**Why:** Without this, the MCP's `get_person` tool returns `PersonDTO` instances with no relationship type visible to Claude. The MCP cannot answer "which of my contacts is a partner?" or "who haven't I checked in with in 2 weeks?" — both of which are core use cases for the relationship coach.

**Effort:** S (1 hour, purely additive).

---

### E2-8 — Consolidate the two Encounter models (M effort)

**What:** The app has two `Encounter` types that diverge silently (`MeetingScribe/People/Encounter.swift` vs `VaultKit/Encounter.swift`). The VaultKit version has a cleaner `Kind` enum; the app version has richer provenance fields. Neither is complete for check-in use.

The right resolution: extend the **app-side Encounter** (it is the persisted canonical form) with the fields from E2-2 above. Then update `VaultKit/Encounter.swift` to match (it is already a DTO-level mirror, currently unused by app UI per D4-checkins.md:28). The `SecondBrainStore` protocol in `VaultKit/SecondBrainStore.swift:9` uses `VaultKit.Encounter` — update it to use the consolidated type or drop the VaultKit version in favour of re-exporting the app-side struct.

**Why:** As long as two `Encounter` shapes coexist, any check-in feature built on top will face a choice: use the app model (not visible to MCP) or the VaultKit model (not persisted by the app). Consolidation is the prerequisite for both E2-2 and MCP write tools for encounters.

**Effort:** M (one day).

---

### E2-9 — Add `content_library` table for per-type exercises and reflections (M effort)

**What:** The content library (Gottman exercises, love-language activities, NVC prompts, DBT interpersonal skills per P3-content.md) needs a SQLite home:

```sql
CREATE TABLE content_library (
    id TEXT PRIMARY KEY,
    relationship_type TEXT NOT NULL,   -- partner/family/closeFriend/universal
    category TEXT NOT NULL,            -- gottman/nvc/loveLanguage/attachment/dbt/custom
    title TEXT NOT NULL,
    body TEXT NOT NULL,                -- markdown exercise text / reflection prompt
    estimated_minutes INTEGER,
    is_builtin INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL
);

CREATE TABLE person_content_progress (
    person_id TEXT NOT NULL,
    content_id TEXT NOT NULL,
    status TEXT NOT NULL,              -- pending/started/completed/skipped
    started_at INTEGER,
    completed_at INTEGER,
    notes TEXT,
    PRIMARY KEY (person_id, content_id)
);
```

`content_library` rows ship with the app (`is_builtin=1`, inserted at v3 migration). User-added content has `is_builtin=0`. `person_content_progress` tracks per-person completion state.

**FTS5 impact:** index `content_library` rows into `vault_fts` with `entity_kind='content'` so `search("Gottman")` or `search("love language activities")` surfaces exercises. Add `'content'` to the `vault_content.entity_kind` CHECK constraint (currently `SecondBrainDB.swift:202`: `IN ('person','meeting','encounter','action_item','voice_note')`).

**Effort:** M. Table DDL + migration is S; the effort is seeding the initial content for 3 relationship types.

---

### E2-10 — Safe JSON migration path: bump personSchemaVersion to 2 with explicit migration block (S effort)

**What:** `PeopleStore.personSchemaVersion = 1` (`PeopleStore.swift:23`). Adding new optional fields to `Person` is backward-compatible without bumping the version (tolerant decoder handles it). However, bumping to `2` is recommended as an auditable boundary, and it is the trigger for a one-time forward migration of existing person.json files:

```swift
// In PeopleStore — after loading each Person from JSON:
// If the envelope.version == 1 and the person has no relationshipType
// but has a Relationship with label "spouse" or "partner", infer:
//   person.relationshipType = .partner
// This heuristic pre-populates the new field from existing data.
```

The `Relationship.label` field is freeform (`Person.swift:55` — "spouse", "manager", "kid", "friend"). A one-time migration pass over all loaded persons can inspect `relationships[].label` to pre-populate `relationshipType` using a simple lookup:

```swift
let partnerLabels: Set<String> = ["spouse", "partner", "wife", "husband", "boyfriend", "girlfriend", "fiancé", "fiancée"]
let familyLabels:  Set<String> = ["mom", "dad", "mother", "father", "sister", "brother", "kid", "child", "parent", "grandparent"]
```

If a person carries a `Relationship` with one of these labels, set `relationshipType` accordingly on first decode. This gives existing users instant relationship-type classification without re-entering data.

**Effort:** S. Pure Swift logic, no schema change needed.

---

### E2-11 — FTS5 body composition: include relationship type and cadence data (S effort)

**What:** The current `insertPerson()` body for `vault_content` (`SecondBrainDB.swift:296–306`) joins: secondary contact info + bio + favorites + memories. After E2-1 and E2-3, extend it to include:

```swift
let profileText = [
    p.relationshipType?.rawValue ?? "",
    p.relationshipProfile?.loveLanguages.map(\.rawValue).joined(separator: " ") ?? "",
    p.relationshipProfile?.relationshipGoals.joined(separator: " ") ?? "",
    p.relationshipProfile?.attachmentStyle?.rawValue ?? ""
].joined(separator: " ")

let bodyText = [secondary, p.bio, p.favorites.joined(separator: " "),
                p.memories.map(\.text).joined(separator: " "),
                profileText].joined(separator: " ")
```

This makes `search("anxious attachment")`, `search("quality time")`, or `search("partner acts of service")` find the right person in the unified FTS index.

**Effort:** S (30 minutes, one-liner change in `insertPerson()`).

---

### E2-12 — Add `person_check_ins` table for structured check-in records separate from encounters (S effort)

**What:** A structured check-in is distinct from a casual encounter log. It has template responses, ratings, and a completion state. Keep it separate from `Encounter` (which is the informal touchpoint log) and track it in SQLite + as a lightweight JSON sidecar:

```sql
CREATE TABLE person_check_ins (
    id TEXT PRIMARY KEY,
    person_id TEXT NOT NULL,
    template_id TEXT NOT NULL,
    completed_at INTEGER,             -- NULL = in-progress
    responses_json TEXT,              -- JSON object: fieldID → answer
    overall_quality INTEGER,          -- 1–5 rating of the relationship at check-in
    notes TEXT,
    created_at INTEGER NOT NULL
);

CREATE INDEX idx_checkins_person ON person_check_ins(person_id, completed_at DESC);
```

This table feeds the `personIDsNeedingCheckIn()` query from E2-6 (via join with `people.last_checkin_at`) and powers the "relationship history" timeline in `PersonDetailView` — showing the arc of a relationship quality rating over time.

**Effort:** S (DDL only; the UI to write rows is M, owned by the check-in flow).

---

## 4. Top 3 Picks

### Pick 1 — E2-1: `RelationshipType` enum on Person (highest leverage, S effort)

This is the single load-bearing field. Every type-specific feature — cadence overrides, content library filtering, per-type check-in templates, FTS filtering, MCP queries — branches off `relationshipType`. Without it, all other relationship-type work is UI scaffolding on top of an untyped data layer. The JSON tolerant decoder makes this a zero-risk migration. Do this first.

### Pick 2 — E2-5: `migrateToV3()` in SecondBrainDB (S effort, enables SQL-layer filtering)

Once `RelationshipType` is on the model, the SQL index must expose it. This migration is additive-only (`ALTER TABLE ADD COLUMN`) — no table rebuilds, no data loss, WAL journal means it's safe to interrupt. The `personIDsNeedingCheckIn()` query (E2-6) is immediately unlocked and replaces the fragile in-memory cadence inference in `SuggestedPeopleView`.

### Pick 3 — E2-10: One-time migration inferring `relationshipType` from existing `Relationship.label` (S effort, zero user friction)

Existing users have people records with labels like "spouse", "dad", "best friend". This migration pre-populates `relationshipType` without asking the user to re-categorize their contacts. It is the difference between "upgrade and nothing works" and "upgrade and your partner is already in the partner path." Small code, high perceived value.

---

## 5. Schema Change Summary Table

| Change | Where | Migration risk | Effort |
|---|---|---|---|
| `RelationshipType` enum + 3 fields on `Person` | `Person.swift` + tolerant decoder | Zero (optional, nil-default) | S |
| Same on `PersonDTO` | `SharedModels.swift` | Zero | S |
| Extend `Encounter` with `kind`, `qualityRating`, `templateID`, `checkInResponses` | `Encounter.swift` (app-side) | Zero (nil-default) | S+M |
| `migrateToV3()` in SecondBrainDB | `SecondBrainDB.swift` | Low (ALTER TABLE ADD COLUMN only) | S |
| `check_in_templates` table | SecondBrainDB v3 migration | Zero (new table) | S |
| `content_library` + `person_content_progress` tables | SecondBrainDB v3 migration | Zero (new tables) | M |
| `person_check_ins` table | SecondBrainDB v3 migration | Zero (new table) | S |
| FTS body includes `relationshipType` + profile text | `SecondBrainDB.insertPerson()` | Zero | S |
| One-time label→type migration on load | `PeopleStore.publishLoaded()` | Zero | S |
| Consolidate VaultKit.Encounter with app Encounter | `VaultKit/Encounter.swift` + `SecondBrainStore.swift` | Low | M |
