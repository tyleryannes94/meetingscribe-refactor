# E4 — Swift Performance & Reliability Audit

**Lens:** P0 transcript tail truncation fix (ENG-A); PeopleStore cold-launch perf with large contact lists; SQLite query optimization; dead library targets (SecondBrainCore, MeetingScribeShared); audio pipeline reliability.

**Repo HEAD:** `tyleryannes94/meetingscribe-refactor` (main)  
**Date:** 2026-06-02  
**Files examined:** MeetingPipelineController.swift, MeetingManager.swift, LiveTranscriber.swift (app + ScribeCore), AudioRecorder.swift, AudioRecovery.swift, PeopleStore.swift, SecondBrainDB.swift, MeetingStore.swift, VaultKit/SecondBrainStore.swift, Package.swift

---

## 1. ENG-A — Transcript tail truncation (P0)

### Status: FIXED — but the fix has one residual gap

The original bug was `stopRecording` calling `renderMarkdown()` before `flush()`, so the last in-flight chunk (up to 5 minutes of audio still running whisper at stop time) was dropped.

**The fix is in place and correct.** `MeetingManager.stopRecording()` at line 352 calls `await liveTranscriber.flush()` first, then `liveTranscriber.renderMarkdown()` at line 353. `flush()` (`LiveTranscriber.swift:155–173`) drains `lastMicTask` and `lastSystemTask` via an `await Task.yield()` + polling loop, with a safety cap of 10,000 iterations — it terminates even on a stuck counter.

`MeetingPipelineController.needsBatchRepair()` (line 74–84) now gates the batch repair on three conditions beyond the prior empty-check:
- `droppedChunkCount > 0` (backpressure drops)
- `recordedDuration <= tolerance` (sub-one-chunk recording)
- `liveCoverageSeconds < (recordedDuration - tolerance)` (silent coverage gap)

**Residual gap — E4-1:** The ScribeCore daemon path (`MeetingManager.swift:141–142`, the `DarwinNotifier.recordingStopped` observer) correctly calls `flush()` then `renderMarkdown()`, but it **does not propagate `droppedChunkCount` or `liveCoverageSeconds` to `finalize()`**. Line 143 writes the live transcript directly and returns — no `pipelineController.finalize()` call with coverage metadata. If recording was daemon-owned and chunks were dropped, the repair gate never fires.

Exact location of the surviving gap:
```
MeetingManager.swift:136–149  (DarwinNotifier.recordingStopped handler)
```
The daemon path does `try? store.writeTranscript(live, ...)` and resets state — it never calls `pipelineController.finalize(...)` at all. This means no batch repair, no summary generation, no action item extraction, and no FTS indexing for any meeting stopped via ScribeCore. This is a **P0 regression path**: anyone using the daemon-based recording (enabled when ScribeCore starts successfully) gets a silent, un-repaired transcript with no summary.

---

## 2. PeopleStore — Cold-launch Performance

### Status: Significantly improved, one issue remains

**What's good:**
- `PeopleStore.init()` (line 79) dispatches `load()` via `DispatchQueue.global(qos: .userInitiated).async` — the main thread is never blocked during startup. The class is `@MainActor` but the load races off correctly via the background dispatch.
- The single-file cache (`_people-cache.json`) at `load()` lines 307–326 eliminates the O(N) per-person file scan that formerly took minutes on scanner-intercepted machines.
- `publishLoaded()` only touches `@MainActor` state after the background read finishes.
- `rebuildPersonIndex()` / `rebuildEncounterCounts()` run on `didSet`, which fires on the main actor after `publishLoaded` — these are O(N) but fast (dictionary rebuild from in-memory arrays).

**E4-2 — `publishLoaded` runs one-time dedup synchronously on main actor (line 342–346):**
```swift
// PeopleStore.swift:342–346
if !UserDefaults.standard.bool(forKey: "peopleDedupV1") {
    UserDefaults.standard.set(true, forKey: "peopleDedupV1")
    let r = self.deduplicate()
    ...
}
```
`deduplicate()` is an O(N²) function (grouped by identity key, then a pass over relationships + encounters). For a 2,000-person graph it does ~4,000 relationship scans on the main actor before the People tab renders. This only fires once per install (guarded by `peopleDedupV1` UserDefault), but any user upgrading from a version before the fix will see a frozen UI during first launch. The dedup should be moved to a `Task.detached` call with a `DispatchQueue.main.async` to re-publish results.

**E4-3 — `db.needsRebuild` triggers `rebuildIndex()` synchronously on main actor (line 349–352):**
```swift
// PeopleStore.swift:349–352
if self.db.needsRebuild {
    self.rebuildIndex()
    ...
}
```
`rebuildIndex()` runs the entire SQLite `rebuild()` method inside a `BEGIN...COMMIT` transaction synchronously on `@MainActor`. With thousands of people and encounters this can take 200–500ms on the main thread. Should be `Task.detached { await MainActor.run { self.rebuildIndex() } }` with a background queue for the SQLite writes.

**E4-4 — `filteredPeople` builds a throwaway dictionary on every call (line 1243):**
```swift
// PeopleStore.swift:1243
let byID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
```
This allocates a fresh `[String: Person]` dict every time the search field changes, despite the identical `personIndex` already existing as a maintained property (line 46). Replace with `personIndex`.

---

## 3. SecondBrainDB — SQLite Query Optimization

### Status: Good fundamentals, two missing indexes

The schema (`SecondBrainDB.swift:137–239`) creates five tables — `people`, `encounters_idx`, `search_index` (FTS5), `vault_content`, `vault_fts` (FTS5) — plus `vault_embeddings`. Pragmas are well-chosen: WAL mode, `synchronous=NORMAL`, 256 MB mmap, 16 MB page cache, `busy_timeout=5000`.

**E4-5 — No index on `encounters_idx.person_id` (missing, line 140–144):**
```sql
CREATE TABLE IF NOT EXISTS encounters_idx (
    id TEXT PRIMARY KEY, person_id TEXT, event_tag_id TEXT, date REAL
);
```
`personIDs(forTagID:)` at line 347 runs:
```sql
SELECT DISTINCT person_id FROM encounters_idx WHERE event_tag_id=?
```
This is a full table scan. With thousands of encounters (one per attended meeting per person) this is O(N). The missing index:
```sql
CREATE INDEX IF NOT EXISTS idx_encounters_event_tag ON encounters_idx(event_tag_id);
CREATE INDEX IF NOT EXISTS idx_encounters_person    ON encounters_idx(person_id);
```
Neither index is created anywhere in `ensureSchema()`. Add both in `migrateToV2()` or a new v3 migration.

**E4-6 — No index on `vault_content(entity_kind, date_epoch)` (missing):**
`vaultContentCount(kind:)` at line 391 runs:
```sql
SELECT COUNT(*) FROM vault_content WHERE entity_kind=?
```
This fires on every People tab `.onAppear` to detect whether meetings need backfilling. Full table scan on a potentially large table. The compound index `(entity_kind, date_epoch)` would also speed up the recency-boosted `searchAll` join. Add:
```sql
CREATE INDEX IF NOT EXISTS idx_vault_content_kind_date ON vault_content(entity_kind, date_epoch);
```

**E4-7 — String interpolation SQL injection vector in `deletePerson` / `deleteVaultContent` (lines 275–278, 330–331):**
```swift
exec("DELETE FROM people WHERE id='\(escape(p.id))';")
exec("DELETE FROM vault_content WHERE entity_id='\(escape(entityID))' AND entity_kind='\(escape(entityKind))';")
```
`escape()` replaces `'` with `''` which is correct, but it's fragile. Every other write in this file uses `bindExec` with proper parameter binding. These should be migrated to `bindExec` / prepared statements to eliminate the risk class entirely (single-quote escaping alone doesn't cover all injection vectors; binding does).

---

## 4. Dead Library Targets

### Status: RESOLVED — SecondBrainCore and MeetingScribeShared are gone

`Package.swift` contains exactly five targets: `VaultKit`, `MeetingScribe`, `ScribeCore`, `MeetingScribeMCP`, `NotionMCP`, and one test target. There is no `SecondBrainCore` or `MeetingScribeShared` target, product, or dependency. The comment at line 22–25 confirms the consolidation:

```swift
// (Superseded the former MeetingScribeShared + SecondBrainCore
// targets, which were byte-identical orphans imported by nothing.)
```

No action needed here. The AUDIT_REPORT_2026-05-30 issue #3 is fully resolved.

---

## 5. Audio Pipeline Reliability

### Status: Strong, two gaps remain

**What's good:**
- `AudioRecorder.stop()` (line 174–218) calls `ChunkedAudioWriter.finalize()` on both mic and system writers via a `DispatchGroup` with a `withCheckedContinuation` — ensures final chunk bytes are flushed before returning the `Result`.
- Watchdog timer fires every 0.1s (silenceCheck every 5s) to catch stalled sources (line 272–285).
- `MicRecorder.checkHealth(staleAfter:)` and `SystemAudioRecorder.checkHealth(staleAfter:)` restart stale sources.
- `ProcessInfo.beginActivity` keeps the scheduler from throttling during recordings.
- `AudioRecovery.ensureDownloaded` handles iCloud eviction before transcription.
- `AudioRecovery.meetingsWithInterruptedRecordings` enables crash recovery on launch.

**E4-8 — Watchdog timer runs on `RunLoop.main` at 0.1s interval (line 283):**
```swift
RunLoop.main.add(t, forMode: .common)
```
At 0.1s this fires 10 times per second. The health-publish path (`publishHealth()`) allocates a `Health` struct + calls `DispatchQueue.main.async` on every tick — that's 10 closures/sec queued to main, each doing `mic.counters.snapshot()` + `system.counters.snapshot()`. During a 2-hour meeting that's 72,000 allocations. The heavy silenceCheck only runs every 50 ticks (5s), but the health publish runs every tick. `RecordingMonitor` and the UI already debounce the level display. The watchdog tick could be raised to 1s (keeping the 5s silenceCheck), or health publishes moved to a 0.1s `TimelineView` on the view layer only.

**E4-9 — No retry on `AVAssetWriter` finalization failure in `ChunkedAudioWriter.finalize()`:**
If the final `AVAssetWriter.finishWriting(completionHandler:)` fails (disk-full, interrupted), the chunk is silently lost with no error surfaced to the `finalize` pipeline. `AudioRecorder.stop()` proceeds and returns a `Result` with `micURL/systemURL` pointing at a file that may have a corrupted last few seconds. The batch repair gate in `needsBatchRepair` won't fire because there is no `droppedChunkCount` for writer errors — only for backpressure drops. The fix: capture `AVAssetWriter.status == .failed` in `finalize()` and set a flag that `AudioRecorder.stop()` checks, then includes in the `Result` so the pipeline can gate on it.

---

## 6. MeetingStore Index Performance

### Status: Good — O(1) path works, one cold-cache race

`MeetingStore` uses a two-layer cache: in-memory `_indexMemoryCache` (protected by a concurrent `DispatchQueue` with barrier writes) and an on-disk `.meeting-index.json`. `upsertInIndex` (line 501) dispatches a `Task.detached` for the cold-cache slow path — correct. `listPastMeetings` (line 427) checks memory cache first.

**E4-10 — `updateRecentJSON` does a `FileManager.fileExists` check per meeting on the calling thread (lines 231–237):**
```swift
// MeetingStore.swift:231–237
let hasSummary: Bool = {
    guard let rel = m.relativeFolderPath, !rel.isEmpty else { return false }
    let summaryURL = vaultURL.appendingPathComponent(rel).appendingPathComponent("summary.md")
    return FileManager.default.fileExists(atPath: summaryURL.path)
}()
```
This runs for each of up to 200 meetings on every call to `writeMeeting`. `writeMeeting` is called from `@MainActor` (e.g., during `finalize()`). With 200 meetings in the recent window, that's 200 `stat()` syscalls on the main actor. `updateRecentJSON` should be moved to `Task.detached`.

---

## 7. Existing Plan Items Most Critical Through This Lens

Endorsing (not re-inventing):

1. **ENG-A batch-repair gate** — the fix is 90% there; the daemon path (E4-1 above) is the remaining 10% and should be treated as P0.
2. **ARCH-1 CaptureKit de-dup** — the four diverged files (`AudioRecorder`, `WhisperRunner`, `NotificationManager`, `LiveTranscriber`) now differ between app and ScribeCore by 11–83 lines. Any fix to the audio pipeline (E4-8, E4-9) must be applied to both copies until CaptureKit ships.
3. **SecondBrainCore / MeetingScribeShared dead targets** — confirmed resolved; no action.

---

## 8. NET-NEW Recommendations

### E4-1 — Fix daemon path: wire finalize() in DarwinNotifier.recordingStopped handler [P0, S]
`MeetingManager.swift:136–149`. The `recordingStopped` observer only writes the raw live transcript. It must call `pipelineController.finalize(meeting:audioResult:liveTranscript:liveDroppedChunks:liveCoverageSeconds:recordedDuration:)`. The recorder counters should be snapshotted from the ScribeCore IPC result or read from a shared file before the daemon tears down. Without this, daemon-path recordings have no summary, no action items, no FTS index, and no batch repair. **Effort: S (hours) — the finalize call is already wired for the direct path; it needs to be called from the daemon path too.**

### E4-2 — Move one-time dedup off main actor in publishLoaded() [P1, S]
`PeopleStore.swift:342–346`. Wrap the `deduplicate()` call in `Task.detached { ... ; await MainActor.run { self.people = ...; self.encounters = ... } }`. Prevents a first-launch freeze for upgrading users with large graphs. **Effort: S.**

### E4-3 — Move SQLite rebuild off main actor when needsRebuild [P1, S]
`PeopleStore.swift:349–352`. Dispatch to `Task.detached` so the full `BEGIN...COMMIT` transaction runs off-main. Publish a `@Published var isIndexing: Bool` flag so the People tab can show a brief "Rebuilding index…" indicator. **Effort: S.**

### E4-4 — Fix filteredPeople to use personIndex instead of rebuilding dict [P1, S]
`PeopleStore.swift:1243`. One-line fix: replace the throwaway `Dictionary(people.map ...)` with `personIndex`. Eliminates a per-keystroke allocation on the main actor in the search path. **Effort: S (minutes).**

### E4-5 — Add missing SQLite indexes: encounters_idx.event_tag_id, encounters_idx.person_id [P1, S]
`SecondBrainDB.swift` — add a `migrateToV3()` block with two `CREATE INDEX IF NOT EXISTS` statements. These turn full table scans into O(log N) index lookups for tag-based and person-based encounter queries. **Effort: S.**

### E4-6 — Add vault_content(entity_kind, date_epoch) composite index [P2, S]
`SecondBrainDB.swift` — same migration block. Speeds up `vaultContentCount(kind:)` and the recency JOIN in `searchAll`. **Effort: S (add one line to the migration).**

### E4-7 — Migrate string-interpolated DELETEs to bindExec() [P2, S]
`SecondBrainDB.swift:275–278, 330–331`. Replace `exec("DELETE FROM ... WHERE id='\(escape(...))'")` calls with `bindExec("DELETE FROM ... WHERE id=?", [.text(...)])`. Closes the injection vector class. **Effort: S.**

### E4-8 — Reduce watchdog timer frequency from 0.1s to 1.0s [P2, S]
`AudioRecorder.swift:272`. Change `withTimeInterval: 0.1` to `withTimeInterval: 1.0`, adjust `silenceCheckCounter` threshold from 50 to 5. Push sub-second level UI updates to `TimelineView` on the view layer (already used by `AudioLevelMeter` per the HANDOFF). Reduces GCD load and `Health` struct allocations by 90x during recordings. **Effort: S.**

### E4-9 — Surface AVAssetWriter finalization failures into AudioRecorder.Result [P1, M]
`ChunkedAudioWriter.finalize()` — capture `AVAssetWriter.status == .failed` and propagate a flag through `AudioRecorder.Result`. `MeetingPipelineController.finalize()` checks this flag and forces `needsBatch = true` regardless of coverage. Prevents silent partial recordings from a disk-full or interrupted write. **Effort: M.**

### E4-10 — Move updateRecentJSON off main actor [P2, S]
`MeetingStore.swift:223`. Wrap the entire `updateRecentJSON` body in `Task.detached(priority: .utility)`. The 200-meeting `fileExists` scan is blocking the main actor on every `writeMeeting` call. **Effort: S (wrap existing body).**

### E4-11 — Add a statement cache / prepared-statement pool to SecondBrainDB [P2, M]
Every `searchAll`, `upsertPerson`, and `insertPerson` call runs `sqlite3_prepare_v2` from scratch. For the rebuild (called on every People tab `.onAppear` after a cold index), this means hundreds of compiles for the same SQL. A `[String: OpaquePointer]` cache keyed on SQL string, finalized on `deinit`, would cut the per-rebuild CPU cost measurably. **Effort: M.**

### E4-12 — Add a compile-time test for needsBatchRepair coverage math [P1, S]
`MeetingPipelineController.swift:74–84`. `needsBatchRepair` is already unit-testable (pure function, no dependencies). Add a `MeetingScribeTests` test case covering: empty live, dropped > 0, short recording, coverage gap, and the happy path (no batch needed). The AUDIT_REPORT called out this logic as the highest-risk item; a test locks in the semantics. **Effort: S.**

---

## 9. Top 3 Picks

**#1 (P0): E4-1 — Wire `finalize()` into the daemon stop path.** Every recording made via ScribeCore (the default when the daemon is running) currently produces no summary, no action items, no FTS index, and no batch repair. This is silent data loss on the primary recording path.

**#2 (P1): E4-9 — Surface AVAssetWriter failures into AudioRecorder.Result.** Disk-full and interrupted writes produce corrupted audio silently. The batch repair gate in `needsBatchRepair` cannot fire because there's no signal — the failure is invisible to the pipeline.

**#3 (P1): E4-5 — Add missing SQLite indexes.** The `encounters_idx.event_tag_id` and `encounters_idx.person_id` full table scans run on the main actor (SecondBrainDB is `@MainActor`) every time a tag filter or person detail renders. With thousands of encounters this is a measureable freeze that gets worse as the graph grows.
