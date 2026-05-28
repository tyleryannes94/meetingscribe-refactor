import Foundation
import CoreGraphics

/// A single laid-out person in the People mindmap (Phase 7).
///
/// Design note: the task spec types `id` as `UUID`, but `Person.id` is a
/// `String` (UUID string) everywhere else in this codebase — Meeting / QuickNote
/// / tags all key on `String`. We mirror that here so a node cross-references a
/// `Person`, an edge, and the FTS index without a type bridge.
struct PersonNode: Identifiable {
    /// Matches `Person.id`.
    let id: String
    /// Layout position in the canvas coordinate space (top-left origin).
    var position: CGPoint
    /// Per-iteration velocity scratch used by the force layout. Not persisted.
    var velocity: CGVector = .zero
    var person: Person
    var isSelected: Bool = false
    /// A pinned node is fixed in place — the force layout won't move it.
    var isPinned: Bool = false

    init(id: String, position: CGPoint, person: Person,
         isSelected: Bool = false, isPinned: Bool = false) {
        self.id = id
        self.position = position
        self.person = person
        self.isSelected = isSelected
        self.isPinned = isPinned
    }

    /// How many meetings mention this person — drives node size.
    var meetingCount: Int { person.meetingMentions.count }

    /// Node diameter: base 56pt, grows to 72pt for well-connected people
    /// (more than five meetings), per the Phase 7 spec.
    var diameter: CGFloat { meetingCount > 5 ? 72 : 56 }

    /// Two-letter initials fallback when the person has no photo.
    var initials: String {
        let parts = person.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let s = String(parts).uppercased()
        return s.isEmpty ? "?" : s
    }
}
