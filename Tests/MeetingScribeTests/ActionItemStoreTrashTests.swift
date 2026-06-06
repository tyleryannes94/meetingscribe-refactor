import XCTest
@testable import MeetingScribe
@testable import VaultKit

/// Phase 0 (P0-3 / P0-4 / P0-5): task soft-delete + Trash + undo, and the
/// schema-migration seam. Verifies deletes are recoverable, Trash survives a
/// reload, retention purges, and the migration engine chains/back-ups correctly.
@MainActor
final class ActionItemStoreTrashTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActionItemTrashTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    // MARK: Soft-delete

    func testDeleteMovesTaskToTrashNotGone() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let t = store.createTask(title: "Ship the deck")
        store.delete(t.id)

        XCTAssertFalse(store.items.contains { $0.id == t.id }, "deleted task leaves the live list")
        let trashed = store.trashedItems.first { $0.id == t.id }
        XCTAssertNotNil(trashed, "deleted task is in Trash")
        XCTAssertNotNil(trashed?.deletedAt, "Trash tombstone is set")
        XCTAssertTrue(trashed?.isTrashed ?? false)
    }

    func testRestoreBringsTaskBack() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let t = store.createTask(title: "Recover me")
        store.delete(t.id)
        XCTAssertTrue(store.restore(t.id))

        XCTAssertTrue(store.items.contains { $0.id == t.id }, "restored task is live again")
        XCTAssertFalse(store.trashedItems.contains { $0.id == t.id })
        XCTAssertNil(store.items.first { $0.id == t.id }?.deletedAt, "tombstone cleared on restore")
    }

    func testBulkDeleteAndBulkRestore() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let a = store.createTask(title: "a")
        let b = store.createTask(title: "b")
        let c = store.createTask(title: "c")

        let trashed = store.delete(ids: [a.id, b.id])
        XCTAssertEqual(Set(trashed), [a.id, b.id])
        XCTAssertEqual(store.items.map(\.id), [c.id], "only the unselected task stays live")
        XCTAssertEqual(store.trashedItems.count, 2)

        let restored = store.restore(ids: trashed)
        XCTAssertEqual(Set(restored), [a.id, b.id])
        XCTAssertEqual(store.trashedItems.count, 0)
        XCTAssertEqual(Set(store.items.map(\.id)), [a.id, b.id, c.id])
    }

    // MARK: Persistence

    func testTrashSurvivesReload() async {
        let store1 = ActionItemStore()
        await store1.awaitInitialLoad()
        _ = store1.createTask(title: "keep")
        let gone = store1.createTask(title: "trash me")
        store1.delete(gone.id)
        // Writes are now debounced/off-main (P0-1); force them to disk before a
        // fresh store reads the file.
        TaskPersistenceCoordinator.shared.flushNow()

        // A fresh store reads the same file: live and trashed partition correctly.
        let store2 = ActionItemStore()
        await store2.awaitInitialLoad()
        XCTAssertEqual(store2.items.map(\.title), ["keep"])
        XCTAssertEqual(store2.trashedItems.map(\.title), ["trash me"])
        XCTAssertNotNil(store2.trashedItems.first?.deletedAt)
    }

    // MARK: Purge / retention

    func testPurgeRemovesPermanently() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let t = store.createTask(title: "x")
        store.delete(t.id)
        store.purge(t.id)
        XCTAssertTrue(store.trashedItems.isEmpty)
        XCTAssertFalse(store.restore(t.id), "a purged task cannot be restored")
    }

    func testEmptyTrash() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let a = store.createTask(title: "a")
        let b = store.createTask(title: "b")
        _ = store.delete(ids: [a.id, b.id])
        store.emptyTrash()
        XCTAssertTrue(store.trashedItems.isEmpty)
    }

    func testExpiredTrashIsPurgedByRetention() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let t = store.createTask(title: "old")
        store.delete(t.id)
        // Pretend "now" is well past the retention window for the just-trashed item.
        store.purgeExpiredTrash(olderThan: 0, now: Date().addingTimeInterval(60))
        XCTAssertTrue(store.trashedItems.isEmpty, "items past retention are purged")
    }

    func testReExtractDoesNotResurrectTrashedTask() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let meetingID = "m1"
        let extracted = ActionItem(
            id: UUID().uuidString, meetingID: meetingID, meetingTitle: "Sync",
            meetingDate: Date(), title: "Follow up with Sarah", owner: nil, notes: nil,
            status: .open, priority: .medium, dueDate: nil, createdAt: Date(), updatedAt: Date())
        store.reconcileExtracted([extracted], for: meetingID)
        let created = store.items.first { $0.meetingID == meetingID }
        XCTAssertNotNil(created)
        store.delete(created!.id)

        // Re-extracting the same line must NOT bring the trashed task back.
        store.reconcileExtracted([extracted], for: meetingID)
        XCTAssertFalse(store.items.contains { $0.meetingID == meetingID },
                       "trashed extracted task is not resurrected on re-extract")
    }

    // MARK: Undoable entity deletes (P0-3)

    func testDeleteProjectUndoRestoresProjectAndLinks() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let p = store.createProject(name: "Launch")
        let t = store.createTask(title: "task", projectID: p.id)

        let undo = store.deleteProjectWithUndo(p.id)
        XCTAssertNotNil(undo)
        XCTAssertNil(store.project(id: p.id), "project removed")
        XCTAssertNil(store.items.first { $0.id == t.id }?.projectID, "task unlinked")

        undo?()
        XCTAssertNotNil(store.project(id: p.id), "project restored")
        XCTAssertEqual(store.items.first { $0.id == t.id }?.projectID, p.id, "task re-linked")
    }

    func testDeleteSectionUndoRestoresSectionAndRefilesTasks() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let p = store.createProject(name: "P")
        let s = store.createSection(projectID: p.id, name: "Backlog")
        let t = store.createTask(title: "task", projectID: p.id, sectionID: s.id)

        let undo = store.deleteSectionWithUndo(s.id)
        XCTAssertNotNil(undo)
        XCTAssertNil(store.items.first { $0.id == t.id }?.sectionID, "task pulled out of section")

        undo?()
        XCTAssertTrue(store.sections.contains { $0.id == s.id }, "section restored")
        XCTAssertEqual(store.items.first { $0.id == t.id }?.sectionID, s.id, "task re-filed")
    }

    // MARK: Project completion (VD-7)

    func testProjectCompletionCounts() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let p = store.createProject(name: "P")
        let a = store.createTask(title: "a", projectID: p.id)
        let b = store.createTask(title: "b", projectID: p.id)
        _ = store.createTask(title: "c", projectID: p.id)
        store.setStatus(a.id, status: .completed)
        store.setStatus(b.id, status: .completed)
        let c = store.completion(forProject: p.id)
        XCTAssertEqual(c.done, 2)
        XCTAssertEqual(c.total, 3)
    }

    // MARK: Completion timestamp (P2-4)

    func testCompletedAtSetKeptAndClearedOnReopen() async {
        let store = ActionItemStore()
        await store.awaitInitialLoad()
        let t = store.createTask(title: "x")
        XCTAssertNil(store.items.first { $0.id == t.id }?.completedAt)

        store.setStatus(t.id, status: .completed)
        let stamp = store.items.first { $0.id == t.id }?.completedAt
        XCTAssertNotNil(stamp, "completing stamps completedAt")

        // Re-completing keeps the original timestamp (idempotent).
        store.setStatus(t.id, status: .completed)
        XCTAssertEqual(store.items.first { $0.id == t.id }?.completedAt, stamp)

        // Reopening clears it.
        store.setStatus(t.id, status: .open)
        XCTAssertNil(store.items.first { $0.id == t.id }?.completedAt)
    }

    // MARK: Off-main coalesced writes (P0-1)

    func testCoordinatorCoalescesToLatestBytesOnFlush() {
        let url = tempRoot.appendingPathComponent("coord_test.json")
        // Long debounce so neither write lands before the explicit flush.
        let coord = TaskPersistenceCoordinator(debounce: 30)
        coord.write(Data("first".utf8), to: url)
        coord.write(Data("second".utf8), to: url)
        coord.flushNow()
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), "second",
                       "only the latest coalesced bytes for a path are written")
    }

    // MARK: Migration seam

    func testMigrationChainsStepsInOrder() {
        let steps: [Int: ([Int]) -> [Int]] = [
            1: { $0 + [10] },
            2: { $0 + [20] }
        ]
        let out = TaskSchemaMigrations.migrate([0], from: 1, to: 3, steps: steps)
        XCTAssertEqual(out, [0, 10, 20], "steps 1→2 and 2→3 apply in order")
    }

    func testMigrationIsIdentityWhenVersionsMatch() {
        let out = TaskSchemaMigrations.migrate([1, 2, 3], from: 2, to: 2, steps: [:])
        XCTAssertEqual(out, [1, 2, 3])
    }

    func testBackupBeforeMigrationCopiesFileOnce() throws {
        let url = tempRoot.appendingPathComponent("action_items.json")
        try Data("{}".utf8).write(to: url)
        TaskSchemaMigrations.backupBeforeMigration(url, from: 1, to: 2)
        let backup = tempRoot.appendingPathComponent("action_items.v1-pre2.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "a pre-migration backup is written")
        // Idempotent: a second call must not throw or overwrite.
        TaskSchemaMigrations.backupBeforeMigration(url, from: 1, to: 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }
}
