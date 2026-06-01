# People / CRM Tab — Senior PM/UX Audit (Round 2)

Lens: treat the People tab as a *compounding relationship CRM* that must stay
sub-second on 1,000+ contacts and feel like one connected workspace with
Meetings/Tasks/Decisions. The single-page Person view, inline editing, embedded
chat, AI suggestions, and multi-select bulk actions already landed (verified in
git: `92f9500`, `8471e18`, `fb72a04`, `f135a3a`, `7d8f1a9`). This audit builds
*past* that.

## Audit (through my lens)

**What's genuinely good (do not re-propose):** list + detail HSplitView with
relevance-ranked default sort, FTS5-backed search (`PeopleStore.swift:1166`),
ghost-contact hiding, AND tag filtering, multi-select bulk tag/merge/delete
(`PeopleListView.swift:252`), inline identity+contact editing
(`PersonDetailView.swift:293`), actionable mailto/tel rows (`:967`), unified
meeting timeline merging recorded + calendar (`:821`), cross-tab person↔task
links via `ownerPersonID` (`:1037`), embedded chat column (`:758`), AI
suggestions (`:559`). Store loads off-main and writes a combined cache for next
launch (`PeopleStore.swift:53-75`) — good cold-start hygiene already.

**Perf / stability gaps (the heavy stuff flagged elsewhere is real, plus more):**

- **`person(by:)` is an O(n) linear scan** (`PeopleStore.swift:473-475`). It is
  called constantly: `PersonDetailView.current` re-resolves it on *every* body
  evaluation (`:216`), every relationship row resolves the other end (`:1165`),
  the chat context blob resolves each relationship (`:719`). On a 1,000-person
  graph each detail render is many full-array scans.
- **`encounterCount` is O(encounters)** (`PeopleStore.swift:82`) and is called
  *inside the sort comparator* for the default and "Most meetings" orders
  (`PeopleListView.swift:50`, `PeopleStore.swift:1176-1177`) and once per row for
  ghost filtering (`:1185`). That's O(n·m) per list refresh — a tag toggle or
  add-person re-sorts the whole list synchronously on the main actor.
- **The graph is O(n²) and synchronous on the main actor.**
  `buildGraph` double-loops every pair to build edges
  (`PeopleGraphViewModel.swift:60-72`) then runs a force layout — all on
  `@MainActor`, kicked off in `.onAppear` (`PeopleGraphView.swift:74-79`) with no
  skeleton. At 500+ contacts this is a multi-hundred-ms (or worse) main-thread
  stall the moment you tap the graph icon. The view itself acknowledges it's
  "rarely useful with 500+ contacts" (`PeopleListView.swift:181-186`).
- **Graph nodes bypass ThumbnailCache.** `PersonNodeView.avatar` uses raw
  `AsyncImage(url:)` on the *full-resolution* photo (`PersonNodeView.swift:106`),
  decoding a full image per node — the exact pattern ThumbnailCache was built to
  kill. ThumbnailCache is only wired into the detail photo strip
  (`PersonDetailView.swift:954`).
- **ThumbnailCache decode is synchronous on the calling (main) thread.**
  `thumbnail(at:)` does the ImageIO downsample inline on a cache miss
  (`ThumbnailCache.swift:18-24`); first scroll past N uncached photos blocks the
  UI. It's also memory-only (`NSCache`, 256 count) — every cold launch re-decodes.
- **Whole-list `List` with no row identity tuning + per-row recency formatter**
  (`PeopleListView.swift:236`, `PersonRow:468`). Fine now, but the relevance sort
  recomputes on every keystroke-adjacent state change.

**Click-count violations (post-redesign):**

- Logging a *recorded* meeting as an encounter is good (1 click, `:1214`), but
  there's no one-click "log calendar meeting as encounter" on calendar rows
  (`:851` is purely informational).
- "Find path between two people" exists in the graph VM (`findPath`, `:168`) but
  there is **no UI to pick the two endpoints** — the feature is unreachable.
- Reconnect/cadence: the list shows relative recency (`PersonRow:468`) but you
  can't *act* on "gone cold" without opening each person (no inline snooze /
  remind / log).
- No way to jump from a Person straight to "compose follow-up email" — contact
  rows open `mailto:` blank (`:972`), losing the meeting/task context.

## NET-NEW recommendations

### TP-1 — Index-backed `personByID` + cached `encounterCount` (kill the O(n)/O(n²) hot paths)
**What/why:** Maintain a `[String: Person]` dictionary and a
`[String: Int]` encounter-count map in `PeopleStore`, rebuilt on mutation, so
`person(by:)`, the sort comparators, and ghost filtering are O(1) lookups instead
of full scans. `relevanceScore`-based default sort then becomes O(n log n) with
O(1) per-comparison instead of O(n·m).
**UX impact:** Eliminates the synchronous hitch on tag-toggle / add-person /
search on large graphs; list stays interactive. No click change.
**Perf/stability:** Pure win — trades a few KB of dictionaries for removing the
dominant main-thread cost. Cache invalidation is local to existing
mutators (`updatePerson`, `addEncounter`, `mergePeople`). **Foundational.**
**Effort:** S · **Impact:** High · **Deps:** none.

### TP-2 — Async, disk-persisted thumbnail cache used everywhere (list rows + graph nodes)
**What/why:** Make `ThumbnailCache.thumbnail` `async` (decode on a utility queue,
publish back), add a small on-disk cache keyed by `path|maxPixel` so cold launches
don't re-decode, and route **graph node avatars and any list avatar** through it
instead of `AsyncImage` on full-res files (`PersonNodeView.swift:106`).
**UX impact:** Photos fade in via skeleton circles instead of stalling scroll or
graph open; consistent avatar rendering across list, detail, and graph.
**Perf/stability:** Removes synchronous ImageIO decode from the main thread
(`ThumbnailCache.swift:18`); disk cache makes *first open* of a photo-heavy person
instant on the second launch. Bounded memory (existing NSCache) + bounded disk.
**Effort:** S–M · **Impact:** High · **Deps:** none. **Foundational.**

### TP-3 — Background graph build + progressive layout + skeleton
**What/why:** Move `buildGraph`'s O(n²) edge construction and force layout off the
main actor (compute nodes/edges in a detached task, hand back positions), show a
skeleton/spinner while it runs, and **cap the live graph to the filtered/top-N
set** (e.g. the active tag filter or the top ~150 by relevance) with a "show all"
escape hatch. Edge build can also be pruned to tag-sharing pairs first
(`PeopleGraphViewModel.swift:63-66`) before the meeting-overlap pass.
**UX impact:** Tapping the graph icon (`PeopleListView.swift:184`) no longer
freezes the app; graph becomes usable at scale instead of "experimental."
**Perf/stability:** Converts a main-thread stall into an async job; capping N
bounds the O(n²) blowup. Cache the last computed layout per filter so re-entry is
instant.
**Effort:** M · **Impact:** High · **Deps:** TP-1 (fast person lookup).

### TP-4 — "Find path between people" UI (surface the dead VM feature)
**What/why:** `findPath` BFS already exists (`PeopleGraphViewModel.swift:168`) but
has no entry point. Add a graph toolbar control: pick A, pick B → highlight the
shortest intro path. This is the killer "who can introduce me to X" CRM move.
**UX impact:** Net-new capability; 2 clicks (pick two nodes) to a warm-intro path.
**Perf/stability:** BFS over the in-memory edge list is cheap; runs on the already-
built graph. No new load cost.
**Effort:** S · **Impact:** Med · **Deps:** TP-3.

### TP-5 — Person → Decisions/Commitments section (close the last cross-tab loop)
**What/why:** The Person page syncs meetings (`:821`) and tasks (`:1068`) but the
Decisions & Commitments ledger (shipped in V4) is invisible here. Add a
"Decisions & commitments" section listing ledger entries where this person is
owner/counterparty, each clickable into the Decisions tab, with an inline "add
commitment" — mirroring the tasks section.
**UX impact:** Completes person↔meetings↔tasks↔decisions parity; "what do I
owe / am owed by this person" answerable in 0 extra clicks on the page.
**Perf/stability:** Reuse the same owner-token matching as tasks
(`PersonDetailView.swift:1023`); back it with a precomputed person→entity index
(see TP-7) so it's O(1) not a full ledger scan per render.
**Effort:** M · **Impact:** High · **Deps:** TP-7.

### TP-6 — Contextual follow-up: "Email/Message with context" from the page
**What/why:** Today email rows open a blank `mailto:` (`:972`). Add a single
"Follow up" action on the identity panel that drafts a mail (or chat message) with
the last meeting title/date and open tasks pre-filled in the body — using the
already-loaded `calendarMeetings`, `personTasks`, and recorded meetings.
**UX impact:** From "open person" → follow-up draft in **2 clicks** vs. today's
read-context → switch app → retype (5+ steps).
**Perf/stability:** Pure string assembly from already-in-memory data; no new load.
**Effort:** S–M · **Impact:** Med · **Deps:** none.

### TP-7 — Reverse person→entity index (one place, feeds tasks/decisions/mentions/timeline)
**What/why:** Right now each Person render re-scans `actionItems.items`
(`:1051`), `manager.pastMeetings` (`:822`), and would re-scan the ledger for
TP-5. Build a single persisted reverse index (person id → meeting ids, task ids,
decision ids, encounter ids), updated on write, so every cross-tab section is an
O(1) fetch and edits in any tab reflect instantly here (and vice-versa).
**UX impact:** "Tag a person → updates list + meeting + tasks" and the inverse
become guaranteed-consistent and instant; no perceptible lag opening a heavily-
connected person.
**Perf/stability:** Removes repeated full-collection scans from every detail
render; persist alongside the existing combined cache (`PeopleStore.swift:65`) so
first open after launch is already populated.
**Effort:** M · **Impact:** High · **Deps:** TP-1. **Foundational.**

### TP-8 — Reconnect / cadence actions inline in the list (act on "gone cold")
**What/why:** The list surfaces recency (`PersonRow:468`) and PeopleInsights has a
reconnect card, but you can't act without opening each person. Add a row hover/
swipe affordance: "Log touch", "Snooze", "Set cadence" — and a saved "Needs
attention" smart filter chip alongside the tag chips (`:368`).
**UX impact:** Triage a stale relationship in **1 click** from the list instead of
open → scroll → add encounter (3+ clicks).
**Perf/stability:** Cadence/last-touch reads come from TP-7 index; smart-filter is
a predicate over the already-loaded array. Keep the row light (no extra image
decode).
**Effort:** M · **Impact:** Med · **Deps:** TP-7, P2-1 (truthful `lastInteractionAt`).

### TP-9 — Collapsible, lazy section scaffold for the 14-section person page
**What/why:** `PersonDetailView.body` eagerly builds ~14 sections every render
(`:230-247`); heavy ones (messages stats, AI suggestions, meeting history,
attached notes) all evaluate even when scrolled offscreen. Wrap sections in
`LazyVStack` + remember-collapsed state, and defer the messages/AI sections until
expanded.
**UX impact:** Faster person open, less scroll fatigue on a long page; user
controls density (modern CRM pattern).
**Perf/stability:** `LazyVStack` defers offscreen section construction; deferring
messages avoids touching the chat.db until asked. Persist collapse state per
section so the layout the user prefers is instant next time.
**Effort:** S–M · **Impact:** Med · **Deps:** none.

### TP-10 — Saved smart segments (persisted multi-tag + recency views)
**What/why:** AND tag-filtering is per-session (`PeopleListView.swift:15`). Let
users *save* a filter combo ("Purple Party 2026 + cold > 90d") as a named segment
chip. Modern CRMs live on saved views.
**UX impact:** Re-run a complex filter in 1 click vs. re-selecting chips each time.
**Perf/stability:** Stored as `@AppStorage`/JSON predicates, evaluated over the
in-memory array — trivial cost. No load impact.
**Effort:** S · **Impact:** Med · **Deps:** TP-1.

## Top 3 picks

1. **TP-1 — Index-backed lookups + cached encounter counts.** Highest conviction:
   it removes the dominant main-thread cost behind every list refresh and detail
   render, and unblocks TP-3/5/7/8. **Phase 1 (foundational/perf).**
2. **TP-2 — Async, disk-persisted thumbnail cache used everywhere (incl. graph
   nodes).** Fixes the flagged synchronous ThumbnailCache decode *and* the graph's
   full-res `AsyncImage` bypass, and speeds first open on relaunch. **Phase 1.**
3. **TP-7 — Reverse person→entity index.** The keystone for true tab integration:
   makes tasks/decisions/meetings/mentions O(1) and guarantees edits sync both
   ways instantly. Enables TP-5 and TP-8. **Phase 2 (integration foundation).**

Then: TP-3/TP-9 in Phase 2 (perf-aware UX), TP-5/TP-6 in Phase 3 (cross-tab
completeness), TP-4/TP-8/TP-10 in Phase 4 (higher-level relationship intelligence).
