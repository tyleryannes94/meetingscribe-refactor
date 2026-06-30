import Foundation
import OSLog

/// Streams on-disk audio chunks into the `LiveTranscriber` so a recording is
/// transcribed every ~5 minutes *while it is still running*, instead of in one
/// long batch pass at stop.
///
/// Why this exists: the primary recording path is the out-of-process
/// **ScribeCore** daemon. It captures audio into rolling 5-minute WAV chunks
/// (`<meetingDir>/chunks/<label>-NNNN.wav`) but does no transcription, and the
/// only cross-process signal back to the app is a lifecycle Darwin notification
/// — there is no "chunk ready" event. Without a bridge the in-process
/// `LiveTranscriber` sits idle for the whole meeting, the live transcript is
/// empty at stop, and the pipeline falls back to a full-file whisper pass (the
/// 30-minute "why is it still processing" wait this fixes).
///
/// The bridge polls the chunks directory on the main actor and feeds each
/// *closed* chunk to whisper as soon as it rotates. It works regardless of which
/// process wrote the chunk, so it needs no changes to the daemon.
///
/// Completeness rule: the chunked writer keeps the highest-numbered chunk open
/// (still being written); chunk N is finalized only once chunk N+1 exists. So we
/// submit every chunk except the current max — until the final sweep at stop,
/// when the writer has closed the trailing partial chunk and all are safe.
@MainActor
final class ChunkStreamBridge {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "ChunkStreamBridge")

    private let chunksDir: URL
    private weak var transcriber: LiveTranscriber?
    /// Chunk file paths already handed to the transcriber, so a chunk is never
    /// submitted twice even though the transcriber deletes it after running.
    private var submitted: Set<String> = []
    private var timer: DispatchSourceTimer?

    /// Matches `ChunkedAudioWriter(chunkSeconds: 300)`. Used only to label the
    /// approximate time window of each chunk for the live transcript header.
    private let chunkSeconds: Double = 300

    init(chunksDir: URL, transcriber: LiveTranscriber) {
        self.chunksDir = chunksDir
        self.transcriber = transcriber
    }

    /// Begin polling. Chunks rotate every 5 minutes, so a coarse 5-second poll
    /// adds negligible latency and is far more robust than FSEvents on a
    /// directory another process is actively writing to.
    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in self?.scan(final: false) }
        t.resume()
        timer = t
    }

    /// Stop polling and do a final sweep, submitting any remaining chunks —
    /// including the trailing partial chunk, which the writer has now closed at
    /// recording stop. Runs synchronously on the main actor so the submissions
    /// are reflected in `LiveTranscriber.pendingCount` before the caller awaits
    /// `flush()`; otherwise the tail chunk could be lost from the transcript.
    func stop() {
        timer?.cancel()
        timer = nil
        scan(final: true)
    }

    private func scan(final: Bool) {
        guard let transcriber else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: chunksDir, includingPropertiesForKeys: nil) else { return }

        // Group chunks by source label (everything before the final "-NNNN").
        // Labels look like "mic-seg1" / "system-seg1"; the segment suffix keeps
        // resumed-recording segments in distinct streams.
        var bySource: [String: [(idx: Int, url: URL)]] = [:]
        for url in files where url.pathExtension == "wav" {
            let name = url.deletingPathExtension().lastPathComponent  // e.g. mic-seg1-0003
            guard let dash = name.lastIndex(of: "-"),
                  let idx = Int(name[name.index(after: dash)...]) else { continue }
            let label = String(name[..<dash])
            bySource[label, default: []].append((idx, url))
        }

        for (label, chunks) in bySource {
            let sorted = chunks.sorted { $0.idx < $1.idx }
            let maxIdx = sorted.last?.idx ?? -1
            let speaker = label.hasPrefix("system") ? "Them" : "Me"
            for c in sorted {
                // Skip the currently-open (highest) chunk until the final sweep.
                if !final && c.idx == maxIdx { continue }
                if submitted.contains(c.url.path) { continue }
                submitted.insert(c.url.path)
                let start = Double(c.idx) * chunkSeconds
                transcriber.enqueueChunk(url: c.url, speaker: speaker,
                                         startSec: start, endSec: start + chunkSeconds)
            }
        }
    }
}
