# G2 — Product Manager: Metrics, Instrumentation & Feedback

> Lens: For a 100%-local, privacy-first app you can't ship cloud analytics — so how does the *developer* know it works and how does a *user* know they're getting value? Measure success, quality (transcription accuracy, summary usefulness), and reliability without ever phoning home.

## Full-app audit (through my lens)

The app already has a respectable **diagnostics-collection** layer but almost zero **measurement / feedback** layer. The distinction matters: today MeetingScribe can tell you *something broke* (and bundle logs for a bug report) but cannot tell you *how often, how well, or whether the user is getting value*.

**What exists (and is good):**
- `ErrorReporter` (`Sources/MeetingScribe/Diagnostics/ErrorReporter.swift:24`) is a clean central funnel: categorized `AppError`, last-100 ring buffer, optional banner, mirrors to `AppLog`. This is the right spine.
- `AppLog` (`Diagnostics/AppLog.swift:15`) — disk-backed, rotated at 2 MB, structured key/values, mirrors to OSLog. Good.
- `TranscriptionLog` (`Transcription/TranscriptionLog.swift:37`) records *every* whisper invocation with `exitCode`, **`elapsedSeconds`**, `outputCharacters`, stderr head/tail. This is a goldmine of quality/perf signal that is **written and then never read** — it's a forensic log, not a metric.
- `DiagnosticsExporter` (`Diagnostics/DiagnosticsExporter.swift:19`) — privacy model is exemplary: allowlist-based redacted settings (`:25`), Keychain never included, user always presses the button, no audio. This is the privacy bar everything else must clear.
- `MeetingHealthDTO` (`VaultKit/SharedModels.swift:64`) with `.ok/.partial/.noTranscript/.fallbackUsed`, computed in `AudioRecorder.swift:256` and surfaced via `MeetingHealthBadge.swift`. A genuine reliability signal — **per meeting, but never aggregated.**

**The gaps my lens exists to catch:**
1. **The four KPIs in MASTER_PLAN_V2 (`:797-802`) — cold-launch, recording-start latency, transcription lag, crash rate — are targets with NO instrumentation.** There is no timer around launch, no `recordingStartLatency` measurement, no crash counter. `TranscriptionLog` captures `elapsedSeconds` per whisper run but nothing computes the "lag per minute of audio" KPI from it. You literally cannot tell if you hit your own targets. This is the single biggest hole.
2. **No quality feedback loop at all.** Grep for `thumbs|rating|feedback|helpful` returns only unrelated hits (a `## Feedback` heading in a note *template*, `isGenerating` flags). The summary is regenerated blindly (`MeetingPipelineController.swift:296`) with no signal on whether the *previous* one was useful. For a local LLM (llama3.1:8b) whose output quality varies run-to-run, having zero "was this summary good?" signal means there's no way to know if a prompt change or model swap helped or hurt.
3. **No transcription-accuracy proxy.** Whisper confidence/`no_speech_prob` are available in whisper.cpp JSON but not parsed or surfaced; `MeetingHealthDTO` only knows byte counts and source-presence, not "this transcript is probably garbage."
4. **Health is never aggregated.** Each meeting has a badge, but there's no "your last 30 recordings: 27 OK, 2 partial, 1 recovered" view. The developer can't see a reliability trend; the user can't see whether their setup is healthy.
5. **No user-facing value reflection.** No stats, no "year in meetings." The relationship-graph + full meeting history is a uniquely rich *local* dataset and the app surfaces none of it back to the user as a sense of value/progress — a retention miss the existing plan's "end-of-day recap" (TDY-6) only barely touches.
6. **`ErrorReporter.recent` is in-memory only** (`:28`), lost on quit. The error *log* persists via AppLog mirroring, but there's no durable, queryable counter of "how many summary failures this week" — so even self-diagnosis requires grepping a text file.
7. **Crash recovery exists** (`AudioRecovery.markRecordingStarted` / `meetingsWithInterruptedRecordings`, `MeetingManager.swift:206,502`) but **a recovered crash is not counted as a crash.** The recovery banner is the only evidence a crash happened; nothing increments a crash-rate metric, so KPI #4 is unmeasurable even though the detection primitive is right there.

## Existing-plan items I rank highest (through my lens)

1. **TST-1 (CI on PR/push) + TST-2 (data-integrity tests)** — the *only* automated quality signal the project will have. Without CI running `swift test`, every "is it working?" question falls back to manual Mac smoke tests (REMAINING_WORK.md is full of "must verify on the Mac"). This is foundational instrumentation, just at the build level.
2. **ENG-A transcript-truncation fix (done) + its `liveDroppedChunks`/`liveCoverageSeconds` snapshot** — this is already producing exactly the coverage metric my lens wants; it just needs to be *surfaced and counted*, not only used as a repair gate.
3. **ENG-G (replace `try?` on persistence with ErrorReporter + user-visible warning)** — converts silent write failures into measured, surfaced events. Directly feeds any reliability metric.
4. **TDY-6 (end-of-day recap)** — the seed of a value-reflection surface; I'd extend it dramatically (see P5-7).
5. **ENG-E (backup honesty)** — a measurement-integrity issue: claiming "backed up" when nothing is, is a metric the *user* relies on being true.

## NET-NEW recommendations

### P5-1 — `MetricsStore`: a local, opt-in metrics ledger (the missing measurement spine)
**What/why:** Add a `Diagnostics/MetricsStore.swift` actor that records timed events and counters to a small append-only file (`logs/metrics.ndjson`) — gated behind a single Settings toggle "Help improve MeetingScribe (local only, never uploaded)", default-off, with copy mirroring the DiagnosticsExporter promise. It records exactly the V2 KPIs: cold-launch ms (timestamp app init → first usable frame), recording-start latency (`startRecording` call → first audio buffer), transcription lag (derive from `TranscriptionLog.elapsedSeconds / recordedSeconds`), and pipeline outcome counts. It is the durable backbone P5-2…P5-5 read from.
**User value:** Indirect — but it's what lets the *developer* honestly answer "did my change help?" without violating privacy. Nothing leaves the machine; the user can open the ndjson.
**Effort:** M · **Impact:** High · **Depends on:** nothing (ErrorReporter/AppLog patterns already exist to mirror).

### P5-2 — Real-Time Factor (RTF) & transcription-lag panel in Diagnostics
**What/why:** `TranscriptionLog` already logs `elapsedSeconds` and `outputCharacters` per run (`TranscriptionLog.swift:42`) but it's write-only forensics. Parse the last N runs into a small Diagnostics panel showing rolling RTF (audio-seconds ÷ wall-seconds), tagged by `LiveTranscriber` vs final-pass vs `QuickTranscribe`. This directly measures V2 KPI #3 ("transcription lag < 30s/min") which is currently un-instrumented.
**User value:** Power users see if GPU/Flash-Attention settings actually help; developer gets the perf KPI for free from data already on disk.
**Effort:** S · **Impact:** High · **Depends on:** P5-1 (or can read TranscriptionLog directly first).

### P5-3 — Summary 👍/👎 with local "why" capture
**What/why:** Add a thumbs control to the Summary tab (`MeetingSummaryTab.swift`). 👎 opens an optional one-tap reason (missed action items / wrong attendees / too long / hallucinated). Store the rating + the `(ollamaModel, prompt-template-id, transcript health)` tuple in `MetricsStore`. On regenerate (`MeetingPipelineController.swift:296`), if the prior summary was 👎, pass the reason as a steering hint to the Ollama prompt.
**User value:** The summary actually gets better the more you correct it — closes the only quality loop the local LLM currently lacks. Pairs perfectly with the planned per-tag templates (you can now measure which template wins).
**Effort:** M · **Impact:** High · **Depends on:** P5-1.

### P5-4 — Reliability dashboard: aggregate `MeetingHealthDTO`
**What/why:** A "Recording health" card in Settings/Diagnostics that aggregates the per-meeting `MeetingHealthDTO` (`SharedModels.swift:64`) across the last 30/90 days: counts of ok/partial/noTranscript/fallbackUsed, plus the most-common warning strings. Surfaces patterns ("system audio silent 6× — check your ScreenCapture permission") the per-meeting badge can't.
**User value:** Turns a permission/mic problem from "one weird badge I ignored" into a diagnosable trend with a fix CTA. Developer sees real-world reliability without telemetry.
**Effort:** S · **Impact:** High · **Depends on:** nothing (DTO already persisted per meeting).

### P5-5 — Count recovered crashes as crashes (close KPI #4)
**What/why:** The crash-recovery path (`AudioRecovery.meetingsWithInterruptedRecordings`, `MeetingManager.swift:502`) already detects an interrupted recording on launch — that *is* a crash signal. Increment a durable crash counter (and log active-recording-hours) so V2 KPI #4 (crashes/hour active) becomes measurable. Add an optional ultra-minimal crash breadcrumb (last category from ErrorReporter at time of crash) written on the recovery path.
**User value:** Honest reliability number for the developer; user sees "MeetingScribe recovered N interrupted recordings" instead of silent loss.
**Effort:** S · **Impact:** Med · **Depends on:** P5-1.

### P5-6 — Self-diagnostics "Run a health check" button
**What/why:** A one-click pre-flight in Diagnostics that actively probes the stack: whisper binary present + model SHA matches (ties to planned ENG-D), Ollama reachable + model pulled, Screen Recording + Mic + Calendar permissions, free disk vs. expected per-hour audio cost, vault writable. Renders a green/red checklist with fix links. Today the user only discovers a broken dependency when a recording silently fails.
**User value:** Converts "why didn't my meeting transcribe?" support loops into self-service. Huge for a local app where the user IS the ops team.
**Effort:** M · **Impact:** High · **Depends on:** ENG-D (model pin) ideally, but independently shippable.

### P5-7 — "Your Year in Meetings" local stats view
**What/why:** A personal, on-device reflection view built entirely from the existing vault + relationship graph: total meetings recorded, hours captured, words transcribed, top 10 people by meeting-time, busiest day/week, action-items created vs. completed, longest "stay-in-touch" gap closed. No network, all local aggregation.
**User value:** The retention/delight hook the plan lacks — turns the uniquely rich local dataset (the moat per V2:36) into something the user *feels*. Also a natural shareable-screenshot growth moment that respects privacy (user chooses to share).
**Effort:** M · **Impact:** Med-High · **Depends on:** nothing; richer with P5-1.

### P5-8 — Transcription-confidence surfacing
**What/why:** Parse whisper.cpp's per-segment `no_speech_prob` / avg logprob from the JSON `WhisperRunner` already invokes (`WhisperRunner.swift`), fold a "confidence" signal into `MeetingHealthDTO`, and visually de-emphasize (gray) low-confidence transcript spans. Feeds P5-4's reliability view ("3 meetings had low-confidence audio").
**User value:** User can trust the transcript at a glance and knows which segments to re-listen to; a real accuracy proxy without any ground-truth.
**Effort:** M · **Impact:** Med · **Depends on:** P5-4.

### P5-9 — Action-item extraction yield metric
**What/why:** Track, per meeting, how many action items the LLM extracted vs. how many the user then edited/deleted/added manually (Tasks CRUD already exists). A persistent "extraction precision" proxy — if users delete most auto-extracted items, the extraction prompt is bad.
**User value:** Indirect (drives prompt quality) but cheap; pairs with P5-3's feedback loop.
**Effort:** S · **Impact:** Med · **Depends on:** P5-1.

### P5-10 — Make `ErrorReporter.recent` durable + a "Recent issues" Settings list
**What/why:** Persist the last-100 ring buffer (`ErrorReporter.swift:28`) to disk so it survives relaunch, and render it as a human-readable "Recent issues" list in Settings (category, message, time) with a "copy" and "export bundle" action inline. Today errors are only readable by grepping `app.log`.
**User value:** User can see what's been failing without opening a text file; lowers the bar to filing a good bug report.
**Effort:** S · **Impact:** Med · **Depends on:** nothing.

### P5-11 — Privacy-preserving opt-in "share aggregate metrics" export (manual, never automatic)
**What/why:** Extend `DiagnosticsExporter` with an *optional* `metrics-aggregate.json` (counts and percentiles only — no titles, names, or transcript content) that the user can choose to attach to a bug report or GitHub issue. Reuses the existing allowlist/redaction discipline (`DiagnosticsExporter.swift:25`). This is how the developer gets *opt-in, user-initiated* field data without ever building a telemetry pipeline.
**User value:** Lets engaged users help improve the app on their terms; preserves the "nothing leaves automatically" promise exactly.
**Effort:** S · **Impact:** Med · **Depends on:** P5-1.

## Top 3 picks

1. **P5-1 — `MetricsStore` (opt-in local metrics ledger).** Without it, the project's own four KPIs are unmeasurable aspirations. It's the spine that makes P5-2/3/5/9/11 possible, and it sets the privacy contract for all measurement.
2. **P5-3 — Summary 👍/👎 with local "why" + regenerate steering.** The local LLM is the product's variable-quality core and currently has zero feedback loop; this is the highest-leverage *quality* instrument and it improves output immediately for the user.
3. **P5-6 — Self-diagnostics "Run a health check."** For a local-first app the user is their own ops team; one button that verifies whisper/Ollama/permissions/disk converts silent failures and support loops into self-service.
