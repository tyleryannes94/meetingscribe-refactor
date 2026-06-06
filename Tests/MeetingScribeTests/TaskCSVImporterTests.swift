import XCTest
@testable import MeetingScribe

/// Phase 6 (PM-20): CSV import — column mapping, quoted fields, value parsing,
/// and a round-trip with the exporter.
final class TaskCSVImporterTests: XCTestCase {

    func testHeaderMappedColumnsAndQuotedFields() {
        let csv = """
        Title,Status,Priority,Owner,Due
        Ship deck,In Progress,High,Bob,2026-05-23
        "Email, urgently",Done,p1,,
        """
        let rows = TaskCSVImporter.parse(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].title, "Ship deck")
        XCTAssertEqual(rows[0].status, .inProgress)
        XCTAssertEqual(rows[0].priority, .high)
        XCTAssertEqual(rows[0].owner, "Bob")
        XCTAssertNotNil(rows[0].dueDate)
        XCTAssertEqual(rows[1].title, "Email, urgently", "quoted comma preserved")
        XCTAssertEqual(rows[1].status, .completed)
        XCTAssertEqual(rows[1].priority, .urgent, "p1 → urgent")
        XCTAssertNil(rows[1].owner)
    }

    func testNoRecognizableHeaderTreatsEachLineAsTitle() {
        let rows = TaskCSVImporter.parse("Just a task\nAnother one")
        XCTAssertEqual(rows.map(\.title), ["Just a task", "Another one"])
    }

    func testExportThenImportPreservesCoreFields() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let item = ActionItem(id: "1", meetingID: "", meetingTitle: "", meetingDate: now,
                              title: "Ship, the thing", owner: "Bob",
                              status: .inProgress, priority: .high, dueDate: now,
                              createdAt: now, updatedAt: now)
        let csv = TaskExporter.csv([item])
        let rows = TaskCSVImporter.parse(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "Ship, the thing")
        XCTAssertEqual(rows[0].status, .inProgress)
        XCTAssertEqual(rows[0].priority, .high)
        XCTAssertEqual(rows[0].owner, "Bob")
        XCTAssertNotNil(rows[0].dueDate)
    }
}
