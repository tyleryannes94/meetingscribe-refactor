# Interconnectedness & Second-Brain Strategy Findings — MeetingScribe v2 Audit

## Top friction points / gaps (file:line citations)

### 1. Embeddings computed but never surfaced proactively
`EmbeddingService.swift` provides cosine similarity and embeddings are computed
post-transcription (`MeetingPipelineController.swift:242`) and stored in
`SecondBrainDB` — but the only consumer is `GlobalSearchView.swift:287` (hybrid
reranking) and the related-meetings panel in `MeetingNotesTab.swift:190`. There
is **no proactive push** of semantically related content to Today, no
"you're about to discuss something you decided differently 3 weeks ago" nudge,
and no cross-entity semantic cluster surfaced anywhere in the UI. The embeddings
exist but are almost entirely invisible to the user.

### 2. Meeting → People → Tasks pipeline is manual at every seam
- `MeetingDetailHeader.swift:855` shows attendee chips where filled dots indicate
  known People records — but creating a Person from an attendee requires the user
  to manually click "Add to People". There is no auto-enrollment of new
  attendees who appear in multiple meetings.
- `ActionItemsSidebar.swift:483–487` filters by `ownerPersonID`, but that field
  is only populated if the user manually links it. The AI extraction in
  `MeetingPipelineController.swift` does not auto-resolve action item owners
  against `PeopleStore`.
- `DecisionStore.swift:39–57` extracts decisions from summaries and stores them
  flat with `meetingID` + `text`. No link to People (who was in the room), no
  link to Tasks (decisions that should create follow-up work), and no forward
  reference to future meetings where the same decision was revisited.

### 3. WeeklyRecap is purely retrospective and author-less
`WeeklyRecap.swift:10–46` writes a markdown file with meetings, decisions, and
open tasks — but:
- No attendee-level breakdown (who owns what, who hasn't delivered)
- No drift detection (tasks from last week that are still open vs. resolved)
- No project health rollup
- Generated on demand only (no scheduled trigger); once written it's a static
  file — not a living dashboard

### 4. DecisionStore has no forward-looking hooks
`DecisionStore.swift` stores decisions chronologically but there is no mechanism
to:
- Flag a decision as "pending validation" (i.e., a future meeting should
  confirm/revisit it)
- Link a decision to a project or task that should implement it
- Alert when a new meeting attendee set overlaps with a prior decision's
  attendee set (pre-meeting brief could say "you decided X with these people
  on DATE")

### 5. ChatTools are reactive, not scheduled/proactive
`ChatTools.swift` provides a rich tool façade over all data, but it only runs
when the user opens the chat rail. There is no scheduled Ollama pass that:
- Runs nightly or post-meeting to synthesize insights
- Pushes a "You have 3 overdue action items promised to Acme team" to Today
- Produces a relationship-health warning ("Haven't spoken to [key contact] in
  30 days and you have an open task assigned to them")

### 6. Voice notes are a dead-end tab
`QuickNotesView.swift` records and transcribes voice notes but they appear
nowhere in Today's dashboard, don't auto-create tasks when action language is
detected, and have no person-linking. They're indexed in `workspaceEntities()`
(`WorkspaceIndex.swift:19–24`) but the only route to them is the Voice Notes
tab itself or ⌘K.

### 7. WorkspaceRouter has no cross-tab data-flow events
`WorkspaceRouter.swift` is a clean navigation router but it's purely
view-selection. There is no "data event bus" layer: when a meeting finishes
processing, there is no mechanism to automatically update People, push tasks to
the triage inbox, or refresh Today — each of these requires the user to navigate
there manually.

---

## Existing items to endorse (from prior plan or codebase)

- `PreMeetingBriefView.swift` — the pre-meeting brief concept is excellent;
  endorse extending it with semantic similarity ("this meeting topic resembles
  your Q2 planning session")
- `WorkspaceIndex.swift` backlinks scan — solid foundation; endorse making
  backlinks visible inline in meeting detail and in People profiles
- Embedding backfill in `MeetingManager.swift:1048` — good; should be triggered
  for Voice Notes too
- `StandupDigest.swift` — endorse; should be scheduled and available in menu bar

---

## NET-NEW recommendations

### PM1-1: Post-Meeting Automation Pipeline ("Meeting Finalize Flow")
- **What:** When a meeting's summary is finalized, automatically: (1) resolve
  all attendees against PeopleStore and create stubs for unknowns with
  `lastMeetingDate` set; (2) extract action items and auto-assign
  `ownerPersonID` via PersonResolver; (3) push extracted decisions to
  DecisionStore WITH the attendee list attached; (4) add the meeting to any
  matching project's `meetingIDs`; (5) send a macOS notification summarizing
  what was created. The user should never have to manually stitch a meeting
  to People or Tasks.
- **Why (second-brain angle):** A second brain that requires manual linking is
  a filing cabinet. Every meeting should automatically propagate its signal
  through the graph within 60 seconds of summarization.
- **Cross-feature connections:** Meetings → People (auto-enroll attendees),
  Meetings → Tasks (owner resolution), Meetings → Projects (meetingIDs),
  Today (notification + widget refresh)
- **Effort:** L | **Impact:** High
- **Deps:** PM1-2 (person auto-enrollment), PM1-3 (owner resolution)

### PM1-2: Automatic Person Enrollment from Recurring Attendees
- **What:** After a new attendee email appears in 2+ meetings within 30 days
  without a corresponding Person record, automatically create a Person stub
  (name from display name, email, first/last seen dates, linked meeting IDs).
  Surface a "New contacts found" card on Today that lets Tyler confirm or
  dismiss each stub with one click.
- **Why (second-brain angle):** The People graph is only as valuable as its
  completeness. Currently it requires manual opt-in for every contact, so
  the graph is perpetually sparse relative to the actual relationship network.
- **Cross-feature connections:** Meetings → People, Today (confirmation card)
- **Effort:** M | **Impact:** High
- **Deps:** none

### PM1-3: Proactive Semantic Nudges via Scheduled Ollama Pass
- **What:** A background `SemanticPulse` service runs a lightweight Ollama
  pass once per hour (or post-meeting) over the last 7 days of data. It
  produces 1–3 "nudges" delivered to Today: e.g., "Decision from 2 weeks ago
  (adopt new pricing) hasn't generated any tasks yet — create one?", "You
  promised Sarah a follow-up 5 days ago (overdue)", "Three voice notes mention
  'budget' — start a project?". Nudges are dismissable and link directly to
  the source entity.
- **Why (second-brain angle):** This is the difference between a reactive
  filing system and a genuine second brain. The local LLM has zero marginal
  cost — the only reason not to run it proactively is architectural inertia.
- **Cross-feature connections:** All tabs feed into nudges; nudges surface in
  Today; deep links go to Meetings / Tasks / People / Voice Notes
- **Effort:** L | **Impact:** High
- **Deps:** PM1-1

### PM1-4: Decision Lifecycle Tracking
- **What:** Extend `Decision` model with `ownerPersonIDs: [String]`,
  `linkedTaskIDs: [String]`, `status: DecisionStatus` (open / implemented /
  superseded), and `revisitedInMeetingIDs: [String]`. When a new meeting
  summary is generated, run a semantic check against open decisions to detect
  if the same topic was discussed — if so, prompt "Did you revisit the X
  decision?" with a one-click link.  Pre-meeting brief for any meeting with
  overlapping attendees shows open decisions from prior meetings with that
  group.
- **Why (second-brain angle):** Decisions are the most durable outputs of any
  meeting. Letting them die as text in a list is the biggest context-loss
  vector in the current product.
- **Cross-feature connections:** Meetings ↔ Decisions ↔ Tasks ↔ People,
  PreMeetingBrief, WeeklyRecap
- **Effort:** M | **Impact:** High
- **Deps:** PM1-1

### PM1-5: Embedding-Powered "Context Flash" in Pre-Meeting Brief
- **What:** Before a meeting, use `EmbeddingService` to semantically cluster
  the meeting title + attendees against all past meetings and voice notes.
  Surface the top 3 most semantically related items in `PreMeetingBriefView`
  with a one-sentence AI summary of the connection ("In your March sprint
  review you committed to the same deadline — it's still open"). Uses
  already-computed embeddings from `SecondBrainDB` — zero extra Ollama calls
  at brief-render time.
- **Why (second-brain angle):** Embeddings are already computed and stored;
  they're just invisible. Surfacing them at the highest-leverage moment (30
  seconds before a meeting) turns a sunk infrastructure cost into daily value.
- **Cross-feature connections:** Embeddings (SecondBrainDB) → PreMeetingBrief
  → Meetings, Voice Notes, Tasks
- **Effort:** S | **Impact:** High
- **Deps:** none (embeddings already exist)

### PM1-6: Voice Notes Auto-Triage
- **What:** After a voice note is transcribed and polished, run a lightweight
  Ollama pass to detect: (a) action language → create draft task in triage
  inbox; (b) person mentions → suggest linking to People records; (c) topic
  overlap with recent meetings → surface in related content panel. Results
  appear as a "Suggestions" card on the Voice Notes detail view.
- **Why (second-brain angle):** Voice notes are currently a dead-end — they
  don't feed the task or people graph at all despite being high-signal captures
  of spontaneous thinking.
- **Cross-feature connections:** Voice Notes → Tasks (triage inbox), Voice
  Notes → People, Voice Notes → Meetings (related panel)
- **Effort:** M | **Impact:** Med
- **Deps:** PM1-1 (same pipeline pattern)

### PM1-7: Relationship Drift Alert on Today
- **What:** On Today, show a "Relationship health" widget that identifies
  People records where: (a) there's an open task owned by or assigned to that
  person, AND (b) the last interaction was >14 days ago. One-line cards with
  "Message" (opens iMessage) and "Schedule" (opens calendar). Computed from
  existing `PeopleStore.lastInteractionAt` and `ActionItem.ownerPersonID`.
- **Why (second-brain angle):** The relationship health concept exists in the
  People tab but is invisible from Today — the primary daily surface. Bringing
  it to Today closes the loop between task commitments and relationship
  maintenance.
- **Cross-feature connections:** People (lastInteractionAt, ownerPersonID) →
  Today widget, iMessage, Calendar
- **Effort:** S | **Impact:** High
- **Deps:** PM1-1 (for ownerPersonID population)

### PM1-8: Live WeeklyRecap Dashboard (replace static MD file)
- **What:** Replace `WeeklyRecap.swift`'s static markdown export with a live
  SwiftUI panel accessible from Today (a "Week in Review" button). The panel
  renders: meetings attended with attendee avatars, decisions made with their
  current status (linked to DecisionStore), tasks created vs. closed (with
  owner breakdown), and a drift indicator (tasks promised last week that are
  still open). Auto-regenerates on first open each Monday.
- **Why (second-brain angle):** A weekly review that requires opening a
  markdown file in Obsidian is not a second brain ritual — it's busywork. The
  data for a real, linked review already exists; it just needs a live view.
- **Cross-feature connections:** Meetings, Decisions, Tasks, People → Today
  (WeekView panel)
- **Effort:** M | **Impact:** Med
- **Deps:** PM1-4 (DecisionStatus)

---

## Top 3 picks

1. **PM1-1 (Post-Meeting Automation Pipeline)** — the single highest-leverage
   change; it makes every other cross-tab connection automatic instead of
   manual, and is the prerequisite for half the other recommendations.

2. **PM1-3 (Proactive Semantic Nudges)** — converts the product from reactive
   to proactive with zero new infrastructure (Ollama is already running). This
   is the "second brain" moment users will actually feel.

3. **PM1-5 (Embedding-Powered Context Flash in Pre-Meeting Brief)** — highest
   ROI relative to effort because embeddings are already computed; it's a
   read-only query that surfaces invisible data at the exactly right moment.
