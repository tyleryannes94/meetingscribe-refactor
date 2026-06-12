import SwiftUI

/// One row in the meeting Actions tab (§3D): checkbox + title + due/owner, with
/// a push-to-Tasks affordance — "→ Tasks" while it's still in triage, "In Tasks"
/// once confirmed.
@available(macOS 14.0, *)
struct MeetingActionRow: View {
    let item: ActionItem
    @ObservedObject var store: ActionItemStore
    /// The meeting this row belongs to — its attendees are the likely owners (P2-9).
    var meeting: Meeting? = nil

    /// Resolved attendees of the meeting, offered first when assigning an owner.
    private var attendeePeople: [Person] {
        guard let m = meeting else { return [] }
        let people = PeopleStore.shared.people
        return m.attendees.compactMap { raw in
            PersonResolver.resolve(raw, in: people).flatMap { id in people.first { $0.id == id } }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.setStatus(item.id, status: item.status == .completed ? .open : .completed)
            } label: {
                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                    .scaledFont(15)
                    .foregroundStyle(item.status == .completed ? NDS.mint : NDS.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .scaledFont(13.5, weight: .medium)
                    .strikethrough(item.status == .completed)
                    .foregroundStyle(item.status == .completed ? NDS.textTertiary : NDS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if item.dueDate != nil { DueChip(date: item.dueDate, status: item.status) }
                    ownerMenu
                }
            }

            Spacer(minLength: 8)

            if item.needsTriage {
                Button { store.confirm(item.id) } label: {
                    Label("Tasks", systemImage: "arrow.right.circle")
                }
                .buttonStyle(MSSecondaryButtonStyle())
                .help("Add to the Tasks workspace")
            } else if item.status != .completed {
                Label("In Tasks", systemImage: "checkmark")
                    .font(NDS.tiny).foregroundStyle(NDS.mint)
            }
        }
        .padding(12)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius, style: .continuous)
            .strokeBorder(NDS.hairline, lineWidth: 1))
        .opacity(item.status == .completed ? 0.7 : 1)
    }

    /// Attendee-first owner assignment (P2-9): the people in the room lead the menu.
    private var ownerMenu: some View {
        Menu {
            if !attendeePeople.isEmpty {
                Section("In this meeting") {
                    ForEach(attendeePeople) { p in
                        Button { store.setOwnerPerson(item.id, personID: p.id, ownerName: p.displayName) } label: {
                            Label(p.displayName, systemImage: "person.fill")
                        }
                    }
                }
            }
            if item.owner?.isEmpty == false {
                Button("Unassign") { store.setOwnerPerson(item.id, personID: nil, ownerName: nil) }
            }
        } label: {
            if let owner = item.owner, !owner.isEmpty {
                HStack(spacing: 5) {
                    MSAvatar(name: owner, size: 16)
                    Text(owner).font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                }
            } else {
                Label("Assign", systemImage: "person.crop.circle.badge.plus")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}
