import XCTest
@testable import MeetingScribe

/// Regression tests for the transcript-sync regex parser. It feeds the
/// audio-synced transcript view; a parser regression would silently blank the
/// transcript pane even when transcript.md is fine on disk.
final class TranscriptParserTests: XCTestCase {

    func testParsesStructuredSpeakerTimestampLines() {
        let md = """
        Me [0:05]: First sentence here.
        Them [1:23]: Another utterance.
        """
        let segs = TranscriptParser.parse(md)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].speaker, "Me")
        XCTAssertEqual(segs[0].startSeconds, 5)
        XCTAssertEqual(segs[0].text, "First sentence here.")
        XCTAssertEqual(segs[1].speaker, "Them")
        XCTAssertEqual(segs[1].startSeconds, 83)
    }

    func testParsesHoursTimestamp() {
        let segs = TranscriptParser.parse("Them [1:02:03]: deep into the call")
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].startSeconds, 3723)
    }

    func testFallsBackToBoldSpeakerFormat() {
        let segs = TranscriptParser.parse("**Me:** hello\n**Them:** hi back")
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].speaker, "Me")
        XCTAssertEqual(segs[0].text, "hello")
        XCTAssertEqual(segs[0].startSeconds, 0)
    }

    func testIgnoresNonMatchingLines() {
        let md = "# Transcript\n\njust some prose with no speaker\n"
        XCTAssertTrue(TranscriptParser.parse(md).isEmpty)
    }

    func testEmptyInputYieldsNoSegments() {
        XCTAssertTrue(TranscriptParser.parse("").isEmpty)
    }
}
