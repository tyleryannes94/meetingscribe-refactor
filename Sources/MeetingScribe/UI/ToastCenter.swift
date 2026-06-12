import SwiftUI

/// Bottom toasts with optional Undo + a secondary action (Toast v2, D3-12).
/// Now stacks (up to 3), pauses auto-dismiss on hover, and supports a second
/// action button (e.g. "Add note" alongside "Undo"). Gives otherwise-irreversible
/// operations a safety net and quick follow-ups.
@available(macOS 14.0, *)
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let undoTitle: String?
        let undo: (() -> Void)?
        let actionTitle: String?
        let action: (() -> Void)?
    }

    /// The visible stack, oldest first. Newest is shown at the bottom.
    @Published private(set) var toasts: [Toast] = []
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    private let lifetime: UInt64 = 6_000_000_000

    func show(_ message: String,
              undoTitle: String? = nil, undo: (() -> Void)? = nil,
              actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let toast = Toast(message: message, undoTitle: undoTitle, undo: undo,
                          actionTitle: actionTitle, action: action)
        toasts.append(toast)
        if toasts.count > 3 { dismiss(toasts.first!.id) }
        schedule(toast.id)
    }

    private func schedule(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: lifetime)
            if !Task.isCancelled { dismiss(id) }
        }
    }

    func performUndo(_ toast: Toast) { toast.undo?(); dismiss(toast.id) }
    func performAction(_ toast: Toast) { toast.action?(); dismiss(toast.id) }

    func dismiss(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        toasts.removeAll { $0.id == id }
    }

    /// Clears every toast (back-compat with the old no-arg dismiss).
    func dismiss() {
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()
        toasts.removeAll()
    }

    /// Hover-pause: stop the auto-dismiss timers while the pointer is over the
    /// stack so the user has time to click Undo/the action.
    func pauseDismissal() { dismissTasks.values.forEach { $0.cancel() } }
    func resumeDismissal() { toasts.forEach { schedule($0.id) } }
}

@available(macOS 14.0, *)
struct ToastOverlay: View {
    @ObservedObject private var center = ToastCenter.shared

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                ForEach(center.toasts) { t in
                    toastView(t)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 28)
            .onHover { hovering in
                if hovering { center.pauseDismissal() } else { center.resumeDismissal() }
            }
        }
        .animation(.easeOut(duration: 0.2), value: center.toasts.map(\.id))
        .allowsHitTesting(!center.toasts.isEmpty)
    }

    private func toastView(_ t: ToastCenter.Toast) -> some View {
        HStack(spacing: 12) {
            Text(t.message).font(.callout).foregroundStyle(.white).lineLimit(2)
            if let title = t.actionTitle, t.action != nil {
                Button(title) { center.performAction(t) }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }
            if let title = t.undoTitle, t.undo != nil {
                Button(title) { center.performUndo(t) }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NDS.brandHover)
            }
            Button { center.dismiss(t.id) } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(Color.black.opacity(0.86), in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
    }
}
