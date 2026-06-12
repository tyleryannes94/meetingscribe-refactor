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
    /// completes. The `Bool` is true when summarization failed (transcript saved
    /// but no summary) so the notification layer can tell the user instead of
    /// failing silently (U4-4). Wire this to show a notification.
    var onComplete: ((Meeting, Bool) -> Void)?

    private let store: MeetingStore
    private let tagStore: TagStore
    private let actionItems: ActionItemStore
    private let decisions: DecisionStore
    private let batchTranscriber: WhisperTranscriber
    private let summarizer: OllamaService

    init(store: MeetingStore,
         tagStore: TagStore,
         actionItems: ActionItemStore,
         decisions: DecisionStore,
         batchTranscriber: WhisperTranscriber = WhisperTranscriber(),
         summarizer: OllamaService = OllamaService()) {
        self.store = store
        self.tagStore = tagStore
        self.actionItems = actionItems
        self.decisions = decisions
        self.batchTranscriber = batchTranscriber
        self.summarizer = summarizer
    }

    // MARK: - ENG-A batch-repair gate

    /// Number of seconds of tolerance (one chunk's worth) allowed between the
    /// live transcript's coverage and the real recording length before we treat
    /// the live transcript as "short" and run a batch repair pass. Chunks close
    /// on a ~5-minute boundary, so a gap under one chunk is just the in-flight
    /// tail, not a loss.
    static let liveCoverageToleranceSeconds: Double = 300

    /// Pure decision for whether the live transcript needs a batch re-transcribe
    /// over the merged audio. Extracted so it can be unit-tested without
    /// whisper-cli. Returns true when the live transcript is empty, when chunks
    /// were dropped under backpressure, when the recording is shorter than one
    /// chunk (so the live transcript is only the unvalidated in-flight flush),
    /// or when live coverage falls more than one chunk short of the real
    /// recording length. (ENG-A)
    static func needsBatchRepair(liveIsEmpty: Bool,
                                 droppedChunks: Int,
                                 coverageSeconds: Double,
                                 recordedDuration: Double,
                                 tolerance: Double = liveCoverageToleranceSeconds) -> Bool {
        if liveIsEmpty { return true }
        if droppedChunks > 0 { return true }
        // Sub-one-chunk recordings never crossed a 5-minute boundary, so the
        // live transcript is just the in-flight tail flushed at stop — which can
        // mis-transcribe even good audio (e.g. a 55s call whose single live
        // chunk produced just "you"). Always run the authoritative batch pass
        // over the afconvert→16kHz merged audio for short recordings.
        if recordedDuration > 0 && recordedDuration <= tolerance { return true }
        if recordedDuration > 0 && coverageSeconds < (recordedDuration - tolerance) { return true }
        return false
    }

    // MARK: - Finalize after stop

    /// Runs the post-stop pipeline. Caller passes the live transcript plus its
    /// drop count / coverage so we can keep a complete live transcript but fall
    /// back to a batch whisper pass when it's empty or incomplete. (ENG-A)
    /// Updates the meeting's `health` field with the recorder's snapshot.
    func finalize(meeting: Meeting,
                  audioResult: AudioRecorder.Result,
                  liveTranscript: String,
                  liveDroppedChunks: Int = 0,
                  liveCoverageSeconds: Double = 0,
                  recordedDuration: Double = 0,
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

        // 2. Decide whether to keep the live transcript or run a full batch
        //    re-transcribe over the merged audio.
        //
        //    A non-empty live transcript can still be silently incomplete:
        //      (a) chunks were dropped under backpressure (`liveDroppedChunks > 0`), or
        //      (b) one or more chunks failed whisper and produced no segment,
        //          leaving live coverage short of the real recording length.
        //    In either case the batch pass over the merged audio is the
        //    authoritative transcript, so we run it and prefer its result.
        //    Previously the batch fallback only fired when the live transcript
        //    was *empty*, so a truncated-but-nonempty transcript was persisted
        //    as-is and every downstream summary / action-item inherited the gap. (ENG-A)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveIsEmpty = trimmed.isEmpty || trimmed == "# Transcript"
        let needsBatch = Self.needsBatchRepair(liveIsEmpty: liveIsEmpty,
                                               droppedChunks: liveDroppedChunks,
                                               coverageSeconds: liveCoverageSeconds,
                                               recordedDuration: recordedDuration)
        if needsBatch {
            var sources: [WhisperTranscriber.SourceInput] = []
            if let mic = mergedMic { sources.append(.init(label: "Me", url: mic)) }
            if let sys = mergedSys { sources.append(.init(label: "Them", url: sys)) }
            if !sources.isEmpty {
                if !liveIsEmpty {
                    log.info("ENG-A repair: live transcript looks incomplete (dropped=\(liveDroppedChunks, privacy: .public), coverage=\(Int(liveCoverageSeconds), privacy: .public)s of \(Int(recordedDuration), privacy: .public)s) — running batch pass")
                }
                do {
                    let segs = try await batchTranscriber.transcribe(sources: sources,
                                                                     in: audioResult.directory)
                    let batch = "# Transcript\n\n" + WhisperTranscriber.render(segs) + "\n"
                    let batchTrimmed = batch.trimmingCharacters(in: .whitespacesAndNewlines)
                    let batchIsEmpty = batchTrimmed.isEmpty || batchTrimmed == "# Transcript"
                    // Only replace if the batch produced real content — a
                    // failed/empty batch must never clobber a partial-but-real
                    // live transcript. When both are non-empty, keep the longer
                    // (the batch is the complete one in the expected case).
                    if !batchIsEmpty {
                        transcript = (liveIsEmpty || batch.count >= transcript.count) ? batch : transcript
                    }
                } catch {
                    log.error("Fallback/repair final transcription failed: \(error.localizedDescription, privacy: .public)")
                    ErrorReporter.shared.report(error, category: .transcription,
                                                context: ["phase": "finalize-batch", "meeting": meeting.id])
                }
            }
        }
        do { try store.writeTranscript(transcript, for: workingMeeting, primaryTag: primary) }
        catch {
            log.error("Failed to write transcript: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage,
                                        context: ["phase": "write-transcript", "meeting": meeting.id])
            lastError = "Couldn't save the transcript: \(error.localizedDescription)"
        }

        // Auto-title ad-hoc captures from the first spoken line (U2-9) so the
        // Meetings list shows real content instead of an "Ad-hoc Recording" wall.
        if workingMeeting.isImpromptu,
           (workingMeeting.userTitle?.isEmpty ?? true),
           workingMeeting.title == "Ad-hoc Recording",
           let derived = Self.deriveTitle(from: transcript) {
            workingMeeting.title = derived
        }

        // 3. Summarize.
        let summary: String
        var summaryFailed = false
        do {
            summary = try await summarizer.summarize(meeting: workingMeeting, transcript: transcript)
        } catch {
            log.error("Summary failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .summary,
                                        context: ["meeting": meeting.id])
            summary = "# Summary\n\n_Summary unavailable: \(error.localizedDescription)_\n"
            summaryFailed = true
        }
        do { try store.writeSummary(summary, for: workingMeeting, primaryTag: primary) }
        catch {
            log.error("Failed to write summary: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage,
                                        context: ["phase": "write-summary", "meeting": meeting.id])
            lastError = "Couldn't save the summary: \(error.localizedDescription)"
        }
        store.cleanChunks(for: workingMeeting, primaryTag: primary)

        // Persist health alongside the meeting.
        try? store.writeMeeting(workingMeeting, primaryTag: primary)

        // 4. Action items. Resolve each owner string to a real Person id via the
        // one identity layer so tasks carry a person edge (P1-1/P2-1), then
        // auto-link the meeting's calendar attendees to their Person records.
        var extracted = ActionItemExtractor.extract(from: summary, meeting: workingMeeting)
        let knownPeople = PeopleStore.shared.people
        for i in extracted.indices where extracted[i].ownerPersonID == nil {
            extracted[i].ownerPersonID = PersonResolver.resolveOwner(extracted[i].owner, in: knownPeople)
        }
        actionItems.reconcileExtracted(extracted, for: workingMeeting.id)
        PeopleStore.shared.linkAttendees(of: workingMeeting)
        PeopleStore.shared.emitMeetingEncounters(for: workingMeeting)   // P1-9

        lastCompletedDir = store.directory(for: workingMeeting, primaryTag: primary)

        // 5. Write in-folder markdown snapshot. Pass real tag names so the
        // canonical file is Obsidian-native and never ships a date-partition
        // folder name as a tag. (C3-1)
        let finalDir = store.directory(for: workingMeeting, primaryTag: primary)
        let tagNameList = tagStore.tagIDs(for: workingMeeting)
            .compactMap { tagStore.tag(by: $0)?.name }
        ObsidianExporter.writeMarkdownFile(for: workingMeeting, to: finalDir, tags: tagNameList)

        // 6. Index into vault FTS so GlobalSearch finds this meeting.
        let tagNames = tagNameList.joined(separator: " ")
        PeopleStore.shared.indexMeeting(workingMeeting,
                                        summary: summary,
                                        tags: tagNames.isEmpty ? nil : tagNames)
        // Semantic embedding for hybrid recall (C2-1b) — fire-and-forget so the
        // network round-trip to the local embedding model never blocks finalize.
        let embedText = workingMeeting.displayTitle + "\n" + summary
        let embedID = workingMeeting.id
        Task { await PeopleStore.shared.embedAndStore(entityID: embedID, entityKind: "meeting", text: embedText) }

        // Append to the day's note — a linkable temporal spine. (C2-4/C3-3)
        DailyNoteWriter.appendMeeting(workingMeeting, storageDir: AppSettings.shared.storageDir)

        // Lift decisions out of the summary into the cross-meeting ledger. (P1-1)
        decisions.extract(from: summary, meeting: workingMeeting)

        MetricsStore.shared.record(.summaryGenerated)   // local-only metric (P5-1)

        liveResetIfStillIdle()

        // Notify interested parties (e.g. NotificationManager) that the
        // pipeline for this meeting has finished.
        onComplete?(workingMeeting, summaryFailed)
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
        var summaryFailed = false
        if regenerateSummary {
            do {
                let summary = try await summarizer.summarize(meeting: meeting, transcript: transcript)
                await MainActor.run {
                    try? store.writeSummary(summary, for: meeting, primaryTag: primary)
                    var extracted = ActionItemExtractor.extract(from: summary, meeting: meeting)
                    let knownPeople = PeopleStore.shared.people
                    for i in extracted.indices where extracted[i].ownerPersonID == nil {
                        extracted[i].ownerPersonID = PersonResolver.resolveOwner(extracted[i].owner, in: knownPeople)
                    }
                    actionItems.reconcileExtracted(extracted, for: meeting.id)
                    PeopleStore.shared.linkAttendees(of: meeting)
                    let tagNameList = tagStore.tagIDs(for: meeting)
                        .compactMap { tagStore.tag(by: $0)?.name }
                    ObsidianExporter.writeMarkdownFile(for: meeting, to: dir, tags: tagNameList)
                    // Index into vault FTS.
                    let tagNames = tagNameList.joined(separator: " ")
                    PeopleStore.shared.indexMeeting(meeting,
                                                    summary: summary,
                                                    tags: tagNames.isEmpty ? nil : tagNames)
                    decisions.extract(from: summary, meeting: meeting)   // ledger (P1-1)
                }
            } catch {
                log.error("transcribeNow summary failed: \(error.localizedDescription, privacy: .public)")
                ErrorReporter.shared.reportAsync(error, category: .summary,
                                                 context: ["phase": "transcribe-now-summary", "meeting": meeting.id])
                summaryFailed = true
            }
        } else {
            // Even without a summary regeneration, refresh the markdown snapshot.
            await MainActor.run {
                let tagNameList = tagStore.tagIDs(for: meeting)
                    .compactMap { tagStore.tag(by: $0)?.name }
                ObsidianExporter.writeMarkdownFile(for: meeting, to: dir, tags: tagNameList)
            }
        }

        // Signal completion to registered observers.
        await MainActor.run { self.onComplete?(meeting, summaryFailed) }
    }

    // MARK: - Auto-title (U2-9)

    /// Derive a short meeting title from the first spoken line of a transcript.
    /// Strips a leading speaker/timestamp prefix ("Me [0:05]:") and caps the
    /// result to ~8 words / 60 chars. Returns nil for an empty transcript.
    nonisolated static func deriveTitle(from transcript: String) -> String? {
        for raw in transcript.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(">") || line.hasPrefix("---") { continue }
            // Strip a short leading "Speaker:" / "Me [0:05]:" prefix. Use the
            // LAST colon within the first ~24 chars so the "0:05" timestamp
            // colon doesn't truncate the speaker label mid-prefix.
            let headEnd = line.index(line.startIndex, offsetBy: min(24, line.count))
            if let lastColon = line[line.startIndex..<headEnd].lastIndex(of: ":") {
                line = String(line[line.index(after: lastColon)...]).trimmingCharacters(in: .whitespaces)
            }
            guard !line.isEmpty else { continue }
            let words = line.split(separator: " ").prefix(8)
            var title = words.joined(separator: " ")
            if title.count > 60 {
                title = String(title.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
            }
            return title.isEmpty ? nil : title
        }
        return nil
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
