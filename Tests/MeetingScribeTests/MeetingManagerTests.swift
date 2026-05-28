import XCTest
@testable import MeetingScribe

/// Basic construction + initial-state checks for `MeetingManager`.
///
/// `MeetingManager.init()` only wires up callbacks (no disk I/O, no system
/// permission prompts), so it's safe to spin one up in a unit test. We point
/// `storageDir` at a throwaway temp dir in `setUp` so nothing here can touch a
/// developer's real meeting notes.
@available(macOS 14.0, *)
@MainActor
final class MeetingManagerTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingScribeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    func testManagerStartsIdle() {
        let manager = MeetingManager()
        guard case .idle = manager.state else {
            return XCTFail("Expected a freshly-constructed manager to be idle, got \(manager.state)")
        }
        XCTAssertNil(manager.activeMeeting, "No meeting should be active before recording starts.")
        XCTAssertFalse(manager.isSyncingTasks, "Task sync should be idle at startup.")
    }

    func testQuickNotesStartIdle() {
        let manager = MeetingManager()
        XCTAssertEqual(manager.quickRecordState, .idle,
                       "Quick-note recording should be idle before any capture.")
    }

    func testManagersOwnIndependentStores() {
        // Each manager owns its own store/action-item graph — constructing a
        // second one must not alias the first's state.
        let a = MeetingManager()
        let b = MeetingManager()
        XCTAssertFalse(a.store === b.store)
        XCTAssertFalse(a.actionItems === b.actionItems)
    }
}
