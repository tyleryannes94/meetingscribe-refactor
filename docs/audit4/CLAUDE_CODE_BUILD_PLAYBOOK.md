# Claude Code Build Playbook — Audit 4 (Projects/Tasks → Notion Replacement)

Copy-paste prompts to have Claude Code build out [`MASTER_PLAN.md`](MASTER_PLAN.md)
in **7 phases**. Each phase is a self-contained, shippable PR. Item IDs in the
prompts (e.g. `BE-5`, `UX-1`, `NP-1`) map to the per-discipline detail in
[`findings/`](findings/) — Claude Code should read the relevant findings entry
(it has the exact `file:line` evidence and rationale) before implementing.

## How to use

- Run **one prompt per Claude Code session**, in order. Don't start the next
  phase until the current PR is open and green.
- **Paste PROMPT 0 first** (once) — or append it to `CLAUDE.md`.
- Each block between `===== COPY =====` markers is self-contained.
- After each phase, smoke-test and open a **draft PR**; let the user review/merge.

## Build order

0. **PROMPT 0** — Ground rules (paste once)
1. **PROMPT 1 — Phase 0: Safety & Trust** (undo/trash, off-main writes, MCP race, migrations)
2. **PROMPT 2 — Phase 1: Modular Data Foundation** (repos, SQLite, change log, query engine, FTS)
3. **PROMPT 3 — Phase 2: The Daily Loop** (reminders, My Work, saved views, recurring)
4. **PROMPT 4 — Phase 3: Interaction Speed** (keyboard nav, NL quick-add, bulk parity, editable table)
5. **PROMPT 5 — Phase 4: Views & Visual System** (calendar, timeline, gallery, color system, avatars)
6. **PROMPT 6 — Phase 5: Notion-class Database & Docs** (custom properties, multi-views, relations, blocks)
7. **PROMPT 7 — Phase 6: AI Moat & Sync** (meeting-born tasks, AI props, two-way sync, agent API)

Git model: **one branch + one draft PR per phase**; split a large phase into
multiple PRs on the same phase branch by sub-section if it gets big.

---

## PROMPT 0 — Ground rules (paste once / append to CLAUDE.md)

```text
You are building out the MeetingScribe Projects/Tasks "replace Notion" roadmap.
Reference docs live in docs/audit4/:
- MASTER_PLAN.md  (the 7-phase plan; item IDs map to findings/)
- findings/01_product_pm.md, 02_product_notion_parity.md, 03_design_ux_interaction.md,
  04_design_views_ia.md, 05_backend_modular_eng.md  (full per-item detail with file:line evidence)
Before implementing any item, READ its findings entry (it has the exact files,
line numbers, and rationale) and the matching phase section of MASTER_PLAN.md.

GROUND RULES (every phase):
1. Branch + PR per phase. Start by: checkout the default branch, pull, then create
   the phase branch I name. Commit per item or tight group. At phase end, push and
   open a DRAFT PR; do not merge — I will. Split a big phase into multiple PRs on
   the same branch.
2. Commit style: imperative, category prefix (feat:/fix:/refactor:/perf:/docs:),
   under 72 chars; body wrapped at 80 explaining WHY when non-obvious. No trailers.
3. Build verification BEFORE every commit of non-trivial Swift: run
   `swift build -c release` (or `make app`). Errors block the commit; warnings are OK.
4. Smoke test before opening a PR that touches capture/UI: `make app`, launch,
   record a ~30s meeting, stop, confirm transcript + summary + action-item
   extraction + notification fire and nothing is lost. Note it in the PR.
5. PERFORMANCE IS A REQUIREMENT. Keep/improve cold-start, scroll smoothness,
   memory, crash-resistance. Do disk/CPU work OFF the main actor; back hot paths
   with caches/indexes; never rewrite the whole DB to change one field. Bound and
   corruption-proof any cache you add.
6. DO NOT regress the capture→transcribe→summarize→persist→extract pipeline. If an
   item touches MeetingPipelineController / the extractor / the stores, call it out
   and proceed carefully with tests.
7. Data safety: every destructive op must be reversible (soft-delete + undo) once
   Phase 0 lands. Never ship a hard delete after that.
8. Reuse existing infra over inventing parallel systems: SchemaEnvelope, VaultKit,
   SecondBrainDB (SQLite/FTS5), ToastCenter, WorkspaceRouter, WorkspaceIndex,
   NotificationManager, ErrorReporter, NotionDesign (NDS) tokens.
9. Scope discipline: implement ONLY the current phase's items. Note out-of-scope
   findings in the PR under "Found but out of scope".

WORKFLOW each phase: read plan + findings → list the phase's items and flag
pipeline-risky ones → implement with build gating → smoke test → push branch →
open DRAFT PR (checklist of items done with their IDs, before/after click counts
where relevant, perf notes, out-of-scope findings) → report back: branch, PR link,
items done, anything blocked.

Confirm you've read docs/audit4/MASTER_PLAN.md before starting.
```

---

## PROMPT 1 — Phase 0: Safety & Trust

```text
===== COPY =====
Implement Phase 0 (Safety & Trust) from docs/audit4/MASTER_PLAN.md. Branch:
claude/p0-tasks-safety. Read findings entries BE-1, BE-4, BE-16, BE-18, PM-11, UX-5
first.

Items:
- P0-1 (BE-1): Add a PersistenceCoordinator actor owning a per-file dirty set + a
  300-500ms debounce. ActionItemStore mutators mark-dirty and return immediately;
  encode (pretty:false on the hot path, pretty only for export) + atomic write run
  OFF the main actor. Flush synchronously on scenePhase==.background / terminate and
  on an explicit flush(). Replace the per-mutation save() calls (ActionItemStore.swift
  ~:536-543, :668-672, :744-757). Emit a "coalesced N->1 writes" counter.
- P0-3 (BE-16) + P0-4 (UX-5/PM-11): Soft-delete. Add deletedAt:Date? to ActionItem,
  Project, ProjectSection, TaskLabel, Initiative; default queries filter it out; add a
  Trash view that restores; a background sweep purges after 30 days. Replace the
  immediate hard removeAll deletes (ActionItemStore.swift ~:482-485, :606-615). On any
  delete (row menu, context menu, page menu, bulk bar) show a ToastCenter undo:
  "Deleted '<title>' — Undo" (plural for bulk), restoring with original sortIndex.
  Add store.reinsert(_:).
- P0-2 (BE-4): Fix the app<->MCP write race. Short-term, safe fix: advisory file lock
  + mtime-precondition on writes (reject if the file changed underneath) on BOTH the
  app side (ActionItemStore) and Sources/MeetingScribeMCP/main.swift (~:254-280,
  :1241-1280), and have the app reload on a DispatchSource file-change event. Document
  that the clean single-writer fix lands in Phase 6 (BE-15 IPC).
- P0-5 (BE-18): Stand up a TaskSchemaMigrations registry and pass a chained migrate
  closure into every SchemaEnvelope.decode (ActionItemStore.swift ~:42-46, :651-655).
  Take a one-time backup of each file before a migration runs. No version bump needed
  yet beyond wiring it; this de-risks Phase 1.

Tests: unit-test the debounce coalescing (N mutations -> 1 write), soft-delete filter,
undo restore, and the mtime-precondition rejection path. Smoke test the full pipeline.
Open a draft PR.
===== COPY =====
```

---

## PROMPT 2 — Phase 1: Modular Data Foundation

```text
===== COPY =====
Implement Phase 1 (Modular Data Foundation) from docs/audit4/MASTER_PLAN.md. Branch:
claude/p1-tasks-data-foundation. Read findings BE-2, BE-3, BE-5, BE-6, BE-7, BE-9,
BE-19 first. This phase is large — split into sub-PRs on the branch if needed
(suggested split: A repos+facade, B SQLite, C change-log+undo, D query+FTS+telemetry).

Items (keep the SwiftUI-facing API stable so views barely change):
- P1-1 (BE-2): Extract TaskRepository / ProjectRepository / LabelRepository /
  SectionRepository / InitiativeRepository over a Store protocol; keep a thin
  @MainActor TaskStore facade that publishes snapshots and delegates. All writes route
  through Phase 0's PersistenceCoordinator.
- P1-2 (BE-3): Move task storage into the existing SQLite stack (reuse
  People/SecondBrainDB.swift patterns / GRDB access). Tables: tasks, projects,
  sections, labels, task_labels, initiatives. Indexes: (project_id,status),
  (owner_person_id), (meeting_id), (status,due_date), (source,external_id). One-time
  JSON->SQLite import via the Phase 0 migration hook. Keep a JSON export so the
  human-readable-vault promise holds. Use WAL mode.
- P1-3 (BE-5): Append-only change_log table. Every mutation emits a
  ChangeEvent{id, entity, entityID, field?, op, lamport, deviceID, payload}.
  Persistence projects FROM the log. This is the keystone — make it the single write
  path through the repos.
- P1-7 (BE-6): Undo/redo via inverse-event application (or UndoManager bridge),
  coalescing rapid events (drag, bulk) into one undo window. Generalizes Phase 0 undo.
- P1-4 (BE-7): TaskQuery value type (filters/sort/group/limit) + TaskQueryEngine that
  compiles to SQL. Replace the bespoke helpers items(for:)/items(forProject:)/
  openItems()/todayAndYesterday()/openCount(...) and the duplicated UI filter logic
  with one path.
- P1-5 (BE-9): Add tasks (title, notes, owner, subtask titles, project name) to the
  FTS5 store with triggers; ranked search via TaskQueryEngine.
- P1-6 (BE-19): OSSignposter counters around encode/write/query (rows scanned, ms,
  coalesced N->1) surfaced in a diagnostics panel; consistent ErrorReporter .storage.

Tests: repo CRUD, JSON->SQLite import round-trip, change-log replay == current state,
undo/redo inverse correctness, TaskQuery -> SQL for a representative query set, FTS
ranking. Bench: 5k-task filter/sort latency before vs after. Open a draft PR.
===== COPY =====
```

---

## PROMPT 3 — Phase 2: The Daily Loop

```text
===== COPY =====
Implement Phase 2 (The Daily Loop) from docs/audit4/MASTER_PLAN.md. Branch:
claude/p2-tasks-daily-loop. Read findings PM-6, PM-8, PM-7, PM-13, PM-1, UX-21,
UX-11, UX-10, NP-3, VD-17, BE-13 first.

Items:
- P2-4 (PM-13): Set completedAt:Date? on status->completed (clear on reopen); optional
  compact status history. Do this first; later items depend on it.
- P2-1 (PM-6/UX-21): Schedule local UNUserNotificationCenter notifications on due /
  optional reminderAt for tasks owned by "me"; cancel on complete/reschedule. Reuse
  NotificationManager. Tap deep-links to the task via .meetingScribeOpenEntity.
- P2-2 (PM-8/UX-11/UX-10): Define "me" (a self-flagged Person or setting). Add a
  top-of-sidebar "My Tasks" view = ownerPersonID==me (|| owner==myName), grouped
  Overdue / Today / This week / Later; make it the default landing for returning users.
  Add toolbar quick-view chips (All / My open / Due this week / Overdue) that set
  filter state in one click; add an owner==me filter dimension.
- P2-3 (PM-7/NP-3/VD-17): Persisted SavedView/DatabaseView {name, viewMode, TaskQuery,
  group, sort, visibleColumns} per project; a view-tab strip atop the database pane;
  remember each project's last view. Built on Phase 1 TaskQuery.
- P2-5 (PM-1/BE-13): Recurring tasks. RecurrenceRule (RFC-5545 RRULE subset:
  freq/interval/byday/end) on a task template; a scheduler materializes the next
  instance on completion (and via a daily pass); seriesID relates instances; generation
  rides the Phase 1 change log. Surface a "Repeat" row in TaskPageView properties.

Tests: notification scheduling/cancellation, My-Tasks query correctness, saved-view
persistence round-trip, recurrence next-instance generation across freq types.
Smoke-test pipeline + notifications. Open a draft PR.
===== COPY =====
```

---

## PROMPT 4 — Phase 3: Interaction Speed

```text
===== COPY =====
Implement Phase 3 (Interaction Speed) from docs/audit4/MASTER_PLAN.md. Branch:
claude/p3-tasks-interaction. Read findings UX-1, UX-6, UX-7, UX-2, UX-3, UX-4, UX-8,
UX-9, UX-12, UX-14, UX-15, UX-18, UX-19, UX-20, UX-22, PM-9, PM-17, NP-18, VD-11 first.
Large phase — consider sub-PRs (A keyboard+quickadd, B bulk+table, C polish+a11y).

Items:
- P3-1 (UX-1): Keyboard nav in list/table/board. focusedTaskID + .focusable();
  arrows + j/k move (O(1) via cached id->index map), Enter open, Space/E toggle done,
  Cmd-Up/Down jump ends; focus ring. Substrate for the rest.
- P3-2 (UX-6/UX-7/PM-9): Inline "+ Add task..." row that commits on Enter and stays
  focused; parse trailing NL tokens (tomorrow/fri/6-12->due, @name->owner via People,
  #urgent/!p1->priority, #label, /project), strip from title, ghost-chip preview.
  Reuse the extractor's date parser (ActionItemExtractor.parseDueClause). Removes the
  "New task" placeholder pattern everywhere.
- P3-3 (UX-2/UX-3/PM-17): Lift multi-select to the shared toolbar so it renders for
  list-sections + table + board; X / Shift range-select; extend the bulk bar with
  set-due / move-project / assignee / section / labels; add store.bulkApply(ids:mutate:)
  = one change-log txn + one write. Undo via Phase 0/1.
- P3-4 (UX-4): Quick-set keystrokes on focused/open task: S status, P priority, A
  assignee, D/T due (T=today, M=tomorrow, W=next week), L label.
- P3-5 (UX-8/NP-18/VD-11): Make table Owner/Priority/Status/Due inline-editable (reuse
  list-row controls); a "Columns" menu to toggle/reorder/add Status/Labels/Start;
  persist column set.
- P3-6 (UX-9): Board cards show a due chip (red overdue) + assignee + tappable due;
  dim/strike completed. (Full visual reskin is Phase 4 VD-10.)
- P3-7 (UX-12): One shared DuePopover (Today/Tomorrow/This weekend/Next week/Someday/
  No date + calendar) used by row, page, table, board.
- P3-8 (UX-18/NP-20): Esc closes the task page; Opt-Up/Down move prev/next in the
  filtered list without returning; restore list scroll + focus on close.
- P3-9 (UX-19): Click cycles open->in-progress->done; check-draw/scale animation +
  animated strike & reorder.
- P3-10 (UX-14): List row-to-row dropDestination (reuse board midpoint sortIndex) +
  drop a row on a rail project/initiative -> setProject; insertion indicator.
- P3-11 (UX-15): accessibilityLabel/Value on every icon control; row
  accessibilityElement(.combine); migrate fixed-point fonts to Dynamic-Type styles /
  @ScaledMetric.
- P3-12 (UX-22): "?" shortcut cheat-sheet, .help() tooltips, first-visit tip, bulk/
  filter actions in the app menu bar.
- P3-13 (UX-20): Consolidate the two task editors — quick-edit inline (status/priority/
  due/labels) + "edit details" -> TaskPageView as the single source of truth.

Before/after: record click/keystroke counts for add-task, set-priority, bulk-move,
and review-10-tasks in the PR. Smoke-test pipeline. Open a draft PR.
===== COPY =====
```

---

## PROMPT 5 — Phase 4: Views & Visual System

```text
===== COPY =====
Implement Phase 4 (Views & Visual System) from docs/audit4/MASTER_PLAN.md. Branch:
claude/p4-tasks-views-visual. Read findings VD-5, VD-6, VD-10, VD-15, VD-1, VD-2, VD-3,
VD-4, VD-7, VD-9, VD-12, VD-13, VD-14, VD-16, VD-8, VD-19, VD-21, VD-18, VD-20, UX-16,
UX-17, NP-13, NP-17, NP-19 first. Build the component substrate FIRST.

Substrate (do first — everything draws on it):
- P4-0a (VD-5): One NDS.priority(_:)/NDS.status(_:) colorblind-tuned color set + a
  non-color redundancy (priority bar / triangle icon). Delete the 3 duplicated raw
  .gray/.blue/.orange/.red switches (ActionItemsTableView, ActionItemsBoardView,
  TaskPageView).
- P4-0b (VD-6/VD-10/VD-15): Shared MSAvatar(person:size:) (monogram-or-photo on a
  selectColor disc), MSCard (NDS surface), DueChip (overdue red / due-today amber,
  relative phrasing). Use across all views.

New views:
- P4-1 (VD-1/NP-19): Calendar view (month/week) over due/start; priority-colored chips;
  drag across days -> setDueDate; "Unscheduled" rail.
- P4-2 (VD-2/NP-19): Timeline/Gantt over start->due spans; swimlane by project/section/
  assignee; today-line; zoom; initiative summary bars.
- P4-3 (VD-3): Swimlane board (group columns by assignee/priority/project/label).
- P4-4 (VD-4/NP-13): Gallery view + project/initiative covers (coverHex/coverSymbol);
  LazyVGrid of rich cards.

Polish & IA:
- P4-5 (VD-7): Project/initiative % complete bar/ring (store.completion(forProject:/
  forInitiative:)) on headers, sidebar nodes, gallery cards.
- P4-6 (VD-9): Sticky, collapsible group/section headers (pinnedViews) + count + mini
  progress.
- P4-7 (VD-12/NP-17): Breadcrumbs reflecting full Initiative > pages > Project > Task,
  each clickable, on all panes.
- P4-8 (VD-13/UX-17/UX-16): Native per-context empty states (ContentUnavailableView /
  MSEmptyState) + 4-6 shimmer skeleton rows on first load.
- P4-9 (VD-14): Dashboard data-viz (Swift Charts): status donut, due-soon bar,
  top-projects bar; each clickable -> sets filter.
- P4-10 (VD-16): Shared searchable SymbolPicker for projects AND initiatives; icons as
  selectColor-tinted tiles.
- P4-11 (VD-8): Density toggle (Comfortable/Compact) via @AppStorage.
- P4-12 (VD-19): Tokenize board/page surfaces off raw AppKit colors -> NDS tokens +
  new NDS.columnBg.
- P4-13 (VD-21): Reduce-motion-gated transitions for view switch / page open / tree
  expand.
- P4-14 (VD-18): Responsive layout: table -> 3 essential columns + rail auto-collapse
  below a breakpoint; board columns flex; gallery reflows.
- P4-15 (VD-20): Page heading outline + wide-board minimap (opt-in past a threshold).

Verify against Reduce Motion + Increase Contrast + a colorblind simulation. Smoke-test
pipeline. Open a draft PR.
===== COPY =====
```

---

## PROMPT 6 — Phase 5: Notion-class Database & Docs

```text
===== COPY =====
Implement Phase 5 (Notion-class Database & Docs) from docs/audit4/MASTER_PLAN.md.
Branch: claude/p5-tasks-database-docs. Read findings NP-1, NP-2, NP-5, NP-8, NP-21,
NP-6, NP-4, NP-11, NP-12, NP-9, NP-15, NP-10, NP-14, NP-16, NP-13, PM-5, PM-14, PM-15,
PM-16, BE-10, BE-11 first. Depends on the Phase 1 data layer. Large — split into
sub-PRs (A properties+views+relations, B block docs+embeds, C links+comments+wiki).

Database layer:
- P5-1 (NP-1/PM-5/BE-10): Custom typed properties (the keystone). PropertyDefinition
  {id,name,kind(text/number/select/multiSelect/date/person/relation/checkbox/url/
  formula),options} per-Project (the DB schema); typed PropertyValue bag on the task
  (JSON column / side-table). Migrate existing status/priority into built-in property
  defs so old data + code keep working. Render generically in the property block + as
  table columns; filter/sort via Phase 1 TaskQuery.
- P5-2 (NP-2): Multiple saved DB views (table/board/list/calendar/gallery/timeline),
  each own filter/sort/group, in a tab strip (extends Phase 2 SavedView + Phase 4 views).
- P5-3 (NP-5/BE-11): relation property kind + RollupDefinition{relation,targetProperty,
  aggregate}; materialize rollups incrementally off the change log, cached.
- P5-4 (NP-8): Linked databases — a block referencing a source project + saved view,
  surfaced/filtered on other pages.
- P5-5 (NP-21): Built-in created/edited-time properties (sortable/filterable) + a small
  safe formula property set (days-until-due, is-overdue).
- P5-6 (NP-6/PM-16): Templates (page + DB-row + recurring), incl. an AI-filled
  "Meeting follow-up" template; capture icon, property defaults, subtasks, body.

Docs/wiki layer:
- P5-7 (NP-4): True block-based doc model ([Block]{type,text,children,props} serialized
  to portable markdown): per-block drag, callout/toggle/columns, page-embed blocks.
- P5-8 (NP-11/PM-15): Embeds + file/image/attachment blocks (vault-stored by relative
  path; bookmark/link-preview; embed meeting recording/transcript snippet).
- P5-9 (NP-12): Synced blocks (stable block IDs + syncedRef).
- P5-10 (NP-9): Bidirectional links + backlinks panel on Project/Task/Initiative;
  reverse-link index over meetingscribe:// refs; auto-reciprocal on @-mention.
- P5-11 (NP-15/PM-14): Comments (page- and block-level) with resolve.
- P5-12 (NP-10): Composable wiki Home (editable block doc from linked views +
  favorites) + optional page metadata (owner/verified/last-reviewed).
- P5-13 (NP-14): Favorites/pinned sidebar section + persisted manual order.
- P5-14 (NP-16): Full-text content search with snippets + jump-to-block.
- P5-15 (NP-13): Page covers + emoji/custom icons feeding the gallery card face.

Tests: property CRUD + generic filter/sort, rollup recompute correctness, block-model
markdown round-trip, backlink index correctness, template instantiation. Smoke-test
pipeline. Open a draft PR.
===== COPY =====
```

---

## PROMPT 7 — Phase 6: AI Moat & Sync

```text
===== COPY =====
Implement Phase 6 (AI Moat & Sync) from docs/audit4/MASTER_PLAN.md. Branch:
claude/p6-tasks-moat-sync. Read findings PM-19, NP-7, BE-8, BE-14, PM-18, UX-13, BE-12,
BE-15, BE-4, PM-10, PM-12, PM-4, PM-20, BE-20, PM-2, PM-3, BE-17, BE-21 first. Large —
split into sub-PRs (A AI moat, B sync+providers, C automation+agent-API, D planning/
reporting/import-export/hardening).

The moat (do first — this is the differentiator):
- P6-1 (PM-19): Lean into meeting-born tasks. (a) Optionally keep OTHERS' action items
  as a "Delegated / Waiting-on" list instead of dropping via isMine
  (ActionItemExtractor.swift). (b) Auto-suggest project + priority from meeting context
  (today all extracted tasks are .medium, no project). (c) Store the source sentence +
  deep link so each task shows "why" (seeds the first comment from Phase 5). (d) A
  triage inbox to accept/snooze/reassign freshly-extracted tasks before the backlog.
- P6-2 (NP-7): AI auto-extracts into typed properties (Phase 5): map transcript
  entities (Customer/Effort/Decision/Risk) to a project's defined properties with a
  confidence chip + one-click confirm; auto-create discovered select options.

Sync & integrations:
- P6-3 (BE-8): Conflict-free sync (per-field LWW + Lamport clock) on the change log;
  stable deviceID + monotonic counter; one resolver for device<->device and external
  merges.
- P6-4 (BE-14): provider abstraction (protocol TaskProvider{pull(since:),push,
  mapStatus,projects} + ProviderRegistry); move Linear/Notion behind it; per-provider
  sync cursor/field-map. mergeExternal becomes the one ingestion point.
- P6-5 (PM-18/UX-13): Two-way sync — debounced write-back on local edits to linked
  tasks (Notion page update; add Linear issueUpdate); "Push selected to..." bulk;
  per-task sync state (queued/synced/error).
- P6-7 (BE-15/BE-4): One TaskService API (CRUD + TaskQuery + bulk) backing both Chat
  tools and the MCP server via IPC — finishing the Phase 0 MCP-race fix with a true
  single-writer; add project/section/label/relation writes + run-query.
- P6-6 (BE-12): Automation/rules engine (Rule{trigger,conditions,actions} over the
  change stream; actions reuse logged/undoable repo mutators; cycle budget).

Planning, reporting, capture, data:
- P6-8 (PM-10): Global quick-capture (system hotkey + menu-bar "New task...") opening a
  tiny NL-parsed capture window -> createTask.
- P6-11 (PM-2/PM-3): Task dependencies (blockedByIDs + derived blocks + "Blocked" chip)
  + milestones/goals (targetDate/startDate + Milestone on Project/Initiative, rendered
  on the Phase 4 timeline).
- P6-12 (PM-4): Estimates + time tracking (estimate, timeSpentMinutes + start/stop
  timer; pull Linear estimate on import).
- P6-9 (PM-12): Reporting/Insights view (completed-per-week, open-vs-created trend,
  overdue-over-time, by project/priority/owner; velocity from estimates).
- P6-10 (PM-20/BE-20): Import/export (CSV + Markdown + JSON; Todoist/Asana/Notion
  import with column mapping); scheduled JSON export to keep the local-first vault.
- P6-13 (BE-17/BE-21): Integrity/validation pass (orphan scan, FK ON DELETE SET NULL,
  match external projects by stable ID not name); mutators return Result/throw
  notFound; per-record rev for optimistic concurrency.

Tests: delegated-extraction filter, AI property mapping confidence path, LWW merge
determinism (two-device replay), provider conformance (Linear+Notion pull/push round
trip), automation trigger->action with cycle guard, dependency blocking, CSV import
mapping. Smoke-test the full pipeline. Open a draft PR.
===== COPY =====
```

---

## Notes

- **Phasing is a recommendation, not a mandate.** P0 and P1 should go first (safety +
  foundation). P2/P3 deliver the most visible day-to-day value and can precede P4–P6 if
  you want quick wins. P5 depends on P1's data layer; P6's AI/sync depend on P1's change
  log.
- **Each prompt is sized for one PR but several are large** — the prompt tells Claude
  Code where to split. Don't be afraid to run a phase as 2–4 sequential sessions on the
  same branch.
- **Always read the findings entry for an item ID before building it** — it carries the
  exact `file:line` evidence and the "why", which these prompts compress.
</content>
