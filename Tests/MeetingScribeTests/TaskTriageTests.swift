import XCTest
@testable import MeetingScribe

/// Tasks redesign backbone (§5B/§5C): the Triage inbox (meeting-extracted items
/// awaiting review) and the cross-project smart views (My day / This week /
/// Overdue). Pure store logic, in-memory.
@MainActor
final class TaskTriageTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskTriageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    private func newStore() async -> ActionItemStore {
        let s = ActionItemStore(); await s.awaitInitialLoad(); return s
    }

    private func extracted(_ title: String, meetingID: String = "m1") -> ActionItem {
        ActionItem(id: UUID().uuidString, meetingID: meetingID, meetingTitle: "Skio",
                   meetingDate: Date(), title: title, owner: nil, notes: nil,
                   status: .open, priority: .medium, dueDate: nil,
                   createdAt: Date(), updatedAt: Date())
    }

    func testExtractedItemIsInTriageManualIsNot() async {
        let store = await newStore()
        store.reconcileExtracted([extracted("Follow up with Maya")], for: "m1")
        _ = store.createTask(title: "A manual task")   // no meeting → not triage

        XCTAssertEqual(store.pendingTriage.map(\.title), ["Follow up with Maya"])
        XCTAssertFalse(store.pendingTriage.contains { $0.title == "A manual task" })
    }

    func testPushedTaskIsConfirmedNotTriage() async {
        let store = await newStore()
        _ = store.addTasks([.init(title: "Send recap")], fromMeetingID: "m1",
                           meetingTitle: "Skio", meetingDate: Date())
        XCTAssertTrue(store.pendingTriage.isEmpty, "pushed tasks are confirmed, never in triage")
        XCTAssertTrue(store.items.first { $0.title == "Send recap" }?.isConfirmed ?? false)
    }

    func testConfirmMovesOutOfTriageAndFilesProject() async {
        let store = await newStore()
        store.reconcileExtracted([extracted("Circulate contract")], for: "m1")
        let project = store.createProject(name: "Skio Integration")
        let id = store.pendingTriage[0].id

        store.confirm(id, projectID: project.id)

        XCTAssertTrue(store.pendingTriage.isEmpty)
        let item = store.items.first { $0.id == id }
        XCTAssertTrue(item?.isConfirmed ?? false)
        XCTAssertEqual(item?.projectID, project.id)
    }

    func testConfirmAllTriage() async {
        let store = await newStore()
        store.reconcileExtracted([extracted("a"), extracted("b"), extracted("c")], for: "m1")
        XCTAssertEqual(store.confirmAllTriage(), 3)
        XCTAssertTrue(store.pendingTriage.isEmpty)
    }

    func testReExtractKeepsConfirmedItemOutOfTriage() async {
        let store = await newStore()
        store.reconcileExtracted([extracted("Keep me")], for: "m1")
        store.confirm(store.pendingTriage[0].id)
        // Re-transcribe yields the same line again.
        store.reconcileExtracted([extracted("Keep me")], for: "m1")

        XCTAssertTrue(store.pendingTriage.isEmpty, "confirmed item must not fall back into triage")
        XCTAssertTrue(store.items.contains { $0.title == "Keep me" && $0.isConfirmed })
    }

    func testSmartViewsClassifyByDueDateAndExcludeTriage() async {
        let store = await newStore()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let over = store.createTask(title: "Overdue task")
        store.setDueDate(over.id, dueDate: yesterday)
        let due = store.createTask(title: "Today task")
        store.setDueDate(due.id, dueDate: today)

        // A triage (unconfirmed extracted) item due today must NOT pollute My day.
        var triageItem = extracted("Triage due today"); triageItem.dueDate = today
        store.reconcileExtracted([triageItem], for: "m1")

        XCTAssertEqual(store.overdueTasks.map(\.title), ["Overdue task"])
        XCTAssertEqual(store.myDayTasks.map(\.title), ["Today task"])
        XCTAssertTrue(store.thisWeekTasks.contains { $0.title == "Today task" })
        XCTAssertFalse(store.myDayTasks.contains { $0.title == "Triage due today" })
    }
}
