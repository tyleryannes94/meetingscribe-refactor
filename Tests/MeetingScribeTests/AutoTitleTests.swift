import XCTest
@testable import MeetingScribe

/// Guards U2-9 — ad-hoc recordings derive a readable title from the first
/// spoken line instead of staying "Ad-hoc Recording".
final class AutoTitleTests: XCTestCase {

    func testDerivesFromSpeakerPrefixedLine() {
        let t = "Me [0:05]: Let's talk about the Q3 pricing changes for Acme."
        let title = MeetingPipelineController.deriveTitle(from: t)
        // First 8 words, with the "Me [0:05]:" speaker prefix stripped.
        XCTAssertEqual(title, "Let's talk about the Q3 pricing changes for")
    }

    func testSkipsHeadingsAndBlankLines() {
        let t = "# Transcript\n\n\nThem: Hi there, thanks for joining today."
        let title = MeetingPipelineController.deriveTitle(from: t)
        XCTAssertEqual(title, "Hi there, thanks for joining today.")
    }

    func testEmptyTranscriptReturnsNil() {
        XCTAssertNil(MeetingPipelineController.deriveTitle(from: "   \n\n# Transcript\n"))
    }

    func testLongLineIsTruncated() {
        let t = "Me: " + Array(repeating: "word", count: 40).joined(separator: " ")
        let title = MeetingPipelineController.deriveTitle(from: t)
        XCTAssertNotNil(title)
        XCTAssertLessThanOrEqual(title!.count, 9 * "word ".count) // ~8 words cap
    }
}
