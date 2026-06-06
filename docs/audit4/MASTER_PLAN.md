# Master Plan — Projects/Tasks → a Notion/Linear/Asana/Things Replacement

Compiled from the five Audit-4 findings docs (`findings/01…05`). The 106
individual improvements are deduped across disciplines and sequenced into **7
phases**. Each phase is independently shippable and leaves the app better than it
found it. Item IDs map back to the findings docs (`PM-*` product, `NP-*`
Notion-parity, `UX-*` interaction, `VD-*` visual/IA, `BE-*` backend).

## Strategy in one picture

```
Trust  →  Foundation  →  Daily loop  →  Speed  →  Views/Visual  →  Database/Docs  →  Moat
P0        P1            P2             P3        P4               P5                P6
(safety) (data layer)  (the habit)    (Linear)  (Notion views)   (Notion db+wiki)  (AI + sync)
```

Two convictions drive the sequence:

1. **Nobody migrates their only task DB into an app that can lose data on a
   misclick.** So safety (undo/trash, fix the MCP write race, off-main durable
   writes) comes *first* — it's cheap and it gates adoption.
2. **The data layer is the ceiling.** A 759-line `@MainActor` god-store that
   re-encodes the whole JSON array on every keystroke cannot host custom
   properties, multiple views, calendars, relations, or sync. Modernizing it
   (P1) is what makes P2–P6 buildable instead of bolted-on.

---

## Phase 0 — Safety & Trust (small, do first)

> Make the feature safe to commit real data to. Pure risk-reduction; little new surface.

| Item | What | Source IDs |
|------|------|-----------|
| P0-1 | **Debounced, coalesced, off-main write path.** A `PersistenceCoordinator` actor owns a per-file dirty set + 300–500ms debounce; mutators mark-dirty and return; encode (`pretty:false` hot path) + atomic write happen off the main actor; flush on background/terminate. Kills the per-keystroke full-DB rewrite on the UI thread. | `BE-1` |
| P0-2 | **Fix the app↔MCP cross-process write race.** Today the app rewrites the whole `action_items.json` from memory while the MCP server independently rewrites it — last writer silently wins (live data-loss bug). Short-term: advisory lock + mtime-precondition + reload on file-change. Long-term: route MCP writes through the app (resolved fully in P1/P6). | `BE-4` |
| P0-3 | **Trash / soft-delete + restore.** Add `deletedAt: Date?` to task/project/section/label/initiative; default queries filter it; a Trash view restores; background purge after 30 days. Replaces today's immediate hard `removeAll`. | `PM-11`, `BE-16` |
| P0-4 | **Undo toast on delete (adopt existing `ToastCenter`).** Snapshot deleted item(s); show "Deleted '…' — Undo". Infra already shipped and used by People/Tags; Tasks just never adopted it. Plural form for bulk delete. | `UX-5`, `PM-11` |
| P0-5 | **Wire real schema migrations.** The `SchemaEnvelope.migrate` hook exists but every version is pinned to `1`; back-compat leans entirely on "new fields are optional". Stand up a `TaskSchemaMigrations` registry + pre-migration backup so P1/P5 structural changes are safe. | `BE-18` |

**Exit:** deleting is reversible, writes are durable + off-main, agents can't
silently clobber the file, and the schema can evolve.

---

## Phase 1 — Modular Data Foundation

> Replace the god-store/whole-file-JSON ceiling with a repository + engine + change-log architecture behind a stable façade, so views never change as the engine swaps underneath.

| Item | What | Source IDs |
|------|------|-----------|
| P1-1 | **Split the god-store into repositories + a thin `@MainActor` façade.** `TaskRepository`/`ProjectRepository`/`LabelRepository`/`SectionRepository`/`InitiativeRepository` over a `Store` protocol; a `TaskStore` façade publishes snapshots for SwiftUI. Testing seams; precondition for swapping storage. | `BE-2` |
| P1-2 | **Move storage to SQLite/GRDB behind the repos.** Tables + indexes on `(project_id,status)`, `(owner_person_id)`, `(meeting_id)`, `(status,due_date)`, `(source,external_id)`. O(log n) lookups, partial reads, transactions, concurrent readers. Reuse the app's existing `SecondBrainDB` SQLite/FTS5 stack. Keep a JSON export so the human-readable-vault promise holds (see P6 import/export). | `BE-3` |
| P1-3 | **Append-only change log / event journal.** Every mutation emits a `ChangeEvent{entity, entityID, field?, op, lamport, deviceID, payload}`. The keystone seam that unlocks undo/redo, conflict-free sync, automation, recurrence, and observability. | `BE-5` |
| P1-4 | **Typed query layer (`TaskQuery` + `TaskQueryEngine`).** One composable predicate/sort/group path compiled to SQL (post-P1-2) or in-memory, replacing the ~8 bespoke `filter`+`sorted` helpers and the duplicated UI filter logic. Saved views (P2) and the agent API (P6) are persisted `TaskQuery` structs. | `BE-7` |
| P1-5 | **Full-text search index for tasks.** Add tasks (title, notes, owner, subtask titles, project name) to the existing FTS5 store with triggers; ranked search via P1-4, exposed to Chat/MCP. | `BE-9`, `NP-16` |
| P1-6 | **Observability seam.** OSSignposter counters around encode/write/query (rows scanned, ms, "save coalesced N→1") in a diagnostics panel; consistent `ErrorReporter` `.storage` category. Proves the P0-1/P1-2 wins and surfaces regressions. | `BE-19` |
| P1-7 | **Undo/redo on the change log.** Inverse-event application (or `UndoManager` bridge); coalesce rapid events (drag, bulk) into one undo window. Generalizes P0-4. | `BE-6` |

**Exit:** a tested, indexed, transactional data layer with a replayable history
and one query path — the substrate every later phase builds on.

---

## Phase 2 — The Daily Loop (the habit that displaces the incumbent)

> The screens and behaviors that make someone open this 20×/day instead of Notion/Things.

| Item | What | Source IDs |
|------|------|-----------|
| P2-1 | **Reminders & due-date notifications.** Schedule local notifications on due/`reminderAt` for tasks owned by "me"; cancel on complete/reschedule; tap deep-links to the task via the existing `.meetingScribeOpenEntity` route. Notification infra already exists (meetings only today). | `PM-6`, `UX-21` |
| P2-2 | **Unified "My Work" view + quick-view chips.** Define "me" (a self-flagged Person/setting). Top-of-sidebar **My Tasks** = `ownerPersonID == me` grouped Overdue / Today / This week / Later; make it the default landing. Add toolbar segmented chips (All · My open · Due this week · Overdue) that set filter state in one click; add an `owner == me` filter dimension. | `PM-8`, `UX-11`, `UX-10` |
| P2-3 | **Saved / smart views (persisted, per-project).** A `SavedView`/`DatabaseView`{name, viewMode, `TaskQuery`, group, sort, visible columns} persisted per project; a view-tab strip atop the database pane; remember each project's last view. Built on P1-4. | `PM-7`, `NP-3`, `VD-17` |
| P2-4 | **Distinct `completedAt` + status history.** Set `completedAt` on →completed (clear on reopen); optional compact status history. Foundational for "done today/this week" and reporting. | `PM-13` |
| P2-5 | **Recurring tasks.** `RecurrenceRule` (RFC-5545 RRULE subset) on a task template + a scheduler that materializes the next instance on completion / via a daily pass; `seriesID` relates instances; generation rides P1-3 so it syncs/undoes cleanly. | `PM-1`, `BE-13` |

**Exit:** the tab answers "what should I do now?", proactively reminds, remembers
how you work, and handles the chores you repeat every week.

---

## Phase 3 — Interaction Speed (feel like Linear)

> Drive every routine action toward ≤1 keystroke; make all three views consistent and triage-ready.

| Item | What | Source IDs |
|------|------|-----------|
| P3-1 | **Keyboard navigation in list/table/board.** `focusedTaskID` + `.focusable()`; `↑/↓`+`j/k` move (O(1) via cached `id→index` map), `Enter` open, `Space`/`E` toggle done, `⌘↑/↓` jump ends; focus ring. The defining gap vs Linear; substrate for the rest. | `UX-1` |
| P3-2 | **Inline quick-add with natural-language parse.** A pinned "+ Add task…" row commits on `Enter` and stays focused; parse trailing tokens — `tomorrow`/`fri`/`6·12`→due, `@name`→owner (People match), `#urgent`/`!p1`→priority, `#label`, `/project` — strip from title, ghost-chip preview. Reuse the extractor's date parser. Kills the "New task" placeholder litter. | `UX-6`, `UX-7`, `PM-9` |
| P3-3 | **Bulk-edit parity across all views + full field set.** Lift selection to the shared toolbar (list sections, table, board), `X`/`⇧` range select; extend the bar with set-due / move-project / assignee / section / labels (not just status/priority/delete); `store.bulkApply(ids:mutate:)` = one mutation + one write. Pair with P0-4 undo. | `UX-2`, `UX-3`, `PM-17` |
| P3-4 | **Quick-set keystrokes on focused/open task.** `S` status, `P` priority, `A` assignee, `D`/`T` due (`T`=today/`M`=tomorrow/`W`=next week), `L` label; surfaced in a `?` cheat-sheet. | `UX-4` |
| P3-5 | **Editable, configurable table cells.** Make Owner (person menu), Priority, Status, Due inline-editable (reuse list-row controls); a "Columns" menu to toggle/reorder/add Status/Labels/Start; persist column set. | `UX-8`, `NP-18`, `VD-11` |
| P3-6 | **Richer board cards.** Add due chip (red overdue) + assignee avatar to the card footer; make the due chip tappable; dim/strike completed. | `UX-9` (visual reskin in P4) |
| P3-7 | **One shared `DuePopover` with relative shortcuts.** Today / Tomorrow / This weekend / Next week / Someday / No date above the calendar; used by row, page, table, board. Collapses two near-duplicate pickers. | `UX-12` |
| P3-8 | **Task page peek + prev/next + Esc.** `Esc` closes; `⌥↑/⌥↓` move to prev/next task in the filtered list without returning; restore list scroll + focus on close. (Side-peek shares cross-app CP-1 infra.) | `UX-18`, `NP-20` |
| P3-9 | **Completion micro-feedback + 3-state checkbox.** Click cycles open→in-progress→done; check-draw/scale animation + animated strike & reorder. | `UX-19` |
| P3-10 | **List drag-reorder + drag-to-rail re-home.** Row-to-row `dropDestination` (reuse board midpoint `sortIndex`); drop a row on a rail project/initiative → `setProject`; insertion indicator. | `UX-14` |
| P3-11 | **Accessibility pass.** `accessibilityLabel`/`Value` on every icon control; row `accessibilityElement(.combine)`; migrate fixed-point fonts to Dynamic-Type text styles / `@ScaledMetric`. | `UX-15` |
| P3-12 | **Discoverability.** `?` shortcut cheat-sheet, `.help()` tooltips on icon controls, first-visit tip, bulk/filter actions in the app menu bar. Lands after P3-1/P3-4 so it documents real shortcuts. | `UX-22` |
| P3-13 | **Consolidate the two task editors.** Row inline-expand editor and `TaskPageView` overlap inconsistently (row assignee is free-text with no person link). Pick one: quick-edit inline (status/priority/due/labels) + "edit details" → page. | `UX-20` |

**Exit:** a power user can run their week from the keyboard; all three views edit
consistently; capture is one typed line.

---

## Phase 4 — Views & Visual System

> Let users *see* work the way it's shaped (by date, timeline, cards), on one systematized, accessible visual language.

**Component substrate first (everything below draws on these):**

| Item | What | Source IDs |
|------|------|-----------|
| P4-0a | **Accessibility-safe, tokenized color system.** One `NDS.priority(_:)`/`NDS.status(_:)` (colorblind-tuned) + a non-color redundancy (priority bar/▲ icon); delete the 3 duplicated raw `.gray/.blue/.orange/.red` switches. | `VD-5` |
| P4-0b | **Shared `MSAvatar` / `MSCard` / `DueChip`.** Monogram-or-photo avatar on a `selectColor` disc; NDS card surface; overdue/due-today urgency chip with relative phrasing. | `VD-6`, `VD-10`, `VD-15` |

**New views:**

| Item | What | Source IDs |
|------|------|-----------|
| P4-1 | **Calendar view (month/week)** over due/start; chips colored by priority; drag across days to reschedule; "Unscheduled" rail. The single biggest missing-view gap. | `VD-1`, `NP-19`, `PM-21` |
| P4-2 | **Timeline / Gantt** over start→due spans; swimlane by project/section/assignee; today-line; zoom; initiative bars. Activates the otherwise-invisible `startDate`. | `VD-2`, `NP-19`, `PM-21` |
| P4-3 | **Swimlane board** (group columns by a 2nd dimension: assignee/priority/project/label). | `VD-3` |
| P4-4 | **Gallery / card view + project covers.** `coverHex`/`coverSymbol` on Project/Initiative; `LazyVGrid` of rich cards. | `VD-4`, `NP-13` |

**Polish & IA:**

| Item | What | Source IDs |
|------|------|-----------|
| P4-5 | **Project/initiative progress indicators** (% complete bar/ring) on page headers, sidebar nodes, gallery cards; `store.completion(forProject:/forInitiative:)`. | `VD-7` |
| P4-6 | **Sticky, collapsible group/section headers** (`pinnedViews`) with count + mini progress. | `VD-9` |
| P4-7 | **Breadcrumbs** reflecting full Initiative › pages › Project › Task, each clickable; on project, initiative, and task panes. | `VD-12`, `NP-17` |
| P4-8 | **Native, illustrated empty states** per context (`ContentUnavailableView`/`MSEmptyState`): empty project → "Add first task", empty board column, empty calendar, over-filtered → "Clear filters". | `VD-13`, `UX-17`, `UX-16` (skeletons) |
| P4-9 | **Dashboard data-viz** (Swift Charts): status donut, due-soon bar, top-projects bar — each clickable → sets filter. | `VD-14`, `PM-12` (full reporting in P6) |
| P4-10 | **Icon system:** shared searchable `SymbolPicker` for projects *and* initiatives; icons as `selectColor`-tinted tiles. | `VD-16` |
| P4-11 | **Density toggle** (Comfortable/Compact) via `@AppStorage`, applied to list/table/board paddings. | `VD-8` |
| P4-12 | **Tokenize board/page surfaces** off raw AppKit colors → `NDS.fieldBg/rowHover/hairline` + new `NDS.columnBg`. | `VD-19` |
| P4-13 | **Motion/transition language** (reduce-motion-gated): cross-fade view switches, slide task-page open, height-animate tree expand. | `VD-21` |
| P4-14 | **Responsive layout** at narrow/wide windows: table drops to 3 essential columns + rail auto-collapses below a breakpoint; board columns flex; gallery reflows. | `VD-18` |
| P4-15 | **Page outline / board minimap** for long bodies / wide boards (opt-in past a threshold). | `VD-20` |

**Exit:** calendar + timeline + gallery exist; the surface is colorblind-safe,
avatar-rich, progress-aware, and visually systematized — demo-worthy next to
Linear/Notion.

---

## Phase 5 — Notion-class Database & Docs

> Cross the line from "styled task list" to "real database + document workspace." Depends on the P1 data layer.

**Database layer:**

| Item | What | Source IDs |
|------|------|-----------|
| P5-1 | **Custom, typed database properties (the keystone).** `PropertyDefinition{id,name,kind(text/number/select/multiSelect/date/person/relation/checkbox/url/formula), options}` owned per-Project; typed `PropertyValue` bag on the task (JSON column / side-table). Existing fields (status/priority) become built-in property defs. Rendered generically in the property block + as table columns; filterable/sortable via P1-4. | `NP-1`, `PM-5`, `BE-10` |
| P5-2 | **Multiple saved database VIEWS over one dataset** (table/board/list/calendar/gallery/timeline), each with own filter/sort/group, in a tab strip. Builds on P2-3 + P4 views. | `NP-2` |
| P5-3 | **Relations + rollups engine.** `relation` property kind + `RollupDefinition{relation, targetProperty, aggregate}`; materialized incrementally off P1-3 events and cached (subsumes per-render count recompute). | `NP-5`, `BE-11` |
| P5-4 | **Linked databases** — a block referencing a source project + saved view, surfaced/filtered on other pages (e.g. "My tasks" on Home). | `NP-8` |
| P5-5 | **Built-in + formula properties** (created/edited time as sortable/filterable columns; a small safe formula set: "days until due", "is overdue"). | `NP-21` |
| P5-6 | **Templates** (page + database-row + recurring), incl. an AI-filled "Meeting follow-up" template. Captures icon, property defaults, subtasks, body. | `NP-6`, `PM-16` |

**Docs / wiki layer:**

| Item | What | Source IDs |
|------|------|-----------|
| P5-7 | **True block-based doc model** (`[Block]{type, text, children, props}` serialized to portable markdown): per-block drag, callout/toggle/columns, page-embed blocks. Substrate for embeds/synced/comments/jump-to-block. | `NP-4` |
| P5-8 | **Embeds & file/image blocks** (stored in the vault by relative path; bookmark/link-preview; embed meeting recording/transcript snippet). | `NP-11`, `PM-15` (attachments) |
| P5-9 | **Synced blocks** (stable block IDs + `syncedRef`; e.g. shared "Decisions"/"Risks" between a meeting page and its project). | `NP-12` |
| P5-10 | **Bidirectional links + backlinks panel** on Project/Task/Initiative pages; reverse-link index over all `meetingscribe://` refs; auto-reciprocal on @-mention. | `NP-9` |
| P5-11 | **Comments** (page- and block-level) with resolve; durable annotations on AI-generated content. | `NP-15`, `PM-14` |
| P5-12 | **Composable wiki Home** (editable block doc built from linked views + favorites) + optional page metadata (owner/verified/last-reviewed). | `NP-10` |
| P5-13 | **Favorites / pinned sidebar section** + persisted manual order. | `NP-14` |
| P5-14 | **Full-text content search with snippets + jump-to-block** (builds on P1-5 + P5-7 block addressing). | `NP-16` |
| P5-15 | **Page covers + richer emoji/custom icons** feeding the gallery card face. | `NP-13` |

**Exit:** each project is a user-schema'd database with many saved views,
relations, and templates; pages are real block documents with embeds, backlinks,
and comments — the Notion mental model, locally.

---

## Phase 6 — The AI Moat & Sync (why you *choose* it)

> Everything above reaches parity. This phase is the part Notion/Linear/Asana structurally can't copy, plus the bridge that makes switching safe.

| Item | What | Source IDs |
|------|------|-----------|
| P6-1 | **Lean into meeting-born tasks (the moat).** (a) Optionally keep *others'* action items as a **Delegated / Waiting-on** list (huge for managers) instead of dropping them via `isMine`. (b) Auto-suggest project + priority from meeting context (today everything is `.medium`, no project). (c) Store the **source sentence + deep link** so each task shows "why" (seeds the first comment, P5-11). (d) A **triage inbox** to accept/snooze/reassign freshly-extracted tasks before they hit the backlog. | `PM-19` |
| P6-2 | **AI auto-extracts into typed properties.** With P5-1, map transcript entities (Customer, Effort, Decision, Risk) to a project's defined properties with a confidence chip + one-click confirm; auto-create discovered select options. "Your calls populate your schema." | `NP-7` |
| P6-3 | **Conflict-free sync (per-field LWW + Lamport clock)** on the change log; stable `deviceID` + monotonic counter; one resolver for both device↔device and external-provider merges. Foundation for the cross-device plan. | `BE-8` |
| P6-4 | **Provider abstraction** (`protocol TaskProvider{pull(since:),push,mapStatus,projects}` + `ProviderRegistry`); move Linear/Notion behind it; per-provider sync cursor/field-map. New integrations (Todoist/Jira/Asana) become a conformance, not a fork. | `BE-14` |
| P6-5 | **Two-way external sync.** On local edits to a linked task, debounced write-back (Notion page update; add Linear `issueUpdate`); "Push selected to…" bulk; per-task sync state (queued/synced/error) instead of one shared banner. | `PM-18`, `UX-13` |
| P6-6 | **Automation / rules engine** (`Rule{trigger, conditions, actions}` over the P1-3 change stream; actions reuse logged/undoable repo mutators; cycle budget). Consolidates today's scattered ad-hoc side-effects. | `BE-12` |
| P6-7 | **Stable agent / MCP `TaskService` API.** One programmatic entry point (CRUD + `TaskQuery` + bulk) backing both Chat tools and the MCP server (via IPC, finishing the P0-2 fix); adds project/section/label/relation writes + run-query. | `BE-15`, `BE-4` |
| P6-8 | **Global quick-capture** (system hotkey + menu-bar "New task…") opening a tiny NL-parsed capture window → `createTask`. Makes the app the default capture target. | `PM-10` |
| P6-9 | **Reporting / Insights view** (completed-per-week, open-vs-created trend, overdue-over-time, by project/priority/owner; velocity once estimates exist). | `PM-12`, `PM-4` (estimates/time tracking) |
| P6-10 | **Import / export** (CSV + Markdown + JSON; Todoist/Asana/Notion import with column mapping). Keeps the local-first vault promise across the SQLite move; removes adoption + lock-in friction. | `PM-20`, `BE-20` |
| P6-11 | **Task dependencies + milestones/goals.** `blockedByIDs` (+ derived `blocks`, "Blocked" chip); `targetDate`/`startDate` + lightweight `Milestone` on Project/Initiative rendered on the timeline. | `PM-2`, `PM-3` |
| P6-12 | **Estimates & time tracking** (`estimate`, `timeSpentMinutes` + start/stop timer; pull Linear `estimate` on import) — powers velocity (P6-9). | `PM-4` |
| P6-13 | **Hardening:** integrity/validation pass (orphan scan, FK `ON DELETE SET NULL`, match external projects by stable ID not name); mutators return `Result`/throw `notFound`; per-record `rev` for optimistic concurrency. | `BE-17`, `BE-21` |

**Exit:** meeting-born tasks with context and a triage inbox; AI that fills your
database schema; safe two-way sync via a clean provider layer; a complete,
race-free agent API; and the planning/reporting depth of a mature PM tool.

---

## Cross-reference — every finding lands in a phase

| Phase | Findings covered |
|-------|------------------|
| **P0 Safety** | BE-1, BE-4 (start), BE-16, BE-18, PM-11, UX-5 |
| **P1 Foundation** | BE-2, BE-3, BE-5, BE-6, BE-7, BE-9, BE-19, NP-16 (index) |
| **P2 Daily loop** | PM-1, PM-6, PM-7, PM-8, PM-13, UX-10, UX-11, UX-21, NP-3, VD-17, BE-13 |
| **P3 Speed** | UX-1, UX-2, UX-3, UX-4, UX-6, UX-7, UX-8, UX-9, UX-12, UX-14, UX-15, UX-18, UX-19, UX-20, UX-22, PM-9, PM-17, NP-18, NP-20, VD-11 |
| **P4 Views/Visual** | VD-1, VD-2, VD-3, VD-4, VD-5, VD-6, VD-7, VD-8, VD-9, VD-10, VD-12, VD-13, VD-14, VD-15, VD-16, VD-18, VD-19, VD-20, VD-21, UX-16, UX-17, NP-13, NP-17, NP-19, PM-21, PM-12 (viz) |
| **P5 Database/Docs** | NP-1, NP-2, NP-4, NP-5, NP-6, NP-8, NP-9, NP-10, NP-11, NP-12, NP-13, NP-14, NP-15, NP-16, NP-21, PM-5, PM-14, PM-15, PM-16, BE-10, BE-11 |
| **P6 Moat/Sync** | PM-2, PM-3, PM-4, PM-10, PM-12, PM-18, PM-19, PM-20, NP-7, UX-13, BE-8, BE-12, BE-14, BE-15, BE-17, BE-20, BE-21, BE-4 (finish) |

## The single highest-value move per phase

- **P0:** undo + trash (PM-11/UX-5/BE-16) — gates adoption for near-zero effort.
- **P1:** the change log (BE-5) — the one seam that makes undo/sync/automation/recurrence cheap instead of bespoke.
- **P2:** "My Work" + reminders (PM-8/PM-6) — the daily habit that displaces the incumbent.
- **P3:** keyboard nav (UX-1) — the defining Linear gap and substrate for everything else.
- **P4:** calendar view (VD-1) on a colorblind-safe color system (VD-5) — the biggest missing-view gap.
- **P5:** custom typed properties (NP-1/BE-10) — the architectural line between a task list and a database.
- **P6:** meeting-born tasks with context + triage (PM-19) — the only thing on this entire list the competitors *structurally cannot* match.
</content>
