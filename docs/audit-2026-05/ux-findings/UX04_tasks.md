# UX04 — TASKS tab: initiatives, projects, pages, tasks & their connections

Senior PM lens, obsessed with low-lift wins. Surface: the Tasks tab — the
project rail, dashboard, task database (list/table/board), the Notion-style
task/project/initiative pages, and how fluidly tasks connect to meetings and
people. This pass builds *around and beyond* UX-B (the accepted "make
initiatives/pages/projects/tasks connected and fluid" anchor) — I do **not**
re-propose UX-B's headline; I propose the concrete adjacent wins that realize
it and push past it. The 3-click rule is applied within Tasks throughout.

The architecture is genuinely strong already: there's an Initiative › Project ›
Page › Section › Task hierarchy, a draggable Kanban, inline-editable rows, a
task-as-page view, project↔meeting linking, and Linear/Notion sync. The gaps
are at the **seams** — owner is free text not a Person, "from meeting" is dead
text, the rail can't reparent by drag, and there's no single "linked items"
home on a task.

---

## Lift from V4

Low-lift items already in V4 that land directly on this surface — re-surface, don't reinvent:

- **U1-1** — First-class **"Push to Linear" button on every task**, parity with the existing "Push to Notion" button (`TaskRowView.swift:304` `notionButton`, `TaskPageView.swift:78`). `createLinearIssue` already exists; the row/page just needs the second button. Lowest-effort IC win. (S)
- **D1-5** — **Bidirectional clickable person↔meeting↔task links everywhere.** Directly enables FT4-1/FT4-2 below; today task→meeting and task→owner are dead ends. (M)
- **D1-2 / D1-1** — `meetingscribe://` deep links + one canonical entity router. A task's "from meeting" / owner chip should resolve through the same router that opens a meeting or person elsewhere. (S/M)
- **D4-3** — **Universal undo (toast + UndoManager).** Tasks already does destructive moves (delete project, reparent, drag-between-columns `dropCard` at `ActionItemsBoardView.swift:84`) with zero undo. (M)

---

## UX improvements (5)

### UX4-1 — Make "From meeting" on a task clickable (kill the dead-end)
- **Friction today:** On the task page the source meeting renders as plain
  `Text(item.meetingTitle)` (`TaskPageView.swift:176-180`); in the row it's a
  non-interactive `Label` (`TaskRowView.swift:117-123`). Every task knows its
  `meetingID` but the user can't get from a task back to the meeting it came
  from — they must leave Tasks, go to Meetings, and search by title. That's
  4+ clicks for a "where did this come from?" that should be 1.
- **Fix:** Wrap the meeting chip in a `Button` that sets `selectedMeetingID`
  (the right pane already renders `MeetingNotesPage` for a selected meeting —
  `ActionItemsView.swift:124-127`), so the jump stays *inside* the Tasks tab.
- **Clicks:** 4+ → **1**.
- **Effort:** S.

### UX4-2 — Drag a page to reparent / move it under an initiative in the rail
- **Friction today:** The store already exposes `setProjectParent` (`ActionItemStore.swift:546`)
  and `setProjectInitiative` (`:405`), but the rail (`ProjectRail` /
  `PageTreeNode` / `InitiativeNode`) offers **no drag**. To move a page under
  an initiative you must open the page → open the initiative menu in `metaRow`
  (`ActionItemsProjectPage.swift:72`) → pick — and there is no way at all to
  reparent a page under another page except deleting and recreating. Reorder
  among siblings is impossible.
- **Fix:** Add `.draggable(project.id)` to `PageTreeNode.row` and
  `.dropDestination(for: String.self)` on page rows and initiative nodes,
  routing to `setProjectParent` / `setProjectInitiative`. Mirrors the pattern
  already shipping for tasks (`sectionGroup` drop at `ActionItemsListView.swift:58`,
  board `dropCard` at `ActionItemsBoardView.swift:84`).
- **Clicks:** 3 (open page → menu → pick) → **1 drag**.
- **Effort:** small-M.

### UX4-3 — Full breadcrumb trail on every page (not just one hop)
- **Friction today:** Only `TaskPageView` has a breadcrumb, and it's a single
  hop — `breadcrumb` is just the project name or "All tasks"
  (`ActionItemsView.swift:145-148`, rendered `TaskPageView.swift:61`). A task
  nested Initiative › Project › Sub-page › Task shows "‹ ProjectName" only;
  the project/initiative pages (`ProjectPageHeader`, `InitiativePage`) have **no**
  breadcrumb at all. The user loses their place in the hierarchy and can't
  climb it in one click.
- **Fix:** Build the breadcrumb from the parent chain
  (`Initiative › Project › Sub-page › Task`), each segment a button that sets
  the matching `selected…ID`. The lookups (`store.initiative(id:)`,
  `store.project(id:)`, `childProjects(of:)`) already exist.
- **Clicks:** climbing 2 levels: rail-hunt (2–3) → **1** per hop.
- **Effort:** small-M.

### UX4-4 — Inline create-and-link for owner & project from the row (typeahead)
- **Friction today:** Setting an owner means expanding the row's detail editor
  (`TaskRowView.swift:351`) and free-typing into a `TextField` — no list of
  known people, no consistency, typos fork the same person. "Move to project"
  is a nested menu (`TaskRowView.swift:148`); creating a *new* project to link
  is buried as "New project named …" (`:155`).
- **Fix:** Replace the owner free-text and the project submenu with a single
  combobox/typeahead popover that lists existing People (for owner) / Projects,
  filters as you type, and offers "Create ‹typed name›" inline — one control
  that both *creates* and *links*. (Owner-as-Person depends on FT4-2; project
  side ships immediately.)
- **Clicks:** owner-set 2 (expand → type) and project-create 3 (menu → submenu
  → confirm) → **1** popover with typeahead.
- **Effort:** small-M.

### UX4-5 — Persist view mode + filters per page, and surface the rail toggle
- **Friction today:** `viewMode`, `filter`, `priorityFilter`, `groupBy` are
  plain `@State` on `ActionItemsView` (`ActionItemsView.swift:13-37`) — they
  reset to `.list` / `.all` every time the tab is rebuilt and are shared across
  *all* projects, so a project you set up as a Board reverts to List on return,
  and switching projects silently carries the previous project's filter. There
  is also no obvious affordance to collapse the 230px rail
  (`ActionItemsView.swift:110`) on a small window.
- **Fix:** Persist `viewMode`/`filter` keyed by project id (a small
  `[projectID: ViewMode]` in the store or `@AppStorage` dict); add a rail
  collapse toggle. Each project remembers how you last looked at it.
- **Clicks:** re-selecting view+filter on every visit (2–3) → **0** (sticky).
- **Effort:** S.

---

## Feature improvements (5)

### FT4-1 — "Linked items" block on every task page (meetings · people · related tasks)
- **What/why:** A task today has scattered, read-only references: a `meetingID`,
  a free-text `owner`, a `projectID`. There's no single place that shows
  *everything this task connects to*, and nothing is clickable. Add one
  "Linked" section on `TaskPageView` (below Properties) listing the source
  meeting, linked people, and sibling tasks from the same meeting — each a
  navigable chip.
- **User value:** Turns a task into the hub the rest of the audit's
  connectivity promise implies; one screen answers "who, which meeting, what
  else came out of it."
- **Effort:** small-M (M if it also writes back-links).
- **Dependency:** FT4-2 (people), D1-5 (clickable links).

### FT4-2 — Link a task owner to a Person in the CRM in ≤2 clicks
- **What/why:** `ActionItem.owner` is a `String?` (`ActionItem.swift:23`) and
  `setOwner` takes a string (`ActionItemStore.swift:502`) — owners are never
  the People entities the app already maintains. Add an optional
  `ownerPersonID` and an assignee picker that searches People (with
  "create person" fallback). Render the owner chip as a link to the person.
- **User value:** "Show me everything Alice owes me" becomes possible; owners
  stop fragmenting on spelling; powers per-person task rollups and the brief.
- **Effort:** small-M.
- **Dependency:** People store read access; FEAT-A/B people work.

### FT4-3 — One-click "Create task" from a meeting / link existing tasks to a meeting
- **What/why:** A project can link meetings (`linkMeeting`,
  `ActionItemsProjectPage.swift:91`) but the reverse — making a task straight
  from a meeting and pre-filling its `meetingID`/`meetingTitle` — has no button.
  `MeetingNotesPage` lists extracted items (`:307`) but offers no "+ Add task
  from this call." Add an "Add task" button on `MeetingNotesPage` that creates
  an item already stamped to that meeting.
- **User value:** Captures the follow-ups the extractor missed, in context,
  without leaving the meeting page.
- **Effort:** S.

### FT4-4 — "My open work" smart view (assignee + overdue), pinned in the rail
- **What/why:** The rail has Home / All tasks / Unsorted (`ProjectRail` at
  `ActionItemsSidebar.swift:46-53`) but no "assigned to me" or "overdue"
  pinned view; the filters exist (`Filter.overdue`, `.thisWeek` in
  `ActionItemsView.swift:54`) but reset and aren't reachable from the rail.
  Add a pinned "My work" rail item (owner == me, sorted overdue-first).
- **User value:** The single most-used PM query — "what's on my plate now" —
  in 1 click from entering the tab.
- **Effort:** S (small-M once tied to FT4-2's `ownerPersonID`).

### FT4-5 — Convert a task into a project / promote a subtask to a task
- **What/why:** Work grows. A task with many subtasks (`Subtask` list,
  `ActionItem.swift:125`) often *is* a mini-project, but there's no path to
  promote it — and no path to spin a project off a task. Add "Convert to
  project" on the task `…` menu (creates a Project, moves subtasks → tasks,
  links it back) and "Promote to task" on each subtask row
  (`TaskPageView.swift:248`).
- **User value:** The hierarchy flexes with reality instead of forcing
  delete-and-rebuild; keeps history/links intact.
- **Effort:** small-M.

---

## Top 3 picks

1. **UX4-1 — clickable "From meeting"** (S). Highest value-to-effort: every
   task already carries `meetingID`; wrapping one `Text` in a `Button` collapses
   a 4-click hunt to 1 click and is the smallest possible down-payment on the
   whole "connected" thesis. **This is the single highest-value low-lift win.**
2. **UX4-2 — drag-to-reparent pages in the rail** (small-M). The store method
   (`setProjectParent`) already exists; this is pure UI and removes the only
   truly painful gap in the hierarchy (you currently cannot move a page at all).
3. **FT4-2 — task owner → Person link** (small-M). Unlocks per-person task
   rollups, FT4-1, FT4-4, and the brief; converts free-text owners into the
   real graph the rest of the app already has.
