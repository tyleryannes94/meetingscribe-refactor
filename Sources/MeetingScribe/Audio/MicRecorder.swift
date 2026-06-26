import Foundation
import AVFoundation
import OSLog

/// Captures the default microphone via AVAudioEngine.
///
/// Architecture (refactored in Batch 4):
///   - The audio tap deep-copies each buffer and dispatches the write to a
///     dedicated serial queue — `AVAudioFile.write(from:)` no longer runs
///     on the real-time audio render thread. Previously a slow disk write
///     or Time Machine snapshot could glitch the recording (audit 3.1).
///   - All cross-thread mutable state (sample counters, RMS level, error
///     string) lives in a lock-protected `AudioCounters` value
///     (`os.OSAllocatedUnfairLock`). Plain-var primitives mutated from
///     multiple threads were UB under Swift's concurrency model and would
///     trip Swift 6 strict-concurrency checks (audit 5.2).
///   - Configuration-change recovery (input device swap, sample-rate flip)
///     still listens for `.AVAudioEngineConfigurationChange` and restarts
///     the engine into the same output file.
final class MicRecorder {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Mic")

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private(set) var outputURL: URL?
    private weak var chunkWriter: ChunkedAudioWriter?
    private var configObserver: NSObjectProtocol?

    /// Dedicated serial queue for disk writes — keeps AVAudioFile.write off
    /// the real-time audio render thread.
    private let writeQueue = DispatchQueue(label: "MeetingScribe.Mic.write",
                                           qos: .userInitiated)

    /// Lock-protected health snapshot. Reads from the main thread take an
    /// unfair-lock snapshot rather than racing on bare vars.
    let counters = AudioCounters()
    var onHealthChange: ((MicRecorder) -> Void)?

    // Mirror the old public API surface so existing call sites keep working.
    var samplesAppended: Int { counters.snapshot().samplesAppended }
    var lastSampleAt: Date? { counters.snapshot().lastSampleAt }
    var lastSoundAt: Date? { counters.snapshot().lastSoundAt }
    var currentLevel: Float { counters.snapshot().currentLevel }
    var restartCount: Int { counters.snapshot().restartCount }
    var lastError: String? { counters.snapshot().lastError }

    func start(outputURL: URL, chunkWriter: ChunkedAudioWriter?) throws {
        self.outputURL = outputURL
        self.chunkWriter = chunkWriter
        try? FileManager.default.removeItem(at: outputURL)

        try startEngine(outputURL: outputURL)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.log.info("AVAudioEngineConfigurationChange — restarting mic capture")
            self.counters.incrementRestart(reason: "Audio device changed; restarted capture.")
            self.onHealthChange?(self)
            // Tear the old engine down fully (drop its tap too) and retry after
            // the route settles — reading the format the instant a config-change
            // fires often yields a transient 0-Hz format. The guard in
            // `startEngine` makes a too-early read recoverable; the delay lets it
            // actually succeed instead of just not-crashing.
            self.restartAfterSettle(outputURL: outputURL, phase: "mic-restart-config-change")
        }
    }

    /// Fully tear down the current engine and restart into the same file after a
    /// short settle delay. Used by the config-change observer and the stall
    /// watchdog. Runs on the main thread (both callers do).
    private func restartAfterSettle(outputURL: URL, phase: String) {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            do {
                try self.startEngine(outputURL: outputURL, reopenFile: false)
            } catch {
                self.log.error("Mic restart failed (\(phase, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                ErrorReporter.shared.reportAsync(error, category: .audio, context: ["phase": phase])
                self.counters.setLastError("Mic restart failed: \(error.localizedDescription)")
                self.onHealthChange?(self)
            }
        }
    }

    private func startEngine(outputURL: URL, reopenFile: Bool = true) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Prefer AirPods / Bluetooth as the recording input when one is connected,
        // and never silently fall back to the built-in mic while it is. Pinning
        // the engine's device (not the system default) keeps it scoped to us.
        Self.applyPreferredInput(to: input, log: log)
        let inputFormat = input.outputFormat(forBus: 0)

        // CRITICAL: `installTap` asserts (throws an Objective-C NSException, which
        // Swift `do/catch` CANNOT catch → SIGABRT) on a 0-channel / 0-Hz format.
        // A Bluetooth/AirPods route change posts `.AVAudioEngineConfigurationChange`
        // and, for a brief window, `outputFormat(forBus:)` returns a transient
        // invalid format. The `makeMicFile` guard below only runs on the
        // file-reopen path, so the restart callers (config-change + stall
        // watchdog, both `reopenFile: false`) used to skip it and crash. Validate
        // here on EVERY path and throw a *catchable* Swift error so those callers
        // can tear down and retry instead of aborting the whole app.
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw NSError(domain: "MeetingScribe.Mic", code: 12, userInfo: [
                NSLocalizedDescriptionKey:
                    "Mic input not ready (\(inputFormat.channelCount)ch @ \(Int(inputFormat.sampleRate))Hz) — device still settling."
            ])
        }

        if reopenFile || file == nil {
            file = try Self.makeMicFile(outputURL: outputURL,
                                        inputFormat: inputFormat,
                                        log: log,
                                        counters: counters)
        }

        // Idempotent: remove any prior tap before installing so a reused input
        // node can never hit "a tap is already installed on bus 0".
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Cheap work that has to run on the audio thread:
            //   1. RMS for the level meter
            //   2. Pass the source buffer into the chunked transcribe writer
            //      (it deep-copies internally before queueing).
            let level = AudioBufferAnalysis.rms(buffer)
            self.counters.recordSample(level: level, sawSound: level > 0.003)
            self.chunkWriter?.append(buffer)

            // Disk I/O moves OFF the audio thread. Deep-copy the buffer so
            // we own the bytes regardless of when AVAudioEngine reuses the
            // source buffer.
            guard let copy = MicRecorder.copy(buffer: buffer) else { return }
            self.writeQueue.async { [weak self] in
                guard let self, let file = self.file else { return }
                do { try file.write(from: copy) }
                catch {
                    self.log.error("Mic m4a write failed: \(error.localizedDescription, privacy: .public)")
                    self.counters.setLastError("Mic write failed: \(error.localizedDescription)")
                    self.onHealthChange?(self)
                }
            }
        }

        try engine.start()
        self.engine = engine
        log.info("Mic capture started: \(outputURL.path, privacy: .public)")
    }

    /// Pins the engine's input to the preferred Bluetooth/AirPods device when
    /// the "prefer Bluetooth mic" setting is on and one is connected. No-ops
    /// (leaving the system default) when the setting is off or no Bluetooth input
    /// exists. Must be called before reading the input format / starting.
    private static func applyPreferredInput(to input: AVAudioInputNode, log: Logger) {
        guard AppSettings.shared.preferBluetoothMic else { return }
        guard let dev = AudioInputDevices.preferredBluetoothInput() else {
            let def = AudioInputDevices.defaultInput()
            if def?.isBuiltIn == true {
                log.notice("Prefer-Bluetooth is on but no AirPods/Bluetooth mic is connected — recording with the built-in mic (\(def?.name ?? "?", privacy: .public)).")
            }
            return
        }
        do {
            try input.auAudioUnit.setDeviceID(dev.id)
            log.info("Pinned mic input to \(dev.name, privacy: .public) (Bluetooth)")
        } catch {
            log.error("Could not pin mic to \(dev.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Open the per-segment mic file for writing.
    ///
    /// The AAC encoder's `AVEncoderBitRateKey` property fails on some input
    /// devices/formats with CoreAudio `kAudioConverterEncodeBitRate`
    /// (error 560226676). AVFoundation has already created the container by
    /// then, so the throw leaves a headerless, untranscribable `.m4a`
    /// (observed 2026-06-11: a 557-byte mic segment that afconvert later
    /// rejected with "Couldn't open input file ('dta?')", yielding a silent
    /// empty transcript). Two-step hardening:
    ///   1. Reject a null input format up front — a 0-channel / 0-Hz device
    ///      can never produce valid AAC, so fail loudly instead of writing a
    ///      doomed stub.
    ///   2. If the bitrate'd open throws, scrub the partial file and retry
    ///      letting AAC pick its own bitrate. Only a second failure
    ///      propagates, and never with a corrupt file left behind.
    private static func makeMicFile(outputURL: URL,
                                    inputFormat: AVAudioFormat,
                                    log: Logger,
                                    counters: AudioCounters) throws -> AVAudioFile {
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw NSError(domain: "MeetingScribe.Mic", code: 11, userInfo: [
                NSLocalizedDescriptionKey:
                    "Microphone input is unavailable (\(inputFormat.channelCount)ch @ \(Int(inputFormat.sampleRate))Hz). Check the input device and mic permission."
            ])
        }

        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderBitRateKey: 32_000
        ]
        do {
            return try AVAudioFile(forWriting: outputURL, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            log.error("Mic AAC file at 32kbps failed (\(error.localizedDescription, privacy: .public)); retrying at codec-default bitrate")
            try? FileManager.default.removeItem(at: outputURL)
            settings.removeValue(forKey: AVEncoderBitRateKey)
            do {
                let file = try AVAudioFile(forWriting: outputURL, settings: settings,
                                           commonFormat: .pcmFormatFloat32, interleaved: false)
                counters.setLastError("Mic encoder rejected the target bitrate; recording at the codec default for this segment.")
                return file
            } catch {
                // Encoder unavailable entirely — don't leave a headerless stub.
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        }
    }

    /// Called from AudioRecorder's watchdog.
    func checkHealth(staleAfter: TimeInterval = 8) {
        guard let engine, engine.isRunning,
              let lastSampleAt = counters.snapshot().lastSampleAt else { return }
        let age = Date().timeIntervalSince(lastSampleAt)
        guard age > staleAfter else { return }
        log.error("Mic stalled — no samples for \(age, format: .fixed(precision: 1))s. Restarting engine.")
        counters.incrementRestart(reason: "Mic stalled for \(Int(age))s; restarting.")
        onHealthChange?(self)
        guard let url = outputURL else { return }
        restartAfterSettle(outputURL: url, phase: "mic-stall-recovery")
    }

    func stop() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        // Drain the write queue so all in-flight buffers land before we
        // drop the file handle. AVAudioFile finalizes the container on
        // deinit, so doing this in order matters.
        writeQueue.sync {}
        file = nil
        let snap = counters.snapshot()
        log.info("Mic capture stopped. samples=\(snap.samplesAppended) restarts=\(snap.restartCount)")
    }

    /// Deep-copy an AVAudioPCMBuffer so the source can be safely reused by
    /// the audio engine while we hold a private copy for the write queue.
    private static func copy(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                          frameCapacity: buffer.frameCapacity) else { return nil }
        dst.frameLength = buffer.frameLength
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if let srcFloat = buffer.floatChannelData, let dstFloat = dst.floatChannelData {
            for ch in 0..<channelCount {
                memcpy(dstFloat[ch], srcFloat[ch], frameCount * MemoryLayout<Float>.size)
            }
            return dst
        }
        if let srcInt16 = buffer.int16ChannelData, let dstInt16 = dst.int16ChannelData {
            for ch in 0..<channelCount {
                memcpy(dstInt16[ch], srcInt16[ch], frameCount * MemoryLayout<Int16>.size)
            }
            return dst
        }
        if let srcInt32 = buffer.int32ChannelData, let dstInt32 = dst.int32ChannelData {
            for ch in 0..<channelCount {
                memcpy(dstInt32[ch], srcInt32[ch], frameCount * MemoryLayout<Int32>.size)
            }
            return dst
        }
        // Last-resort: AudioBufferList copy (handles interleaved data).
        let srcABL = buffer.audioBufferList.pointee
        let dstABL = dst.mutableAudioBufferList.pointee
        if dstABL.mNumberBuffers == srcABL.mNumberBuffers {
            for i in 0..<Int(srcABL.mNumberBuffers) {
                let s = withUnsafePointer(to: srcABL.mBuffers) { $0.advanced(by: i).pointee }
                let d = withUnsafePointer(to: dstABL.mBuffers) { $0.advanced(by: i).pointee }
                if let sData = s.mData, let dData = d.mData {
                    memcpy(dData, sData, Int(s.mDataByteSize))
                }
            }
            return dst
        }
        return nil
    }
}
