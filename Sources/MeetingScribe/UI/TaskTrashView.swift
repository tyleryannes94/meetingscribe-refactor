import SwiftUI

/// Trash for soft-deleted tasks (P0-3). Lists items the user deleted (kept for
/// `ActionItemStore.trashRetention`, then auto-purged), with one-click Restore
/// or permanent delete, plus Empty Trash. Reached from the Tasks toolbar
/// overflow menu. The 6-second "Undo" toast handles the immediate misclick;
/// this is the recoverable safety net after the toast is gone.
@available(macOS 14.0, *)
struct TaskTrashView: View {
    @ObservedObject var store: ActionItemStore
    @Environment(\.dismiss) private var dismiss

    private var trashed: [ActionItem] {
        store.trashedItems.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(NDS.divider)
            if trashed.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 460, height: 440)
        .background(NDS.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash").foregroundStyle(NDS.textSecondary)
            Text("Trash").font(.headline)
            Spacer()
            if !trashed.isEmpty {
                Button("Empty Trash", role: .destructive) { store.emptyTrash() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 30))
                .foregroundStyle(NDS.textTertiary)
            Text("Trash is empty").foregroundStyle(NDS.textSecondary)
            Text("Deleted tasks are kept here for 30 days, then removed.")
                .font(NDS.small).foregroundStyle(NDS.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(trashed) { item in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).lineLimit(1)
                            if let deleted = item.deletedAt {
                                Text("Deleted \(deleted.formatted(.relative(presentation: .named)))")
                                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        Button("Restore") { store.restore(item.id) }
                            .buttonStyle(.plain)
                            .foregroundStyle(NDS.brand)
                        Button { store.purge(item.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(NDS.textTertiary)
                        .help("Delete permanently")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    Divider().overlay(NDS.divider).opacity(0.5)
                }
            }
        }
    }
}
