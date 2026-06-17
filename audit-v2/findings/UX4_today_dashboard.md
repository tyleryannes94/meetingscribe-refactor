# Today View & Dashboard UX Findings — MeetingScribe v2 Audit

**Agent ID:** UX4  
**Sub-lens:** Today View & Dashboard — morning briefing quality, proactive intelligence surfacing, command-center potential

---

## Top friction points / gaps (file:line citations)

### 1. Standup digest is dumb markdown — zero AI
`StandupDigest.swift:10` generates a structured plaintext bullet list from raw data (meetings yesterday, meetings today, open tasks). There is no AI synthesis, no clustering of themes, no "what's blocked," no pattern recognition. A user pasting this into Slack still has to mentally compose the actual update. Ollama is running at zero marginal cost — this is the single most obvious missed opportunity in the whole file.

### 2. Pre-meeting brief exists in Meetings tab but is invisible from Today
`PreMeetingBriefView.swift` is mounted inside `MeetingTranscriptTab.swift:28` — only visible AFTER opening a meeting. The Today view has a `upNextCard` (TodayView.swift:664) that shows the next meeting, but there is no link or inline preview of who's in the meeting, what you discussed last time with them, or what open tasks exist for them. You have to navigate away from Today to get any context.

### 3. `turnaroundCard` only fires at ≤15 minutes — too late for prep
`TodayView.swift:167` filters to `mins >= 0 && mins <= 15`. By then there is no time to review prior context. A "prep window" should start at 30–45 minutes for important meetings and gate on relationship health (first meeting with someone? surface their profile earlier).

### 4. `StayConnectedSection` and `SuggestedPeopleView` are buried inside the "More" shelf
`TodayView.swift:150–155` — both people-context widgets are collapsed under the disclosure group. They are therefore invisible by default every morning. The whole point of "stay connected" nudges is that they surface unprompted. Hiding them defeats the purpose.

### 5. `WeeklyRecap.swift` is triggered only from `GlobalSearchView.swift:449` — never from Today
The weekly recap is structurally invisible to Today. There is no "your week so far" or "week ahead" at-a-glance. The weekly ledger in `TodayView.swift:288` shows completed tasks but has no AI narrative, no forward look, no "you have 3 big meetings this week" preview.

### 6. `HomeTasksBoard` is a heavy full-kanban on the home screen
`HomeTasksBoard.swift:83` renders a horizontally-scrolling 3-column Kanban with every open task. On a day with 40 open items this is a wall of cards. The board belongs in the Tasks tab; Today should have a curated 3–5 task "focus list" for the day — not a complete project board.

### 7. No LLM-generated "morning insight" anywhere on Today
Today assembles data from 8 different sources (meetings, tasks, decisions, follow-ups, people, notes, commitments, on-this-day) but never synthesizes them. There is no sentence like "You have 3 back-to-back meetings with Sarah's team and 2 overdue items from last week's session with her." Ollama can generate this in under 2 seconds at zero cost.

### 8. `NeedsAttentionWidget` links are not person-contextualized
`NeedsAttentionWidget.swift:73` shows meeting title + due date but no `ownerPersonID`. You can't tell from the widget whether an overdue task is your own commitment or something you're waiting on from someone else. The `commitmentsSection` in TodayView.swift:389 splits owe/owed but is also buried in "More."

### 9. `dayShapeStrip` shows counts, not quality signals
`TodayView.swift:712` shows "N meetings left," overdue count, and next meeting time. It doesn't surface: "You haven't met with Alex in 3 weeks and you're meeting them at 2pm," "You have 5 overdue items from this person," or any quality signal. It's a counter, not a briefing.

### 10. No persistent "Today's focus" — the user has no way to set intention
There's no lightweight mechanic for Tyler to say "my top 3 things today are X, Y, Z." The closest analog is the HomeTasksBoard with the "Today" filter, but that's passive (due-date-based) not intentional.

---

## Existing items to endorse (from prior plan or codebase)

- **turnaroundCard (U3-2):** Good mechanic, needs a wider prep window and person-context injection.
- **1:1 section (U1-1):** Person-first 1:1 cards with open loops and last-met — exactly right model; extend it with the pre-meeting brief data.
- **dayShapeStrip (U3-3):** Right idea, wrong signals — evolve to quality not just quantity.
- **onThisDay section (C2-9):** Genuinely useful second-brain feature; keep and expand with AI context ("a year ago you committed to X with this person — did it happen?").
- **StayConnectedSection:** The logic is correct; the placement (buried in "More") is wrong.
- **commitmentsSection owe/owed split:** Solid data model; needs to move above the fold.

---

## NET-NEW recommendations

### UX4-1: AI Morning Briefing Card — "Your day in one paragraph"
- **What:** A single LLM-generated card at the top of Today (below the header, above quickActions) that synthesizes the day's signals into 3–4 sentences. Uses local Ollama. Prompt feeds in: today's meetings + attendees, overdue count + who they involve, top open commitment due today, and one relationship nudge. Regenerates once per morning (cached to disk, TTL until midnight). Shows a shimmer skeleton while loading so page renders immediately.
- **Why (second-brain angle):** This is the qualitative leap from "widget collage" to "morning briefing." The user sees one sentence that connects people → tasks → meetings before any tab is clicked.
- **Cross-feature connections:** Meetings (attendees → People), Tasks (overdue items + ownerPersonID), People (relationship health, last interaction), Decisions (any unresolved decision relevant to today's meeting).
- **Effort:** M | **Impact:** High
- **Deps:** OllamaService already integrated; PreMeetingBriefView shows the data model exists.

### UX4-2: Inline Pre-Meeting Context Strip on Meeting Cards
- **What:** Each meeting card in `todaySection` (and `oneOnOneDaySection`) gets a collapsible context strip (2-3 lines) showing: last time you met this person, the one open loop from that meeting, and a talking point from their People record. Strip is generated at render time from existing data — no LLM needed. Expand on hover or via a "Prep" chevron.
- **Why (second-brain angle):** Right now the pre-meeting brief is only accessible by clicking into the meeting. Moving a digest of it onto the Today card means Tyler never has to navigate away to remember "what did I owe Sarah."
- **Cross-feature connections:** PreMeetingBriefView (same data, inline view), People (encounters + talkingPoints), Tasks (ownerPersonID filter).
- **Effort:** M | **Impact:** High
- **Deps:** UX4-1 (establishes pattern); PersonResolver already resolves attendees to People records.

### UX4-3: Move "Stay Connected" and Commitments Above the Fold
- **What:** Pull `StayConnectedSection` and the owe/owed `commitmentsSection` out of the "More" shelf and give them persistent above-fold placement, ordered by urgency. Limit to 2 items each (most urgent) with a "Show all" link. Add a "Dismiss for today" per item so it's not noisy.
- **Why (second-brain angle):** Proactive nudges only work if they're visible. Hiding relationship health signals behind a disclosure group means the user has to remember to look — defeating the entire purpose of a second brain.
- **Cross-feature connections:** People (health scores + overdueDays), Tasks (owe/owed split), Meetings (which meeting spawned the commitment).
- **Effort:** S | **Impact:** High
- **Deps:** none (existing components, layout change only).

### UX4-4: AI-Enhanced Standup Digest
- **What:** Add a second generation mode to `StandupDigest.swift`: an Ollama-synthesized paragraph mode alongside the existing bullet-list mode. The AI version gets the same structured data but outputs: a 3-sentence first-person standup, a "blockers" sentence if overdue items exist, and a "shipping today" line if any in-progress tasks are due. Toggle between modes in the sheet. The bullet mode remains as fallback.
- **Why (second-brain angle):** The current standup requires Tyler to transform data into prose mentally. The AI version transforms "what happened" into "what I'd actually say in a standup call."
- **Cross-feature connections:** Tasks (in-progress + overdue), Meetings (yesterday + today), People (meeting attendees → who is involved in each item).
- **Effort:** M | **Impact:** Med
- **Deps:** OllamaService; UX4-1 establishes the Ollama morning-synthesis pattern.

### UX4-5: "Today's Focus" Pinning — Intentional Task Surfacing
- **What:** Add a lightweight 3-slot "Focus for today" section above the HomeTasksBoard. The user picks up to 3 tasks from anywhere (drag from board, or a picker popover) and pins them for the day. Persisted via `@AppStorage` with a midnight TTL. If the user hasn't set focus by 9am, AI suggests 3 candidates based on: due date, last-touched, and which meeting they came from. Board still exists below but is visually subordinate.
- **Why (second-brain angle):** Intention-setting is what separates a second brain from a task dump. Today should help the user commit to their top 3 before diving in.
- **Cross-feature connections:** Tasks (ActionItemStore), Meetings (task provenance — which meeting created this task), People (if a task has an ownerPersonID, surface whose relationship it serves).
- **Effort:** M | **Impact:** High
- **Deps:** HomeTasksBoard already exists; this wraps it with a focus layer.

### UX4-6: Relationship-Aware Meeting Prep Window Expansion
- **What:** Extend `turnaroundCard` trigger window from ≤15 min to ≤45 min, with tiered urgency: 45-30 min shows a softer "Prep window" state; 15-0 min shows the current gold urgency. For first-ever meetings with a person (no prior encounters), expand to 60 min and surface a "First meeting brief" — summarizing everything MeetingScribe knows about them from other data (shared meetings via other People, iMessage data if any, LinkedIn-style notes from their People record).
- **Why (second-brain angle):** 15 minutes to prep is firefighting. 45 minutes is planning. The data to make this valuable already exists.
- **Cross-feature connections:** People (encounters count, lastInteractionAt, talkingPoints, memories), Meetings (prior meetings with attendees).
- **Effort:** S | **Impact:** High
- **Deps:** none (existing turnaroundCard; PersonResolver + PeopleStore already accessible).

### UX4-7: "On This Day" LLM Context Thread
- **What:** For each `onThisDay` meeting card, add a one-line AI-generated note: "At this meeting you committed to X — status: [open/done]." This threads historical meeting to present commitments without the user having to open the old meeting. Uses per-card Ollama inference, lazy-loaded.
- **Why (second-brain angle):** The "on this day" feature resurfaces the past but leaves interpretation to the user. Adding commitment-threading makes it truly actionable — "remember this? here's what happened to it."
- **Cross-feature connections:** Decisions (DecisionStore), Tasks (meetingID foreign key → which tasks came from this meeting), People (who was in the meeting and whether you've met them since).
- **Effort:** M | **Impact:** Med
- **Deps:** UX4-1 establishes Ollama synthesis pattern.

---

## Top 3 picks

1. **UX4-1 — AI Morning Briefing Card:** Transforms Today from a widget collage into a genuine morning briefing with a single LLM call. Highest possible signal-to-noise ratio improvement; connects all 5 tabs in one paragraph. Zero new data models needed.

2. **UX4-3 — Move Stay Connected + Commitments Above the Fold:** The relationship nudges and owe/owed splits are already built correctly; they're just invisible. This is a layout fix with outsized behavioral impact — it makes the second brain proactive instead of reactive.

3. **UX4-5 — Today's Focus Pinning:** Adds the missing intentionality layer. Today tells you what's happening; Focus tells you what you're committing to. Together they cover the full morning ritual: orient → commit → execute.
