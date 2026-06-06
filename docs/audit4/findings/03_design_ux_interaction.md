# 03 — Design / UX / Interaction (Projects & Tasks)

**Lens:** I'm auditing the Projects/Tasks feature the way a Linear/Things/Superhuman power user
experiences it on day 40, not day 1: how many clicks and keystrokes does each routine action cost,
does the keyboard ever leave the mouse behind, and do mutations feel instant, reversible, and
forgiving. The bar is "I could run my whole week here without opening Notion." This is a pure
interaction-design pass — perf/architecture (covered in the G2 audit) is referenced only where it
changes how an interaction *feels*.

---

## Verified already-built (do NOT re-propose)

Grounded in code, these already exist and work — proposals below assume them:

- **Multi-select + bulk action bar** for the list view: `taskSelectMode`, `taskSelection: Set<String>`,
  bulk set-status / set-priority / delete (`ActionItemsListView.swift:40-192`). (The G2 doc proposed this as TK-3; it's now shipped, but only in the list — see UX-2.)
- **Resizable, persisted Tasks sidebar** with a drag handle + cursor + 180–360 clamp, stored in `@AppStorage("tasks.railWidth")` (`ActionItemsView.swift:42-132`).
- **Inline status / priority / due editing on list rows** via borderless menus + graphical date popover (`TaskRowView.swift:183-279`); right-click context menu for mark-done / set-priority / move-project / delete (`TaskRowView.swift:68-92`).
- **Board kanban with drag-reorder** using midpoint `sortIndex`, drag preview, tall droppable filler for empty columns (`ActionItemsBoardView.swift:50-104`).
- **Task-as-page** (Notion-style) with assignee→Person hard link, "open person" jump, clickable "From meeting" link, debounced notes autosave (`TaskPageView.swift:144-244, 358-369`).
- **Drag-to-section** in project list (`ActionItemsListView.swift:58-69`), per-section add/rename/delete.
- **Hover-reveal divider, row hover fill, 0.12s ease animation** on rows (`TaskRowView.swift:55-65`).
- **Empty state** with New-task + Re-extract CTAs and context-sensitive copy (`ActionItemsChrome.swift:409-440`).
- **Tasks dashboard landing** (quick-action cards, open tasks, pages, recent notes) (`ActionItemsChrome.swift:8-105`).
- **⌘K command palette** with `.tasks` scope, arrow-key nav, and a "new task" command (`GlobalSearchView.swift:26-69, 127`).
- **Global ⌘N New Task / Today widgets for overdue + due-today** (`MeetingScribeApp.swift:118-124`, `TodayView.swift:62`).
- **ToastCenter undo infrastructure** exists and is wired into the window (`ToastCenter.swift`, `MainWindow.swift:266`) — but Tasks doesn't use it yet (see UX-5).

---

## Improvements

### UX-1 — No keyboard navigation anywhere in the task list/table/board
- **Problem:** The single most important power-user affordance is missing. The entire Tasks tab is mouse-driven: the only shortcut is `⌥⌘N` (`ActionItemsChrome.swift:353`) and global `⌘N` (`MeetingScribeApp.swift:124`). There is no focus cursor, no `j/k`/arrow movement, no `Enter`-to-open, no `Space`/`E` to toggle done. (Compare: GlobalSearch already does arrow-nav, `GlobalSearchView.swift:67-69` — the pattern exists in-codebase but never reached the list.)
- **Evidence:** No `onKeyPress`/`onMoveCommand`/`.focusable` in `ActionItemsListView.swift`, `ActionItemsTableView.swift`, `ActionItemsBoardView.swift` (grep clean across all three).
- **Recommendation:** Add a `focusedTaskID` to the view, make the list `.focusable()`, bind `↑/↓` and `j/k` to move the cursor (O(1) via a cached `id→index` map), `Enter` to open the page, `Space`/`E` to toggle done, `⌘↑/⌘↓` to jump to list ends. Render the focused row with a ring/tint.
- **User impact:** Triaging a 30-item backlog goes from 30 mouse round-trips to holding `j` + tapping `e`. This is the difference between "feels like a web form" and "feels like Linear."
- **Effort:** M · **Deps:** none (UX-3/UX-4 build on the cursor).

### UX-2 — Multi-select exists only in the flat list; absent in sections, table, and board
- **Problem:** The bulk bar (`taskSelectToolbar`) is only rendered by `listBody` (`ActionItemsListView.swift:104-105`). Inside a **project** you get `sectionedListBody`, which never shows the Select toggle or `selectableRow` (`ActionItemsListView.swift:8-30`) — so the exact place a user lives (a project) has no bulk edit. Table and board have none either.
- **Evidence:** `taskSelectToolbar` referenced once (`ActionItemsListView.swift:105`); `sectionedListBody` calls `row(for:)` directly (line 68), not `selectableRow`.
- **Recommendation:** Lift `taskSelectMode`/`taskSelection` to the shared toolbar so it renders for every view mode; route section rows through `selectableRow`; add a checkbox on board-card hover and a leading checkbox column in the table. Pair with `X` to toggle and `⇧-click`/`⇧↓` for range select.
- **User impact:** "Move these 6 tasks into the new sprint project" while *inside* a project drops from ~12 clicks to select-then-1.
- **Effort:** M · **Deps:** UX-1 (range select reuses the cursor).

### UX-3 — Bulk bar can't set the fields users most want to batch (due, project, assignee, section)
- **Problem:** Bulk actions are status / priority / delete only (`ActionItemsListView.swift:155-169`). The highest-value batch edits — set a due date on a sprint, move a pile into a project, assign an owner — aren't there, even though the store has `setDueDate`/`setProject`/`setOwnerPerson`/`setSection`.
- **Evidence:** `bulkSetStatus`/`bulkSetPriority`/`bulkDeleteTasks` only (`ActionItemsListView.swift:181-192`).
- **Recommendation:** Add `bulkSetDue`, `bulkMoveProject`, `bulkSetOwner`, `bulkSetSection`, `bulkAddLabel` to the bar (menu/date-popover, same controls as the row). Show a one-line "6 tasks moved to Q3 Launch" undo toast (see UX-5).
- **User impact:** Weekly planning ("everything due Friday → next week") becomes one gesture instead of opening each task.
- **Effort:** S · **Deps:** UX-2, UX-5.

### UX-4 — No quick-set keystrokes on the focused/open task (S / P / A / D)
- **Problem:** Even on the task page or a focused row, changing a field always means: click the menu → read the list → click the value (3 interactions). Linear/Things let you press `S`, `P`, `A`, `D` to pop the right picker on the current item.
- **Evidence:** Status/priority are `Menu` labels everywhere (`TaskRowView.swift:184, 211`; `TaskPageView.swift:127-143`); no single-key bindings.
- **Recommendation:** With a focused row (UX-1) or open page, bind `S` (status), `P` (priority), `A` (assignee), `D`/`T` (due — with `T`=today, `M`=tomorrow, `W`=next week shortcuts inside the popover), `L` (label). Show these in a `?` cheat-sheet overlay.
- **User impact:** Set priority: 3 clicks → 1 keystroke + 1. Setting "due today" becomes `D` `T`.
- **Effort:** M · **Deps:** UX-1.

### UX-5 — Task delete is silent and irreversible (undo infra sits unused)
- **Problem:** `store.delete` removes the item and saves with no confirmation and no undo (`ActionItemStore.swift:482-485`). Delete is reachable from the row menu, context menu, page menu, and bulk bar — one slip loses a task permanently. Meanwhile People/Tags already show "Deleted X — Undo" toasts (`PeopleListView.swift:290`, `TagStore.swift:119`) using the shared `ToastCenter`. Tasks just never adopted it.
- **Evidence:** No `ToastCenter` reference in any ActionItems UI file; `delete` does a hard `removeAll`.
- **Recommendation:** Snapshot the deleted item(s) and call `ToastCenter.shared.show("Deleted '\(title)'", undoTitle: "Undo") { store.reinsert(snapshot) }`. Use the plural form for bulk delete. Add `store.reinsert(_:)` preserving original `sortIndex`.
- **User impact:** Removes a genuine data-loss footgun; matches the safety bar set elsewhere in the app.
- **Effort:** S · **Deps:** none (infra exists).

### UX-6 — "New task" always inserts the literal placeholder "New task" instead of letting you type
- **Problem:** Every create path inserts a task literally titled "New task"/"Untitled task" and then navigates to the page expecting a rename (`ActionItemsChrome.swift:403`, `ActionItemStore.swift:158`, board `:42`, global `MeetingScribeApp.swift:120`). The title field is not auto-focused on the page, so the user must click into it, select-all, and retype. If they get distracted, the backlog fills with rows literally named "New task."
- **Evidence:** `createTask(title: "New task" …)` everywhere; `TaskPageView.titleRow` binds `$titleDraft` but never sets `@FocusState` on appear.
- **Recommendation:** Replace placeholder-create with an **inline quick-add row** ("+ Add task…") pinned to the bottom of each list/section that captures the title first, commits on `Enter`, and stays focused for the next one (Things/Linear pattern). Where a page open is wanted, auto-focus + select-all the title field.
- **User impact:** Add 5 tasks: today ~5×(click+select-all+type+click-away) → type-Enter-type-Enter-type. Eliminates "New task" litter.
- **Effort:** M · **Deps:** none.

### UX-7 — No natural-language date/assignee parsing on entry
- **Problem:** Setting a due date always means opening a graphical calendar popover and clicking a day (`TaskRowView.swift:259-278`). There's no "Ship deck **tomorrow** @alice #urgent" parse-on-type that Things/Todoist/Linear use.
- **Evidence:** Title is plain text in/out (`store.setTitle`); no date/owner parsing in `createTask` or the quick-add path (missing).
- **Recommendation:** In the quick-add row (UX-6), parse trailing tokens: `tomorrow`/`fri`/`next week`/`6/12` → `dueDate`; `@name` → owner (matched against People); `#urgent`/`#p1` → priority; `!label` → label. Strip the tokens from the saved title; show a ghost chip preview as they type.
- **User impact:** Capture a fully-specified task in one line without ever touching a menu or calendar. Biggest single "feels like a real task app" jump.
- **Effort:** L · **Deps:** UX-6.

### UX-8 — Table view is read-only for the fields that matter (owner, priority, due)
- **Problem:** In the table, Owner, Priority, and Due are static `Text` — only Project and the status circle are interactive (`ActionItemsTableView.swift:88-96`). To change priority you must leave the table, open the page, change it, come back. This is inconsistent with the list (which edits everything inline) and surprising because the table *looks* like an editable spreadsheet.
- **Evidence:** `Text(item.owner ?? "—")`, `Text(item.priority.label)`, `Text(dueShort(item))` (`ActionItemsTableView.swift:88-94`).
- **Recommendation:** Reuse the row's existing priority `Menu`, due popover, and assignee→person menu as the cell content. The handlers already exist on the store.
- **User impact:** Edit a field in the dense view: 4 clicks (leave→open→edit→return) → 2. Removes a jarring read-only/editable mismatch within one tab.
- **Effort:** M · **Deps:** none.

### UX-9 — Board cards hide due date and assignee — the two things you triage on
- **Problem:** A kanban card shows title, label bars, subtask count, priority, project, meeting — but **no due date and no owner avatar** (`ActionItemsBoardView.swift:106-146`). On a board you scan for "what's late / whose is this," and neither is visible; you can't set a due date on a card at all.
- **Evidence:** `boardCard` builds priority chip + project + meeting; no `dueDate`/`owner` rendering.
- **Recommendation:** Add a due chip (red when overdue, reusing `dueText`/`dueColor` logic) and a small assignee avatar/initials to the card footer; make the due chip tappable to the date popover. Dim/strike completed cards.
- **User impact:** Board becomes usable for real triage instead of a status-only toy; due edits without leaving the board.
- **Effort:** S · **Deps:** none.

### UX-10 — Filter/group/sort state isn't visible or one-click; no saved views
- **Problem:** Status, priority, and group-by all live buried inside one funnel `Menu` (`ActionItemsChrome.swift:323-339`). There's an active-filter clear pill, but to *apply* "Due this week" or "My open tasks" you open the menu and drill. No saved/quick views, no "My work" filter (owner = me).
- **Evidence:** Single filter `Menu` (`ActionItemsChrome.swift:323`); `Filter`/`PriorityFilter` enums have no owner dimension (`ActionItemsView.swift:61-91`).
- **Recommendation:** Surface 3–4 segmented quick-view chips in the toolbar (All · My open · Due this week · Overdue) that set the filter state in one click; add an `owner == me` filter. Keep the funnel menu for the long tail.
- **User impact:** The daily slices ("what's mine / what's late") drop from 2–3 clicks-in-a-menu to 1, and become discoverable instead of hidden.
- **Effort:** M · **Deps:** none.

### UX-11 — No "My tasks" concept; the tab can't answer "what should I do now?"
- **Problem:** There's no notion of *me*. Filters are status/priority only; the dashboard shows "Open tasks" globally. A daily driver needs a personal queue (mine, sorted by due/priority). Today's widget reads `owner != ""` (anyone's), not "mine" (`TodayView.swift:166`).
- **Evidence:** No current-user identity used in task filtering anywhere; `homeSentinel` dashboard lists all open items (`ActionItemsChrome.swift:36`).
- **Recommendation:** Define "me" (a People record flagged self, or a setting). Add a top-of-rail "My Tasks" smart view = `ownerPersonID == me || owner == myName`, grouped Overdue / Today / This week / Later. Make it the default landing for returning users.
- **User impact:** Opening Tasks answers "what's on me today" instantly instead of dumping the whole org's backlog.
- **Effort:** M · **Deps:** UX-10 (filter plumbing).

### UX-12 — Two different due-date pickers, calendar-only, no relative shortcuts
- **Problem:** Due editing is a graphical month grid in both the row (`TaskRowView.swift:259-278`) and page (`TaskPageView.swift:288-298`), with only Clear/Done. Setting "tomorrow" takes a calendar hunt; there are no Today/Tomorrow/Next-week/No-date quick buttons, and the two popovers are near-duplicate code that can drift.
- **Evidence:** Both popovers are `DatePicker(.graphical)` + Clear/Done; no relative-date row.
- **Recommendation:** Build one shared `DuePopover` with a top row of Today / Tomorrow / This weekend / Next week / Someday / No date, then the calendar below. Use it from row, page, table (UX-8), and board (UX-9).
- **User impact:** "Due tomorrow" goes from open-popover→find-the-cell→click to a single button; one component to maintain.
- **Effort:** S · **Deps:** none (enables UX-8/9 consistency).

### UX-13 — Mutations are optimistic visually but offer no feedback for slow/failed sync
- **Problem:** Pushing to Notion/Linear collapses the row to one spinner (`TaskRowView.swift:312-318`) and funnels all errors into a single shared `lastError` banner (`ActionItemsChrome.swift:461, 471`). Push 5 tasks → the whole row's actions vanish behind a spinner; one failure shows a generic banner with no per-task retry. No success confirmation.
- **Evidence:** `isPushing` hides `linearButton`/`notionButton`; `lastError` is view-wide.
- **Recommendation:** Per-row sync state (idle→queued→synced/failed) with an inline retry on failure; a brief "Pushed to Linear ✓" toast on success. Don't hide the other action buttons during a push.
- **User impact:** Batch pushes stop feeling like a freeze; failures are recoverable in place instead of a dead-end banner.
- **Effort:** M · **Deps:** UX-5 (toast), bulk push from UX-3.

### UX-14 — No drag-and-drop reorder or cross-project drag in the list; drag is board-only
- **Problem:** The list supports drag *into a section* (`ActionItemsListView.swift:58-69`) but you can't reorder within a section, and you can't drag a row onto a project/initiative in the rail to move it. Manual ordering only exists on the board's `sortIndex`.
- **Evidence:** List `ForEach` has `.draggable(item.id)` but no `.dropDestination` between rows (`ActionItemsListView.swift:67-69`); rail items aren't drop targets.
- **Recommendation:** Add row-to-row `dropDestination` in sectioned lists (reuse the board's midpoint `sortIndex` logic) and make rail project/initiative rows accept a dropped task id → `setProject`. Show an insertion indicator line on hover.
- **User impact:** Reordering and re-homing tasks becomes direct manipulation instead of menu-diving; matches the board's quality.
- **Effort:** M · **Deps:** none.

### UX-15 — Accessibility gaps: icon-only controls, fixed font sizes, no VoiceOver labels on key chips
- **Problem:** Many controls are icon-only `Menu`/`Button`s with no `accessibilityLabel`: the status circle, priority capsule, due chip, sync buttons, and overflow ellipsis (`TaskRowView.swift:183-365`). Sizes are hard-coded points (`.font(.system(size: 13))`, `12.5`, etc. throughout) rather than Dynamic-Type text styles, so the tab won't scale for low-vision users. Only the section "+"/options buttons have labels (`ActionItemsListView.swift:46, 53`).
- **Evidence:** Grep shows `accessibilityLabel` only on section controls and board "+" buttons; row/page pickers have none. Pervasive fixed-point fonts in `TaskRowView.swift`, `ActionItemsChrome.swift`.
- **Recommendation:** Add `accessibilityLabel`/`accessibilityValue` to every icon control ("Status: Open", "Priority: High", "Due: overdue"), give the row an `accessibilityElement(children: .combine)` summary, and migrate to relative text styles (`.callout`, `.caption`) or `@ScaledMetric` so Dynamic Type works.
- **User impact:** Makes the tab usable with VoiceOver and at larger text sizes — currently effectively keyboard- and screen-reader-inaccessible.
- **Effort:** M · **Deps:** none.

### UX-16 — No loading/skeleton state on first paint or during sync; abrupt content pop-in
- **Problem:** On tab open the view kicks off `refreshPastMeetings` + `backfillActionItemsIfNeeded` (`ActionItemsView.swift:155-158`) and external sync runs async, but the list shows either empty-state or fully-populated with nothing in between — content pops in. There's a small `ProgressView` in the toolbar during sync (`ActionItemsChrome.swift:349`) but the list area gives no signal.
- **Evidence:** No skeleton/placeholder rows; `content` switches straight between `emptyState` and the populated list.
- **Recommendation:** Show 4–6 shimmer skeleton rows while the initial load / first sync is in flight; keep stale data visible with a subtle "syncing" affordance during refresh rather than blanking.
- **User impact:** First open feels intentional instead of flickery; reduces the "is it broken / empty?" doubt on a fresh import.
- **Effort:** S · **Deps:** needs a store `isLoading` flag.

### UX-17 — Empty states are generic; no contextual empties for project / filter / board column
- **Problem:** There's one global empty state (`ActionItemsChrome.swift:409-440`). A brand-new **project** with a database shows generic "No action items"; an over-filtered list shows "No items match the current filters" with no one-click "clear filters"; empty board columns show only the faint "Drag a task here" only in the *list* section path, not the board.
- **Evidence:** Single `emptyState` + `emptyMessage` (`ActionItemsChrome.swift:409-440`); board columns have no empty messaging (`ActionItemsBoardView.swift:50-74`).
- **Recommendation:** Per-context empties: new project → "Add your first task to '\(project)'" with the quick-add focused; filtered-empty → "No matches — Clear filters" button; empty board column → subtle "Nothing \(status.label.lowercased())."
- **User impact:** Empty screens become next-step prompts instead of dead ends; the filter trap (looks broken when a filter hides everything) gets a one-click escape.
- **Effort:** S · **Deps:** none.

### UX-18 — Opening a task replaces the whole pane; no back/forward, no peek, loses scroll
- **Problem:** Selecting a task swaps the right pane entirely to `TaskPageView` (`ActionItemsView.swift:134-137`); closing returns to a list that re-derives from scratch and loses scroll position and the previously focused row. There's a breadcrumb back-button (`TaskPageView.swift:70-79`) but no `Esc`-to-close, no next/prev-task arrows, no lightweight peek.
- **Evidence:** Right pane is an `if/else` over `selectedTaskID`; close just nils it; no scroll restoration or focus return.
- **Recommendation:** Bind `Esc` to close the page; add `⌥↑/⌥↓` (or `J/K` on the page) to move to the prev/next task in the current filtered list without returning to the list; restore the list's scroll + focus to the task you came from on close.
- **User impact:** Reviewing 10 tasks in a row becomes open→read→`⌥↓`→read… instead of open→back→scroll-find→open. Keeps spatial context.
- **Effort:** M · **Deps:** UX-1 (shares the ordered id list).

### UX-19 — Status toggle is all-or-nothing; no in-progress affordance, no completion micro-feedback
- **Problem:** The big title-row status button only flips open↔completed (`TaskPageView.swift:106`, `ActionItemsTableView.swift:74-75`); reaching "In Progress" requires the menu. And completing a task just swaps an SF Symbol — no satisfying check animation, no strike-through transition, no haptic/sound. Completion is the most-repeated action and currently feels flat.
- **Evidence:** `status == .completed ? .open : .completed` toggle (multiple sites); `strikethrough` applied with no transition.
- **Recommendation:** Make the checkbox cycle open→in-progress→done on click (with a clear three-state glyph), or expose a hover "play" affordance for in-progress. Add a quick scale/checkmark-draw animation + optional sound on completion, and animate the strike-through + reorder.
- **User impact:** The hundred-times-a-day action gets a moment of delight and a faster path to "in progress" without a menu.
- **Effort:** S · **Deps:** none.

### UX-20 — Inline detail editor and page duplicate the same editing UI inconsistently
- **Problem:** A list row can expand inline into a full detail editor (`TaskRowView.swift:378-456`: title, assignee, dates, labels, subtasks, notes) **and** a tap also opens the full `TaskPageView` with overlapping-but-different controls (free-text assignee with no person link in the row editor vs. person-link menu on the page). Two editors for one task means inconsistent capabilities and double the maintenance; users learn one and get surprised by the other.
- **Evidence:** `detailEditor` in `TaskRowView.swift:378` vs. `TaskPageView.properties` (`TaskPageView.swift:124`); row editor's assignee is plain `TextField` (`:391`) with no person link, page has the link menu (`:160`).
- **Recommendation:** Pick one editing surface. Recommended: keep the row's *quick-edit* to inline status/priority/due/labels only, and route "edit details" to the page (single source of truth). Or, if inline-expand stays, port the person-link menu into it so capabilities match.
- **User impact:** Consistent, predictable editing; person-linking available wherever you edit; less drift.
- **Effort:** M · **Deps:** decide direction with UX-8.

### UX-21 — No reminders/notifications for due tasks; due dates are passive
- **Problem:** Tasks carry due dates and the app already has Notifications permission + meeting-start alerts (`OnboardingSheet.swift:371`), but nothing notifies on a task becoming due/overdue. The Today widget surfaces overdue *only if the user opens the app* (`TodayView.swift:62`).
- **Evidence:** No `UNUserNotificationCenter` scheduling tied to `dueDate` anywhere in ActionItems; notifications are meeting-only.
- **Recommendation:** Schedule a local notification at a user-set time on the due date (and an overdue nudge) for tasks owned by "me" (UX-11). Tapping the notification deep-links to the task via the existing `.meetingScribeOpenEntity` route.
- **User impact:** Due dates become actionable commitments instead of decoration; closes the loop that makes a task app trustworthy enough to leave Notion.
- **Effort:** M · **Deps:** UX-11 ("me"), deep-link route (exists).

### UX-22 — Discoverability: power features are invisible (no shortcut hints, no menus)
- **Problem:** The good interactions that *do* exist are hidden. Drag-to-section, the right-click context menu, `⌥⌘N`, the funnel filter, multi-select — none are hinted in the UI. New users won't find them, and there's no `?`/shortcut sheet. The "Select" toggle is a bare text button with no icon/tooltip (`ActionItemsListView.swift:146`).
- **Evidence:** Only `.help()` tooltips on a few buttons; no onboarding hints, no keyboard-shortcut reference, no first-run coachmarks for the Tasks tab.
- **Recommendation:** Add a `?` shortcut-cheatsheet overlay (lists every nav/quick-set key from UX-1/4), `.help()` tooltips on every icon control, and a one-time inline hint ("Tip: drag tasks between sections, or press ⌥⌘N") on first visit. Add the bulk/filter actions to the app menu bar so they're searchable via Help.
- **User impact:** The speed features become *findable*, which is what actually makes them get used — a fast app nobody can discover is a slow app.
- **Effort:** S · **Deps:** lands after UX-1/UX-4 so the sheet documents real shortcuts.

---

## Top 5 picks

1. **UX-1 — Keyboard navigation (j/k/arrows, Enter, Space/E).** The defining gap vs. Linear/Things and the substrate for quick-set, prev/next, and range-select. Highest leverage per unit effort.
2. **UX-6 + UX-7 — Inline quick-add with natural-language parsing.** Turns capture from a multi-click placeholder-then-rename chore into one typed line ("Ship deck tomorrow @alice #urgent"). The clearest "this is a real task app now" moment.
3. **UX-5 — Undo on delete (adopt the existing ToastCenter).** Removes a true data-loss footgun for near-zero effort; the infra is already shipped and used elsewhere.
4. **UX-11 + UX-10 — "My Tasks" smart view + one-click quick-view chips.** Lets the tab answer "what should I do now?" — the prerequisite for it replacing a daily driver, not just storing tasks.
5. **UX-8 + UX-9 — Make table fields editable and put due/assignee on board cards.** Fixes the two non-list views so all three editing surfaces are consistent and triage-ready; mostly reuses existing handlers, so high ratio of value to effort.

---

*Scope note:* This pass deliberately avoids re-proposing the G2 audit's caching/persistence
work (debounced off-main writes, memoized filters, indexed counts). Those make these interactions
*feel* instant; the items above are what make them *exist* and be *discoverable*. Several UX items
(UX-1 cursor map, UX-3 bulk writes, UX-13 per-row sync) will land better once G2's `itemsRevision`
substrate is in place, but none are blocked on it.
