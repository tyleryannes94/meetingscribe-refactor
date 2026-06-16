import SwiftUI

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - My Tasks (5-2)

    /// The current user's open tasks bucketed Asana-style into Recently Assigned
    /// / Today / Upcoming / Later. "Mine" reuses the established owner-alias match
    /// (an unowned task counts as the user's own capture).
    @ViewBuilder
    var myTasksPane: some View {
        let mine = store.items.filter {
            !$0.needsTriage && $0.status != .completed
                && ActionItemsViewModel.isMine($0, myNameAliases: Set(AppSettings.shared.myNameAliases))
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today) ?? today
        let in14 = cal.date(byAdding: .day, value: 14, to: today) ?? today

        let recentlyAssigned = mine.filter { $0.createdAt >= weekAgo }
            .sorted { $0.createdAt > $1.createdAt }
        let dueToday = mine.filter { $0.dueDate.map { cal.isDateInToday($0) } ?? false }
        let upcoming = mine.filter {
            guard let d = $0.dueDate else { return false }
            return d > today && d <= in14 && !cal.isDateInToday(d)
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let later = mine.filter {
            guard let d = $0.dueDate else { return true }
            return d > in14
        }

        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "person.fill").scaledFont(20).foregroundStyle(NDS.brand)
                Text("My Tasks").font(NDS.title)
                Spacer()
                stat(label: "Open", value: mine.count, color: NDS.brand)
            }
            .padding(.horizontal, 32).padding(.top, 22).padding(.bottom, 14)
            Divider().overlay(NDS.divider)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    myTasksSection("Recently assigned", items: Array(recentlyAssigned.prefix(20)))
                    myTasksSection("Today", items: dueToday)
                    myTasksSection("Upcoming", items: upcoming)
                    myTasksSection("Later", items: later)
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func myTasksSection(_ title: String, items: [ActionItem]) -> some View {
        if !items.isEmpty {
            DisclosureGroup {
                ForEach(items) { row(for: $0) }
            } label: {
                HStack(spacing: 6) {
                    Text(title).scaledFont(13, weight: .semibold)
                        .foregroundStyle(.secondary).textCase(.uppercase).tracking(0.6)
                    Text("\(items.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
