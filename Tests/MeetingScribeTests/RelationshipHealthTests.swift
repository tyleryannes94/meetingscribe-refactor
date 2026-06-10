import XCTest
@testable import VaultKit

final class RelationshipHealthTests: XCTestCase {
    // On cadence, well-logged, regular → thriving.
    func testCurrentAndConsistentIsThriving() {
        let h = RelationshipHealth(daysSinceLast: 3, cadenceDays: 7, encounterCount: 10, medianGapDays: 6)
        XCTAssertGreaterThanOrEqual(h.score, 75)
        XCTAssertEqual(h.band, .thriving)
    }

    // Way past cadence with little history → overdue.
    func testLongSilenceIsOverdue() {
        let h = RelationshipHealth(daysSinceLast: 60, cadenceDays: 7, encounterCount: 1, medianGapDays: 0)
        XCTAssertLessThan(h.score, 25)
        XCTAssertEqual(h.band, .overdue)
    }

    // Recency dominates: same person, more days silent → never increases score.
    func testRecencyIsMonotonic() {
        let fresh = RelationshipHealth(daysSinceLast: 2, cadenceDays: 14, encounterCount: 5, medianGapDays: 12)
        let stale = RelationshipHealth(daysSinceLast: 40, cadenceDays: 14, encounterCount: 5, medianGapDays: 12)
        XCTAssertGreaterThan(fresh.score, stale.score)
    }

    // Score is always clamped to 0...100.
    func testScoreClamped() {
        let hi = RelationshipHealth(daysSinceLast: 0, cadenceDays: 30, encounterCount: 999, medianGapDays: 1)
        let lo = RelationshipHealth(daysSinceLast: 9999, cadenceDays: 1, encounterCount: 0, medianGapDays: 0)
        XCTAssert((0...100).contains(hi.score))
        XCTAssert((0...100).contains(lo.score))
    }

    // Band thresholds line up with the documented bins.
    func testBandThresholds() {
        XCTAssertEqual(RelationshipHealth.Band(score: 80), .thriving)
        XCTAssertEqual(RelationshipHealth.Band(score: 50), .steady)
        XCTAssertEqual(RelationshipHealth.Band(score: 25), .drifting)
        XCTAssertEqual(RelationshipHealth.Band(score: 0), .overdue)
    }
}
