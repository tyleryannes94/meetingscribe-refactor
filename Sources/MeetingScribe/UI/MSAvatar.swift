import SwiftUI
import AppKit
import VaultKit

/// The relationship-health ring color for a person (C2-10), or nil for untyped
/// one-off contacts (no ring). Uses the shared health formula so the ring agrees
/// with the badge and the MCP coach.
@available(macOS 14.0, *)
@MainActor
func healthRingColor(for person: Person, in store: PeopleStore) -> Color? {
    guard person.relationshipType != .unset else { return nil }
    let encs = store.encounters(for: person.id)
    let dates = encs.map(\.date).sorted(by: >)
    let medianGap: Int = {
        guard dates.count >= 2 else { return 0 }
        var gaps = (0..<(dates.count - 1)).map { Int(dates[$0].timeIntervalSince(dates[$0 + 1]) / 86400) }
        gaps.sort()
        return gaps[gaps.count / 2]
    }()
    let last = dates.first ?? person.lastInteractionAt
    let daysSince = last.map { Int(Date().timeIntervalSince($0) / 86400) } ?? 9_999
    let h = RelationshipHealth(daysSinceLast: daysSince, cadenceDays: person.effectiveCheckInDays,
                               encounterCount: encs.count, medianGapDays: medianGap)
    switch h.band {
    case .thriving: return NDS.mint
    case .steady:   return NDS.sky
    case .drifting: return NDS.gold
    case .overdue:  return NDS.danger
    }
}

/// Shared avatar (VD-6). A colored disc with up to two initials tinted
/// deterministically from the name, or a photo when one is available. One
/// definition for People rows, task owners, board/calendar/gallery cards, and
/// attendee stacks — so "who is this" is a glance everywhere.
@available(macOS 14.0, *)
struct MSAvatar: View {
    let name: String
    var image: NSImage? = nil
    var size: CGFloat = 18
    /// Relationship-health ring color (C2-10). When set, a colored ring is drawn
    /// just outside the avatar — one glanceable people language everywhere.
    var ringColor: Color? = nil

    /// Squircle corner radius (Bloom uses 34% of the side).
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.custom(NDS.psName(.body, .heavy), fixedSize: size * 0.42))
                    .foregroundStyle(NDS.avatarText)
                    .frame(width: size, height: size)
                    .background(NDS.avatarGradient(name))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(ringColor ?? NDS.hairline, lineWidth: ringColor == nil ? 0.5 : 2))
        .accessibilityLabel(name.isEmpty ? "No owner" : name)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}

/// Overlapping stack of avatars for multi-person cards (VD-6). Shows up to
/// `max` discs then a "+N" counter.
@available(macOS 14.0, *)
struct MSAvatarStack: View {
    let names: [String]
    var size: CGFloat = 18
    var max: Int = 3

    var body: some View {
        let shown = names.prefix(max)
        let overflow = names.count - shown.count
        let squircle = RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
        HStack(spacing: -size * 0.28) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, n in
                MSAvatar(name: n, size: size)
                    .overlay(squircle.strokeBorder(NDS.fieldBg, lineWidth: 2))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.custom(NDS.psName(.body, .bold), fixedSize: size * 0.4))
                    .foregroundStyle(NDS.textSecondary)
                    .frame(width: size, height: size)
                    .background(NDS.surface2, in: squircle)
                    .overlay(squircle.strokeBorder(NDS.fieldBg, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(names.joined(separator: ", "))
    }
}
