import SwiftUI

/// Inline "connect attendee → person" inspector, shown as a trailing panel
/// inside the meeting detail when an attendee chip is clicked.
///
/// Replaces the old "jump straight to the People tab" behavior: the user stays
/// in the meeting and can either link this attendee's email to a person already
/// in their second brain, or add them as a brand-new person — without losing
/// the meeting context. Once linked, "Open in People" still routes over (and,
/// thanks to global back/forward, returns here in one click).
@available(macOS 14.0, *)
struct MeetingPersonConnectPanel: View {
    /// Raw attendee string from the calendar event ("Name <email>" or bare).
    let attendee: String
    let meeting: Meeting
    let onClose: () -> Void

    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var router: WorkspaceRouter

    @State private var query: String = ""
    @State private var didSeedQuery = false
    /// Set after a successful link so we can show a confirmation state.
    @State private var connectedID: String?

    // MARK: - Parsing (via the one identity layer, P1-1)

    private var identity: AttendeeIdentity { PersonResolver.parse(attendee) }
    private var fullName: String { identity.hasName ? identity.name : attendee }
    private var email: String { identity.email }

    /// The person this attendee already resolves to (email first, exact name).
    private var existingPerson: Person? {
        guard let id = PersonResolver.resolve(identity: identity, in: people.people) else { return nil }
        return people.person(by: id)
    }

    /// People matching the search box. When the box is empty we surface the
    /// best name matches so the common "link to the obvious person" case is one
    /// click. The already-linked person (if any) is pinned to the top.
    private var matches: [Person] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base: [Person]
        if q.isEmpty {
            base = people.people
        } else {
            base = people.people.filter {
                $0.displayName.lowercased().contains(q)
                || $0.emails.contains { $0.lowercased().contains(q) }
                || $0.company.lowercased().contains(q)
            }
        }
        let pinned = existingPerson
        let rest = base.filter { $0.id != pinned?.id }
        return ([pinned].compactMap { $0 } + rest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: NDS.splitPaneTopInset)
            headerBar
            Divider().overlay(NDS.divider)
            identityBlock
            Divider().overlay(NDS.divider)
            if let id = connectedID, let p = people.person(by: id) {
                connectedState(p)
            } else {
                connectBody
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NDS.sidebarBg)
        .onAppear {
            guard !didSeedQuery else { return }
            didSeedQuery = true
            // Pre-fill the search with the attendee's name so likely matches
            // show immediately — but only if they're not already linked.
            if existingPerson == nil { query = fullName }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.plus")
                .scaledFont(13).foregroundStyle(NDS.brand)
            Text("Connect attendee").scaledFont(13, weight: .bold)
            Spacer()
            NotionIconButton(systemName: "xmark", help: "Close") { onClose() }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var identityBlock: some View {
        HStack(spacing: 10) {
            MSAvatar(name: fullName, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(fullName).scaledFont(13.5, weight: .semibold)
                    .foregroundStyle(NDS.textPrimary).lineLimit(1)
                if !email.isEmpty {
                    Text(email).scaledFont(11).foregroundStyle(NDS.textSecondary).lineLimit(1)
                } else {
                    Text("No email on this invite").scaledFont(11).foregroundStyle(NDS.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: - Connected confirmation

    private func connectedState(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green).scaledFont(15)
                Text("Linked to \(p.displayName)").scaledFont(13, weight: .medium)
                    .foregroundStyle(NDS.textPrimary)
            }
            if !email.isEmpty {
                Text("\(email) is now saved on this person and the meeting is on their timeline.")
                    .scaledFont(11).foregroundStyle(NDS.textSecondary)
            } else {
                Text("This meeting is now on \(p.displayName)'s timeline.")
                    .scaledFont(11).foregroundStyle(NDS.textSecondary)
            }
            HStack(spacing: 8) {
                Button { router.openPerson(p.id) } label: {
                    Label("Open in People", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(MSSecondaryButtonStyle())
                Button { onClose() } label: { Text("Done") }
                    .buttonStyle(MSPrimaryButtonStyle())
            }
        }
        .padding(14)
    }

    // MARK: - Connect / search

    private var connectBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if existingPerson != nil {
                Text("Already linked — or pick a different person.")
                    .scaledFont(11).foregroundStyle(NDS.textTertiary)
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            }

            // Search box
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").scaledFont(11).foregroundStyle(NDS.textTertiary)
                TextField("Search people…", text: $query).scaledFont(12).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").scaledFont(11).foregroundStyle(NDS.textTertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NDS.hairline, lineWidth: 1))
            .padding(.horizontal, 14).padding(.vertical, 8)

            // Matches
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if matches.isEmpty {
                        Text(query.isEmpty ? "No people yet." : "No matches for “\(query)”.")
                            .scaledFont(11).foregroundStyle(NDS.textTertiary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                    ForEach(matches.prefix(40)) { p in
                        personRow(p, isLinked: p.id == existingPerson?.id)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 300)

            Divider().overlay(NDS.divider).padding(.horizontal, 14).padding(.vertical, 6)

            Button { addAsNew() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").scaledFont(13)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Add as new person").scaledFont(12.5, weight: .semibold)
                        Text(fullName).scaledFont(10.5).foregroundStyle(NDS.textTertiary).lineLimit(1)
                    }
                    Spacer()
                }
                .foregroundStyle(NDS.brand)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NDS.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }

    private func personRow(_ p: Person, isLinked: Bool) -> some View {
        Button { connect(to: p) } label: {
            HStack(spacing: 9) {
                MSAvatar(name: p.displayName, size: 26,
                         ringColor: healthRingColor(for: p, in: people))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.displayName).scaledFont(12.5, weight: .medium)
                        .foregroundStyle(NDS.textPrimary).lineLimit(1)
                    if let sub = subtitle(p) {
                        Text(sub).scaledFont(10.5).foregroundStyle(NDS.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isLinked {
                    Text("Linked").scaledFont(9.5, weight: .semibold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.14), in: Capsule())
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ p: Person) -> String? {
        if let first = p.emails.first { return first }
        let roleCompany = [p.role, p.company].filter { !$0.isEmpty }.joined(separator: " · ")
        return roleCompany.isEmpty ? nil : roleCompany
    }

    // MARK: - Actions

    private func connect(to person: Person) {
        if !email.isEmpty { people.addEmail(email, to: person.id) }
        people.addMeetingMention(meeting.id, toPersonID: person.id)
        // Bump last-interaction so the person sorts up in "recent".
        if var p = people.person(by: person.id) {
            let candidate = meeting.startDate
            if (p.lastInteractionAt ?? .distantPast) < candidate {
                p.lastInteractionAt = candidate
                people.updatePerson(p)
            }
        }
        connectedID = person.id
        ToastCenter.shared.show("Linked \(fullName) to \(person.displayName)")
    }

    private func addAsNew() {
        let p = people.createPerson(displayName: fullName, email: email)
        connect(to: p)
    }
}
