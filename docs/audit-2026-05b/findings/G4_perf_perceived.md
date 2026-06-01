# G4 — Perceived Performance (Skeletons, Optimistic UI, Instant-feel)

One-line lens: make every first open and every interaction *feel* instant — render cached/last-known content immediately, show skeletons only when truly cold, apply edits optimistically and reconcile, and never let the UI block on disk or the LLM.

## Audit (through my lens)

The refactor already has a strong perceived-perf foundation — this audit builds *past* it, not over it:

- **Keep-alive tab ZStack with cross-fade is built.** `MainWindow.tabContent` (MainWindow.swift:90-106) keeps each visited section in the hierarchy, toggles via `.opacity` + `.allowsHitTesting`, and animates with `.easeOut(0.15)`. `visited` is seeded with `[.today, persisted]` (MainWindow.swift:81-85) so the user's last tab paints on first frame. Tab switches are already instant after first visit. **Net-new opportunity is the *first* visit to each tab, which still builds cold.**
- **MeetingBodyCache is excellent** (Storage/MeetingBodyCache.swift): sync `cached()` for instant first paint, async `load()` with mtime freshness + per-id coalescing, LRU(64), `patchNotes/Summary/Transcript` for hot writes, and `prefetch(top 10)` (MeetingManager.swift:690-693). `MeetingDetailViewModel.show()` (MeetingDetailViewModel.swift:47-70) does cache-snapshot-then-async-refresh correctly and even tracks `isLoading`/`loadedFromCache`.
- **PeopleStore has a single-file cold-start cache** (`_people-cache.json`, PeopleStore.swift:248-269): reads one file instead of thousands of `person.json`, loads off-main (init:60), publishes on main. Comment notes this fixed multi-*minute* cold loads under file-scanner interception.
- **ToastCenter exists** with Undo + 6s auto-dismiss (ToastCenter.swift) — the substrate for optimistic-edit feedback is already here.
- **Optimistic notes editing is built**: `patchNotes` writes cache immediately, debounced disk save runs separately (MeetingDetailViewModel.swift:87-92; UnifiedMeetingDetail save timer ~600ms).

### The gaps (net-new territory)

1. **False-empty flash — the single biggest perceived-perf bug.** The detail tabs branch only on `isEmpty`, with no "still loading" state. On a *cold-cache* click (cache miss → `cached()` returns `.empty`), the user sees a fully-formed **empty state** before the async disk load lands a frame or two later:
   - Summary: `if summary.isEmpty { emptySummaryView }` renders "No summary / Ollama wasn't running…" (MeetingSummaryTab.swift:29, 67-77).
   - Transcript: `if transcript.isEmpty { placeholder("No transcript", "didn't capture audio, or transcription failed") }` (MeetingTranscriptTab.swift:31-34).
   These read as *errors*, not loading. `MeetingDetailViewModel.isLoading` exists but **`UnifiedMeetingDetail.reload()` (UnifiedMeetingDetail.swift:166-226) doesn't use the VM** — it sets plain `@State summary/transcript` strings, so the view has no way to tell "loading" from "genuinely empty." This is a flicker on the most-used surface in the app.
2. **No skeleton/shimmer primitive exists.** `grep skeleton|shimmer|redacted` finds zero loading placeholders — every wait is a bare `ProgressView().controlSize(.small)` (36 usages). For full-pane cold loads (a tab's first build, a cold meeting body) NN/g recommends a content-shaped skeleton over a spinner or blank ([nngroup.com/articles/skeleton-screens](https://www.nngroup.com/articles/skeleton-screens/)) — a spinner gives no sense of structure and reads as "stuck."
3. **Meetings/People lists can flash an empty state on cold launch.** `MeetingsView` shows `emptyState` ("No meetings yet") when `groups.allSatisfy { $0.1.isEmpty }` (MeetingsView.swift:167, 187-198). `pastMeetings` starts `[]` and is filled by `refreshPastMeetings` on a `Task.detached` (MeetingManager.swift:428-486). People relies on its JSON cache but `DuplicateReviewSheet` and similar gate on `loaded` with a centered `ProgressView` (PeopleListView.swift:522-523). On a slow cold disk the meetings list paints "No meetings yet" before the index lands — alarming for a returning user with hundreds of meetings.
4. **Optimistic UI is limited to notes.** Tag changes route through `handleTagChange` which can physically move vault folders; action-item edits go through `ActionItemStore` upsert. These are fast but there's no consistent "apply-now, reconcile-or-rollback-with-toast" pattern, so any path that *does* touch disk/LLM (rename-tag folder move, follow-up draft, summary regen) can feel like it stalls the row.
5. **LLM/transcribe feedback is honest but heavy.** Summary regen and Transcribe-Now surface a `ProgressView + "Generating…"` (MeetingSummaryTab.swift:87-91) and the row stays put; there's no optimistic "summary is being rewritten" skeleton replacing the old summary, so the user stares at stale content with a tiny spinner.

## NET-NEW recommendations

### PP-1 — `isLoading` tri-state on detail tabs (kill the false-empty flash)
**What/why:** Make the summary/transcript/notes bodies branch on three states — *loading* (cache cold, disk read in flight), *empty* (load finished, file genuinely absent), *content*. Either adopt the existing `MeetingDetailViewModel` in `UnifiedMeetingDetail` (it already exposes `isLoading`/`loadedFromCache`) or add a `bodyState: .loading/.empty/.content` derived from "did the async `load()` complete." Show a skeleton (PP-2) while loading; only show "No summary / No transcript" *after* load completes empty.
**UX impact:** Eliminates the most jarring flicker in the app — the "this meeting failed" flash on a cold click. No click change; pure trust/polish.
**Perf/stability:** Zero new I/O — reuses MeetingBodyCache's existing sync+async split. The skeleton only appears on genuine cache misses (first view of a meeting this session); warm clicks stay instant and skip it (per NN/g, <1s loads shouldn't flash a skeleton). Effort: S. Impact: High. Deps: PP-2.

### PP-2 — `SkeletonView` / `.redacted`-style shimmer primitive
**What/why:** Add one reusable `SkeletonView` (rounded gray bars sized to mimic title/lines/cards) plus a `.skeleton(if:)` modifier wrapping SwiftUI's `.redacted(reason: .placeholder)` with a subtle, reduce-motion-aware shimmer. Use it for: cold meeting body (PP-1), cold list first-build (PP-3), Person detail panel (PersonDetailView has 4 bare spinners at :566/:1269/:1330/:1641), and ChatPanel "thinking."
**UX impact:** Communicates page structure while loading instead of a blank/spinner; "illusion of shorter wait" (NN/g). Consistent loading language across all 5 tabs.
**Perf/stability:** Static gray rects = trivial render cost; gate the shimmer animation behind `accessibilityReduceMotion` (already read in UnifiedMeetingDetail.swift:22) to avoid distraction/accessibility issues. Skeleton must auto-dismiss <10s; if a load exceeds that, swap to a determinate state. Effort: S. Impact: High. Deps: none.

### PP-3 — Persisted "list snapshot" for instant cold-launch lists
**What/why:** On cold launch, render a cached snapshot of the meetings list (and People list) immediately instead of `[]`→empty-state→populate. Persist a lightweight `[MeetingRowSummary]` (id, title, date, primary tag, attendee count, cached summary preview) to a single JSON file on every index refresh — mirror the proven `_people-cache.json` pattern (PeopleStore.swift:248-269). `MeetingManager` seeds `pastMeetings` from it synchronously at init, then `refreshPastMeetings` reconciles. Guard `emptyState` so it only shows when the *refreshed* index is empty, never during the cold window.
**UX impact:** Returning users see their real meeting list on the first painted frame — no "No meetings yet" flash. First-open *feels* instant even on a cold disk.
**Perf/stability:** One small file read on the main thread at launch (kB-scale, like the people cache) vs. a full index scan. Reduces launch-time main-thread work and removes the empty→full reflow. Crash-safe: snapshot is derived/disposable; if missing or stale, falls back to today's behavior. Effort: M. Impact: High. Deps: none.

### PP-4 — Warm the persisted section's caches during launch idle
**What/why:** `prefetchTopMeetingBodies(limit:10)` exists (MeetingManager.swift:690) but isn't obviously fired at launch. Kick it (plus People index `rebuildIndexIfNeeded`) on a low-priority post-launch task so by the time the user clicks the first meeting in their persisted tab, its body is already in `MeetingBodyCache`. Also prefetch the body of the *first row* of the meetings list specifically.
**UX impact:** The very first meeting click of a session — currently the one most likely to hit a cold cache and trigger PP-1's skeleton — becomes instant warm content instead.
**Perf/stability:** Pure `Task.detached(priority: .utility)` background warming, already coalesced by the cache. Bounded to 10 entries (LRU cap 64) so no memory blowup. Should yield to `ResourceGovernor` (AI/ResourceGovernor.swift) so it pauses under thermal/power pressure. Effort: S. Impact: Med. Deps: PP-1/PP-2 (graceful even alone).

### PP-5 — Optimistic edit + reconcile pattern via ToastCenter
**What/why:** Generalize the notes-patch pattern into a tiny helper: apply the mutation to in-memory `@Published` state immediately, fire the disk/network write in a detached task, and on failure roll back + `ToastCenter.show("Couldn't save tag", undoTitle: "Retry")`. Apply to tag add/remove, action-item status/title/priority, and person-field edits — anything currently routed straight through a store mutation that *might* touch disk.
**UX impact:** Every edit registers in <16ms regardless of disk speed; failures surface non-blocking with retry instead of a frozen row. Tag-a-person reflects in People list + meeting + tasks instantly (the cross-tab sync goal).
**Perf/stability:** Moves disk writes off the interaction path entirely. Reconcile guards against lost updates (compare-and-swap on the mutated field). ToastCenter already caps to one toast + auto-dismiss, so no overlay buildup. Effort: M. Impact: High. Deps: none (ToastCenter built).

### PP-6 — Optimistic regeneration: skeleton over stale content for summary/transcribe
**What/why:** When the user hits "Generate Summary" / "Regenerate" / Transcribe-Now (MeetingSummaryTab.swift:83-97), immediately replace the summary body with a skeleton (PP-2) labeled "Rewriting summary…" instead of leaving stale text under a 16px spinner. When `transcribingMeetingIDs` drops the id (already observed at UnifiedMeetingDetail.swift:111-117), swap skeleton → fresh content.
**UX impact:** Makes a 10-60s LLM job *feel* like progress is happening on the right content, not a frozen page. The existing in-flight observation wiring means no new state machine.
**Perf/stability:** No extra LLM load — purely a view-state swap keyed off the existing `transcribingMeetingIDs` set. If the job exceeds the skeleton's ~10s comfort window, fall back to a determinate "still working" line (NN/g: >10s wants explicit progress). Effort: S. Impact: Med. Deps: PP-2.

### PP-7 — Lazy-build heavy tab subtrees behind a skeleton placeholder
**What/why:** The keep-alive ZStack builds a section's *entire* view tree on first visit. For heavy tabs (People with its graph/index, Tasks board) defer the expensive subtree (e.g. SQLite index build, large `LazyVGrid` of person cards) by one runloop and show a skeleton for that first frame, so the *tab switch animation* (0.15s cross-fade) never janks waiting on construction.
**UX impact:** First-ever switch to People/Tasks animates smoothly instead of hitching on index build; the cross-fade stays buttery.
**Perf/stability:** Spreads first-build cost across two frames; `rebuildIndexIfNeeded` (PeopleStore.swift:90-94) already defers index build, so this mainly adds the visible skeleton during that window. No new caches. Effort: M. Impact: Med. Deps: PP-2.

### PP-8 — Audio-URL flash suppression on meeting switch
**What/why:** `reload()` intentionally leaves *stale* `audioURLs` from the prior meeting until the async discovery finishes (UnifiedMeetingDetail.swift:186-213), which can briefly show the previous meeting's audio bar. Clear `audioURLs` synchronously to the cached set (cache the discovered URLs alongside the body) so the audio bar matches the new meeting on the first frame.
**UX impact:** No phantom audio player flashing the wrong meeting's controls during a switch.
**Perf/stability:** Extend `MeetingBodyCache.Body` to memoize `audioURLs` (already does the disk reads); sync `cached()` then returns them too — removes a per-switch `fileExists` round-trip. Tiny memory addition (a few URLs/entry). Effort: S. Impact: Low. Deps: none.

## Top 3 picks

1. **PP-1 — tri-state detail loading (kill false-empty flash)** → **Phase 1.** Highest conviction: it removes the single most alarming flicker (a "meeting failed" empty state flashing on every cold click) and is nearly free because the cache + VM already exist. Foundational for PP-2/PP-6.
2. **PP-3 — persisted list snapshot for instant cold launch** → **Phase 1.** Reuses the proven `_people-cache.json` pattern to make first-open show the real meetings list on frame one instead of an empty-state flash — the cheapest possible win on first-open feel, no data-layer change.
3. **PP-5 — optimistic edit + reconcile via ToastCenter** → **Phase 2.** Generalizes the existing notes-patch + ToastCenter substrate so every edit (tags, tasks, person fields) feels instant and reflects cross-tab immediately, while disk/LLM writes move off the interaction path with non-blocking failure recovery.

Highest-value single recommendation: **PP-1** — it's the only item that fixes a genuine *bug* in perceived performance (false-empty/error flash on the app's most-used surface), at S effort, by wiring up infrastructure that's already built.

Perf/caching insight: the refactor's caches are good but **the UI doesn't yet distinguish "cold" from "empty,"** so it punishes the cache miss with an error-looking flash. The whole strategy is *cache-first render + skeleton-only-when-truly-cold + optimistic-write/reconcile* — none of it touches the data layer, and every piece reuses existing primitives (MeetingBodyCache, `_people-cache.json` pattern, ToastCenter, the keep-alive ZStack). Skeletons must be gated to genuine cache misses and reduce-motion-aware, per NN/g — never flash on warm/<1s loads.
