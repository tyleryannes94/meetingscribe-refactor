import Foundation

/// A connection between two people in the mindmap (Phase 7). Two people are
/// connected when they share at least one tag OR appeared in at least one
/// meeting together. The edge carries enough context to color, weight, and
/// label itself in the canvas.
///
/// Design note: `sourceID` / `targetID` are `String` to match `Person.id`
/// (see `PersonNode`). The edge is undirected; `id` is order-independent so the
/// same pair never produces two edges.
struct RelationshipEdge: Identifiable {
    let id: String
    let sourceID: String
    let targetID: String
    /// Tag IDs both people carry — used to color the edge.
    let sharedTags: [String]
    /// How many meetings both people appeared in.
    let sharedMeetingCount: Int
    /// Derived strength, clamped 0...1 (sharedMeetingCount / graph meeting count).
    var weight: Double

    init(sourceID: String,
         targetID: String,
         sharedTags: [String],
         sharedMeetingCount: Int,
         weight: Double) {
        // Order-independent id so (A,B) and (B,A) collapse to one edge.
        self.id = [sourceID, targetID].sorted().joined(separator: "::")
        self.sourceID = sourceID
        self.targetID = targetID
        self.sharedTags = sharedTags
        self.sharedMeetingCount = sharedMeetingCount
        self.weight = min(1.0, max(0.0, weight))
    }

    /// Line width for rendering: thicker = stronger connection.
    var lineWidth: CGFloat { 1.0 + CGFloat(weight) * 3.0 }

    func connects(_ nodeID: String) -> Bool { sourceID == nodeID || targetID == nodeID }

    /// The other endpoint, given one node id (nil if the id isn't on this edge).
    func other(than nodeID: String) -> String? {
        if sourceID == nodeID { return targetID }
        if targetID == nodeID { return sourceID }
        return nil
    }
}
