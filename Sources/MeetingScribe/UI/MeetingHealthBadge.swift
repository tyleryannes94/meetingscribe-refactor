import SwiftUI
import VaultKit

/// Renders a small status pill for a meeting's end-of-pipeline health
/// (`MeetingHealthDTO`). Drop in next to a meeting's title in cards / lists
/// to surface "no transcript" / "fallback used" / "partial" without the
/// user having to open the detail view.
///
/// Audit 8.1B: previously, an end-of-meeting failure (revoked Screen
/// Recording mid-call, dead mic, empty whisper output) finalized silently
/// — no badge, no warning. Now the badge is visible at-a-glance and the
/// hover popover lists the specific warnings collected by `AudioRecorder`.
@available(macOS 14.0, *)
struct MeetingHealthBadge: View {
    let health: MeetingHealthDTO?
    var compact: Bool = false

    var body: some View {
        if let health, health.status != .ok || !health.warnings.isEmpty {
            badge(for: health)
        } else if health == nil {
            EmptyView()    // older meetings without health data — nothing to show
        }
    }

    @ViewBuilder
    private func badge(for health: MeetingHealthDTO) -> some View {
        let (label, icon, color) = style(for: health.status)
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            if !compact { Text(label).font(.system(size: 10, weight: .medium)) }
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .help(helpText(for: health))
        .accessibilityLabel(Text("\(label) recording quality: \(helpText(for: health))"))
    }

    private func style(for status: MeetingHealthDTO.Status) -> (String, String, Color) {
        switch status {
        case .ok:
            return ("OK", "checkmark.circle.fill", .green)
        case .partial:
            return ("Partial", "exclamationmark.triangle.fill", .orange)
        case .noTranscript:
            return ("No transcript", "xmark.octagon.fill", .red)
        case .fallbackUsed:
            return ("Recovered", "arrow.triangle.2.circlepath", .yellow)
        }
    }

    private func helpText(for health: MeetingHealthDTO) -> String {
        var lines: [String] = []
        switch health.status {
        case .ok: lines.append("Recording captured both sources successfully.")
        case .partial: lines.append("Recording captured one source successfully; the other was silent.")
        case .noTranscript: lines.append("Recording produced no transcribable audio.")
        case .fallbackUsed: lines.append("Recording finalized after retrying transcription on CPU.")
        }
        if !health.warnings.isEmpty {
            lines.append("")
            lines.append(contentsOf: health.warnings)
        }
        let mins = Int(health.recordedSeconds / 60)
        lines.append("")
        lines.append("Recorded \(mins) min — mic \(byteString(health.micBytes)) / system \(byteString(health.systemBytes))")
        return lines.joined(separator: "\n")
    }

    private func byteString(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
