# Data Model & Store Architecture Findings — MeetingScribe Tasks Audit

**Agent ID:** E1 | **Role:** Staff Engineer — Data Model & Store Architecture
**Primary files:** `ActionItem.swift`, `ActionItemStore.swift` (1,335 lines), `Project.swift`, `Initiative.swift`, `TaskQuery.swift`, `TaskPersistenceCoordinator.swift`, `TaskSchemaMigrations.swift`, `TaskChangeLog.swift`

---

## Top existing friction points (file:line citations)

### 1. No `context` field — work and personal tasks are permanently mixed

`ActionItem.swift` has no concept of a work/personal context (or "space", "area", "workspace"). The only organizational primitive above a task is `projectID` (optional string). There is no top-level signal that cleanly separates a "Personal" domain from a "Work" domain at the model level. Tyler's explicit goal ("tasks shouldn't all be meshed together") is architecturally impossible without adding this field.

`Initiative.swift` (lines 1–24) has no `context` or `area` field either — so even at the highest tier, "Work Initiatives" and "Personal Initiatives" live in a single undifferentiated list.

### 2. Linear scan on every single-task lookup — latent O(n) per mutation

Every mutation in `ActionItemStore` calls the private `update(_:mutate:)` helper (line 995), which runs:
```swift
guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
```
That is O(n) over `items` on every status change, priority change, due date set, label toggle, etc. For completions, the store does **two** sequential O(n) scans (line 853–868): one to read `wasCompleted`, a second inside `update`. The `reachableViaBlockers` DFS (line 984–993) calls `items.first(where:)` inside a loop — O(n) per hop, O(n·d) total where d is dependency depth. With 500+ tasks this is imperceptible today but will stall the main actor at scale (TaskPersistenceCoordinator comment already notes prior launch stalls from O(1) disk I/O — the same pattern here).

There is **no** `[String: ActionItem]` dictionary index on the store. All reads are linear array scans.

### 3. `TaskQuery.Filters` has no `context` / `source` axis for work-vs-personal

`TaskQuery.swift` lines 29–63 define `Filters` with statuses, priorities, labels, owner, date windows, and a search string. There is no `contextIDs: Set<String>?` or `initiativeIDs: Set<String>?` filter, so a "Work" saved view cannot be expressed as a `TaskQuery`. The query engine and saved-view system (referenced in TaskQuery.swift line 9 as "Phase 2") therefore cannot enforce the separation Tyler wants.

### 4. Saved views for Tasks don't exist yet — only Meetings has them

`SavedViews.swift` (the `SavedView` struct, lines 13–21) is wired only to `MeetingsView`. `ActionItemStore` and `TaskQuery` both reference "saved views (Phase 2)" in comments (TaskQuery.swift line 9, ActionItemStore.swift line 173) but there is no `SavedTaskView` struct, no persistence key, and no UI for it. The `TaskQuery` is `Codable` and `Hashable` — the plumbing is ready, but the feature is absent.

### 5. `ActionItemsViewModel` re-implements filtering in parallel to `TaskQueryEngine`

`ActionItemsViewModel.swift` (lines 107–164) has its own `filteredSorted(items:now:)` function with manual `filter`, `priorityFilter`, and `search` logic — a separate implementation from `TaskQueryEngine.evaluate`. This means two code paths that must stay in sync, and neither can easily be serialised as a saved view.

### 6. `TaskChangeLog` records only a `summary: String` — no field-level diff

`TaskChangeLog.swift` line 96: every `update` call (ActionItemStore line 1002) emits `"Updated "\(copy.title)""` with no indication of *what* changed. Undo/redo (referenced in TaskChangeLog.swift line 7 as "BE-6") is impossible from this log because there's no before/after value stored. The Lamport clock and deviceID are already wired (lines 23, 26), but the payload is too thin to be useful.

### 7. `TaskSchemaMigrations` steps are empty — all migrations are identity

`TaskSchemaMigrations.swift` lines 25–39: all five `migrate` calls pass `steps: [:]`. The migration engine (lines 47–57) is correct and tested, but every type is pinned at version 1 with no actual transform registered. Adding a new required field (e.g., `context`) would require bumping to version 2 with a real step, and that infrastructure doesn't yet exist in practice — the first real migration is still untested end-to-end.

### 8. Atomic write for all tasks in one blob — no per-task granularity

`ActionItemStore.save()` (line 1243) writes `items + trashedItems` as a single JSON array. With 1,000 tasks and each task carrying a `notes` markdown blob, this is a large re-encode and re-write on every mutation. The debounce in `TaskPersistenceCoordinator` (0.4 s, line 34) absorbs bursts but a rapid sequence of edits to different tasks each flushes the entire file. There is no per-task or per-project dirty tracking.

### 9. `Initiative` is missing a `targetDate` field

`Initiative.swift` (lines 1–24): `Initiative` has `status` (active/archived) and a `body` but no `targetDate` or deadline. `Project` has `targetDate` (Project.swift line 35) but the top tier does not. You cannot set a Q2 deadline on an Initiative, which is core Asana/Linear behaviour.

### 10. `Project.Status` only has `active` / `archived` — no `on_hold`, `completed`

`Project.swift` lines 42–47: two states. Asana/Linear both expose at minimum active / on hold / completed / archived. A project that is done but not deleted cannot be marked as such without archiving it, which conflates "finished" with "put away".

---

## Existing items worth endorsing / prioritizing

- **`TaskPersistenceCoordinator` debounced off-main write (P0-1/BE-1):** Correct fix for the launch-stall root cause. Should be kept and the debounce window tuned down to 0.2 s for local SSD.
- **`SchemaEnvelope` + `TaskSchemaMigrations` framework (P0-5/BE-18):** The migration seam is sound; just needs its first real step.
- **`TaskQuery` as the single composable read path (BE-7):** The right abstraction. Worth completing Phase 2 (saved views) on top of it.
- **Lamport clock in `TaskChangeLog` (BE-5/BE-8):** Correct foundation for future sync. Preserve it; just thicken the event payload.
- **Soft-delete + 30-day trash retention (P0-3):** Well-implemented; the undo closures for projects/sections/initiatives are a particularly clean pattern.

---

## NET-NEW recommendations

### E1-1: Add `contextID` to `ActionItem` and `Initiative`, with a `WorkspaceContext` model

- **What:** Add a new top-level model `WorkspaceContext: Identifiable, Codable` with `id`, `name` (e.g., "Work", "Personal"), `colorHex`, and `sortIndex`. Persist it in `workspace_contexts.json`. Add `var contextID: String?` to `ActionItem` and `Initiative`. Add `func contexts(forInitiative:)` and `func items(forContext:) -> [ActionItem]` to the store. Add `.context(String)` to `TaskQuery.Scope` and `contextIDs: Set<String>?` to `TaskQuery.Filters`.
- **Why:** This is the only architecturally sound way to achieve Tyler's "work vs personal separation" goal. A label can be renamed or deleted; a context is a first-class organisational primitive that survives restructuring. Without it, every filter and saved view is a workaround.
- **Effort:** M (2 days) | **Impact:** High
- **Deps:** none

### E1-2: Add an `[String: Int]` ID-index to `ActionItemStore` for O(1) lookup

- **What:** Maintain a lazy `private var itemIndex: [String: Int] = [:]` (task id → index into `items`) that is rebuilt whenever `items` is assigned and updated on append/remove. Replace all `items.firstIndex(where: { $0.id == id })` calls in `update(_:mutate:)` (line 995), `blockers(for:)` (line 979), `reachableViaBlockers` (line 990), and the two extra scans in `setStatus` (lines 853–868) with O(1) dictionary lookups. Similarly maintain a `projectIndex: [String: Int]` and `sectionIndex: [String: Int]`.
- **Why:** Every mutation is currently O(n). At 500 tasks this is ~microseconds, but `reachableViaBlockers` is O(n·d) and `deleteLabel` (line 576) does a full `items` scan inside a save. The index costs one dictionary rebuild on load (which is already off-main) and O(1) bookkeeping per append/remove. This is the standard fix for array-backed stores with frequent point lookups.
- **Effort:** S (4 hours) | **Impact:** Med (future-proofing + correctness at scale)
- **Deps:** none

### E1-3: Persist `SavedTaskView` (a named `TaskQuery`) on `ActionItemStore`

- **What:** Add `struct SavedTaskView: Identifiable, Codable` with `id`, `name`, `icon: String?`, `query: TaskQuery`, and `sortIndex: Double`. Add `@Published private(set) var savedTaskViews: [SavedTaskView]` to `ActionItemStore`, persisted to `saved_task_views.json` via the existing `writeEnvelope` path. Add `createSavedTaskView`, `updateSavedTaskView`, `deleteSavedTaskView` store methods. Wire `TaskQuery.Scope.context` (from E1-1) so "Work Only" or "Personal" are one-click saved views.
- **Why:** `TaskQuery` is already `Codable` and `Hashable` (TaskQuery.swift line 12) — it was designed for this. `ActionItemsViewModel` re-implements filtering in parallel; saved views unify both. This is the model half of the "Phase 2" feature that has been deferred since the query engine was written.
- **Effort:** M (1.5 days) | **Impact:** High
- **Deps:** E1-1 (for context filter), E1-2 (for O(1) query evaluation at scale)

### E1-4: Add `Initiative.targetDate` and expand `Project.Status`

- **What:** Add `var targetDate: Date?` to `Initiative` (mirrors `Project.targetDate`). Expand `Project.Status` to `case active, onHold, completed, archived` and add a corresponding `setProjectStatus` mutation. Update `TaskQueryEngine` to expose a `projectStatus` filter. Both changes are additive; old JSON decodes via `decodeIfPresent`.
- **Why:** A quarter-level initiative with no deadline is organisationally incomplete. "Completed" vs "Archived" on a project is a real distinction (Asana/Linear both have it). `openCount(forInitiative:)` should exclude projects marked `.completed`.
- **Effort:** S (3 hours) | **Impact:** Med
- **Deps:** none

### E1-5: Thicken `TaskChangeEvent` with field-level before/after values for undo/redo

- **What:** Add `var field: String?` and `var oldValue: AnyCodable?` / `var newValue: AnyCodable?` to `TaskChangeEvent`. Update `ActionItemStore.update(_:mutate:)` to capture the before-snapshot and emit per-field events (e.g., `field: "status"`, `oldValue: "open"`, `newValue: "completed"`). Add an `undo()` function on `ActionItemStore` that reads the most recent event and applies the inverse. The change log already has a Lamport clock and deviceID — it just needs non-empty payloads.
- **Why:** The changelog exists explicitly to enable undo/redo (TaskChangeLog.swift line 7, "BE-6") but the `summary: String` payload (line 95) carries no machine-readable before/after. You cannot reconstruct the previous state from `"Updated \"Fix the bug\""`. Every mutation already passes through `update(_:mutate:)` — adding a snapshot before `mutate` is a one-line change per mutation.
- **Effort:** M (2 days) | **Impact:** High (undo-on-delete, cmd-Z task edits)
- **Deps:** none

### E1-6: Add write-ahead backup before each full-file save (crash safety)

- **What:** In `TaskPersistenceCoordinator.writeNow(_:to:)` (line 85), before overwriting the file, rename the existing file to `<name>.bak` atomically. On next launch, detect a `.bak` sibling and offer recovery. Alternatively: write to `<name>.tmp` first, then `rename(2)` over the live file (the current `Data.write(to:options:.atomic)` already does this via `NSFileCoordinator`, but only if the directory's extended attributes survive a kernel panic — confirm this is true for `~/Library/Application Support`).
- **Why:** The current `data.write(to:url,options:[.atomic])` (TaskPersistenceCoordinator.swift line 92) does atomic replacement via a temp file in the same directory, which is correct on a single volume. However the 0.4 s debounce window means up to 0.4 s of mutations can be in the pending dict on a hard crash, lost permanently. A generation-based backup (`.json` + `.json.bak`) gives a one-generation safety net at near-zero cost.
- **Effort:** S (2 hours) | **Impact:** High (data integrity)
- **Deps:** none

### E1-7: Add `taskTemplateID` field + `TaskTemplate` model for rapid task creation

- **What:** Add `struct TaskTemplate: Identifiable, Codable` with `title`, `defaultPriority`, `defaultLabels`, `defaultEstimate`, `sectionID`, `projectID`, `subtasks: [String]`, and `recurrence`. Persist in `task_templates.json`. Add `var templateID: String?` to `ActionItem` so created tasks trace back to their template. Add `createTask(fromTemplate:)` to `ActionItemStore`. Wire into the quick-add flow.
- **Why:** Tyler wants "faster task creation — make multiple back-to-back easily". A template for "standup blocker", "customer feedback", or "personal errand" collapses a 5-field form into a single pick. This is missing from the model entirely; `TaskQuickAddParser` covers free-text capture but not reuse of a saved shape.
- **Effort:** M (2 days) | **Impact:** High (directly addresses speed goal)
- **Deps:** E1-1 (templates are context-scoped)

---

## Top 3 picks

1. **E1-1 — `contextID` on `ActionItem` + `Initiative`** — The only model change that unblocks Tyler's top stated goal (work/personal separation). Everything else in the UI is a workaround without this field.
2. **E1-3 — `SavedTaskView` persistence** — `TaskQuery` has been `Codable` since it was written and explicitly designed for this; it's the fastest high-value unlock from "Phase 2" and makes every future filter permanently reusable.
3. **E1-5 — Field-level `TaskChangeEvent` with before/after values** — The changelog infrastructure is present but hollow; filling it unlocks cmd-Z undo across all task mutations without any architectural change, and is the single highest-trust reliability improvement available.

**Single highest priority:** **E1-1** (`contextID`). It is the load-bearing model change for the redesign's core goal, has zero breaking risk (it's an optional field on a schema-enveloped JSON file), and every downstream improvement — saved views, sidebar sections, query filters, quick-add defaults — is more valuable once tasks can be scoped by context.
