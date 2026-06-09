import SwiftUI

/// Status pill with a glyph (AV-4). Color comes from `NDS.status`, but meaning
/// is carried by the status `systemImage` too, so it stays legible for
/// colorblind users and in high-contrast mode — color is never the only signal.
@available(macOS 14.0, *)
struct MSStatusBadge: View {
    let status: ActionItem.Status
    var showLabel: Bool = true

    var body: some View {
        let color = NDS.status(status)
        HStack(spacing: 4) {
            Image(systemName: status.systemImage).font(.caption2)
            if showLabel { Text(status.label).font(.caption2) }
        }
        .foregroundStyle(color)
        .padding(.horizontal, showLabel ? 8 : 5).padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityLabel("Status: \(status.label)")
    }
}

/// Priority pill with a glyph (AV-4 / VD-5). Same contract as `MSStatusBadge`:
/// color from `NDS.priority`, redundancy from `NDS.priorityGlyph`.
@available(macOS 14.0, *)
struct MSPriorityBadge: View {
    let priority: ActionItem.Priority
    var showLabel: Bool = true

    var body: some View {
        let color = NDS.priority(priority)
        HStack(spacing: 4) {
            Image(systemName: NDS.priorityGlyph(priority)).font(.caption2)
            if showLabel { Text(priority.label).font(.caption2) }
        }
        .foregroundStyle(color)
        .padding(.horizontal, showLabel ? 8 : 5).padding(.vertical, 4)
        .background(color.opacity(0.16), in: Capsule())
        .accessibilityLabel("Priority: \(priority.label)")
    }
}
