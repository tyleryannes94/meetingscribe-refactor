# MeetingScribe — Master Efficiency & Architecture Plan

> Synthesized from five independent specialist analyses of the codebase.  
> Date: 2026-05-27  
> Status: Proposed — not yet implemented

---

## Executive Summary

MeetingScribe is slowing down and crashing because a single process is trying to be five different things simultaneously: a real-time audio recorder, a Whisper transcription engine, an Ollama AI pipeline, a SwiftUI application, and a background sync daemon — all on `@MainActor`. The fix is architectural, not cosmetic. The plan below separates the work into two binaries, fixes the immediate crash and performance bugs that can be patched today, redesigns the data layer so it is iCloud-native and multi-process safe, and enables iPhone input with zero third-party infrastructure.

The single most important outcome: **a crash in audio capture or AI processing can never kill your meeting list again.**

---

## What the Five Agents Found — and Where They Disagree

All five agents agreed on three things: audio/AI processing must leave the main UI process; the vault should be iCloud Drive file-based with a SQLite derived index; and the iPhone strategy is iCloud Drive inbox + Apple Shortcuts, not a custom server or a full iOS app.

The one meaningful disagreement was about how many separate applications to create. Agent 1 (architecture) and Agent 5 (UX) both want separate apps, but Agent 1 recommends splitting on technical blast radius (Recorder + Brain), while Agent 5 recommends splitting on product identity (Core + Meetings + People + Tasks). After reconciliation, the right answer for a solo user is **two binaries, not four apps.** Splitting People and Tasks into their own `.app` bundles creates significant deep-linking overhead and three extra apps in the Dock for negligible reliability gain — those subsystems are tightly coupled UI that belongs together. The real crash source is the heavy processing, not the navigation tabs. Two binaries delivers 95% of the stability benefit at 20% of the migration cost.

---

## The Two-Binary Architecture

### Binary 1: Scribe Core (background daemon)

A headless `LSUIElement` app that registers as a Login Item via `SMAppService.mainApp`. It has no Dock icon. It owns the menu bar extra — the only persistent UI the user sees without opening a window. It handles everything that crashes or burns CPU:

- Audio capture (mic + system audio via ScreenCaptureKit)
- Whisper transcription (subprocess management of `whisper-cli`)  
- Ollama AI pipeline (summarization, action-item extraction, person extraction)
- Post-recording finalization (`MeetingPipelineController` logic)
- Export to Obsidian, Google Drive, Notion
- CloudKit sync engine
- iCloud Drive inbox watcher (NSMetadataQuery) for iPhone inputs
- Calendar polling and auto-record detection
- All `UNUserNotificationCenter` posts — Scribe Core is the only process that sends notifications

Scribe Core requires: Microphone, Screen Recording, Calendar access, and Full Disk Access for the vault. It never opens a window. A crash in Whisper, a memory spike from the Ollama pipeline, or a runaway audio watchdog timer has zero effect on the user's ability to browse their meeting history or people graph.

### Binary 2: Scribe (the UI app — current MeetingScribe.app, slimmed down)

The current MeetingScribe.app keeps all of its UI: meeting list, meeting detail (transcript, summary, notes, chat), people graph, action items board, quick notes, calendar tab, and settings. What it loses is all the processing work. It becomes a read-heavy application that renders data from the shared vault and communicates intent to Scribe Core via the shared vault (file drops) and Darwin notifications for instant signals.

This app is opened on demand. It does not auto-launch. It requires no system permissions beyond Calendar access (read-only, for the Calendar tab) and Contacts (for the People importer).

### Inter-Process Communication

Three layers, each for a different purpose:

**Darwin notifications** (`CFNotificationCenter.darwinNotify`) handle fire-and-forget signals with no payload: `com.tyleryannes.meetingscribe.recordingStarted`, `.recordingStopped`, `.transcriptionComplete`, `.vaultChanged`. These wake the UI app immediately when Scribe Core finishes work, so the meeting list refreshes the moment a new transcript is ready. Cost is essentially zero.

**The vault on disk** is the primary message bus for all data. When the UI app wants to trigger a recording, it writes an intent file to `vault/commands/start-recording.json`. Scribe Core watches that directory with `DispatchSource.makeFileSystemObjectSource`. This pattern avoids XPC complexity for simple commands. For responses, Scribe Core updates `meeting.json` and posts a Darwin notification; the UI app reads the updated file.

**XPC** (optional, Phase 2) for search: once the vault grows large, the UI app can connect to Scribe Core via `NSXPCConnection` to query the SQLite FTS5 index without loading it independently. For Phase 1, each process maintains its own SQLite derived index (both in WAL mode, so concurrent reads are safe).

### What the MCP Servers Change

The two existing MCP binaries (`MeetingScribeMCP`, `NotionMCP`) remain unchanged as separate executables. Their read paths already point at the vault via `AppSettings.shared.storageDir`. No changes needed. The MCP binary is the reason the vault-as-canonical-files approach is correct — it is already the data contract.

---

## Fix These Bugs Today (Before Any Architectural Split)

Agent 2 identified five critical bugs in the current monolith that cause crashes and slowness. These should be fixed immediately in the existing codebase, regardless of whether the architectural split happens.

**Bug 1 — `DispatchSemaphore.wait()` inside async context (active crash risk)**  
`WhisperRunner.tryAutoDownloadBaseEnModel()` and `QuickTranscribe.swift` both call `DispatchSemaphore.wait()` on Swift cooperative threads. This permanently blocks cooperative thread pool workers, causing thread pool exhaustion and watchdog kills. Fix: convert `tryAutoDownloadBaseEnModel` to an `async` function using `URLSession.data(from:)`. Estimated effort: 30 minutes.

**Bug 2 — `@Published var tagStore` and `@Published var liveTranscriber` inside `MeetingManager`**  
Both are themselves `ObservableObject`s. Wrapping them with `@Published` causes `MeetingManager.objectWillChange` to fire every time either object's own properties change — during recording, `liveTranscriber.segments` appends on every Whisper chunk, cascading through every `@EnvironmentObject(manager)` consumer in the view hierarchy. Fix: change both to `let`. They are already passed into the environment directly; `MeetingManager` does not need to republish their changes. This immediately cuts render invalidation frequency during recording by at least 50%. Estimated effort: 10 minutes.

**Bug 3 — Three concurrent 12Hz timers on the main run loop**  
The `AudioRecorder` watchdog fires at 0.1s, `MeetingManager`'s voice level timer at 0.08s, and `AudioLevelMeter`'s per-view `Timer.publish` at 0.08s — all on `RunLoop.main`, all publishing to `@MainActor` state. If `AudioLevelMeter` appears in both the main window and the menu bar extra, this is four timers. Fix: consolidate to one timer at 0.1s in `RecordingMonitor`; remove the per-view `Timer.publish` in `AudioLevelMeter` and have it read from the `RecordingMonitor` published value instead. Estimated effort: 1 hour.

**Bug 4 — `refreshPastMeetings(force: true)` called from 8+ places with no coalescing**  
Each call replaces the entire `@Published var pastMeetings: [Meeting]` array, firing an `objectWillChange` cascade regardless of whether the content changed. Fix: add a 300ms `PassthroughSubject + debounce` in front of the force path; add an identity check (compare `id` arrays) before the assignment. Estimated effort: 45 minutes.

**Bug 5 — Cold-cache disk scan on `@MainActor`**  
`MeetingStore.upsertInIndex()` can trigger a full synchronous disk walk on the main thread if the index cache is cold. Fix: wrap the scan in `Task.detached` when called from a context that could be `@MainActor`. Estimated effort: 20 minutes.

**Total for all five fixes: under 3 hours of work. Do these first.**

---

## The Vault — Data Layer Redesign

Agent 3 produced the clearest, most complete analysis here. The existing data layer is 90% correct; the changes needed are targeted.

### Adopt iCloud Drive as the canonical location

Change `AppSettings.shared.storageDir` to default to `~/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/`. This single change gives the user free backup, free sync to new Macs, and free iPhone access via the Files app and Obsidian Mobile — with no code changes beyond the default path. The entire Backup subsystem (`iCloudBackupManager`, `BackupScheduler`, `BackupEncryption`) can be deleted once the vault is in iCloud Drive. The AES key in the keychain goes with it.

### Replace tag-grouped directories with date-partitioned layout

The current `<TagFolder>/<slug>/` structure moves hundreds of folders when you rename a tag, generating thousands of iCloud sync events. Replace with `meetings/<yyyy>/<yyyy-MM>/<slug>/`. This is a one-time migration: scan existing directories, rename folders, rewrite `relativeFolderPath` in each `meeting.json`. The `MeetingStore.rebuildIndex()` method already has the scan logic needed.

### Add NSFileCoordinator to all vault writes

Before introducing a second process that touches the same files, wrap every `MeetingStore` write method in `NSFileCoordinator.coordinate(writingItemAt:options:error:byAccessor:)`. This is the Apple-correct mechanism for multi-process safe file I/O and is required before any architectural split.

### Make the Obsidian vault and the MeetingScribe vault the same folder

The `ObsidianExporter` today writes to an external vault as a one-way push. Invert this: the vault IS an Obsidian vault. Each meeting folder contains `<slug>.md` alongside `meeting.json`. No separate export step; the user just points Obsidian at the vault folder. The `ObsidianExporter` becomes a thin formatter that writes the markdown file into the existing meeting folder.

### Vault-level index file for iPhone fast access

Add a single `_recent.json` file at the vault root, updated on every meeting write, containing the last 90 days of meeting stubs (id, title, startDate, folderPath, hasSummary) as a flat JSON array. This is what an iPhone Shortcut reads to show "today's meetings" without traversing 200 directories. Under 5KB for 90 days of typical usage.

### The SQLite index stays derived and process-local

The existing `SecondBrainDB` design is correct: SQLite is a derived index rebuilt from canonical JSON, not the source of truth. WAL mode is already on. Each process maintains its own copy of the index (stored under `.vault-index.nosync/` — the `.nosync` extension tells iCloud not to sync this directory). The `rebuild-token` sentinel file pattern (a zero-byte file whose mtime is touched on any canonical write) lets each process cheaply detect "did anything change since I last rebuilt?" via file-attribute reading rather than traversing the entire vault.

Extend the existing schema to cover meetings and action items in the `vault_fts` FTS5 table alongside people and encounters. This enables "show me everything related to Alice" as a single query across all entity types.

### VaultKit — one shared Swift library

Merge `SecondBrainCore` and `MeetingScribeShared` into a single `VaultKit` Swift package target with no AppKit/SwiftUI imports. All split binaries import `VaultKit`. It contains: `SecondBrainStore` protocol, `Person`, `Encounter`, `MeetingDTO`, `SchemaEnvelope`, `VaultFileStore` (the NSFileCoordinator-backed implementation), and `VaultFTS` (the SQLite FTS5 layer). This is the architectural foundation that makes everything else possible.

---

## iPhone Input — The Right Approach

Agent 4's analysis was thorough. The recommendation is unambiguous.

### Primary: iCloud Drive inbox + NSMetadataQuery

Build an `iCloudInboxWatcher` class (~200 lines of Swift) that runs `NSMetadataQuery` on app launch in Scribe Core. It watches `vault/inbox/` for new `.json` and `.m4a` files, routes them by the `type` field, and moves processed files to `vault/inbox/processed/`. This is zero-infrastructure, free, works offline (queues until sync), requires no network configuration, and covers every input type.

JSON format for iPhone-deposited items is consistent and simple:
```json
{ "type": "add-person" | "voice-note" | "action-item" | "quick-note",
  "title": "...", "body": "...", "created": "ISO8601",
  ... type-specific fields ... }
```

### Four iPhone Shortcuts

Create these four Shortcuts on iPhone and add them to the home screen:
1. **Add Person** — asks for name/company/email, writes JSON to iCloud inbox
2. **Voice Note** — records audio, saves m4a + sidecar JSON to iCloud inbox
3. **Action Item** — asks for task + due date, writes JSON to iCloud inbox
4. **Quick Note** — ask for note text (or use "Dictate Text" for hands-free), writes JSON

Add Siri phrases to the two most-used ones ("Hey Siri, new meeting person", "Hey Siri, quick note").

### What to keep from existing phone infrastructure

The HTTP server (`iPhoneInputService`) is worth keeping as a secondary path — it gives instant feedback and supports photo capture. The Apple Notes importer (`AppleNotesImporter`) is excellent for the people-only case and should stay exactly as-is. Neither is the primary path.

Do not build an iOS app, do not stand up a server, do not use CloudKit Records from Shortcuts (no native support), do not use polling timers.

---

## Migration Roadmap — Four Phases

### Phase 0: Emergency fixes (this week, ~3 hours)

Fix the five bugs identified above in the existing monolith. These are independent of the architectural split and deliver immediate, measurable stability improvement. Ship them.

### Phase 1: Vault hardening (1–2 weeks)

1. Create `VaultKit` package target (merge `SecondBrainCore` + `MeetingScribeShared`)
2. Add `NSFileCoordinator` to all `MeetingStore` write methods
3. Change default `storageDir` to iCloud Drive
4. Migrate directory layout to date-partitioned `meetings/<yyyy>/<yyyy-MM>/`
5. Write `_recent.json` on every meeting write
6. Invert `ObsidianExporter` — vault IS the Obsidian vault
7. Delete `iCloudBackupManager` and `BackupScheduler` — iCloud Drive is the backup now
8. Build `iCloudInboxWatcher` for iPhone inputs
9. Create the four iPhone Shortcuts

At the end of Phase 1, the existing monolith is stable and the vault is iCloud-native. The iPhone workflow is live.

### Phase 2: Extract Scribe Core (2–4 weeks)

Create the `ScribeCore` target as an `LSUIElement` app. Move into it:
- `Sources/MeetingScribe/Audio/` (all audio subsystems)
- `Sources/MeetingScribe/Transcription/` (Whisper runner, transcriber, live transcriber)
- `Sources/MeetingScribe/Detection/` (AppDetector, AmbientMeetingDetector)
- `MeetingPipelineController` (post-stop finalization)
- `PersonExtractionController` and `ActionItemBackfillController`
- `OllamaService` and AI summarization
- `CalendarService` (polling loop)
- `NotificationManager`
- `MenuBarView` and the `MenuBarExtra` scene

Wire the existing `MeetingScribeApp.swift` shell to communicate with Scribe Core via Darwin notifications and vault command files. Register Scribe Core as a Login Item in the onboarding flow.

At the end of Phase 2, Scribe Core is a separate process. A Whisper crash cannot kill the meeting list. Memory pressure from AI inference does not affect the UI.

### Phase 3: Polish and optimization (ongoing)

- Implement `CKSyncEngine` for the lightweight `VaultPerson`/`VaultMeeting` CloudKit index
- Add XPC interface to Scribe Core for FTS5 search queries from the UI app
- Whisper model caching: keep model loaded between chunks in a long-running transcription session to eliminate the per-chunk cold-load latency
- GPU failure persistence: remember whether GPU Whisper succeeded per session, skip the GPU retry on subsequent chunks when it has failed

---

## What NOT to Do

Several ideas that sound good but should be rejected:

**Do not split the UI into four separate apps** (Meetings, People, Tasks, Notes as separate `.app` bundles). For a solo user, the navigation coupling between these views is real and valuable. The People graph links to meetings; the Tasks board links to meetings; the Chat needs both. Splitting them means implementing full deep-link routing for every navigation action and maintaining four sets of window management code. The stability win is zero — none of these subsystems cause crashes.

**Do not build a custom sync server.** iCloud Drive and CloudKit are free, reliable, and already trusted by iOS. A server adds hosting cost, auth complexity, and a new failure mode.

**Do not use `NSDistributedNotificationCenter` for payloads.** It has a documented 32KB limit and serializes through userInfo dictionaries. Use Darwin notifications for signals (no payload) and vault files for data.

**Do not extend the HTTP server to cover all input types.** The Wi-Fi dependency is fundamental, not fixable. The iCloud Drive inbox supersedes it for everything except photo capture.

**Do not implement CloudKit for the canonical meeting files.** CloudKit has a 1MB record size limit and is not designed for binary audio files. iCloud Drive handles those correctly. CloudKit is for the lightweight search index only.

---

## Summary Decision Table

| Question | Answer |
|---|---|
| How many binaries? | 2: Scribe Core (daemon) + Scribe (UI) |
| How many user-visible apps? | 2 (one in Dock, one in menu bar only) |
| Vault location | iCloud Drive, `~/Library/Mobile Documents/...` |
| Vault format | JSON + Markdown + audio files (same as today) |
| Directory layout | Date-partitioned `meetings/yyyy/yyyy-MM/` |
| Multi-process safety | NSFileCoordinator on all writes |
| SQLite index | Derived, process-local, WAL mode, FTS5 |
| iCloud strategy | iCloud Drive for files; CloudKit for index (Phase 3) |
| iPhone input | iCloud Drive inbox + NSMetadataQuery + 4 Shortcuts |
| iOS app? | No |
| Custom server? | No |
| MCP servers | Unchanged — already correct |
| Do first | Fix the 5 bugs in Phase 0 — ~3 hours |

---

*Generated 2026-05-27. All findings derived from static analysis of the 177-file Swift codebase at ~/MeetingScribe.*
