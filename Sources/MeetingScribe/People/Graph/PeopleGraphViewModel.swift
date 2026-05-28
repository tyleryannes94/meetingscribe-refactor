import Foundation
import CoreGraphics
import Observation

/// Drives the People mindmap (Phase 7). Builds nodes + edges from the current
/// people set, runs the force layout, and owns selection / pinning / filtering
/// state. `@Observable` so SwiftUI tracks only the properties a view reads.
///
/// Marked `@MainActor` because it is created and mutated from the People tab
/// (which already lives on the main actor via `PeopleStore`).
@MainActor
@Observable
final class PeopleGraphViewModel {
    var nodes: [PersonNode] = []
    var edges: [RelationshipEdge] = []
    var selectedTags: Set<String> = []
    var searchQuery: String = ""
    var layoutEngine = GraphLayout()

    /// The canvas size the layout targets — set by the view's GeometryReader.
    var bounds: CGRect = CGRect(x: 0, y: 0, width: 900, height: 640)

    /// Currently selected node, if any (drives highlight + the detail panel).
    private(set) var selectedNodeID: String?

    /// Highlighted shortest path (node ids) from the "Find Path" action.
    private(set) var pathNodeIDs: [String] = []

    /// Last full people set passed to `buildGraph`, kept so tag/search filtering
    /// can rebuild without the caller re-supplying it.
    private var sourcePeople: [Person] = []

    // MARK: - Build

    /// Creates nodes and edges. Edge rule: two people connect if they share ≥1
    /// tag OR appeared in ≥1 meeting together. Nodes seed on a circle, then the
    /// force layout untangles them.
    func buildGraph(from people: [Person], filterTags: Set<String> = []) {
        sourcePeople = people
        selectedTags = filterTags

        let filtered = filterTags.isEmpty
            ? people
            : people.filter { !$0.tagIDs.isDisjoint(with: filterTags) }

        // Graph-wide distinct meeting count normalizes edge weight to 0...1.
        let totalMeetings = max(1, Set(filtered.flatMap { $0.meetingMentions }).count)

        let n = filtered.count
        let cx = bounds.midX, cy = bounds.midY
        let radius = min(bounds.width, bounds.height) * 0.4
        nodes = filtered.enumerated().map { i, p in
            let angle = (Double(i) / Double(max(1, n))) * 2 * .pi
            let pos = CGPoint(x: cx + CoreGraphics.cos(angle) * radius,
                              y: cy + CoreGraphics.sin(angle) * radius)
            return PersonNode(id: p.id, position: pos, person: p)
        }

        var built: [RelationshipEdge] = []
        for i in 0..<filtered.count {
            for j in (i + 1)..<filtered.count {
                let a = filtered[i], b = filtered[j]
                let shared = Array(a.tagIDs.intersection(b.tagIDs))
                let meetings = a.meetingMentions.intersection(b.meetingMentions).count
                guard !shared.isEmpty || meetings > 0 else { continue }
                let weight = Double(meetings) / Double(totalMeetings)
                built.append(RelationshipEdge(sourceID: a.id, targetID: b.id,
                                              sharedTags: shared,
                                              sharedMeetingCount: meetings,
                                              weight: weight))
            }
        }
        edges = built
        applyForceLayout()
    }

    /// Re-runs the force layout against the current nodes/edges. Useful after
    /// pinning nodes or resizing the canvas.
    func applyForceLayout() {
        layoutEngine.layout(nodes: &nodes, edges: edges, in: bounds)
    }

    /// Re-filters by tag set and rebuilds.
    func filterByTags(_ tags: Set<String>) {
        buildGraph(from: sourcePeople, filterTags: tags)
    }

    func toggleTag(_ tagID: String) {
        var t = selectedTags
        if t.contains(tagID) { t.remove(tagID) } else { t.insert(tagID) }
        filterByTags(t)
    }

    func resetFilters() {
        searchQuery = ""
        pathNodeIDs = []
        filterByTags([])
    }

    // MARK: - Selection

    /// Tapping the already-selected node clears the selection (toggle).
    func selectNode(_ id: String) {
        selectedNodeID = (selectedNodeID == id) ? nil : id
        pathNodeIDs = []
        for i in nodes.indices { nodes[i].isSelected = (nodes[i].id == selectedNodeID) }
    }

    func clearSelection() {
        selectedNodeID = nil
        pathNodeIDs = []
        for i in nodes.indices { nodes[i].isSelected = false }
    }

    var selectedPerson: Person? {
        guard let id = selectedNodeID else { return nil }
        return node(by: id)?.person
    }

    // MARK: - Pin / move / remove

    func pinNode(_ id: String, at point: CGPoint) {
        guard let i = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[i].position = point
        nodes[i].isPinned = true
    }

    func togglePin(_ id: String) {
        guard let i = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[i].isPinned.toggle()
    }

    func setPosition(_ id: String, to point: CGPoint) {
        guard let i = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[i].position = point
    }

    func removeNode(_ id: String) {
        nodes.removeAll { $0.id == id }
        edges.removeAll { $0.connects(id) }
        if selectedNodeID == id { clearSelection() }
    }

    // MARK: - Queries

    func node(by id: String) -> PersonNode? { nodes.first { $0.id == id } }

    func edges(for id: String) -> [RelationshipEdge] { edges.filter { $0.connects(id) } }

    /// IDs of nodes directly connected to `id`.
    func connectedIDs(to id: String) -> Set<String> {
        var result = Set<String>()
        for e in edges { if let o = e.other(than: id) { result.insert(o) } }
        return result
    }

    /// The highlight set when a node is selected: the node plus its neighbors.
    var highlightSet: Set<String>? {
        guard let id = selectedNodeID else { return nil }
        return connectedIDs(to: id).union([id])
    }

    // MARK: - Find Path (BFS shortest path)

    /// Computes and highlights the shortest path between two people. Returns the
    /// ordered node ids (inclusive of both ends); empty if disconnected.
    @discardableResult
    func findPath(from a: String, to b: String) -> [String] {
        let path = shortestPath(from: a, to: b)
        pathNodeIDs = path
        return path
    }

    func clearPath() { pathNodeIDs = [] }

    private func shortestPath(from a: String, to b: String) -> [String] {
        if a == b { return [a] }
        var adjacency: [String: [String]] = [:]
        for e in edges {
            adjacency[e.sourceID, default: []].append(e.targetID)
            adjacency[e.targetID, default: []].append(e.sourceID)
        }
        var queue = [a]
        var visited: Set<String> = [a]
        var parent: [String: String] = [:]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current == b { break }
            for neighbor in adjacency[current] ?? [] where !visited.contains(neighbor) {
                visited.insert(neighbor)
                parent[neighbor] = current
                queue.append(neighbor)
            }
        }
        guard visited.contains(b) else { return [] }
        var path = [b]
        var current = b
        while current != a, let p = parent[current] {
            path.append(p)
            current = p
        }
        return path.reversed()
    }

    /// True when both endpoints of `edge` are on the highlighted path.
    func edgeOnPath(_ edge: RelationshipEdge) -> Bool {
        guard pathNodeIDs.count > 1 else { return false }
        for i in 0..<(pathNodeIDs.count - 1) {
            let s = pathNodeIDs[i], t = pathNodeIDs[i + 1]
            if (edge.sourceID == s && edge.targetID == t) ||
               (edge.sourceID == t && edge.targetID == s) { return true }
        }
        return false
    }
}
