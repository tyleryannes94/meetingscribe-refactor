import XCTest
@testable import MeetingScribe

/// Pure-function tests for `SyncIndex` — the file enumeration / exclusion
/// rules + the relative-path → absolute-URL resolver. No URLSession; those
/// paths are exercised by integration testing on a real Mac.
final class SyncIndexTests: XCTestCase {

    private var vaultRoot: URL!

    override func setUpWithError() throws {
        vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vaultRoot)
    }

    private func write(_ contents: String, at relative: String,
                       mtime: Date? = nil) throws -> URL {
        let url = vaultRoot.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url, options: .atomic)
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime],
                                                  ofItemAtPath: url.path)
        }
        return url
    }

    // MARK: - Exclusion rules

    func testExcludesRebuildableCachesAndAuth() {
        XCTAssertTrue(SyncIndex.isExcluded("accounts.json"))
        XCTAssertTrue(SyncIndex.isExcluded("sync-peers.json"))
        XCTAssertTrue(SyncIndex.isExcluded(".meeting-index.json"))
        XCTAssertTrue(SyncIndex.isExcluded("_remote/work-macbook/foo.json"))
        XCTAssertTrue(SyncIndex.isExcluded("_inbox/processed/.processed_ids.json"))
        XCTAssertFalse(SyncIndex.isExcluded("meetings/2026/2026-06/q3-planning/notes.md"))
        XCTAssertFalse(SyncIndex.isExcluded("people/horst/person.json"))
    }

    func testRejectsParentTraversal() {
        // Any `..` segment must be refused — a peer can't ask us to read
        // outside the vault root.
        XCTAssertTrue(SyncIndex.isExcluded("../escape.json"))
        XCTAssertTrue(SyncIndex.isExcluded("meetings/../../../etc/passwd"))
        XCTAssertTrue(SyncIndex.isExcluded("ok/..hidden.json"),
                      "any `..` substring is refused — safer than parsing")
    }

    // MARK: - Enumeration

    func testEnumeratesOnlySyncableFiles() throws {
        _ = try write("# notes", at: "meetings/2026/2026-06/q3/notes.md")
        _ = try write("{}", at: "meetings/2026/2026-06/q3/meeting.json")
        _ = try write("{}", at: "people/horst/person.json")
        // Excluded:
        _ = try write("{}", at: "accounts.json")
        _ = try write("{}", at: "sync-peers.json")
        _ = try write("{}", at: "_remote/work-macbook/oldfile.json")
        _ = try write("{}", at: ".meeting-index.json")

        let entries = SyncIndex.entries(under: vaultRoot)
        let paths = Set(entries.map(\.path))
        XCTAssertTrue(paths.contains("meetings/2026/2026-06/q3/notes.md"))
        XCTAssertTrue(paths.contains("meetings/2026/2026-06/q3/meeting.json"))
        XCTAssertTrue(paths.contains("people/horst/person.json"))
        XCTAssertFalse(paths.contains("accounts.json"))
        XCTAssertFalse(paths.contains("sync-peers.json"))
        XCTAssertFalse(paths.contains(".meeting-index.json"))
        XCTAssertFalse(paths.contains { $0.hasPrefix("_remote/") })
    }

    func testSinceFilterStripsOlderEntries() throws {
        let old = Date().addingTimeInterval(-3600)   // 1h ago
        let recent = Date().addingTimeInterval(-60)  // 1m ago
        _ = try write("old", at: "meetings/a/notes.md", mtime: old)
        _ = try write("recent", at: "meetings/b/notes.md", mtime: recent)

        let cutoff = Date().addingTimeInterval(-300) // 5m ago
        let entries = SyncIndex.entries(under: vaultRoot, since: cutoff)
        let paths = Set(entries.map(\.path))
        XCTAssertTrue(paths.contains("meetings/b/notes.md"))
        XCTAssertFalse(paths.contains("meetings/a/notes.md"))
    }

    func testEntryCarriesMtimeAndSize() throws {
        let target = Date().addingTimeInterval(-120)
        let body = "some body content"
        _ = try write(body, at: "meetings/x/notes.md", mtime: target)

        let entries = SyncIndex.entries(under: vaultRoot)
        let entry = entries.first { $0.path == "meetings/x/notes.md" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.size, body.utf8.count)
        XCTAssertEqual(entry!.mtime.timeIntervalSince1970,
                       target.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Path resolution

    func testAbsoluteURLResolvesNormally() {
        let url = SyncIndex.absoluteURL(forRelative: "meetings/2026/foo/notes.md",
                                        under: vaultRoot)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.path.hasPrefix(vaultRoot.standardized.path))
        XCTAssertTrue(url!.path.hasSuffix("/meetings/2026/foo/notes.md"))
    }

    func testAbsoluteURLRefusesExcludedPaths() {
        XCTAssertNil(SyncIndex.absoluteURL(forRelative: "accounts.json", under: vaultRoot))
        XCTAssertNil(SyncIndex.absoluteURL(forRelative: "_remote/work/x.json",
                                            under: vaultRoot))
    }

    func testAbsoluteURLRefusesEscapes() {
        XCTAssertNil(SyncIndex.absoluteURL(forRelative: "../escape.json", under: vaultRoot))
        XCTAssertNil(SyncIndex.absoluteURL(forRelative: "meetings/../../../etc/passwd",
                                            under: vaultRoot))
    }

    func testAbsoluteURLRefusesEmpty() {
        XCTAssertNil(SyncIndex.absoluteURL(forRelative: "", under: vaultRoot))
        XCTAssertNil(SyncIndex.absoluteURL(forRelative: "/", under: vaultRoot))
    }
}
