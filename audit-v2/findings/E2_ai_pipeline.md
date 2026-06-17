# AI & LLM Pipeline Engineering Findings — MeetingScribe v2 Audit

**Agent ID:** E2  
**Sub-lens:** Ollama pipeline, embeddings, chat tool-use, proactive AI, throughput

---

## Top friction points / gaps (file:line citations)

### 1. Embedding coverage is limited to meetings and voice notes — no people, tasks, or action items

`SecondBrainDB.swift:214` defines `entity_kind IN ('person','meeting','encounter','action_item','voice_note')` in the schema constraint, and the `embedAndStore` calls exist for that set — but in practice only meetings (`MeetingPipelineController.swift:246`, `MeetingManager.swift:1068`) and voice notes (`QuickNotesController.swift:261`) ever get embedded. People records, action items, encounters, and projects are never passed through `EmbeddingService.embed()`. That means a semantic query like "find people I haven't talked to who worked on authentication" will never surface a person record — only meetings that mention authentication. The "second brain" embedding layer is siloed to content-type meetings.

### 2. allEmbeddings() scans the full table for every hybrid search

`SecondBrainDB.swift:470` runs `SELECT entity_id, entity_kind, dim, vec FROM vault_embeddings` — loading every stored vector into memory — every time `searchVaultHybrid` is called (`PeopleStore.swift:223`). At 100 meetings this is fine. At 1,000+ meetings with people and action items added (the right v2 state), this is a 10-50 MB in-memory scan per query with O(n) cosine comparisons done serially in Swift. There is no ANN index (FAISS, sqlite-vss, or even a basic HNSW). This will feel sluggish and is a scale cliff.

### 3. generate() / summarize() use /api/generate (non-streaming) with a 600-second timeout

`OllamaService.swift:253-289` calls `/api/generate` with `stream: false`. For a 1-hour meeting transcript on `qwen2.5:7b` this can block the URLSession task for 30-90 seconds with zero UI feedback. The chat client (`OllamaChatClient.swift:121-129`) caps `num_ctx` at 4,096 for conversational speed, but the summarizer uses 8,192 (`OllamaService.swift:269`) — inconsistent policy across the same model. No streaming mode exists in either path.

### 4. ResourceGovernor governs Whisper live transcription only — not Ollama

`ResourceGovernor.swift` exposes `shouldRunLiveTranscription` but has no equivalent `shouldRunBackgroundAI` or `shouldEmbedNow` gate. Any proactive embedding or background summarization task spawned post-meeting (`Task { await PeopleStore.shared.embedAndStore(…) }` at `MeetingPipelineController.swift:246`) runs at the same QoS regardless of whether the Mac is under thermal pressure or on battery. On a MacBook during a meeting, this could create a thermal feedback loop.

### 5. No proactive AI pipeline exists — everything is pull-only (user-initiated)

The entire Ollama call graph is reactive: user asks chat a question → tool calls fire → response. There is no background daemon that processes completed meetings, scores relationship health, surfaces upcoming context, or generates meeting-prep packages. `PreMeetingBriefView.swift:375` calls `OllamaService().generate(…)` only when the user opens the brief view — the LLM result is computed on-demand rather than pre-cached. On a slow model this means the user stares at a spinner before a call instead of seeing a pre-built brief.

### 6. The tool-use dedup is session-local only and maxIterations is 6

`OllamaChatClient.swift:98-100` — `seenToolSignatures` is a local `Set<String>` that resets each `send()` call. A multi-turn conversation can repeat the same tool call across turns because the dedup doesn't persist between turns in the session's full conversation log. `maxIterations = 6` (`OllamaChatClient.swift:79`) is a hard ceiling; complex cross-entity queries (person → meetings → action items → projects) regularly hit this limit and surface an HTTP -2 error to the user.

### 7. HardwareProfile recommends model but doesn't gate proactive tasks

`HardwareProfile.swift` provides `recommendedSummaryModel` but the chat client uses `AppSettings.shared.ollamaModel` unconditionally (`OllamaChatClient.swift:124`). If the user has `llama3.1:70b` configured and only 8 GB RAM, every chat turn will thrash. The hardware profile knowledge is only surfaced as a Settings hint string — not enforced at runtime.

---

## Existing items to endorse (from prior plan or codebase)

- **Connection state caching** (`OllamaService.swift:144-163`): The 5-second freshness window for the `/api/tags` probe is well-designed — eliminates redundant probe calls during post-meeting embedding bursts.
- **Leaked tool call recovery** (`OllamaChatClient.swift:277-333`): The brace-matched JSON parser for models that emit tool calls as plain text is defensive engineering worth keeping. It correctly handles nested-object arguments and code-fence wrapping.
- **Hybrid recall with RRF** (`PeopleStore.swift:220-230`): Reciprocal-rank fusion of lexical + semantic results is the right architecture; the gap is scope (only meetings/voice notes) and scale (linear scan).
- **Type-aware meeting summaries** (`OllamaService.swift:34-101`): Meeting-type inference from title keywords + attendee count is clean and conservative. Already implemented.
- **EgressPolicy guard** (`OllamaService.swift:264`, `EmbeddingService.swift:26`): Blocking non-local egress for transcript/embedding content is a strong privacy invariant worth preserving throughout all new proactive features.

---

## NET-NEW recommendations

### E2-1: Proactive Post-Meeting AI Background Job
- **What:** After `MeetingPipelineController` finishes a meeting, enqueue a background `Task` (gated by `ResourceGovernor`) that: (a) embeds all attendees' Person records if not yet embedded; (b) embeds all action items extracted from the meeting; (c) pre-generates the pre-meeting brief for the *next* meeting with any overlapping attendees; (d) scores the relationship health delta for each attendee. Use `.background` QoS, cancel if thermal state reaches `.serious`.
- **Why (second-brain angle):** Today the LLM only fires when the user asks. True second-brain behavior means Tyler opens the pre-meeting brief and the context is already there — pre-built while the Mac was idle. Zero marginal cost since Ollama is local.
- **Cross-feature connections:** Meetings → People (embedding people on meeting completion) → Today (pre-cached brief ready in PreMeetingBriefView) → Tasks (action item embeddings for semantic search).
- **Effort:** M | **Impact:** High
- **Deps:** E2-2 (ResourceGovernor gate), E2-3 (embedding scope expansion)

### E2-2: ResourceGovernor — AI Work Scheduling Gate
- **What:** Add `shouldRunBackgroundAI: Bool` to `ResourceGovernor` (gates on: not `.critical` thermal, not active meeting recording, not low-power-mode) and `preferredOllamaNumCtx: Int` (returns 2048 on battery/fair thermal, 8192 otherwise). All proactive Ollama calls must check this gate before firing. Integrate with the existing `deferLiveTranscriptionOnBattery` pattern.
- **Why:** Without a gate, background embedding during a live meeting (or after, on battery) creates thermal pressure that degrades Whisper transcription quality and user experience.
- **Cross-feature connections:** Governs E2-1, E2-3, E2-4. Works alongside the existing transcription deferral logic.
- **Effort:** S | **Impact:** High
- **Deps:** none

### E2-3: Expand Embedding Coverage to All Entity Types
- **What:** Call `embedAndStore` for Person records (display name + role + memories concatenated), action items (title + notes + ownerName), and encounters (content field) on creation/update. Add a one-time backfill `MigrationRunner` step that embeds all existing entities. Update `searchVaultHybrid` to accept an optional `entityKinds: Set<String>` filter so callers can scope to people-only or tasks-only semantic search.
- **Why:** Cross-entity semantic recall is the core of the second brain premise. "Find everyone I talked to about authentication before I shipped it" requires people embeddings. Currently impossible.
- **Cross-feature connections:** People tab (semantic recall in global search), Tasks (find tasks similar to current discussion), Chat (tool `search_vault` returns people + task results).
- **Effort:** M | **Impact:** High
- **Deps:** E2-5 (ANN scaling, ideally before rolling out to large collections)

### E2-4: Streaming Summaries via /api/generate?stream=true
- **What:** Add a `generateStreaming(prompt:…, onChunk: (String) -> Void)` method to `OllamaService` that uses `/api/generate` with `stream: true` and a line-by-line NDJSON reader. Wire `MeetingPipelineController` and `PreMeetingBriefView` to stream into a `@Published var streamedSummary: String` so the UI shows progressive output.
- **Why:** A 45-second blank state while Ollama finishes is a UX cliff. Streaming shows first tokens within ~1s on M2. The `OllamaChatClient` already handles streaming conceptually (it has a `progress` callback for tool calls) — this extends that pattern to generation.
- **Cross-feature connections:** Meeting detail (summary appears progressively), PreMeetingBriefView (brief renders live), FollowUpGeneratorService (follow-up draft appears word-by-word).
- **Effort:** M | **Impact:** High
- **Deps:** none

### E2-5: ANN Vector Index — Replace allEmbeddings() Full Table Scan
- **What:** Introduce a `VectorIndex` class backed by an in-process HNSW or ball-tree structure (can be pure Swift or wrap sqlite-vss). On app launch, load all vectors into the index once. On upsert, update the index incrementally. Replace the `allEmbeddings()` linear scan in `searchVaultHybrid` and `relatedMeetings` with an approximate k-NN query. At 500 entities, the scan costs ~5ms; at 5,000 (full people + tasks + meetings), it crosses 100ms and blocks the search thread.
- **Why:** Scale cliff. The current O(n) scan is fine for a prototype but will degrade when People embeddings are added (E2-3). Fix the foundation before the scope expands.
- **Cross-feature connections:** GlobalSearch (fast semantic recall), People graph (fast "related people" suggestions), Meetings (fast "related meetings" backlinks).
- **Effort:** L | **Impact:** Med (won't matter until user has 500+ embedded entities, but that's achievable within months of v2 launch)
- **Deps:** E2-3

### E2-6: Smart Nudge Engine — Relationship + Task Context Signals
- **What:** A lightweight background service (`SmartNudgeEngine`) that runs on a 30-minute timer (only when `shouldRunBackgroundAI`). It queries: (a) people with `relationshipHealth == .drifting` who have an upcoming meeting in the next 48h (from CalendarKit integration); (b) action items past due where the owner is an attendee in an upcoming meeting; (c) decisions from past meetings that have not been referenced or followed up on in 60+ days. Surfaces these as dismissible notification banners in the Today view.
- **Why:** This is the core proactive second-brain feature. Tyler should not have to remember to check — the app should notice "You have a 1:1 with Sarah tomorrow and you haven't talked since her last check-in 40 days ago; here's what you discussed then."
- **Cross-feature connections:** Today (banner widget) → People (relationship health) → Meetings (prior discussion context) → Tasks (overdue items for the person).
- **Effort:** L | **Impact:** High
- **Deps:** E2-1, E2-2, E2-3

### E2-7: Increase maxIterations and Add Cross-Entity Tool Orchestration
- **What:** Raise `maxIterations` from 6 to 12 in `OllamaChatClient.swift:79`. Add a `plan_and_execute` meta-tool that takes a multi-step user intent (e.g., "brief me on Sarah before tomorrow") and returns a structured JSON plan of sub-tool calls, which the loop then executes sequentially. This prevents the model from exhausting iterations on a linear chain when it could plan ahead.
- **Why:** 6 iterations fails any query that requires: get person → list their meetings → get meeting summaries → list open action items → synthesize. That's already 5+ tool hops. Real cross-entity questions hit the wall routinely.
- **Cross-feature connections:** Chat (all tabs), PreMeetingBriefView (pre-meeting intelligence).
- **Effort:** S (maxIterations change is trivial; plan-and-execute is M)
- **Impact:** Med
- **Deps:** none

---

## Top 3 picks

1. **E2-4 (Streaming Summaries)** — Highest visible UX impact, lowest risk, independent of all other changes. Turns a UX dead-zone into a delightful "thinking out loud" experience with ~1 day of work.
2. **E2-1 + E2-2 (Proactive Background Job + ResourceGovernor gate)** — These two together unlock the "second brain" promise: Tyler's pre-meeting brief is pre-built, his relationship nudges are ready, and the Mac's thermal state is respected throughout. This is the single change that makes the app feel proactive vs. reactive.
3. **E2-3 (Expand Embedding Coverage)** — Without people and task embeddings, "semantic search" is really just "meeting keyword search." Expanding coverage to all entity types is a prerequisite for any meaningful cross-entity intelligence and should be the first migration step after the ResourceGovernor gate is in place.
