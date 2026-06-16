# MeetingScribe Tasks — Phased Master Plan
*Compiled from 9-agent audit (D1–D3, E1–E2, P1–P3, U1). Date: 2026-06-16.*

---

## Convergence Map

These themes were independently raised by **4 or more agents** — they are the highest-signal items in the entire audit.

| Theme | Agents | Signal |
|---|---|---|
| Work / Personal context separation | D1, D3, E1, P1, P3, U1 | **6/9 — #1 priority** |
| "Today" smart view (no today-focused entry point exists) | D1, U1 (x2) | 3/9 |
| Quick-add speed / auto-refocus after submit | D2, U1, U1 | 3/9 |
| Triage inbox grouped by source meeting | P2, P2 (x2), U1 | 3/9 |
| Home board focus filter + "+N more" fix | D1, D3, P3, U1 | 4/9 |
| ViewModel completion + typed route enum | E2 (x2), E1 | 3/9 |
| Saved views (TaskQuery is Codable, never wired to persistence) | P3, E1, D1 | 3/9 |
| Initiative roll-up task view (initiatives are dead-ends) | P1, U1, D1 | 3/9 |

---

## Critical Bugs / P0 (Fix Before Anything Else)

These are working code that is simply not wired up or silently broken.

### P0-1: Quick-add popover has no `@FocusState` — focus is lost after every submit
- **What:** `quickAddPopover` in `ActionItemsChrome.swift:450` has no focus binding. After pressing Enter, the cursor goes nowhere. Creating 5 tasks requires 4 mouse clicks.
- **File:line:** `ActionItemsChrome.swift:450`, `TaskPageView.swift:subtasks()`
- **Effort:** S | **Impact:** High (directly answers Tyler's "multiple tasks back to back" goal)

### P0-2: `detailEditor` in `ActionItemRow` is unreachable — dead interaction
- **What:** `onToggleExpand` in `ActionItemsListView.swift:row(for:)` always sets `selectedTaskID`, never `editingID`. The fully-built inline expansion panel (`TaskRowView.swift:413–492`) is simply never shown.
- **File:line:** `ActionItemsListView.swift:419–465`, `TaskRowView.swift:413`
- **Effort:** S | **Impact:** High

### P0-3: `PageTreeNode.onTapGesture` never clears `selectedInitiativeID` — stale highlight bug
- **What:** Tapping a project while an initiative is selected leaves the initiative still highlighted.
- **File:line:** `ActionItemsSidebar.swift:562`
- **Effort:** S | **Impact:** Med

### P0-4: Archived initiatives and projects are shown alongside active ones with no visual distinction
- **What:** `sortedInitiatives()` and `standaloneTopProjects()` return archived items without filtering. No "Show archived" toggle exists.
- **File:line:** `ActionItemStore.swift:632`, `ActionItemStore.swift:671`
- **Effort:** S | **Impact:** Med

### P0-5: "This Week" filter includes `createdAt` — wrong behavior, should be `dueDate`
- **What:** `ActionItemsListView.swift:280–285` includes `createdThisWeek` in "This Week" results.
- **File:line:** `ActionItemsListView.swift:280`
- **Effort:** S | **Impact:** Med

---

## Phase 0 — Architecture Foundation (Prerequisite for everything)
*These are internal changes. No visible UI ships. Required before Phase 1.*

### A0-1: Complete ViewModel migration (E2-1)
Wire `ActionItemsViewModel` as `@StateObject` in `ActionItemsView`. Delete 29 `@State` vars from the view. Unify `GroupBy`, `Filter`, `ViewMode` enums (currently defined twice with diverged cases). Delete `var filtered` from `ActionItemsListView` and replace with `vm.filteredSorted()`. **Eliminates 3 parallel filter implementations.**
- **Effort:** M | **Deps:** none

### A0-2: Typed `TasksRoute` enum replacing sentinel strings (E2-2)
Replace all `selectedProjectID == "__home__"` magic strings with a `TasksRoute` enum. Makes adding new surfaces safe. Required before Context Spaces.
- **Effort:** M | **Deps:** A0-1

### A0-3: `TasksEnvironment` to kill 3-binding prop drilling (E2-4)
`ProjectRail`, `PageTreeNode`, and `InitiativeNode` each receive the same 3 `@Binding` parameters. Define a `@EnvironmentObject` struct instead. Fixes P0-3 as a side effect.
- **Effort:** S–M | **Deps:** A0-2

### A0-4: O(1) ID index on `ActionItemStore` (E1-2)
Add `private var itemIndex: [String: Int]` rebuilt on `items` assignment. Replace all `items.firstIndex(where:)` with dictionary lookup. Also add `projectIndex` and `sectionIndex`.
- **Effort:** S | **Deps:** none

---

## Phase 1 — Foundation: Work/Personal Separation + Today View
*The #1 convergence theme (6/9 agents). Everything else is downstream of this.*

### 1-1: `WorkspaceContext` model + `contextID` on Initiative & ActionItem (D1-4, D3-1, E1-1, P1-1)
**THE single most important change in this audit.** Add:
- `WorkspaceContext: Identifiable, Codable` (id, name, colorHex, sortIndex) — persisted to `workspace_contexts.json`
- `var contextID: String?` on `Initiative` and `ActionItem` (additive; old JSON decodes `nil → .work`)
- `TaskQuery.Scope.context(String)` and `contextIDs: Set<String>?` in `TaskQuery.Filters`
- Store methods: `contexts()`, `items(forContext:)`
- Two built-in contexts pre-seeded: "Work" (blue) and "Personal" (green)
- **Effort:** M | **Impact:** High | **Deps:** A0-4

### 1-2: Context switcher in sidebar header (D1-4, D3-1, P1-1, U1-10)
Above "Home" in `ProjectRail`, add a compact segmented control: `All | Work | Personal`. Selection scopes the entire sidebar initiative/project tree AND the task list. Switching context is instant — no navigation change. A "Show all" pill in All Tasks, Today, and Triage inbox spans contexts regardless of selection.
- **Effort:** M | **Impact:** High | **Deps:** 1-1

### 1-3: "Today" smart view as sidebar top entry + default landing (D1-2, U1-1, U1-6)
Add a "Today" permanent rail item (below Home, above Triage). Content: overdue tasks (red header), then due today, then started today. Grouped by Initiative/Project. Count badge that resets on visit. Make it the **default landing** when entering the Tasks tab (replace the current aimless "All tasks" default). Implement as a new sentinel route: `.today`.
- **Effort:** M | **Impact:** High | **Deps:** A0-2

### 1-4: Home board focus filter + fix "+N more" (D3-4, P3-8, D1-8, U1-9)
- Add `FilterBar` above `HomeTasksBoard` columns: `Today | This Week | All` time pills + `Work | Personal | All` context toggle (from 1-2)
- Make `"+N more"` a tappable button that deep-links to Tasks in Board view, filtered to that column
- Make columns scrollable (remove hard 8-card cap OR make the column itself scroll to 160px max-height)
- **Effort:** S–M | **Impact:** High | **Deps:** 1-1

### 1-5: Context color coding on task rows + Kanban cards (D3-1, U1-10)
Once `contextID` exists, render a 3px colored left border on every task row and a colored top stripe on every Kanban card indicating Work/Personal/Other. No text labels — just color. NDS tokens for context colors.
- **Effort:** S | **Impact:** High | **Deps:** 1-1

---

## Phase 2 — Speed & Daily Fluency
*Directly addresses "fewer clicks, faster task creation, multiple tasks back-to-back."*

### 2-1: Fix quick-add auto-refocus (P0-1) — ship with Phase 2 (D2-1)
Add `@FocusState` to `quickAddPopover`. On submit (Enter), clear text AND re-focus immediately. Same fix for `TaskPageView.subtasks()` inline subtask field.
- **Effort:** S | **Impact:** High | **Deps:** none

### 2-2: Wire inline `detailEditor` (P0-2) — single-tap expands, double-tap opens page (D2-2)
Change `onToggleExpand` in `ActionItemsListView.row(for:)` to set `editingID` (not `selectedTaskID`). Double-click or `→` arrow key opens `TaskPageView`. Single tap is now inline-edit.
- **Effort:** S | **Impact:** High | **Deps:** none

### 2-3: Extend `TaskQuickAddParser` with `@ProjectName` and `due:today/friday` (D2-4, U1-2)
- Recognize `@ProjectName` (fuzzy-match against `store.projects`) — auto-route task without extra click
- Recognize `due:today`, `due:tomorrow`, `due:friday`, `due:+3d`
- Surface hint text in the popover: "Type @Project or due:friday"
- **Effort:** S | **Impact:** High | **Deps:** none

### 2-4: Keyboard property shortcuts in list: `p`=priority, `d`=due, `e`=estimate, `m`=move (D2-3)
Extend the `.onKeyPress` block (`ActionItemsListView.swift:135–140`) with 4 more handlers. `p` cycles priority; `d` opens an inline date field (type-ahead); `e` opens estimate picker; `m` opens project mover menu.
- **Effort:** M | **Impact:** High | **Deps:** 2-2

### 2-5: Replace graphical date-picker popover with type-ahead date field (D2-4)
Replace `DatePicker(.graphical)` in `TaskRowView` and `TaskPageView` with a `TextField` that parses via `NSDataDetector`. Show parsed date preview below; calendar icon falls back to graphical. Accepts: "tod", "tom", "fri", "6/12", "+3d".
- **Effort:** M | **Impact:** High | **Deps:** none

### 2-6: ⌘-Click / Shift-Click native multi-select + bulk action bar (U1-3)
Wire `.onTapGesture(modifiers: .command)` and `.onTapGesture(modifiers: .shift)` on task rows. Auto-show bulk action bar (Set status / Move project / Set priority / Delete) when selection is non-empty. No "Select mode" toggle needed.
- **Effort:** S | **Impact:** High | **Deps:** none

### 2-7: Compact priority dot replaces verbose priority capsule on collapsed rows (D3-5)
Replace `priorityPicker` capsule (text label visible always) with a 10×10 colored dot (no text) on collapsed rows. Priority label stays in expanded detail and on hover tooltip. Use existing `MSPriorityBadge(showLabel: false)`.
- **Effort:** S | **Impact:** Med | **Deps:** none

### 2-8: Hide sync buttons for tasks with no integration configured (D3-10)
Conditionally render Linear/Notion row buttons only when the project has a sync target configured. Cleans up row visual noise for 90% of tasks.
- **Effort:** S | **Impact:** Med | **Deps:** none

---

## Phase 3 — Navigation & Structure
*Initiative→Project→Task should feel traversable. Work/personal should feel organized.*

### 3-1: ⌘K Tasks-scoped jump palette (D1-7)
`⌘K` opens a floating inline omnibox searching Initiatives, Projects, and Tasks simultaneously. Items grouped by type, showing parent hierarchy inline (e.g., "Work / Q3 Launch / Website"). Selecting navigates there. Tasks-scoped only (not global search). Implemented as an NSPanel overlay.
- **Effort:** M | **Impact:** High | **Deps:** A0-2

### 3-2: Initiative roll-up task view (P1-2, D1 — initiatives are dead-ends)
When a user selects an initiative in the sidebar, show a two-panel right pane: top = project index (compressed); bottom = `ActionItemsListView` scoped to `TaskQuery(scope: .anyProjects(projectIDs))`. Add a progress bar from `completion(forInitiative:)` (already in store). Add quick-add bar that prompts project if multiple exist.
- **Effort:** M | **Impact:** High | **Deps:** A0-2, 1-1

### 3-3: `TaskQuery.Scope.initiative(String)` (P1-5)
One new enum case, resolved by the query engine to `anyProjects(store.projects(forInitiative:).map(\.id))`. Eliminates 4+ duplicated project-ID resolution loops.
- **Effort:** S | **Impact:** Med | **Deps:** A0-1

### 3-4: Sidebar zone separation — "Smart Views" above, "My Work" below (D1-1)
Split `ProjectRail`'s `ScrollView` into two visual zones with a Divider+label: **Smart Views** (Home, Today, Triage, All tasks, My Tasks, Unsorted, People, Waiting-on) and **My Work** (Initiatives tree, Pages tree, Meeting notes). Linear's left rail uses this pattern.
- **Effort:** M | **Impact:** High | **Deps:** A0-3

### 3-5: Initiative context menu — rename, archive, change icon, assign context (P1-3)
Expand `InitiativeNode.contextMenu` with: inline rename, archive/unarchive, SF Symbol icon picker, context assignment (Work/Personal). Add drag handle for reordering.
- **Effort:** S | **Impact:** Med | **Deps:** 1-1

### 3-6: Clickable breadcrumb trail: Initiative → Project → Task (D1-3)
Replace `taskBreadcrumb` in `ActionItemsView.swift:252` with a multi-tier clickable breadcrumb in both `TaskPageView` header and project pane header. Each segment navigates back up. If no initiative, show project only.
- **Effort:** S | **Impact:** High | **Deps:** A0-2

### 3-7: Pinned projects rail — drag-to-pin top 3 slots (U1-4)
Permanent "Pinned" section at top of `ProjectRail` (above Home). Drag any project/initiative to pin (max 3). Persisted in `AppSettings`. Zero-click nav to most-used projects on launch.
- **Effort:** M | **Impact:** High | **Deps:** none

### 3-8: Extend WorkspaceRouter history to include Tasks-internal nav (D1-6)
Add `selectedTaskID` and `selectedProjectID` (as a typed route) to `NavState`. `goBack()`/`goForward()` restore the Tasks pane's internal selection.
- **Effort:** S | **Impact:** Med | **Deps:** A0-2

### 3-9: Hide archived items by default with "Show archived" toggle (P0-4)
Filter `sortedInitiatives()` and `standaloneTopProjects()` to exclude `.archived`. Add a "Show archived" text button at bottom of sidebar rail.
- **Effort:** S | **Impact:** Med | **Deps:** none

### 3-10: `@SceneStorage`-backed `TasksNavState` (E2-6)
Persist `route`, `viewMode`, `railWidth`, `selectedTaskID` across restarts and multiple windows.
- **Effort:** S | **Impact:** Med | **Deps:** A0-2

---

## Phase 4 — Meeting → Tasks Integration
*Tyler's explicit goal: pull in meeting notes and action items while keeping them well-organized.*

### 4-1: Group triage inbox by source meeting with per-meeting bulk actions (P2-1, U1-5)
Restructure `TriageInboxView` into collapsible sections grouped by `meetingID`. Each group header shows: meeting title, date, attendee avatars, and two controls: "Add all to project…" (project picker routes the whole group) and "Dismiss meeting" (discard all with undo).
- **Effort:** M | **Impact:** High | **Deps:** none

### 4-2: Smart project suggestion in triage rows (P2-2)
In `TriageRow`, fuzzy-match `item.meetingTitle` against `store.projects`. Render top match as a pre-filled project chip. Tap to confirm; tap again to open full picker.
- **Effort:** S | **Impact:** High | **Deps:** none

### 4-3: "Insert meeting context" button in task body editor (P2-4)
In `TaskPageView.bodyEditor`, add a toolbar button "Insert from meeting" that (for `!isManual` tasks) appends a formatted block to `noteDraft`: meeting title, date, and summary excerpt. Zero new screens.
- **Effort:** S | **Impact:** High | **Deps:** none

### 4-4: Inline meeting peek panel — no tab switch (P2-3)
When "Open source meeting" is clicked in `TriageRow` or `TaskPageView`, open a right-pane sheet within Tasks showing: meeting title, date, attendees, summary excerpt (400 chars), decisions list, and "Go to full meeting →". Eliminates the context-breaking tab jump.
- **Effort:** M | **Impact:** High | **Deps:** none

### 4-5: Meeting provenance strip on task detail (D3-6)
When `!item.isManual`, add a dismissable banner at top of `TaskPageView` and expanded `detailEditor`: "[🗓] From: [meetingTitle · date]" with "View meeting" link. Light NDS card with brand-color left border.
- **Effort:** S | **Impact:** Med | **Deps:** 4-4

### 4-6: Meeting source badge on Kanban cards and task rows (D3-2, D3-3)
Render a small icon badge (calendar icon for meeting-extracted, pencil for manual, L for Linear, N for Notion) on every task row and Kanban card. Use `ActionItem.source` and `isManual` (fields already exist).
- **Effort:** S | **Impact:** High | **Deps:** none

### 4-7: "All N in Tasks inbox" status bridge on meeting summary tab (P2-7)
In `MeetingSummaryTab.swift`'s `actionItemsSection`, replace the raw count with a dual state: "N in Tasks inbox — review →" (tappable, opens triage filtered to this meeting) or "All in Tasks ✓" once confirmed.
- **Effort:** S | **Impact:** Med | **Deps:** 4-1

### 4-8: Re-extract surface from triage empty state (P2-6)
In `TriageInboxView` inbox-zero state, add a visible "Re-extract from past meetings" button (currently buried in overflow menu).
- **Effort:** S | **Impact:** Med | **Deps:** none

---

## Phase 5 — Saved Views, Recurrence, & Power Features
*Asana/Notion parity gaps that matter most for a dual work+personal tracker.*

### 5-1: Saved Views — named, persisted, pinned to sidebar (P3-1, E1-3)
`SavedTaskView: Identifiable, Codable` wrapping `TaskQuery` + display name + optional emoji. Persisted to `saved_task_views.json`. Sidebar gets a collapsible "Views" section (below Smart Views). Toolbar gets "Save view" when any filter is active. Include 3 built-in system views: "My Open Tasks", "Overdue", "Due This Week". **`TaskQuery` is already `Codable` and designed for this** — this is pure plumbing + UI.
- **Effort:** M | **Impact:** High | **Deps:** 1-1 (for context-scoped views)

### 5-2: "My Tasks" rail item with Asana-style personal sections (P3-2)
Permanent "My Tasks" rail item. Pane shows 4 collapsible sections: Recently Assigned (7 days), Today (due today or user-pinned), Upcoming (2–14 days), Later. User drags tasks between sections to schedule. Fixed via `ownerPersonID` once the user links their own Person record.
- **Effort:** M | **Impact:** High | **Deps:** 5-1

### 5-3: Recurrence series UI — badge + "edit all future" dialog (P3-3)
- Add `repeat` icon to task rows and Kanban cards when `recurrence != nil`
- Add "Recurring" smart list to sidebar
- When editing a task with `seriesID`, show: "Change this task only / This and all future"
- Add custom interval input in `TaskPageView` recurrence picker (every 2 weeks, etc.)
- **Effort:** M | **Impact:** High | **Deps:** none

### 5-4: Task templates — global and per-project (P3-5, E1-7)
`TaskTemplate` model: name, default title prefix, priority, labels, subtask list, assignee, estimate, recurrence. Persisted to `task_templates.json`. Access via: "New task from template…" in project `+` menu; "Save current task as template" in `TaskPageView` context menu; QuickAdd keyword matching.
- **Effort:** M | **Impact:** High | **Deps:** 1-1

### 5-5: Extended GroupBy — by owner, label, project, initiative, custom select (P3-4)
Add `.owner`, `.label`, `.project`, `.initiative`, `.customSelect(propertyID)` to `GroupBy` enum. In "All Tasks" scope, add `.project` grouping. Store active `GroupBy` in per-project `AppSettings`.
- **Effort:** S | **Impact:** High | **Deps:** A0-1

### 5-6: Initiative target date + expanded project status (E1-4)
- Add `var targetDate: Date?` to `Initiative`
- Expand `Project.Status` to: `active, onHold, completed, archived`
- Both additive; old JSON decodes via `decodeIfPresent`
- **Effort:** S | **Impact:** Med | **Deps:** none

### 5-7: Field-level `TaskChangeEvent` with before/after values — unlocks undo (E1-5)
Add `field: String?` and `oldValue/newValue` to `TaskChangeEvent`. Capture before-snapshot in `update(_:mutate:)`. Add `undo()` on `ActionItemStore`. The changelog infrastructure is fully present — just hollow.
- **Effort:** M | **Impact:** High | **Deps:** none

### 5-8: Table view — column picker + custom property columns + inline editing (P3-7)
- Column picker popover (gear icon in table header): all standard fields + project custom properties
- Inline-editable cells for title and due date (double-click)
- Shift-click multi-select in table
- **Effort:** M | **Impact:** Med | **Deps:** 5-5

---

## Phase 6 — Optional / Platform Hardening

### 6-1: Sprint / Cycle primitive on Projects (P3-6)
`Sprint` struct: id, name, startDate, endDate, status. Persisted in project JSON. Task gets optional `sprintID`. Sprint grouping mode in list view. Sprint velocity in `TaskInsightsView`. S effort per sprint, M for full UI.
- **Effort:** L | **Impact:** Med | **Deps:** 5-5

### 6-2: Calendar drag-to-reschedule + start-date spans (P3-9)
Draggable calendar chips → `store.setDueDate`. Start-date "span" markers. Week-view toggle. Unscheduled tasks sidebar panel.
- **Effort:** M | **Impact:** Med | **Deps:** none

### 6-3: Property drawer slide-in panel (replaces in-place row expand) (D3-9)
Fixed 340px drawer sliding from right edge, anchored to the row. Row stays collapsed height. "Open full page" CTA inside drawer.
- **Effort:** L | **Impact:** High | **Deps:** A0-3

### 6-4: Write-ahead backup before each full-file save (E1-6)
In `TaskPersistenceCoordinator.writeNow`, rename existing file to `.bak` before write. Offer recovery on next launch if `.bak` is newer.
- **Effort:** S | **Impact:** High (data integrity) | **Deps:** none

### 6-5: Initiative completion arc in sidebar (D3-7)
Small progress ring next to each initiative name in sidebar using `progressForInitiative` (already computed). Hover tooltip: "12/20 tasks complete".
- **Effort:** S | **Impact:** Med | **Deps:** none

### 6-6: Keyboard sidebar navigation (D1-5)
`⌘1` focuses sidebar. Arrow keys move through rail items; `Return` selects; `Space` expands/collapses. Currently sidebar is a custom `VStack`, not a `List`, so no automatic focus ring.
- **Effort:** M | **Impact:** Med | **Deps:** A0-3

### 6-7: NavigationSplitView migration (E2-3)
Replace the manual `HStack + drag divider` in `ActionItemsView.body` with `NavigationSplitView`. Gets sidebar collapse, drag-to-resize, and accessibility for free.
- **Effort:** M | **Impact:** Med | **Deps:** A0-2, A0-3

---

## Build Order Summary

```
Phase 0 (Arch)  → A0-1, A0-2, A0-3, A0-4   (no visible changes, unblocks all)
P0 Bug fixes    → P0-1 through P0-5          (ship immediately, any order)
Phase 1         → 1-1 → 1-2, 1-3, 1-4, 1-5  (sequential: model first, then UI)
Phase 2         → 2-1 through 2-8            (parallel, all independent)
Phase 3         → 3-3 → 3-4, 3-6, 3-2 → 3-1, 3-5, 3-7, 3-8, 3-9, 3-10
Phase 4         → 4-1, 4-2, 4-3, 4-4 (parallel) → 4-5, 4-6, 4-7, 4-8
Phase 5         → 5-1 → 5-2, 5-3, 5-4, 5-5, 5-6, 5-7, 5-8
Phase 6         → 6-1 through 6-7            (optional, any order)
```

---

## Appendix — Findings Files

| Agent | File | Focus |
|---|---|---|
| D1 | `findings/D1_ia_navigation.md` | IA & Navigation |
| D2 | `findings/D2_interaction_speed.md` | Interaction & Speed |
| D3 | `findings/D3_visual_density.md` | Visual Design & Density |
| E1 | `findings/E1_data_model_store.md` | Data Model & Store |
| E2 | `findings/E2_ui_architecture.md` | UI Architecture |
| P1 | `findings/P1_hierarchy_org.md` | Hierarchy & Organization |
| P2 | `findings/P2_meeting_tasks_integration.md` | Meeting → Tasks |
| P3 | `findings/P3_feature_gaps_asana_notion.md` | Asana/Notion parity gaps |
| U1 | `findings/U1_daily_power_user.md` | Daily power user persona |
