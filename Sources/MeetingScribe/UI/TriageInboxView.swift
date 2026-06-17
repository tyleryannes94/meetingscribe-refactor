import SwiftUI

/// Triage inbox (redesign §5B): meeting-extracted action items awaiting a quick
/// yes/no before they enter the task workspace. Source data is
/// `ActionItemStore.pendingTriage`. Confirm files an item into Tasks (optionally
/// under a project); discard trashes it. Bulk "Add all" confirms everything.
@available(macOS 14.0, *)
struct TriageInboxView: View {
    @ObservedObject var store: ActionItemStore
    var onOpenMeeting: (String) -> Void = { _ in }
    /// Re-run extraction across past meetings (4-8). Wired by `ActionItemsView`.
    var onReextract: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Triage items grouped by source meeting, most-recent meeting first (4-1).
    private var meetingGroups: [(meetingID: String, items: [ActionItem])] {
        let groups = Dictionary(grouping: store.pendingTriage, by: { $0.meetingID })
        return groups
            .map { (meetingID: $0.key, items: $0.value) }
            .sorted { ($0.items.first?.meetingDate ?? .distantPast) > ($1.items.first?.meetingDate ?? .distantPast) }
    }

    var body: some View {
        let items = store.pendingTriage
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(count: items.count)
                if items.isEmpty {
                    VStack(spacing: 14) {
                        MSEmptyState(systemImage: "tray.and.arrow.down",
                                     title: "Inbox zero",
                                     message: "Action items extracted from your meetings land here for a quick review before they hit your task list.")
                        // 4-8: re-extraction is a first-class button here, not
                        // buried in an overflow menu.
                        Button { onReextract() } label: {
                            Label("Re-extract from past meetings", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(MSSecondaryButtonStyle())
                    }
                    .frame(minHeight: 300)
                } else {
                    ForEach(meetingGroups, id: \.meetingID) { group in
                        MeetingTriageGroup(meetingID: group.meetingID, items: group.items,
                                           store: store, onOpenMeeting: onOpenMeeting)
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

/// A collapsible group of triage items from one meeting (4-1), with per-meeting
/// bulk actions: file the whole group into a project, or dismiss it.
@available(macOS 14.0, *)
private struct MeetingTriageGroup: View {
    let meetingID: String
    let items: [ActionItem]
    @ObservedObject var store: ActionItemStore
    var onOpenMeeting: (String) -> Void
    @State private var expanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var meetingTitle: String {
        let t = items.first?.meetingTitle ?? ""
        return t.isEmpty ? "Untitled meeting" : t
    }
    private var meetingDate: Date? { items.first?.meetingDate }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if expanded {
                ForEach(items) { item in
                    TriageRow(item: item, store: store, onOpenMeeting: onOpenMeeting)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(NDS.motion(.easeOut(duration: 0.15), reduce: reduceMotion)) { expanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .scaledFont(9, weight: .bold)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(NDS.textTertiary)
            }
            .buttonStyle(.plain)
            Button { onOpenMeeting(meetingID) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").scaledFont(12).foregroundStyle(NDS.lilac)
                    Text(meetingTitle).scaledFont(14, weight: .bold).foregroundStyle(NDS.textPrimary).lineLimit(1)
                    if let d = meetingDate {
                        Text(Self.shortDate(d)).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Open the source meeting")
            Text("\(items.count)")
                .font(NDS.tiny.monospacedDigit())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(NDS.accentSoft, in: Capsule())
                .foregroundStyle(NDS.textSecondary)
            Spacer()
            Menu {
                Button("No project") { confirmAll(projectID: nil) }
                Divider()
                ForEach(store.projects) { p in Button(p.name) { confirmAll(projectID: p.id) } }
            } label: {
                Label("Add all to project…", systemImage: "folder.badge.plus").font(NDS.small)
            }
            .menuStyle(.borderlessButton).fixedSize()
            Button { dismissMeeting() } label: {
                Image(systemName: "trash").foregroundStyle(NDS.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss every item from this meeting")
        }
    }

    private func confirmAll(projectID: String?) {
        withAnimation(NDS.motion(NDS.springStandard, reduce: reduceMotion)) {
            store.confirm(ids: items.map(\.id), projectID: projectID)
        }
    }

    private func dismissMeeting() {
        let ids = items.map(\.id)
        let title = meetingTitle
        withAnimation(NDS.motion(NDS.springStandard, reduce: reduceMotion)) {
            let trashed = store.delete(ids: ids)
            ToastCenter.shared.show("Dismissed \(trashed.count) from “\(title)”", undoTitle: "Undo") {
                store.restore(ids: trashed)
            }
        }
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: d)
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

            // 4-2: a one-tap project suggestion fuzzy-matched from the meeting title.
            if let s = suggestedProject {
                Button { confirm(projectID: s.id) } label: {
                    NotionChip("→ \(s.name)?", color: NDS.brand, systemImage: "wand.and.stars")
                }
                .buttonStyle(.plain)
                .help("File into “\(s.name)” (matched from the meeting)")
            }

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

    /// Shared-word overlap between a project name and the meeting title (4-2).
    private func fuzzyScore(_ projectName: String) -> Int {
        let stop: Set<String> = ["the", "a", "and", "with", "for", "of", "to", "meeting", "sync", "call", "weekly"]
        let pw = Set(projectName.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)).subtracting(stop)
        let mw = Set(item.meetingTitle.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)).subtracting(stop)
        return pw.intersection(mw).count
    }

    /// The best-matching project for this item's meeting, if any words overlap.
    private var suggestedProject: Project? {
        guard !item.meetingTitle.isEmpty else { return nil }
        let best = store.projects.max { fuzzyScore($0.name) < fuzzyScore($1.name) }
        return best.flatMap { fuzzyScore($0.name) > 0 ? $0 : nil }
    }
}
