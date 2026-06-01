# G2 — Tasks / Actions Tab (Senior PM/UX)

Lens: treat the Tasks tab as a real task manager (Linear/Things/Asana) — every task reachable in ≤3 clicks, every per-task action ≤2 clicks, board/table/list buttery on large datasets, and tasks woven into meetings/people/decisions. Cache and index everything that's recomputed per keystroke.

## Audit (through my lens)

**Verified already-built (do NOT re-propose):**
- Person↔task hard link: `ActionItem.ownerPersonID` (`ActionItems/ActionItem.swift:28`), assignee→Person picker + "open person" jump in `TaskPageView.swift:144-188`, reverse lookup `items(forPerson:)` (`ActionItemStore.swift:513`).
- Meeting links: clickable "From meeting" in `TaskPageView.swift:226-244` (posts `.meetingScribeOpenEntity`); project↔meeting link menu in `ActionItemsProjectPage.swift:91-110`; meeting notes page with inline items `MeetingNotesPage` (`ActionItemsProjectPage.swift:274`).
- Board drag/reorder w/ midpoint `sortIndex` (`ActionItemsBoardView.swift:84-104`), Linear+Notion push (`ActionItemsChrome.swift:460-506`), initiatives→projects→sub-pages tree, sections, labels, subtasks, schema-enveloped persistence with **off-main initial load** (`ActionItemStore.swift:41-55`).

**Problems found:**

1. **Dead duplicated view-state layer.** `ActionItemsViewModel.swift` (287 lines, `@Observable`, full filter/sort/group logic) is **never instantiated** — `MainWindow.swift:215` builds `ActionItemsView(store:)`, which still carries its own inline `@State` + duplicate `Filter`/`GroupBy`/`filtered` (`ActionItemsView.swift:12-101`, `ActionItemsListView.swift:123-228`). Two sources of truth that have already drifted (VM has `groupBy.owner/dueDay`; the live view has `.meeting/.dueDate`). Confusing and a latent-bug source.

2. **Every keystroke re-filters + re-sorts the entire item array, uncached.** `filtered` (`ActionItemsListView.swift:123`) is a computed property: 3 chained `.filter` + `.sorted` over `store.items` on every `body` eval — and `projectFiltered`, `tableSorted` (`ActionItemsTableView.swift:23`), `grouped`, and each board column (`columnItems`, `ActionItemsBoardView.swift:21`) re-derive from it. Typing in search recomputes all of it per character. `DateFormatter()` is even allocated inside `dueShort`/`groupKey` per row. Fine at 50 tasks; janky at 1–2k (post-Linear-import).

3. **No list virtualization in table/board.** Table uses a plain `VStack` inside `ScrollView` (`ActionItemsTableView.swift:8-19`) — every row is materialized (list/sectioned views correctly use `LazyVStack`). Board columns are eager `ForEach` in an `HStack`. A large imported backlog builds the whole tree up front → slow first paint + memory spike.

4. **Synchronous full-file write on every single mutation.** `update()`/`setStatus`/`setPriority`/`toggleSubtask` each call `save()`, which JSON-encodes the **entire** `items` array (pretty+sorted) and writes atomically on the main actor (`ActionItemStore.swift:536-543, 668-672, 744-757`). Dragging a card or checking 5 subtasks = N full re-encodes of the whole DB on the UI thread.

5. **No multi-select / bulk actions in Tasks** (People already got this — briefing line 8). To mark 8 tasks done or move them to a project you click each row's menu individually. Linear's core speed unlock is `X` to select + bulk-edit ([Linear Docs](https://linear.app/docs/select-issues)).

6. **No keyboard navigation.** Only `⌥⌘N` exists (`ActionItemsChrome.swift:353`). No j/k, no arrow nav, no `S/P/A/D` quick-set, no Enter-to-open. Everything is mouse-driven menus. A task manager without keyboard flow feels slow.

7. **Click-count gaps.**
   - Set assignee→person: open task page (1) → click assignee menu (2) → pick person (3) = 3 clicks, *and only available on the full page* — the inline list row and table row can't link a person at all.
   - Reassign priority/status from list: inline (good, 2 clicks). But **board cards** have no due-date and no inline assignee; editing them needs opening the task.
   - Table view exposes Task/Project/Owner/Priority/Due but **owner and priority are read-only text** (`ActionItemsTableView.swift:88-92`) — you must open the task to change them. Inconsistent with the list row, which edits inline.

8. **Two parallel filter pill systems & a dashboard-vs-All-tasks split.** Default landing differs between files: `ActionItemsView.swift:23` defaults `selectedProjectID = nil` (All tasks) while the VM defaults to `homeSentinel` (dashboard) — more drift. The "This Week" filter logic is duplicated and slightly different across `ViewModel.filteredSorted` and `ActionItemsListView.filtered`.

9. **Sidebar is a hard-coded 230px, non-resizable** (`ActionItemsView.swift:110` `.frame(width: 230)`) — flagged cross-app. Long initiative/project trees truncate; no way to widen.

10. **Meeting list in rail capped at `prefix(40)`** (`ActionItemsSidebar.swift:108`) and recomputes open-task counts per meeting per render (`store.items(for:)` filters the full array for each of 40 rows). O(meetings × items) on every sidebar redraw.

## NET-NEW recommendations

**TK-1 — Collapse to the existing ViewModel as the single cached source of truth.**
What/why: Wire `ActionItemsView` to `@State private var vm = ActionItemsViewModel()` (it's already written, `@Observable`, `@MainActor`), delete the duplicate inline enums + `filtered`/`projectFiltered`/`grouped`/`tableSorted`. Memoize the derived list: cache `(filterSignature, itemsRevision) → [ActionItem]` so `body` re-uses the last result unless inputs changed; bump an `itemsRevision: Int` in the store on each mutation.
UX impact: none visible; kills the drift bugs (default landing, This-Week, group-by mismatch).
Perf/stability: removes per-keystroke full re-filter/sort; one cached array reused across list/table/board. Cache keyed on a cheap signature string → near-zero recompute on pure redraws. **S/M, High.** Dep: none (foundational).

**TK-2 — Debounced, coalesced, off-main persistence.**
What/why: Replace per-mutation `save()` with a dirty-flag + 300–500ms debounce that encodes on a background task and writes atomically; flush on `scenePhase`/`onDisappear`. Encode with `pretty:false` for the hot path (keep pretty only for export).
UX impact: drag/check/edit feels instant — no main-thread stall mid-gesture.
Perf/stability: collapses N writes during a drag into 1; moves JSON encode off the UI thread. Lower crash risk from interrupted atomic writes mid-burst. **S, High.** Dep: none.

**TK-3 — Multi-select + bulk action bar (Linear parity).**
What/why: Add `selectedTaskIDs: Set<String>` to the VM; checkbox on hover at row left, `X` to toggle, `⇧↑/↓` range, `⌘A` select-all-filtered. Floating bottom bar: Set status / priority / project / assignee / due / delete. Store gets `bulkSetStatus(_:to:)` etc. that mutate in one pass + one save.
UX impact: "mark 8 done" goes from ~16 clicks → select + 1 action. Matches [Linear](https://linear.app/docs/select-issues).
Perf/stability: one batched mutation + one debounced write (with TK-2) instead of N. Selection is just a `Set` — no copies. **M, High.** Dep: TK-1, TK-2.

**TK-4 — Keyboard-first navigation & quick-set.**
What/why: Make the list/table focusable; `j/k`+arrows move a focus cursor, `Enter` opens, `Space`/`E` toggle done, `S/P/A/L/D` open status/priority/assignee/label/due inline on the focused row, `C` new task. Surface in a `?` shortcut sheet.
UX impact: power users never touch the mouse; every per-task action ≤1 keystroke from focus.
Perf/stability: pure SwiftUI focus state; no data cost. Add a small `id`→index map (cached) so cursor math is O(1). **M, High.** Dep: TK-1.

**TK-5 — Editable, virtualized table; richer board cards.**
What/why: Make table Owner/Priority/Status/Due inline-editable (reuse the list row's menus/popovers) so behavior matches the list (`ActionItemsTableView.swift:88-94`). Wrap table rows and board columns in `LazyVStack`/lazy stacks. Add inline due-chip + assignee avatar to board cards (`ActionItemsBoardView.swift:106`).
UX impact: edit a field in table without opening the task (3→1 click); consistent across all three views.
Perf/stability: lazy materialization → faster first paint and lower memory on big boards/tables. **M, Med.** Dep: TK-1.

**TK-6 — Person link from any view + reciprocal task panel on Person.**
What/why: Add the assignee→Person menu (already in `TaskPageView`) to the list row's ellipsis and the table Owner cell, so linking doesn't require opening the page. Confirm the People tab shows a cached "Tasks owned" section reading `items(forPerson:)` and updates live.
UX impact: link a person to a task in 2 clicks from the list; tasks↔people feels two-way.
Perf/stability: reuse `personPickerList` (already capped to 50, sorted by recency). Cache the person-display-name lookup map in the VM to avoid `people.person(by:)` per row. **S/M, Med.** Dep: TK-1.

**TK-7 — Cached counts + indexed lookups in store/sidebar.**
What/why: Precompute, on each store revision, dictionaries: `openCountByProject`, `openCountByInitiative`, `itemsByMeetingID`, `countByMeetingID`. Sidebar (`ActionItemsSidebar.swift:46-53,108-167`) and dashboard read O(1) instead of re-filtering `store.items` per badge per render.
UX impact: none visible (same numbers), but sidebar/board redraws stop hitching as the backlog grows.
Perf/stability: turns O(rows × items) per render into O(1) reads; recompute once per mutation (cheap, debounced with TK-2). Persist nothing extra. **S, Med.** Dep: TK-2.

**TK-8 — Resizable sidebar with persisted width.**
What/why: Replace `.frame(width: 230)` (`ActionItemsView.swift:110`) with a draggable splitter (`NavigationSplitView` column or a drag handle) clamped 200–360px, width stored in `AppSettings`. Shared with the cross-app sidebar fix.
UX impact: deep initiative trees stop truncating; user controls density.
Perf/stability: layout-only; persist one Double. No runtime cost. **S, Med.** Dep: align with global sidebar work.

**TK-9 — "Group by" cached buckets + sticky group headers; promote saved views.**
What/why: Move grouping to the VM's `groupItems` (already written) with cached buckets keyed on the filter signature; make group headers sticky in the `ScrollView`. Add 2–3 one-click saved views (My open, Due this week, Overdue) as toolbar chips that set filter state.
UX impact: switching group-by is instant; common slices reachable in 1 click vs. drilling the filter menu.
Perf/stability: bucketing runs once per change, not per redraw. Saved views are just stored filter structs. **M, Med.** Dep: TK-1.

**TK-10 — Optimistic, decoupled external push (Notion/Linear).**
What/why: `pushToNotion/Linear` already run in a `Task`, but errors land in a shared `lastError` banner and the row shows a single spinner. Add per-row optimistic state (queued→synced) and retry; never block the UI. Cache the Linear team/project list (currently re-fetched on each popover, `ActionItemsProjectPage.swift:186-190`).
UX impact: pushing N tasks doesn't freeze; clear per-task sync status.
Perf/stability: network off the main actor (already is); caching the project list avoids repeat fetches; failures isolated per row, lowering "one bad push kills the batch" risk. **M, Low/Med.** Dep: TK-3 (bulk push).

## Top 3 picks

1. **TK-2 — Debounced off-main persistence** → **Phase 1** (foundational perf/stability). Highest-leverage: every interaction in the tab currently triggers a synchronous full-DB encode+write on the UI thread. Fixing it makes everything else feel instant and is a prerequisite for bulk ops.
2. **TK-1 — Single cached ViewModel source of truth** → **Phase 1**. Kills the dead-code drift and removes per-keystroke re-filter/sort; the caching substrate that TK-3/4/5/9 build on.
3. **TK-3 — Multi-select + bulk action bar** → **Phase 3**. The biggest day-to-day UX win and the clearest Linear-parity gap; ~16 clicks → 2 for batch edits.

**Single highest-value recommendation:** TK-2 (debounced, coalesced, off-main writes) — it's small, removes the worst latent jank/crash vector, and unblocks bulk actions.

**Perf/caching insight:** The whole tab recomputes everything per render — filtered/sorted lists per keystroke, sidebar/badge counts per redraw (O(rows×items)), and a full-array JSON write per field edit, all on the main actor. The fix is one cheap `itemsRevision` counter in the store driving (a) memoized filtered/grouped arrays keyed on a filter signature and (b) precomputed count/index dictionaries, plus a debounced background writer. That single pattern de-janks list, table, board, and sidebar at once and scales to post-import 1–2k-task backlogs.

Sources: [Linear — Select issues](https://linear.app/docs/select-issues), [Linear — Assign issues](https://linear.app/docs/assigning-issues), [Bulk edit in Linear](https://www.storylane.io/tutorials/how-to-bulk-edit-issues-in-linear)
