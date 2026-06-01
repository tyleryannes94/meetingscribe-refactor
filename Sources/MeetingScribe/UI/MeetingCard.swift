import SwiftUI
import AppKit

/// Shared meeting card component used throughout the Today view.
/// Three visual variants — `.live`, `.upcoming`, `.past` — share the same
/// chrome (rounded rectangle, hover elevation, generous padding) but differ in
/// what they emphasize (red accent + audio meter, primary blue Join button,
/// muted status icons).
///
/// Visual spec, modeled after Stripe / Cash App native apps:
///   - Card: 14pt corner radius, 16pt padding, hairline border, hover shadow
///   - Title: .headline (15pt semibold)
///   - Time: monospaced .callout
///   - Meta: .caption secondary
///   - Buttons: bordered / borderedProminent, .regular size
@available(macOS 14.0, *)
struct MeetingCard: View {
    enum Variant { case live, upcoming, past }

    let meeting: Meeting
    let variant: Variant
    var isExpanded: Bool = false
    var onOpen: () -> Void

    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var recordingMonitor: RecordingMonitor
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 14) {
                timeColumn
                content
                Spacer(minLength: 0)
                accessory
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor,
                                  lineWidth: variant == .live ? 1.5
                                           : isExpanded ? 1.2 : 0.5)
            )
            .shadow(color: .black.opacity(hovering ? 0.06 : 0.025),
                    radius: hovering ? 8 : 3,
                    y: hovering ? 3 : 1)
            .scaleEffect(hovering && !reduceMotion ? 1.005 : 1.0)
            .animation(NDS.motion(.spring(response: 0.18, dampingFraction: 0.85), reduce: reduceMotion), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Time column

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch variant {
            case .live:
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                    .pulsingSymbol(active: !reduceMotion)
            default:
                Text(timeOfDay()).font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(durationMinutes())m")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 60, alignment: .leading)
    }

    // MARK: - Content (title, meta, tags, primary actions)

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(meeting.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                // End-of-pipeline health badge (audit 8.1) — surfaces
                // recordings that finished with no transcribable audio or
                // partial capture so the user isn't blindsided by an
                // empty summary.
                if variant == .past {
                    MeetingHealthBadge(health: meeting.health, compact: true)
                }
                if meeting.conferenceURL != nil && variant == .upcoming {
                    Image(systemName: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if meeting.isLive && variant == .upcoming {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.red.opacity(0.12), in: Capsule())
                }
                if meeting.seriesID?.isEmpty == false {
                    Image(systemName: "repeat")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.purple)
                        .help("Recurring meeting")
                }
                if meeting.isImported {
                    Text("Imported")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                        .help("Imported from an audio file")
                }
            }
            metaRow
            if variant == .live { liveLine } else { actionsRow }
        }
    }

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 6) {
            if !meeting.attendees.isEmpty {
                Text("\(meeting.attendees.count) attendee\(meeting.attendees.count == 1 ? "" : "s")")
            }
            if let cal = meeting.calendarName {
                if !meeting.attendees.isEmpty { Text("·").foregroundStyle(.tertiary) }
                Text(cal).lineLimit(1)
            }
            ForEach(tagStore.tags(for: meeting).prefix(3)) { t in
                TagChipMini(tag: t)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var liveLine: some View {
        HStack(spacing: 12) {
            // Direction A — mic and system levels read as separate labeled
            // rows so it's obvious both sources are being captured.
            VStack(alignment: .leading, spacing: 2) {
                meterRow(label: "MIC", level: recordingMonitor.recordingHealth.micLevel,
                         tint: NDS.selectColor("green"))
                meterRow(label: "SYS", level: recordingMonitor.recordingHealth.systemLevel,
                         tint: NDS.selectColor("blue"))
            }
            Spacer()
            Button(role: .destructive) {
                Task { await manager.stopRecording() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.regular)
        }
    }

    private func meterRow(label: String, level: Float, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NDS.textTertiary)
                .frame(width: 28, alignment: .leading)
            AudioLevelMeter(level: level, tint: tint, bars: 12, height: 16)
        }
    }

    @ViewBuilder
    private var actionsRow: some View {
        switch variant {
        case .upcoming:
            HStack(spacing: 8) {
                if meeting.conferenceURL != nil {
                    // Primary: Join & Record (the 95% action) with a
                    // chevron dropdown for the rare "join without recording" case.
                    // Replaces the old 3-button layout that required a decision
                    // under time pressure.
                    Menu {
                        Button {
                            if let url = meeting.conferenceURL.flatMap(URL.init(string:)) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: { Label("Join (no recording)", systemImage: "video") }

                        Divider()

                        Button {
                            Task {
                                if case .recording = manager.state {
                                    await manager.stopRecording()
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                }
                                await manager.startRecording(for: meeting)
                            }
                        } label: { Label("Record only (no join)", systemImage: "record.circle") }
                    } label: {
                        Label("Join & Record", systemImage: "video.fill")
                    } primaryAction: {
                        Task { await manager.switchToRecording(meeting) }
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    // No conference URL: just a Record button.
                    Button {
                        Task {
                            if case .recording = manager.state {
                                await manager.stopRecording()
                                try? await Task.sleep(nanoseconds: 300_000_000)
                            }
                            await manager.startRecording(for: meeting)
                        }
                    } label: { Label("Record", systemImage: "record.circle") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
        case .past:
            HStack(spacing: 8) {
                pastStatus
                Spacer()
            }
        case .live:
            EmptyView()
        }
    }

    /// Direction A — a single plain-English status instead of three opaque
    /// transcript / notes / summary chips that were hard to read at a glance.
    @ViewBuilder
    private var pastStatus: some View {
        if manager.isTranscribingMeeting(meeting) {
            HStack(spacing: 6) {
                StatusPulseDot(color: NDS.selectColor("orange"), size: 8)
                Text("Transcribing")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NDS.selectColor("orange"))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(NDS.selectColor("orange").opacity(0.12), in: Capsule())
        } else if transcriptReady {
            HStack(spacing: 5) {
                Circle().fill(NDS.selectColor("green")).frame(width: 6, height: 6)
                Text("Ready")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NDS.selectColor("green"))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(NDS.selectColor("green").opacity(0.16), in: Capsule())
        } else {
            Text("No transcript")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NDS.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(NDS.fieldBg, in: Capsule())
        }
    }

    // MARK: - Accessory (chevron)

    @ViewBuilder
    private var accessory: some View {
        if variant != .live {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isExpanded
                                 ? AnyShapeStyle(NDS.brand)
                                 : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(NDS.motion(.spring(response: 0.22, dampingFraction: 0.85), reduce: reduceMotion), value: isExpanded)
        } else if manager.isTranscribingMeeting(meeting) {
            ProgressView().controlSize(.small)
        }
    }

    // MARK: - Helpers

    private var backgroundFill: some ShapeStyle {
        switch variant {
        case .live: return AnyShapeStyle(Color.red.opacity(0.05))
        default:
            if isExpanded { return AnyShapeStyle(NDS.brand.opacity(0.06)) }
            return AnyShapeStyle(NDS.fieldBg)
        }
    }
    private var borderColor: Color {
        switch variant {
        case .live: return .red.opacity(0.55)
        default:
            if isExpanded { return NDS.brand.opacity(0.5) }
            return hovering ? NDS.brand.opacity(0.3) : NDS.hairline
        }
    }

    private func timeOfDay() -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: meeting.startDate)
    }
    private func durationMinutes() -> Int {
        max(0, Int(meeting.endDate.timeIntervalSince(meeting.startDate) / 60))
    }
    /// Transcript-ready status WITHOUT reading the file. Previously `pastStatus`
    /// called `String(contentsOf: transcript.md)` on every body eval — for every
    /// row, every scroll — the #1 list jank/hang vector (V5 PR-1). The health DTO
    /// already records whether the transcript is non-empty; only fall back to a
    /// cheap existence *stat* for older meetings that predate health.
    private var transcriptReady: Bool {
        switch meeting.health?.status {
        case .ok, .partial, .fallbackUsed: return true
        case .noTranscript: return false
        case .none:
            let dir = manager.store.directory(for: meeting, primaryTag: tagStore.primaryTag(for: meeting))
            return FileManager.default.fileExists(atPath: dir.appendingPathComponent("transcript.md").path)
        }
    }
}

// MARK: - Pulsing status dot

/// A small dot that gently pulses opacity — used by the "Transcribing" status.
@available(macOS 14.0, *)
struct StatusPulseDot: View {
    var color: Color
    var size: CGFloat = 8
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(on ? 0.35 : 1)
            .animation(NDS.motion(.easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                                  reduce: reduceMotion), value: on)
            // With Reduce Motion on, stay static at full opacity (no pulse).
            .onAppear { if !reduceMotion { on = true } }
    }
}

// MARK: - Tag chip mini (used inside cards)

@available(macOS 14.0, *)
struct TagChipMini: View {
    let tag: MeetingTag
    var body: some View {
        let color = Color(hex: tag.colorHex ?? "") ?? NDS.brand
        HStack(spacing: 3) {
            if let s = tag.symbol { Image(systemName: s).font(.system(size: 9)) }
            Text(tag.name).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color)
    }
}
