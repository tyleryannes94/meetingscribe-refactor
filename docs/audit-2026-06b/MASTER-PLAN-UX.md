# MeetingScribe — Master Plan UX-V6 (15-Agent Focused Audit Synthesis)

> **Target:** `~/MeetingScribeRefactor` @ `166e8df` · ~349 Swift files / ~75K LOC.
> **Mandate:** usability · navigation · integrating people into meetings & tasks · a "clean and expensive" UX overhaul.
> **Method:** 15 independent expert agents in 4 groups (Design ×5, Product ×3, End-User Personas ×4, Competitive ×3 with live web research). Each read the June-10 25-agent plan (`docs/audit-2026-06/`) first, audited the live source citing file:line, then proposed net-new work. 172 net-new items produced; this doc dedupes, ranks, and sequences them.
> **Date:** 2026-06-11 · **Status:** Proposed.
> **Per-agent detail:** `docs/audit-2026-06b/findings/*.md`. Every item ID resolves to a full write-up there.

## 1. Executive summary

The June-10 audit's verdict was "the plumbing is further along than the product." This audit's verdict is one level up: **the design system is further along than the design.** NDS has real tokens, bundled brand fonts, CI design-lint, skeleton/empty-state/motion primitives — and the app bypasses nearly all of it: 435 raw SF-Pro text sites, 15 corner radii vs 4 tokens, 12 ad-hoc shadow recipes, ~40 animation literals outside the motion tokens, `.minTap()` with zero call sites, 9 bespoke empty states, 3 button systems, and no app icon in the bundle. "Clean and expensive" is therefore mostly an **adoption-and-enforcement problem**, not an invention problem — sweeps plus lint rules, then a native chrome/materials pass.

The second structural finding: **people are strings, not citizens.** Meetings hold attendees as raw `"Name <email>"` text parsed six divergent ways; the task extractor never sets `ownerPersonID`; fast record paths create attendee-less orphans. Three shipping bugs trace to this (empty follow-up recipients, "Dan"→"Daniel" substring matches, hollow bulk-add records). One identity layer — **PersonResolver** — was independently demanded by three agents and is the hard dependency under every people feature in both this plan and the existing one.

Third: the app's best artifacts are hidden. The series-aware pre-meeting brief lives inside a tab labeled "Transcript" and regenerates on every visit; transcript↔audio tap-to-seek is fully built but its call site never passes the controller. **Wiring and placement beat new engines, again.**

### Convergence map — where independent agents agreed (highest signal)

| # | Theme | Independently raised by | Phase |
|---|---|---|---|
| CV1 | One person-identity resolver (attendee/owner strings → Person records) | P1-1 · P2-1 · P2-10 (+ U2-8, P2-8 depend on it) | 1 |
| CV2 | Premium floating ⌘K: verbs + entities + snippets + query carry-through | C3-2 · D3-4 · D1-8 · U2-2 · U2-3 · U2-10 · C1-7 · U4-5 | 4 |
| CV3 | Native chrome & materials pass (translucent sidebar, hidden title bar; kill in-rail theme toggle) | C3-3 · D2-4 · C3-4 · D2-10 · C3-10 | 2 |
| CV4 | One typographic voice, lint-enforced | D2-1 · C3-7 · D5-11 | 2 |
| CV5 | One motion language + reduce-motion compliance, lint-enforced | D3-1 · C3-8 · D2-11 · D5-8 · D3-10 | 2 |
| CV6 | Today: calm, editorial, day-shaped (15 sections → ~4 modules) | D5-1 · D2-6 · D1-7 · D4-11 · D4-4 · U3-3 | 7 |
| CV7 | Brief-as-hero: cached/pre-warmed, people-first, never 4 clicks deep | C1-1 · U1-3 · U1-10 · U3-12 · U3-9 · U1-7 · P2-5 · P1-10 | 5 |
| CV8 | Series spine: recurring meetings (esp. 1:1s) as a first-class thread | D1-6 · C1-4 · U1-2 · U1-6 | 5 |
| CV9 | Encounter quick-log must honor its 1-tap contract; one flow, not two | C2-12 · D3-6 · U1-8 | 0 |
| CV10 | Menu bar = next-meeting intelligence (the Cron/Notion-Calendar move) | U3-1 · C3-6 · P3-11 | 7 |
| CV11 | One adaptive sheet container (11+ hard-coded frames) | D4-5 · D5-4 | 3 |
| CV12 | Designed error layer + failure parity (summary fails → user is told) | D4-1 · U4-3 · U4-4 | 3 |
| CV13 | One copy voice / jargon decision, lint-enforced | D4-6 · U4-1 · P3-12 | 3 |
| CV14 | One IA across desktop/web/MCP (same sections, names, glyphs, routes) | D1-9 · P3-2 · P3-1 | 8 |
| CV15 | Keyboard-first layer beyond ⌘K (j/k everywhere, single-key actions, "?" overlay) | D3-8 · C2-11 · C3-11 · U2-4 | 4 |
| CV16 | Humans visible on task & meeting rows (owner chips that navigate, face piles, open-loop counts) | P2-3 · P2-11 · P2-12 · U1-9 · P1-7 · C1-11 | 6 |
| CV17 | Fast record paths must attach to the live calendar event + ask "who's this with?" | U2-1 · P1-4 · U2-9 | 1 |
| CV18 | Tabbed plain-language Settings with an Advanced basement | D5-6 · C3-5 · U4-2 | 8 |

## 2. Phase 0 — Shipping bugs & trust emergencies (do first, all small)

Independent of everything else; each is an S-effort fix to something currently broken or trust-damaging in `main`.

| ID | Item | Why it's P0 | Source | Effort |
|---|---|---|---|---|
| U4-10 | Paywall copy emergency pass | Live paywall leaks "set `FeatureGate.shared.isPro = true` in Xcode" to end users | U4 | S |
| P1-6 | Bulk "Add to People" must link + bump | Creates hollow Person records with no meeting link — silent data-model divergence | P1 | S |
| C1-3 | Wire transcript↔audio sync | Tap-to-seek fully built in `TranscriptSyncView`; call site (`MeetingTranscriptTab.swift:42`) never passes the `AudioPlayerController` | C1 | S |
| D5-2 | Fix tertiary-text contrast token | `textTertiary` ≈3.9:1 at 11pt — an AA failure the contrast test codifies; harden the test | D5 | S |
| C2-12 | One encounter flow (CV9) | Retire legacy `AddEncounterSheet`; wire `QuickEncounterSheet` into the profile (`PersonDetailView.swift:343`) and make it truly 1-tap (D3-6, U1-8 fold in) | C2/D3/U1 | S |
| U4-4 | Failure parity notification | Summary failures currently notify nobody — capture promise silently broken | U4 | S |
| D2-8 | Fix nav `person.2` icon collision | Meetings and People share a glyph in the rail | D2 | S |

## 3. Phase 1 — Identity & navigation spine (foundations)

Everything in Phases 4–8 stands on these. PersonResolver (CV1) is the keystone of the entire audit.

| ID | Item | What/why | Source | Effort | Impact | Depends on |
|---|---|---|---|---|---|---|
| P1-1 | **PersonResolver** — one email-keyed identity layer (merges P2-1, P2-10) | Resolve attendee strings + extracted task owners to Person records at finalize/extraction, with backfill; kills six divergent parsers and three shipping bugs | P1/P2 | M | High | none |
| D1-3 | `PendingRoute` mailbox (folds P3-7 landing contract) | Deterministic deep-links; deletes all NotificationCenter + `asyncAfter` navigation; every notification lands somewhere real | D1/P3 | M | High | none |
| D1-1 | State-bearing, semantically correct nav rail | Rail reflects where you are, restores where you were | D1 | S | High | none |
| D1-2 | Entity-complete navigation history | Back/forward remembers people/notes/tasks, not just meetings (`WorkspaceRouter.swift:44`) | D1 | M | High | D1-3 |
| D1-4 | Collapse the second meeting surface in Tasks | The "📁 Workspace" shadow tree + `MeetingNotesPage` undoes canonical-detail routing | D1 | M | High | none |
| U2-1 | Live-event snap (CV17) | Fast record paths (`startRecording(for: nil)`, 4 call sites) auto-attach to the live calendar meeting — zero-click capture becomes metadata-correct | U2 | S | High | none |
| P1-4 | "Who's this with?" picker at record time | Catches the no-calendar case CV17 can't | P1 | M | High | P1-1 |
| U2-9 | Auto-title ad-hoc recordings from first transcript chunk | Kills the "Ad-hoc Recording" orphan wall | U2 | S | Med | none |
| P3-1 | Web hash-routes twinned 1:1 with `meetingscribe://` | Cheapest item with the longest dependency tail: citations, handoff, notification landings | P3 | S | High | none |

## 4. Phase 2 — The premium shell ("clean and expensive" core)

The visible overhaul. Sweeps + lint so it can't drift back.

| ID | Item | What/why | Source | Effort | Impact | Depends on |
|---|---|---|---|---|---|---|
| C3-3 | Native chrome & materials pass (merges D2-4; CV3) | Translucent sidebar, hidden title bar, glass floating surfaces — "the stage every other expensive detail performs on" | C3/D2 | M–L | High | best after planned 2A shell unification |
| D2-1 | Modular type ramp + text-style lint (merges C3-7, D5-11; CV4) | One typeface voice at named sizes; sweep the 435 raw SF-Pro sites; Bricolage reserved for display moments | D2/C3/D5 | M | High | none |
| D2-2 | Elevation token system | Dark-first: surface, not shadow; replaces 12 ad-hoc shadow recipes | D2 | S | High | none |
| D2-3 | Radius ramp + nesting rule, linted | 15 radii → 4 tokens | D2 | S | Med-High | none |
| D3-1 | NDS Motion Language spec + lint (merges D2-11, C3-8, D5-8; CV5) | One spring vocabulary, reduce-motion-proof incl. NDS's own buttons; ~40 literals → tokens | D3/D2/C3/D5 | M | High | none |
| D2-7 | Designed recording state | Semantic `NDS.recording` + live border treatment; kill raw `.red` | D2 | S | High | none |
| C3-1 | Real app icon + one brand-mark pipeline | There is literally no app icon in the bundle; mark flows to onboarding + empty states | C3 | S–M | High | none |
| C3-4 | Follow the system appearance (merges D2-10) | Kill the web-style in-rail Light/Dark toggle | C3/D2 | S | Med | none |
| C3-9 | Brandize the first five minutes | Onboarding + empty states on NDS, not system-gray (pairs with held item 1E) | C3 | M | High | C3-1 |
| D2-9 | Surface-adoption sweep | 48 hand-rolled cards → `msCard`; paddings → tokens | D2 | M | Med-High | D2-2/D2-3 |
| D2-5 | Glow budget | One luminous moment per screen | D2 | S | Med-High | D2-2 |
| D4-7 | Design-lint v2 (folds D5-3 minTap rule, U4-1 jargon rule) | Radius, semantic-color, primitive-bypass, tap-target, jargon rules — the "can't drift back" lock | D4/D5/U4 | S | High | sweeps land first |
| D2-12 | Name the system | Retire Notion/Untitled/Stripe identity residue (with C3-10 chrome de-dup) | D2/C3 | S | Med | none |

## 5. Phase 3 — Component, state & copy system

Every state designed; one anatomy per concept.

| ID | Item | What/why | Source | Effort | Impact | Depends on |
|---|---|---|---|---|---|---|
| D4-1 | `MSErrorState` + human-readable error layer (merges U4-3; CV12) | The missing fourth state; one `ErrorPresenter`, three plain-language fields; no more raw `whisper-cli` stderr in the transcript tab | D4/U4 | M | High | none |
| D4-2 | Empty-state system v2 | One visual signature + filtered-empty variants; replaces 9 bespoke clones (Meetings' uses the People icon) | D4 | M | High | C3-1 mark |
| D4-9 | Skeleton standards | Shaped placeholders, labeled spinners | D4 | S–M | Med | none |
| D4-5 | `MSSheet` adaptive sheet container (merges D5-4; CV11) | One sheet anatomy; replaces 11+ hard-coded frames and 4 header patterns | D4/D5 | M | High | none |
| D4-3 | `TaskMetaCluster` | One task rendering across all 6 surfaces (list/board/table/gallery/Today/person) | D4 | M | High | none |
| D4-10 | `MSFilterChip` with counts | One chip component | D4 | S | Med | none |
| D3-10 | `.ndsHover(_:)` hover/press standard | Kills 15 bespoke hover implementations | D3 | M | High | D3-1 |
| D3-12 | Toast v2 | Stacking, hover-pause, action affordance (undo rides on this) | D3 | S | Med | none |
| U3-11 | Kill `NSAlert.runModal` → NDS toasts/dialogs | Modal jank reads cheap | U3 | S | Med | D3-12 |
| D4-6 | Copy voice guide + entity-name decree (merges U4-1 word-map, P3-12 lexicon; CV13) | "task" everywhere; vault/Ollama/MCP jargon → human words; unblocks held item 1E | D4/U4/P3 | S | High | none |
| D4-8 | "No selection" panes that earn their pixels | Premium apps design the in-between | D4 | M | Med-High | D4-2 |
| D5-5 | Semantic rows | Button-ify `onTapGesture` rows, combined a11y elements, heading rotor | D5 | M | High | none |
| D5-10 | AttendeeChip legibility + real target | Legible "in People" state | D5 | S | Med-High | none |

## 6. Phase 4 — Command layer & keyboard model

The power-user contract. Depends on Phase 1 routing.

| ID | Item | What/why | Source | Effort | Impact | Depends on |
|---|---|---|---|---|---|---|
| C3-2 | Floating ⌘K command palette (merges D3-4; CV2) | Raycast-grade: verbs + entities + per-result actions, blurred glass, spring-in | C3/D3 | M | High | D1-3, D3-1 |
| D1-8 | One query engine, many mouths (folds P3-5 partially) | ⌘K, GlobalSearch, web, MCP share the FTS5 hybrid brain + search-escalation row | D1/P3 | M | Med-High | none |
| U2-3 | Matched-context snippets in results (merges U4-5) | Results show the matched sentence, not bare titles | U2/U4 | M | High | D1-8 |
| U2-2 | Query carry-through | Search result → transcript, pre-highlighted, no retyping | U2 | S | High | D1-3 |
| U2-10 | Search qualifiers | `with:@sarah before:may in:transcripts` | U2 | M | High | P1-1, D1-8 |
| C1-7 | Search-in-context for transcripts | Counter + Enter/Shift-Enter | C1 | S | Med-High | none |
| D3-8 | Unified keyboard model (merges C2-11, C3-11; CV15) | j/k list nav everywhere, single-key actions, "?" shortcut overlay | D3/C2/C3 | M | High | none |
| U2-4 | Keyboard-first triage | Inbox-zero on action items in 60s (~30 clicks → keystrokes) | U2 | M | High | D3-8 |
| D3-3 | Real ⌘Z via `NSUndoManager` | Zero undo today; bridges stores | D3 | M | High | none |
| D3-2 | One-click task completion + celebration beat | The Things-3 moment; currently a menu click | D3 | S | High | D3-1 |
| U2-5 | Global Quick Entry window (Things-style), live-meeting aware | Capture without alt-tab (with U2-6 dock capture line, U2-7 explicit dictation destination) | U2 | M | High | U2-1 |
| D1-10 | Directional section transitions | Spatial nav model | D1 | S | Med | D3-1 |
| D1-5 | Universal entity Peek (space-bar/hover preview) | Quick look at any entity without committing navigation | D1 | L | High | D1-3 |

## 7. Phase 5 — People in meetings

The mandate's heart. All of it stands on PersonResolver.

| ID | Item | What/why | Source | Effort | Impact | Depends on |
|---|---|---|---|---|---|---|
| P1-2 | "Who's here" people rail in meeting detail (folds P1-11 mentioned-not-present) | Health, last-met, open commitments per attendee, right there | P1 | M | High | P1-1 |
| C1-1 | Brief-as-hero (CV7) | Prep greets you in the meeting view, not buried in a "Transcript" tab (`UnifiedMeetingDetail.swift:357`) | C1 | M | High | none |
| U1-10 | Persist + pre-warm briefs (merges U3-12 LLM right-of-way) | Kills the on-appear Ollama wait; the latency floor under every brief surface | U1/U3 | S | High | none |
| U3-9 | People-first brief content (merges U1-7, P2-5) | The brief leads with the humans: shared history, open loops "between you and X" | U3/U1/P2 | S–M | High | P1-1, U1-10 |
| P1-5 | Shared-history strip | "3rd meeting with Jane this quarter" | P1 | S | Med-High | P1-1 |
| P1-7 | Face piles on meeting rows (CV16) | Today, Meetings list, MeetingCard | P1 | S | Med-High | P1-1 |
| D1-6 | Series spine (merges C1-4, U1-2; CV8) | Recurring meeting = first-class thread; prev/next; the "1:1 home" both directions | D1/C1/U1 | M | High | P1-1 |
| U1-6 | Commitment carry-forward on series finalize | Last 1:1's open items roll into the next | U1 | M | Med | D1-6 |
| U1-1 | "Your 1:1 Day" person-first rail on Today | Manager prep: ~40 clicks → 0 | U1 | M | High | U1-10, D1-6 |
| U1-5 | "Discuss next time" talking-points inbox (merges P2-4) | The one missing object no plan covers; surfaces in pre-meeting brief | U1/P2 | M | High | P1-1 |
| P1-3 | Speaker→person mapping ("This is Jane") | Per-meeting sidecar; person-attributed talk-time + action items | P1 | M | High | P1-1 |
| P1-8 | Person-aware follow-up composer (merges P2-7) | Drafts addressed to the actual humans | P1/P2 | M | Med-High | P1-1 |
| P1-9 | Recorded meetings emit encounters | One interaction stream feeding health + C2-1 timeline | P1 | M | Med | P1-1 |
| P1-10 | Person context in meeting Ask-AI + brief synthesis | The vault knows who these people are; use it | P1 | S–M | High | P1-1 |
| C1-2 | "Mark moment" in-call highlight | Fathom's signature gesture → pinned summary anchors (with C1-10 time-remaining cue) | C1 | M | High | none |
| P1-12 | Live "in the room" per-person quick-capture | Tag a note to a person while recording | P1 | M | Med-High | P1-2 |
| U3-5 | External/internal awareness from attendee domains | Customer vs team framing everywhere | U3 | S | High | P1-1 |

## 8. Phase 6 — People in tasks

| ID | Item | What/why | Source | Effort | Impact | Depends on |
|---|---|---|---|---|---|---|
| P2-2 | People facet in Tasks IA | Sidebar section + person scope (rails exist: `TaskQuery.Scope.person`) | P2 | M | High | P1-1 |
| P2-3 | Owner chips that navigate (CV16) | Every owner chip is an `EntityLink` (with P2-11 humans-on-Today, P2-12 open-commitment counts, U1-9 linked attendee chips) | P2/U1 | S | High | D1-3 |
| P2-8 | `@person` + `>person` tokens in quick-add (merges U2-8) | Person-addressed capture at typing speed | P2/U2 | M | High | P1-1 |
| P2-9 | Attendee-first assignment in meeting Actions tab | The people in the room are the likely owners | P2 | S | High | P1-1 |
| P2-6 | Waiting-on lifecycle | Capture delegated items by default, age them, one-click nudge | P2 | M | High | P1-1 |
| C1-11 | Forward-looking person header | "Next with Priya" + open loops on the meeting header | C1 | M | High | P1-1, D1-6 |

## 9. Phase 7 — Person profile, Today & menu bar (the daily surfaces)

| ID | Item | What/why | Source | Effort | Impact | Depends on |
|---|---|---|---|---|---|---|
| C2-1 | Unified "Story" timeline as profile default | Encounters+meetings+notes+decisions in one stream (gated on planned `PersonDetailView` decomposition) | C2 | M | High | P1-9; planned 2G decomposition |
| C2-3 | Health "why" popover + trend + next-best action | Score without explanation is decoration | C2 | S–M | High | none |
| C2-4 | Reconnect-with-context + local AI draft | Last-topic snippet + Ollama-drafted opener — uniquely private | C2 | M | High | none |
| C2-2 | Keep-in-touch kanban by health band | A People list mode (Dex-proven) | C2 | M | High | none |
| C2-10 | Health-ring avatars everywhere | One glanceable people language (with C2-7 de-emoji, C2-9 "known for 3 years" line) | C2 | S | Med-High | none |
| C2-6 | Mood as first-class field | Currently serialized into a dead `[mood:x]` string; mood-tinted heat map | C2 | S–M | Med-High | none |
| D5-7 | Identity pane: adaptive 3-zone calm layout | The profile's premium moment (with D5-9 meeting header 8 rows → 3) | D5 | M | High | none |
| U1-4 | Per-person evidence compiler | Perf-review season: 6 months of evidence, deterministic, no LLM wait (with U1-11 "My Team" smart group) | U1 | M | High | P1-1 |
| D5-1 | **Today, calm by default** (merges D2-6, D1-7, D4-11, D4-4; CV6) | 15 stacked sections → 4 confident modules + "More" shelf; one section-header spec; merge the two drifting-people modules | D5/D2/D1/D4 | M | High | D4-3 |
| U3-3 | "Day shape" strip atop Today | The 7am coffee scan answered in 10 seconds | U3 | M | High | D5-1 |
| U3-2 | Turnaround card | The back-to-back bridge: 30 seconds between meetings, what's next, who, one number | U3 | M | High | U1-10 |
| U3-4 | One-line outcome per meeting, everywhere | Lists answer "what happened" without opening anything | U3 | S | High | none |
| U3-1 | Menu-bar next-meeting intelligence (merges C3-6, P3-11; CV10) | Countdown + prep card + live recording state — the Cron standard | U3/C3/P3 | M | High | U1-10 |
| U3-6 | Exec-grade Weekly Ledger | "What did I commit to this week" + copy-as-update (with U3-10 attributed quote bank) | U3 | M | High | P1-1 |

## 10. Phase 8 — Cross-surface coherence & trust

| ID | Item | What/why | Source | Effort | Impact | Depends on |
|---|---|---|---|---|---|---|
| P3-2 | One canonical IA (merges D1-9; CV14) | Same sections, order, words, glyphs on desktop + web | P3/D1 | S | High | D1-1 |
| P3-3 | Mac presence on the phone | Live recording status + remote stop | P3 | S | High | none |
| P3-4 | Phone Today = pocket schedule (merges U3-7) | Next meeting + the humans in it (with U3-8 read-first person dossier) | P3/U3 | M | High | P3-1 |
| P3-6 | Citations that navigate, on every surface | Ask-AI/MCP answers deep-link to source | P3 | S | High | P3-1, D1-3 |
| P3-8 | Phone quick capture into `_inbox/` | Notes + tasks + encounters, app closed or not | P3 | M | High | P3-1 |
| P3-9 | Bidirectional handoff | "Send to phone" / "Open on Mac" | P3 | S | Med | P3-1 |
| P3-10 | MCP parity: projects + Today aggregate | Claude sees what you see | P3 | S | Med | none |
| D5-6 | Tabbed, plain-language Settings (merges C3-5, U4-2; CV18) | 24-section scroll → toolbar tabs + Advanced basement | D5/C3/U4 | M | High | D4-6 |
| U4-6 | Trust Center | One room for "Your data" incl. **Delete this conversation** (no delete affordance exists today) — with U4-7 per-client consent tracking, C1-9 transcript trim/redact | U4/C1 | M | High | none |
| U4-9 | Capability-aware UI | Never advertise what can't work yet (with U4-8 sidebar identity fixes, U4-11 first-summary recap) | U4 | M | High | none |
| C1-5 | Saved Views as tabs (Meetings + Tasks) | Premium list management (with C1-6 "Copy for Slack/email" split button, C1-8 meeting-type templates, C1-12 edit-summary-by-asking) | C1 | M | Med-High | none |
| D3-5 | Drop-target choreography | Board + list drag-drop feedback (with D3-7 numeric transitions, D3-9 FloatingOverlay lifecycle animation, D3-11 inline mention popover) | D3 | M | Med-High | D3-1 |

## 11. How to use this plan

- Phases are dependency-ordered; Phase 0 is non-negotiable and independent. Phase 1 (PersonResolver + routing) unblocks Phases 4–8; Phase 2–3 (shell + components) can run in parallel with Phase 1.
- Every ID resolves to a full write-up in `docs/audit-2026-06b/findings/<agent-file>.md` — hand a builder the ID + that file.
- This plan deliberately excludes reliability/security/monetization work — that's owned by `docs/audit-2026-06/MASTER-PLAN.md`. Where an item here upgrades a planned item (e.g. C3-2 is the premium spec for planned 2A's Cmd-K), build the merged version once.
- Respect `CLAUDE.md`: `swift build -c release` (or `make app`) green before any push; ask before pushing.

## Appendix — full item catalog by agent

- **D1 (IA/navigation):** D1-1…D1-10 — `findings/D1_ia_navigation.md`
- **D2 (visual/premium):** D2-1…D2-12 — `findings/D2_visual_premium.md`
- **D3 (interaction/motion):** D3-1…D3-12 — `findings/D3_interaction_motion.md`
- **D4 (states/consistency):** D4-1…D4-11 — `findings/D4_states_consistency.md`
- **D5 (a11y/density):** D5-1…D5-11 — `findings/D5_a11y_density.md`
- **P1 (people↔meetings):** P1-1…P1-12 — `findings/P1_people_meetings.md`
- **P2 (people↔tasks):** P2-1…P2-12 — `findings/P2_people_tasks.md`
- **P3 (cross-surface):** P3-1…P3-12 — `findings/P3_cross_surface.md`
- **U1 (manager):** U1-1…U1-11 — `findings/U1_manager.md`
- **U2 (busy IC):** U2-1…U2-10 — `findings/U2_busy_ic.md`
- **U3 (exec):** U3-1…U3-12 — `findings/U3_exec.md`
- **U4 (non-technical):** U4-1…U4-11 — `findings/U4_nontechnical.md`
- **C1 (meeting tools):** C1-1…C1-12 — `findings/C1_meeting_tools.md`
- **C2 (personal CRM):** C2-1…C2-12 — `findings/C2_personal_crm.md`
- **C3 (premium macOS):** C3-1…C3-11 — `findings/C3_premium_macos.md`
