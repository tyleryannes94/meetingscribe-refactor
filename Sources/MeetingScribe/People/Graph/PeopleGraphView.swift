import SwiftUI

/// The People mindmap (Phase 7) — a SwiftUI `Canvas` for the edges with a
/// hit-testable node overlay on top, wrapped in pan + zoom gestures. Selecting
/// a node highlights it and its neighbors (dimming the rest) and opens the
/// detail panel; the filter bar drives tag/search filtering and re-layout.
///
/// No third-party graph library: layout is `GraphLayout` (force-directed) and
/// all rendering is first-party SwiftUI.
@available(macOS 14.0, *)
struct PeopleGraphView: View {
    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var peopleTags: PeopleTagStore

    /// Switch back to the list, optionally selecting a person there.
    var onExit: () -> Void
    var onOpenProfile: (String) -> Void

    @State private var viewModel = PeopleGraphViewModel()
    @State private var didBuild = false

    @State private var scale: CGFloat = 1.0
    @State private var scaleStart: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var panStart: CGSize = .zero

    @State private var dragNode: String?
    @State private var dragStart: CGPoint = .zero

    var body: some View {
        VStack(spacing: 0) {
            GraphFilterBar(viewModel: viewModel,
                           availableTags: availableTags,
                           onExit: onExit)
            ZStack(alignment: .topTrailing) {
                canvas
                if let person = viewModel.selectedPerson {
                    GraphDetailPanel(viewModel: viewModel,
                                     person: person,
                                     tagName: { peopleTags.tag(by: $0)?.name },
                                     photoURL: photoURL(for:),
                                     onViewProfile: onOpenProfile)
                        .zIndex(1)
                }
            }
        }
    }

    // MARK: - Canvas + nodes

    private var canvas: some View {
        GeometryReader { geo in
            let edgeList = viewModel.edges
            let positions = Dictionary(uniqueKeysWithValues: viewModel.nodes.map { ($0.id, $0.position) })

            ZStack {
                // Background — taps deselect, drags pan.
                Rectangle().fill(NDS.bg)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.clearSelection() }

                edgeCanvas(edges: edgeList, positions: positions)

                ForEach(viewModel.nodes) { node in
                    nodeView(node)
                        .position(node.position)
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(panGesture)
            .gesture(magnifyGesture)
            .clipped()
            .onAppear {
                guard !didBuild else { return }
                viewModel.bounds = CGRect(origin: .zero, size: geo.size)
                viewModel.buildGraph(from: people.people, filterTags: [])
                didBuild = true
            }
            .overlay(alignment: .bottomLeading) { legend }
            .overlay { if viewModel.nodes.isEmpty { emptyState } }
        }
    }

    private func edgeCanvas(edges: [RelationshipEdge], positions: [String: CGPoint]) -> some View {
        Canvas { ctx, _ in
            for edge in edges {
                guard let a = positions[edge.sourceID], let b = positions[edge.targetID] else { continue }
                let onPath = viewModel.edgeOnPath(edge)
                let dimmed = edgeDimmed(edge)
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                let baseColor = onPath ? (Color(hex: "#06B6D4") ?? .cyan) : edgeColor(edge)
                let alpha = onPath ? 0.95 : (dimmed ? 0.05 : 0.45)
                let width = onPath ? edge.lineWidth + 1.5 : edge.lineWidth
                ctx.stroke(path, with: .color(baseColor.opacity(alpha)), lineWidth: width)

                // Pill label at the midpoint for strong meeting overlap.
                if edge.sharedMeetingCount > 2 && !dimmed {
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    let rect = CGRect(x: mid.x - 9, y: mid.y - 7, width: 18, height: 14)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 7),
                             with: .color(baseColor.opacity(0.85)))
                    let text = Text("\(edge.sharedMeetingCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    ctx.draw(text, at: mid)
                }
            }
        }
    }

    private func nodeView(_ node: PersonNode) -> some View {
        let pills = tagPills(for: node.person, limit: 3)
        return PersonNodeView(
            node: node,
            isDimmed: nodeDimmed(node),
            isOnPath: viewModel.pathNodeIDs.contains(node.id),
            photoURL: photoURL(for: node.person),
            tags: pills.shown,
            overflowCount: pills.overflow,
            onTap: { viewModel.selectNode(node.id) },
            onDoubleTap: { onOpenProfile(node.id) },
            onTogglePin: { viewModel.togglePin(node.id) },
            onViewProfile: { onOpenProfile(node.id) },
            onFindConnections: { viewModel.selectNode(node.id) },
            onRemove: { viewModel.removeNode(node.id) }
        )
        .gesture(dragGesture(for: node))
    }

    // MARK: - Gestures

    private func dragGesture(for node: PersonNode) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragNode != node.id {
                    dragNode = node.id
                    dragStart = node.position
                }
                let p = CGPoint(x: dragStart.x + value.translation.width / scale,
                                y: dragStart.y + value.translation.height / scale)
                viewModel.setPosition(node.id, to: p)
            }
            .onEnded { _ in dragNode = nil }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: panStart.width + value.translation.width,
                                height: panStart.height + value.translation.height)
            }
            .onEnded { _ in panStart = offset }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(0.3, min(3.0, scaleStart * value.magnification))
            }
            .onEnded { _ in scaleStart = scale }
    }

    // MARK: - Highlight / dim logic

    private var trimmedQuery: String {
        viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func nodeDimmed(_ node: PersonNode) -> Bool {
        if let set = viewModel.highlightSet, !set.contains(node.id) { return true }
        let q = trimmedQuery
        if !q.isEmpty && !node.person.displayName.lowercased().contains(q) { return true }
        return false
    }

    private func edgeDimmed(_ edge: RelationshipEdge) -> Bool {
        if viewModel.edgeOnPath(edge) { return false }
        if let sel = viewModel.selectedNodeID { return !edge.connects(sel) }
        let q = trimmedQuery
        if !q.isEmpty {
            let a = viewModel.node(by: edge.sourceID)?.person.displayName.lowercased() ?? ""
            let b = viewModel.node(by: edge.targetID)?.person.displayName.lowercased() ?? ""
            return !(a.contains(q) || b.contains(q))
        }
        return false
    }

    // MARK: - Resolvers

    /// Edge color: the first shared tag's color, else the brand accent.
    private func edgeColor(_ edge: RelationshipEdge) -> Color {
        if let first = edge.sharedTags.first, let tag = peopleTags.tag(by: first) {
            return color(for: tag)
        }
        return NDS.brand
    }

    private func color(for tag: MeetingTag) -> Color {
        if let hex = tag.colorHex, let c = Color(hex: hex) { return c }
        return NDS.selectColor(tag.name)
    }

    private func tagPills(for person: Person, limit: Int) -> (shown: [GraphTagPill], overflow: Int) {
        let pills = person.tagIDs.compactMap { id -> GraphTagPill? in
            guard let tag = peopleTags.tag(by: id) else { return nil }
            return GraphTagPill(id: id, name: tag.name, color: color(for: tag))
        }
        .sorted { $0.name < $1.name }
        if pills.count <= limit { return (pills, 0) }
        return (Array(pills.prefix(limit)), pills.count - limit)
    }

    private func photoURL(for person: Person) -> URL? {
        guard let rel = person.photoRelativePaths.first else { return nil }
        return people.photoURL(for: person, relativePath: rel)
    }

    private var availableTags: [GraphTagPill] {
        let used = people.usedTagIDs()
        return peopleTags.allTags
            .filter { used.contains($0.id) }
            .map { GraphTagPill(id: $0.id, name: $0.name, color: color(for: $0)) }
    }

    // MARK: - Chrome

    private var legend: some View {
        HStack(spacing: 12) {
            Label("\(viewModel.nodes.count) people", systemImage: "person.2")
            Label("\(viewModel.edges.count) connections", systemImage: "link")
            if Int(scale * 100) != 100 {
                Text("\(Int(scale * 100))%")
            }
        }
        .font(NDS.tiny)
        .foregroundStyle(NDS.textTertiary)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: NDS.radius))
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No people to graph").font(.headline)
            Text("Add or import people, or clear the tag filter, to see the mindmap.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
    }
}
