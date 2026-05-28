import XCTest
@testable import MeetingScribe

/// Smoke + concurrency tests for the lock-protected `AudioCounters` used by
/// both audio recorders. Catches the basic ordering and accumulation bugs;
/// running under TSan (`swift test --sanitize=thread`) catches the races
/// the old bare-var pattern had.
final class AudioCountersTests: XCTestCase {

    func testInitialSnapshotIsZero() {
        let c = AudioCounters()
        let snap = c.snapshot()
        XCTAssertEqual(snap.samplesAppended, 0)
        XCTAssertEqual(snap.restartCount, 0)
        XCTAssertEqual(snap.currentLevel, 0)
        XCTAssertNil(snap.lastSampleAt)
        XCTAssertNil(snap.lastSoundAt)
        XCTAssertNil(snap.lastError)
    }

    func testRecordSampleUpdatesAll() {
        let c = AudioCounters()
        let t = Date()
        c.recordSample(level: 0.5, sawSound: true, at: t)
        let snap = c.snapshot()
        XCTAssertEqual(snap.samplesAppended, 1)
        XCTAssertEqual(snap.currentLevel, 0.5, accuracy: 0.0001)
        XCTAssertEqual(snap.lastSampleAt, t)
        XCTAssertEqual(snap.lastSoundAt, t)
    }

    func testSilentSampleAdvancesSampleNotSound() {
        let c = AudioCounters()
        let t1 = Date(timeIntervalSinceNow: -60)
        let t2 = Date()
        c.recordSample(level: 0.01, sawSound: false, at: t1)
        c.recordSample(level: 0.02, sawSound: false, at: t2)
        let snap = c.snapshot()
        XCTAssertEqual(snap.samplesAppended, 2)
        XCTAssertEqual(snap.lastSampleAt, t2)
        XCTAssertNil(snap.lastSoundAt, "Silence should never set lastSoundAt")
    }

    func testConcurrentMutationDoesNotCrashOrLoseUpdates() {
        // 8 producers x 1000 calls each. Lock-protected so the total has
        // to exactly equal producers * iterations. Catches a missed-write
        // bug in the unfair-lock wrapper.
        let c = AudioCounters()
        let producers = 8
        let iterations = 1000
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.audio.counters", attributes: .concurrent)
        for _ in 0..<producers {
            group.enter()
            queue.async {
                for _ in 0..<iterations {
                    c.recordSample(level: Float.random(in: 0...1),
                                   sawSound: Bool.random())
                }
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(c.snapshot().samplesAppended, producers * iterations)
    }
}
