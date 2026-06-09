import XCTest
@testable import MeetingScribe

/// Regression for crash-recovery audio merge. `mergeSegments` used to
/// reconstruct candidate filenames `mic-001..mic-{totalSegments}` and merge
/// only those, so any segment whose index fell OUTSIDE that range was silently
/// dropped. A crash mid-recording can leave a non-contiguous run that doesn't
/// start at 001 (e.g. only `mic-003.m4a` survives, often the bulk of the call) —
/// "Recover audio from folder" then transcribed nothing. The fix globs the
/// segments actually on disk instead. These tests use the single-segment copy
/// path so they don't need a real AAC stream to mux.
final class AudioMergeRecoveryTests: XCTestCase {

    private func makeMeetingDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("merge-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("audio", isDirectory: true),
            withIntermediateDirectories: true)
        return dir
    }

    /// A lone surviving segment at an index ABOVE the reported count must still
    /// be merged (the precise shape of the reported bug: mic-003 + count=2).
    func testHighIndexLoneSegmentIsRecovered() async throws {
        let dir = try makeMeetingDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = Data("the-real-recording".utf8)
        try bytes.write(to: dir.appendingPathComponent("audio/mic-003.m4a"))

        // totalSegments is the (stale/miscounted) value the old code keyed off.
        let merged = try await AudioRecorder.mergeSegments(in: dir, totalSegments: 2)

        let micOut = dir.appendingPathComponent("mic.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: micOut.path),
                      "mic-003 must be recovered even though its index exceeds totalSegments")
        XCTAssertEqual(try Data(contentsOf: micOut), bytes)
        XCTAssertEqual(merged.mic?.lastPathComponent, "mic.m4a")
        XCTAssertNil(merged.system, "no system segments present → no system output")
    }

    /// A non-1-based segment (mic-002 with no mic-001) is still recovered.
    func testNonContiguousStartIsRecovered() async throws {
        let dir = try makeMeetingDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = Data("segment-two".utf8)
        try bytes.write(to: dir.appendingPathComponent("audio/system-002.m4a"))

        let merged = try await AudioRecorder.mergeSegments(in: dir, totalSegments: 1)

        let sysOut = dir.appendingPathComponent("system.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sysOut.path))
        XCTAssertEqual(try Data(contentsOf: sysOut), bytes)
        XCTAssertEqual(merged.system?.lastPathComponent, "system.m4a")
        XCTAssertNil(merged.mic)
    }
}
