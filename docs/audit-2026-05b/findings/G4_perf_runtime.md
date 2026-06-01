# G4 Staff Engineer — Runtime Performance (scroll / re-render / list cost)

Lens: hunt SwiftUI runtime anti-patterns that cause scroll jank, re-render storms, and battery drain — synchronous disk I/O in view bodies, O(n) lookups per render, comparators doing O(m) work, whole-array re-filter per keystroke, non-lazy stacks, and full-array re-encode on every edit. The product already has good *cold-start* caching (off-main `PeopleStore.load()`, combined cache file, `MeetingBodyCache`, `ThumbnailCache`); the gap is *steady-state* runtime cost during scroll, typing, and selection.

## Audit (through my lens)

**1. Synchronous disk read inside a list-cell body (the worst offender).**
`MeetingCard.hasFile(_:)` (`UI/MeetingCard.swift:316-322`) does `try? String(contentsOf: dir.appendingPathComponent("transcript.md"), encoding: .utf8)` and reads the *entire* transcript file off disk **on every body evaluation** of the `.past` status pill (`pastStatus`, line 255). This card is rendered for every past meeting in `TodayView.todaySection` (`UI/TodayView.swift:446-448`). On a busy day that's N synchronous main-thread file reads of full multi-KB transcripts on every scroll/hover/re-render — a direct cause of scroll hitching. Worse, it's *redundant*: `Meeting.health` (`Models/Meeting.swift:46`, `MeetingHealthDTO`) already encodes whether the recording produced a transcript (`status == .noTranscript`/`.ok`), and `MeetingListRow` (`MeetingsView.swift:478,527`) already drives its status dot purely from `meeting.health` with **zero disk I/O**. So one of the two list components reads the whole file per render and the other reads nothing.

**2. `hasFile` also recomputes the meeting directory each call.** Before the read it calls `tagStore.primaryTag(for: meeting)` → `tags(for:)` → `tagIDs(for:)` → `compactMap { tag(by:$0) }`, and `tag(by:)` is `allTags.first { $0.id == id }` (`Storage/TagStore.swift:126-153`) — an O(tags) linear scan per tag id, per card, per render. `tags(for:)` is *also* called directly in `MeetingCard.metaRow` (`MeetingCard.swift:140`) and `MeetingListRow` (`MeetingsView.swift:491`), so every meeting cell pays repeated linear tag scans on every render. No `[id: MeetingTag]` dictionary exists.

**3. `PersonDetailView` re-runs an O(n) people scan many times per render.** `current` (`People/PersonDetailView.swift:216`) is `people.person(by: person.id) ?? person`, and `person(by:)` is `people.first { $0.id == id }` (`PeopleStore.swift:473`) — a linear scan over the whole people array. `current` is a *computed property* referenced throughout the body (header, tags, favorites, photo, relationships), so a single body pass triggers many full-array scans. `relationshipRows` (line 719) calls `people.person(by: r.toPersonID)` once per relationship → O(relationships × people). With hundreds–thousands of imported contacts this is a measurable per-render cost. No `[id: Person]` index is maintained on the store.

**4. Whole-array re-filter + re-sort on every keystroke / interaction in People.** `PeopleListView.filtered` (`People/PeopleListView.swift:34-41`) is a computed property: every render calls `people.filteredPeople(query:tagID:)` and then `sorted(...)`. `filteredPeople` (`PeopleStore.swift:1166-1188`), in the empty-query branch, sorts the entire array by `relevanceScore(encounterCount:)` where `encounterCount(for:)` is `encounters.reduce(...)` — an O(encounters) scan **per element**, making the sort O(people × encounters × log people). Combined with `.recent`/`.meetings` sorts in `sorted` that *also* call `encounterCount`/`meetingCount` inside the comparator (lines 46-52), People list scrolling and typing re-do this whole computation with no memoization or debounce.

**5. Hidden O(n) helpers recomputed in the list chrome.** `ghostCount` (`PeopleStore.swift:1191`) and the ghost filter (line 1185) call `isGhost(encounterCount:)` → `encounterCount` (another O(encounters) scan) for *every* person, and `usedTagIDs()` (line 1197) reduces over all people; these feed `tagChips` and `ghostFooter` and are re-evaluated on render. `MeetingsView.dayCell` calls `calendarMeetings.contains { ... }` (`MeetingsView.swift:357`) **inside each of 42 day cells**, recomputing the deduped `calendarMeetings` array (line 280, an O(meetings) set-insert pass) per cell — O(42 × meetings) per month-grid render.

**6. ThumbnailCache: cold miss still decodes synchronously on the main thread.** `ThumbnailCache.thumbnail` (`UI/ThumbnailCache.swift:18`) is correct on a cache *hit*, but on a miss `downsample` runs `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceShouldCacheImmediately: true` **synchronously in the view body** at `PersonDetailView.swift:954`. First open of a person with a photo (or first scroll past one) blocks the render thread on ImageIO decode. There's no async placeholder/skeleton path.

**7. Full-array re-encode + atomic write on every single edit.** `TagStore.persist()` (`Storage/TagStore.swift:70-83`) re-encodes the *entire* `allTags`+`meetingTags`+`seriesTags` structure and atomically rewrites the whole file on every `addTag`/`removeTag`/`setTags` (lines 158-176). `PeopleStore.writePerson` (`PeopleStore.swift:477-492`) re-encodes person.json **and** regenerates the full markdown mirror on every edit, and bulk operations loop it per record (`applyTagToSelection` → `updatePerson` per selected person, `PeopleListView.swift:309-315`; `removeTagFromAll` writes per person, `PeopleStore.swift:1203-1207`). A bulk-tag of 50 people = 50 synchronous encode+markdown+atomic-write cycles on the main actor. (PeopleStore *does* debounce the combined *cache* file off-main — good — but the per-record canonical writes are still synchronous and unbatched.)

**8. Good patterns already in place (don't re-propose):** `MeetingsView.meetingList` uses `LazyVStack` (line 154); `refreshPastMeetings` is debounced + off-main (`MeetingManager.swift:428-444`); `MeetingBodyCache` + `MeetingDetailViewModel` load detail bodies async with `applyIfCurrent` guards; `PeopleStore` init loads off-main and writes a combined cache for next launch.

## NET-NEW recommendations

**PR-1 — Kill the per-render transcript disk read in `MeetingCard`; drive status from `meeting.health`.**
What/why: replace `hasFile("transcript.md")` (`MeetingCard.swift:255,316`) with a pure read of `meeting.health?.status` (already populated; `MeetingListRow` does exactly this). If a richer "ready" signal is needed, persist a tiny `hasTranscript: Bool` on `Meeting` at finalize and read that. No file is ever opened during render.
UX impact: removes invisible scroll stutter on the Today feed; status pill is unchanged visually. Clicks: 0 change.
Perf/stability: eliminates N synchronous full-file main-thread reads per scroll/re-render frame — the single biggest jank source found. Cache approach: reuse the already-cached `health` value; no new I/O. Removes a crash/hang surface (large transcript on a slow/iCloud-evicted file). Effort: S. Impact: High. Deps: none.

**PR-2 — Add a `[String: MeetingTag]` index to `TagStore` and a per-meeting tag cache.**
What/why: maintain `tagsByID` rebuilt on `allTags` mutation; make `tag(by:)` O(1) (`TagStore.swift:126`). Optionally memoize `tags(for:)` results in a `[meetingID: [MeetingTag]]` dictionary invalidated on `setTags`. Removes repeated O(tags) scans in `metaRow`/`MeetingListRow`/`hasFile`.
UX impact: smoother meeting-list scrolling; none visible.
Perf/stability: O(1) lookups; cache is in-memory and tiny. Effort: S. Impact: Med. Deps: none.

**PR-3 — Maintain a `[String: Person]` index in `PeopleStore`; make `person(by:)` and `encounterCount` O(1).**
What/why: keep `peopleByID` in sync on every people mutation; keep `encounterCountByPersonID: [String:Int]` updated on encounter add/remove (replace the `encounters.reduce` scan at `PeopleStore.swift:82`). Fixes the O(n) `current` in `PersonDetailView:216` and the O(n×m) `relationshipRows:719`, plus every comparator/ghost/usedTags helper that calls `encounterCount`.
UX impact: instant person-detail open + scroll, especially with large graphs.
Perf/stability: converts several O(people)/O(encounters) hot paths to O(1) dictionary reads; indexes are derived in-memory, rebuilt off-main alongside `load()`. Effort: M. Impact: High. Deps: none (pairs with PR-4).

**PR-4 — Memoize + debounce the People list pipeline.**
What/why: move `filtered`/`sorted` out of a render-time computed property into a cached `@Published filteredPeople` recomputed only when `query`, `tagFilters`, `sortOrder`, or the people array actually change; debounce the query (~150 ms) so each keystroke doesn't re-sort the whole array. Sort keys (relevance/recency/count) should be precomputed once per recompute using PR-3's `encounterCountByPersonID`, not inside the comparator (`PeopleListView.swift:43-58`, `PeopleStore.swift:1175-1186`).
UX impact: typing in People search stays responsive at thousands of contacts (before: full re-filter+re-sort per keystroke).
Perf/stability: drops per-keystroke cost from O(people × encounters × log people) to O(people log people) once, off the keystroke path. Cache approach: cached result array + dirty flag. Effort: M. Impact: High. Deps: PR-3.

**PR-5 — Async/off-main thumbnail decode with a skeleton placeholder.**
What/why: make `ThumbnailCache` decode on a background queue and publish into the cache, with the view showing a placeholder until ready (or pre-warm visible photos). Keep the synchronous fast-path only for cache hits (`ThumbnailCache.swift:18`, used at `PersonDetailView.swift:954`).
UX impact: person detail/photos never block the render thread on first open; graceful fade-in.
Perf/stability: removes a synchronous ImageIO decode from the body; bounded `NSCache` already caps memory. Effort: S. Impact: Med. Deps: none.

**PR-6 — Precompute month-grid meeting density once per render, not per cell.**
What/why: in `MeetingsView`, compute `calendarMeetings` once and build a `Set<DateComponents>` (or `[startOfDay: Bool]`) of days-with-meetings, then have `dayCell` do an O(1) membership test instead of `calendarMeetings.contains { ... }` per cell (`MeetingsView.swift:280,357`).
UX impact: instant month switching/scrubbing.
Perf/stability: O(42 × meetings) → O(meetings) per grid render; precomputed dictionary. Effort: S. Impact: Med. Deps: none.

**PR-7 — Batch + off-main the per-record canonical writes for bulk edits.**
What/why: add a `withBatchedWrites { }` path to `PeopleStore`/`TagStore` so bulk tag/merge/delete (`applyTagToSelection`, `removeTagFromAll`, `mergeSelection`) coalesce into a single off-main encode pass instead of N synchronous encode+markdown+atomic writes (`PeopleStore.swift:477-492,1203-1207`; `TagStore.persist` `:70`). Defer the markdown-mirror regeneration to a debounced background task.
UX impact: bulk-tagging 50 people no longer freezes the UI for a beat.
Perf/stability: collapses N main-actor encodes into one off-main batch; lowers fsync churn and battery. Effort: M. Impact: Med. Deps: PR-3.

**PR-8 — Make `Meeting`/`Person` row views cheaper to diff (stable identity + `Equatable`).**
What/why: ensure `MeetingCard`/`MeetingListRow`/`PersonRow` are value-stable so SwiftUI can skip re-rendering unchanged cells; today every store mutation (e.g. a tag edit anywhere) republishes the whole array and re-evaluates all visible cells, each of which then re-runs the O(n) helpers above. Conform row models to `Equatable` on the fields the row actually displays, and pass only those into the cell (not the whole `@EnvironmentObject` store where avoidable).
UX impact: editing one person/meeting stops re-rendering the entire visible list.
Perf/stability: cuts re-render fan-out; complements PR-2/PR-3 by reducing how *often* the hot paths run. Effort: M. Impact: Med. Deps: PR-2, PR-3.

## Top 3 picks

1. **PR-1 — remove the per-render transcript disk read in `MeetingCard`** (Phase 1, foundational/perf). Highest conviction: a synchronous full-file read on the main thread inside a list cell, rendered per past meeting per frame, when the answer is already cached in `meeting.health`. Pure win, S effort.
2. **PR-3 + PR-4 — O(1) people/encounter indexes and a memoized, debounced People list pipeline** (Phase 1). Removes the dominant steady-state cost at scale (per-keystroke whole-array re-filter+re-sort with nested O(encounters) scans).
3. **PR-2 — `TagStore` ID index + per-meeting tag cache** (Phase 1). Cheap, unblocks PR-1's status path and de-janks every meeting list.

All three are Phase 1 (perf/infra foundation) so the higher-level UX phases render on a smooth base.
