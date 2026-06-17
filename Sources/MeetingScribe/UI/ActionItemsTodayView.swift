import SwiftUI

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Today smart view (1-3)

    /// Narrows a task list to the active workspace context (1-2). nil context
    /// ("All") passes everything through. Used by Today and the main list so the
    /// context switcher scopes every task surface consistently.
    func contextFiltered(_ list: [ActionItem]) -> [ActionItem] {
        guard let cid = env.activeContextID else { return list }
        return list.filter { store.effectiveContextID(for: $0) == cid }
    }

    /// Count that drives the sidebar "Today" badge: overdue + due-today, scoped
    /// to the active context.
    var todayCount: Int {
        contextFiltered(store.overdueTasks).count + contextFiltered(store.myDayTasks).count
    }

    /// The default Tasks landing (1-3): overdue first (red), then due today.
    /// Excludes triage items (those live in the inbox). Honors the context
    /// switcher.
    @ViewBuilder
    var todayPane: some View {
        let overdue = contextFiltered(store.overdueTasks).sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        let dueToday = contextFiltered(store.myDayTasks).sorted { sort($0, $1) }
        VStack(spacing: 0) {
            todayHeader(overdue: overdue.count, dueToday: dueToday.count)
            Divider().overlay(NDS.divider)
            if overdue.isEmpty && dueToday.isEmpty {
                todayEmpty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !overdue.isEmpty {
                            todaySection("Overdue", items: overdue, tint: NDS.selectColor("red"))
                        }
                        if !dueToday.isEmpty {
                            todaySection("Today", items: dueToday, tint: NDS.brand)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func todayHeader(overdue: Int, dueToday: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill").scaledFont(16).foregroundStyle(NDS.selectColor("orange"))
                    Text("Today").scaledFont(22, weight: .bold, kind: .display)
                }
                Text(Self.todayDateString())
                    .font(NDS.small).foregroundStyle(NDS.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                if overdue > 0 {
                    stat(label: "Overdue", value: overdue, color: NDS.selectColor("red"))
                }
                stat(label: "Due today", value: dueToday, color: NDS.brand)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }

    private func todaySection(_ title: String, items: [ActionItem], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title)
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(tint)
                    .textCase(.uppercase).tracking(0.6)
                Text("\(items.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer()
            }
            ForEach(items) { row(for: $0) }
        }
    }

    private var todayEmpty: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").scaledFont(40).foregroundStyle(NDS.selectColor("green"))
            Text("All clear for today").font(.headline)
            Text("Nothing overdue and nothing due today. Nice work.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    static func todayDateString() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}
