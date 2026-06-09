import SwiftUI

/// Lightweight task analytics (PM-12). A read-only sheet that shows the *shape*
/// of the work — status mix, overdue, weekly throughput, and the busiest
/// projects — so the tab earns its place as a real planning tool. Uses simple
/// proportional bars (no charting dependency) and reads the live store.
@available(macOS 14.0, *)
struct TaskInsightsView: View {
    @ObservedObject var store: ActionItemStore
    @Environment(\.dismiss) private var dismiss

    private var live: [ActionItem] { store.items }
    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(NDS.textSecondary)
                Text("Insights").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().overlay(NDS.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statRow
                    section("Completed in the last 7 days") { completedPerDay }
                    section("Busiest projects (open tasks)") { topProjects }
                }
                .padding(18)
            }
        }
        .frame(width: 520, height: 560)
        .background(NDS.bg)
    }

    // MARK: Stats

    private var openCount: Int { live.filter { $0.status == .open }.count }
    private var inProgressCount: Int { live.filter { $0.status == .inProgress }.count }
    private var doneCount: Int { live.filter { $0.status == .completed }.count }
    private var overdueCount: Int {
        let today = cal.startOfDay(for: Date())
        return live.filter { i in
            guard let d = i.dueDate, i.status != .completed else { return false }
            return d < today
        }.count
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            stat("Open", openCount, .blue)
            stat("In progress", inProgressCount, .orange)
            stat("Done", doneCount, .green)
            stat("Overdue", overdueCount, .red)
        }
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 26, weight: .semibold)).foregroundStyle(color)
            Text(label).font(NDS.small).foregroundStyle(NDS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Sections

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(NDS.small.weight(.semibold)).foregroundStyle(NDS.textTertiary)
            content()
        }
    }

    /// (label, count) for each of the last 7 days, oldest → newest.
    private var last7Days: [(label: String, count: Int)] {
        let f = DateFormatter(); f.dateFormat = "EEE"
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let count = live.filter { i in
                guard let c = i.completedAt else { return false }
                return cal.isDate(c, inSameDayAs: day)
            }.count
            return (f.string(from: day), count)
        }
    }

    private var completedPerDay: some View {
        let data = last7Days
        let maxV = max(data.map(\.count).max() ?? 0, 1)
        return VStack(spacing: 6) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                bar(label: d.label, value: d.count, maxValue: maxV, tint: NDS.brand)
            }
        }
    }

    private var topProjects: some View {
        let data = store.projects
            .map { (name: $0.name, count: store.openCount(forProject: $0.id)) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(6)
        let maxV = max(data.map(\.count).max() ?? 0, 1)
        return Group {
            if data.isEmpty {
                Text("No open tasks in any project.").font(NDS.small).foregroundStyle(NDS.textTertiary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                        bar(label: d.name, value: d.count, maxValue: maxV, tint: NDS.selectColor(d.name))
                    }
                }
            }
        }
    }

    private func bar(label: String, value: Int, maxValue: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(NDS.small).foregroundStyle(NDS.textSecondary)
                .frame(width: 96, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                let w = geo.size.width * CGFloat(value) / CGFloat(maxValue)
                ZStack(alignment: .leading) {
                    Capsule().fill(NDS.fieldBg).frame(height: 14)
                    Capsule().fill(tint).frame(width: max(value > 0 ? 6 : 0, w), height: 14)
                }
            }
            .frame(height: 14)
            Text("\(value)").font(NDS.small.monospacedDigit()).foregroundStyle(NDS.textTertiary)
                .frame(width: 28, alignment: .trailing)
        }
    }
}
