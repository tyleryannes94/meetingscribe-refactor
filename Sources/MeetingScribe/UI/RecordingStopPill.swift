import SwiftUI

/// Title-bar "Stop · MM:SS" pill from the design comp — a live, always-visible
/// recording control shown while a meeting is recording. The elapsed timer
/// ticks via `TimelineView`; the dot pulses unless Reduce Motion is on.
@available(macOS 14.0, *)
struct RecordingStopPill: View {
    let startedAt: Date
    let onStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: onStop) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let elapsed = max(0, Int(ctx.date.timeIntervalSince(startedAt)))
                HStack(spacing: 7) {
                    Circle().fill(NDS.danger).frame(width: 9, height: 9)
                        .opacity(reduceMotion ? 1 : (pulse ? 0.35 : 1))
                    Text("Stop · \(Self.format(elapsed))")
                        .scaledFont(12.5, weight: .bold).monospacedDigit()
                }
                .foregroundStyle(NDS.danger)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(NDS.danger.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(NDS.danger.opacity(0.3), lineWidth: 1))
                .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .help("Stop recording")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private static func format(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
