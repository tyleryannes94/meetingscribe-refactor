import XCTest
@testable import MeetingScribe

/// C2-4 — the distress pre-flight guard. A miss (failing to catch a real
/// crisis signal) is the failure mode we care about, so these tests bias
/// toward confirming detection, plus a few guards against obvious false
/// positives that would erode trust.
final class DistressFilterTests: XCTestCase {

    func testSelfHarmPhrasesDetected() {
        for s in ["I just want to die", "sometimes I think about killing myself",
                  "I feel suicidal", "I'd be better off dead", "I can't go on like this"] {
            XCTAssertEqual(DistressFilter.scan(s), .selfHarm, "missed: \(s)")
        }
    }

    func testAbusePhrasesDetected() {
        for s in ["he hits me when he's angry", "I'm afraid of him",
                  "she threatened to take the kids", "he won't let me leave"] {
            XCTAssertEqual(DistressFilter.scan(s), .abuse, "missed: \(s)")
        }
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(DistressFilter.scan("I WANT TO DIE"), .selfHarm)
    }

    func testNeutralTextIsNotFlagged() {
        for s in ["We grabbed coffee and caught up about work",
                  "Talked about the kids' soccer schedule",
                  "He was a little quiet but we had a nice dinner",
                  "I saw my therapist today and felt better"] {
            XCTAssertNil(DistressFilter.scan(s), "false positive: \(s)")
        }
    }

    func testSelfHarmTakesPrecedenceOverAbuse() {
        // When both signals appear, self-harm resources surface first.
        let s = "he hits me and honestly I want to die"
        XCTAssertEqual(DistressFilter.scan(s), .selfHarm)
    }

    func testSupportiveMessageCarriesResourcesAndReassurance() {
        let selfHarm = DistressFilter.supportiveMessage(for: .selfHarm)
        XCTAssertTrue(selfHarm.contains("988"))
        XCTAssertTrue(selfHarm.contains("not sent for AI analysis"))

        let abuse = DistressFilter.supportiveMessage(for: .abuse)
        XCTAssertTrue(abuse.contains("1-800-799-7233"))
    }
}
