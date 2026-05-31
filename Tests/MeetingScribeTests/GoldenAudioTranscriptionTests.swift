import XCTest
@testable import MeetingScribe

/// E5-1 — golden-audio transcription regression suite.
///
/// Runs the *real* bundled `whisper-cli` against committed reference clips and
/// asserts the transcript hasn't regressed (normalized WER under a threshold).
/// The whisper subprocess is the app's core value and is otherwise explicitly
/// untested, so a model/whisper.cpp bump can silently degrade quality.
///
/// Skips (rather than fails) when the whisper binary, the model, or the
/// fixtures are absent, so CI on a runner without whisper stays green while a
/// developer Mac with whisper installed gets real coverage. See
/// `Fixtures/golden-audio/README.md` for how to add clips.
@MainActor
final class GoldenAudioTranscriptionTests: XCTestCase {

    /// Maximum tolerated word-error-rate against the expected transcript.
    /// base.en is imperfect; tune if the pinned model legitimately changes.
    static let maxWER = 0.35

    private func fixturesDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden-audio", isDirectory: true)
    }

    private func whisperAvailable() -> Bool {
        let fm = FileManager.default
        let binary = AppSettings.shared.whisperBinary
        let model = AppSettings.shared.whisperModel
        return fm.fileExists(atPath: binary) && fm.fileExists(atPath: model)
    }

    func testGoldenClipsTranscribeWithinWER() async throws {
        try XCTSkipUnless(whisperAvailable(),
                          "whisper-cli and/or the ggml model are not installed — skipping golden-audio regression")

        let dir = fixturesDir()
        let fm = FileManager.default
        let wavs = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        try XCTSkipUnless(!wavs.isEmpty,
                          "no golden-audio .wav fixtures present — see Fixtures/golden-audio/README.md")

        let transcriber = WhisperTranscriber()
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoldenAudio-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        for wav in wavs {
            let base = wav.deletingPathExtension().lastPathComponent
            let expectedURL = dir.appendingPathComponent("\(base).expected.txt")
            guard let expected = try? String(contentsOf: expectedURL, encoding: .utf8) else {
                XCTFail("missing expected transcript for \(base) (\(base).expected.txt)")
                continue
            }

            let segs = try await transcriber.transcribe(
                sources: [.init(label: "Me", url: wav)], in: workDir)
            let produced = WhisperTranscriber.render(segs)

            let wer = Self.wordErrorRate(expected: expected, produced: produced)
            XCTAssertLessThanOrEqual(
                wer, Self.maxWER,
                "WER \(String(format: "%.2f", wer)) exceeds \(Self.maxWER) for \(base).\n"
                + "expected: \(Self.normalize(expected))\nproduced: \(Self.normalize(produced))")
        }
    }

    // MARK: - Scoring helpers

    /// Lowercase, strip punctuation, collapse whitespace to comparable words.
    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let kept = lowered.unicodeScalars.map { scalar -> Character in
            (CharacterSet.alphanumerics.contains(scalar) || scalar == " ") ? Character(scalar) : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Word-level error rate = Levenshtein(words) / max(expectedWords, 1).
    static func wordErrorRate(expected: String, produced: String) -> Double {
        let e = normalize(expected).split(separator: " ").map(String.init)
        let p = normalize(produced).split(separator: " ").map(String.init)
        guard !e.isEmpty else { return p.isEmpty ? 0 : 1 }
        let distance = levenshtein(e, p)
        return Double(distance) / Double(e.count)
    }

    private static func levenshtein(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}
