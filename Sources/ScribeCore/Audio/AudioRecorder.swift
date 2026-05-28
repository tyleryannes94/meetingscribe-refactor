import Foundation
import AVFoundation
import VaultKit
import OSLog

/// Coordinates microphone and system audio capture for a single meeting.
/// Each call to `start(in:segment:)` writes a NEW pair of segment files:
///   <dir>/audio/mic-001.m4a, system-001.m4a, mic-002.m4a, …
/// After all segments are recorded, call `mergeSegments(in:totalSegments:)`
/// to produce the final `<dir>/mic.m4a` and `<dir>/system.m4a`.
///
/// Hardening:
///   - Watchdog timer fires every 5s during recording and asks each source
///     recorder to check its sample-flow freshness; stale sources restart.
///   - `ProcessInfo.beginActivity` keeps the OS from throttling/suspending
///     us during long recordings.
///   - Publishes `health` snapshots so the UI can show "last audio sample
///     N seconds ago" indicators.
///   - Final-pass merge is a passthrough mux via AVAssetReader +
///     AVAssetWriter (no re-encode) — was previously
///     `AVAssetExportPresetAppleM4A` which re-encoded the whole concatenated
///     stream for every meeting end (audit 3.3).
///   - `stop()` returns a `MeetingHealthDTO` describing how the recording
///     went so the pipeline can persist a status badge.
@available(macOS 14.0, *)
final class AudioRecorder {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "AudioRecorder")

    private let mic = MicRecorder()
    private let system = SystemAudioRecorder()

    private(set) var micChunkWriter: ChunkedAudioWriter?
    private(set) var systemChunkWriter: ChunkedAudioWriter?
    private(set) var currentDirectory: URL?
    private(set) var currentSegment: Int = 0

    private var watchdog: Timer?
    private var activityToken: NSObjectProtocol?

    struct Health: Equatable {
        var micSamples: Int = 0
        var systemSamples: Int = 0
        var micSecondsSinceLastSample: Double = 0
        var systemSecondsSinceLastSample: Double = 0
        var micRestarts: Int = 0
        var systemRestarts: Int = 0
        var lastError: String?
        /// Latest RMS amplitude per source (0...1), updated as each audio
        /// buffer arrives. Drives the live waveform/bars indicator.
        var micLevel: Float = 0
        var systemLevel: Float = 0
        /// True if either source has been stalled longer than 10s.
        var isStalled: Bool {
            micSecondsSinceLastSample > 10 || systemSecondsSinceLastSample > 10
        }
    }

    /// Fired on the main queue every 5s during recording (and on any source
    /// health change). Drive the UI from this.
    var onHealth: ((Health) -> Void)?

    /// Fired when both mic AND system audio have been silent for the
    /// `silenceAutoStopSeconds` window (default 5 min). MeetingManager
    /// hooks this to stop the recording automatically.
    var onSilenceAutoStop: (() -> Void)?

    /// Silence window before auto-stop. 300s = 5 min, matching the user's
    /// request. Set to 0 to disable.
    var silenceAutoStopSeconds: TimeInterval = 300

    /// Grace period after recording starts during which we ignore silence
    /// (avoids stopping immediately if the mic is muted at the very start).
    private var startTime: Date?

    struct Result {
        let directory: URL
        let segmentIndex: Int
        let micURL: URL?
        let systemURL: URL?
        /// End-of-segment health summary. Drives meeting health badges.
        let health: MeetingHealthDTO
    }

    /// Per-source chunk callback. Fires on each writer's queue.
    var onMicChunk: ((URL, Int, Double, Double) -> Void)?
    var onSystemChunk: ((URL, Int, Double, Double) -> Void)?

    /// Starts recording a new segment. `segment` is 1-indexed.
    func start(in directory: URL, segment: Int) async throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let audioDir = directory.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let chunksDir = directory.appendingPathComponent("chunks", isDirectory: true)
        try FileManager.default.createDirectory(at: chunksDir, withIntermediateDirectories: true)

        currentDirectory = directory
        currentSegment = segment

        let micName = String(format: "mic-%03d.m4a", segment)
        let systemName = String(format: "system-%03d.m4a", segment)
        let micURL = audioDir.appendingPathComponent(micName)
        let systemURL = audioDir.appendingPathComponent(systemName)

        let settings = AppSettings.shared
        var errors: [Error] = []

        // Surface health changes from each source into the unified callback.
        mic.onHealthChange = { [weak self] _ in self?.publishHealth() }
        system.onHealthChange = { [weak self] _ in self?.publishHealth() }

        var enabledMic = false
        var enabledSystem = false

        if settings.captureMic {
            let writer = ChunkedAudioWriter(dir: chunksDir, label: "mic-seg\(segment)", chunkSeconds: 300)
            writer.onChunkReady = { [weak self] url, idx, s, e in
                self?.onMicChunk?(url, idx, s, e)
            }
            micChunkWriter = writer
            do {
                try mic.start(outputURL: micURL, chunkWriter: writer)
                enabledMic = true
            } catch {
                log.error("Mic start failed: \(error.localizedDescription, privacy: .public)")
                ErrorReporter.shared.reportAsync(error, category: .audio,
                                                 context: ["phase": "mic-start"])
                errors.append(error)
                micChunkWriter = nil
            }
        }
        if settings.captureSystem {
            let writer = ChunkedAudioWriter(dir: chunksDir, label: "system-seg\(segment)", chunkSeconds: 300)
            writer.onChunkReady = { [weak self] url, idx, s, e in
                self?.onSystemChunk?(url, idx, s, e)
            }
            systemChunkWriter = writer
            do {
                try await system.start(outputURL: systemURL, chunkWriter: writer)
                enabledSystem = true
            } catch {
                log.error("System start failed: \(error.localizedDescription, privacy: .public)")
                ErrorReporter.shared.reportAsync(error, category: .audio,
                                                 context: ["phase": "system-start"])
                errors.append(error)
                systemChunkWriter = nil
            }
        }

        if !settings.captureMic && !settings.captureSystem {
            throw NSError(domain: "MeetingScribe", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Both mic and system capture are disabled."])
        }
        if errors.count == 2 { throw errors[0] }

        // Record manifest entry so future tools (transcribe-now, importers)
        // know which files belong to which segment without filename parsing.
        try? AudioManifestStore.appendSegment(meetingDir: directory,
                                              micFile: enabledMic ? micName : nil,
                                              systemFile: enabledSystem ? systemName : nil,
                                              startedAt: Date())

        // Tell the OS this app is doing important user-initiated work — keep
        // it on the high-throughput scheduler band and don't suspend it.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
            reason: "MeetingScribe recording in progress"
        )

        startTime = Date()
        startWatchdog()
    }

    func stop() async -> Result {
        stopWatchdog()
        let started = startTime
        startTime = nil
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }

        mic.stop()
        await system.stop()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            if let w = micChunkWriter {
                group.enter()
                w.finalize { group.leave() }
            }
            if let w = systemChunkWriter {
                group.enter()
                w.finalize { group.leave() }
            }
            group.notify(queue: .main) { cont.resume() }
        }
        micChunkWriter = nil
        systemChunkWriter = nil

        let dir = currentDirectory ?? FileManager.default.temporaryDirectory
        // Close the manifest entry for this segment.
        AudioManifestStore.closeLastSegment(meetingDir: dir)

        let audioDir = dir.appendingPathComponent("audio", isDirectory: true)
        let mURL = audioDir.appendingPathComponent(String(format: "mic-%03d.m4a", currentSegment))
        let sURL = audioDir.appendingPathComponent(String(format: "system-%03d.m4a", currentSegment))
        let resolvedMic = FileManager.default.fileExists(atPath: mURL.path) ? mURL : nil
        let resolvedSys = FileManager.default.fileExists(atPath: sURL.path) ? sURL : nil

        let health = computeHealth(startedAt: started,
                                   micURL: resolvedMic, systemURL: resolvedSys)
        return Result(directory: dir,
                      segmentIndex: currentSegment,
                      micURL: resolvedMic,
                      systemURL: resolvedSys,
                      health: health)
    }

    /// Build a `MeetingHealthDTO` from the per-segment recorder counters
    /// + on-disk byte sizes. Drives the end-of-meeting UI badge (audit 8.1B).
    private func computeHealth(startedAt: Date?, micURL: URL?, systemURL: URL?) -> MeetingHealthDTO {
        let micSnap = mic.counters.snapshot()
        let sysSnap = system.counters.snapshot()
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0

        func bytes(_ url: URL?) -> Int64 {
            guard let url else { return 0 }
            return Int64((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
        }
        let micBytes = bytes(micURL)
        let sysBytes = bytes(systemURL)
        let captureMic = AppSettings.shared.captureMic
        let captureSystem = AppSettings.shared.captureSystem

        var warnings: [String] = []
        if captureMic, micSnap.samplesAppended == 0 {
            warnings.append("Mic captured no audio. Check Microphone permission in System Settings → Privacy & Security.")
        }
        if captureSystem, sysSnap.samplesAppended == 0 {
            warnings.append("System audio captured no audio. Check Screen Recording permission — after granting, quit and relaunch the app.")
        }
        if let err = micSnap.lastError { warnings.append("Mic: \(err)") }
        if let err = sysSnap.lastError { warnings.append("System: \(err)") }

        let bothDead = (captureMic && micSnap.samplesAppended == 0) &&
                       (captureSystem && sysSnap.samplesAppended == 0)
        let oneDead  = (captureMic && micSnap.samplesAppended == 0) !=
                       (captureSystem && sysSnap.samplesAppended == 0)

        let status: MeetingHealthDTO.Status
        if bothDead { status = .noTranscript }
        else if oneDead { status = .partial }
        else { status = .ok }

        return MeetingHealthDTO(status: status,
                                warnings: warnings,
                                recordedSeconds: elapsed,
                                micBytes: micBytes,
                                systemBytes: sysBytes)
    }

    // MARK: - Watchdog

    private var silenceCheckCounter = 0

    private func startWatchdog() {
        watchdog?.invalidate()
        // 0.1s tick drives the live audio-level meter. Heavy checks (stall
        // recovery, silence auto-stop) only fire every 50 ticks (~5s) so we
        // don't burn CPU.
        let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.publishHealth()
            self.silenceCheckCounter += 1
            if self.silenceCheckCounter >= 50 {
                self.silenceCheckCounter = 0
                self.mic.checkHealth(staleAfter: 8)
                Task { await self.system.checkHealth(staleAfter: 8) }
                self.checkSilenceAutoStop()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    private func checkSilenceAutoStop() {
        guard silenceAutoStopSeconds > 0 else { return }
        guard let start = startTime else { return }
        // 30s grace period after start so we don't kill a recording that
        // just hasn't picked up any sound yet.
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 30 else { return }

        let now = Date()
        let micSilence = mic.lastSoundAt.map { now.timeIntervalSince($0) } ?? elapsed
        let sysSilence = system.lastSoundAt.map { now.timeIntervalSince($0) } ?? elapsed
        let bothSilent = micSilence >= silenceAutoStopSeconds &&
                         sysSilence >= silenceAutoStopSeconds
        if bothSilent {
            log.info("Auto-stop: \(Int(self.silenceAutoStopSeconds))s of silence on both mic AND system audio.")
            DispatchQueue.main.async { [weak self] in self?.onSilenceAutoStop?() }
            startTime = nil  // don't refire while the stop is in flight
        }
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    private func publishHealth() {
        let now = Date()
        let micSnap = mic.counters.snapshot()
        let sysSnap = system.counters.snapshot()
        let health = Health(
            micSamples: micSnap.samplesAppended,
            systemSamples: sysSnap.samplesAppended,
            micSecondsSinceLastSample: micSnap.lastSampleAt.map { now.timeIntervalSince($0) } ?? 0,
            systemSecondsSinceLastSample: sysSnap.lastSampleAt.map { now.timeIntervalSince($0) } ?? 0,
            micRestarts: micSnap.restartCount,
            systemRestarts: sysSnap.restartCount,
            lastError: micSnap.lastError ?? sysSnap.lastError,
            micLevel: micSnap.currentLevel,
            systemLevel: sysSnap.currentLevel
        )
        DispatchQueue.main.async { [weak self] in self?.onHealth?(health) }
    }

    // MARK: - Segment merging

    enum MergeError: Error, LocalizedError {
        case exportFailed(String)
        case noSegments
        var errorDescription: String? {
            switch self {
            case .exportFailed(let m): return "Audio merge failed: \(m)"
            case .noSegments: return "No audio segments to merge."
            }
        }
    }

    /// Concatenates `mic-001.m4a..mic-NNN.m4a` into `mic.m4a` (and likewise for
    /// system). Skips a source if it has no segments. Idempotent — overwrites
    /// the merged files. Uses passthrough mux — no re-encode.
    static func mergeSegments(in directory: URL, totalSegments: Int) async throws -> (mic: URL?, system: URL?) {
        guard totalSegments > 0 else { throw MergeError.noSegments }
        let audioDir = directory.appendingPathComponent("audio", isDirectory: true)
        let micSegments = (1...totalSegments).map {
            audioDir.appendingPathComponent(String(format: "mic-%03d.m4a", $0))
        }.filter { FileManager.default.fileExists(atPath: $0.path) }
        let sysSegments = (1...totalSegments).map {
            audioDir.appendingPathComponent(String(format: "system-%03d.m4a", $0))
        }.filter { FileManager.default.fileExists(atPath: $0.path) }

        let micOut = directory.appendingPathComponent("mic.m4a")
        let sysOut = directory.appendingPathComponent("system.m4a")

        async let mic: URL? = mergeOrSkip(segments: micSegments, into: micOut)
        async let sys: URL? = mergeOrSkip(segments: sysSegments, into: sysOut)
        return try await (mic, sys)
    }

    /// One segment: just copy. Multiple: concat via the passthrough merger.
    private static func mergeOrSkip(segments: [URL], into output: URL) async throws -> URL? {
        guard let first = segments.first else { return nil }
        try? FileManager.default.removeItem(at: output)
        if segments.count == 1 {
            try FileManager.default.copyItem(at: first, to: output)
            return output
        }
        try await PassthroughAudioMerger.merge(segments: segments, into: output)
        return output
    }
}
