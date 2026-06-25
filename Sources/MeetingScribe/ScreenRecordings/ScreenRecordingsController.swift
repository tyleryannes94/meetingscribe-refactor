import Foundation
import AVFoundation
import AppKit
import ScreenCaptureKit
import OSLog

/// Owns screen-recording state: live capture, per-recording transcription
/// progress + errors. Mirrors `QuickNotesController` (same `RecordState`
/// shape) but for video. Audio transcription reuses `QuickTranscribe`
/// (`afconvert` extracts the mov's audio track); summarization is Phase 2.
@available(macOS 14.0, *)
@MainActor
final class ScreenRecordingsController: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "ScreenRecordings")

    enum RecordState: Equatable {
        case idle, recording(startedAt: Date), transcribing, error(String)
    }

    @Published private(set) var state: RecordState = .idle
    @Published private(set) var recordings: [ScreenRecording] = []
    @Published private(set) var transcribing: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private let store = ScreenRecordingStore()
    private let transcriber = QuickTranscribe()
    private var recorder: ScreenRecorder?
    private var pending: ScreenRecording?

    func refresh() {
        recordings = store.listRecordings()
    }

    // MARK: - Recording lifecycle

    func startRecording(target: ScreenRecorder.Target, includeMic: Bool) async {
        if case .recording = state { return }
        let now = Date()
        let modeValue: ScreenRecording.Mode = {
            switch target {
            case .fullScreen: return .fullScreen
            case .window: return .window
            case .region: return .region
            }
        }()
        var rec = ScreenRecording(id: UUID().uuidString,
                                  title: "Recording \(Self.shortTime.string(from: now))",
                                  createdAt: now,
                                  durationSeconds: 0,
                                  width: 0, height: 0,
                                  mode: modeValue,
                                  hasMic: includeMic,
                                  micIsSidecar: includeMic,
                                  snippet: "")
        do {
            try store.writeRecording(rec)
            let recorder = ScreenRecorder()
            try await recorder.start(target: target,
                                     outputURL: store.videoURL(for: rec),
                                     micOutputURL: includeMic ? store.micSidecarURL(for: rec) : nil)
            rec.width = recorder.pixelWidth
            rec.height = recorder.pixelHeight
            try? store.writeRecording(rec)
            self.recorder = recorder
            pending = rec
            state = .recording(startedAt: now)
            refresh()
        } catch {
            log.error("startRecording failed: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .audio,
                                        context: ["phase": "screen-record-start"])
            state = .error(error.localizedDescription)
        }
    }

    func stopRecording() async {
        guard case .recording = state, let recorder, var rec = pending else { return }
        let duration = await recorder.stop()
        self.recorder = nil
        pending = nil
        rec.durationSeconds = duration
        state = .transcribing
        try? store.writeRecording(rec)
        await writeThumbnail(for: rec)
        refresh()

        guard recorder.capturedVideo,
              FileManager.default.fileExists(atPath: store.videoURL(for: rec).path) else {
            setError(rec.id, "No video was captured. Check Screen Recording permission.")
            state = .idle
            return
        }
        await transcribe(rec)
        state = .idle
    }

    /// Live mic/system level for the recording UI meter.
    func currentLevel() -> Float { recorder?.currentLevel ?? 0 }

    // MARK: - Transcription

    func reTranscribe(_ rec: ScreenRecording) {
        guard FileManager.default.fileExists(atPath: store.videoURL(for: rec).path) else {
            setError(rec.id, "Recording file not found.")
            return
        }
        setError(rec.id, nil)
        Task { await transcribe(rec) }
    }

    private func transcribe(_ rec: ScreenRecording) async {
        setError(rec.id, nil)
        transcribing.insert(rec.id)
        let audioURL = store.videoURL(for: rec)
        let result: (text: String, error: String?) = await Task.detached(priority: .userInitiated) { [transcriber] in
            do {
                let t = try await transcriber.transcribe(audioURL: audioURL)
                return (t, nil)
            } catch {
                return ("", error.localizedDescription)
            }
        }.value

        var finalized = rec
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        finalized.snippet = String(trimmed.prefix(150))
        try? store.writeRecording(finalized)
        try? store.writeTranscript(result.text, for: finalized)
        transcribing.remove(rec.id)
        refresh()

        if let err = result.error {
            log.error("screen transcribe failed: \(err, privacy: .public)")
            setError(rec.id, "Transcription failed: \(err)")
        } else if trimmed.isEmpty {
            setError(rec.id, "Transcription returned no text — the recording may have had no spoken audio.")
        }
    }

    // MARK: - Thumbnail

    private func writeThumbnail(for rec: ScreenRecording) async {
        let asset = AVURLAsset(url: store.videoURL(for: rec))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        do {
            let cg = try await gen.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image
            ScreenshotCapturer.writePNG(cg, to: store.thumbnailURL(for: rec))
        } catch {
            // Non-fatal — the list just shows a placeholder.
            log.info("thumbnail generation skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reads + edits

    func readTranscript(_ rec: ScreenRecording) -> String { store.readTranscript(for: rec) }
    func readSummary(_ rec: ScreenRecording) -> String { store.readSummary(for: rec) }

    func saveTranscript(_ text: String, for rec: ScreenRecording) {
        try? store.writeTranscript(text, for: rec)
        var updated = rec
        updated.snippet = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150))
        try? store.writeRecording(updated)
        refresh()
    }

    func videoURL(_ rec: ScreenRecording) -> URL { store.videoURL(for: rec) }
    func thumbnailURL(_ rec: ScreenRecording) -> URL { store.thumbnailURL(for: rec) }
    func audioSources(_ rec: ScreenRecording) -> [URL] { store.audioSources(for: rec) }

    func delete(_ rec: ScreenRecording) {
        store.deleteRecording(rec)
        refresh()
    }

    func isTranscribing(_ rec: ScreenRecording) -> Bool { transcribing.contains(rec.id) }
    func error(for rec: ScreenRecording) -> String? { errors[rec.id] }

    private func setError(_ id: String, _ err: String?) {
        if let err { errors[id] = err } else { errors.removeValue(forKey: id) }
    }

    // MARK: - Window enumeration (for the window picker)

    func shareableWindows() async -> [SCWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return [] }
        return content.windows
            .filter { ($0.title?.isEmpty == false) && $0.frame.width > 80 && $0.frame.height > 80 }
            .sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
    }

    private static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d h:mm a"
        return f
    }()
}
