import XCTest
@testable import MeetingScribe

/// Cross-tab "Push to Tasks": creating meeting-linked tasks from a call's notes
/// / action items, deduped, and — critically — surviving a re-transcribe
/// (reconcileExtracted must not delete user-pushed tasks).
@MainActor
final class PushToTasksTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PushToTasksTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    private func newStore() async -> ActionItemStore {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        return store
    }

    func testAddTasksCreatesMeetingLinkedTasks() async {
        let store = await newStore()
        let created = store.addTasks(
            [.init(title: "Send recap"), .init(title: "Book follow-up", owner: "Me")],
            fromMeetingID: "m1", meetingTitle: "Skio Sync", meetingDate: Date())

        XCTAssertEqual(created.count, 2)
        XCTAssertTrue(store.items.contains { $0.title == "Send recap" && $0.meetingID == "m1" })
        XCTAssertEqual(created.first { $0.title == "Book follow-up" }?.owner, "Me")
        XCTAssertTrue(created.allSatisfy { $0.source == ActionItemStore.pushedSource })
        XCTAssertTrue(created.allSatisfy { $0.status == .open && !$0.isManual })
    }

    func testAddTasksDedupesByNormalizedTitle() async {
        let store = await newStore()
        _ = store.addTasks([.init(title: "Send recap")], fromMeetingID: "m1",
                           meetingTitle: "Skio", meetingDate: Date())
        // Same title (different case/whitespace) and a within-batch dup.
        let second = store.addTasks(
            [.init(title: "  send RECAP "), .init(title: "New thing"), .init(title: "New thing")],
            fromMeetingID: "m1", meetingTitle: "Skio", meetingDate: Date())

        XCTAssertEqual(second.count, 1, "only the genuinely new, unique task is created")
        XCTAssertEqual(store.items.filter { $0.meetingID == "m1" }.count, 2)
    }

    func testReExtractDoesNotDeletePushedTasks() async {
        let store = await newStore()
        _ = store.addTasks([.init(title: "Pushed by me")], fromMeetingID: "m1",
                           meetingTitle: "Skio", meetingDate: Date())
        // Simulate a re-transcribe producing a different extracted set.
        let extracted = ActionItem(
            id: UUID().uuidString, meetingID: "m1", meetingTitle: "Skio",
            meetingDate: Date(), title: "Extracted action", owner: nil, notes: nil,
            status: .open, priority: .medium, dueDate: nil,
            notionPageID: nil, notionURL: nil, delegated: nil,
            createdAt: Date(), updatedAt: Date())
        store.reconcileExtracted([extracted], for: "m1")

        XCTAssertTrue(store.items.contains { $0.title == "Pushed by me" },
                      "user-pushed task must survive a re-extract")
        XCTAssertTrue(store.items.contains { $0.title == "Extracted action" })
    }

    func testPushSkipsTrashedSignature() async {
        let store = await newStore()
        let created = store.addTasks([.init(title: "Send recap")], fromMeetingID: "m1",
                                     meetingTitle: "Skio", meetingDate: Date())
        store.delete(created[0].id)   // user trashed it
        let again = store.addTasks([.init(title: "Send recap")], fromMeetingID: "m1",
                                   meetingTitle: "Skio", meetingDate: Date())
        XCTAssertTrue(again.isEmpty, "a trashed line should not be resurrected by re-push")
    }

    func testDraftsFromNotesStripsMarkdownPrefixes() {
        let notes = """
        - [ ] Email the deck
        * Schedule kickoff
        1. Confirm budget
        ## Section header
        Plain line

        """
        let drafts = ActionItemStore.draftsFromNotes(notes)
        XCTAssertEqual(drafts.map(\.title),
                       ["Email the deck", "Schedule kickoff", "Confirm budget",
                        "Section header", "Plain line"])
    }
}
