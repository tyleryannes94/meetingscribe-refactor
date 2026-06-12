# End-User — Engineering Manager (7 direct reports)
> I live in People and Meetings: weekly 1:1s with 7 reports, skip-levels, and perf-review season — I need per-person context in seconds, not clicks, before and during every 1:1.

## Full-app audit (through my lens)

### Scenario 1 — Monday morning, five back-to-back 1:1s (8:55am, coffee in hand)

I open the app to answer one question: *who am I meeting, and what do I owe each of them?* Today can't answer it.

- **Today's feed ordering buries my day.** `TodayView.swift:52-105` stacks: header → record button → `upNextCard` → NeedsAttention → today's meetings → ActionItems → follow-ups → commitments → decisions → on-this-day → voice notes → suggested people → StayConnected → Reconnect. My five 1:1s are the *fifth* block; the people-context surfaces (StayConnected, Reconnect) are dead last, below "On this day." On a 1:1-heavy day, meetings and the humans in them should lead.
- **`upNextCard` is person-blind.** `TodayView.swift:442-467` shows title, relative start, Join & Record, Open — no avatar, no attendee, no "open commitments: 3", no last-time one-liner. For "Weekly 1:1 — Priya" the single most valuable glance (what we left off on) requires leaving Today.
- **The pre-meeting brief exists but is hidden inside a tab named "Transcript."** `PreMeetingBriefView` is genuinely good — series-aware via `seriesID` (`PreMeetingBriefView.swift:199-209`), carries forward the last occurrence's summary plus open commitments, synthesizes via Ollama. But it's only rendered as the `.upcoming` branch of `transcriptBody` (`MeetingTranscriptTab.swift:24-29`). Nobody preps for a 1:1 by clicking a tab labeled Transcript on a meeting that has no transcript.
- **Click count, Monday prep for 7 reports:** Today → Open meeting (1) → Transcript tab (2) → wait for Ollama generation (~5-15s, `PreMeetingBriefView.swift:229-238`) — per meeting. For the reports I'm *not* meeting today but want a pulse on: People tab (1) → find person (2) → Meetings tab (3) → open last 1:1 (4) → Actions tab (5). **~5 clicks + LLM latency × 7 people ≈ 35-40 interactions** for what should be one digest.
- **The brief is regenerated on every visit.** `brief`/`briefMeetingID` are `@State` (`PreMeetingBriefView.swift:23-25`) — navigate away and back, the view re-instantiates and re-pays the Ollama latency. Nothing is persisted.

### Scenario 2 — Mid-1:1, "wait, what did you commit to last week?"

Priya is talking; I have ~4 seconds of socially acceptable screen-glancing.

- **Hitting Record destroys the brief.** The moment the meeting goes `.live`, `transcriptBody` swaps to `LiveTranscriptScroll` (`MeetingTranscriptTab.swift:20-23`). The "Open commitments to follow up" list I had 2 minutes ago is now unreachable from inside the meeting I'm in.
- **The recurring-series sidebar is notes-only and read-only.** `MeetingNotesTab.swift:8-127` renders "CALLS IN THIS SERIES" with prior occurrences — the right idea — but it shows only `userNotes`, not the prior summary or its action items, and lives in the Notes tab.
- **Fallback path mid-call:** People tab → Priya → Tasks tab. But person↔task matching is owner-*string* token matching (`PersonDetailView.swift:1486-1497` — first name "priya" in a free-text owner field), undirected (no "she owes me" vs "I owe her" — the Today split at `TodayView.swift:159-182` matches against *my* name aliases only), and that's still **4 clicks while a human watches me**.
- **Series exist only if the calendar says so.** `seriesID` is set solely from `event.hasRecurrenceRules` (`CalendarService.swift:178`); ad-hoc recordings get `seriesID: nil` (`TodayView.swift:642`, `MeetingManager.swift:1131`). The impromptu "got 15 minutes?" 1:1 — half of management — never joins the thread, so the next week's brief can't see it.
- **The person record doesn't know its 1:1 series exists.** `meetingHistorySection` (`PersonDetailView.swift:1209-1230`) is a flat reverse-chron list where "Weekly 1:1 — Priya" appears 26 times interleaved with every staff meeting she attended, capped at `prefix(30)` (line 1224), with no summary snippet per row. There is no "this is our recurring 1:1, here's the thread" object anywhere on her profile, and no "next meeting with her" either (the identity pane shows past only; `addToMeetingSheet` at line 373 is write-only).

### Scenario 3 — Perf-review season, six months of evidence per report

- **The data is captured but uncompilable.** Per report I need: every 1:1 (recorded + quiet), what they committed to and delivered, decisions they drove, growth notes. Today: Meetings tab capped at 30 rows, no date-range filter, no export; Decisions capped at `prefix(8)` (`PersonDetailView.swift:1174-1178`); memories and attached notes on a separate tab. Compiling H1 evidence for 7 reports is an afternoon of clicking and copy-paste.
- The master plan *has* "Performance-review compilation" — in Phase 3, **and** on the explicit defer list ("manager-persona-only; defer until the wedge confirms"). From inside this persona: this is the single moment the app would earn its keep for a year, twice a year, and most of it needs zero LLM (see U1-4).

### What's already strong (credit where due)

- The unified recorded+calendar timeline on person detail (`PersonDetailView.swift:1157-1230`, U2-1) means my unrecorded 1:1s no longer read as "we never met." Genuinely manager-aware.
- `MeetingPersonConnectPanel` (`UnifiedMeetingDetail.swift:153-163`) — linking an attendee to a person without losing meeting context is the right interaction model. One nit: for an *already-linked* attendee, left-click still opens the connect panel; navigating to their profile is right-click → "Open in People" only (`MeetingDetailHeader.swift:799-833`). The common case (open my report's profile from our 1:1) is hidden behind the rare case (re-link).
- `EncounterHeatMap` + per-person check-in goal (`PersonDetailView.swift:1417-1466`) — a 13-week consistency view per report is exactly skip-level hygiene.
- Meetings search matches attendee strings (`MeetingsView.swift:227-232`), so "priya" does filter — though as text, not as a person entity.
- One bug-level mismatch: `QuickEncounterSheet`'s doc comment promises "auto-saves on tap" / "sheet dismisses automatically after step 1" (`QuickEncounterSheet.swift:71-74`) but the code only toggles `selectedKind` (line 123-127) and requires the explicit Save button (line 188-196). The 10-second-log design goal is currently not met. Also: the `Kind` chips (Call/Coffee/Video/Message/Met Up/Milestone, lines 9-40) have no "1:1" — the manager's most common encounter literally has no chip.

## Existing-plan items I rank highest

1. **Per-report 1:1 prep digest (2H)** — the single highest-leverage planned item for this persona; the raw materials (`PreMeetingBriefView`, growth themes, commitments) all converge here.
2. **Quiet 1:1 capture (2B)** — half my 1:1s are walks; without unrecorded stubs every downstream surface (health, briefs, review evidence) lies.
3. **Directed commitments — iOwe/theyOwe + personID (2C)** — kills the fragile owner-string matching (`PersonDetailView.swift:1486-1497`) that mid-1:1 recall depends on.
4. **Proactive pre-meeting brief N min before (2D)** — the brief must come to me; today I excavate it from the Transcript tab.
5. **`selectedPersonID` on router + EntityLink (2A)** — deletes the NotificationCenter-plus-50ms-delay person-open hack (`TodayView.swift:628-634`, `PeopleListView.swift:125-127`).
6. **Growth-theme threads (2B)** — the connective tissue between weekly 1:1s and review season.

## NET-NEW recommendations

### U1-1 — "Your 1:1 Day" person-first rail on Today
- **What/why:** A horizontal card rail pinned at the top of Today on meeting days: one card per meeting, **person-first** — avatar, name, time, health dot, "owes you 2 · you owe 1," and a one-line "last time:" carry-over. Click expands the full brief inline. This is the *aggregated morning surface* the planned per-meeting prep digest (2H) still lacks — that item extends `PreMeetingBriefView` (one meeting at a time, inside detail); this is the 8:55am answer for all five at once. Reorder `TodayView.feed` so this rail + today's meetings lead and the relationship strips move up, above "On this day."
- **User value:** Monday prep drops from ~35-40 interactions across 7 people to **0 clicks** (glance) / 1 click per deep-dive.
- **Effort:** M
- **Impact:** High
- **Depends on:** U1-10 (cached briefs); amplifies planned 2H/2D.

### U1-2 — Series ⇄ Person binding: the "1:1 home"
- **What/why:** Detect recurring series whose attendee set is exactly {me, one person} and bind `seriesID` → `Person`. Then: (a) person Meetings tab pins a collapsible "Weekly 1:1" group at top instead of 26 interleaved flat rows (`PersonDetailView.swift:1209-1230`); (b) meeting detail for a bound series shows a person sidebar (health, open commitments, talking points); (c) "Add to this series" on ad-hoc recordings with the same person backfills the `seriesID: nil` gap (`CalendarService.swift:178` only sets it from calendar recurrence). The connection the app *almost* has (`PreMeetingBriefView.swift:199-209` uses seriesID; the person record never does) becomes first-class and bidirectional.
- **User value:** "Open our 1:1 thread" from a person = 1 click; impromptu 1:1s stop falling out of the series; the People pillar finally reaches *inside* meetings.
- **Effort:** M
- **Impact:** High
- **Depends on:** none (enables U1-4, U1-6, U1-8).

### U1-3 — "Last time" panel survives hitting Record
- **What/why:** When recording a meeting that has series context, keep the brief reachable: a collapsible "Last time" pane (or live-tab toggle) alongside `LiveTranscriptScroll` instead of the brief vanishing the moment mode goes `.live` (`MeetingTranscriptTab.swift:20-29`). Show last summary + open commitments with tap-to-complete checkboxes.
- **User value:** Mid-1:1 "what did you commit to?" goes from 4-6 clicks in another tab to **0 clicks, already on screen**.
- **Effort:** S
- **Impact:** High
- **Depends on:** U1-10 helps; pairs with planned in-meeting scratchpad (2D).

### U1-4 — Deterministic per-person evidence compiler (pull perf-review forward)
- **What/why:** The plan defers "performance-review compilation" to Phase 3 as an LLM feature. 80% of it is a **deterministic concat that could ship now**: "Compile Jan–Jun" on the person Meetings tab emits chronological markdown — every meeting (recorded + calendar + quiet), its summary bullets, this person's commitments + completion status, decisions, dated memories. Remove the `prefix(30)`/`prefix(8)` caps behind a date-range picker. LLM synthesis layers on later.
- **User value:** Review evidence per report: an afternoon of clicking → 1 click. Twice a year × 7 reports, this alone justifies a license.
- **Effort:** M
- **Impact:** High
- **Depends on:** U1-2 (series grouping makes output coherent); better with 2C.

### U1-5 — "Discuss next time" talking-points inbox per person
- **What/why:** Between 1:1s I accumulate "raise X with Priya" thoughts; the app has no home for them — memories are past-facing, tasks are owned work. Add a lightweight per-person "Discuss next time" list: quick-capture from person detail, the meeting view, and Cmd-K ("@priya: discuss conference budget"); auto-inserted as a section in the next 1:1's brief; check-off in-meeting moves them to the meeting record. (The Fellow.app mechanic, locally.) Not anywhere in the existing plans.
- **User value:** Closes the capture→prep loop; nothing I owed a report a conversation about silently evaporates between Tuesdays.
- **Effort:** M
- **Impact:** High
- **Depends on:** none; surfaces via U1-1/U1-3.

### U1-6 — Commitment carry-forward on series finalize
- **What/why:** When a series occurrence finalizes, diff its open action items against the new meeting: anything unresolved from last week surfaces as "Still open from last 1:1 — carry forward / mark done / drop," relinking carried items to the new occurrence. Plans cover creating tasks from meetings (2C) and a ledger, but not the *series-hop review* that keeps a 1:1 thread truthful week over week.
- **User value:** Briefs stop re-listing zombie commitments; quiet accountability without my spreadsheet.
- **Effort:** M
- **Impact:** Med
- **Depends on:** 2C directed commitments; U1-2.

### U1-7 — Scope the brief's open items to the counterpart
- **What/why:** `computeBrief()` flatMaps open items from *every* meeting sharing *any* attendee (`PreMeetingBriefView.swift:169-181`). For a skip-level with someone who attends all-hands, the "open commitments" list is polluted with other people's items from group meetings. Filter to items owned by the 1:1 counterpart (via `ownerPersonID`) + items I owe them; group meetings only contribute items belonging to us two.
- **User value:** The brief reads like it knows who I'm meeting — precision is what makes me trust it mid-conversation.
- **Effort:** S
- **Impact:** Med
- **Depends on:** 2C personID (string-match fallback works today).

### U1-8 — Make QuickEncounterSheet honor its own contract + add a "1:1" kind
- **What/why:** Two surgical fixes: (a) the sheet's stated design ("tap a Kind chip — auto-saves on tap," `QuickEncounterSheet.swift:71-74`) doesn't match the code (tap only selects, line 123-127; Save is a separate click) — make kind-tap save immediately with a 3s undo toast, mood/note editable in the toast window; (b) add `oneOnOne = "1:1"` to `Encounter.Kind` (lines 9-40) — the most common professional encounter has no chip, so quiet 1:1s get logged as "Coffee."
- **User value:** Log a hallway 1:1 in literally one tap (currently 3+); encounter data stops misrepresenting work interactions.
- **Effort:** S
- **Impact:** Med
- **Depends on:** none; complements planned quiet 1:1 capture (2B).

### U1-9 — Linked attendee chip: navigate first, manage second
- **What/why:** In meeting detail, left-clicking an attendee who already *is* a person still opens the connect panel; profile navigation hides in the context menu (`MeetingDetailHeader.swift:29, 799-833`). Invert for linked attendees: left-click → rich hover-card/popover (avatar, role, health, open commitments, "Open profile") matching the planned 2A hover-card; "Manage link…" moves to the context menu. Unlinked attendees keep the connect-panel default.
- **User value:** Person context from within any meeting: right-click-and-hunt → 1 left click. This is the "people are first-class inside meetings" pillar at the chip level.
- **Effort:** S
- **Impact:** Med
- **Depends on:** refines planned 2A attendee hover-card (concrete interaction spec).

### U1-10 — Persist and pre-warm briefs
- **What/why:** Briefs are `@State`-only and regenerate per view instance (`PreMeetingBriefView.swift:23-25, 184-190`). Persist generated brief markdown per meeting (keyed on meetingID + latest-prior-occurrence ID for invalidation); on launch / morning, pre-generate today's briefs in a background Ollama queue.
- **User value:** Briefs become instant glances instead of 5-15s spinners — the difference between a habit and a feature.
- **Effort:** S
- **Impact:** High (it's the latency floor under U1-1/U1-3 and planned 2D)
- **Depends on:** none.

### U1-11 — "My Team" pinned smart group + work-aware types
- **What/why:** `RelationshipType` has no work granularity beyond `colleague` at a 30-day cadence (`Person.swift:56-88`); the plan's "Team view / org rollup" is Phase-3-deferred. Ship the minimal version now: `directReport` and `manager` types (or a privileged "Team" tag), a pinned "My Team" group at the top of the People sidebar (above ghosts, no re-filtering every visit — `PeopleListView.swift:43-65` filters are transient `@State`), default 7-day cadence for reports. The org-rollup analytics can stay deferred; the *grouping* shouldn't.
- **User value:** My 7 reports are always 1 click away, sorted by 1:1 recency/health — the People tab opens to my actual job.
- **Effort:** S
- **Impact:** High
- **Depends on:** none; concrete pull-forward/redesign of deferred Phase-3 team view.

## Top 3 picks

1. **U1-1 — "Your 1:1 Day" rail on Today** — converts the app's best hidden asset (the series-aware brief) into the zero-click morning surface a manager opens the app for.
2. **U1-5 — "Discuss next time" talking-points inbox** — the one genuinely missing object in the data model; closes the between-meetings → in-meeting loop no planned item touches.
3. **U1-2 — Series ⇄ Person binding** — the structural fix making person and 1:1-series one navigable thing; everything else (briefs, evidence, carry-forward) stands on it.

**Single highest-priority rec overall:** U1-1 (with U1-10 as its enabler) — it serves all four pillars at once: usability (40 clicks → 0), navigation (one hop to any 1:1's context), people-in-meetings (person-first meeting cards), and the premium feel (a Notion-Calendar-grade "your day" hero is exactly what "clean and expensive" looks like on a manager's Monday).
