import SwiftUI

/// Shared due-date chip (VD-15). Relative phrasing ("2d overdue" / "Today" /
/// "Fri") with urgency color from `NDS.due` — red overdue, amber today, neutral
/// otherwise, muted when completed. One definition for table, list row, board,
/// calendar, and gallery so urgency reads the same everywhere.
@available(macOS 14.0, *)
struct DueChip: View {
    let date: Date?
    var status: ActionItem.Status = .open
    /// `chip` = tinted capsule (cards/rows); `plain` = bare colored text (table).
    var style: Style = .chip
    var showIcon: Bool = true

    enum Style { case chip, plain }

    var body: some View {
        let color = NDS.due(date, status: status)
        HStack(spacing: 4) {
            if showIcon, date != nil {
                Image(systemName: "calendar").font(.caption2)
            }
            Text(label).font(.caption2.monospacedDigit())
        }
        .foregroundStyle(date == nil ? NDS.textTertiary : color)
        .modifier(ChipBackground(style: style, color: color, active: date != nil))
        .accessibilityLabel(date == nil ? "No due date" : "Due \(accessibleLabel)")
    }

    private struct ChipBackground: ViewModifier {
        let style: Style
        let color: Color
        let active: Bool
        func body(content: Content) -> some View {
            switch style {
            case .plain:
                content
            case .chip:
                content
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(active ? color.opacity(0.14) : NDS.fieldBg, in: Capsule())
            }
        }
    }

    private var label: String {
        guard let date else { return "Set due" }
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        let startDue = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startToday, to: startDue).day ?? 0
        if status != .completed {
            if days < 0 { return "\(-days)d overdue" }
        }
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if days > 0 && days < 7 { return Self.weekday.string(from: date) }
        return Self.short.string(from: date)
    }

    private var accessibleLabel: String {
        guard let date else { return "" }
        return Self.short.string(from: date)
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let short: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
}
