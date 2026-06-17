# U1 — Daily Executive / Meeting-Heavy User Persona Findings — MeetingScribe v2 Audit

*Persona: 5–8 meetings/day, back-to-back, needs instant context switching. 6 meetings today, first one starts in 10 minutes.*

---

## Top friction points / gaps (file:line citations)

### 7am: prep for first meeting
- **Pre-meeting brief requires manual navigation.** To access `PreMeetingBriefView`, the user must open the Meetings tab and tap into the specific calendar event. There is no automatic "You have a meeting in 10 minutes — here's your brief" push to Today. `TodayView.swift:66` has `upNextCard` and `turnaroundCard`, but `turnaroundCard` only fires when ≤15 min remain and shows one line of context — not the full brief.
- **Brief synthesis is cold at 7am.** `BriefCache` (`PreMeetingBriefView.swift:438`) stores briefs, but only after a user has manually opened that meeting once. A user arriving at 7am cold (app relaunched overnight) gets a loading spinner ("Synthesizing brief…") the moment they need to walk into a meeting.
- **No proactive "today's meeting dossier" surface.** `dayShapeStrip` (`TodayView.swift:711`) shows meeting count, first meeting time, and overdue tasks — a great 10-second scan — but carries no narrative AI context. The user still has to open each meeting to read its brief.
- **1:1 cards don't deep-link to the brief.** `oneOnOneDaySection` (`TodayView.swift:228`) routes via `router.openMeeting(pair.meeting)`, which opens the meeting detail, not the pre-meeting brief tab within it. An extra tap is required to get to the actionable context.

### Between meetings: context switching in 90 seconds
- **turnaroundCard is 15-min-window only.** Once a meeting ends and the next starts within 2 minutes, `turnaroundCard` (`TodayView.swift:165`) fires correctly — but it shows only title, one person's name, and open loop count. There is no "what ended, what's next, what changed" synthesis. The user must either remember or re-navigate.
- **No "just ended" card.** After `manager.lastStoppedMeetingID` fires (`MainWindow.swift:614`), Today does not surface "Your last meeting just finished — 3 action items extracted." The user learns about extracted items only by navigating to the Meetings tab.
- **Action items from the just-ended meeting are not injected into Today until the next `refreshPastMeetings()` cycle.** `MainWindow.swift:617` calls `manager.refreshPastMeetings()` on stop, but `NeedsAttentionWidget` (`TodayView.swift:71`) may not immediately reflect newly extracted items if the transcription/extraction pipeline is still running.
- **Pre-meeting brief is not pre-warmed proactively.** `BriefCache.load()` is checked only when the user opens `PreMeetingBriefView`. A background job warming briefs for all today's upcoming meetings at app launch does not exist.

### End of day: catch-up and follow-up
- **Follow-ups section is collapsed under "More."** `followUpsSection` (`TodayView.swift:344`) is hidden behind `moreSection` disclosure (`TodayView.swift:107`). A user with 6 meetings ending at 6pm who needs to send follow-up emails must expand "More" to see them. This is high-friction at end-of-day.
- **No "end of day" mode or session.** The app has no concept of a daily closing workflow: review what was decided, confirm all action items are captured, batch-send follow-ups, and schedule what's deferred. Users must manually stitch this together across Today, Meetings, and Tasks tabs.
- **Weekly ledger is also behind "More."** `weeklyLedgerSection` (`TodayView.swift:287`) is hidden. An exec checking "what did I do today?" at 6pm has to expand the disclosure first.
- **"Copy as update" is the only follow-up automation.** `weeklyUpdateText()` (`TodayView.swift:318`) copies a formatted text block, but it covers the whole week. No meeting-level follow-up email draft is generated.

### Weekly review on Friday
- **No dedicated Friday / week-end surface.** `WeeklyRecap` exists as a file (referenced in briefing), but there is no "Run weekly review" trigger in Today, and no UI that presents a synthesized "here's what your week looked like across all 30 meetings" view.
- **Standup digest is accessible via a button** (`TodayView.swift:601`) but is for morning standup context, not an end-of-week review.
- **Decisions are buried in "More."** `decisionsSection` is inside the collapsed `moreSection`. An exec doing a Friday review of "what did we decide this week?" has no fast path.

---

## Existing items to endorse (from prior plan or codebase)

- **turnaroundCard (U3-2):** Good foundation for between-meeting context switching. Needs expansion (see U1-2 below).
- **dayShapeStrip (U3-3):** The 10-second morning scan is the right UX pattern. Extend it with AI narrative.
- **BriefCache (PreMeetingBriefView.swift:438):** Smart caching pattern. The right infrastructure — just needs proactive warming.
- **oneOnOneDaySection (U1-1):** Person-first 1:1 view is exactly right for this persona. Needs brief deep-link.
- **followUpsSection (P2-6/U3-3):** The right feature — wrong placement (behind "More").
- **weeklyLedgerSection (U3-6):** Useful — wrong placement.
- **Prior plan item 1-1 (WorkspaceContext):** Work/personal separation is table stakes for an exec with mixed personal/professional calendars.

---

## NET-NEW recommendations

### U1-1: Proactive Morning Brief Push to Today
- **What:** At app launch (or at a user-configured time, e.g., 7:00am), run a background job that pre-warms `BriefCache` for all of today's calendar meetings (iterate `calendar.upcoming` filtered to today, call `OllamaService().generate(...)` for each with no prior user interaction required). Surface a collapsible "Today's briefs ready" card at the top of `TodayView` — tapping any meeting title deep-links directly to `PreMeetingBriefView`, not the meeting detail root.
- **Why (second-brain angle):** The second brain should push intelligence to the user before they ask. An exec arriving 10 minutes before their first meeting should see their briefs waiting, not need to navigate to find them.
- **Cross-feature connections:** CalendarService (upcoming list) → PreMeetingBriefView (synthesis) → TodayView (push card) → People (talking points per attendee). Bridges Today, Meetings, and People in one feature.
- **Effort:** M | **Impact:** High
- **Deps:** BriefCache already exists; needs background job scheduling and Today card UI.

### U1-2: Expanded turnaroundCard with "Just Ended / Up Next" Dual Panel
- **What:** Replace the single-line `turnaroundCard` with a two-panel transition card that appears after a meeting ends and a next one is within 30 minutes. Left panel: "Just finished — [Title] — N action items extracted, M decisions made, 1 follow-up to send." Right panel: "Up next in X min — [Title] — brief summary (pulled from BriefCache), open loops with attendees." One-tap actions: "Mark follow-up sent", "Open brief", "Add action item."
- **Why (second-brain angle):** The 90-second gap between meetings is the highest-leverage moment in an exec's day. The app should hand them a context snapshot, not make them navigate.
- **Cross-feature connections:** MeetingManager (lastStoppedMeetingID) → ActionItemStore (new items) → BriefCache (next brief) → TodayView. Pure interconnectedness play — bridges Meetings, Tasks, and Today.
- **Effort:** M | **Impact:** High
- **Deps:** U1-1 (brief pre-warming), `manager.lastStoppedMeetingID` (already published, MainWindow.swift:614).

### U1-3: End-of-Day Digest Mode
- **What:** After the last meeting of the day (detected when `calendar.upcoming` has no more meetings today and a meeting ended within the last 2 hours), surface a pinned "End of Day" card in Today containing: (1) all extracted action items from today's meetings, grouped by meeting, with one-tap assign/defer; (2) all pending follow-up emails in one list with AI-drafted one-liners per meeting; (3) decisions made today; (4) "Close day" button that marks the digest seen and collapses it. This replaces the need to manually navigate to "More" → followUpsSection.
- **Why (second-brain angle):** End-of-day is when context is lost if not captured. Proactively aggregating everything from the day removes the cognitive load of "did I miss anything?"
- **Cross-feature connections:** CalendarService (last meeting detection) → MeetingManager (today's meetings + action items + decisions) → PeopleStore (follow-up recipients) → TodayView. Cross-cuts Today, Meetings, Tasks, and People.
- **Effort:** L | **Impact:** High
- **Deps:** U1-2 (the just-ended detection pattern), DecisionStore, followUpsSection logic.

### U1-4: Friday Weekly Intelligence Report (Proactive, Not Manual)
- **What:** Every Friday afternoon (or whenever the user opens Today on Friday after 3pm), auto-generate and surface a "Your week" card in Today with: meeting count, total time in meetings, top decisions (pulled from DecisionStore), completed vs. created action items ratio, relationship health changes (who did you meet most, who drifted), and a 3-sentence AI narrative ("You had a heavy week — 32 meetings, 18 action items closed. Two key decisions were made on Project X. You haven't spoken to Sarah in 2 weeks despite 3 open loops."). One-tap exports to Notion or copies as Slack update.
- **Why (second-brain angle):** An exec shouldn't have to ask for a weekly review — the second brain should volunteer it. `WeeklyRecap.swift` already generates markdown; this surfaces it proactively with people-aware context layered on top.
- **Cross-feature connections:** WeeklyRecap → DecisionStore → PeopleStore (relationship health) → ActionItemStore (weekly completions) → TodayView → Notion/Obsidian export. Highest-connectivity feature in this list.
- **Effort:** M | **Impact:** High
- **Deps:** WeeklyRecap.swift already exists. Needs Friday detection, Today card UI, people-health delta.

### U1-5: Promote followUpsSection and decisionsSection Out of "More"
- **What:** Remove `followUpsSection` and `decisionsSection` from the `moreSection` collapse and promote them to be always visible below `NeedsAttentionWidget` in the main feed — but only when they have content (0-state hidden). The "More" collapse is useful for sections that are always present; follow-ups and decisions are time-sensitive and should be loud.
- **Why (second-brain angle):** Follow-ups rot within 24 hours. Hiding them behind a disclosure is a reliability failure — the user misses them and the app loses trust as a second brain.
- **Cross-feature connections:** TodayView layout only. Minimal effort, high daily value.
- **Effort:** S | **Impact:** High
- **Deps:** none.

### U1-6: Live Brief Injection into Recording Notes
- **What:** When a recording starts for a calendar meeting that has a cached brief, automatically inject the brief text into the meeting's notes at the top as a collapsible "Pre-meeting context" block (the hook exists: `manager.attachBriefToNotes` is already called at `PreMeetingBriefView.swift:385`). During recording, show the brief in a persistent side drawer or overlay so the user can glance at it without leaving the recording UI.
- **Why (second-brain angle):** Having the brief available during the meeting (not just before) means the exec can reference open loops in real time. Currently `attachBriefToNotes` only fires if the meeting was already recorded (`onlyIfRecorded: true` flag), which means it never helps during a live recording.
- **Cross-feature connections:** PreMeetingBriefView (BriefCache) → MeetingManager (startRecording) → MeetingRecordDock (recording overlay). Bridges pre-meeting prep with live recording.
- **Effort:** S | **Impact:** High
- **Deps:** Fix `onlyIfRecorded: true` to also fire on new recordings.

---

## Top 3 picks

1. **U1-1** — Proactive morning brief push eliminates the #1 friction moment (arriving at a meeting cold). Zero new AI infra needed — just background warming of existing synthesis.
2. **U1-5** — Promoting followUpsSection/decisionsSection out of "More" is an S-effort change with immediate daily impact for any exec user. The most ROI-efficient fix in this list.
3. **U1-3** — End-of-Day Digest Mode closes the loop on the whole day and makes the app feel like a genuine second brain rather than a passive recorder. This is the feature that makes an exec tell a colleague "you need this app."
