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
    /// IDs currently running the local AI analysis (Phase 2).
    @Published private(set) var analyzing: Set<String> = []
    /// IDs whose analysis pushed one or more tasks into the task store.
    @Published private(set) var recordingsWithTasks: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private let store = ScreenRecordingStore()
    private let transcriber = QuickTranscribe()
    private let ollama = OllamaService()
    private let actionItems: ActionItemStore?
    private var recorder: ScreenRecorder?
    private var pending: ScreenRecording?

    /// `actionItemStore` is injected so analysis can push extracted action items
    /// into Tasks (the same path voice notes use). Optional so the controller
    /// still builds without it (extraction is then skipped).
    init(actionItemStore: ActionItemStore? = nil) {
        self.actionItems = actionItemStore
    }

    /// Coalesces back-to-back tab re-appearances so the synchronous
    /// `listRecordings()` vault scan runs at most once per 30 s on the appear path.
    private var listThrottle = RefreshThrottle(interval: 30)

    /// Forced refresh — used after a capture/edit/delete so the list reflects
    /// the mutation immediately. Re-arms the throttle window.
    func refresh() {
        _ = listThrottle.shouldRun(force: true)
        reload()
    }

    /// onAppear path: re-scan the vault only when the cached snapshot is stale,
    /// so rapid Recordings tab switches don't re-hit disk on the main thread.
    func refreshIfStale() {
        guard listThrottle.shouldRun() else { return }
        reload()
    }

    /// Scans the vault off the main thread and publishes the result in place,
    /// so neither the first load nor a refresh ever blocks the UI. A subtle
    /// refresh hint shows while the scan is in flight.
    private func reload() {
        let store = self.store
        RefreshIndicator.shared.begin()
        Task.detached(priority: .userInitiated) { [weak self] in
            let list = store.listRecordings()
            await MainActor.run {
                self?.recordings = list
                RefreshIndicator.shared.end()
            }
        }
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

    /// Resolves the actual video file (recorded `.mov` or imported `.<ext>`).
    private func existingVideoURL(_ rec: ScreenRecording) -> URL {
        store.existingVideoURL(for: rec) ?? store.videoURL(for: rec)
    }

    // MARK: - Import (local file / web URL)

    /// Imports a local video file, then transcribes it. The user can Analyze it
    /// afterwards like a recorded clip.
    @discardableResult
    func importVideo(from url: URL) async -> String? {
        let now = Date()
        let base = url.deletingPathExtension().lastPathComponent
        var rec = ScreenRecording(id: UUID().uuidString,
                                  title: base.isEmpty ? "Imported \(Self.shortTime.string(from: now))" : base,
                                  createdAt: now, durationSeconds: 0, width: 0, height: 0,
                                  mode: .imported, hasMic: false, micIsSidecar: false, snippet: "")
        state = .transcribing
        do {
            try store.writeRecording(rec)
            let dest = try store.importVideo(from: url, for: rec)
            let asset = AVURLAsset(url: dest)
            rec.durationSeconds = (try? await CMTimeGetSeconds(asset.load(.duration))) ?? 0
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize) {
                rec.width = Int(abs(size.width)); rec.height = Int(abs(size.height))
            }
            try? store.writeRecording(rec)
            await writeThumbnail(for: rec)
            refresh()
            await transcribe(rec)
            state = .idle
            return rec.id
        } catch {
            log.error("importVideo failed: \(error.localizedDescription, privacy: .public)")
            state = .error("Import failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Downloads a video from a web URL (yt-dlp if installed, else a direct media
    /// link) and imports it. User-initiated fetch.
    func importFromURL(_ urlString: String) async {
        state = .transcribing
        do {
            let tmp = try await VideoImporter.fetch(urlString)
            defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }
            _ = await importVideo(from: tmp)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Transcription

    func reTranscribe(_ rec: ScreenRecording) {
        guard store.existingVideoURL(for: rec) != nil else {
            setError(rec.id, "Recording file not found.")
            return
        }
        setError(rec.id, nil)
        Task { await transcribe(rec) }
    }

    private func transcribe(_ rec: ScreenRecording) async {
        setError(rec.id, nil)
        transcribing.insert(rec.id)
        let audioURL = existingVideoURL(rec)
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

    // MARK: - Local AI analysis (Phase 2)

    /// Samples + OCRs the recording, summarizes it via the local LLM (Ollama),
    /// writes `summary.md`, and pushes any extracted action items into Tasks.
    /// Fully on-device — `OllamaService` is EgressPolicy-guarded to 127.0.0.1.
    func analyze(_ rec: ScreenRecording) async {
        guard !analyzing.contains(rec.id) else { return }
        analyzing.insert(rec.id)
        setError(rec.id, nil)
        defer {
            analyzing.remove(rec.id)
            refresh()
        }
        let transcript = store.readTranscript(for: rec)
        let framesDir = store.framesDir(for: rec)
        let frames = await ScreenAnalyzer.ocr(videoURL: existingVideoURL(rec), framesDir: framesDir)
        let onScreen = ScreenAnalyzer.onScreenTextMarkdown(frames)

        // Optional local multimodal pass: "watch" sampled frames with a vision
        // model (qwen2.5vl / llava) for a richer description. Best-effort — if
        // the model can't be pulled or run, we fall back to OCR + transcript.
        var visualDescription = ""
        if AppSettings.shared.useScreenVisionModel {
            let frameURLs = ScreenAnalyzer.frameURLs(in: framesDir)
            visualDescription = (try? await ollama.describeFrames(frameURLs)) ?? ""
        }

        do {
            let summary = try await ollama.analyzeScreenRecording(
                transcript: transcript, onScreenText: onScreen, visualDescription: visualDescription)
            try? store.writeSummary(summary, for: rec)
            await extractTasks(from: summary, rec: rec)
        } catch {
            log.error("screen analysis failed: \(error.localizedDescription, privacy: .public)")
            setError(rec.id, "Analysis failed: \(error.localizedDescription). Is the summary engine running?")
        }
    }

    /// Parses the summary's `## Action Items` section (same parser meetings/voice
    /// notes use) and reconciles the items into the task store as confirmed,
    /// user-owned tasks.
    private func extractTasks(from summary: String, rec: ScreenRecording) async {
        guard let store = actionItems else { return }
        var items = ActionItemExtractor.extract(from: summary, sourceID: rec.id,
                                                sourceTitle: rec.title, sourceDate: rec.createdAt)
        guard !items.isEmpty else { return }
        let myName = AppSettings.shared.userName
        let known = PeopleStore.shared.people
        for i in items.indices {
            items[i].source = "screen_recording"
            if items[i].owner?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                items[i].owner = myName
            }
            if items[i].ownerPersonID == nil {
                items[i].ownerPersonID = PersonResolver.resolveOwner(items[i].owner, in: known)
            }
            items[i].confirmedAt = Date()
            items[i].delegated = nil
        }
        store.reconcileExtracted(items, for: rec.id)
        recordingsWithTasks.insert(rec.id)
    }

    func isAnalyzing(_ rec: ScreenRecording) -> Bool { analyzing.contains(rec.id) }
    func hasSummary(_ rec: ScreenRecording) -> Bool {
        !store.readSummary(for: rec).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Thumbnail

    private func writeThumbnail(for rec: ScreenRecording) async {
        let asset = AVURLAsset(url: existingVideoURL(rec))
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

    func videoURL(_ rec: ScreenRecording) -> URL { existingVideoURL(rec) }
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
