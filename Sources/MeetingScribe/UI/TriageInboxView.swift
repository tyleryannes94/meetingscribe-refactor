import SwiftUI

/// Triage inbox (redesign §5B): meeting-extracted action items awaiting a quick
/// yes/no before they enter the task workspace. Source data is
/// `ActionItemStore.pendingTriage`. Confirm files an item into Tasks (optionally
/// under a project); discard trashes it. Bulk "Add all" confirms everything.
@available(macOS 14.0, *)
struct TriageInboxView: View {
    @ObservedObject var store: ActionItemStore
    var onOpenMeeting: (String) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let items = store.pendingTriage
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(count: items.count)
                if items.isEmpty {
                    MSEmptyState(systemImage: "tray.and.arrow.down",
                                 title: "Inbox zero",
                                 message: "Action items extracted from your meetings land here for a quick review before they hit your task list.")
                        .frame(minHeight: 300)
                } else {
                    ForEach(items) { item in
                        TriageRow(item: item, store: store, onOpenMeeting: onOpenMeeting)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(NDS.motion(NDS.springStandard, reduce: reduceMotion), value: items.count)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NDS.bg)
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Triage inbox")
                    .scaledFont(28, weight: .heavy, relativeTo: .largeTitle, kind: .display)
                    .tracking(-0.6)
                Text(count == 0
                     ? "Nothing to review"
                     : "\(count) action item\(count == 1 ? "" : "s") from your meetings awaiting review")
                    .font(NDS.small).foregroundStyle(NDS.textSecondary)
            }
            Spacer()
            if count > 0 {
                Button {
                    withAnimation(NDS.motion(NDS.springStandard, reduce: reduceMotion)) {
                        _ = store.confirmAllTriage()
                    }
                } label: {
                    Label("Add all \(count) → Tasks", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(MSPrimaryButtonStyle())
            }
        }
    }
}

@available(macOS 14.0, *)
private struct TriageRow: View {
    let item: ActionItem
    @ObservedObject var store: ActionItemStore
    var onOpenMeeting: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(NDS.accent)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(NDS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if item.dueDate != nil {
                        DueChip(date: item.dueDate, status: item.status)
                    }
                    if let owner = item.owner, !owner.isEmpty {
                        HStack(spacing: 5) {
                            MSAvatar(name: owner, size: 16)
                            Text(owner).font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                        }
                    }
                    if !item.meetingTitle.isEmpty {
                        Button { onOpenMeeting(item.meetingID) } label: {
                            NotionChip(item.meetingTitle, color: NDS.lilac, systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.plain)
                        .help("Open the source meeting")
                    }
                }
            }

            Spacer(minLength: 8)

            // Optional: file under a project on confirm.
            if !store.projects.isEmpty {
                Menu {
                    Button("No project") { confirm(projectID: nil) }
                    Divider()
                    ForEach(store.projects) { p in
                        Button(p.name) { confirm(projectID: p.id) }
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Add to a project")
            }
            Button { confirm(projectID: nil) } label: {
                Label("Add", systemImage: "checkmark")
            }
            .buttonStyle(MSSecondaryButtonStyle())
            Button {
                let id = item.id, title = item.title
                withAnimation(NDS.motion(NDS.springStandard, reduce: reduceMotion)) {
                    store.delete(id)
                }
                ToastCenter.shared.show("Discarded “\(title)”", undoTitle: "Undo") { store.restore(id) }
            } label: {
                Image(systemName: "trash").foregroundStyle(NDS.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Discard")
        }
        .padding(14)
        .background(NDS.accentSoft, in: RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous)
            .strokeBorder(NDS.accent.opacity(0.28), lineWidth: 1))
    }

    private func confirm(projectID: String?) {
        withAnimation(NDS.motion(NDS.springStandard, reduce: reduceMotion)) {
            store.confirm(item.id, projectID: projectID)
        }
    }
}
