import Foundation
import IOKit.ps

/// Power/thermal awareness for the capture + AI pipeline. The app was previously
/// "power-blind" — it ran the same per-chunk live transcription whether plugged
/// in or on a hot battery. This centralizes the policy so the energy-expensive
/// path (per-chunk Whisper cold-loads) can be deferred to a single batch pass on
/// stop when the machine is constrained. (E2-2/E2-3/E2-7)
@MainActor
final class ResourceGovernor: ObservableObject {
    static let shared = ResourceGovernor()
    private init() {}

    var thermalState: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }
    var isLowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// True when running on battery (not wall power). Desktops report AC.
    var isOnBattery: Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let type = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }

    /// Whether to run live (during-meeting) transcription now, or defer the whole
    /// transcript to one batch pass on stop. The finalize path already
    /// batch-transcribes whatever the live pass didn't cover, so deferring just
    /// means an empty live transcript and a full pass at the end.
    var shouldRunLiveTranscription: Bool {
        let s = AppSettings.shared
        if !s.liveTranscriptionEnabled { return false }
        if thermalState == .critical { return false }
        if s.deferLiveTranscriptionOnBattery && (isOnBattery || isLowPowerMode) { return false }
        return true
    }

    // MARK: - Universal AI work gate (P0-C)

    /// Tiers of background AI work, ordered loosely by how much sustained energy
    /// each costs. The gate (`canScheduleWork`) applies a stricter power/thermal
    /// policy as the cost rises, so cheap nudges can run on battery while
    /// expensive insight passes wait for wall power. No work tier ever runs while
    /// a meeting is being transcribed — live capture quality comes first.
    enum AIWorkTier {
        /// Re-embedding entities for semantic recall. Moderate, bursty cost.
        case backgroundEmbedding
        /// Multi-step Ollama synthesis (briefs, weekly reviews, relationship
        /// health). The most expensive sustained work — wants AC power.
        case backgroundInsight
        /// A single short local prompt (a conversation starter, a one-line
        /// nudge). Cheapest — allowed under light thermal pressure on battery.
        case backgroundNudge
    }

    /// Set once at app startup so the work gate can tell whether a meeting is
    /// currently being captured — without ResourceGovernor depending on the
    /// MeetingManager layer above it. Defaults to "not transcribing" so the gate
    /// is safe before wiring (and in tests). Wired in `MeetingScribeApp`.
    var isTranscribingProvider: @MainActor () -> Bool = { false }

    /// Whether any meeting is being transcribed right now.
    var isTranscribing: Bool { isTranscribingProvider() }

    /// Whether a background AI job of the given tier may run *right now*. This is
    /// the single authority every Phase 3 background job checks before enqueuing,
    /// so live transcription is never starved by speculative work (audit C-12).
    ///
    /// - `.backgroundEmbedding`: idle (no transcription) and thermal < serious.
    /// - `.backgroundInsight`:    idle, thermal < serious, AND on wall power.
    /// - `.backgroundNudge`:      thermal < serious and not low-power mode.
    func canScheduleWork(tier: AIWorkTier) -> Bool {
        let belowSerious = thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
        switch tier {
        case .backgroundEmbedding:
            return !isTranscribing && belowSerious
        case .backgroundInsight:
            return !isTranscribing && belowSerious && !isOnBattery && !isLowPowerMode
        case .backgroundNudge:
            return belowSerious && !isLowPowerMode
        }
    }

    /// Human-readable power/thermal state for diagnostics + the perf log.
    var statusDescription: String {
        var bits: [String] = [isOnBattery ? "battery" : "AC"]
        if isLowPowerMode { bits.append("low-power") }
        switch thermalState {
        case .nominal:  break
        case .fair:     bits.append("thermal: fair")
        case .serious:  bits.append("thermal: serious")
        case .critical: bits.append("thermal: critical")
        @unknown default: break
        }
        return bits.joined(separator: ", ")
    }
}
