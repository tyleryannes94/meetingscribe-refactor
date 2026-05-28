import Foundation
import os

/// Lock-protected health counters shared between an audio recorder's
/// callback thread and the main-actor watchdog that publishes health.
///
/// Replaces the previous pattern of bare `var` properties on `MicRecorder` /
/// `SystemAudioRecorder` that were mutated from audio threads and read from
/// the main thread without synchronization (audit 5.2 / 3.2). Plain
/// primitive writes happened to work on ARM64 but were undefined behavior
/// under Swift's concurrency model and will be flagged by Swift 6's strict
/// concurrency checks.
///
/// Use:
///   let counters = AudioCounters()
///   // From audio thread:
///   counters.recordSample(level: rms, sawSound: rms > 0.003)
///   // From main thread:
///   let snapshot = counters.snapshot()
///
/// Snapshots are value types — once you have one, it's safe to inspect
/// without holding the lock.
public final class AudioCounters: @unchecked Sendable {
    public struct Snapshot: Equatable, Sendable {
        public var samplesAppended: Int
        public var lastSampleAt: Date?
        public var lastSoundAt: Date?
        public var currentLevel: Float
        public var restartCount: Int
        public var lastError: String?
    }

    private let lock = OSAllocatedUnfairLock<Snapshot>(
        initialState: .init(samplesAppended: 0,
                            lastSampleAt: nil,
                            lastSoundAt: nil,
                            currentLevel: 0,
                            restartCount: 0,
                            lastError: nil)
    )

    public init() {}

    /// Hot path — called from the audio render thread for every buffer.
    /// Cheap enough that lock contention isn't measurable in practice.
    public func recordSample(level: Float, sawSound: Bool, at time: Date = Date()) {
        lock.withLock {
            $0.samplesAppended &+= 1
            $0.lastSampleAt = time
            $0.currentLevel = level
            if sawSound { $0.lastSoundAt = time }
        }
    }

    public func incrementRestart(reason: String) {
        lock.withLock {
            $0.restartCount &+= 1
            $0.lastError = reason
        }
    }

    public func setLastError(_ message: String?) {
        lock.withLock { $0.lastError = message }
    }

    public func snapshot() -> Snapshot {
        lock.withLock { $0 }
    }
}
