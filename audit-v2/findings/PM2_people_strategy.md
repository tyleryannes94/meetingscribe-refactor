# People Feature Product Strategy — MeetingScribe v2 Audit

**Agent:** PM2 — Senior PM, People Feature Sub-Lens
**Date:** 2026-06-16

---

## Top friction points / gaps (file:line citations)

### 1. People is a data store, not a relationship intelligence engine

The `Person` model (Person.swift:218–360) has a rich schema — memories, specialDates, talkingPoints, encounters, attachedNotes, relationships — but no derived intelligence layer sits on top of it. There is no proactive "here's what you need to know before you see this person" surface beyond the pre-meeting brief. Clay's killer feature is *automatic context assembly*; MeetingScribe has all the ingredients but assembles nothing without user prompting.

### 2. AI suggestions are impoverished in scope

`PersonAISuggestions` (PersonAISuggestions.swift:8–22) proposes only tags, relationship edges, and encounter titles. It doesn't suggest: follow-up tasks, conversation starters, sentiment shifts, relationship risk flags, or "what changed since last meeting." The model output is three flat arrays with no priority or reasoning attached. Compare to Clay, which surfaces "last touched X days ago + you have Y open threads."

### 3. KeepInTouchBoard is read-only triage with no action

`KeepInTouchBoard.swift:56–139` renders four kanban columns (Overdue/Drifting/Steady/Thriving) with avatar cards. Clicking opens the person detail. That is the entire interaction. There is no inline "log a check-in," no "draft a message," no "remind me in 3 days," no AI-generated conversation starter. The board identifies the problem but offers no path to resolution from the same surface. A user who sees 11 "Overdue" contacts must open each one individually.

### 4. Tasks owned by a person are matched by string fragility

`PersonDetailView.swift:1573–1598`: `ownerMatchesPerson` uses a fallback string-contains check for legacy tasks that predate the `ownerPersonID` hard link. Tasks with ambiguous owners ("Dan" matching "Daniel") or ownership expressed as a company name are invisible here. No aggregate view of "tasks I owe this person" vs. "tasks this person owes me" exists.

### 5. Encounter model is minimal and not auto-populated from meetings

`Encounter.swift:7–46`: Encounters have a `meetingID` field but nothing in the pipeline auto-creates an Encounter when a meeting ends with this person as an attendee. The user must manually add encounters. This means the encounter heatmap (PersonDetailView.swift:1533) is chronically underpopulated for anyone the user meets via calendar, making the health score meaningless for large professional networks.

### 6. Relationship graph is undirected and unexploited

`Person.swift:190–205`: `Relationship` edges carry only a freeform `label` and `toPersonID`. The bidirectional mirror (mentioned in the struct comment) is the extent of graph reasoning. There is no "who connects me to whom" (mutual contacts), no "second-degree reach for this company," no cluster visualization beyond the existing force-directed people graph. Clay's "connected via" feature drives high-value discovery.

### 7. iMessage analysis is deep but siloed

`PersonDetailView.swift:1–200` and `2462–2590`: The iMessage analysis pipeline is sophisticated — 6 presets, distress pre-flight guard, all-time deep analysis, cached AttachedNotes. But the output stays locked inside the person detail view. Nothing surfaces to: Today dashboard, pre-meeting brief, the AI chat's default context, or the KeepInTouchBoard. A relationship summary that took 30 seconds of Ollama compute is invisible to 4 of the 5 app tabs.

### 8. No relationship velocity or trajectory signal

The health model (`KeepInTouchBoard.swift:24–37`) computes a health score from daysSinceLast and cadence but has no trajectory signal: is this relationship improving or declining? A person last seen 20 days ago with a 30-day cadence who was seen weekly before is on a different trajectory than a person with a stable 20-day rhythm. Without velocity, the board can't distinguish "drifting but recovering" from "accelerating toward loss."

### 9. No push-to-task from relationship context

Nothing in the People tab can create a task. Seeing "I need to follow up with Sarah about the budget" in a deep analysis note has zero path to creating a task without switching to the Tasks tab and reconstructing context. Clay, Notion, and Linear all handle "create task from here" as a first-class action.

### 10. PersonDetailView is a 2836-LOC monolith

The detail view renders all sections in a single file with no clear information hierarchy. For a professional contact the "iMessage analysis" section is noise; for a close friend the "Meeting history" section may be empty. There is no adaptive layout that surfaces the most relevant sections first based on relationship type and available data signal.

---

## Existing items to endorse (from prior plan or codebase)

- **Relationship health bands** (KeepInTouchBoard): the Overdue/Drifting/Steady/Thriving model is conceptually right — keep and extend it.
- **SpecialDates + birthday** (Person.swift:53–67, 247): surfacing these in "coming up" is correct; just needs a Today dashboard widget.
- **talkingPoints** (Person.swift:243): the "discuss next time" concept is excellent and maps directly to pre-meeting brief. Already wired to `PreMeetingBriefView`.
- **Deep analysis / allTime cached notes** (PersonDetailView.swift:2592–2668): the pattern of "pay Ollama cost once, cache result forever" is exactly right. Extend to generate structured data, not just prose.
- **Embedded chat per person** (PersonDetailView.swift:1217–1247): person-scoped AI chat with example prompts is the right pattern. Needs better default context injection.
- **Relevance score / ghost contact filter** (Person.swift:412–437): the ghost-detection heuristic protects the list from noise. Keep.
- **MCP exposure** (MCPInstaller.swift:1–60): the MCP server means external Claude can query people data. This is a huge multiplier — build more people tools into the MCP.

---

## NET-NEW recommendations

### PM2-1: Auto-Encounter Creation from Meetings

- **What:** When a meeting ends (recording stops + attendees confirmed), automatically create an `Encounter` record for each confirmed attendee — linking `meetingID`, pre-filling `eventName` from the meeting title, `date` from `startDate`, and `notes` from the meeting summary's first 2–3 sentences. User gets a toast: "Logged 3 encounters from [Meeting Name]" with an undo option.
- **Why (second-brain angle):** The encounter heatmap and health score are the foundation of relationship intelligence. Both are meaningless if they only capture manual check-ins. Auto-creation from meetings ensures the graph reflects reality with zero user friction — making "Overdue" actually mean something for professional contacts.
- **Cross-feature connections:** Meetings tab (pipeline hook post-summary), People tab (encounter heatmap, health bands, KeepInTouchBoard), Today dashboard (health signals update automatically).
- **Effort:** M | **Impact:** High
- **Deps:** None — `Encounter.meetingID` field already exists.

### PM2-2: Relationship Velocity Signal + Trajectory Badge

- **What:** Add a `velocityTrend` computed property to the health model: compare the median encounter gap over the last 60 days vs. the prior 60 days. Surface as a directional badge on the KeepInTouchBoard card (↑ improving, ↓ declining, → stable) and as a tooltip "Frequency up 40% vs. last 60 days." Store a lightweight rolling window (last 12 encounter dates) to compute without re-scanning all history.
- **Why (second-brain angle):** A health score without trajectory is a speedometer without direction. Velocity lets Tyler distinguish "drifting but I just saw them last week" from "steadily slipping for 3 months." Clay shows this implicitly via contact frequency graphs.
- **Cross-feature connections:** KeepInTouchBoard (badge), PersonDetailView encounter heatmap (trend overlay line), Today dashboard StayConnected section (flag recovering relationships differently than declining ones), WeeklyRecap (include velocity trends in the markdown summary).
- **Effort:** M | **Impact:** High
- **Deps:** PM2-1 (more encounter data means more accurate velocity).

### PM2-3: One-Tap Actions on KeepInTouchBoard Cards

- **What:** Each card in the KeepInTouchBoard gets a swipe-right (or hover-reveal) action strip with three inline buttons: (1) **Log check-in** — opens a minimal sheet (event name pre-filled "Call", date today, optional note); (2) **AI starter** — runs Ollama in the background to generate a 1–2 sentence conversation opener based on the person's last memory/encounter/talkingPoint, copies to clipboard with a toast; (3) **Remind me** — creates a time-based task ("Check in with [Name]") in the Tasks tab with `ownerPersonID` linked.
- **Why (second-brain angle):** The board identifies who needs attention. Without inline action it's a dashboard that makes Tyler feel guilty but doesn't help him act. The AI conversation starter is the "Clay magic" moment — local Ollama means this is free and instant.
- **Cross-feature connections:** Tasks tab (creates action item with person link), Encounters (logs check-in), clipboard (AI starter), People health score (updates after log).
- **Effort:** M | **Impact:** High
- **Deps:** PM2-1 (richer encounter data makes AI starter more contextual).

### PM2-4: Person Intelligence Card — Proactive Pre-Surface

- **What:** A new `PersonIntelligenceCard` widget (replaces or augments the static AI suggestions panel in PersonDetailView) that runs a lightweight Ollama pass on every person view and delivers: (a) one-sentence "what to know right now" (e.g., "You haven't connected in 47 days — last you discussed her job search"), (b) up to 3 ranked follow-ups derived from meeting summaries + talkingPoints + open tasks, (c) an emotional tenor note if a deep analysis exists ("sentiment has been warm but low-frequency lately"). Auto-refreshes if the person was last analyzed >7 days ago.
- **Why (second-brain angle):** This is the "briefing without asking" moment. Today, the user must manually trigger "Ask AI" or "Run analysis" to get context. Proactive delivery makes People feel like a relationship advisor, not a contact book.
- **Cross-feature connections:** Meetings (source of follow-ups), Tasks (surfaced open items), iMessage analysis (emotional tenor), PreMeetingBriefView (shares the same output format so the brief can embed the card).
- **Effort:** L | **Impact:** High
- **Deps:** PM2-1, existing `OllamaService`, `personContextForAI()` already built in PersonDetailView.swift:1202.

### PM2-5: Task Mutation from People Tab

- **What:** Add a "New task" button to the PersonDetailView tasks section (currently shows tasks but has no create affordance — PersonDetailView.swift:1569). The sheet pre-fills `ownerPersonID` with the current person and offers a "linked to [recent meeting]" dropdown. Also: a "tasks they owe me" vs. "tasks I owe them" toggle so Tyler can see both sides of commitments.
- **Why (second-brain angle):** Every meeting with a person generates commitments in both directions. Without create-from-person, Tyler must context-switch to Tasks tab, lose the person context, and re-associate manually. This is the single-biggest workflow break in the cross-tab experience.
- **Cross-feature connections:** Tasks tab (ActionItemStore), Meetings (meetingID linking), Today dashboard (task counts update).
- **Effort:** S | **Impact:** High
- **Deps:** None — `ActionItemStore` and `ownerPersonID` field already exist.

### PM2-6: Relationship Summary Auto-Surfaced in PreMeetingBrief

- **What:** When `PreMeetingBriefView` loads for a meeting, for each attendee who has an existing `deep-all` or `summary-all` AttachedNote, pull the first 200 characters as a "Relationship context" chip in the attendee row. If no cached analysis exists but >3 meetings with this person are on record, auto-trigger a lightweight Ollama pass (no iMessage required, just meeting summaries) and cache the result.
- **Why (second-brain angle):** The pre-meeting brief is where relationship intelligence has maximum ROI — 2 minutes before a call. Currently it shows prior meetings and open tasks but no relationship context. Adding the cached summary costs nothing (already computed) and transforms the brief from a calendar view into a genuine briefing.
- **Cross-feature connections:** Meetings (PreMeetingBriefView), People (AttachedNotes, meetingMentions), iMessage analysis pipeline.
- **Effort:** S | **Impact:** High
- **Deps:** Existing `attachedNotes` on `Person`, existing `PreMeetingBriefView`.

### PM2-7: Mutual Contacts / Second-Degree Discovery

- **What:** In the people graph and PersonDetailView, compute "who else do you both know" by intersecting attendee lists across meeting history. Surface as a "Mutual contacts" chip: "You've both been in meetings with Alex Chen and Maria Santos." Store the intersection as a derived index in `SecondBrainDB` rather than computing per-render.
- **Why (second-brain angle):** Clay's most-loved feature. For job search, warm introductions, or simply "how do I get to this person," mutual contact discovery converts the graph from decorative to instrumental.
- **Cross-feature connections:** People graph (visual edges), Meetings (attendee overlap), GlobalSearch (find "who knows both X and Y"), AI chat (answer "who can introduce me to...").
- **Effort:** L | **Impact:** Med
- **Deps:** PeopleStore's `extractedMeetingIDs` and meeting attendee data; `SecondBrainDB` (SecondBrainDB.swift).

### PM2-8: Adaptive PersonDetailView Layout by Relationship Type + Data Signal

- **What:** Replace the current fixed-order section layout in PersonDetailView (2836 LOC monolith) with a data-driven priority stack: for colleagues, lead with Meeting History + Tasks; for close friends/family, lead with Encounter Heatmap + iMessage analysis + Memories; for unset/ghost contacts, lead with a nudge to classify. Each section header gets a disclosure arrow (collapsed by default if empty). The "no data" empty states should link to the relevant action ("Record a meeting with them," "Import from iMessage").
- **Why (second-brain angle):** A colleague's detail view shouldn't lead with "No iMessage history." The current one-size-fits-all layout makes every profile feel incomplete. Adaptive layout makes sparse profiles feel intentional rather than broken.
- **Cross-feature connections:** Person.relationshipType, all existing PersonDetailView sections.
- **Effort:** M | **Impact:** Med
- **Deps:** None — pure UI restructure, no model changes.

### PM2-9: People Intelligence Weekly Digest

- **What:** Extend `WeeklyRecap.swift` to include a "Relationship pulse" section: (a) 3 people whose health score dropped the most this week (going from Steady → Drifting), (b) 2 upcoming special dates within 14 days, (c) 1 "dormant but warm" contact (high past encounter density, last seen >60 days). Delivered as part of the existing weekly recap Markdown doc.
- **Why (second-brain angle):** Relationship maintenance fails not from lack of caring but from lack of awareness. A weekly digest that names the specific people requiring attention turns ambient guilt into actionable context. Free via Ollama; zero user-initiated work.
- **Cross-feature connections:** WeeklyRecap (existing hook), People health scores, SpecialDates, Today dashboard (weekly recap widget).
- **Effort:** S | **Impact:** Med
- **Deps:** PM2-1 (accurate health scores), PM2-2 (velocity data for "dropped most").

### PM2-10: MCP Tools for Relationship Intelligence

- **What:** Expose 3 new tools in the MCP server: `get_relationship_health(person_id)` → returns band, score, days since last contact, velocity trend; `list_overdue_checkins(limit)` → returns top N overdue people sorted by relationship type priority; `suggest_conversation_starter(person_id)` → runs Ollama with person context and returns a 1–2 sentence opener. This lets external Claude Desktop sessions answer "who should I reconnect with this week" without opening the app.
- **Why (second-brain angle):** The MCP server (MCPInstaller.swift:1–60) is already the bridge to external Claude. Relationship intelligence tools in the MCP mean the second brain becomes queryable from anywhere Claude Desktop is used — turning MeetingScribe's people graph into an ambient intelligence layer.
- **Cross-feature connections:** MCP server, PeopleStore, health model, Ollama.
- **Effort:** M | **Impact:** High
- **Deps:** PM2-2 (velocity for health tool).

---

## Top 3 picks

1. **PM2-1 (Auto-Encounter from Meetings)** — the health score and KeepInTouchBoard are meaningless without accurate encounter data. This single change makes the entire relationship intelligence stack meaningful for professional contacts, which are the majority of Tyler's network. Zero new UI required; pure pipeline work.

2. **PM2-3 (Inline Actions on KeepInTouchBoard)** — the board already identifies who needs attention. Adding Log / AI Starter / Remind converts a dashboard into a workflow tool. The AI-generated conversation starter is the highest-delight, lowest-effort "Clay moment" in the entire app.

3. **PM2-6 (Relationship Summary in PreMeetingBrief)** — highest ROI on already-computed data. The `summary-all` AttachedNote exists; the PreMeetingBriefView exists. Injecting 200 characters of relationship context into the brief requires a single lookup and makes People feel like it pays dividends throughout the rest of the app.
