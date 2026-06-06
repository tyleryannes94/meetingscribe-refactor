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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary).textCase(.uppercase).tracking(0.6)
                Text("\(rows.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    let t = store.createTask(title: "New task", projectID: pid, sectionID: sectionID)
                    selectedTaskID = t.id
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
                    switch groupBy {
                    case .none:
                        ForEach(projectFiltered) { selectableRow($0) }
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
    }

    /// Wraps a row with a selection checkbox in multi-select mode. (TK-3)
    @ViewBuilder
    func selectableRow(_ item: ActionItem) -> some View {
        if taskSelectMode {
            HStack(spacing: 8) {
                Button { toggleTaskSelection(item.id) } label: {
                    Image(systemName: taskSelection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
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

    var filtered: [ActionItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return store.items
            .filter { item in
                switch filter {
                case .all: return true
                case .open: return item.status == .open
                case .inProgress: return item.status == .inProgress
                case .completed: return item.status == .completed
                case .upcoming:
                    guard let due = item.dueDate, item.status != .completed else { return false }
                    let weekOut = cal.date(byAdding: .day, value: 7, to: today) ?? today
                    return due >= today && due <= weekOut
                case .thisWeek:
                    guard item.status != .completed else { return false }
                    let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
                    let endOfWeek = cal.date(byAdding: .day, value: 7, to: startOfWeek) ?? today
                    let createdThisWeek = item.createdAt >= startOfWeek && item.createdAt < endOfWeek
                    let dueThisWeek = item.dueDate.map { $0 >= startOfWeek && $0 < endOfWeek } ?? false
                    return createdThisWeek || dueThisWeek
                case .overdue:
                    guard let due = item.dueDate else { return false }
                    return due < today && item.status != .completed
                }
            }
            .filter { item in
                switch priorityFilter {
                case .any: return true
                case .low: return item.priority == .low
                case .medium: return item.priority == .medium
                case .high: return item.priority == .high
                case .urgent: return item.priority == .urgent
                }
            }
            .filter { item in
                switch ownerScope {
                case .anyone: return true
                case .mine: return isMine(item)
                }
            }
            .filter { item in
                guard !search.isEmpty else { return true }
                let q = search.lowercased()
                return item.title.lowercased().contains(q)
                    || (item.owner ?? "").lowercased().contains(q)
                    || item.meetingTitle.lowercased().contains(q)
            }
            .sorted(by: sort)
    }

    /// A task counts as "mine" when its owner matches one of my name aliases, or
    /// it's unassigned (my own captured task). Drives the "My open" quick view.
    func isMine(_ item: ActionItem) -> Bool {
        let owner = (item.owner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if owner.isEmpty { return true }
        return AppSettings.shared.myNameAliases.contains(owner.lowercased())
    }

    func sort(_ a: ActionItem, _ b: ActionItem) -> Bool {
        if a.status == .completed && b.status != .completed { return false }
        if b.status == .completed && a.status != .completed { return true }
        switch (a.dueDate, b.dueDate) {
        case (let x?, let y?): if x != y { return x < y }
        case (nil, _?): return false
        case (_?, nil): return true
        default: break
        }
        if a.priority.weight != b.priority.weight {
            return a.priority.weight > b.priority.weight
        }
        return a.meetingDate > b.meetingDate
    }

    // MARK: - Grouping

    /// `filtered` narrowed to the project selected in the rail (if any).
    var projectFiltered: [ActionItem] {
        guard let pid = selectedProjectID else { return filtered }
        if pid == Self.noProjectSentinel {
            return filtered.filter { $0.projectID == nil }
        }
        return filtered.filter { $0.projectID == pid }
    }

    var grouped: [String: [ActionItem]] {
        Dictionary(grouping: projectFiltered, by: { groupKey(for: $0) })
    }

    var groupedKeys: [String] {
        let keys = Array(grouped.keys)
        switch groupBy {
        case .priority:
            let order = ["Urgent", "High", "Medium", "Low"]
            return order.filter { keys.contains($0) }
        case .status:
            let order = ["In Progress", "Open", "Completed"]
            return order.filter { keys.contains($0) }
        default:
            return keys.sorted()
        }
    }

    func groupKey(for item: ActionItem) -> String {
        switch groupBy {
        case .none: return ""
        case .meeting: return item.meetingTitle
        case .priority: return item.priority.label
        case .status: return item.status.label
        case .dueDate:
            guard let d = item.dueDate else { return "No due date" }
            let cal = Calendar.current
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDateInTomorrow(d) { return "Tomorrow" }
            if cal.isDateInYesterday(d) { return "Yesterday" }
            if d < Date() { return "Overdue" }
            let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
            return f.string(from: d)
        }
    }

    @ViewBuilder
    func section(title: String, items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
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
            isPushing: pushingIDs.contains(item.id),
            isExpanded: editingID == item.id,
            onToggleExpand: {
                selectedTaskID = item.id
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
