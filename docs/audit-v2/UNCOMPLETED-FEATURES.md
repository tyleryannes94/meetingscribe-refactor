# MeetingScribe — Uncompleted Features (all audits)

*Generated 2026-06-16. **Part 1** verifies the [`audit-v2/master-plan.md`](../../audit-v2/master-plan.md) 60-item registry. **Part 2** sweeps every other improvement plan in the repo (root master plans V1–V3, audit-2026 relationship-coach, V4, V5, UX-V6, audit4, improvement-audit, REMAINING_WORK) for net-new items not in audit-v2. Every item was verified against the current `main` for **both implementation and reachability** — a feature that exists in code but is never rendered/scheduled/registered counts as not done (the "Brief Me" trap: the button existed but lived in an orphaned view).*

> **Read Part 2 first if triaging severity** — it contains a confirmed data-loss bug and an inert monetization layer that Part 1 (a single subsystem) does not cover.

## Status legend

- **DONE_WIRED** — implemented and actually reachable/active.
- **PARTIAL** — core exists but a specified sub-capability is missing.
- **ORPHANED** — code exists but is not wired into UI / nav / pipeline (highest-value quick wins — like Brief Me was).
- **MISSING** — not implemented.

# Part 1 — Audit-v2 registry (60 items)

## Scoreboard

| Status | Count | Items |
|---|---|---|
| ✅ DONE_WIRED | 33 | P0-A/B/C/E · 1-A/C/E/F/G/H/I · 2-A/B/C/F/G/H/I/J · 3-A/C/E/F · 4-A/C/F/G · 5-C/D/J/K · 6-C/F |
| 🟡 PARTIAL | 16 | P0-D/F · 1-B/D · 2-D/E · 3-B · 4-B/I · 5-A/B/F/G · 6-A/B/E |
| 🟠 ORPHANED | 4 | 3-D · 4-D · 5-E · 6-D |
| 🔴 MISSING | 7 | 3-G/H · 4-E/H · 5-H/I · 6-G |

**27 of 60 items are not fully complete.** Recently wired separately (outside this registry): Integrations hub, Contacts import, Ambient mic detection, Symbol picker — see PR #195.

---

## 🔴 MISSING — not implemented (7)

| ID | Feature | What's needed | Evidence |
|---|---|---|---|
| **3-G** | Global capture bar (⌘⇧Space) | A ⌥⌘Space task-only quick-entry panel exists, but not the spec'd ⌘⇧Space bar with **voice-note + encounter** capture. | `UI/QuickEntryWindow.swift`; `Settings.swift` (hotkey defaults to ⌥⌘Space, text-only) |
| **3-H** | Proactive pre-meeting brief push | No "15 min before event" notification deep-linking to `PreMeetingBriefView`. Brief only opens on manual navigation. | `Notifications/NotificationManager.swift`; `PreMeetingBriefView.swift` (on-demand only) |
| **4-E** | Cited answer UX in chat | No "Sources" disclosure in `ChatBubble`; retrieval evidence is never surfaced, so answers are unverifiable. | `ChatPanel.swift:164-228` (no sources block) |
| **4-H** | Quarterly recap generator | Only `WeeklyRecap` (7-day markdown) exists; no quarterly scope, no Notion export of either. | `WeeklyRecap.swift:1-46`; no `QuarterlyRecap` found |
| **5-H** | First Steps card + onboarding follow-up | One-time `OnboardingSheet` modal exists, but no dismissible First Steps card on Today blank state and no "First Meeting Ready" notification. | `OnboardingSheet.swift`; `TodayView.swift` (no blank-state card) |
| **5-I** | End-of-day wrap-up card | No after-5pm logic on Today; no `EndOfDayCard`/`WrapUpCard`. | `TodayView.swift` (fixed sections, no time-conditional) |
| **6-G** | Claude Projects sync | Does not exist anywhere. | grep `Claude.*Project` → 0 hits in Sources |

---

## 🟠 ORPHANED — built but unreachable (4) — *best ROI: wiring only*

| ID | Feature | What's missing to make it live | Evidence |
|---|---|---|---|
| **3-D** | Voice-note auto-extract pipeline | `generatePrompt()` exists but is on-demand; after the polish pass nothing auto-extracts action items / persons / decisions. Needs to fire automatically post-polish. | `QuickNotes/QuickNotesController.swift:155, 220-235` |
| **4-D** | Topic-clustered decision ledger view | `DecisionLedgerView` is fully built but only opens as a **sheet** from Today; it's not a top-level nav destination, and it groups by month rather than topic-clustering decision embeddings. | `DecisionLedgerView.swift:1-122`; `TodayView.swift:697`; `TopLevelSection` has no `.decisions` |
| **5-E** | Inline AI insight cards on entity detail | `PeopleInsightsView`/`TaskInsightsView` exist but are mounted in **list** views, not pinned to `PersonDetailView`/`UnifiedMeetingDetail` headers. `InsightEngine` publishes events these views don't consume. | `PeopleInsightsView.swift`, `TaskInsightsView.swift`, `InsightEngine.swift` |
| **6-D** | MCP tool surface expansion | Only **2 of 8** planned tools registered (`get_relationship_health`, `list_encounters`). Missing: `getPersonBrief`, `searchDecisions`, `listWaitingOn`, `listOpenDecisions`, `getVoiceNoteExtracts`, `scheduleFollowUp` — most of the backing logic already exists in the app. | `MeetingScribeMCP/main.swift:652-985` |

---

## 🟡 PARTIAL — core present, sub-capability missing (16)

| ID | Feature | Gap | Evidence |
|---|---|---|---|
| **P0-D** | MeetingManager actor split | Never split into `TranscriptionEngine`/`MeetingLibraryService`; still a 1,339-line monolith (sub-controllers were extracted, core actor not). | `MeetingManager.swift:23` |
| **P0-F** | SQLite join tables | Tables created & writes wired, but the **read/query methods are never called**; `encounter_tasks` table missing; `Person.linkedProjectIDs` never added. | `People/SecondBrainDB.swift:204-220, 332-343` |
| **1-B** | Index decisions + encounters | Decisions backfill exists; **encounters have no dedicated store/backfill** (indexed only via `PeopleStore.addEncounter`). | `DecisionStore.swift:163-198`; `PeopleStore.swift` |
| **1-D** | PersonContextBuilder canonical service | Built, but only `PersonBriefSheet` calls it. The planned shared callers (chat, PreMeetingBrief, WeeklyRecap, MCP, GlobalSearch) still assemble context ad-hoc. | `People/PersonContextBuilder.swift:78-122` |
| **2-D** | One-tap actions on board cards | "Log check-in" + "AI conversation starter" wired; **"Remind me in 3 days" missing** (2 of 3). | `UI/KeepInTouchBoard.swift:161-203` |
| **2-E** | Multi-signal relationship health | Meeting-mention signal integrated; **iMessage signal stubbed** (`recentIMessageThemes = nil`, "until Phase 2 iMessage wiring lands"). | `PersonContextBuilder.swift:116`; `PeopleStore.swift:1275-1279` |
| **3-B** | Enriched daily-brief notification | Live body + "View Standup" deep link done; **no 7:50am pre-warm** (counts refresh only on launch/foreground). | `NotificationManager.swift:239-258` |
| **4-B** | Semantic Connections panel | Related-meetings panel exists **only in the Notes tab**, not a unified "Connections" panel; `PersonDetailView` has none; no `DecisionDetailView`. | `UnifiedMeetingDetail.swift:62-64`; `MeetingNotesTab.swift:161-219` |
| **4-I** | ANN vector index | Still a full-table scan in `allEmbeddings()` (in-memory cache only); no HNSW/ANN approximation. | `SecondBrainDB.swift:622-640` |
| **5-A** | Relational context strip | Vertical co-attendee list, not the spec'd **horizontal strip**; in `UnifiedMeetingDetail`, `relatedMeetings` loads but is **never rendered** (orphaned data fetch). | `PersonDetailView.swift:1792-1840`; `UnifiedMeetingDetail.swift:64, 392` |
| **5-B** | ⌘K cross-entity recency | Surfaces recent **people only**; missing recent decisions, tasks, encounters. | `GlobalSearchView.swift:368-388` |
| **5-F** | Capability discovery panel | Works in the meeting chat tab, but Today has no chat rail / collapsible "What can I ask?" section. | `ChatPanel.swift:72-93`; `MeetingChatTab.swift:13-18` |
| **5-G** | Tool-use narration + write-back cards | Human-readable tool names shown; **no Undo affordance** for write operations. | `ChatPanel.swift:197-225` |
| **6-A** | Notion bidirectional sync | Push + **manual** pull only; status changes in Notion are not auto-pulled back into `ActionItemStore`. | `NotionActionItemService.swift:45-80`; `TaskSyncService.swift:416-454` |
| **6-B** | Linear context menu | "Push to Linear" exists as an **icon button**, not the spec'd right-click context menu on task rows. | `ActionItemsChrome.swift:662-684`; `TaskRowView.swift:397-405` |
| **6-E** | Integration status dashboard | Webhook history shown in "Automation" tab; **no unified status panel** for Notion/Linear/Calendar/iMessage/MCP. | `WebhookSettingsView.swift`; `SettingsView.swift:95-96` |

---

## Suggested sequencing

1. **Orphaned first** (wiring-only, highest ROI): 6-D (register 6 MCP tools), 4-D (add `.decisions` nav destination), 5-E (mount insight cards in detail headers), 3-D (auto-run voice-note extraction). Plus the orphaned data-fetch inside 5-A (render the already-loaded `relatedMeetings`).
2. **High-impact missing**: 4-E (cited sources in chat), 3-H (pre-meeting brief push), 5-H/5-I (onboarding + end-of-day cards).
3. **Partial completions**: 2-E + 1-D (iMessage signal + share PersonContextBuilder), 6-A (Notion pull-back), 2-D/3-B/5-B/5-F/5-G polish.
4. **Heavier infra** (lower urgency): P0-D (actor split), P0-F (join-table reads + `encounter_tasks`), 4-I (ANN index), 4-H/6-G (quarterly recap, Claude Projects sync).

---

# Part 2 — Cross-plan findings (other audit generations)

*Net-new items from every other plan in the repo, deduped against Part 1. Verified against current `main`. Items already in Part 1 are not repeated.*

## ⚠️ Severity-1 — fix regardless of roadmap

| Issue | Status | Evidence |
|---|---|---|
| **MCP `logEncounter` writes wrong envelope key** — writes `["version": 1, …]` but `SchemaEnvelope` expects `schemaVersion`, so every encounter logged via MCP/Claude **silently fails to decode** app-side (data loss). | 🔴 BROKEN | `Sources/MeetingScribeMCP/main.swift:1665` vs `Sources/VaultKit/SchemaEnvelope.swift:17`; app decode `PeopleStore.swift:435-437` |
| **Monetization layer inert** — `ProPaywallView` is never presented (no `.sheet` binding anywhere), `FeatureGate.isEnabled()` has zero non-Monetization callers, `overrideAllEnabled = true` in DEBUG, `StoreKitManager.purchase()` is a "Coming soon" alert, `isPro` read from `UserDefaults` (bypassable). Revenue cannot ship. | 🟠 ORPHANED + 🔴 MISSING billing | `Monetization/ProPaywallView.swift`, `FeatureGate.swift:64`, `StoreKitManager.swift:74` |
| **`QuickEncounterSheet` duplicate-save** — `saveIfValid()` fires from both `onSubmit` and `.keyboardShortcut(.return)` with no `isSaving` guard → Return creates two encounter records. | 🟡 PARTIAL | `QuickEncounterSheet.swift` |

## Resolved during this session
- **UX-V6 D1-4** ("collapse the second meeting surface in Tasks") — resolved by deleting the orphaned `MeetingNotesPage` (PR #195).

## A. Tasks subsystem — `audit/master-plan.md` (orthogonal to audit-v2)

| ID | Feature | Status | Evidence |
|---|---|---|---|
| 2-4 | Keyboard property shortcuts (`p`/`d`/`e`/`m` in list) | 🔴 MISSING | `ActionItemsListView` has no such handlers |
| 2-5 | Type-ahead date picker (inline "tod"/"+3d") | 🔴 MISSING | parser in `TaskQuickAddParser`, UI still `.graphical` |
| 6-7 | NavigationSplitView migration for Tasks | 🔴 MISSING | `ActionItemsView.swift:179` "NOT a NavigationSplitView" |
| 5-8 | Table view column picker + custom props | 🔴 MISSING | `ActionItemsTableView.swift:183`; no picker |
| 6-2 | Calendar drag-to-reschedule + spans | 🔴 MISSING | no calendar-drag impl |
| 6-4 | Write-ahead `.bak` backup before save | 🔴 MISSING | plain `write()` calls |
| 6-6 | Keyboard sidebar nav (⌘1, arrows, Return) | 🔴 MISSING | sidebar is custom `VStack`, not `List` |
| 3-1 | ⌘K Tasks-scoped jump palette | 🟠 ORPHANED | `TasksJumpPalette.swift` skeletal, partly wired |
| 5-2 | My Tasks personal sections (Today/Upcoming/Later) | 🟡 PARTIAL | rail item + `ActionItemsMyTasks.swift` partial |
| 5-5 | Extended GroupBy (owner/label/project/initiative) | 🟡 PARTIAL | `TaskQuery.GroupBy` enum, not all modes in UI |
| TK-4 | Bulk actions beyond delete (status/priority) | 🟡 PARTIAL | `taskSelectMode`+`bulkDeleteTasks()` only |
| A0-1/A0-3 | ViewModel migration + TasksEnvironment (kill prop-drilling) | 🟡 PARTIAL | enums defined twice; 3-binding forwarding remains |

## B. Relationship-coach + monetization — `docs/audit-2026/MASTER-PLAN.md`

| Item | Status | Evidence |
|---|---|---|
| `RelationshipPromptLibrary` (28 Gottman/NVC prompts) | 🟠 ORPHANED | `weeklyPrompt()`/`rotatingPrompt()` have zero callers |
| Check-in notifications | 🟠 ORPHANED | `syncPersonReminders()` only called from `QuickEncounterSheet.swift:97`, never on launch; `LOG_NOW` action never handled in `NotificationManager.swift:338-362` |
| Per-type AI analysis presets | 🟠 ORPHANED | `ConversationAnalysisPreset` never branches on `relationshipType` |
| Health-score arc-ring UI | 🔴 MISSING | no `Person+ConnectionStrength`, no arc view; paywall promises it |
| StoreKit 2 billing / `Transaction.updates` | 🔴 MISSING | `StoreKitManager.swift:74` stub |
| Encounters SQLite indexes (`idx_encounters_*`) | 🔴 MISSING | no index creation in `SecondBrainDB` migration |
| Guided first-person add (tap-target cards) | 🟡 PARTIAL | `AddPersonSheet.swift` plain Picker |

## C. UX-V6 premium overhaul — `docs/audit-2026-06b/MASTER-PLAN-UX.md` (largest pending workstream: ~75 of 172 items)

*A "clean and expensive" visual/UX rehaul the Phase 1–6 waves did not address. Highest-leverage / blocking items below; full enumeration lives in the source plan.*

**Blocking (unlock downstream polish):**
- **D2-1** Modular type ramp + lint — ~435 raw `.font(.headline/.caption)` sites vs 6 NDS tokens. 🔴 MISSING
- **C3-3 / D2-4** Native chrome & materials (translucent sidebar, glass) — sidebar is a flat opaque rect. 🔴 MISSING
- **D1-3** `PendingRoute` mailbox — nav uses NotificationCenter + `asyncAfter(0.05)` race; blocks deterministic deep-links (Spotlight/widgets/MCP). 🔴 MISSING

**Orphaned (built, unwired):**
- **C1-3** Transcript↔audio tap-to-seek — `TranscriptSyncView` fully built; `MeetingTranscriptTab.swift:42` never passes the audio controller. 🟠 ORPHANED

**Other high-value:** D5-6 tabbed Settings (23-section scroll → tabs) MISSING · U4-10 paywall copy leaks dev debug text MISSING · D1-1 live nav-rail badges MISSING · D1-8/D1-9/P3-2 unify search + desktop/web IA MISSING · D2-2/D2-3/D2-9 elevation/radius/surface token sweeps MISSING · D4-1/D4-2 error + empty-state systems MISSING · D3-3 real ⌘Z undo MISSING · D3-2 one-click complete + celebration MISSING · P1-9/P1-11/P1-12 people-in-meeting surfaces MISSING · P2-2/P2-3/P2-8/P2-9 people-in-tasks (owner chips, `@person` tokens) MISSING · C2-1 unified profile "Story" timeline MISSING · C3-6/U3-1 premium menu-bar next-meeting card PARTIAL · D2-6/D5-1 Today editorial hierarchy PARTIAL.

## D. V5 architecture/UX — `docs/audit-2026-05b/MASTER_PLAN_V5_UX_Performance.md`

| Item | Status | Evidence |
|---|---|---|
| `EntityGraphIndex` (write-time reverse index, kill O(n) joins) | 🔴 MISSING | no such type; related to Part-1 P0-F (partial) |
| `WorkspaceSplit` unified pane primitive | 🔴 MISSING | 4 hand-rolled split systems |
| `MSList` shared keyboard-navigable list | 🔴 MISSING | lists are mouse-only `ScrollView+Button` |
| Side-peek overlay (open link without losing place) | 🔴 MISSING | all links are navigating jumps |
| Meeting outline / jump-to-moment | 🔴 MISSING | no outline rail / in-transcript find |
| Enhanced Notes merged canvas (Notes/Transcript/Summary) | 🟡 PARTIAL | `UnifiedMeetingDetail.swift:471` still 4 tabs |
| Hover-preview on backlinks/chips | 🔴 MISSING | depends on side-peek |
| `VaultEventBus` (coalesced, surgical cache invalidation) | 🟡 PARTIAL | Part-1 P0-B `SecondBrainEventBus` exists but MCP `vaultChanged` has no observer → MCP/Shortcut edits invisible until relaunch |

## E. V4 hardening + strategic — `docs/audit-2026-05/MASTER_PLAN_V4.md`

| Item | Status | Evidence |
|---|---|---|
| `VaultFileStore` unified domain layer (one write path app+MCP) | 🔴 MISSING | app and MCP have separate write logic (root cause of the §Severity-1 envelope bug) |
| Vault encryption at rest + sensitive-meeting mode | 🔴 MISSING | SQLite is plaintext |
| `LicenseManager` (signed offline license) | 🔴 MISSING | only StoreKit stub |
| On-device Recall timeline (consent-first always-on) | 🔴 MISSING | new category; default-off — build responsibly or skip |

## F. Cross-cutting orphans & infra — `docs/improvement-audit/*`, `docs/REMAINING_WORK.md`

| Item | Status | Evidence |
|---|---|---|
| Cross-entity `searchAll()` not wired into ⌘K | 🟠 ORPHANED | `SecondBrainDB.searchAll()` (BM25, all kinds) exists; `GlobalSearchView` uses `WorkspaceIndex` (no people) instead |
| Speaker diarization | 🟠 ORPHANED | `DiarizedTranscript.parse()` never called; `--diarize` flag passed but output unused |
| Per-tag summary templates (1:1 vs all-hands) | 🔴 MISSING | single hardcoded prompt in `MeetingPipelineController.summarize()` |
| Weekly relationship-intelligence digest | 🔴 MISSING | live overdue list exists; no weekly digest/notification |
| CaptureKit extraction (retire app↔daemon dup, ~12–25 diverged files) | 🔴 MISSING | no `CaptureKit` target; baseline at `scripts/capturekit-dup-baseline.txt` |
| Two-binary daemon ownership of capture | 🟡 PARTIAL | `ScribeCore` IPC scaffolded; `MeetingManager` still owns `AudioRecorder`/`LiveTranscriber` |
| iPhone Shortcuts (4 exported, Siri phrases) | 🔴 MISSING | `iCloudInboxWatcher` receives drops; Shortcuts not authored |

## G. Held items — `docs/audit-2026-06/HELD-ITEMS.md` (deliberately deferred, need a human decision)

1. Live-transcript truncation fix (needs a real test recording).
2. E2E pipeline harness + DI + CaptureKit extraction (high blast radius — land tests first).
3. Sparkle release signing + `SUFeedURL` repoint (needs `SPARKLE_PRIVATE_KEY` secret).
4. `LicenseManager` (Ed25519/Keychain) — security-sensitive.
5. Directory-traversal `resolveInsideVault` hardening (needs malicious-path test).
6. Onboarding de-jargon / copy voice ("vault" → ?) — needs a brand-voice decision.
7. Phase 3/5 big bets (Apple Foundation Models, ambient capture, full Decision Ledger) — sequence after Phase 2.

## Obsolete / superseded plans (excluded — no live items)
- `MASTER_PLAN.md` / `MASTER_PLAN_V2.md` / `MASTER_PLAN_V3.md` and `AUDIT_REPORT_2026-05-30.md` — folded into later audits; V4 Phase 0–5 shipped (PRs #13–#25).
- `UX_QUICKWINS_PLAN.md` / `SESSION_IMPROVEMENTS_2026-05-31.md` — mostly shipped or absorbed into V5/UX-V6 (residuals: quick-add bar, tag merge UI, inline-edit-everywhere — all PARTIAL/MISSING, low priority).
- `docs/audit4/` raw findings — deduped into the master plans above; `TYLER_TODO.md` is an execution runbook, not a feature tracker.
