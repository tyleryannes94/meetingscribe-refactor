import XCTest
@testable import MeetingScribe

/// Phase 3 (P3-2 / UX-7): natural-language quick-add parsing.
final class TaskQuickAddParserTests: XCTestCase {

    func testPriorityTokens() {
        XCTAssertEqual(TaskQuickAddParser.parse("Ship deck !high").priority, .high)
        XCTAssertEqual(TaskQuickAddParser.parse("x !urgent").priority, .urgent)
        XCTAssertEqual(TaskQuickAddParser.parse("x !p1").priority, .urgent)
        XCTAssertEqual(TaskQuickAddParser.parse("x !p4").priority, .low)
        XCTAssertNil(TaskQuickAddParser.parse("no priority here").priority)
    }

    func testLabelsCollectedInOrder() {
        let p = TaskQuickAddParser.parse("Email #work #urgent-ish team")
        XCTAssertEqual(p.labelNames, ["work", "urgent-ish"])
    }

    func testTokensStrippedFromTitle() {
        let p = TaskQuickAddParser.parse("Ship deck !high #marketing")
        XCTAssertEqual(p.title, "Ship deck")
        XCTAssertEqual(p.priority, .high)
        XCTAssertEqual(p.labelNames, ["marketing"])
    }

    func testDateDetectedAndRemovedFromTitle() {
        let p = TaskQuickAddParser.parse("Call Sarah tomorrow")
        XCTAssertNotNil(p.dueDate, "a natural-language date is detected")
        XCTAssertFalse(p.title.lowercased().contains("tomorrow"), "the date phrase is stripped")
        XCTAssertTrue(p.title.contains("Call Sarah"))
    }

    func testPlainTitleUnchanged() {
        let p = TaskQuickAddParser.parse("Just a normal task")
        XCTAssertEqual(p.title, "Just a normal task")
        XCTAssertNil(p.priority)
        XCTAssertNil(p.dueDate)
        XCTAssertTrue(p.labelNames.isEmpty)
    }
}
