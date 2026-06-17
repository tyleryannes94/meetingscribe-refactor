import SwiftUI

/// Shared navigable chips for the two foreign-key edges of an `ActionItem` —
/// its source meeting (or voice note) and its owner person. Adopted across the
/// Tasks list / board / strip surfaces so "click the meeting" and "click the
/// owner" behave identically everywhere (04 §4.1).
///
/// Both chips degrade to inert tertiary text when the linked entity can't be
/// resolved — preserves the existing guard pattern from `ActionItemsTableView`
/// and `TaskRowView` without duplicating it.
@available(macOS 14.0, *)
struct TaskMeetingChip: View {
    let item: ActionItem
    @EnvironmentObject var manager: MeetingManager
    @EnvironmentObject var router: WorkspaceRouter

    var body: some View {
        if item.isManual {
            EmptyView()
        } else if item.source == "voice_note" {
            // Voice-note source: route via voiceNote kind, not openMeeting
            // (manager.meeting(id:) returns nil for note ids). Edge case §6.4.
            Button { router.route(kind: .voiceNote, id: item.meetingID, manager: manager) } label: {
                Label(item.meetingTitle, systemImage: "mic")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(NDS.brand)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Open “\(item.meetingTitle)”")
        } else if let m = manager.meeting(id: item.meetingID) {
            Button { router.openMeeting(m) } label: {
                Label(item.meetingTitle, systemImage: "calendar")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(NDS.brand)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Open “\(item.meetingTitle)”")
        } else {
            // Source meeting is gone (deleted). Soft-degrade per 04 §4.4.
            Label(item.meetingTitle, systemImage: "calendar")
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .help("Source meeting unavailable")
        }
    }
}

/// Owner chip — avatar + name. Navigates to the linked person when
/// `ownerPersonID` is set; otherwise renders as a plain label (still informative
/// for self-owned and unresolved-owner tasks).
@available(macOS 14.0, *)
struct TaskOwnerChip: View {
    let item: ActionItem
    var size: CGFloat = 14
    @EnvironmentObject var router: WorkspaceRouter

    var body: some View {
        if let owner = item.owner, !owner.isEmpty {
            if let pid = item.ownerPersonID {
                Button { router.openPerson(pid) } label: {
                    HStack(spacing: 4) {
                        MSAvatar(name: owner, size: size)
                        Text(owner).font(.caption2)
                    }
                    .foregroundStyle(NDS.brand)
                }
                .buttonStyle(.plain)
                .help("Open \(owner) in People")
            } else {
                HStack(spacing: 4) {
                    MSAvatar(name: owner, size: size)
                    Text(owner).font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}
