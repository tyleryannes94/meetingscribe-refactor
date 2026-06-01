# G4 Staff Engineer — Cold-Start / First-Open Load Time & Caching Strategy

**Lens:** What happens between process launch and the first *interactive, populated* paint — and how to make that paint come from persisted cache, instantly, then refresh in the background. Everything tied to load/runtime/memory/crash.

---

## Audit (through my lens)

### The launch path, step by step
`MeetingScribeApp.body` (`MeetingScribeApp.swift:25`) constructs **8 `@StateObject`s eagerly** (`CalendarService`, `MeetingManager`, `NotificationManager`, `AppDetector`, `FloatingOverlayController`, `ChatSession`, `UpdaterController`, `VaultMigrationManager`, `WorkspaceRouter`) plus injects `PeopleStore.shared`, `PeopleTagStore.shared` into the environment (`:34-35`). All of these initializers run **before the first frame**.

`startServices()` (`:155-218`) is already well-disciplined: it documents a "FAST PATH" (callback wiring, hotkey, cheap UserDefaults migrations) and pushes everything heavy to `Task.detached` — keychain migration (`:188`), Ollama probe (`:195`), orphaned-chunk cleanup (`:202`), calendar timer deferred 800ms (`:222`), and a body-cache prefetch deferred 600ms (`:214`). `manager.store.preloadIndex()` (`:183`) warms the meeting index off-main. **This is genuinely good** — the prior audits already did the obvious "get work off the launch thread" pass.

### What's already cached (verify-in-code — do NOT re-propose)
- **Meeting index:** `MeetingStore` keeps an in-memory `_indexMemoryCache` (`MeetingStore.swift:61`) + on-disk `.meeting-index.json` (`:419`), layered 3 ways (`listPastMeetings` `:427`). `preloadIndex()` warms it off-main (`:338`).
- **Upcoming calendar:** `CalendarService` reads `.upcoming-cache.json` **off-main in `init`** and publishes last session's list (`CalendarService.swift:37-51`) — the *one* place that already does cache-first render. 30s TTL on EventKit (`:95`).
- **People graph:** `PeopleStore` reads a single combined `_people-cache.json` (`PeopleStore.swift:248-269`) instead of thousands of `person.json` files, loads off-main, debounced rewrite (`:65-74`).
- **Action items / projects / labels / sections / initiatives:** `ActionItemStore.init` decodes 5 JSON files off-main, publishes back (`ActionItemStore.swift:41-55`).
- **Meeting bodies:** `MeetingBodyCache` (64-entry LRU, mtime freshness, in-flight coalescing) (`MeetingBodyCache.swift`). Prefetch top-10 (`:110`).
- **Photos:** `ThumbnailCache` (downsampled, decoded-image cache).
- **`_recent.json`** stub for the iPhone picker (`MeetingStore.swift:223`).

### The gaps that still make first-open feel slow / empty
1. **SQLite opens synchronously on the launch thread.** `PeopleStore.shared` is built in `MeetingScribeApp.body` (`:34`), and `PeopleStore` has `private let db = SecondBrainDB()` (`PeopleStore.swift:50`), whose `init { open() }` (`SecondBrainDB.swift:50`) runs `sqlite3_open` → `PRAGMA journal_mode=WAL` → `PRAGMA quick_check` → `ensureSchema()` **all on main, before first paint.** On a cold disk / scanner-intercepted file open, `quick_check` walks the whole db file. This is the single remaining hard-synchronous disk-bound item on the launch path. (The comment at `:48-52` says the db is "NOT touched during init" — but *opening* it is, and `quick_check` reads pages.)

2. **No store renders cache-first on the *first frame*.** Every store starts with empty `@Published` arrays and async-fills. Only `CalendarService` warms from cache in `init` — but even that publishes *after* an off-main `Data(contentsOf:)`, so the first frame is still empty for a beat. `MeetingManager.pastMeetings` (`MeetingManager.swift:31`), `ActionItemStore.items`, `PeopleStore.people` all paint **empty** on frame 1, then pop in. There are **no skeletons** — `TodayView` (`TodayView.swift:28`) renders its feed against empty arrays, so first open is a flash of blank widgets, not a perceived-instant populated screen.

3. **`TodayView.onAppear` fires 8 calls** (`:31-39`): 2 refreshes + 6 `backfill*IfNeeded()` passes (action items, people, search index, embeddings, decisions). Each is individually guarded, but they all kick on the very first appear, competing with first-paint settling. No staggering like `startServices` uses.

4. **Caches are ad-hoc and uncoordinated.** Five different files (`.meeting-index.json`, `.upcoming-cache.json`, `_people-cache.json`, `action_items.json`+4, `_recent.json`), three different encoders/versioning conventions, no shared TTL/eviction/atomic-write/corruption-recovery layer, no single "is this cache valid for this vault revision" gate. `SecondBrainDB` has corruption recovery (`quick_check` → delete+rebuild, `:61-67`); the JSON caches have **none** — a truncated `_people-cache.json` from a mid-write crash decodes to `nil` and silently falls back to the minutes-long per-file scan (`:256`).

5. **Cold-start has no measurement.** `MetricsStore` exists but records no `timeToInteractive` / `firstPaint` metric. We're optimizing blind.

---

## NET-NEW recommendations

### PC-1 — Cache-first "Launch Snapshot": render last-session UI on frame 0
**What/why:** Persist one small `launch-snapshot.json` at the vault root containing exactly what the **first screen (Today)** needs: today's meetings, top ~20 recent meetings (id/title/date/summary-preview), open action-item count + top 5, people count. Write it on every quit/resign-active and after each pipeline finish. On launch, **synchronously** read it (it's a few KB) *before* the heavier per-store caches and seed the stores' `@Published` arrays so Today paints fully populated on frame 0; the real store loads then reconcile in the background. This is the cache-first render pattern the briefing asks for — instant populated first open instead of empty-then-pop.
**UX impact:** First open: blank flash → fully populated Today. Perceived launch "instant."
**Perf/stability:** A few-KB synchronous read is cheaper than the current empty-paint-then-async-reconcile churn (which re-lays-out the whole feed when each store fills). Snapshot is derived/disposable; corrupt → ignore and fall through to existing caches. Memory negligible.
**Effort:** M · **Impact:** High · **Deps:** PC-3 (shared cache layer) ideal but not required.

### PC-2 — Move `SecondBrainDB` open + `quick_check` off the launch thread
**What/why:** `PeopleStore.shared` constructs `SecondBrainDB()` synchronously during `MeetingScribeApp.body` (`PeopleStore.swift:50`), running `sqlite3_open`/`quick_check`/`ensureSchema` on main before first paint (`SecondBrainDB.swift:50-68`). Make `db` lazy / open inside the existing off-main `load()` (`PeopleStore.swift:60`), or behind a `Task.detached`. The People tab already builds the index lazily via `rebuildIndexIfNeeded()` (`:90`), so nothing on the launch path needs the open db.
**UX impact:** None visible — removes a stall.
**Perf/stability:** Removes the last hard-synchronous disk-bound item from the launch thread. `quick_check` page-walk no longer blocks first paint. No correctness change (recovery logic still runs, just off-main).
**Effort:** S · **Impact:** High · **Deps:** none.

### PC-3 — Shared `VaultCache` layer (atomic write, versioning, TTL, corruption recovery)
**What/why:** Collapse the five ad-hoc caches behind one tiny actor: typed `read<T>(key)`/`write<T>(key,_,ttl)`, atomic temp-file rename, schema-version + vault-revision stamp, and `quick_check`-style "decode failed → discard, don't crash" recovery (the JSON caches lack this today; only SQLite has it). Each store keeps its own cache *contents*; they share the *mechanics*.
**UX impact:** Indirect — fewer "People looks empty after relaunch" incidents (the failure mode the `:244-247` comment describes).
**Perf/stability:** One audited atomic-write path eliminates the truncated-cache-on-crash class of bug. Centralizes invalidation so a vault-path change clears everything consistently. Low memory.
**Effort:** M · **Impact:** High · **Deps:** none; PC-1/PC-4 ride on it.

### PC-4 — Skeleton loading states keyed on `loadedAt`, not array emptiness
**What/why:** Today/Meetings/People/Tasks currently render against empty arrays with no distinction between "empty vault" and "not loaded yet." Add a per-store `hasLoadedOnce` flag and render shimmer skeleton rows (matching final row geometry) until first load completes. Pair with PC-1 so skeletons only appear on true first run (no snapshot yet).
**UX impact:** Eliminates blank-flash + layout-jump on first open; "empty vault" gets the real actionable empty state instead of looking like a stuck load.
**Perf/stability:** Skeletons are cheap static views; they *reduce* re-layout cost vs. populating an empty list. No disk.
**Effort:** M · **Impact:** Med · **Deps:** PC-1.

### PC-5 — Stagger `TodayView.onAppear` backfills off the first-paint frame
**What/why:** `TodayView.onAppear` (`:31-39`) fires 8 calls synchronously on first appear, including 6 `backfill*IfNeeded()` passes (search index, embeddings, people, decisions) that compete with paint settling. Move the backfills behind a single `Task` with the same `~600-800ms` deferral `startServices` already uses (`MeetingScribeApp.swift:214,222`), and run them sequentially at `.utility`.
**UX impact:** Smoother first scroll/interaction on Today.
**Perf/stability:** Backfills are the heaviest first-appear work (embeddings touch Ollama, search index walks meetings). Deferring them protects the first interactive frame; guards already prevent re-runs.
**Effort:** S · **Impact:** Med · **Deps:** none.

### PC-6 — Persist the meeting-body prefetch as a warm-on-launch summary cache
**What/why:** `MeetingBodyCache` is in-memory only (`MeetingBodyCache.swift:58`), so the top-10 prefetch (`MeetingScribeApp.swift:214`) re-reads from disk every launch. Persist a slim `summary-previews.json` (id → first-sentence preview + mtime) so list rows in Meetings/Today show real summary previews on frame 0 instead of date/attendee fallback (`cachedSummaryPreview` returns nil when cold, `:83`). Refresh entries whose mtime changed.
**UX impact:** Meeting/Today cards show their AI summary preview immediately on first open, not after a click-warm.
**Perf/stability:** A few KB; rides PC-3's atomic writer. Avoids 10 file reads on every launch. mtime check keeps it truthful.
**Effort:** S · **Impact:** Med · **Deps:** PC-3.

### PC-7 — Instrument cold-start in `MetricsStore` (local-only)
**What/why:** Record `launchToFirstPaint` and `launchToInteractive` (first populated Today) into the existing opt-in `MetricsStore`. We're tuning launch with zero numbers today.
**UX impact:** None directly; enables data-driven tuning + a "slow launch" self-diagnostic.
**Perf/stability:** Two timestamps; negligible. Lets us *prove* PC-1/PC-2 wins and catch regressions.
**Effort:** S · **Impact:** Med · **Deps:** none.

### PC-8 — Lazy-construct non-first-screen `@StateObject`s
**What/why:** `UpdaterController`, `ChatSession`, `FloatingOverlayController`, `AppDetector` are all built eagerly in `body` (`MeetingScribeApp.swift:13-17`) though none is needed for the Today first paint. Defer the ones whose `init` does real work (verify each) to first use / a post-launch `Task`, or make their heavy setup lazy.
**UX impact:** None visible.
**Perf/stability:** Shrinks the synchronous init chain on the launch thread. Audit each init first — several may already be trivial; only defer the ones that touch disk/network/timers.
**Effort:** M · **Impact:** Med · **Deps:** none.

---

## Top 3 picks

1. **PC-1 — Launch Snapshot (cache-first frame-0 render).** *(Phase 1)* The headline win and exactly the briefing's ask: first open paints a fully populated Today from a few-KB cache, then reconciles. Highest perceived-speed impact.
2. **PC-2 — Move `SecondBrainDB` open off the launch thread.** *(Phase 1)* Smallest effort, removes the last hard-synchronous disk-bound item still on the launch path. Pure win.
3. **PC-3 — Shared `VaultCache` layer.** *(Phase 1)* The foundational infra that makes PC-1/PC-4/PC-6 safe and consistent, and finally gives the JSON caches the crash-recovery the SQLite layer already has.

All three are Phase 1 (foundational caching). PC-4/PC-5/PC-6 land in Phase 2 (perceived-speed polish on the foundation); PC-7/PC-8 fold in alongside.

**Highest-value single recommendation:** PC-1 — render last-session state from a persisted snapshot on frame 0, then refresh. **Key caching insight:** the app already does the hard part (everything's off-main, every store has *a* cache) — but it caches for the *second* read, not the *first paint*. The missing pattern is a single small snapshot read synchronously-enough to seed `@Published` state before the first frame, plus skeletons for true cold runs; that converts an empty-then-pop launch into an instant-populated one without adding launch-thread disk work.
