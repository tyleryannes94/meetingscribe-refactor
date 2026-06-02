# Group 3 — Engineering Findings Summary
> 5 agents: E1 Architecture · E2 Data Model · E3 MCP Server · E4 Performance · E5 Testing
> Date: 2026-06-02

## Convergence (themes 3+ agents independently raised)

| Theme | Agents | Signal |
|---|---|---|
| `RelationshipType` enum missing at every layer — Person, PersonDTO, VaultKit, MCP, SQLite schema | E1, E2, E3 | 🔴 Universal blocker — every typed feature starts here |
| Encounter data exists on disk but has NO MCP tools, NO VaultKit DTO, NOT in PersonDTO | E3, P5 (cross-group) | 🔴 Core coaching loop completely blocked at MCP layer |
| NEW P0 BUG: Daemon stop path never calls `finalize()` | E4 | 🔴 Any meeting stopped via ScribeCore = no summary, no action items, no FTS index |
| `attach_note_to_person` implemented in PeopleChatTools.swift but NOT ported to MCP main.swift | E3 | 🟠 30-line copy = cumulative Claude coaching sessions |
| TSan CI test exists but `--sanitize=thread` never enabled in CI | E5 | 🟡 Thread safety tests are development-only, never enforced |

## New P0 Bug (E4 — not in any prior plan)
**Daemon recording path does not call `finalize()`.**
`MeetingManager.swift:136–149` — the `DarwinNotifier.recordingStopped` observer writes the raw live transcript and resets state without ever calling `pipelineController.finalize()`. Any meeting stopped via ScribeCore (the daemon) gets no summary, no action items, no FTS indexing, and no batch repair pass. This is a silent data-loss bug on the background-recording code path. **Fix: wire `finalize()` into the daemon stop handler before any other work.**

## Top Picks Per Agent

**E1 (Architecture):** E1-1 — `RelationshipPath` enum in VaultKit with `suggestedCheckInDays` and `supportsDepthContent` computed properties (backward-compatible optional, ~110 lines, S). E1-3 — Extract `EncounterStore` from PeopleStore (S, zero behavioral change, establishes pattern). E1-2 — `PersonDetailViewModel` to pull `personContextForAI()` and owner-matching out of view struct (unit-testable).

**PersonDetailView.swift decomposition map (E1):**
- `messagesSection` (~470 lines, 1356–1829) — biggest extraction; move `AnalysisScope`/`ConversationAnalysisPreset` enums out first
- `encountersSection` → `EncountersSectionView`
- `memoriesSection` → `MemoriesSectionView`
- `relationshipsSection` → `RelationshipGraphSectionView`
- Identity panel → `PersonIdentityPanel`

**E2 (Data Model):** Person persisted as JSON (`people/<slug>/person.json`), NOT SQLite rows. SQLite `secondbrain.db` (schema v2) has `people` table with 8 columns — none for relationship_type or cadence. E2-1 — Add `RelationshipType` enum + `checkInCadenceDays` + `loveLanguage` + `attachmentStyle` to `Person` (optional, decoder-safe). E2-5 — `migrateToV3()` in SecondBrainDB (additive `ALTER TABLE` only). E2-10 — Forward migration inferring type from existing `Relationship.label` strings ("spouse" → .partner, "dad" → .familyMember).

**E3 (MCP Server):** All 17 tools catalogued. Gaps: Encounter records invisible to Claude (no EncounterDTO in VaultKit, no tools), `attachedNotes` absent from PersonDTO and MCP, `attach_note_to_person` implemented in PeopleChatTools but never ported. E3-3 — Port `attach_note_to_person` (30 lines, one afternoon). E3-1+E3-2 — `EncounterDTO` + `get_person_encounters`/`log_encounter`. E3-10 — Split main.swift into 5 focused files.

**E4 (Performance):** E4-1 — Wire `finalize()` into daemon stop path (P0, hours). E4-9 — Surface `AVAssetWriter` finalization failures to trigger batch repair. E4-5 — Add missing SQLite indexes on `encounters_idx(event_tag_id)` and `encounters_idx(person_id)` (currently full table scans on @MainActor). SecondBrainCore + MeetingScribeShared are already gone from Package.swift.

**E5 (Testing):** 13 test files, ~53 methods — solid baseline. E5-5 — `RelationshipTypeTests` before writing any RelationshipType code (silent discard pattern in tolerant decoder). E5-1 — `NameSimilarityTests` (80 lines of Jaro-Winkler, zero tests, gates all People auto-linking). E5-6 — Enable TSan in CI (`--sanitize=thread`, one YAML line).

## Single Highest-Priority Recommendation (Engineering Group)
**E4-1: Wire `finalize()` into the daemon stop path** — this is a new P0 data-loss bug not in any prior plan. Any meeting stopped via the ScribeCore daemon silently produces no summary, no action items, no search index. Fix it before releasing. Takes hours, not days.

## Detail Files
- `findings/E1-architecture.md`
- `findings/E2-data-model.md`
- `findings/E3-mcp-server.md`
- `findings/E4-performance.md`
- `findings/E5-testing.md`
