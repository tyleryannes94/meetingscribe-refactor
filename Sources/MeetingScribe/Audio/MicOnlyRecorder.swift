import Foundation
import AVFoundation
import OSLog

/// Minimal mic-only recorder used by Note Transcriber and Whispr-Flow-style
/// dictation. Writes a single .m4a file via AVAudioRecorder (simpler than the
/// AVAudioEngine path used for meeting recording).
final class MicOnlyRecorder {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "MicOnly")
    private var recorder: AVAudioRecorder?
    private(set) var outputURL: URL?
    private(set) var startTime: Date?

    /// Called on the main queue approximately every 0.08 s while recording,
    /// with the latest normalized level (0...1). Set before calling `start`.
    var onLevel: ((Float) -> Void)?

    /// Background timer that polls `AVAudioRecorder` metering and fires `onLevel`.
    private var levelTimer: DispatchSourceTimer?

    func start(outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let r = try AVAudioRecorder(url: outputURL, settings: settings)
        r.isMeteringEnabled = true
        guard r.record() else {
            throw NSError(domain: "MeetingScribe", code: 20,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone recorder failed to start. Microphone permission may be denied."])
        }
        recorder = r
        self.outputURL = outputURL
        startTime = Date()
        log.info("MicOnlyRecorder started → \(outputURL.path, privacy: .public)")
        startLevelTimer()
    }

    @discardableResult
    func stop() -> (url: URL?, duration: Double) {
        stopLevelTimer()
        let url = outputURL
        let dur = startTime.map { Date().timeIntervalSince($0) } ?? 0
        recorder?.stop()
        recorder = nil
        outputURL = nil
        startTime = nil
        log.info("MicOnlyRecorder stopped, duration=\(dur)s")
        return (url, dur)
    }

    // MARK: - Internal level polling

    private func startLevelTimer() {
        guard onLevel != nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now(), repeating: .milliseconds(80), leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in
            guard let self, let recorder = self.recorder, recorder.isRecording else { return }
            recorder.updateMeters()
            let db = recorder.averagePower(forChannel: 0)
            let level: Float = db > -60 ? pow(10, db / 20) : 0
            let cb = self.onLevel
            DispatchQueue.main.async { cb?(level) }
        }
        t.resume()
        levelTimer = t
    }

    private func stopLevelTimer() {
        levelTimer?.cancel()
        levelTimer = nil
    }

    var isRecording: Bool { recorder?.isRecording ?? false }

    /// Approx peak amplitude (-160 dB silent → 0 dB clipping). Caller must
    /// call updateMeters before reading.
    func currentLevel() -> Float {
        recorder?.updateMeters()
        return recorder?.averagePower(forChannel: 0) ?? -160
    }

    /// 0...1 normalized level (perceptual scale based on -60 dB silence
    /// floor). Drives the live audio-bars indicator.
    func normalizedLevel() -> Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        guard db > -60 else { return 0 }
        return pow(10, db / 20)
    }
}
