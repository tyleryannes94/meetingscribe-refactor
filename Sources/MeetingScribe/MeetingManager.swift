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

    // MARK: - Sub-controllers (Batch 6 / audit 5.1)

    let store = MeetingStore()
    let tagStore = TagStore()
    let actionItems = ActionItemStore()
    let recordingMonitor = RecordingMonitor()
    @Published var dictation = QuickDictation()

    /// In-memory cache for meeting body files (transcript / notes / summary)
    /// keyed by meeting id. Makes clicking into a meeting feel instant by
    /// returning a cached snapshot synchronously while a background refresh
    /// pulls the latest from disk. See `MeetingBodyCache`.
    lazy var bodyCache: MeetingBodyCache = MeetingBodyCache(store: store, tagStore: tagStore)

    /// Voice-notes state + behavior. Views that only render quick notes
    /// can observe this directly for scoped invalidation.
    let quickNotesController = QuickNotesController()

    /// Post-stop + Transcribe-Now pipeline state.
    lazy var pipelineController = MeetingPipelineController(
        store: store, tagStore: tagStore, actionItems: actionItems,
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
                self.state = .recording(meeting: self.activeMeeting, startedAt: Date())
                self.lastError = nil
            }
        }
        DarwinNotifier.observe(DarwinNotifier.recordingStopped) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, case .stopping = self.state else { return }
                let meeting = self.activeMeeting ?? Self.adhocMeeting()
                let primary = self.tagStore.primaryTag(for: meeting)
                await self.liveTranscriber.flush()
                let live = self.liveTranscriber.renderMarkdown()
                try? self.store.writeTranscript(live, for: meeting, primaryTag: primary)
                self.state = .idle
                self.activeMeeting = nil
                self.lastStoppedMeetingID = meeting.id
                self.recordingMonitor.resetToIdle()
                self.refreshPastMeetings(force: true)
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
        do {
            try store.ensureRoot()
            var m = meeting ?? Self.adhocMeeting()
            if meeting == nil { m.isImpromptu = true }
            if m.isImpromptu, tagStore.tagIDs(for: m).isEmpty {
                tagStore.addTag("preset-impromptu", to: m, propagateToSeries: false)
            }
            m.segmentCount = 1
            activeMeeting = m
            liveTranscriber.reset()
            let primary = tagStore.primaryTag(for: m)
            try store.writeMeeting(m, primaryTag: primary)

            // --- ScribeCore delegation with 1-second timeout fallback ---
            let scribeCoreSucceeded = await tryStartViaScribeCore()
            usingScribeCore = scribeCoreSucceeded

            if !scribeCoreSucceeded {
                // Fallback: direct AudioRecorder path
                audio.onMicChunk = { [weak self] url, _, s, e in
                    self?.liveTranscriber.submitChunk(url: url, speaker: "Me", startSec: s, endSec: e)
                }
                audio.onSystemChunk = { [weak self] url, _, s, e in
                    self?.liveTranscriber.submitChunk(url: url, speaker: "Them", startSec: s, endSec: e)
                }

                let dir = store.directory(for: m, primaryTag: primary)
                try await audio.start(in: dir, segment: m.segmentCount)
                AudioRecovery.markRecordingStarted(in: dir)
                // Use the resolved meeting `m` (which is `activeMeeting`), not the
                // `meeting` parameter — that param is nil for ad-hoc recordings, so
                // publishing it left `.recording(meeting:)` empty on the direct path
                // while `activeMeeting` was set. (ScribeCore path already used `m`.)
                state = .recording(meeting: m, startedAt: Date())
            }
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

            try await audio.start(in: dir, segment: live.segmentCount)
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
        if case .recording = state { _ = await audio.stop() }
        if let m = activeMeeting {
            AudioRecovery.clearRecordingMarker(in: store.directory(for: m, primaryTag: tagStore.primaryTag(for: m)))
        }
        activeMeeting = nil
        state = .idle
        recordingMonitor.resetToIdle()
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
        Task.detached(priority: .userInitiated) { [weak self] in
            let list = storeRef.listPastMeetings(forceRescan: force)
            await MainActor.run {
                self?.pastMeetings = list
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
        // Also refresh the past-meetings list + invalidate the body cache
        // after the pipeline finishes — the controller updates summaries /
        // action items in place, but the list snapshot here is the publish
        // source for views and the body cache must drop the now-stale entry
        // so the next read pulls the fresh transcript / summary.
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

    /// Manually add an audio file to a meeting (not a whole-meeting import). The
    /// file is copied into the meeting's `audio/` folder as the next segment and
    /// transcription is kicked off.
    func importAudioFile(_ source: URL, into meeting: Meeting) {
        let primary = tagStore.primaryTag(for: meeting)
        let dir = store.directory(for: meeting, primaryTag: primary)
        let audioDir = dir.appendingPathComponent("audio", isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
            let (mic, sys) = AudioRecovery.discoverSegments(in: dir)
            let nextIndex = max(mic.count, sys.count) + 1
            let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
            // Uploaded audio is treated as a "mic" (Me) source for transcription.
            let dest = audioDir.appendingPathComponent(String(format: "mic-%03d.%@", nextIndex, ext))
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
            AudioRecovery.rebuildManifest(in: dir)
            refreshPastMeetings(force: true)
            transcribeNow(meeting: meeting)
        } catch {
            log.error("importAudioFile failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .audio,
                                        context: ["phase": "import-audio-file", "meeting": meeting.id])
            lastError = "Couldn't import audio: \(error.localizedDescription)"
        }
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
            guard let summary = try? await summarizerRef.summarize(meeting: meeting, transcript: body) else { return }
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
                       description: String? = nil) {
        var updated = meeting
        if let title { updated.userTitle = title }
        if let description { updated.userDescription = description }
        let primary = tagStore.primaryTag(for: updated)
        do {
            try store.writeMeeting(updated, primaryTag: primary)
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

    /// Phase B — one-shot per-session pass that extracts people from the most
    /// recent meetings that haven't been processed yet.
    func backfillPeopleIfNeeded(force: Bool = false) {
        personExtraction.runIfNeeded(meetings: pastMeetings, force: force)
    }

    func userNotes(for meeting: Meeting) -> String {
        let cached = bodyCache.cached(meeting.id)
        if !cached.isEmpty { return cached.notes }
        return store.readUserNotes(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
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

    func revealInFinder(_ meeting: Meeting) {
        let dir = store.directory(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        }
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
    var quickNoteErrors: [String: String] { quickNotesController.errors }

    func refreshQuickNotes() { quickNotesController.refresh() }
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
    func saveQuickNoteTranscript(_ text: String, for note: QuickNote) {
        quickNotesController.saveTranscript(text, for: note)
    }
    func saveQuickNotePolished(_ text: String, for note: QuickNote) {
        quickNotesController.savePolished(text, for: note)
    }
    func lastErrorForQuickNote(_ note: QuickNote) -> String? { quickNotesController.error(for: note) }
    func isPolishingQuickNote(_ note: QuickNote) -> Bool { quickNotesController.isPolishing(note) }
    func isTranscribingQuickNote(_ note: QuickNote) -> Bool { quickNotesController.isTranscribing(note) }
    func readQuickNotePolished(_ note: QuickNote) -> String { quickNotesController.readPolished(note) }
    func readQuickNoteTranscript(_ note: QuickNote) -> String { quickNotesController.readTranscript(note) }
    func deleteQuickNote(_ note: QuickNote) { quickNotesController.delete(note) }
    func quickNoteAudioURL(_ note: QuickNote) -> URL { quickNotesController.audioURL(note) }

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
