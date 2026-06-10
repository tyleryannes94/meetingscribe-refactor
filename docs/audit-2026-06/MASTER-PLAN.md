# MeetingScribe Refactor — Unified Master Plan (25-Agent Audit Synthesis)

> **Target repo:** `~/MeetingScribeRefactor` · 269 Swift files · ~59K LOC
> **Method:** 25 independent auditors across 5 expertise groups — Design, PM, Staff Eng, End-User, Competitive. 125 deduped recommendations.
> **Per-group digests** (alongside this file): `GROUP-DESIGN.md` (→ `GROUP-1-DESIGN-FINDINGS.md`), `GROUP-PM.md` (→ `GROUP-2-PRODUCT-FINDINGS.md`), `GROUP-ENGINEERING.md` (→ `GROUP-3-ENGINEERING-FINDINGS.md`), `GROUP-END-USER.md` (→ `GROUP-4-PERSONA-FINDINGS.md`), `GROUP-COMPETITIVE.md` (→ `GROUP-5-COMPETITIVE-FINDINGS.md`).

---

## 1. Executive summary

**North star the audit converged on:** *Be the trustworthy, 100%-local "second brain" that captures every meeting and every relationship — and makes that captured context **agentically queryable** by both the human and Claude — with zero data leaving the Mac.* Privacy is not the pitch; it is the qualifier. The wedge is **capture completeness + recall + on-device intelligence**.

Three structural truths emerged independently from multiple groups:

1. **The plumbing is further along than the product.** Powerful engines already exist but are unwired: FTS5/BM25 hybrid search (`WorkspaceIndex.swift`, `SecondBrainDB.swift`), `RelationshipPromptLibrary` (28 Gottman/NVC prompts), `DecisionStore` (`Sources/MeetingScribe/Decisions/`), speaker diarization output, the `ProPaywallView`, `FeatureGate`, and `WorkspaceRouter.openMeeting/openPerson`. **The single highest-leverage move is wiring what already exists**, not building new engines. (5/5 groups flagged ≥3 unwired engines.)

2. **The app silently loses data and can't see itself.** Daemon recordings never call `finalize()`; live transcripts truncate the final minutes; SQLite migrations swallow errors; `insertPerson()` drops v3 columns; embeddings orphan on delete. Meanwhile there is **no funnel instrumentation, no integration test, and no CI gate** — so the app is blind to its own correctness. Reliability + observability is the foundation everything else stands on. (Engineering group: 10/15 items are correctness/data-integrity.)

3. **Positioning is undecided, and that paralyzes monetization.** Is this a **meeting tool** ($10–15/mo) or a **relationship coach** ($20–30/yr)? Both PM and Competitive groups demand the decision be made and embedded in code (`MeetingScribeApp.swift` + `CLAUDE.md`) before Phase 2. The monetization rails (`FeatureGate`, `ProPaywallView`) are built but `overrideAllEnabled = true` and the paywall is never presented — **one `.sheet` binding away from being live.**

**Headline themes:** (a) *Make it trustworthy* — fix data-loss + add tests/CI/observability; (b) *Make it queryable* — finish RAG + MCP read/synthesize tools; (c) *Make it a habit* — onboarding, encounter quick-log, proactive briefs/notifications; (d) *Make it pay* — decide the wedge, present the paywall, license intelligence not data; (e) *Make it native* — App Intents, Spotlight, WidgetKit, Apple Foundation Models, Obsidian-vault moat.

---

## 2. Cross-cutting themes (125 items → 8 clusters)

> ⭐ = multiple independent groups converged (high signal).

| # | Theme | What it covers | Convergence |
|---|-------|----------------|-------------|
| **T1** | **Reliability & data integrity** ⭐ | finalize-never-called, live-transcript truncation, daemon orphan folders, SQLite transactions + integrity check, `insertPerson` v3 columns, atomic writes, write-ahead journal, vault migration path write-back, dup-encounter/stale-notification bugs, directory-traversal validation | Eng (core) + PM (P0 bugs) + End-User (silent ghosting) |
| **T2** | **Testability & observability** ⭐ | E2E pipeline harness, golden-audio WER suite, CI gate (build/test/TSan/coverage), funnel + activation event log, reliability dashboards (cold-launch, RTF, health), north-star "Capture rate" | Eng + PM converge directly |
| **T3** | **Time-to-value & onboarding** ⭐ | de-jargon first-run, disambiguate 3 record buttons, "Setup Complete" celebration, Day-0 seed-3-people flow, auto-populate People from attendees, SetupCheck required-vs-optional split, adaptive "Next steps" card, first-summary confetti | Design + PM + End-User all independently |
| **T4** | **Navigation, IA & design-system maturity** ⭐ | route Today→canonical detail, unify split panes, `EntityLink` router protocol, `selectedPersonID`, Recents+Cmd-K, forward/back stack, NDS.motion gating, accessibility (labels/glyphs/Dynamic Type), button consolidation, `RelationshipType.color`, loading skeletons, paywall token migration | Design (owns) + End-User (nav stack) |
| **T5** | **Relationship-coach habit loop** ⭐ | chip-first encounter quick-log, health score + ring, check-in notifications + Today drift strip, `RelationshipType` cadence extension, auto-bump `lastInteractionAt`, calendar-aware drift, growth-theme threads, quiet 1:1 capture, relationship prompts Pro-gated, warm copy | PM + End-User + Design converge hard |
| **T6** | **Recall, knowledge synthesis & MCP** ⭐ | finish whole-vault RAG + citations, Decision/Commitment Ledger, directed commitments (iOwe/theyOwe), backlinks index, MCP write tools + search_everything + resources + find_path, MCP 2025-06-18 spec, coaching-framework coverage, registry publish, graph generalization | PM + End-User + Competitive — strongest cross-group cluster |
| **T7** | **Monetization & positioning** ⭐ | DECIDE the wedge, wire paywall sheet, invert `overrideAllEnabled` + QA toggle, LicenseManager (Ed25519/Keychain), free tier + price anchors, "license intelligence not data", compliance-grade positioning, provable-privacy panel | PM (owns) + Competitive |
| **T8** | **Native platform & competitive parity** | App Intents/Spotlight/WidgetKit/Control Center, Apple Foundation Models backend, Apple Reminders write, in-meeting scratchpad, mid-call recap, calendar auto-record, conversation intelligence, Obsidian moat, iPhone Shortcuts capture, retention/right-to-forget | Competitive (owns) + End-User (Shortcuts, mobile) |

**Architecture/tech-debt** (Eng) is connective tissue under all themes: `CaptureKit` extraction (kills app/daemon dupe), Services domain layer + DI (kills 494 `.shared` accesses — verified), typed versioned `ScribeBridge` IPC, `VaultFileStore` unifying app+MCP persistence, `@Observable` migration, `PersonDetailView` decomposition (2,356 LOC — verified). Sequenced as enablers, not standalone bets.

---

## 3. Phases

Each workstream is written to be handed directly to Claude Code. Effort: **S** ≤1 day · **M** 2–4 days · **L** ≥1 week. Build gate per `CLAUDE.md`: `swift build -c release` (or `make app`) must pass before any push.

---

### PHASE 1 — Stop the bleeding & turn on the lights (Foundations + quick wins)

**Goal:** No more silent data loss. The app can test itself, see its funnel, present a paywall, and a new user reaches first-summary without jargon. Decide the wedge.

#### 1A. Data-integrity P0s (T1) — **must ship first**
- **Fix daemon orphan recordings** — gate `ScribeCore` daemon recording behind `AppSettings.usingScribeCoreRecording` (default **false**) until finalize lands. *Files:* `ScribeCore/ScribeCoreApp.swift`, `ScribeCore/MeetingPipelineController.swift`, `ScribeCore/AppSettings`. **S**
- **Fix live-transcript truncation** — `await` in-flight mic/system tasks in `LiveTranscriber.flush()` before render; change batch-repair gate from `liveIsEmpty` to coverage-vs-duration. *Files:* `ScribeCore/Transcription/LiveTranscriber*`, pipeline controller. **M**
- **Wrap SQLite migrations in transactions** — `BEGIN/COMMIT/ROLLBACK` around `migrateToV2/V3` mirroring `rebuild()`. *File:* `People/SecondBrainDB.swift`. **S**
- **Fix `insertPerson()`** to bind `relationship_type` + `check_in_cadence` (v3 columns). *File:* `People/SecondBrainDB.swift`. **S**
- **Complete vault migration** — write back `relativeFolderPath`, emit `meetings/yyyy/yyyy-MM/slug`, gate completed-flag on full move success. *File:* `VaultMigrationManager`. **M**
- **Directory-traversal validation** — hoist `resolveInsideVault` into `VaultKit`, call on every app-side write (not just MCP), add malicious-path rejection test. *Files:* `VaultKit/VaultPaths.swift`, all write sites. **M**
- **Dup-encounter + stale-notification quartet** — `isSaving` guard on `QuickEncounterSheet`; fix remove-then-readd in `scheduleCheckIn`; move `scheduleBirthdayReminders` outside horizon guard; cancel notifications on `deletePerson`. *Files:* `ScribeCore/Notifications/*`, People views. **S**

#### 1B. Testability & CI (T2)
- **E2E pipeline harness** — headless XCTest driving `finalize` on a fixture WAV; assert transcript/summary/`meeting.json`/FTS5 land; variants for dropped-chunk repair, race, crash-recovery. **L**
- **CI gate** — `swift build` + `swift test` on every PR/push; parallel TSan job; coverage floor on pipeline files. (Per MEMORY: CI billing blocked → verify locally + make the workflow ready.) **S**
- **Services domain layer + DI seam** — protocol-front core services in `VaultKit`, inject via initializers; the only unit-test seam for recording. (Enabler for the harness.) **L**
- **CaptureKit extraction** — move the 25 duplicated Audio/Transcription/Detection/AI files into a shared target; protocol-abstract the 12 diverged ones. **M**

#### 1C. Observability & metrics (T2)
- **Funnel + activation event log** — local SQLite event log for record→stop→transcript→summary→action; waterfall view. **M**
- **Define & compute north-star "Capture rate"** (% of calendar meetings recorded AND usably summarized). **M**
- **Reliability dashboards** — cold-launch ms, transcription RTF, 30/90-day MeetingHealth aggregates, recovered-interrupted-recording crash counter. **S**

#### 1D. Monetization rails on (T7)
- **DECISION: choose the wedge** — commit to one positioning; embed in `MeetingScribeApp.swift` + `CLAUDE.md`. **S** *(blocks Phase 2 framing)*
- **Wire `ProPaywallView`** — add `.sheet(item: $FeatureGate.shared.paywallFeature)` in `MainWindow`; one line activates every `showPaywall()` call site. *Files:* `Monetization/FeatureGate.swift` (binding exists), `MainWindow`. **S**
- **Invert `FeatureGate.overrideAllEnabled`** true→false (it's `var overrideAllEnabled: Bool = true` today, line 55) behind `--dev-unlock` + DEBUG "simulate free/Pro" Settings toggle. **S**
- **LicenseManager** — Keychain + offline Ed25519 validation gating *features only* (never the vault). **M**
- **Free tier** (10 meetings/mo, People unlimited) + Settings Plan grid with Granola/Fathom/Lasting anchors. **S**
- **Provable-privacy panel** — Settings surface with live values ("0 bytes left this Mac", engine identity, vault path, audio retention) + consent-script helper + privacy line in MCP `serverInfo`. **S**

#### 1E. Onboarding first-win (T3)
- **First-run clarity bundle** — de-jargon ("vault"/"Ollama"→plain copy), one-liners on the 3 record buttons, 3-step how-it-works tour, honest empty/status copy. *Files:* `OnboardingSheet`, `SetupCheckSheet`, `MeetingCard`. **S**
- **"Setup Complete" celebration** before the setup check (what / 3 jobs / 30-sec nudge). **M**
- **Day-0 seed-3-people + first-summary confetti** — replace blank `TodayView` with 2-min "name 3 people + cadences", one-time confetti on first summary. **M**
- **Auto-populate People from attendees** — post-transcription banner "Found 3 attendees — add to People?", email as dedup key (`PersonExtractionController`). **S**
- **SetupCheck split** — Recording (required) vs Summaries (optional Ollama). **S**

#### 1F. Design-system quick wins (T4)
- **`RelationshipType.color`** computed property backed by NDS palette (replaces dead `colorName` stub; enum lives in `Sources/MeetingScribe/People/Person.swift` — verified; unblocks rings/health/People). **S**
- **Gate all motion through `NDS.motion()`** + Reduce Motion env, 3-speed hierarchy (only 5 sites use it today — verified). **S**
- **Migrate `ProPaywallView` to NDS tokens** (kill `.pink/.purple` leaks on the conversion screen). **S**
- **Button consolidation** — retire `Untitled*`, adopt `MS*` + `.minTap()` (44pt). **S**
- **`NDS.splitPaneTopInset`** applied consistently (fix `PeopleListView` `.padding(.top,60)` drift). **S**
- **Loading skeleton tri-state** — `LoadState` enum keyed on `loadedAt` + `.redacted(.placeholder)`, reduce-motion aware (stops "No summary" flashing as error). **M**

#### 1G. Recall/MCP foundations + native verb (T6/T8)
- **Finish RAG grounding** — extend retrieval across all entity kinds (not summary-only `prefix(1200)` top-5), ~8 token-budgeted passages, scope chips, inline citations, speaker attribution. *Files:* `Chat/ChatSession.swift`, `WorkspaceIndex.swift`. **M**
- **Modernize MCP to 2025-06-18 spec** — bump `protocolVersion` (`MeetingScribeMCP/main.swift:1844` still reports `2024-11-05` — verified), declare resources/prompts capabilities, add `title`+`outputSchema` to all tools. **M**
- **Fix coaching-framework coverage** — `tool_getCoachingContext` only handles partner(Gottman)/family(NVC); add real frameworks for friend/colleague/acquaintance. **S**
- **App Intents suite** — finish `QuickAddMeetingIntent` stub + add StartRecording / CaptureQuickNote / AddActionItem / AskMyVault / LogEncounter + AppEntities. **M**
- **Publish MeetingScribeMCP** to Glama / mcpservers.org / registry (gated on coverage fix). **S**

**P0 bug sweep (PM):** also fix Sparkle placeholder keys (no updates ship) and MCP `get_person` omitting birthday.

**Definition of done:** Daemon path gated; truncation + migration + SQLite + insertPerson fixed with the E2E harness green; funnel events recording; paywall presents on a gated action with `overrideAllEnabled=false`; a new user goes permissions→seed-3-people→first recording→summary→confetti with no "vault/Ollama" jargon; RAG answers cite sources; MCP reports 2025-06-18 and is published; the wedge decision is in `CLAUDE.md`.

---

### PHASE 2 — Navigation backbone, habit loop & native muscle

**Goal:** Every entity is one click away and navigable both directions; relationship maintenance is a 2-second daily habit; the app pushes value (briefs/notifications) and lives in native surfaces.

#### 2A. Navigation & IA backbone (T4)
- **Route Today cards into canonical detail** via `router.openMeeting()` (exists, `WorkspaceRouter.swift:123` — verified); delete ~50 LOC duplicate inline expand. *Files:* `TodayView.swift`, `WorkspaceRouter.swift`. **S**
- **Unify split panes** under one `NavigationSplitView` shell + `@SceneStorage` (Meetings native, People HSplitView, Tasks hand-rolled today). **M**
- **`EntityLink` open protocol** — one enum + `router.open(_:)` so every chip/row/label navigates (fixes dead attendee chips, "From meeting" labels, decision→person). **M**
- **`selectedPersonID` on router** — `openPerson()` already exists (`WorkspaceRouter.swift:130`) but `TodayView` has a *local* `openPerson` at line 628; unify all paths and delete the NotificationCenter jump. **M**
- **Recents rail + Cmd-K quick-switcher** — track last 5 `(section,entityID,timestamp)` in router. **M**
- **Global forward/back stack** (Cmd-[ / Cmd-]) + breadcrumb spine in `WorkspaceRouter`. **M**
- **Attendee chip hover card** with one-click "Add to People" (`PersonExtractionController`). **M**
- **Resurrect `ActionItemsViewModel`** as single source of task-list state (migrate 12 `@State`, `@AppStorage`-persist filter/viewMode/groupBy). **M**
- **Restore month-view** as Meetings list-mode toggle; delete orphaned `CalendarTabView` (~500 LOC dead). **M**

#### 2B. Relationship-coach habit loop (T5)
- **`RelationshipType` cadence extension** — `suggestedCheckInDays`, `lastCheckInAt`, typed cadence defaults; additive schema migration. *File:* `People/Person.swift`. **S** *(keystone — 22-auditor consensus)*
- **Chip-first encounter quick-log** on `PersonDetailView` — kind picker (call/coffee/dinner/quality-time/difficult-convo) + optional note/mood emoji, wiring VaultKit `Kind` (5 taps → 1). **M**
- **Auto-bump `lastInteractionAt`** from finalized-meeting attendees + recent messages (stop crying wolf). **M**
- **Calendar-aware drift** — derive last-interaction from calendar + recordings + messages (fix silent-ghosting). **M**
- **Check-in notifications + Today drift strip** — `RELATIONSHIP_CHECKIN` category, daily scheduler for partner/family/close-friend, snooze + quick-log deep-link; person #4 fires paywall. **M**
- **Relationship health score + ring** — recency+depth+streak (0–100) ring on partner/family profile, health-ordered Today strip. **M**
- **Inner-Circle Today strip** — partner/close-family/close-friends, status rings, overdue-first. **M**
- **`RelationshipHealth` widget** below identity panel (days-since-check-in dot, sentiment, "Log a moment"). **M**
- **Wire `RelationshipPromptLibrary`** into `PersonDetailView`, Pro-gated weekly card with blurred free teaser. **S**
- **Quiet 1:1 capture** — "Log a 1:1" sheet creating non-recorded meeting stub + person memory. **M**
- **Growth-theme threads** — dated trended `GrowthTheme` model as mini-timelines on person detail. **M**
- **Warm copy + photo hero avatar** — lowercase journal copy for partner/family; first photo as 52pt avatar with `RelationshipType.color` ring. **S**

#### 2C. Tasks & commitments (T6)
- **Directed commitment tracking** — add `direction` (iOwe/theyOwe/mutual) + `personID` to `ActionItem`; split Today into "I owe Priya" / "Priya owes me". **M**
- **Inline meeting→task creation** with persistent bidirectional link + "Tasks sourced from this meeting". **M**
- **Universal backlink index** — write-time `BacklinkIndex` actor + backlinks panel on every entity detail. **M**
- **Decision & Commitment Ledger (UI)** — wire `DecisionStore` scaffold (`Decisions/DecisionStore.swift` — verified) into extraction + nav tab + person backlinks (full MCP/atoms in Phase 3). **L**

#### 2D. Native platform muscle (T8)
- **Write action items to Apple Reminders** (`EKReminder` + deep-links) + "Schedule next" `EKEvent`, two-way status sync. **M**
- **Spotlight (CoreSpotlight)** — index meetings/people/action-items as `CSSearchableItem` with `meetingscribe://` deep-links. **M**
- **WidgetKit + Control Center** — real widget extension (Needs-Attention, due Action-Items) + Tahoe controls (Start Recording, Quick Note) firing the new App Intents. **L**
- **In-meeting hybrid scratchpad** — timestamped `TextEditor` in the dock/overlay; Ollama merges typed bullets with AI notes on finalize (the Granola mechanic). **M**
- **Mid-call "catch me up"** — one-tap Ollama recap over rolling chunks without stopping capture. **M**
- **Calendar-driven auto-record** (opt-in, armed mode) with pre-roll buffer. **M**
- **Proactive pre-meeting brief** — scheduled job N min before event, one-tap brief + `get_meeting_prep` MCP tool. **M**
- **Enrich meeting-start notification** with synthesized brief + Prep deep-link. **M**
- **Daily/weekly/morning ritual** — evening recap, Friday auto-filled weekly review, 8am morning brief, 7-day-absence welcome-back banner. **M**

#### 2E. Recording UX & reliability (T1/T8)
- **Live + post-recording status feedback** — reuse voice-note level meter ("Listening: Mic + System"), "transcribing on your Mac" toast. **M**
- **Atomic-write helper** for all canonical artifacts (`writeAtomicallyReplacing`). **S**
- **SQLite integrity check** — `PRAGMA quick_check` on open + auto-rebuild from `person.json`. **S**
- **Finalize write-ahead journal + resume on crash** — per-meeting `pipeline-state.json`, resume below-indexed-stage on launch. **M**
- **Surface speaker diarization** — transcript toggle + speaker-attributed action items. **M**
- **`@Observable` migration** — `MeetingManager`/`MeetingPipelineController`/`LiveTranscriber`; delete ~25 forwarding shims. **M**
- **`.starting/.stopping` transient `RecordingState`** claimed synchronously before first `await`. **S**

#### 2F. MCP read/synthesize + recall (T6)
- **`search_everything` / `semantic_search` MCP tool** wrapping `searchVaultHybrid` (FTS5 + embeddings) with deep-link citations. **M**
- **`get_backlinks` + `find_path` + `get_decisions` MCP tools** over `WorkspaceIndex`/`PeopleGraphViewModel`/`DecisionStore`. **M**
- **MCP resources** — `relationship://brief` (overdue people, birthdays 30d, tasks due, recent encounters) injected at session start. **M**
- **MCP write tools** — create/update action-item, `update_person`, `attach_note`, `log_encounter`, `get_relationship_health`, `list_drifting_contacts`. **M**

#### 2G. Security, retention & data layer (T1/T7/T8)
- **Encrypt Notion API key** — lift from `claude_desktop_config.json` plaintext into `KeychainStore`, migrate existing keys. **M**
- **Sign vault file commands** — HMAC-SHA256 on `_commands/` JSON with per-session Keychain key + replay protection. **M**
- **iMessage consent + audit log** — `imessage-access.log`, one-time onboarding consent, recent-access Settings view. **M**
- **Retention & right-to-forget** — audio-vs-transcript TTL + "Forget this meeting/person" purging folder, DB rows, FTS index, embeddings (fix orphaned vectors). **M**
- **`VaultFileStore`** — `NSFileCoordinator`-backed store conforming to `SecondBrainStore`; route app + MCP through it (kills MCP's 50 free-function disk readers). **L**
- **Typed versioned `ScribeBridge` IPC** — one Codable envelope in `VaultKit`; `liveDroppedChunks` crosses as a typed field. **M**
- **`PersonDetailView` decomposition** (2,356 LOC → identity/health/encounters/section-grid + coordinator). **L**

#### 2H. PM/engagement extras
- **Follow-up lifecycle tracking** — persist sent-status, surface unsent recaps in `NeedsAttentionWidget`, ~24h nudge. **M**
- **Per-report 1:1 prep digest** — extend `PreMeetingBriefView` with bio + growth themes + open directed commitments. **M**
- **Private vs shareable note visibility** gating MCP reads (lock icon in UI). **M**
- **Dynamic Type / accessibility round 2** — adaptive frames on the 5 fixed-size sheets + `.accessibilityHeading` traits; icon-button labels; color-dot glyphs. **M**
- **Drag-to-reorder affordance** (handle + preview + drop-zone accent) on Action Items list/board. **M**
- **Daily Note in-app journal** (`DailyNoteView` over `DailyNoteWriter`, free-write + managed block + "On this day"). **M**
- **`[[` wikilink / `@person` autocomplete** in `MarkdownEditor` (popover over `WorkspaceIndex`). **M**
- **Local A/B harness + bidirectional summary feedback**. **M**
- **iPhone Shortcuts vault capture** — 4 Siri Shortcuts writing JSON envelopes to `_inbox/` via `iCloudInboxWatcher`. **M**
- **Mobile review layout + `/whatsnew` sync-glance** dashboard. **M**

**Definition of done:** Today/People/Tasks share one nav shell with working Cmd-K, Recents, Cmd-[/]; any chip/attendee/decision navigates; logging an encounter is one tap and bumps health truthfully; check-in notifications fire and deep-link; action items mirror to Apple Reminders and Spotlight; the MCP server reads/searches/writes the vault and injects a session brief; Notion key is in Keychain; "Forget this meeting" purges everything; `PersonDetailView` is decomposed.

---

### PHASE 3 — The agentic brain & synthesis layer

**Goal:** The vault becomes a queryable knowledge graph that Claude (and the user) can reason over; meetings auto-produce structured, attributed atoms; zero-install on-device LLM.

- **"Ask your vault" RAG, fully realized** — NL Q&A over all transcripts with citations on the FTS5+embeddings+Ollama stack (uniquely 100% local). **L**
- **Decision & Commitment Ledger, full** — typed person-attributed atoms (Decisions, Commitments who→what→by-when, Open Questions) async post-finalize; per-person Commitments tab; graph edges. **L**
- **Upgrade extraction to LLM-backed attributed atoms** — replace `DecisionStore`'s "## Key Decisions" bullet-scrape with structured emission. **M**
- **Apple Foundation Models backend** — `LLMProvider` protocol + `FoundationModelsService` (Tahoe's free on-device LLM); default to it, Ollama as long-context fallback — removes the multi-GB install (the #1 onboarding cliff). **L**
- **Transitive graph MCP queries** — edge-following tools over `EntityGraphIndex`. **M**
- **Generalize the people-only graph** to first-class meeting/project/topic/decision `GraphNode` kinds, reusing the force layout. **M**
- **Conversation intelligence** — talk-time ratio, per-segment breakdown, `NLEmbedding` topic timeline (on-device). **M**
- **Unified review-then-execute fan-out card** after finalize — approve-then-execute checkboxes composing FollowUpGenerator + Linear/Notion + EventKit + People writes. **M**
- **Performance-review compilation** — one-click Markdown draft from 6 months of dated 1:1 points, commitments, growth deltas, shareable-only notes. **M**
- **Smart `@`-mention completions** in notes & tasks. **M**
- **Bulk link creation & multi-select batch toolbar**. **M**
- **Team view + org rollup** — typed manager/directReport relationships, "My Team" filter, pattern aggregator. **M**
- **Relationship-type-aware AI presets + fix hard-coded "Tyler" preamble** (pass real userName + type into LLM). **S** *(can pull earlier — privacy/correctness fix)*

**Definition of done:** A user (or Claude via MCP) asks "what did I commit to Priya and what's overdue?" and gets a cited, person-attributed answer; meetings auto-emit Decisions/Commitments/Open-Questions; Apple Foundation Models runs the summary with no Ollama installed; the graph view shows meetings/projects/decisions, not just people.

---

### PHASE 4 — Openness, scriptability & ecosystem

**Goal:** Cement the no-lock-in, "your data is yours" moat and make the vault a programmable substrate.

- **Vault Query API** — read-only `meetingscribe query --tag --since --format=json` CLI + per-tab "export filtered list" + JSON schema export. **L**
- **"Your vault IS an Obsidian vault" moat** — `ObsidianExporter` already writes native markdown; add "Open in Obsidian" onboarding step (starter `.obsidian` config + README) + opt-in two-way folder mirror. **M** *(positioning transformational; seed a lightweight one-way version in Phase 1 onboarding)*
- **Two-way EventKit/Reminders status-sync hardening** + iCloud propagation to iPhone/Watch. **M**
- **CI dependency-direction guard + diverging-pair detector** — VaultKit never imports AppKit/SwiftUI; services never import views; fail when an allowlisted CaptureKit pair diverges. **S** *(pull into Phase 1/2 if cheap)*

**Definition of done:** A power user scripts a report off the vault from the terminal; opening the vault folder in Obsidian "just works" with backlinks intact; CI blocks layering violations.

---

### PHASE 5 — Transformational bets

**Goal:** Category-defining capabilities only a local-first relationship-graph product can ship.

- **Always-on ambient capture** — the armed auto-record (Phase 2) graduates to trustworthy always-listening, *gated on* the Phase 2 retention/right-to-forget primitive and the write-ahead journal. **L**
- **Proactive relationship-coach agent** — MCP resources + write tools + health/drift tools so Claude *initiates* ("you haven't talked to your sister in 3 weeks; her birthday is in 9 days — draft a message?"). **L**
- **Cross-meeting commitment accountability engine** — the Ledger (Phase 3) becomes a standing dashboard nudging both sides of every mutual obligation across relationships and projects. **L**
- **Compliance-grade local positioning, productized** — formal "compliance mode" (audit log, retention enforcement, exportable proof-of-local) targeting legal/healthcare/finance who *cannot* use cloud notetakers — the durable wedge. **M**

**Definition of done:** The app can be left running all day with a credible privacy/retention story; Claude proactively surfaces relationship and commitment actions unprompted; there is a named buyer the product is unambiguously built for.

---

## 4. Top 10 do-first

| # | Title | Group | Impact | Effort | Phase |
|---|-------|-------|--------|--------|-------|
| 1 | Wire `ProPaywallView` to `MainWindow` (one `.sheet` binding) | PM | Transformational | S | 1 |
| 2 | DECISION: choose the core wedge (meeting vs coach) | PM | Transformational | S | 1 |
| 3 | Gate daemon recording behind disabled-by-default flag (orphan data loss) | Eng | High | S | 1 |
| 4 | Fix live-transcript truncation (`LiveTranscriber.flush` + repair gate) | Eng | High | M | 1 |
| 5 | E2E pipeline integration harness (golden-audio + Ollama) | Eng | High | L | 1 |
| 6 | Instrument funnel + activation events + "Capture rate" north star | PM | High | M | 1 |
| 7 | Invert `overrideAllEnabled` + DEBUG free/Pro QA toggle | PM | High | S | 1 |
| 8 | First-run clarity bundle (de-jargon + record-button labels + tour) | End-User | High | S | 1 |
| 9 | Finish RAG grounding across all entities + citations + speaker attribution | Competitive | High | M | 1 |
| 10 | `RelationshipType` cadence extension (`suggestedCheckInDays`, `lastCheckInAt`) | PM | High | S | 1→2 |

---

## 5. Risks, dependencies, sequencing & what to defer/kill

### Hard dependency chains (respect these)
- **Tests before refactors.** The E2E harness + Services/DI seam (1A/1B) must land *before* the big architectural moves (`CaptureKit`, `VaultFileStore`, `@Observable`, `PersonDetailView` split) — otherwise those refactors are unverifiable and reintroduce the very data-loss bugs Phase 1 fixes.
- **`RelationshipType` cadence extension (2B) gates the entire coach habit loop** — health score, drift notifications, Today strip, prompts all read its fields. Land it first in Phase 2 (additive migration).
- **MCP 2025-06-18 spec bump + coaching-coverage fix (1G) gate every other MCP bet** (resources, write tools, search_everything in Phase 2) and the registry publish. Do not publish before the coverage fix — the differentiator is *worse than baseline* for 5 of 7 relationship types today.
- **`EntityLink`/router unification (2A) gates** backlinks panel, decision→person links, and graph generalization (Phase 3).
- **Retention/right-to-forget (2G) gates always-on capture (5)** — never ship always-on without a forget primitive.
- **The wedge decision (1D) frames Phase 2's emphasis** — it decides whether the coach loop (2B) or the native meeting muscle (2D) leads.

### Risks
- **CI is billing-blocked** (per MEMORY) — the Phase 1 CI gate must run *locally* (pre-push hook / `make test`) so the coverage/TSan guard is real while GitHub Actions is red. Treat the local harness as the gate, not green-CI.
- **Architectural refactors are L-effort, high-blast-radius.** Stage `CaptureKit` and `VaultFileStore` behind the diverging-pair/dependency-direction CI guard (Phase 4, pull early) so drift can't silently recur mid-migration.
- **`overrideAllEnabled=false` exposes every half-wired gate at once.** Pair the flip with the DEBUG free/Pro toggle and a manual pass over all `showPaywall()` call sites in the same PR.
- **Apple Foundation Models (Phase 3)** is Tahoe-version-dependent and quality-variable for long context — ship behind `LLMProvider` with Ollama fallback; never the *only* backend.
- **Daemon path** stays disabled (1A) until the write-ahead journal + finalize (2E) land — do not re-enable for convenience.

### Defer
- **Team view / org rollup, performance-review compilation, bulk-link batch ops** (Phase 3) — high value but manager-persona-only; defer until the wedge confirms that persona is primary.
- **Two-way Obsidian folder mirror** (Phase 4) — ship one-way "open in Obsidian" first; bidirectional is a conflict-resolution rabbit hole.
- **Local A/B harness** (2H) — valuable, not user-facing; late Phase 2 / Phase 3.

### Kill / collapse
- **Orphaned `CalendarTabView`** (~500 LOC) — delete after wiring month-view as a Meetings toggle (2A).
- **The ~50 LOC duplicate Today inline-detail layer** — delete when routing through `WorkspaceRouter` (2A).
- **The never-wired XPC protocol vs file-command struct duplication** — collapse into the single typed `ScribeBridge` envelope (2G).
- **The 25 duplicated app/daemon files** (12 diverged) — collapse into `CaptureKit` (1B); never patch a bug in both copies.
- **MCP's 50 free-function disk readers** — collapse into `VaultFileStore` (2G).
- **The dead `colorName` stub** on `RelationshipType` — replace, don't keep alongside `.color` (1F).
- **`~/MeetingScribe` (old repo, same bundle id, unmerged work — per MEMORY)** — resolve/retire before any distribution; never ship two binaries under `com.tyleryannes.MeetingScribe`.

---

## 6. References

Per-group digests in `docs/audit-2026/`:
- `GROUP-DESIGN.md` → `GROUP-1-DESIGN-FINDINGS.md`
- `GROUP-PM.md` → `GROUP-2-PRODUCT-FINDINGS.md`
- `GROUP-ENGINEERING.md` → `GROUP-3-ENGINEERING-FINDINGS.md`
- `GROUP-END-USER.md` → `GROUP-4-PERSONA-FINDINGS.md`
- `GROUP-COMPETITIVE.md` → `GROUP-5-COMPETITIVE-FINDINGS.md`

A `v2` re-audit pass exists under `docs/audit-2026-v2/` (Design/Product/Engineering) — consult for deltas on the highest-churn areas (recording pipeline, nav backbone, monetization). Prior master plans (root `MASTER_PLAN*.md`, `docs/audit-2026/MASTER-PLAN.md`, `docs/audit4/`) were left intact; this document supersedes them.
