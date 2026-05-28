import Foundation
import AVFoundation
import ScreenCaptureKit
import os
import OSLog

/// Captures system audio via ScreenCaptureKit and writes it to an .m4a file.
/// Optionally also forwards PCM buffers to a `ChunkedAudioWriter` for streaming
/// transcription.
///
/// Architecture (rewritten in the Batch 4 audio refactor):
///   - All cross-thread mutable health state lives in a lock-protected
///     `AudioCounters` (`os.OSAllocatedUnfairLock`) — previously bare
///     primitives that were UB under Swift's concurrency model.
///   - The `restartStream` reentrancy guard is now an unfair-lock CAS
///     instead of a plain bool, fixing the audit-5.2 race where two
///     restarts could slip past the check before either flag-set ran.
@available(macOS 14.0, *)
final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "SystemAudio")

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var startedSession = false
    private let queue = DispatchQueue(label: "MeetingScribe.SystemAudio")
    private weak var chunkWriter: ChunkedAudioWriter?

    /// Lock-protected health snapshot — shared across the SCStream
    /// callback queue and the main-thread watchdog.
    let counters = AudioCounters()
    /// Set by AudioRecorder so we can call back when recording health changes.
    var onHealthChange: ((SystemAudioRecorder) -> Void)?

    // Mirror old API surface so call sites stay working.
    var samplesAppended: Int { counters.snapshot().samplesAppended }
    var lastSampleAt: Date? { counters.snapshot().lastSampleAt }
    var lastSoundAt: Date? { counters.snapshot().lastSoundAt }
    var currentLevel: Float { counters.snapshot().currentLevel }
    var stallCount: Int { counters.snapshot().restartCount }
    var lastError: String? { counters.snapshot().lastError }

    /// State preserved across reconnect attempts so we can fully restart.
    private var savedOutputURL: URL?
    /// CAS-style guard for `restartStream`: only one restart in flight at a
    /// time. Replaces the audit-5.2 race where two restarts could slip past
    /// a plain bool check.
    private let restartGuard = OSAllocatedUnfairLock<Bool>(initialState: false)

    private(set) var outputURL: URL?

    func start(outputURL: URL, chunkWriter: ChunkedAudioWriter?) async throws {
        self.outputURL = outputURL
        self.savedOutputURL = outputURL
        self.chunkWriter = chunkWriter
        try? FileManager.default.removeItem(at: outputURL)
        try await startInternal(outputURL: outputURL, removingExisting: false)
    }

    private func startInternal(outputURL: URL, removingExisting: Bool) async throws {
        if removingExisting {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                          onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "MeetingScribe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display available for capture."])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        // 16 kHz mono is the format whisper wants, and cuts buffer pool size.
        config.sampleRate = 16_000
        config.channelCount = 1
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "MeetingScribe", code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed to start."])
        }
        self.writer = writer
        self.writerInput = input
        self.startedSession = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        log.info("System audio capture started: \(outputURL.path, privacy: .public)")
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        writerInput?.markAsFinished()
        if let writer {
            await writer.finishWriting()
            if writer.status == .failed {
                let msg = writer.error?.localizedDescription ?? "unknown"
                log.error("AVAssetWriter ended in .failed: \(msg, privacy: .public)")
                counters.setLastError("AVAssetWriter failed at end: \(msg)")
            }
        }
        writer = nil
        writerInput = nil
        startedSession = false
        let snap = counters.snapshot()
        log.info("System audio capture stopped. samples=\(snap.samplesAppended) stalls=\(snap.restartCount)")
    }

    /// Called from AudioRecorder's watchdog. If no samples have arrived for
    /// `staleAfter` seconds, count it as a stall and attempt to restart.
    func checkHealth(staleAfter: TimeInterval = 8) async {
        guard let stream, let lastSampleAt = counters.snapshot().lastSampleAt else { return }
        let age = Date().timeIntervalSince(lastSampleAt)
        guard age > staleAfter else { return }
        log.error("System audio stalled — no samples for \(age, format: .fixed(precision: 1))s. Restarting stream.")
        counters.incrementRestart(reason: "System audio stalled for \(Int(age))s; restarting.")
        onHealthChange?(self)
        _ = stream  // silence unused warning when restartInFlight
        await restartStream()
    }

    /// Attempts to restart the SCStream while keeping the same AVAssetWriter
    /// session, so any audio captured before the stall stays in the same file.
    ///
    /// The restart guard is an unfair-lock CAS — the prior bool-based check
    /// was racy under audit 5.2 (two callers could read `false`, both write
    /// `true`, both proceed).
    private func restartStream() async {
        let alreadyRestarting = restartGuard.withLock { state -> Bool in
            if state { return true }
            state = true
            return false
        }
        if alreadyRestarting { return }
        defer { restartGuard.withLock { $0 = false } }

        if let s = stream {
            try? await s.stopCapture()
        }
        stream = nil
        guard let url = savedOutputURL else { return }
        // We don't tear down the writer — keep appending into the same file.
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                              onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 16_000
            config.channelCount = 1
            config.width = 2; config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await s.startCapture()
            self.stream = s
            log.info("System audio stream restarted into \(url.path, privacy: .public)")
        } catch {
            log.error("Failed to restart SCStream: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.reportAsync(error, category: .audio,
                                             context: ["phase": "scstream-restart"])
            counters.setLastError("Failed to restart SCStream: \(error.localizedDescription)")
            onHealthChange?(self)
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio,
              sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              let input = writerInput,
              let writer else { return }

        // Detect writer entering .failed mid-recording.
        if writer.status == .failed {
            let msg = writer.error?.localizedDescription ?? "unknown"
            log.error("Writer entered .failed mid-stream: \(msg, privacy: .public)")
            counters.setLastError("Writer failed mid-stream: \(msg)")
            onHealthChange?(self)
            return
        }

        if !startedSession {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: pts)
            startedSession = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }

        if let pcm = SampleBufferConverter.toPCMBuffer(sampleBuffer) {
            let level = AudioBufferAnalysis.rms(pcm)
            counters.recordSample(level: level, sawSound: level > 0.003)
            chunkWriter?.append(pcm)
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("SCStream didStopWithError: \(error.localizedDescription, privacy: .public)")
        ErrorReporter.shared.reportAsync(error, category: .audio,
                                         context: ["phase": "scstream-did-stop"])
        counters.setLastError("SCStream stopped: \(error.localizedDescription)")
        onHealthChange?(self)
        // Attempt automatic recovery.
        Task { await self.restartStream() }
    }
}
