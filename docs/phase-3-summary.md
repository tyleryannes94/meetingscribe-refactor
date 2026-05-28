# Phase 3 — Intelligence

## What was built/changed

1. **Speaker diarization** — opt-in `[SPEAKER_NN]` parsing from whisper.cpp.
2. **Meeting coaching** — a new "Coach" tab analyzing talk-time, questions, and
   action-item density.
3. **Smart follow-up** — generate an email/Slack recap draft from the summary +
   action items via Ollama.

## Files created / modified

**Created — Transcription:**
- `Sources/MeetingScribe/Transcription/SpeakerDiarization.swift`
  (`Speaker`, `DiarizedSegment`, `DiarizedTranscript.parse(_:)`, `.markdown()`)

**Created — Coaching:**
- `Sources/MeetingScribe/Coaching/MeetingCoach.swift` (`CoachingReport`, `TalkTimeSlice`)
- `Sources/MeetingScribe/Coaching/CoachingReportView.swift`

**Created — Followup:**
- `Sources/MeetingScribe/Followup/FollowUpSuggestion.swift`
- `Sources/MeetingScribe/Followup/FollowUpGeneratorService.swift`
- `Sources/MeetingScribe/Followup/FollowUpView.swift`

**Modified:**
- `Sources/MeetingScribe/Models/Settings.swift` — `whisperDiarizationEnabled` (default off)
- `Sources/MeetingScribe/Transcription/WhisperRunner.swift` — appends `--diarize` when enabled
- `Sources/MeetingScribe/UI/UnifiedMeetingDetail.swift` — `DetailTab.coach` + `coachBody` (wired)
- (plus the Phase 0 foundation build fix)

## How to use

- **Diarization:** enable `whisperDiarizationEnabled` in settings. Requires a
  tinydiarize-capable whisper model; standard ggml models ignore `--diarize`.
  Output gets `[SPEAKER_00]`/`[SPEAKER_01]` turn markers, parsed into a
  `DiarizedTranscript`.
- **Coach tab:** open any past meeting → the **Coach** tab (already wired into
  `UnifiedMeetingDetail`) shows talk-time bars, question count, action-item
  density, and plain-language suggestions. Runs on the transcript only.
- **Follow-up:** host `FollowUpView(meetingTitle:summary:actionItems:)`, pick
  Email or Slack, click *Draft follow-up*; copy or share the result. Requires
  Ollama running.

## Notes for the next developer

- `FollowUpView` is decoupled (takes plain strings), so it can be hosted
  anywhere; it isn't yet given its own tab/button in the detail view — wire it
  where it makes sense (e.g. a button in the Coach or Summary tab).
- Talk-time balance only populates when a `DiarizedTranscript` has multiple
  speakers; otherwise the Coach report omits that section.
- `MeetingCoach` is pure, deterministic heuristics (no model calls) so it's
  cheap to run inline as the tab renders.
