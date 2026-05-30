import XCTest
@testable import MeetingScribe
@testable import VaultKit

/// Tests for MeetingStore's index, O(1) directory cache, and tolerance of
/// the legacy raw-payload meeting.json shape.
final class MeetingStoreTests: XCTestCase {

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

    private func makeMeeting(id: String = UUID().uuidString, minutesAgo: Int = 60) -> Meeting {
        let start = Date().addingTimeInterval(-Double(minutesAgo) * 60)
        return Meeting(id: id, title: "Test \(id.prefix(4))",
                       startDate: start,
                       endDate: start.addingTimeInterval(1800),
                       attendees: [], notes: nil, location: nil,
                       conferenceURL: nil, calendarName: nil, seriesID: nil,
                       userDescription: nil, userTitle: nil,
                       isImpromptu: true, isImported: false, segmentCount: 0)
    }

    func testWritingThenListingReadsBackThroughIndex() throws {
        let store = MeetingStore()
        let a = makeMeeting(id: "a", minutesAgo: 60)
        let b = makeMeeting(id: "b", minutesAgo: 30)
        try store.writeMeeting(a, primaryTag: nil)
        try store.writeMeeting(b, primaryTag: nil)
        let list = store.listPastMeetings()
        XCTAssertEqual(list.map(\.id), ["b", "a"], "Newer meetings come first")
    }

    func testDirectoryLookupIsO1AfterWrite() throws {
        let store = MeetingStore()
        let m = makeMeeting()
        try store.writeMeeting(m, primaryTag: nil)
        let dir = store.directory(for: m, primaryTag: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        // relativeFolderPath should be persisted so a fresh meeting object
        // (no cache warm-up) still resolves O(1).
        let reread = store.readMeeting(at: dir)
        XCTAssertNotNil(reread?.relativeFolderPath, "Path should be persisted on write")
    }

    func testReadsLegacyRawMeetingJSON() throws {
        // Simulate an older build that wrote meeting.json as a raw payload
        // (no SchemaEnvelope). SchemaEnvelope.decode should tolerate it.
        let dir = tempRoot.appendingPathComponent("Untagged/old-meeting")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let raw = """
        {
          "id":"legacy",
          "title":"Legacy",
          "startDate":"2025-01-01T00:00:00Z",
          "endDate":"2025-01-01T01:00:00Z",
          "attendees":[]
        }
        """
        try raw.write(to: dir.appendingPathComponent("meeting.json"), atomically: true, encoding: .utf8)
        let store = MeetingStore()
        let list = store.listPastMeetings(forceRescan: true)
        XCTAssertTrue(list.contains(where: { $0.id == "legacy" }))
    }

    func testCleanupOrphanedChunksRemovesStaleChunksDir() throws {
        let store = MeetingStore()
        let m = makeMeeting()
        try store.writeMeeting(m, primaryTag: nil)
        let dir = store.directory(for: m, primaryTag: nil)
        let chunks = dir.appendingPathComponent("chunks")
        try FileManager.default.createDirectory(at: chunks, withIntermediateDirectories: true)
        let staleFile = chunks.appendingPathComponent("mic-0001.wav")
        FileManager.default.createFile(atPath: staleFile.path, contents: Data())
        // Backdate to 48h ago.
        let old = Date().addingTimeInterval(-48 * 3600)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: staleFile.path)
        store.cleanupOrphanedChunks(olderThan: 24 * 3600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chunks.path))
    }
}
