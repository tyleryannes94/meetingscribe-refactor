import XCTest
@testable import MeetingScribe
@testable import VaultKit

/// Phase 1 (BE-5): the append-only task change log. Verifies events are
/// recorded with a monotonic Lamport clock, bounded in memory, and survive a
/// reload. Tests use fresh `TaskChangeLog` instances (not the singleton) so they
/// are isolated.
@MainActor
final class TaskChangeLogTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskChangeLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
        UserDefaults.standard.removeObject(forKey: "tasks.lamport")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
        UserDefaults.standard.removeObject(forKey: "tasks.lamport")
    }

    func testRecordBumpsLamportMonotonically() async {
        let log = TaskChangeLog()
        await log.awaitInitialLoad()
        let e1 = log.record(.create, entity: .task, id: "a", summary: "created")
        let e2 = log.record(.update, entity: .task, id: "a", summary: "updated")
        let e3 = log.record(.delete, entity: .task, id: "a", summary: "trashed")
        XCTAssertEqual(e2.lamport, e1.lamport + 1)
        XCTAssertEqual(e3.lamport, e2.lamport + 1)
        XCTAssertEqual(log.recent.suffix(3).map(\.op), [.create, .update, .delete])
        XCTAssertTrue(log.recent.suffix(3).allSatisfy { $0.entity == .task })
        XCTAssertFalse(e1.deviceID.isEmpty, "a stable device id is stamped")
    }

    func testEventsPersistAndReload() async {
        let log1 = TaskChangeLog()
        await log1.awaitInitialLoad()
        log1.record(.create, entity: .task, id: "persist-me", summary: "x")
        TaskPersistenceCoordinator.shared.flushNow()

        let log2 = TaskChangeLog()
        await log2.awaitInitialLoad()
        XCTAssertTrue(log2.recent.contains { $0.entityID == "persist-me" },
                      "recorded events survive a reload")
    }

    func testInMemoryTailIsBounded() async {
        let log = TaskChangeLog()
        await log.awaitInitialLoad()
        for i in 0..<600 {
            log.record(.update, entity: .task, id: "t\(i)", summary: "u")
        }
        XCTAssertLessThanOrEqual(log.recent.count, 500, "the in-memory tail is capped")
        XCTAssertEqual(log.recent.last?.entityID, "t599", "newest events are kept")
    }
}
