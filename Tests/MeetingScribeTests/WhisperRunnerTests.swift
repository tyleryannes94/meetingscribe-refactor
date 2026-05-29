import XCTest
import CryptoKit
@testable import MeetingScribe

/// Covers `WhisperRunner.parse` (the JSON shape whisper-cli emits, plus the
/// malformed-input paths) and the model-checksum rejection extracted for
/// ENG-D. The subprocess/argv plumbing needs a real binary so it isn't unit
/// tested here; the parser and checksum are the data-integrity-critical parts.
final class WhisperRunnerTests: XCTestCase {

    private func json(_ s: String) -> Data { Data(s.utf8) }

    // MARK: - parse(.segments)

    func testParseSegmentsExtractsOffsetsAndTrimmedText() throws {
        let data = json("""
        {"transcription":[
          {"offsets":{"from":0,"to":1500},"text":" Hello there."},
          {"offsets":{"from":1500,"to":3000},"text":"General Kenobi "}
        ]}
        """)
        guard case let .segments(segs) = try WhisperRunner.parse(data, mode: .segments) else {
            return XCTFail("expected .segments")
        }
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0], WhisperRunner.Segment(startMs: 0, endMs: 1500, text: "Hello there."))
        XCTAssertEqual(segs[1].text, "General Kenobi")
    }

    func testParseSegmentsDropsEmptyAndOffsetlessSegments() throws {
        let data = json("""
        {"transcription":[
          {"offsets":{"from":0,"to":10},"text":"   "},
          {"text":"no offsets so dropped in segment mode"},
          {"offsets":{"from":10,"to":20},"text":"kept"}
        ]}
        """)
        guard case let .segments(segs) = try WhisperRunner.parse(data, mode: .segments) else {
            return XCTFail("expected .segments")
        }
        XCTAssertEqual(segs.map(\.text), ["kept"])
    }

    // MARK: - parse(.plainText)

    func testParsePlainTextJoinsTrimmedNonEmpty() throws {
        let data = json("""
        {"transcription":[
          {"text":" one "},
          {"text":"  "},
          {"text":"two"}
        ]}
        """)
        guard case let .text(t) = try WhisperRunner.parse(data, mode: .plainText) else {
            return XCTFail("expected .text")
        }
        XCTAssertEqual(t, "one two")
    }

    // MARK: - malformed input

    func testParseMalformedJSONThrowsJsonParse() {
        XCTAssertThrowsError(try WhisperRunner.parse(json("{ not json ]"), mode: .plainText)) { err in
            guard case WhisperRunner.RunnerError.jsonParse = err else {
                return XCTFail("expected .jsonParse, got \(err)")
            }
        }
    }

    func testParseWrongShapeThrowsJsonParse() {
        // Valid JSON, but missing the required `transcription` key.
        XCTAssertThrowsError(try WhisperRunner.parse(json(#"{"segments":[]}"#), mode: .segments)) { err in
            guard case WhisperRunner.RunnerError.jsonParse = err else {
                return XCTFail("expected .jsonParse, got \(err)")
            }
        }
    }

    // MARK: - checksum (ENG-D)

    private func tempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wr-\(UUID().uuidString).bin")
        try data.write(to: url)
        return url
    }

    func testFileMatchesSHA256IsTrueForCorrectHashAndCaseInsensitive() throws {
        let payload = Data("hello whisper model".utf8)
        let url = try tempFile(payload)
        defer { try? FileManager.default.removeItem(at: url) }
        let expected = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(WhisperRunner.fileMatchesSHA256(url, expectedHex: expected))
        XCTAssertTrue(WhisperRunner.fileMatchesSHA256(url, expectedHex: expected.uppercased()),
                      "comparison must be case-insensitive")
        XCTAssertEqual(WhisperRunner.sha256Hex(of: url), expected)
    }

    func testFileMatchesSHA256RejectsWrongHashAndMissingFile() throws {
        let url = try tempFile(Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertFalse(WhisperRunner.fileMatchesSHA256(url, expectedHex: String(repeating: "0", count: 64)))
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString)")
        XCTAssertFalse(WhisperRunner.fileMatchesSHA256(missing, expectedHex: WhisperRunner.baseEnModelSHA256))
        XCTAssertNil(WhisperRunner.sha256Hex(of: missing))
    }

    func testBaseEnModelSHA256IsPinned() {
        XCTAssertEqual(WhisperRunner.baseEnModelSHA256.count, 64)
        XCTAssertEqual(WhisperRunner.baseEnModelSHA256,
                       "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002")
    }
}
