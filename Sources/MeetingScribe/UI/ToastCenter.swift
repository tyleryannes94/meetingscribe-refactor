import SwiftUI

/// Lightweight bottom toast with an optional Undo action (D4-3). Gives
/// otherwise-irreversible operations (e.g. a tag rename that physically moves
/// vault folders) a safety net.
@available(macOS 14.0, *)
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let undoTitle: String?
        let undo: (() -> Void)?
    }

    @Published var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, undoTitle: String? = nil, undo: (() -> Void)? = nil) {
        current = Toast(message: message, undoTitle: undoTitle, undo: undo)
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { current = nil }
        }
    }

    func performUndo() {
        current?.undo?()
        dismiss()
    }

    func dismiss() {
        current = nil
        dismissTask?.cancel()
    }
}

@available(macOS 14.0, *)
struct ToastOverlay: View {
    @ObservedObject private var center = ToastCenter.shared

    var body: some View {
        VStack {
            Spacer()
            if let t = center.current {
                HStack(spacing: 12) {
                    Text(t.message).font(.callout).foregroundStyle(.white).lineLimit(2)
                    if let title = t.undoTitle, t.undo != nil {
                        Button(title) { center.performUndo() }
                            .buttonStyle(.plain)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(NDS.brandHover)
                    }
                    Button { center.dismiss() } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Color.black.opacity(0.86), in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: center.current?.id)
        .allowsHitTesting(center.current != nil)
    }
}
