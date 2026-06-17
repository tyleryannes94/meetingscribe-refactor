# Data Layer & Persistence Findings — MeetingScribe v2 Audit

## Top friction points / gaps (file:line citations)

### 1. vault_content entity_kind CHECK constraint excludes decisions and action items
`SecondBrainDB.swift:219` defines:
```sql
entity_kind TEXT NOT NULL CHECK(entity_kind IN ('person','meeting','encounter','action_item','voice_note'))
```
`action_item` is in the allowlist, but **no code path in the codebase calls `upsertVaultContent` for action items or decisions**. `PeopleStore.swift:161–181` only indexes meetings and voice notes. `DecisionStore.swift` persists to a flat `decisions.json` with no FTS or embedding index. The entire Decisions ledger and Tasks index are invisible to global search and semantic recall. A user cannot ask the AI "what did we decide about X?" and get a result from the decisions ledger.

### 2. Decisions are stored as a single monolithic JSON array
`DecisionStore.swift:23` writes `decisions.json` as `[Decision]` — one flat array for the entire vault. There is no schema versioning (no `SchemaEnvelope`, no `schemaVersion` field, no `TaskSchemaMigrations`-style registry). A single corrupted decision corrupts the entire ledger. The `Decision` struct (`DecisionStore.swift:6–11`) carries only `meetingID`, `meetingTitle`, `date`, and `text` — no `personIDs`, no `projectID`, no `status`, no embedding. Decisions have zero cross-entity linkage beyond a meeting reference.

### 3. Action items are a single `action_items.json` file, not indexed in FTS/embeddings
`ActionItemStore.swift:56` writes all live and trashed tasks to one flat `action_items.json`. The file is enveloped and migration-aware (via `TaskSchemaMigrations`), but there is no call from `ActionItemStore` to `SecondBrainDB.upsertVaultContent`, so tasks are dark to the `searchVaultHybrid` engine. Users can't search "all tasks about feature X" from ⌘K. Semantic recall for tasks does not exist.

### 4. `allEmbeddings()` loads entire vector table into memory on every hybrid search call
`SecondBrainDB.swift:467` pulls ALL embeddings from the DB on every `searchVaultHybrid` call (`PeopleStore.swift:223`). At v1 scale (dozens of meetings) this is fine. At v2 scale with decisions, tasks, and backfill across hundreds of meetings, this becomes a full table scan + heap allocation on every query. There's no ANN index (SQLite-vec, FAISS, or even a pre-sorted cache). This is a latency time-bomb.

### 5. Two parallel FTS tables with overlapping coverage
`SecondBrainDB.swift:153–155` creates `search_index` (FTS5, people-only, v1). `SecondBrainDB.swift:226–228` creates `vault_fts` (FTS5, all entities, v2). People are inserted into **both** (`insertPerson` at line 335–352 writes to both `search_index` and `vault_content`/`vault_fts`). This is a write-amplification bug and a rebuild-consistency hazard: `rebuild()` at line 285 clears `search_index` and `vault_content WHERE entity_kind='person'` — but the FTS triggers fire on vault_content changes, not on search_index changes. Divergence is likely under partial rebuilds.

### 6. No cross-entity relational index in SQLite
The DB has entity rows but no foreign-key join tables. Cross-entity queries that v2 needs — "all tasks owned by person P", "all decisions from meetings where person P attended", "all meetings linked to project Q", "context around a decision: who was in the room, what tasks followed?" — require loading all JSON files into memory and filtering in Swift. The SQLite layer has no `meeting_attendees`, `task_persons`, or `decision_persons` tables.

### 7. `SecondBrainDB` is owned and gated through `PeopleStore`
`PeopleStore.swift:69` declares `private let db = SecondBrainDB()`. The DB is only accessible through People-tab pathways. Non-People entities (decisions, tasks) that want to index themselves must route through `PeopleStore.shared`, creating a layering violation and making it easy to miss indexing calls. `indexMeeting` and `indexVoiceNote` are exposed as methods on `PeopleStore`, not on a lower-level shared service.

### 8. `SchemaEnvelope` is not applied to `DecisionStore` or `MeetingStore`
`MeetingStore.swift` uses `meetingSchemaVersion = 2` as a constant but the meeting JSON has no in-file envelope — `MeetingStore.swift:33` sets the version, but `Decision` has no version field and no migration path. A v2 field added to `Decision` (e.g. `personIDs: [String]`) silently defaults to empty on old records with no migration log.

---

## Existing items to endorse (from prior plan or codebase)

- **`SecondBrainDB` WAL + corrupt-check + rebuild pattern** (`SecondBrainDB.swift:66–85`): the `quick_check` + delete + rebuild flow is solid. Worth keeping and extending to cover the new entities.
- **`TaskPersistenceCoordinator` debounce/coalesce/flush-on-terminate** pattern: excellent. The `.bak` write-ahead backup at `TaskPersistenceCoordinator.swift:95–99` should be adopted by DecisionStore.
- **`TaskSchemaMigrations` registry** with per-step transforms and backup-before-migrate: the right abstraction. Needs a `DecisionSchemaMigrations` counterpart.
- **Hybrid RRF search** in `searchVaultHybrid` (`PeopleStore.swift:220–263`): well-engineered. Preserves lexical as fallback. Worth keeping; just needs vector scaling mitigation.
- **`SchemaEnvelope` + `SharedCoders`** in VaultKit: good foundation; extend to Decisions.

---

## NET-NEW recommendations

### E3-1: Unified Entity Indexer — extract `SecondBrainDB` from `PeopleStore` into a shared service
- **What:** Promote `SecondBrainDB` (or a new `VaultIndexService`) to a top-level singleton accessible to all stores. Add `indexDecision()`, `indexTask()`, and `indexTranscript()` entry points. Remove the `PeopleStore`-as-gatekeeper anti-pattern. Every store (ActionItemStore, DecisionStore, MeetingStore) writes to the index directly after a mutation.
- **Why (second-brain angle):** Without this, decisions and tasks are permanently dark to semantic recall and the AI chat assistant. "What did we decide about onboarding?" returns nothing. "Show me all tasks from my Q3 planning meeting" returns nothing. The second brain is blind to two of its five data domains.
- **Cross-feature connections:** GlobalSearch, AI Chat (ChatTools), PreMeetingBrief, WeeklyRecap, StandupDigest.
- **Effort:** M | **Impact:** High
- **Deps:** none

### E3-2: Relational join tables in SQLite for cross-entity queries
- **What:** Add three tables to `SecondBrainDB` (v4 migration):
  - `meeting_persons(meeting_id, person_id)` — attendees
  - `decision_persons(decision_id, person_id)` — who was in the room
  - `task_persons(task_id, person_id, role TEXT)` — owner/mentioned
  
  Populate on index. Expose query methods: `decisionIDs(forPersonID:)`, `taskIDs(forPersonID:)`, `meetingIDs(forPersonID:)` (currently O(n) in-memory scans).
- **Why (second-brain angle):** Pre-meeting brief needs "open tasks owned by this attendee" and "decisions made with this person". Today this is a brute-force in-memory filter. At v2 scale (>1000 tasks, >500 decisions) it becomes a blocking hitch.
- **Cross-feature connections:** PreMeetingBriefView, PersonDetailView, TodayView 1:1 section, WeeklyRecap.
- **Effort:** M | **Impact:** High
- **Deps:** E3-1

### E3-3: Apply `SchemaEnvelope` + `DecisionSchemaMigrations` to `DecisionStore`
- **What:** Wrap `decisions.json` in `SchemaEnvelope`. Add `personIDs: [String]?`, `projectID: String?`, and `status: DecisionStatus?` fields to `Decision`. Add `DecisionSchemaMigrations` registry with `backupBeforeMigration` support. Add `TaskPersistenceCoordinator`-style debounced off-main writes.
- **Why (second-brain angle):** Decisions are currently write-once snapshots with no context. A decision linked to people and projects becomes a first-class second-brain entity: the AI can say "three months ago you decided X in a meeting with Sarah — there are 2 open tasks related to that decision."
- **Cross-feature connections:** DecisionStore, PersonDetailView (decisions tab), ProjectDetailView, PreMeetingBrief.
- **Effort:** S | **Impact:** High
- **Deps:** none

### E3-4: ANN approximation or cached embedding index for `searchVaultHybrid`
- **What:** Replace the `allEmbeddings()` full-table scan in `searchVaultHybrid` with a session-cached embedding map, rebuilt async after mutations (similar to `PeopleStore`'s `personIndex` / `encounterCountIndex` pattern). At >500 embeddings, add an optional flat-index cosine pre-filter (top-K by dot product using Accelerate BLAS) before full cosine scoring. Alternatively, integrate `sqlite-vec` extension when stable.
- **Why (second-brain angle):** Hybrid search is the core recall primitive. If it degrades to multi-second latency as content grows, the AI chat and GlobalSearch both feel broken. Local Ollama embeddings make this table grow fast (every meeting + voice note + task).
- **Cross-feature connections:** GlobalSearch, ChatTools, searchVaultHybrid, relatedMeetingIDs.
- **Effort:** M | **Impact:** Med
- **Deps:** E3-1

### E3-5: Index action items into vault_fts + embeddings after store mutations
- **What:** In `ActionItemStore`, after any `upsert`/`add`/`update` call, index the task into `SecondBrainDB.upsertVaultContent(entityKind: "action_item", ...)` with `title + notes + owner + project` as body. Run `embedAndStore` async. Add `ActionItemStore.deindex(id:)` on soft-delete.
- **Why (second-brain angle):** ⌘K should be able to find tasks by semantic content ("something about dashboard latency"), not just title prefix. The AI chat's `ActionItemChatTools` currently scans in-memory arrays; FTS+embeddings would let it answer "what did I commit to last week?" accurately across hundreds of tasks.
- **Cross-feature connections:** GlobalSearch, ActionItemChatTools, TodayView, PreMeetingBrief.
- **Effort:** S | **Impact:** High
- **Deps:** E3-1

---

## Top 3 picks

1. **E3-1** — Extracting `SecondBrainDB` from `PeopleStore` is the prerequisite for everything; without it, decisions and tasks stay invisible to the entire intelligence layer.
2. **E3-5** — Indexing tasks into FTS+embeddings is an S-effort change that immediately unlocks semantic search and AI chat accuracy for the most-used data in the app.
3. **E3-3** — Wrapping `DecisionStore` in `SchemaEnvelope` with person/project linkage is S effort but transforms decisions from read-only meeting artifacts into navigable cross-entity nodes — the foundation of true second-brain recall.
