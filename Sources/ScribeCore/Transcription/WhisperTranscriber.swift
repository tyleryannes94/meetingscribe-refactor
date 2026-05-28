import Foundation
import OSLog

/// Batch transcriber for finalizing a meeting's mic + system audio after
/// stop. Multi-source: produces a single chronologically-ordered, speaker-
/// labeled segment list.
///
/// All whisper-cli invocation lives in `WhisperRunner` (Batch 5 / audit
/// 4.3) — this class now only handles afconvert (m4a → wav) and the
/// multi-source merging / speaker label logic.
final class WhisperTranscriber {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Whisper")

    struct Segment {
        let speaker: String
        let startMs: Int
        let endMs: Int
        let text: String
    }

    struct SourceInput {
        let label: String      // e.g. "Me", "Them"
        let url: URL
    }

    enum TranscribeError: Error, LocalizedError {
        case afconvertFailed(Int32, String)
        case runner(WhisperRunner.RunnerError)

        var errorDescription: String? {
            switch self {
            case .afconvertFailed(let c, let m): return "afconvert exited \(c): \(m)"
            case .runner(let e): return e.errorDescription
            }
        }
    }

    func transcribe(sources: [SourceInput], in workDir: URL) async throws -> [Segment] {
        var all: [Segment] = []
        for source in sources {
            let wav = workDir.appendingPathComponent(
                "\(source.url.deletingPathExtension().lastPathComponent).wav")
            try convertToWav(input: source.url, output: wav)
            let runner = WhisperRunner(workDir: workDir)
            do {
                let result = try await runner.run(audio: wav, output: .segments)
                guard case let .segments(segs) = result else { continue }
                all.append(contentsOf: segs.map {
                    Segment(speaker: source.label,
                            startMs: $0.startMs, endMs: $0.endMs, text: $0.text)
                })
            } catch let e as WhisperRunner.RunnerError {
                throw TranscribeError.runner(e)
            }
        }
        all.sort { $0.startMs < $1.startMs }
        return all
    }

    // MARK: - afconvert

    private func convertToWav(input: URL, output: URL) throws {
        try? FileManager.default.removeItem(at: output)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        proc.arguments = [
            input.path,
            output.path,
            "-d", "LEI16@16000",
            "-c", "1",
            "-f", "WAVE"
        ]
        let err = Pipe()
        proc.standardError = err
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TranscribeError.afconvertFailed(proc.terminationStatus, msg)
        }
    }

    // MARK: - Rendering

    /// Renders a merged transcript with speaker labels.
    static func render(_ segments: [Segment]) -> String {
        var out = ""
        var currentSpeaker = ""
        for seg in segments {
            if seg.text.isEmpty { continue }
            if seg.speaker != currentSpeaker {
                if !out.isEmpty { out += "\n\n" }
                out += "\(seg.speaker) [\(format(ms: seg.startMs))]: "
                currentSpeaker = seg.speaker
            } else {
                out += " "
            }
            out += seg.text
        }
        return out
    }

    private static func format(ms: Int) -> String {
        let s = ms / 1000
        let h = s / 3600
        let m = (s % 3600) / 60
        let r = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, r) }
        return String(format: "%d:%02d", m, r)
    }
}

extension WhisperTranscriber.TranscribeError: Reportable {
    var userMessage: String { errorDescription ?? String(describing: self) }
}
