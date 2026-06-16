import SwiftUI
import AppKit

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Dashboard (default Tasks landing)

    var tasksDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 9) {
                    Text("✅").scaledFont(26)
                    Text("Tasks").font(NDS.title)
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    QuickActionCard("New task", subtitle: "Add a task", systemImage: "plus",
                                    tint: NDS.selectColor("green")) {
                        let t = store.createTask(title: "New task"); env.selectedProjectID = nil; env.selectedTaskID = t.id
                    }
                    QuickActionCard("New page", subtitle: "Add to your workspace",
                                    systemImage: "doc.badge.plus", tint: NDS.brand) {
                        let p = store.createProject(name: "Untitled"); env.selectedTaskID = nil; env.selectedProjectID = p.id
                    }
                    QuickActionCard("All tasks", subtitle: "\(store.openItems().count) open",
                                    systemImage: "tray.full", tint: NDS.selectColor("blue")) {
                        env.selectedTaskID = nil; env.selectedMeetingID = nil; env.selectedProjectID = nil
                    }
                    QuickActionCard("Board", subtitle: "Kanban view",
                                    systemImage: "rectangle.split.3x1", tint: NDS.selectColor("orange")) {
                        vm.viewMode = .board; env.selectedTaskID = nil; env.selectedMeetingID = nil; env.selectedProjectID = nil
                    }
                }

                dashboardSection("Open tasks", count: store.openItems().count) {
                    let items = Array(store.openItems().prefix(6))
                    if items.isEmpty {
                        dashEmpty("No open tasks. Nice.")
                    } else {
                        ForEach(items) { item in
                            Button { env.selectedProjectID = nil; env.selectedTaskID = item.id } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: item.status.systemImage)
                                        .foregroundStyle(item.status == .inProgress ? NDS.selectColor("orange") : NDS.selectColor("blue"))
                                    Text(item.title).font(NDS.body).lineLimit(1)
                                    Spacer()
                                    if let p = store.project(for: item) {
                                        NotionChip(p.name, color: NDS.selectColor(p.name))
                                    }
                                    Text(item.priority.label).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                dashboardSection("Pages", count: store.childProjects(of: nil).count) {
                    let pages = Array(store.childProjects(of: nil).prefix(8))
                    if pages.isEmpty { dashEmpty("No pages yet — create one above.") }
                    else {
                        ForEach(pages) { p in
                            Button { env.selectedTaskID = nil; env.selectedMeetingID = nil; env.selectedProjectID = p.id } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: p.icon ?? "doc.text").foregroundStyle(NDS.selectColor(p.name))
                                    Text(p.name).font(NDS.body).lineLimit(1)
                                    Spacer()
                                    let open = store.openCount(forProject: p.id)
                                    if open > 0 { Text("\(open)").font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                dashboardSection("Recent meeting notes", count: nil) {
                    let recent = Array(manager.pastMeetings.prefix(6))
                    if recent.isEmpty { dashEmpty("No meetings yet.") }
                    else {
                        ForEach(recent) { m in
                            Button { env.selectedTaskID = nil; env.selectedProjectID = nil; env.selectedMeetingID = m.id } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "doc.text").foregroundStyle(NDS.textSecondary)
                                    Text(m.displayTitle).font(NDS.body).lineLimit(1)
                                    Spacer()
                                    Text(Self.dashDate(m.startDate)).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .notionPageColumn()
        }
        .background(NDS.bg)
    }

    @ViewBuilder
    func dashboardSection<Content: View>(_ title: String, count: Int?,
                                                 @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NotionEyebrow(text: title, count: count)
                .padding(.horizontal, 10).padding(.bottom, 2)
            VStack(spacing: 1) { content() }
                .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NDS.hairline, lineWidth: 1))
        }
    }

    func dashEmpty(_ text: String) -> some View {
        Text(text).font(NDS.small).foregroundStyle(NDS.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 10)
    }

    static func dashDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }

    // MARK: - Project page (Notion-style: header → sub-pages → database/add)

    /// Context › Initiative › Project trail above a project pane (3-6).
    @ViewBuilder
    func projectCrumbBar(_ project: Project) -> some View {
        let initiative = project.initiativeID.flatMap { store.initiative(id: $0) }
        var crumbs: [BreadcrumbItem] {
            var c: [BreadcrumbItem] = [BreadcrumbItem(label: "Tasks", systemImage: "chevron.left",
                                                      action: { env.selectedProjectID = nil })]
            if let cid = initiative?.contextID, let ctx = store.context(id: cid) {
                c.append(BreadcrumbItem(label: ctx.name, color: store.contextColor(id: cid), action: nil))
            }
            if let initiative {
                c.append(BreadcrumbItem(label: initiative.name, systemImage: initiative.icon ?? "flag.fill",
                                        action: { env.go(.initiative(initiative.id)) }))
            }
            c.append(BreadcrumbItem(label: project.name, systemImage: project.icon ?? "doc.text", action: nil))
            return c
        }
        BreadcrumbBar(items: crumbs)
            .padding(.horizontal, 32).padding(.top, 14).padding(.bottom, 2)
    }

    @ViewBuilder
    func projectPane(_ project: Project) -> some View {
        let kids = store.childProjects(of: project.id)
        if store.pageHasDatabase(project) {
            projectCrumbBar(project)
            ProjectPageHeader(store: store, project: project, bodyFills: false,
                              onOpenInitiative: { env.selectedInitiativeID = $0 },
                              onOpenProject: { env.selectedProjectID = $0 })
            if !kids.isEmpty { subPagesSection(project, kids: kids) }
            Divider().overlay(NDS.divider)
            toolbar
            Divider().overlay(NDS.divider)
            content
        } else {
            // Free-form page: the markdown editor IS the page. Sections are
            // headings, to-dos are checkboxes — all authored inline. A
            // database is the one thing you add as a separate block.
            projectCrumbBar(project)
            ProjectPageHeader(store: store, project: project, bodyFills: true,
                              onOpenInitiative: { env.selectedInitiativeID = $0 },
                              onOpenProject: { env.selectedProjectID = $0 })
            docFooter(project, kids: kids)
        }
    }

    /// Slim bar under a free-form page: add a database (separate block) or a
    /// sub-page; shows sub-page links inline.
    func docFooter(_ project: Project, kids: [Project]) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(NDS.divider)
            HStack(spacing: 8) {
                Menu {
                    Button { enableDatabase(project, view: .table) } label: { Label("Table", systemImage: "tablecells") }
                    Button { enableDatabase(project, view: .board) } label: { Label("Board", systemImage: "rectangle.split.3x1") }
                    Button { enableDatabase(project, view: .list)  } label: { Label("List",  systemImage: "list.bullet") }
                } label: {
                    Label("Add database", systemImage: "tablecells.badge.ellipsis").font(NDS.small)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

                Button {
                    let p = store.createProject(name: "Untitled", parentID: project.id)
                    env.selectedProjectID = p.id
                } label: {
                    Label("Add sub-page", systemImage: "doc.badge.plus").font(NDS.small)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.textSecondary)

                if !kids.isEmpty {
                    Divider().frame(height: 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(kids) { k in
                                Button { env.selectedMeetingID = nil; env.selectedTaskID = nil; env.selectedProjectID = k.id } label: {
                                    NotionChip(k.name, color: NDS.selectColor(k.name), systemImage: k.icon ?? "doc.text")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 32).padding(.vertical, 8)
        }
    }

    func subPagesSection(_ project: Project, kids: [Project]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NotionEyebrow(text: "Sub-pages", count: kids.count)
                .padding(.bottom, 2)
            ForEach(kids) { k in
                Button {
                    env.selectedMeetingID = nil; env.selectedTaskID = nil; env.selectedProjectID = k.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: k.icon ?? "doc.text").scaledFont(13)
                            .foregroundStyle(NDS.selectColor(k.name))
                        Text(k.name).font(NDS.body).underline()
                        Spacer()
                        Image(systemName: "chevron.right").scaledFont(10).foregroundStyle(NDS.textTertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 8)
    }

    func enableDatabase(_ project: Project, view: ViewMode) {
        store.setProjectDatabaseEnabled(project.id, true)
        vm.viewMode = view
    }

    var taskDatabasePane: some View {
        VStack(spacing: 0) {
            if let pid = realSelectedProjectID, let project = store.project(id: pid) {
                projectPane(project)
            } else {
                header
                Divider().overlay(NDS.divider)
                toolbar
                Divider().overlay(NDS.divider)
                content
            }
            if let err = vm.lastError {
                errorBanner(err)
            }
        }
        .alert("Rename section", isPresented: Binding(
            get: { renameSectionID != nil },
            set: { if !$0 { renameSectionID = nil } }
        )) {
            TextField("Section name", text: $renameSectionDraft)
            Button("Save") {
                if let id = renameSectionID {
                    store.renameSection(id, name: renameSectionDraft.trimmingCharacters(in: .whitespaces))
                }
                renameSectionID = nil
            }
            Button("Cancel", role: .cancel) { renameSectionID = nil }
        }
        .onChange(of: manager.lastTaskSyncError) { _, v in
            if let v { vm.lastError = v }
        }
    }

    // MARK: - Header

    var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Text("📋").scaledFont(26)
                    Text(headerTitle).font(NDS.title)
                }
                Text(subtitle)
                    .font(NDS.small).foregroundStyle(NDS.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                stat(label: "Open", value: store.items.filter { $0.status == .open }.count, color: NDS.selectColor("blue"))
                stat(label: "In Progress", value: store.items.filter { $0.status == .inProgress }.count, color: NDS.selectColor("orange"))
                stat(label: "Done", value: store.items.filter { $0.status == .completed }.count, color: NDS.selectColor("green"))
            }
        }
        .padding(.horizontal, 32).padding(.top, 22).padding(.bottom, 14)
    }

    var headerTitle: String {
        if let pid = realSelectedProjectID, let p = store.project(id: pid) { return p.name }
        return "Action items"
    }

    func stat(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(value)").font(.system(size: 14, weight: .semibold).monospacedDigit()) // design-lint:allow
            Text(label).font(NDS.small).foregroundStyle(NDS.textSecondary)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 7))
    }

    var subtitle: String {
        let total = store.items.count
        if total == 0 { return "Add a task, or sync from Linear/Notion, or record a meeting." }
        let open = store.items.filter { $0.status != .completed }.count
        var s = "\(open) open · \(total) total"
        if let sync = manager.lastTaskSyncSummary { s += "  ·  \(sync)" }
        return s
    }

    // MARK: - Toolbar

    var toolbar: some View {
        HStack(spacing: 8) {
            // View switcher (text tabs)
            ForEach(ViewMode.allCases) { m in
                viewTab(m)
            }
            Divider().frame(height: 16).overlay(NDS.divider)
            // One-click saved-slice chips (P2-2 / UX-10) — the daily views that
            // were previously buried in the filter menu.
            quickViewChip("All", active: vm.filter == .all && vm.priorityFilter == .any && vm.ownerScope == .anyone) {
                vm.filter = .all; vm.priorityFilter = .any; vm.ownerScope = .anyone
            }
            quickViewChip("My open", active: vm.ownerScope == .mine && vm.filter == .open) {
                vm.ownerScope = .mine; vm.filter = .open; vm.priorityFilter = .any
            }
            quickViewChip("This week", active: vm.filter == .thisWeek) { vm.filter = .thisWeek }
            quickViewChip("Overdue", active: vm.filter == .overdue) { vm.filter = .overdue }
            if store.items.contains(where: { $0.delegated == true }) {
                quickViewChip("Delegated", active: vm.ownerScope == .delegated) {
                    vm.ownerScope = vm.ownerScope == .delegated ? .anyone : .delegated
                }
            }
            Spacer()
            // Active-filter pill (only when filtering)
            if vm.filter != .all || vm.priorityFilter != .any {
                Button { vm.filter = .all; vm.priorityFilter = .any } label: {
                    HStack(spacing: 4) {
                        Text(filterSummary).font(NDS.small)
                        Image(systemName: "xmark").scaledFont(9, weight: .bold)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(NDS.brand.opacity(0.14), in: Capsule())
                    .foregroundStyle(NDS.brand)
                }
                .buttonStyle(.plain)
            }
            // Filter + sort menu
            Menu {
                Picker("Status", selection: $vm.filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                Picker("Priority", selection: $vm.priorityFilter) {
                    ForEach(PriorityFilter.allCases) { Text($0.label).tag($0) }
                }
                if vm.viewMode == .list {
                    Picker("Group by", selection: $vm.groupBy) {
                        ForEach(GroupBy.allCases) { Text($0.label).tag($0) }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Filter & group")

            // Search (icon-style compact field)
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(NDS.textTertiary)
                TextField("Search", text: $vm.search).textFieldStyle(.plain).frame(width: 130)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 7))

            if manager.isSyncingTasks { ProgressView().controlSize(.small) }

            Button { quickAdding = true } label: { Label("New", systemImage: "plus") }
                .buttonStyle(UntitledPrimaryButtonStyle())
                .keyboardShortcut("n", modifiers: [.command, .option])
                .help("Create a new task (⌥⌘N)")
                .popover(isPresented: $quickAdding, arrowEdge: .bottom) { quickAddPopover }

            // Overflow
            Menu {
                Button {
                    Task { await manager.syncExternalTasks() }
                } label: { Label("Sync from Linear / Notion", systemImage: "arrow.triangle.2.circlepath") }
                .disabled(!manager.hasTaskConnectors)
                Button {
                    manager.backfillActionItemsIfNeeded(force: true)
                } label: { Label("Re-extract from meetings", systemImage: "arrow.clockwise") }
                Divider()
                Button { showInsights = true } label: {
                    Label("Insights", systemImage: "chart.bar.xaxis")
                }
                Button { exportTasksCSV() } label: {
                    Label("Export tasks (CSV)…", systemImage: "square.and.arrow.up")
                }
                Button { importTasksCSV() } label: {
                    Label("Import tasks (CSV)…", systemImage: "square.and.arrow.down")
                }
                Button { showShortcuts = true } label: {
                    Label("Keyboard shortcuts", systemImage: "keyboard")
                }
                Button {
                    showTrash = true
                } label: {
                    Label(store.trashedItems.isEmpty ? "Trash" : "Trash (\(store.trashedItems.count))",
                          systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
    }

    func viewTab(_ m: ViewMode) -> some View {
        let selected = vm.viewMode == m
        return Button { vm.viewMode = m } label: {
            HStack(spacing: 5) {
                Image(systemName: m.systemImage).scaledFont(11)
                Text(m.label).scaledFont(12.5, weight: selected ? .semibold : .regular)
            }
            .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(selected ? NDS.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func quickViewChip(_ label: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .scaledFont(12, weight: active ? .semibold : .regular)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? NDS.brand.opacity(0.16) : Color.clear, in: Capsule())
                .foregroundStyle(active ? NDS.brand : NDS.textSecondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    var filterSummary: String {
        var parts: [String] = []
        if vm.filter != .all { parts.append(vm.filter.label) }
        if vm.priorityFilter != .any { parts.append(vm.priorityFilter.label) }
        return parts.joined(separator: " · ")
    }

    /// Creates a manual task, scoped to the currently-selected project, and
    /// opens it for editing in the list view.
    /// Natural-language quick-add (P3-2). One line → a fully-specified task.
    var quickAddPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Email Sarah friday !high #work", text: $quickAddText)
                .textFieldStyle(.plain)
                .font(NDS.body)
                .frame(width: 320)
                .focused($quickAddFocused)
                .onSubmit { commitQuickAdd() }
                .onAppear { quickAddFocused = true }
            Text("Try +Project, due:friday, !high, #label, @person")
                .font(NDS.small).foregroundStyle(NDS.textTertiary)
        }
        .padding(14)
    }

    func commitQuickAdd() {
        let raw = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { quickAdding = false; return }
        let pid = realSelectedProjectID
        // Adding a task to a doc-only page turns its database on.
        if let pid, let p = store.project(id: pid), !store.pageHasDatabase(p) {
            store.setProjectDatabaseEnabled(pid, true)
        }
        _ = store.createTask(parsing: raw, projectID: pid)
        quickAddText = ""
        if vm.viewMode == .table || vm.viewMode == .board { vm.viewMode = .list }
        if vm.filter == .completed { vm.filter = .all }
        // Popover stays open + cleared for rapid multi-entry; refocus the field
        // so the next task can be typed without a mouse click (P0-1). Esc closes.
        Task { @MainActor in quickAddFocused = true }
    }

    func exportTasksCSV() {
        let csv = TaskExporter.csv(store.items,
                                   projectName: { store.project(id: $0)?.name },
                                   labelName: { store.label(id: $0)?.name })
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tasks.csv"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? Data(csv.utf8).write(to: url)
        }
    }

    func importTasksCSV() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let pid = realSelectedProjectID
        if let pid, let p = store.project(id: pid), !store.pageHasDatabase(p) {
            store.setProjectDatabaseEnabled(pid, true)
        }
        for row in TaskCSVImporter.parse(text) {
            let t = store.createTask(title: row.title, projectID: pid,
                                     status: row.status ?? .open, priority: row.priority ?? .medium)
            if let due = row.dueDate { store.setDueDate(t.id, dueDate: due) }
            if let owner = row.owner { store.setOwner(t.id, owner: owner) }
        }
    }

    func addTask() {
        let pid = (env.selectedProjectID == Self.noProjectSentinel) ? nil : env.selectedProjectID
        // Adding a task to a doc-only page turns its database on.
        if let pid, let p = store.project(id: pid), !store.pageHasDatabase(p) {
            store.setProjectDatabaseEnabled(pid, true)
        }
        let t = store.createTask(title: "New task", projectID: pid)
        vm.viewMode = .list
        if vm.filter == .completed { vm.filter = .all }
        env.selectedTaskID = t.id
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .scaledFont(40).foregroundStyle(.secondary)
            Text("No action items").font(.headline)
            Text(emptyMessage).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button {
                    addTask()
                } label: {
                    Label("New task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    manager.backfillActionItemsIfNeeded(force: true)
                } label: {
                    Label("Re-extract from meetings", systemImage: "arrow.clockwise")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    var emptyMessage: String {
        if store.items.isEmpty {
            return "Action items get pulled from each meeting's summary as it generates. Record a call, or click Re-extract to backfill from existing summaries."
        }
        return "No items match the current filters."
    }

    func errorBanner(_ err: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(err).font(.caption).textSelection(.enabled)
            Spacer()
            Button {
                vm.lastError = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Notion push

    func pushToNotion(_ item: ActionItem) {
        vm.pushingIDs.insert(item.id)
        vm.lastError = nil
        Task {
            do {
                if item.notionPageID != nil {
                    try await NotionActionItemService.update(item)
                } else {
                    let result = try await NotionActionItemService.push(item)
                    store.setNotion(item.id, pageID: result.id, url: result.url)
                }
            } catch {
                vm.lastError = error.localizedDescription
            }
            vm.pushingIDs.remove(item.id)
        }
    }

    // MARK: - Linear push

    /// Creates a Linear issue for this action item under the user's default
    /// team (Settings → Task sync). Stores the resulting issue ID/URL so the
    /// button flips to "Open in Linear". The backend (`createLinearIssue`)
    /// already existed and was only reachable through chat before this.
    func pushToLinear(_ item: ActionItem) {
        vm.pushingIDs.insert(item.id)
        vm.lastError = nil
        Task {
            do {
                let settings = AppSettings.shared
                guard let key = settings.linearAPIKey, !key.isEmpty else {
                    throw PushError("Linear API key isn't set. Open Settings → Task sync → add your Linear key.")
                }
                guard let teamID = settings.linearDefaultTeamID, !teamID.isEmpty else {
                    throw PushError("No default Linear team chosen. Open Settings → Task sync → Choose default team.")
                }
                let projectID = store.project(for: item)?.linearProjectID
                let result = try await TaskSyncService.createLinearIssue(
                    apiKey: key, teamID: teamID, title: item.title,
                    description: item.notes, projectID: projectID)
                store.setLinear(item.id, issueID: result.id, url: result.url)
            } catch {
                vm.lastError = error.localizedDescription
            }
            vm.pushingIDs.remove(item.id)
        }
    }
}

/// Lightweight error for user-facing push failures with a ready message.
struct PushError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
