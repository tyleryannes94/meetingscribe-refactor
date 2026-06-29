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

        // Watchdog timeout so a hung whisper subprocess can never wedge the
        // pipeline forever ("Re-transcribe stuck on Processing…"). The input is
        // a 16 kHz mono Int16 WAV (32000 bytes/sec), so estimate its duration
        // from file size and allow up to ~3x real-time + slack.
        let fileSize = ((try? FileManager.default.attributesOfItem(atPath: audio.path))?[.size] as? Int64) ?? 0
        let durationSec = max(0, Double(fileSize - 44) / 32000.0)
        let timeout = max(300, durationSec * 3 + 180)

        let useGPUFirst = AppSettings.shared.whisperUseGPU
        let firstResult = try runOnce(audio: audio, output: output, forceCPU: !useGPUFirst, timeout: timeout)
        if !firstResult.result.isEmpty { return firstResult.result }

        // First pass was empty. If we just ran on GPU, retry on CPU.
        if useGPUFirst {
            log.info("whisper produced empty output on GPU — retrying on CPU")
            TranscriptionLog.note(tag: "WhisperRunner",
                                  message: "GPU pass empty — retrying on CPU (--no-gpu)",
                                  extra: ["audio": audio.path])
            let retry = try runOnce(audio: audio, output: output, forceCPU: true, timeout: timeout)
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

    private func runOnce(audio: URL, output: Output, forceCPU: Bool, timeout: TimeInterval) throws -> OnceResult {
        let prefix = workDir.appendingPathComponent("\(audio.deletingPathExtension().lastPathComponent)-\(forceCPU ? "cpu" : "gpu").whisper")
        let stderr = try runWhisper(audio: audio, prefix: prefix, forceCPU: forceCPU, timeout: timeout)
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

    private func runWhisper(audio: URL, prefix: URL, forceCPU: Bool, timeout: TimeInterval) throws -> String {
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

        // Drain BOTH pipes concurrently. Draining stdout only AFTER
        // waitUntilExit() could deadlock if whisper fills the 64 KB stdout
        // buffer (it never exits, we never read) — so read both off-thread.
        let drainGroup = DispatchGroup()
        let drainQ = DispatchQueue(label: "whisper.drain", attributes: .concurrent)
        let stderrBox = DataBox(), stdoutBox = DataBox()
        drainGroup.enter()
        drainQ.async { stderrBox.data = errPipe.fileHandleForReading.readDataToEndOfFile(); drainGroup.leave() }
        drainGroup.enter()
        drainQ.async { stdoutBox.data = outPipe.fileHandleForReading.readDataToEndOfFile(); drainGroup.leave() }

        // Watchdog: terminate a hung subprocess so the pipeline never blocks
        // forever. On timeout the process exits non-zero and we throw, which
        // surfaces as a transcription error rather than a stuck "Processing…".
        let watchdog = DispatchWorkItem {
            if proc.isRunning {
                self.log.error("whisper exceeded \(Int(timeout))s timeout — terminating")
                proc.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        proc.waitUntilExit()
        watchdog.cancel()
        drainGroup.wait()
        let elapsed = Date().timeIntervalSince(started)
        let stderrStr = String(data: stderrBox.data, encoding: .utf8) ?? ""

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

    /// Box so the concurrent drain closures can write back captured Data
    /// without a `var` capture warning.
    private final class DataBox { var data = Data() }

    // MARK: - Argv (single source of truth)

    /// IMPORTANT: do NOT pass `--no-context`. In whisper-cpp 1.8.4 it causes
    /// whisper to exit 0 but emit an EMPTY transcript — the root cause of the
    /// historical "ran but produced no text" failures. The comment is here
    /// so it can never get lost: this is the one place argv is built.
    static func argv(audio: URL, model: String, prefix: URL, forceCPU: Bool) -> [String] {
        let cores = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        let settings = AppSettings.shared
        // English-only models (.en) MUST be told `en`: passing `--language auto`
        // to an .en model on low-SNR mic audio destabilizes the decoder into
        // repetition loops ("It's rain" ×N). For multilingual models, honor the
        // user's setting.
        let isEnglishModel = URL(fileURLWithPath: model).lastPathComponent.contains(".en")
        let lang = isEnglishModel ? "en" : settings.whisperLanguage
        var args = [
            "-m", model,
            "-f", audio.path,
            "--output-json",
            "--output-file", prefix.path,
            "--no-prints",
            "--language", lang,
            "--best-of", "1",
            "--beam-size", "1",
            "--threads", "\(cores)",
            // Suppress non-speech tokens so breaths/noise aren't decoded as words.
            "--suppress-nst"
        ]
        // Voice Activity Detection: only feed speech to the decoder, so non-speech
        // gaps (the user's mic while the other party talks) can't be hallucinated
        // into filler. Only when the VAD model is actually present on disk —
        // `preflight` downloads it best-effort.
        if settings.whisperVADEnabled,
           FileManager.default.fileExists(atPath: settings.whisperVADModel) {
            args.append(contentsOf: ["--vad", "--vad-model", settings.whisperVADModel])
        }
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
                let trimmed = Self.collapseInlineRepeats(s.text.trimmingCharacters(in: .whitespaces))
                guard !trimmed.isEmpty, !Self.isHallucination(trimmed), let off = s.offsets else { return nil }
                return Segment(startMs: off.from, endMs: off.to, text: trimmed)
            }
            return .segments(Self.dropRepetitionLoops(segs))
        case .plainText:
            let kept = decoded.transcription
                .map { Self.collapseInlineRepeats($0.text.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.isEmpty && !Self.isHallucination($0) }
            // Reuse the loop filter on text-only segments too.
            let deduped = Self.dropRepetitionLoops(kept.enumerated().map {
                Segment(startMs: $0.offset, endMs: $0.offset, text: $0.element)
            }).map(\.text)
            return .text(deduped.joined(separator: " "))
        }
    }

    // MARK: - Repetition / loop filtering
    //
    // Whisper's signature failure on continuous low-SNR audio is to emit the
    // SAME short phrase across many consecutive segments ("It's rain" ×230) — a
    // decoder loop, not real speech. The bracket filter (`isHallucination`)
    // can't catch plain-word loops, so we collapse them here.

    /// Collapses an immediately-repeated 1–5-word phrase inside one segment,
    /// e.g. "It's rain It's rain" → "It's rain".
    static func collapseInlineRepeats(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let pattern = #"\b([\w']+(?:\s+[\w']+){0,4})(?:\s+\1\b)+"#
        return text.replacingOccurrences(of: pattern, with: "$1",
                                         options: [.regularExpression, .caseInsensitive])
    }

    /// Drops runaway repeated segments: a short phrase (≤6 words) repeated more
    /// than twice, or appearing back-to-back, is a hallucination loop. Longer
    /// segments are real speech and kept even if they recur.
    static func dropRepetitionLoops(_ segs: [WhisperRunner.Segment]) -> [WhisperRunner.Segment] {
        func norm(_ s: String) -> String {
            s.lowercased().trimmingCharacters(in: .punctuationCharacters)
                .trimmingCharacters(in: .whitespaces)
        }
        var out: [WhisperRunner.Segment] = []
        var counts: [String: Int] = [:]
        for seg in segs {
            let key = norm(seg.text)
            let wordCount = key.split(whereSeparator: { $0 == " " }).count
            guard wordCount <= 6 else { out.append(seg); continue }
            // Back-to-back duplicate of the previous kept short phrase.
            if let last = out.last, norm(last.text) == key { continue }
            counts[key, default: 0] += 1
            if counts[key, default: 0] > 2 { continue }   // 3rd+ occurrence of a short phrase
            out.append(seg)
        }
        return out
    }

    // MARK: - Hallucination filter

    /// Whisper emits these strings when audio is silent or too noisy to decode.
    /// Keeping them in the transcript produces misleading "[silence]" / "dramatic
    /// music" entries that confuse both readers and the summary LLM.
    private static let hallucinationPatterns: [String] = [
        "[silence]", "[BLANK_AUDIO]", "[Music]", "[music]",
        "(silence)", "(dramatic music)", "(tense music)", "(ambient music)",
        "(music)", "(piano music)", "(classical music)", "(upbeat music)",
        "(mumbling)", "(indistinct chatter)", "(crowd noise)"
    ]

    static func isHallucination(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Exact-match known hallucination strings
        if hallucinationPatterns.contains(where: { lower == $0.lowercased() }) { return true }
        // Segments that are ONLY bracketed/parenthesized tokens with no real words
        let stripped = text.replacingOccurrences(of: #"[\[\(][^\]\)]+[\]\)]"#, with: "",
                                                   options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty
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
        // Best-effort: make sure the VAD model is present so argv can enable VAD.
        // Never blocks transcription — failure just means we transcribe without it.
        if AppSettings.shared.whisperVADEnabled {
            await Self.ensureVADModel()
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

    /// Best-effort fetch of the small Silero VAD ggml model so whisper-cli's
    /// `--vad` can run. Never throws — on any failure it records a timestamp and
    /// won't retry for 24h, and transcription proceeds without VAD.
    static func ensureVADModel() async {
        let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "WhisperRunner")
        let fm = FileManager.default
        let path = AppSettings.shared.whisperVADModel
        if fm.fileExists(atPath: path),
           let size = try? fm.attributesOfItem(atPath: path)[.size] as? Int64, size > 100_000 {
            return
        }
        let lastFail = AppSettings.shared.whisperVADDownloadFailedAt
        if lastFail > 0, Date().timeIntervalSince1970 - lastFail < 86_400 { return }

        func recordFailure() { AppSettings.shared.whisperVADDownloadFailedAt = Date().timeIntervalSince1970 }

        let url = URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin")!
        let dest = URL(fileURLWithPath: path)
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let session = URLSession(configuration: .ephemeral)
            let (tempURL, response) = try await session.download(for: URLRequest(url: url, timeoutInterval: 120))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                log.error("VAD model download HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                recordFailure(); return
            }
            let scratch = fm.temporaryDirectory.appendingPathComponent("vad-\(UUID().uuidString).bin")
            try fm.moveItem(at: tempURL, to: scratch)
            let size = (try? fm.attributesOfItem(atPath: scratch.path)[.size] as? Int64) ?? 0
            guard size > 100_000 else { try? fm.removeItem(at: scratch); recordFailure(); return }
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: scratch, to: dest)
            AppSettings.shared.whisperVADDownloadFailedAt = 0
            log.info("Installed Silero VAD model (\(size) bytes)")
        } catch {
            log.error("VAD model download failed: \(error.localizedDescription, privacy: .public)")
            recordFailure()
        }
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
