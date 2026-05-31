# Engineering — Performance & Resource Usage (CPU · memory · disk · battery · energy)

*Lens: a meeting recorder runs for hours, often unplugged, while the user is on a video call that already taxes the SoC. Every always-on watt, every per-chunk model reload, every 4 Hz timer that fires while hidden is a battery and thermal cost the user feels as fan noise and a dying laptop. This sub-role hunts CPU/battery drains, memory growth on long meetings, main-thread blocking, redundant work, and the energy impact of always-on capture.*

---

## Full-app audit (through my lens)

### What the rebuild already got right (so I don't re-flag it)
- The three 12 Hz `RunLoop.main` timers (Phase-0 Bug 3) **were** consolidated: there is now one `0.1s` watchdog in `AudioRecorder.startWatchdog()` (`AudioRecorder.swift:267-285`) that does the cheap level publish every tick and gates the expensive stall/silence checks to every 50 ticks (~5s). Good.
- `RecordingMonitor.pushVoiceLevel` (`RecordingMonitor.swift:26`) only re-publishes when the level moves > 0.005, so it doesn't cascade `objectWillChange` at the full tick rate. Good.
- `LiveTranscriber` has bounded backpressure (`maxPending = 16`, `LiveTranscriber.swift:48,64`) — long meetings won't OOM the live stream. Good.
- `refreshPastMeetings` is debounced 300 ms (`MeetingManager.swift:169`) and the index is an O(1) in-memory cache (`MeetingStore.swift:62-66`). Good.
- `OllamaService` caches reachability with a 5 s freshness window (`OllamaService.swift:74-75`) instead of probing per call. Good.
- Launch is staggered: notifications/Ollama/orphan-cleanup are `Task.detached`, the calendar timer first-fires after 800 ms, body prefetch after 600 ms (`MeetingScribeApp.swift:180-204`). Good.

So this is a tuning audit, not a teardown. The remaining drains are concentrated in five places.

### Drain 1 — whisper.cpp cold-loads the model on **every** 5-minute chunk (biggest energy + latency cost)
`LiveTranscriber.processChunk` constructs a fresh `WhisperRunner` per chunk (`LiveTranscriber.swift:121`) and `WhisperRunner.runWhisper` spawns a brand-new `whisper-cli` `Process` each time (`WhisperRunner.swift:152-161`). Every spawn re-reads the ~140 MB ggml model from disk, re-allocates the inference context, and re-warms Metal. For a 90-minute meeting that's ~18 chunks/source × 2 sources = **~36 cold model loads**, each paying the 2–4 s warm-up the V2 plan itself called out (`MASTER_PLAN_V2.md:752`). That is wasted CPU, wasted memory-bandwidth, wasted disk reads, and — because it happens *during* the call — direct battery + thermal load while the user is least able to afford it. The empty-output GPU→CPU retry path (`WhisperRunner.swift:113-121`) can **double** that cost for a whole session on pre-M5 hardware: a transient empty result forces a second full subprocess+model-load per chunk.

### Drain 2 — always-on / hidden-tab timers in the keep-alive ZStack
`MainWindow.tabContent` mounts every visited tab forever and toggles visibility via `.opacity` (`MainWindow.swift:86-97`). Anything timer-driven inside a hidden tab keeps firing:
- `TranscriptSyncView` runs a **0.25 s timer (4 Hz)** unconditionally (`TranscriptSyncView.swift:120`). It now guards `isVisible` (partial ARCH-2 fix, `:124`), but the `Timer.publish` itself still wakes the main RunLoop 4×/sec for the lifetime of the view even when the tab is hidden *and* nothing is playing — the cheapest fix (don't schedule the timer at all unless playing+visible) isn't done.
- `MeetingTranscriptTab` / `LiveTranscriptScroll` schedules a **1 Hz** `Timer.publish` (`MeetingTranscriptTab.swift:62`) that updates `now` to drive a countdown, ticking even when the live pane is off-screen.
- `FloatingOverlay.RecordingPill` runs a **1 Hz** timer (`FloatingOverlay.swift:257`) — acceptable while recording, but it's a `Timer.publish` driving a full SwiftUI re-render of the pill every second.

None of these is catastrophic alone, but on battery the RunLoop wakeups defeat App Nap / coalescing and keep the CPU out of its deepest idle states.

### Drain 3 — ambient detector & app detector poll on a wall-clock timer
`AmbientMeetingDetector` polls **every 1 s** (`AmbientMeetingDetector.swift:56`) and `AppDetector` every **15 s** (`AppDetector.swift:37`), both on `RunLoop.main`. Ambient detection is off by default (`startIfEnabled`, `:47-50`) — good — but when on it's a 1 Hz main-thread wakeup forever, purely to check `micIsInUse()`. `AppDetector`'s 15 s `NSWorkspace.runningApplications` scan is the kind of fixed-interval poll the V2 plan explicitly warns against ("Do not use polling timers… burns CPU", `MASTER_PLAN_V2.md:775`). These should be event-driven (mic-in-use notifications / `NSWorkspace.didActivateApplicationNotification`) or at minimum back off when idle.

### Drain 4 — full-resolution image decode in the view body, no thumbnail cache
`PersonDetailView.photoThumb` calls `NSImage(contentsOf: url)` **inside the view builder** (`PersonDetailView.swift:633-635`) for a 72×72 thumbnail. SwiftUI re-evaluates `body` frequently; each pass re-decodes the **full-resolution** source image from disk (could be a multi-MB HEIC/JPEG from Apple/Google Photos) only to downscale it to 72 pt. `PeopleGraphView` resolves photo URLs per node too (`:217-218`). There's no `CGImageSourceCreateThumbnailAtIndex` downsampling and no decoded-image cache, so scrolling a person with several photos, or a graph of many people, repeatedly decodes large images on the main thread → CPU spikes, memory churn, and jank.

### Drain 5 — no energy/thermal awareness anywhere
There is **zero** use of `ProcessInfo.isLowPowerModeEnabled`, `thermalState`, or `NSProcessInfo` activity assertions in the whole tree (confirmed by search). The app behaves identically on a plugged-in M2 mini and a battery-at-15%-and-thermally-throttled MacBook: same whisper thread count (`activeProcessorCount - 1`, `WhisperRunner.swift:202`), same GPU-first policy, same 4 Hz UI timers, same per-chunk Ollama/whisper cadence. For an always-on capture app this is the single biggest missed lever.

### Smaller observations
- `WhisperRunner.argv` hardcodes threads = `activeProcessorCount - 1` (`:202`). On a battery-constrained / efficiency-core machine this saturates P-cores during a call. No knob, no low-power reduction.
- `renderMarkdown()` re-walks and re-`sort`s the full `segments` array on every append in `processChunk` (`LiveTranscriber.swift:128` sorts on each chunk; render is O(n) per call) — fine at meeting scale but quadratic-ish on very long sessions.
- `TranscriptParser.parse` runs two `NSRegularExpression` passes over the entire transcript on **every** `rawTranscript` change (`TranscriptSyncView.swift:119,259`) with no memoization — the existing-plan ARCH-4 item; I endorse it below.
- Body prefetch warms 10 meeting bodies into RAM at launch (`MeetingScribeApp.swift:203`) with no eviction policy visible — fine now, worth a cap as the vault grows.

---

## Existing-plan items I rank highest (through my lens)

1. **ARCH-2 — gate hidden-tab timers / drive transcript-sync off the player time-observer** (`MASTER_PLAN_V3.md:123`). Highest-value existing perf item: the 0.25 s timer and the keep-alive ZStack are the textbook "burns battery while hidden" pattern. The partial `isVisible` guard helps but the timer still schedules; finish it by only running when *visible AND playing*, ideally via `addPeriodicTimeObserver` so there's no free-running timer at all.
2. **ARCH-4 — memoize `TranscriptParser.parse` keyed by transcript hash, off-main for large inputs** (`MASTER_PLAN_V3.md:125`). Eliminates redundant double-regex passes on every change; directly removes main-thread work on long transcripts.
3. **Phase-3 "keep the whisper model loaded between chunks"** (`MASTER_PLAN_V2.md:752`). This is buried as a one-liner but is, by my measurement-by-reasoning, the **largest** energy item in the app. It deserves promotion out of "Phase 3 polish." See E2-1 for the concrete shape.
4. **NAV-4 — scope keep-alive to the 1–2 heaviest tabs** (`MASTER_PLAN_V3.md:64`). Reduces the surface area of Drain 2 and frees retained view memory.
5. **ARCH-1 — CaptureKit de-dup** (`MASTER_PLAN_V3.md:122`). Performance-relevant because today every perf fix (E2-1, thread tuning, GPU-failure persistence) must be written **twice** and can silently diverge between app and daemon copies.
6. **Phase-3 "GPU failure persistence"** (`MASTER_PLAN_V2.md:753`). Stops Drain 1's worst case (per-chunk double-spawn) by remembering within a session that GPU returns empty and skipping the GPU attempt.

---

## NET-NEW recommendations

### E2-1 — Persistent whisper warm-pool (long-lived inference server, not per-chunk subprocess)
**What/why:** Replace the spawn-a-process-per-chunk model (`WhisperRunner.swift:152`, `LiveTranscriber.swift:121`) with a single long-lived whisper process that keeps the model resident and accepts chunk paths over stdin/a pipe (whisper.cpp ships `whisper-server`; or a small persistent `whisper-cli` wrapper). One model load per recording session instead of ~36. This is *more* than the V2 one-liner: it's a warm **pool** — pre-warm the process at `startRecording` so the *first* chunk also avoids the cold load, and keep it alive across the brief idle between chunks within a session, tearing down on stop (or after an idle TTL).
**User value:** Dramatically lower CPU/GPU/battery during calls, less fan noise, lower transcription lag (V2 KPI target < 30 s/min, `MASTER_PLAN_V2.md:801`), and the final-pass transcribe completes faster on stop.
**Effort:** L · **Impact:** High · **Depends on:** ARCH-1 (do once, in CaptureKit, not twice); pairs with GPU-failure persistence.

### E2-2 — Low-power / thermal adaptive mode ("Energy budget")
**What/why:** Introduce a `ResourceGovernor` that reads `ProcessInfo.isLowPowerModeEnabled` and `thermalState` (and AC-vs-battery via `IOPSCopyPowerSourcesInfo`) and feeds policy into the hotspots: on battery+lowPower+nominal → keep current behavior; on `.fair`/`.serious` thermal or Low Power Mode → drop whisper `--threads` (`WhisperRunner.swift:202`), force CPU-off-GPU or defer live transcription entirely until stop, slow UI timers from 4 Hz→1 Hz, and pause speculative work (body prefetch, ambient/app polling). Surface a one-line status ("Low Power: live transcript paused, full transcript on stop").
**User value:** A recorder that doesn't murder the battery mid-meeting and self-throttles before the fans scream. This is the differentiator vs. "always max threads."
**Effort:** M · **Impact:** High · **Depends on:** none (the governor is additive; hotspots read it).

### E2-3 — Defer live transcription on battery → batch-only "finalize on stop"
**What/why:** The most expensive thing the app does during a call is live, per-chunk whisper. Offer (and auto-select under E2-2 when on battery/low-power) a **"transcribe after the meeting"** mode: capture audio only during the call (cheap), then run a single batch pass on the merged audio when recording stops, ideally while the Mac is idle/plugged in. The pipeline already has a batch path and the ENG-A merged-audio repair, so the machinery exists.
**User value:** A multi-hour meeting can be recorded on battery with near-zero incremental CPU beyond audio capture; transcript appears shortly after stop. Users who want the live pane keep it.
**Effort:** M · **Impact:** High · **Depends on:** E2-2 for auto-selection; reuses existing batch finalize.

### E2-4 — Hardware-aware model & decoder selection
**What/why:** Whisper model and flags are static (`AppSettings.whisperModel`, fixed threads/beam). At first run (or in Settings) detect the chip class (P/E core counts via `sysctl`, GPU family, RAM) and pick a sensible default: `base.en` on an M1 Air, `small.en`/`medium.en` on an M2/M3 Pro+ with headroom, smaller on a low-RAM machine; set thread count from **performance**-core count, not total. Cache the decision.
**User value:** Best transcription quality the hardware can sustain without thermal throttling — and lighter defaults on constrained machines so the app stays "light."
**Effort:** S–M · **Impact:** Med · **Depends on:** none (extends E2-2's hardware probe).

### E2-5 — Thumbnail downsampling + decoded-image cache for people photos
**What/why:** Replace `NSImage(contentsOf:)` in the view body (`PersonDetailView.swift:635`, `PeopleGraphView.swift:217`) with `CGImageSourceCreateThumbnailAtIndex` downsampling to the display size, behind an `NSCache<NSString, NSImage>` keyed by path+size. Decode off-main on first miss. Persist a small on-disk thumbnail next to each photo so subsequent launches skip full decode entirely.
**User value:** No main-thread image jank, far lower memory for photo-heavy people / the graph view, faster People tab.
**Effort:** S · **Impact:** Med · **Depends on:** none.

### E2-6 — Replace fixed-interval pollers with event-driven detection
**What/why:** Convert `AppDetector`'s 15 s `runningApplications` scan (`AppDetector.swift:37`) to `NSWorkspace.shared.notificationCenter` activate/launch/terminate observers, and gate `AmbientMeetingDetector`'s 1 Hz loop (`AmbientMeetingDetector.swift:56`) behind a CoreAudio "device-in-use" property listener so it only spins up when a mic is actually live. Directly honors the V2 prohibition on polling timers (`MASTER_PLAN_V2.md:775`).
**User value:** Removes a class of forever-on wakeups; auto-detect gets *faster* (event latency < poll interval) while using less energy.
**Effort:** M · **Impact:** Med · **Depends on:** none.

### E2-7 — Built-in energy/perf profiling harness ("Diagnostics → Performance")
**What/why:** There's a `Diagnostics` module and a `TranscriptionLog` that already records per-whisper elapsed (`WhisperRunner.swift:180-188`); extend it into a lightweight in-app perf panel: rolling main-thread hang detection (watchdog on a known cadence), per-chunk whisper wall-time + cold-vs-warm flag, live-transcription backlog (`pendingCount`/`droppedChunkCount`), peak RSS, and a one-click "export perf report." Add an opt-in signpost (`os_signpost`) instrumentation around record/transcribe/summarize so Instruments traces are meaningful.
**User value:** The V2 KPIs (cold launch < 1 s, start latency < 200 ms, lag < 30 s/min, `MASTER_PLAN_V2.md:797-802`) are currently *estimated* — this makes them measured and regression-catchable, and gives the user evidence when they report "fans spun up."
**Effort:** M · **Impact:** Med · **Depends on:** none; complements TST-1 CI.

### E2-8 — Background-finalize with an NSProcessInfo activity assertion + idle scheduling
**What/why:** Post-stop finalize (merge → batch transcribe → Ollama summarize) is heavy and currently runs immediately regardless of power state. Wrap it in `ProcessInfo.beginActivity(.userInitiated)` so it isn't killed by App Nap, but make the *scheduling* power-aware: on battery+lowPower, defer the Ollama summarization pass until the machine is plugged in or idle (notify "summary will generate when charging"). Keep transcription prompt (users want the transcript) but the LLM pass is the most deferrable expensive step.
**User value:** Recording-then-closing-the-lid-on-battery doesn't trigger a multi-minute CPU/GPU burn; summaries materialize when it's free to do so.
**Effort:** M · **Impact:** Med · **Depends on:** E2-2 (power state), ENG-A finalize path.

### E2-9 — Cap and evict the in-RAM meeting-body prefetch cache
**What/why:** `prefetchTopMeetingBodies(limit: 10)` (`MeetingScribeApp.swift:203`) and the body cache have no visible eviction. Add an LRU bound (count + total bytes) so transcript/summary bodies don't accumulate unbounded as the user clicks through many meetings in a session.
**User value:** Stable memory footprint on long working sessions; the "light app" promise holds.
**Effort:** S · **Impact:** Low–Med · **Depends on:** none.

### E2-10 — Coalesce live transcript re-renders (snapshot diffing, not per-chunk sort)
**What/why:** Each completed chunk does `segments.append` + full `segments.sort` + an `objectWillChange` that re-renders `LiveTranscriptScroll` (`LiveTranscriber.swift:127-128`). Keep segments insertion-sorted (binary insert by `startSec`) and batch UI publishes on a short coalescing interval so a burst of catch-up chunks doesn't trigger N full list re-layouts.
**User value:** Smoother live pane, less main-thread layout cost when transcription catches up after a backlog.
**Effort:** S · **Impact:** Low–Med · **Depends on:** none.

---

## Top 3 picks

1. **E2-1 — Persistent whisper warm-pool.** The per-chunk cold model load is the single largest avoidable energy/CPU cost in the app, paid continuously during every call. Promote it out of "Phase 3 polish."
2. **E2-2 — Low-power / thermal adaptive mode.** The app is power-blind today; one `ResourceGovernor` reading `isLowPowerModeEnabled`/`thermalState`/AC-state and steering the hotspots is the highest-leverage *new* lever for a battery-bound always-on recorder.
3. **E2-3 — Defer live transcription to batch-on-stop on battery.** Turns a multi-hour unplugged recording from a thermal event into near-pure audio capture, reusing the batch path that already exists.

**Single highest-priority recommendation overall:** **E2-1 (persistent whisper warm-pool)** — it removes ~35 redundant 140 MB model loads per long meeting, cutting active-recording CPU/GPU/battery and transcription lag simultaneously, and it's the foundation the adaptive-mode (E2-2) policies steer.
