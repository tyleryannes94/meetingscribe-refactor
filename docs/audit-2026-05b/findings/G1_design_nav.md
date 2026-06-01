# Design — Navigation, Information Architecture & Click-Reduction

One-line lens: the tab model, how users move between/within tabs, WorkspaceRouter, deep-linking, back/forward, command palette — getting to any action fast, cheaply, without crashes.

## Audit (through my lens)

The nav shell is in good shape post-V4: a single `WorkspaceRouter` (`WorkspaceRouter.swift:13`) is now the source of truth for `section` + `selectedMeetingID`, and `MainWindow` mirrors it via a computed accessor (`MainWindow.swift:55-58`). Keep-alive tabs render in a ZStack with opacity cross-fade and lazy first-build (`MainWindow.swift:90-106`) — good for perf, and prewarming was deliberately removed (`:220-225`). 5 top-level sections, grouped WORKSPACE / ORGANIZE (`MainWindow.swift:31-42`). `⌘1–⌘5` jump tabs, `⌘K` search, `⌘R`/`⇧⌘R` record, `⇧⌘N`/`⇧⌘P`/`⌘N` create (`MeetingScribeApp.swift:84-124`). Deep links via `meetingscribe://<kind>/<id>` resolved through `onOpenURL` → router (`MeetingScribeApp.swift:54`, `WorkspaceLinks.swift:78`). Command palette (`GlobalSearchView.swift`) merges FTS5 results + a static `allCommands` list (`:370-402`) with hybrid semantic refine (`:242-246`).

Gaps that cost clicks / risk friction:

1. **No global back/forward history.** Once you click a search result → meeting → a backlinked person → that person's meeting, there is *no way back* except re-navigating. `WorkspaceRouter` holds only the *current* `section`/`selectedMeetingID` — no stack. Browsers, Things, Notion all have `⌘[`/`⌘]`. Returning to where you were is currently 2–4 clicks (re-open search, retype, re-select).
2. **No breadcrumb / location indicator in the shell.** The nav rail highlights the tab but within Meetings/Tasks there's no "you are here" trail. `ActionItemsView` has a local `taskBreadcrumb` (`ActionItemsView.swift:115`) but it's tab-private; the workspace has no unified breadcrumb.
3. **Command palette is context-blind.** `allCommands` (`GlobalSearchView.swift:370`) is a fixed global list. When a meeting is open, the palette can't offer "Copy summary", "Add follow-up task", "Open in Obsidian" — those live only in `MeetingDetailHeader`. So an in-meeting action is mouse-hunt, not `⌘K` → type. Briefing target: after opening an entity, every action ≤2 clicks; today many header actions are 1 click but undiscoverable, and palette can't reach them at all.
4. **Per-tab position isn't remembered.** Only `selectedMeetingID` persists (`WorkspaceRouter.swift:27`). Re-entering People/Tasks/Notes drops you to the top / empty detail. `meetings.scope` persists (`MeetingsView.swift:31`) but selection in People/Tasks doesn't — re-selecting a person after a tab hop is +2 clicks every time.
5. **No "recents / jump back" surface.** There's no recently-viewed list anywhere; empty-query `⌘K` shows recent *meetings* only (`GlobalSearchView.swift:213`), not recent people/tasks/notes you actually touched. Getting back to a person you viewed 30s ago = open `⌘K`, switch to People filter, type.
6. **Navigation goes through stringly-typed NotificationCenter.** `⌘1–⌘5` post `.meetingScribeNavigate` with an untyped `object` (`MeetingScribeApp.swift:88`), observed in `MainWindow:419`. Works, but bypasses the router that was just built to be the single surface — and an unhandled/cast-failed object silently no-ops. Centralizing reduces drift and one class of "click did nothing" bugs.
7. **`⌘K` has no in-palette result preview / multi-step.** Selecting a person routes via notification (`WorkspaceRouter.swift:51`) and the People tab must be built + listening; there's a documented one-runloop-hop hack (`MainWindow.swift:431-436`). It works but is fragile on a cold tab.

## NET-NEW recommendations

### DN-1 — Global back/forward navigation stack (`⌘[` / `⌘]`)
**What/why:** Add a bounded (cap ~50) ring buffer of `NavLocation { section, entityKind?, entityID? }` to `WorkspaceRouter`. Every `route()`/`openMeeting()`/`openPerson()` pushes; `⌘[`/`⌘]` and rail back/forward chevrons pop/replay *without* re-running search or FTS. Toolbar shows disabled state at ends.
**UX impact:** Return to prior context: 2–4 clicks (re-search/retype) → **1 keypress**. Makes deep cross-entity exploration (the whole point of the relationship graph) safe to do.
**Perf/stability:** Pure in-memory value structs; replay reuses the already-warm index/body cache (no disk re-read). Cap the buffer to bound memory. Replaying a stale ID that was deleted should fall through to the section (guard like `route`'s existing `else` at `WorkspaceRouter.swift:69`) — no crash.
**Effort:** M **Impact:** High **Deps:** none (router already centralizes selection).

### DN-2 — Contextual command palette (inject the open entity's actions)
**What/why:** Pass the current router context into `GlobalSearchView`; prepend a "This Meeting" / "This Person" command section built from the same closures `MeetingDetailHeader`/Person view already expose (Copy summary, Add follow-up task, Open in Obsidian, Calendar write-back `MeetingDetailHeader.swift:343`). Empty-query palette leads with these.
**UX impact:** Any in-entity action becomes `⌘K` → 2–3 chars → Enter (**≤2 interactions**, keyboard-only) vs hunting a header menu. Directly satisfies the "every action ≤2 clicks after open" rule and makes hidden actions discoverable.
**Perf/stability:** Commands are lightweight structs built lazily on palette open; zero added cost when palette is closed. No new data loads — reuses existing action closures.
**Effort:** M **Impact:** High **Deps:** DN-7 (typed context helps), router context.

### DN-3 — Persist & restore per-tab selection + last position
**What/why:** Extend `WorkspaceRouter` with `selectedPersonID`, `selectedTaskID`/`projectID`, `selectedVoiceNoteID`, persisted like `selectedMeetingID`/`meetings.scope`. On tab re-entry, restore the prior detail instead of empty.
**UX impact:** Tab hop then return to the same person/task: +2 clicks (re-find, re-select) → **0**. The 5 tabs finally feel like one continuous workspace (briefing goal #3).
**Perf/stability:** A few stored UUID strings in UserDefaults; restoring selects an already-loaded row (no extra fetch). Guard against deleted IDs (fall back to empty detail). Negligible memory.
**Effort:** S **Impact:** High **Deps:** DN-7.

### DN-4 — Cache-backed "Recently viewed" rail + empty-`⌘K` recents
**What/why:** Maintain a small persisted MRU list of `WorkspaceEntity`s (last ~15 viewed, any kind) updated on every `route()`. Surface as a collapsible "Recent" group at the top of the nav rail and as the default empty-query content in `⌘K` (replacing meetings-only suggestions at `GlobalSearchView.swift:213`).
**UX impact:** Jump back to anything touched recently: open search → filter → type (3+ clicks) → **1 click / 1 keypress**. Mirrors Things' "Recent" and Slack's quick-switcher.
**Perf/stability:** MRU is ~15 tiny structs persisted to a JSON cache (like `.upcoming-cache.json`); read once at launch into memory, written on change. First-open shows recents instantly from cache — no index scan. Bounded list = bounded memory.
**Effort:** M **Impact:** High **Deps:** DN-7 for entity routing.

### DN-5 — Workspace breadcrumb bar (cheap, shell-level)
**What/why:** A thin breadcrumb above tab content driven by router state: `Section › Entity title` (+ back chevron from DN-1). Reuses titles already in `selectedMeeting`/person/task — no new queries.
**UX impact:** Orientation + a 1-click "up" target; back chevron co-locates DN-1. Reduces "where am I / how do I get out" disorientation in deep detail panes.
**Perf/stability:** Renders from in-memory router state only; no fetch, trivial view. No effect on cold start.
**Effort:** S **Impact:** Med **Deps:** DN-1, DN-7.

### DN-6 — Quick-switcher mode for `⌘K` (type-ahead tab + entity jump, no filter clicks)
**What/why:** Make the palette's first keystrokes match tab names and recents *before* FTS (e.g. "pe" → "Go to People" + recent people already rank top), so navigation needs no filter-pill click (`GlobalSearchView.swift:72-96`). Add `Tab` to cycle filter scopes from the keyboard.
**UX impact:** Tab jump + entity open from one box: filter-pill click + type + select (3) → **type + Enter (1–2)**. Keyboard-first power-user path.
**Perf/stability:** Reorders existing in-memory results; the static command list is already O(n) tiny. Hybrid semantic refine stays gated behind the stale-query guard (`:244`) so fast typing isn't clobbered — no added load.
**Effort:** S **Impact:** Med **Deps:** DN-4.

### DN-7 — Route all navigation through the router (retire stringly NotificationCenter hops)
**What/why:** Replace `.meetingScribeNavigate`/`OpenPerson`/`FilterByTag` posts (`MeetingScribeApp.swift:88`, `WorkspaceRouter.swift:52,90`) with direct typed `router.select(_:)` / `router.open(_:)` calls. Keep notifications only where a not-yet-built tab must self-subscribe, and make those typed.
**UX impact:** Indirect — but eliminates a class of "shortcut did nothing" failures (cast-failed `object` silently no-ops) that read to users as broken clicks. Foundation for DN-1/3/4/5.
**Perf/stability:** Removes a runloop-hop hack (`MainWindow.swift:431-436`) and cross-thread notification churn → fewer race windows on cold tabs (lower crash/no-op risk). No data cost.
**Effort:** M **Impact:** Med **Deps:** none; unblocks the rest.

### DN-8 — Make the nav rail collapsible + keyboard-focusable
**What/why:** Add a `⌥⌘S` toggle to collapse the 240px rail (`MainWindow.swift:165`) to an icon-only 56px strip on narrow windows (it already auto-collapses chat at <860px, `:248`), and `⌃Tab` to move focus between rail / content / chat.
**UX impact:** Reclaims ~184px for content on small screens; keyboard users can traverse panes without the mouse. Native macOS feel (matches Mail/Notes).
**Perf/stability:** Pure layout/state toggle; the ZStack tabs are unaffected. No new allocations.
**Effort:** S **Impact:** Med **Deps:** none.

## Top 3 picks

1. **DN-1 — Global back/forward stack** → **Phase 2.** Highest-conviction: the relationship graph *invites* deep cross-entity hops, but there's no way back. One ring buffer turns a 2–4-click re-navigation into one keypress, entirely from warm cache. Pair with DN-5's back chevron.
2. **DN-7 — Route everything through the router** → **Phase 1 (foundational).** Cheap, removes the fragile notification/runloop-hop hacks, and is the substrate DN-1/3/4/5 build on. Stability + correctness win first.
3. **DN-4 — Cache-backed Recently-viewed** → **Phase 3.** Collapses "get back to what I just looked at" to one click, backed by a tiny persisted MRU cache that also makes first-open `⌘K` instant. (DN-3 per-tab restore is the close runner-up, also Phase 3.)
