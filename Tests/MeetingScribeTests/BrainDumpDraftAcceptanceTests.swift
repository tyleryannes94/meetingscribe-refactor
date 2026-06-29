import XCTest
@testable import MeetingScribe

/// Accepting a `TaskDraft` should create an ActionItem in the live store and
/// flip the draft's state to `.accepted(externalID:)`. We synthesise a draft,
/// drive the same code path the review pane uses (createTask + setDueDate +
/// setDraftState), and assert the round-trip.
@MainActor
final class BrainDumpDraftAcceptanceTests: XCTestCase {

    private var tmpDir: URL!
    private var originalStorageDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrainDumpAcceptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        originalStorageDir = AppSettings.shared.storageDir
        AppSettings.shared.storageDir = tmpDir
    }

    override func tearDownWithError() throws {
        AppSettings.shared.storageDir = originalStorageDir
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testAcceptingTaskDraftCreatesActionItem() async throws {
        let actionItems = ActionItemStore()
        await actionItems.awaitInitialLoad()
        let baselineCount = actionItems.items.count

        let brainDump = BrainDumpStore()
        await brainDump.awaitInitialLoad()
        let session = brainDump.createSession(body: "Plan the refactor.")

        let draft = TaskDraft(
            title: "Outline the refactor plan",
            priorityRaw: "high",
            dueDate: Date(timeIntervalSinceReferenceDate: 1_000_000)
        )
        brainDump.appendDraft(session.id, .task(draft))

        // Simulate the review pane's accept action.
        let created = actionItems.createTask(
            title: draft.title,
            projectID: draft.suggestedProjectID,
            priority: draft.priority
        )
        if let due = draft.dueDate {
            actionItems.setDueDate(created.id, dueDate: due)
        }
        brainDump.setDraftState(session.id, draft.id, .accepted(externalID: created.id))

        XCTAssertEqual(actionItems.items.count, baselineCount + 1)
        XCTAssertEqual(actionItems.items.last?.title, "Outline the refactor plan")
        XCTAssertEqual(actionItems.items.last?.priority, .high)

        let updated = try XCTUnwrap(brainDump.session(session.id))
        if case .task(let t) = updated.drafts.first {
            if case .accepted(let id) = t.state {
                XCTAssertEqual(id, created.id, "draft carries the new action item id")
            } else {
                XCTFail("expected accepted draft state")
            }
        } else {
            XCTFail("expected task draft")
        }
    }

    func testRejectingDraftDoesNotCreateTask() async throws {
        let actionItems = ActionItemStore()
        await actionItems.awaitInitialLoad()
        let baselineCount = actionItems.items.count

        let brainDump = BrainDumpStore()
        await brainDump.awaitInitialLoad()
        let session = brainDump.createSession(body: "Reject me")
        let draft = TaskDraft(title: "Throw-away suggestion")
        brainDump.appendDraft(session.id, .task(draft))

        brainDump.setDraftState(session.id, draft.id, .rejected)

        XCTAssertEqual(actionItems.items.count, baselineCount)
        let updated = try XCTUnwrap(brainDump.session(session.id))
        if case .task(let t) = updated.drafts.first {
            XCTAssertEqual(t.state, .rejected)
        } else {
            XCTFail("expected task draft")
        }
    }
}
