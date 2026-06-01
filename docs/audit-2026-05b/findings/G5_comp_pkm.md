# Competitive Analysis — PKM / Second-Brain Navigation & Layout (CP-)

Lens: how Notion, Tana, Reflect, Obsidian, Capacities, Craft, and Linear make a large
knowledge base feel *instantly navigable* — multi-pane layout, link/backlink UX,
command bars, peek/preview, and the caching tricks that keep all of it sub-frame fast.
Every pattern below is tied to MeetingScribe's hard speed/first-open constraint.

## Audit (through my lens)

MeetingScribe's navigation today:

- **5-tab ZStack keep-alive shell, no top-level multi-pane.** `MainWindow.tabContent`
  renders each `TopLevelSection` as a lazily-built, opacity-toggled layer
  (`MainWindow.swift:90-106`). Smart for warmth/perf, but it means you can only ever
  see *one* tab — a person and the meeting that mentions them can never sit side-by-side.
  Tana, Capacities, Obsidian, and Notion all let two related entities coexist.
- **Single router, but every cross-entity jump is a full tab swap.** `WorkspaceRouter`
  is the one good consolidation (`WorkspaceRouter.swift:43-93`): meetings open in the
  Meetings detail, people post a notification to the People tab, etc. But `open(person)`
  *flips the whole window* to People (`:50-54`). There is no "peek" — no way to glance at
  a linked person/meeting without losing your current context. Notion's side-peek and
  Obsidian's hover-preview exist precisely to avoid this.
- **Command palette is a modal, not a command runner.** `GlobalSearchView` is a 620×480
  sheet (`GlobalSearchView.swift:59`) launched from a rail button / ⌘K
  (`MainWindow.swift:144-156`). It searches + navigates with type filters and arrow keys —
  good — but it only *finds and opens*. It can't *act* ("mark task done", "tag person",
  "start recording", "toggle theme"). Linear's ⌘K is navigation **and** every action,
  contextual to the current view. Empty-query state shows recent meetings only, not a
  cross-entity recents/quick-jump list.
- **Backlinks exist but are one-directional and meeting-only.** `UnifiedMeetingDetail`
  loads `backlinks` + `relatedMeetings` lazily ("most expensive, least time-critical",
  `:214-223`) and renders a `backlinksPanel`/`relatedMeetingsPanel`
  (`MeetingNotesTab.swift:29-30`). People/Tasks/Notes have no symmetric backlink surface,
  and there's no on-hover preview of a backlink target — you must click through (a tab swap).
- **No breadcrumb/history spine across tabs.** Tasks have a local breadcrumb
  (`TaskPageView.swift:70-75`, `ActionItemsView.swift:115`) but there's no global
  back/forward or "recently viewed" — once you tab-swap to a person you can't cheaply
  return to the meeting you came from. Obsidian's per-pane history (Pane Relief) and
  browser-style back/forward are the standard fix.

Click reality: opening a person from a meeting = 1 click but **destroys** the meeting
context (full tab swap, no return path). Acting on a found item from ⌘K = open it, *then*
hunt for the control = 2–3 clicks. Both are exactly what the comp set engineers away.

## Competitive patterns (live research, 2026)

- **Tana — List Navigation View (list pane + detail pane).** Click an item in the list
  and its full content opens in the adjacent detail pane; the list stays put while you
  read/edit. Shift-click opens a new panel to the right; tabs switch contexts.
  (https://tana.inc/docs/navigation, https://outliner.tana.inc/docs/navigation)
  Command line (⌘K) sets tags/field values and records custom shortcuts (⌘⇧K) —
  navigation *and* mutation. (https://tana.inc/docs/command-line)
- **Notion — Side-peek / Center-peek + hover preview.** A linked page opens in a thin
  right-side panel (side-peek) or a centered modal (center-peek) *over* your current page,
  so you never lose context; hovering a link/mention previews content before you commit.
  (https://x.com/NotionHQ/status/1716494726445334691,
  https://www.sparxno.com/blog/peek-pages-notion)
- **Obsidian — stacking hover preview + optimized backlinks pane + pane history.**
  Hover any link to preview; previews *stack* (hover a link inside a preview). The
  backlinks pane was optimized so switching files/editing no longer lags, and
  back/forward no longer mangles pane type. (https://help.obsidian.md/Plugins/Page+preview,
  https://obsidian.md/changelog/page/17/, https://github.com/pjeby/pane-relief)
- **Capacities — swap-to-main panels + compressed backlinks + faster startup.** Hover a
  side-panel tab to reveal a "swap" button that moves it into the main panel; backlinks to
  one object collapse into a compressed view; recent releases ship "faster startup &
  loading". (https://docs.capacities.io/reference/navigation,
  https://capacities.io/whats-new/release-44/)
- **Reflect — recency/backlink-weighted ranking + instant open.** Local-first; "opens
  instantly"; the picker prioritizes recently created/updated notes and notes with many
  incoming backlinks so the thing you want is the first hit.
  (https://reflect.app/, https://reflect.app/blog/april-2024-update)
- **Craft — redesigned fluid nav, auto-reciprocal backlinks.** Sidebar spaces with
  Documents/Calendar/Search toggles; any @-mention auto-creates a reciprocal backlink;
  2025 update ships a redesigned, "more fluid and accessible" navigation system.
  (https://www.craft.do/, https://support.craft.do/hc/en-us/articles/360019463958-Links-and-backlinks)
- **Linear — the speed bible.** Database in the client; reads hit an in-memory pool, so
  "click into a project, the issues are there… nothing to fetch." Heaviest tables
  *lazy-hydrate on demand* (data-level code-splitting) so a 10k-issue workspace boots like
  a 100-issue one. Shell tokens (sidebar width, theme) are restored from local storage
  *before* any bundle parses → themed shell on first paint. ⌘K is navigation **and** every
  action, contextual, searching local memory. Animate only `transform`/`opacity`,
  durations <100ms, asymmetric (appear instant, fade out ~150ms).
  (https://performance.dev/how-is-linear-so-fast-a-technical-breakdown)

## NET-NEW recommendations

### CP-1 — Side-peek overlay for cross-entity links (Notion side-peek + Tana detail pane)
**What/why:** Add a single reusable right-side `peek` panel that overlays the current tab
(not a tab swap) when you click a linked person/meeting/task/note. Drives off the existing
`WorkspaceRouter` — add `@Published var peek: WorkspaceEntity?` alongside `selectedMeetingID`;
a backlink/attendee tap sets `peek` instead of calling `openPerson` (which flips tabs).
"Open full" button promotes the peek to its home tab. This is the #1 thing the comp set has
and MeetingScribe lacks: glance at a linked entity without losing where you are.
**UX impact:** view a meeting's attendee → before: 1 click but loses the meeting (full tab
swap, no return); after: 1 click, meeting stays visible, Esc dismisses. Every backlink in
`UnifiedMeetingDetail` becomes a peek, not a context-destroying jump.
**Perf/stability:** the peek renders the *same* lightweight summary view used in lists, not
the full detail — hydrate the heavy body lazily (mirror `UnifiedMeetingDetail`'s "backlinks
last" ordering, `:214`). Cache the last N peeked entities' summaries in a small in-memory LRU
keyed by entity ID so re-peeking is instant. Slide in with `opacity`+`transform` only,
~120ms. No new top-level view kept warm → no cold-start cost.
**Effort:** M **Impact:** High **Deps:** WorkspaceRouter, NDS components.

### CP-2 — Promote ⌘K from "search & open" to a contextual command runner (Linear/Tana)
**What/why:** Extend `GlobalSearchView` with an *action* result class alongside entity
results: "Mark '…' done", "Tag person…", "Start recording", "New voice note", "Toggle dark
mode", "Open Settings". Actions surface contextually (when a meeting is focused, show its
actions first). This collapses the "find it, then hunt for the control" loop.
**UX impact:** mark a found task done — before: ⌘K → open task → find checkbox (3 clicks);
after: ⌘K → type "done" → ↵ (≤2, no mouse). Every common action reachable from one keystroke.
**Perf/stability:** actions are static descriptors + closures; recompute is trivial vs.
entity search which already runs on the in-memory `WorkspaceIndex`. Zero network, zero load
cost. Reuses the existing modal — no new window.
**Effort:** M **Impact:** High **Deps:** CP-3 ranking helps; WorkspaceIndex.

### CP-3 — Recency + backlink-weighted ⌘K empty/zero-query state (Reflect)
**What/why:** Replace "recent meetings only" with a cross-entity quick-jump list ranked by
recency *and* incoming backlink count (the person you opened 5 times this week, the active
project). Add a persisted "recently viewed" ring (last ~20 entity IDs) written by
`WorkspaceRouter.route()`.
**UX impact:** open ⌘K with no query → the thing you want is usually hit #1–3, so navigation
is "⌘K ↵" not "⌘K, type, scan". Big compounding win for daily drivers.
**Perf/stability:** the recents ring is a tiny `[String]` in UserDefaults — read once at
launch, O(1) updates. Backlink counts come from the already-built index; cache the ranked
list and invalidate only on entity open. Negligible memory, no first-open penalty.
**Effort:** S **Impact:** High **Deps:** WorkspaceIndex backlink counts.

### CP-4 — Hover-preview on backlinks & attendee chips (Obsidian/Notion hover preview)
**What/why:** On hover over a backlink, attendee chip, or task link, show a small popover
with the target's title + 2–3 line summary + last-touched date — before any click. Pairs
with CP-1 (hover to glance, click to peek, click "open" to commit) — the exact Notion/
Obsidian ladder.
**UX impact:** disambiguate a link with zero clicks; cuts wrong-click round-trips to backlinks
that turn out not to be the one you wanted.
**Perf/stability:** popover content = the cached summary from CP-1's LRU; fetch on a 300ms
hover-intent delay so scrolling a list never triggers work (Obsidian's optimized-backlinks
lesson: hover/backlink work must not lag the host view). `transform`+`opacity` only.
**Effort:** M **Impact:** Med **Deps:** CP-1 summary cache.

### CP-5 — Global back/forward + breadcrumb spine across tabs (Obsidian Pane Relief)
**What/why:** A navigation history stack in `WorkspaceRouter` (entity + section per entry)
with ⌘[ / ⌘] back/forward and a persistent breadcrumb in the content header. Today only
Tasks have a local breadcrumb (`TaskPageView.swift:70`); there's no cross-tab return path.
**UX impact:** after jumping meeting → person → their other meeting, ⌘[ walks you straight
back. Removes the "how do I get back to where I was" dead-end that the current tab-swap model
creates.
**Perf/stability:** history is an array of value-type entity refs (IDs + kind), capped at ~50
— trivial memory. Re-navigation hits warm tabs (already kept alive) and CP-1's summary cache,
so back/forward is instant. No new rendering surface.
**Effort:** M **Impact:** High **Deps:** WorkspaceRouter, CP-1.

### CP-6 — Optional two-pane "List + Detail" mode for Meetings/People/Tasks (Tana List Nav)
**What/why:** Let the three list-heavy tabs run as a master-list + detail split (Tana's List
Navigation View / Capacities swap-panels) instead of list-then-push. Click a row → detail
fills the right pane, list stays; arrow keys walk the list and the detail follows.
**UX impact:** triage 10 meetings/people — before: open, read, back, open next (4 clicks/item);
after: click once then ↓↓↓ (keyboard, detail auto-follows). Massive for review sessions.
**Perf/stability:** the detail pane reuses the *existing* `UnifiedMeetingDetail`/Person view
— no new view type. Debounce arrow-key selection (~120ms) so holding ↓ doesn't hydrate every
intermediate row's heavy body; only the settled row loads its body (Linear's lazy-hydrate
principle). Make it a per-tab toggle so narrow windows fall back to single-pane.
**Effort:** L **Impact:** High **Deps:** CP-1 plumbing reuse.

### CP-7 — Pre-paint shell restore: theme + last tab before first frame (Linear inline shell)
**What/why:** Linear writes sidebar width/theme to local storage and applies them *before*
any bundle parses, so the shell is correct on the first painted frame. MeetingScribe reads
`lastSelectedSection` and `appearanceDark` from UserDefaults but applies them during view
construction. Hoist these reads to the earliest point in `MeetingScribeApp` launch and render
the nav rail + selected-tab skeleton (not its data) before stores finish loading.
**UX impact:** the window appears already on the right tab, right theme, with a skeleton — no
flash of default/light/Today on cold start. Perceived first-open feels instant.
**Perf/stability:** pure reordering — reads two UserDefaults keys earlier; cost is ~microseconds.
Skeleton is static views (no store dependency), so it paints while `MeetingStore`/index hydrate
in the background. Directly improves the briefing's first-open constraint at ~zero risk.
**Effort:** S **Impact:** High **Deps:** MeetingScribeApp launch path.

### CP-8 — Symmetric backlink surface for People / Tasks / Notes (Craft auto-reciprocal)
**What/why:** Meetings have backlinks (`UnifiedMeetingDetail`/`MeetingNotesTab`) but People,
Tasks, and Voice Notes don't expose a consistent "Linked / Mentioned in" panel. Add the same
compressed backlinks component (Capacities-style grouping) to every entity detail, fed by one
shared `backlinks(to:)` index path.
**UX impact:** from a person, jump to every meeting/task/note that references them in one place
— today you'd cross-search manually. Makes the 5 tabs feel like one connected graph.
**Perf/stability:** build a single reverse-link index once at launch (or incrementally on
write) and persist it next to the body cache, so each detail just looks up its own key — O(1),
no per-open scan. Render the panel last (lowest priority), exactly as the meeting view already
does (`:214`). Cache invalidation is per-entity on edit (Linear's "one delta, one cell").
**Effort:** M **Impact:** Med **Deps:** shared reverse-link index; CP-1 reuses it.

## Top 3 picks

1. **CP-1 — Side-peek overlay (Phase 2).** The single highest-value pattern from the entire
   comp set: every other app lets you glance at a linked entity without losing context;
   MeetingScribe's tab-swap model can't. Unblocks CP-4/CP-5/CP-6. Foundational UX shift,
   cheap because it reuses summary views + an LRU cache.
2. **CP-7 — Pre-paint shell restore (Phase 1).** Pure-perf, near-zero-risk first-open win that
   directly serves the briefing's cold-start constraint — right tab/theme/skeleton on frame 1,
   à la Linear's inline shell. Belongs in the foundational phase.
3. **CP-2 — ⌘K as a contextual command runner (Phase 3).** Turns the existing palette into
   Linear's "one primitive, used everywhere," cutting multi-click action paths to "⌘K ↵" and
   teaching shortcuts as a side effect.

Phase placement: **P1** CP-7, CP-3 (cache/infra + ranking); **P2** CP-1, CP-5, CP-8 (peek +
history + symmetric backlinks — the connected-workspace layer); **P3** CP-2, CP-4 (command
runner + hover preview); **P4** CP-6 (two-pane list/detail — highest-effort, builds on all of it).

Single highest-value: **CP-1 side-peek** — it converts MeetingScribe from five siloed tabs
into one navigable graph, the core thing every PKM leader does and the current ZStack model
structurally prevents.
