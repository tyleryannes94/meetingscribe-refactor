# G5 Competitive/Industry — Performance & Caching (instant-load, cache-first, crash-safe)

> Lens: how do the speed leaders (Superhuman <100ms ethos, Linear's in-memory sync engine, SwiftUI/WWDC25 guidance, SQLite tuning) achieve *instant* first-open and navigation, and what does MeetingScribe need to match them? Every recommendation is cache-backed and stability-aware.

## Audit (through my lens)

MeetingScribe already has a genuinely good caching spine — better than most local apps at this stage. Verified in live source:

- **MeetingBodyCache** (`Storage/MeetingBodyCache.swift`): 64-entry LRU, mtime-freshness, in-flight coalescing, sync `cached()` for instant first paint + async `load()`. Detail view consumes it correctly (`MeetingDetailViewModel.swift:47-69` — sync snapshot then background refresh, with cancellation). This is exactly the cache-first pattern Vercel/Next describe for "render optimistically, then reconcile."
- **MeetingStore** has a layered index cache: in-memory list → on-disk `.meeting-index.json` → disk scan (`listPastMeetings` `MeetingStore.swift:427-439`), plus an O(1) `relativeFolderPath` directory cache that self-heals back into `meeting.json` (`directory(for:)` :114-156). `preloadIndex()` (:338) primes it on a detached task at launch.
- **ThumbnailCache** (`UI/ThumbnailCache.swift`): ImageIO downsample → NSCache(256). Correct decode-cost reduction.
- **Launch** (`MeetingScribeApp.swift:155-218`) is well-staged: synchronous fast-path = only callback wiring + hotkeys; everything heavy (index preload, keychain, Ollama, body prefetch at +600ms, calendar at +800ms) is deferred/detached. Good.
- Lists use `LazyVStack`/`ForEach` (`MeetingsView.swift:154`) — lazy, but the grouped section header pattern can still over-instantiate.

**Gaps vs. the speed leaders:**

1. **Caches are RAM-only and rebuilt every cold launch.** `MeetingBodyCache` and `ThumbnailCache` start empty on every relaunch; the body prefetch is gated behind a 600ms sleep (`MeetingScribeApp.swift:215`). The *first* open of the first tab after a cold start therefore still hits disk/JSON. Linear's whole trick is that the data is *already there* on startup ([performance.dev](https://performance.dev/how-is-linear-so-fast-a-technical-breakdown)) — there's no equivalent persisted snapshot here for the first paint.
2. **SQLite (`SecondBrainDB.swift:75-81`) is under-tuned.** Only `journal_mode=WAL` is set. No `synchronous=NORMAL`, no `mmap_size`, no `cache_size`, no `temp_store=memory`, no `busy_timeout` — i.e. the default ~2MB page cache and syscall I/O. The Messages reader (`MessagesAnalyzer.swift:50`) opens read-only with zero pragmas. The recommended production set is precisely these knobs ([phiresky](https://phiresky.github.io/blog/2020/sqlite-performance-tuning/), [oneuptime](https://oneuptime.com/blog/post/2026-02-02-sqlite-production-setup/view)).
3. **No predictive prefetch.** Bodies are prefetched as a static top-10 (`MeetingManager.swift:692`); nothing prefetches *on hover / selection-change* the way Superhuman pre-renders the thread you're about to open ([Superhuman](https://blog.superhuman.com/superhuman-is-built-for-speed/)).
4. **No persisted UI snapshot.** First frame of Today/Meetings has nothing to render until the index task resolves — no skeleton-from-last-session.
5. **Crash resilience is partial.** SQLite has `quick_check` + auto-rebuild (good, :84-105), but the JSON index/body writes rely on `coordinatedWrite`; there's no write-ahead journal for the multi-minute finalize (acknowledged as E3-3 in the plan) and no startup integrity sweep for the markdown vault.
6. **Markdown→AttributedString parsing is synchronous on the main thread** (`MeetingTranscriptTab.swift:184` flags it) — a hitch on large transcripts.

## NET-NEW recommendations

### CB-1 — Persisted disk snapshot for instant first paint (the "Linear startup" move)
**What/why:** Serialize a small `launch-snapshot.json` (or a `kv` table in SQLite) holding the last-rendered Today + Meetings list rows (id, title, date, attendee count, primary tag, 1-line summary preview) and write it on quit/background. On next cold launch, render that snapshot **synchronously in the first frame**, before the index task resolves — exactly Linear's "data already in IndexedDB at startup" pattern ([performance.dev](https://performance.dev/how-is-linear-so-fast-a-technical-breakdown), [QCon SF 2025](https://qconsf.com/presentation/nov2025/why-fetch-when-you-can-sync-building-local-first-apps-sync-engine-architecture)). Reconcile against the real index when it lands.
**UX impact:** First tab is visually complete at 0ms instead of after the detached index task (currently a brief empty/loading window). Click-to-content unchanged but *first open* feels instant.
**Perf/stability:** Pure win — one tiny JSON read on the fast path (kept <30KB). Snapshot is advisory, never authoritative, so a stale/corrupt snapshot can't lose data (fall through to index). Write atomically.
**Effort:** M · **Impact:** High · **Deps:** none (reuses MeetingStore index shape)

### CB-2 — Persist MeetingBodyCache + thumbnails across launches (warm cache on disk)
**What/why:** Back the hot body cache and thumbnail cache with a disk tier (`Caches/bodies/*.json`, `Caches/thumbs/*`). On launch, hydrate the top-N most-recent entries from this disk tier synchronously-ish (off-main but immediate) instead of re-reading source markdown + re-decoding images. Mirrors Linear/Next's service-worker cache-first navigation ([performance.dev](https://performance.dev/how-is-linear-so-fast-a-technical-breakdown)).
**UX impact:** First click into a recent meeting after relaunch comes from RAM/local cache, not a cold disk read of a 200KB transcript.
**Perf/stability:** Lower cold-start disk pressure; keep mtime check so source-of-truth edits still win. Cache is disposable — corruption just triggers a re-read. Cap disk size (LRU prune to ~50MB).
**Effort:** M · **Impact:** High · **Deps:** CB-1 (shared snapshot infra)

### CB-3 — SQLite production pragma profile
**What/why:** On every connection open (`SecondBrainDB.openConnection` :75, and the read-only Messages opens), set `synchronous=NORMAL; mmap_size=268435456; cache_size=-65536; temp_store=memory; busy_timeout=5000; wal_autocheckpoint=512`. These are the standard production knobs ([phiresky](https://phiresky.github.io/blog/2020/sqlite-performance-tuning/), [calmops](https://calmops.com/database/sqlite/sqlite-ops/), [sqlite.org/pragma](https://sqlite.org/pragma.html)).
**UX impact:** Faster FTS5 search and people-graph queries (the recall moat in Phase 2 leans on this).
**Perf/stability:** Big read win, ~64MB cache + 256MB mmap is fine for an M2. `synchronous=NORMAL` under WAL keeps atomicity/consistency, accepts a tiny last-commit-loss-on-power-cut risk — acceptable for a derived index that can be rebuilt (already has `quick_check` auto-rebuild). Add `busy_timeout` to remove lock-contention crashes.
**Effort:** S · **Impact:** High · **Deps:** none

### CB-4 — Predictive prefetch on selection/hover (Superhuman pre-render)
**What/why:** When a meeting row is hovered or becomes selected in a list, fire `MeetingBodyCache.load()` for it *and* its visible neighbors, and pre-parse the summary markdown to `AttributedString` off-main. Superhuman preloads/pre-renders the next likely thread; navigation from a list can be made instant by rendering with predicted data ([Superhuman](https://blog.superhuman.com/superhuman-is-built-for-speed/), [Vercel](https://vercel.com/kb/guide/optimizing-hard-navigations)).
**UX impact:** Click-into-detail (currently sync-cache-then-async) becomes fully warm — the open is the cache hit, not the disk read.
**Perf/stability:** Bounded (only hovered ± neighbors), `.utility` priority, coalesced by existing in-flight map. No memory blowup (LRU cap holds).
**Effort:** S · **Impact:** Med · **Deps:** CB-2

### CB-5 — Off-main markdown rendering + cached AttributedString
**What/why:** `MeetingTranscriptTab.swift:184` notes `AttributedString(markdown:)` blocks synchronously. Move parsing to a background task and cache the parsed `AttributedString` keyed by (meetingID, field, mtime) inside MeetingBodyCache. WWDC25's SwiftUI guidance is explicit: keep `body` lightweight, precompute formatted values, never do heavy work in view body ([Apple](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance), [WWDC25/306](https://developer.apple.com/videos/play/wwdc2025/306/)).
**UX impact:** No hitch opening a long transcript/summary; scrolling stays at 120Hz.
**Perf/stability:** Removes a main-thread hang class. Parsed cache is small relative to the source text already held.
**Effort:** M · **Impact:** Med · **Deps:** CB-2

### CB-6 — Vault write-ahead journal + startup resume/integrity sweep (crash safety)
**What/why:** Extend the planned E3-3 finalize journal into a general "pending vault op" log: before a multi-step write (finalize, retag/folder-move `moveMeeting` :356, index rewrite), append an intent record; clear it on success. On launch, replay/rollback any incomplete op and run a fast vault sanity sweep (does each indexed meeting's dir exist?). WAL's core guarantee — log the change before applying it, replay on crash — is the standard atomicity/durability mechanism ([Wikipedia WAL](https://en.wikipedia.org/wiki/Write-ahead_logging), [PostgreSQL WAL](https://www.postgresql.org/docs/current/wal-intro.html)).
**UX impact:** A crash mid-finalize or mid-retag resumes instead of stranding/losing a meeting — directly protects the capture promise.
**Perf/stability:** Append-only journal is cheap; the startup sweep is bounded by meeting count and runs detached. Highest *stability* leverage item.
**Effort:** M · **Impact:** High · **Deps:** none (complements E3-3/E3-4)

### CB-7 — Skeleton-from-snapshot loading states (perceived speed)
**What/why:** Where data isn't yet warm, render skeleton rows shaped by the CB-1 snapshot's row count/sizes rather than a spinner. Speed leaders minimize spinners and animations because motion *costs* perceived time ([Superhuman](https://blog.superhuman.com/superhuman-is-built-for-speed/)); skeletons + optimistic fills read as instant ([Vercel](https://vercel.com/kb/guide/optimizing-hard-navigations)).
**UX impact:** No "blank then pop" on any tab; perceived load drops below the 100ms feel-threshold.
**Perf/stability:** Cheap; skeletons are static shapes. Pairs with D5-1 reduce-motion (no `repeatForever` shimmer if reduce-motion is on).
**Effort:** S · **Impact:** Med · **Deps:** CB-1

### CB-8 — Launch-time budget + lightweight perf instrumentation
**What/why:** Add an opt-in, local-only timing harness (signposts via `os_signpost`) around the launch fast-path and first-tab paint, and a debug overlay that reports cold-start ms and cache hit-rates. Superhuman's discipline is *measuring* the % of actions under 100/50ms ([Superhuman performance metrics](https://blog.superhuman.com/performance-metrics-for-blazingly-fast-web-apps/)); WWDC25 ships a dedicated SwiftUI Instrument for exactly this ([WWDC25/306](https://developer.apple.com/videos/play/wwdc2025/306/)).
**UX impact:** Indirect — turns "feels slow" into a tracked regression budget so phases 2-4 features can't silently erode startup.
**Perf/stability:** Signposts are near-zero-cost when not tracing. Ties into the planned P5-1 MetricsStore.
**Effort:** S · **Impact:** Med · **Deps:** P5-1 (MetricsStore, optional)

## Top 3 picks

1. **CB-1 — Persisted launch snapshot for instant first paint.** Highest-leverage instant-open win; the single move that makes MeetingScribe feel like Linear on cold start. **Phase 1 (foundational caching).**
2. **CB-3 — SQLite production pragma profile.** Tiny effort, broad speedup (search/recall/people graph), and removes a lock-contention crash class. **Phase 1.**
3. **CB-6 — Vault write-ahead journal + startup resume sweep.** The crash-resilience keystone that protects captured meetings end-to-end. **Phase 1** (foundational stability; complements Phase 0 correctness fixes).

CB-2 (persisted body/thumb cache) is the natural Phase 1/2 follow-on; CB-4/CB-5/CB-7 (predictive prefetch, off-main markdown, skeletons) land in Phase 2 once the snapshot infra exists; CB-8 sits alongside whenever MetricsStore ships.
