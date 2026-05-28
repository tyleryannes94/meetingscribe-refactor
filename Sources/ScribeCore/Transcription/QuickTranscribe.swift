import Foundation
import OSLog

/// One-shot transcription: takes an audio file, converts to 16 kHz WAV via
/// afconvert, runs whisper-cli via the shared `WhisperRunner`, returns the
/// plain-text transcript.
///
/// Used by Note Transcriber and the dictation hotkey path.
final class QuickTranscribe {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "QuickTranscribe")

    enum QError: Error, LocalizedError {
        case afconvert(Int32, String)
        case afconvertEmpty(String)
        case runner(WhisperRunner.RunnerError)

        var errorDescription: String? {
            switch self {
            case .afconvert(let c, let m): return "afconvert exited \(c). \(m.prefix(200))"
            case .afconvertEmpty(let p): return "afconvert produced an empty file at \(p)."
            case .runner(let e): return e.errorDescription
            }
        }
    }

    /// Transcribes the given audio file to plain text.
    /// Must be called with `await` from an async context.
    func transcribe(audioURL: URL) async throws -> String {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingScribe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // afconvert → 16 kHz mono WAV.
        let wav = work.appendingPathComponent("audio.wav")
        try afconvert(input: audioURL, output: wav)
        let wavSize = (try? FileManager.default.attributesOfItem(atPath: wav.path)[.size] as? Int64) ?? 0
        if wavSize < 1024 { throw QError.afconvertEmpty(wav.path) }

        log.info("transcribe start: wav=\(wavSize)B")
        TranscriptionLog.note(tag: "QuickTranscribe",
                              message: "Start",
                              extra: ["audio": audioURL.path,
                                      "wavBytes": "\(wavSize)"])

        let runner = WhisperRunner(workDir: work)
        // The runner handles the GPU→CPU retry internally.
        do {
            let r = try await runner.run(audio: wav, output: .plainText)
            guard case let .text(t) = r else { return "" }
            return t
        } catch let e as WhisperRunner.RunnerError {
            throw QError.runner(e)
        }
    }

    // MARK: - Subprocesses

    private func afconvert(input: URL, output: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        p.arguments = [input.path, output.path, "-d", "LEI16@16000", "-c", "1", "-f", "WAVE"]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw QError.afconvert(p.terminationStatus, msg)
        }
    }
}
