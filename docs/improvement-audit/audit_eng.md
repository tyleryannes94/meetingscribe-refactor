# MeetingScribe (Refactor) — Engineering Audit

**Target:** `/Users/tyleryannes/MeetingScribeRefactor` (the rebuilt Swift Package — NOT `~/MeetingScribe`)
**Scope:** Current code on `main` (last commit `e15c1db`). macOS 14+, Apple Silicon, SwiftPM, SwiftUI/AppKit.
**Size:** 206 Swift files, ~43k LOC. 4 executables (MeetingScribe, ScribeCore, MeetingScribeMCP, NotionMCP) + 3 libraries (MeetingScribeShared, SecondBrainCore, VaultKit).

The rebuild was sold as "more efficient backend, NavigationSplitView, vault migration, transcript sync." This audit assesses the **current** code from five engineering lenses and explicitly checks whether the issues flagged in the OLD repo were fixed, persist, or were newly introduced.

Severity key: **P0** = data loss / crash / security; **P1** = wrong behavior, perf cliff, or major maintainability hazard; **P2** = polish / cleanup.

---

## What the rebuild already fixed (verified in code)

- **`AudioCounters`** is now lock-protected with a TSan-tested concurrency test (`Tests/.../AudioCountersTests.swift`). The old "bare-var racing recorder counters" bug is genuinely gone.
- **`WhisperRunner`** consolidates the three near-identical whisper invocations into one argv builder, with the `--no-context` footgun documented in a single place (`WhisperRunner.swift:196`). Real de-duplication of the invocation logic.
- **`LiveTranscriber`** now has bounded backpressure (`maxPending = 16`) and per-source parallel queues, replacing the single shared `workQueue` that serialized mic behind system.
- **`refreshPastMeetings`** is debounced through a Combine `PassthroughSubject` (300 ms), fixing the "@Published array replaced on every call site" thrash.
- **`MeetingStore`** has an in-memory index cache + O(1) `relativeFolderPath` directory resolution, replacing the per-`onAppear` disk read + O(N) tree walk.
- **Sub-controller extraction** (`MeetingPipelineController`, `QuickNotesController`, `ActionItemBackfillController`, `PersonExtractionController`) splits the old MeetingManager god-object so views can scope SwiftUI invalidation.
- **Crash-recovery** path exists (`scanForInterruptedRecordings`, stale `.recording.inprogress` markers, manifest rebuild).
- **CI gates releases on `swift test` passing** before publishing (`release.yml` `release: needs: [test]`).

These are real improvements. The findings below are what remains or was newly introduced.

---

# ENG-1 — Architecture & State Management

### [P1] MainWindow is still an opacity-ZStack tab switcher, not NavigationSplitView
**File:** `Sources/MeetingScribe/UI/MainWindow.swift:83-100` (`tabContent`)
**Problem:** The top-level shell builds every visited section in a `ZStack` and shows/hides via `.opacity(section == s ? 1 : 0)` + `.allowsHitTesting`. `NavigationSplitView` appears in exactly **one** file (`MeetingsView.swift`) — i.e. the rebuild adopted it for the *Meetings list/detail* pane only, not the app shell. The "NavigationSplitView rebuild" claim is therefore partial.
**Root cause:** The keep-alive ZStack pattern was retained to make tab-switching feel instant (`visited` set + cross-fade). But it keeps all visited tabs mounted, all their `@StateObject`s alive, all their timers running (e.g. `TranscriptSyncView`'s 0.25 s timer, hourly refresh tasks), and defeats SwiftUI's lazy teardown.
**Why it matters:** Every visited tab's `.task`/`Timer`/`onReceive` stays live forever. Memory and main-thread wakeups grow monotonically with tabs visited. It also means `@AppStorage("mainWindow.lastSelectedSection")` is the single source of truth for navigation with no deep-link/state-restoration story beyond the persisted enum.
**Fix:** Move the shell to `NavigationSplitView { sidebar } detail: { ... }` with a `@State selection`. If instant-switch is required, scope keep-alive to the 1-2 heaviest tabs only and let the rest deallocate. At minimum, gate the always-on timers (see ENG-2).
**Tests to add:** Snapshot/state test asserting that switching away from `.meetings` tears down `TranscriptSyncView`'s timer subscription (observe a teardown hook).

### [P1] Navigation state is fragmented across three competing mechanisms
**Files:** `MainWindow.swift:50` (`@AppStorage sectionRaw`), `TodayView.swift:23` (`@State expandedMeetingID`), `CalendarTabView.swift:20` (`@State expandedID`)
**Problem:** `TodayView` and `CalendarTabView` *still* carry their own ad-hoc expand/collapse state (`expandedMeetingID`, `expandedID`, `toggleExpand`, "Collapse" buttons) — the exact inline-expansion pattern the rebuild was supposed to replace with detail navigation. So the app now has THREE navigation models live at once: ZStack tabs (shell), NavigationSplitView (Meetings), and inline expand/collapse (Today + Calendar).
**Root cause:** The NavigationSplitView migration was applied to MeetingsView only; Today and the Calendar tab were left on the legacy inline-expand UI.
**Why it matters:** Inconsistent UX (clicking a meeting does different things in different tabs), duplicated card-rendering code, and no shared selection model. Routing (`routeEntity` in MainWindow) can open a meeting in a sheet but can't drive Today/Calendar's inline expansion, so deep links land on a collapsed card.
**Fix:** Converge on a single `NavigationSplitView`-based selection. Replace inline expand/collapse in Today + Calendar with navigation to the shared `UnifiedMeetingDetail`. Delete `expandedMeetingID`/`expandedID`/`toggleExpand`.
**Tests to add:** UI test: deep-link to a meeting via `.meetingScribeOpenEntity` and assert detail is shown regardless of source tab.

### [P1] `startRecording` publishes the wrong meeting into `.recording` state
**File:** `MeetingManager.swift:206` (and `init` observer at `:131`)
**Problem:** In the direct-audio path, state is set to `.recording(meeting: meeting, ...)` using the **function parameter** `meeting` (which is `nil` for ad-hoc recordings), not `m`/`activeMeeting` (the resolved ad-hoc meeting). The ScribeCore path's observer at `:131` does it correctly using `self.activeMeeting`. So depending on whether ScribeCore handled the start, the published `.recording` association differs.
**Root cause:** Copy bug — local `m` shadows `meeting` but the wrong identifier was used at the state-assignment site.
**Why it matters:** Any view that reads the associated meeting off `RecordingState.recording(meeting:)` gets `nil` for ad-hoc recordings on the fallback path, while `activeMeeting` is set. Inconsistent state is a classic source of "the recording card shows nothing" bugs.
**Fix:** `state = .recording(meeting: m, startedAt: Date())` at line 206. Audit every read of the associated value to prefer `activeMeeting`.
**Tests to add:** `MeetingManagerTests`: start ad-hoc with ScribeCore stubbed off, assert `if case .recording(let mm, _) = state { mm != nil && mm?.id == activeMeeting?.id }`.

### [P2] Forwarding-shim sprawl on MeetingManager
**File:** `MeetingManager.swift:714-762` (~25 Quick Notes shims) + `:415-447` (pipeline shims)
**Problem:** The "extract sub-controllers but keep legacy API as forwarding shims" approach left ~50 pass-through methods on MeetingManager. The class is still 869 lines and remains the de-facto god-object every view depends on.
**Root cause:** Extraction done without migrating call sites ("so existing views keep compiling without per-view edits" — comment at `:18`).
**Fix:** Migrate views to observe `quickNotesController` / `pipelineController` directly, then delete the shims. Track as a debt ticket; don't let "temporary" shims calcify.

---

# ENG-2 — Performance & Responsiveness

### [P1] Keep-alive ZStack keeps every visited tab's timers and tasks running
**File:** `MainWindow.swift:84-99`; victims include `TranscriptSyncView.swift:118`, `MainWindow.swift:343-351`
**Problem:** Because tabs are never torn down (ENG-1), their always-on work runs forever: `TranscriptSyncView` runs `Timer.publish(every: 0.25)` *unconditionally* (line 118 — fires 4×/sec even when no audio is attached and the tab is hidden), and each tab's `.task` loops persist.
**Root cause:** Hidden-but-mounted views still execute `.onReceive`/`.task`.
**Why it matters:** On a long session a user who's opened detail views accumulates N background 4 Hz timers competing with the main thread — the opposite of the "more efficient backend" goal.
**Fix:** (a) Only run the sync timer when `audioController != nil && isPlaying`; switch to driving active-segment updates off the player's time-observer instead of a free-running timer. (b) Pause hidden tabs' timers (`scenePhase`/visibility gate) or actually tear them down via NavigationSplitView.
**Tests to add:** Performance test counting active timer fires while a detail view is hidden (should be 0).

### [P2] `TranscriptSyncView` re-parses the whole transcript and re-derives speaker colors on every `rawTranscript` change
**File:** `TranscriptSyncView.swift:116-117, 252-263`
**Problem:** `parse()` runs an NSRegularExpression over every line and rebuilds the speaker-color dictionary on appear and on any transcript change. For a long meeting (thousands of lines) this is a synchronous main-thread pass.
**Fix:** Memoize parse keyed by transcript hash; move parsing off the main actor for large inputs (`Task.detached`, publish results back).

### [P2] `convertToM4A` / `afconvert` and segment merges block via `waitUntilExit` on a detached thread
**File:** `MeetingManager.swift:802-819`, pipeline merges in `MeetingPipelineController.swift:75, 190`
**Problem:** Synchronous `Process.waitUntilExit()` is wrapped in `Task.detached`, which parks a cooperative-pool thread for the whole conversion. Fine occasionally, but import + multiple merges can starve the (small) cooperative pool.
**Fix:** Use a dedicated `DispatchQueue` / process-termination handler instead of blocking a structured-concurrency worker, or cap concurrency explicitly.

### [P2] Hourly refresh task forces a full rescan of all tabs
**File:** `MainWindow.swift:343-351`
**Problem:** `refreshPastMeetings(force: true)` + `refreshQuickNotes()` + `calendar.refreshUpcoming(force: true)` every hour bypasses the throttle and re-scans disk even if nothing changed.
**Fix:** Make the periodic refresh non-forced (respect the 2 s throttle / index cache) or drive it off filesystem change events.

---

# ENG-3 — Concurrency, Reliability & Data Integrity

### [P0] Live transcript is truncated at stop; the batch fallback that should recover the tail is skipped
**Files:** `MeetingManager.swift:331` (`renderMarkdown()` captured at stop), `MeetingPipelineController.swift:86-104` (finalize fallback gate), `LiveTranscriber.swift:98-108` (un-awaited per-source task chains)
**Problem:** `stopRecording` calls `liveTranscriber.renderMarkdown()` **synchronously**, but the live transcriber's per-source work is fire-and-forget `Task.detached` chains (`lastMicTask`/`lastSystemTask`) that are **never awaited at stop**. Any chunk still running whisper at stop time — in practice the final 0-5 minute chunk of every meeting — is not yet in `segments`, so it's missing from the rendered transcript. The finalize pipeline is supposed to backstop this by re-running whisper on the merged audio, BUT it only does so when the live transcript is *completely empty* (`liveIsUseful = !trimmed.isEmpty && trimmed != "# Transcript"`, `:88`). For any normal meeting the live transcript is non-empty, so the batch pass is skipped and **the tail is silently dropped from the persisted `transcript.md`**. This is the old "live-transcript truncation at stop" bug, still present.
**Root cause:** No flush/await of in-flight live chunks at stop, combined with an all-or-nothing "is live useful?" gate that ignores partial completeness.
**Why it matters:** Silent, permanent loss of the final minutes of every recording's transcript — the worst kind of data bug because the meeting *looks* fully transcribed. Action items / summary are then generated from a truncated transcript.
**Fix:** (1) Add `LiveTranscriber.flush() async` that awaits `lastMicTask` and `lastSystemTask` before `renderMarkdown()`; call it in `stopRecording`. (2) Change the finalize gate from "is live empty?" to "is the merged audio meaningfully longer than `liveTranscriber.lastTranscribedSecond`?" — if the live transcript covers < (duration − one chunk), run the batch pass and prefer its output. (3) Always run batch when `droppedChunkCount > 0`.
**Tests to add:** `LiveTranscriberTests`: submit N chunks where the last is still "processing" at stop, assert `flush()` waits and the rendered transcript includes the final chunk. Pipeline test: live transcript covering 90% of duration triggers batch fallback.

### [P0] Vault layout migration is half-wired: moves folders but never updates `relativeFolderPath`, and new/retagged meetings still use the OLD flat tag layout
**Files:** `Storage/VaultMigrationManager.swift:24-95`, `Storage/MeetingStore.swift:96-134` (`desiredDirectory` / `directory(for:)`), `MeetingManager.swift:604-616` (`handleTagChange` → `moveMeeting`)
**Problem:** `migrateLayout` moves each meeting folder from `<TagFolder>/<slug>/` to `meetings/yyyy/yyyy-MM/<slug>/` (`:79`) but does **not** rewrite that meeting's persisted `relativeFolderPath` in `meeting.json`, nor invalidate the store's path caches. Meanwhile `MeetingStore.desiredDirectory` (`:96`) — the path used to *create* every new meeting and the fallback used whenever the persisted path is stale — still computes `<TagFolder>/<slug>`. So post-migration:
  - Existing meetings: step 1 of `directory(for:)` checks the stale persisted path (now gone → fails), step 3 checks the stale tag path (gone → fails), and only the **O(N) tree-walk fallback** (`:128`) finds them — exactly the perf regression the cache was meant to avoid, re-incurred on first access of every meeting.
  - New meetings are still written into the **old** flat `<TagFolder>/<slug>` layout (`writeMeeting` → `desiredDirectory`), so the two layouts coexist indefinitely.
  - Worse, `handleTagChange` (`:608`) calls `store.moveMeeting(to:)` which uses `desiredDirectory`, **moving a migrated meeting back out** of `meetings/yyyy/...` into the flat tag layout.
**Root cause:** The migration was written as a one-shot folder mover without touching the store's path model; `desiredDirectory` was never updated to the new layout.
**Why it matters:** Data integrity + perf. Files don't get lost (tree-walk self-heals reads), but the "migration" doesn't actually migrate the *model*, the new layout is never used for new data, and retagging silently undoes the migration for that meeting. The migration flag (`vault.layoutMigration.v2.completed`) is set to `true` even when individual `moveItem` calls fail (`:80-82` swallows the error and `continue`s, then `:89` marks complete) — so a partial migration is recorded as complete and never retried.
**Fix:** (1) After each successful move, read the meeting.json, set `relativeFolderPath` to the new relative path, and write it back (or call `store.cacheResolvedPath`). (2) Update `desiredDirectory` to emit the date-partitioned layout so new + retagged meetings match. (3) Make `moveMeeting`/`handleTagChange` layout-aware (don't relocate by tag in the date-partitioned world — tag is metadata, not path). (4) Only set the completed flag if the move count == discovered count; otherwise leave `needsLayoutMigration = true`.
**Tests to add:** `VaultMigrationManagerTests`: seed a tag-layout vault, migrate, assert (a) every meeting.json `relativeFolderPath` points under `meetings/yyyy/yyyy-MM/`, (b) `directory(for:)` resolves without a tree walk, (c) flag stays false if a move is blocked by a pre-existing dest.

### [P1] `transcribeNow` vs `finalize` can both run for the same meeting, racing on `transcript.md`
**Files:** `MeetingPipelineController.swift:56-62` (finalize inserts into `transcribingIDs`), `:154-165` (transcribeNow guards on `transcribingIDs`), `MeetingManager.swift:339-355` (finalize runs detached after stop)
**Problem:** `transcribeNow` guards against re-entry via `transcribingIDs` (`:155`), and `finalize` also inserts the id (`:61`). But finalize runs on a **detached task kicked off after `stopRecording` returns** (`MeetingManager.swift:339`), and `lastStoppedMeetingID` is published *before* finalize starts. The UI surfaces the just-stopped meeting immediately; if the user hits "Transcribe Now" on it in the window between stop and finalize inserting the id, `transcribeNow`'s guard passes, and both pipelines run concurrently — both call `AudioRecorder.mergeSegments` on the same `audio/` dir and both `writeTranscript`. Last-writer-wins on `transcript.md`, and the two merges can interleave on the same output files.
**Root cause:** The de-dup set is populated only once each pipeline actually starts its async body; there's no claim taken synchronously at the moment the meeting becomes user-actionable.
**Why it matters:** Corrupted/short merged audio and a transcript that flip-flops; this is the old "stop/finalize vs Transcribe Now race," still reachable.
**Fix:** Insert the meeting id into `transcribingIDs` **synchronously inside `stopRecording` on the main actor** before dispatching finalize, so any concurrent `transcribeNow` is correctly rejected. Make `mergeSegments` write to a temp file + atomic rename to avoid interleaved partial outputs.
**Tests to add:** Concurrency test driving `finalize` and `transcribeNow` for the same id; assert only one runs and `transcript.md` is internally consistent.

### [P1] Whisper model auto-download has no integrity verification (size-only check)
**File:** `Transcription/WhisperRunner.swift:306-369`
**Problem:** `tryAutoDownloadBaseEnModel` validates only HTTP 200 and `size > 10_000_000`. There is **no SHA-256 / checksum verification** against a known-good digest. A truncated transfer (≥10 MB), a CDN/HF error body, a proxy-injected page, or a corrupted-but-large file passes and is atomically installed as the model. whisper-cpp then fails downstream with "bad magic / failed to load model" (the strings `LiveTranscriber.summarizeWhisperError` already special-cases — evidence this happens in the wild).
**Root cause:** Download verifies liveness/size, not content. This is the old "Whisper model download checksum" gap, still present.
**Why it matters:** Silent install of a corrupt model that breaks all transcription until the user manually nukes it.
**Fix:** Pin the expected SHA-256 of `ggml-base.en.bin`, hash the downloaded file (stream via `CryptoKit.SHA256`), reject on mismatch and delete the scratch file. Optionally verify the ggml magic header bytes as a cheap pre-check.
**Tests to add:** `WhisperRunnerTests`: feed a wrong-content file of valid size to the installer and assert it's rejected and removed.

### [P1] No CloudKit/iCloud *backup* exists, but the rebuild docs imply one; iCloud paths only do file-coordination download
**Files:** `Sources/MeetingScribe/Backup/` (empty directory), `Sync/iCloudInboxWatcher.swift`, `Audio/AudioRecovery.swift` (`ensureDownloaded`)
**Problem:** There is **no CloudKit code anywhere** (`grep CKContainer/accountStatus` → 0 hits) and the `Backup/` directory is empty. The only "iCloud" behavior is: (a) `iCloudInboxWatcher` polling `_inbox/` via `NSMetadataQuery`, and (b) `AudioRecovery.ensureDownloaded` calling `startDownloadingUbiquitousItem`. So "iCloud backup" is really "the vault may live in an iCloud Drive folder, and we download evicted files on demand." If any UI/onboarding/marketing claims backup, it **misreports status** — there's no backup subsystem, no account-status check, no upload verification.
**Why it matters:** Users may believe recordings are backed up when they're only stored in whatever folder they chose. If that folder isn't iCloud Drive, there is zero redundancy.
**Fix:** Either implement a real backup target (CloudKit assets or an explicit export) with an honest status surface, or remove every "backup" affordance and state plainly "stored locally; place your vault in iCloud Drive for sync." Don't show a backup status that isn't backed by code.
**Tests to add:** N/A (architectural); add an assertion that any "backup status" string is derived from a real reachability check, not a stub.

### [P2] `iCloudInboxWatcher.processedIDs` grows unbounded and is persisted on every item
**File:** `Sync/iCloudInboxWatcher.swift:14-15, 90, 140-160`
**Problem:** `processedIDs` is an ever-growing `Set<String>` written to `.processed_ids.json` (atomic) on every processed item. Over months of iPhone-Shortcut drops this set and its rewrite cost grow without bound. Also `moveToProcessed` can fail silently (`try?`), leaving a file in `_inbox/` that will be re-detected but skipped by `processedIDs` — orphaned forever.
**Fix:** Cap/prune `processedIDs` (e.g. keep last N, or rely on the moved-to-`processed/` folder as the dedup source of truth). Log/handle `moveItem` failures.

### [P2] `recordingStopped` Darwin observer rewrites transcript with un-flushed live render (same root cause as P0 above)
**File:** `MeetingManager.swift:135-148`
**Problem:** The ScribeCore stop path calls `renderMarkdown()` and `writeTranscript` directly in the notification handler — same un-flushed-live-chunks problem as the direct path, and it does **not** run the finalize pipeline's batch fallback at all on this branch (it just writes live and goes idle). So ScribeCore-handled recordings get *only* the (truncated) live transcript with no batch recovery.
**Fix:** Route both paths through one finalize entry point that flushes live, then decides on batch fallback.

---

# ENG-4 — Code Quality, Maintainability & Tech Debt

### [P1] ~25 source files are physically duplicated between `Sources/MeetingScribe/` and `Sources/ScribeCore/` — and they have already drifted
**Files:** `Package.swift:68-80` (ScribeCore target with a 5-file `exclude` list), plus the duplicated tree:
`Audio/AudioRecorder.swift`, `Audio/MicRecorder.swift`, `Audio/SystemAudioRecorder.swift`, `Audio/ChunkedAudioWriter.swift`, `Audio/AudioRecovery.swift`, `Audio/PassthroughAudioMerger.swift`, `Audio/SampleBufferConverter.swift`, `Audio/AudioBufferAnalysis.swift`, `Audio/AudioCounters.swift`, `Audio/MicOnlyRecorder.swift`, `Transcription/WhisperRunner.swift`, `Transcription/WhisperTranscriber.swift`, `Transcription/LiveTranscriber.swift`, `Transcription/QuickTranscribe.swift`, `Transcription/SpeakerDiarization.swift`, `Transcription/TranscriptPolisher.swift`, `Transcription/TranscriptionLog.swift`, `AI/OllamaService.swift`, `RecordingMonitor.swift`, `Detection/*.swift`, `Notifications/NotificationManager.swift`, etc.
**Problem:** These are **real copies, not symlinks** (verified: distinct inodes, different mtimes). And they have **already diverged** — `diff` shows `MeetingScribe/.../LiveTranscriber.swift` uses `AppLog`/`ErrorReporter` while `ScribeCore/.../LiveTranscriber.swift` uses raw `os.Logger`; `AudioRecorder.swift` and `WhisperRunner.swift` also differ between the two. A bug fixed in one copy stays broken in the other.
**Root cause:** ScribeCore (the IPC daemon) and the app each compile their own copy of the audio/transcription stack instead of sharing a library target. The `commonSwiftSettings` and `VaultKit` extraction stopped at the model layer; the heavy audio/AI logic was never libraryized.
**Why it matters:** This is the single biggest maintainability hazard in the codebase. The whisper-truncation (ENG-3 P0) and checksum (ENG-3 P1) bugs each have to be fixed in **two** places, and the drift means they may already behave differently across the app vs the daemon.
**Fix:** Extract the audio + transcription + AI stack into a new library target (e.g. `CaptureKit`) depended on by both `MeetingScribe` and `ScribeCore`. Delete the duplicate trees. The `exclude:` list in Package.swift becomes unnecessary once the daemon-only controllers live behind the shared lib's API.
**Tests to add:** A CI guard script that fails if any file path exists under both `Sources/MeetingScribe/` and `Sources/ScribeCore/` (prevents regression of the duplication).

### [P1] God-files remain in the People subsystem
**Files:** `People/PeopleStore.swift` (1177 lines), `People/PersonDetailView.swift` (1208 lines), `MeetingManager.swift` (869), `MeetingScribeMCP/main.swift` (1081)
**Problem:** The rebuild split MeetingManager but left equally large god-objects elsewhere. `PersonDetailView` at 1208 lines is the largest view in the app; `PeopleStore` at 1177 mixes FTS indexing, graph, persistence, and import.
**Fix:** Apply the same sub-controller treatment used on MeetingManager to `PeopleStore` (split store / index / graph) and decompose `PersonDetailView` into sections.

### [P2] `desiredDirectory` doc-comment and actual layout contradict the migration target
**Files:** `MeetingStore.swift:8` (doc says `<storageDir>/<TagFolder>/<slug>/`) vs `VaultMigrationManager.swift` (migrates to `meetings/yyyy/yyyy-MM/<slug>/`)
**Problem:** Documentation describes the pre-migration layout as if current; nothing documents the post-migration target or that both can coexist. (Underlying behavior bug covered in ENG-3 P0.)
**Fix:** Single source of truth for the on-disk layout; update the doc-comment and make code match.

### [P2] Forwarding shims (cross-ref ENG-1 P2) and `delete_dead_code.sh` / `setup_refactor_repo.sh` at repo root
**Files:** repo root `delete_dead_code.sh`, `setup_refactor_repo.sh`, multiple `MASTER_PLAN*.md`
**Problem:** One-off scripts and competing planning docs (`MASTER_PLAN.md`, `MASTER_PLAN_V2.md`, `HANDOFF.md`) at the package root add noise and ambiguity about the source of truth.
**Fix:** Move scratch scripts under `scripts/`, archive superseded plans.

---

# ENG-5 — Security/Privacy, Error Handling & Testing/CI

### [P1] CI only runs on release tags (and manual dispatch) — never on PRs or pushes to main
**File:** `.github/workflows/release.yml:13-16`
**Problem:** The **only** workflow triggers on `push: tags: ['v*']` and `workflow_dispatch`. There is no `pull_request:` and no `push: branches: [main]`. So `swift test` runs **only when you cut a release** — the test job exists but never gates day-to-day commits. Broken code lands on `main` and is only caught at release time (when it's most expensive). This is the old "CI only on release tags" issue, unchanged.
**Root cause:** Single release-oriented workflow; no separate CI workflow.
**Why it matters:** The test suite (modest as it is) provides zero protection during development. Combined with the duplicate-file drift (ENG-4) and absence of a build job on PRs, regressions are invisible until release.
**Fix:** Add `.github/workflows/ci.yml` triggered on `pull_request` and `push: branches: [main]` that runs `swift build` + `swift test` (and ideally `swift test --sanitize=thread` given the concurrency surface). Keep `release.yml` for tagged releases only.
**Tests to add:** N/A — this is the CI fix itself. Add a `swift build -c release` step so non-compiling code is blocked on PR.

### [P1] Test coverage is thin and skips the highest-risk subsystems
**Files:** `Tests/MeetingScribeTests/*` (5 files; `PlaceholderTests` literally says real tests are "added in Batch 8")
**Problem:** Existing tests cover `ActionItemExtractor`, `AudioCounters`, `MeetingStore` index, `MeetingManager` init, and JSON round-trips. There are **no tests** for: the whisper JSON parser (`WhisperRunner.parse`), the transcript-truncation/flush path, the finalize-vs-transcribeNow race, vault migration, the transcript parser (`TranscriptParser.parse`), or the inbox watcher. The two P0 data-loss bugs above live in exactly the untested code.
**Fix:** Prioritize tests for the data-integrity paths: `WhisperRunner.parse` (segments + plainText + malformed JSON), `LiveTranscriber.flush`, `VaultMigrationManager`, `TranscriptParser` (the regex at `TranscriptSyncView.swift:29`), and a finalize/transcribeNow concurrency test. These are named per-finding above.

### [P2] Pervasive `try?` swallows errors on the write/move paths
**Files:** `MeetingManager.swift:141, 332, 552, 595, 681`; `VaultMigrationManager.swift:80`; `MeetingStore.swift` (transcript/notes/summary writes); `iCloudInboxWatcher.swift:139`
**Problem:** Transcript/summary/notes/meeting-json writes and folder moves use `try?`, discarding failures. A full disk, permission error, or iCloud-evicted parent silently no-ops — the user sees stale data with no error surfaced. The migration's swallowed `moveItem` error (ENG-3 P0) is the most damaging instance.
**Fix:** Replace `try?` on persistence with real error handling routed through the existing `ErrorReporter` (which is used elsewhere), and surface a user-visible warning on write failure for transcript/notes/summary.

### [P2] Whisper model fetched over network on first use with no user consent gate
**File:** `WhisperRunner.swift:272-279, 306`
**Problem:** First transcription silently downloads ~140 MB from HuggingFace. For a privacy-positioned local-first app, a silent outbound network fetch (even of a model) should be consented. Combined with the missing checksum (ENG-3 P1), it's also a supply-chain trust gap.
**Fix:** Gate the auto-download behind explicit onboarding consent ("Download the base.en model? ~140 MB"), pin the checksum, and consider bundling the model or offering an offline import.

### [P2] `URLSession(configuration: .ephemeral)` download has a 600 s timeout but no resume/retry
**File:** `WhisperRunner.swift:323-327`
**Problem:** A flaky connection during the 140 MB download just fails (returns false → `modelMissing`), with no resumable download and no retry. The user must re-trigger transcription to retry, and any partial bytes are discarded.
**Fix:** Use a resumable background `URLSessionDownloadTask` with retry/backoff; surface progress.

---

## Prioritized cross-cutting summary

| # | Sev | Finding | Lens |
|---|-----|---------|------|
| 1 | P0 | Live transcript truncated at stop; batch fallback skipped → silent loss of final minutes of every transcript | ENG-3 |
| 2 | P0 | Vault migration half-wired: moves folders but not `relativeFolderPath`; new/retagged meetings still use old layout; partial migration marked complete | ENG-3 |
| 3 | P1 | ~25 audio/transcription files duplicated app vs ScribeCore and already drifted | ENG-4 |
| 4 | P1 | finalize vs Transcribe-Now race on `transcript.md` / merged audio | ENG-3 |
| 5 | P1 | Whisper model auto-download has no checksum (size-only) | ENG-3/ENG-5 |
| 6 | P1 | CI only runs on release tags — never on PRs/main | ENG-5 |
| 7 | P1 | MainWindow still opacity-ZStack tabs (not NavigationSplitView); Today/Calendar still inline expand/collapse | ENG-1 |
| 8 | P1 | No real backup subsystem (`Backup/` empty, no CloudKit) despite "vault/backup" framing | ENG-3 |
| 9 | P1 | `startRecording` publishes wrong meeting (`meeting` param vs `m`) into `.recording` | ENG-1 |
| 10 | P1 | Thin tests; data-integrity paths untested | ENG-5 |
