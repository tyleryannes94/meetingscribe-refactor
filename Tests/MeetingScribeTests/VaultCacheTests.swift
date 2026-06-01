import XCTest
@testable import MeetingScribe

/// VaultCache round-trip, schema-version gating, TTL expiry, and
/// corruption-tolerance (V5 PC-3 / PS-8 stability floor).
final class VaultCacheTests: XCTestCase {

    private struct Sample: Codable, Equatable {
        var id: String
        var count: Int
    }

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    func testRoundTrip() {
        let value = Sample(id: "a", count: 3)
        VaultCache.save(value, name: "sample", version: 1)
        let loaded = VaultCache.load(Sample.self, name: "sample", version: 1)
        XCTAssertEqual(loaded, value)
    }

    func testMissingReturnsNil() {
        XCTAssertNil(VaultCache.load(Sample.self, name: "absent", version: 1))
    }

    func testVersionMismatchReturnsNil() {
        VaultCache.save(Sample(id: "a", count: 3), name: "sample", version: 1)
        XCTAssertNil(VaultCache.load(Sample.self, name: "sample", version: 2))
    }

    func testTTLExpiryReturnsNil() {
        let saved = Date()
        VaultCache.save(Sample(id: "a", count: 3), name: "sample", version: 1, now: saved)
        // 10s later with a 5s maxAge → expired.
        let later = saved.addingTimeInterval(10)
        XCTAssertNil(VaultCache.load(Sample.self, name: "sample", version: 1, maxAge: 5, now: later))
        // Within maxAge → still valid.
        let soon = saved.addingTimeInterval(2)
        XCTAssertNotNil(VaultCache.load(Sample.self, name: "sample", version: 1, maxAge: 5, now: soon))
    }

    func testCorruptFileReturnsNil() throws {
        let url = VaultCache.cacheRoot().appendingPathComponent("sample.json")
        try FileManager.default.createDirectory(at: VaultCache.cacheRoot(), withIntermediateDirectories: true)
        try Data("{not valid json".utf8).write(to: url)
        XCTAssertNil(VaultCache.load(Sample.self, name: "sample", version: 1))
    }

    func testInvalidate() {
        VaultCache.save(Sample(id: "a", count: 3), name: "sample", version: 1)
        VaultCache.invalidate(name: "sample")
        XCTAssertNil(VaultCache.load(Sample.self, name: "sample", version: 1))
    }
}
