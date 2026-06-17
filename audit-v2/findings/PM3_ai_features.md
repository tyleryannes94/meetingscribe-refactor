# AI & Local LLM Product Features — MeetingScribe v2 Audit

**Agent ID prefix: PM3-**

---

## Top friction points / gaps (file:line citations)

### 1. Embeddings are invisible to users
`EmbeddingService.swift` computes cosine-similarity vectors; `PeopleStore.swift:205` surfaces related meetings via `relatedMeetings(for:limit:)`. This is wired inside `UnifiedMeetingDetail.swift:61,372` and `MeetingNotesTab.swift:190` as auto-discovered backlinks — but the result is never exposed to the user as a navigable "Similar meetings" section, nor as a cross-tab signal ("3 past meetings with this person touched the same topic"). The user gets zero transparency into what the embedding index knows.

### 2. `generate()` is purely reactive — no proactive AI loop exists
`OllamaService.generate()` (`OllamaService.swift:254`) is called only in response to explicit user actions (record→summarize, click FollowUp, click PersonSuggestions). There is no idle-time worker that uses the always-on local LLM to enrich data silently. The `ResourceGovernor` (`ResourceGovernor.swift:9`) already exists to gate on thermal/battery state, but nothing consumes it for background AI work.

### 3. `PersonSuggestionEngine` is too narrow and gated behind a button
`PersonAISuggestions.swift:25–48` only proposes tags, relationships, and encounters — it does not generate relationship health scores, conversation trend analysis, or talking-point recommendations. The generation is also triggered manually, not after every new meeting that involved the person.

### 4. Follow-up generation is siloed to a single meeting, never cross-meeting
`FollowUpGeneratorService.swift` drafts per-meeting emails/Slack. There is no AI that composes a weekly summary email, a pre-1:1 nudge synthesizing the last 3 meetings + open tasks, or a "you have 4 things to catch up on with Alex" digest.

### 5. `SummaryFeedback` captures user thumbs-down but the signal is never aggregated
`SummaryFeedback.swift` stores per-meeting steering notes in `UserDefaults`. This feedback is injected into the next regeneration for the same meeting (`OllamaService.swift:350`) but is never used to tune the default prompt globally, identify which meeting types produce poor summaries, or surface "5 summaries thumbed down this month" as a diagnostic to the user.

### 6. Chat's RAG is meetings-only
`ChatSession.swift:250–264` retrieves only entities with `entityKind == "meeting"` for grounding. Voice notes, people memories, task descriptions, and decisions are never semantic-searched and injected into the assistant context.

### 7. `ResourceGovernor` is only wired to live transcription
`ResourceGovernor.swift:27–33` gates live transcription. Nothing gates the embedding backfill, Ollama summarization, or any future background AI work through the same thermal/battery policy. A hot M2 during a meeting could thrash an idle embedding job with no guard.

### 8. No AI-generated "why this matters to you" surface on Today tab
`TodayView.swift:41–51` triggers backfills on appear but produces only structured data (meetings, tasks). There is no AI narrative layer — no "Here's what's changed since Monday" or "Three open commitments from last week are overdue" written by the LLM from the user's own data.

---

## Existing items to endorse (from prior plan or codebase)

- **Retrieve-then-ground (C2-2)** in `ChatSession.swift:233–283` — a solid RAG foundation. Worth expanding to all entity kinds (see PM3-4).
- **Meeting type inference + type-aware prompts (C1-8)** in `OllamaService.swift:34–101` — smart pattern, should be extended to follow-up generation and pre-meeting brief generation.
- **Backfill infrastructure** (`backfillEmbeddingsIfNeeded`, `backfillSearchIndexIfNeeded`, etc. in `TodayView.swift:47–51`) — a clean idle-time pattern ready to host more AI enrichment tasks.
- **`ResourceGovernor`** — should be the single gating authority for ALL background AI work, not just live transcription.

---

## NET-NEW recommendations

### PM3-1: Proactive Insight Engine — silent background enrichment via Ollama
- **What:** A background `InsightEngine` actor that fires on idle (AC power + nominal thermal via `ResourceGovernor`) and runs Ollama jobs over unprocessed data: (a) generate a relationship-health score + conversation trend paragraph for any person with a new meeting since their last score; (b) extract "decisions" from voice notes (currently only done for meetings); (c) backfill `PersonAISuggestions` after every meeting that involved that person. All outputs are stored as structured fields and surfaced in-app without the user doing anything.
- **Why (second-brain angle):** Local LLM has zero marginal cost. Every minute the app is open while idle is wasted intelligence potential. The second brain should be continuously enriching itself.
- **Cross-feature connections:** People tab (relationship scores), Meetings tab (decisions from voice notes), Today tab (show freshly computed insights in the morning card).
- **Effort:** L | **Impact:** High
- **Deps:** PM3-5 (ResourceGovernor wiring)

### PM3-2: Semantic "Ask Your Vault" Surface — exposed embeddings in UI
- **What:** A "Related" sidebar chip set visible on every meeting, person, and task detail view, powered by cosine similarity from the existing embedding index. Clicking a related item navigates cross-tab. Add a "Why related?" tooltip that generates a one-sentence Ollama explanation on demand. In Global Search, add a "Semantic" toggle that switches from FTS to embedding similarity for fuzzy/conceptual queries ("meetings about hiring decisions").
- **Why (second-brain angle):** The embedding index is computed but invisible. Making it navigable turns silent infrastructure into a discoverable knowledge graph — the user can explore topics they don't know the exact words for.
- **Cross-feature connections:** Meetings ↔ People ↔ Tasks (cross-entity similarity); Global Search (new mode).
- **Effort:** M | **Impact:** High
- **Deps:** None (embedding index already populated)

### PM3-3: AI Relationship Brief — auto-generated pre-1:1 narrative
- **What:** For each upcoming 1:1 on the calendar, generate (via Ollama, triggered ~15 minutes before) a 3-paragraph "Relationship Brief": (1) what you've committed to each other since your last meeting, (2) open tensions or unresolved items extracted from memories + meeting summaries, (3) suggested talking points. Display inline in `PreMeetingBriefView`. Update `PersonSuggestionEngine` to also output a `conversationHealthScore` (0–100) and a one-line "relationship momentum" phrase.
- **Why (second-brain angle):** Pre-meeting brief today shows structured data (prior meetings, open tasks). Adding AI narrative synthesis makes it a true coaching surface — the app tells you what to say, not just what happened.
- **Cross-feature connections:** Calendar integration (timing trigger), People tab (health score persisted to person record), Meetings tab (consumed in pre-meeting brief).
- **Effort:** M | **Impact:** High
- **Deps:** PM3-1 (relationship health pipeline)

### PM3-4: Expand RAG grounding to all entity kinds
- **What:** Extend `ChatSession.groundedSystemPrompt()` (`ChatSession.swift:246`) to retrieve from people memories, voice notes, decisions, and task descriptions — not only `entityKind == "meeting"`. Add a `VaultIndex` protocol so each entity type can register itself as a semantic recall source. The retrieved context block should clearly label entity kind and link.
- **Why (second-brain angle):** "What has Alex been asking for across all our voice notes and tasks?" currently can't be answered from grounded context — the LLM has to fall back to tool calls. Full-vault RAG means the chat assistant can answer complex cross-entity questions in a single turn.
- **Cross-feature connections:** Chat (primary), People tab (memory retrieval), Voice Notes (semantic recall).
- **Effort:** M | **Impact:** High
- **Deps:** None

### PM3-5: ResourceGovernor as universal AI work gating authority
- **What:** Extend `ResourceGovernor` with a `shouldRunBackgroundAI: Bool` property and a `backgroundAIQoS: QualityOfService` property (`.utility` when AC + nominal thermal, `.background` on battery/fair, paused on critical/LPM). Wire ALL background Ollama tasks (embedding backfill, insight engine, relationship scoring) through this single gating function instead of each implementing its own heuristics.
- **Why (second-brain angle):** Prevents silent thermal/battery degradation from background AI work, and makes future AI features safe to add without per-feature power analysis.
- **Cross-feature connections:** All AI features.
- **Effort:** S | **Impact:** Med
- **Deps:** None

### PM3-6: AI Digest Composer — weekly narrative from structured data
- **What:** Replace the current `WeeklyRecap` markdown template with an Ollama-composed narrative: feed the LLM the week's meetings, closed tasks, new memories, and relationship check-in statuses, and have it write a 3-paragraph "what you accomplished / what's at risk / what to focus on" digest. Render in Today tab's Monday morning card and optionally email to self. Differentiate from `StandupDigest` (which is daily, tactical) — the weekly digest is strategic/reflective.
- **Why (second-brain angle):** Structured data summaries (lists of items) feel like a report. An LLM-composed narrative with your own data as source material feels like having a thoughtful chief of staff.
- **Cross-feature connections:** Today tab (Monday card), WeeklyRecap (replace/augment), People tab (relationship momentum included), Tasks tab (closed vs open ratio).
- **Effort:** M | **Impact:** High
- **Deps:** PM3-5

### PM3-7: SummaryFeedback aggregation + global prompt learning
- **What:** Persist `SummaryFeedback` ratings to a local SQLite table (not `UserDefaults`) with meeting type, rating, and reason. After 5+ thumbs-down with reasons, run an Ollama pass that reads all the negative feedback and proposes refined prompt additions for that meeting type. Present the proposal to the user with a one-tap "Apply" that updates the meeting-type instruction block in `OllamaService.MeetingType.instructionBlock`. Show a "Summary quality score" in Settings (% thumbs-up this month).
- **Why (second-brain angle):** The app should learn from the user's preferences, not just collect feedback that goes nowhere. A self-improving prompt loop means v2 summaries are personalized to how Tyler actually thinks about meetings.
- **Cross-feature connections:** Meetings tab (summary quality), Settings (prompt tuning), OllamaService (instructionBlock mutation).
- **Effort:** L | **Impact:** Med
- **Deps:** None

### PM3-8: In-context AI annotations on transcript — "highlight + ask"
- **What:** In the transcript view, let the user select any text span and hit a shortcut (⌘J) to open a popover asking "What's the context behind this?" or "Draft a follow-up about this." The selection is sent to Ollama with the surrounding meeting context as system prompt. The result is shown inline and can be saved as a note or memory. No modal, no context switch.
- **Why (second-brain angle):** The transcript is the richest raw data source and currently has zero interactive AI. This turns passive reading into active intelligence extraction at the moment of relevance, without breaking flow.
- **Cross-feature connections:** Meetings tab (transcript view), People tab (save as memory), Tasks tab (save as task).
- **Effort:** M | **Impact:** Med
- **Deps:** None

---

## Top 3 picks

1. **PM3-2 (Semantic "Ask Your Vault" surface)** — the embedding index is already built and dark; making it visible in the UI is the highest-ROI AI feature unlock in the codebase right now. Low deps, high payoff.
2. **PM3-3 (AI Relationship Brief)** — pre-meeting narrative synthesis directly addresses Tyler's stated "People feature overhaul" goal and the interconnectedness principle; bridges Calendar → People → Meetings in one feature.
3. **PM3-1 (Proactive Insight Engine)** — turns the local Ollama stack from a reactive tool into an always-on enrichment layer; this is what makes MeetingScribe feel like a second brain rather than a meeting recorder.
