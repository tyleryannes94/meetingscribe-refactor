# Relationship Manager / People-Centric User (U2) Findings — MeetingScribe v2 Audit

Persona: manages 50+ relationships, uses 1:1s as primary work surface, needs to remember
context from months ago, treats contacts like a CRM. Scenarios tested:
1. Preparing for a 1:1 with someone not seen in 6 weeks
2. Logging a new contact after a conference
3. Remembering what was promised 2 months ago
4. Weekly review of neglected relationships

---

## Top friction points / gaps (file:line citations)

### Scenario 1 — Preparing for a 1:1 after 6 weeks

**What exists:** `PersonDetailView` has a two-pane layout (identity + tab work-area), a
`PreMeetingBriefView` that surfaces talkingPoints per attendee
(`PreMeetingBriefView.swift:51–55`), tasks linked to the person (`PersonDetailView.swift:1600`),
meeting backlinks (`person.meetingMentions`), and a per-person AI chat column
(`PersonDetailView.swift:365–373`).

**Gaps:**
- **No "prep brief" button on the Person profile itself.** `PreMeetingBriefView` only renders
  inside a meeting's transcript tab (`MeetingTranscriptTab.swift:28`). To prep for tomorrow's
  1:1, the user must find the calendar event first, not just open the person's profile and say
  "what do I need to know before I meet them?"
- **talkingPoints are a flat, unordered list** (`Person.swift:243`). There is no concept of
  priority, staleness, or "added from which meeting." A point from 6 weeks ago looks the same
  as one added this morning.
- **The Overview tab** shows talkingPoints, memories, encounters, and tasks but they are
  separate siloed sections — there is no synthesized "catch-up view" that temporally orders
  everything that happened since the last meeting and flags what is overdue or unresolved.
- **calendarMeetings** (unrecorded future meetings) are loaded into state
  (`PersonDetailView.swift:275`) but there is no surface that says "your next 1:1 is in 2 days —
  here's what you should cover."
- **No AI-generated pre-meeting brief** scoped to a specific person. The chat column exists but
  the user must phrase their own question. There's no one-click "Brief me on [Name]" that
  aggregates: last meeting summary, open tasks, overdue talking points, and iMessage themes.

---

### Scenario 2 — Logging a new contact after a conference

**What exists:** Add Person sheet, multi-source import (Contacts/Gmail/calendar/vcard/CSV),
tag support, Quick Encounter sheet (`PersonDetailView.swift:388–393`), `bio` / `memories` /
`favorites` fields on `Person`.

**Gaps:**
- **No "conference/event" capture flow.** The Add Person sheet is a generic form. A
  relationship manager returning from a conference needs: who they met, where, what was
  said, and a follow-up action — all in one gesture. There is no "Add from event" mode that
  pre-fills context (event tag, date, location, talking-points noted).
- **No post-add prompt to log first encounter.** After creating a person, the user is dropped
  back into the list. First encounter (where/how you met) is a separate flow requiring a
  second deliberate action.
- **Tags help but are global across meetings + people.** There is no concept of a "group"
  or "cohort" attached to a Person at creation time (e.g., "Met at SaaStr 2026"), distinct
  from tag-based filtering. The tag approach works but conference attendees become invisible
  noise in the full tag chip bar after the event ends.
- **No business card scan / URL enrichment.** The import flow covers Contacts/CSV but not
  "paste a LinkedIn URL or snap a business card and fill the fields automatically." For a
  conference context, this is the highest-friction gap.

---

### Scenario 3 — Remembering what was promised 2 months ago

**What exists:** `personTasks` (`PersonDetailView.swift:1600`) shows action items linked to a
person, showing which meeting they originated from (`item.meetingTitle`,
`PersonDetailView.swift:1682`). iMessage analysis (`.actionItems` preset) surfaces pending
follow-ups from texts. Memories and attachedNotes can store freeform promises.

**Gaps:**
- **Promise ≠ task.** A promise like "I'll introduce you to my designer friend" rarely gets
  logged as a formal task. There is no "commitments" concept at the person level — only the
  Today tab's cross-cutting `commitmentsSection` (`TodayView.swift:389`) groups open tasks by
  direction, but it is tab-global and not surfaced inside the person's profile.
- **No "since our last meeting, here's what you committed to" aggregation.** The tasks section
  shows all tasks sorted by open/done then due date but does not call out the ones that
  originated from the last meeting with this person or tasks that are now overdue.
- **iMessage action-item extraction is on-demand**, requiring the user to run the
  `.actionItems` analysis preset manually. There is no automatic pipeline that scans iMessage
  threads and surfaces: "You mentioned introducing [Name] to your designer. Still pending."
- **Memories have no `source` field.** A memory like "promised to send the YC batch list" has
  no link back to which meeting or message it came from (`Memory` struct, `Person.swift:6–17`).
  Verifying what was actually said requires manually digging through transcripts.
- **No "owed to this person" / "this person owes you" split** inside the person profile.
  `TodayView.swift:399–400` has "You owe / Owed to you" but only at the global level. Opening
  a person should immediately show the commitment balance for that relationship.

---

### Scenario 4 — Weekly review of neglected relationships

**What exists:** Keep-in-touch board (`KeepInTouchBoard.swift`) with four health bands
(Overdue / Drifting / Steady / Thriving), relationship-health ring on every avatar, health
based on cadence vs. days-since-last-encounter, `reconnectThresholdDays` per relationship
type (`Person.swift:114`), reconnect-draft feature (`PersonDetailView.swift:259`).

**Gaps:**
- **The board is a destination, not a push surface.** The user must navigate to the board to
  see who is drifting. The Today tab's `StayConnectedSection` is the closest push surface but
  does not link directly to "here are the 4 people in Overdue right now."
- **Health score uses only encounters, not iMessages or meeting mentions.**
  `KeepInTouchBoard.swift:27–36` computes health from `store.encounters()`. If the user texted
  someone 3 times last week but hasn't logged a formal encounter, they appear in Overdue.
  `lastInteractionAt` is only used when encounter data is empty.
- **Board cards show only name + last-met; no context.** For 50+ contacts, seeing "Sarah Chen
  — Last met 6 weeks ago" in the Overdue column doesn't help you decide what to say. A quick
  AI-generated conversation starter or "last topic discussed" snippet on the card would
  dramatically reduce the friction of acting on the board.
- **No weekly digest email/notification of neglected relationships.** `NotificationManager`
  fires daily brief notifications (`NotificationManager.swift:240`) but there is no "weekly
  relationship health report" that tells the user: "3 Colleagues moved to Overdue this week."
- **No relationship-strength trend.** The health model is point-in-time. There is no way to
  see that a relationship has been gradually drifting over 3 months — the board always shows
  the current state, never the trajectory.
- **Board is inaccessible from Today.** The Today tab has a `StayConnectedSection` but the
  board widget itself is only reachable via the icon button in `PeopleListView.swift:253`.
  There is no deep link from Today → board.

---

## Existing items to endorse (from prior plan or codebase)

- **KeepInTouchBoard (C2-2)** — the kanban health board is genuinely useful; it should be
  promoted to a Today widget, not hidden inside the People sidebar button.
- **talkingPoints surfaced in PreMeetingBriefView (U1-5)** — correct architecture; needs to
  go further (see U2-2 below).
- **Reconnect draft (C2-4)** — AI-drafted opener when reconnecting is a high-value feature.
  The "Reconnect with context" flow should be available from the board cards, not only from
  inside the full profile.
- **AI chat column in PersonDetailView** — embedding the chat in the profile is the right
  call for deep Q&A; the gap is in reducing the prompt friction (see U2-1 below).
- **Encounter heat map (D4-6)** — useful visual; should include iMessage/meeting-mention
  signals alongside logged encounters.

---

## NET-NEW recommendations

### U2-1: One-Click "Brief Me" Button on Every Person Profile
- **What:** A prominent "Brief me on [Name]" button (or keyboard shortcut `B`) on the person
  detail header that runs a structured AI brief covering: (a) last meeting summary, (b) open
  tasks and overdue commitments for this person, (c) pending talkingPoints, (d) iMessage
  themes from the past 30 days, and (e) any upcoming calendar event with them. Output renders
  as a collapsible card at the top of the Overview tab — ephemeral but pinnable.
- **Why (second-brain angle):** The app has ALL the raw material for this brief; it just never
  synthesizes it proactively per person. This converts the profile from a data dumping ground
  into an intelligent prep surface.
- **Cross-feature connections:** Meetings (last summary), Tasks (open items), iMessage
  (MessagesAnalyzer), Calendar (CalendarService), People (talkingPoints, memories). Feeds
  directly into PreMeetingBriefView.
- **Effort:** M | **Impact:** High
- **Deps:** none (all data sources already connected)

### U2-2: Commitment Ledger Per Person
- **What:** A dedicated "Commitments" section in the person's Tasks tab that splits action
  items into two buckets: "You owe [Name]" (tasks you own that reference this person or
  originated from a meeting with them) and "[Name] owes you" (tasks where this person is the
  owner). Each item shows: task title, originating meeting, due date, and days overdue. Add a
  "Log promise" quick-add that creates a task linked to this person without needing to open
  the Tasks tab.
- **Why (second-brain angle):** The Today tab has a global commitment split but it's
  ungrouped by person. Opening Sarah's profile and instantly seeing "You owe her 3 things,
  2 of which are overdue" is the killer workflow for a relationship manager.
- **Cross-feature connections:** ActionItemStore (ownerPersonID), TodayView commitmentsSection
  (can reuse the column component), PreMeetingBriefView (inject into the brief).
- **Effort:** S | **Impact:** High
- **Deps:** none

### U2-3: Multi-Signal Relationship Health (iMessage + Meeting Mentions)
- **What:** Extend `RelationshipHealth` calculation and `KeepInTouchBoard` to incorporate
  three signals beyond manual encounters: (a) iMessage activity via `MessagesAnalyzer` stats,
  (b) meeting mentions (`person.meetingMentions`), and (c) calendar events with this person
  (`calendarMeetings`). Weight them less than logged encounters but use them to prevent false
  "Overdue" classification for people you're actively communicating with through other
  channels.
- **Why (second-brain angle):** A health score that only counts manual encounter logs penalizes
  power users who communicate via iMessage or attend ad-hoc calendar meetings. False Overdue
  signals erode trust in the board and the user stops checking it.
- **Cross-feature connections:** MessagesAnalyzer, CalendarService, PeopleStore, KeepInTouchBoard.
- **Effort:** M | **Impact:** High
- **Deps:** none

### U2-4: Conference / Event Rapid-Capture Mode
- **What:** An "Add from Event" sheet (⇧⌘E or a toolbar button) that: (1) asks for an event
  name (pre-populates from today's calendar if available), (2) lets the user add N people in
  bulk with name + one-liner context, (3) creates a shared tag for the event, (4) opens a
  QuickEncounterSheet for each in sequence with the event as context, and (5) surfaces a
  "Follow up" task stub per person added. Essentially a conference contact intake flow.
- **Why (second-brain angle):** The current flow requires 4–5 separate actions per person
  (Add Person → encounter → tag → note → task). After a conference with 10 new contacts, this
  is 40–50 clicks. Reducing it to one multi-step flow increases the probability the user
  actually logs these contacts while the memory is fresh.
- **Cross-feature connections:** PeopleStore (bulk add), PeopleTagStore (auto-tag), CalendarService
  (pre-fill event name), ActionItemStore (follow-up task stubs), QuickEncounterSheet (reuse).
- **Effort:** M | **Impact:** High
- **Deps:** none

### U2-5: Relationship Trajectory Sparkline on Board Cards
- **What:** Add a micro-sparkline (7 dots, last 7 weeks of encounter/signal density) to each
  card on the KeepInTouchBoard. A card in Drifting that has been declining for 5 weeks looks
  very different from one that just dropped due to a vacation gap. Add a "trending down"
  indicator (↓) on cards where the gap is widening week-over-week.
- **Why (second-brain angle):** Point-in-time health is weak. Trajectory tells you whether a
  relationship needs an urgent nudge or a natural pause. This is the difference between
  reactive CRM (someone fell off) and proactive relationship intelligence.
- **Cross-feature connections:** PeopleStore encounters, KeepInTouchBoard card rendering, weekly
  health computation already in `KeepInTouchBoard.swift`.
- **Effort:** S | **Impact:** Med
- **Deps:** U2-3 (multi-signal health first so sparkline reflects real signal)

### U2-6: Proactive Weekly Relationship Brief (Notification + Today Widget)
- **What:** Every Monday morning, generate a "Relationship Brief" notification and Today
  widget section listing: (a) people who moved into Overdue this week, (b) upcoming special
  dates or birthdays in the next 14 days, (c) people you met last week with open follow-ups,
  and (d) the one person who has drifted the longest from their target cadence. Single tap
  opens the KeepInTouchBoard.
- **Why (second-brain angle):** The board is currently passive — you have to go look. A weekly
  push turns the keep-in-touch board into a relationship accountability system without any
  extra user effort.
- **Cross-feature connections:** NotificationManager, TodayView (widget slot), KeepInTouchBoard,
  SpecialDate/birthday fields on Person, WorkspaceRouter (deep link → board).
- **Effort:** M | **Impact:** High
- **Deps:** none

### U2-7: talkingPoint Aging + Auto-Surface in Pre-Meeting Brief
- **What:** Add `addedAt: Date` and `meetingSourceID: String?` to the talkingPoint data model
  (currently `[String]`, `Person.swift:243`). Show an age indicator on points older than 30
  days ("⚠ 6 weeks old"). Auto-surface overdue talking points at the top of the
  `PreMeetingBriefView` for this person's next meeting, highlighted distinctly from fresh ones.
  Points resolved in a meeting can be checked off and logged as a memory.
- **Why (second-brain angle):** Stale talking points that get surfaced at a 1:1 months later
  are embarrassing. But points forgotten entirely are worse. Aging signals let the user
  decide: still relevant, or remove it?
- **Cross-feature connections:** Person.talkingPoints → PreMeetingBriefView, meeting transcript
  (auto-check off if topic appears in transcript), PersonDetailView talkingPointsSection.
- **Effort:** S | **Impact:** Med
- **Deps:** none (additive schema change with tolerant decoding)

### U2-8: Reconnect Opener from Board Card (Not Just Profile)
- **What:** Surface the existing reconnect-draft feature (`PersonDetailView.swift:259`) as a
  right-click / hover action directly on KeepInTouchBoard cards. Right-click → "Draft message"
  → inline popover generates AI opener with context (last topic, elapsed time). Reduces the
  "find person → open profile → find reconnect button" journey to a single right-click from
  the board.
- **Why (second-brain angle):** The board is the weekly triage surface. Acting directly from
  the board (draft → copy → switch to Messages) collapses a 5-step workflow into 2 steps.
- **Cross-feature connections:** KeepInTouchBoard, PersonDetailView reconnect draft logic,
  OllamaService.
- **Effort:** S | **Impact:** Med
- **Deps:** none

---

## Top 3 picks

1. **U2-1 (Brief Me button)** — synthesizes every data source the app already has into a
   per-person prep brief; highest ROI for the 1:1 preparation scenario and the most visible
   proof that MeetingScribe is a second brain, not a CRM list.

2. **U2-2 (Commitment Ledger per person)** — closes the biggest gap between "I have tasks in
   an app" and "I know what I owe each person and what they owe me"; directly exploits the
   existing `ownerPersonID` link that is already on every ActionItem.

3. **U2-3 (Multi-Signal Health)** — without iMessage and meeting-mention signals, the health
   board produces false Overdue alerts that erode user trust; fixing this makes every other
   health-based feature (board, notifications, trajectory sparkline) trustworthy.
