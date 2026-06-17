# Engineering Group Compilation — MeetingScribe v2 Audit

**Agents represented:** E2 (AI/LLM Pipeline), E3 (Data Layer & Persistence), E5 (People Data Model & Cross-Feature Connectivity)
**Missing agents:** E1, E4 (no findings files present at compilation time — this document should be updated when those files land)

---

## Convergence within this group (items 2+ agents raised independently)

### 1. Embedding / FTS coverage gap — all 3 agents
E2 (gap #1), E3 (gaps #1, #3), and E5 (E5-2 deps, E5-3 rationale) all independently identify that the semantic search / FTS layer is scoped to meetings + voice notes only. People records, action items, encounters, and decisions are dark. The root cause differs slightly per agent — E2 focuses on the missing `embedAndStore` calls; E3 traces it to `SecondBrainDB` being gated inside `PeopleStore`; E5 notes that Person has no persisted strength score to use in recall ranking — but all three converge on the same fix: expand indexing to all entity types via a promoted shared service.

### 2. O(n) in-memory scan for cross-entity joins — E2 and E3
E2 (#2, allEmbeddings full scan) and E3 (#4, same issue; also #6, no SQLite join tables) both flag that every cross-entity query is a full in-memory sweep. E5 surfaces the same pattern for the `linkedProjectIDs` missing join (E5-4). The converged fix is (a) SQLite join tables for entity-to-person edges and (b) a cached/ANN vector index replacing the linear scan.

### 3. No proactive / background AI pipeline — E2 and E5
E2 (#5) identifies that every Ollama call is user-initiated. E5 (E5-1, relationship strength scheduling) proposes the same architectural fix: a background job that runs after meeting finalization and on a recurring timer to compute derived signals. Both agents converge on needing `ResourceGovernor` to gate background AI work.

### 4. Person model missing computed/persisted fields for AI intelligence — E5 + E2/E3 implications
All three agents' recommendations imply fields that don't exist on `Person`: strength score (E5-1), aliases for better resolution (E5-2), project edges (E5-4). E2's proactive job (E2-1) and E3's relational join tables (E3-2) both require these Person fields to be populated. The model gap is a shared dependency.

### 5. Decisions are structurally isolated — E3 and E5
E3 (#1, #2) identifies Decisions as dark to FTS/embeddings and structurally simple (no `personIDs`, no `projectID`). E5 (E5-5 rationale) highlights that the `meetingMentions` set on Person carries no role or context metadata — the same shallow-linkage pattern. Both converge on enriching cross-entity edges with typed, contextual metadata rather than bare ID sets.

---

## All net-new recommendations (deduplicated, with source agent IDs)

| ID | Title | Agent | Effort | Impact |
|----|-------|-------|--------|--------|
| E2-1 | Proactive Post-Meeting AI Background Job | E2 | M | High |
| E2-2 | ResourceGovernor — AI Work Scheduling Gate | E2 | S | High |
| E2-3 | Expand Embedding Coverage to All Entity Types | E2 | M | High |
| E2-4 | Streaming Summaries via /api/generate?stream=true | E2 | M | High |
| E2-5 | ANN Vector Index — Replace allEmbeddings() Full Table Scan | E2 | L | Med |
| E2-6 | Smart Nudge Engine — Relationship + Task Context Signals | E2 | L | High |
| E2-7 | Increase maxIterations + Cross-Entity Tool Orchestration | E2 | S/M | Med |
| E3-1 | Unified Entity Indexer — promote SecondBrainDB out of PeopleStore | E3 | M | High |
| E3-2 | Relational join tables in SQLite for cross-entity queries | E3 | M | High |
| E3-3 | Apply SchemaEnvelope + DecisionSchemaMigrations to DecisionStore | E3 | S | High |
| E3-4 | ANN approximation / cached embedding index for searchVaultHybrid | E3 | M | Med |
| E3-5 | Index action items into vault_fts + embeddings after store mutations | E3 | S | High |
| E5-1 | Persist `relationshipStrengthScore` + schedule background refresh | E5 | M | High |
| E5-2 | Add `aliases: [String]` and `linkedExternalIDs: [String: String]` to Person | E5 | M | High |
| E5-3 | PersonContextBuilder — canonical service replacing ad-hoc context strings | E5 | M | High |
| E5-4 | `linkedProjectIDs` reverse edge on Person — materialized at task-write time | E5 | S | High |
| E5-5 | MeetingMentionRecord — replace raw Set<String> with typed backlink | E5 | M | Med |
| E5-6 | Encounter gains `taskIDs: [String]` — close the person ↔ encounter ↔ task triangle | E5 | S | Med |

**Note:** E2-3/E2-5 and E3-1/E3-4 overlap significantly and should be implemented as one coordinated effort (see sequencing below).

---

## Group's top 10 picks with rationale

### 1. E3-1 — Unified Entity Indexer (promote SecondBrainDB out of PeopleStore)
**Rationale:** This is the single highest-leverage architectural fix in the Engineering group. It is a prerequisite for E2-3, E3-2, E3-5, and partially E5-3. Without it, decisions and action items remain dark to all AI recall, and every new entity type added in v2 will route through a layering violation. S–M effort that unblocks ~6 downstream features.

### 2. E5-3 — PersonContextBuilder canonical service
**Rationale:** Zero model schema changes, pure refactor, immediately improves quality of all six AI surfaces (chat, PreMeetingBrief, WeeklyRecap, StandupDigest, MCP tools, GlobalSearch). Can ship in isolation. High confidence, bounded scope, immediate payoff.

### 3. E3-5 — Index action items into vault_fts + embeddings
**Rationale:** S effort once E3-1 lands. Tasks are the highest-frequency writes in the app and are currently invisible to ⌘K and AI chat recall. Fixing this single gap produces the most visible improvement to AI chat answer quality.

### 4. E3-3 — SchemaEnvelope + enriched Decision model (personIDs, projectID, status)
**Rationale:** S effort. Transforms Decisions from read-only meeting artifacts into navigable second-brain nodes. Once personIDs are on decisions, E3-2's join table for `decision_persons` can be populated without a backfill problem.

### 5. E5-1 — Persisted relationshipStrengthScore + background refresh
**Rationale:** The persisted score is the numerical foundation for every proactive relationship intelligence feature: drift alerts, keep-in-touch ranking, Today strip ordering, WeeklyRecap health section. Without it, all strength-based features are live-computed, fragile, and unavailable to background jobs.

### 6. E2-2 + E2-1 — ResourceGovernor gate + Proactive Post-Meeting AI Job (bundled)
**Rationale:** These two are inseparable for safety. Shipping the background job (E2-1) without the thermal/battery gate (E2-2) risks degrading live transcription quality. Together they make the app proactively intelligent: pre-meeting briefs are pre-built, relationship scores are refreshed, new meeting entities are embedded — all while Tyler is away from the keyboard.

### 7. E5-2 — Aliases + linkedExternalIDs on Person
**Rationale:** Closes the PersonResolver name-only miss bug. Every incorrectly-missed attendee link is a silent data-loss event that compounds: the person's encounter count, strength score, meeting backlinks, and AI context all come up short. Fixing the resolver surface pays dividends across every AI feature.

### 8. E5-4 — linkedProjectIDs reverse edge on Person
**Rationale:** S effort. The person ↔ project join is currently a full ActionItemStore scan in the view layer (PersonDetailView.swift:1590). Materializing it at write time makes the "What is Jane working on?" query O(1) and enables the Today 1:1 strip to show shared projects for upcoming meetings.

### 9. E3-2 — Relational join tables in SQLite
**Rationale:** Enables all complex cross-entity queries (person → decisions → tasks → meetings) to happen in SQLite rather than in-memory Swift loops. Directly powers PreMeetingBriefView, the AI chat's cross-entity tool chains, and WeeklyRecap. Dep on E3-1.

### 10. E2-4 — Streaming Summaries via /api/generate?stream=true
**Rationale:** Highest visible UX impact per engineering hour in the AI pipeline. Turns a 30–90s blank state after a meeting into a live streaming experience. No architectural changes needed — purely additive to OllamaService.

---

## Group's highest-priority single recommendation

**E3-1 — Unified Entity Indexer: extract SecondBrainDB from PeopleStore into a shared service.**

Every other Engineering recommendation in this group either (a) requires it as a prerequisite or (b) is severely undercut without it. As long as `SecondBrainDB` is private to `PeopleStore`, the entire intelligence layer — embeddings, FTS, hybrid search, semantic recall — is structurally incapable of seeing decisions, tasks, or any future entity type. This is the one change that makes MeetingScribe's "second brain" label accurate rather than aspirational.

**Implementation path:**
1. Move `SecondBrainDB` (or wrap as `VaultIndexService`) into a new `Infrastructure/` module, exposed as a singleton.
2. Remove the `private let db = SecondBrainDB()` from `PeopleStore.swift:69`; switch all `PeopleStore` callers to `VaultIndexService.shared`.
3. Add `indexDecision()`, `indexTask()`, `indexTranscript()` entry points.
4. Wire `ActionItemStore`, `DecisionStore`, `MeetingStore` to call `VaultIndexService` after mutations.
5. Run one-time backfill migration for existing decisions and tasks.

Estimated effort: **M** (2–3 days). No user-facing changes. No schema changes to existing entity files. Unblocks E2-3, E3-2, E3-3, E3-5, E5-3, E2-1, E2-6 — approximately 7 features that compound into the app's v2 identity.
