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
    /// Mirror of `MeetingManager.silencePrompt` so the floating pill (which
    /// observes this controller, not the manager) can show the keep-recording
    /// banner when a meeting goes silent past its end while the window is closed.
    @Published private(set) var meetingSilencePrompt: MeetingManager.SilenceContinuePrompt?
    /// QuickNote ids whose task-mode extraction has landed. Mirrors
    /// `QuickNotesController.notesWithTasks` so the floating DonePill view
    /// re-renders (it observes this controller, not the sub-controller).
    @Published private(set) var taskReadyNoteIDs: Set<String> = []
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

        // Meeting recording — show the floating HUD ONLY while the main window is
        // closed/minimized, so the live meeting (stop, open, add note) is always
        // reachable. When the window is open the persistent nav-rail indicator
        // covers it instead.
        manager.$state
            .removeDuplicates()
            .sink { [weak self] _ in self?.reevaluateMeetingPill() }
            .store(in: &cancellables)

        // The pill's visibility also depends on the main window opening/closing,
        // which doesn't change `manager.state`. Re-check on those window events.
        for name in [NSWindow.willCloseNotification,
                     NSWindow.didBecomeKeyNotification,
                     NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in
                    // willClose fires before isVisible flips — defer a beat.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self?.reevaluateMeetingPill()
                    }
                }
                .store(in: &cancellables)
        }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.reevaluateMeetingPill() }
            .store(in: &cancellables)

        // Mirror the manager's end-of-meeting silence prompt so the floating pill
        // can surface the "keep recording?" banner when the window is closed.
        manager.$silencePrompt
            .removeDuplicates()
            .sink { [weak self] p in self?.meetingSilencePrompt = p }
            .store(in: &cancellables)

        // Task-mode voice notes: surface a toast with a See Tasks shortcut
        // the moment extraction lands, regardless of which app is frontmost.
        NotificationCenter.default.publisher(for: .meetingScribeVoiceNoteTasksReady)
            .sink { [weak self] notif in
                guard let id = notif.userInfo?["id"] as? String,
                      let count = notif.userInfo?["count"] as? Int else { return }
                self?.taskReadyNoteIDs.insert(id)
                let title = (notif.userInfo?["title"] as? String) ?? "Voice note"
                let msg = count == 1
                    ? "“\(title)” → 1 task suggestion"
                    : "“\(title)” → \(count) task suggestions"
                ToastCenter.shared.show(msg, actionTitle: "See tasks") {
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(
                        name: .meetingScribeOpenVoiceNote,
                        object: nil,
                        userInfo: ["id": id, "focusTasks": true]
                    )
                }
            }
            .store(in: &cancellables)
    }

    /// Show the floating meeting pill when a meeting is recording AND the main
    /// window isn't on screen; hide it otherwise. Only touches the `.hidden` /
    /// `.meetingRecording` states so it never fights an active voice-note HUD.
    private func reevaluateMeetingPill() {
        switch state {
        case .hidden, .meetingRecording: break
        default: return
        }
        let startedAt: Date? = {
            if case .recording(_, let at) = manager?.state { return at }
            return nil
        }()
        if let startedAt, !isMainWindowVisible() {
            if case .meetingRecording = state { /* already showing */ }
            else { transition(to: .meetingRecording(startedAt: startedAt)) }
        } else if case .meetingRecording = state {
            transition(to: .hidden)
        }
    }

    /// The main window is "on screen" when a titled, non-panel, non-minimized
    /// window titled "MeetingScribe" is visible (the Settings window is titled
    /// "MeetingScribe Settings", so it doesn't count).
    private func isMainWindowVisible() -> Bool {
        NSApp.windows.contains { w in
            w.isVisible && !w.isMiniaturized &&
            w.styleMask.contains(.titled) && !(w is NSPanel) &&
            w.title == "MeetingScribe"
        }
    }

    /// Bring the app + main window forward and open the live meeting. Handled at
    /// the app level (the main window's view may be torn down while closed).
    func openLiveMeeting() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .meetingScribeOpenLiveMeeting, object: nil)
        transition(to: .hidden)
    }

    @discardableResult
    func addLiveNote(_ text: String) -> String? {
        manager?.appendLiveNote(text)
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
        // Auto-size the window to the SwiftUI content (`.preferredContentSize`, the
        // NSHostingController default). The pill draws at its intrinsic width per
        // state, so the window never clips a label — this is the fix for GC-1's
        // truncation bug (the old window was pinned to a too-narrow 520pt).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 466, height: 96),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false   // the SwiftUI pill draws its own soft gold glow
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces,
                                     .stationary,
                                     .ignoresCycle,
                                     .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        // When the content resizes (a state change widens/narrows the pill), keep
        // it pinned bottom-centre. Drags only move the window (didMove), so this
        // doesn't fight `isMovableByWindowBackground`.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let w = self.window else { return }
                self.positionAtBottomCenter(w)
            }
        }
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

    /// Per-state intrinsic width (matches `prototype/VoiceNotePill.dc.html`:
    /// recording 410, transcribing 372, saved 466). The Saved state widens when a
    /// "Tasks" button is also present. The window auto-sizes to this, so labels
    /// never truncate — that's the GC-1 fix.
    private var pillWidth: CGFloat {
        switch controller.state {
        case .recording:                    return 410
        case .meetingRecording:             return 540
        case .transcribing:                 return 372
        case .done(let note, _):            return controller.taskReadyNoteIDs.contains(note.id) ? 540 : 466
        case .error:                        return 380
        case .hidden:                       return 410
        }
    }

    var body: some View {
        content
            .frame(width: pillWidth, alignment: .leading)
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#221b1a") ?? .black,
                                                  Color(hex: "#191420") ?? .black],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(NDS.gold.opacity(0.26), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 30, y: 22)
            .shadow(color: NDS.gold.opacity(0.10), radius: 8)
            .padding(20)   // breathing room inside the window for the soft glow
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .hidden:
            EmptyView()
        case .recording(let startedAt):
            RecordingPill(startedAt: startedAt, controller: controller)
        case .meetingRecording(let startedAt):
            MeetingRecordingPill(startedAt: startedAt, controller: controller)
        case .transcribing:
            TranscribingPill(controller: controller)
        case .done(let note, let transcript):
            DonePill(note: note, transcript: transcript, controller: controller)
        case .error(let msg):
            ErrorPill(message: msg, controller: controller)
        }
    }
}

// MARK: - Shared pill chrome

/// 2×3 dot drag-grip on the leading edge (prototype `gripIcon`).
@available(macOS 14.0, *)
private struct PillGrip: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(NDS.textTertiary).frame(width: 2.6, height: 2.6)
                    }
                }
            }
        }
        .frame(width: 16)
        .accessibilityHidden(true)
    }
}

/// 40×40 round status badge (recording dot / spinner / check).
@available(macOS 14.0, *)
private struct PillBadge<Content: View>: View {
    let fill: Color
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack { Circle().fill(fill); content() }
            .frame(width: 40, height: 40)
    }
}

/// The shared ghost "×" dismiss button (30×30, all states).
@available(macOS 14.0, *)
private struct PillDismiss: View {
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .scaledFont(12, weight: .semibold)
                .foregroundStyle(NDS.textTertiary)
                .frame(width: 30, height: 30)
                .background(NDS.textPrimary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .help(help)
    }
}

/// 32pt action button used in the Saved state (Copy = neutral, Open/Tasks = lilac).
@available(macOS 14.0, *)
private struct PillActionButton: View {
    enum Kind { case neutral, lilac }
    let label: String
    let systemImage: String
    let kind: Kind
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).scaledFont(12, weight: .semibold)
                Text(label).scaledFont(12.5, weight: .bold).fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(kind == .lilac ? NDS.lilac : NDS.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(kind == .lilac ? NDS.lilacSoft : NDS.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(kind == .lilac ? NDS.lilac.opacity(0.3) : NDS.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// Pulsing danger dot inside the 40px recording badge (prototype `rec-pulse`).
@available(macOS 14.0, *)
private struct RecPulseDot: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle()
            .fill(NDS.danger)
            .frame(width: 13, height: 13)
            .opacity(on ? 0.45 : 1)
            .scaleEffect(on ? 0.82 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

@available(macOS 14.0, *)
private struct RecordingPill: View {
    let startedAt: Date
    @ObservedObject var controller: FloatingOverlayController
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 11) {
            PillGrip()
            PillBadge(fill: NDS.danger.opacity(0.16)) { RecPulseDot() }
            VStack(alignment: .leading, spacing: 1) {
                Text("Voice note")
                    .scaledFont(14, weight: .bold).foregroundStyle(NDS.textPrimary)
                    .lineLimit(1)
                Text("Recording · \(elapsedString())")
                    .scaledFont(12, weight: .semibold).monospacedDigit()
                    .foregroundStyle(NDS.gold)
                    .lineLimit(1).truncationMode(.tail)
                if let dest = dictationDestination {
                    DictationDestinationLabel(destination: dest)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            AudioLevelMeter(level: controller.manager?.recordingMonitor.voiceNoteLevel ?? 0,
                            tint: NDS.gold, bars: 16, height: 26)
                .fixedSize()
            Button(action: controller.stopRecording) {
                Image(systemName: "stop.fill")
                    .scaledFont(15, weight: .bold).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(NDS.danger, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: NDS.danger.opacity(0.4), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .help("Stop & transcribe")
            PillDismiss(help: "Cancel (discard)", action: controller.cancelOverlay)
        }
        .onReceive(timer) { now = $0 }
    }

    private func elapsedString() -> String {
        let s = Int(now.timeIntervalSince(startedAt))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Destination for the active capture — but only when the live recording is
    /// a hotkey dictation (which can paste). UI-button voice notes always just
    /// save, so they show no destination line.
    private var dictationDestination: QuickDictation.Destination? {
        guard let dictation = controller.manager?.dictation,
              case .recording = dictation.state else { return nil }
        return dictation.destination
    }
}

/// Glanceable, subtle line under the timer telling the user where this capture
/// will land — typed into the frontmost app, or saved to Notes only. The trust
/// win for U2-7: a private thought can't silently paste into a shared chat.
@available(macOS 14.0, *)
private struct DictationDestinationLabel: View {
    let destination: QuickDictation.Destination

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName).scaledFont(9, weight: .semibold)
            Text(text).scaledFont(10, weight: .medium, relativeTo: .caption2)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var iconName: String {
        switch destination {
        case .paste:    return "arrow.right"
        case .saveOnly: return "lock.fill"
        }
    }

    private var text: String {
        switch destination {
        case .paste(let app): return "types into \(app)"
        case .saveOnly:       return "saves to Notes"
        }
    }
}

@available(macOS 14.0, *)
private struct MeetingRecordingPill: View {
    let startedAt: Date
    @ObservedObject var controller: FloatingOverlayController
    @State private var now = Date()
    @State private var showNote = false
    @State private var note = ""
    @State private var noteFlash: String?
    @FocusState private var noteFocused: Bool
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                PillGrip()
                PillBadge(fill: NDS.danger.opacity(0.16)) { RecPulseDot() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.manager?.activeMeeting?.displayTitle ?? "Recording meeting")
                        .scaledFont(14, weight: .bold).foregroundStyle(NDS.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("Recording · \(elapsedString())")
                            .scaledFont(12, weight: .semibold).monospacedDigit()
                            .foregroundStyle(NDS.gold)
                        if let live = controller.manager?.liveTranscriber {
                            Text("·").foregroundStyle(NDS.textTertiary)
                            LiveTranscribeBadge(transcriber: live, startedAt: startedAt)
                        }
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                PillActionButton(label: "Note", systemImage: "note.text.badge.plus", kind: .neutral) {
                    showNote.toggle(); if showNote { noteFocused = true }
                }
                PillActionButton(label: "Open", systemImage: "arrow.up.right",
                                 kind: .lilac, action: controller.openLiveMeeting)
                Button(action: controller.stopRecording) {
                    Image(systemName: "stop.fill")
                        .scaledFont(15, weight: .bold).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(NDS.danger, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .shadow(color: NDS.danger.opacity(0.4), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .help("Stop recording")
                PillDismiss(help: "Hide overlay (recording continues)", action: controller.cancelOverlay)
            }

            if let p = controller.meetingSilencePrompt {
                SilenceContinueBanner(prompt: p,
                                      onKeep: { controller.manager?.keepRecordingDespiteSilence() },
                                      onStop: { controller.stopRecording() })
            }

            if showNote {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle").foregroundStyle(NDS.textTertiary)
                    TextField("Add a note to this meeting…", text: $note)
                        .textFieldStyle(.plain).scaledFont(12.5)
                        .foregroundStyle(NDS.textPrimary)
                        .focused($noteFocused)
                        .onSubmit(submitNote)
                    if let flash = noteFlash {
                        Text(flash).font(NDS.tiny).foregroundStyle(NDS.mint)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(NDS.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(NDS.hairline, lineWidth: 1))
            }
        }
        .onReceive(timer) { now = $0 }
    }

    private func submitNote() {
        let stamp = controller.addLiveNote(note)
        note = ""
        withAnimation { noteFlash = stamp ?? "Saved" }
        let token = noteFlash
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if noteFlash == token { withAnimation { noteFlash = nil; showNote = false } }
        }
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
        HStack(spacing: 11) {
            PillGrip()
            PillBadge(fill: NDS.gold.opacity(0.12)) {
                ProgressView().controlSize(.small).tint(NDS.gold) // design-lint:allow
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Transcribing")
                    .scaledFont(14, weight: .bold).foregroundStyle(NDS.textPrimary)
                // Wraps to two lines — must never truncate (GC-1 anti-truncation rule).
                Text("Whisper is running locally · usually a few seconds")
                    .scaledFont(12).foregroundStyle(NDS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            PillDismiss(help: "Cancel", action: controller.cancelOverlay)
        }
    }
}

@available(macOS 14.0, *)
private struct DonePill: View {
    let note: QuickNote
    let transcript: String
    @ObservedObject var controller: FloatingOverlayController
    @State private var copiedFlash = false

    private var hasTasks: Bool { controller.taskReadyNoteIDs.contains(note.id) }

    private var snippet: String {
        let s = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Saved to Voice Notes" : s
    }

    var body: some View {
        HStack(spacing: 11) {
            PillGrip()
            PillBadge(fill: NDS.mint.opacity(0.18)) {
                Image(systemName: "checkmark").scaledFont(15, weight: .bold).foregroundStyle(NDS.mint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Voice note saved")
                    .scaledFont(14, weight: .bold).foregroundStyle(NDS.textPrimary)
                    .lineLimit(1)
                Text(snippet)
                    .scaledFont(12).foregroundStyle(NDS.textTertiary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if hasTasks {
                PillActionButton(label: "Tasks", systemImage: "checklist", kind: .lilac) {
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(
                        name: .meetingScribeOpenVoiceNote, object: nil,
                        userInfo: ["id": note.id, "focusTasks": true])
                    controller.cancelOverlay()
                }
            }
            PillActionButton(label: copiedFlash ? "Copied" : "Copy",
                             systemImage: copiedFlash ? "checkmark" : "doc.on.doc",
                             kind: .neutral) {
                controller.copyTranscript()
                copiedFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedFlash = false }
            }
            PillActionButton(label: "Open", systemImage: "arrow.up.right",
                             kind: .lilac, action: controller.goToRecording)
            PillDismiss(help: "Dismiss", action: controller.cancelOverlay)
        }
    }
}

@available(macOS 14.0, *)
private struct ErrorPill: View {
    let message: String
    @ObservedObject var controller: FloatingOverlayController
    var body: some View {
        HStack(spacing: 11) {
            PillGrip()
            PillBadge(fill: NDS.danger.opacity(0.16)) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .scaledFont(15, weight: .bold).foregroundStyle(NDS.danger)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Voice note error")
                    .scaledFont(14, weight: .bold).foregroundStyle(NDS.textPrimary)
                    .lineLimit(1)
                Text(message)
                    .scaledFont(12).foregroundStyle(NDS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            PillDismiss(help: "Dismiss", action: controller.cancelOverlay)
        }
    }
}

extension Notification.Name {
    /// Posted by FloatingOverlay's "Go to Recording" button. userInfo["id"]
    /// = QuickNote.id. MainWindow listens and switches to Notes tab +
    /// selects that note.
    static let meetingScribeOpenVoiceNote = Notification.Name("MeetingScribeOpenVoiceNote")

    /// Posted by the floating meeting pill's "Open" button. Handled at the app
    /// level (the main window may be closed): reopen + activate the window and
    /// route to the live meeting.
    static let meetingScribeOpenLiveMeeting = Notification.Name("MeetingScribeOpenLiveMeeting")

    /// Posted by `QuickNotesController` after a task-mode voice note finishes
    /// extracting tasks. userInfo: id (QuickNote.id), count (Int), title (String).
    /// Drives the toast notification + opens the note's Recommended Tasks
    /// section when the user clicks See Tasks.
    static let meetingScribeVoiceNoteTasksReady = Notification.Name("MeetingScribeVoiceNoteTasksReady")
}
