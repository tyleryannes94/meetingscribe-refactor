import SwiftUI

/// Presentational owner chip (D4-3): avatar + name, or a muted em dash when a
/// task is unowned. Extracted so the table, and later the card surfaces, render
/// an owner identically.
@available(macOS 14.0, *)
struct TaskOwnerLabel: View {
    let owner: String?

    var body: some View {
        if let owner, !owner.isEmpty {
            HStack(spacing: 5) {
                TaskOwnerAvatar(name: owner, size: 16)
                Text(owner).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } else {
            Text("—").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// Reusable task "meta" cluster (D4-3): priority indicator + due chip + owner,
/// composed from the same shared primitives the table uses (`MSPriorityBadge`,
/// `DueChip`, `TaskOwnerLabel`) so the trio reads identically everywhere.
///
/// Purely presentational — it takes the resolved values, no store. The table is
/// the first consumer of the building blocks below; wiring this combined view
/// into the board/gallery/calendar/list card surfaces is a noted follow-up.
@available(macOS 14.0, *)
struct TaskMetaCluster: View {
    let priority: ActionItem.Priority
    let dueDate: Date?
    let status: ActionItem.Status
    let owner: String?

    /// Convenience: build straight from an `ActionItem`.
    init(item: ActionItem) {
        self.priority = item.priority
        self.dueDate = item.dueDate
        self.status = item.status
        self.owner = item.owner
    }

    init(priority: ActionItem.Priority, dueDate: Date?,
         status: ActionItem.Status, owner: String?) {
        self.priority = priority
        self.dueDate = dueDate
        self.status = status
        self.owner = owner
    }

    var body: some View {
        HStack(spacing: 8) {
            MSPriorityBadge(priority: priority)
            DueChip(date: dueDate, status: status, style: .plain)
            TaskOwnerLabel(owner: owner)
        }
    }
}
