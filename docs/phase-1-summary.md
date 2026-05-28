# Phase 1 — Quality

## What was built/changed

1. **Notarization prep + docs.** Confirmed the project already has the right
   pieces (Hardened Runtime via `--options runtime` in the Makefile, a correct
   `Resources/Entitlements.plist`, bundle id `com.tyleryannes.MeetingScribe`).
   Added `NOTARIZATION.md` with the `notarytool`/`stapler` steps.
2. **`@Observable` migration (partial, deliberate).** Migrated the two
   ViewModel classes off `ObservableObject`/`@Published` to the modern
   `@Observable` macro.
3. **Test target.** It already existed; added `MeetingManagerTests`.

## Files created / modified

**Created:**
- `NOTARIZATION.md`
- `Tests/MeetingScribeTests/MeetingManagerTests.swift`

**Modified:**
- `Sources/MeetingScribe/UI/ActionItemsViewModel.swift` — `@Observable`, dropped `@Published`, `import Observation`
- `Sources/MeetingScribe/UI/MeetingDetailViewModel.swift` — same
- (plus the Phase 0 foundation build fix carried onto this branch)

## How to use

- **Notarizing a build:** follow `NOTARIZATION.md` — sign with a Developer ID
  identity, `xcrun notarytool submit … --wait`, then `xcrun stapler staple`.
- No user-facing app changes.

## Important deviations / notes for the next developer

- **`@Observable` is intentionally partial.** Only `ActionItemsViewModel` and
  `MeetingDetailViewModel` were migrated — they have **zero consumers** (vestigial
  scaffolding from a prior "Batch 7"), so the migration is fully self-contained
  and verifiable.
- **`MeetingManager` was deliberately NOT migrated.** It's `@EnvironmentObject`
  in ~19 views and has Combine `$`-publisher subscribers in `FloatingOverlay`
  (`manager.quickNotesController.$state`, `.dictation.$state`, `.$notes`). Those
  break under `@Observable` (Observation has no `$` publisher). A full migration
  must rewire those sinks and all 19 environment injections — it warrants its own
  runtime-tested PR, not a blind change.
- **Entitlements:** did NOT create a sandboxed `MeetingScribe.entitlements`
  (`app-sandbox=true` would break ScreenCaptureKit + the bundled MCP helpers;
  `network.client` is a no-op when unsandboxed). The existing Hardened-Runtime,
  non-sandboxed setup is correct for notarization.
- Tests run on CI (`macos-14`); locally they need full Xcode for `XCTest`.
