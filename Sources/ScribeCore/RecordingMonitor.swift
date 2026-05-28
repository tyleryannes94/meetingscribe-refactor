import Foundation
import Combine

/// High-frequency recording signals (mic/system levels, capture health) live
/// here — NOT on `MeetingManager`. These values change ~12×/second while
/// recording, and keeping them on the app-wide manager meant every published
/// tick re-rendered every tab that observes the manager. Isolating them so
/// only the audio meters observe this object keeps the rest of the UI still.
///
/// Batch 6 / audit 5.4: voice level is now pushed by producers via
/// `pushVoiceLevel(_:)` (gated by an internal change-detector), and the
/// always-on 12 Hz timer that previously polled `MicOnlyRecorder.normalizedLevel`
/// even when idle is gone. The timer in `MeetingManager` now only runs
/// during a recording / dictation session.
@available(macOS 14.0, *)
@MainActor
final class RecordingMonitor: ObservableObject {
    @Published private(set) var voiceNoteLevel: Float = 0
    @Published private(set) var recordingHealth: AudioRecorder.Health = .init()

    /// Producers (MicOnlyRecorder, dictation, quick-notes capture) push
    /// the latest RMS level here. Internally we coalesce — only publishing
    /// when the value actually moves — to avoid a stream of redundant
    /// objectWillChange events (especially the idle `0` case).
    func pushVoiceLevel(_ value: Float) {
        if abs(value - voiceNoteLevel) > 0.005 {
            voiceNoteLevel = value
        }
    }

    /// Back-compat alias for any remaining call site.
    func setVoiceLevel(_ value: Float) { pushVoiceLevel(value) }

    func setHealth(_ health: AudioRecorder.Health) {
        recordingHealth = health
    }

    /// Reset to idle. Call when recording / dictation stops so the meter
    /// returns to zero on the next view render.
    func resetToIdle() {
        if voiceNoteLevel != 0 { voiceNoteLevel = 0 }
        recordingHealth = .init()
    }
}
