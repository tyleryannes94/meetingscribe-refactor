# MeetingScribe v2 — Master Plan

*Compiled from 25-agent audit. Groups: Engineering (E1–E5), Product Management (PM1–PM5), Persona (U1–U5), UX (UX1–UX5), Competitive (C1–C5).*

---

## Executive Summary

MeetingScribe v1 has built a technically sophisticated local-first foundation — embeddings, FTS5, Ollama integration, RelationshipHealth scoring, calendar sync, iMessage analysis, a full MCP server, and a rich relational data model — but almost none of this infrastructure is visible or proactive from the user's perspective. Every AI interaction is pull-based: Tyler opens a tab, navigates somewhere, asks a question. The 25-agent audit converges on one defining diagnosis: **the app has the brain but not the behavior**. The infrastructure for a second brain exists; the pipelines, surfaces, and background intelligence that make a second brain feel alive do not. v2's mission is to close that gap: automate the seams between meetings, people, and tasks; surface the intelligence that is already computed but hidden; and shift from reactive chat to proactive ambient intelligence. The result should be a product where the second brain does work for Tyler while he's in his next meeting, not just when he remembers to open the app.

---

## Convergence Map

Items independently raised by 3 or more agents across different groups. These are the highest-confidence priorities.

| # | Theme | Convergent Agents | Groups Represented |
|---|-------|-------------------|-------------------|
| C-1 | **Post-Meeting Automation Pipeline** — meeting end triggers automatic encounter creation, owner resolution, integration push, and T+45 notification | PM1-1, PM2-1, PM4-1, PM5-3, E2-1, C5-4, C1-2, UX3-1, U1-2 | PM, ENG, COMPETITIVE, UX, PERSONA |
| C-2 | **Proactive / Push Intelligence — everything is reactive today** — Ollama is always on, ResourceGovernor exists, zero background AI work runs | PM1-3, PM3-1, PM5-1, PM5-2, E2-1, E2-2, C1, C3, C4, C5-2, UX5-1, U1-1, U4-5 | PM, ENG, COMPETITIVE, UX, PERSONA |
| C-3 | **SecondBrainDB / VaultIndexService extraction** — SecondBrainDB locked inside PeopleStore; decisions and tasks are dark to all AI recall | E2-3, E3-1, E3-5, E5-3, PM3-2, PM1 | ENG, PM |
| C-4 | **Embeddings built but entirely invisible to users** — UI never exposes embedding search, similarity, or connections | E2-3, E3-1, PM1, PM3-2, C1, C3-5, C4-6, C5, UX5, U3-2 | ENG, PM, COMPETITIVE, UX, PERSONA |
| C-5 | **Pre-meeting brief is passive and under-leveraged** — must be navigated to manually; lacks iMessage context and cross-meeting semantic synthesis | PM1-5, PM2-6, PM3-3, C3-6, C5-2, U1-1, U2-1, U5-3 | PM, COMPETITIVE, PERSONA |
| C-6 | **People: auto-encounter creation from meetings** — health scores and board are inaccurate without automatic encounter linkage | PM2-1, PM1-2, E5-1, U2-3, C2 | PM, ENG, PERSONA, COMPETITIVE |
| C-7 | **Person AI Recap Brief / "Brief Me"** — no single surface synthesizes transcript + iMessage + tasks + talking points per person | PM2-4, PM3-3, U2-1, C2-1 | PM, PERSONA, COMPETITIVE |
| C-8 | **Semantic search / vault exposure to users** — FTS5 and embeddings run but are never navigable in the UI | PM3-2, E2-3, E3-1, C4, U3-2, UX5 | PM, ENG, COMPETITIVE, UX, PERSONA |
| C-9 | **Decisions: rationale + FTS + search** — Decision struct has no rationale, no personIDs, not indexed for embeddings or FTS | U3-1, U3-2, E3-3, E3-5, C4-1, PM1-4 | PERSONA, ENG, COMPETITIVE, PM |
| C-10 | **Daily ritual anchoring** — morning notification is generic, weekly recap is pull-only, no scheduled proactive surfaces | PM5-1, PM5-2, U1-4, U4-5, C4-2 | PM, PERSONA, COMPETITIVE |
| C-11 | **followUpsSection + decisionsSection buried in "More"** — time-sensitive data hidden behind disclosure | U1-5, U3, U5, UX4-3 | PERSONA, UX |
| C-12 | **ResourceGovernor as universal AI work gating authority** — background jobs need thermal/battery gating before shipping | E2-2, PM3-5, E1 | ENG, PM |
| C-13 | **People ↔ Tasks cross-tab path broken** — no task create from People tab; no filter by person from Tasks; People → Project join is O(n) scan | PM1, PM2-5, E5-4, U2-2 | PM, ENG, PERSONA |
| C-14 | **Chat citations / source attribution missing** — AI answers unverifiable; erodes trust | C1-3, C3, C5, UX5-8 | COMPETITIVE, UX |
| C-15 | **ProactiveContextEngine / SecondBrainEventBus** — no typed event stream between stores; every cross-domain feature requires bespoke wiring | E1-1, E1-2, PM3, PM5, C5-1 | ENG, PM, COMPETITIVE |

---

## P0: Critical / Prerequisite Infrastructure

*Must ship before Phase 1. These items unblock 6–10 downstream features each. No user-facing UI changes required.*

### P0-A — VaultIndexService: Extract SecondBrainDB from PeopleStore
**Source agents:** E3-1 (top pick), E2-3, E5-3, PM3-2, PM1  
**What:** Move `SecondBrainDB` (or wrap as `VaultIndexService`) into a new `Infrastructure/` module exposed as an `@MainActor` singleton. Remove `private let db = SecondBrainDB()` from `PeopleStore.swift:69`. Add `indexDecision()`, `indexTask()`, `indexTranscript()`, `indexEncounter()` entry points. Wire `ActionItemStore`, `DecisionStore`, `MeetingStore` to call `VaultIndexService` after mutations. Run one-time backfill migration.  
**Why:** As long as SecondBrainDB is private to PeopleStore, every AI intelligence feature — embeddings, FTS, hybrid search, semantic recall — is structurally incapable of seeing decisions, tasks, or any future entity type. This is the root cause of Convergence Item C-4 (embeddings invisible).  
**Effort:** M (2–3 days)  
**Impact:** Unblocks E2-3, E3-2, E3-3, E3-5, E5-3, E2-1, E2-6, PM3-2, C4-6 — approximately 9 downstream features  
**Deps:** None  
**Files to read first:** `PeopleStore.swift` (line 69), `SecondBrainDB.swift`, `EmbeddingService.swift`, `VaultSearchService.swift`

### P0-B — SecondBrainEventBus
**Source agents:** E1-1, E1-2 (top picks), C5-1, PM3  
**What:** Typed `AsyncStream`-based event bus (`SecondBrainEventBus`) for cross-store events: `meetingFinalized`, `personUpdated`, `taskCreated`, `encounterLogged`, `decisionExtracted`. Replace current direct store cross-calls and `NotificationCenter` usage with typed event subscriptions.  
**Why:** Currently every cross-tab feature requires bespoke wiring between stores. An EventBus makes post-meeting automation (P0-C), background AI jobs (Phase 3), and future agentic features trivially composable without coupling stores.  
**Effort:** M  
**Impact:** Architectural prerequisite for the entire Phase 3 automation pipeline  
**Deps:** None (can ship in parallel with P0-A)  
**Files to read first:** `MeetingManager.swift`, `PeopleStore.swift`, `ActionItemStore.swift`, `NotificationManager.swift`

### P0-C — ResourceGovernor as Universal AI Work Gate
**Source agents:** E2-2, PM3-5, E1  
**What:** Extend `ResourceGovernor` to gate all background AI work (not just live transcription). Add `.backgroundEmbedding`, `.backgroundInsight`, `.backgroundNudge` work tiers. Background jobs check `ResourceGovernor.canScheduleWork(tier:)` before enqueuing.  
**Why:** Shipping background Ollama jobs (Phase 3) without a thermal/battery gate risks degrading live transcription quality. This is the safety prerequisite for all proactive AI features.  
**Effort:** S  
**Impact:** Safety gate for all of Phase 3  
**Deps:** None  
**Files to read first:** `ResourceGovernor.swift`

### P0-D — MeetingManager Actor Split
**Source agents:** E1-3 (top pick), E1  
**What:** Split `MeetingManager` into `TranscriptionEngine` (manages live recording, publishes `transcribingMeetingIDs`) and `MeetingLibraryService` (meeting CRUD, summary fetch, observable by multiple tabs). Today `MeetingManager` is a monolithic `@MainActor` class; every tick of `transcribingMeetingIDs` re-renders Today, Meetings, and any listening tab simultaneously.  
**Why:** Eliminates the most significant render-thrashing bottleneck. Required before adding more subscribers to MeetingManager state (Phase 3 pipeline, Today briefing card).  
**Effort:** M  
**Impact:** Performance prerequisite for Phase 3 and Phase 5  
**Deps:** P0-B (EventBus can replace some direct MeetingManager observers)  
**Files to read first:** `MeetingManager.swift`, `TodayView.swift`, `MeetingLibraryView.swift`

### P0-E — DecisionStore: SchemaEnvelope + Enriched Model
**Source agents:** E3-3, U3-1, PM1-4, E3  
**What:** Apply `SchemaEnvelope` + `DecisionSchemaMigrations` to `DecisionStore`. Enrich `Decision` struct with: `rationale: String?`, `personIDs: [String]`, `projectID: String?`, `status: DecisionStatus` (open/superseded/resolved), `revisitDate: Date?`. Run Ollama rationale-extraction pass at summary-generation time (zero extra cost — runs in the same pipeline pass).  
**Why:** Decisions are the most structurally underserved entity. No rationale = useless 6 months later. No personIDs = can't populate join tables (P0-F). This is the data prerequisite for the entire Phase 4 decisions ledger.  
**Effort:** S  
**Impact:** Prerequisite for C-9 (Decisions search), Phase 4  
**Deps:** P0-A (VaultIndexService will index decisions once model is enriched)  
**Files to read first:** `DecisionStore.swift` (lines 6–12), `SchemaMigrations.swift`

### P0-F — SQLite Join Tables for Cross-Entity Queries
**Source agents:** E3-2, E5-4, E2  
**What:** Add SQLite join tables: `meeting_persons`, `decision_persons`, `task_persons`, `encounter_tasks`. Materialize `Person.linkedProjectIDs` reverse edge at task-write time (currently O(n) ActionItemStore scan at `PersonDetailView.swift:1590`). Backfill from existing data.  
**Why:** Every cross-entity query today is a full in-memory sweep. Join tables enable O(log n) person → decisions → tasks → meetings queries in SQLite, directly powering PreMeetingBriefView, AI chat cross-entity tool chains, and WeeklyRecap.  
**Effort:** M  
**Impact:** Performance and correctness prerequisite for Phases 2 and 4  
**Deps:** P0-A, P0-E  
**Files to read first:** `SecondBrainDB.swift`, `PersonDetailView.swift` (line 1590), `ActionItemStore.swift`

---

## Phase 1: Second Brain Foundation

*Immediate second-brain value. All items assume P0 is complete. Low architectural risk.*

### 1-A — Index Action Items into vault_fts + Embeddings (E3-5)
**Source agents:** E3-5, PM1, PM3-2  
**What:** After every `ActionItemStore` mutation, call `VaultIndexService.indexTask()`. Tasks are the highest-frequency writes and currently invisible to ⌘K and AI chat recall.  
**Effort:** S | **Impact:** High | **Deps:** P0-A

### 1-B — Index Decisions + Encounters into Vault (E2-3, E3-1 extension)
**Source agents:** E2-3, E3-5, U3-2  
**What:** Wire `DecisionStore` and `EncounterStore` mutation hooks to `VaultIndexService`. Run one-time backfill for existing records.  
**Effort:** S | **Impact:** High | **Deps:** P0-A, P0-E

### 1-C — Streaming Summaries via /api/generate?stream=true (E2-4)
**Source agents:** E2-4 (top pick from E2), PM4  
**What:** Replace blocking `OllamaService` summary call with streaming SSE. Show token-by-token output in `MeetingSummaryView`. Turns 30–90s blank state into a live "thinking" experience.  
**Effort:** M | **Impact:** High | **Deps:** None (independent of P0)

### 1-D — PersonContextBuilder Canonical Service (E5-3)
**Source agents:** E5-3 (top pick from E5), E2, E3  
**What:** Create `PersonContextBuilder` actor that assembles canonical person context strings (last meeting, open tasks, talking points, iMessage themes, strength score, meeting mentions). Replace all ad-hoc context string assembly across chat, PreMeetingBriefView, WeeklyRecap, StandupDigest, MCP tools, GlobalSearch.  
**Effort:** M | **Impact:** High (immediate quality uplift across all 6 AI surfaces) | **Deps:** P0-F

### 1-E — Person: Aliases + LinkedExternalIDs (E5-2)
**Source agents:** E5-2, E5  
**What:** Add `aliases: [String]` and `linkedExternalIDs: [String: String]` to `Person` model. Expand `PersonResolver` to match on aliases and external IDs. Fixes silent name-only attendee miss bug: every unlinked attendee is a data-loss event that compounds across strength scores, encounter counts, and AI context.  
**Effort:** M | **Impact:** High | **Deps:** P0-F (join tables backfill benefits from correct resolution)

### 1-F — Persist RelationshipStrengthScore + Background Refresh (E5-1)
**Source agents:** E5-1, PM2-2, U2-3, C2-2  
**What:** Add `relationshipStrengthScore: Double` and `strengthLastComputedAt: Date` to `Person` model. Compute on meeting finalization and on a daily background timer (gated by P0-C ResourceGovernor). Feed Today strip ordering, WeeklyRecap health section, and KeepInTouchBoard ranking.  
**Effort:** M | **Impact:** High | **Deps:** P0-C, P0-F

### 1-G — Promote followUpsSection + decisionsSection Out of "More" (U1-5)
**Source agents:** U1-5, U3, U5, UX4-3 (convergence item C-11)  
**What:** Remove `followUpsSection` and `decisionsSection` from `moreSection` in `TodayView.swift`. Wrap each in content-availability guard (show when non-empty, hide when empty). One afternoon, one PR.  
**Effort:** S | **Impact:** High | **Deps:** None

### 1-H — Embedded Persistent Cache (E4-1)
**Source agents:** E4-1 (top pick from E4)  
**What:** Replace per-query `[Float]` deserialization of embedding vectors with a persistent `NSCache`-backed `EmbeddingCache` keyed by entity ID + content hash. Eliminates the largest hidden allocation on the retrieval hot path before hybrid search becomes the default for all AI features.  
**Effort:** M | **Impact:** Med (performance) | **Deps:** P0-A

### 1-I — O(1) WebAPI Meeting Lookup (E4-3)
**Source agents:** E4-3  
**What:** Replace linear scan in MCP/WebAPI meeting lookup with a Dictionary index keyed by meeting ID. One-hour fix that prevents MCP/Claude integration from degrading under 500+ meetings.  
**Effort:** S | **Impact:** Med | **Deps:** None

---

## Phase 2: People Intelligence Overhaul

*The "relationship OS" experience. Depends on Phase 1 data foundation.*

### 2-A — Auto-Encounter Creation from Meetings (PM2-1, convergence C-6)
**Source agents:** PM2-1 (top pick), PM1-2, E5, U2-3  
**What:** When a meeting is finalized, auto-create `Encounter` records for each confirmed attendee (`Encounter.meetingID` already exists). Resolve attendees against `PeopleStore` using `PersonResolver` (now with aliases from 1-E). The KeepInTouchBoard and health scores are meaningless for professional contacts without this.  
**Effort:** M | **Impact:** High | **Deps:** 1-E, P0-B (fires on `meetingFinalized` event)

### 2-B — "Brief Me" Button on Every Person Profile (U2-1, convergence C-7)
**Source agents:** U2-1, PM2-4, PM3-3, C2-1  
**What:** Add "Brief Me" button to `PersonDetailView` header. On tap, trigger `PersonContextBuilder.buildBrief(personID:)` → Ollama synthesis prompt → stream result into a native `PersonBriefView` sheet. Content: last meeting summary, open tasks owed/owed-by, talking points, iMessage themes, next calendar event, relationship health delta. This is the single most visible proof that MeetingScribe is a second brain.  
**Effort:** M | **Impact:** High | **Deps:** 1-D (PersonContextBuilder), 1-F (strength score), Phase 1 indexing

### 2-C — Commitment Ledger Per Person (U2-2)
**Source agents:** U2-2, PM1, U4-3  
**What:** Scope the existing global owe/owed split (TodayView.swift:399) to the person profile. Show "You owe Alex: [list]" and "Alex owes you: [list]" using `ownerPersonID` on `ActionItem`. S effort — the data linkage already exists.  
**Effort:** S | **Impact:** High | **Deps:** 1-A (tasks indexed), P0-F (join tables for O(1) lookup)

### 2-D — One-Tap Actions on KeepInTouchBoard Cards (PM2-3)
**Source agents:** PM2-3, PM2, C2  
**What:** Add hover-reveal action strip on board cards: "Log check-in" (one tap creates Encounter), "AI conversation starter" (Ollama local call — the "Clay moment"), "Remind me in 3 days." Converts the board from a guilt dashboard into a workflow tool.  
**Effort:** M | **Impact:** High | **Deps:** 2-A, 1-D

### 2-E — Multi-Signal Relationship Health: iMessage + Meeting Mentions (U2-3)
**Source agents:** U2-3, PM2-2, E5-1  
**What:** Integrate `MessagesAnalyzer` output into `RelationshipHealthService`. Weight: meeting frequency (existing) + days since last iMessage + response rate + iMessage sentiment. Without iMessage signals, health board produces false "Overdue" alerts for people Tyler texts regularly.  
**Effort:** M | **Impact:** High | **Deps:** 1-F, `MessagesAnalyzer.swift`

### 2-F — Task Mutation from People Tab (PM2-5)
**Source agents:** PM2-5, PM1, U2-2  
**What:** Add "New Task" button to `PersonDetailView` that creates an `ActionItem` pre-populated with `ownerPersonID`. Wire back to TasksStore. Closes the dead-end workflow where Tyler identifies a follow-up needed with someone but must switch tabs to capture it.  
**Effort:** S | **Impact:** High | **Deps:** P0-F

### 2-G — Relationship Summary Auto-Surfaced in PreMeetingBriefView (PM2-6)
**Source agents:** PM2-6, PM3-3, C3-6, U2-7  
**What:** Pull `summary-all` AttachedNote (already exists) into `PreMeetingBriefView` alongside iMessage thread context from `MessagesAnalyzer`. The brief is the highest-ROI moment for relationship intelligence (2 minutes before a call). 200-character relationship summary + last 3 iMessage thread subjects = "Brief Me" for the pre-meeting context.  
**Effort:** S | **Impact:** High | **Deps:** 1-D, P0-F

### 2-H — Relationship Velocity Trajectory Sparkline (PM2-2, U2-5)
**Source agents:** PM2-2, U2-5  
**What:** Add 12-week sparkline of encounter frequency to `PersonDetailView` and KeepInTouchBoard cards. Shows trajectory (accelerating/decelerating) rather than just current state. Requires persisted strength score history (store weekly snapshots).  
**Effort:** S | **Impact:** Med | **Deps:** 1-F

### 2-I — MeetingMentionRecord: Replace Raw Set<String> with Typed Backlink (E5-5)
**Source agents:** E5-5  
**What:** Replace `Person.meetingMentions: Set<String>` with `MeetingMentionRecord: {meetingID, role, timestamp, excerpt}`. Enables "mentioned in 3 decisions in Q4 planning" rather than just "mentioned in these meetings."  
**Effort:** M | **Impact:** Med | **Deps:** P0-F

### 2-J — Encounter Gains taskIDs — Close Person ↔ Encounter ↔ Task Triangle (E5-6)
**Source agents:** E5-6  
**What:** Add `taskIDs: [String]` to `Encounter`. Populate from auto-encounter creation (2-A) using action items extracted from the associated meeting. Closes the last missing edge in the person graph.  
**Effort:** S | **Impact:** Med | **Deps:** 2-A

---

## Phase 3: Post-Meeting Automation & Proactive AI

*The defining shift from v1 to v2: app works for Tyler while he's in his next meeting. Depends on P0 (EventBus, ResourceGovernor) and Phase 2 data quality.*

### 3-A — Unified Post-Meeting Pipeline (convergence C-1)
**Source agents:** PM1-1, PM2-1, PM4-1, PM5-3, E2-1, C5-4, C1-2, UX3-1 — **the highest-consensus item across all 25 agents**  
**What:** When `meetingFinalized` event fires on `SecondBrainEventBus`, orchestrate a sequential pipeline:
1. Auto-create `Encounter` records for confirmed attendees (2-A)
2. Resolve action item `ownerPersonID` fields against PeopleStore
3. Cross-link decision `personIDs` using meeting attendee list
4. Push to configured external integrations (Notion, Linear, Calendar) based on saved preferences
5. Fire `notifyTranscriptionComplete` push notification
6. Schedule T+45min "Did you capture everything?" follow-up notification
7. Trigger background `InsightEngine` pass (3-C) gated by ResourceGovernor

Implement as `PostMeetingPipelineCoordinator` actor subscribed to EventBus.  
**Effort:** L | **Impact:** Critical | **Deps:** P0-A, P0-B, P0-C, 2-A

### 3-B — Enriched Daily-Brief Notification with Deep Link (PM5-2, convergence C-10)
**Source agents:** PM5-2, PM1-3, U1-1, U4-5  
**What:** Replace generic 8am notification body (currently hardcoded in `NotificationManager.swift:234–245`) with live-computed content: "4 meetings · 2 follow-ups due · Alex's check-in overdue." Add `UNNotificationAction` with `"View Standup"` deep link to standup sheet. BriefCache pre-warm job fires at 7:50am (gated by ResourceGovernor).  
**Effort:** S | **Impact:** High | **Deps:** P0-C, 1-F, `NotificationManager.swift`, `BriefCache.swift`

### 3-C — ProactiveContextEngine / InsightEngine (convergence C-2)
**Source agents:** PM3-1, PM1-3, E1-4, E2-1, E2-6, C5, UX5-1  
**What:** `InsightEngine` background actor (Swift `Actor`) that runs on idle (AC power + nominal thermal, gated by P0-C ResourceGovernor):
- Relationship health scoring pass (refresh all persons with stale `strengthLastComputedAt`)
- Decision cross-linking pass (identify unlinked decisions from recent meetings)
- Semantic nudge generation (cosine similarity between recent meeting content and open action items → surface "this task seems related to your Q2 discussion")
- Pre-meeting brief pre-computation for next-24h calendar events

Publishes results to EventBus as `InsightAvailable` events that Today and notification system subscribe to.  
**Effort:** L | **Impact:** Critical (defines v2 identity) | **Deps:** P0-B, P0-C, 1-F, Phase 2

### 3-D — Voice Note → Auto-Extract Pipeline (U4-2)
**Source agents:** U4-2 (top pick from U4), PM1-6, U4  
**What:** After Ollama polish pass on voice note transcription (already runs), add a second structured-extraction pass: extract action items → `ActionItemStore`, identify mentioned persons → `PersonResolver` → link encounter, detect decision language → `DecisionStore`. Zero extra user action required.  
**Effort:** M | **Impact:** High | **Deps:** P0-B (fires `taskCreated`, `encounterLogged` events), 1-E

### 3-E — Post-Meeting Review Mode in Meeting Detail (UX3-1)
**Source agents:** UX3-1 (top pick from UX3), PM1-1, PM5-3  
**What:** Time-sensitive UI mode that appears in `UnifiedMeetingDetail` for 24h after meeting ends: checklist of "Review action items," "Link decisions to people," "Set follow-up calendar event," "Export to Notion." Auto-collapses when all items are checked or 24h expires. The human-in-the-loop complement to the automated 3-A pipeline.  
**Effort:** M | **Impact:** High | **Deps:** 3-A (pipeline populates checklist state)

### 3-F — Scheduled Weekly Review Ritual (PM5-1, convergence C-10)
**Source agents:** PM5-1, PM1-8, PM3-6, PM2-9, U1-4  
**What:** Friday 4:30pm push notification → native `WeeklyReviewView` (replace `WeeklyRecap.swift` markdown export). Content: Ollama-narrated weekly synthesis, carry-forward comparison to prior week, relationship pulse section, streaks and compounding value sparklines. Transforms the weekly review from a passive export into a scheduled closure ritual.  
**Effort:** M | **Impact:** High | **Deps:** 3-C (InsightEngine pre-computes), 1-F

### 3-G — Global Capture Bar (⌘⇧Space) (U4-1)
**Source agents:** U4-1 (top pick from U4), U1, U5  
**What:** System-level hotkey launches a floating capture panel (NSPanel, key window, does not require app focus). Supports: quick task (TaskQuickAddParser syntax), voice note (1-tap record), encounter log. Eliminates the navigation tax on all capture flows for all personas. `TaskQuickAddParser` already supports rich syntax — purely UX wiring.  
**Effort:** M | **Impact:** High | **Deps:** P0-B (dispatches events on capture)

### 3-H — Proactive Pre-Meeting Brief Push Notification (C5-2, PM1-5)
**Source agents:** C5-2, PM1-5, PM2-6, U1-1, U5-3  
**What:** 15 minutes before each CalendarEvent, fire a push notification with "View Brief" action deep-linking to `PreMeetingBriefView`. InsightEngine (3-C) pre-computes the brief at 3-C idle time so the view loads instantly. Closes the biggest ambient intelligence gap.  
**Effort:** M | **Impact:** High | **Deps:** 3-C, `CalendarService.swift`

---

## Phase 4: Knowledge Graph & Discoverability

*Surface the intelligence. Transforms the app from a recorder into a queryable second brain.*

### 4-A — Decision FTS + Semantic Index + Rationale (U3-1, U3-2, convergence C-9)
**Source agents:** U3-1, U3-2, E3-3, E3-5, C4-1, PM1-4  
**What:** Wire `DecisionStore` mutations to `VaultIndexService` (enabled by P0-A + P0-E). Index decision title + rationale + personIDs into vault_fts and embeddings. Turns the decision ledger from a read-only feed into a queryable knowledge base.  
**Effort:** M | **Impact:** High | **Deps:** P0-A, P0-E, 1-B

### 4-B — Semantic Connections Panel (C4-6, PM3-2, convergence C-8)
**Source agents:** C4-6, PM3-2, C1, C3-5, C5, UX5  
**What:** Add "Connections" section to entity detail views (`UnifiedMeetingDetail`, `PersonDetailView`, `DecisionDetailView`): embedding-powered cross-entity similar items panel. "Related meetings," "Mentioned in decisions," "People who discuss this topic." This is the highest-ROI use of already-built embedding infrastructure. Creates the "surprise discovery" moment defining second-brain tools.  
**Effort:** M | **Impact:** High | **Deps:** P0-A, 1-A, 1-B, Phase 1 indexing complete

### 4-C — "Why did we decide X?" Chat Tool (U3-5, C1-4)
**Source agents:** U3-5, C1-4, PM3-2  
**What:** New `searchDecisions(query:)` tool in `ChatTools.swift` backed by vault FTS + embedding hybrid search over decisions. Enables "Why did we choose React over Vue in March?" with cited source attribution (decision record + meeting backlink).  
**Effort:** S | **Impact:** High | **Deps:** 4-A

### 4-D — Topic-Clustered Decision Ledger View (U3-3)
**Source agents:** U3-3, PM1-4, C4-3  
**What:** New top-level `DecisionLedgerView` with topic clustering (k-means on decision embeddings → labeled clusters), filter by person/project/date range/status. Without a dedicated decisions view, power users re-litigate decisions they made months ago.  
**Effort:** L | **Impact:** High | **Deps:** 4-A, P0-E

### 4-E — Cited Answer UX in Chat (C1-3, convergence C-14)
**Source agents:** C1-3, C3, C5, UX5-8  
**What:** Add "Sources" disclosure group to `ChatBubble` showing retrieval evidence for grounded answers (meeting title + date, decision, person, task). Retrieval logging already happens in `searchVaultHybrid`; this is a pure UI addition. Without citations, the chat assistant is untrustworthy for real decisions.  
**Effort:** M | **Impact:** High | **Deps:** P0-A, Phase 1 indexing

### 4-F — Backlinks + Related Meetings Panel in Meeting Detail (UX3-2)
**Source agents:** UX3-2 (top pick from UX3), C4-6  
**What:** Add "Related" section to `UnifiedMeetingDetail` showing: similar meetings by embedding cosine similarity (already computed, just never displayed), shared attendees, referenced decisions. "The embedding similarity computation is already running and the results are already loaded into view state" (UX3 agent).  
**Effort:** S | **Impact:** High | **Deps:** P0-A

### 4-G — Expand RAG Grounding to All Entity Kinds (PM3-4)
**Source agents:** PM3-4, E2-7, C4  
**What:** Expand AI chat tool `searchVaultHybrid` to include people, tasks, encounters, and decisions in retrieval candidates. Increase `maxIterations` in `ChatTools.swift` to allow multi-hop chains (person → their decisions → related meetings). Currently restricted to meeting transcripts and voice notes.  
**Effort:** S/M | **Impact:** High | **Deps:** 4-A, 4-B

### 4-H — Quarterly Recap Generator (U3-4)
**Source agents:** U3-4, U3, PM5  
**What:** Extend `WeeklyRecap` pattern to a quarterly scope. Ollama synthesizes 12-week arc: decisions made, relationships grown, projects moved. Export to Notion as a structured quarterly review page. Valuable for performance reviews, investor updates, personal reflection.  
**Effort:** M | **Impact:** High | **Deps:** 3-F (weekly recap), 4-D (decision ledger)

### 4-I — ANN Vector Index — Replace allEmbeddings() Full Table Scan (E2-5, E3-4)
**Source agents:** E2-5, E3-4  
**What:** Replace the `allEmbeddings()` full-table scan in `searchVaultHybrid` with a cached ANN approximation (HNSW or SQLite-FTS5 cosine approximation). As the vault grows to thousands of entities, the current O(n) scan becomes the dominant latency in every AI response.  
**Effort:** L | **Impact:** Med (future-proofing) | **Deps:** P0-A, Phase 1 indexing complete

---

## Phase 5: Native macOS Excellence & Habit Loops

*Polish, daily rituals, onboarding. Items from Persona and UX groups.*

### 5-A — Relational Context Strip on Entity Detail Views (UX1-1)
**Source agents:** UX1-1 (top pick from UX1), UX2-4, UX3-2  
**What:** Horizontal scrollable strip at the top of `PersonDetailView`, `UnifiedMeetingDetail`, and task detail showing related entities: last meeting, open tasks, linked decisions, next calendar event. "The 5 silos perception disappears when each entity shows its neighbors" (UX1 agent). Uses join tables (P0-F) for O(1) lookup.  
**Effort:** M | **Impact:** High | **Deps:** P0-F, Phase 1 and 2 complete

### 5-B — ⌘K Cross-Entity Recency (UX1-3)
**Source agents:** UX1-3 (top pick from UX1)  
**What:** Expand `GlobalSearchView` (⌘K) to include recent people, decisions, tasks, and encounters in recency order alongside meetings. Uses existing `backStack` for frecency scoring. Transforms ⌘K from a meeting-picker into a true second-brain launcher.  
**Effort:** S | **Impact:** High | **Deps:** Phase 1 indexing complete

### 5-C — AI Morning Briefing Card on Today (UX4-1, PM5-2)
**Source agents:** UX4-1 (top pick from UX4), PM5-2, U1-1  
**What:** Native SwiftUI card at the top of `TodayView` rendered from the InsightEngine's pre-computed morning brief: one Ollama-synthesized paragraph connecting today's meetings, open follow-ups, and relationship nudges. Replaces the current static header. "Connects all 5 tabs in one paragraph. Zero new data models needed" (UX4 agent).  
**Effort:** M | **Impact:** High | **Deps:** 3-C (InsightEngine pre-computes brief), 3-B

### 5-D — Compounding Value Dashboard (PM5-4)
**Source agents:** PM5-4, PM5  
**What:** Add streak counter (flame icon + day count) to Today header anchored to daily opens and standup completions. Add 12-week sparklines for meeting frequency and action capture rate to a dedicated "Your Second Brain" section. Add `MetricsStore` events for ritual-completion tracking (prerequisite for all streak mechanics). Makes the second brain's value visibly compound.  
**Effort:** M | **Impact:** High | **Deps:** `MetricsStore.swift`, 3-F

### 5-E — Inline AI Insight Cards on Entity Detail Views (UX5-3)
**Source agents:** UX5-3 (top pick from UX5), PM3-1  
**What:** Pinned, auto-refreshing AI insight card at the top of `PersonDetailView` and `UnifiedMeetingDetail`. Ollama generates a 2-sentence proactive insight ("You haven't discussed the budget approval with Alex since June — it's marked open"). Dismissible. Refreshes on entity open (ResourceGovernor gated).  
**Effort:** M | **Impact:** High | **Deps:** 3-C, 1-D

### 5-F — Capability Discovery Panel ("What can I ask?") (UX5-2)
**Source agents:** UX5-2 (top pick from UX5 #3), U5-4  
**What:** Collapsible "What can I ask?" section in the chat rail showing categorized suggested prompts organized by entity type (People, Meetings, Decisions, Tasks). Pre-populated with real data ("Ask about your last 1:1 with Alex"). The tool suite is already implemented — users just don't know it exists.  
**Effort:** S | **Impact:** High | **Deps:** None

### 5-G — Tool-Use Narration and Write-Back Confirmation Cards (UX5-6)
**Source agents:** UX5-6  
**What:** Replace raw JSON tool-call bubbles in `ChatBubble` with human-readable narration ("I created a task for Alex due Friday") and inline confirmation cards for write operations with Undo affordance. Makes the AI feel like a product rather than a prototype.  
**Effort:** M | **Impact:** Med | **Deps:** None

### 5-H — Post-Onboarding "First Steps" Card + Onboarding Flow (U5-1, U5-3)
**Source agents:** U5-1, U5-3, U5-2, U5  
**What:** Dismissible "First Steps" card on Today blank state: 3 concrete actions (Record your first meeting, Add a person, Set your check-in cadence). "First Meeting Ready" push notification fires when first meeting summary completes. Plain-language rewrite of Screen Recording permission prompt. Closes the primary new-user abandonment cliff.  
**Effort:** S-M | **Impact:** High (retention) | **Deps:** None

### 5-I — End-of-Day Wrap-Up Card on Today (PM5-5, U1-3)
**Source agents:** PM5-5, U1-3  
**What:** After 5pm (configurable), Today appends an "End of Day" card: uncompleted follow-ups, action items created vs. completed, tomorrow's first meeting brief. Closes the daily loop and creates the "app told me I forgot something" moment that defines a second-brain experience.  
**Effort:** M | **Impact:** High | **Deps:** 3-C, 5-C

### 5-J — "Waiting On" Board — First-Class Delegation View (U4-3)
**Source agents:** U4-3, U4  
**What:** New `WaitingOnView` (sidebar section or Today card) showing tasks with `delegated: true` grouped by person with last-updated timestamp. The `delegated` flag already exists on `ActionItem`. Pure UI surface with O(1) lookup via P0-F join tables.  
**Effort:** M | **Impact:** High | **Deps:** P0-F

### 5-K — Privacy Positioning: "100% Local" Visible Badge (C1-5)
**Source agents:** C1-5, C1, C5  
**What:** Add persistent "100% Local · No Cloud" badge to Today header and onboarding. Capitalize on Limitless/Rewind shutdown leaving the privacy-first meeting intelligence space vacant. S effort; potentially high acquisition impact in a market actively looking for a local-first alternative.  
**Effort:** S | **Impact:** High (positioning) | **Deps:** None

---

## Phase 6: Integration Depth & External Connectivity

*Notion, Linear, Calendar, MCP expansion, bidirectional sync.*

### 6-A — Notion Bidirectional Sync (PM4-2)
**Source agents:** PM4-2 (top pick from PM4), C4-5  
**What:** Upgrade Notion integration from one-way action-item export to full bidirectional sync: create meeting summary pages with decisions and attendee relations, pull status changes back into `ActionItemStore`. Makes MeetingScribe the authoritative write-head for the user's knowledge system rather than a parallel silo.  
**Effort:** L | **Impact:** High | **Deps:** P0-E (decisions enriched), Phase 3 pipeline

### 6-B — Linear Action-Item Context Menu + Auto-Create (PM4-4)
**Source agents:** PM4-4, PM4  
**What:** Add Linear context menu to `ActionItem` rows in meeting detail and Today view: "Create Linear Issue" with pre-populated title, description (from meeting context), and assignee. Surfaces the most powerful integration at the exact moment the user decides to act on a task.  
**Effort:** M | **Impact:** High | **Deps:** None

### 6-C — Calendar Write-Back (PM4-5)
**Source agents:** PM4-5, PM4  
**What:** From PreMeetingBriefView and Post-Meeting Review Mode, allow scheduling follow-up events directly to CalendarService. "Schedule follow-up with Alex" creates a calendar event without leaving MeetingScribe.  
**Effort:** M | **Impact:** High | **Deps:** `CalendarService.swift`, 3-E

### 6-D — MCP Tool Surface Expansion — 8–10 New Fine-Grained Tools (C5-6)
**Source agents:** C5-6, PM4-10, PM2-10  
**What:** Add to `MeetingScribeMCP`: `getPersonBrief(personID:)`, `searchDecisions(query:)`, `listWaitingOn(personID:)`, `getRelationshipHealth(personID:)`, `getEncounterHistory(personID:limit:)`, `listOpenDecisions(projectID:)`, `getVoiceNoteExtracts(query:)`, `scheduleFollowUp(personID:date:)`. Makes MeetingScribe the richest MCP server for professional context among macOS apps.  
**Effort:** M | **Impact:** High | **Deps:** Phase 2 data model, 4-A

### 6-E — Unified Integration Status + Health Dashboard (PM4-8)
**Source agents:** PM4-8, PM4  
**What:** Settings section showing all integration statuses (Notion, Linear, Calendar, iMessage, MCP) with last-sync time, error state, and retry button. Currently integration failures are silent or cryptic.  
**Effort:** S | **Impact:** Med | **Deps:** None

### 6-F — Outbound Webhook System (PM4-6)
**Source agents:** PM4-6, C5-1  
**What:** User-configurable webhook endpoints triggered by EventBus events: `meetingFinalized`, `taskCreated`, `decisionExtracted`. Enables external automation (Zapier, custom scripts) without requiring an MCP client.  
**Effort:** M | **Impact:** Med | **Deps:** P0-B (EventBus)

### 6-G — Claude Projects Sync (C5-3)
**Source agents:** C5-3, C5  
**What:** Export meeting summaries, decisions, and people briefs to a user's Claude Project as a living knowledge source. MeetingScribe becomes the structured data layer for the user's Claude workspace. Requires periodic re-export on a schedule.  
**Effort:** M | **Impact:** High | **Deps:** Phase 2 complete, 4-A

---

## Appendix: Full Item Registry

| ID | Title | Source Agents | Phase | Effort | Impact | Deps |
|----|-------|--------------|-------|--------|--------|------|
| P0-A | VaultIndexService extraction | E3-1, E2-3, E5-3, PM3-2 | P0 | M | Critical | — |
| P0-B | SecondBrainEventBus | E1-1, E1-2, C5-1 | P0 | M | Critical | — |
| P0-C | ResourceGovernor universal gate | E2-2, PM3-5, E1 | P0 | S | Critical | — |
| P0-D | MeetingManager actor split | E1-3 | P0 | M | High | P0-B |
| P0-E | DecisionStore SchemaEnvelope + enriched model | E3-3, U3-1, PM1-4 | P0 | S | High | P0-A |
| P0-F | SQLite join tables | E3-2, E5-4 | P0 | M | High | P0-A, P0-E |
| 1-A | Index tasks into vault_fts + embeddings | E3-5, PM1 | 1 | S | High | P0-A |
| 1-B | Index decisions + encounters into vault | E2-3, U3-2 | 1 | S | High | P0-A, P0-E |
| 1-C | Streaming summaries | E2-4 | 1 | M | High | — |
| 1-D | PersonContextBuilder service | E5-3 | 1 | M | High | P0-F |
| 1-E | Person aliases + linkedExternalIDs | E5-2 | 1 | M | High | P0-F |
| 1-F | Persist relationshipStrengthScore | E5-1, PM2-2 | 1 | M | High | P0-C, P0-F |
| 1-G | Promote followUps + decisions out of "More" | U1-5 | 1 | S | High | — |
| 1-H | Embedding persistent cache | E4-1 | 1 | M | Med | P0-A |
| 1-I | O(1) WebAPI meeting lookup | E4-3 | 1 | S | Med | — |
| 2-A | Auto-encounter creation from meetings | PM2-1, PM1-2 | 2 | M | High | 1-E, P0-B |
| 2-B | "Brief Me" button on person profile | U2-1, PM2-4, PM3-3 | 2 | M | High | 1-D, 1-F |
| 2-C | Commitment ledger per person | U2-2, PM1 | 2 | S | High | 1-A, P0-F |
| 2-D | One-tap actions on KeepInTouch cards | PM2-3 | 2 | M | High | 2-A, 1-D |
| 2-E | Multi-signal relationship health | U2-3, PM2-2, E5-1 | 2 | M | High | 1-F |
| 2-F | Task mutation from People tab | PM2-5, U2-2 | 2 | S | High | P0-F |
| 2-G | Relationship summary in PreMeetingBrief | PM2-6, PM3-3, C3-6 | 2 | S | High | 1-D, P0-F |
| 2-H | Trajectory sparkline on board cards | PM2-2, U2-5 | 2 | S | Med | 1-F |
| 2-I | MeetingMentionRecord typed backlink | E5-5 | 2 | M | Med | P0-F |
| 2-J | Encounter gains taskIDs | E5-6 | 2 | S | Med | 2-A |
| 3-A | Unified post-meeting pipeline | PM1-1, PM4-1, E2-1, C5-4 | 3 | L | Critical | P0-A/B/C, 2-A |
| 3-B | Enriched daily-brief notification | PM5-2, U1-1 | 3 | S | High | P0-C, 1-F |
| 3-C | ProactiveContextEngine / InsightEngine | PM3-1, E1-4, E2-6 | 3 | L | Critical | P0-B/C, Phase 2 |
| 3-D | Voice note auto-extract pipeline | U4-2, PM1-6 | 3 | M | High | P0-B, 1-E |
| 3-E | Post-meeting review mode | UX3-1, PM5-3 | 3 | M | High | 3-A |
| 3-F | Scheduled weekly review ritual | PM5-1, PM1-8 | 3 | M | High | 3-C, 1-F |
| 3-G | Global capture bar (⌘⇧Space) | U4-1 | 3 | M | High | P0-B |
| 3-H | Proactive pre-meeting brief push | C5-2, PM1-5 | 3 | M | High | 3-C |
| 4-A | Decision FTS + semantic index + rationale | U3-1, U3-2, E3-3 | 4 | M | High | P0-A, P0-E, 1-B |
| 4-B | Semantic connections panel | C4-6, PM3-2 | 4 | M | High | P0-A, Phase 1 |
| 4-C | "Why did we decide X?" chat tool | U3-5, C1-4 | 4 | S | High | 4-A |
| 4-D | Topic-clustered decision ledger view | U3-3, PM1-4 | 4 | L | High | 4-A, P0-E |
| 4-E | Cited answer UX in chat | C1-3, UX5-8 | 4 | M | High | P0-A, Phase 1 |
| 4-F | Backlinks + related meetings panel | UX3-2, C4-6 | 4 | S | High | P0-A |
| 4-G | Expand RAG to all entity kinds | PM3-4, E2-7 | 4 | S/M | High | 4-A, 4-B |
| 4-H | Quarterly recap generator | U3-4 | 4 | M | High | 3-F, 4-D |
| 4-I | ANN vector index | E2-5, E3-4 | 4 | L | Med | P0-A, Phase 1 |
| 5-A | Relational context strip on entity views | UX1-1, UX2-4 | 5 | M | High | P0-F, Phases 1–2 |
| 5-B | ⌘K cross-entity recency | UX1-3 | 5 | S | High | Phase 1 |
| 5-C | AI morning briefing card on Today | UX4-1, PM5-2 | 5 | M | High | 3-C, 3-B |
| 5-D | Compounding value dashboard + streaks | PM5-4 | 5 | M | High | MetricsStore, 3-F |
| 5-E | Inline AI insight cards on entity views | UX5-3, PM3-1 | 5 | M | High | 3-C, 1-D |
| 5-F | Capability discovery panel | UX5-2, U5-4 | 5 | S | High | — |
| 5-G | Tool-use narration + write-back cards | UX5-6 | 5 | M | Med | — |
| 5-H | Post-onboarding first steps + onboarding | U5-1, U5-3 | 5 | S-M | High | — |
| 5-I | End-of-day wrap-up card | PM5-5, U1-3 | 5 | M | High | 3-C, 5-C |
| 5-J | "Waiting On" delegation board | U4-3 | 5 | M | High | P0-F |
| 5-K | "100% Local" privacy badge | C1-5 | 5 | S | High | — |
| 6-A | Notion bidirectional sync | PM4-2 | 6 | L | High | P0-E, Phase 3 |
| 6-B | Linear action-item context menu | PM4-4 | 6 | M | High | — |
| 6-C | Calendar write-back | PM4-5 | 6 | M | High | 3-E |
| 6-D | MCP tool surface expansion | C5-6, PM4-10 | 6 | M | High | Phase 2, 4-A |
| 6-E | Integration status dashboard | PM4-8 | 6 | S | Med | — |
| 6-F | Outbound webhook system | PM4-6, C5-1 | 6 | M | Med | P0-B |
| 6-G | Claude Projects sync | C5-3 | 6 | M | High | Phase 2, 4-A |
