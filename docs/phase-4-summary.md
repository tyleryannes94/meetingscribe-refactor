# Phase 4 — Power Features

## What was built/changed

1. **Obsidian export** — export a meeting as Obsidian-flavored markdown
   (frontmatter, `[[wikilinks]]`, `#tags`) into a vault.
2. **Ambient meeting detection** — notices sustained microphone use and offers
   to record, even for apps the window-based `AppDetector` doesn't recognize.
3. **Compliance Mode** — a recording disclaimer + timestamped consent log.

## Files created / modified

**Created — Export:**
- `Sources/MeetingScribe/Export/ObsidianExporter.swift`
- `Sources/MeetingScribe/Export/ExportSettings.swift` (vault path + filename template)

**Created — Detection:**
- `Sources/MeetingScribe/Detection/AmbientMeetingDetector.swift`
- `Sources/MeetingScribe/Detection/MeetingDetectionSettingsView.swift`

**Created — Compliance:**
- `Sources/MeetingScribe/Compliance/ConsentRecord.swift`
- `Sources/MeetingScribe/Compliance/ComplianceManager.swift`
- `Sources/MeetingScribe/Compliance/ComplianceSettings.swift` (+ `ComplianceSettingsView`)

**Modified:**
- `Sources/MeetingScribe/UI/UnifiedMeetingDetail.swift` — "Obsidian (vault)" item in the export menu + `exportToObsidian(_:)`
- `Sources/MeetingScribe/MeetingScribeApp.swift` — `AmbientMeetingDetector.shared.startIfEnabled()` at launch
- `Sources/MeetingScribe/MeetingManager.swift` — gated `ComplianceManager.shared.recordingDidStart(...)` in `startRecording`
- (plus the Phase 0 foundation build fix)

## How to use

- **Obsidian export:** set `obsidianVaultPath` (via `ExportSettings`); then in a
  meeting's **Export** menu choose **Obsidian (vault)**. With no vault set it
  falls back to a save panel. Attendees become `[[wikilinks]]`; meeting tags
  become `#tags`.
- **Ambient detection:** enable it in `MeetingDetectionSettingsView` (off by
  default). After N seconds of continuous mic use (sensitivity slider, default
  20s) it posts `.meetingScribeAmbientMeetingDetected`. Add an observer to offer
  "start recording."
- **Compliance Mode:** enable in `ComplianceSettingsView`, pick US/EU/Custom.
  When a recording starts, a disclaimer notification
  (`.meetingScribeConsentDisclaimer`) fires and a `ConsentRecord` is appended to
  `<storageDir>/compliance/consent-log.json`.

## Important deviations / notes for the next developer

- **Ambient detection uses CoreAudio, not `AVAudioSession`.** The plan said
  `AVAudioSession`, but that framework is **iOS-only** — it does not exist on
  macOS. The macOS-correct signal is
  `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input device,
  which is what `AmbientMeetingDetector` polls.
- The consent-disclaimer notification has no UI observer yet — add a banner/toast
  that reads `userInfo["text"]`.
- The new Settings views (`MeetingDetectionSettingsView`,
  `ComplianceSettingsView`) aren't yet inserted into `SettingsView` — drop them
  into a tab when wiring the Settings UI.
