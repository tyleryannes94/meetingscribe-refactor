import Foundation
import Combine
import AppKit
import AVFoundation
import VaultKit
import OSLog

/// Top-level orchestrator. Owns the audio pipeline and recording lifecycle
/// directly; delegates everything else to focused sub-controllers extracted
/// in Batch 6 (audit 5.1):
///
///   • `quickNotesController` — voice notes (record / import / transcribe /
///     polish / per-note progress + errors)
///   • `pipelineController`   — post-stop pipeline + Transcribe Now
///   • `actionItemBackfill`   — one-shot session backfill of action items
///
/// Views that only care about one of those concerns can `@ObservedObject`
/// the sub-controller directly to scope SwiftUI invalidation. The legacy
/// API surface on this class is preserved as forwarding shims so existing
/// views keep compiling without per-view edits.
@available(macOS 14.0, *)
@MainActor
final class MeetingManager: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "MeetingManager")

    // MARK: - Recording state (still owned here — singular global)

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var activeMeeting: Meeting?
    @Published private(set) var pastMeetings: [Meeting] = []
    @Published private(set) var lastStoppedMeetingID: String?
    /// Meetings found at launch with a stale `.recording.inprogress` marker —
    /// i.e. recordings interrupted by a crash. Surfaced as a "Recover" banner.
    @Published private(set) var interruptedMeetingIDs: Set<String> = []

    let liveTranscriber = LiveTranscriber()

    /// Returns the currently-live calendar meeting to snap an ad-hoc recording
    /// onto (U2-1). Injected at app wiring so the manager stays decoupled from
    /// CalendarService. Returns nil when there isn't exactly one live event.
    var liveCalendarMeetingProvider: (() -> Meeting?)?

    // MARK: - Sub-controllers (Batch 6 / audit 5.1)

    let store = MeetingStore()
    let tagStore = TagStore()
    let actionItems = ActionItemStore()
    let decisions = DecisionStore()
    let recordingMonitor = RecordingMonitor()
    @Published var dictation = QuickDictation()

    /// In-memory cache for meeting body files (transcript / notes / summary)
    /// keyed by meeting id. Makes clicking into a meeting feel instant by
    /// returning a cached snapshot synchronously while a background refresh
    /// pulls the latest from disk. See `MeetingBodyCache`.
    lazy var bodyCache: MeetingBodyCache = MeetingBodyCache(store: store, tagStore: tagStore)

    /// Voice-notes state + behavior. Views that only render quick notes
    /// can observe this directly for scoped invalidation.
    // 3-D: pass the task store so finished voice notes auto-extract action
    // items. `lazy` because an inline default can't reference `actionItems`.
    lazy var quickNotesController = QuickNotesController(actionItemStore: actionItems)

    /// Screen-recording state (capture / transcription / analysis), parallel to
    /// voice notes. `lazy` so it can inject `actionItems` for task extraction.
    lazy var screenRecordingsController = ScreenRecordingsController(actionItemStore: actionItems)

    /// Post-stop + Transcribe-Now pipeline state.
    lazy var pipelineController = MeetingPipelineController(
        store: store, tagStore: tagStore, actionItems: actionItems, decisions: decisions,
        batchTranscriber: batchTranscriber, summarizer: summarizer
    )

    /// One-shot per-session action-item backfill.
    lazy var actionItemBackfill = ActionItemBackfillController(
        store: store, tagStore: tagStore, actionItems: actionItems
    )

    /// Phase B — auto-extracts people mentioned in transcripts into the
    /// `PeopleStore` graph (post-meeting + a one-shot backfill of recent
    /// meetings).
    lazy var personExtraction = PersonExtractionController(
        store: store, tagStore: tagStore, summarizer: summarizer
    )

    /// Ollama reachability (cheap read off OllamaService cache; published
    /// so settings UI can show a status pill).
    @Published private(set) var ollamaReachable: Bool = false

    /// External task-sync (Linear / Notion) status.
    @Published var isSyncingTasks: Bool = false
    @Published var lastTaskSyncError: String?
    @Published var lastTaskSyncSummary: String?

    // MARK: - Internals

    private let audio = AudioRecorder()
    private let batchTranscriber = WhisperTranscriber()
    private let summarizer = OllamaService()

    /// True when the current recording was started via ScribeCore (IPC).
    /// False means the direct AudioRecorder path is active (fallback mode).
    private var usingScribeCore = false

    /// Set to true when ScribeCore posts the `coreReady` Darwin notification.
    /// Used to skip the full 5-second wait if the daemon is already up.
    private var scribeCoreReady = false

    /// Streams the daemon's on-disk 5-minute chunks into `liveTranscriber`
    /// during recording, so a meeting is transcribed as it runs instead of in
    /// one batch pass at stop. Non-nil only while a ScribeCore recording with
    /// live transcription enabled is in progress.
    private var chunkStreamBridge: ChunkStreamBridge?

    /// Wall-clock start of the active recording, used to compute the recorded
    /// duration at stop on the ScribeCore path (where the audio result carries
    /// no duration). Set when recording actually begins, cleared at stop.
    private var recordingStartedAt: Date?

    private let refreshSubject = PassthroughSubject<Bool, Never>()
    private var refreshCancellable: AnyCancellable?

    init() {
        // Dictation hands its produced QuickNote through the controller's
        // polish pipeline so the user gets both raw + polished automatically.
        dictation.onNoteCreated = { [weak self] note in
            self?.quickNotesController.handleDictationNote(note)
        }
        // Push-based voice levels: MicOnlyRecorder polls on a background
        // queue and calls back on main. No RunLoop timer needed here.
        quickNotesController.onLevelUpdate = { [weak self] level in
            self?.recordingMonitor.pushVoiceLevel(level)
        }
        dictation.onLevelUpdate = { [weak self] level in
            self?.recordingMonitor.pushVoiceLevel(level)
        }
        audio.onHealth = { [weak self] h in
            Task { @MainActor in self?.recordingMonitor.setHealth(h) }
        }
        // Persist the partial transcript to disk as each 5-minute chunk lands,
        // so opening a meeting mid-recording shows progress and — more
        // importantly — the transcript is already complete when the user stops,
        // making finalize near-instant instead of a full-file whisper pass.
        liveTranscriber.onTranscriptUpdated = { [weak self] in
            self?.persistLiveTranscriptIfRecording()
        }
        // 5 min of silence on BOTH mic and system → auto-stop.
        audio.onSilenceAutoStop = { [weak self] in
            self?.log.info("Auto-stopping due to silence on both audio sources.")
            Task { @MainActor in await self?.stopRecording() }
        }
        // Failsafe: detect recordings interrupted by a crash on the previous run
        // and flag them for recovery. Deferred so it runs after init completes.
        DispatchQueue.main.async { [weak self] in self?.scanForInterruptedRecordings() }
        // Listen for ScribeCore signals so state stays in sync when recording
        // is owned by the daemon (usingScribeCore == true).
        DarwinNotifier.observe(DarwinNotifier.recordingStarted) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, case .starting = self.state else { return }
                self.recordingStartedAt = Date()
                self.state = .recording(meeting: self.activeMeeting, startedAt: Date())
                self.lastError = nil
            }
        }
        DarwinNotifier.observe(DarwinNotifier.recordingStopped) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, case .stopping = self.state else { return }
                let meeting = self.activeMeeting ?? Self.adhocMeeting()
                let primary = self.tagStore.primaryTag(for: meeting)
                let recordedDuration = self.recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                self.recordingStartedAt = nil
                // Final sweep: submit the trailing chunk(s) the daemon just
                // closed, then drain whisper before we render. stop() enqueues
                // synchronously so flush() sees the tail in `pendingCount`.
                self.chunkStreamBridge?.stop()
                self.chunkStreamBridge = nil
                await self.liveTranscriber.flush()
                let live = self.liveTranscriber.renderMarkdown()
                try? self.store.writeTranscript(live, for: meeting, primaryTag: primary)
                // Claim the pipeline slot synchronously before publishing state changes
                // so a concurrent "Transcribe Now" cannot race the daemon-stop finalize.
                // Previously this path skipped beginPipeline + finalize entirely, so
                // meetings stopped via ScribeCore got no summary, no action items, and
                // no FTS index. (E4-1)
                self.pipelineController.beginPipeline(meeting.id)
                self.state = .idle
                self.activeMeeting = nil
                self.lastStoppedMeetingID = meeting.id
                self.recordingMonitor.resetToIdle()
                self.refreshPastMeetings(force: true)
                let liveDropped = self.liveTranscriber.droppedChunkCount
                let liveCoverage = self.liveTranscriber.lastTranscribedSecond
                // ScribeCore owns the audio hardware, but the vault directory is
                // identical to the direct-recording path. Build a synthetic Result
                // pointing at the on-disk directory so the pipeline can read the
                // audio manifest and run a batch repair pass if needed. (E4-1)
                let dir = self.store.directory(for: meeting, primaryTag: primary)
                let synthResult = AudioRecorder.Result(
                    directory: dir,
                    segmentIndex: AudioManifestStore.segmentCount(meetingDir: dir),
                    micURL: nil,
                    systemURL: nil,
                    health: MeetingHealthDTO(status: .ok, warnings: [],
                                             recordedSeconds: recordedDuration,
                                             micBytes: 0, systemBytes: 0))
                Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else { return }
                    await self.pipelineController.finalize(
                        meeting: meeting,
                        audioResult: synthResult,
                        liveTranscript: live,
                        liveDroppedChunks: liveDropped,
                        liveCoverageSeconds: liveCoverage,
                        recordedDuration: recordedDuration
                    ) { [weak self] in
                        Task { @MainActor in
                            if self?.activeMeeting == nil { self?.liveTranscriber.reset() }
                            self?.bodyCache.invalidate(meeting.id)
                            self?.refreshPastMeetings(force: true)
                            // U2-9: auto-name ad-hoc recordings once the summary exists.
                            Task { await self?.generateAutoTitleIfNeeded(for: meeting) }
                        }
                    }
                    await MainActor.run { self.personExtraction.extract(for: meeting) }
                }
            }
        }
        // When ScribeCore daemon finishes booting it posts coreReady. This
        // is used by tryStartViaScribeCore() to detect a live daemon faster
        // than a fixed 5-second timeout.
        DarwinNotifier.observe(DarwinNotifier.coreReady) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scribeCoreReady = true
            }
        }
        // When a tag's display name changes, rename its vault folder on disk
        // so existing meeting directories stay grouped under the new name.
        tagStore.onTagRenamed = { [weak self] oldFolder, newFolder in
            Task.detached(priority: .utility) { [weak self] in
                self?.store.renameTagFolder(oldFolderName: oldFolder,
                                            newFolderName: newFolder)
            }
        }
        // Coalesce rapid refreshPastMeetings calls so the @Published array isn't
        // replaced on every individual call site (audit bug 4).
        refreshCancellable = refreshSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] force in self?._doRefreshPastMeetings(force: force) }
    }

    // MARK: - Recording control

    func startRecording(for meeting: Meeting?) async {
        guard case .idle = state else { return }
        state = .starting
        Task { await ActivityLog.shared.log(.recordStart) }  // 1C funnel
        do {
            try store.ensureRoot()
            // Live-event snap (U2-1): a "quick record" with no meeting attaches
            // to the currently-live calendar event when there's exactly one, so
            // zero-click capture is born metadata-correct (title + attendees)
            // instead of an attendee-less "Ad-hoc Recording" orphan.
            let resolved = meeting ?? liveCalendarMeetingProvider?()
            var m = resolved ?? Self.adhocMeeting()
            if resolved == nil { m.isImpromptu = true }
            if m.isImpromptu, tagStore.tagIDs(for: m).isEmpty {
                tagStore.addTag("preset-impromptu", to: m, propagateToSeries: false)
            }
            m.segmentCount = 1
            // Prevent recurring-series ID collisions: EKEvent.eventIdentifier is
            // the same for every occurrence of a recurring series. If a folder
            // already exists for this ID but belongs to a *different day*, this is
            // a distinct occurrence — give it a fresh UUID so it never overwrites
            // a prior recording.
            if let existingDir = store.findExistingDirectory(forMeetingID: m.id),
               let existing = store.readMeeting(at: existingDir) {
                let cal = Calendar.current
                if !cal.isDate(existing.startDate, equalTo: m.startDate, toGranularity: .day) {
                    m.id = UUID().uuidString
                    m.relativeFolderPath = nil
                } else {
                    // Per-meeting capture override (set in Edit mode) persists to
                    // disk; pick it up if the in-memory meeting (e.g. from a
                    // calendar refresh) didn't carry it. Only for the same
                    // occurrence — a different day is a distinct recording.
                    if m.captureMic == nil { m.captureMic = existing.captureMic }
                    if m.captureSystem == nil { m.captureSystem = existing.captureSystem }
                }
            }
            activeMeeting = m
            liveTranscriber.reset()
            let primary = tagStore.primaryTag(for: m)
            try store.writeMeeting(m, primaryTag: primary)
            // Surface the just-created meeting (esp. an ad-hoc recording) in the
            // lists right away — otherwise it's stuck in `activeMeeting` only and
            // can't be clicked into until the next refresh.
            refreshPastMeetings(force: true)

            // Carry the pre-meeting brief into this recording's notes so it's
            // visible (Notes tab) during and after the call, not just on the
            // upcoming-event screen. No-op when no brief was generated.
            if let cachedBrief = BriefCache.load(m.id) {
                attachBriefToNotes(cachedBrief, for: m, onlyIfRecorded: false)
            }

            // --- ScribeCore delegation with 1-second timeout fallback ---
            let scribeCoreSucceeded = await tryStartViaScribeCore()
            usingScribeCore = scribeCoreSucceeded

            if scribeCoreSucceeded {
                // ScribeCore records out-of-process and only signals lifecycle
                // events — it never transcribes. Bridge its on-disk 5-minute
                // chunks into liveTranscriber so the meeting is transcribed as it
                // runs (the same per-chunk behavior the direct path gets via
                // callbacks), gated by the same power/thermal governor.
                if ResourceGovernor.shared.shouldRunLiveTranscription {
                    let chunksDir = store.directory(for: m, primaryTag: primary)
                        .appendingPathComponent("chunks", isDirectory: true)
                    let bridge = ChunkStreamBridge(chunksDir: chunksDir, transcriber: liveTranscriber)
                    bridge.start()
                    chunkStreamBridge = bridge
                } else {
                    AppLog.info("transcription", "Live transcription deferred to batch — \(ResourceGovernor.shared.statusDescription)")
                }
            }

            if !scribeCoreSucceeded {
                // Fallback: direct AudioRecorder path.
                // Power/thermal governor (E2-2/E2-3): when on battery/low-power or
                // thermally critical, skip live transcription — finalize does a
                // single batch pass on stop instead, avoiding per-chunk cold-loads.
                if ResourceGovernor.shared.shouldRunLiveTranscription {
                    audio.onMicChunk = { [weak self] url, _, s, e in
                        self?.liveTranscriber.submitChunk(url: url, speaker: "Me", startSec: s, endSec: e)
                    }
                    audio.onSystemChunk = { [weak self] url, _, s, e in
                        self?.liveTranscriber.submitChunk(url: url, speaker: "Them", startSec: s, endSec: e)
                    }
                } else {
                    AppLog.info("transcription", "Live transcription deferred to batch — \(ResourceGovernor.shared.statusDescription)")
                }

                let dir = store.directory(for: m, primaryTag: primary)
                try await audio.start(in: dir, segment: m.segmentCount,
                                      micOverride: m.captureMic, systemOverride: m.captureSystem)
                AudioRecovery.markRecordingStarted(in: dir)
                recordingStartedAt = Date()
                // Use the resolved meeting `m` (which is `activeMeeting`), not the
                // `meeting` parameter — that param is nil for ad-hoc recordings, so
                // publishing it left `.recording(meeting:)` empty on the direct path
                // while `activeMeeting` was set. (ScribeCore path already used `m`.)
                state = .recording(meeting: m, startedAt: Date())
            }
            MetricsStore.shared.record(.meetingRecorded)   // local-only metric (P5-1)
            // When ScribeCore is handling recording, state is updated via the
            // DarwinNotifier.recordingStarted signal observed in init().
            lastError = nil
        } catch {
            usingScribeCore = false
            log.error("Start failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .audio,
                                        context: ["phase": "start-recording"])
            lastError = error.localizedDescription
            state = .error(error.localizedDescription)
        }
    }

    /// Attempts to start recording via ScribeCore.
    ///
    /// Fast path: if ScribeCore already posted `coreReady` this session the
    /// command is sent immediately with a 5-second timeout for the response.
    ///
    /// Slow path: if coreReady hasn't fired yet we wait up to 5 seconds for
    /// both the daemon boot AND the command acknowledgement. This handles the
    /// first recording after login before ScribeCore has fully started.
    ///
    /// Returns true if ScribeCore acknowledged the startRecording command.
    private func tryStartViaScribeCore() async -> Bool {
        // E3-1 kill-switch: the daemon path captures into an orphan folder and
        // never finalizes the meeting (total silent loss). Hard-disable it
        // until that path is finished — always record via the direct path.
        guard AppSettings.shared.useScribeCoreDaemon else { return false }
        // If the daemon hasn't announced itself yet, wait a little for coreReady.
        if !scribeCoreReady {
            let deadline = Date().addingTimeInterval(5)
            while !scribeCoreReady, Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms polls
            }
        }
        guard scribeCoreReady else {
            log.info("ScribeCore not ready after 5s — falling back to direct audio")
            return false
        }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await ScribeCoreXPCClient.shared.startRecording()
                    return true
                } catch {
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 second timeout
                return false
            }
            for await result in group {
                group.cancelAll()
                return result
            }
            return false
        }
    }

    /// Resumes recording for a previously-stopped past meeting. Appends a NEW
    /// segment file. Final merge happens at stop.
    func continueRecording(for meeting: Meeting) async {
        guard case .idle = state else { return }
        do {
            var live = pastMeetings.first(where: { $0.id == meeting.id }) ?? meeting
            let primary = tagStore.primaryTag(for: live)
            let dir = store.directory(for: live, primaryTag: primary)
            let audioDir = dir.appendingPathComponent("audio", isDirectory: true)
            if live.segmentCount == 0 {
                try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
                for (legacy, segName) in [("mic.m4a", "mic-001.m4a"), ("system.m4a", "system-001.m4a")] {
                    let from = dir.appendingPathComponent(legacy)
                    let to = audioDir.appendingPathComponent(segName)
                    if FileManager.default.fileExists(atPath: from.path),
                       !FileManager.default.fileExists(atPath: to.path) {
                        try FileManager.default.moveItem(at: from, to: to)
                    }
                }
                live.segmentCount = 1
            }
            live.segmentCount += 1
            try store.writeMeeting(live, primaryTag: primary)
            activeMeeting = live
            liveTranscriber.reset()

            audio.onMicChunk = { [weak self] url, _, s, e in
                self?.liveTranscriber.submitChunk(url: url, speaker: "Me", startSec: s, endSec: e)
            }
            audio.onSystemChunk = { [weak self] url, _, s, e in
                self?.liveTranscriber.submitChunk(url: url, speaker: "Them", startSec: s, endSec: e)
            }

            try await audio.start(in: dir, segment: live.segmentCount,
                                  micOverride: live.captureMic, systemOverride: live.captureSystem)
            AudioRecovery.markRecordingStarted(in: dir)
            state = .recording(meeting: live, startedAt: Date())
            lastError = nil
        } catch {
            log.error("Continue failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .audio,
                                        context: ["phase": "continue-recording", "meeting": meeting.id])
            lastError = error.localizedDescription
            state = .error(error.localizedDescription)
        }
    }

    func stopRecording() async {
        guard case let .recording(_, startedAt) = state else { return }
        state = .stopping
        Task { await ActivityLog.shared.log(.recordStop) }  // 1C funnel

        if usingScribeCore {
            // Delegate stop to ScribeCore; finalization is triggered when we
            // receive the DarwinNotifier.recordingStopped signal (observed in init).
            usingScribeCore = false
            try? await ScribeCoreXPCClient.shared.stopRecording()
            return
        }

        // Direct path (ScribeCore not running or timed out during start)
        usingScribeCore = false
        let meeting = activeMeeting ?? Self.adhocMeeting()
        let result = await audio.stop()
        let primary = tagStore.primaryTag(for: meeting)
        // Clean stop — clear the crash marker so the launch sweep doesn't flag
        // this finished recording for recovery.
        AudioRecovery.clearRecordingMarker(in: store.directory(for: meeting, primaryTag: primary))
        // Wait for the final in-flight chunk(s) before rendering — otherwise the
        // last 0–5 min of audio (still running whisper at stop) is dropped from
        // the persisted transcript and from the summary/action items derived from it.
        await liveTranscriber.flush()
        let live = liveTranscriber.renderMarkdown()
        do { try store.writeTranscript(live, for: meeting, primaryTag: primary) }
        catch {
            log.error("Failed to write live transcript: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage,
                                        context: ["phase": "write-live-transcript", "meeting": meeting.id])
            lastError = "Couldn't save the transcript: \(error.localizedDescription)"
        }

        // Claim this meeting in the pipeline synchronously (main actor) BEFORE
        // publishing lastStoppedMeetingID / dispatching finalize — otherwise a
        // "Transcribe Now" tap in that window starts a 2nd pipeline that races
        // finalize on transcript.md / summary.md. (ENG-C)
        pipelineController.beginPipeline(meeting.id)

        state = .idle
        activeMeeting = nil
        lastStoppedMeetingID = meeting.id
        recordingMonitor.resetToIdle()

        // Snapshot live-transcription health on the main actor (these are
        // @MainActor-isolated on liveTranscriber) so the detached finalize can
        // decide whether the live transcript needs a batch repair pass. (ENG-A)
        let liveDropped = liveTranscriber.droppedChunkCount
        let liveCoverage = liveTranscriber.lastTranscribedSecond
        let recordedDuration = Date().timeIntervalSince(startedAt)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.pipelineController.finalize(meeting: meeting,
                                                   audioResult: result,
                                                   liveTranscript: live,
                                                   liveDroppedChunks: liveDropped,
                                                   liveCoverageSeconds: liveCoverage,
                                                   recordedDuration: recordedDuration) { [weak self] in
                Task { @MainActor in
                    if self?.activeMeeting == nil { self?.liveTranscriber.reset() }
                    // Pipeline rewrote transcript.md / summary.md on disk;
                    // drop the cache entry so the detail view re-reads.
                    self?.bodyCache.invalidate(meeting.id)
                    self?.refreshPastMeetings(force: true)
                    // U2-9: now that the summary exists, name ad-hoc recordings
                    // from their content (no-op for titled / calendar meetings).
                    Task { await self?.generateAutoTitleIfNeeded(for: meeting) }
                }
            }
            // Pipeline finished writing transcript.md — now extract any people
            // mentioned in it into the second-brain graph (Phase B).
            await MainActor.run { self.personExtraction.extract(for: meeting) }
        }
    }

    func switchToRecording(_ meeting: Meeting) async {
        if let url = meeting.conferenceURL.flatMap(URL.init(string:)) {
            NSWorkspace.shared.open(url)
        }
        if case .recording = state {
            await stopRecording()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        await startRecording(for: meeting)
    }

    func cancelRecording() async {
        chunkStreamBridge?.stop()
        chunkStreamBridge = nil
        recordingStartedAt = nil
        if case .recording = state { _ = await audio.stop() }
        if let m = activeMeeting {
            AudioRecovery.clearRecordingMarker(in: store.directory(for: m, primaryTag: tagStore.primaryTag(for: m)))
        }
        activeMeeting = nil
        state = .idle
        recordingMonitor.resetToIdle()
    }

    /// Write the partial live transcript to disk for the in-progress meeting.
    /// Invoked by `liveTranscriber.onTranscriptUpdated` as each ~5-minute chunk
    /// is transcribed, so the meeting is visibly transcribed while recording and
    /// the finished transcript is ready the moment the user stops. No-op when no
    /// meeting is active or nothing has transcribed yet.
    private func persistLiveTranscriptIfRecording() {
        guard let m = activeMeeting else { return }
        let live = liveTranscriber.renderMarkdown()
        guard live.trimmingCharacters(in: .whitespacesAndNewlines) != "# Transcript" else { return }
        let primary = tagStore.primaryTag(for: m)
        do {
            try store.writeTranscript(live, for: m, primaryTag: primary)
            bodyCache.invalidate(m.id)
        } catch {
            // Non-fatal: the authoritative write happens at stop. Don't surface.
            log.error("Live transcript persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Past meetings

    private var lastPastMeetingsRefresh: Date = .distantPast
    private let pastMeetingsRefreshInterval: TimeInterval = 2.0

    func refreshPastMeetings(force: Bool = false) {
        refreshSubject.send(force)
    }

    private func _doRefreshPastMeetings(force: Bool) {
        if !force, Date().timeIntervalSince(lastPastMeetingsRefresh) < pastMeetingsRefreshInterval {
            return
        }
        lastPastMeetingsRefresh = Date()
        let storeRef = store
        RefreshIndicator.shared.begin()
        Task.detached(priority: .userInitiated) { [weak self] in
            let list = storeRef.listPastMeetings(forceRescan: force)
            await MainActor.run {
                self?.pastMeetings = list
                RefreshIndicator.shared.end()
            }
        }
    }

    // MARK: - Ollama lifecycle

    func refreshOllamaStatus() async {
        ollamaReachable = await summarizer.isReachable()
    }

    @discardableResult
    func ensureOllamaRunning() async -> Bool {
        let ok = await summarizer.ensureRunning()
        ollamaReachable = ok
        return ok
    }

    // MARK: - Manual transcription (forwards to pipeline controller)

    /// Forwarder for legacy call sites.
    var transcribingMeetingIDs: Set<String> { pipelineController.transcribingIDs }

    func isTranscribingMeeting(_ meeting: Meeting) -> Bool {
        pipelineController.isTranscribing(meeting)
    }

    func hasAudio(for meeting: Meeting) -> Bool {
        !discoveredAudioSegments(for: meeting).mic.isEmpty ||
        !discoveredAudioSegments(for: meeting).system.isEmpty
    }

    func transcribeNow(meeting: Meeting, regenerateSummary: Bool = true) {
        pipelineController.transcribeNow(meeting: meeting, regenerateSummary: regenerateSummary)
        Task { [weak self] in
            while self?.pipelineController.isTranscribing(meeting) == true {
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            await MainActor.run {
                self?.bodyCache.invalidate(meeting.id)
                self?.refreshPastMeetings(force: true)
            }
        }
    }

    /// Regenerate summary from the existing transcript only — never re-runs
    /// Whisper. Falls back to `transcribeNow` when no transcript exists yet.
    func regenerateSummaryOnly(meeting: Meeting) {
        // Wire the cache-invalidation callback if not already set.
        if pipelineController.onInvalidateCache == nil {
            pipelineController.onInvalidateCache = { [weak self] id in
                self?.bodyCache.invalidate(id)
                self?.refreshPastMeetings(force: true)
            }
        }
        pipelineController.regenerateSummaryOnly(meeting: meeting)
    }

    var lastCompletedMeetingDir: URL? { pipelineController.lastCompletedDir }

    func discoveredAudioSegments(for meeting: Meeting) -> (mic: [URL], system: [URL]) {
        let primary = tagStore.primaryTag(for: meeting)
        let dir = store.directory(for: meeting, primaryTag: primary)
        return filesByPrefix(in: dir)
    }

    private func filesByPrefix(in dir: URL) -> (mic: [URL], system: [URL]) {
        // iCloud-/extension-tolerant discovery — recognizes evicted placeholders
        // and non-.m4a segments so `hasAudio` and Transcribe Now don't miss a
        // recording that's intact on disk but not yet downloaded.
        AudioRecovery.discoverSegments(in: dir)
    }

    // MARK: - Recovery & manual import (failsafes)

    /// Launch sweep: find meetings whose recording was interrupted by a crash
    /// (stale in-progress marker), rebuild their audio manifests from disk, and
    /// publish their ids so the detail view can offer "Recover Audio".
    func scanForInterruptedRecordings() {
        let storeRef = store
        Task.detached(priority: .utility) { [weak self] in
            let root = AppSettings.shared.storageDir
            let dirs = AudioRecovery.meetingsWithInterruptedRecordings(under: root)
            guard !dirs.isEmpty else { return }
            var ids: [String] = []
            for dir in dirs {
                AudioRecovery.rebuildManifest(in: dir)            // make audio discoverable
                if let m = storeRef.readMeeting(at: dir) { ids.append(m.id) }
            }
            await MainActor.run {
                self?.interruptedMeetingIDs.formUnion(ids)
                if !ids.isEmpty { self?.refreshPastMeetings(force: true) }
            }
        }
    }

    /// True if this meeting was flagged as an interrupted (crashed) recording.
    func wasInterrupted(_ meeting: Meeting) -> Bool { interruptedMeetingIDs.contains(meeting.id) }

    /// Recover a meeting's audio from its folder: download any iCloud-evicted
    /// segments, rebuild the manifest, clear the crash marker, then transcribe.
    func recoverAudio(for meeting: Meeting) {
        let primary = tagStore.primaryTag(for: meeting)
        let dir = store.directory(for: meeting, primaryTag: primary)
        Task.detached(priority: .userInitiated) { [weak self] in
            await AudioRecovery.ensureDownloaded(in: dir)
            AudioRecovery.rebuildManifest(in: dir)
            AudioRecovery.clearRecordingMarker(in: dir)
            await MainActor.run {
                self?.interruptedMeetingIDs.remove(meeting.id)
                if AudioRecovery.hasRecoverableAudio(in: dir) {
                    self?.transcribeNow(meeting: meeting)
                } else {
                    self?.lastError = "No audio files found in this meeting's folder."
                }
            }
        }
    }

    /// Add an attendee (a name, an email, or "Name <email>") to a meeting and
    /// persist it (redesign §4D — "add {person} to a meeting"). Returns the
    /// updated meeting, or nil if it was a no-op (blank / already present).
    @discardableResult
    func addAttendee(_ attendee: String, to meeting: Meeting) -> Meeting? {
        guard let updated = Self.meeting(meeting, addingAttendee: attendee) else { return nil }
        let primary = tagStore.primaryTag(for: meeting)
        try? store.writeMeeting(updated, primaryTag: primary)
        refreshPastMeetings(force: true)
        return updated
    }

    /// The meeting a meeting-scoped chat is currently about. Set when the chat
    /// rail opens for a meeting so the chat tools can resolve it by id even when
    /// it isn't (yet) a finalized past meeting — e.g. a calendar/today meeting
    /// whose id is the calendar event id, not an internal recording UUID. Fixes
    /// "Ask AI" returning "meeting not found" for the meeting you're looking at.
    var chatContextMeeting: Meeting?

    /// The loaded meeting with this id, if any (Phase 4 task↔meeting links).
    /// Falls back to the active chat-context meeting so an in-progress / calendar
    /// meeting still resolves.
    func meeting(id: String) -> Meeting? {
        pastMeetings.first { $0.id == id } ?? (chatContextMeeting?.id == id ? chatContextMeeting : nil)
    }

    /// Reads a meeting's `summary.md` off disk (4-3 / 4-4). Returns nil when the
    /// meeting isn't loaded or has no summary yet.
    func summaryText(forMeetingID id: String) -> String? {
        guard let m = meeting(id: id) else { return nil }
        let dir = store.directory(for: m, primaryTag: tagStore.primaryTag(for: m))
        let url = dir.appendingPathComponent("summary.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Pure, disk-free attendee-dedup helper (testable). Case-insensitive on the
    /// whole attendee string; returns nil when blank or already present.
    nonisolated static func meeting(_ meeting: Meeting, addingAttendee attendee: String) -> Meeting? {
        let trimmed = attendee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !meeting.attendees.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return nil }
        var m = meeting
        m.attendees.append(trimmed)
        return m
    }

    /// Push selected notes / action items from a meeting into the Tasks tab
    /// (cross-tab integration). Returns the newly-created tasks. `lines` are
    /// freeform note lines (markdown prefixes are stripped); `drafts` are
    /// pre-built specs (e.g. from a call's action items). Both are deduped
    /// against existing tasks for the meeting.
    @discardableResult
    func pushToTasks(meeting: Meeting,
                     lines: [String] = [],
                     drafts: [ActionItemStore.TaskDraft] = [],
                     projectID: String? = nil) -> [ActionItem] {
        let lineDrafts = lines.flatMap { ActionItemStore.draftsFromNotes($0) }
        let all = drafts + lineDrafts
        guard !all.isEmpty else { return [] }
        let created = actionItems.addTasks(all,
                                           fromMeetingID: meeting.id,
                                           meetingTitle: meeting.displayTitle,
                                           meetingDate: meeting.startDate,
                                           projectID: projectID)
        if !created.isEmpty {
            ToastCenter.shared.show(created.count == 1
                                    ? "Added 1 task to Tasks"
                                    : "Added \(created.count) tasks to Tasks")
        }
        return created
    }

    /// Manually add an audio file to a meeting (not a whole-meeting import). The
    /// file is copied into the meeting's `audio/` folder as the next segment and
    /// transcription is kicked off.
    func importAudioFile(_ source: URL, into meeting: Meeting) {
        let primary = tagStore.primaryTag(for: meeting)
        let dir = store.directory(for: meeting, primaryTag: primary)
        let importsDir = dir.appendingPathComponent("imports", isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: importsDir, withIntermediateDirectories: true)
            let existing = (try? fm.contentsOfDirectory(at: importsDir, includingPropertiesForKeys: nil)) ?? []
            let nextIndex = existing.count + 1
            let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
            let dest = importsDir.appendingPathComponent(String(format: "import-%03d.%@", nextIndex, ext))
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
            refreshPastMeetings(force: true)
            transcribeNow(meeting: meeting)
        } catch {
            log.error("importAudioFile failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .audio,
                                        context: ["phase": "import-audio-file", "meeting": meeting.id])
            lastError = "Couldn't import audio: \(error.localizedDescription)"
        }
    }

    func importedRecordingURLs(for meeting: Meeting) -> [URL] {
        let dir = store.directory(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
        let importsDir = dir.appendingPathComponent("imports", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: importsDir.path),
              let contents = try? fm.contentsOfDirectory(at: importsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let audioExts = Set(["m4a", "mp4", "mp3", "wav", "caf", "aac", "flac", "ogg", "opus"])
        return contents
            .filter { audioExts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Manually set a meeting's transcript from a file (.txt/.md/.srt/.vtt).
    func importTranscriptFile(_ source: URL, into meeting: Meeting, regenerateSummary: Bool = true) {
        do {
            let raw = try String(contentsOf: source, encoding: .utf8)
            let cleaned = Self.cleanTranscript(raw, ext: source.pathExtension.lowercased())
            setTranscript(cleaned, for: meeting, regenerateSummary: regenerateSummary)
        } catch {
            lastError = "Couldn't read transcript file: \(error.localizedDescription)"
        }
    }

    /// Write a transcript directly onto a meeting and (optionally) regenerate the
    /// summary + action items from it.
    func setTranscript(_ text: String, for meeting: Meeting, regenerateSummary: Bool) {
        let primary = tagStore.primaryTag(for: meeting)
        let body = text.contains("# Transcript") ? text : "# Transcript\n\n" + text + "\n"
        try? store.writeTranscript(body, for: meeting, primaryTag: primary)
        bodyCache.invalidate(meeting.id)
        refreshPastMeetings(force: true)
        guard regenerateSummary else { return }
        let summarizerRef = summarizer
        let storeRef = store
        let actionItemsRef = actionItems
        Task.detached(priority: .userInitiated) {
            guard let summary = try? await summarizerRef.summarize(meeting: meeting, transcript: body) else {
                await ActivityLog.shared.log(.summaryFailed)  // 1C funnel
                return
            }
            await ActivityLog.shared.log(.summaryReady)  // 1C funnel
            await MainActor.run {
                try? storeRef.writeSummary(summary, for: meeting, primaryTag: primary)
                let extracted = ActionItemExtractor.extract(from: summary, meeting: meeting)
                actionItemsRef.reconcileExtracted(extracted, for: meeting.id)
                self.bodyCache.invalidate(meeting.id)
                self.refreshPastMeetings(force: true)
            }
        }
    }

    /// Strip SRT/VTT sequence numbers and timestamp cues, leaving spoken text.
    nonisolated private static func cleanTranscript(_ raw: String, ext: String) -> String {
        guard ext == "srt" || ext == "vtt" else { return raw }
        var out: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t == "WEBVTT" { continue }
            if t.range(of: #"^\d+$"#, options: .regularExpression) != nil { continue }
            if t.contains("-->") { continue }
            out.append(t)
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Meeting editing

    func updateMeeting(_ meeting: Meeting,
                       title: String? = nil,
                       description: String? = nil,
                       source: MeetingSource?? = nil,
                       captureMic: Bool?? = nil,
                       captureSystem: Bool?? = nil) {
        var updated = meeting
        if let title { updated.userTitle = title }
        if let description { updated.userDescription = description }
        // Double-optional: nil = don't touch, .some(nil) = clear back to auto-detect.
        if let source { updated.userSource = source }
        // Same convention for per-meeting capture (v3): outer nil = leave as-is,
        // .some(nil) = inherit global default, .some(x) = force that source.
        if let captureMic { updated.captureMic = captureMic }
        if let captureSystem { updated.captureSystem = captureSystem }
        let primary = tagStore.primaryTag(for: updated)
        do {
            try store.writeMeeting(updated, primaryTag: primary)
            // T13: rename propagates to denormalized task `meetingTitle` so the
            // Tasks list shows the new title without waiting for a re-extract.
            if title != nil && updated.displayTitle != meeting.displayTitle {
                actionItems.refreshMeetingTitle(updated.id, to: updated.displayTitle)
            }
            // Mirror the change onto the live in-memory meeting if it's the
            // one currently being recorded, so the UI reflects the picker
            // change immediately without waiting for a list refresh.
            if let active = activeMeeting, active.id == updated.id {
                activeMeeting = updated
                if case .recording(_, let startedAt) = state {
                    state = .recording(meeting: updated, startedAt: startedAt)
                }
            }
            refreshPastMeetings(force: true)
        } catch {
            log.error("updateMeeting failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage,
                                        context: ["phase": "update-meeting", "meeting": meeting.id])
        }
    }

    func handleTagChange(for meeting: Meeting, previousPrimary: MeetingTag?) {
        let newPrimary = tagStore.primaryTag(for: meeting)
        guard newPrimary?.id != previousPrimary?.id else { return }
        do {
            try store.moveMeeting(meeting, to: newPrimary)
            try store.writeMeeting(meeting, primaryTag: newPrimary)
            refreshPastMeetings(force: true)
        } catch {
            log.error("tag-folder move failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage,
                                        context: ["phase": "tag-change", "meeting": meeting.id])
        }
    }

    // MARK: - File accessors

    func transcriptMarkdown(for meeting: Meeting) -> String {
        // Prefer the in-memory cache so list / detail switching stays
        // glitch-free. Falls through to a synchronous disk read only when
        // the cache is genuinely cold for this meeting.
        let cached = bodyCache.cached(meeting.id)
        if !cached.isEmpty { return cached.transcript }
        return store.readTranscript(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
    }
    func summaryMarkdown(for meeting: Meeting) -> String {
        let cached = bodyCache.cached(meeting.id)
        if !cached.isEmpty { return cached.summary }
        return store.readSummary(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
    }

    /// Preferred async path for views that can wait one frame for the body.
    /// Always returns the freshest copy and warms the cache for next time.
    func body(for meeting: Meeting) async -> MeetingBodyCache.Body {
        await bodyCache.load(meeting)
    }

    /// C1-12: persist an edited summary (used by both the edit-by-asking apply
    /// and its one-step undo). Writes to disk and patches the cache so the next
    /// read — and the open detail's `summary` state — see it immediately.
    func applyEditedSummary(_ markdown: String, for meeting: Meeting) {
        let primary = tagStore.primaryTag(for: meeting)
        bodyCache.patchSummary(meetingID: meeting.id, summary: markdown)
        try? store.writeSummary(markdown, for: meeting, primaryTag: primary)
    }

    /// C1-12: "edit the summary by asking" — rewrite the current summary per a
    /// plain-language instruction ("shorter", "more on decisions", "turn into an
    /// email") with the local model, persist it, and return the new text so the
    /// caller can show it and offer undo. Throws if the engine is unreachable.
    func rewriteSummary(instruction: String, current: String,
                        for meeting: Meeting) async throws -> String {
        let prompt = """
        You are editing an existing meeting summary. Apply this instruction:
        "\(instruction)"

        Rules: stay faithful to the original — do not invent facts, names, dates,
        or action items. Output ONLY the rewritten summary in Markdown, with no
        preamble or commentary.

        ----- CURRENT SUMMARY -----
        \(current)
        """
        let rewritten = try await summarizer.generate(prompt: prompt, temperature: 0.2)
        let cleaned = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw OllamaService.SummaryError.unreachable("empty rewrite") }
        applyEditedSummary(cleaned, for: meeting)
        return cleaned
    }

    /// U2-9: give an ad-hoc recording a short, searchable name derived from its
    /// own transcript/summary with the local model, stored as an *auto*-title
    /// that NEVER overrides a user-chosen name. No-op unless the meeting is
    /// impromptu and has neither a user title nor an existing auto-title — so a
    /// Meetings list stops filling up with identical "Ad-hoc Recording" rows.
    func generateAutoTitleIfNeeded(for meeting: Meeting) async {
        // Re-read the freshest copy from disk: finalize just rewrote
        // meeting.json, and the user may have typed a name in the meantime.
        let primary = tagStore.primaryTag(for: meeting)
        let dir = store.directory(for: meeting, primaryTag: primary)
        let current = store.readMeeting(at: dir) ?? meeting

        guard current.isImpromptu, Self.isUnnamed(current) else { return }

        // Prefer the summary; fall back to the head of the raw transcript.
        var source = store.readSummary(for: current, primaryTag: primary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty {
            source = store.readTranscript(for: current, primaryTag: primary)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !source.isEmpty else { return }
        let snippet = String(source.prefix(2000))

        let prompt = """
        Read the meeting notes below and write a short title naming what the \
        meeting was about. Use 4 to 6 words, in plain language. Output only the \
        title — no quotes, no surrounding punctuation, no trailing period.

        ----- MEETING NOTES -----
        \(snippet)
        """

        guard let raw = try? await summarizer.generate(prompt: prompt, temperature: 0.3) else { return }
        let title = Self.sanitizedAutoTitle(raw)
        guard !title.isEmpty else { return }

        // Re-check on-disk state so we never clobber a title the user typed
        // while the model was running.
        let latest = store.readMeeting(at: dir) ?? current
        guard latest.isImpromptu, Self.isUnnamed(latest) else { return }

        var updated = latest
        updated.autoTitle = title
        do {
            try store.writeMeeting(updated, primaryTag: tagStore.primaryTag(for: updated))
        } catch {
            log.error("auto-title write failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Reflect the new name in the live UI immediately.
        if activeMeeting?.id == updated.id { activeMeeting?.autoTitle = title }
        if let idx = pastMeetings.firstIndex(where: { $0.id == updated.id }) {
            pastMeetings[idx].autoTitle = title
        }
        refreshPastMeetings(force: true)
    }

    /// True when the user hasn't named the meeting and it has no auto-title yet.
    private static func isUnnamed(_ m: Meeting) -> Bool {
        let user = m.userTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let auto = m.autoTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return user.isEmpty && auto.isEmpty
    }

    /// Trim a model-emitted title down to a clean 4–6-word phrase: first line
    /// only, strip a "Title:" preamble, surrounding quotes, and trailing
    /// punctuation, then cap length defensively.
    private static func sanitizedAutoTitle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = s.split(whereSeparator: \.isNewline).first {
            s = String(firstLine)
        }
        if let colon = s.range(of: "Title:", options: [.caseInsensitive]) {
            s = String(s[colon.upperBound...])
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”"))
        while let last = s.last, ".,;:!".contains(last) { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 80 {
            s = String(s.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    /// After a Transcribe Now / summary / notes-save operation, callers
    /// should invalidate so the next read returns the new on-disk file.
    func invalidateBodyCache(_ meetingID: String) {
        bodyCache.invalidate(meetingID)
    }

    /// Kick a background prefetch of the top-N most-recent meetings so
    /// the first few clicks-into-detail come straight from RAM.
    func prefetchTopMeetingBodies(limit: Int = 10) {
        bodyCache.prefetch(pastMeetings, limit: limit)
    }

    func reextractActionItems(for meeting: Meeting) {
        actionItemBackfill.reextract(for: meeting)
    }

    func backfillActionItemsIfNeeded(force: Bool = false) {
        actionItemBackfill.runIfNeeded(meetings: pastMeetings, force: force)
    }

    /// A short, instant (non-LLM) brief for an upcoming meeting's start
    /// notification: open commitments + prior-meeting context with the same
    /// attendees. nil when there's no history. (P2-2)
    func briefSnippet(for meeting: Meeting) -> String? {
        func emails(_ attendees: [String]) -> Set<String> {
            Set(attendees.compactMap { s -> String? in
                if let lt = s.firstIndex(of: "<"), let gt = s.firstIndex(of: ">"), lt < gt {
                    return String(s[s.index(after: lt)..<gt]).lowercased()
                }
                return s.contains("@") ? s.lowercased() : nil
            })
        }
        let mine = emails(meeting.attendees)
        guard !mine.isEmpty else { return nil }
        let prior = pastMeetings.filter { !emails($0.attendees).isDisjoint(with: mine) }
        guard !prior.isEmpty else { return nil }
        let open = prior.flatMap { actionItems.items(for: $0.id).filter { $0.status != .completed } }
        var parts: [String] = []
        if !open.isEmpty {
            parts.append("\(open.count) open item\(open.count == 1 ? "" : "s") to follow up")
        }
        parts.append("\(prior.count) prior meeting\(prior.count == 1 ? "" : "s") with these attendees")
        return parts.joined(separator: " · ")
    }

    /// Phase B — one-shot per-session pass that extracts people from the most
    /// recent meetings that haven't been processed yet.
    func backfillPeopleIfNeeded(force: Bool = false) {
        personExtraction.runIfNeeded(meetings: pastMeetings, force: force)
    }

    private var didBackfillSearchIndex = false

    /// Re-index all past meetings into the FTS index if it's missing them — e.g.
    /// after a `secondbrain.db` rebuild/reset, which only restores people, not
    /// meetings. Runs at most once per session and only when the index is
    /// actually empty of meetings, so the common case pays just one COUNT(*).
    /// Keeps global search (C2-1) trustworthy rather than silently stale.
    func backfillSearchIndexIfNeeded() {
        guard !didBackfillSearchIndex else { return }
        didBackfillSearchIndex = true
        guard !pastMeetings.isEmpty,
              PeopleStore.shared.indexedMeetingCount() == 0 else { return }
        Task { @MainActor in
            for (i, m) in self.pastMeetings.enumerated() {
                let primary = self.tagStore.primaryTag(for: m)
                let summary = self.store.readSummary(for: m, primaryTag: primary)
                let tagNames = self.tagStore.tagIDs(for: m)
                    .compactMap { self.tagStore.tag(by: $0)?.name }
                    .joined(separator: " ")
                PeopleStore.shared.indexMeeting(m, summary: summary,
                                                tags: tagNames.isEmpty ? nil : tagNames)
                if i % 20 == 19 { await Task.yield() }  // keep the UI responsive
            }
        }
    }

    private var didBackfillDecisions = false

    /// Extract decisions from one meeting's summary into the ledger. Call when a
    /// meeting finalizes / re-transcribes. (P1-1)
    func extractDecisions(for meeting: Meeting) {
        let summary = store.readSummary(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
        guard !summary.isEmpty else { return }
        decisions.extract(from: summary, meeting: meeting)
    }

    /// One-shot per-session pass that fills the Decision Ledger from every past
    /// meeting's summary. (P1-1)
    func backfillDecisionsIfNeeded() {
        guard !didBackfillDecisions else { return }
        didBackfillDecisions = true
        let meetings = pastMeetings
        guard !meetings.isEmpty else { return }
        Task { @MainActor in
            for (i, m) in meetings.enumerated() {
                let summary = self.store.readSummary(for: m, primaryTag: self.tagStore.primaryTag(for: m))
                if !summary.isEmpty { self.decisions.extract(from: summary, meeting: m) }
                if i % 20 == 19 { await Task.yield() }
            }
            // P0-E: ensure decisions that were already extracted (so `extract`
            // no-ops) still land in the vault index after the P0 upgrade.
            self.decisions.backfillVaultIndexIfNeeded()
        }
    }

    private var didBackfillEmbeddings = false

    /// One-shot per-session pass that computes semantic embeddings for any past
    /// meetings that don't have one yet (e.g. all of them, the first time the
    /// embedding model is available). Runs in the background, throttled, and
    /// no-ops per meeting when the model is unreachable. (C2-1b)
    func backfillEmbeddingsIfNeeded() {
        guard !didBackfillEmbeddings else { return }
        didBackfillEmbeddings = true
        let meetings = pastMeetings
        guard !meetings.isEmpty else { return }
        Task { @MainActor in
            let have = PeopleStore.shared.embeddedMeetingIDs()
            let todo = meetings.filter { !have.contains($0.id) }
            guard !todo.isEmpty else { return }
            // Ensure the embedding model is present (idempotent; pulls ~274 MB
            // once). If Ollama is down this throws and we just skip — embeds
            // no-op and search stays lexical.
            try? await OllamaChatClient.pullModel(AppSettings.shared.ollamaEmbeddingModel)
            for m in todo {
                let primary = self.tagStore.primaryTag(for: m)
                let summary = self.store.readSummary(for: m, primaryTag: primary)
                await PeopleStore.shared.embedAndStore(
                    entityID: m.id, entityKind: "meeting",
                    text: m.displayTitle + "\n" + summary)
                await Task.yield()
            }
        }
    }

    func userNotes(for meeting: Meeting) -> String {
        let cached = bodyCache.cached(meeting.id)
        if !cached.isEmpty { return cached.notes }
        return store.readUserNotes(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
    }

    /// Append a timestamped bullet to the live meeting's notes — the shared
    /// "add note" action behind the recording dock, nav-rail indicator, and the
    /// floating pill. The timestamp is relative to the recording start. Returns a
    /// short confirmation ("Noted at 4:12") or nil if no meeting is active.
    @discardableResult
    func appendLiveNote(_ text: String) -> String? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let m = activeMeeting else { return nil }
        var stamp = ""
        if case .recording(_, let startedAt) = state {
            let s = max(0, Int(Date().timeIntervalSince(startedAt)))
            stamp = s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                              : String(format: "%d:%02d", s / 60, s % 60)
        }
        let existing = userNotes(for: m)
        let bullet = stamp.isEmpty ? "- \(raw)" : "- [\(stamp)] \(raw)"
        saveUserNotes(existing.isEmpty ? bullet : existing + "\n" + bullet, for: m)
        return stamp.isEmpty ? "Noted" : "Noted at \(stamp)"
    }

    func saveUserNotes(_ text: String, for meeting: Meeting) {
        let primary = tagStore.primaryTag(for: meeting)
        // Optimistically patch the cache so concurrent reads see the new
        // text immediately. Disk persistence runs synchronously here
        // (the caller is already on a debounce) but the cache update is
        // what makes tab-switch-and-back feel instant.
        bodyCache.patchNotes(meetingID: meeting.id, notes: text)
        do {
            try store.writeMeeting(meeting, primaryTag: primary)
            try store.writeUserNotes(text, for: meeting, primaryTag: primary)
        } catch {
            log.error("Saving notes failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage,
                                        context: ["phase": "save-notes", "meeting": meeting.id])
        }
    }

    /// Markers that delimit the auto-injected pre-meeting brief inside a
    /// meeting's `notes.md`. Kept stable so regeneration updates in place and
    /// the user's own notes around it are never touched.
    static let briefNoteBegin = "<!-- ms-pre-meeting-brief -->"
    static let briefNoteEnd = "<!-- /ms-pre-meeting-brief -->"

    /// Writes (or updates) the pre-meeting brief at the TOP of the meeting's
    /// `notes.md`, between markers, so the brief is visible in the always-present
    /// Notes tab before, during, and after the call. Idempotent: re-running
    /// replaces the existing block rather than stacking, and the user's own notes
    /// are preserved. `onlyIfRecorded` avoids materializing a vault folder for a
    /// calendar event that hasn't been recorded yet.
    /// No-op since the de-tabbed canvas (ux-audit-2026-06b) renders the brief
    /// in its own MSSection. Injecting it into `notes.md` made the editor show
    /// the brief a second time — duplicate content the user couldn't delete.
    /// The pre-existing markers in any meeting's notes are stripped at load
    /// time by `UnifiedMeetingDetail.stripBriefBlock`.
    func attachBriefToNotes(_ brief: String, for meeting: Meeting, onlyIfRecorded: Bool = true) {
        // intentionally empty
    }

    func revealInFinder(_ meeting: Meeting) {
        let dir = store.directory(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        }
    }

    /// Absolute path to the meeting's canonical Obsidian markdown (`<slug>.md`),
    /// or nil if it hasn't been written yet (e.g. not finalized). Used for
    /// "Open in Obsidian". (C3-x)
    func canonicalMarkdownURL(for meeting: Meeting) -> URL? {
        let dir = store.directory(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
        let url = dir.appendingPathComponent("\(meeting.slug).md")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func audioURLs(for meeting: Meeting) -> [URL] {
        let dir = store.directory(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
        let fm = FileManager.default
        let mic = dir.appendingPathComponent("mic.m4a")
        let sys = dir.appendingPathComponent("system.m4a")
        var urls: [URL] = []
        if fm.fileExists(atPath: mic.path) { urls.append(mic) }
        if fm.fileExists(atPath: sys.path) { urls.append(sys) }
        if !urls.isEmpty { return urls }
        let audioDir = dir.appendingPathComponent("audio", isDirectory: true)
        if fm.fileExists(atPath: audioDir.path),
           let contents = try? fm.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) {
            return contents.filter { $0.pathExtension.lowercased() == "m4a" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return []
    }

    // MARK: - Quick Notes — forwarding shims to QuickNotesController
    //
    // Preserves the legacy MeetingManager API so existing views compile
    // unchanged. New views should observe `quickNotesController` directly
    // for scoped invalidation.

    enum QuickRecordState: Equatable {
        case idle, recording(startedAt: Date), transcribing, error(String)
    }
    var quickRecordState: QuickRecordState {
        switch quickNotesController.state {
        case .idle: return .idle
        case .recording(let at): return .recording(startedAt: at)
        case .transcribing: return .transcribing
        case .error(let m): return .error(m)
        }
    }
    var quickNotes: [QuickNote] { quickNotesController.notes }
    var quickNotesTranscribing: Set<String> { quickNotesController.transcribing }
    var quickNotesPolishing: Set<String> { quickNotesController.polishing }
    var quickNotesStructuringPrompt: Set<String> { quickNotesController.structuringPrompt }
    var quickNoteErrors: [String: String] { quickNotesController.errors }

    func refreshQuickNotes() { quickNotesController.refresh() }
    /// Throttled appear-path refresh — see `QuickNotesController.refreshIfStale`.
    func refreshQuickNotesIfStale() { quickNotesController.refreshIfStale() }
    func startQuickNote() async {
        await quickNotesController.startRecording()
    }
    func stopQuickNote() async {
        await quickNotesController.stopRecording()
        recordingMonitor.resetToIdle()
    }
    @discardableResult
    func importVoiceNote(from url: URL) async -> String? {
        await quickNotesController.importVoiceNote(from: url)
    }
    func reTranscribeQuickNote(_ note: QuickNote) { quickNotesController.reTranscribe(note) }
    func repolishQuickNote(_ note: QuickNote) { quickNotesController.rePolish(note) }
    func regenerateQuickNotePrompt(_ note: QuickNote) { quickNotesController.generatePrompt(note) }
    func saveQuickNoteTranscript(_ text: String, for note: QuickNote) {
        quickNotesController.saveTranscript(text, for: note)
    }
    func saveQuickNotePolished(_ text: String, for note: QuickNote) {
        quickNotesController.savePolished(text, for: note)
    }
    func saveQuickNotePrompt(_ text: String, for note: QuickNote) {
        quickNotesController.savePrompt(text, for: note)
    }
    func lastErrorForQuickNote(_ note: QuickNote) -> String? { quickNotesController.error(for: note) }
    func isPolishingQuickNote(_ note: QuickNote) -> Bool { quickNotesController.isPolishing(note) }
    func isStructuringQuickNotePrompt(_ note: QuickNote) -> Bool { quickNotesController.isStructuringPrompt(note) }
    func isTranscribingQuickNote(_ note: QuickNote) -> Bool { quickNotesController.isTranscribing(note) }
    func readQuickNotePolished(_ note: QuickNote) -> String { quickNotesController.readPolished(note) }
    func readQuickNotePrompt(_ note: QuickNote) -> String { quickNotesController.readPrompt(note) }
    func readQuickNoteTranscript(_ note: QuickNote) -> String { quickNotesController.readTranscript(note) }
    func deleteQuickNote(_ note: QuickNote) { quickNotesController.delete(note) }
    func quickNoteAudioURL(_ note: QuickNote) -> URL { quickNotesController.audioURL(note) }

    // MARK: - De-duplicate meetings

    /// Meetings that share a normalized title AND the same start minute are
    /// duplicates (e.g. a calendar event recorded twice, or a re-import). Groups
    /// of 2+ such meetings.
    private func duplicateMeetingGroups() -> [[Meeting]] {
        var groups: [String: [Meeting]] = [:]
        for m in pastMeetings {
            let name = m.displayTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let minute = Int(m.startDate.timeIntervalSince1970 / 60)
            groups["\(name)|\(minute)", default: []].append(m)
        }
        return groups.values.filter { $0.count > 1 }
    }

    /// How many duplicate meetings would be removed (for the confirm/summary).
    func duplicateMeetingCount() -> Int {
        duplicateMeetingGroups().reduce(0) { $0 + ($1.count - 1) }
    }

    /// Higher = keep this copy (more recorded content / a real duration / a
    /// user-given title wins).
    private func meetingRichness(_ m: Meeting) -> Int {
        var s = m.segmentCount * 4
        if m.endDate > m.startDate { s += 2 }
        if m.userTitle?.isEmpty == false { s += 2 }
        if m.notes?.isEmpty == false { s += 1 }
        if m.isImported { s += 1 }
        return s
    }

    /// Collapse each duplicate group to its richest copy; the rest are archived
    /// (moved to a recoverable trash folder) and dropped from the list. Returns
    /// the number removed.
    @discardableResult
    func deduplicateMeetings() -> Int {
        let groups = duplicateMeetingGroups()
        guard !groups.isEmpty else { return 0 }
        var removed = 0
        for group in groups {
            guard let keeper = group.max(by: { meetingRichness($0) < meetingRichness($1) }) else { continue }
            for m in group where m.id != keeper.id {
                store.archiveDuplicate(m)
                removed += 1
            }
        }
        if removed > 0 { refreshPastMeetings(force: true) }
        return removed
    }

    // MARK: - Import a meeting from external audio

    func importMeeting(from url: URL) async {
        let now = Date()
        let base = url.deletingPathExtension().lastPathComponent
        var m = Self.adhocMeeting()
        m.title = base.isEmpty ? "Imported Meeting" : base
        m.isImpromptu = true
        m.isImported = true
        m.startDate = now
        let dur = Self.audioDuration(at: url)
        m.endDate = now.addingTimeInterval(dur > 0 ? dur : 3600)
        m.segmentCount = 0
        if tagStore.tagIDs(for: m).isEmpty {
            tagStore.addTag("preset-impromptu", to: m, propagateToSeries: false)
        }
        let primary = tagStore.primaryTag(for: m)
        do {
            try store.ensureRoot()
            try store.writeMeeting(m, primaryTag: primary)
            let dir = store.directory(for: m, primaryTag: primary)
            let dest = dir.appendingPathComponent("mic.m4a")
            try await Task.detached(priority: .userInitiated) {
                try MeetingManager.convertToM4A(src: url, dest: dest)
            }.value
            AppLog.info("Meeting", "Imported audio",
                        ["meeting": m.id, "source": url.lastPathComponent])
            refreshPastMeetings(force: true)
            lastStoppedMeetingID = m.id
            transcribeNow(meeting: m, regenerateSummary: true)
        } catch {
            log.error("importMeeting failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .audio,
                                        context: ["phase": "import-meeting", "source": url.path])
            lastError = "Import failed: \(error.localizedDescription)"
        }
    }

    nonisolated static func convertToM4A(src: URL, dest: URL) throws {
        try? FileManager.default.removeItem(at: dest)
        if src.pathExtension.lowercased() == "m4a" {
            try FileManager.default.copyItem(at: src, to: dest)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        p.arguments = ["-f", "m4af", "-d", "aac", src.path, dest.path]
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "ImportMeeting", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "afconvert failed: \(msg.prefix(200))"])
        }
    }

    // MARK: - Impromptu

    func startImpromptu(source: String) {
        let now = Date()
        var m = Self.adhocMeeting()
        m.title = "Impromptu \(source) call"
        m.isImpromptu = true
        m.startDate = now
        m.endDate = now.addingTimeInterval(60 * 60)
        let presetID: String? = {
            switch source.lowercased() {
            case "zoom", "meet", "teams": return "preset-impromptu"
            case "slack", "slack huddle":  return "preset-huddle"
            default: return "preset-impromptu"
            }
        }()
        if let pid = presetID {
            tagStore.addTag(pid, to: m, propagateToSeries: false)
        }
        Task { await startRecording(for: m) }
    }

    // MARK: - Helpers

    static func adhocMeeting() -> Meeting {
        let now = Date()
        return Meeting(
            id: UUID().uuidString,
            title: "Ad-hoc Recording",
            startDate: now,
            endDate: now.addingTimeInterval(60 * 60),
            attendees: [],
            notes: nil,
            location: nil,
            conferenceURL: nil,
            calendarName: nil,
            seriesID: nil,
            userDescription: nil,
            userTitle: nil,
            isImpromptu: true,
            segmentCount: 0
        )
    }

    private static func audioDuration(at url: URL) -> Double {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }

}
