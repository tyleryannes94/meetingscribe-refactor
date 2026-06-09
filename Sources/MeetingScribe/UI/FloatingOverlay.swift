import SwiftUI
import AppKit
import Combine

/// Whispr-Flow-style floating overlay shown while a voice note (either via
/// the UI button OR the dictation hotkey) is being recorded and transcribed.
///
/// States:
///   • Recording: pulsing red dot + elapsed time + Stop / Cancel
///   • Transcribing: spinner + "Transcribing…"
///   • Done: transcript preview + Copy Transcript + Go to Recording
///   • Error: error text + Dismiss
///
/// Lives in its own borderless NSWindow at level `.floating` so it sits above
/// every other window without stealing focus or appearing in Cmd-Tab.
@available(macOS 14.0, *)
@MainActor
final class FloatingOverlayController: ObservableObject {
    enum State: Equatable {
        case hidden
        case recording(startedAt: Date)
        case meetingRecording(startedAt: Date)
        case transcribing
        case done(note: QuickNote, transcript: String)
        case error(String)
    }

    @Published private(set) var state: State = .hidden
    private(set) weak var manager: MeetingManager?

    private var window: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var lastSeenNoteID: String?
    private var autoHideTask: Task<Void, Never>?

    // MARK: - Setup

    func attach(to manager: MeetingManager) {
        self.manager = manager

        // UI-button-initiated voice notes. We observe the QuickNotesController
        // directly (rather than the legacy MeetingManager.$quickRecordState
        // which was removed when state moved into the sub-controller).
        manager.quickNotesController.$state
            .removeDuplicates()
            .map { Self.bridgeState($0) }
            .sink { [weak self] s in self?.handleQuickRecord(s) }
            .store(in: &cancellables)

        // Hotkey-initiated dictation. dictation is itself an ObservableObject,
        // so subscribe to its state publisher.
        manager.dictation.$state
            .removeDuplicates()
            .sink { [weak self] s in self?.handleDictation(s) }
            .store(in: &cancellables)

        // When a new QuickNote lands (transcription done), transition the
        // overlay to .done with that note.
        manager.quickNotesController.$notes
            .sink { [weak self] notes in self?.handleNotesChange(notes) }
            .store(in: &cancellables)

        // Meeting recording — promote the same floating HUD to full meetings so
        // stopping isn't buried behind a Zoom window. (D4-1)
        manager.$state
            .removeDuplicates()
            .sink { [weak self] s in self?.handleMeetingState(s) }
            .store(in: &cancellables)
    }

    private func handleMeetingState(_ s: RecordingState) {
        switch s {
        case .recording(_, let startedAt):
            transition(to: .meetingRecording(startedAt: startedAt))
        case .idle, .error, .starting, .stopping:
            // Only clear the overlay if IT was showing the meeting HUD — a
            // concurrent voice note keeps its own state.
            if case .meetingRecording = state { transition(to: .hidden) }
        }
    }

    /// Map the sub-controller's RecordState to the legacy QuickRecordState
    /// the overlay's state machine consumes.
    private static func bridgeState(_ s: QuickNotesController.RecordState) -> MeetingManager.QuickRecordState {
        switch s {
        case .idle: return .idle
        case .recording(let at): return .recording(startedAt: at)
        case .transcribing: return .transcribing
        case .error(let m): return .error(m)
        }
    }

    // MARK: - State machine

    private func handleQuickRecord(_ s: MeetingManager.QuickRecordState) {
        switch s {
        case .recording(let startedAt):
            transition(to: .recording(startedAt: startedAt))
        case .transcribing:
            transition(to: .transcribing)
        case .idle:
            // Final transition handled when a new note appears.
            break
        case .error(let msg):
            transition(to: .error(msg))
        }
    }

    private func handleDictation(_ s: QuickDictation.State) {
        switch s {
        case .recording(let startedAt):
            transition(to: .recording(startedAt: startedAt))
        case .transcribing:
            transition(to: .transcribing)
        case .idle:
            break
        case .error(let msg):
            transition(to: .error(msg))
        }
    }

    private func handleNotesChange(_ notes: [QuickNote]) {
        // Only transition to "done" if we were just transcribing AND a brand-
        // new note arrived (sorted newest-first by QuickNoteStore).
        guard case .transcribing = state, let latest = notes.first else { return }
        if latest.id == lastSeenNoteID { return }
        lastSeenNoteID = latest.id
        let transcript = manager?.readQuickNoteTranscript(latest) ?? latest.snippet
        transition(to: .done(note: latest, transcript: transcript))
    }

    private func transition(to next: State) {
        state = next
        switch next {
        case .hidden:
            window?.orderOut(nil)
        case .recording, .meetingRecording, .transcribing, .done, .error:
            ensureWindow()
            window?.orderFrontRegardless()
        }
        // Done + error auto-hide after a delay; recording/transcribing persist.
        autoHideTask?.cancel()
        switch next {
        case .done:    scheduleHide(after: 30)
        case .error:   scheduleHide(after: 8)
        default:       break
        }
    }

    private func scheduleHide(after seconds: Double) {
        autoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.transition(to: .hidden)
        }
    }

    // MARK: - User actions (called from the SwiftUI view)

    func stopRecording() {
        guard let manager else { return }
        // Meeting HUD: stop the meeting recording.
        if case .meetingRecording = state {
            Task { await manager.stopRecording() }
            return
        }
        if case .recording = manager.quickRecordState {
            Task { await manager.stopQuickNote() }
        } else if case .recording = manager.dictation.state {
            manager.dictation.toggle()  // hotkey toggle ends recording
        }
    }

    func cancelOverlay() {
        // Soft cancel: just hide the overlay. Recording (if any) continues.
        transition(to: .hidden)
    }

    func copyTranscript() {
        guard case .done(_, let transcript) = state else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(transcript, forType: .string)
    }

    func goToRecording() {
        guard case .done(let note, _) = state else { return }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(
            name: .meetingScribeOpenVoiceNote,
            object: nil,
            userInfo: ["id": note.id]
        )
        transition(to: .hidden)
    }

    // MARK: - Window

    private func ensureWindow() {
        if window != nil { return }
        let hosting = NSHostingController(rootView: FloatingOverlayView(controller: self))
        hosting.view.wantsLayer = true
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 80),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces,
                                     .stationary,
                                     .ignoresCycle,
                                     .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        positionAtBottomCenter(window)
        self.window = window
    }

    private func positionAtBottomCenter(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = window.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 60
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - View

@available(macOS 14.0, *)
struct FloatingOverlayView: View {
    @ObservedObject var controller: FloatingOverlayController

    var body: some View {
        Group {
            switch controller.state {
            case .hidden:
                EmptyView()
            case .recording(let startedAt):
                RecordingPill(startedAt: startedAt, controller: controller)
            case .meetingRecording(let startedAt):
                MeetingRecordingPill(startedAt: startedAt, controller: controller)
            case .transcribing:
                TranscribingPill(controller: controller)
            case .done(_, let transcript):
                DonePill(transcript: transcript, controller: controller)
            case .error(let msg):
                ErrorPill(message: msg, controller: controller)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Color.black.opacity(0.06),
                                                  Color.clear],
                                         startPoint: .top, endPoint: .bottom))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(10)
    }
}

@available(macOS 14.0, *)
private struct RecordingPill: View {
    let startedAt: Date
    @ObservedObject var controller: FloatingOverlayController
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            PulsingDot()
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(elapsedString())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            AudioLevelMeter(micLevel: controller.manager?.recordingMonitor.voiceNoteLevel ?? 0,
                            systemLevel: 0,
                            bars: 14, height: 24)
                .frame(width: 130)
            Spacer()
            OverlayButton(label: "End",
                          systemImage: "stop.fill",
                          tint: .red,
                          prominent: true,
                          action: controller.stopRecording)
            Button(action: controller.cancelOverlay) {
                Image(systemName: "xmark")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide overlay")
            .help("Hide overlay (recording continues)")
        }
        .onReceive(timer) { now = $0 }
    }

    private func elapsedString() -> String {
        let s = Int(now.timeIntervalSince(startedAt))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

@available(macOS 14.0, *)
private struct MeetingRecordingPill: View {
    let startedAt: Date
    @ObservedObject var controller: FloatingOverlayController
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            PulsingDot()
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording meeting")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(elapsedString())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            AudioLevelMeter(micLevel: controller.manager?.recordingMonitor.recordingHealth.micLevel ?? 0,
                            systemLevel: 0,
                            bars: 14, height: 24)
                .frame(width: 130)
            Spacer()
            OverlayButton(label: "Stop",
                          systemImage: "stop.fill",
                          tint: .red,
                          prominent: true,
                          action: controller.stopRecording)
            Button(action: controller.cancelOverlay) {
                Image(systemName: "xmark")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide overlay")
            .help("Hide overlay (recording continues)")
        }
        .onReceive(timer) { now = $0 }
    }

    private func elapsedString() -> String {
        let s = Int(now.timeIntervalSince(startedAt))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

@available(macOS 14.0, *)
private struct TranscribingPill: View {
    @ObservedObject var controller: FloatingOverlayController
    var body: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcribing").font(.callout.weight(.semibold))
                Text("Whisper is running locally · usually a few seconds")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: controller.cancelOverlay) {
                Image(systemName: "xmark")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide overlay")
        }
    }
}

@available(macOS 14.0, *)
private struct DonePill: View {
    let transcript: String
    @ObservedObject var controller: FloatingOverlayController
    @State private var copiedFlash = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .scaledFont(14, weight: .bold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice note ready").font(.callout.weight(.semibold))
                Text(transcript.isEmpty ? "(empty transcript)" : transcript)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            OverlayButton(label: copiedFlash ? "Copied" : "Copy",
                          systemImage: copiedFlash ? "checkmark" : "doc.on.doc",
                          tint: copiedFlash ? .green : .primary,
                          prominent: false) {
                controller.copyTranscript()
                copiedFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedFlash = false }
            }
            OverlayButton(label: "Open",
                          systemImage: "arrow.up.right",
                          tint: NDS.brand,
                          prominent: false,
                          action: controller.goToRecording)
            Button(action: controller.cancelOverlay) {
                Image(systemName: "xmark")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, height: 26)
                    .background(Color.secondary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide overlay")
        }
    }
}

@available(macOS 14.0, *)
private struct ErrorPill: View {
    let message: String
    @ObservedObject var controller: FloatingOverlayController
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Voice note error").font(.callout).bold()
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Dismiss") { controller.cancelOverlay() }
                .controlSize(.small)
        }
    }
}

@available(macOS 14.0, *)
private struct PulsingDot: View {
    @State private var scale: CGFloat = 1.0
    @State private var glow: Double = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.18))
                .frame(width: 28, height: 28)
                .scaleEffect(1 + CGFloat(glow))
                .opacity(1 - glow)
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .scaleEffect(scale)
                .shadow(color: .red.opacity(0.5), radius: 4)
        }
        .onAppear {
            // Reduce Motion: keep the dot static (no perpetual pulse/glow).
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                scale = 1.18
            }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                glow = 0.6
            }
        }
    }
}

@available(macOS 14.0, *)
private struct OverlayButton: View {
    let label: String
    let systemImage: String
    let tint: Color
    let prominent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).scaledFont(11, weight: .semibold)
                Text(label).scaledFont(12.5, weight: .semibold)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(prominent ? .white : tint)
            .background(
                Capsule().fill(
                    prominent ? AnyShapeStyle(tint)
                              : AnyShapeStyle(Color.secondary.opacity(hovering ? 0.16 : 0.10))
                )
            )
            .overlay(Capsule().strokeBorder(
                prominent ? Color.clear : tint.opacity(0.2), lineWidth: 0.5
            ))
            .shadow(color: prominent ? tint.opacity(0.25) : .clear,
                    radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.spring(response: 0.15, dampingFraction: 0.85), value: hovering)
        .onHover { hovering = $0 }
    }
}

extension Notification.Name {
    /// Posted by FloatingOverlay's "Go to Recording" button. userInfo["id"]
    /// = QuickNote.id. MainWindow listens and switches to Notes tab +
    /// selects that note.
    static let meetingScribeOpenVoiceNote = Notification.Name("MeetingScribeOpenVoiceNote")
}
