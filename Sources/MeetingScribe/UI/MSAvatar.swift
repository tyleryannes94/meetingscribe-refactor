import SwiftUI
import AppKit

/// Shared avatar (VD-6). A colored disc with up to two initials tinted
/// deterministically from the name, or a photo when one is available. One
/// definition for People rows, task owners, board/calendar/gallery cards, and
/// attendee stacks — so "who is this" is a glance everywhere.
@available(macOS 14.0, *)
struct MSAvatar: View {
    let name: String
    var image: NSImage? = nil
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(NDS.selectColor(name))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(NDS.hairline, lineWidth: 0.5))
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
        HStack(spacing: -size * 0.34) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, n in
                MSAvatar(name: n, size: size)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(NDS.textSecondary)
                    .frame(width: size, height: size)
                    .background(NDS.fieldBg, in: Circle())
                    .overlay(Circle().strokeBorder(NDS.hairline, lineWidth: 0.5))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(names.joined(separator: ", "))
    }
}
