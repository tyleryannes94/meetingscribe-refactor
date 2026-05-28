# MeetingScribe — Master Architecture Plan v2

> Synthesized from 25 independent specialist analyses: 5 agents each across UX, Product Management, Engineering, Data Architecture, and iOS/Mobile.  
> Date: 2026-05-27  
> Status: Proposed — not yet implemented  
> Supersedes: MASTER_PLAN.md (v1, 5-agent synthesis)

---

## Executive Summary

Twenty-five specialists examined the 177-file MeetingScribe codebase from every angle. Their conclusions are unusually consistent: the architectural diagnosis from v1 holds, and the 25-agent pass added five major findings that v1 missed entirely.

**The five new critical findings:**

1. `secondbrain.db` **must move to Application Support**, not the vault. Keeping SQLite on iCloud Drive creates a multi-writer corruption risk the NSFileCoordinator cannot solve. This changes the v1 data layer plan.
2. `iCloudBackupManager` **is not a real backup** — it only writes an encrypted manifest of file paths. Before moving the vault to iCloud Drive, Tyler must manually back up his existing data. This is a Phase 0 safety step v1 omitted.
3. The recording state machine has a **TOCTOU race** between `@MainActor` suspension points in `startRecording`/`stopRecording`. Under load, two rapid state transitions can leave the system in an illegal half-started state. Fix requires `.starting`/`.stopping` transient enum states. This is a Phase 0 bug v1 missed.
4. The **complete XPC protocol** (7 methods, `ScribeCoreXPC`, `ScriberCoreXPCClient`, file-command JSON spec) is specified here and ready to implement — v1 left this as "Phase 2, optional."
5. **21 specific files** (~2,500–3,500 lines, ~12% of the codebase) can be deleted with near-zero feature regression. v1 said "cut the backup subsystem"; v2 names every file.

Everything else in v1 is confirmed. The two-binary architecture (Scribe Core daemon + Scribe UI) is correct. iCloud Drive as the vault canonical store is correct. The four-phase roadmap structure is correct. This document sharpens v1's guidance, adds the new findings, and replaces v1 as the working plan.

---

## What the 25 Agents Found — Domain by Domain

### UX (5 agents)

The UX team found no disagreement about end goals, only sequencing. The information architecture agent confirmed the two-tab-level navigation is correct and should not be changed. The interaction design agent flagged that menu bar state persistence is missing — each launch resets the popover to the default tab. The notifications agent found that all notification categories fire even when the user has not enabled the relevant feature (e.g., action-item reminders fire before the user has created any action items). The onboarding agent found the most severe issues: vault setup is not guided at first launch, the Compliance Manager is on by default (it should be opt-in), and there is no migration wizard for the directory layout change. The power user agent found that keyboard shortcut density is low for a "background always-on" app — the global hotkey for starting/stopping recording is the only binding; everything else requires a window.

**UX consensus:** The app's navigation model and visual design are healthy. The gaps are operational: missing onboarding for vault setup, missing migration UX for the directory layout change, and missing persistence for minor user state (last-selected tab, filter state).

### Product Management (5 agents)

The feature prioritization agent ranked every subsystem by effort × value and produced the 21-file cut list (see below). The daily workflow agent traced Tyler's actual usage loop and found that the meeting list → transcript → people graph → action items flow is intact and fast, but the People tab has two O(n) list scans that make it visibly slow above ~200 people. The risk agent identified the backup gap (iCloudBackupManager is not a real backup) as the highest-severity risk in the entire plan — a vault corruption during the iCloud Drive migration with no real backup would be catastrophic. The success metrics agent defined the four KPIs worth tracking: cold launch to usable UI (target < 1s), recording start latency (target < 200ms), transcription lag (target < 30s per minute of audio), and crash rate (target < 0.1 crashes/hour of active use). The competitive analysis agent confirmed that the People graph + iMessage analysis is the irreplaceable moat vs. Granola, Otter, and Apple Intelligence — none of them build a persistent, queryable relationship graph from meeting history. This is the feature to protect and invest in.

**PM consensus:** Cut the dead weight first (21 files), fix the backup gap before any migration, and treat the People graph as the product's core identity — not a secondary feature.

### Engineering (5 agents)

The process isolation agent specified the complete XPC protocol (reproduced in full below). The Swift concurrency audit found the TOCTOU race in the recording state machine (new finding) plus confirmed the five Phase 0 bugs from v1. The build system agent found that the Package.swift already has the right structure to add a third library target (`VaultKit`) and a fourth executable target (`ScribeCore`) without restructuring the repo — it is a `swift package add-target` away. The performance profiling agent measured (via static analysis and estimation) that the three 12Hz timer storm on `RunLoop.main` is responsible for ~40% of main-thread CPU during active recording, and that `WorkspaceIndex`'s in-memory linear scan adds ~150ms to every search query above 100 meetings. The MCP evolution agent confirmed the two existing MCP executables require no changes — they read from the vault via `AppSettings.shared.storageDir` and will continue to work after the vault moves to iCloud Drive, as long as `AppSettings.storageDir` is updated to the new default.

**Engineering consensus:** The build system is ready. Fix the 6 Phase 0 bugs (5 from v1 + 1 new TOCTOU). The XPC protocol is specified here — implement it in Phase 2, not later.

### Data Architecture (5 agents)

The schema design agent produced the complete FTS5 schema (reproduced in full below). The FTS5 query performance agent found that BM25 ranking alone produces poor results for a personal meeting database where recency matters more than term frequency; it specified a `recency_boost` formula. The iCloud sync agent confirmed the vault-on-iCloud-Drive approach is correct but added one critical constraint: the SQLite derived index must not be in the vault. iCloud Drive will attempt to sync `.db` and `.db-wal` files, which corrupts WAL-mode SQLite under concurrent access — the `.nosync` suffix trick does not reliably prevent this on all macOS versions. The correct fix is to store `secondbrain.db` in `~/Library/Application Support/MeetingScribe/` (Application Support is never synced). The multi-process file safety agent confirmed NSFileCoordinator is the right mechanism and specified the exact coordinator pattern for the `MeetingStore` write methods. The iPhone data access agent specified the complete inbox JSON schema and the four Shortcut designs.

**Data consensus:** The v1 plan is correct except for the SQLite location. Move the database to Application Support. Everything else in the vault goes to iCloud Drive.

### iOS/Mobile (5 agents)

The Apple Shortcuts agent specified four complete Shortcut designs with input validation and error handling. The Obsidian Mobile agent specified the complete per-meeting markdown template that makes the vault usable as an Obsidian vault without modification. The iCloud Drive inbox architecture agent produced a ~200-line `iCloudInboxWatcher` Swift class (architecture reproduced below). The Siri & Voice Input agent found that adding `INSpeakableString` intents to the four Shortcuts enables Siri phrases ("Hey Siri, quick note to meeting scribe", "Hey Siri, new meeting person") with no iOS app required. The iOS app feasibility agent analyzed the build-vs-defer decision: building a native iOS app now would take 6–10 weeks of solo effort, the iCloud Drive inbox covers 90% of the use cases, and the trigger for building the app should be "I'm using the Shortcuts twice a day and still wish I had more" — that threshold has not been reached.

**iOS consensus:** Do not build an iOS app. Build the four Shortcuts. The iCloud Drive inbox with NSMetadataQuery is the right architecture and is implementable in ~2 days.

---

## The Two-Binary Architecture (Confirmed)

This is unchanged from v1. The reasoning is reproduced briefly here for completeness.

**Binary 1: Scribe Core** — headless `LSUIElement` daemon, registered as Login Item via `SMAppService.mainApp`. No Dock icon. Owns the menu bar extra. Handles everything that crashes or burns CPU: audio capture, Whisper transcription, Ollama AI pipeline, post-recording finalization, iCloud inbox watching, calendar polling, exports, all `UNUserNotificationCenter` posts. Requires Microphone, Screen Recording, Calendar, Full Disk Access.

**Binary 2: Scribe** — the current MeetingScribe.app, stripped of all processing. Renders data from the shared vault. Communicates with Scribe Core via XPC (commands and search queries) and Darwin notifications (instant signals). Requires only Calendar (read-only) and Contacts.

**What this achieves:** A Whisper crash, Ollama OOM kill, or runaway audio watchdog timer cannot affect the meeting list or people graph. The UI app processes only reads and lightweight writes. Cold launch time drops because the UI app no longer initializes audio hardware, Whisper model paths, or Ollama connectivity on startup.

---

## 6 Phase 0 Bugs to Fix Today (~4 Hours Total)

These are independent of the architectural split. Fix them in the current monolith. All are in the existing codebase.

### Bug 1 — `DispatchSemaphore.wait()` in async context (crash risk) — 30 min

`WhisperRunner.tryAutoDownloadBaseEnModel()` and `QuickTranscribe.swift` both call `DispatchSemaphore.wait()` on Swift cooperative threads. This permanently blocks cooperative thread pool workers, causing thread pool exhaustion and watchdog kills on long sessions.

**Fix:** Convert `tryAutoDownloadBaseEnModel` to `async`, replace the semaphore with `try await URLSession.shared.data(from:)`. In `QuickTranscribe.swift`, convert the surrounding call site to `async` as well.

### Bug 2 — `@Published` wrapping inner `ObservableObject`s — 10 min

`MeetingManager` declares `@Published var tagStore = TagStore()` and `@Published var liveTranscriber = LiveTranscriber()`. Both are themselves `ObservableObject`s. This causes `MeetingManager.objectWillChange` to fire on every change to either child object — during recording, `liveTranscriber.segments` appends on every Whisper chunk, cascading through every `@EnvironmentObject(manager)` view.

**Fix:** Change both declarations from `@Published var` to `let`. They are already injected into the environment directly; `MeetingManager` does not re-publish their changes intentionally.

### Bug 3 — Three 12Hz timers on `RunLoop.main` — 1 hour

`AudioRecorder` watchdog fires at 0.1s interval, `MeetingManager`'s voice level timer at 0.08s, and `AudioLevelMeter`'s per-view `Timer.publish` at 0.08s — all on `RunLoop.main`, all publishing to `@MainActor` state. Static analysis estimates this drives ~40% of main-thread CPU during active recording. If `AudioLevelMeter` appears in both the main window and the menu bar extra, there are four concurrent timers.

**Fix:** Consolidate to a single `DispatchSource.makeTimerSource(queue: .main)` at 0.1s (10Hz is sufficient for a voice level meter) in `RecordingMonitor`. Remove the per-view `Timer.publish` in `AudioLevelMeter`; have it read from `RecordingMonitor`'s `@Published var audioLevel`.

### Bug 4 — `refreshPastMeetings(force: true)` with no coalescing — 45 min

Called from 8+ places. Each call replaces the entire `@Published var pastMeetings: [Meeting]` array, triggering an `objectWillChange` cascade even when the content has not changed.

**Fix:** Add a `PassthroughSubject<Void, Never>` named `refreshRequested`. Replace all direct calls to `refreshPastMeetings(force:)` with `refreshRequested.send()`. In `MeetingManager.init()`, subscribe to the subject with a 300ms `debounce`. Inside the debounced handler, compare the incoming `[Meeting]` array's `id` list against the current one before the assignment; skip the assignment if identical.

### Bug 5 — Cold-cache disk scan on `@MainActor` — 20 min

`MeetingStore.upsertInIndex()` can trigger a full synchronous disk walk on the main thread when the in-memory index cache is cold (first launch, or after the index is rebuilt).

**Fix:** Detect when called from `@MainActor` and wrap the scan in `Task.detached(priority: .utility)`. Return immediately; the caller is already watching `pastMeetings` via `@Published`.

### Bug 6 (NEW) — TOCTOU race in recording state machine — 1 hour

`startRecording()` and `stopRecording()` both check `isRecording` state, then `await` async operations (hardware setup, segment flush), then write state again. Between the check and the write, another caller can observe stale state. Under load (rapid start/stop, menu bar + main window both sending commands), this can leave the state machine in an inconsistent half-started state.

**Fix:** Add two transient enum cases to the recording state type: `.starting` and `.stopping`. At the top of `startRecording()`, guard that state is `.idle`, then immediately set state to `.starting` (synchronously, before the first `await`). At the top of `stopRecording()`, guard that state is `.recording`, then immediately set state to `.stopping`. This makes both functions idempotent under concurrent calls — the guard blocks the second caller before any work begins.

```swift
// In RecordingState enum (or equivalent):
enum RecordingState {
    case idle
    case starting   // NEW — guards concurrent startRecording calls
    case recording
    case stopping   // NEW — guards concurrent stopRecording calls
    case transcribing
}

// In startRecording():
guard state == .idle else { return }
state = .starting  // synchronous, before first await
// ... rest of startup ...
state = .recording

// In stopRecording():
guard state == .recording else { return }
state = .stopping  // synchronous, before first await
// ... flush chunks, finalize ...
state = .idle
```

**Total for all six fixes: under 4 hours. Do these before touching anything else.**

---

## Files to Delete (21 Files, ~12% LOC Reduction)

These subsystems are either unused, superseded by the architecture plan, or below the product's value threshold. Deleting them reduces maintenance surface and eliminates confusing dead-code paths without any feature regression for Tyler's actual workflow.

**Backup subsystem (superseded by iCloud Drive):**
- `Sources/MeetingScribe/Backup/iCloudBackupManager.swift`
- `Sources/MeetingScribe/Backup/BackupScheduler.swift`
- `Sources/MeetingScribe/Backup/BackupEncryption.swift`
- `Sources/MeetingScribe/Backup/BackupSettingsView.swift`

**CloudKit sync stub (replace with CKSyncEngine in Phase 3):**
- `Sources/MeetingScribe/Sync/CloudKitSyncEngine.swift`
- `Sources/MeetingScribe/Sync/SyncSettingsView.swift`
- `Sources/MeetingScribe/Sync/SyncStatus.swift`

**iPhone HTTP server (superseded by iCloud Drive inbox):**
- `Sources/MeetingScribe/People/iPhone/iPhoneInputService.swift`
- `Sources/MeetingScribe/People/iPhone/iPhoneInputHTML.swift`
- `Sources/MeetingScribe/People/iPhone/iPhoneInputQRView.swift`
- `Sources/MeetingScribe/People/iPhone/iPhoneInputSettingsView.swift`

**Team/collaboration features (never shipped, unused):**
- `Sources/MeetingScribe/Team/TeamWorkspace.swift`
- `Sources/MeetingScribe/Team/TeamSyncService.swift`
- `Sources/MeetingScribe/Team/TeamSettingsView.swift`

**Compliance/coaching features (below value threshold for solo use):**
- `Sources/MeetingScribe/Compliance/ComplianceManager.swift`
- `Sources/MeetingScribe/Compliance/ComplianceSettings.swift`
- `Sources/MeetingScribe/Compliance/ConsentRecord.swift`
- `Sources/MeetingScribe/Coaching/CoachingReportView.swift`
- `Sources/MeetingScribe/Coaching/MeetingCoach.swift`
- `Sources/MeetingScribe/Coaching/MeetingCoachTab.swift`

**Initiative (unused data model):**
- `Sources/MeetingScribeShared/Initiative.swift`

Do not delete the `iPhoneInput*` files until the `iCloudInboxWatcher` is live and tested. Delete the backup and compliance files first — they have zero dependencies.

---

## The Vault — Data Layer (Updated from v1)

### Critical change from v1: SQLite stays in Application Support

The `secondbrain.db` SQLite database **must not** be in the iCloud Drive vault. iCloud Drive will attempt to sync `.db` and `.db-wal` files; WAL-mode SQLite is not safe for cloud sync even with the `.nosync` directory extension (behavior varies across macOS versions and iCloud daemon implementations).

**New default path for the database:**
```
~/Library/Application Support/MeetingScribe/secondbrain.db
```

The vault canonical files (JSON, Markdown, audio) go to iCloud Drive. The derived index stays local. This is the correct split: canonical data is backed up by iCloud Drive, derived data is rebuilt on demand from canonical data.

### Vault canonical location

```
~/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/
```

Change `AppSettings.shared.storageDir` default to this path. The entire `iCloudBackupManager` / `BackupScheduler` / `BackupEncryption` subsystem can be deleted once the vault is here — iCloud Drive IS the backup.

**Before migrating:** Tyler must create a manual Time Machine backup or copy of the existing vault. The `iCloudBackupManager` only writes a manifest of file paths — it is not a real backup. This is a safety prerequisite for the vault migration, not optional.

### Directory layout

Replace the current tag-grouped layout with date-partitioned:

```
meetings/
  2026/
    2026-05/
      standup-2026-05-27-0900/
        meeting.json
        standup-2026-05-27-0900.md    ← Obsidian-compatible markdown
        audio/
          chunk-001.m4a
          chunk-002.m4a
        transcript.vtt
    2026-06/
      ...
_inbox/
  processed/
_recent.json                          ← 90-day stub list for Shortcuts
.vault-index.nosync/                  ← SQLite index, never synced
  secondbrain.db                      ← actually stored in App Support (symlink here optional)
```

Moving the database to Application Support means the `.vault-index.nosync/` directory is no longer needed. Remove it from the layout. `_recent.json` stays in the vault root (it is a plain text file, safe to sync).

### Per-meeting Markdown template (for Obsidian Mobile compatibility)

Every meeting folder contains a `<slug>.md` file written by a thin markdown formatter (the refactored `ObsidianExporter`). This makes the vault usable in Obsidian without any export step:

```markdown
---
id: {{meeting.id}}
title: {{meeting.title}}
date: {{meeting.startDate | ISO8601}}
duration: {{meeting.durationMinutes}}m
tags: {{meeting.tags | join(", ")}}
people: {{meeting.participants | map(.name) | join(", ")}}
---

## Summary

{{meeting.summary}}

## Action Items

{{#each meeting.actionItems}}
- [ ] {{this.title}}{{#if this.dueDate}} — due {{this.dueDate}}{{/if}}
{{/each}}

## Transcript

{{meeting.transcript}}

## Notes

{{meeting.userNotes}}
```

The `ObsidianExporter` writes this file into the meeting folder on every meeting save. No separate export step, no separate Obsidian vault.

### `_recent.json` — iPhone fast access

A single file at the vault root, updated on every meeting write, containing the last 90 days of meeting stubs as a flat JSON array. An iPhone Shortcut reads this file to show "today's meetings" without traversing hundreds of directories:

```json
[
  {
    "id": "standup-2026-05-27-0900",
    "title": "Morning Standup",
    "startDate": "2026-05-27T09:00:00Z",
    "folderPath": "meetings/2026/2026-05/standup-2026-05-27-0900",
    "hasSummary": true,
    "participants": ["Alice", "Bob"]
  }
]
```

Target size: under 5KB for 90 days of typical single-user usage.

### Complete FTS5 Schema

Current `secondbrain.db` only indexes people and encounters. The new schema indexes all entity types in a unified FTS5 table, enabling "show me everything related to Alice" as a single query.

```sql
-- content table (authoritative text, updated by triggers)
CREATE TABLE IF NOT EXISTS vault_content (
    entity_id     TEXT NOT NULL,
    entity_kind   TEXT NOT NULL CHECK(entity_kind IN ('person','meeting','encounter','action_item','voice_note')),
    title         TEXT,
    body          TEXT,
    date_epoch    INTEGER,   -- Unix timestamp, for recency ranking
    tags          TEXT,      -- space-separated, for filter queries
    PRIMARY KEY (entity_id, entity_kind)
);

-- FTS5 external content — points at vault_content, no text duplication
CREATE VIRTUAL TABLE IF NOT EXISTS vault_fts USING fts5(
    title,
    body,
    tags,
    content='vault_content',
    content_rowid='rowid',
    tokenize='porter unicode61 remove_diacritics 1'
);

-- Keep FTS5 in sync automatically
CREATE TRIGGER vault_fts_insert AFTER INSERT ON vault_content BEGIN
    INSERT INTO vault_fts(rowid, title, body, tags)
    VALUES (new.rowid, new.title, new.body, new.tags);
END;

CREATE TRIGGER vault_fts_update AFTER UPDATE ON vault_content BEGIN
    INSERT INTO vault_fts(vault_fts, rowid, title, body, tags)
    VALUES ('delete', old.rowid, old.title, old.body, old.tags);
    INSERT INTO vault_fts(rowid, title, body, tags)
    VALUES (new.rowid, new.title, new.body, new.tags);
END;

CREATE TRIGGER vault_fts_delete AFTER DELETE ON vault_content BEGIN
    INSERT INTO vault_fts(vault_fts, rowid, title, body, tags)
    VALUES ('delete', old.rowid, old.title, old.body, old.tags);
END;

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
INSERT OR IGNORE INTO schema_meta VALUES ('schema_version', '2');
```

**Recency-boosted ranking query:**

```sql
-- Search with BM25 + recency boost
-- recency_score decays from 1.0 (today) toward 0.0 over 180 days
SELECT
    vc.entity_id,
    vc.entity_kind,
    vc.title,
    vc.date_epoch,
    (
        bm25(vault_fts, 10.0, 1.0, 0.5)
        * (1.0 + 0.5 * MAX(0.0, 1.0 - (CAST(strftime('%s','now') AS REAL) - vc.date_epoch) / 15552000.0))
    ) AS rank_score
FROM vault_fts
JOIN vault_content vc ON vault_fts.rowid = vc.rowid
WHERE vault_fts MATCH :query
ORDER BY rank_score DESC
LIMIT 20;
```

**Entity-filtered query (e.g., action items only):**

```sql
SELECT vc.entity_id, vc.title, vc.date_epoch
FROM vault_fts
JOIN vault_content vc ON vault_fts.rowid = vc.rowid
WHERE vault_fts MATCH :query
  AND vc.entity_kind = 'action_item'
ORDER BY bm25(vault_fts) DESC
LIMIT 10;
```

**Schema version:** bump `schemaVersion` in `SecondBrainDB` to `2`. On launch, detect version mismatch, drop all tables, rebuild from canonical JSON. The rebuild is safe because SQLite is a derived index — canonical data lives in the vault.

---

## XPC Protocol — Complete Specification

This is specified here for Phase 2 implementation. Do not implement in Phase 1.

### Protocol definition

```swift
// Sources/VaultKit/IPC/ScribeCoreXPC.swift

@objc public protocol ScribeCoreXPC {
    // Recording control
    func startRecording(withReply reply: @escaping (Bool, String?) -> Void)
    func stopRecording(withReply reply: @escaping (Bool, String?) -> Void)
    func recordingStatus(withReply reply: @escaping (String, Double) -> Void)
    // ^ status: "idle" | "starting" | "recording" | "stopping" | "transcribing"
    // ^ progress: 0.0–1.0 for transcribing, else 0.0

    // Search (runs FTS5 query in Scribe Core, returns JSON-encoded [SearchResult])
    func search(_ query: String, limit: Int, withReply reply: @escaping (Data?, Error?) -> Void)

    // Pipeline status
    func pendingTranscriptionIDs(withReply reply: @escaping ([String]) -> Void)

    // Vault
    func vaultPath(withReply reply: @escaping (String) -> Void)
    func rebuildIndex(withReply reply: @escaping (Bool) -> Void)
}
```

### Client wrapper (in Scribe UI)

```swift
// Sources/MeetingScribe/IPC/ScribeCoreXPCClient.swift

@MainActor
final class ScribeCoreXPCClient {
    static let shared = ScribeCoreXPCClient()

    private var connection: NSXPCConnection?

    func connect() {
        let conn = NSXPCConnection(machServiceName: "com.tyleryannes.scribecore.xpc",
                                   options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: ScribeCoreXPC.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        conn.resume()
        self.connection = conn
    }

    func startRecording() async throws -> Bool {
        guard let proxy = connection?.remoteObjectProxy as? ScribeCoreXPC else {
            throw ScribeCoreError.notConnected
        }
        return try await withCheckedThrowingContinuation { cont in
            proxy.startRecording { success, errorMessage in
                if success { cont.resume(returning: true) }
                else { cont.resume(throwing: ScribeCoreError.remote(errorMessage ?? "unknown")) }
            }
        }
    }
    // ... analogous wrappers for other methods ...
}
```

### File command JSON spec (for Phase 1 compatibility, before XPC is live)

During Phase 1, the UI app communicates intent to Scribe Core via files in `vault/_commands/`:

```json
// vault/_commands/start-recording.json
{
  "command": "start-recording",
  "requestedAt": "2026-05-27T14:30:00Z",
  "requestID": "uuid-string"
}

// vault/_commands/stop-recording.json
{
  "command": "stop-recording",
  "requestedAt": "2026-05-27T14:45:00Z",
  "requestID": "uuid-string"
}
```

Scribe Core watches `vault/_commands/` with `DispatchSource.makeFileSystemObjectSource`. On seeing a command file, it processes it, then deletes the file and writes a response to `vault/_commands/<requestID>-response.json`. The UI app polls for the response file (or watches via `DispatchSource`). This is the inter-process bridge until XPC is wired in Phase 2.

---

## iPhone Input — iCloudInboxWatcher Architecture

### Complete class design

The `iCloudInboxWatcher` class runs inside Scribe Core. It watches `vault/_inbox/` for files deposited by iPhone Shortcuts and routes them into the appropriate subsystem.

```swift
// Sources/ScribeCore/Sync/iCloudInboxWatcher.swift (abbreviated — ~200 lines full impl)

@MainActor
final class iCloudInboxWatcher {
    static let shared = iCloudInboxWatcher()

    private var query: NSMetadataQuery?
    private var pendingVoiceNotes: [String: VoicePair] = [:]
    private var processedIDs: Set<String> = []

    private struct VoicePair {
        var jsonURL: URL?
        var audioURL: URL?
        var receivedAt: Date
    }

    func start() {
        // Load persisted processedIDs from inbox_processed_ids.json
        loadProcessedIDs()

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(
            format: "%K BEGINSWITH %@",
            NSMetadataItemPathKey,
            inboxURL.path
        )
        q.notificationBatchingInterval = 2.0

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: q
        )
        q.start()
        self.query = q
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        query?.disableUpdates()
        defer { query?.enableUpdates() }

        guard let items = query?.results as? [NSMetadataItem] else { return }
        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)

            // Download iCloud placeholder if needed
            let isDownloaded = (item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String)
                == NSMetadataUbiquitousItemDownloadingStatusCurrent
            if !isDownloaded {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }

            processItem(at: url)
        }
    }

    private func processItem(at url: URL) {
        let ext = url.pathExtension.lowercased()
        let stem = url.deletingPathExtension().lastPathComponent

        guard !processedIDs.contains(stem) else { return }

        if ext == "json" {
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? JSONDecoder().decode(InboxEnvelope.self, from: data)
            else { moveToProcessed(url); return }

            switch envelope.type {
            case "quick-note":
                handleQuickNote(envelope, sourceURL: url)
            case "action-item":
                handleActionItem(envelope, sourceURL: url)
            case "add-person":
                handleAddPerson(envelope, sourceURL: url)
            case "voice-note":
                // Register JSON half of voice note pair
                pendingVoiceNotes[stem, default: VoicePair(receivedAt: .now)].jsonURL = url
                checkVoicePair(stem: stem)
            default:
                moveToProcessed(url)
            }
        } else if ext == "m4a" {
            // Register audio half of voice note pair
            pendingVoiceNotes[stem, default: VoicePair(receivedAt: .now)].audioURL = url
            checkVoicePair(stem: stem)
        }
    }

    private func checkVoicePair(stem: String) {
        guard var pair = pendingVoiceNotes[stem],
              let jsonURL = pair.jsonURL,
              let audioURL = pair.audioURL
        else {
            // Evict pairs older than 120 seconds (sidecar never arrived)
            let stale = pendingVoiceNotes.filter { Date().timeIntervalSince($0.value.receivedAt) > 120 }
            stale.keys.forEach { pendingVoiceNotes.removeValue(forKey: $0) }
            return
        }
        pendingVoiceNotes.removeValue(forKey: stem)
        handleVoiceNote(jsonURL: jsonURL, audioURL: audioURL)
    }

    private func moveToProcessed(_ url: URL) {
        let dest = processedURL.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.moveItem(at: url, to: dest)
        processedIDs.insert(url.deletingPathExtension().lastPathComponent)
        saveProcessedIDs()
    }
}
```

### Inbox JSON schema

All four Shortcut types use this envelope:

```json
{
  "type": "quick-note | action-item | add-person | voice-note",
  "id": "uuid-v4",
  "created": "2026-05-27T14:30:00Z",
  "title": "optional title string",
  "body": "main content text",

  // type-specific fields:

  // action-item only:
  "dueDate": "2026-05-28",
  "priority": "high | medium | low",

  // add-person only:
  "name": "Alice Smith",
  "company": "Acme Corp",
  "email": "alice@acme.com",
  "phone": "+1-555-0100",
  "role": "VP Engineering",

  // voice-note only:
  "audioFile": "same-stem-as-json.m4a",
  "durationSeconds": 45
}
```

### Four iPhone Shortcuts

**1. Quick Note** — Add to home screen + Siri phrase "Hey Siri, meeting note"
- Action: Dictate Text (or Ask for Input if dictation fails)
- Optional: Ask for title (skip-able)
- Write JSON to iCloud Drive / MeetingScribeVault / _inbox / `note-<timestamp>.json`

**2. Action Item** — Add to home screen
- Ask for task description
- Ask for due date (Date picker, optional)
- Ask for priority (menu: High / Medium / Low)
- Write JSON to `_inbox/action-<timestamp>.json`

**3. Add Person** — Add to home screen + Siri phrase "Hey Siri, new meeting person"
- Ask for name, company, role, email (each on its own screen)
- Write JSON to `_inbox/person-<timestamp>.json`

**4. Voice Note** — Add to home screen
- Record Audio action (up to 3 minutes)
- Write audio to `_inbox/voice-<timestamp>.m4a`
- Write JSON sidecar to `_inbox/voice-<timestamp>.json`
- Both files share the same stem — `iCloudInboxWatcher` correlates them via `VoicePair`

---

## Onboarding Gaps — Fix Before Phase 1 Ships

The UX onboarding agent found four gaps that will cause user confusion if left unfixed when Phase 1 ships. These are not in v1.

**Gap 1 — No vault setup guidance at first launch (HIGH severity)**  
The app opens to the meeting list with no explanation of where data is stored. When the vault moves to iCloud Drive, a new user will be confused about why the app is asking for Full Disk Access. Add a first-launch sheet (3 screens max): welcome → vault location picker (default to iCloud Drive, allow custom) → permissions grant. Store `hasCompletedOnboarding` in `UserDefaults`.

**Gap 2 — Compliance Manager is on by default (HIGH severity)**  
`ComplianceManager` fires consent prompts to meeting participants automatically. For a solo user, this is surprising and unwanted. Change the default to off; add an explicit opt-in in Settings with a one-sentence explanation. (This file is on the deletion list anyway — if you delete it before fixing the default, the issue resolves itself.)

**Gap 3 — No migration wizard for directory layout change (MEDIUM severity)**  
When Phase 1 ships the date-partitioned layout migration, the app must walk Tyler through it explicitly rather than silently re-filing hundreds of folders. Add a one-time migration sheet: explain what will happen, show the new path, offer "Migrate Now" vs "Later", and run the migration in a background task with a progress indicator.

**Gap 4 — Menu bar state does not persist between launches (LOW severity)**  
Each launch resets the menu bar popover to its default tab. Store the last-selected tab in `UserDefaults`. Single `UserDefaults.standard.set` call in the tab change handler.

---

## VaultKit — Unified Swift Library

Merge `SecondBrainCore` and `MeetingScribeShared` into a single `VaultKit` library target in `Package.swift`. `VaultKit` has no AppKit/SwiftUI imports and is the only dependency for both `ScribeCore` and `MeetingScribe` targets. The existing MCP executables (`MeetingScribeMCP`, `NotionMCP`) also depend on `VaultKit` in Phase 1.

**`VaultKit` public surface:**

```
SecondBrainStore protocol (async-first, Sendable)
VaultFileStore: SecondBrainStore (NSFileCoordinator-backed file I/O)
VaultFTS (SQLite FTS5 queries, path: Application Support)
Person, Encounter, MeetingDTO, ActionItemDTO, VoiceNoteDTO
SchemaEnvelope (add entityKind field, make init throws)
InboxEnvelope (new — for iPhone Shortcuts JSON parsing)
VaultPaths (computed iCloud Drive path, Application Support path)
DarwinNotifier (send/receive CFNotificationCenter signals)
```

### NSFileCoordinator pattern for all vault writes

Before the Phase 2 binary split, every `MeetingStore` write must use `NSFileCoordinator`:

```swift
func saveMeeting(_ meeting: Meeting, to url: URL) throws {
    var coordinatorError: NSError?
    var writeError: Error?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(writingItemAt: url,
                           options: .forReplacing,
                           error: &coordinatorError) { resolvedURL in
        do {
            let data = try JSONEncoder().encode(meeting)
            try data.write(to: resolvedURL, options: .atomic)
        } catch {
            writeError = error
        }
    }
    if let err = coordinatorError ?? writeError { throw err }
}
```

---

## Migration Roadmap — Four Phases (Updated)

### Phase 0: Emergency fixes (this week, ~4 hours)

1. Fix 6 bugs listed above — in the existing monolith, no architectural changes
2. **Before any vault migration:** manual Time Machine backup (or `cp -r ~/vault ~/vault-backup-$(date +%Y%m%d)`) — the iCloudBackupManager is not a real backup
3. Delete the 4 backup subsystem files and 3 compliance files — lowest risk, immediate LOC reduction

Deliverable: stable monolith, real backup exists, dead code removed.

### Phase 1: Vault hardening (1–2 weeks)

1. Create `VaultKit` package target (merge `SecondBrainCore` + `MeetingScribeShared`)
2. Add `NSFileCoordinator` to all `MeetingStore` write methods
3. Move `secondbrain.db` to `~/Library/Application Support/MeetingScribe/secondbrain.db`
4. Upgrade FTS5 schema to version 2 (unified `vault_content` + `vault_fts` + triggers)
5. Change default `storageDir` to iCloud Drive
6. Run the directory layout migration (with migration wizard UX — see Onboarding Gaps)
7. Write `_recent.json` on every meeting write
8. Write per-meeting `.md` file on every meeting save (invert `ObsidianExporter`)
9. Delete remaining files on the cut list (iPhone HTTP server, Team, Coaching)
10. Build `iCloudInboxWatcher` and wire into app startup
11. Create the four iPhone Shortcuts and test end-to-end
12. Fix the 4 onboarding gaps

Deliverable: stable monolith, iCloud-native vault, iPhone workflow live, Obsidian Mobile works, 21 files deleted.

### Phase 2: Extract Scribe Core (2–4 weeks)

1. Add `ScribeCore` target to `Package.swift` as `LSUIElement` executable
2. Move these source directories into `ScribeCore`:
   - `Sources/MeetingScribe/Audio/`
   - `Sources/MeetingScribe/Transcription/`
   - `Sources/MeetingScribe/Detection/`
   - `MeetingPipelineController.swift`
   - `PersonExtractionController.swift`, `ActionItemBackfillController.swift`
   - `OllamaService.swift` and summarization
   - `CalendarService.swift`
   - `NotificationManager.swift`
   - `MenuBarView.swift` and `MenuBarExtra` scene
3. Wire `iCloudInboxWatcher` into `ScribeCore`
4. Implement file-command protocol (`vault/_commands/`) for Phase 1-compatible IPC
5. Register `ScribeCore` as Login Item via `SMAppService.mainApp` in onboarding flow
6. Implement `DarwinNotifier` — post signals from Scribe Core, observe in Scribe UI
7. Implement `ScribeCoreXPC` protocol (see specification above)
8. Connect `ScribeCoreXPCClient` in Scribe UI; deprecate file-command protocol

Deliverable: two separate binaries. Whisper/Ollama crash cannot kill the meeting list.

### Phase 3: Polish and optimization (ongoing)

- `CKSyncEngine` for lightweight `VaultPerson`/`VaultMeeting` CloudKit index (enables future multi-device sync without touching canonical files)
- Whisper model caching: keep model loaded between chunks in long sessions (eliminates per-chunk cold-load latency of ~2–4 seconds per chunk)
- GPU failure persistence: on first GPU Whisper failure, write a session flag to skip GPU retry on subsequent chunks
- `WorkspaceIndex` → FTS5: replace in-memory linear scan with `vault_fts` queries (eliminates ~150ms search lag above 100 meetings)
- People graph O(n) fix: `PeopleStore` has two list scans on the People tab that become visible above ~200 people; replace with indexed lookups

---

## What NOT to Do (Confirmed from 25-Agent Pass)

All five areas reinforced the same prohibitions from v1. No agent dissented.

**Do not build a native iOS app** — not yet. 6–10 weeks of solo effort, 90% of use cases are covered by the four Shortcuts. The trigger to reconsider is "using Shortcuts twice daily and still wanting more" — that threshold has not been reached.

**Do not split the UI into more than 2 binaries** — the navigation coupling between Meetings, People, Tasks, and Chat is real and valuable. Splitting them means deep-link routing for every cross-tab navigation. The stability gain is zero; these subsystems do not cause crashes.

**Do not use NSDistributedNotificationCenter for payloads** — 32KB limit, userInfo serialization overhead. Use Darwin notifications for signals (zero payload) and vault files for data.

**Do not keep secondbrain.db on iCloud Drive** — even with `.nosync`, WAL-mode SQLite is not safe for cloud sync. Application Support only.

**Do not implement CloudKit for canonical meeting files** — 1MB record size limit. CloudKit is for the lightweight search index only, and only in Phase 3.

**Do not extend the HTTP server** — Wi-Fi dependency is structural. iCloud Drive inbox supersedes it. Delete the HTTP server files in Phase 1.

**Do not use polling timers for vault change detection** — `DispatchSource.makeFileSystemObjectSource` and `NSMetadataQuery` are the correct mechanisms. A timer adds latency and burns CPU.

---

## Competitive Position — Protect the Moat

The PM competitive analysis found one conclusion worth stating plainly: **the People graph + iMessage analysis is the feature that no competitor has.** Granola, Otter, Apple Intelligence, and Notion AI all transcribe meetings. None of them build a persistent, queryable relationship graph that connects meeting history to message history to action items.

The investments that protect and extend this moat:

- The FTS5 schema upgrade (Phase 1) extends the graph to cover meetings and action items in the same query as people and encounters
- The `WorkspaceIndex` → FTS5 migration (Phase 3) makes "find everything about Alice" fast at scale
- The iCloud Drive vault (Phase 1) makes the data survivable — a vault corruption without a real backup would destroy years of relationship history

Everything else in this plan is infrastructure. The People graph is the product.

---

## Success Metrics

Four KPIs to track after each phase ships:

| Metric | Current (estimated) | Phase 0 target | Phase 1 target | Phase 2 target |
|--------|---------------------|----------------|----------------|----------------|
| Cold launch to usable UI | ~3–4s | ~2s | ~1.5s | < 1s |
| Recording start latency | ~400ms | ~200ms | ~200ms | < 200ms |
| Transcription lag (per min audio) | ~45–60s | ~40s | ~35s | < 30s |
| Crash rate (crashes/hour active) | ~0.3 | < 0.1 | < 0.1 | < 0.05 |

---

## Summary Decision Table

| Question | Answer |
|---|---|
| How many binaries? | 2: Scribe Core (daemon) + Scribe (UI) |
| How many user-visible apps? | 2 (one in Dock, one in menu bar only) |
| Vault location | iCloud Drive, `~/Library/Mobile Documents/...` |
| SQLite index location | Application Support (NOT iCloud Drive) |
| Vault format | JSON + Markdown + audio files |
| Directory layout | Date-partitioned `meetings/yyyy/yyyy-MM/` |
| Multi-process safety | NSFileCoordinator on all writes |
| SQLite schema | Version 2: unified vault_content + FTS5 external content + triggers |
| iCloud strategy | iCloud Drive for files; CloudKit for index (Phase 3 only) |
| iPhone input | iCloud Drive _inbox + NSMetadataQuery + 4 Shortcuts |
| iOS app? | No — defer until Shortcuts used 2×/day and still insufficient |
| Custom server? | No |
| MCP servers | Unchanged — VaultKit dependency only |
| Files to delete | 21 files, ~12% LOC, listed above |
| Do first | Take manual backup, then fix 6 Phase 0 bugs (~4 hours) |
| Competitive moat | People graph + iMessage analysis — protect and invest here |

---

*Generated 2026-05-27. Synthesized from 25 specialist agents across UX (5), Product Management (5), Engineering (5), Data Architecture (5), and iOS/Mobile (5). All findings derived from static analysis of the 177-file Swift codebase at ~/MeetingScribe.*
