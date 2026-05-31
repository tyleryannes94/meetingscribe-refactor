import SwiftUI
import AppKit

/// Compact action-items list shown on the Today page. Surfaces action
/// items from today's + yesterday's calls. Click an item to mark it
/// complete or open the full Action Items tab for deeper edits.
@available(macOS 14.0, *)
struct ActionItemsWidget: View {
    @ObservedObject var store: ActionItemStore
    /// Called when the user clicks "Open all" to switch the host view to
    /// the dedicated Action Items tab.
    var onOpenFull: () -> Void

    @State private var showCompleted = false

    private var items: [ActionItem] {
        let base = store.todayAndYesterday()
        return showCompleted ? base : base.filter { $0.status != .completed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    ForEach(items.prefix(8)) { item in
                        row(item)
                    }
                }
                if items.count > 8 {
                    Button {
                        onOpenFull()
                    } label: {
                        Text("+ \(items.count - 8) more — open all")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NDS.brand)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NDS.fieldBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(NDS.hairline, lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .foregroundStyle(NDS.brand)
                Text("Action items").font(.headline)
                Text("today & yesterday").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle(isOn: $showCompleted) {
                Text("Done").font(.caption2)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Button {
                onOpenFull()
            } label: {
                Label("Open", systemImage: "arrow.up.right")
                    .labelStyle(.titleOnly)
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.green)
            Text(allDoneMessage)
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var allDoneMessage: String {
        if store.todayAndYesterday().isEmpty {
            return "No action items from yesterday or today yet. They appear here automatically as meetings get summarized."
        }
        return "All clear — every action item from today and yesterday is done."
    }

    private func row(_ item: ActionItem) -> some View {
        HStack(spacing: 10) {
            Button {
                let next: ActionItem.Status = (item.status == .completed) ? .open : .completed
                store.setStatus(item.id, status: next)
            } label: {
                Image(systemName: item.status.systemImage)
                    .foregroundStyle(statusColor(item.status))
                    .font(.callout)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption)
                    .strikethrough(item.status == .completed)
                    .foregroundStyle(item.status == .completed ? .secondary : .primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let owner = item.owner, !owner.isEmpty {
                        Text(owner).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text("·").foregroundStyle(.tertiary)
                    Text(item.meetingTitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if let due = item.dueDate {
                        Text("·").foregroundStyle(.tertiary)
                        Text(dueText(due))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(dueColor(due, status: item.status))
                    }
                }
            }
            Spacer(minLength: 0)
            priorityPip(item.priority)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenFull() }
    }

    private func priorityPip(_ p: ActionItem.Priority) -> some View {
        Circle()
            .fill(color(for: p))
            .frame(width: 6, height: 6)
            .help("Priority: \(p.label)")
    }
    private func color(for p: ActionItem.Priority) -> Color {
        switch p {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
    private func statusColor(_ s: ActionItem.Status) -> Color {
        switch s {
        case .open: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        }
    }
    private func dueText(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "today" }
        if cal.isDateInTomorrow(d) { return "tomorrow" }
        if cal.isDateInYesterday(d) { return "yesterday" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }
    private func dueColor(_ d: Date, status: ActionItem.Status) -> Color {
        guard status != .completed else { return .secondary }
        return d < Calendar.current.startOfDay(for: Date()) ? .red : .secondary
    }
}
