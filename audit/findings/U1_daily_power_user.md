# Daily Power User Findings — MeetingScribe Tasks Audit

**Persona:** The Daily Power User — uses MeetingScribe Tasks every single workday,
50–200 tasks live at any time, moves fast, loses patience with anything that
takes more than one click or one keystroke.

---

## A Typical Morning Narration

It's 8:47 AM. I open MeetingScribe and land on the Tasks tab. The dashboard
(`ActionItemsChrome.swift:8`) shows me "Open tasks" capped at 6 (`prefix(6)` at
line 37), "Pages" capped at 8, and "Recent meeting notes." That's it. With 120+
tasks live, the dashboard is useless — I can already see that three high-priority
things I need to action today aren't in the visible six. I have no idea what's
overdue without clicking through to "Overdue" in the toolbar. The Kanban board on
the Home page (`HomeTasksBoard.swift:77`) caps each column at 8 cards with a "+N
more" label that isn't clickable — it just taunts me.

I need to add five tasks I thought of on my morning commute. I hit ⌥⌘N for the
quick-add popover (`ActionItemsChrome.swift:373`). Good — it stays open after
each submit so I can type back-to-back. But I can't tab-assign a project, set
priority, or set a due date without leaving the popover. The natural-language
parser (`commitQuickAdd:463`) handles `!high` and `#label` but not `@ProjectName`
scoping to a specific project. I end up in the list view after closing the popover
and doing five separate clicks to assign projects.

Now I want to triage what's actually urgent today. I click "Overdue" in the
toolbar. I get a flat list — no grouping by project, so my work tasks and personal
tasks are interleaved. I have a "Work" initiative and a "Personal" initiative but
the sidebar (`ActionItemsSidebar.swift:56`) puts them in a collapsible section
below Home, Triage inbox, All tasks, Unsorted tasks, People, and Waiting-on. To
get to my Work project I scroll past five fixed items, past the People section,
past Waiting-on, then click the Initiative to expand it, then click the Project.
That's 4–6 clicks every single morning.

I right-click a task to mark it done — the context menu works (`TaskRowView.swift:73`).
Good. But I can't select multiple overdue tasks and batch-reschedule them with a
keyboard shortcut; I have to click "Select" in the toolbar, wait for checkboxes to
appear, click each task, then use the "Due" menu. No ⌘-click multi-select.

At 9:15 I finish a meeting. I go to the Triage inbox. The items from the meeting
show up — but there's no way to bulk-accept all of them with one click, or to
quickly assign a project to the whole batch before confirming. I have to open each
item, assign a project, then accept. With 8 action items from a 1-hour standup,
this takes 3–4 minutes.

By 10 AM I've opened Notion for the third time this week to look at my project
kanban because the board view here doesn't remember which project I was in — every
time I switch away and come back, it resets to "All tasks" board mode instead of
staying in my Work project board.

---

## Top Existing Friction Points (file:line citations)

### F1 — Dashboard caps at 6 open tasks, no "Today" or "Due today" section
`ActionItemsChrome.swift:37` — `prefix(6)` on `store.openItems()` with no "See
all" link and no date-aware grouping. A power user with 120+ tasks sees a random
6. There is no "Due today" or "Overdue" section anywhere on the dashboard.

### F2 — Home Kanban caps columns at 8 non-clickable "+N more"
`HomeTasksBoard.swift:77` — `list.prefix(8)` with a dead `"+\(list.count - 8) more"`
text label. Power user can't see or interact with the rest of the column.

### F3 — Quick-add popover has no project/due-date inline field
`ActionItemsChrome.swift:450–461` — The popover accepts `!priority` and `#label`
via NLP but the placeholder shows no `@project` syntax. There is no `due:today`
or `@ProjectName` support in `TaskQuickAddParser`. After batch-adding 5 tasks,
every one needs a manual project assignment.

### F4 — No ⌘-click or shift-click multi-select in the list view
`ActionItemsListView.swift:163–177` — Multi-select requires clicking a "Select"
button to enter a separate mode. Standard macOS ⌘-click and shift-click are not
wired. "Select" button is at the very top of the list, requiring upward scroll to
reach it.

### F5 — Sidebar puts Initiatives behind 5+ fixed items every session
`ActionItemsSidebar.swift:56–79` — Fixed rail items (Home, Triage inbox, All
tasks, Unsorted tasks, People, Waiting-on) always appear above the Initiatives
tree with no way to pin a project to the top. For someone who lives in 2–3
projects, this is 3–4 clicks every navigation.

### F6 — Triage inbox has no batch-accept or batch-assign-project flow
No file exposes a bulk confirm path. Each meeting action item requires individual
open → assign project → confirm. 8 items from a meeting = 8 full round trips.

### F7 — Board view does not persist project context across tab switches
`ActionItemsChrome.swift:225–235` — `taskDatabasePane` resolves `realSelectedProjectID`
on each render, but there is no persistence of `selectedProjectID` across tab
navigation. Switching to Meetings and back resets to global board.

### F8 — "This week" filter is creation-or-due-date based, not "work due this week"
`ActionItemsListView.swift:280–285` — A task created this week appears in "This
week" even if it isn't due until next month. Counter-intuitive: I want tasks DUE
this week, not tasks I happened to create this week.

### F9 — No "Today" smart list / Today view of any kind
The toolbar chips are `All / My open / This week / Overdue / Delegated`
(`ActionItemsChrome.swift:315–327`). There is no "Today" chip or smart list for
tasks due or started today. Overdue catches yesterday and earlier; This week is
noisy. A daily power user opens tasks every morning wanting "what do I do TODAY."

### F10 — Work / Personal context completely invisible at the global level
`ActionItemsChrome.swift:271–274` — The header stats (`Open / In Progress / Done`)
are global across all initiatives with no work/personal breakdown. The dashboard
shows a flat pool. With 80 work tasks and 40 personal tasks, there's no at-a-glance
separation.

---

## Existing Items Worth Endorsing / Prioritizing

- **⌥⌘N quick-add with stay-open behavior** (`ActionItemsChrome.swift:475`) — good pattern, just needs project + date inline support
- **j/k keyboard navigation in list** (`ActionItemsListView.swift:136–137`) — correct macOS power-user affordance, needs more surface coverage
- **Triage inbox pattern** (`ActionItemsSidebar.swift:59–62`) — the right model; needs bulk-confirm UX on top of it
- **Bulk actions bar** (`ActionItemsListView.swift:182–228`) — already wired for status/priority/project/due/delete; great foundation; needs ⌘-click to reach it without entering "Select" mode
- **`waitingSection` / Delegated chip** — useful for a power user's daily review

---

## NET-NEW Recommendations

### U1-1: "Today" Smart View — Due Today + Overdue in One Place
- **What:** Add a "Today" smart list as a permanent top-level rail item (between Home and Triage inbox) and a toolbar chip. It shows: overdue tasks first (red), then tasks due today, then tasks started today with no due date. Grouped by Initiative/Project. Not just a renamed filter — it should include a morning "catch-up" count badge on the rail item that resets when the user visits.
- **Why:** The single most-frequent daily entry point for a power user is "what do I need to do today." Currently requires 3 clicks (Overdue, then This week, manually triangulate). This is table stakes in Asana, Things 3, and Linear.
- **Effort:** S | **Impact:** High
- **Deps:** none

### U1-2: Inline Project + Due-Date in Quick-Add Parser
- **What:** Extend `TaskQuickAddParser` to recognize `@ProjectName` (fuzzy match against `store.projects`) and `due:today / due:friday / due:next-week`. Surface the `@` syntax in the popover hint text. Auto-route the created task into that project without any follow-up click.
- **Why:** F3 above. Batch-creating tasks is the second most-frequent daily action. Leaving the popover to assign projects kills momentum. The parser already handles `!priority` and `#label` — extending it to `@project` is incremental.
- **Effort:** S | **Impact:** High
- **Deps:** none

### U1-3: ⌘-Click / Shift-Click Native Multi-Select
- **What:** In `ActionItemsListView`, wire `.onTapGesture(modifiers: .command)` and `.onTapGesture(modifiers: .shift)` on each row to add/range-add to `taskSelection`, and automatically show the bulk action bar whenever `taskSelection` is non-empty — without requiring the user to click "Select" first. "Select" mode button becomes a "select all" affordance instead.
- **Why:** F4. Standard macOS convention that power users muscle-memory. The bulk action infrastructure already exists (`ActionItemsListView.swift:182`); this just adds the entry point.
- **Effort:** S | **Impact:** High
- **Deps:** none

### U1-4: Pinned Projects Rail — Drag-to-Pin Any Project to the Top 3 Slots
- **What:** Add a "Pinned" section at the top of `ProjectRail` (above Home). Drag any project or initiative from the tree into pinned slots (max 3). Persisted in `AppSettings`. On launch, clicking a pinned project navigates directly to it — zero scrolling, zero expanding.
- **Why:** F5. The daily power user lives in 2–3 projects. The current sidebar forces a 4–6 click navigation every morning. Every professional task manager (Asana, Linear, Notion) supports some form of favorite/pinned views.
- **Effort:** M | **Impact:** High
- **Deps:** none

### U1-5: Triage Batch-Confirm with One-Click Project Assignment
- **What:** In the Triage inbox, add a "Confirm all to project…" button at the top that pops a project picker, then marks all pending triage items as confirmed and assigns them to that project in one action. Also add ⌘-A to select-all triage items, then assign + confirm the selection.
- **Why:** F6. 8 action items from a standup currently = 8 manual round trips. A whole meeting's worth of items almost always belongs to one project. This mirrors Asana's "Accept all" in inbox.
- **Effort:** M | **Impact:** High
- **Deps:** none

### U1-6: Context-Aware Dashboard — "Your Day" Section with Initiative Breakdown
- **What:** Replace the current dashboard's generic "Open tasks" `prefix(6)` section (`ActionItemsChrome.swift:36–59`) with a "Your day" section showing: overdue count, due today, in-progress — each as a clickable row grouped under the task's Initiative badge. Below that, keep the Pages section but add an "Initiative summary" widget: two columns (Work initiatives / Personal initiatives) with open counts. Remove the hard cap of 6/8 items.
- **Why:** F1, F10. The dashboard is meant to orient you at the start of the day. A power user with 120+ tasks across work and personal initiatives gets zero useful signal from a random 6-item list. This is the #1 reason users abandon to Notion.
- **Effort:** M | **Impact:** High
- **Deps:** U1-1

### U1-7: Fix "This Week" to Mean "Due This Week" Only
- **What:** In `ActionItemsListView.swift:280–285`, remove the `createdThisWeek` branch from the `thisWeek` filter. "This week" should mean `dueDate` falls in the current week window, not `createdAt`. Add a separate chip or sub-filter "Created this week" if that view is wanted.
- **Why:** F8. A task I created on Monday but due in 6 weeks has no business appearing in "This week." It pollutes the view and destroys trust in the filter.
- **Effort:** S | **Impact:** Med
- **Deps:** none

### U1-8: Persistent View Context Across Tab Switches
- **What:** Store `selectedProjectID` and `viewMode` in `ActionItemsViewModel` as `@AppStorage` (or in `AppSettings`) so they survive tab switching. When the user returns to Tasks, they land on the same project/view they left.
- **Why:** F7. Today every tab switch resets context. For a power user who switches between Meetings and Tasks 20 times a day, re-navigating to their project each time is a serious friction cost.
- **Effort:** S | **Impact:** Med
- **Deps:** none

### U1-9: Clickable "+N More" on Home Kanban Board
- **What:** In `HomeTasksBoard.swift:77–79`, make the `"+\(list.count - 8) more"` text a tappable `Button` that deep-links into the Tasks tab in Board view, filtered to that column's status and expanded to show all items. Remove the hard 8-card cap or make it configurable (user drags the board taller).
- **Why:** F2. A Kanban board that doesn't show all cards is a progress meter, not a task board. The "+N more" label actively misleads — it implies you know what's there but can't touch it.
- **Effort:** S | **Impact:** Med
- **Deps:** none

### U1-10: Work / Personal Namespace — Initiative-Level Color Coding Throughout
- **What:** Add an optional "context" field to Initiative (e.g., `work` vs `personal` vs `custom`). Surface this as a colored left-border or background tint on every task row, every Kanban card, and in the header stats breakdown (`ActionItemsChrome.swift:272–274`). In the dashboard, split the "Open tasks" section into two swimlanes by context. In the sidebar rail, show context color dots next to initiative names.
- **Why:** F10. Work and personal tasks are fundamentally different contexts that should never feel like the same pool. Every power user eventually resorts to labeling everything "work" or "personal" manually — this bakes the separation in structurally.
- **Effort:** M | **Impact:** High
- **Deps:** none

---

## Top 3 Picks

1. **U1-1 (Today Smart View)** — Highest daily-use impact; zero today-focused entry point currently exists; S effort.
2. **U1-6 (Context-Aware Dashboard)** — The dashboard is the first thing seen every morning; replacing the useless 6-task cap with an actionable "Your Day" view is the single biggest quality-of-life jump.
3. **U1-2 (Inline @project in quick-add)** — Every back-to-back task creation session ends with manual project-assignment cleanup; this closes that loop in the parser with minimal scope.
