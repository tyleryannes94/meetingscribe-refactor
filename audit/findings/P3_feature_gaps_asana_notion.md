# Feature Gap Analysis vs Asana & Notion — MeetingScribe Tasks Audit
**Agent ID prefix: P3-**
**Auditor lens: Feature parity with Asana (2024–2025) and Notion (2024–2025), prioritized for a dual work+personal tracker**

---

## Top existing friction points (file:line citations)

### 1. No saved views / pinned filters anywhere in the codebase
`TaskQuery` is `Codable` and was designed for saved views (its own comment: "saved views (Phase 2) persist it" — `TaskQuery.swift:9`), but there is zero UI for creating, naming, or pinning a saved view. The sidebar (`ActionItemsSidebar.swift`) and the chrome toolbar (`ActionItemsChrome.swift`) have no "Save this view" affordance. Every time the user switches projects or restarts the app, all filter state resets. This is the single biggest parity gap against both Asana (saved sections + custom saved searches) and Notion (saved filters per database view).

### 2. Recurring task UX is model-only — no visibility in list/board/table
`RecurrenceRule` is complete (`Recurrence.swift:1–43`). The property chip lives in `TaskPageView` / `TaskMetaCluster` (confirmed grep hit at `TaskPageView.swift:162–169`). But:
- The list view `TaskRowView` / `ActionItemsListView.swift` never surfaces a recurrence badge on the row — a user looking at 30 tasks cannot tell which ones auto-respawn.
- The board `HomeTasksBoard.swift:87–119` shows no recurrence indicator on cards.
- There is no "Recurring tasks" rail bucket or filter shortcut. Asana and Things 3 both surface a dedicated "Recurring" or "Repeating" smart list.
- `seriesID` on `ActionItem` is never used in the UI — there is no way to "edit all future instances" (Asana's "This and all following" dialog). Users who change the title of one instance get a silent fork.

### 3. GroupBy options are limited and missing the most useful dimensions
`GroupBy` enum (`ActionItemsView.swift:137–149`) has: none, meeting, priority, status, dueDate. Missing from Asana/Notion standard groupings:
- **Assignee/Owner** — critical for work+personal split
- **Label/Tag**
- **Project** (cross-project "All tasks" view with project grouping is the most common power-user layout in Asana)
- **Initiative** (the top tier of the 3-tier hierarchy is never available as a group-by axis)
- **Custom property** (Notion's killer feature — group by any select/checkbox property)

### 4. Multi-select is buried behind a mode toggle, not gesture-driven
`taskSelectMode` (`ActionItemsView.swift:43`) requires clicking a "Select" button to enter a separate mode, then clicking individual circles. Asana and Notion both support shift-click range selection and cmd-click individual selection — no mode toggle required. The `taskSelectToolbar` (`ActionItemsListView.swift:182–228`) has bulk status, priority, project, and due date — but no bulk label assignment and no bulk section assignment.

### 5. Table view columns are fixed and can't be resized or toggled
`ActionItemsTableView.swift` defines static column widths in the `Col` enum (`ActionItemsTableView.swift:7–14`). There is no column picker, no drag-to-resize, and no way to show custom properties as columns. Notion's table view lets you show any property as a column. Asana's list view lets you show/hide fields per view. This is especially painful when using custom properties (which the model supports via `NP-1`).

### 6. HomeTasksBoard shows ALL tasks with no work/personal separation
`HomeTasksBoard.swift:17–25` pulls every non-triage task from the store, sorted only by sortIndex/createdAt. There is no initiative-scoping, no project filter, and no "My tasks only" toggle. For Tyler's explicit goal of separating work and personal tasks, the home board is currently noise. The `+8 more` truncation at line 79 means high-priority tasks can be invisible.

### 7. Calendar view is due-date only, read-only, and doesn't show start dates
`ActionItemsCalendarView.swift:93–98` filters strictly on `dueDate` — tasks with only a `startDate` don't appear. Tasks can't be drag-rescheduled on the calendar (tapping only opens the task page). Notion's calendar view supports drag-to-reschedule; Asana's timeline (Gantt) shows start-to-due spans. Even a simple drag-to-new-date would make the calendar useful.

### 8. No task templates
Neither `ActionItem.swift`, `ActionItemStore`, nor any UI file references templates. Asana has project templates and task templates with pre-filled fields, subtasks, and assignees. Notion has database templates. For recurring workflows (e.g., "weekly 1:1 prep task" always has 4 standard subtasks), there is zero shortcut — the user re-creates subtasks every time.

### 9. No sprint/cycle planning — `estimate` field is orphaned
`ActionItem.estimate` (`ActionItem.swift:98`) stores story points. `TaskInsightsView` exists (`ActionItemsView.swift:51`). But there is no sprint or cycle primitive — no way to scope a set of tasks to a time-boxed iteration, no velocity tracking, no "current sprint" rail item. Linear (which the app already syncs with) has Cycles; Asana has Sprints. Even a lightweight "Sprint" tag on a project section would close this gap.

### 10. "My Tasks" is imprecise and can't be customized
`ownerScope: .mine` (`ActionItemsView.swift:18`) uses `isMine()` which matches `AppSettings.shared.myNameAliases` (`ActionItemsListView.swift:318–322`). This is a text-match heuristic — if the alias list is wrong or empty, "My tasks" shows everything (unassigned = mine at line 320). There's no global "My Tasks" page in the sidebar like Asana's dedicated My Tasks view with its own sort order, sections (Recently Assigned / Today / Upcoming / Later), and custom layout independent of projects.

---

## Existing items worth endorsing / prioritizing

- **`TaskQuery` engine** (`TaskQuery.swift:1–214`) is the right foundation. It's `Codable`, composable, and pure. Building saved views on top of it is straightforward — the data layer is ready.
- **Multi-select bulk actions** (TK-3/TK-4) at `ActionItemsListView.swift:182–256` — the hard part (store mutations) is done. The UX just needs shift-click and label/section bulk ops added.
- **Custom properties per project** (`TaskProperties.swift`, `NP-1`) — already in the model. The missing piece is surfacing them as table columns and allowing GroupBy on select properties.
- **Triage inbox** — strong differentiator vs Asana/Notion. Worth keeping prominent in the sidebar and ensuring confirmed tasks land in the right project by default.
- **`estimate` + `TaskInsightsView`** — the velocity data is latent. Sprint planning would unlock it.

---

## NET-NEW recommendations

### P3-1: Saved Views — persisted, named, pinned to sidebar
- **What:** A `SavedView` model wrapping a `TaskQuery` + display name + optional emoji icon. Persisted to `saved_views.json`. Sidebar rail gets a "Views" section (collapsible, drag-to-reorder) below Initiatives. Toolbar gets a "Save view" button when any filter is active. Views are global (not per-project) so cross-project saved searches work. Include 3 built-in system views: "My Open Tasks", "Overdue", "Due This Week" — which also solve the work/personal split when scoped to an initiative.
- **Why:** `TaskQuery` is already `Codable` — this is almost entirely a UI build. It directly addresses Tyler's goal of Asana/Notion quality and faster navigation. Without saved views, every filter combination requires 4–5 clicks to recreate. This is the #1 parity gap.
- **Effort:** M (2–3 days) | **Impact:** High
- **Deps:** None (TaskQuery is ready)

### P3-2: "My Tasks" dedicated sidebar section with Asana-style personal sections
- **What:** A permanent top-level "My Tasks" rail item (above Initiatives) that opens a dedicated pane — not just an `ownerScope` filter. The pane has four collapsible sections: **Recently Assigned** (last 7 days, sorted by createdAt), **Today** (due today or pinned by user), **Upcoming** (due 2–14 days), **Later** (no due date or due 15+ days). User can drag tasks between sections to manually schedule. The `ownerScope.mine` filter is fixed via `ownerPersonID` (not the alias heuristic) once the user links their own Person record in settings.
- **Why:** This is the clearest separation between "work stuff assigned to me" and "personal items I created." Asana's My Tasks view is the most-used view for individual contributors. Today the closest equivalent is clicking "Anyone → Mine" in the chrome toolbar, which still dumps everything into a flat undifferentiated list. The data model already supports all four section types via existing fields.
- **Effort:** M (2 days) | **Impact:** High
- **Deps:** P3-1 (conceptually related but can ship independently)

### P3-3: Recurrence series UI — badge on rows + "edit all future" dialog
- **What:** (a) Add a recurring icon (SF Symbol `repeat`) to `TaskRowView` and `HomeTasksBoard` card when `item.recurrence != nil`. (b) Add a "Recurring" smart list to the sidebar rail (filter: `recurrence != nil`, scoped to confirmed tasks). (c) When the user edits title/due/assignee on a recurring task that has a `seriesID`, show a confirmation sheet: "Change this task only / This and all future tasks" — applying the latter propagates through the series via the store. (d) In `TaskPageView` recurrence picker, add custom interval input (every 2 weeks, every 3 months) beyond the current 4-option frequency picker.
- **Why:** The model is 100% ready (`Recurrence.swift`, `seriesID` on `ActionItem`). The UI gives no signal that a task repeats and provides no series editing. A user who edits "Weekly standup prep" unknowingly forks the series — this will cause silent data loss in practice. Things 3, Todoist, and Asana all surface recurring status prominently on the task row.
- **Effort:** M (2–3 days) | **Impact:** High
- **Deps:** None

### P3-4: Saved view + GroupBy additions — Assignee, Label, Project, Initiative
- **What:** Extend `GroupBy` enum with: `.owner`, `.label`, `.project`, `.initiative`, `.customSelect(propertyID: String)`. The last option renders a sub-menu in the GroupBy picker listing all select-type custom properties of the current project. In the "All Tasks" scope, add `.project` grouping (most-requested Asana-equivalent layout). Store the active GroupBy in the per-project `AppSettings` blob alongside `savedTaskViewMode`.
- **Why:** GroupBy by project in "All Tasks" is how power users get a "portfolio view" without leaving the task tab. GroupBy by initiative gives Tyler the work/personal separation he wants — Work Initiative vs Personal Initiative as top-level groupings. The current 5 GroupBy options miss these obvious axes.
- **Effort:** S (1 day) | **Impact:** High
- **Deps:** None (all data is on `ActionItem` already)

### P3-5: Task templates — per-project and global
- **What:** A `TaskTemplate` model: name, default title prefix, pre-filled priority, labels, subtask list (titles only), assignee, estimate, recurrence. Stored in `task_templates.json`. Access via: (a) "New task from template…" in the project header `+` menu; (b) a "Templates" section in the `TaskPageView` bottom panel; (c) QuickAdd parser: "standup prep" → matches a template by keyword and pre-fills. No complex form builder needed — just a "Save current task as template" button in `TaskPageView` context menu.
- **Why:** Tyler's work cadence almost certainly has repeating task shapes (sprint planning, weekly review, 1:1 prep). Currently each new instance requires manually re-adding the same 4–6 subtasks. Notion and Asana both solve this with templates. The subtask model (`Subtask` array on `ActionItem`) is already perfectly suited to store template checklist items.
- **Effort:** M (2–3 days) | **Impact:** Med–High
- **Deps:** None

### P3-6: Sprint / Cycle primitive on Projects
- **What:** Add a `Sprint` struct to `Project.swift`: `id`, `name`, `startDate`, `endDate`, `status` (planning/active/completed). A project can have multiple sprints. Tasks get an optional `sprintID`. In the project list view, a "Sprints" toggle in the toolbar switches the section grouping from manual sections to sprint buckets. `TaskInsightsView` gains a "Sprint velocity" panel showing points completed vs committed per sprint. Sprint creation: a "New sprint" button in the project sidebar section (like Linear's cycle button). This does NOT require backend changes — sprints are local JSON like everything else.
- **Why:** `estimate` (`ActionItem.swift:98`) is an orphaned field today. Sprint planning is the missing activation layer. Tyler is already syncing to Linear (which has Cycles) — naming this "Sprint" or "Cycle" makes it a meaningful local equivalent. Without a time-box primitive, the task tracker feels like a flat to-do list regardless of how many projects exist.
- **Effort:** L (4–5 days) | **Impact:** Med
- **Deps:** None (additive to existing Project model)

### P3-7: Table view — column picker + custom property columns + resize
- **What:** (a) A column picker popover (gear icon in table header) listing all standard fields + the current project's custom properties, with toggle checkboxes. (b) Drag-handle on column headers to resize — widths persisted per-project in AppSettings. (c) Inline-editable cells for title and due date (double-click to edit in place, no need to open full page). (d) Multi-select in table via shift-click row (no mode toggle needed).
- **Why:** The fixed 6-column table (`ActionItemsTableView.swift:7–14`) can't show custom properties despite the model supporting them (`NP-1`). Notion's database table is the gold standard here — every property is a column. Even Asana's list view lets you show/hide fields. For Tyler's work tasks, showing "estimate" and "sprint" columns alongside due date would make the table useful for planning.
- **Effort:** M (2–3 days) | **Impact:** Med
- **Deps:** P3-6 (sprint column only; rest is independent)

### P3-8: Home board — Initiative-scoped lanes + "Work vs Personal" toggle
- **What:** Add a segmented control above `HomeTasksBoard` columns: **All / Work / Personal / [custom initiative]**. Selecting "Work" filters the board to tasks in initiatives tagged as work context; "Personal" shows personal initiative tasks. The initiative tagging is a new boolean `isPersonal: Bool` on `Initiative`. Also: replace the `+8 more` truncation with a scrollable column (max-height capped, scrollable within the column) so no tasks are invisible.
- **Why:** `HomeTasksBoard.swift:17–25` currently floods the board with every task. Tyler's #5 goal is explicit work/personal separation. The home board is supposed to be the daily driver view — but mixed work and personal Kanban is unusable. This is a lightweight change: one filter and one field on `Initiative`.
- **Effort:** S (< 1 day) | **Impact:** High
- **Deps:** None

### P3-9: Calendar drag-to-reschedule + start-date spans
- **What:** (a) Make calendar task chips draggable — dropping on a new cell calls `store.setDueDate`. (b) Show a distinct "start" marker for tasks that have `startDate` (lighter tint chip on the start date). (c) Add a "week" toggle alongside the month navigator to show a 7-day agenda layout with time-blocked tasks. (d) Tasks with no due date appear in a floating "Unscheduled" sidebar panel to the right of the grid, drag-able onto the calendar to assign a date.
- **Why:** The current calendar is read-only and due-date-only (`ActionItemsCalendarView.swift:93–98`). Notion calendar and Asana timeline both support drag-to-schedule. The "Unscheduled" sidebar is a Notion original that is extremely useful for planning sessions — drag 5 tasks onto the calendar in 30 seconds vs opening each task page. `startDate` is already on the model (`ActionItem.swift:41`) but never rendered in the calendar.
- **Effort:** M (2–3 days) | **Impact:** Med
- **Deps:** None

---

## Top 3 picks

1. **P3-1 — Saved Views** — Closes the single biggest navigation gap (every filter is ephemeral today), directly enables the work/personal split via scoped saved searches, and the data layer (`TaskQuery` being `Codable`) is already built. Highest ROI per hour of effort in the entire gap list.

2. **P3-3 — Recurrence series UI** — The model is 100% complete but the UI is invisible. Recurring tasks that silently fork on edit will corrupt user data in practice. A recurrence badge on rows + "this and all future" dialog is a 2-day fix that prevents a trust-destroying bug and closes a major Asana/Todoist parity gap simultaneously.

3. **P3-8 — Home board work/personal toggle** — The home Kanban is Tyler's daily-driver view. Adding a single initiative-context filter + fixing the `+8 more` truncation (currently hides tasks) is a sub-1-day change that immediately delivers on the explicit work/personal separation goal without requiring any model changes.
