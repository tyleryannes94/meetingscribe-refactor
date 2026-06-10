import SwiftUI

// Phase 1 (1F) — replaces the dead `colorName` asset-name stub with a real,
// NDS-backed accent color per relationship type. Used by avatar rings, the
// health widget, People rows, and type chips so the relationship-coach surfaces
// read warm and signal type at a glance. Keeping this in a SwiftUI extension
// leaves `Person.swift`'s model layer free of any UI dependency.
extension RelationshipType {
    /// Signature Bloom accent for this relationship type, drawn from the NDS palette.
    var color: Color {
        switch self {
        case .romanticPartner:  return NDS.accent       // coral — warmest tie
        case .familyMember:     return NDS.gold         // amber
        case .closeFriend:      return NDS.mint         // teal
        case .friend:           return NDS.sky          // sky
        case .colleague:        return NDS.lilac        // lilac
        case .acquaintance:     return NDS.textTertiary // muted
        case .unset:            return NDS.textTertiary // neutral
        }
    }
}
