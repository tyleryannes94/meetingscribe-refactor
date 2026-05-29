import XCTest
@testable import MeetingScribe

/// Locks in the ENG-B fix: the one-time tag→date-partitioned vault migration
/// must (a) actually move meetings into `meetings/yyyy/yyyy-MM/<slug>/`, and
/// (b) only mark itself complete when EVERY discovered meeting landed. The
/// original code counted failures as successes and set the completed flag
/// unconditionally, so a partial migration was marked done forever and the
/// unmoved meetings were stranded in the old layout.
@MainActor
final class VaultMigrationManagerTests: XCTestCase {

    private let migratedKey = "vault.layoutMigration.v2.completed"
    private var vault: URL!

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: migratedKey)
        vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultMig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        UserDefaults.standard.removeObject(forKey: migratedKey)
    }

    @discardableResult
    private func writeOldLayoutMeeting(tag: String, slug: String, startDate: String) throws -> URL {
        let dir = vault.appendingPathComponent(tag, isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        {"id":"\(slug)","title":"T","startDate":"\(startDate)","endDate":"\(startDate)","attendees":[]}
        """
        try json.write(to: dir.appendingPathComponent("meeting.json"), atomically: true, encoding: .utf8)
        return dir
    }

    func testFullMigrationMovesToDateLayoutAndSetsFlag() async throws {
        try writeOldLayoutMeeting(tag: "Work", slug: "standup", startDate: "2025-03-15T09:00:00.000Z")

        let mgr = VaultMigrationManager()
        await mgr.migrateLayout(vaultURL: vault)

        let dest = vault.appendingPathComponent("meetings/2025/2025-03/standup/meeting.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path),
                      "meeting should be moved to the date-partitioned layout")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: migratedKey),
                      "a fully-successful migration sets the completed flag")
        XCTAssertFalse(mgr.needsLayoutMigration)
    }

    func testPartialMigrationLeavesFlagFalseSoItRetries() async throws {
        let src = try writeOldLayoutMeeting(tag: "Work", slug: "blocked",
                                            startDate: "2025-04-10T10:00:00.000Z")
        // Pre-occupy the destination so the move throws — simulating a partial
        // failure mid-migration.
        let dest = vault.appendingPathComponent("meetings/2025/2025-04/blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("occupied".utf8).write(to: dest.appendingPathComponent("occupied"))

        let mgr = VaultMigrationManager()
        await mgr.migrateLayout(vaultURL: vault)

        XCTAssertFalse(UserDefaults.standard.bool(forKey: migratedKey),
                       "a partial migration must NOT be marked complete")
        XCTAssertTrue(mgr.needsLayoutMigration)
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.appendingPathComponent("meeting.json").path),
                      "the meeting that failed to move is still present (not silently lost)")
    }

    func testUnparseableMeetingJSONCountsAsFailureNotComplete() async throws {
        let dir = vault.appendingPathComponent("Work/garbage", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ not valid meeting json".write(to: dir.appendingPathComponent("meeting.json"),
                                             atomically: true, encoding: .utf8)

        let mgr = VaultMigrationManager()
        await mgr.migrateLayout(vaultURL: vault)

        XCTAssertFalse(UserDefaults.standard.bool(forKey: migratedKey),
                       "an unmigratable (unparseable) meeting must keep the flag false")
    }
}
