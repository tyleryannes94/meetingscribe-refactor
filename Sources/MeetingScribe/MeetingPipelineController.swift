import Foundation
import VaultKit
import OSLog

/// Owns the background pipeline that runs AFTER `MeetingManager.stopRecording`:
///   1. Merge per-segment files
///   2. Run the final whisper pass (or accept the live transcript if useful)
///   3. Generate Ollama summary
///   4. Extract action items, reconcile into the store
///
/// Also owns the "Transcribe Now" button state per meeting (`transcribingIDs`).
/// Extracted from MeetingManager in Batch 6 (audit 5.1) so views observing
/// pipeline progress don't invalidate on unrelated state changes.
@available(macOS 14.0, *)
@MainActor
final class MeetingPipelineController: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Pipeline")

    /// IDs of past meetings currently being (re-)transcribed via the
    /// "Transcribe Now" button. Independent of the global recording state so
    /// the user can start a new recording for a different meeting.
    @Published private(set) var transcribingIDs: Set<String> = []
    /// Directory of the most recently finalized meeting — so the UI can
    /// auto-select it after stop.
    @Published private(set) var lastCompletedDir: URL?
    /// Most recent pipeline error surfaced to the user.
    @Published var lastError: String?

    /// Called on the main actor when a pipeline run (finalize OR transcribeNow)
    /// completes successfully. Wire this to show a notification.
    var onComplete: ((Meeting) -> Void)?

    private let store: MeetingStore
    private let tagStore: TagStore
    private let actionItems: ActionItemStore
    private let batchTranscriber: WhisperTranscriber
    private let summarizer: OllamaService

    init(store: MeetingStore,
         tagStore: TagStore,
         actionItems: ActionItemStore,
         batchTranscriber: WhisperTranscriber = WhisperTranscriber(),
         summarizer: OllamaService = OllamaService()) {
        self.store = store
        self.tagStore = tagStore
        self.actionItems = actionItems
        self.batchTranscriber = batchTranscriber
        self.summarizer = summarizer
    }

    // MARK: - Finalize after stop

    /// Runs the post-stop pipeline. Caller passes the live transcript so we
    /// can skip a redundant whisper batch pass when the live one is useful.
    /// Updates the meeting's `health` field with the recorder's snapshot.
    func finalize(meeting: Meeting,
                  audioResult: AudioRecorder.Result,
                  liveTranscript: String,
                  liveResetIfStillIdle: () -> Void) async {
        AppLog.info("Meeting", "Finalize pipeline started", ["meeting": meeting.id])
        transcribingIDs.insert(meeting.id)
        defer { transcribingIDs.remove(meeting.id) }

        let primary = tagStore.primaryTag(for: meeting)
        var transcript = liveTranscript
        var workingMeeting = meeting
        workingMeeting.health = audioResult.health

        // 1. Merge per-segment files into <dir>/{mic,system}.m4a.
        var mergedMic: URL? = audioResult.micURL
        var mergedSys: URL? = audioResult.systemURL
        let segments = AudioManifestStore.segmentCount(meetingDir: audioResult.directory)
        if segments > 0 {
            do {
                let merged = try await AudioRecorder.mergeSegments(in: audioResult.directory,
                                                                   totalSegments: segments)
                mergedMic = merged.mic ?? mergedMic
                mergedSys = merged.system ?? mergedSys
            } catch {
                log.error("Segment merge failed: \(error.localizedDescription, privacy: .public)")
                ErrorReporter.shared.report(error, category: .audio,
                                            context: ["phase": "finalize-merge", "meeting": meeting.id])
            }
        }

        // 2. Decide whether the live transcript is good enough.
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveIsUseful = !trimmed.isEmpty && trimmed != "# Transcript"
        if !liveIsUseful {
            var sources: [WhisperTranscriber.SourceInput] = []
            if let mic = mergedMic { sources.append(.init(label: "Me", url: mic)) }
            if let sys = mergedSys { sources.append(.init(label: "Them", url: sys)) }
            if !sources.isEmpty {
                do {
                    let segs = try await batchTranscriber.transcribe(sources: sources,
                                                                     in: audioResult.directory)
                    transcript = "# Transcript\n\n" + WhisperTranscriber.render(segs) + "\n"
                } catch {
                    log.error("Fallback final transcription failed: \(error.localizedDescription, privacy: .public)")
                    ErrorReporter.shared.report(error, category: .transcription,
                                                context: ["phase": "finalize-batch", "meeting": meeting.id])
                }
            }
        }
        try? store.writeTranscript(transcript, for: workingMeeting, primaryTag: primary)

        // 3. Summarize.
        let summary: String
        do {
            summary = try await summarizer.summarize(meeting: workingMeeting, transcript: transcript)
        } catch {
            log.error("Summary failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .summary,
                                        context: ["meeting": meeting.id])
            summary = "# Summary\n\n_Summary unavailable: \(error.localizedDescription)_\n"
        }
        try? store.writeSummary(summary, for: workingMeeting, primaryTag: primary)
        store.cleanChunks(for: workingMeeting, primaryTag: primary)

        // Persist health alongside the meeting.
        try? store.writeMeeting(workingMeeting, primaryTag: primary)

        // 4. Action items.
        let extracted = ActionItemExtractor.extract(from: summary, meeting: workingMeeting)
        actionItems.reconcileExtracted(extracted, for: workingMeeting.id)

        lastCompletedDir = store.directory(for: workingMeeting, primaryTag: primary)

        // 5. Write in-folder markdown snapshot.
        let finalDir = store.directory(for: workingMeeting, primaryTag: primary)
        ObsidianExporter.writeMarkdownFile(for: workingMeeting, to: finalDir)

        // 6. Index into vault FTS so GlobalSearch finds this meeting.
        let tagNames = tagStore.tagIDs(for: workingMeeting)
            .compactMap { tagStore.tag(by: $0)?.name }
            .joined(separator: " ")
        PeopleStore.shared.indexMeeting(workingMeeting,
                                        summary: summary,
                                        tags: tagNames.isEmpty ? nil : tagNames)

        liveResetIfStillIdle()

        // Notify interested parties (e.g. NotificationManager) that the
        // pipeline for this meeting has finished.
        onComplete?(workingMeeting)
    }

    // MARK: - Transcribe Now

    func isTranscribing(_ meeting: Meeting) -> Bool {
        transcribingIDs.contains(meeting.id)
    }

    /// Synchronously mark a meeting as "in the pipeline" from the main actor,
    /// BEFORE the detached `finalize` task actually starts. Closes the window
    /// where a user hitting "Transcribe Now" between stop and finalize's own
    /// insert would launch a second pipeline that clobbers transcript.md /
    /// summary.md for the same meeting. Idempotent with finalize's insert. (ENG-C)
    func beginPipeline(_ meetingID: String) {
        transcribingIDs.insert(meetingID)
    }

    func transcribeNow(meeting: Meeting, regenerateSummary: Bool = true) {
        guard !transcribingIDs.contains(meeting.id) else { return }
        transcribingIDs.insert(meeting.id)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runTranscribePipeline(meeting: meeting,
                                             regenerateSummary: regenerateSummary)
            await MainActor.run {
                self.transcribingIDs.remove(meeting.id)
            }
        }
    }

    private func runTranscribePipeline(meeting: Meeting, regenerateSummary: Bool) async {
        let primary = await MainActor.run { tagStore.primaryTag(for: meeting) }
        let dir = await MainActor.run { store.directory(for: meeting, primaryTag: primary) }

        // 1. Migrate any legacy top-level mic.m4a / system.m4a → audio/mic-001.m4a etc.
        migrateLegacyAudio(in: dir)

        // 1b. Failsafe: if the meeting lives in iCloud and its segments were
        // evicted, pull them back down before we try to read/merge them.
        await AudioRecovery.ensureDownloaded(in: dir)

        // 2. Discover segments (iCloud- and extension-tolerant).
        let (mics, systems) = filesByPrefix(in: dir)
        let totalSegments = max(mics.count, systems.count)
        guard totalSegments > 0 else {
            await MainActor.run { self.lastError = "No audio segments found for this meeting." }
            return
        }

        // 3. Merge segments → mic.m4a + system.m4a (passthrough, no re-encode).
        var mergedMic: URL?
        var mergedSys: URL?
        do {
            let merged = try await AudioRecorder.mergeSegments(in: dir, totalSegments: totalSegments)
            mergedMic = merged.mic
            mergedSys = merged.system
        } catch {
            log.error("transcribeNow merge failed: \(error.localizedDescription, privacy: .public)")
        }

        // 4. Whisper on merged files (fall back to segments if merge failed).
        var sources: [WhisperTranscriber.SourceInput] = []
        if let mic = mergedMic { sources.append(.init(label: "Me", url: mic)) }
        else if let first = mics.first { sources.append(.init(label: "Me", url: first)) }
        if let sys = mergedSys { sources.append(.init(label: "Them", url: sys)) }
        else if let first = systems.first { sources.append(.init(label: "Them", url: first)) }
        guard !sources.isEmpty else { return }

        let transcript: String
        do {
            let segments = try await batchTranscriber.transcribe(sources: sources, in: dir)
            transcript = "# Transcript\n\n" + WhisperTranscriber.render(segments) + "\n"
            try await MainActor.run { try store.writeTranscript(transcript, for: meeting, primaryTag: primary) }
        } catch {
            log.error("transcribeNow whisper failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.reportAsync(error, category: .transcription,
                                             context: ["phase": "transcribe-now", "meeting": meeting.id])
            await MainActor.run { self.lastError = "Transcription failed: \(error.localizedDescription)" }
            return
        }

        // 5. Regenerate summary (best effort).
        if regenerateSummary {
            do {
                let summary = try await summarizer.summarize(meeting: meeting, transcript: transcript)
                await MainActor.run {
                    try? store.writeSummary(summary, for: meeting, primaryTag: primary)
                    let extracted = ActionItemExtractor.extract(from: summary, meeting: meeting)
                    actionItems.reconcileExtracted(extracted, for: meeting.id)
                    ObsidianExporter.writeMarkdownFile(for: meeting, to: dir)
                    // Index into vault FTS.
                    let tagNames = tagStore.tagIDs(for: meeting)
                        .compactMap { tagStore.tag(by: $0)?.name }
                        .joined(separator: " ")
                    PeopleStore.shared.indexMeeting(meeting,
                                                    summary: summary,
                                                    tags: tagNames.isEmpty ? nil : tagNames)
                }
            } catch {
                log.error("transcribeNow summary failed: \(error.localizedDescription, privacy: .public)")
                ErrorReporter.shared.reportAsync(error, category: .summary,
                                                 context: ["phase": "transcribe-now-summary", "meeting": meeting.id])
            }
        } else {
            // Even without a summary regeneration, refresh the markdown snapshot.
            await MainActor.run { ObsidianExporter.writeMarkdownFile(for: meeting, to: dir) }
        }

        // Signal completion to registered observers.
        await MainActor.run { self.onComplete?(meeting) }
    }

    // MARK: - Disk helpers (nonisolated; called from detached tasks)

    nonisolated private func filesByPrefix(in dir: URL) -> (mic: [URL], system: [URL]) {
        // Delegate to the shared, iCloud-/extension-tolerant discovery so the
        // transcription pipeline recovers evicted and non-.m4a segments too.
        AudioRecovery.discoverSegments(in: dir)
    }

    nonisolated private func migrateLegacyAudio(in dir: URL) {
        let fm = FileManager.default
        let (mics, sys) = filesByPrefix(in: dir)
        guard mics.isEmpty && sys.isEmpty else { return }
        let audioDir = dir.appendingPathComponent("audio", isDirectory: true)
        try? fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let legacyMic = dir.appendingPathComponent("mic.m4a")
        let legacySys = dir.appendingPathComponent("system.m4a")
        if fm.fileExists(atPath: legacyMic.path) {
            try? fm.copyItem(at: legacyMic, to: audioDir.appendingPathComponent("mic-001.m4a"))
        }
        if fm.fileExists(atPath: legacySys.path) {
            try? fm.copyItem(at: legacySys, to: audioDir.appendingPathComponent("system-001.m4a"))
        }
    }
}
