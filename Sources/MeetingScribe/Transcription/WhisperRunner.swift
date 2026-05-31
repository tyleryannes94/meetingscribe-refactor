import Foundation
import OSLog
import CryptoKit

/// One place that knows how to invoke `whisper-cli`. Consolidates the three
/// near-identical implementations that used to live in `WhisperTranscriber`,
/// `QuickTranscribe`, and `LiveTranscriber` (audit 4.3). Encapsulates:
///
///   • argv construction (shared flag handling, including the documented
///     "do NOT pass --no-context" guard)
///   • the GPU-then-CPU empty-output retry path (pre-M5 Metal failure mode)
///   • subprocess lifecycle + stderr capture + diagnostic logging
///   • result shape: structured segments OR plain text
///
/// Both whisper-cli output modes are supported because the live + batch paths
/// have different needs:
///   - .segments(prefix:): writes JSON via --output-json, parses timestamps.
///     Used by the batch transcriber that needs speaker-tagged segments.
///   - .plainText: writes JSON to disk anyway (whisper-cli has no
///     stdout-JSON mode) but only extracts the joined text. Used by the
///     live + voice-note paths that don't need segment-level timing.
///
/// The class itself is stateless; instances exist only to let callers stash
/// a per-call working directory cleanly. Safe to construct ad-hoc.
struct WhisperRunner {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "WhisperRunner")

    enum Output {
        /// Parse JSON segments with start/end offsets.
        case segments
        /// Concatenate the JSON segments' text into one string.
        case plainText
    }

    struct Segment: Equatable, Sendable {
        let startMs: Int
        let endMs: Int
        let text: String
    }

    enum RunResult: Sendable {
        case segments([Segment])
        case text(String)

        var isEmpty: Bool {
            switch self {
            case .segments(let s): return s.allSatisfy { $0.text.isEmpty }
            case .text(let t): return t.isEmpty
            }
        }
    }

    enum RunnerError: Error, LocalizedError {
        case binaryMissing(String)
        case modelMissing(String)
        case audioMissing(String)
        case audioEmpty(String)
        case modelTooSmall(String, Int64)
        case subprocess(Int32, String)
        case jsonMissing(URL)
        case jsonParse(String)
        case empty(String)

        var errorDescription: String? {
            switch self {
            case .binaryMissing(let p):
                return "whisper-cli not found at \(p). Install: brew install whisper-cpp, then set the path in Settings."
            case .modelMissing(let p):
                return "Whisper model not found at \(p). Download a ggml model (e.g. ggml-base.en.bin)."
            case .audioMissing(let p):
                return "Audio file missing at \(p)."
            case .audioEmpty(let p):
                return "Audio file at \(p) is empty (0 bytes). Recording may have failed — check Microphone permission."
            case .modelTooSmall(let p, let n):
                return "Whisper model at \(p) is only \(n) bytes — incomplete download. Re-download a ggml model."
            case .subprocess(let c, let m):
                return "whisper-cli exited \(c). \(m.prefix(300))"
            case .jsonMissing(let u):
                return "whisper-cli didn't produce JSON at \(u.path) — check the binary."
            case .jsonParse(let m):
                return "Failed to parse whisper JSON: \(m)"
            case .empty(let stderr):
                return "whisper-cli ran but produced no text. \(stderr.isEmpty ? "Recording may be silent." : "stderr: \(stderr.prefix(300))")"
            }
        }
    }

    let binary: String
    let model: String
    /// Working directory for whisper's output files. Caller is responsible
    /// for cleanup (or for picking a temp dir that gets nuked).
    let workDir: URL

    init(binary: String = AppSettings.shared.whisperBinary,
         model: String = AppSettings.shared.whisperModel,
         workDir: URL) {
        self.binary = binary
        self.model = model
        self.workDir = workDir
    }

    /// Run whisper-cli on `audio` and return either segments or joined text.
    /// Automatically retries on CPU if the first GPU pass returns empty
    /// (the documented pre-M5 Metal failure mode).
    func run(audio: URL, output: Output) async throws -> RunResult {
        try await preflight(audio: audio)

        let useGPUFirst = AppSettings.shared.whisperUseGPU
        let firstResult = try runOnce(audio: audio, output: output, forceCPU: !useGPUFirst)
        if !firstResult.result.isEmpty { return firstResult.result }

        // First pass was empty. If we just ran on GPU, retry on CPU.
        if useGPUFirst {
            log.info("whisper produced empty output on GPU — retrying on CPU")
            TranscriptionLog.note(tag: "WhisperRunner",
                                  message: "GPU pass empty — retrying on CPU (--no-gpu)",
                                  extra: ["audio": audio.path])
            let retry = try runOnce(audio: audio, output: output, forceCPU: true)
            if !retry.result.isEmpty { return retry.result }
            throw RunnerError.empty(retry.stderr)
        }
        throw RunnerError.empty(firstResult.stderr)
    }

    // MARK: - Single invocation

    private struct OnceResult {
        let result: RunResult
        let stderr: String
    }

    private func runOnce(audio: URL, output: Output, forceCPU: Bool) throws -> OnceResult {
        let prefix = workDir.appendingPathComponent("\(audio.deletingPathExtension().lastPathComponent)-\(forceCPU ? "cpu" : "gpu").whisper")
        let stderr = try runWhisper(audio: audio, prefix: prefix, forceCPU: forceCPU)
        let jsonURL = URL(fileURLWithPath: prefix.path + ".json")
        defer {
            // Best-effort cleanup so working dirs don't grow unbounded.
            try? FileManager.default.removeItem(at: jsonURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: prefix.path + ".txt"))
        }
        guard let data = try? Data(contentsOf: jsonURL), !data.isEmpty else {
            // No JSON? Either whisper exited 0 with no output, or the
            // binary doesn't support the flags we passed.
            throw RunnerError.jsonMissing(jsonURL)
        }
        let parsed = try Self.parse(data, mode: output)
        return OnceResult(result: parsed, stderr: stderr)
    }

    private func runWhisper(audio: URL, prefix: URL, forceCPU: Bool) throws -> String {
        let args = Self.argv(audio: audio, model: model, prefix: prefix, forceCPU: forceCPU)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        let errPipe = Pipe()
        let outPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = outPipe

        let started = Date()
        try proc.run()

        // Drain stderr concurrently so we don't block on a full pipe.
        var stderrData = Data()
        let stderrQueue = DispatchQueue(label: "whisper.stderr.drain")
        stderrQueue.async {
            let handle = errPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                stderrData.append(chunk)
            }
        }
        proc.waitUntilExit()
        stderrQueue.sync {}
        _ = outPipe.fileHandleForReading.readDataToEndOfFile()
        let elapsed = Date().timeIntervalSince(started)
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

        TranscriptionLog.record(
            tag: "WhisperRunner",
            command: binary,
            arguments: args,
            exitCode: proc.terminationStatus,
            elapsedSeconds: elapsed,
            outputCharacters: 0,
            stderr: stderrStr
        )
        if proc.terminationStatus != 0 {
            throw RunnerError.subprocess(proc.terminationStatus, stderrStr)
        }
        return stderrStr
    }

    // MARK: - Argv (single source of truth)

    /// IMPORTANT: do NOT pass `--no-context`. In whisper-cpp 1.8.4 it causes
    /// whisper to exit 0 but emit an EMPTY transcript — the root cause of the
    /// historical "ran but produced no text" failures. The comment is here
    /// so it can never get lost: this is the one place argv is built.
    static func argv(audio: URL, model: String, prefix: URL, forceCPU: Bool) -> [String] {
        let cores = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        let settings = AppSettings.shared
        let lang = settings.whisperLanguage
        var args = [
            "-m", model,
            "-f", audio.path,
            "--output-json",
            "--output-file", prefix.path,
            "--no-prints",
            "--language", lang,
            "--best-of", "1",
            "--beam-size", "1",
            "--threads", "\(cores)"
        ]
        // flash-attn off by default — empty transcripts on pre-M5 Apple Silicon.
        if !settings.whisperFlashAttention { args.append("--no-flash-attn") }
        if forceCPU || !settings.whisperUseGPU { args.append("--no-gpu") }
        // Speaker diarization (opt-in). whisper.cpp emits `[SPEAKER_NN]` turn
        // markers in segment text; SpeakerDiarization.parse() maps those into a
        // DiarizedTranscript. Standard ggml models ignore the flag, so passing
        // it is harmless when the model doesn't support tinydiarize.
        if settings.whisperDiarizationEnabled { args.append("--diarize") }
        return args
    }

    // MARK: - JSON parsing

    private struct WhisperJSON: Decodable {
        struct Segment: Decodable {
            struct Offsets: Decodable { let from: Int; let to: Int }
            let offsets: Offsets?
            let text: String
        }
        let transcription: [Segment]
    }

    static func parse(_ data: Data, mode: Output) throws -> RunResult {
        let decoded: WhisperJSON
        do { decoded = try JSONDecoder().decode(WhisperJSON.self, from: data) }
        catch { throw RunnerError.jsonParse(error.localizedDescription) }

        switch mode {
        case .segments:
            let segs = decoded.transcription.compactMap { s -> Segment? in
                let trimmed = s.text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, let off = s.offsets else { return nil }
                return Segment(startMs: off.from, endMs: off.to, text: trimmed)
            }
            return .segments(segs)
        case .plainText:
            let joined = decoded.transcription
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return .text(joined)
        }
    }

    // MARK: - Model checksum (ENG-D)

    /// Known-good SHA-256 of `ggml-base.en.bin` from the whisper.cpp HF repo.
    /// A downloaded model whose bytes don't hash to this is rejected so a
    /// truncated / MITM'd / garbage-but-large file can't install as the model
    /// and silently break all transcription. Update only if the upstream
    /// artifact is intentionally revved.
    static let baseEnModelSHA256 = "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"

    /// SHA-256 the file at `url`, returning lowercase hex, or nil if unreadable.
    static func sha256Hex(of url: URL) -> String? {
        guard let bytes = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// True iff the file at `url` hashes to `expectedHex` (case-insensitive).
    /// Extracted from the download path so the rejection logic is unit-testable
    /// without a 140 MB network fetch.
    static func fileMatchesSHA256(_ url: URL, expectedHex: String) -> Bool {
        guard let hex = sha256Hex(of: url) else { return false }
        return hex.caseInsensitiveCompare(expectedHex) == .orderedSame
    }

    // MARK: - Pre-flight

    private func preflight(audio: URL) async throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: binary) else { throw RunnerError.binaryMissing(binary) }

        // Auto-bootstrap the model on first use. The default settings path
        // is `<storageDir>/models/ggml-base.en.bin` and a fresh install
        // doesn't ship one — so the first voice note used to fail with
        // "Whisper model not found". Pull it from the canonical
        // whisper.cpp host if it's missing, the directory is writable, AND
        // the user is still on the default base.en path (we don't want to
        // surprise users who picked a custom model location).
        if !fm.fileExists(atPath: model) {
            if Self.isDefaultBaseEnPath(model),
               await Self.tryAutoDownloadBaseEnModel(to: model) {
                // fall through to size check
            } else {
                throw RunnerError.modelMissing(model)
            }
        }

        let modelSize = (try? fm.attributesOfItem(atPath: model)[.size] as? Int64) ?? 0
        if modelSize < 10_000_000 {
            throw RunnerError.modelTooSmall(model, modelSize)
        }
        guard fm.fileExists(atPath: audio.path) else { throw RunnerError.audioMissing(audio.path) }
        let audioSize = (try? fm.attributesOfItem(atPath: audio.path)[.size] as? Int64) ?? 0
        if audioSize < 1024 { throw RunnerError.audioEmpty(audio.path) }
    }

    /// True iff `path` looks like the default `<storage>/models/ggml-base.en.bin`
    /// location AppSettings.whisperModel returns when the user hasn't picked
    /// a custom model. We only auto-download in that case so we never
    /// overwrite or surprise a user who chose another path.
    private static func isDefaultBaseEnPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent == "ggml-base.en.bin"
            && url.deletingLastPathComponent().lastPathComponent == "models"
    }

    /// True iff the configured whisper model file exists and is a sane size.
    /// Used by the first-run Setup Check (D3-1) to show readiness.
    static var isModelReady: Bool {
        let path = AppSettings.shared.whisperModel
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        return size >= 10_000_000
    }

    /// Public one-tap download for the Setup Check. Returns true if the default
    /// base.en model is present afterwards. No-op when it already exists; only
    /// downloads when the user is on the default base.en path (we never touch a
    /// custom model location).
    static func ensureDefaultModelDownloaded() async -> Bool {
        if isModelReady { return true }
        let path = AppSettings.shared.whisperModel
        guard isDefaultBaseEnPath(path) else { return false }
        return await tryAutoDownloadBaseEnModel(to: path)
    }

    /// Download ggml-base.en.bin from the canonical whisper.cpp HF host
    /// (~140 MB) into `path`. Uses async URLSession so cooperative thread
    /// pool workers are never blocked. Writes via a temp file + atomic rename
    /// so a partial / interrupted download never leaves a corrupt model on
    /// disk. Returns true iff the file ended up where it should be and
    /// is at least the minimum sane size.
    private static func tryAutoDownloadBaseEnModel(to path: String) async -> Bool {
        let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "WhisperRunner")
        let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!
        let dest = URL(fileURLWithPath: path)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
        } catch {
            log.error("Cannot create models dir: \(error.localizedDescription, privacy: .public)")
            return false
        }
        log.info("Auto-downloading ggml-base.en.bin from HuggingFace")
        TranscriptionLog.note(tag: "WhisperRunner",
                              message: "Auto-downloading whisper model",
                              extra: ["from": url.absoluteString, "to": path])

        let request = URLRequest(url: url, timeoutInterval: 600)
        let (tempURL, response): (URL, URLResponse)
        do {
            let session = URLSession(configuration: .ephemeral)
            (tempURL, response) = try await session.download(for: request)
        } catch {
            log.error("Whisper model download failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            log.error("Whisper model download HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return false
        }

        // Move the URLSession temp file to a stable scratch path before
        // URLSession can delete it on task completion.
        let scratch = fm.temporaryDirectory.appendingPathComponent(
            "ggml-base.en.\(UUID().uuidString).bin")
        do {
            try fm.moveItem(at: tempURL, to: scratch)
        } catch {
            log.error("Cannot move downloaded model to scratch: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let size = (try? fm.attributesOfItem(atPath: scratch.path)[.size] as? Int64) ?? 0
        guard size > 10_000_000 else {
            log.error("Downloaded whisper model is too small: \(size) bytes")
            try? fm.removeItem(at: scratch)
            return false
        }

        // Verify the bytes against the known-good SHA-256 so a truncated /
        // MITM'd / garbage-but-large file can't install as the model and
        // silently break all transcription. (ENG-D)
        guard Self.fileMatchesSHA256(scratch, expectedHex: Self.baseEnModelSHA256) else {
            let got = Self.sha256Hex(of: scratch) ?? "<unreadable>"
            log.error("Whisper model checksum mismatch — rejecting. got=\(got, privacy: .public)")
            TranscriptionLog.note(tag: "WhisperRunner",
                                  message: "Whisper model checksum mismatch — rejected",
                                  extra: ["expected": Self.baseEnModelSHA256, "got": got])
            try? fm.removeItem(at: scratch)
            return false
        }

        do {
            // _moveItem_ instead of replaceItem so we don't depend on dest
            // already existing.
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: scratch, to: dest)
        } catch {
            log.error("Cannot install whisper model at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? fm.removeItem(at: scratch)
            return false
        }
        log.info("Installed whisper model (\(size) bytes) at \(path, privacy: .public)")
        TranscriptionLog.note(tag: "WhisperRunner",
                              message: "Auto-downloaded whisper model OK",
                              extra: ["bytes": "\(size)", "path": path])
        return true
    }
}

extension WhisperRunner.RunnerError: Reportable {
    var userMessage: String { errorDescription ?? String(describing: self) }
}
