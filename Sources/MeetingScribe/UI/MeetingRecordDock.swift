import SwiftUI

/// In-app docked recording bar for a live MEETING (redesign §2A). Per the §2
/// rule, meeting recording is in-app only — never a system hover overlay. Shown
/// bottom-right of the content area while recording a meeting and the user isn't
/// on the Meetings tab (gated by `RecordingPresentation.showsMeetingDock`).
@available(macOS 14.0, *)
struct MeetingRecordDock: View {
    let startedAt: Date
    /// "Open & add notes" → jump to the live meeting's notes.
    let onOpen: () -> Void

    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var recordingMonitor: RecordingMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [NDS.danger, NDS.accent],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 3)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(NDS.danger).frame(width: 8, height: 8)
                        .opacity(reduceMotion ? 1 : (pulse ? 0.35 : 1))
                    Text("REC").scaledFont(10, weight: .heavy).foregroundStyle(NDS.danger)
                    Text("RECORDING MEETING")
                        .scaledFont(10, weight: .bold, relativeTo: .caption2).tracking(0.8)
                        .foregroundStyle(NDS.textSecondary)
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(elapsed(asOf: ctx.date))
                            .scaledFont(12.5, weight: .semibold).monospacedDigit()
                            .foregroundStyle(NDS.textPrimary)
                    }
                }

                if let m = manager.activeMeeting {
                    Text(m.displayTitle)
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(NDS.textPrimary).lineLimit(1)
                    Text(metaLine(m))
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                }

                HStack(spacing: 8) {
                    AudioLevelMeter(micLevel: recordingMonitor.recordingHealth.micLevel,
                                    systemLevel: recordingMonitor.recordingHealth.systemLevel,
                                    isActive: true, height: 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onOpen) {
                        Label("Open & add notes", systemImage: "note.text")
                    }
                    .buttonStyle(MSPrimaryButtonStyle())
                    Button { Task { await manager.stopRecording() } } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                    .help("Stop recording")
                }
            }
            .padding(12)
        }
        .frame(width: 308)
        .background(NDS.fieldBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(NDS.danger.opacity(0.38), lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 16, y: 8)
        .padding(18)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording meeting")
    }

    private func elapsed(asOf now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(startedAt)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    private func metaLine(_ m: Meeting) -> String {
        let names = m.attendees.prefix(3).map { a in
            a.components(separatedBy: "<").first?.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ").first ?? a
        }.filter { !$0.isEmpty }
        let who = names.isEmpty ? nil : names.joined(separator: ", ")
        return [who, "System + Mic"].compactMap { $0 }.joined(separator: " · ")
    }
}
