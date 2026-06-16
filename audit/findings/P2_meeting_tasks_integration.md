# P2 — Meeting → Tasks Integration Findings — MeetingScribe Tasks Audit

## Top existing friction points (file:line citations)

### 1. Triage inbox is a flat undifferentiated list — no meeting grouping
`TriageInboxView.swift:24` — items from every meeting are rendered in a single `ForEach`, sorted soonest-due-first, then newest. When you have action items from three back-to-back calls, there is no visual separator to tell them apart. The meeting chip (`NotionChip(item.meetingTitle, ...)` at line 96) is the only context anchor, and it renders inline at caption size. Users must read each row's chip to reconstruct meeting context. A flat list of 15 AI-extracted tasks across 4 meetings with no grouping is overwhelming.

### 2. "Add all → Tasks" bulk-accept has no project-routing
`TriageInboxView.swift:54-59` — `confirmAllTriage()` (`ActionItemStore.swift:364-368`) confirms every pending item with `projectID = nil`, so every bulk-added task lands in Unsorted. The per-item project-assignment `Menu` at `TriageInboxView.swift:107-119` works but is buried behind an icon with no label, and it only appears when `!store.projects.isEmpty`. There is no meeting-level "add all items from this meeting to project X" affordance. This means any bulk workflow guarantees an Unsorted cleanup pass.

### 3. Clicking a meeting in the Tasks sidebar redirects away instead of opening inline
`ActionItemsView.swift:191-198` — When `selectedMeetingID` is set (via the sidebar Meeting notes section), the right pane renders `Color.clear` and then fires `router.openMeeting(m)`, jumping the user to the Meetings tab and clearing `selectedMeetingID`. There is no embedded meeting context panel within the Tasks tab. This means if a user is reviewing the Triage inbox and clicks "Open source meeting", they leave the Tasks workflow entirely. Context is lost.

### 4. No way to pull meeting notes/summary into a task body
`TaskPageView.swift:432-464` — `bodyEditor` renders a plain markdown `TextEditor` seeded with `item.notes`. There is no affordance to insert meeting summary text, transcript excerpt, or decision list from the source meeting into the task body. If you open a triage item and want to add context from the meeting, you must navigate away, manually copy text, come back, and paste. Compare with Linear's ability to reference an issue body inline or Notion's `/mention` block.

### 5. Triage items from a meeting have no "pre-triaged" project suggestion
`TriageRow` (`TriageInboxView.swift:66-147`) shows a generic project picker with all projects, sorted however they appear in the store. If a user has a project called "Acme Onboarding" and the source meeting was "Acme Onboarding Kickoff", there is no logic to pre-select or rank that project. Every row starts from an empty suggestion. This forces manual decision-making per item.

### 6. Meeting summary tab's per-meeting triage flow is siloed from the Tasks triage inbox
`MeetingSummaryTab.swift:350-363` — The summary tab has its own inline "Add N → Tasks" button that calls `confirm(ids:)` directly. This is a good fast path, but it bypasses the Triage inbox entirely — users who use it never see the inbox, so the triage badge count can be confusing. There is no visual bridge telling the user "3 items from this meeting are currently in your triage inbox" from the summary view.

### 7. "From meeting" property on TaskPageView is clickable but routes to another tab
`TaskPageView.swift:299-318` — The meeting backlink fires a `NotificationCenter` post (`meetingScribeOpenEntity`) which presumably opens the Meetings tab. A confirmed task that you open in the Tasks task page has a functional but context-breaking backlink. There is no in-pane meeting context panel — just a jump.

### 8. Re-extract is not surfaced as a first-run discovery path
`ActionItemsChrome.swift:548` — The empty-triage empty state says "Record a call, or click Re-extract to backfill from existing summaries," but "Re-extract" is buried in the overflow `...` menu (`ActionItemsChrome.swift:384`). A new user with existing meetings who sees inbox zero has no obvious path to populate it.

---

## Existing items worth endorsing / prioritizing

- **`MeetingActionRow.swift`** — per-item "→ Tasks" / "In Tasks" status label at the row level is excellent. Keeps the Tasks status visible without leaving the meeting context.
- **`ActionItem.needsTriage` computed var** (`ActionItem.swift:121-123`) — clean, correctly excludes completed and trashed items. Good foundation for grouping logic.
- **`pendingTriage` sort** (`ActionItemStore.swift:337-344`) — soonest-due first makes sense for the confirmation flow.
- **`confirmAllTriage()` returning count** (`ActionItemStore.swift:364-368`) — good for toast feedback; already wired to the header button.
- **Attendee-first owner assignment** in `MeetingActionRow.swift` (P2-9) — excellent UX; should be replicated in `TriageRow`.

---

## NET-NEW recommendations

### P2-1: Group triage inbox by source meeting, with per-meeting bulk actions
- **What:** Restructure `TriageInboxView` to render items grouped by `meetingID`. Each group gets a collapsible section header showing the meeting title, date, and attendee avatars. The header has two controls: (a) "Add all to project…" — a project picker that routes the whole group, and (b) "Dismiss meeting" — discards all items from that meeting with undo. Individual rows retain their per-item Add/Discard controls.
- **Why:** When you have 20 items across 5 meetings, you process them meeting-by-meeting, not item-by-item. The meeting is the unit of context. Grouping matches how users think ("everything from the design review") and makes the per-group bulk-add safe enough to trust without reviewing every row.
- **Effort:** M | **Impact:** High
- **Deps:** none

### P2-2: Smart project suggestion in triage rows based on meeting title
- **What:** In `TriageRow`, compute a ranked project suggestion by fuzzy-matching `item.meetingTitle` against `store.projects`. Render the top match as a pre-filled project chip (tappable to confirm to that project; tappable again to open the full picker). Show "No suggestion" if confidence < threshold.
- **Why:** Most users record meetings in the context of a project ("Product Review", "Acme Onboarding"). Pre-filling eliminates the blank-slate decision per row and converts triage from a two-click-per-item flow into a one-click confirm-or-override flow.
- **Effort:** S | **Impact:** High
- **Deps:** none

### P2-3: Inline meeting context panel — "peek" without leaving Tasks
- **What:** When the user clicks "Open source meeting" in `TriageRow` (or the "From meeting" property in `TaskPageView`), instead of routing to the Meetings tab, open a popover or right-pane sheet within the Tasks tab that shows: meeting title, date, attendees, AI summary excerpt (first 400 chars), decisions list, and a "Go to full meeting →" link. This eliminates the context switch.
- **Why:** `ActionItemsView.swift:191-198` currently fires `router.openMeeting(m)` and abandons the task flow. The user wants context, not a tab switch. The data is already available via `manager.pastMeetings`.
- **Effort:** M | **Impact:** High
- **Deps:** none

### P2-4: "Insert meeting context" action in task body editor
- **What:** Add a toolbar button in `bodyEditor` (`TaskPageView.swift:432`) — "Insert from meeting" — that, for non-manual tasks (`!item.isManual`), appends a formatted block to `noteDraft`: meeting title, date, and the raw summary text from `summary.md`. Optionally add a "Insert decisions" variant. This is analogous to Notion's `/mention` embed.
- **Why:** The task body is where detailed context lives, but meeting-sourced tasks arrive with an empty body. Engineers and PMs routinely paste meeting summary fragments into task descriptions. This eliminates the copy-paste-switch-tab-paste cycle. `item.meetingID` already gives us the path to `summary.md`.
- **Effort:** S | **Impact:** High
- **Deps:** none (needs access to summary file path, already available via `AppSettings.shared.storageDir`)

### P2-5: Meeting context badge on confirmed task rows
- **What:** In `TaskRowView.swift`, when `!item.isManual` and the task is confirmed, render a subtle meeting chip (meeting title, truncated to 18 chars) after the project chip. Tapping it opens the inline peek panel (P2-3). Currently `TaskRowView.swift:149-150` renders a `Label(item.meetingTitle, systemImage: "calendar")` only in a non-obvious location.
- **Why:** Once a task is confirmed and in the workspace, users lose the meeting provenance signal. Surfacing it on the row makes it easy to re-open the source meeting when you're working the task.
- **Effort:** S | **Impact:** Med
- **Deps:** P2-3 (for the peek panel target)

### P2-6: Re-extract surface from triage inbox empty state
- **What:** When `TriageInboxView` renders the inbox-zero state (`TriageInboxView.swift:18-22`), add a visible "Re-extract from past meetings" button that calls `manager.backfillActionItemsIfNeeded(force: true)`. Currently this action lives only in the buried overflow menu.
- **Why:** New users with existing meetings will see inbox zero and not know how to populate it. One visible button with the right label converts a confused moment into an aha moment.
- **Effort:** S | **Impact:** Med
- **Deps:** none

### P2-7: Per-meeting triage status bridging into the summary tab
- **What:** In `MeetingSummaryTab.swift`'s `actionItemsSection`, replace the raw count label with a dual state: if any items are still in the Triage inbox (checked via `items.filter { $0.needsTriage }.count > 0`), render "N in Tasks inbox — review →" as a tappable link that opens the Triage inbox filtered to this meeting. Once all are confirmed, render "All in Tasks ✓".
- **Why:** The summary tab and triage inbox are currently independent flows with no cross-referencing. A user who processes tasks from the summary view and then opens the Triage inbox will be confused about status. The bridge makes the two surfaces feel like a single coherent system.
- **Effort:** S | **Impact:** Med
- **Deps:** P2-1 (for the filtered triage view)

### P2-8: Batch project assignment from "Add all → Tasks" header button
- **What:** Change the "Add all N → Tasks" button in `TriageInboxView.swift:52-60` to a split button: left side "Add all" (current behavior, no project), right side opens a project picker to route the entire inbox to one project. Show the picker as a `Menu` inline.
- **Why:** Power users who process a meeting-themed inbox all belong in one project. The current "Add all" landing everything in Unsorted is the most common post-triage cleanup complaint.
- **Effort:** S | **Impact:** High
- **Deps:** none

---

## Top 3 picks

1. **P2-1** — Group triage by meeting with per-group bulk actions. This is the single highest-leverage change: it reframes the inbox as a meeting-level workflow (the natural mental model) and makes the bulk path trustworthy.
2. **P2-4** — "Insert meeting context" in task body. Zero new screens, one button, eliminates a 5-step copy-paste tax every time a user wants to add meeting notes to a task.
3. **P2-3** — Inline meeting peek panel. The current tab-jump on "Open source meeting" breaks flow at exactly the moment users need context most. An inline popover costs one M-effort sprint and makes the meeting↔task link feel native rather than bolted on.
