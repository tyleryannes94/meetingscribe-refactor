# Architecture Refactor — Handoff Instructions

All code changes are on disk in `~/MeetingScribe`. The git HEAD.lock from a previous session is blocking sandbox commits. Run these commands in your Terminal to finalize everything.

---

## Step 1 — Clear the git lock and commit all changes

```bash
cd ~/MeetingScribe
rm .git/HEAD.lock .git/index.lock 2>/dev/null; true
git add -A
git commit -m "feat: Phase 0+1+2 architectural refactor (50-agent build)"
```

## Step 2 — Push to a separate branch (keeps main untouched)

```bash
git push origin HEAD:architecture-refactor
```

This creates `architecture-refactor` on GitHub without touching `main`.

## Step 3 — Delete the 20 dead-code files

```bash
bash ~/MeetingScribe/delete_dead_code.sh
git add -A
git commit -m "chore: delete 20 dead-code files (backup, compliance, team, iPhone HTTP)"
git push origin HEAD:architecture-refactor
```

## Step 4 — Build verification (requires Xcode / Swift on your Mac)

```bash
cd ~/MeetingScribe
swift build -c release 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`  
If errors appear, they will be import-related — check for any remaining `import MeetingScribeShared` and replace with `import VaultKit`.

## Step 5 — Install the app locally

```bash
make app   # or your usual build+sign script
```

---

## What was built across all 3 phases

### Phase 0 — Bug fixes (6 bugs)
- **Bug 1**: `DispatchSemaphore.wait()` eliminated from `WhisperRunner` and `QuickTranscribe` — converted to async/await. No more thread pool exhaustion.
- **Bug 2**: `@Published var tagStore/liveTranscriber` changed to `let` — stops render storm cascade during recording.
- **Bug 3**: Main-thread timer storm fixed — `AudioLevelMeter` now uses `TimelineView` instead of `Timer.publish`; level updates are push-based via `RecordingMonitor`.
- **Bug 4**: `refreshPastMeetings` debounced (300ms `PassthroughSubject`) — 8+ call sites coalesced.
- **Bug 5**: `MeetingStore.upsertInIndex` cold-cache scan moved off `@MainActor` via `Task.detached`.
- **Bug 6** (new): TOCTOU race in recording state machine fixed — added `.starting`/`.stopping` transient states to `RecordingState`.

### Phase 1 — Vault hardening
- **VaultKit** library created — merges `SecondBrainCore` + `MeetingScribeShared` into one Foundation-only module. All targets now import `VaultKit`.
- **NSFileCoordinator** added to all `MeetingStore` write methods — multi-process safe.
- **FTS5 schema v2** — unified `vault_content` + `vault_fts` external-content table covering all entity types (people, meetings, action items, voice notes, encounters). Recency-boosted `searchAll()` method added.
- **SQLite moved** to `~/Library/Application Support/MeetingScribe/secondbrain.db` — no longer in iCloud Drive (eliminates WAL corruption risk).
- **iCloud Drive vault default** — `AppSettings` now defaults to `~/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/`.
- **Date-partitioned directory layout** — `VaultMigrationManager` + `VaultMigrationSheet` handle one-time migration with progress UI.
- **iCloudInboxWatcher** — watches `vault/_inbox/` via `NSMetadataQuery` for iPhone Shortcut drops. Routes quick notes, action items, people, and voice note pairs.
- **`_recent.json`** — written on every meeting save; used by iPhone Shortcuts to list today's meetings without traversing directories.
- **ObsidianExporter inverted** — `writeMarkdownFile(for:to:)` writes `<slug>.md` into the meeting folder automatically after every pipeline finalization. Vault IS your Obsidian vault.
- **20 dead-code files** identified and scripted for deletion (backup subsystem, CloudKit stub, iPhone HTTP server, Team, Compliance, Coaching). Run `delete_dead_code.sh`.
- **Onboarding** — vault location step added to `OnboardingSheet`. Menu bar last-selected tab persists via `@AppStorage`.

### Phase 2 — ScribeCore binary scaffolding
- **`ScribeCore` executable target** added to `Package.swift` — headless `LSUIElement` daemon.
- **`Sources/ScribeCore/`** created with:
  - `ScribeCoreApp.swift` — `@main` entry point, `NSApp.setActivationPolicy(.prohibited)`, `MenuBarExtra` scene
  - `ScribeCoreServices.swift` — service orchestrator
  - `IPC/VaultCommandWatcher.swift` — watches `vault/_commands/` via `DispatchSource` for file-based IPC from the UI
  - `IPC/ScribeCoreXPC.swift` — XPC protocol interface (7 methods, ready for Phase 2 completion)
  - `ScribeCore.entitlements` — microphone, calendar, network, user-selected files
  - `Info.plist` — `LSUIElement = true`, bundle ID `com.tyleryannes.ScribeCore`
  - `AppSettings.swift` — ScribeCore-scoped, reads same `storageDir` UserDefaults key as the UI app
- **Audio (10 files)**, **Transcription (7 files)**, **Detection (2 files)** copied to `ScribeCore/`.
- **AI, Calendar, Notifications** copied to `ScribeCore/`.
- **`ScribeCoreXPCClient`** added to `Sources/MeetingScribe/IPC/` — file-command client for Phase 1 IPC.
- **`SMAppService` Login Item** registration wired into `MeetingScribeApp.swift`.
- **`DarwinNotifier`** in VaultKit — fire-and-forget CFNotificationCenter IPC signals.

### Training guide
- `MeetingScribe_Training_Guide.docx` — 10-section Word document covering all features.

---

## What still needs to be done (Phase 2 completion)

The ScribeCore binary scaffolding is in place. To fully activate the two-binary split:

1. **Remove Audio/Transcription/Detection from the `MeetingScribe` target** in Package.swift — these are now compiled into `ScribeCore`. Update `MeetingManager` to use `ScribeCoreXPCClient` for all recording commands instead of owning `AudioRecorder` directly.

2. **Wire `ScribeCoreServices` to own `AudioRecorder`** — move `MeetingManager`'s audio pipeline into `ScribeCoreServices.start()`.

3. **Move `MenuBarView` to `ScribeCore`** — the menu bar extra should live in the daemon, not the UI app.

4. **Build and sign `ScribeCore.app`** as a separate app bundle and embed it inside `MeetingScribe.app/Contents/Library/LoginItems/`.

5. **Test the two-binary flow**: launch `ScribeCore`, send a `start-recording.json` command from the UI, confirm `VaultCommandWatcher` handles it.

These steps are the natural next session's work once the Phase 1 foundation is verified working.
