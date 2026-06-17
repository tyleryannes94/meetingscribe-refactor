# People Feature UX Findings — MeetingScribe v2 Audit

**Agent:** UX2 — Senior Product Designer, People Feature UX sub-lens
**Files audited:** PeopleListView.swift, PersonDetailView.swift, KeepInTouchBoard.swift, PeopleInsightsView.swift, Person.swift

---

## Top friction points / gaps (file:line citations)

### 1. The detail view is a scroll wall — no information hierarchy
`PersonDetailView.swift:361–374` builds an `HSplitView` with a `detailPane` on the left. That pane is a single long ScrollView of sections stacked sequentially: identity → health → type → tags → favorites → AI suggestions → talking points → memories → messages → notes → encounters → meetings → relationships → people graph insets → perf evidence. There is no visual hierarchy separating "now-relevant" from "historical reference." A first-time open of a person you just met presents a mostly-empty wall of section headers. The `PersonTab` enum exists (overview / meetings / tasks / messages / notes) but reading the HSplitView body, tabs are shown in the detail pane header — not used to progressively disclose the section list — so every tab still renders the same wall with different sections foregrounded.

### 2. iMessage analysis is buried behind 3–4 clicks
`PersonDetailView.swift:2166–2228`: the Messages section only appears after scrolling to it, requires "Analyze" → menu → preset choice → time range → "Run analysis." For the app's most powerful intelligence feature, the entry point is a borderless-button label inside a section the user has to find first. There is no proactive nudge to run analysis on a person who has substantial iMessage history but no analysis yet.

### 3. Relationship type defaults to `.unset` with no first-open prompt
`Person.swift:313` defaults `relationshipType` to `.unset`. The keep-in-touch board (`PeopleListView.swift:101`) only shows people where `relationshipType != .unset`. `PeopleInsightsView.swift:29` only surfaces "Reconnect" using `reconnectThresholdDays` which is also type-dependent. The result: new people added manually or via transcript extraction are invisible on the board and get generic thresholds — but the app never prompts the user to set the type. The `relationshipTypePicker` at `PersonDetailView.swift:877` is buried in the identity panel, below the fold on first render.

### 4. No "first-open experience" for a person just added
After adding a person or landing on someone from a meeting extraction, the detail view is largely empty cards. There is no guided moment: "You just met Alex — here's what I can do for you: set a relationship type, log how you met, add talking points, check if they're in your iMessage." The app has all the pieces to generate this — it just never surfaces them together.

### 5. Talking points are not surfaced at the right moment
`Person.swift:243` and `PersonDetailView.swift:2092–2116` implement talking points. They surface in the pre-meeting brief (referenced in briefing.md) but on the person detail view they're just a plain list buried after memories. There is no visual distinction for "urgent / overdue" talking points (e.g., ones you've been carrying for >14 days without a meeting). And there's no quick-add shortcut from a meeting recap ("add to talking points for Alex") — the connection is one-directional.

### 6. Keep-in-touch board is an island, not the default relationship view
`PeopleListView.swift:29,89,251–254`: board mode is a full-screen replace triggered by a small icon button (only shown when at least one typed person exists). It is not the default or even a prominent entry point. The board (`KeepInTouchBoard.swift:110–138`) shows cards with name, last-met, and relationship-type emoji. It does not show: upcoming special dates, open talking points, open tasks assigned to this person, or any actionable one-click to "reach out." Clicking a card just opens the person profile — no inline action.

### 7. PeopleInsightsView is a passive list, not a command surface
`PeopleInsightsView.swift:23–211`: the overview (shown in the right pane when no person is selected) has "Reconnect," "Coming up," and "Most active" cards. The "Mark reached out" button (`line 36–41`) only bumps `lastInteractionAt` — it doesn't prompt to log what you did, add a memory, or set a follow-up. There's no "Start a conversation" / "Draft a message" action on coming-up birthdays. The view is a dashboard that reads but doesn't act.

### 8. The person list sidebar has no relationship health signal per row
`PersonRow` (`PeopleListView.swift:609–647`) shows a health-ring avatar color, name, badge, and last-interaction relative time. It does not show: relationship type label in text (only a badge icon), how overdue the check-in is, or any open talking points. "Who needs attention" requires switching to the board — which is hidden behind an icon.

### 9. AI suggestions are opt-in and require manual trigger every time
`PersonDetailView.swift:1022–1092`: the `aiSuggestionsSection` shows a "Suggest" button that runs on demand. Suggestions are not persisted between sessions (state is `@State private var aiSuggestions`). For a second-brain tool with free local AI, this is a missed opportunity: suggestions should auto-run in the background on first open of a new profile and be cached, surfacing on the next visit.

### 10. Open tasks owned by a person are accessible via Tasks tab but not surfaced on the Person detail's overview
The `PersonTab.tasks` tab (`PersonDetailView.swift:287–298`) exists, but the Overview section does not show a count or preview of open tasks. Someone checking "what's pending with Sarah?" has to click to the Tasks tab — the overview gives no signal that tasks exist.

---

## Existing items to endorse (from prior plan or codebase)

- **Health ring on PersonRow** (`PeopleListView.swift:620`) — already implemented; extend to show band text on hover.
- **Keyboard verbs N / L / T / ⌘1–5** (`PersonDetailView.swift:344–358`) — excellent; worth documenting in onboarding.
- **QuickEncounterSheet** from Today view unified with person detail (`PersonDetailView.swift:390`) — the right pattern.
- **KeepInTouchBoard band ordering** (worst first: Overdue → Drifting → Steady → Thriving) — correct triage priority.
- **Reconnect draft via Ollama** (`PersonDetailView.swift:1960–2020`) — powerful, but buried. Deserves promotion.
- **`knownSinceLine`** (`PersonDetailView.swift:826–836`) — "Known for 3 years · first met Mar 2022" is great second-brain context.
- **Special dates + birthday surfacing** in PeopleInsightsView — keep and expand to include inline actions.

---

## NET-NEW recommendations

### UX2-1: Relationship Onboarding Card ("First Open" Experience)
- **What:** When a person's profile opens and `relationshipType == .unset` AND encounter count = 0, show a dismissible "Welcome" card pinned to the top of the detail pane (above all sections): "You just met [Name]. Set a relationship type to enable health tracking, log how you met, and drop a note." Inline: a relationship-type picker, a one-tap "Log first meeting" (opens QuickEncounterSheet pre-filled with today's date), and a memory field. Auto-dismiss once any action is taken.
- **Why (second-brain angle):** The first 24 hours after meeting someone is when context is richest. Capturing it immediately creates the foundation for all subsequent health scoring, AI suggestions, and pre-meeting briefs. Right now nothing prompts this.
- **Cross-feature connections:** Feeds KeepInTouchBoard (moves person from invisible to tracked), pre-meeting brief (talking points captured here surface before the next meeting), PeopleInsights "Reconnect" card.
- **Effort:** S | **Impact:** High
- **Deps:** none

### UX2-2: Proactive iMessage Intelligence Banner
- **What:** When a person has a matching email/phone and iMessage history exists (check asynchronously on profile open), and no `attachedNotes` of kind "summary" exist yet, show a single-line banner above the Messages section: "You have [N] messages with [Name]. Run AI relationship summary?" with a single "Analyze" button that runs the `relationshipSummary` preset at `recent1000` scope immediately — no extra popover needed. If a cached summary exists, show a "Last analyzed [date] · Refresh" link instead.
- **Why (second-brain angle):** The iMessage analysis is MeetingScribe's most powerful relationship intelligence feature. Making it opt-in and deeply buried means most users never discover it. A proactive, zero-click-to-start entry doubles the chance it's used.
- **Cross-feature connections:** The summary result should auto-suggest memories (extract key facts), talking points, and tags — bridging Messages → Memories → Overview in one pass.
- **Effort:** M | **Impact:** High
- **Deps:** none

### UX2-3: KeepInTouchBoard 2.0 — Actionable Cards with Inline Context
- **What:** Redesign each board card (`KeepInTouchBoard.swift:110–138`) from "name + last met" to a richer 3-line card: name + relationship type (line 1), last met + health score text (line 2), and a contextual action line (line 3): if talking points exist → "2 things to discuss"; if birthday/special date in 14 days → "Birthday in 5 days"; if open tasks → "3 open tasks"; else → a one-tap "Reach out" that opens the reconnect draft. Make the board the **default right-pane view** when no person is selected (replacing or complementing PeopleInsightsView), gated to users with ≥5 typed people. Add a column-level "Send a quick note to all Overdue" AI batch action.
- **Why (second-brain angle):** The board is the only surface that shows the whole relationship portfolio at a glance. Making it richer and more prominent turns it from a curiosity into a daily driver.
- **Cross-feature connections:** Talking points (People), open tasks (Tasks tab), special dates (PeopleInsights), reconnect draft (existing Ollama feature), Today tab "Stay Connected" section.
- **Effort:** M | **Impact:** High
- **Deps:** UX2-1 (type-setting), none else

### UX2-4: Contextual "What's Pending With [Name]" Overview Strip
- **What:** At the very top of the PersonDetailView overview section (before health badge), add a horizontally-scrollable "Today with [Name]" strip of chips: upcoming meetings today/this week with this person (from CalendarService), open tasks owned by them (count + badge), unresolved talking points (count), and days until next special date. Each chip is tappable — meetings open the UnifiedMeetingDetail, tasks navigate to the Tasks tab filtered by owner, etc. This collapses to nothing when all are zero so it's never noise.
- **Why (second-brain angle):** The #1 question when opening someone's profile is "what do I need to know right now?" The answer is scattered across 3 tabs and a calendar. Surfacing it as a scannable strip at the top eliminates the need to tab-hop.
- **Cross-feature connections:** CalendarService (meetings), ActionItemStore (tasks), talkingPoints (People), specialDates (PeopleInsights). Bridges People → Tasks → Meetings in one view.
- **Effort:** M | **Impact:** High
- **Deps:** none

### UX2-5: Auto-Run AI Suggestions on Background Open (Cached)
- **What:** When a person's profile is opened and `aiSuggestions` has never been generated (no cached value stored on the `Person` model or in a lightweight `UserDefaults` keyed by person ID + date), kick off `generateAISuggestions()` automatically in the background `.task`. Store the result in a lightweight `PersonAISuggestionsCache` (person ID → suggestions + generation date, JSON-persisted) so subsequent opens are instant. Show suggestions passively (non-blocking, no spinner in-face) — a subtle animated card that slides in after a few seconds. Add an "Accept all" one-tap option for when all suggestions are good.
- **Why (second-brain angle):** AI suggestions exist but are purely opt-in and ephemeral (lost on view close). With free local AI, running suggestions on every profile open is zero-cost and turns the People feature from a manual CRM into an auto-enriching second brain.
- **Cross-feature connections:** Suggestions populate tags (filterable in list), relationships (surfaced in graph), and encounters (appear in timeline). Bridges AI → People → Graph.
- **Effort:** M | **Impact:** Med-High
- **Deps:** none

### UX2-6: "After the Meeting" Person Update Flow
- **What:** When a meeting ends and attendees are matched to Person records, surface a lightweight post-meeting modal (or Today-tab card) per person: "You just met with [Name]. Anything to capture?" with three fields: memory (free text), talking point for next time, and a one-tap relationship health bump. Pre-populate with AI-extracted follow-ups from the meeting summary. If the person has `relationshipType == .unset`, include the type picker here too.
- **Why (second-brain angle):** Meetings are the richest signal source for relationship data. Right now, meeting → person data flow is one-directional (meeting mentions populate `meetingMentions`). A post-meeting capture loop closes the cycle: the meeting teaches the second brain something about the person.
- **Cross-feature connections:** MeetingManager (meeting end event), PersonDetailView (memories, talkingPoints), AI summary (pre-populate with action items). Bridges Meetings → People in real-time.
- **Effort:** L | **Impact:** High
- **Deps:** none

### UX2-7: Person List "Attention Needed" Smart Sort
- **What:** Add a new `PeopleSort` case `.attentionNeeded` that ranks people by: (overdue days / cadence days) × relationship weight (partner=3×, family/close friend=2×, colleague=1×). Show this sort as a badge count in the sidebar header — "3 need attention" — that is clickable to activate the sort. In `.attentionNeeded` sort mode, color the row background subtly by health band (danger tint for overdue, gold tint for drifting).
- **Why (second-brain angle):** "Who should I reach out to today?" is the most valuable daily question the People feature could answer. Right now the user has to open the board, scroll, and interpret. A smart-sorted list answers it in the sidebar without leaving the standard list view.
- **Cross-feature connections:** Today tab (could pull the top 3 "attention needed" into the Stay Connected section), KeepInTouchBoard (consistent health formula).
- **Effort:** S | **Impact:** Med
- **Deps:** none

### UX2-8: Talking Points "Time Since Added" Urgency Signal
- **What:** For each talking point in `PersonDetailView`, show how long ago it was added (relative date). Add a visual urgency signal: if a talking point is >14 days old and no meeting with this person is scheduled in the next 7 days, show it with a subtle amber highlight and a tooltip "Carry-over — added 18 days ago." Add a "Raise in next meeting" action that adds the talking point to the next upcoming meeting's agenda notes via CalendarService or MeetingManager.
- **Why (second-brain angle):** Talking points go stale. The app knows when a meeting is coming up with this person (CalendarService + attendee matching). Connecting these surfaces creates proactive "don't forget" reminders rather than a passive list.
- **Cross-feature connections:** CalendarService (upcoming meetings), MeetingManager (agenda notes), pre-meeting brief (where these surface already).
- **Effort:** S | **Impact:** Med
- **Deps:** none

---

## Top 3 picks

1. **UX2-4 — Contextual "What's Pending" Strip** — answers the #1 question on every profile open, bridges 3 tabs into one scannable strip, zero new data needed.
2. **UX2-2 — Proactive iMessage Intelligence Banner** — promotes the app's most powerful feature from buried to front-of-mind with one-click activation; high leverage on existing infrastructure.
3. **UX2-1 — First Open Onboarding Card** — closes the critical gap where newly-added people are invisible to health tracking; captures relationship context at peak signal moment.
