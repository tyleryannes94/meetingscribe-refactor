import SwiftUI

/// A small colored tag pill displayed under a node's name.
struct GraphTagPill: Identifiable {
    let id: String
    let name: String
    let color: Color
}

/// The individual node widget in the People mindmap (Phase 7): an avatar
/// (photo or initials), the name, and up to three tag pills. The node renders
/// a bright ring when selected and dims when it falls outside the current
/// highlight/search focus. Tap / double-tap / context-menu actions are handed
/// up to the parent via closures; dragging is owned by the parent canvas.
@available(macOS 14.0, *)
struct PersonNodeView: View {
    let node: PersonNode
    /// Fades the node when it's outside the active highlight (selection/search).
    var isDimmed: Bool
    /// True when this node sits on the highlighted "Find Path" route.
    var isOnPath: Bool = false
    /// Resolved photo URL, if the person has an attached photo.
    var photoURL: URL?
    /// Pre-resolved tag pills (name + color), already capped by the caller.
    var tags: [GraphTagPill]
    var overflowCount: Int = 0

    var onTap: () -> Void
    var onDoubleTap: () -> Void
    var onTogglePin: () -> Void
    var onViewProfile: () -> Void
    var onFindConnections: () -> Void
    var onRemove: () -> Void

    private var ringColor: Color {
        if node.isSelected { return NDS.brand }
        if isOnPath { return Color(hex: "#06B6D4") ?? .cyan }
        return .clear
    }

    var body: some View {
        VStack(spacing: 4) {
            avatar
                .overlay(
                    Circle().strokeBorder(ringColor, lineWidth: node.isSelected || isOnPath ? 3 : 0)
                )
                .overlay(alignment: .topTrailing) {
                    if node.isPinned {
                        Image(systemName: "pin.fill")
                            .scaledFont(9, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(NDS.brand, in: Circle())
                            .offset(x: 2, y: -2)
                    }
                }

            Text(node.person.displayName)
                .scaledFont(11, weight: .semibold)
                .foregroundStyle(NDS.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 96)

            if !tags.isEmpty {
                HStack(spacing: 3) {
                    ForEach(tags) { pill in
                        Text(pill.name)
                            .scaledFont(8, weight: .medium)
                            .lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .foregroundStyle(pill.color)
                            .background(pill.color.opacity(0.16), in: Capsule())
                    }
                    if overflowCount > 0 {
                        Text("+\(overflowCount)")
                            .scaledFont(8, weight: .medium)
                            .foregroundStyle(NDS.textTertiary)
                    }
                }
                .frame(maxWidth: 110)
            }
        }
        .opacity(isDimmed ? 0.18 : 1.0)
        .contentShape(Rectangle())
        // Double-tap registered before single tap so the single-tap handler
        // doesn't swallow it.
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture(count: 1) { onTap() }
        .contextMenu {
            Button(node.isPinned ? "Unpin" : "Pin") { onTogglePin() }
            Button("View Profile") { onViewProfile() }
            Button("Find Connections") { onFindConnections() }
            Divider()
            Button("Remove from Graph", role: .destructive) { onRemove() }
        }
        .help(node.person.displayName)
        .animation(.easeInOut(duration: 0.15), value: isDimmed)
        .animation(.easeInOut(duration: 0.15), value: node.isSelected)
    }

    @ViewBuilder
    private var avatar: some View {
        let d = node.diameter
        Group {
            if let url = photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsCircle
                    }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(avatarTint.gradient)
            Text(node.initials)
                .font(.system(size: node.diameter * 0.34, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    /// Deterministic per-person tint so the same person keeps a stable color.
    private var avatarTint: Color {
        NDS.selectColor(node.person.id)
    }
}
