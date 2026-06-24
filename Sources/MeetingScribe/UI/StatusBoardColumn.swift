import SwiftUI

// MARK: - Reusable status board column
//
// One kanban column keyed on a task status, with drop-target highlight, drag
// reorder, and an add button. Used by the Today board and the Home "Open tasks"
// board (and anywhere else that wants a status board outside the project-scoped
// `boardBody`). The caller supplies the column's items + an `onDrop` that knows
// the right ordering scope, so this view stays scope-agnostic.

@available(macOS 14.0, *)
struct StatusBoardColumn: View {
    let parent: ActionItemsView
    @ObservedObject var store: ActionItemStore
    let status: ActionItem.Status
    let items: [ActionItem]
    /// `(draggedID, beforeID)` — beforeID nil means "append to the end".
    var onDrop: (_ draggedID: String, _ beforeID: String?) -> Void
    var onAdd: () -> Void
    var width: CGFloat = 260

    @State private var targetCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isTargeted: Bool { targetCount > 0 }
    private func setTargeted(_ t: Bool) { targetCount = max(0, targetCount + (t ? 1 : -1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(items) { item in
                parent.boardCard(item)
                    .onTapGesture(count: 2) { parent.env.selectedTaskID = item.id }
                    .onTapGesture { parent.vm.editingID = item.id }
                    .taskQuickActions(item: item, store: store) { parent.env.selectedTaskID = item.id }
                    .draggable(item.id) {
                        Text(item.title).font(.caption).lineLimit(2)
                            .padding(8).frame(width: 220, alignment: .leading)
                            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        for id in ids { onDrop(id, item.id) }
                        return true
                    } isTargeted: { setTargeted($0) }
            }
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 50)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { ids, _ in
                    for id in ids { onDrop(id, nil) }
                    return true
                } isTargeted: { setTargeted($0) }
        }
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(8)
        .background(isTargeted ? NDS.status(status).opacity(0.10) : NDS.columnBg,
                    in: RoundedRectangle(cornerRadius: NDS.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius)
            .strokeBorder(NDS.status(status).opacity(isTargeted ? 0.85 : 0), lineWidth: 1.5))
        .animation(NDS.motion(.easeOut(duration: NDS.motionFast), reduce: reduceMotion), value: isTargeted)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle().fill(NDS.status(status)).frame(width: 8, height: 8)
            Image(systemName: status.systemImage)
                .scaledFont(11, weight: .semibold).foregroundStyle(NDS.status(status))
            Text(status.label).font(.callout.weight(.bold))
            Text("\(items.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            Spacer()
            Button(action: onAdd) { Image(systemName: "plus") }
                .buttonStyle(.borderless).help("Add a task to \(status.label)")
        }
        .padding(.horizontal, 4)
    }
}
