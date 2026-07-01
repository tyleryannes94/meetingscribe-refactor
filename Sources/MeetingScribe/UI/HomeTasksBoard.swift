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

    /// Focus filter (1-4): time horizon + workspace context.
    @State private var timeScope: TimeScope = .all
    @State private var activeContextID: String?

    enum TimeScope: String, CaseIterable, Identifiable {
        case today, thisWeek, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return "Today"
            case .thisWeek: return "This Week"
            case .all: return "All"
            }
        }
    }

    private func matchesScope(_ item: ActionItem) -> Bool {
        // Context filter (1-4): resolve via the task's project → initiative.
        if let cid = activeContextID, store.effectiveContextID(for: item) != cid { return false }
        // Time filter (1-4). In-progress always shows so active work isn't hidden.
        switch timeScope {
        case .all: return true
        case .today:
            if item.status == .inProgress { return true }
            return item.dueDate.map { Calendar.current.isDateInToday($0) } ?? false
        case .thisWeek:
            if item.status == .inProgress { return true }
            guard let due = item.dueDate else { return false }
            let horizon = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            return due >= Calendar.current.startOfDay(for: Date()) && due <= horizon
        }
    }

    private func items(_ status: ActionItem.Status) -> [ActionItem] {
        store.items
            .filter { !$0.needsTriage && $0.status == status && matchesScope($0) }
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
                .buttonStyle(MSPrimaryButtonStyle()).controlSize(.small) // design-lint:allow
            }
            filterBar
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

    /// Time + context focus pills (1-4).
    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(TimeScope.allCases) { ts in
                pill(ts.label, active: timeScope == ts) { timeScope = ts }
            }
            if !store.contexts.isEmpty {
                Divider().frame(height: 14).overlay(NDS.divider)
                pill("All", active: activeContextID == nil) { activeContextID = nil }
                ForEach(store.sortedContexts()) { c in
                    pill(c.name, active: activeContextID == c.id, color: store.contextColor(id: c.id)) {
                        activeContextID = (activeContextID == c.id) ? nil : c.id
                    }
                }
            }
            Spacer()
        }
    }

    private func pill(_ title: String, active: Bool, color: Color? = nil,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption2.weight(active ? .semibold : .regular))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(active ? (color ?? NDS.brand).opacity(0.16) : NDS.columnBg, in: Capsule())
                .foregroundStyle(active ? (color ?? NDS.brand) : NDS.textSecondary)
        }
        .buttonStyle(.plain)
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
                // Scroll the whole column (1-4) instead of capping at 8 with a
                // dead "+N more" label.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) { ForEach(list) { card($0) } }
                }
                .frame(maxHeight: 400)
            }
        }
        .padding(10)
        .frame(width: 240, alignment: .topLeading)
        .background(NDS.columnBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius))
    }

    private func card(_ item: ActionItem) -> some View {
        let labels = store.labels(for: item)
        return VStack(alignment: .leading, spacing: 4) {
            // Workspace-context stripe (1-5).
            if let cColor = store.contextColor(for: item) {
                RoundedRectangle(cornerRadius: 1.5).fill(cColor).frame(height: 3)
            }
            if !labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(labels.prefix(5)) { l in
                        Capsule().fill(Color(hex: l.colorHex) ?? .gray).frame(width: 20, height: 4)
                    }
                }
            }
            HStack(alignment: .top, spacing: 4) {
                Text(item.title).font(.caption).lineLimit(2)
                    .strikethrough(item.status == .completed)
                Spacer(minLength: 4)
                TaskSourceBadge(item: item)
            }
            HStack(spacing: 6) {
                MSPriorityBadge(priority: item.priority, showLabel: false)
                if item.dueDate != nil {
                    DueChip(date: item.dueDate, status: item.status, style: .plain)
                }
                if item.recurrence != nil {
                    Image(systemName: "repeat").font(.caption2).foregroundStyle(NDS.brand)
                }
                Spacer(minLength: 0)
                if let owner = item.owner, !owner.isEmpty {
                    TaskOwnerAvatar(name: owner, size: 16)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Pin to natural height so sparse columns don't stretch cards tall.
        .fixedSize(horizontal: false, vertical: true)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius)
            .strokeBorder(NDS.hairline, lineWidth: 0.5))
        .opacity(item.status == .completed ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { openTask(item.id) }
        .contextMenu { TaskQuickMenu(item: item, store: store, onOpen: { openTask(item.id) }) }
    }
}
