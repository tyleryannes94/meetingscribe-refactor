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
    /// U2-6: inline capture line — a note or quick-add task without leaving the dock.
    @State private var capture = ""
    @State private var captureFlash: String?
    @FocusState private var captureFocused: Bool
    /// C1-2: count of "mark moment" highlights flagged this session.
    @State private var markCount = 0
    @State private var markFlash = false

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
                    HStack(spacing: 6) {
                        Text(m.displayTitle)
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(NDS.textPrimary).lineLimit(1)
                        // C1-10: time-remaining / overrun cue for scheduled meetings.
                        if !m.isImpromptu {
                            Spacer(minLength: 6)
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                if let cue = remainingCue(m, asOf: ctx.date) {
                                    Text(cue.text)
                                        .scaledFont(11, weight: .semibold).monospacedDigit()
                                        .foregroundStyle(cue.color)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(cue.color.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            .fixedSize()
                        }
                    }
                    Text(metaLine(m))
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
                }

                HStack(spacing: 8) {
                    AudioLevelMeter(micLevel: recordingMonitor.recordingHealth.micLevel,
                                    systemLevel: recordingMonitor.recordingHealth.systemLevel,
                                    isActive: true, height: 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: markMoment) {
                        Image(systemName: markFlash ? "flag.fill" : "flag")
                            .foregroundStyle(markFlash ? NDS.gold : NDS.textSecondary)
                    }
                    .buttonStyle(MSSecondaryButtonStyle())
                    .help("Mark this moment (adds a highlight to the recap)")
                    .overlay(alignment: .topTrailing) {
                        if markCount > 0 {
                            Text("\(markCount)")
                                .scaledFont(9, weight: .bold).monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(NDS.gold).clipShape(Capsule())
                                .offset(x: 5, y: -5)
                        }
                    }
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

                if let p = manager.silencePrompt {
                    SilenceContinueBanner(prompt: p,
                                          onKeep: { manager.keepRecordingDespiteSilence() },
                                          onStop: { Task { await manager.stopRecording() } })
                }

                captureLine
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
            if let m = manager.activeMeeting { markCount = MeetingMarks.load(m.id).count }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording meeting")
    }

    /// U2-6: a one-line capture field. Plain text appends a timestamped bullet
    /// to the live meeting's notes; a leading `!` or `todo ` files it through the
    /// quick-add parser as a task instead — so capture is one field, not Open →
    /// detail → Notes tab.
    @ViewBuilder
    private var captureLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle")
                    .scaledFont(12, weight: .medium).foregroundStyle(NDS.textTertiary)
                TextField("Note or todo…", text: $capture)
                    .textFieldStyle(.plain)
                    .scaledFont(12.5)
                    .foregroundStyle(NDS.textPrimary)
                    .focused($captureFocused)
                    .onSubmit(submitCapture)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(NDS.fieldBg)
            .clipShape(RoundedRectangle(cornerRadius: NDS.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 1))

            if let flash = captureFlash {
                Text(flash)
                    .font(NDS.tiny).foregroundStyle(NDS.mint)
                    .transition(.opacity)
            }
        }
    }

    private func submitCapture() {
        let raw = capture.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        let lower = raw.lowercased()
        if lower.hasPrefix("todo ") || raw.hasPrefix("!") {
            // Task: drop a leading "todo " label; keep "!" (it's the priority token).
            let body = lower.hasPrefix("todo ") ? String(raw.dropFirst(5)) : raw
            _ = manager.actionItems.createTask(parsing: body)
            flash("Task added")
        } else {
            // Note: append a timestamped bullet to the live meeting's notes.
            if let m = manager.activeMeeting {
                let stamp = elapsed(asOf: Date())
                let existing = manager.userNotes(for: m)
                let bullet = "- [\(stamp)] \(raw)"
                let merged = existing.isEmpty ? bullet : existing + "\n" + bullet
                manager.saveUserNotes(merged, for: m)
                flash("Noted at \(stamp)")
            } else {
                _ = manager.actionItems.createTask(parsing: raw)
                flash("Captured")
            }
        }
        capture = ""
    }

    /// C1-2: flag the current moment. Writes a timestamped highlight (relative to
    /// the recording start) to the live meeting's marks sidecar; the finished
    /// recap surfaces these as a "Highlights" anchor list.
    private func markMoment() {
        guard let m = manager.activeMeeting else { return }
        let second = max(0, Date().timeIntervalSince(startedAt))
        let marks = MeetingMarks.add(second: second, to: m.id)
        markCount = marks.count
        withAnimation(NDS.motion(.easeOut(duration: NDS.motionFast), reduce: reduceMotion)) {
            markFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(NDS.motion(.easeOut(duration: NDS.motionFast), reduce: reduceMotion)) {
                markFlash = false
            }
        }
    }

    private func flash(_ message: String) {
        withAnimation(NDS.motion(.easeOut(duration: NDS.motionFast), reduce: reduceMotion)) {
            captureFlash = message
        }
        let token = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if captureFlash == token {
                withAnimation(NDS.motion(.easeOut(duration: NDS.motionFast), reduce: reduceMotion)) {
                    captureFlash = nil
                }
            }
        }
    }

    /// C1-10: "12 min left" for a scheduled meeting, going amber under 5 min and
    /// "+8 over" once past `endDate`. nil before the meeting is anywhere near
    /// ending so the cue doesn't shout for a freshly-started hour-long block.
    private func remainingCue(_ m: Meeting, asOf now: Date) -> (text: String, color: Color)? {
        let remaining = m.endDate.timeIntervalSince(now)
        let mins = Int(ceil(remaining / 60))
        switch remaining {
        case ..<0:
            let over = Int(floor(-remaining / 60))
            return ("+\(over) min over", NDS.danger)
        case 0..<(5 * 60):
            return ("\(max(1, mins)) min left", NDS.gold)
        case (5 * 60)..<(20 * 60):
            return ("\(mins) min left", NDS.textTertiary)
        default:
            return nil   // plenty of time — stay quiet
        }
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
