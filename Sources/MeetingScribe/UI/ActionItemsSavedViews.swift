import SwiftUI

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Saved views (5-1)

    /// Renders a saved view by running its persisted `TaskQuery` through the
    /// store's query engine.
    @ViewBuilder
    func savedViewPane(_ id: String) -> some View {
        if let view = store.savedView(id: id) {
            let tasks = store.tasks(matching: view.query)
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Image(systemName: view.icon ?? "line.3.horizontal.decrease.circle")
                            .scaledFont(16).foregroundStyle(NDS.brand)
                        Text(view.name).scaledFont(22, weight: .bold, kind: .display)
                    }
                    Spacer()
                    stat(label: "Tasks", value: tasks.count, color: NDS.brand)
                    if !view.isBuiltIn {
                        Menu {
                            Button(role: .destructive) { store.deleteSavedTaskView(id); env.selectedProjectID = nil } label: {
                                Label("Delete view", systemImage: "trash")
                            }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
                Divider().overlay(NDS.divider)
                if tasks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle").scaledFont(36).foregroundStyle(NDS.selectColor("green"))
                        Text("Nothing matches this view").font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) { ForEach(tasks) { row(for: $0) } }
                            .padding(16)
                    }
                }
            }
        }
    }

    /// Builds a `TaskQuery` from the current toolbar filter state (5-1), so an
    /// active filter can be saved as a one-click view.
    func currentSavedQuery() -> TaskQuery {
        var f = TaskQuery.Filters(includeCompleted: vm.filter == .completed)
        switch vm.filter {
        case .all: break
        case .open: f.statuses = [.open]; f.includeCompleted = false
        case .inProgress: f.statuses = [.inProgress]; f.includeCompleted = false
        case .completed: f.statuses = [.completed]; f.includeCompleted = true
        case .overdue: f.overdue = true; f.includeCompleted = false
        case .thisWeek, .upcoming: f.dueWithinDays = 7; f.includeCompleted = false
        }
        if vm.priorityFilter != .any {
            let p: ActionItem.Priority
            switch vm.priorityFilter {
            case .low: p = .low; case .medium: p = .medium
            case .high: p = .high; case .urgent: p = .urgent; case .any: p = .medium
            }
            f.priorities = [p]
        }
        let q = vm.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { f.search = q }
        return TaskQuery(scope: .all, filters: f)
    }

    /// True when there's an active filter worth saving (drives the "Save view" button).
    var hasActiveFilter: Bool {
        vm.filter != .all || vm.priorityFilter != .any
            || !vm.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The Recurring smart list (5-3): every task carrying a repeat rule.
    @ViewBuilder
    var recurringPane: some View {
        let tasks = store.items
            .filter { !$0.needsTriage && $0.recurrence != nil }
            .sorted { sort($0, $1) }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "repeat").scaledFont(16).foregroundStyle(NDS.brand)
                Text("Recurring").scaledFont(22, weight: .bold, kind: .display)
                Spacer()
                stat(label: "Tasks", value: tasks.count, color: NDS.brand)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
            Divider().overlay(NDS.divider)
            if tasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "repeat").scaledFont(36).foregroundStyle(NDS.textTertiary)
                    Text("No recurring tasks").font(.headline)
                    Text("Set a repeat rule on a task to have it respawn when completed.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
            } else {
                ScrollView { LazyVStack(spacing: 8) { ForEach(tasks) { row(for: $0) } }.padding(16) }
            }
        }
    }

    func commitSaveView() {
        let name = newViewName.trimmingCharacters(in: .whitespacesAndNewlines)
        savingView = false
        guard !name.isEmpty else { return }
        let v = store.createSavedTaskView(name: name, icon: "line.3.horizontal.decrease.circle",
                                          query: currentSavedQuery())
        newViewName = ""
        env.selectedProjectID = Self.savedViewSentinel(v.id)
    }
}
