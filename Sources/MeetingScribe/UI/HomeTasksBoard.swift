import SwiftUI

/// A compact Kanban board of all open tasks, shown on the home (Today) page.
/// Columns are task statuses; each has a one-tap "Add task" button (Notion /
/// Trello style), and there's an "Add task" button at the top of the board.
/// Tapping a card — or "Add task" — deep-links into the Tasks tab via
/// `WorkspaceRouter.pendingTaskID`. Meeting-extracted items awaiting triage are
/// excluded (they live in the Triage inbox until accepted).
@available(macOS 14.0, *)
struct HomeTasksBoard: View {
    @ObservedObject var store: ActionItemStore
    @EnvironmentObject private var router: WorkspaceRouter

    /// Active work plus a Done column so cards have somewhere to land.
    private let columns: [ActionItem.Status] = [.open, .inProgress, .completed]

    private func items(_ status: ActionItem.Status) -> [ActionItem] {
        store.items
            .filter { !$0.needsTriage && $0.status == status }
            .sorted { a, b in
                let sa = a.sortIndex ?? .greatestFiniteMagnitude
                let sb = b.sortIndex ?? .greatestFiniteMagnitude
                if sa != sb { return sa < sb }
                return a.createdAt > b.createdAt
            }
    }

    private func openTask(_ id: String) {
        router.pendingTaskID = id
        router.section = .actions
    }

    private func addTask(_ status: ActionItem.Status) {
        let t = store.createTask(title: "New task", status: status)
        openTask(t.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tasks board", systemImage: "rectangle.split.3x1")
                    .font(.headline).foregroundStyle(NDS.textPrimary)
                Spacer()
                Button { addTask(.open) } label: {
                    Label("Add task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { column($0) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius))
    }

    private func column(_ status: ActionItem.Status) -> some View {
        let list = items(status)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(NDS.status(status)).frame(width: 8, height: 8)
                Text(status.label).font(.callout.weight(.semibold))
                Text("\(list.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer()
                Button { addTask(status) } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add a task to \(status.label)")
            }
            if list.isEmpty {
                Text("Nothing here").font(.caption2).foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(list.prefix(8)) { card($0) }
                if list.count > 8 {
                    Text("+\(list.count - 8) more").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 240, alignment: .topLeading)
        .background(NDS.columnBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius))
    }

    private func card(_ item: ActionItem) -> some View {
        let labels = store.labels(for: item)
        return VStack(alignment: .leading, spacing: 4) {
            if !labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(labels.prefix(5)) { l in
                        Capsule().fill(Color(hex: l.colorHex) ?? .gray).frame(width: 20, height: 4)
                    }
                }
            }
            Text(item.title).font(.caption).lineLimit(2)
                .strikethrough(item.status == .completed)
            HStack(spacing: 6) {
                MSPriorityBadge(priority: item.priority, showLabel: false)
                if item.dueDate != nil {
                    DueChip(date: item.dueDate, status: item.status, style: .plain)
                }
                Spacer(minLength: 0)
                if let owner = item.owner, !owner.isEmpty {
                    TaskOwnerAvatar(name: owner, size: 16)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius)
            .strokeBorder(NDS.hairline, lineWidth: 0.5))
        .opacity(item.status == .completed ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { openTask(item.id) }
        .contextMenu { TaskQuickMenu(item: item, store: store, onOpen: { openTask(item.id) }) }
    }
}
