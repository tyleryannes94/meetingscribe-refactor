# Phase 2 — Sync & iOS Foundations

## What was built/changed

1. **`SecondBrainCore` library target** — a dependency-free (Foundation-only)
   model layer so a future iOS app can share the Second Brain core.
2. **CloudKit sync stubs** — the `SyncStatus`/`CloudKitSyncEngine`/settings
   surface, ready for a real `CKSyncEngine` (macOS 15+) implementation.
3. **Quick Add `AppIntent` stub** — "create a meeting draft" from Spotlight/
   Shortcuts.

## Files created / modified

**Created — SecondBrainCore (new SPM target + library product):**
- `Sources/SecondBrainCore/Person.swift`
- `Sources/SecondBrainCore/Encounter.swift`
- `Sources/SecondBrainCore/SecondBrainStore.swift` (protocol + `InMemorySecondBrainStore`)
- `Sources/SecondBrainCore/SecondBrainCoreExports.swift`

**Created — Sync:**
- `Sources/MeetingScribe/Sync/SyncStatus.swift`
- `Sources/MeetingScribe/Sync/CloudKitSyncEngine.swift` (actor; `startSync`/`stopSync`/`syncNow`/`accountIsAvailable`)
- `Sources/MeetingScribe/Sync/SyncSettingsView.swift`

**Created — Widgets:**
- `Sources/MeetingScribe/Widgets/QuickAddWidget.swift` (`QuickAddMeetingIntent` + `AppShortcutsProvider`)

**Modified:**
- `Package.swift` — added `SecondBrainCore` target + library product
- (plus the Phase 0 foundation build fix)

## How to use

- **iCloud sync:** drop `SyncSettingsView()` into the Settings window. The
  toggle starts/stops the (stubbed) engine and shows status. Real sync is not
  active yet — `startSync()` reports `.upToDate` immediately.
- **Quick Add:** once the app is built and run, `QuickAddMeetingIntent` appears
  in Shortcuts/Spotlight as "Quick Add Meeting" (title → draft). The draft is
  acknowledged but not yet persisted (TODO marked in the file).

## Notes for the next developer

- `SecondBrainCore.Person` is intentionally separate from the app's existing
  `People.Person` (which has UI/storage ties). The library is **not yet wired
  into the app** to avoid name ambiguity — bridge them when the iOS app lands.
- `CloudKitSyncEngine` avoids any `CKSyncEngine` API so it compiles on the
  `.macOS(.v14)` target; the real implementation needs macOS 15 and the
  `iCloud.com.tyleryannes.MeetingScribe` container + entitlement.
- `QuickAddMeetingIntent.perform()` should post a draft to `MeetingManager`
  (AppIntents run outside the normal app lifecycle, so use NotificationCenter or
  a shared store).
