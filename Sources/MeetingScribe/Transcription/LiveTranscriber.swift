import Foundation
import OSLog

/// Consumes finished WAV chunks from the chunked writers (one chunk every
/// 5 minutes per source) and runs whisper-cli on each, in order, on per-
/// source background queues. Each chunk's text is appended to a Published
/// transcript so SwiftUI views update live.
///
/// Architecture (refactored in Batch 5):
///   - **Parallel queues per source** — mic and system audio chunks are
///     processed on independent queues. Previously they shared one
///     `workQueue`, so a slow mic chunk would block a ready system
///     chunk (audit 4.1).
///   - **Bounded backpressure** — `pendingCount` is capped at
///     `maxPending`. Chunks beyond the cap are dropped from the LIVE
///     stream with a warning surfaced via `lastError`; the final pass
///     after stop still picks them up from the merged audio (audit 4.4).
///     This prevents OOM on long meetings where transcription falls
///     behind capture.
///   - **Centralized invocation** — uses `WhisperRunner` instead of
///     re-implementing process/argv/parse plumbing (audit 4.3).
@MainActor
final class LiveTranscriber: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "LiveTranscriber")

    struct LiveSegment: Identifiable {
        let id = UUID()
        let speaker: String      // "Me" / "Them"
        let startSec: Double
        let endSec: Double
        let text: String
    }

    @Published private(set) var segments: [LiveSegment] = []
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var lastError: String?
    /// How many chunks have been dropped because the pipeline fell
    /// behind. Surfaced in the UI so the user can react (e.g. switch to
    /// a smaller whisper model) — the final transcript still includes
    /// them because batch transcription re-runs against the merged audio.
    @Published private(set) var droppedChunkCount: Int = 0

    /// Cap on `pendingCount`. Roughly two failed-keep-up cycles before we
    /// start shedding load. 16 chunks ≈ 80 minutes of buffered audio per
    /// source if every chunk is 5 minutes — well past the point a user
    /// would notice the live pane was stale.
    private let maxPending = 16

    /// Optional hook fired on the main actor after each chunk's text is folded
    /// into `segments`. The owner uses it to persist the partial transcript to
    /// disk as the meeting runs, so a long recording is visibly transcribed
    /// every ~5 minutes instead of only at stop.
    var onTranscriptUpdated: (() -> Void)?

    // Per-source serialization is now achieved by chaining Task.detached
    // calls via `lastMicTask` / `lastSystemTask` (see `enqueueChunk` + `chain`).
    // The two sources run in parallel; within a source, chunks are ordered.

    /// Queue a chunk for transcription. Safe to call from any thread — used by
    /// the in-process `AudioRecorder` callbacks, which fire on the capture queue.
    nonisolated func submitChunk(url: URL, speaker: String, startSec: Double, endSec: Double) {
        // Hop to the main actor, where all the pending-counter / task-chain
        // state lives, then enqueue.
        Task { @MainActor in
            self.enqueueChunk(url: url, speaker: speaker, startSec: startSec, endSec: endSec)
        }
    }

    /// Main-actor entry point for callers already on the main actor — namely the
    /// `ChunkStreamBridge` that feeds chunks written by the out-of-process
    /// ScribeCore daemon. Enqueuing synchronously (no `Task` hop) guarantees the
    /// submission is reflected in `pendingCount` before a caller awaits
    /// `flush()`, so the final-sweep tail chunk can't be lost.
    func enqueueChunk(url: URL, speaker: String, startSec: Double, endSec: Double) {
        // Backpressure: if we're already behind, drop this chunk. The batch pass
        // after stop will recover its content from the merged audio, so we don't
        // lose anything user-facing — only the live preview misses a window.
        if self.pendingCount >= self.maxPending {
            self.droppedChunkCount += 1
            self.lastError = "Live transcription falling behind by \(self.pendingCount) chunks. Dropped \(self.droppedChunkCount) live previews; full transcript will be generated at stop."
            AppLog.warn("LiveTranscriber", "Dropped chunk (backpressure)",
                        ["pending": "\(self.pendingCount)",
                         "speaker": speaker,
                         "audio": url.path])
            try? FileManager.default.removeItem(at: url)
            return
        }
        self.pendingCount += 1
        self.isProcessing = true

        // Per-source serialization: chain the new chunk onto whatever task is
        // already running for this source. Cross-source chunks run in parallel.
        let priority: TaskPriority = .userInitiated
        if speaker == "Me" {
            self.lastMicTask = Self.chain(after: self.lastMicTask, priority: priority) { [weak self] in
                await self?.processChunk(url: url, speaker: speaker,
                                         startSec: startSec, endSec: endSec)
            }
        } else {
            self.lastSystemTask = Self.chain(after: self.lastSystemTask, priority: priority) { [weak self] in
                await self?.processChunk(url: url, speaker: speaker,
                                         startSec: startSec, endSec: endSec)
            }
        }
    }

    /// Per-source serialization. Each new chunk's task awaits the previous
    /// chunk's task on the SAME source so within-source ordering is preserved;
    /// the two sources still run in parallel.
    private var lastMicTask: Task<Void, Never>?
    private var lastSystemTask: Task<Void, Never>?

    private static func chain(after prior: Task<Void, Never>?,
                              priority: TaskPriority,
                              _ body: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task.detached(priority: priority) {
            await prior?.value
            await body()
        }
    }

    nonisolated private func processChunk(url: URL, speaker: String,
                                          startSec: Double, endSec: Double) async {
        defer {
            try? FileManager.default.removeItem(at: url)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingCount = max(0, self.pendingCount - 1)
                if self.pendingCount == 0 { self.isProcessing = false }
            }
        }

        let runner = WhisperRunner(workDir: url.deletingLastPathComponent())
        do {
            let result = try await runner.run(audio: url, output: .plainText)
            guard case let .text(text) = result, !text.isEmpty else { return }
            let seg = LiveSegment(speaker: speaker, startSec: startSec, endSec: endSec, text: text)
            await MainActor.run {
                self.segments.append(seg)
                self.segments.sort { $0.startSec < $1.startSec }
                self.lastError = nil
                self.onTranscriptUpdated?()
            }
        } catch let e as WhisperRunner.RunnerError {
            let msg = Self.summarizeRunnerError(e)
            log.error("\(msg, privacy: .public)")
            await MainActor.run {
                ErrorReporter.shared.report(e, category: .transcription,
                                            context: ["speaker": speaker, "audio": url.path])
                self.lastError = msg
            }
        } catch {
            log.error("Unexpected transcription error: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                ErrorReporter.shared.report(error, category: .transcription,
                                            context: ["speaker": speaker, "audio": url.path])
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Awaits all in-flight per-source transcription so the final chunk(s)
    /// flushed by `AudioRecorder.stop()` are included before `renderMarkdown()`.
    /// Without this, the last 0–5 minutes of a meeting (the chunk still running
    /// whisper at stop time) were silently dropped from the persisted transcript,
    /// and every downstream summary / action-item extraction inherited the gap.
    /// Safe to call when idle — with no pending work it returns immediately.
    func flush() async {
        // Chunks finalized during AudioRecorder.stop() reach us via submitChunk,
        // whose MainActor hop assigns the tail task. Yield once so those hops run
        // before we snapshot the chains.
        await Task.yield()
        // Drain until nothing is in flight. processChunk's `defer` always
        // decrements pendingCount (even on error), so this terminates; the
        // safety cap is belt-and-suspenders against an unexpected stuck counter.
        var safety = 0
        while pendingCount > 0, safety < 10_000 {
            await lastMicTask?.value
            await lastSystemTask?.value
            await Task.yield()
            safety += 1
        }
        // Final await in case a tail task is completing as pendingCount hits 0.
        await lastMicTask?.value
        await lastSystemTask?.value
    }

    /// Render the current segments as a single Markdown transcript with speaker labels.
    func renderMarkdown() -> String {
        var out = "# Transcript\n\n"
        var currentSpeaker = ""
        for seg in segments {
            if seg.text.isEmpty { continue }
            if seg.speaker != currentSpeaker {
                if !out.hasSuffix("\n\n") { out += "\n\n" }
                out += "**\(seg.speaker)** [\(Self.format(seg.startSec))]: "
                currentSpeaker = seg.speaker
            } else {
                out += " "
            }
            out += seg.text
        }
        return out + "\n"
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let r = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, r) }
        return String(format: "%d:%02d", m, r)
    }

    /// End-of-segment time across all completed chunks. Anything between
    /// this and "now" is audio waiting for the next chunk to close.
    var lastTranscribedSecond: Double {
        segments.map(\.endSec).max() ?? 0
    }

    /// Picks the most actionable line out of whisper's stderr / error message.
    /// Pulled out so a single human-friendly summary lives in one place.
    nonisolated static func summarizeWhisperError(exitCode: Int32, stderr: String) -> String {
        let lines = stderr.split(separator: "\n").map(String.init)
        let prioritized = lines.filter { line in
            let l = line.lowercased()
            return l.contains("bad magic")
                || l.contains("invalid model")
                || l.contains("failed to load model")
                || l.contains("failed to initialize whisper context")
                || l.contains("error:")
        }
        let chosen = prioritized.first ?? lines.last(where: { !$0.isEmpty }) ?? ""
        if chosen.lowercased().contains("bad magic") || chosen.lowercased().contains("invalid model") {
            return "whisper-cli failed (\(exitCode)): model file is corrupted or empty. Re-download it via ./scripts/setup.sh"
        }
        if chosen.lowercased().contains("failed to initialize whisper context") {
            return "whisper-cli failed (\(exitCode)): could not initialize whisper context. The model file may be corrupted, or whisper-cpp may be incompatible with the model. Try ./scripts/build-whisper-cpu.sh for a CPU-only fallback."
        }
        return "whisper-cli failed (\(exitCode)): \(chosen.isEmpty ? String(stderr.prefix(400)) : chosen)"
    }

    nonisolated private static func summarizeRunnerError(_ e: WhisperRunner.RunnerError) -> String {
        switch e {
        case .subprocess(let code, let stderr):
            return summarizeWhisperError(exitCode: code, stderr: stderr)
        default:
            return e.errorDescription ?? String(describing: e)
        }
    }

    func reset() {
        segments = []
        pendingCount = 0
        isProcessing = false
        lastError = nil
        droppedChunkCount = 0
    }
}
