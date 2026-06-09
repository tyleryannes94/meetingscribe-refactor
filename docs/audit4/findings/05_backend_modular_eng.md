# 05 — Modular Backend / Data Architecture (Staff Backend Eng)

**Lens:** Treat Projects/Tasks as the data plane for a Notion/Linear-scale workspace, not a meeting side-feature. The question is whether the persistence, schema, query, sync, and extension layers can hold thousands of tasks across multiple views, devices, automations, and external providers — or whether the single `@MainActor` god-store with full-file JSON rewrites is the ceiling. Focus is on *foundations* (storage engine, schema, query/index layer, change log, provider/automation abstractions) that unblock every downstream feature, not on UI.

This finding is deliberately scoped to backend/data/perf/extensibility and avoids re-treading the UI/caching items already covered in `G2_tab_tasks.md` (TK-1…TK-10) and the cross-tab index work in `G3_sync_datamodel.md` (SD-1…SD-8). Where they overlap I reference, not duplicate.

---

## Verified already-built (do NOT re-propose)

- **Schema-enveloped persistence with a migration hook.** All six task files write through `SchemaEnvelope` (`ActionItemStore.swift:744-758`); `SchemaEnvelope.decode` accepts both legacy raw-array and `{schemaVersion,data}` shapes and exposes a `migrate:(payload, from, to)` closure (`Sources/VaultKit/SchemaEnvelope.swift:32-49`). The envelope substrate exists — it's just unused for real migrations (all versions pinned to `1`, `ActionItemStore.swift:651-655`).
- **Off-main *initial load*.** Decode happens in `Task.detached` and publishes back on the main actor (`ActionItemStore.swift:41-55`). (Note: only the *read* is off-main; every *write* is still synchronous on-main — see BE-1.)
- **Real foreign keys on the model.** `ActionItem` carries `meetingID`, `ownerPersonID`, `projectID`, `sectionID`, `labelIDs`, plus generic `source`/`externalID`/`externalURL` and Notion `notionPageID`/`notionURL` (`ActionItem.swift:16-62`). The Initiative › Project › Task hierarchy with `parentID` nesting and cycle-guard reparenting exists (`ActionItemStore.swift:558-583`).
- **External import normalization + dedup.** `ExternalTask` DTO and `mergeExternal` dedup by `(source, externalID)` / `notionPageID`, preserving local-only fields (`ActionItemStore.swift:188-231`); Linear GraphQL paging and Notion DB query/property decoders exist (`TaskSyncService.swift:37-301`).
- **Two agent surfaces already CRUD tasks.** In-process Chat tools (`Chat/ActionItemChatTools.swift:22-291`) and the out-of-process MCP server reading/writing `action_items.json` directly (`Sources/MeetingScribeMCP/main.swift:204-280, 1208-1280`).
- **A live SQLite + FTS5 engine in the app.** `SecondBrainDB` already ships `vault_fts`, triggers, BM25 ranking, and a `migrateToV2()` path (`People/SecondBrainDB.swift:174-218`) — the substrate for BE-3/BE-9 exists; tasks just don't use it.

---

## Improvements

> Foundational items (unblock multiple others): **BE-1, BE-2, BE-3, BE-5, BE-7**.

### BE-1 — Debounced, coalesced, off-main write path (durability layer)  *[FOUNDATIONAL]*
- **Problem:** Every mutation re-encodes the *entire* array (pretty+sorted) and writes atomically on the main actor. `update()` → `save()` (`ActionItemStore.swift:536-543`), and `writeEnvelope` runs `encoder(pretty:true,sorted:true)` + `data.write(.atomic)` synchronously on `@MainActor` (`:744-757`). A drag (N midpoint-`sortIndex` writes) or toggling 5 subtasks = N full-DB encodes + N atomic file replacements on the UI thread. At 1–10k tasks each encode is multi-ms and scales O(n) with library size, on the hot path of every keystroke-driven edit.
- **Evidence:** `ActionItemStore.swift:536-543`, `:668-672`, `:744-757`.
- **Recommendation:** Introduce a `PersistenceCoordinator` actor that owns a per-file dirty set and a 300–500ms debounce; mutators mark dirty and return immediately; the actor encodes (`pretty:false` for the hot path, pretty only on export) and writes off-main. Flush synchronously on `scenePhase==.background`/terminate and on explicit `flush()`. Keep `.atomic`. This is the same fix `G2_tab_tasks.md` TK-2 calls for from the UI side — own it in the data layer so Chat/MCP/automation writes get it too.
- **Impact:** Removes the worst main-thread stall and the torn-write-during-burst risk; prerequisite for bulk ops and automation that fire many writes.
- **Effort:** S–M · **Deps:** none.

### BE-2 — Split the god-store into repositories + a façade  *[FOUNDATIONAL]*
- **Problem:** `ActionItemStore` is a 759-line `@MainActor` object owning five published arrays and *all* CRUD for items, projects, labels, sections, initiatives, project↔meeting links, subtasks, external merge, and persistence for six files (`ActionItemStore.swift:12-16` + the whole file). Every consumer (tab, Today widget, Chat, sidebar) depends on the whole thing; there are no testing seams and no separation between domain logic and storage.
- **Evidence:** Entire `ActionItemStore.swift`; five `@Published` arrays at `:12-16`; six `save*()`/`load*()` pairs at `:657-739`.
- **Recommendation:** Extract `TaskRepository`, `ProjectRepository`, `LabelRepository`, `SectionRepository`, `InitiativeRepository`, each a small actor/struct over a `Store` protocol (load/save/observe), all routing writes through BE-1's coordinator. Keep a thin `@MainActor TaskStore` façade that exposes `@Published` snapshots for SwiftUI and delegates. This is the decomposition `MASTER_PLAN_V3.md` ARCH-3 already wants applied to other god-files.
- **Impact:** Independent testing, parallel evolution, smaller recompiles; precondition for swapping the storage engine (BE-3) behind a repo without touching views.
- **Effort:** M · **Deps:** none (do alongside BE-1).

### BE-3 — Move task storage to SQLite/GRDB behind the repositories  *[FOUNDATIONAL]*
- **Problem:** Whole-array-in-memory + whole-file-rewrite is structurally O(n) per write and O(n) per query, and offers no indexing, no partial reads, no transactions, no concurrent reader. It will not scale to 10k tasks with several views.
- **Evidence:** `decodeArray` loads the full array (`ActionItemStore.swift:60-67`); every reader is `items.filter{…}` (`:72-95, 244-250, 409-412, 513-515`); every writer rewrites the file (`:668-672`).
- **Recommendation:** Add a `tasks` table (+ `projects`, `sections`, `labels`, `task_labels`, `initiatives`) in the *existing* SQLite stack (`SecondBrainDB` already links GRDB-style access, `People/SecondBrainDB.swift`). Indexes on `(project_id,status)`, `(owner_person_id)`, `(meeting_id)`, `(status,due_date)`, `(source,external_id)`. Repositories (BE-2) expose typed queries; SwiftUI gets snapshots via a published cache. Keep a JSON export/import path for the human-readable-vault promise (`docs/ARCHITECTURE.md:360`) and so the MCP server's file contract can be regenerated. Use the `SchemaEnvelope.migrate` hook (already wired but unused) only for the one-time JSON→SQLite import.
- **Impact:** O(log n) lookups, partial/streamed reads, transactional multi-row writes, the substrate for query engine (BE-7), FTS (BE-9), change log (BE-5), and rollups (BE-11).
- **Effort:** L · **Deps:** BE-1, BE-2. (Highest-leverage but largest; can be staged behind the repo protocol so views never change.)

### BE-4 — Cross-process write race between the app and the MCP server  *[CORRECTNESS]*
- **Problem:** The app holds `items` in memory and rewrites the *whole* file on save; the MCP server independently reads `action_items.json`, mutates a record, and rewrites the whole file (`writeActionItemsRaw`, `Sources/MeetingScribeMCP/main.swift:266-280`; `tool_updateActionItem`/`tool_createActionItem`, `:1208-1280`). There is no file lock, no mtime check, no merge. Last writer wins: an MCP edit is silently overwritten by the next in-app `save()`, and vice-versa. This is a live data-loss bug today, before any cross-device sync exists.
- **Evidence:** `Sources/MeetingScribeMCP/main.swift:254-280, 1241-1280`; app side `ActionItemStore.swift:668-672`.
- **Recommendation:** Single-writer discipline: route all MCP task mutations through the running app (local IPC/HTTP endpoint, or a command-queue file the app drains) rather than direct file writes; or, if BE-3 lands, point the MCP server at the SQLite DB with WAL mode so both processes are real concurrent writers under one engine. Short-term mitigation: advisory file lock + mtime-precondition (reject write if the file changed under you) and have the app reload on `DispatchSource` file-change events.
- **Impact:** Eliminates silent task loss; makes the agent surface trustworthy.
- **Effort:** M · **Deps:** ideally BE-3 (clean fix); a lock/reload mitigation is independent.

### BE-5 — Append-only change log / event journal (event sourcing seam)  *[FOUNDATIONAL]*
- **Problem:** Mutations are destructive in place (`update` bumps `updatedAt` and overwrites, `ActionItemStore.swift:536-543`). There is no history, so undo/redo, audit, conflict-free sync, and "what changed since last sync" are all impossible. Cross-device sync (`docs/CROSS_DEVICE_SYNC_MASTER_PLAN.md`) and the merge engine want exactly this delta stream.
- **Evidence:** `ActionItemStore.swift:132-141, 536-543`; sync plan asks for additive idempotent merge (`docs/sync-plans/agent-5-merge-ingestion-engine.md`).
- **Recommendation:** Emit a `ChangeEvent { id, entity, entityID, field?, op, lamport/timestamp, deviceID, payload }` for every mutation into an append-only `change_log` table/file. Drive persistence *from* the log (the projection is BE-3's tables). This single seam unlocks BE-6 (undo/redo), BE-8 (delta sync), and observability (BE-19).
- **Impact:** The keystone for sync, undo, and audit; turns the data layer from "current state only" into a replayable history.
- **Effort:** M · **Deps:** BE-2 (mutations funnel through repos so the log is the only write path).

### BE-6 — Undo/redo on the change log
- **Problem:** No undo anywhere in task editing — a mis-drag or accidental "delete" is unrecoverable (`delete` is immediate `removeAll` + save, `ActionItemStore.swift:482-485`).
- **Evidence:** `ActionItemStore.swift:482-485, 606-615`.
- **Recommendation:** With BE-5 in place, implement undo as inverse-event application (or an `UndoManager` bridge that registers the inverse of each `ChangeEvent`). Group rapid events (drag, bulk edit) into one undo coalescing window.
- **Impact:** Table-stakes editor safety; pairs with the bulk-edit work in `G2_tab_tasks.md` TK-3.
- **Effort:** M · **Deps:** BE-5.

### BE-7 — A real query layer (typed predicates + sort/group) replacing ad-hoc filters  *[FOUNDATIONAL]*
- **Problem:** Querying is scattered, hand-rolled, and duplicated: `items(for:)`, `items(forProject:)`, `openItems()`, `todayAndYesterday()`, `openCount(forProject:)`, `openCount(forInitiative:)`, each a bespoke `filter`+`sorted` (`ActionItemStore.swift:72-127, 244-250, 409-412, 513-515`). UI layers add *more* duplicate filter/sort logic (documented in `G2_tab_tasks.md` #2). There is no composable way to express "open, due this week, in project X, label Y, sorted by priority then due."
- **Evidence:** `ActionItemStore.swift:72-127`, sort helper `:110-127`.
- **Recommendation:** Define a `TaskQuery { filters:[FilterClause], sort:[SortKey], group:GroupBy?, limit }` value type and a `TaskQueryEngine` that compiles it to a SQLite `WHERE/ORDER BY` (post-BE-3) or an in-memory evaluation (pre-BE-3) — one code path. Saved views become persisted `TaskQuery` structs (matches `G2` TK-9). Expose to Chat/MCP so agents can run structured queries instead of pulling everything and filtering client-side (`ActionItemChatTools.swift:131-157` currently loads all items then filters in Swift).
- **Impact:** One correct, indexed, reusable query path for every view, badge, agent, and automation; kills filter drift.
- **Effort:** M · **Deps:** BE-2; far better with BE-3.

### BE-8 — Conflict-free sync model (per-field LWW + Lamport clock) on the change log
- **Problem:** The cross-device plan is "additive idempotent merge" but the model has no per-field version vectors or causal ordering — only `updatedAt` (`ActionItem.swift:65`). `mergeExternal` already shows the pain: it hand-picks which fields to overwrite vs preserve (`ActionItemStore.swift:196-214`). Two devices editing different fields of the same task will clobber whole records on a coarse last-write-wins.
- **Evidence:** `ActionItem.swift:64-65`; field-by-field preservation logic `ActionItemStore.swift:196-214`; sync plan `docs/CROSS_DEVICE_SYNC_MASTER_PLAN.md`.
- **Recommendation:** Adopt per-field LWW-Register semantics keyed by `(lamportClock, deviceID)` carried in BE-5's events; merge = replay both logs, last-writer-per-field wins deterministically. Add a stable `deviceID` and a monotonic per-device counter. This generalizes both external-provider merges and device↔device merges into one resolver.
- **Impact:** Correct, deterministic multi-writer merges; the foundation the sync master plan needs to move from one-way backup to bidirectional.
- **Effort:** L · **Deps:** BE-5.

### BE-9 — Full-text search index for tasks
- **Problem:** No search index for tasks; the UI substring-filters titles in memory per keystroke (`G2_tab_tasks.md` #2). Notes/owner/subtasks aren't searchable at all.
- **Evidence:** No FTS for tasks; meeting/people FTS exists in `SecondBrainDB.swift:179-218` but tasks aren't indexed.
- **Recommendation:** Add tasks to the existing FTS5 store (title, notes, owner, subtask titles, project name) with triggers mirroring `vault_fts`. Expose ranked search via BE-7's query engine and to Chat/MCP.
- **Impact:** Instant search at 10k tasks; uniform search surface across the app.
- **Effort:** M · **Deps:** BE-3 (or standalone against SecondBrainDB).

### BE-10 — Generic custom-field / property schema (Notion-parity)  *[EXTENSIBILITY]*
- **Problem:** Every task attribute is a hardcoded Swift field (`ActionItem.swift:13-65`). Adding a Notion-style custom property (a "Story Points" number, an "Environment" select, a relation) requires a Swift code change, a new Codable field, and a release. A Notion replacement *is* arbitrary user-defined properties — this is the single biggest extensibility gap.
- **Evidence:** Fixed fields `ActionItem.swift:13-65`; `Status`/`Priority` are closed enums (`:78-117`).
- **Recommendation:** Introduce a `PropertyDefinition { id, name, kind(text/number/select/multiSelect/date/person/relation/checkbox/url), options, config }` owned per-Project (the "database schema") and a typed `PropertyValue` bag on the task (`properties: [PropertyID: PropertyValue]`, stored as a JSON column post-BE-3 or a side-table). Keep the current first-class fields as built-in property definitions so existing data and code keep working. Status/priority become select properties with default option sets.
- **Impact:** Users (and agents) add fields without a build; views/filters (BE-7) operate generically; this is the architectural difference between a task list and a database product.
- **Effort:** L · **Deps:** BE-3, BE-7.

### BE-11 — Relations + rollups engine
- **Problem:** Relations are ad-hoc one-offs: `projectID`, `ownerPersonID`, `meetingIDs`, `linearProjectID`, each with bespoke reverse lookups (`ActionItemStore.swift:398-433, 513-515`) and bespoke counts (`openCount(forProject:)` `:93-95`, `openCount(forInitiative:)` `:409-412`). No generic way to define "Tasks ← relation → other Tasks" or to roll up child values to a parent.
- **Evidence:** `ActionItemStore.swift:93-95, 398-433, 513-515`.
- **Recommendation:** Build on BE-10's `relation` property kind + a `RollupDefinition { sourceRelation, targetProperty, aggregate(count/sum/min/max/percentDone) }`. Materialize rollups incrementally off BE-5 events (recompute only affected parents) and cache them (subsumes the per-render count recomputation flagged in `G2` TK-7).
- **Impact:** Project progress %, initiative roll-ups, sub-task completion, dependency counts — all generic and cached instead of O(n) per render.
- **Effort:** L · **Deps:** BE-5, BE-10.

### BE-12 — Automation / rules engine (triggers → conditions → actions)
- **Problem:** No automation primitive. Cross-field side-effects are inlined ad hoc (e.g. completing all subtasks doesn't change status; deleting a label scrubs it from items by hand, `ActionItemStore.swift:306-315`). A Linear/Notion replacement needs "when status→Done, set completedAt"; "when due passes, bump priority"; "when added to project X, assign owner."
- **Evidence:** No rules layer; ad-hoc side effects `ActionItemStore.swift:306-315, 347-354, 383-390`.
- **Recommendation:** A `Rule { trigger(EventType), conditions:[FilterClause], actions:[Action] }` evaluated by an `AutomationEngine` subscribed to BE-5's change stream. Actions reuse repository mutators (so they're logged and undoable). Guard against cycles with a per-cycle event budget.
- **Impact:** User- and agent-defined automation without code; consolidates scattered side-effects into one auditable place.
- **Effort:** L · **Deps:** BE-5, BE-7.

### BE-13 — Recurring-task generation engine
- **Problem:** No recurrence concept; tasks are one-shot (`ActionItem` has `dueDate`/`startDate` but no recurrence rule, `ActionItem.swift:30-42`). A productivity tool needs repeating tasks.
- **Evidence:** `ActionItem.swift:30-42` — no `recurrence`.
- **Recommendation:** Add an optional `RecurrenceRule` (RFC-5545 RRULE subset: freq, interval, byday, end) to a task template, and a scheduler that materializes the next instance on completion (or via a daily background pass). Generation goes through the repository + change log (BE-5) so instances sync and undo cleanly. Persist `seriesID` to relate instances.
- **Impact:** Closes a core feature gap vs Things/Todoist; clean because it rides BE-5/BE-12.
- **Effort:** M · **Deps:** BE-5; optionally BE-12 (recurrence as a rule).

### BE-14 — Provider abstraction for external integrations  *[EXTENSIBILITY]*
- **Problem:** Linear and Notion are bespoke, duplicated code paths. `TaskSyncService` is a single `enum` with Linear GraphQL and Notion REST hardcoded side by side (`TaskSyncService.swift:37-301`), Notion *push* lives in a *separate* `NotionActionItemService` (`NotionActionItemService.swift`), and `syncExternalTasks` hardcodes an `if linearKey {…} if notionKey {…}` ladder (`TaskSyncService.swift:416-454`). Adding Todoist/Jira/Asana means copy-pasting another decoder set and another branch; there's no pull/push symmetry, no per-provider field mapping, no incremental-sync cursor storage.
- **Evidence:** `TaskSyncService.swift:37-301, 416-454`; `NotionActionItemService.swift:45-80`.
- **Recommendation:** Define `protocol TaskProvider { var id; func pull(since:) async throws -> [ExternalTask]; func push(_:) async throws -> ExternalRef; func mapStatus/mapPriority; func projects() }` plus a `ProviderRegistry`. Move Linear/Notion behind it; store per-provider sync state (cursor, lastSync, field map) in a `provider_state` record. `mergeExternal` (`ActionItemStore.swift:188-231`) becomes the one ingestion point fed by any provider, and resolves via BE-8's field-level merge instead of the hand-tuned overwrite list.
- **Impact:** New integrations are a conformance, not a fork; pull/push unified; incremental sync possible.
- **Effort:** M–L · **Deps:** BE-8 for clean merge (works without it, less robust).

### BE-15 — Stabilize the agent/MCP CRUD surface on the query/repo layer
- **Problem:** Two agent surfaces diverge. Chat tools call the in-memory store (`ActionItemChatTools.swift:116-127`) and *load-all-then-filter* in Swift (`:131-157`); the MCP server bypasses the app entirely and edits the file (BE-4). They expose different field sets and no project/section/label/relation writes. As agents become first-class clients of a Notion replacement, this surface must be complete and consistent.
- **Evidence:** `ActionItemChatTools.swift:22-291`; `Sources/MeetingScribeMCP/main.swift:1006-1280`.
- **Recommendation:** Define one `TaskService` API (CRUD + `TaskQuery` from BE-7 + bulk ops) as the *single* programmatic entry point; back both Chat tools and the MCP server with it (MCP via the IPC channel from BE-4). Add missing verbs: set project/section/labels, create/move project, bulk update, run-query.
- **Impact:** Agents get a complete, race-free, query-capable API; one place to validate and authorize writes.
- **Effort:** M · **Deps:** BE-4, BE-7.

### BE-16 — Trash / soft-delete with restore + retention
- **Problem:** Deletes are hard and immediate for tasks, projects, labels, sections, initiatives (`ActionItemStore.swift:306-315, 347-354, 383-390, 482-485, 606-615`). Combined with no undo (BE-6) and the MCP race (BE-4), an accidental or automated delete is permanent and silent.
- **Evidence:** `ActionItemStore.swift:482-485, 606-615`.
- **Recommendation:** Add `deletedAt: Date?` (soft-delete) to entities; queries filter it out by default; a Trash view lists and restores; a background sweep purges after N days. Cascade as tombstones, not destruction, so sync (BE-8) can propagate deletes without losing the ability to undo.
- **Impact:** Safety net; correct delete semantics under sync; standard for the category.
- **Effort:** M · **Deps:** BE-7 (default filter); plays with BE-5/BE-8 (tombstones).

### BE-17 — Data-integrity & validation layer (referential + invariant checks)
- **Problem:** Dangling references and invariants aren't enforced. `mergeExternal` auto-creates projects by *name* match (`resolveProjectID`, `ActionItemStore.swift:235-240`) → easy to spawn duplicate/garbage projects. Nothing validates that a task's `sectionID` belongs to its `projectID`, that `labelIDs` exist, or that `ownerPersonID` resolves. `delete` cleans up `projectID`/`sectionID`/`labelIDs` by manual loops (`:306-315, 347-354, 606-615`) that are easy to miss for new relations.
- **Evidence:** `ActionItemStore.swift:235-240, 306-315, 347-354, 606-615`.
- **Recommendation:** With BE-3, declare FK constraints (`ON DELETE SET NULL`) so cleanup is the engine's job, not hand-loops. Add a `validate()`/`integrityCheck()` pass (orphan scan, section-project mismatch, label existence) runnable on launch/import, reporting via the existing `ErrorReporter` (`ActionItemStore.swift:754-756`). Match external projects by stable `linearProjectID`/`externalID`, not display name.
- **Impact:** Prevents silent corruption and duplicate-project sprawl; removes fragile manual cascade code.
- **Effort:** M · **Deps:** BE-3 for FK enforcement (validation pass is standalone).

### BE-18 — Versioned schema migrations actually wired (not pinned to v1)
- **Problem:** All schema versions are hardcoded `1` and no `migrate:` closure is ever passed to `SchemaEnvelope.decode` (`ActionItemStore.swift:42-46, 651-655`). Today back-compat relies entirely on "every new field is optional" — which works for additions but cannot rename a field, change a type, or split a struct (e.g. moving status into a select property for BE-10). The migration machinery exists but is dormant.
- **Evidence:** `ActionItemStore.swift:42-46, 651-655`; unused `migrate` param `Sources/VaultKit/SchemaEnvelope.swift:37-47`.
- **Recommendation:** Establish a `TaskSchemaMigrations` registry (`from→to` transforms), bump versions deliberately, and pass the chained migrate closure into every `decode`. First real use: the JSON→SQLite import (BE-3) and the built-in→custom-property remap (BE-10). Add a one-time backup of the pre-migration file.
- **Impact:** Unblocks every structural schema change the roadmap needs without breaking installs; de-risks BE-3/BE-10.
- **Effort:** S–M · **Deps:** none (enabler for BE-3, BE-10).

### BE-19 — Observability: metrics + a write/query telemetry seam
- **Problem:** Persistence only logs on *failure* (`ActionItemStore.swift:754-756`); there's no visibility into write frequency, encode time, save sizes, query latency, or sync deltas. You can't tell that "drag = 40 full-DB writes" without reading the code. At scale you're flying blind on exactly the perf cliffs this audit is about.
- **Evidence:** `ActionItemStore.swift:744-757` (log on error only).
- **Recommendation:** Add lightweight signposts/counters (OSSignposter) around encode/write and query execution (rows scanned, ms), surfaced in a debug/diagnostics panel. Emit a "save coalesced N→1" counter from BE-1 to prove the win. Feed `ErrorReporter` category `.storage` consistently.
- **Impact:** Makes regressions and hot paths measurable; validates BE-1/BE-3 gains; cheap insurance.
- **Effort:** S · **Deps:** BE-1 (to instrument the coordinator).

### BE-20 — Import / export pipeline (round-trippable, human-readable vault)
- **Problem:** The vault's "plain files you can grep/back up" promise (`docs/ARCHITECTURE.md:360`, `docs/USER_GUIDE.md:323`) is met today *because* storage is JSON; moving to SQLite (BE-3) breaks it unless export is a first-class feature. There's also no standard CSV/Markdown/Notion-export ingest path beyond the live API connectors.
- **Evidence:** `ActionItemStore.swift:744-757` (JSON is the only format); architecture promise `docs/ARCHITECTURE.md:360`.
- **Recommendation:** A `TaskExporter`/`TaskImporter` producing/consuming a stable JSON snapshot (and CSV/Markdown) of tasks+projects+properties, plus a Notion/CSV importer that feeds BE-14's ingestion path. Run export on a schedule so the grep-able file always exists alongside the DB, preserving the local-first contract and giving the cross-device sync (`docs/CROSS_DEVICE_SYNC_MASTER_PLAN.md`) a clean file to ship.
- **Impact:** Keeps the local-first promise across the storage change; unlocks migration in/out of competitors; backup-friendly.
- **Effort:** M · **Deps:** BE-3 (so export reflects the DB); BE-10 (export custom props).

### BE-21 — Concurrency & validation hardening on mutators
- **Problem:** Mutators silently no-op on missing IDs (`update` early-returns if not found, `ActionItemStore.swift:536-537`; same for `updateProject`/`updateInitiative`) so a stale-ID write from an agent or another device just vanishes with no signal. Titles aren't validated except in `createTask` (`:152-158`); `sortIndex` collisions can occur. There's no optimistic-concurrency token, so concurrent edits to the same record race even in-process.
- **Evidence:** `ActionItemStore.swift:536-543, 391-395, 633-640`; trim only in `createTask` `:152-158`.
- **Recommendation:** Make mutators return a `Result`/throw `notFound` so callers (Chat/MCP/automation) learn the write failed; validate/normalize inputs centrally in the repository; add a per-record `rev` (version) for optimistic concurrency that BE-8's merge and BE-15's API can check.
- **Impact:** Agent and sync writes become observable and safe; fewer silent drops.
- **Effort:** S–M · **Deps:** BE-2; pairs with BE-8/BE-15.

---

## Top 5 picks

1. **BE-1 — Debounced off-main write coordinator.** *(Phase 1, foundational/perf.)* Smallest change that removes the worst main-thread stall and torn-write risk; everything that writes more (bulk ops, automation, recurrence) depends on it.
2. **BE-3 — SQLite/GRDB storage behind repositories.** *(Phase 2, foundational/scale.)* The single change that lifts the O(n)-per-write/O(n)-per-query ceiling and is the substrate for the query engine, FTS, custom fields, rollups, and the change log. Staged behind BE-2's repo protocol so views never change.
3. **BE-5 — Append-only change log.** *(Phase 2, foundational/extensibility.)* The keystone seam: it's the prerequisite for undo (BE-6), conflict-free sync (BE-8), automation (BE-12), recurrence (BE-13), and observability — without it those are all bespoke.
4. **BE-4 — Fix the app↔MCP file write race.** *(Phase 1, correctness.)* A live, silent data-loss bug *today*; trust in the agent surface is impossible until this is closed.
5. **BE-10 — Generic custom-field/property schema.** *(Phase 3, extensibility.)* The architectural line between a task list and a Notion-class database; the highest-ceiling feature, cleanly enabled once BE-3/BE-7 exist.

**Single highest-value:** BE-5 (change log) — it is the one abstraction that turns "current-state JSON blobs" into a replayable, syncable, undoable, automatable system, and it unblocks the most downstream features.

---

## Target module architecture (sketch)

```
                         SwiftUI views / Today widget / Chat tools / MCP server
                                              │ (snapshots + TaskService API)
                          ┌───────────────────┴────────────────────┐
                          │            TaskService (façade)         │  ← single programmatic API (BE-15)
                          │   CRUD · bulk · TaskQuery · subscribe    │
                          └───────────────────┬────────────────────┘
        ┌──────────────┬───────────────┬──────┴───────┬───────────────┬─────────────────┐
        │ TaskRepo     │ ProjectRepo   │ LabelRepo     │ SectionRepo   │ InitiativeRepo  │  (BE-2)
        └──────┬───────┴───────┬───────┴──────┬────────┴───────┬───────┴────────┬────────┘
               │               │              │                │                │
        ┌──────┴───────────────┴──────────────┴────────────────┴────────────────┴───────┐
        │  Engines: QueryEngine (BE-7) · AutomationEngine (BE-12) · RollupEngine (BE-11) │
        │           RecurrenceScheduler (BE-13) · PropertySchema (BE-10) · FTS (BE-9)     │
        └───────────────────────────────────┬───────────────────────────────────────────┘
                                             │ every mutation emits a ChangeEvent
                          ┌──────────────────┴───────────────────┐
                          │     ChangeLog (append-only, BE-5)     │ ──► SyncResolver (LWW/Lamport, BE-8)
                          └──────────────────┬───────────────────┘        ▲   provider pull/push
                                             │ projects into                │
                          ┌──────────────────┴───────────────────┐   ┌─────┴───────────────────────┐
                          │  PersistenceCoordinator (BE-1, actor) │   │ ProviderRegistry (BE-14)    │
                          │  debounced · coalesced · off-main     │   │  Linear · Notion · Jira ... │
                          └──────────────────┬───────────────────┘   └─────────────────────────────┘
                          ┌──────────────────┴───────────────────┐
                          │  Storage engine: SQLite/GRDB (BE-3)   │ + JSON export/import (BE-20)
                          │  indexes · FK constraints · WAL · FTS │   migrations (BE-18) · trash (BE-16)
                          └───────────────────────────────────────┘
```

Key principle: views and agents talk only to `TaskService`; every write funnels through repositories → `ChangeLog` → `PersistenceCoordinator` → engine, so persistence/sync/undo/automation/observability are cross-cutting layers rather than logic smeared across one 759-line `@MainActor` object.
