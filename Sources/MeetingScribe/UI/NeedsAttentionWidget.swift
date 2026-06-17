import SwiftUI

/// "Needs attention" — the overdue + due-today open action items, surfaced at
/// the top of Today so the most time-sensitive work is the first thing seen
/// (TDY-2). Distinct from `ActionItemsWidget`, which shows everything from
/// today + yesterday regardless of due date. Renders nothing when empty so it
/// never adds dead space to the feed.
@available(macOS 14.0, *)
struct NeedsAttentionWidget: View {
    @ObservedObject var store: ActionItemStore
    /// Switch the host to the Action Items tab.
    var onOpenFull: () -> Void

    /// Open, dated items that are due today or already overdue, soonest first.
    private var items: [ActionItem] {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        return store.items
            .filter { $0.status != .completed }
            .filter { ($0.dueDate ?? .distantFuture) < endOfToday }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Needs attention").font(.headline)
                    Text("\(items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onOpenFull) {
                        Label("Open", systemImage: "arrow.up.right")
                            .labelStyle(.titleOnly).font(.caption)
                    }
                    .buttonStyle(MSSecondaryButtonStyle()).controlSize(.small)
                    .accessibilityLabel("Open all action items")
                }
                VStack(spacing: 6) {
                    ForEach(items.prefix(6)) { item in row(item) }
                }
                if items.count > 6 {
                    Button(action: onOpenFull) {
                        Text("+ \(items.count - 6) more — open all").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(NDS.brand)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5))
        }
    }

    private func row(_ item: ActionItem) -> some View {
        HStack(spacing: 10) {
            Button {
                store.setStatus(item.id, status: .completed)
            } label: {
                Image(systemName: item.status.systemImage)
                    .foregroundStyle(.orange).font(.callout)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(item.title) done")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.caption).lineLimit(2)
                HStack(spacing: 6) {
                    if !item.meetingTitle.isEmpty {
                        Text(item.meetingTitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        Text("·").foregroundStyle(.tertiary)
                    }
                    if let due = item.dueDate {
                        Text(dueText(due))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(due < Calendar.current.startOfDay(for: Date()) ? .red : .orange)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenFull() }
    }

    private func dueText(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "due today" }
        if cal.isDateInYesterday(d) { return "due yesterday" }
        if d < cal.startOfDay(for: Date()) {
            let days = cal.dateComponents([.day], from: d, to: Date()).day ?? 0
            return "\(days)d overdue"
        }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "due \(f.string(from: d))"
    }
}
