# Visual Design & Information Density Findings — MeetingScribe Tasks Audit

**Auditor role:** Senior Product Designer — Visual Design & Information Density
**ID prefix:** D3-

---

## Top existing friction points (file:line citations)

### 1. Task row hides critical fields behind expand — project and meeting source are second-class
`TaskRowView.swift:142–155` shows `projectName` and `meetingTitle` in a `caption2` sub-row below the title. Both are in `.tertiary` or `.secondary` styling and rendered identically (same font, same row), so at a glance a user cannot tell which tasks came from a meeting vs were created manually, and which project a task belongs to.  The `isManual` flag exists (`ActionItem.swift:116`) and the `source` field is set, but the only visual differentiation is `.tertiary` color — no icon treatment that scans well at speed.

### 2. Kanban cards carry almost no information
`HomeTasksBoard.swift:87–119` — each card shows: colored label bars (20px wide, 4px tall — nearly invisible dots), title (caption, 2-line limit), priority badge (icon only, no label), optional due chip, owner avatar.  Missing from cards: project name, subtask progress, `source` indicator (meeting vs manual), `delegated` flag, `estimate`/story-points.  The card is 240px wide and 8px padded — there is space for at least one more metadata row.  A user looking at the Home board cannot tell whether a task is a Linear ticket, a meeting follow-up, or a personal to-do.

### 3. Home board is ALL tasks — no focus filter
`HomeTasksBoard.swift:17–26`: `items(_:)` returns `store.items.filter { !$0.needsTriage }` — every non-triage task in every project and initiative. The Home Kanban is therefore a noisy full-dump. `TodayView.swift:87` embeds this board below calendar content, so a user with 40+ tasks has a completely unmanageable wall of cards. There is no filter to "just today" or "just this week" or "just work context" vs "personal".

### 4. Work vs personal separation is invisible — there is no context/space concept
`Initiative.swift` has `colorHex` and `icon` but no `context` or `space` field. `Project.swift` similarly has `colorHex`/`icon` but no axis to declare work vs personal. **Nothing on the task row, card, or board visually groups or badges tasks by life context.** This is the highest-frequency friction point for Tyler's stated goal of not mixing work and personal.

### 5. Priority chip is verbose on every single row
`TaskRowView.swift:253–270` — every row renders a full priority chip (icon + text label, e.g. "↑ High") in an opaque capsule. For a list of 30 tasks that are all "Medium", this creates a wall of identically-colored noise capsules that trains eyes to ignore priority. Asana/Linear use a single colored square or dot, not a pill with a text label, on dense rows.

### 6. Sync buttons (Linear / Notion) are always visible on every row
`TaskRowView.swift:347–401` — two icon buttons appear on hover (`linearButton`, `notionButton`). For tasks that will never touch Linear or Notion (personal tasks), these are permanent visual noise and a false affordance. They take ~52px of right-side width that could be used for more useful metadata.

### 7. Inline expanded editor duplicates UI in a dissonant style
`TaskRowView.swift:413–492` — `detailEditor` renders a completely different visual language (`.roundedBorder` text fields, `TextEditor`, `.bordered` buttons) inside the same row. This clashes with the rest of the card-based NDS design. The expand-in-place approach also causes the row to grow to 200–300px, pushing other rows off screen with no visual anchor.

### 8. `TaskInsightsView` is flat and project-unaware
`TaskInsightsView.swift` — shows global counts (open/in-progress/done/overdue), last 7-day bar chart (completion only, not creation), and top-6 projects by open count. No drill-down, no initiative-level rollup, no throughput trend, no overdue-by-project breakdown, no "work vs personal" split. The chart uses proportional bars that are not clickable; a click on a project bar does nothing.

### 9. Label chips overflow the sub-row silently
`TaskRowView.swift:169–171` — `ForEach(assignedLabels) { l in labelChip(l) }` renders every label in a horizontal `HStack(spacing: 8)` that already holds owner, project, meeting-title, subtask count, and source badge. On tasks with 3+ labels or long project names, items wrap or clip with no truncation indicator. The caption-sized HStack has no max width constraint.

### 10. Kanban board column width is fixed at 240px regardless of screen size
`HomeTasksBoard.swift:83`: `.frame(width: 240, ...)`. On a 27" monitor a board with 3 columns uses only 732+padding px out of 2560px — columns don't stretch. On a 13" MacBook the board requires horizontal scrolling even for 3 columns.

---

## Existing items worth endorsing / prioritizing

- **D3-2 (already in code):** One-click completion with celebration ring (`TaskRowView.swift:40–41`, `214–248`) — this is correct and should stay.
- **VD-15 `DueChip`:** The shared, unified due-date chip with relative phrasing ("2d overdue", "Today") is well-implemented and correctly reused across surfaces.
- **VD-7 progress readout in `ActionItemStore`:** `progressForProject` and `progressForInitiative` are computed (`ActionItemStore.swift:143–149`) but never rendered in the sidebar, board, or row. These should be surfaced immediately.
- **`isManual` / `source` fields:** Already on the model (`ActionItem.swift:54, 116`). Just needs a visual badge.

---

## NET-NEW recommendations

### D3-1: Context Spaces — Work / Personal axis on Initiatives and Projects
- **What:** Add a `context: ContextSpace` enum field to `Initiative` and `Project` (cases: `.work`, `.personal`, `.shared`). Render a small colored left-rail strip or icon badge on every task row and Kanban card that indicates context. The sidebar collapses or expands sections by context. Home board gets a segmented filter: "All | Work | Personal".
- **Why:** Tyler's #5 goal is explicit. Currently there is zero visual or structural separation between a "Buy birthday gift" task and a "Ship analytics dashboard" task — they sit in the same undifferentiated list. The model supports Initiatives already; adding one enum field unlocks the entire separation.
- **Effort:** S (model) + M (UI threading through row/card/board/sidebar) = M total | **Impact:** High
- **Deps:** none

### D3-2: Source-Awareness Badge on Every Card
- **What:** Render a small pill or icon at the top-right of every Kanban card and task row that distinguishes: meeting-extracted (calendar icon, muted teal), manual (pencil icon, neutral), Linear-synced (L icon, brand color), Notion-synced (N icon, purple). Use `ActionItem.source` and `isManual` which already exist.
- **Why:** Users do not know at a glance "did this come from a meeting?" This is foundational to the app's core pitch (meeting → task). Currently `!item.isManual` renders `Label(item.meetingTitle, ...)` at `.caption2 .tertiary` buried in the sub-row — nearly invisible, no distinct visual treatment. The badge would make the meeting-extraction value prop visible at every touchpoint.
- **Effort:** S | **Impact:** High
- **Deps:** none (fields exist)

### D3-3: Kanban Card — Second Metadata Row for Project + Source
- **What:** Add a second `HStack` row to every `HomeTasksBoard.card` below the priority/due/owner row. Left side: project name in a colored capsule using `Project.colorHex` (already on the model). Right side: source badge (D3-2). Also show a `subtaskProgress` fraction ("2/5") inline when `total > 0`.
- **Why:** `HomeTasksBoard.swift:87–119` — cards are currently title + tiny label bars + priority dot + due chip + avatar. On a 240px-wide card this is too sparse on information. A user cannot tell what project a task belongs to without tapping through. Notion and Linear both surface the project/label prominently on every card.
- **Effort:** S | **Impact:** High
- **Deps:** D3-2 for source badge; otherwise standalone

### D3-4: Home Board Focus Filter — "Today" / "This Week" / "All" + Context toggle
- **What:** Add a `FilterBar` above the `HomeTasksBoard` Kanban with three time-scope pills (Today, This Week, All) and a context toggle (Work / Personal / All) from D3-1. The board's `items(_:)` method (`HomeTasksBoard.swift:17–26`) already filters by triage status; extend it to also filter by `dueDate` range and `context`.
- **Why:** Showing every non-triage task on the Home page is unscalable. For daily planning, a user wants Today's tasks, not 60 accumulated items. Linear's "My Issues" view and Asana's "My Tasks" today filter are exactly this affordance.
- **Effort:** M | **Impact:** High
- **Deps:** D3-1 for context filter

### D3-5: Replace Verbose Priority Capsule with Compact Priority Dot on Dense Rows
- **What:** Replace `priorityPicker` (`TaskRowView.swift:253–270`) with a 10x10 colored dot (no text label) on collapsed rows. Priority text label only appears in the expanded detail editor or on hover tooltip. Priority color from `NDS.priority` is already computed. Use `MSPriorityBadge(showLabel: false)` (already exists on the Kanban card).
- **Why:** A text capsule for "Medium" on every row in a 40-task list trains users to ignore it. A colored dot signals priority in 2px of width; a tooltip on hover confirms the label. This is how Linear and GitHub Issues handle priority on dense lists.
- **Effort:** S | **Impact:** Med
- **Deps:** none

### D3-6: "Meeting Source" Provenance Strip on Task Page and Triage
- **What:** When a task has `!isManual`, add a dismissable banner at the top of the task detail panel (TaskPageView and the expanded row's `detailEditor`) that reads: "[Calendar icon] From: [meetingTitle] · [meetingDate]" with a "View meeting" deep-link. Style as a light NDS card with `NDS.brand` left border.
- **Why:** The meeting-extraction loop is the app's unique value. Currently the provenance is buried in the sub-row label — it's not visible in the full task page. Users who expand a task cannot see where it came from.
- **Effort:** S | **Impact:** Med
- **Deps:** none

### D3-7: Initiative Completion Arc in Sidebar
- **What:** Render a small arc/ring (think macOS Podcasts progress indicator) next to each Initiative name in the sidebar using `progressForInitiative` from `ActionItemStore` (already computed at `ActionItemStore.swift:149`). On hover, a tooltip shows "12/20 tasks complete".
- **Why:** The data is already computed — `VD-7` note in the store says "drives a % complete indicator" but nothing renders it. Initiative progress is invisible everywhere in the UI. This is a 1-line data hookup + a 20-line ring component.
- **Effort:** S | **Impact:** Med
- **Deps:** none

### D3-8: Adaptive Kanban Column Width
- **What:** Change `HomeTasksBoard.swift:83` from `.frame(width: 240)` to `.frame(minWidth: 200, idealWidth: 260, maxWidth: 340)` inside the `HStack`. Use `GeometryReader` on the board container to compute a width that fills available horizontal space evenly for 3 columns with 12px gaps. Cap cards at 340px; let them shrink on small screens rather than forcing scroll for 3 columns.
- **Why:** Fixed 240px columns waste screen real estate on large monitors and force horizontal scroll on 13" MacBooks. The Kanban is embedded in `TodayView` at full window width but columns don't respond to it.
- **Effort:** S | **Impact:** Med
- **Deps:** none

### D3-9: Inline Detail Editor — Replace with "Property Drawer" Slide-In Panel
- **What:** Instead of `detailEditor` expanding in-place within the row (pushing all other tasks down, `TaskRowView.swift:413–492`), open a fixed-height 340px drawer that slides in from the right edge of the list column — anchored to the row — when the user clicks a task title. The drawer contains the same fields but in NDS card style, with the full `TaskPageView` accessible via "Open full page" CTA. The row itself stays at its collapsed height while the drawer is open.
- **Why:** The current expand pushes 10+ tasks off-screen while editing one. The drawer keeps context (user can see adjacent tasks). This matches how Linear handles inline editing.
- **Effort:** L | **Impact:** High
- **Deps:** none (replaces existing expand, no model changes)

### D3-10: Sync Button Conditionalization
- **What:** Hide the Linear and Notion sync icon buttons from the task row's trailing area for tasks that belong to projects with no sync integration configured. Show them only when the parent project (or app-level settings) has a Linear workspace or Notion database connected. Gate on `item.source == "linear"` (already exists) and a project-level `syncTarget` setting.
- **Why:** Every row currently shows two sync icon buttons that do nothing useful for purely local personal tasks. This is false affordance and visual noise that competes with the priority and due-date chips for attention.
- **Effort:** S | **Impact:** Med
- **Deps:** requires a project-level `syncTarget` property (not yet in model) — model change is S

---

## Top 3 picks

1. **D3-1 — Context Spaces (Work / Personal)** — The single highest-priority improvement. Tyler explicitly named work/personal mixing as the core organizational pain. A `context` enum on Initiative/Project threads through to every surface (row, card, sidebar, board filter) and solves the problem at the root rather than patching individual views.

2. **D3-9 — Property Drawer replaces in-place expand** — The current expand-in-place editor is the most disruptive interaction in the whole Tasks feature. It ruins list scannability every time a user wants to set a due date. A fixed-position drawer preserves context and unblocks daily use.

3. **D3-4 — Home Board Focus Filter (Today / This Week / All + Context toggle)** — Without a time and context filter the Home Kanban is unusable for daily planning at scale. This directly addresses Tyler's "revamped Home page" goal and requires no model changes — only a FilterBar view and a predicate extension on the existing `items(_:)` method.
