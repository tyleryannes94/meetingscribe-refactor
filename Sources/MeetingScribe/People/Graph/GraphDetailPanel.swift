import SwiftUI

/// The side panel shown when a node is selected (Phase 7). Slides in from the
/// right (300pt) with the person's photo, name, tags, recency, meeting count,
/// a list of direct connections (with shared context), and actions to open the
/// full profile or highlight the shortest path to another person.
@available(macOS 14.0, *)
struct GraphDetailPanel: View {
    @Bindable var viewModel: PeopleGraphViewModel
    let person: Person
    /// Resolves a people-tag id to its display name.
    var tagName: (String) -> String?
    /// Resolves a person's first photo to a file URL.
    var photoURL: (Person) -> URL?
    var onViewProfile: (String) -> Void

    private var connections: [(person: Person, edge: RelationshipEdge)] {
        viewModel.edges(for: person.id).compactMap { edge in
            guard let otherID = edge.other(than: person.id),
                  let node = viewModel.node(by: otherID) else { return nil }
            return (node.person, edge)
        }
        .sorted { $0.edge.weight > $1.edge.weight }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !person.tagIDs.isEmpty { tagsSection }
                    statsSection
                    actionsSection
                    connectionsSection
                }
                .padding(14)
            }
        }
        .frame(width: 300)
        .background(NDS.rightRailBg)
        .overlay(alignment: .leading) { Divider() }
        .transition(.move(edge: .trailing))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).scaledFont(15, weight: .bold).lineLimit(1)
                let sub = [person.role, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
                if !sub.isEmpty {
                    Text(sub).font(NDS.tiny).foregroundStyle(NDS.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button { viewModel.clearSelection() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(NDS.textTertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .padding(.top, 48) // clear the window toolbar overlay on macOS Tahoe
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let url = photoURL(person) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                    else { initials }
                }
            } else { initials }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
    }

    private var initials: some View {
        ZStack {
            Circle().fill(NDS.selectColor(person.id).gradient)
            Text(initialsText).scaledFont(16, weight: .bold).foregroundStyle(.white)
        }
    }

    private var initialsText: String {
        let parts = person.displayName.split(separator: " ").prefix(2).compactMap { $0.first }
        let s = String(parts).uppercased()
        return s.isEmpty ? "?" : s
    }

    // MARK: - Sections

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("TAGS")
            FlowTags(tags: person.tagIDs.compactMap { id in
                tagName(id).map { GraphTagPill(id: id, name: $0, color: NDS.selectColor($0)) }
            })
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("ACTIVITY")
            HStack {
                Image(systemName: "calendar").foregroundStyle(NDS.textTertiary)
                Text("Last interaction")
                Spacer()
                Text(lastInteractionText).foregroundStyle(NDS.textSecondary)
            }
            .font(NDS.small)
            HStack {
                Image(systemName: "person.2").foregroundStyle(NDS.textTertiary)
                Text("Meetings")
                Spacer()
                Text("\(person.meetingMentions.count)").foregroundStyle(NDS.textSecondary)
            }
            .font(NDS.small)
        }
    }

    private var lastInteractionText: String {
        guard let date = person.lastInteractionAt else { return "—" }
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: date)
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            Button {
                onViewProfile(person.id)
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Menu {
                if viewModel.pathNodeIDs.count > 1 {
                    Button("Clear path") { viewModel.clearPath() }
                    Divider()
                }
                ForEach(otherPeople, id: \.id) { other in
                    Button(other.displayName) {
                        viewModel.findPath(from: person.id, to: other.id)
                    }
                }
            } label: {
                Label("Find Path", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)
            .help("Highlight the shortest connection path to another person")
        }
    }

    private var otherPeople: [Person] {
        viewModel.nodes.map(\.person)
            .filter { $0.id != person.id }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("CONNECTIONS (\(connections.count))")
            if connections.isEmpty {
                Text("No direct connections in the current graph.")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            } else {
                ForEach(connections, id: \.person.id) { item in
                    connectionRow(item.person, item.edge)
                }
            }
        }
    }

    private func connectionRow(_ other: Person, _ edge: RelationshipEdge) -> some View {
        Button {
            viewModel.selectNode(other.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(other.displayName).scaledFont(12.5, weight: .medium)
                    .foregroundStyle(NDS.textPrimary)
                Text(contextText(edge))
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
        }
        .buttonStyle(.plain)
    }

    private func contextText(_ edge: RelationshipEdge) -> String {
        var parts: [String] = []
        if edge.sharedMeetingCount > 0 {
            parts.append("\(edge.sharedMeetingCount) shared meeting\(edge.sharedMeetingCount == 1 ? "" : "s")")
        }
        if !edge.sharedTags.isEmpty {
            let names = edge.sharedTags.compactMap { tagName($0) }
            if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        }
        return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).scaledFont(10, weight: .semibold)
            .foregroundStyle(NDS.textTertiary)
    }
}

/// Simple wrapping tag layout for the detail panel.
@available(macOS 14.0, *)
private struct FlowTags: View {
    let tags: [GraphTagPill]
    var body: some View {
        // A modest two-per-row wrap is enough for the 300pt panel.
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { pill in
                        Text(pill.name)
                            .scaledFont(10, weight: .medium)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .foregroundStyle(pill.color)
                            .background(pill.color.opacity(0.16), in: Capsule())
                    }
                }
            }
        }
    }
    private var rows: [[GraphTagPill]] {
        stride(from: 0, to: tags.count, by: 2).map {
            Array(tags[$0..<min($0 + 2, tags.count)])
        }
    }
}
