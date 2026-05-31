# UX06 — In-the-Moment Recording (start/stop, HUD, live status, live transcript, menu-bar, F5 dictation, Note Transcriber)

Senior-PM lens on how fast and clear it is to start a recording, *know* you're recording, and stop it — plus feedback during transcribe/summarize. The voice-note path already has a polished Whispr-style floating HUD; **meeting recording does not** — that asymmetry drives most of the friction below.

## Lift from V4
- **D4-1** — Single global record toggle + persistent recording HUD for *meeting* recording (today only voice-note dictation has a HUD; there is no global record hotkey). Directly my surface; I extend it below rather than re-spec it.
- **D5-1** — Reduce-motion pass; `PulsingDot` runs an always-on `repeatForever` glow + scale (`FloatingOverlay.swift:408-415`), a vestibular trigger on the primary recording affordance.
- **D1-2** — Register `meetingscribe://` + `onOpenURL`; needed so a "start recording" deep link / Shortcut works (enables FT6-5).
- **C5-4** — Streaming summarization with live token render; removes the post-stop spinner that today gives zero progress signal.

## UX improvements (5)

### UX6-1 — Persistent meeting-recording HUD (not just voice notes)
**Friction today:** `FloatingOverlayController.attach` only subscribes to `quickNotesController.$state` and `dictation.$state` (`FloatingOverlay.swift:43-54`) — meeting recording (`manager.state == .recording`) never drives the overlay. Once the main window is behind a Zoom call, the *only* "you are recording" signal is the menu-bar icon (`MainWindow.swift:136`) and a toolbar button you can't see. To confirm/stop you must Cmd-Tab back to MeetingScribe → find toolbar/Today → click Stop (3 clicks + a context switch).
**Fix:** Add a `.recording(meeting)` case to the existing overlay state machine; reuse `RecordingPill` (elapsed + level meter + End). It already floats over fullscreen via `.canJoinAllSpaces`/`.fullScreenAuxiliary` (`FloatingOverlay.swift:190-193`).
**Clicks:** stop-from-anywhere 3→1. **Effort:** small-M.

### UX6-2 — Live meeting transcript: add Copy + Jump-to-bottom + manual scroll
**Friction today:** `LiveTranscriptScroll` auto-scrolls on every new chunk (`MeetingTranscriptTab.swift:115-119`) with no way to copy what's accrued and no "back to live" control — scrolling up to re-read silently fights the auto-scroll on the next chunk, and there's no Copy affordance at all during the meeting.
**Fix:** Add a small toolbar (Copy transcript, "Jump to live" pill that appears only when scrolled up) mirroring the polished post-meeting `TranscriptSyncView` toolbar (`TranscriptSyncView.swift:131-200`). Pause auto-scroll while the user is scrolled away from bottom.
**Clicks:** copy-live-transcript ∞→1. **Effort:** S.

### UX6-3 — Stop button needs a confirm + clear "what happens next" on long recordings
**Friction today:** Stop is a one-click destructive action everywhere (`MainWindow.swift:570-575`, `TodayView.swift:111-113`, `MenuBarView.swift:120`). After stop, the UI just shows "N finalizing" (`MainWindow.swift:594-599`) — the user gets no sense of how long transcribe+summarize will take, and a misclick on a 90-min recording ends it instantly.
**Fix:** For recordings over a threshold (e.g. >2 min), Stop shows a tiny inline confirm ("End & transcribe?" with elapsed time) before tearing down; on confirm, surface an ETA/stage chip ("Transcribing 1 of 18 chunks…") driven by existing `transcribingMeetingIDs` + chunk count. Cheap insurance against the accidental-stop data loss.
**Clicks:** unchanged for intentional stop; prevents 1 catastrophic misclick. **Effort:** small-M.

### UX6-4 — "Stop" label is ambiguous across two parallel recordings
**Friction today:** Voice-note Stop (`MainWindow.swift:546-550`) and meeting Stop (`MainWindow.swift:570-575`) can both be live simultaneously and both read "Stop …" with near-identical red stop icons. The overlay's End button (`FloatingOverlay.swift:275`) and the menu-bar "Stop & Transcribe" (`MenuBarView.swift:120`) add a third/fourth phrasing for the same concept. A user mid-call can't tell which Stop ends the *meeting* vs the *note*.
**Fix:** Standardize verbs/icons: meeting = "End meeting" (stop.fill, red), voice note = "Stop note" (stop.circle, neutral). Show the meeting title inline on the meeting Stop button when space allows.
**Clicks:** removes a guess/undo loop. **Effort:** S.

### UX6-5 — Surface the F5 dictation hotkey where it's actually used
**Friction today:** Dictation is the fastest capture path (F5 toggle, paste-at-cursor — `QuickDictation.swift:67-73`, registered in `MeetingScribeApp.swift:275-287`) but it is discoverable *only* in Settings. Neither the menu-bar "New Voice Note" row (`MenuBarView.swift:80-86`) nor the Notes empty state (`QuickNotesView.swift:41-52`) mentions the hotkey. New users never learn the marquee feature.
**Fix:** Add the resolved hotkey glyph (reuse `HotkeyDisplay.modifierString`/`keyName`, `GlobalHotkey.swift:85-117`) as a trailing hint on the menu-bar voice-note row and a one-line "Tip: press ⌥F5 anywhere to dictate" in the Notes empty state.
**Clicks:** discovery, not clicks. **Effort:** S.

## Feature improvements (5)

### FT6-1 — Pause / resume a meeting recording
**What/why:** Today recording is binary start/stop (`manager.state`); a break, a sidebar conversation, or a sensitive moment forces either a full stop (losing the single-file continuity) or recording dead air. Add a Pause that suspends capture and the chunk timer, keeping one meeting/transcript.
**Value:** Cleaner transcripts, privacy control, no orphaned partial meetings. **Effort:** small-M. **Dep:** AudioRecorder chunk-timer gating.

### FT6-2 — One global "record meeting" hotkey (parity with F5 dictation)
**What/why:** There's a global dictation hotkey but no global *meeting* record hotkey; starting a meeting always requires the window/menu-bar/Today (`startRecording(for:)` callers). Add a settable global toggle that calls `startRecording(for: nil)` / `stopRecording()`.
**Value:** True start-from-anywhere; pairs with UX6-1's HUD. **Effort:** S (the `GlobalHotkey` + Settings plumbing already exists for dictation). **Dep:** D4-1.

### FT6-3 — Audio-level / silence indicator during meeting recording
**What/why:** The voice-note HUD shows a live `AudioLevelMeter` (`FloatingOverlay.swift:270-273`), but a meeting recording shows no level at all — a dead mic or muted system audio is invisible until you read the transcript afterward. Add the existing meter (mic + system) to the Today "Recording now" card and the new HUD, with a subtle "No audio detected" warning after N seconds of silence.
**Value:** Catches the worst failure (recorded nothing) *while* it's fixable. **Effort:** S (meter component + `recordingMonitor` levels exist).

### FT6-4 — "Add marker / bookmark" during recording
**What/why:** No way to flag a moment live ("decision here", "follow up"). A single hotkey/button drops a timestamped marker into the transcript stream, rendered as a jump chip in `TranscriptSyncView` afterward.
**Value:** Turns a 60-min recording into navigable highlights; huge for action-item extraction quality. **Effort:** small-M. **Dep:** transcript segment model already has timestamps.

### FT6-5 — Start recording from menu-bar in one click when a call is detected
**What/why:** `AppDetector` already knows when you're in a Zoom/Meet call (`currentCallSource`, used by `autoStartIfNeeded` `MainWindow.swift:232-241`) but the menu-bar only offers one-click record for *calendar* live events (`MenuBarView.swift:88-94`). When a detected call has no calendar match, the user falls back to "Record Ad-hoc". Promote a "Record this call (Zoom detected)" row to the top of the menu when `currentCallSource != nil`.
**Value:** Captures the impromptu calls people forget to record — the highest-regret miss. **Effort:** S (detector + start path both exist).

## Top 3 picks
1. **UX6-1 — persistent meeting-recording HUD.** Highest-value: closes the single biggest gap (you literally can't see/stop a meeting recording without context-switching), reuses an existing polished component, and lifts D4-1. small-M.
2. **FT6-3 — live audio-level/silence indicator for meetings.** S effort, prevents the worst silent failure (recording nothing), components already exist.
3. **UX6-5 + FT6-2 — surface and globalize the record/dictation hotkeys.** Tiny effort, makes the fastest capture paths discoverable and start-from-anywhere true.

**Single highest-value low-lift win:** UX6-1 — the persistent meeting-recording HUD.
