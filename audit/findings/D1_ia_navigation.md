# Information Architecture & Navigation Findings — MeetingScribe Tasks Audit

**Role:** Senior Product Designer — IA & Navigation lens  
**ID prefix:** D1-

---

## Top existing friction points (file:line citations)

### 1. No persistent "home base" — landing is ad-hoc

`ActionItemsView.swift:25–26` sets `selectedProjectID = nil` as the default, meaning first-click into Tasks dumps the user straight into **All tasks** — a flat, unsorted, project-agnostic list. The Home sentinel (`__home__`) and the actual `tasksDashboard` view exist but are not the default landing. The one place that defaults to Home is the extracted `ActionItemsViewModel` (`ActionItemsViewModel.swift:99`: `var selectedProjectID = ActionItemsViewModel.homeSentinel`) — but this ViewModel is not yet wired to the live view. The two sources of truth are inconsistent, so the actual startup state is unpredictable.

### 2. The sidebar conflates two completely different contexts without visual separation

`ActionItemsSidebar.swift:56–137` stacks, in a single continuous `ScrollView`, the following in order:
- Smart views (Home, Triage inbox, All tasks, Unsorted tasks)
- People facet (conditionally rendered)
- Waiting-on (conditionally rendered)
- Initiatives (section header + tree)
- Pages (section header + tree)
- Meeting notes (collapsible)

There is no visual grouping between "smart system views" and "your actual work hierarchy." A new user cannot tell at a glance whether "Unsorted tasks" is a peer of "Initiative A" or something fundamentally different. This is not the same as Notion's or Linear's sidebar, where system views and user-created spaces have distinct visual regions or dividers.

### 3. "New page" button creates a Project, not a task — terminology confusion

`ActionItemsSidebar.swift:41–51`: The primary action button in the sidebar is labeled **"New page"** and calls `creating = true`, which via `commitNew()` at line 176 calls `store.createProject(name: n)`. The home dashboard (`ActionItemsChrome.swift:22`) also has "New page / Add to your workspace." The distinction between a Task and a Page/Project is never surfaced to the user. Someone who just wants to add a task has to find the small "+ New" button in the toolbar (`ActionItemsChrome.swift:371`), which is separated from the sidebar's "New page" action by the full width of the window.

### 4. Initiative → Project → Task hierarchy is not traversable as a breadcrumb trail

`ActionItemsView.swift:252–254` computes `taskBreadcrumb` as either the selected project name or "All tasks" — there is no Initiative tier in the breadcrumb. When inside a project that belongs to an initiative, there is no UI affordance showing "Initiative A / Project B" at the top of the pane. The user can only see hierarchy context by looking at the sidebar, which may be scrolled or collapsed.

### 5. The "Home" dashboard (`tasksDashboard`) does not surface today's work

`ActionItemsChrome.swift:9–105`: The dashboard shows "Open tasks (all, prefix 6)", "Pages (prefix 8)", and "Recent meeting notes (prefix 6)." It has no:
- Today's due tasks
- Overdue tasks highlighted
- Tasks due this week vs next week
- Any temporal signal beyond "open"

A user opening the app in the morning gets the same Home view whether it's a busy Monday or a completed Friday. There is no "focus mode" or "my day" framing.

### 6. Clicking a meeting in the sidebar causes a tab switch, not in-pane navigation

`ActionItemsView.swift:191–198`: When `selectedMeetingID` is set, the view fires `router.openMeeting(m)` and immediately clears `selectedMeetingID`. This jumps the user out of the Tasks tab entirely into the Meetings tab. There is no meeting-in-context view inside Tasks. For a user working from the meeting's action items back to the task list, this is a 2-click minimum to return.

### 7. `HomeTasksBoard` (home page Kanban) caps columns at 8 tasks each

`HomeTasksBoard.swift:76–80`: Each column shows `list.prefix(8)` and then a "+N more" label that is not tappable. There is no way to see the rest without switching tabs. The board also shows **all tasks across all projects mixed together** with no filtering by initiative or context (work vs personal).

### 8. WorkspaceRouter history does not include Tasks-internal navigation

`WorkspaceRouter.swift:80–85`: `NavState` stores `section`, `meetingID`, `personID` — but not `selectedProjectID`, `selectedTaskID`, or `selectedInitiativeID`. Back/forward navigation works at the tab level but loses all in-Tasks context: if you navigate Initiative → Project → Task → back, you land at the Tasks tab root, not the previous project.

---

## Existing items worth endorsing / prioritizing

**D1-4 (already commented in code):** The decision to route meeting sidebar taps to the canonical Meetings-tab detail (`ActionItemsView.swift:194–198`, comment "D1-4: one canonical meeting surface") is architecturally correct. Avoid reverting to a parallel meeting detail inside Tasks.

**TK-8 resizable sidebar:** `ActionItemsView.swift:46–47, 159–172` — persisted, draggable sidebar width is table stakes for a dense information tool. Good to have; should be kept.

**Collapsing Meeting notes by default:** `ActionItemsSidebar.swift:28` (`meetingNotesExpanded = false`) — correct call. Meeting notes are reference material, not a daily navigation destination.

**Triage inbox placement:** Having a dedicated `triageSentinel` rail item near the top (`ActionItemsSidebar.swift:60–62`) gives the meeting → task pipeline a clear, findable entry point. Worth keeping prominent.

---

## NET-NEW recommendations

### D1-1: Separate sidebar into two visually distinct zones — "My Work" and "System"

- **What:** Split the sidebar `ScrollView` into two regions with a clear visual divider: (1) **System** — Home, Today, Triage inbox, All tasks, Unsorted, People, Waiting-on; (2) **My Work** — Initiatives tree, Pages tree. Consider a fixed-height top zone for System and a scrollable bottom zone for My Work, like Linear's left rail.
- **Why:** The current flat list treats "Unsorted tasks" as visually equal to "Q3 Launch" initiative. Users build a mental model of "system filters" vs "my actual work" — the UI should reflect that split. Directly addresses Tyler's goal of better organization and clarity.
- **Effort:** M | **Impact:** High
- **Deps:** none

### D1-2: Add a "My Day / Today" smart view at the top of the sidebar

- **What:** A dedicated **Today** rail entry (distinct from the global Today tab) that scopes to: tasks due today, tasks marked as focus/do-today, and overdue tasks. It should be the default landing when entering the Tasks tab. Implement as a new sentinel constant (`__today__`) and a corresponding `todayPane` in the chrome, showing a sorted list with an "Overdue" header before "Due today."
- **Why:** The current Home dashboard (`tasksDashboard`) shows recent open tasks with no temporal framing (`ActionItemsChrome.swift:36–58`). There is no answer to "what do I work on right now?" This is the single most important daily-use surface for any task manager.
- **Effort:** M | **Impact:** High
- **Deps:** D1-1

### D1-3: Full Initiative → Project breadcrumb trail in the content pane header

- **What:** Replace `taskBreadcrumb` (`ActionItemsView.swift:252–254`) with a clickable multi-tier breadcrumb: `Initiative Name > Project Name > Task Title`. Each segment is tappable and navigates back up the hierarchy. The breadcrumb should appear in both `TaskPageView` and the `projectPane` header. If there is no initiative, show only the project segment.
- **Why:** Currently, once inside a task, the user has no way to know which initiative it belongs to without checking the sidebar. Navigating up requires using the sidebar, not an in-pane affordance. This closes the nav loop without sidebar dependency.
- **Effort:** S | **Impact:** High
- **Deps:** none

### D1-4: Work vs Personal context switching — top-level Workspaces or Spaces concept

- **What:** Introduce a "Space" or "Context" selector at the very top of the sidebar (above Home/Today), letting users switch between 2–4 named contexts (e.g., Work, Personal). Each Space has its own initiative/project tree. Switching Spaces filters the entire sidebar and task list. Store as a top-level array of `WorkspaceContext` objects (name, color, icon), each acting as a scope for initiatives. A "Show all" toggle lets cross-context views (All tasks, Today) span Spaces.
- **Why:** Tyler's explicit goal: "tasks shouldn't all be meshed together." The data model already has Initiatives but they are all rendered in a single flat list. Without a hard separation, Work and Personal initiatives visually merge. This is the highest-leverage IA change for the stated goal.
- **Effort:** L | **Impact:** High
- **Deps:** D1-1

### D1-5: Keyboard shortcut for sidebar focus + arrow-key navigation through items

- **What:** A single shortcut (e.g., `⌘1` or `⌥S`) focuses the sidebar. Arrow keys move through rail items; `Return` selects; `Space` expands/collapses an initiative. Currently `TaskShortcutsView` exists but sidebar keyboard navigation is absent (the sidebar is a custom `VStack`, not a `List`, so macOS focus ring doesn't apply automatically).
- **Why:** Getting to a project currently requires a mouse click on the sidebar, then potentially a second click to expand an initiative. Keyboard-first navigation is a native macOS expectation and directly reduces click count for power users.
- **Effort:** M | **Impact:** Med
- **Deps:** none

### D1-6: Extend WorkspaceRouter history to include Tasks-internal navigation

- **What:** Add `selectedTaskID` and `selectedProjectID` to `NavState` in `WorkspaceRouter.swift:81–85`. The router's `goBack()`/`goForward()` methods already coalesce state — extend them to also restore the Tasks tab's internal selection so back-navigation returns to the previous project or task, not the Tasks tab root.
- **Why:** Current back/forward (`WorkspaceRouter.swift:145–155`) only restores tab-level section. After navigating Task A → Task B, pressing Back lands the user on the Tasks tab with no selection — they must re-navigate to Task A. This breaks the mental model of "undo my last navigation."
- **Effort:** S | **Impact:** Med
- **Deps:** none

### D1-7: Pinned "Jump to project" command palette (⌘K style)

- **What:** A `⌘K` shortcut opens an inline omnibox (over the sidebar, floating) that searches across Initiatives, Projects, Tasks, and Meeting notes simultaneously. Items are grouped by type and show their parent hierarchy inline (e.g., "Q3 Launch / Website Redesign"). Selecting an entry navigates there. Distinct from global search — this is Tasks-scoped and navigation-only.
- **Why:** As the initiative/project tree grows, finding a project by scrolling the sidebar becomes slow. The existing search field (`ActionItemsChrome.swift:362–367`) filters only the current task list — it is not a navigation tool. Power users need to teleport, not scroll.
- **Effort:** M | **Impact:** High
- **Deps:** none

### D1-8: HomeTasksBoard — per-Space or per-Initiative column filter + tappable overflow

- **What:** Add a compact filter row above the Kanban columns in `HomeTasksBoard` letting the user scope to one Space or Initiative. The "+N more" text at `HomeTasksBoard.swift:80` should be a button that navigates to that status column in the full Board view in Tasks tab, pre-scoped to the same filter. Remove the hard cap of 8 or make it user-configurable.
- **Why:** Today's board mixes every task from every project. Work and personal tasks appear in the same column. The "+N more" is a dead end — there's no way to see those tasks without manually switching tabs and re-filtering.
- **Effort:** S | **Impact:** Med
- **Deps:** D1-4 (for Space filter); standalone tappable overflow is independent

---

## Top 3 picks

1. **D1-4 — Work vs Personal Spaces** — Tyler named this explicitly as a goal; without it, all other IA improvements are cosmetic because the underlying context collapse remains.
2. **D1-2 — Today smart view as default landing** — Replaces the purposeless All-tasks default with a daily-use anchor; this is the single highest-ROI change for daily use patterns.
3. **D1-7 — ⌘K project/task jump palette** — As the initiative tree grows, keyboard teleportation becomes the difference between a tool people use and one they abandon because navigation is slow.
