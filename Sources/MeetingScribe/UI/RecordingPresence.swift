import SwiftUI

/// Shared "what is live transcription doing right now" status, derived from the
/// LiveTranscriber's published state plus the audio health. Used by the nav-rail
/// indicator, the floating pill, and the meeting detail so they all tell the
/// same story: is it warming up, transcribing, caught up — or capturing no audio
/// at all (the silent-mic case that produced mysteriously empty transcripts).
struct LiveCaptureStatus {
    enum Kind {
        case warmup        // recording, first 5-min chunk not closed yet
        case transcribing  // whisper running on a landed chunk
        case caughtUp      // all chunks so far transcribed

        var label: String {
            switch self {
            case .warmup:       return "Listening"
            case .transcribing: return "Transcribing live"
            case .caughtUp:     return "Transcribed live"
            }
        }
        var systemImage: String {
            switch self {
            case .warmup:       return "ear"
            case .transcribing: return "waveform"
            case .caughtUp:     return "checkmark.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .warmup:       return NDS.textTertiary
            case .transcribing: return NDS.gold
            case .caughtUp:     return NDS.mint
            }
        }
    }

    let kind: Kind
    let detail: String

    /// Evaluate the current live-capture state from the LiveTranscriber's own
    /// published progress. `elapsed` is seconds since the recording started.
    ///
    /// (A no-audio/silent-mic warning was prototyped here but removed: the
    /// `AudioRecorder.Health` sample counters proved unreliable on the live
    /// path — they read zero even while the mic was capturing — so the warning
    /// false-positived. A trustworthy signal would need the actual captured
    /// byte count, not the health snapshot.)
    @MainActor
    static func evaluate(elapsed: TimeInterval,
                         transcriber: LiveTranscriber) -> LiveCaptureStatus {
        let captured = transcriber.lastTranscribedSecond
        let capturedStr = clock(captured)

        if transcriber.droppedChunkCount > 0 {
            return .init(kind: .transcribing, detail: "catching up · \(capturedStr) done")
        }
        if transcriber.isProcessing || transcriber.pendingCount > 0 {
            return .init(kind: .transcribing, detail: "\(capturedStr) transcribed")
        }
        if captured > 0 {
            return .init(kind: .caughtUp, detail: "\(capturedStr) transcribed")
        }
        // Before the first chunk closes (chunks rotate every 5 min).
        let remain = max(0, 300 - elapsed)
        return .init(kind: .warmup, detail: "first transcript in \(clock(remain))")
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r)
                     : String(format: "%d:%02d", m, r)
    }
}

/// Compact status chip: icon + "Transcribing live · 5:00 transcribed".
@available(macOS 14.0, *)
struct LiveTranscribeBadge: View {
    @ObservedObject var transcriber: LiveTranscriber
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { ctx in
            let status = LiveCaptureStatus.evaluate(
                elapsed: max(0, ctx.date.timeIntervalSince(startedAt)),
                transcriber: transcriber)
            HStack(spacing: 5) {
                Image(systemName: status.kind.systemImage)
                    .scaledFont(10, weight: .semibold)
                Text(status.kind.label)
                    .scaledFont(11, weight: .bold)
                Text("· \(status.detail)")
                    .scaledFont(11, weight: .medium)
                    .foregroundStyle(NDS.textTertiary)
                    .lineLimit(1)
            }
            .foregroundStyle(status.kind.tint)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(status.kind.label). \(status.detail)")
        }
    }
}

/// "You left the call?" prompt — shown when the scheduled meeting time has
/// passed and both mic + system audio have gone silent. Offers Keep recording
/// (override the auto-stop) or Stop now, with a live countdown to the automatic
/// stop. `compact` drops to a single button row for the floating pill.
@available(macOS 14.0, *)
struct SilenceContinueBanner: View {
    let prompt: MeetingManager.SilenceContinuePrompt
    var compact: Bool = false
    let onKeep: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill").scaledFont(11, weight: .semibold)
                    .foregroundStyle(NDS.gold)
                Text("No audio since the meeting ended — keep recording?")
                    .scaledFont(11.5, weight: .semibold)
                    .foregroundStyle(NDS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let remain = max(0, Int(prompt.autoStopAt.timeIntervalSince(ctx.date)))
                Text("Auto-stops in \(remain / 60):\(String(format: "%02d", remain % 60))")
                    .scaledFont(10.5, weight: .medium).monospacedDigit()
                    .foregroundStyle(NDS.textTertiary)
            }
            HStack(spacing: 6) {
                Button(action: onKeep) {
                    Label("Keep recording", systemImage: "record.circle")
                        .scaledFont(11.5, weight: .semibold)
                        .frame(maxWidth: compact ? nil : .infinity)
                }
                .buttonStyle(MSPrimaryButtonStyle())
                Button(action: onStop) {
                    Label("Stop now", systemImage: "stop.fill").scaledFont(11.5, weight: .semibold)
                }
                .buttonStyle(MSSecondaryButtonStyle())
            }
        }
        .padding(9)
        .background(NDS.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(NDS.gold.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No audio since the meeting ended. Keep recording, or stop now.")
    }
}

/// Persistent recording indicator that lives in the left nav rail so the live
/// meeting is reachable from EVERY page while recording (redesign request:
/// "persistent in the navbar regardless of the page you go to"). Offers exactly
/// the two actions the spec calls for — jump into the meeting, and add a quick
/// note — plus a glanceable live-transcription status.
@available(macOS 14.0, *)
struct RecordingNavIndicator: View {
    let startedAt: Date
    let collapsed: Bool
    let onOpen: () -> Void
    @ObservedObject var transcriber: LiveTranscriber

    @EnvironmentObject var manager: MeetingManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var showNote = false
    @State private var note = ""
    @State private var noteFlash: String?
    @FocusState private var noteFocused: Bool

    var body: some View {
        Group {
            if collapsed { collapsedBody } else { expandedBody }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    // MARK: Expanded

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                recDot
                Text("REC").scaledFont(10, weight: .heavy).foregroundStyle(NDS.danger)
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(LiveCaptureStatus.clock(ctx.date.timeIntervalSince(startedAt)))
                        .scaledFont(11.5, weight: .semibold).monospacedDigit()
                        .foregroundStyle(NDS.textSecondary)
                }
            }
            if let m = manager.activeMeeting {
                Text(m.displayTitle)
                    .scaledFont(12.5, weight: .semibold)
                    .foregroundStyle(NDS.textPrimary).lineLimit(1)
            }
            LiveTranscribeBadge(transcriber: transcriber, startedAt: startedAt)

            if let p = manager.silencePrompt {
                SilenceContinueBanner(prompt: p,
                                      onKeep: { manager.keepRecordingDespiteSilence() },
                                      onStop: { Task { await manager.stopRecording() } })
            }

            HStack(spacing: 6) {
                Button(action: onOpen) {
                    Label("Open", systemImage: "arrow.up.forward.square")
                        .scaledFont(11.5, weight: .semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MSPrimaryButtonStyle())
                Button { showNote.toggle(); if showNote { noteFocused = true } } label: {
                    Image(systemName: "note.text.badge.plus").scaledFont(12, weight: .semibold)
                }
                .buttonStyle(MSSecondaryButtonStyle())
                .help("Add a quick note to this meeting")
            }

            if showNote { noteField }
            if let flash = noteFlash {
                Text(flash).font(NDS.tiny).foregroundStyle(NDS.mint).transition(.opacity)
            }
        }
        .padding(10)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(NDS.danger.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, NDS.spaceMD)
        .padding(.bottom, NDS.spaceSM)
    }

    private var noteField: some View {
        HStack(spacing: 6) {
            TextField("Note…", text: $note)
                .textFieldStyle(.plain).scaledFont(12)
                .focused($noteFocused)
                .onSubmit(submitNote)
            Button(action: submitNote) {
                Image(systemName: "arrow.up.circle.fill").scaledFont(15)
                    .foregroundStyle(NDS.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius, style: .continuous)
            .strokeBorder(NDS.hairline, lineWidth: 1))
    }

    // MARK: Collapsed (icon-only rail)

    private var collapsedBody: some View {
        VStack(spacing: 6) {
            Button(action: onOpen) {
                ZStack {
                    Circle().fill(NDS.danger.opacity(0.16)).frame(width: 34, height: 34)
                    recDot
                }
            }
            .buttonStyle(.plain)
            .help("Open the meeting being recorded")
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(LiveCaptureStatus.clock(ctx.date.timeIntervalSince(startedAt)))
                    .scaledFont(9, weight: .semibold).monospacedDigit()
                    .foregroundStyle(NDS.textTertiary)
            }
        }
        .padding(.bottom, NDS.spaceSM)
    }

    private var recDot: some View {
        Circle().fill(NDS.danger).frame(width: 9, height: 9)
            .opacity(reduceMotion ? 1 : (pulse ? 0.4 : 1))
    }

    private func submitNote() {
        let stamp = manager.appendLiveNote(note)
        note = ""
        showNote = false
        withAnimation { noteFlash = stamp ?? "Saved" }
        let token = noteFlash
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if noteFlash == token { withAnimation { noteFlash = nil } }
        }
    }
}
