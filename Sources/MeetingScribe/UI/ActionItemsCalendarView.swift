import SwiftUI

/// Month calendar view over task due dates (VD-1) — the biggest missing-view
/// gap vs. Notion/Asana. Each task appears as a chip in its due-date cell
/// (overdue in red); tapping opens the task. Tasks with no due date don't
/// appear here (they live in the list/board).
@available(macOS 14.0, *)
extension ActionItemsView {

    private var gcal: Calendar { Calendar.current }

    var calendarBody: some View {
        let monthStart = startOfMonth(calendarMonth)
        return VStack(spacing: 10) {
            calendarHeader(monthStart)
            weekdayHeader
            calendarGrid(monthStart)
        }
        .padding(16)
    }

    private func calendarHeader(_ monthStart: Date) -> some View {
        HStack(spacing: 10) {
            Text(monthTitle(monthStart)).font(.title3.weight(.semibold))
            Spacer()
            Button { calendarMonth = addMonths(-1, to: monthStart) } label: {
                Image(systemName: "chevron.left")
            }.buttonStyle(.plain)
            Button("Today") { calendarMonth = Date() }.font(NDS.small).buttonStyle(.plain)
            Button { calendarMonth = addMonths(1, to: monthStart) } label: {
                Image(systemName: "chevron.right")
            }.buttonStyle(.plain)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(NDS.small).foregroundStyle(NDS.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func calendarGrid(_ monthStart: Date) -> some View {
        let cells = monthCells(monthStart)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    calendarCell(day)
                }
            }
        }
    }

    @ViewBuilder
    private func calendarCell(_ day: Date?) -> some View {
        if let day {
            let tasks = tasksDue(on: day)
            let isToday = gcal.isDateInToday(day)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(gcal.component(.day, from: day))")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? NDS.brand : NDS.textSecondary)
                ForEach(Array(tasks.prefix(3))) { t in
                    Text(t.title)
                        .scaledFont(9).lineLimit(1)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(taskDueTint(t).opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(taskDueTint(t))
                        .contentShape(Rectangle())
                        .onTapGesture { env.selectedTaskID = t.id }
                        .contextMenu { TaskQuickMenu(item: t, store: store, onOpen: { env.selectedTaskID = t.id }) }
                }
                if tasks.count > 3 {
                    Text("+\(tasks.count - 3) more").scaledFont(8).foregroundStyle(NDS.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(height: 94, alignment: .topLeading)
            .frame(maxWidth: .infinity)
            .background(isToday ? NDS.brand.opacity(0.06) : NDS.fieldBg, in: RoundedRectangle(cornerRadius: 6))
        } else {
            Color.clear.frame(height: 94)
        }
    }

    // MARK: Data + date helpers

    private func tasksDue(on day: Date) -> [ActionItem] {
        projectFiltered.filter { i in
            guard let d = i.dueDate else { return false }
            return gcal.isDate(d, inSameDayAs: day)
        }
    }

    private func taskDueTint(_ t: ActionItem) -> Color {
        if t.status == .completed { return NDS.textTertiary }
        if let d = t.dueDate, d < gcal.startOfDay(for: Date()) { return .red }
        return NDS.brand
    }

    private func startOfMonth(_ date: Date) -> Date {
        gcal.date(from: gcal.dateComponents([.year, .month], from: date)) ?? date
    }
    private func addMonths(_ n: Int, to date: Date) -> Date {
        gcal.date(byAdding: .month, value: n, to: date) ?? date
    }
    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }
    private var weekdaySymbols: [String] {
        let base = DateFormatter().veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let shift = gcal.firstWeekday - 1
        guard shift > 0, shift < base.count else { return base }
        return Array(base[shift...] + base[..<shift])
    }

    /// Cells for the month grid: leading blanks so the 1st sits under its
    /// weekday, then every day, padded to whole weeks.
    private func monthCells(_ monthStart: Date) -> [Date?] {
        let firstWeekday = gcal.component(.weekday, from: monthStart)
        let leading = (firstWeekday - gcal.firstWeekday + 7) % 7
        let numDays = gcal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<numDays {
            cells.append(gcal.date(byAdding: .day, value: d, to: monthStart))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
