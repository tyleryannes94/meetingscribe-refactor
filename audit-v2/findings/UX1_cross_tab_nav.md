# Information Architecture & Cross-Tab Navigation Findings — MeetingScribe v2 Audit

**ID prefix:** UX1-  
**Auditor lens:** How users move between all 5 tabs, global search quality, deep links, back-navigation, and whether the app feels like one brain or 5 silos.

---

## Top friction points / gaps (file:line citations)

### 1. Task → Source meeting requires 3 interactions, not 1
`TaskPageView.swift:377–385` shows a deliberate design choice: clicking a task's "From meeting" link opens a *popover peek*, not the meeting itself. That peek has a secondary "Open Full" button (`openSourceMeeting` at line 538–539). So the path is: Tasks tab → task detail → click "From meeting" → popover → click "Open Full" → Meetings tab. That's 4 clicks from a task row in the sidebar to the meeting detail. It should be 2 (task row → meeting detail with back-link).

### 2. Person → Their tasks: zero direct path
`PersonDetailView.swift:1337` links from a person's timeline to their meetings via `router.openMeeting`. But there is **no** "open tasks owned by this person" cross-link anywhere in `PersonDetailView.swift`. A person with 8 open action items from their owner field (`ownerPersonID`) can only be reached by going to Tasks, filtering, and searching — not from the person card. `WorkspaceRouter.swift:65` defines `pendingTaskID` but no `pendingPersonFilter` for the Tasks pane.

### 3. Meeting → Attendee tasks: buried two levels deep
From the `UnifiedMeetingDetail`, clicking an attendee chip (`MeetingDetailHeader.swift:884`) opens the person in People. From People, tasks are invisible. The connection `meeting → attendee → open tasks for that person` does not exist as a shortcut. The `MeetingPersonConnectPanel.swift:131` shows person links but no task count or link to Tasks filtered by owner.

### 4. ⌘K lands on the entity but loses context
`GlobalSearchView.swift:400–408`: searching "project kickoff" and selecting a task opens the Tasks tab via `pendingTaskID`, but the search query is NOT carried to the Tasks tab (only `pendingTranscriptQuery` exists for meetings, `WorkspaceRouter.swift:59`). The user lands at the task with no "you came from search" breadcrumb, no highlighted query, and back-nav returns to the last section, not the search palette.

### 5. ⌘K empty state is meeting-centric
`GlobalSearchView.swift:259–266`: empty query shows the 8 most recent meetings for `.all` and `.meetings` filters. There is no "recently visited" cross-entity list — a person you just opened, a task you just edited, or a voice note you just recorded does not appear. The palette is effectively a meeting-jump shortcut unless you type.

### 6. WorkspaceRouter has no task→person→meeting chain
`WorkspaceRouter.swift:229–256`: `.actionItem` and `.project` routes just do `section = .actions` with no ID routing (lines 241–243). An `openTask(id:)` method exists only as `pendingTaskID` — the task pane consumes it — but there is no equivalent `openProject(id:)`. You can navigate to a task from outside Tasks, but not to a project.

### 7. Calendar-only meetings in Person timeline are dead-ends
`PersonDetailView.swift:1339–1342`: calendar-only meetings are rendered as non-interactive rows (`timelineRowContent(m, recorded: false)` with no button wrapper). There is no way to "view in calendar" or see other attendees from that row. An unrecorded 1:1 on the timeline is visually present but totally inert.

### 8. Back/forward history does not capture People sub-panel state
`WorkspaceRouter.swift:93–108`: `NavState` captures `meetingID`, `personID`, and `TasksSelection`, but nothing for People's internal tab selection (Meetings sub-tab, Graph view, Keep-in-touch board, analysis panel). Going back to a person always lands on their default tab, not where you left off.

### 9. No "related entities" surface at meeting level
`UnifiedMeetingDetail` (confirmed from `MeetingSummaryTab.swift` and `MeetingDetailHeader.swift` references) shows attendees and action items, but there is no unified "also related" panel showing: which project this meeting is linked to, which decisions are connected, or which voice notes were taken the same day. The data relationships exist (e.g. `project.meetingIDs` from `ActionItemsProjectPage.swift:168`) but are not surfaced in the meeting view.

### 10. Voice Notes tab is fully isolated
`GlobalSearchView.swift:330`: voice notes only appear in ⌘K under the `.voiceNotes` filter or `.all`. `TodayView.swift` shows recent voice notes only in the collapsed "More" section. There are no voice note backlinks anywhere in People or Meetings views. A voice note taken before a meeting is invisible to that meeting's detail.

---

## Existing items to endorse (from prior plan or codebase)

- **Browser-style back/forward** (`WorkspaceRouter.swift:116–206`): already implemented and wired to toolbar buttons. Solid foundation — needs to be extended to People sub-state (UX1-8 above).
- **`in:` qualifier syntax** (`GlobalSearchView.swift:233–249`): `in:meetings pricing` is a clean power-user affordance. Worth documenting in a tooltip.
- **Meeting peek panel from task** (`TaskPageView.swift:384`): the popover peek is a good interaction pattern — it prevents tab-switching for a quick glance. The gap is that "Open Full" should be click 1, not click 3 from the task row.
- **`pendingTranscriptQuery`** (`WorkspaceRouter.swift:59`): carrying the search query into the meeting transcript pre-highlighted is excellent. The same pattern should be applied to Tasks and People.
- **Person timeline with recorded meeting backlinks** (`PersonDetailView.swift:1337`): the `router.openMeeting` integration already works; the gap is its narrowness (no tasks, no decisions, no voice notes in the timeline).

---

## NET-NEW recommendations

### UX1-1: Relational Context Strip ("Related to this")
- **What:** A collapsible "Related" strip at the bottom of every meeting detail, person detail, and task detail. The strip auto-populates from the existing data graph: for a meeting, show linked project(s), attendees' open tasks, and voice notes from the same day. For a person, show their open tasks (filtered by `ownerPersonID`) and their co-attendee frequency. For a task, show the source meeting (1-click) and the assignee's person card (1-click).
- **Why (second-brain angle):** The data relationships already exist in the model — `meetingID` on tasks, `ownerPersonID`, `project.meetingIDs` — but they are invisible at the point of use. A strip makes the graph tangible without requiring the user to navigate away.
- **Cross-feature connections:** Meetings ↔ Tasks ↔ People ↔ Voice Notes
- **Effort:** M | **Impact:** High
- **Deps:** none — all data is in-memory

### UX1-2: "Jump to" keyboard shortcuts from anywhere
- **What:** When viewing a task, `⌘⏎` opens its source meeting. When viewing a meeting, `⌘P` opens the first attendee, `⌘T` jumps to the triage inbox filtered to this meeting's tasks. When viewing a person, `⌘T` opens Tasks filtered by `ownerPersonID == person.id`. These are single-chord, context-aware escape hatches.
- **Why (second-brain angle):** Keyboard-first users should never have to reach for the mouse to traverse the graph. The router already supports all these destinations — what's missing are the keybindings that activate them.
- **Cross-feature connections:** All 5 tabs; WorkspaceRouter already handles the routing logic
- **Effort:** S | **Impact:** High
- **Deps:** UX1-1 (the related strip makes the destinations visible before the shortcut fires)

### UX1-3: ⌘K "Recently visited" cross-entity history
- **What:** When ⌘K opens with an empty query, show a "Recently visited" section — the last 12 entities (any kind: meetings, people, tasks, projects, voice notes) the user actually opened, sorted by visit time. Pull from `WorkspaceRouter`'s `backStack` history, which already captures section + meetingID + personID + TasksSelection per entry.
- **Why (second-brain angle):** The current empty state (8 recent meetings) makes ⌘K a meeting-picker disguised as a universal palette. Cross-entity recency makes it a true second-brain launcher — the app remembers your last context, not just your last recording.
- **Cross-feature connections:** WorkspaceRouter history → GlobalSearchView; touches all entity kinds
- **Effort:** S | **Impact:** High
- **Deps:** none; `backStack` data is already available

### UX1-4: Person tab → Tasks filtered view (1-click)
- **What:** Add an "Open tasks" button on PersonDetailView (next to the existing meetings timeline), which calls `router.openTasks` with a new `ownerFilter: personID` sentinel. `ActionItemsView` consumes it and applies an owner filter without requiring the user to manually set one.
- **Why (second-brain angle):** A person's record is the right place to ask "what do I owe them / what do they owe me?" That question currently requires 3+ manual steps in the Tasks tab.
- **Cross-feature connections:** People → Tasks; reuses `pendingTasksRoute` pattern from `WorkspaceRouter.swift:65–76`
- **Effort:** S | **Impact:** Med
- **Deps:** none

### UX1-5: Voice Notes ↔ Meetings timeline bridge
- **What:** When a voice note was created within ±2 hours of a meeting, show it as a linked item in the meeting's detail ("Voice note taken during this meeting"). Conversely, on a voice note's detail, show any meeting from the same ±2h window. The link uses `router.open` and deep-links bidirectionally.
- **Why (second-brain angle):** Voice notes are the highest-signal content a user produces — they're what you scribble *during* a call. Yet they are completely invisible to the meeting they annotate. Surfacing this connection turns a filing cabinet into a coherent record.
- **Cross-feature connections:** Meetings ↔ Voice Notes; `QuickNotesView` ↔ `UnifiedMeetingDetail`
- **Effort:** M | **Impact:** Med
- **Deps:** none; date comparison uses existing `createdAt` and `startDate` fields

### UX1-6: ⌘K search-query passthrough to Tasks and People tabs
- **What:** Mirror the existing `pendingTranscriptQuery` pattern (`WorkspaceRouter.swift:59`) for Tasks and People. When the user selects a task from ⌘K, carry the query into the Tasks tab and pre-highlight it in the task detail. When they select a person, pre-populate the People search field with the query so the user can immediately see related people.
- **Why (second-brain angle):** Search confidence: the user knows *why* they landed on a result because the query is still visible. Without it, opening a result from search feels like a teleport with no spatial memory.
- **Cross-feature connections:** GlobalSearchView → WorkspaceRouter → ActionItemsView / PeopleListView
- **Effort:** S | **Impact:** Med
- **Deps:** none

### UX1-7: Project↔Meeting deep-link (bidirectional)
- **What:** `WorkspaceRouter.route` currently drops `.project` on `section = .actions` with no ID (`WorkspaceRouter.swift:241–243`). Add `openProject(id:)` alongside `openMeeting` and `openPerson`. In the meeting detail, show a "Part of project" chip if `project.meetingIDs` includes this meeting. Clicking it routes to that project's page in Tasks.
- **Why (second-brain angle):** Projects and meetings are tightly linked in the data model but invisible to each other in the UI. A meeting summary should answer "is this advancing a project?" without a separate Tasks visit.
- **Cross-feature connections:** Meetings ↔ Tasks (Project pages); WorkspaceRouter
- **Effort:** M | **Impact:** Med
- **Deps:** none

---

## Top 3 picks

1. **UX1-3 — ⌘K cross-entity recency** — Highest ROI for effort (S). Transforms the app's primary navigation shortcut from a meeting-picker into a true second-brain launcher. No new data needed, uses existing `backStack`.

2. **UX1-1 — Relational Context Strip** — The single structural change that makes every tab feel connected. Surfaces data relationships that already exist in the model but are invisible at the point of use. The "5 silos" perception disappears when each entity shows its neighbors.

3. **UX1-2 — Context-aware keyboard shortcuts** — Makes the router's existing cross-tab routing accessible without the mouse. For a keyboard-first macOS app, `⌘⏎` to open source meeting from a task is the minimum viable power-user affordance.
