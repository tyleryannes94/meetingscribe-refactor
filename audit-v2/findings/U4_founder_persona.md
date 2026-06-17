# U4 — High-Velocity Founder Persona Findings — MeetingScribe v2 Audit

> Persona: 10+ meetings/day, voice notes between calls, delegates constantly.
> Every extra tap is a failure. Context switches are brutal.

---

## Top friction points / gaps (file:line citations)

### 1. Voice note requires navigating to a tab to start recording
`QuickNotesView.swift:126–133` — the record button lives inside the Notes tab
sidebar. A founder walking between rooms has to: switch to the app → click the
Notes tab → click "New Note". That is 3+ interactions. There is no global
keyboard shortcut, no menubar/floating trigger, no "just started recording"
confirmation from anywhere else in the app. The `FloatingOverlay` exists for
meetings (referenced in `QuickNotesView.swift:23–29`) but there is no analogous
always-visible quick-record affordance for voice notes.

### 2. Voice notes are completely siloed from People and Tasks
After a voice note is transcribed and polished
(`QuickNoteDetail.swift:357–408`), nothing happens automatically. The note sits
in the Notes tab. No action items are extracted, no people mentioned in the
transcript are linked to Person records, no tasks are created. The founder has
to manually copy text, switch tabs, and create tasks. That is the opposite of a
second brain.

### 3. TaskQuickAddParser can only be triggered from inside the Tasks tab
`TaskQuickAddParser.swift` is solid — it handles `@person`, `>delegate`,
`+project`, `!priority`, natural-language dates. But there is no evidence of a
system-wide "capture bar" that can be summoned from any context. A founder
coming off a call needs one hotkey → type → done, without the Tasks tab being
open or even visible.

### 4. StandupDigest is pull-only, shallow, and only covers yesterday+today
`StandupDigest.swift:26–51` generates a markdown digest but only lists meeting
titles and task titles — no context about WHO is in those meetings, no rollup of
what was delegated to whom, no voice notes from the prior 24h. The open
commitments block (`lines:38–43`) truncates at 12 items with no priority
ordering and no grouping by person (critical for a delegator). The digest must
be manually triggered; no scheduled push.

### 5. No "between-calls" mode or session-level capture
Between 10 meetings there is no lightweight state for "I am in transit, capture
everything until my next meeting." Each voice note is a discrete object with no
temporal/session context. A founder says three things walking to their car: a
task for Sarah, a product idea, and a follow-up for the last call. All three
land as separate orphaned voice notes with no automatic linking to the recent
meeting or upcoming attendees.

### 6. Delegation tracking has no accountability loop
`TaskQuickAddParser.swift:55–64` — the `>name` delegated flag is parsed but
there is no view or digest that surfaces "things I am waiting on from others" as
a first-class list. A high-velocity founder delegates 20 items a day and needs a
real-time "waiting on" board, not a flat task list they have to filter manually.

### 7. ActionItemsChrome overflow menu has no "capture from voice" shortcut
`ActionItemsChrome.swift:430–471` — the overflow menu contains sync, re-extract,
insights, export, trash. None of these help the founder who is between calls and
wants to capture a task verbally in under 2 seconds.

---

## Existing items to endorse (from prior plan or codebase)

- `TaskQuickAddParser` shorthand syntax (`@person`, `>delegate`, `+project`,
  `due:friday`) is genuinely powerful — worth surfacing globally, not just in
  the Tasks tab.
- Auto-polish on voice notes (`QuickNoteDetail.swift:213–218`) is the right
  default — zero friction after capture.
- `FloatingOverlay` notification-based routing
  (`QuickNotesView.swift:23–29`) proves the infrastructure for cross-tab deep
  links exists; it just needs to extend to a global capture trigger.
- `PersonResolver` linking action items to people already exists per briefing —
  the missing piece is wiring voice note transcripts through the same resolver
  automatically.

---

## NET-NEW recommendations

### U4-1: Global Capture Bar (⌘⇧Space anywhere in app)
- **What:** A floating, keyboard-summoned capture bar available at all times —
  regardless of which tab is active. Accepts: typed task (full parser syntax),
  voice snippet (tap mic icon, speak, tap stop), or pasted text. Auto-detects
  intent: if the input looks like a task it goes to Tasks; if it looks like a
  note it goes to Voice Notes. One keystroke, one action, dismissed.
- **Why (second-brain angle):** Capture latency is the enemy of a second brain.
  If capture requires navigation, the thought is lost before it is logged.
  Founders between calls can summon this mid-stride.
- **Cross-feature connections:** Tasks (TaskQuickAddParser), Voice Notes
  (QuickNotesController), People (PersonResolver for @mentions)
- **Effort:** M | **Impact:** High
- **Deps:** none

### U4-2: Voice Note → Auto-Extract Pipeline
- **What:** After a voice note is polished (Ollama pass already runs), fire a
  second local LLM pass that: (a) extracts action items and creates them in
  Tasks with owner links if `@name` is mentioned, (b) links Person records for
  any people named, (c) optionally attaches the note to the most-recent meeting
  if it was recorded within 15 minutes of that meeting ending. Surface a
  "N items extracted" badge on the note row in the sidebar.
- **Why (second-brain angle):** The founder spoke the tasks out loud. The app
  transcribed them. Not extracting them is leaving value on the table — and
  requiring manual copy-paste is a fatal flow break.
- **Cross-feature connections:** Tasks (ActionItemStore), People (PeopleStore,
  PersonResolver), Meetings (link by timestamp proximity)
- **Effort:** M | **Impact:** High
- **Deps:** U4-1 (nice-to-have), existing Ollama polish pass

### U4-3: "Waiting On" Board — First-Class Delegation View
- **What:** A dedicated view (accessible from Today and Tasks) that shows every
  task where `delegated == true`, grouped by assignee (Person), with time-since-
  delegation and overdue highlighting. One-tap "nudge" that drafts an iMessage
  or email to that person referencing the task title. Auto-populates from
  `TaskQuickAddParser`'s `>name` captures and from meeting action-item
  extraction where `ownerPersonID != self`.
- **Why (second-brain angle):** A founder who delegates 20 things a day needs an
  accountability surface, not a filtered task list. The data already exists
  (`delegated` flag, `ownerPersonID`) — it just is not surfaced with the right
  hierarchy.
- **Cross-feature connections:** People (PersonDetailView, encounter log),
  Tasks (ActionItemStore), Messages (iMessage draft via MessagesAnalyzer)
- **Effort:** M | **Impact:** High
- **Deps:** none (all data already exists)

### U4-4: Between-Calls Context Session
- **What:** When the app detects a meeting just ended and another is starting
  within 30 minutes, activate a lightweight "transit session" mode. During this
  window: voice notes and quick tasks are auto-tagged with the ending meeting's
  ID and upcoming meeting attendees are pre-loaded for @mention autocomplete in
  the capture bar. When the next meeting starts, any unprocessed transit notes
  are summarized and prepended to the pre-meeting brief.
- **Why (second-brain angle):** The 10-meeting-day founder's most productive
  capture window is the 5 minutes between calls. The app knows exactly when that
  window is (calendar) and who both meetings involve (attendees). Connecting
  these closes the capture → context loop automatically.
- **Cross-feature connections:** Calendar (CalendarService.upcoming), Meetings,
  Voice Notes, People (attendee resolver), PreMeetingBriefView
- **Effort:** L | **Impact:** High
- **Deps:** U4-2

### U4-5: Proactive StandupDigest Push + Delegation Rollup
- **What:** At a configurable time (default 8:00 AM), push a macOS notification
  with the StandupDigest — but extend the digest to include: (a) delegation
  accountability summary ("You are waiting on 7 people — 3 are overdue"), (b)
  voice notes captured yesterday that produced action items, (c) first meeting
  of the day with attendee relationship health snapshot. One-click "Copy for
  Slack" from the notification.
- **Why (second-brain angle):** The current digest requires manual trigger
  (`StandupDigest.swift` is fully pull-based). A proactive push replaces the
  founder's morning scroll-and-compile ritual with one notification.
- **Cross-feature connections:** StandupDigest, Tasks (delegated filter), Voice
  Notes, People (relationship health), macOS UserNotifications
- **Effort:** S | **Impact:** High
- **Deps:** U4-3

### U4-6: Menubar Quick-Record with 1-Tap Stop
- **What:** Add a persistent menubar icon (or extend the existing FloatingOverlay
  concept) with a single-click "record voice note" and a second click to stop.
  The note transcribes and extracts in the background. No app switch required.
  Badge the menubar icon while recording so the founder can confirm it is live
  without switching away.
- **Why (second-brain angle):** The phone-in-the-hallway use case. The founder
  cannot context-switch to the app. They need always-available capture with
  zero navigation.
- **Cross-feature connections:** QuickNotesController, AudioRecorder
  (AudioRecorder.swift already handles mic + system audio with watchdog health),
  U4-2 (auto-extract)
- **Effort:** M | **Impact:** High
- **Deps:** none

---

## Top 3 picks

1. **U4-2** — Voice Note → Auto-Extract Pipeline: highest leverage because it
   converts captured audio into structured data (tasks + people links) with zero
   extra user action. Directly eliminates the biggest flow break for a
   high-velocity founder.
2. **U4-1** — Global Capture Bar: removes the navigation tax on every capture.
   Summoning Tasks or Notes without a tab switch is the single most impactful
   UX change for someone with 10+ daily context switches.
3. **U4-3** — Waiting On Board: turns the existing `delegated` flag into a
   real accountability surface. The founder already enters delegation data; the
   app just fails to surface it as a coherent view. Highest ratio of impact to
   implementation effort.
