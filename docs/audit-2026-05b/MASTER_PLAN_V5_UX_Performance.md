# MeetingScribe — Master Plan V5: UX, Layout, Integration & Performance

> **Repo:** `~/MeetingScribeRefactor` (HEAD `38d314d`). **Method:** 20 independent expert agents in 5 groups — Modern Design & Layout (4) · Per-Tab UX (5) · Tab Integration & Sync (3) · Performance/Load/Stability (4) · Competitive & Best Practices (4, live web research). Each verified what's already built (V4 Phases 0–5 shipped), audited the live source citing `file:line`, and proposed net-new work focused on **layout/design, click-reduction, tab integration & syncing, per-tab UX — every item constrained by speed, load time, crash-prevention, and cache-first first-open.**
> **Date:** 2026-05-31 · **Status:** Proposed. **Per-agent detail:** `audit2/findings/*.md` — item IDs (e.g. `PC-1`, `SD-3`) map there.

---

## 1. Executive summary

The app is feature-rich and the data/caching *substrate* is already good (LRU `MeetingBodyCache`, `ThumbnailCache`, `.upcoming-cache.json`, off-main store loads, `ResourceGovernor`). The opportunity now is almost entirely in the **presentation and integration layers**, and the 20 agents converged hard on a single story:

**The caches serve the second read, not the first paint; the five tabs are five different apps stitched together; and a handful of hot paths do synchronous disk/CPU work on the main thread during scroll and render.** Fixing those three things — with a cache-first launch snapshot, one native shell + shared components, a cross-tab entity index, and the removal of main-thread I/O — is what radically improves usability *and* speed at the same time.

Critically, the speed/stability work is **not** a separate track from the UX work — it's the foundation that makes the UX feel instant. So Phase 1 is the performance/caching/crash spine, and Phases 2–4 build the radically-better UX *on top of cache-backed, off-main primitives*.

### Convergence map — where independent agents agreed (highest signal)

| Theme | Independent agents | Phase |
|---|---|---|
| **Cache-first "launch snapshot" — render last session on frame 0, reconcile after** | CB-1, PC-1, TT-1, PP-3, SC-6, TM-1, CP-7 (7 agents) | 1 |
| **Skeleton / `loadState` tri-state — kill the blank/false-empty flash on cold open** | DI-1, DV-4, PP-1, PP-2, PC-4, SC-4, DL-8, TT-7 | 1 |
| **Kill the synchronous full-transcript read in `MeetingCard` (scroll-jank + hang risk)** | PR-1, PS-1, TM-2 | 1 |
| **O(1) indexes (people/tags/encounters) — remove O(n)/O(n²) work per render** | PR-3, PR-2, TP-1, TK-7, SD-3 | 1 |
| **Async/off-main thumbnail decode (only confirmed main-thread decode) + persist it** | DI-2, PR-5, TP-2 | 1 |
| **Native `NavigationSplitView` shell — retire the hand-rolled ZStack/HStack rail + inset hacks** | CM-1, DL-1, CM-2 | 2 |
| **Shared component library (`MSList`/search/empty/tag) — keyboard nav + behavior parity everywhere** | SC-1, SC-2, SC-3, SC-5, SC-8, DV-2, DV-5 | 2 |
| **Cross-tab reverse entity index (person→meetings/tasks/decisions) + stable attendee IDs** | SD-3, SD-2, SD-4, TP-7 | 2 |
| **`VaultEventBus` + observe `vaultChanged` + chips observe stores — instant live propagation** | SP-1, SP-2, SP-3, SP-4, DI-3, PP-5 | 2 |
| **Fluid navigation: shared selection, global back/forward, side-peek, breadcrumb, recents** | SD-1, DN-1, DN-7, DN-4, CP-1, CP-5 | 2 |
| **Merge meeting Transcript/Notes/Summary into one "Enhanced Notes" canvas (fewer clicks)** | CN-1, TM-5 | 3 |
| **⌘K from search → contextual command runner / quick-switcher** | CP-2, DN-2, DN-6, TS-2, CM-5 | 3 |
| **Collapse 3 competing type systems → NDS tokens; semantic colors + materials** | DV-3, DV-6, CM-3 | 4 |

---

## 2. Phase 1 — Instant & Stable Foundation
**Goal:** the app opens to a populated screen in <100ms, never flashes blank/empty, never janks on scroll, and never crashes silently. This is the user's headline constraint (speed, load, crash, cache) and the substrate Phases 2–4 build on.

### 2.1 Cache-first instant open
| ID | Item | UX / perf impact | Source | Effort |
|---|---|---|---|---|
| **PC-3** | **Shared `VaultCache` layer** — atomic write, versioning, TTL, corruption-recovery (give the ad-hoc JSON caches the safety SQLite already has). Foundation for the rest. | Infra; makes snapshots safe & consistent | Perf/coldstart | M |
| **PC-1 / CB-1 / TT-1 / SC-6 / PP-3 / TM-1** | **Launch Snapshot** — persist a tiny per-surface snapshot (Today feed, meeting list rows, people list, task list) and render it synchronously on frame 0, then reconcile when stores hydrate. The single biggest perceived-speed win; "the data is already there" (Linear/Superhuman pattern). | Blank cold-open → fully populated instantly | Perf/coldstart, CompPerf, Today, Sync, Perceived, Meetings | L |
| **PC-2** | Move `SecondBrainDB` `sqlite3_open` + `quick_check` off the launch thread (last hard-synchronous disk item, runs in `PeopleStore.shared` during `body`). | Removes a launch stall | Perf/coldstart | S |
| **TT-2 / PC-5 / PC-8** | Defer heavy backfills (embeddings, decisions, person-extraction) off the first-paint frame; lazy-construct non-first-screen `@StateObject`s. | First frame paints before CPU work | Today, Perf | S–M |
| **CB-3** | SQLite production pragma profile (`synchronous=NORMAL`, `mmap_size`, `cache_size`, `busy_timeout`) — broad speedup + removes a lock-contention crash vector. | Faster search/recall/graph | CompPerf | S |
| **PC-7 / CB-8** | Local-only cold-start instrumentation in `MetricsStore` + a launch-time budget. | Measure the win | Perf | S |

### 2.2 Skeletons & honest loading states
| ID | Item | UX / perf impact | Source | Effort |
|---|---|---|---|---|
| **PP-1 / PC-4** | Tri-state `loadState` (loading / loaded / empty) on detail tabs + lists, keyed on `loadedAt` not array-emptiness — fixes the cold-cache "No summary / No transcript" *error-looking* flash. | Removes a real perceived-perf bug | Perceived, Perf | S |
| **DI-1 / DV-4 / PP-2 / SC-4** | A reusable `MSSkeleton` / `.redacted(.placeholder)` primitive; show structure while cold, gated to true cache-misses and reduce-motion-aware. | First paint feels instant | Design×2, Perceived, Sync | S |
| **DV-5 / SC-3** | `MSEmptyState` on `ContentUnavailableView` for every empty/zero/error state. | Consistent, actionable empties | Design, Sync | S |

### 2.3 Kill main-thread I/O & O(n) render work
| ID | Item | UX / perf impact | Source | Effort |
|---|---|---|---|---|
| **PR-1 / PS-1 / TM-2** | **Stop `MeetingCard.hasFile` reading the entire transcript via `String(contentsOf:)` on every body eval** (`MeetingCard.swift:316`); drive status from `meeting.health`; route all list/card status through cache. The #1 scroll-jank + hang vector. | Smooth scrolling; no hangs | Runtime, Stability, Meetings | S |
| **PR-3 / TP-1** | `[String: Person]` index in `PeopleStore`; make `person(by:)` + `encounterCount` O(1) (today O(n)/O(n²), run inside a sort comparator on the main actor). | De-janks People + everything that resolves a person | Runtime, People | S |
| **PR-2** | `[String: MeetingTag]` index in `TagStore` + per-meeting tag cache (today `tag(by:)` is an O(tags) scan per card per render). | De-janks every meeting list | Runtime | S |
| **DI-2 / PR-5 / TP-2** | Async, fade-in, **disk-persisted** thumbnail cache used everywhere incl. graph nodes (today `ThumbnailCache` decodes synchronously, memory-only; graph nodes bypass it via full-res `AsyncImage`). | Removes the confirmed scroll-decode stall | Design, Runtime, People | S–M |
| **PR-4** | Memoize + debounce the People list pipeline (empty-query sort is O(people×encounters×log people) per keystroke). | Instant typing/filtering | Runtime | S |
| **TK-2 / PR-7 / SP-4** | Debounced, coalesced, **off-main** persistence; batch bulk-edit writes (today every field edit synchronously JSON-encodes the entire DB on the main actor). | No stutter on edit/bulk | Tasks, Runtime, Sync | M |

### 2.4 Crash-prevention & stability
| ID | Item | UX / perf impact | Source | Effort |
|---|---|---|---|---|
| **PS-3** | Hard crash capture (`NSSetUncaughtExceptionHandler` + signal handlers) into the diagnostics bundle (none today). | Silent crashes → diagnosable | Stability | S |
| **PS-5 / PS-2 / PS-6** | Byte-bound the caches (`totalCostLimit` + body-byte cap); bound the Chat conversation; cache+bound `backlinks` instead of full-corpus rescan. | Prevents OOM kills; bounds memory | Stability | S–M |
| **PS-4** | Race-proof the off-main `PeopleStore.load()` path (latent data race on the core graph). | Prevents corruption/crash | Stability | S |
| **CB-6** | Vault write-ahead journal + startup resume/integrity sweep (crash-safety keystone for captured meetings). | No stranded/half-written meetings | CompPerf | M |
| **PS-8** | Stability test floor (long-meeting fuzz, race tests) for the above. | Locks in the fixes | Stability | M |

---

## 3. Phase 2 — One Native, Connected Workspace
**Goal:** the five tabs stop being five apps. A native shell, one shared component set, a cross-tab entity graph, live propagation, and fluid navigation make it feel like a single workspace where everything is one or two clicks (or one keystroke) away. Built on Phase 1's cache-backed, off-main primitives.

### 3.1 Native shell & unified layout
| ID | Item | UX / perf impact | Source | Effort |
|---|---|---|---|---|
| **CM-1** | Adopt `NavigationSplitView` for the shell (sidebar + detail), keep tab warmth via `@SceneStorage`. Retires the hand-rolled ZStack keep-alive + the `splitPaneTopInset=60`/`padding(.top,48)` titlebar hacks. The system lazily builds the detail column and caches layout — **cheaper** than the always-resident opacity stack. | Native feel; lower memory | CompMacOS | L |
| **DL-1 / DL-5** | One shared `WorkspaceSplit` pane primitive (unify the 4 conflicting pane systems + 3 sidebar-width triples); promote the top-inset into it (delete 5 copies). | Panes stop jumping width; resize always works | Layout | M |
| **CM-2 / DL-2 / DN-8** | Restore window frame + `.defaultSize`; collapsible, keyboard-focusable sidebars with a uniform toggle. | Native window behavior; reclaim width | CompMacOS, Layout, Nav | S–M |
| **DL-3 / DL-4** | Reading-measure cap on all prose panes (lines run to 1200px today); width-adaptive density tiers (compact/regular/wide) off one root `GeometryReader`. | Readable prose; great at any size | Layout | S–M |

### 3.2 Shared component library (behavior + perf parity)
| ID | Item | UX / perf impact | Source | Effort |
|---|---|---|---|---|
| **SC-1** | `MSList` selectable-list primitive wrapping `List(selection:)` — keyboard nav + selection **everywhere** (today Meetings/Tasks are mouse-only `ScrollView+Button`; only People has keyboard nav). Host for skeletons, snapshot cache, and row context menus. | Keyboard nav in every tab | Sync | M |
| **SC-2** | `MSSearchField` (one component) + universal ⌘F-to-focus + Esc-to-clear (replaces 7 divergent fields). | Consistent, fast search | Sync | S |
| **SC-5 / SD-6** | `MSTagPicker` over one `TagRegistry` — unify the two disjoint tag namespaces (meeting tags vs people tags). | Tag once, works everywhere | Sync, Datamodel | M |
| **DV-2 / SC-8** | Extract `MSCard`/`MSListRow`/`MSSurface`; collapse to one button vocabulary (retire `Untitled*`). Stops visual drift; one place to optimize. | Visual consistency | Design, Sync | M |
| **SC-7** | Row-level context menus in the `MSList` row protocol (missing on the main meeting/person rows today). | Right-click actions everywhere | Sync | S |

### 3.3 Cross-tab entity graph (the integration keystone)
| ID | Item | UX / perf impact | Source | Effort |
|---|---|---|---|---|
| **SD-3 / TP-7** | **Cache-backed `EntityGraphIndex` actor** — persisted reverse index (person→meetings/tasks/decisions, meeting→tasks/backlinks) built at write-time. Turns every cross-tab join from an O(n) scan / 2-disk-reads-per-meeting into an O(1) cache read. | Instant "everything about X" | Datamodel, People | M |
| **SD-2** | Stable `personID` on meeting attendees + a persisted resolver (replaces brittle email/substring matching scanned O(n) per PersonDetail render). | Reliable attendee↔person links | Datamodel | M |
| **SD-4** | Replace file-scanning `backlinks(toMeetingID:)` with persisted link rows. | Instant backlinks | Datamodel | S |
| **SD-5** | Give `Decision` a person edge (`commitOwnerPersonID`/`relatedPersonIDs`) — today decisions have no person link at all. | Decisions appear on people | Datamodel | S |
| **SD-8** | Index lifecycle + integrity guard (build/verify/rebuild). | Keeps the graph honest | Datamodel | S |

### 3.4 Live propagation (edit once, reflects everywhere)
| ID | Item | UX / perf impact | Source | Effort |
|---|---|---|---|---|
| **SP-2** | A typed, **coalesced** `VaultEventBus` (debounced, ID-scoped) as the propagation backbone — replaces ad-hoc string `NotificationCenter` hops; enables surgical cache/FTS invalidation (never nuke-all). | No re-render storms | Propagation | M |
| **SP-1 / SP-5** | App-side `vaultChanged`/`inboxChanged` observer + idempotent `reloadFromDisk()` — today the MCP posts `vaultChanged` but **nothing observes it**, so Claude-driven edits stay invisible until relaunch. | Claude/Shortcut edits appear live | Propagation | M |
| **SP-3** | Make `AttendeeChip` + `MeetingSummaryTab` observe `PeopleStore` (they read it statically today → stale chips after tagging/creating a person). | No stale views | Propagation | S |
| **DI-3 / PP-5** | Generalized optimistic-edit + reconcile via `ToastCenter` (instant apply, background persist, Undo). | Edits feel instant | Design, Perceived | M |
| **SP-8** | Subscribe Today to the bus for live refresh. | Today never stale | Propagation | S |

### 3.5 Fluid navigation
| ID | Item | UX / perf impact | Source | Effort |
|---|---|---|---|---|
| **SD-1 / DN-7** | Shared `selectedPersonID`/`focus` in `WorkspaceRouter`; route **all** navigation through the router (retire fragile NotificationCenter/`asyncAfter(0.05)` hops). | Selecting a person carries context across tabs | Datamodel, Nav | M |
| **CP-1** | **Side-peek overlay** for cross-entity links (Notion/Tana pattern) — open a linked person/meeting/task without losing your place. The single pattern the current one-tab-at-a-time ZStack structurally blocks. | Explore links, keep context | CompPKM | M |
| **DN-1 / CP-5** | Global back/forward stack (`⌘[`/`⌘]`) + workspace breadcrumb spine. | 2–4-click re-nav → one keystroke | Nav, CompPKM | M |
| **DN-4 / DN-6** | Cache-backed "Recently viewed" rail + empty-⌘K recents + quick-switcher (type-ahead jump). | Get back to anything in 1 click | Nav | S–M |

---

## 4. Phase 3 — Per-Tab Excellence & Click-Reduction
**Goal:** make each tab the best version of its job, applying the 3-click/2-click rule, on top of the shared primitives. Every list is now `MSList` (cache-backed, keyboard, skeletoned), so these are mostly higher-level UX moves.

### Today
| ID | Item | Clicks / impact | Source | Effort |
|---|---|---|---|---|
| **TT-3 / TT-5** | A glanceable "status strip" hero; consolidate the three overlapping task surfaces into one prioritized "Today's work" block. | 5-second glance; less clutter | Today | M |
| **TT-6 / TT-4 / TT-8** | Pull recent/pinned Notes into Today (the one tab it never references); snapshot per-section lists into `@State`; route person-open through shared selection (kill the `asyncAfter` hack). | Complete hub; no re-compute | Today | S–M |

### Meetings
| ID | Item | Clicks / impact | Source | Effort |
|---|---|---|---|---|
| **CN-1 / TM-5** | **"Enhanced Notes" merged canvas** — collapse Transcript/Notes/Summary tabs into one default view (Granola pattern); lift action-items + decisions into an always-present "Outcomes" strip (out of the summary-gated branch). Render cached merged markdown; lazy-load transcript on toggle. | 3 tabs → 1; outcomes always visible | CompNotetakers, Meetings | M |
| **TM-4 / TM-7 / TM-8** | Decisions section + 1-click capture to ledger; virtualize/paginate long transcripts + in-transcript find (stability for marathon meetings); collapsible compact reading header. | Faster, stable long transcripts | Meetings | M |
| **CN-2 / TM-9** | Clickable meeting outline / jump-to-moment rail; inline attendee→Person hover card + "Add all to People". | Navigate a meeting in 1 click | CompNotetakers, Meetings | M |

### People
| ID | Item | Clicks / impact | Source | Effort |
|---|---|---|---|---|
| **TP-3 / TP-9** | Background graph build + progressive layout + skeleton (today O(n²) edges + force layout synchronously on `@MainActor` in `.onAppear`); lazy section scaffold for the 14-section person page. | Graph + person page open instantly | People | M |
| **TP-5 / TP-8 / TP-4** | Person→Decisions/Commitments section (closes the last cross-tab loop); inline reconnect/cadence actions on "gone cold"; surface the dead "find path between people" feature. | Act in ≤2 clicks | People | S–M |

### Tasks
| ID | Item | Clicks / impact | Source | Effort |
|---|---|---|---|---|
| **TK-1** | Collapse to the existing (currently dead, drifting) `ActionItemsViewModel` as the single cached source of truth. | Removes dead-code + per-keystroke re-sort | Tasks | M |
| **TK-3 / TK-4** | Multi-select + bulk action bar (Linear parity; ~16 clicks → 2); keyboard-first nav & quick-set. | Big day-to-day win | Tasks | M |
| **TK-5 / TK-8 / TK-9** | Editable virtualized table + richer board cards; resizable sidebar w/ persisted width (fixed 230px today); cached "group by" buckets + saved views. | Smooth at scale | Tasks | M |

### Secondary (Notes / Chat / Search / Settings)
| ID | Item | Clicks / impact | Source | Effort |
|---|---|---|---|---|
| **TS-4** | Sectioned Settings + **revive the orphaned `IntegrationsView`** (a polished card UI with zero call sites today) replacing the 900-line single-scroll Form; lazy section bodies. | Findable settings; faster open | Secondary, CompMacOS | S–M |
| **TS-1 / TS-5** | Persist & thread the Chat session (in-memory only today → wiped each relaunch); make voice notes a first-class linkable entity. | Durable chat; connected notes | Secondary | M |
| **CP-2 / TS-2 / TS-6** | ⌘K as a contextual command runner (inject the open entity's actions); Settings + recent searches in ⌘K; context-aware chat prompts + "Ask about this" everywhere. | Do anything from ⌘K | CompPKM, Secondary | M |
| **CN-6 / PP-6** | Sub-30s "summary-ready" path with optimistic skeleton over stale content for regenerate/transcribe. | Hits industry speed bar | CompNotetakers, Perceived | M |

---

## 5. Phase 4 — Premium Native Polish & Best-in-Class Recall
**Goal:** make it look and feel like a premium Mac app, and match/beat competitors on recall — the delight layer on a now-fast, connected foundation.

### Design system & native feel
| ID | Item | Impact | Source | Effort |
|---|---|---|---|---|
| **DV-3** | Mechanically collapse the three competing type systems (590+ font calls: NDS tokens + raw `.system(size:)` + SwiftUI styles) into NDS `Font.TextStyle` tokens — also finishes Dynamic Type (today shipped 3×). | Real hierarchy + accessibility | Design | M |
| **DV-1 / DV-6 / DV-9** | Spacing + elevation scale with a lint; tokenize remaining color leaks + semantic status colors; tokenize/cache shadows. | Consistent, enforceable system | Design | S–M |
| **CM-3 / DV-7** | Semantic system colors + materials (macOS 26 Liquid Glass-ready), NDS as a thin alias; native translucency on chrome. | Premium native look | CompMacOS, Design | M |
| **CM-4 / CM-6 / CM-7 / CM-5** | One native `.toolbar` with trailing search; native sidebar disclosure groups + badges; native control idioms; hold-⌘ shortcut reveal + type-to-jump. | Feels hand-built for Mac | CompMacOS | M |
| **DV-8 / DL-4** | Density (compact/comfortable) toggle backed by the spacing scale. | User-tunable density | Design, Layout | S |

### Interaction delight
| ID | Item | Impact | Source | Effort |
|---|---|---|---|---|
| **CP-4** | Hover-preview on backlinks + attendee chips (Obsidian/Notion). | Peek without navigating | CompPKM | S–M |
| **DI-7 / DI-6 / DI-5 / DI-4** | Hover-reveal quick actions on rows; drag-and-drop in Tasks + drop-to-import on meetings; two-stage tab transition; persistent progress toast for long jobs. | Alive, responsive feel | Design | M |

### Best-in-class recall & competitive parity
| ID | Item | Impact | Source | Effort |
|---|---|---|---|---|
| **CN-7 / CN-4** | "Ask across all meetings" with cited, deep-linked answers (Fathom/Zoom moat parity, done 100% local); preset "ask this meeting" chips (Zoom Catch-me-up). | Recall parity, privately | CompNotetakers | M |
| **CN-5 / CN-8 / CN-9** | One-click highlight/clip → timestamped & shareable; density/comfort + scannable rows; a visible "instant, offline, no bot" local-first trust strip. | Differentiated polish | CompNotetakers | S–M |
| **CB-4 / CB-5 / CB-2** | Predictive prefetch on hover/selection (Superhuman pre-render); off-main markdown render with cached `AttributedString`; persist `MeetingBodyCache`+thumbnails across launches. | Everything feels pre-loaded | CompPerf | M |
| **CP-6 / CP-8 / TP-10** | Optional two-pane list+detail mode; symmetric backlinks for People/Tasks/Notes; saved smart segments. | Power-user depth | CompPKM, People | M |

---

## 6. How to use this plan
- **Phases are dependency-ordered and each radically improves the app:** P1 makes it *fast & stable*, P2 makes it *one connected native workspace*, P3 makes *each tab excellent & low-click*, P4 makes it *premium & best-in-class*.
- **Performance/caching/crash isn't a phase you finish — it's the Phase-1 spine that every later item inherits** (cache-backed indexes, off-main writes, skeleton-from-snapshot).
- Each item ID resolves to a full write-up (problem, `file:line`, UX impact, perf note, effort) in `audit2/findings/<file>.md`.
- Respect the project workflow (`CLAUDE.md`): `swift build -c release` / `make app` + record→stop→transcribe smoke test before every commit.

## Appendix — item catalog by group
- **Design & Layout:** DV-1…9 (visual), DL-1…8 (layout), DN-1…8 (nav), DI-1…8 (interaction)
- **Per-Tab UX:** TT-1…8 (Today), TM-1…10 (Meetings), TP-1…10 (People), TK-1…10 (Tasks), TS-1…8 (secondary)
- **Integration & Sync:** SD-1…8 (data model), SC-1…8 (consistency), SP-1…8 (propagation)
- **Performance:** PC-1…8 (cold-start), PR-1…8 (runtime), PS-1…8 (stability), PP-1…8 (perceived)
- **Competitive:** CN-1…9 (notetakers), CP-1…8 (PKM), CM-1…7 (macOS), CB-1…8 (perf best-practice)
Full detail: `audit2/findings/*.md`.
