import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Board (Kanban) view

    var boardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    let pid = (env.selectedProjectID == Self.noProjectSentinel) ? nil : env.selectedProjectID
                    let t = store.createTask(title: "New task", projectID: pid, status: .open)
                    env.selectedTaskID = t.id
                } label: {
                    Label("Add task", systemImage: "plus")
                }
                .buttonStyle(MSPrimaryButtonStyle())
                .help("Create a new task")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(ActionItem.Status.allCases) { status in
                        boardColumn(status)
                    }
                }
                .padding(16)
            }
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
        // The drop-target highlight (D3-5) needs per-column `@State` to track
        // whether a dragged card is hovering this column. `ActionItemsView` is a
        // big shared struct, so the state lives in this small wrapper view
        // instead — it owns `isTargeted` and drives the tint/ring, while the
        // actual move math (`dropCard`) and card rendering stay on the parent.
        BoardColumnView(parent: self,
                        status: status,
                        items: columnItems(status),
                        store: store,
                        selectedTaskID: $env.selectedTaskID,
                        viewMode: $vm.viewMode)
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
        HStack(alignment: .top, spacing: NDS.spaceSM) {
            // Left priority accent bar — redundant with the badge glyph below so
            // priority reads without relying on color alone (AV-4).
            RoundedRectangle(cornerRadius: 2)
                .fill(NDS.priority(item.priority))
                .frame(width: 3)
                .opacity(item.priority == .low ? 0 : 1)
            VStack(alignment: .leading, spacing: 6) {
                // Workspace-context stripe (1-5).
                if let cColor = store.contextColor(for: item) {
                    RoundedRectangle(cornerRadius: 1.5).fill(cColor).frame(height: 3)
                }
                let itemLabels = store.labels(for: item)
                if !itemLabels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(itemLabels) { l in
                            Capsule().fill(Color(hex: l.colorHex) ?? .gray)
                                .frame(width: 22, height: 4)
                        }
                    }
                }
                HStack(alignment: .top, spacing: 4) {
                    Text(item.title).font(.caption).lineLimit(3)
                        .strikethrough(item.status == .completed)
                    Spacer(minLength: 4)
                    TaskSourceBadge(item: item)
                }
                if item.subtaskProgress.total > 0 {
                    Label("\(item.subtaskProgress.done)/\(item.subtaskProgress.total)", systemImage: "checklist")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    MSPriorityBadge(priority: item.priority, showLabel: false)
                    if item.dueDate != nil {
                        DueChip(date: item.dueDate, status: item.status, style: .plain)
                    }
                    if let name = store.project(for: item)?.name {
                        Text(name).font(.caption2).foregroundStyle(NDS.brand).lineLimit(1).help(name)
                    }
                    Spacer(minLength: 4)
                    TaskOwnerChip(item: item, size: 16)
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
                TaskMeetingChip(item: item)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius)
            .strokeBorder(NDS.hairline, lineWidth: 0.5))
        .opacity(item.status == .completed ? 0.6 : 1)
    }
}

// MARK: - Board column with drop-target choreography (D3-5)

/// One kanban column. Owns the `isTargeted` highlight state so that, while a
/// card is dragged over this column, the column background tints to the status
/// color and an accent ring appears — the user can see where the card will land
/// *before* releasing. The move math (`parent.dropCard`) and card rendering
/// (`parent.boardCard`) are unchanged; this view only adds the visual feedback.
@available(macOS 14.0, *)
private struct BoardColumnView: View {
    let parent: ActionItemsView
    let status: ActionItem.Status
    let items: [ActionItem]
    @ObservedObject var store: ActionItemStore
    @Binding var selectedTaskID: String?
    @Binding var viewMode: ActionItemsView.ViewMode

    // A counter rather than a plain Bool: a column holds several drop
    // destinations (one per card + the tail filler), and SwiftUI's
    // enter/exit callbacks for adjacent targets can interleave. Counting
    // keeps the highlight stable as the pointer slides between cards.
    @State private var targetCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isTargeted: Bool { targetCount > 0 }

    /// Increment on enter, decrement on exit; clamp so stray exits can't go
    /// negative and strand the highlight on.
    private func setTargeted(_ targeted: Bool) {
        targetCount = max(0, targetCount + (targeted ? 1 : -1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(items) { item in
                parent.boardCard(item)
                    .taskQuickActions(item: item, store: store) { selectedTaskID = item.id }
                    .draggable(item.id) {
                        Text(item.title).font(.caption).lineLimit(2)
                            .padding(8)
                            .frame(width: 220, alignment: .leading)
                            .background(NDS.fieldBg,
                                        in: RoundedRectangle(cornerRadius: NDS.rowRadius))
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        for id in ids { parent.dropCard(id, toStatus: status, beforeID: item.id) }
                        return true
                    } isTargeted: { setTargeted($0) }
            }
            // Tall droppable filler so the whole column accepts a drop (incl.
            // dropping onto an empty column → append at the end).
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 80)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { ids, _ in
                    for id in ids { parent.dropCard(id, toStatus: status, beforeID: nil) }
                    return true
                } isTargeted: { setTargeted($0) }
        }
        .frame(width: 280, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(8)
        .background(isTargeted ? NDS.status(status).opacity(0.10) : NDS.columnBg,
                    in: RoundedRectangle(cornerRadius: NDS.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: NDS.cardRadius)
                .strokeBorder(NDS.status(status).opacity(isTargeted ? 0.85 : 0),
                              lineWidth: 1.5)
        )
        // Reduce-motion-proof: `NDS.motion` returns nil (instant) when the user
        // has Reduce Motion on, so the tint/ring snaps instead of animating.
        .animation(NDS.motion(.easeOut(duration: NDS.motionFast), reduce: reduceMotion),
                   value: isTargeted)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle().fill(NDS.status(status)).frame(width: 8, height: 8)
            Image(systemName: status.systemImage)
                .scaledFont(11, weight: .semibold).foregroundStyle(NDS.status(status))
            Text(status.label).font(.callout.weight(.bold))
            Text("\(items.count)").font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                let pid = (parent.env.selectedProjectID == ActionItemsView.noProjectSentinel)
                    ? nil : parent.env.selectedProjectID
                let t = store.createTask(title: "New task", projectID: pid, status: status)
                selectedTaskID = t.id
            } label: { Image(systemName: "plus") }
            .buttonStyle(.borderless).help("Add a task to \(status.label)")
            .accessibilityLabel("Add a task to \(status.label)")
        }
        .padding(.horizontal, 4)
    }
}
