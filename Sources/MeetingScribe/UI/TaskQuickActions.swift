import SwiftUI

/// Shared right-click quick-edit menu for a task, used by EVERY action-item
/// view (list, table, board, gallery, calendar) so a user can change status,
/// priority, project, and — new — add/remove labels without opening the task.
///
/// It's a plain `View` whose `body` is a set of menu controls, so it drops
/// straight into a `.contextMenu { TaskQuickMenu(...) }`. All edits go through
/// `ActionItemStore` directly; the optional `onOpen` adds an "Open" item for
/// views where double-click isn't wired.
@available(macOS 14.0, *)
struct TaskQuickMenu: View {
    let item: ActionItem
    @ObservedObject var store: ActionItemStore
    /// When provided, adds an "Open" entry (handy on cards without a tap-to-open).
    var onOpen: (() -> Void)? = nil

    private var assigned: Set<String> { Set(item.labelIDs ?? []) }

    var body: some View {
        if let onOpen {
            Button { onOpen() } label: { Label("Open", systemImage: "arrow.up.forward.square") }
            Divider()
        }

        Button {
            store.setStatus(item.id, status: item.status == .completed ? .open : .completed)
        } label: {
            Label(item.status == .completed ? "Mark open" : "Mark done",
                  systemImage: item.status == .completed ? "circle" : "checkmark.circle.fill")
        }

        Menu("Status") {
            ForEach(ActionItem.Status.allCases) { s in
                Button { store.setStatus(item.id, status: s) } label: {
                    Label(s.label, systemImage: item.status == s ? "checkmark" : s.systemImage)
                }
            }
        }

        Menu("Priority") {
            ForEach(ActionItem.Priority.allCases) { p in
                Button { store.setPriority(item.id, priority: p) } label: {
                    Label(p.label, systemImage: item.priority == p ? "checkmark" : "circle")
                }
            }
        }

        // Add / remove labels in place — the headline of this feature. Toggling
        // an existing label adds it (checkmark) or removes it. New labels are
        // still created from the task detail (a menu can't take free text).
        Menu("Labels") {
            if store.labels.isEmpty {
                Text("No labels yet — create one in the task")
            } else {
                ForEach(store.labels) { l in
                    Button { store.toggleLabel(item.id, labelID: l.id) } label: {
                        Label(l.name, systemImage: assigned.contains(l.id) ? "checkmark" : "tag")
                    }
                }
            }
        }

        if !store.projects.isEmpty {
            Menu("Move to project") {
                Button("No project") { store.setProject(item.id, projectID: nil) }
                Divider()
                ForEach(store.projects) { p in
                    Button(p.name) { store.setProject(item.id, projectID: p.id) }
                }
            }
        }

        Divider()
        Button(role: .destructive) {
            let id = item.id, title = item.title
            store.delete(id)
            ToastCenter.shared.show("Deleted “\(title)”", undoTitle: "Undo") { store.restore(id) }
        } label: { Label("Delete", systemImage: "trash") }
    }
}

@available(macOS 14.0, *)
extension View {
    /// Attaches the shared quick-edit context menu and a double-click-to-open
    /// gesture to any task row/card. `simultaneousGesture` is used so the
    /// double-click coexists with a card's drag gesture (board) and with any
    /// existing single-tap handler.
    func taskQuickActions(item: ActionItem,
                          store: ActionItemStore,
                          onOpen: @escaping () -> Void) -> some View {
        self
            .contextMenu { TaskQuickMenu(item: item, store: store, onOpen: onOpen) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
    }
}
