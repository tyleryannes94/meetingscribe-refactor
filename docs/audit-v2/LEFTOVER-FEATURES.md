# Leftover / Skipped Features — autonomous build pass (2026-06-16)

*Companion to [`UNCOMPLETED-FEATURES.md`](UNCOMPLETED-FEATURES.md). This records what the autonomous build pass shipped, what it corrected, and everything it deliberately left for later — with the reason for each. Items needing a human decision were skipped per instruction and collected here.*

## ✅ Built & merged this pass

| PR | Items |
|---|---|
| #195 | Wired the orphaned screens: Brief Me, Integrations hub, Contacts import, Ambient mic-detection settings, Symbol picker; deleted superseded `MeetingNotesPage`. |
| #197 (Wave 1) | **MCP `logEncounter` envelope-key fix** (stops silent encounter data loss); `QuickEncounterSheet` duplicate-save guard; encounters SQLite indexes; `RelationshipPromptLibrary` weekly prompt mounted; check-in reminders scheduled on launch; related-meetings strip rendered (5-A). |
| #198 (Wave 2) | `DecisionLedgerView` surfaced as a top-level nav destination (4-D reachability half). |
| #199 (Wave 3) | Today first-steps onboarding card (5-H); after-5pm end-of-day wrap-up card (5-I). |
| #201 (Wave 4) | **6-D MCP tools** (5 of 6): `list_open_decisions`, `search_decisions`, `list_waiting_on`, `get_voice_note_extracts`, `get_person_brief` — all disk-backed. |
| #202 (Wave 5) | **3-H pre-meeting brief push** — 15-min-before notification per upcoming meeting, deep-linking to the meeting/brief. |

## 🔧 Corrections to the audit (already built — verified during this pass)

The earlier cross-plan sweep over-flagged several items. Precise inspection found these **already implemented and reachable**, so they were not rebuilt:

- **Tasks subsystem** (audit/master-plan.md): 2-4 keyboard property shortcuts, 5-8 table column picker, 6-6 keyboard sidebar nav, TK-4 bulk actions (status/priority/project/due), 5-2 My Tasks sections — all present in `ActionItemsListView` / `ActionItemsTableView` / `ActionItemsSidebar` / `ActionItemsMyTasks`.
- **C1-3** transcript↔audio tap-to-seek — already wired (`MeetingTranscriptTab` passes the `AudioPlayerController` to `TranscriptSyncView`).

> These should be marked DONE in the next revision of `UNCOMPLETED-FEATURES.md`.

---

## ⏭️ Skipped — needs your input / a product decision

| Item | Why skipped |
|---|---|
| **Monetization & StoreKit billing** (audit-2026 / V4 P3) | Revenue model is a business decision — paywall presentation, pricing, lifetime-vs-subscription, and real StoreKit 2 wiring all need your call. The layer is currently inert (paywall never presented, `FeatureGate` never enforced). |
| **Sparkle release signing** (held #3) | Needs the `SPARKLE_PRIVATE_KEY` secret + `SUFeedURL` repoint — can't be done without your credentials. |
| **Copy-voice de-jargon** (D4-6 / held #6) | "Vault/Ollama/MCP" → plain words is a brand-voice decision; needs your word-map direction. |
| **Per-type AI analysis presets** (P3-2) | Which presets show (or how the prompt preamble changes) per relationship type is a UX judgment call I didn't want to guess. |
| **Vault encryption at rest** (V4 E4-5) | Threat-model + key-management design decision (where keys live, sensitive-meeting mode UX). |
| **On-device Recall timeline** (V4 C4-2) | New always-on-capture category with consent/jurisdiction implications — explicitly "build responsibly or skip." |
| **iPhone Shortcuts** (REMAINING_WORK) | The 4 Shortcuts must be authored in the iOS Shortcuts app, not in this repo; the receiving `iCloudInboxWatcher` already exists. |

---

## ⏳ Skipped — buildable next, but more than a quick win (deferred for scope/risk)

Each is real and self-contained but needs a non-trivial change (a new AI pass, an async refactor, a core-enum expansion, or message-model plumbing) rather than a wiring tweak. Listed with the specific blocker so they can be picked up cleanly:

| Item | Blocker |
|---|---|
| **3-D Voice-note auto-extract** | `QuickNotesController` has no `ActionItemStore` reference and there's no extraction prompt for voice notes — needs store injection + a new Ollama extraction pass + parse, not just a call. |
| **2-E iMessage signal in relationship health** | `PersonContextBuilder.build()` is synchronous; pulling iMessage themes needs an async path (`MessagesAnalyzer.conversationSummary` is an async Ollama call) plus Full-Disk-Access handling. |
| **1-D Share `PersonContextBuilder`** across surfaces | Mechanical but touches 5 call sites (chat, PreMeetingBrief, WeeklyRecap, MCP, GlobalSearch) with regression risk; wants its own focused PR. |
| **Per-tag summary templates** | `OllamaService.buildPrompt` is a static func with no tag access; needs a tag→template map threaded through `summarize()`. |
| **5-B Cross-entity ⌘K (decisions/encounters)** | `WorkspaceEntityKind` has no `.decision`/`.encounter` cases; adding them expands a core enum across many switches + needs open/deeplink handlers. The mapper already drops these kinds today. |
| **4-E Chat citations + 5-G write-back undo** | `ContentBlock.toolResult` has no source field and there's no undo/rollback path — a hardcoded "Sources" disclosure would be misleading, so this needs real retrieval-source plumbing first. |
| **6-D MCP `scheduleFollowUp`** | The other 5 tools shipped (#201). This last one needs EventKit write access inside the MCP process (uncertain perms) — deferred. |
| **3-B 7:50am brief pre-warm** | 3-H (the push) shipped (#202). The 7:50 pre-warm still needs a background timer that pre-generates briefs into BriefCache. |
| **Check-in `LOG_NOW` deep-link handler** | Routing the check-in notification to a person needs a `meetingscribe://person/<id>` URL-scheme route, which doesn't exist yet — a scheme expansion, not a wiring tweak. |
| **5-F Capability discovery on Today / 5-E inline AI insight cards** | 5-F: Today has no chat rail to host it. 5-E: a new Ollama-generating per-entity card (not a reuse of the list-level insight views). |
| **4-D topic clustering** | Nav is now done; k-means over decision embeddings remains. |
| **4-H Quarterly recap** | Extend `WeeklyRecap` to quarterly scope + Notion export. |
| **6-A Notion pull-back / 6-B Linear context menu / 6-E integration status dashboard** | Integration depth — each a contained PR. |

---

## 🏗️ Skipped — large / architectural (not autonomous-build-sized)

- **UX-V6 premium overhaul** (audit-2026-06b, ~75 items): type-ramp sweep (~435 sites), native chrome/materials, elevation/radius/surface token sweeps, `PendingRoute` nav mailbox, tabbed Settings, command-palette upgrade, people-in-meetings/tasks surfaces, profile "Story" timeline. This is a design-led workstream; the 3 blockers (D2-1 type ramp, C3-3 native chrome, D1-3 PendingRoute) gate the rest.
- **Architecture (V5/V4):** `EntityGraphIndex`, `MSList`, `WorkspaceSplit`, side-peek overlay, `VaultFileStore` (the root cause of the MCP envelope class of bug), CaptureKit extraction / two-binary daemon ownership, `MeetingManager` actor split (P0-D), ANN vector index (4-I).
- **Relationship-coach completion:** health-score arc-ring UI, guided first-person add cards, check-in `LOG_NOW` deep-link handler (launch scheduling is done; the tap-through routing remains).

---

## Held items (from `docs/audit-2026-06/HELD-ITEMS.md`)
Unchanged — all 7 still await the conditions noted there (test recordings, secrets, security review, brand-voice direction). See that file.
