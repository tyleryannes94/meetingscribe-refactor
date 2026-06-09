import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Table view

    var tableBody: some View {
        ScrollView([.vertical]) {
            VStack(spacing: 0) {
                tableHeaderRow
                Divider()
                ForEach(tableSorted) { item in
                    tableRow(item)
                    Divider().opacity(0.4)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    /// `projectFiltered` ordered by the clicked column.
    var tableSorted: [ActionItem] {
        let asc = tableSortAscending
        func cmp<T: Comparable>(_ a: T, _ b: T) -> Bool { asc ? a < b : a > b }
        return projectFiltered.sorted { a, b in
            switch tableSort {
            case .task:    return cmp(a.title.lowercased(), b.title.lowercased())
            case .project:
                return cmp(store.project(for: a)?.name.lowercased() ?? "~",
                           store.project(for: b)?.name.lowercased() ?? "~")
            case .owner:   return cmp((a.owner ?? "~").lowercased(), (b.owner ?? "~").lowercased())
            case .priority: return cmp(a.priority.weight, b.priority.weight)
            case .due:
                return cmp(a.dueDate ?? .distantFuture, b.dueDate ?? .distantFuture)
            }
        }
    }

    var tableHeaderRow: some View {
        HStack(spacing: 10) {
            Text("").frame(width: 22)
            sortHeader("Task", .task).frame(maxWidth: .infinity, alignment: .leading)
            sortHeader("Project", .project).frame(width: 140, alignment: .leading)
            sortHeader("Owner", .owner).frame(width: 90, alignment: .leading)
            sortHeader("Priority", .priority).frame(width: 80, alignment: .leading)
            sortHeader("Due", .due).frame(width: 80, alignment: .leading)
            Text("Meeting").frame(width: 160, alignment: .leading)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.vertical, 6)
    }

    func sortHeader(_ label: String, _ col: TableSort) -> some View {
        Button {
            if tableSort == col { tableSortAscending.toggle() }
            else { tableSort = col; tableSortAscending = (col == .task || col == .owner || col == .project) }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                if tableSort == col {
                    Image(systemName: tableSortAscending ? "chevron.up" : "chevron.down")
                        .scaledFont(7, weight: .bold)
                }
            }
        }
        .buttonStyle(.plain)
    }

    func tableRow(_ item: ActionItem) -> some View {
        HStack(spacing: 10) {
            Button {
                store.setStatus(item.id, status: item.status == .completed ? .open : .completed)
            } label: {
                Image(systemName: item.status.systemImage)
                    .foregroundStyle(item.status == .completed ? .green
                                     : item.status == .inProgress ? .orange : .blue)
            }
            .buttonStyle(.plain).frame(width: 22)
            Text(item.title)
                .font(.callout)
                .strikethrough(item.status == .completed)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            projectCell(item).frame(width: 140, alignment: .leading)
            Group {
                if let owner = item.owner, !owner.isEmpty {
                    HStack(spacing: 5) {
                        TaskOwnerAvatar(name: owner, size: 16)
                        Text(owner).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text("—").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 90, alignment: .leading)
            Menu {
                ForEach(ActionItem.Priority.allCases) { p in
                    Button(p.label) { store.setPriority(item.id, priority: p) }
                }
            } label: {
                MSPriorityBadge(priority: item.priority)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: 96, alignment: .leading)
            Menu {
                Button("Today") { store.setDueDate(item.id, dueDate: Self.startOfToday()) }
                Button("Tomorrow") { store.setDueDate(item.id, dueDate: Self.daysFromToday(1)) }
                Button("Next week") { store.setDueDate(item.id, dueDate: Self.daysFromToday(7)) }
                if item.dueDate != nil {
                    Divider()
                    Button("Clear due date") { store.setDueDate(item.id, dueDate: nil) }
                }
            } label: {
                DueChip(date: item.dueDate, status: item.status, style: .plain)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: 96, alignment: .leading)
            Text(item.meetingTitle).font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(1).frame(width: 160, alignment: .leading)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { selectedTaskID = item.id }
    }

    @ViewBuilder
    func projectCell(_ item: ActionItem) -> some View {
        Menu {
            projectMenuItems(for: item)
        } label: {
            if let name = store.project(for: item)?.name {
                Text(name).font(.caption).lineLimit(1)
                    .foregroundStyle(NDS.brand)
            } else {
                Text("—").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
    }

    @ViewBuilder
    func projectMenuItems(for item: ActionItem) -> some View {
        Button("No project") { store.setProject(item.id, projectID: nil) }
        Divider()
        ForEach(store.projects) { p in
            Button(p.name) { store.setProject(item.id, projectID: p.id) }
        }
        Divider()
        Button("New project from this task…") {
            let p = store.createProject(name: item.meetingTitle)
            store.setProject(item.id, projectID: p.id)
        }
    }

    func priorityColor(_ p: ActionItem.Priority) -> Color { NDS.priority(p) }
    func dueShort(_ item: ActionItem) -> String {
        guard let d = item.dueDate else { return "—" }
        return Self.dueShortFormatter.string(from: d)
    }
    private static let dueShortFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    /// Overdue → red, due today → orange, otherwise neutral. (Completed never
    /// reads as overdue.)
    func dueColor(_ item: ActionItem) -> Color { NDS.due(item.dueDate, status: item.status) }

    static func startOfToday() -> Date { Calendar.current.startOfDay(for: Date()) }
    static func daysFromToday(_ n: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: n, to: startOfToday())
    }
}
