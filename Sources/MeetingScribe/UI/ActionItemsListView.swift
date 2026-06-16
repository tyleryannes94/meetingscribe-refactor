import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Sectioned list (within a project)

    func sectionedListBody(projectID pid: String) -> some View {
        let secs = store.sections(forProject: pid)
        let secIDs = Set(secs.map { $0.id })
        let noSection = projectFiltered.filter { $0.sectionID == nil || !secIDs.contains($0.sectionID ?? "") }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(secs) { s in
                    sectionGroup(name: s.name,
                                 sectionID: s.id,
                                 rows: projectFiltered.filter { $0.sectionID == s.id },
                                 pid: pid)
                }
                if !noSection.isEmpty || secs.isEmpty {
                    sectionGroup(name: secs.isEmpty ? "Tasks" : "No section",
                                 sectionID: nil,
                                 rows: noSection,
                                 pid: pid)
                }
                addSectionControl(pid: pid)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    func sectionGroup(name: String, sectionID: String?, rows: [ActionItem], pid: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(name)
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(.secondary).textCase(.uppercase).tracking(0.6)
                Text("\(rows.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    let t = store.createTask(title: "New task", projectID: pid, sectionID: sectionID)
                    env.selectedTaskID = t.id
                } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless).help("Add a task to this section")
                .accessibilityLabel("Add a task to this section")
                if let sectionID {
                    Menu {
                        Button("Rename…") { renameSectionID = sectionID; renameSectionDraft = name }
                        Button(role: .destructive) {
                            if let undo = store.deleteSectionWithUndo(sectionID) {
                                ToastCenter.shared.show("Deleted section “\(name)”", undoTitle: "Undo", undo: undo)
                            }
                        } label: { Text("Delete section") }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Section options")
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { ids, _ in
                for id in ids { store.setSection(id, sectionID: sectionID) }
                return true
            }
            if rows.isEmpty {
                Text("Drag a task here, or click +")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(rows) { item in
                    row(for: item).draggable(item.id)
                }
            }
        }
    }

    @ViewBuilder
    func addSectionControl(pid: String) -> some View {
        if addingSection {
            HStack(spacing: 6) {
                TextField("Section name", text: $newSectionName, onCommit: { commitSection(pid: pid) })
                    .textFieldStyle(.roundedBorder).frame(width: 220)
                Button("Add") { commitSection(pid: pid) }
                Button("Cancel") { addingSection = false; newSectionName = "" }
            }
            .padding(.top, 6)
        } else {
            Button {
                addingSection = true
            } label: {
                Label("Add section", systemImage: "plus.rectangle.on.rectangle")
            }
            .buttonStyle(.borderless)
            .padding(.top, 6)
        }
    }

    func commitSection(pid: String) {
        let n = newSectionName.trimmingCharacters(in: .whitespaces)
        addingSection = false
        newSectionName = ""
        guard !n.isEmpty else { return }
        store.createSection(projectID: pid, name: n)
    }

    var listBody: some View {
        VStack(spacing: 0) {
            taskSelectToolbar
            ScrollView {
                LazyVStack(spacing: 8) {
                    switch vm.groupBy {
                    case .none:
                        ForEach(projectFiltered) { item in
                            selectableRow(item)
                                .background(focusedTaskID == item.id ? NDS.brand.opacity(0.07) : Color.clear)
                                .overlay(alignment: .leading) {
                                    if focusedTaskID == item.id {
                                        RoundedRectangle(cornerRadius: 1).fill(NDS.brand).frame(width: 2.5)
                                    }
                                }
                        }
                    default:
                        ForEach(groupedKeys, id: \.self) { key in
                            if let rows = grouped[key] {
                                section(title: key, items: rows)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .focusable()
        .onKeyPress(.downArrow) { moveFocus(1); return .handled }
        .onKeyPress(.upArrow) { moveFocus(-1); return .handled }
        .onKeyPress(KeyEquivalent("j")) { moveFocus(1); return .handled }
        .onKeyPress(KeyEquivalent("k")) { moveFocus(-1); return .handled }
        .onKeyPress(.return) { openFocused(); return .handled }
        .onKeyPress(.space) { toggleFocusedDone(); return .handled }
    }

    // MARK: - Keyboard navigation (UX-1)

    func moveFocus(_ delta: Int) {
        let order = projectFiltered.map(\.id)
        guard !order.isEmpty else { return }
        if let cur = focusedTaskID, let idx = order.firstIndex(of: cur) {
            focusedTaskID = order[min(max(idx + delta, 0), order.count - 1)]
        } else {
            focusedTaskID = delta >= 0 ? order.first : order.last
        }
    }
    func openFocused() {
        if let id = focusedTaskID { env.selectedTaskID = id }
    }
    func toggleFocusedDone() {
        guard let id = focusedTaskID, let item = store.items.first(where: { $0.id == id }) else { return }
        store.setStatus(id, status: item.status == .completed ? .open : .completed)
    }

    /// Wraps a row with a selection checkbox in multi-select mode. (TK-3)
    @ViewBuilder
    func selectableRow(_ item: ActionItem) -> some View {
        if taskSelectMode {
            HStack(spacing: 8) {
                Button { toggleTaskSelection(item.id) } label: {
                    Image(systemName: taskSelection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .scaledFont(16)
                        .foregroundStyle(taskSelection.contains(item.id) ? NDS.brand : NDS.textTertiary)
                }
                .buttonStyle(.borderless)
                row(for: item)
            }
        } else {
            row(for: item)
        }
    }

    /// Select toggle + bulk action bar (TK-3/TK-4): set status/priority/delete.
    @ViewBuilder
    var taskSelectToolbar: some View {
        HStack(spacing: 10) {
            Button(taskSelectMode ? "Done" : "Select") {
                taskSelectMode.toggle()
                if !taskSelectMode { taskSelection = [] }
            }
            .font(NDS.small)
            if taskSelectMode && !taskSelection.isEmpty {
                Text("\(taskSelection.count) selected")
                    .font(NDS.small).foregroundStyle(NDS.textSecondary)
                Spacer()
                Menu {
                    ForEach(ActionItem.Status.allCases) { s in
                        Button(s.label) { bulkSetStatus(s) }
                    }
                } label: { Label("Status", systemImage: "circle.lefthalf.filled") }
                .menuStyle(.borderlessButton).fixedSize()
                Menu {
                    ForEach(ActionItem.Priority.allCases) { p in
                        Button(p.label) { bulkSetPriority(p) }
                    }
                } label: { Label("Priority", systemImage: "flag") }
                .menuStyle(.borderlessButton).fixedSize()
                Menu {
                    Button("No project") { bulkMoveProject(nil) }
                    Divider()
                    ForEach(store.projects) { p in Button(p.name) { bulkMoveProject(p.id) } }
                } label: { Label("Project", systemImage: "folder") }
                .menuStyle(.borderlessButton).fixedSize()
                Menu {
                    Button("Today") { bulkSetDue(Self.startOfToday()) }
                    Button("Tomorrow") { bulkSetDue(Self.daysFromToday(1)) }
                    Button("Next week") { bulkSetDue(Self.daysFromToday(7)) }
                    Divider()
                    Button("Clear due date") { bulkSetDue(nil) }
                } label: { Label("Due", systemImage: "calendar") }
                .menuStyle(.borderlessButton).fixedSize()
                Button(role: .destructive) { bulkDeleteTasks() } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(NDS.divider) }
    }

    func toggleTaskSelection(_ id: String) {
        if taskSelection.contains(id) { taskSelection.remove(id) } else { taskSelection.insert(id) }
    }
    func bulkSetStatus(_ s: ActionItem.Status) {
        for id in taskSelection { store.setStatus(id, status: s) }
    }
    func bulkSetPriority(_ p: ActionItem.Priority) {
        for id in taskSelection { store.setPriority(id, priority: p) }
    }
    func bulkMoveProject(_ projectID: String?) {
        for id in taskSelection { store.setProject(id, projectID: projectID) }
    }
    func bulkSetDue(_ date: Date?) {
        for id in taskSelection { store.setDueDate(id, dueDate: date) }
    }
    func bulkDeleteTasks() {
        let ids = Array(taskSelection)
        guard !ids.isEmpty else { return }
        let trashed = store.delete(ids: ids)
        taskSelection = []
        taskSelectMode = false
        let n = trashed.count
        guard n > 0 else { return }
        ToastCenter.shared.show("Deleted \(n) \(n == 1 ? "task" : "tasks")", undoTitle: "Undo") {
            store.restore(ids: trashed)
        }
    }

    // MARK: - Filtered data

    /// Live tasks narrowed by the toolbar facets, via the single canonical
    /// implementation on `ActionItemsViewModel` (A0-1).
    var filtered: [ActionItem] {
        vm.filtered(store.items, myNameAliases: Set(AppSettings.shared.myNameAliases))
    }

    /// A task counts as "mine" when its owner matches one of my name aliases, or
    /// it's unassigned (my own captured task). Drives the "My open" quick view.
    func isMine(_ item: ActionItem) -> Bool {
        ActionItemsViewModel.isMine(item, myNameAliases: Set(AppSettings.shared.myNameAliases))
    }

    func sort(_ a: ActionItem, _ b: ActionItem) -> Bool {
        ActionItemsViewModel.defaultSort(a, b)
    }

    // MARK: - Grouping

    /// `filtered` narrowed to the project selected in the rail (if any).
    var projectFiltered: [ActionItem] {
        // People facet (P2-2): route the person scope through the shared
        // `TaskQueryEngine` so `TaskQuery.Scope.person` stops being dead code.
        if let personID = selectedPersonID {
            let query = TaskQuery(scope: .person(personID))
            return filtered.filter { TaskQueryEngine.matches($0, query, now: Date()) }
        }
        // Waiting-on bucket (P2-6): delegated commitments, oldest first.
        if isWaitingScope {
            return filtered.filter { $0.delegated == true }
                .sorted { $0.createdAt < $1.createdAt }
        }
        // "All tasks" and "Unsorted" honor the active context switcher (1-2);
        // an explicitly-opened project/person/waiting bucket spans contexts.
        guard let pid = env.selectedProjectID else { return contextFiltered(filtered) }
        if pid == Self.noProjectSentinel {
            return contextFiltered(filtered.filter { $0.projectID == nil })
        }
        return filtered.filter { $0.projectID == pid }
    }

    var grouped: [String: [ActionItem]] {
        vm.grouped(projectFiltered)
    }

    var groupedKeys: [String] {
        vm.groupedKeys(projectFiltered)
    }

    func groupKey(for item: ActionItem) -> String {
        vm.groupKey(for: item)
    }

    @ViewBuilder
    func section(title: String, items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase).tracking(0.6)
                Text("\(items.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.top, 8)
            ForEach(items) { selectableRow($0) }
        }
    }

    // MARK: - Row

    @ViewBuilder
    func row(for item: ActionItem) -> some View {
        ActionItemRow(
            item: item,
            projects: store.projects,
            projectName: store.project(for: item)?.name,
            allLabels: store.labels,
            assignedLabels: store.labels(for: item),
            isPushing: vm.pushingIDs.contains(item.id),
            isExpanded: vm.editingID == item.id,
            contextColor: store.contextColor(for: item),
            onToggleExpand: {
                // P0-2: single tap expands the inline detail editor in place.
                vm.editingID = (vm.editingID == item.id) ? nil : item.id
            },
            onOpenPage: {
                // Double-click (or ⏎ on the keyboard cursor) opens the full page.
                env.selectedTaskID = item.id
            },
            onStatus: { store.setStatus(item.id, status: $0) },
            onPriority: { store.setPriority(item.id, priority: $0) },
            onDue: { store.setDueDate(item.id, dueDate: $0) },
            onStart: { store.setStartDate(item.id, startDate: $0) },
            onTitle: { store.setTitle(item.id, title: $0) },
            onOwner: { store.setOwner(item.id, owner: $0?.isEmpty == true ? nil : $0) },
            onNotes: { store.setNotes(item.id, notes: $0?.isEmpty == true ? nil : $0) },
            onProject: { store.setProject(item.id, projectID: $0) },
            onCreateProject: { name in
                let p = store.createProject(name: name)
                store.setProject(item.id, projectID: p.id)
            },
            sections: item.projectID.map { store.sections(forProject: $0) } ?? [],
            onSection: { store.setSection(item.id, sectionID: $0) },
            onToggleLabel: { store.toggleLabel(item.id, labelID: $0) },
            onCreateLabel: { name in
                let l = store.createLabel(name: name)
                store.toggleLabel(item.id, labelID: l.id)
            },
            onAddSubtask: { store.addSubtask(item.id, title: $0) },
            onToggleSubtask: { store.toggleSubtask(item.id, subtaskID: $0) },
            onDeleteSubtask: { store.deleteSubtask(item.id, subtaskID: $0) },
            onDelete: {
                let id = item.id, title = item.title
                store.delete(id)
                ToastCenter.shared.show("Deleted “\(title)”", undoTitle: "Undo") { store.restore(id) }
            },
            onPush: { pushToNotion(item) },
            onOpenNotion: { url in
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            },
            onPushLinear: { pushToLinear(item) },
            onOpenLinear: { url in
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            }
        )
    }
}
