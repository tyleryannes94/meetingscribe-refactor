# G4 Staff Engineer — Memory Usage & Crash-Prevention / Stability

**Lens:** Hunt the things that crash or OOM a *local-first* app the user runs for hours — force-unwraps, unbounded in-RAM collections (full transcripts/photos/chat held in memory), main-thread file I/O that trips the watchdog, off-MainActor mutation of `@MainActor` state, and the long-meeting audio→transcription pipeline. Cross-cutting: bounded/evicting caches serve **both** crash-safety and first-open speed.

## Audit (through my lens)

**The good (verify, don't re-propose).** The pipeline already has real defenses:
- `LiveTranscriber` has **bounded backpressure** — `maxPending = 16`, drops live previews when transcription falls behind, recovers them from merged audio at stop (`LiveTranscriber.swift:48,64-73`). Audio streams to disk incrementally via `AVAssetWriter`/`ChunkedAudioWriter`, not buffered in RAM (`SystemAudioRecorder.swift:217-225`, `ChunkedAudioWriter.swift`). Crash-recovery sweep + crash marker exist (`MeetingManager.swift:124,508`, `AudioRecovery.swift`).
- `MeetingBodyCache` is a real **count-bounded LRU** (cap 64, mtime-fresh, off-main reads, load coalescing) — `MeetingBodyCache.swift:56,219-224`.
- `MeetingStore` index + directory caches are bounded by meeting count and invalidated on write (`MeetingStore.swift:53,61`). `ErrorReporter` funnels catch-blocks into a capped (100) ring + diagnostics (`ErrorReporter.swift:28,33`).
- `try!` / `fatalError` / `preconditionFailure` count in the app source: **zero** (good). Most `!` are `URL(string:literal)!` / `Color(hex:literal)!` constants (safe). The scary-looking `firstIndex(of:".")!` (`NotionMCP/main.swift:343`) is guarded by a preceding `^\d+\.\s` regex match; `loserToKeeper[...]!` (`PeopleStore.swift:914`) is guarded by its `where` clause. No live crash there.

**The risks I'd actually fix:**

1. **Synchronous full-file read inside a list-card body.** `MeetingCard.hasFile("transcript.md")` does `try? String(contentsOf:)` — reading the *entire* transcript (can be 200KB+) **just to test non-empty** — and it's called from the card's `body` at `MeetingCard.swift:255` (`hasFile` at :316-322). In a scrolling Meetings/Today list this is repeated main-thread I/O per row per render → scroll jank now, watchdog-class hangs on a large library with a file scanner intercepting every `open()`. The body cache exists but isn't used here.

2. **`ChatSession.messages` is unbounded** (`ChatSession.swift:17,148,174`). Every turn appends, and the *entire* array (which can carry injected transcript/notes context) is re-sent to the model each `dispatch` (`:170-174,186-192`). A long "ask your vault" session grows RAM and per-turn token cost without bound; nothing trims or summarizes old turns.

3. **Off-`MainActor` mutation path on a `@MainActor` singleton.** `PeopleStore` is `@MainActor` but `init` kicks `load()` onto a global queue (`PeopleStore.swift:60`), and `load()` calls instance methods (`readCache`, `loadPeople`, touches `self.db`) off-main, funneling results back via a `Thread.isMainThread` check (`:248-298`). It works today by convention but is a latent data race the moment a field read sneaks in before `publishLoaded` — exactly the class of bug Swift 6 strict concurrency flags. Same off-main-`self` pattern in `deduplicate`'s cache write (`:926`).

4. **`backlinks(toMeetingID:)` does an unbounded full-corpus scan** — reads *every* meeting's `notes.md` + `summary.md` into Strings to substring-match a link (`WorkspaceIndex.swift:73-90`). It's `Task.detached` (off-main, good) but transient memory is O(total vault text) and it re-reads from disk every call with no cache. On a multi-year vault this is a memory + latency spike.

5. **`ThumbnailCache` bounds by count, not bytes.** `NSCache.countLimit = 256` but no `totalCostLimit` (`ThumbnailCache.swift:12-16`). 256 decoded thumbnails is fine; but cost-limiting is the correct lever and makes it honest under memory pressure.

6. **No crash capture.** `grep` finds no `NSSetUncaughtExceptionHandler` / `signal()` handler anywhere. `ErrorReporter` catches *recoverable* errors only; a hard crash leaves nothing in the diagnostics bundle, so "it crashed" is unreproducible. Plan item E5-4 (crash-report capture) is **not yet built**.

7. **`LiveTranscriber.segments` re-sorts on every append** — `segments.sort` runs inside the per-chunk MainActor hop (`LiveTranscriber.swift:127-128`), O(n log n) each time, and `renderMarkdown` rebuilds the whole string by `+=` (`:176-190`). Minor for ≤~100 chunks, but it's main-actor work that scales with meeting length.

**Test floor:** no stability/regression tests for any of the above (the plan's E5-1/E5-2 harness is still Phase 0 "to build"). Nothing guards the body-cache eviction, the backpressure cap, or the off-main load path.

## NET-NEW recommendations

- **PS-1 — Stop reading whole files to test existence; use a cheap stat + the body cache.**
  *What/why:* Replace `MeetingCard.hasFile` (`:316-322`) with a non-empty **file-size stat** (`attributesOfItem` → `.size > fewBytes`) or a `manager.bodyCache.cachedSummaryPreview`-style sync peek; never `String(contentsOf:)` in a row body.
  *UX:* Smooth scrolling in Meetings/Today; removes per-render hitch.
  *Perf/stability:* Eliminates O(file-size) main-thread I/O per row per render → kills a watchdog-hang vector on large libraries; stat is ~constant-cost. Cache-backed.
  *Effort:* S · *Impact:* High · *Deps:* none.

- **PS-2 — Bound the Chat conversation (sliding window + token-budget guard).**
  *What/why:* Cap `ChatSession.messages` retained context (e.g. last N turns / M tokens), summarize-and-drop older turns before `dispatch` (`ChatSession.swift:148-192`). Hard ceiling on injected per-turn context size.
  *UX:* Long chats stay responsive; no surprise slowdown after 30 turns.
  *Perf/stability:* Caps RAM growth and per-turn token cost → prevents an OOM/latency creep in the headline "Ask your vault" (Phase 2) flow. Eviction = cache discipline.
  *Effort:* M · *Impact:* High · *Deps:* coordinates with C1-1/C2-2 recall work.

- **PS-3 — Add hard crash capture into the diagnostics bundle.**
  *What/why:* Install `NSSetUncaughtExceptionHandler` + a `signal()` handler (SIGABRT/SIGSEGV/SIGILL) at launch (`MeetingScribeApp.startServices`) that writes a last-gasp crash record (thread, reason, recording-in-progress flag) next to `app.log`; surface a "previous run crashed — recover?" banner. Implements the unbuilt E5-4.
  *UX:* A crash becomes a recoverable, reportable event instead of silent loss.
  *Perf/stability:* Pure safety net; near-zero runtime cost. Makes every other stability bug diagnosable.
  *Effort:* S · *Impact:* High · *Deps:* none.

- **PS-4 — Make the off-main `PeopleStore.load()` path race-proof.**
  *What/why:* Move file reads into a `nonisolated static`/free function that takes only `Sendable` inputs and returns a `Sendable` snapshot, then `await MainActor.run` to publish — instead of calling `@MainActor` instance methods off-main and gating with `Thread.isMainThread` (`PeopleStore.swift:60,248-298,926`).
  *UX:* none (invisible) — prevents a hang/garbled-People crash class.
  *Perf/stability:* Removes a latent data race on the people graph the whole product sits on; aligns with Swift 6 concurrency so it can't silently regress. No perf change.
  *Effort:* M · *Impact:* High · *Deps:* none (precursor to E1-1 DI work).

- **PS-5 — Byte-bound the caches (totalCostLimit + body-byte cap).**
  *What/why:* Add `ThumbnailCache.cache.totalCostLimit` and pass `setObject(_,cost:)` with pixel-bytes (`ThumbnailCache.swift:12-24`); add a **total-bytes** ceiling to `MeetingBodyCache` alongside the count cap (`:56,219`) so 64 multi-MB transcripts can't blow past budget.
  *UX:* none directly; keeps the app from being killed under pressure (which reads as a crash).
  *Perf/stability:* Honest memory accounting; NSCache evicts correctly on pressure. First-open stays fast (caches still warm).
  *Effort:* S · *Impact:* Med · *Deps:* none.

- **PS-6 — Cache + bound `backlinks` instead of full-corpus re-scan.**
  *What/why:* Persist a backlink index (or reuse the FTS5 `vault_content` table the briefing notes already ships) so `backlinks` (`WorkspaceIndex.swift:73-90`) is a query, not an N-file read; cap any fallback scan to a recency window.
  *UX:* Instant "linked from" instead of a spike when opening a meeting.
  *Perf/stability:* Removes an O(total-vault-text) transient memory + latency spike on large vaults. Cache-backed (ties to C2-1 FTS5 re-wire).
  *Effort:* M · *Impact:* Med · *Deps:* C2-1 (FTS5).

- **PS-7 — Coalesce live-transcript updates; insert sorted instead of re-sorting.**
  *What/why:* Replace `segments.append` + full `segments.sort` (`LiveTranscriber.swift:127-128`) with an ordered insert, and batch UI publishes (e.g. coalesce within a runloop tick) to cut main-actor churn during long meetings; build `renderMarkdown` once at finalize.
  *UX:* Live pane stays smooth in hour-plus meetings.
  *Perf/stability:* Drops main-actor CPU from O(n log n)/chunk to O(log n); fewer SwiftUI invalidations. (Overlaps plan E2-10 "coalesce live-transcript re-renders" but adds the sort fix.)
  *Effort:* S · *Impact:* Med · *Deps:* none.

- **PS-8 — Stand up a stability test floor for the above.**
  *What/why:* Unit tests for `MeetingBodyCache` eviction + byte cap, `LiveTranscriber` backpressure/drop accounting, `ChatSession` window trim, and a fuzz test feeding a synthetic 4-hour chunk stream to assert bounded RAM. Slots into the unbuilt E5-1/E5-2 harness.
  *UX:* none — guards regressions.
  *Perf/stability:* Locks in every fix above so they can't silently rot; the long-meeting fuzz test is the one that would catch a real OOM.
  *Effort:* M · *Impact:* High · *Deps:* PS-1/2/5/7.

## Top 3 picks

1. **PS-3 — Hard crash capture** → **Phase 1** (foundational/infra). Cheapest way to convert silent crashes into recoverable, diagnosable events; unblocks reproducing everything else.
2. **PS-1 — Kill the synchronous full-transcript read in the card body** → **Phase 1**. Highest-value single fix: removes a real main-thread-hang / scroll-jank vector and is purely cache/stat-backed (helps load speed too).
3. **PS-4 — Race-proof the off-main `PeopleStore.load()`** → **Phase 1**. Closes a latent data race on the core people graph before the recall/DI work piles on top of it.

**Single highest-value:** PS-1 — it's both the most likely cause of a real user-visible hang/crash on a growing library and a direct first-open/scroll speed win, at S effort.

**Perf/caching insight:** every fix here is cache- or stat-backed, not "do less." The pattern to enforce app-wide: **never read a file body to answer a boolean or a preview** — stat for existence/size, and serve previews from the already-bounded `MeetingBodyCache`. Add **byte** ceilings (not just counts) to every cache so the OS never has to kill the process to reclaim memory — which is the crash the user is actually asking us to prevent.
