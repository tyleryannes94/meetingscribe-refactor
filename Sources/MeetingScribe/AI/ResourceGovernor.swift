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
