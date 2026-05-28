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
            self.engine?.stop()
            do {
                try self.startEngine(outputURL: outputURL, reopenFile: false)
            } catch {
                self.log.error("Mic restart after config change failed: \(error.localizedDescription, privacy: .public)")
                ErrorReporter.shared.reportAsync(error, category: .audio,
                                                 context: ["phase": "mic-restart-config-change"])
                self.counters.setLastError("Mic restart failed: \(error.localizedDescription)")
                self.onHealthChange?(self)
            }
        }
    }

    private func startEngine(outputURL: URL, reopenFile: Bool = true) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        if reopenFile || file == nil {
            let fileSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVEncoderBitRateKey: 32_000
            ]
            file = try AVAudioFile(forWriting: outputURL,
                                   settings: fileSettings,
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        }

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
        engine.stop()
        do {
            try startEngine(outputURL: url, reopenFile: false)
        } catch {
            log.error("Mic stall recovery failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.reportAsync(error, category: .audio,
                                             context: ["phase": "mic-stall-recovery"])
            counters.setLastError("Mic stall recovery failed: \(error.localizedDescription)")
            onHealthChange?(self)
        }
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
