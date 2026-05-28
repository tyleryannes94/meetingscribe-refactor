# Phase 5 — Scale

## What was built/changed

1. **iCloud encrypted backup** — AES-256-GCM-encrypted archives written to the
   app's iCloud Drive ubiquity container, on a daily schedule.
2. **Team sync foundation** — a `TeamWorkspace` model + a `TeamSyncService`
   stub for CloudKit shared zones, with a settings UI.
3. **Windows research spike** — `WINDOWS_SPIKE.md` at the repo root.

## Files created / modified

**Created — Backup:**
- `Sources/MeetingScribe/Backup/BackupEncryption.swift` (AES-256-GCM via CryptoKit; keychain-managed key)
- `Sources/MeetingScribe/Backup/iCloudBackupManager.swift` (actor; ubiquity-container writes)
- `Sources/MeetingScribe/Backup/BackupScheduler.swift` (daily cadence, gated)
- `Sources/MeetingScribe/Backup/BackupSettingsView.swift`

**Created — Team:**
- `Sources/MeetingScribe/Team/TeamWorkspace.swift`
- `Sources/MeetingScribe/Team/TeamSyncService.swift` (actor stub)
- `Sources/MeetingScribe/Team/TeamSettingsView.swift`

**Created — repo root:**
- `WINDOWS_SPIKE.md`

**Modified:**
- (the Phase 0 foundation build fix carried onto this branch)

## How to use

- **Backup:** enable in `BackupSettingsView` (off by default). "Back up now"
  triggers an immediate encrypted backup; the scheduler then runs daily. The key
  is generated once and stored in the login keychain
  (`com.tyleryannes.MeetingScribe.backup`). The encrypted artifact is a storage
  *manifest* today (the encryption + iCloud-write path is complete; bundling the
  full file tree is a marked TODO).
- **Team:** `TeamSettingsView` lets you create a workspace, invite members by
  email, and list shared meetings — all in-memory until CloudKit shared zones
  are implemented.

## Notes for the next developer

- `iCloudBackupManager` requires the
  `com.apple.developer.icloud-container-identifiers` entitlement and an
  iCloud-signed build; without it `runBackup()` throws `.iCloudUnavailable`
  (handled gracefully in the UI).
- Encryption uses `AES.GCM` `combined` blobs (nonce ‖ ciphertext ‖ tag);
  `BackupEncryption.decrypt` reverses it. Date fields use ISO-8601 on both
  encode and decode (kept in sync).
- `TeamSyncService` methods carry `TODO(CloudKit)` markers indicating exactly
  where the shared-zone calls go.
- See `WINDOWS_SPIKE.md` for the cross-platform assessment (recommendation:
  Electron/Tauri wrapper reusing whisper.cpp + Ollama; ~6–8 months).
