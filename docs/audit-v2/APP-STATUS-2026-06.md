# MeetingScribe — App Status (2026-06)

*Generated 2026-06-17 by a two-agent audit of every improvement plan in the repo, verified against the current `main` (which includes ~27 PRs merged this cycle, #195–#227). Lists what's genuinely **not built** — items already shipped are excluded. Some older audits flag already-built items as missing; those corrections are noted.*

## Executive summary

| Layer | Built | Reality |
|---|---|---|
| **Intelligence / People** | ~80% | The recent waves landed it: relationship health (incl. iMessage signal), person insights, Story timeline, mood, decision clustering, brief/digest/check-in notifications, MCP tools, capability discovery. |
| **UX-V6 polish** | ~81% | Tokens (elevation/radius/motion/recording), MSErrorState, MSEmptyState, MSSkeleton, MSFilterChip, ndsHover, semantic rows, fit fixes, command-palette, guided-add — mostly done. |
| **Audit-v2 registry** | ~57/60 | Nearly complete. |
| **Tasks subsystem** | ~70% | ViewModel/route/context/today done; O(1) index, table view, multi-select, initiative roll-up pending. |
| **V5 performance / infra / shell** | ~5–30% | **The hard architectural layer is largely not started** — EntityGraphIndex, VaultEventBus, CaptureKit extraction, MSList, NavigationSplitView, off-main persistence. |

**One-line:** the *features* are in good shape; the remaining work is **architecture/performance** (V5 infra), a tail of **UX polish**, and **decision-gated** items (monetization, copy-voice, Sparkle).

> **Excluded (built this cycle):** Brief Me + orphaned-view wiring, voice-note auto-extract, per-tag summary templates, the iMessage trio (ask-about-texts, structured insights, health signal), capability discovery, decision clustering + ledger nav + decisions-in-⌘K, relationship-coach polish (prompts, check-in-on-launch, insight card, health ring, guided cards, weekly digest, Remind-me/Nudge), MCP disk tools, pre-meeting push, Today first-steps/end-of-day cards, Story timeline (C2-1), mood-as-field (C2-6), waiting-on nudge (P2-6), recording color (D2-7), palette icon fix (D2-8), adaptive sheets, person-profile fit fixes, two Ask-AI bug fixes. Also already built (older audits mis-flag these): turnaround card, day-shape strip, 1:1 day rail, `Encounter.taskIDs`, `MeetingMentionRecord`, per-person in-meeting capture (P1-12), transcript↔audio sync (C1-3), calendar write-back (6-C), MeetingNotesPage deletion (D1-4), PersonResolver (P1-1), MSEmptyState/MSErrorState.

---

## 🔴 Critical architecture path (V5 — the highest-leverage remaining work)

These are unbuilt, large, and block downstream features/velocity:

| Item | What | Why it matters | Size |
|---|---|---|---|
| **SP-2 VaultEventBus** | Typed, coalesced cross-store event bus | MCP/Shortcut edits are invisible until relaunch (`vaultChanged` unobserved); blocks live propagation | M |
| **SD-3 EntityGraphIndex** | Write-time `person → meetings/tasks/decisions` reverse index | Person joins are O(n); "everything about X" is slow/impossible at scale | M |
| **ARCH-1 CaptureKit extraction** | Shared library for ~22 byte-identical audio/transcription/detection files duped between `MeetingScribe/` and `ScribeCore/` | Blocks the two-binary daemon split; `scripts/capturekit-dup-baseline.txt` tracks the dupes | L |
| **Two-binary daemon activation** | Move audio ownership + MenuBar to the `ScribeCore` daemon; signed embed; XPC | Scaffolded, not activated (~10–15 days) | L |
| **SC-1 MSList** | Reusable `List(selection:)` primitive w/ keyboard nav | Meetings/Tasks lists are mouse-only today | M |
| **CM-1 NavigationSplitView** | Replace Tasks' manual HStack+drag split (`ActionItemsView.swift:179`) | Native shell consistency | L |
| **Off-main persistence** | Debounced, off-`@MainActor` writes (every edit re-encodes full DB today) | UI hitches on bulk edits | M |
| **MeetingManager actor split (P0-D)** | `TranscriptionEngine` + `MeetingLibraryService` | Render-thrashing | M |
| **4-I / ANN index** | Replace `allEmbeddings()` O(n) scan with ANN/HNSW | AI latency at scale | L |

---

## 🟡 Feature gaps (not started / partial — buildable)

**People / meetings:** 4-B semantic Connections panel · 2-G relationship summary in PreMeetingBrief · 5-A relational context strip (partial — related-meetings render, no full strip) · P1-3 speaker→person mapping (diarization parsed-but-unsurfaced) · D1-6 series spine prev/next (seriesID + SeriesHubView exist; nav missing) · U1-6 commitment carry-forward on series · C2-2 keep-in-touch kanban mode (board exists; no kanban) · 2-H trajectory sparkline · P1-5 shared-history strip · P1-7 face piles on meeting rows · U3-5 external/internal attendee awareness.

**Search / keyboard:** U2-10 search qualifiers (`with:@x before:may`) · C1-7 in-transcript find · D3-3 universal ⌘Z (NSUndoManager) · D3-8 unified j/k + "?" overlay (Tasks shortcuts sheet exists; global trigger missing) · DN-1 global back/forward spine.

**Tasks:** table view + column picker · multi-select + bulk-action bar · initiative roll-up · extended GroupBy · calendar drag-to-reschedule · A0-4 O(1) ID index.

**Integrations (note: user asked to skip integrations/MCP earlier):** 6-A Notion bidirectional sync · 6-B Linear context menu.

**Coach model fields:** Encounter.quality chips · Person.loveLanguage / attachmentStyle · per-person suppress-reconnect flag · type-specific PersonRow glyph/color · progressive prompt unlocks.

**Infra refactors (non-blocking):** PersonDetailViewModel extraction · EncounterStore split · MSSearchField/MSTagPicker unification · crash capture + memory bounds · write-ahead journal.

---

## 🔑 Decision-gated (need your call — not auto-buildable)

- **Monetization** — StoreKit 2 IAP / LemonSqueezy, tier gating, Pro monthly report (`StoreKitManager.swift` is a stub). Needs pricing + App Store Connect.
- **Copy-voice guide** (D4-6) — "task/follow-up" vocabulary, de-jargon vault/Ollama/MCP. Needs brand-voice direction.
- **Sparkle auto-update** — needs the signing secret + `SUFeedURL`.
- **License system** — Ed25519/offline design, security-sensitive.
- **Side-peek overlay (CP-1)** — needs a ZStack/architecture decision.
- **On-device Recall, iPhone Shortcuts authoring** — strategic / client-side.

---

## Docs status

| Doc | Status |
|---|---|
| `audit-v2/master-plan.md` | ~57/60 done — near complete |
| `docs/audit-2026-06b/MASTER-PLAN-UX.md` (UX-V6) | ~81% done |
| `docs/audit-2026/MASTER-PLAN.md` (coach + monetization) | ~83% done; remainder is model fields + decision-gated |
| `docs/audit-2026-05b/MASTER_PLAN_V5...` (perf/infra) | **largely unbuilt — the main remaining workstream** |
| `audit/master-plan.md` (Tasks) | ~70% done |
| `docs/REMAINING_WORK.md` | CaptureKit / daemon / iPhone Shortcuts pending |
| root `MASTER_PLAN*.md`, older `audit-2026-05/05b` findings | superseded / folded into the above |

See [`UNCOMPLETED-FEATURES.md`](UNCOMPLETED-FEATURES.md) and [`LEFTOVER-FEATURES.md`](LEFTOVER-FEATURES.md) for the prior per-item detail.
