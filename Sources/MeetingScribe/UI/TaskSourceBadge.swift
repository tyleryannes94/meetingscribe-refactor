import SwiftUI

/// A tiny origin glyph for a task (4-6): where did this come from — a meeting, a
/// manual capture, Linear, or Notion? Used on Kanban cards (Home + Tasks board)
/// where the source is otherwise invisible. List rows already show the meeting
/// label and external chip, so they don't need it.
@available(macOS 14.0, *)
struct TaskSourceBadge: View {
    let item: ActionItem

    var body: some View {
        if let badge = Self.badge(for: item) {
            Image(systemName: badge.symbol)
                .font(.caption2)
                .foregroundStyle(badge.color)
                .help(badge.tip)
        }
    }

    static func badge(for item: ActionItem) -> (symbol: String, color: Color, tip: String)? {
        if item.source == "linear" { return ("l.square", NDS.brand, "From Linear") }
        if item.source == "notion" { return ("n.square", .purple, "From Notion") }
        if !item.isManual { return ("calendar.badge.checkmark", NDS.textTertiary,
                                    "From “\(item.meetingTitle)”") }
        return ("pencil", NDS.textTertiary, "Created manually")
    }
}
