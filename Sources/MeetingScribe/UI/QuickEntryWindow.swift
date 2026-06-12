import SwiftUI
import AppKit

/// U2-5 — Global Quick Entry (Things-style), live-meeting aware.
///
/// A 4th global hotkey opens a small floating panel with ONE text field wired
/// straight to the task store's natural-language quick-add parser — WITHOUT
/// activating the main app. The flow is: hotkey → type → Enter → back to
/// whatever you were doing, ~3 seconds, zero alt-tab.
///
/// The panel is an `NSPanel` with `.nonactivatingPanel`, so it can become key
/// (and accept keystrokes) without pulling MeetingScribe to the foreground —
/// mid-Zoom you stay in Zoom. The recipe mirrors `FloatingOverlayController`'s
/// floating window, but adds keyboard focus (the overlay never needs input).
///
/// Live-meeting awareness: if a recording is in progress when you capture, the
/// new task is annotated with an elapsed-time note pointing at that meeting, so
/// "fix the typo Sarah mentioned" lands with "Captured 12:34 into …" attached.
@available(macOS 14.0, *)
@MainActor
final class QuickEntryController: ObservableObject {
    private(set) weak var manager: MeetingManager?
    private var panel: NSPanel?

    /// Live-meeting context captured at the moment the panel opens. Nil when no
    /// recording is in progress → the entry is just a plain quick-add.
    @Published private(set) var liveMeetingTitle: String?
    private var liveStartedAt: Date?

    func attach(to manager: MeetingManager) {
        self.manager = manager
    }

    // MARK: - Show / hide

    /// Hotkey action: open if closed, close if already open (acts as a toggle so
    /// a double-press dismisses without reaching for the mouse).
    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        captureLiveContext()
        let panel = makePanel()
        self.panel = panel
        positionAtTopCenter(panel)
        // Key (so the field gets keystrokes) WITHOUT activating the app — the
        // .nonactivatingPanel style mask makes this not steal focus from Zoom.
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        liveMeetingTitle = nil
        liveStartedAt = nil
    }

    // MARK: - Submit

    /// Enter handler: push the raw string through the same quick-add parser the
    /// Tasks tab uses, so `!priority #label @person friday` grammar all works.
    func submit(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let manager else { hide(); return }

        let created = manager.actionItems.createTask(parsing: trimmed)

        // Live-meeting link: attach an elapsed-time note so the capture is tied
        // back to the meeting it was taken during. Graceful no-op otherwise.
        if let startedAt = liveStartedAt {
            let elapsed = Self.elapsedString(since: startedAt)
            let title = liveMeetingTitle ?? "the live recording"
            manager.actionItems.setNotes(
                created.id,
                notes: "Captured \(elapsed) into “\(title)”."
            )
        }
        hide()
    }

    var elapsedSinceStart: String? {
        guard let liveStartedAt else { return nil }
        return Self.elapsedString(since: liveStartedAt)
    }

    // MARK: - Helpers

    private func captureLiveContext() {
        guard let manager, case .recording(let meeting, let startedAt) = manager.state else {
            liveMeetingTitle = nil
            liveStartedAt = nil
            return
        }
        liveStartedAt = startedAt
        let title = meeting?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        liveMeetingTitle = title.isEmpty ? "Recording in progress" : title
    }

    private static func elapsedString(since startedAt: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(rootView: QuickEntryView(controller: self))
        hosting.view.wantsLayer = true
        let panel = QuickEntryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 96),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces,
                                    .stationary,
                                    .ignoresCycle,
                                    .fullScreenAuxiliary]
        return panel
    }

    private func positionAtTopCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        // Sit in the upper third — clear of the bottom voice-note overlay and
        // close to where the eye expects a Spotlight-style capture bar.
        let y = frame.maxY - size.height - (frame.height * 0.22)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// NSPanel subclass that can become key while borderless — required so the text
/// field receives keystrokes. Without this override a borderless panel refuses
/// key status and typing goes nowhere.
@available(macOS 14.0, *)
private final class QuickEntryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - View

@available(macOS 14.0, *)
private struct QuickEntryView: View {
    @ObservedObject var controller: QuickEntryController
    @State private var text = ""
    @State private var now = Date()
    @FocusState private var focused: Bool
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = controller.liveMeetingTitle {
                liveChip(title: title)
            }
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .scaledFont(18, weight: .semibold)
                    .foregroundStyle(NDS.brand)
                TextField("Add a task or note…", text: $text)
                    .textFieldStyle(.plain)
                    .font(NDS.body)
                    .foregroundStyle(NDS.textPrimary)
                    .focused($focused)
                    .onSubmit { submit() }
            }
            Text("Add !priority, #label, @person, or a date like “friday”. Esc to dismiss.")
                .font(NDS.tiny)
                .foregroundStyle(NDS.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 0.5)
        )
        .padding(10)
        .onAppear { focused = true }
        .onExitCommand { controller.hide() }
        .onReceive(timer) { now = $0 }
    }

    private func liveChip(title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
            Text("Linking to “\(title)”")
                .scaledFont(11, weight: .semibold, relativeTo: .caption2)
                .foregroundStyle(NDS.textSecondary)
                .lineLimit(1)
            if let elapsed = controller.elapsedSinceStart {
                Text("· \(elapsed)")
                    .font(NDS.tiny.monospacedDigit())
                    .foregroundStyle(NDS.gold)
            }
        }
        // `now` drives the elapsed label so the chip ticks while open.
        .id(now.timeIntervalSinceReferenceDate.rounded())
    }

    private func submit() {
        controller.submit(text)
        text = ""
    }
}
