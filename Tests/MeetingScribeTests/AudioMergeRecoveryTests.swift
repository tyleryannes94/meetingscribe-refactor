import XCTest
import AVFoundation
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

    /// Two real AAC segments must concatenate WITHOUT crashing. The old merger
    /// called `requestMediaDataWhenReady` once per segment; the second call
    /// threw an uncaught AVFoundation NSException → SIGABRT, so this exact path
    /// (the normal end-of-recording finalize for any 2+ segment call) aborted
    /// the app. Generates silence so it doesn't depend on fixtures.
    func testMergeTwoRealSegmentsConcatenatesWithoutCrashing() async throws {
        let dir = try makeMeetingDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s1 = dir.appendingPathComponent("audio/mic-002.m4a")
        let s2 = dir.appendingPathComponent("audio/mic-003.m4a")
        try Self.writeSilentAAC(to: s1, seconds: 0.6)
        try Self.writeSilentAAC(to: s2, seconds: 0.6)

        try await PassthroughAudioMerger.merge(segments: [s1, s2],
                                               into: dir.appendingPathComponent("mic.m4a"))

        let out = dir.appendingPathComponent("mic.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        let dur = try await AVURLAsset(url: out).load(.duration).seconds
        // ~1.2s if both segments made it; ~0.6s would mean the second was dropped.
        XCTAssertGreaterThan(dur, 1.0, "both segments should be present in the merge")
    }

    /// Write `seconds` of AAC-encoded silence to `url` as a valid `.m4a`.
    private static func writeSilentAAC(to url: URL, seconds: Double) throws {
        let sampleRate = 44_100.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: frames) else {
            throw NSError(domain: "test", code: 1)
        }
        buffer.frameLength = frames   // zero-filled → silence
        try file.write(from: buffer)
    }
}
