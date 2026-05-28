import SwiftUI

/// Settings section for ambient (mic-based) meeting detection. Toggling it on
/// starts `AmbientMeetingDetector`; the slider tunes how many seconds of
/// continuous mic use count as "in a meeting" (lower = more sensitive).
@available(macOS 14.0, *)
struct MeetingDetectionSettingsView: View {
    @AppStorage("ambientDetectionEnabled") private var enabled = false
    @AppStorage("ambientDetectionThreshold") private var threshold = 20.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Detect meetings from microphone activity")
                    Text("Notices when an app uses your mic for a while and offers to record — "
                         + "even apps MeetingScribe doesn't recognize by window.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: enabled) { _, on in
                if on { AmbientMeetingDetector.shared.start() }
                else { AmbientMeetingDetector.shared.stop() }
            }

            HStack(spacing: 10) {
                Text("Sensitivity").font(.caption).foregroundStyle(.secondary)
                // Invert: left = more sensitive (shorter threshold).
                Slider(value: $threshold, in: 5...60, step: 5) {
                    Text("Seconds of mic use")
                } minimumValueLabel: {
                    Text("High").font(.caption2)
                } maximumValueLabel: {
                    Text("Low").font(.caption2)
                }
                Text("\(Int(threshold))s").font(.caption.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
        }
    }
}
