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

    /// SF Symbol that signals this relationship type as UI chrome. Replaces the
    /// raw `emoji` glyph (C2-7) — benchmarks (Things 3, Linear, Clay, Dex) never
    /// use OS emoji as iconography. Paired with `color` in `RelationshipTypeChip`.
    var symbol: String {
        switch self {
        case .romanticPartner:  return "heart.fill"
        case .familyMember:     return "house.fill"
        case .closeFriend:      return "person.2.fill"
        case .friend:           return "person.fill"
        case .colleague:        return "briefcase.fill"
        case .acquaintance:     return "hand.wave.fill"
        case .unset:            return "person.crop.circle"
        }
    }
}

/// Shared typed-glyph chip for a `RelationshipType` (C2-7). Renders the type's
/// SF Symbol — and optionally its label — inside a capsule tinted with the
/// type's accent `color`: a soft fill (`.opacity`) behind a full-strength glyph
/// and label. Defined once here and reused by People rows, the type picker, and
/// the Today "Stay connected" badges so the relationship surfaces read warm and
/// signal type at a glance without OS emoji as chrome.
@available(macOS 14.0, *)
struct RelationshipTypeChip: View {
    let type: RelationshipType
    /// When false, the chip collapses to a compact glyph-only capsule badge
    /// (used as an avatar overlay / inline row badge).
    var showLabel: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.symbol)
                .scaledFont(showLabel ? 10 : 9, weight: .semibold)
            if showLabel {
                Text(type.displayName)
                    .scaledFont(11, weight: .medium)
            }
        }
        .foregroundStyle(type.color)
        .padding(.horizontal, showLabel ? 7 : 4)
        .padding(.vertical, showLabel ? 3 : 4)
        .background(type.color.opacity(0.14), in: Capsule())
        .help(type.displayName)
        .accessibilityLabel(type.displayName)
    }
}
