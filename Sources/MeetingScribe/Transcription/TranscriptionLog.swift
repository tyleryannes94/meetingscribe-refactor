import Foundation
import OSLog

/// Disk-backed diagnostic log for every whisper invocation. Lives at
/// `<storageDir>/logs/transcription.log`. Each run appends a single
/// timestamped block with the full command, exit code, output length,
/// the head + tail of stderr, and the elapsed wall time.
///
/// Goal: when transcription fails in the field, the user can open the
/// log file (or send it) and we can see exactly what happened — which
/// flags ran, what whisper printed, which fall-through paths fired.
///
/// File is rotated when it exceeds `maxBytes` (default 2 MB) — we truncate
/// to the last half so old entries get evicted but recent context stays.
enum TranscriptionLog {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "TranscriptionLog")
    private static let queue = DispatchQueue(label: "transcription.log",
                                              qos: .utility)
    private static let maxBytes: Int = 2 * 1024 * 1024 // 2 MB
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Path the log is written to. Public so Settings can offer "Reveal log".
    static var fileURL: URL {
        AppSettings.shared.storageDir
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("transcription.log")
    }

    /// Records one whisper invocation. Safe to call from any thread —
    /// actual I/O is serialized on `queue`. `tag` identifies the caller
    /// (e.g. "QuickTranscribe", "WhisperTranscriber", "LiveTranscriber")
    /// so a log scan can answer "why did the post-meeting transcribe fail?".
    static func record(
        tag: String,
        command: String,
        arguments: [String],
        exitCode: Int32,
        elapsedSeconds: Double,
        outputCharacters: Int,
        stderr: String,
        extra: [String: String] = [:]
    ) {
        queue.async {
            do {
                let dir = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                rotateIfNeeded()
                let block = formatBlock(
                    tag: tag,
                    command: command,
                    arguments: arguments,
                    exitCode: exitCode,
                    elapsedSeconds: elapsedSeconds,
                    outputCharacters: outputCharacters,
                    stderr: stderr,
                    extra: extra
                )
                if let data = block.data(using: .utf8) {
                    appendToFile(data)
                }
            } catch {
                log.error("TranscriptionLog write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Records a non-whisper diagnostic note (used for pre-flight errors
    /// like missing binary, empty source audio, etc).
    static func note(tag: String, message: String, extra: [String: String] = [:]) {
        queue.async {
            do {
                let dir = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                rotateIfNeeded()
                var lines: [String] = ["=== \(formatter.string(from: Date())) [\(tag)] note ==="]
                lines.append(message)
                for (k, v) in extra { lines.append("  \(k): \(v)") }
                lines.append("")
                if let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) {
                    appendToFile(data)
                }
            } catch {
                log.error("TranscriptionLog note failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Helpers

    private static func formatBlock(
        tag: String,
        command: String,
        arguments: [String],
        exitCode: Int32,
        elapsedSeconds: Double,
        outputCharacters: Int,
        stderr: String,
        extra: [String: String]
    ) -> String {
        var lines: [String] = []
        lines.append("=== \(formatter.string(from: Date())) [\(tag)] exit=\(exitCode) elapsed=\(String(format: "%.2fs", elapsedSeconds)) outputChars=\(outputCharacters) ===")
        lines.append("$ \(command) \(arguments.joined(separator: " "))")
        for (k, v) in extra {
            lines.append("  \(k): \(v)")
        }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // Keep stderr bounded — head + tail.
            let head = String(trimmed.prefix(800))
            let tail = trimmed.count > 1600 ? "\n...[truncated]...\n" + String(trimmed.suffix(800)) : ""
            lines.append("--- stderr ---")
            lines.append(head + tail)
        }
        lines.append("")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendToFile(_ data: Data) {
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    /// Truncate to ~half size when we cross the cap. Cheaper than streaming
    /// rotation; we don't care about pristine boundaries.
    private static func rotateIfNeeded() {
        let url = fileURL
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > maxBytes else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        let keep = data.suffix(maxBytes / 2)
        // Try to start at a clean block boundary (next "=== " marker). Decode
        // once; if the tail isn't valid UTF-8 (truncated mid-codepoint) just
        // keep the raw bytes rather than force-unwrapping and crashing.
        if let text = String(data: keep, encoding: .utf8),
           let range = text.range(of: "=== ") {
            let trimmed = String(text[range.lowerBound...])
            try? trimmed.data(using: .utf8)?.write(to: url)
        } else {
            try? keep.write(to: url)
        }
    }
}
