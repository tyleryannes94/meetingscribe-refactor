import XCTest
@testable import MeetingScribe

/// Guards D4-1 — raw engine stderr must never reach the user as the headline,
/// and shell instructions / file paths get stripped from the fallback.
final class ErrorPresenterTests: XCTestCase {

    func testWhisperFailureBecomesPlainModelError() {
        let raw = "whisper-cli failed (1): model file is corrupted or empty. Re-download it via ./scripts/setup.sh"
        let p = ErrorPresenter.present(raw)
        XCTAssertEqual(p.kind, .model)
        XCTAssertFalse(p.title.lowercased().contains("whisper"))
        XCTAssertFalse(p.diagnosis.contains("./scripts"))
        XCTAssertNotNil(p.fixLabel)
    }

    func testOllamaFailureBecomesSummaryEngineError() {
        let p = ErrorPresenter.present("Ollama wasn't running, summarization failed")
        XCTAssertEqual(p.kind, .summaryEngine)
        XCTAssertFalse(p.title.lowercased().contains("ollama"))
    }

    func testEmptyAudioError() {
        let p = ErrorPresenter.present("Audio file at /Users/x/y.wav is empty (0 bytes)")
        XCTAssertEqual(p.kind, .audio)
    }

    func testGenericSanitizesPaths() {
        let raw = "Connection reset while reading /Users/me/vault/db.sqlite"
        let p = ErrorPresenter.present(raw)
        XCTAssertEqual(p.kind, .generic)
        XCTAssertFalse(p.diagnosis.contains("/Users/"))
    }
}
