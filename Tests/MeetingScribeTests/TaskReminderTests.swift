import XCTest
@testable import MeetingScribe

/// Phase 2 (P2-1): the pure selection behind due-date reminders. The
/// notification-center scheduling itself isn't unit-testable, but the decision
/// of *which* tasks get reminders is — and that's where the logic lives.
final class TaskReminderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func task(_ id: String, _ status: ActionItem.Status, due: TimeInterval?) -> ActionItem {
        ActionItem(id: id, meetingID: "", meetingTitle: "", meetingDate: now,
                   title: id, status: status, priority: .medium,
                   dueDate: due.map { now.addingTimeInterval($0) },
                   createdAt: now, updatedAt: now)
    }

    func testSelectsOnlyIncompleteFutureDueSortedSoonestFirst() {
        let items = [
            task("past", .open, due: -3600),       // overdue → can't schedule in the past
            task("later", .open, due: 7200),
            task("soon", .open, due: 3600),
            task("done", .completed, due: 3600),   // completed → excluded
            task("none", .open, due: nil)          // no due date → excluded
        ]
        let out = NotificationManager.tasksNeedingDueReminder(items, now: now)
        XCTAssertEqual(out.map(\.id), ["soon", "later"], "soonest future due first; past/done/no-due excluded")
    }

    func testRespectsLimit() {
        let items = (0..<10).map { task("t\($0)", .open, due: Double(($0 + 1) * 3600)) }
        let out = NotificationManager.tasksNeedingDueReminder(items, now: now, limit: 3)
        XCTAssertEqual(out.map(\.id), ["t0", "t1", "t2"], "capped to the soonest N")
    }
}
