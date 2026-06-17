# Meetings Feature UX Findings — MeetingScribe v2 Audit

## Top friction points / gaps (file:line citations)

### Meeting List
- **No attendee-filter in the list pane.** `MeetingsView.swift:159` comments "Person filter deferred — attendee→person lives in PeopleStore, out of scope here." This is the most natural way to find all meetings with a specific colleague and it's deliberately missing.
- **List row shows "N attendees" but never names them.** `MeetingListRow:694–700` — hovering gives no preview of who is actually there. A tiny avatar strip or "Alice, Bob +2" would communicate relationship relevance at a glance without opening the detail.
- **Month view is decoration, not navigation.** `MeetingsView:536–576` — `dayCell` only shows a 4px blue dot for meeting presence. No time-of-day lane, no meeting count badge > 1. A user with 5 meetings on a day sees one dot.
- **No cross-meeting continuity signal in the list.** A recurring 1:1 and a one-off ad hoc call look identical in the list row (the `repeat` icon at line 682 is 9pt and tertiary). Users can't tell "this series has open items from last time" without clicking in.

### Meeting Detail — Layout
- **"Notes" tab is first but the wrong default for past meetings.** `UnifiedMeetingDetail.swift:409–416` — smart default sets `tab = .notes` even for past meetings with a summary, relying on `summaryExpanded` to auto-expand the disclosure. But the summary is capped at `maxHeight: 320` (`MeetingSummaryTab.swift:138`), so long summaries are silently truncated behind a fixed scroll area inside an already-scrollable outer view — double-scrolling, disorienting.
- **Decisions have no dedicated tab or surface.** `MeetingSummaryTab.swift:97–102` — decisions are shown as `prefix(3)` in the `outcomesStrip` with a tiny `checkmark.seal` icon and no expand affordance. There is no tab for decisions; they are buried and capped. A meeting with 10 decisions hides 7 of them with no "show all" link.
- **Actions tab badge is the only proactive nudge.** `UnifiedMeetingDetail.swift:238–240` — the badge count ("Actions 3") is the sole indicator of unreviewed items. There is no post-meeting checklist prompt, no "you have 2 unconfirmed action items — review now?" banner.
- **Backlinks surface but are invisible.** `UnifiedMeetingDetail.swift:371–376` — `backlinks` and `relatedMeetings` are loaded and stored in state, but there is no UI rendering them anywhere in the detail view. These are computed but dead.
- **No "post-meeting workflow" state.** The detail view has no concept of "this meeting just ended 10 minutes ago, here's what to do next." There's no post-call landing state that differs from viewing a 6-month-old meeting.

### Pre-Meeting Brief
- **Brief is text-only, no interactive affordances.** `PreMeetingBriefView.swift:169–199` — open action items from prior meetings are read-only list rows. You cannot check them off, mark them "discussed," or link them to this meeting's agenda from the brief. The items are dead data.
- **No agenda / goal field.** There is no place to set a meeting agenda or goal before joining. The brief shows what happened before but not what you intend to accomplish. The LLM prompt (`PreMeetingBriefView.swift:363`) generates "Suggested talking points" — but this is AI-guessed, not user-owned. A simple "What do you want to get out of this meeting?" field would make the brief personal and feed the post-meeting review.
- **Person memories and iMessage context not shown in the brief.** `PreMeetingBriefView.swift:51–79` — `talkingPointsSection` correctly surfaces `p.talkingPoints`, but `p.memories` and `p.lastInteractionAt` are completely absent. A person's key memories ("got promoted in May," "moving to Austin") and when you last messaged them are exactly what you want 5 minutes before a call.
- **Brief is consumed silently.** There is no affordance to mark the brief as read, dismiss it, or note "yes I reviewed this." No signal flows back to the system.

### People Rail
- **Rail is 280px wide but only shows health status and "last met."** `MeetingPeopleRail.swift:52` — relationship health capsule is shown but decisions from prior shared meetings are not surfaced. "You and Alice made 3 decisions together last month, 1 is still open" would be actionable; "Thriving / 3d ago" is not.
- **Quick-note capture (P1-12) is invisible.** `MeetingPersonRow.swift:139–152` — the `+` button to capture a person-attributed note is a tiny overlay in the top-right corner of each row. New users will never discover this.
- **No "unlink attendee" in the rail.** Once linked, there's no UI to correct a wrong link from within the meeting detail. The only path is People → person record.

### Chat Tab
- **Context is rich but the example prompts don't leverage it.** `MeetingChatTab.swift:13–18` — prompts are generic ("Summarize the key decisions") when the injected context includes per-person memories and talking points. "What should I follow up with Alice about based on her open items?" would demonstrate the second-brain capability immediately.
- **Chat is per-meeting but decisions/actions made in chat don't write back.** A user can ask "pull the action items" in chat and get an answer, but there's no "Save these to Actions tab" affordance. Chat is read-only relative to the meeting's structured data.

---

## Existing items to endorse

- **Smart tab default** (`UnifiedMeetingDetail.swift:405–421`) — right direction; needs refinement so it defaults to Summary (not Notes) for past meetings with content.
- **Series spine / occurrence navigation** (`allOccurrences`, `previousOccurrence`, `nextOccurrence`) — solid foundation for a meeting history timeline, just not yet surfaced visually.
- **`attachBriefToNotes`** (`PreMeetingBriefView.swift:385`) — seeding the brief into notes at record time is exactly right; makes sure the context travels with the recording.
- **People rail quick-note → encounter** (`MeetingPersonRow.swift:183–186`) — the model is correct; the discoverability is the problem, not the feature.
- **`chatContext` person injection** (`MeetingChatTab.swift:45–64`) — injecting relationship memories and talking points into every chat turn is a genuine second-brain move; needs to be more visible to users.

---

## NET-NEW recommendations

### UX3-1: Post-Meeting Review Mode
- **What:** When a past meeting's detail is opened within 4 hours of its end time, render a distinct "Post-Meeting Review" banner at the top of the Notes canvas with a 3-step checklist: (1) Review action items (links to Actions tab), (2) Confirm decisions (links to decisions section), (3) Update notes for each person (links to People rail capture). Dismiss once all three are completed. Store dismissed state per meeting.
- **Why (second-brain angle):** The highest-value moment for capturing context is right after a meeting. Today the app treats a 10-minute-old meeting identically to a 6-month-old one. A lightweight review ritual turns meetings into structured knowledge within minutes of hanging up.
- **Cross-feature connections:** Actions tab (triage), Decisions strip, People rail (encounter notes), WorkspaceRouter (navigation between steps)
- **Effort:** M | **Impact:** High
- **Deps:** none

### UX3-2: Backlinks + Related Meetings Panel in Detail View
- **What:** Render the already-computed `backlinks` and `relatedMeetings` arrays (currently loaded but never displayed, `UnifiedMeetingDetail.swift:371–376`) as a collapsible "Connected" section at the bottom of the Notes canvas. Each entry: meeting title, date, relationship type ("mentioned this meeting," "semantic match"). Clicking navigates via `WorkspaceRouter`.
- **Why (second-brain angle):** The embedding similarity and backlink graph are built and running — they just have no UI. Making connections visible turns a meeting library into a knowledge graph the user can explore.
- **Cross-feature connections:** WorkspaceIndex (entity catalog), EmbeddingService (semantic search), WorkspaceRouter (navigation)
- **Effort:** S | **Impact:** High
- **Deps:** none (data already loaded)

### UX3-3: Interactive Pre-Meeting Brief with Intent Setting
- **What:** Add two interactive elements to `PreMeetingBriefView`: (1) an "Intent for this meeting" text field ("What do you want to walk away with?") that is stored and carried into the post-meeting review (UX3-1) as a "did you accomplish this?" prompt; (2) checkboxes on open action items in the brief so you can mark "discussed" or "carried forward" before/during the meeting, writing a status update back to the action item. Also inject `p.memories.prefix(3)` for each resolved attendee alongside `talkingPoints`.
- **Why (second-brain angle):** The brief is currently read-only passive context. Making it interactive — letting you set an intent and disposition open items — closes the loop between past commitments and future action. The intent field gives the AI a hook to evaluate meeting success post-call.
- **Cross-feature connections:** ActionItemStore (status updates), PeopleStore (memories), PostMeetingReview (UX3-1), OllamaService (intent-aware brief synthesis)
- **Effort:** M | **Impact:** High
- **Deps:** UX3-1 (for intent handoff)

### UX3-4: Attendee Filter in Meeting List
- **What:** Add a "Person" filter chip to `MeetingsView.filterRow` (alongside Tag and Source) that opens a person-picker and filters the meeting list to meetings where `PersonResolver.resolve` maps any attendee to the selected person's ID. The filter should persist into saved views.
- **Why (second-brain angle):** The most common second-brain query is "show me all my meetings with [person]." Currently requires global search or navigating to the person's profile. A filter chip makes this first-class from the Meetings tab.
- **Cross-feature connections:** PeopleStore (person resolution), SavedView (filter persistence), PersonResolver (attendee matching)
- **Effort:** M | **Impact:** High
- **Deps:** none

### UX3-5: Decisions First-Class Surface
- **What:** Add a "Decisions" section to the Actions tab (or a dedicated fifth tab) that lists all decisions for this meeting with owner, date, and a "revisit" affordance that creates a linked action item. The `outcomesStrip` cap of `prefix(3)` (`MeetingSummaryTab.swift:97`) should become "show all" expandable.
- **Why (second-brain angle):** Decisions are structurally different from action items (they're commitments, not tasks) and are currently treated as second-class. Burying them behind a 3-item cap means most meeting decisions are invisible. Surfacing them drives accountability.
- **Cross-feature connections:** ActionItemStore (create revisit task), DecisionsStore, WeeklyRecap (decision summary)
- **Effort:** S | **Impact:** Med
- **Deps:** none

### UX3-6: Chat → Structured Data Write-Back
- **What:** When the meeting chat returns a list of action items or decisions in a recognized format, render a "Save to Actions" / "Save as Decision" button beneath the AI message. On tap, parse the items and upsert into `ActionItemStore` / `DecisionsStore` with `meetingID` set to the current meeting.
- **Why (second-brain angle):** Chat is currently read-only relative to structured data. A user who asks "pull the action items from this transcript" and gets a list back has to manually re-enter them. Closing this loop makes the AI chat a first-class editing surface, not just a reader.
- **Cross-feature connections:** ActionItemStore, DecisionsStore, ChatPanel, MeetingChatTools
- **Effort:** M | **Impact:** Med
- **Deps:** none

### UX3-7: People Rail — "What to follow up on" Row
- **What:** Below each linked person's health capsule in `MeetingPersonRow`, add a max-2-line "Follow up:" row pulling the person's first open action item with `ownerPersonID == person.id` and first `talkingPoint`. Tapping navigates to the action item. Show nothing if both are empty.
- **Why (second-brain angle):** The rail currently tells you how the relationship is doing but not what to do. Surfacing one open commitment per person makes the "Who's here" rail actionable rather than informational.
- **Cross-feature connections:** ActionItemStore (owner filter), PeopleStore (talking points), WorkspaceRouter (navigation)
- **Effort:** S | **Impact:** Med
- **Deps:** none

---

## Top 3 picks

1. **UX3-2 (Backlinks + Related Meetings)** — The embedding similarity computation is already running and the results are already loaded into view state. This is a high-impact, low-effort fix that turns hidden infrastructure into visible second-brain value with a single new UI section.
2. **UX3-1 (Post-Meeting Review Mode)** — The highest-value capture window is the 10 minutes after a meeting. A time-sensitive review checklist closes the loop between meeting → actions → people and is the most compelling demonstration of what a second brain should do proactively.
3. **UX3-3 (Interactive Pre-Meeting Brief with Intent Setting)** — Turning the brief from a read-only summary into an intent-setting and commitment-disposition surface is the highest-leverage change to the pre-meeting workflow and creates a feedback loop the AI can use post-call.
