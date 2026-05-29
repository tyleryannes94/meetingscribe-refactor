import XCTest
@testable import MeetingScribe

/// Covers the parts of `LiveTranscriber` that don't need a real whisper-cli:
/// timestamp formatting, the stderr→friendly-message summarizer, and — most
/// importantly — that `flush()` drains all in-flight work and terminates even
/// when transcription fails fast. `flush()` is what stops the final 0–5 min of
/// a meeting being dropped before `renderMarkdown()` (ENG-A); a flush that hung
/// or returned early would silently reintroduce the data loss.
@MainActor
final class LiveTranscriberTests: XCTestCase {

    func testFormatShortAndLong() {
        XCTAssertEqual(LiveTranscriber.format(0), "0:00")
        XCTAssertEqual(LiveTranscriber.format(65), "1:05")
        XCTAssertEqual(LiveTranscriber.format(3661), "1:01:01")
    }

    func testSummarizeWhisperErrorPrioritizesContextInitFailure() {
        let stderr = "loading model...\nerror: failed to initialize whisper context\ntrailing noise"
        let msg = LiveTranscriber.summarizeWhisperError(exitCode: 3, stderr: stderr)
        XCTAssertTrue(msg.contains("could not initialize whisper context"), msg)
        XCTAssertTrue(msg.contains("3"), "exit code should be surfaced")
    }

    func testSummarizeWhisperErrorBadMagic() {
        let msg = LiveTranscriber.summarizeWhisperError(exitCode: 1, stderr: "whisper_model_load: bad magic")
        XCTAssertTrue(msg.contains("corrupted or empty"), msg)
    }

    func testFlushReturnsImmediatelyWhenIdle() async {
        let lt = LiveTranscriber()
        await lt.flush()
        XCTAssertEqual(lt.pendingCount, 0)
    }

    func testFlushDrainsAllPendingEvenWhenWhisperBinaryMissing() async {
        // Point at a guaranteed-missing binary so each chunk fails preflight
        // fast (binaryMissing) but still runs processChunk's `defer`, which is
        // what decrements pendingCount. If flush ignored those tail tasks the
        // counter would never reach 0.
        let prior = AppSettings.shared.whisperBinary
        AppSettings.shared.whisperBinary = "/nonexistent/whisper-cli-\(UUID().uuidString)"
        defer { AppSettings.shared.whisperBinary = prior }

        let lt = LiveTranscriber()
        for i in 0..<6 {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("chunk-\(i)-\(UUID().uuidString).wav")
            lt.submitChunk(url: url,
                           speaker: i % 2 == 0 ? "Me" : "Them",
                           startSec: Double(i * 300),
                           endSec: Double((i + 1) * 300))
        }
        await lt.flush()
        XCTAssertEqual(lt.pendingCount, 0,
                       "flush() must await every in-flight per-source task to completion")
        XCTAssertFalse(lt.isProcessing)
    }
}
