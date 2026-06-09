import XCTest
@testable import MeetingScribe

/// Phase 6 (PM-20): CSV export — header shape and RFC-4180 escaping.
final class TaskExporterTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testHeaderAndRowEscaping() {
        let item = ActionItem(
            id: "1", meetingID: "", meetingTitle: "Sync", meetingDate: now,
            title: "Ship deck, with comma", owner: "Bob \"the builder\"",
            status: .open, priority: .high, projectID: "p1", labelIDs: ["l1"],
            createdAt: now, updatedAt: now)

        let csv = TaskExporter.csv([item],
                                   projectName: { _ in "Launch" },
                                   labelName: { _ in "urgent" })
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertTrue(lines[0].hasPrefix("Title,Status,Priority,Owner,Project"))
        // Comma-containing title is quoted; inner quotes are doubled.
        XCTAssertTrue(lines[1].contains("\"Ship deck, with comma\""))
        XCTAssertTrue(lines[1].contains("\"Bob \"\"the builder\"\"\""))
        XCTAssertTrue(lines[1].contains("Launch"))
        XCTAssertTrue(lines[1].contains("urgent"))
        XCTAssertTrue(lines[1].contains("High"))
    }

    func testEmptyExportIsHeaderOnly() {
        let csv = TaskExporter.csv([])
        XCTAssertEqual(csv.split(separator: "\n").count, 1)
    }
}
