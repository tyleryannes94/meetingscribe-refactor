# U3 — PM / Researcher (Second Brain) Findings — MeetingScribe v2 Audit

## Top friction points / gaps (file:line citations)

### 1. DecisionStore has no rationale field — "what" without "why"
`DecisionStore.swift:6–12` — `Decision` stores `text` (the decision text) and `meetingID`/`meetingTitle`, but no `rationale`, `context`, `alternatives`, or `discussionExcerpt` field. Parsing (`parseDecisions`, line 61–79) extracts only the bullet text from "## Key Decisions". Six months from now, "We chose Postgres over DynamoDB" is useless without the reasoning. A PM needs WHY, not just WHAT.

### 2. DecisionStore is not searchable via GlobalSearch
`GlobalSearchView.swift:283` — FTS kinds scanned are `[.meeting, .voiceNote, .person]`. There is no `WorkspaceEntityKind.decision`. Decisions live in `decisions.json` but are never indexed into the vault FTS (`PeopleStore.searchVault`). Searching "database choice" returns meeting titles, not the decision itself. The user must remember which meeting to navigate to.

### 3. No cross-decision topic clustering or deduplication
The `Decision` struct has no `topic`, `project`, or `tag` field (`DecisionStore.swift:6–12`). Decisions accumulate as a flat chronological list (TodayView.swift:438–443 shows `decisions.decisions` unfiltered). There is no way to group "all decisions about the backend" or "all decisions for Project X" — forcing the user to scan hundreds of entries.

### 4. Decisions are not cross-linked to Tasks or People
`DecisionStore.swift` has no `ownerPersonID`, `projectID`, or `taskIDs`. `WorkspaceIndex.swift` (`workspaceEntities()`, line 11–49) does not enumerate decisions at all. A decision to "ship feature X by Q3" creates no automatic link to the Project or the person who made the call.

### 5. Embeddings capped at summary-level, not decision-level
`EmbeddingService.swift:35` — payload is capped at 8,000 chars of "title + summary". Individual decisions are never embedded separately. Semantic search for "what did we decide about authentication" will retrieve meetings by summary proximity, not the specific decision statement.

### 6. GlobalSearch has no "decisions" filter tab
`GlobalSearchView.swift:27–50` — `SearchFilter` has `.all, .people, .meetings, .tasks, .notes, .voiceNotes` — no `.decisions`. A PM who wants to answer "what did we decide about X?" has no scoped path; they must search meetings and read through summaries.

### 7. WeeklyRecap includes decisions but no quarterly roll-up
`WeeklyRecap.swift:18,31` — weekly decisions are appended to the recap markdown. There is no quarterly, project-scoped, or cross-period aggregation. Preparing a quarterly review requires the user to manually open N weekly recaps and copy-paste.

### 8. Related meetings via embeddings are not surfaced on the decision itself
`UnifiedMeetingDetail.swift:373–377` — `relatedMeetingIDs(toID:)` is called per-meeting and surfaces related meetings. But from a decision view, there is no "other meetings where this topic was discussed" link. The PM has to open the source meeting, then pivot to related meetings, then scan those summaries.

### 9. SeriesHub shows decisions per-series only
`SeriesHubView.swift:73` — decisions are filtered to a series. If a project topic spans multiple ad-hoc meetings (not a recurring series), there is no "project decisions" view that aggregates across them.

### 10. No "decision confidence" or "status" tracking
Decisions extracted from summaries have no `status` (standing / revisited / reversed / superseded). A PM using this as a second brain has no way to flag "this decision was revisited in November" without going back and manually reading notes.

---

## Existing items to endorse (from prior plan or codebase)

- **DecisionStore itself (P1-1 / C1-11 / C2-8)** — solid foundation; the ledger concept is correct and worth building on aggressively.
- **SeriesHubView decisions section** (`SeriesHubView.swift:299`) — per-series decisions panel is exactly the right mental model, just needs to expand to project-level.
- **MeetingPeekPanel decisions preview** (`MeetingPeekPanel.swift:20,64`) — showing decisions on task hover is a great cross-tab connection; worth keeping.
- **TodayView decisionsSection** (`TodayView.swift:437`) — right place for a "recent decisions" feed; needs date-range filtering and topic grouping to be actionable.
- **WeeklyRecap** — already collects decisions weekly. Quarterly roll-up should be layered on top.
- **`in:` qualifier syntax** (`GlobalSearchView.swift:233–249`) — the `in:meetings` syntax is already parsed; adding `in:decisions` is a small extension.
- **Hybrid semantic + FTS search** (`GlobalSearchView.swift:290–296`) — excellent architecture; just needs decisions indexed.

---

## NET-NEW recommendations

### U3-1: Decision Rationale Extraction — enrich the Decision struct
- **What:** Add `rationale: String`, `discussants: [String]` (attendee names who spoke on the topic), and `status: DecisionStatus` (`.standing / .revisited / .superseded`) to the `Decision` struct. Update `parseDecisions` to extract not just the bullet text but the surrounding paragraph or the AI-generated "Rationale" block from the summary. Add an optional `supersededByDecisionID` pointer.
- **Why (second-brain angle):** "What did we decide?" is only half the question. "Why?" is the other half that prevents re-litigating in 6 months. Local Ollama can fill the rationale field at zero cost immediately after summary generation.
- **Cross-feature connections:** DecisionStore → MeetingSummaryTab (show rationale inline) → PersonDetail (show decisions a person was involved in) → Tasks (link the decision to the project it spawned) → WeeklyRecap + QuarterlyRecap.
- **Effort:** M | **Impact:** High
- **Deps:** none

### U3-2: Decision FTS + Semantic Index — make decisions first-class search citizens
- **What:** Index each `Decision` into the vault FTS table (`PeopleStore.searchVault`) with `entityKind = "decision"`. Embed each decision text (+ rationale) separately via `EmbeddingService.embed()`. Add `.decisions` to `GlobalSearchView.SearchFilter` and `WorkspaceEntityKind`. Add `WorkspaceEntityKind.decision` to `WorkspaceIndex.workspaceEntities()`.
- **Why (second-brain angle):** "What did we decide about X?" should return the specific decision row in 10 seconds, not a list of meetings to read through. This is the single most important retrieval improvement for the researcher persona.
- **Cross-feature connections:** GlobalSearch → DecisionStore → MeetingDetail (jump directly to the source meeting + decision highlight) → AI Chat tools (expose `search_decisions` tool).
- **Effort:** M | **Impact:** High
- **Deps:** U3-1

### U3-3: Topic-Clustered Decision Ledger View — a dedicated "Decisions" surface
- **What:** New view (accessible from Meetings sidebar or ⌘K "Show decision ledger") that displays all decisions grouped by AI-inferred topic cluster (e.g., "Infrastructure", "Pricing", "Hiring"). Use local Ollama k-means/topic labeling over decision embeddings to auto-assign topics. Provide a timeline view and a topic-grid view. Add filter by date range, topic, project, and person. Allow the user to override topic labels, mark decisions as superseded, and link to tasks.
- **Why (second-brain angle):** This is the "quarterly review in 10 seconds" feature. A PM can open the decision ledger, filter to Q3, and see every decision made by topic — without opening a single meeting. This transforms MeetingScribe from a meeting archive into an institutional memory tool.
- **Cross-feature connections:** DecisionStore → Projects (filter by project) → People (filter by decision-maker) → WeeklyRecap / new QuarterlyRecap → AI Chat ("summarize all pricing decisions from last 6 months").
- **Effort:** L | **Impact:** High
- **Deps:** U3-1, U3-2

### U3-4: Quarterly Recap Generator — AI-authored review from structured data
- **What:** Add a "Generate Quarterly Review" command (in ⌘K palette alongside "Generate weekly review", `GlobalSearchView.swift:448–451`). The generator queries DecisionStore for the date range, groups by topic cluster (U3-3), pulls open tasks by project, and asks local Ollama to write a narrative summary. Output as markdown to vault, with optional Notion push. Add a "what changed" diff mode (Q2 vs Q3).
- **Why (second-brain angle):** Quarterly reviews are the canonical PM artifact. If MeetingScribe can generate a first-draft QBR from meeting data, decisions, and tasks in one click, it's irreplaceable. This is the "wow" moment for the researcher persona.
- **Cross-feature connections:** DecisionStore + WeeklyRecap + ActionItemStore + ProjectStore → OllamaService → Notion export → TodayView (surface the generated doc).
- **Effort:** M | **Impact:** High
- **Deps:** U3-1, U3-3

### U3-5: "Why did we decide X?" Chat Tool — natural language decision archaeology
- **What:** Add a `search_decisions(query: String, dateRange: ClosedRange<Date>?, topicFilter: String?)` tool to `ChatTools.swift`. The tool runs hybrid semantic search over decision embeddings + FTS, returns the top N decisions with rationale and source meeting links, and lets the AI compose a narrative answer. Wire a ⌘K shortcut: "Ask about a decision" that pre-fills the chat with "What did we decide about…".
- **Why (second-brain angle):** This is the 10-second answer to "why did we decide X?" The AI can cite specific decisions with meeting dates, attendees, and rationale — making MeetingScribe the authoritative institutional memory assistant.
- **Cross-feature connections:** AI Chat → DecisionStore → MeetingDetail (deep-link to source meeting) → PeopleStore (who was in the room).
- **Effort:** S | **Impact:** High
- **Deps:** U3-2

### U3-6: Project History Timeline — all meetings + decisions for a project, in one view
- **What:** On the Project detail view (Tasks tab), add a "History" section that lists all meetings linked to the project (`project.meetingIDs`) in chronological order, showing: meeting date, attendees, key decisions, and open tasks spawned. Surface related meetings (via embedding similarity, already computed in `UnifiedMeetingDetail.swift:373`) that are not yet explicitly linked. Let the user one-click link them. Add an "AI Narrative" button that summarizes the project's history in prose.
- **Why (second-brain angle):** "What's the history of Project X?" is answered entirely within MeetingScribe — no Confluence, no Notion. The PM can onboard a new team member to project history in seconds.
- **Cross-feature connections:** Tasks (ProjectDetail) → Meetings (timeline) → DecisionStore (project decisions) → People (attendees) → AI Chat.
- **Effort:** M | **Impact:** High
- **Deps:** U3-1, existing `project.meetingIDs`

### U3-7: "Discussed in these meetings" backlink on every Decision
- **What:** After a decision is found via search or in the ledger, show a "Related meetings" panel: (a) the source meeting, (b) meetings where the same topic was discussed via embedding similarity, (c) meetings explicitly linking to the source meeting via backlinks (already computed in `backlinks(toMeetingID:)`, `WorkspaceIndex.swift:61–93`). One click opens the meeting at the relevant moment.
- **Why (second-brain angle):** Decisions don't live in isolation. "We chose Postgres" might have been foreshadowed two meetings earlier and revisited one meeting later. Showing the conversation thread around a decision is what makes the second brain actually useful.
- **Cross-feature connections:** DecisionStore → WorkspaceIndex backlinks → EmbeddingService → MeetingDetail (jump to transcript moment).
- **Effort:** S | **Impact:** Med
- **Deps:** U3-2, existing backlinks infrastructure

---

## Top 3 picks

1. **U3-2** — Decision FTS + semantic search: the single highest-leverage change. If you can't *find* a decision, nothing else matters. Indexing decisions into the vault FTS with embeddings turns the decision ledger from a read-only feed into a queryable knowledge base.
2. **U3-1** — Decision rationale extraction: "what" without "why" is useless 6 months later. Enriching the Decision struct with rationale (Ollama extracts it from the summary at summary-generation time, zero extra cost) makes every downstream feature — search, quarterly recap, project history — 10x more valuable.
3. **U3-3** — Topic-clustered Decision Ledger view: the dedicated researcher surface that makes MeetingScribe the canonical institutional memory tool. Without a top-level decisions view, power users will keep going back to raw meeting notes.
