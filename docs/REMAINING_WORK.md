# MeetingScribe — Remaining Work (post scope-review)

> Companion to `MASTER_PLAN_V2.md` / `MASTER_PLAN_V3.md` / `AUDIT_REPORT_2026-05-30.md`.
> Written after the scope-review pass that landed ENG-A, the orphaned-target
> cleanup, the People spacing fix, and the MCP doc correction.
>
> **Why these items are here and not just "done":** every item below either (a)
> requires reconciling *intentional* per-target behavioral divergence, or (b)
> must be verified by actually recording → transcribing on a Mac. They can't be
> compiled or runtime-tested in the CI/scope-review sandbox (Linux, no Swift
> toolchain), and shipping them unverified would risk replacing a building app
> with a non-building one. Do them on the Mac, where `swift build -c release` /
> `make app` and a real record→stop→transcribe smoke test gate each step.

---

## Status of the scope-review pass

| Item | State |
|---|---|
| ENG-A — batch repair on dropped/short live transcript | ✅ Done (`needsBatchRepair` gate + threading + tests) |
| Orphaned `MeetingScribeShared` / `SecondBrainCore` targets | ✅ Deleted; tests + Package.swift repointed to VaultKit |
| Spent scripts (`delete_dead_code.sh`, `setup_refactor_repo.sh`) | ✅ Deleted |
| req #1 — People split-pane spacing | ✅ `NDS.splitPaneTopInset` shared by both panes |
| Docs — MCP described as 7 read-only tools | ✅ Corrected to 17 (12 read + 5 write) in README/ARCH/USER_GUIDE |
| ARCH-1 — CaptureKit extraction | ⏳ Below (needs Mac) |
| Phase 2 — two-binary activation | ⏳ Below (needs Mac) |
| iPhone Shortcuts | ⏳ Below (client-side, authored on iPhone) |
| V3 §4 — "best-in-class" feature ideas | ⏳ Below (optional, GUI-heavy) |

---

## 1. ARCH-1 — CaptureKit extraction (retire app↔daemon duplication)

**Current reality (verified during scope review):** of the 24 files in
`scripts/capturekit-dup-baseline.txt`, **22 are byte-identical** between
`Sources/MeetingScribe/…` and `Sources/ScribeCore/…`. Only **2 differ, and the
differences are intentional, not drift:**

- `Audio/AudioRecorder.swift` — the **app** imports `AppKit` and uses
  `NSWorkspace` to pause capture when the display sleeps; the **daemon**
  deliberately omits AppKit (headless, no NSWorkspace). ~33-line diff.
- `Notifications/NotificationManager.swift` — ~175-line diff. Per the Phase-2
  design the **daemon** is meant to become the *sole* notification poster, so
  the two copies legitimately do different things today.

So this is not a "flatten to identical" job — it needs a real shared library
with the per-target bits abstracted.

### Steps

1. **Create the target.** Add a `CaptureKit` library target to `Package.swift`,
   depending on `VaultKit`. It will import AVFoundation / ScreenCaptureKit /
   CoreMedia / EventKit / UserNotifications as needed (a macOS library target
   can; keep it off SwiftUI).

2. **Move the shared dependency leaves first.** The audio/transcription files
   reference `ErrorReporter`, `AppLog`, `AppSettings`, and DTOs
   (`MeetingHealthDTO`, …). These exist in *both* the app and daemon targets
   today, which is the real reason the files compile in both places. Move the
   shared ones into `CaptureKit` (or VaultKit) so there's a single definition,
   and delete the per-target copies. Do this **before** moving the big files —
   verify a build after this step alone.

3. **Move the 22 byte-identical files** from `Sources/MeetingScribe/{Audio,
   Transcription,Detection,Calendar,AI}` into `Sources/CaptureKit/…`, delete the
   `Sources/ScribeCore/…` copies, and have both executables depend on
   `CaptureKit`. (Calendar/AI are in the baseline but the daemon excludes some
   via `Package.swift` `exclude:` — keep those exclusions consistent.)

4. **Abstract the 2 diverged files:**
   - `AudioRecorder`: gate the NSWorkspace/display-sleep logic behind
     `#if canImport(AppKit)` **and** a stored `pauseOnDisplaySleep` flag the app
     sets true and the daemon leaves false — OR inject a tiny
     `DisplaySleepObserver` protocol (app provides an AppKit impl, daemon a
     no-op). Prefer the protocol; it's testable.
   - `NotificationManager`: decide ownership. Phase-2 target state is
     "daemon posts, app observes." Until Phase 2 lands, keep a single
     `NotificationManager` in CaptureKit whose `post…` methods are guarded by an
     `isPrimaryPoster` flag (daemon true, app false) so you don't double-post.

5. **Keep the CI guard honest.** `scripts/check-cross-tree-dupes.sh` +
   `capturekit-dup-baseline.txt` exist to block *new* dupes. As files leave the
   two trees, remove their baseline entries (the guard already fails on a stale
   baseline entry, which will remind you).

6. **Smoke test on the Mac:** `make app`, launch, record a 30-second meeting,
   stop, confirm transcript + summary + notification all fire from the
   daemon-owned path. This is the test CI can't run.

---

## 2. Phase 2 — activate the two-binary split

Scaffolding is already in place (`ScribeCore` target, `ScribeCoreApp`,
`ScribeCoreServices`, `IPC/VaultCommandWatcher`, `IPC/ScribeCoreXPC`,
`ScribeCoreXPCClient`, `DarwinNotifier`, `SMAppService` login-item registration,
and the `usingScribeCore` branch already present in
`MeetingManager.start/stopRecording`). What's left is to make the daemon the
real owner of capture. From `HANDOFF.md`, in order, each gated by a build:

1. **Move audio ownership to the daemon.** Wire `ScribeCoreServices.start()` to
   own the `AudioRecorder` + `LiveTranscriber`; have the UI's `MeetingManager`
   send start/stop via `ScribeCoreXPCClient` (currently the file-command bridge)
   instead of owning `audio` directly. The `usingScribeCore` path in
   `MeetingManager.stopRecording` already exists — extend it so finalize is
   driven entirely by the `recordingStopped` Darwin signal.

   ⚠️ **ENG-A interaction:** the ENG-A repair gate now lives in
   `MeetingPipelineController.finalize` and is fed `liveDroppedChunks /
   liveCoverageSeconds / recordedDuration` snapshotted in the *direct* stop
   path. When the daemon owns capture, those values live in the daemon's
   `LiveTranscriber`; thread them across the XPC/Darwin boundary (e.g. include
   them in the stop response or a small status file) so the repair gate still
   works in the daemon-owned path. Don't let Phase 2 silently regress ENG-A.

2. **Move `MenuBarView` + the `MenuBarExtra` scene into ScribeCore** so the menu
   bar lives in the always-running daemon, not the on-demand UI app.

3. **Build + sign `ScribeCore.app`** as its own bundle and embed it at
   `MeetingScribe.app/Contents/Library/LoginItems/ScribeCore.app` (update the
   `Makefile`; reuse the existing self-signed "MeetingScribe Local Signer"
   identity so TCC permissions survive).

4. **Promote XPC over the file bridge** once the daemon is stable (the protocol
   in `IPC/ScribeCoreXPC.swift` is already defined; wire the live
   `NSXPCConnection` in `ScribeCoreXPCClient`).

5. **Two-binary smoke test:** launch ScribeCore, send a start from the UI,
   confirm `VaultCommandWatcher` (or XPC) handles it, kill the daemon
   mid-record, confirm the UI's meeting list survives (the whole point).

---

## 3. iPhone Shortcuts (client-side)

The `iCloudInboxWatcher` + `_inbox/` JSON contract is already built and wired.
What's missing is the four Shortcuts themselves — these are authored in the iOS
Shortcuts app, not in this repo. Build them per the spec in
`MASTER_PLAN_V2.md` → "Four iPhone Shortcuts" (Quick Note, Action Item, Add
Person, Voice Note), each writing the documented envelope JSON to
`iCloud Drive / MeetingScribeVault / _inbox/`. Add Siri phrases to Quick Note
and Add Person. Export them and, optionally, commit the `.shortcut` files under
a new `Shortcuts/` dir for reproducibility.

---

## 4. V3 §4 — optional "best-in-class" ideas (not required fixes)

These are net-new features, GUI-heavy, and want runtime iteration:

- **Speaker-labeled transcript & summary** — `Transcription/SpeakerDiarization.swift`
  exists but isn't surfaced; attribute lines/action-items to speakers.
- **"Stay in touch" nudges** on Today — "haven't talked to X in N days" from
  message `lastDate` + meeting history; snooze/done.
- **Unified "find everything about X"** — wire FTS5 `searchAll()` into
  `GlobalSearchView` across people + meetings + tasks + messages.
- **Per-tag summary templates** — 1:1 vs all-hands vs decisions-only prompts.

(Already shipped from this list in prior PRs: write-capable MCP, send-follow-up
in Mail, ⌘N quick-add, de-hardcoded user name.)
