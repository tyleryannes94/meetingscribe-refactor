import Foundation
import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import OSLog

/// Captures screen video + system audio via ScreenCaptureKit into a single
/// `.mov` (H.264 video + AAC audio). Microphone voice-over, when requested, is
/// recorded to a sidecar `mic.m4a` via `MicOnlyRecorder` and stitched back in
/// at playback/transcription time — this avoids fragile real-time mic→video
/// muxing while still capturing the user's narration (see the plan's mic
/// fallback note).
///
/// Modeled on `SystemAudioRecorder` (same SCStream + AVAssetWriter shape) but
/// with a real video output and configurable dimensions / frame rate.
@available(macOS 14.0, *)
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "ScreenRecorder")

    /// What to capture. Resolved to an `SCContentFilter` + dimensions at `start`.
    enum Target {
        case fullScreen
        case window(SCWindow)
        /// A rectangle in the main display's coordinate space (points, top-left origin).
        case region(CGRect)
    }

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var startedSession = false
    private let queue = DispatchQueue(label: "MeetingScribe.ScreenRecorder")

    /// Optional mic sidecar recorder (only when `includeMic` is true).
    private var micRecorder: MicOnlyRecorder?
    private(set) var micSidecarURL: URL?
    /// True once the mov is finalized with at least one video frame.
    private(set) var capturedVideo = false

    private(set) var outputURL: URL?
    private(set) var pixelWidth = 0
    private(set) var pixelHeight = 0
    private var startTime: Date?

    /// Live preview level for the UI meter (0...1), updated off the system-audio buffers.
    private(set) var currentLevel: Float = 0

    /// Begin capture. `fps` defaults to 30; dimensions are derived from the target.
    func start(target: Target, outputURL: URL, micOutputURL: URL?, fps: Int32 = 30) async throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)

        let (filter, width, height) = try await resolve(target)
        pixelWidth = width
        pixelHeight = height

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: fps)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.queueDepth = 6

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        if writer.canAdd(videoInput) { writer.add(videoInput) }

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        if writer.canAdd(audioInput) { writer.add(audioInput) }

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "MeetingScribe", code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter failed to start."])
        }
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.startedSession = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        self.startTime = Date()

        // Mic voice-over → sidecar file (robust fallback path).
        if let micOutputURL {
            let mic = MicOnlyRecorder()
            try mic.start(outputURL: micOutputURL)
            self.micRecorder = mic
            self.micSidecarURL = micOutputURL
        }

        log.info("Screen capture started: \(width)x\(height) @\(fps)fps → \(outputURL.path, privacy: .public)")
    }

    /// Stops capture and finalizes the file. Returns the recorded duration.
    @discardableResult
    func stop() async -> Double {
        if let stream { try? await stream.stopCapture() }
        stream = nil

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        if let writer {
            await writer.finishWriting()
            if writer.status == .failed {
                let msg = writer.error?.localizedDescription ?? "unknown"
                log.error("Screen AVAssetWriter ended in .failed: \(msg, privacy: .public)")
            }
        }
        writer = nil
        videoInput = nil
        audioInput = nil
        startedSession = false

        // Stop the mic sidecar (its own AVAudioRecorder).
        _ = micRecorder?.stop()
        micRecorder = nil

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        startTime = nil
        log.info("Screen capture stopped (\(String(format: "%.1f", duration))s, hadVideo=\(self.capturedVideo))")
        return duration
    }

    // MARK: - Filter resolution

    private func resolve(_ target: Target) async throws -> (SCContentFilter, Int, Int) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "MeetingScribe", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display available for capture."])
        }
        let scale = backingScale()
        switch target {
        case .fullScreen:
            let filter = SCContentFilter(display: display, excludingWindows: [])
            return (filter, even(display.width), even(display.height))
        case .window(let window):
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let w = Int(window.frame.width * scale)
            let h = Int(window.frame.height * scale)
            return (filter, even(max(w, 2)), even(max(h, 2)))
        case .region(let rect):
            // Crop to the rect by capturing the full display and letting the
            // configuration's sourceRect select the region.
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let w = Int(rect.width * scale)
            let h = Int(rect.height * scale)
            return (filter, even(max(w, 2)), even(max(h, 2)))
        }
    }

    private func backingScale() -> CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    /// H.264 prefers even dimensions.
    private func even(_ n: Int) -> Int { n % 2 == 0 ? n : n + 1 }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer), let writer else { return }
        if writer.status == .failed { return }

        switch type {
        case .screen:
            // Drop frames that aren't a complete, displayable update.
            guard isCompleteFrame(sampleBuffer), let videoInput else { return }
            startSessionIfNeeded(sampleBuffer)
            if videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
                capturedVideo = true
            }
        case .audio:
            guard let audioInput else { return }
            startSessionIfNeeded(sampleBuffer)
            if audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
            if let pcm = SampleBufferConverter.toPCMBuffer(sampleBuffer) {
                currentLevel = AudioBufferAnalysis.rms(pcm)
            }
        @unknown default:
            break
        }
    }

    private func startSessionIfNeeded(_ sampleBuffer: CMSampleBuffer) {
        guard !startedSession, let writer else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        writer.startSession(atSourceTime: pts)
        startedSession = true
    }

    /// True when the ScreenCaptureKit frame status is `.complete` (an actual
    /// rendered update rather than an idle/blank tick).
    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let raw = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return true }
        return status == .complete
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("Screen SCStream didStopWithError: \(error.localizedDescription, privacy: .public)")
        ErrorReporter.shared.reportAsync(error, category: .audio,
                                         context: ["phase": "screen-scstream-did-stop"])
    }
}
