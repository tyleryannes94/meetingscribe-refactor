import XCTest
@testable import MeetingScribe

/// Scoped message analysis (#3 "select what to analyze"): the date-window math
/// that floors the stats/snippet SQL queries. Pure logic — no chat.db needed.
final class MessageWindowTests: XCTestCase {
    typealias Window = MessagesAnalyzer.MessageWindow

    private func ns(_ d: Date) -> Int64 { Int64(d.timeIntervalSinceReferenceDate * 1_000_000_000) }

    func testAllTimeIsUnbounded() {
        let (lower, upper) = Window.allTime.appleDateBounds()
        XCTAssertNil(lower)
        XCTAssertNil(upper)
    }

    func testLastDaysFloorsAtNowMinusN() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000_000)
        let (lower, upper) = Window.lastDays(30).appleDateBounds(now: now)
        XCTAssertEqual(lower, ns(now.addingTimeInterval(-30 * 86400)))
        XCTAssertNil(upper)
    }

    func testSinceSetsLowerBoundOnly() {
        let d = Date(timeIntervalSinceReferenceDate: 500_000_000)
        let (lower, upper) = Window.since(d).appleDateBounds()
        XCTAssertEqual(lower, ns(d))
        XCTAssertNil(upper)
    }

    func testBetweenOrdersBounds() {
        let a = Date(timeIntervalSinceReferenceDate: 200)
        let b = Date(timeIntervalSinceReferenceDate: 100)
        let (lower, upper) = Window.between(a, b).appleDateBounds()  // deliberately reversed
        XCTAssertEqual(lower, ns(b))   // min
        XCTAssertEqual(upper, ns(a))   // max
    }

    func testPresetsAndLabels() {
        XCTAssertEqual(Window.presets, [.allTime, .lastDays(30), .lastDays(90), .lastDays(365)])
        XCTAssertEqual(Window.lastDays(90).label, "Last 90 days")
        XCTAssertEqual(Window.allTime.label, "All time")
    }
}
