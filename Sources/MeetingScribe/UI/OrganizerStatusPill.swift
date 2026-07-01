import SwiftUI

/// Persistent, app-wide progress indicator for "Organize my Tasks". Shown while
/// the (slow) AI pass runs so the user can keep working — the review modal no
/// longer blocks them. Tapping it opens the modal to watch progress or review
/// results. Stays up after completion (as "N recommendations") until the user
/// clears them, so results are always one click away.
@available(macOS 14.0, *)
struct OrganizerStatusPill: View {
    @ObservedObject var organizer: TaskOrganizer

    private var busy: Bool { organizer.isRunning || organizer.refining }
    private var visible: Bool { busy || organizer.pendingCount > 0 }

    var body: some View {
        Group {
            if visible {
                Button { organizer.isPresentingResults = true } label: { content }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(NDS.springStandard, value: visible)
        .animation(NDS.springStandard, value: busy)
    }

    private var content: some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.small)  // design-lint:allow
                Text("Organizing your tasks…")
                    .scaledFont(12, weight: .semibold).foregroundStyle(NDS.textPrimary)
                Text("tap to watch").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            } else {
                Image(systemName: "wand.and.stars").scaledFont(12, weight: .semibold)
                    .foregroundStyle(NDS.brand)
                Text("\(organizer.pendingCount) task recommendation\(organizer.pendingCount == 1 ? "" : "s")")
                    .scaledFont(12, weight: .semibold).foregroundStyle(NDS.textPrimary)
                Text("review").font(NDS.tiny).foregroundStyle(NDS.brand)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(NDS.fieldBg, in: Capsule())
        .overlay(Capsule().strokeBorder(busy ? NDS.brand.opacity(0.4) : NDS.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .padding(.bottom, 16)
    }
}
