import XCTest
@testable import MeetingScribe

/// Phase 2 (P2-5): recurring tasks — the rule math and the spawn-on-completion
/// behavior in the store.
@MainActor
final class RecurrenceTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecurrenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    func testRuleRollsDatesForward() {
        let cal = Calendar(identifier: .gregorian)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(RecurrenceRule(frequency: .daily).next(after: base, calendar: cal),
                       cal.date(byAdding: .day, value: 1, to: base))
        XCTAssertEqual(RecurrenceRule(frequency: .weekly).next(after: base, calendar: cal),
                       cal.date(byAdding: .weekOfYear, value: 1, to: base))
        XCTAssertEqual(RecurrenceRule(frequency: .monthly, interval: 2).next(after: base, calendar: cal),
                       cal.date(byAdding: .month, value: 2, to: base))
    }

    func testCompletingRecurringSpawnsNextOpenInstance() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let t = store.createTask(title: "Weekly report")
        let due = Date(timeIntervalSince1970: 1_700_000_000)
        store.setDueDate(t.id, dueDate: due)
        store.setRecurrence(t.id, RecurrenceRule(frequency: .weekly))
        let before = store.items.count

        store.setStatus(t.id, status: .completed)

        // The completed instance stays as history.
        XCTAssertEqual(store.items.first { $0.id == t.id }?.status, .completed)
        // Exactly one new instance was created.
        XCTAssertEqual(store.items.count, before + 1)

        let next = store.items.first { $0.status == .open && $0.title == "Weekly report" }
        XCTAssertNotNil(next, "a fresh open instance is spawned")
        XCTAssertEqual(next?.recurrence?.frequency, .weekly, "recurrence carries forward")
        XCTAssertEqual(next?.seriesID, t.id, "instances share a series id")
        XCTAssertEqual(next?.dueDate,
                       Calendar.current.date(byAdding: .weekOfYear, value: 1, to: due),
                       "due date rolls forward one week")

        // Re-completing the already-completed original must not spawn again.
        store.setStatus(t.id, status: .completed)
        XCTAssertEqual(store.items.filter { $0.title == "Weekly report" }.count, 2)
    }

    func testNonRecurringTaskDoesNotSpawn() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let t = store.createTask(title: "One-off")
        let before = store.items.count
        store.setStatus(t.id, status: .completed)
        XCTAssertEqual(store.items.count, before, "a non-recurring task spawns nothing")
    }
}
