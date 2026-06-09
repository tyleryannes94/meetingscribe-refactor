import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Board (Kanban) view

    var boardBody: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(ActionItem.Status.allCases) { status in
                    boardColumn(status)
                }
            }
            .padding(16)
        }
    }

    /// Cards in a status column, ordered by manual sortIndex (drag order),
    /// falling back to the default sort for items never dragged.
    func columnItems(_ status: ActionItem.Status) -> [ActionItem] {
        projectFiltered.filter { $0.status == status }
            .sorted { a, b in
                let sa = a.sortIndex ?? .greatestFiniteMagnitude
                let sb = b.sortIndex ?? .greatestFiniteMagnitude
                if sa != sb { return sa < sb }
                return sort(a, b)
            }
    }

    func boardColumn(_ status: ActionItem.Status) -> some View {
        let items = columnItems(status)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: status.systemImage)
                Text(status.label).font(.callout.weight(.semibold))
                Text("\(items.count)").font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    let pid = (selectedProjectID == Self.noProjectSentinel) ? nil : selectedProjectID
                    let t = store.createTask(title: "New task", projectID: pid, status: status)
                    selectedTaskID = t.id
                    viewMode = .list
                } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless).help("Add a task to \(status.label)")
                .accessibilityLabel("Add a task to \(status.label)")
            }
            .padding(.horizontal, 4)
            ForEach(items) { item in
                boardCard(item)
                    .draggable(item.id) {
                        Text(item.title).font(.caption).lineLimit(2)
                            .padding(8)
                            .frame(width: 220, alignment: .leading)
                            .background(NDS.fieldBg,
                                        in: RoundedRectangle(cornerRadius: NDS.rowRadius))
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        for id in ids { dropCard(id, toStatus: status, beforeID: item.id) }
                        return true
                    }
            }
            // Tall droppable filler so the whole column accepts a drop (incl.
            // dropping onto an empty column → append at the end).
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 80)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { ids, _ in
                    for id in ids { dropCard(id, toStatus: status, beforeID: nil) }
                    return true
                }
        }
        .frame(width: 280, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(8)
        .background(NDS.columnBg,
                    in: RoundedRectangle(cornerRadius: NDS.cardRadius))
    }

    /// Moves `id` into `status` and reorders it just before `beforeID` (or to
    /// the end when nil), using a midpoint sortIndex so neighbors don't shift.
    func dropCard(_ id: String, toStatus status: ActionItem.Status, beforeID: String?) {
        guard id != beforeID, store.items.contains(where: { $0.id == id }) else { return }
        let col = columnItems(status).filter { $0.id != id }
        let targetIndex: Int = {
            if let beforeID, let idx = col.firstIndex(where: { $0.id == beforeID }) { return idx }
            return col.count
        }()
        let prev = targetIndex > 0 ? col[targetIndex - 1].sortIndex : nil
        let next = targetIndex < col.count ? col[targetIndex].sortIndex : nil
        let newIndex: Double = {
            switch (prev, next) {
            case let (p?, n?): return (p + n) / 2
            case let (p?, nil): return p + 1
            case let (nil, n?): return n - 1
            case (nil, nil): return 0
            }
        }()
        let current = store.items.first { $0.id == id }
        if current?.status != status { store.setStatus(id, status: status) }
        store.setSortIndex(id, sortIndex: newIndex)
    }

    private static let dueFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    func boardCard(_ item: ActionItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let itemLabels = store.labels(for: item)
            if !itemLabels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(itemLabels) { l in
                        Capsule().fill(Color(hex: l.colorHex) ?? .gray)
                            .frame(width: 22, height: 4)
                    }
                }
            }
            Text(item.title).font(.caption).lineLimit(3)
                .strikethrough(item.status == .completed)
            if item.subtaskProgress.total > 0 {
                Label("\(item.subtaskProgress.done)/\(item.subtaskProgress.total)", systemImage: "checklist")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(item.priority.label)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(priorityColor(item.priority).opacity(0.16), in: Capsule())
                    .foregroundStyle(priorityColor(item.priority))
                if let due = item.dueDate {
                    let overdue = due < Calendar.current.startOfDay(for: Date()) && item.status != .completed
                    let isToday = Calendar.current.isDateInToday(due)
                    Label(Self.dueFormatter.string(from: due), systemImage: "calendar")
                        .labelStyle(.titleOnly)
                        .font(.caption2)
                        .foregroundStyle(overdue ? Color.red : (isToday ? Color.orange : Color.secondary))
                }
                if let name = store.project(for: item)?.name {
                    Text(name).font(.caption2).foregroundStyle(NDS.brand).lineLimit(1)
                }
                if let owner = item.owner, !owner.isEmpty {
                    TaskOwnerAvatar(name: owner, size: 16)
                }
                Spacer()
                Menu {
                    ForEach(ActionItem.Status.allCases) { s in
                        Button(s.label) { store.setStatus(item.id, status: s) }
                    }
                    Divider()
                    projectMenuItems(for: item)
                    Divider()
                    Button(role: .destructive) {
                        let id = item.id, title = item.title
                        store.delete(id)
                        ToastCenter.shared.show("Deleted “\(title)”", undoTitle: "Undo") { store.restore(id) }
                    } label: { Text("Delete") }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
            }
            Text(item.meetingTitle).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius)
            .strokeBorder(NDS.hairline, lineWidth: 0.5))
        .opacity(item.status == .completed ? 0.6 : 1)
    }
}
