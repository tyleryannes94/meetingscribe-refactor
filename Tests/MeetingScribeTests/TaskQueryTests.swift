import XCTest
@testable import MeetingScribe

/// Phase 1 (BE-7): the structured query engine. Pure, deterministic tests over
/// hand-built tasks — the single filter/sort path every surface will use.
final class TaskQueryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func task(_ id: String,
                      title: String = "t",
                      status: ActionItem.Status = .open,
                      priority: ActionItem.Priority = .medium,
                      project: String? = nil,
                      owner: String? = nil,
                      due: TimeInterval? = nil,
                      labels: [String]? = nil,
                      trashed: Bool = false) -> ActionItem {
        ActionItem(id: id, meetingID: "", meetingTitle: "", meetingDate: now,
                   title: title, owner: owner, notes: nil, status: status,
                   priority: priority, dueDate: due.map { now.addingTimeInterval($0) },
                   projectID: project, labelIDs: labels,
                   deletedAt: trashed ? now : nil,
                   createdAt: now, updatedAt: now)
    }

    func testScopeProjectAndNoProject() {
        let items = [task("a", project: "p1"), task("b", project: "p2"), task("c")]
        var q = TaskQuery(scope: .project("p1"))
        XCTAssertEqual(TaskQueryEngine.evaluate(q, over: items, now: now).map(\.id), ["a"])
        q = TaskQuery(scope: .noProject)
        XCTAssertEqual(TaskQueryEngine.evaluate(q, over: items, now: now).map(\.id), ["c"])
    }

    func testTrashedAreNeverReturned() {
        let items = [task("a"), task("b", trashed: true)]
        let out = TaskQueryEngine.evaluate(TaskQuery(), over: items, now: now)
        XCTAssertEqual(out.map(\.id), ["a"])
    }

    func testStatusAndIncludeCompleted() {
        let items = [task("a", status: .open), task("b", status: .completed)]
        let excl = TaskQuery(filters: .init(includeCompleted: false))
        XCTAssertEqual(TaskQueryEngine.evaluate(excl, over: items, now: now).map(\.id), ["a"])
        let onlyDone = TaskQuery(filters: .init(statuses: [.completed]))
        XCTAssertEqual(TaskQueryEngine.evaluate(onlyDone, over: items, now: now).map(\.id), ["b"])
    }

    func testOverdueAndDueWithin() {
        let items = [
            task("late", due: -3600),                 // 1h ago → overdue
            task("soon", due: 2 * 86400),             // in 2 days
            task("far", due: 30 * 86400),             // in 30 days
            task("done", status: .completed, due: -3600), // overdue but completed
            task("none")
        ]
        let overdue = TaskQuery(filters: .init(overdue: true))
        XCTAssertEqual(TaskQueryEngine.evaluate(overdue, over: items, now: now).map(\.id), ["late"])

        let week = TaskQuery(filters: .init(dueWithinDays: 7))
        XCTAssertEqual(TaskQueryEngine.evaluate(week, over: items, now: now).map(\.id), ["soon"])
    }

    func testLabelsRequireAll() {
        let items = [
            task("a", labels: ["x", "y"]),
            task("b", labels: ["x"]),
            task("c", labels: ["y"])
        ]
        let q = TaskQuery(filters: .init(labelIDs: ["x", "y"]))
        XCTAssertEqual(TaskQueryEngine.evaluate(q, over: items, now: now).map(\.id), ["a"])
    }

    func testSearchAcrossTitleOwnerNotes() {
        let items = [task("a", title: "Email Sarah"), task("b", title: "Deck", owner: "sarah")]
        let q = TaskQuery(filters: .init(search: "sarah"))
        XCTAssertEqual(Set(TaskQueryEngine.evaluate(q, over: items, now: now).map(\.id)), ["a", "b"])
    }

    func testPrioritySortAndAscendingReversesIt() {
        let items = [
            task("low", priority: .low),
            task("urgent", priority: .urgent),
            task("med", priority: .medium)
        ]
        let desc = TaskQuery(sort: .priority)
        XCTAssertEqual(TaskQueryEngine.evaluate(desc, over: items, now: now).map(\.id),
                       ["urgent", "med", "low"])
        let asc = TaskQuery(sort: .priority, ascending: true)
        XCTAssertEqual(TaskQueryEngine.evaluate(asc, over: items, now: now).map(\.id),
                       ["low", "med", "urgent"])
    }

    func testTitleSortAndLimit() {
        let items = [task("a", title: "Charlie"), task("b", title: "alpha"), task("c", title: "Bravo")]
        let q = TaskQuery(sort: .title, ascending: true, limit: 2)
        XCTAssertEqual(TaskQueryEngine.evaluate(q, over: items, now: now).map(\.title), ["alpha", "Bravo"])
    }
}
