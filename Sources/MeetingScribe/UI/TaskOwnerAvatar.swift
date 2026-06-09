import SwiftUI

/// Small monogram avatar for a task's owner (VD-6) — a colored disc with up to
/// two initials, tinted deterministically from the name. Turns "who owns this"
/// from a read into a glance across the table, board, and calendar.
@available(macOS 14.0, *)
struct TaskOwnerAvatar: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(NDS.selectColor(name), in: Circle())
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}
