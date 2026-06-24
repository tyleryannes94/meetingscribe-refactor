import SwiftUI

// MARK: - Initiative detail page (redesigned roll-up)
//
// One screen for an initiative: a compact, non-scrolling header (icon, name,
// progress, target, collapsible description) over its projects shown as a
// BOARD — one column per project, each holding that project's open tasks as
// draggable cards, with a per-column quick-add. Drag a card between columns to
// move it to another project. A LIST alternative stacks the same projects as
// collapsible sections in a single page scroll. The layout choice persists per
// initiative.
//
// Replaces the old three-band rollup (an embedded page clamped to 240pt with
// its own scroll + a progress strip + a second scrolling task list) that had
// multiple competing scroll regions.

@available(macOS 14.0, *)
struct InitiativeDetailView: View {
    let parent: ActionItemsView
    @ObservedObject var store: ActionItemStore
    let initiativeID: String

    enum Layout: String { case board, list }

    @AppStorage private var layoutRaw: String
    @State private var nameDraft = ""
    @State private var bodyDraft = ""
    @State private var descExpanded = false
    @State private var showIconPicker = false
    @State private var showTarget = false
    @State private var targetDraft = Date()

    init(parent: ActionItemsView, store: ActionItemStore, initiativeID: String) {
        self.parent = parent
        _store = ObservedObject(wrappedValue: store)
        self.initiativeID = initiativeID
        _layoutRaw = AppStorage(wrappedValue: Layout.board.rawValue,
                                "initiative.\(initiativeID).layout")
    }

    private var layout: Layout { Layout(rawValue: layoutRaw) ?? .board }
    private var initiative: Initiative? { store.initiative(id: initiativeID) }
    private var projects: [Project] { store.projects(forInitiative: initiativeID) }

    var body: some View {
        if let ini = initiative {
            content(ini)
                .background(NDS.bg)
                .onAppear { nameDraft = ini.name; bodyDraft = ini.body }
                .onChange(of: initiativeID) { _, _ in
                    nameDraft = ini.name; bodyDraft = ini.body; descExpanded = false
                }
        }
    }

    @ViewBuilder
    private func content(_ ini: Initiative) -> some View {
        switch layout {
        case .board:
            // Header is fixed; the board is a single two-axis scroll below it —
            // no nested/competing vertical scrolls.
            VStack(spacing: 0) {
                headerBlock(ini)
                Divider().overlay(NDS.divider)
                boardScroll
            }
        case .list:
            // The whole page is one vertical scroll.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerBlock(ini)
                    listSections.padding(.horizontal, 20)
                }
                .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Header

    private func headerBlock(_ ini: Initiative) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NotionEyebrow(text: "Initiative")
                Spacer()
                layoutToggle
            }
            HStack(spacing: 11) {
                Button { showIconPicker = true } label: {
                    Image(systemName: ini.icon ?? "flag.fill")
                        .scaledFont(22, weight: .semibold)
                        .foregroundStyle(NDS.brand)
                        .frame(width: 38, height: 38)
                        .background(NDS.brand.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showIconPicker, arrowEdge: .bottom) {
                    SymbolPicker(selection: Binding(
                        get: { ini.icon ?? "flag.fill" },
                        set: { store.setInitiativeIcon(initiativeID, icon: $0) }
                    ))
                }
                TextField("Untitled initiative", text: $nameDraft, onCommit: {
                    store.renameInitiative(initiativeID, name: nameDraft)
                })
                .textFieldStyle(.plain).font(NDS.title)
                Spacer()
                NotionChip("\(store.openCount(forInitiative: initiativeID)) open", color: NDS.brand)
            }
            headerProgress(ini)
            descriptionBlock(ini)
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    private func headerProgress(_ ini: Initiative) -> some View {
        let (done, total) = store.completion(forInitiative: initiativeID)
        let frac = total == 0 ? 0 : Double(done) / Double(total)
        return HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NDS.fieldBg).frame(height: 6)
                    Capsule().fill(NDS.brand).frame(width: geo.size.width * frac, height: 6)
                }
            }
            .frame(height: 6)
            Text("\(done)/\(total)")
                .font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textSecondary)
            targetControl(ini)
        }
    }

    private func targetControl(_ ini: Initiative) -> some View {
        let target = ini.targetDate
        return Menu {
            Button("Today") { store.setInitiativeTargetDate(initiativeID, Calendar.current.startOfDay(for: Date())) }
            Button("In 1 week") { store.setInitiativeTargetDate(initiativeID, Calendar.current.date(byAdding: .day, value: 7, to: Date())) }
            Button("In 1 month") { store.setInitiativeTargetDate(initiativeID, Calendar.current.date(byAdding: .month, value: 1, to: Date())) }
            if target != nil {
                Divider()
                Button("Clear target") { store.setInitiativeTargetDate(initiativeID, nil) }
            }
        } label: {
            if let t = target {
                NotionChip(Self.targetString(t), color: NDS.brand, systemImage: "target")
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "target").scaledFont(10)
                    Text("Set target").font(NDS.tiny)
                }
                .foregroundStyle(NDS.textTertiary)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    @ViewBuilder
    private func descriptionBlock(_ ini: Initiative) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeOut(duration: 0.15)) { descExpanded.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .scaledFont(8, weight: .bold)
                        .rotationEffect(.degrees(descExpanded ? 90 : 0))
                        .foregroundStyle(NDS.textTertiary)
                    Text(descExpanded ? "Description" : (ini.body.isEmpty ? "Add a description" : "Description"))
                        .font(NDS.small).foregroundStyle(NDS.textSecondary)
                    if !descExpanded, !ini.body.isEmpty {
                        Text("· \(ini.body.prefix(60))")
                            .font(NDS.small).foregroundStyle(NDS.textTertiary).lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if descExpanded {
                RichMarkdownEditor(text: Binding(
                    get: { bodyDraft },
                    set: { bodyDraft = $0; store.setInitiativeBody(initiativeID, body: $0) }
                ), placeholder: "Describe this initiative — goals, scope, timeline…")
                .frame(minHeight: 90, maxHeight: 180)
            }
        }
    }

    private var layoutToggle: some View {
        HStack(spacing: 2) {
            toggleButton(.board, icon: "rectangle.split.3x1", help: "Board")
            toggleButton(.list, icon: "list.bullet", help: "List")
        }
        .padding(2)
        .background(NDS.fieldBg, in: Capsule())
    }

    private func toggleButton(_ l: Layout, icon: String, help: String) -> some View {
        let selected = layout == l
        return Button { layoutRaw = l.rawValue } label: {
            Image(systemName: icon)
                .scaledFont(12, weight: selected ? .semibold : .regular)
                .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(selected ? NDS.rowSelected : .clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: - Board mode

    @ViewBuilder
    private var boardScroll: some View {
        if projects.isEmpty {
            emptyProjects
        } else {
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(projects) { p in
                        InitiativeProjectColumn(parent: parent, store: store, project: p,
                                                onOpen: { openProject($0) })
                    }
                    addProjectColumn
                }
                .padding(16)
            }
        }
    }

    private var addProjectColumn: some View {
        Button { addProject() } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus").scaledFont(15, weight: .semibold)
                Text("Add project").font(NDS.small)
            }
            .foregroundStyle(NDS.textTertiary)
            .frame(width: 200, height: 90)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(NDS.fieldBg.opacity(0.4), in: RoundedRectangle(cornerRadius: NDS.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius)
                .strokeBorder(NDS.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - List mode

    @ViewBuilder
    private var listSections: some View {
        if projects.isEmpty {
            emptyProjects
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(projects) { p in
                    let items = parent.initiativeProjectColumnItems(p.id)
                    MSSection(p.name, systemImage: p.icon ?? "doc.text",
                              count: items.count,
                              persistenceKey: "initiative.\(initiativeID).proj.\(p.id)",
                              trailing: {
                                  Button { openProject(p.id) } label: {
                                      Image(systemName: "arrow.up.right.square").scaledFont(12)
                                  }
                                  .buttonStyle(.plain).foregroundStyle(NDS.textTertiary)
                                  .help("Open project")
                              }) {
                        if items.isEmpty {
                            Text("No open tasks")
                                .font(NDS.small).foregroundStyle(NDS.textTertiary).padding(.vertical, 4)
                        } else {
                            ForEach(items) { parent.row(for: $0) }
                        }
                        QuickAddTaskField(placeholder: "Add to \(p.name)", projectID: p.id,
                                          sectionID: nil, status: .open)
                            .environmentObject(store)
                            .padding(.top, 4)
                    }
                }
                Button { addProject() } label: {
                    Label("Add project", systemImage: "plus").font(NDS.small)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.brand).padding(.top, 2)
            }
        }
    }

    // MARK: - Shared

    private var emptyProjects: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus").scaledFont(36).foregroundStyle(NDS.textTertiary)
            Text("No projects yet").scaledFont(15, weight: .semibold)
            Text("Group your work into projects under this initiative.")
                .font(NDS.small).foregroundStyle(NDS.textSecondary).multilineTextAlignment(.center)
            Button { addProject() } label: {
                Label("Create the first project", systemImage: "plus")
            }
            .buttonStyle(MSPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func openProject(_ pid: String) {
        parent.env.selectedInitiativeID = nil
        parent.env.selectedMeetingID = nil
        parent.env.selectedProjectID = pid
    }

    private func addProject() {
        let p = store.createProject(name: "Untitled")
        store.setProjectInitiative(p.id, initiativeID: initiativeID)
        openProject(p.id)
    }

    static func targetString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: d)
    }
}

// MARK: - One project column on the initiative board

@available(macOS 14.0, *)
private struct InitiativeProjectColumn: View {
    let parent: ActionItemsView
    @ObservedObject var store: ActionItemStore
    let project: Project
    var onOpen: (String) -> Void

    @State private var targetCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isTargeted: Bool { targetCount > 0 }
    private func setTargeted(_ t: Bool) { targetCount = max(0, targetCount + (t ? 1 : -1)) }
    private var items: [ActionItem] { parent.initiativeProjectColumnItems(project.id) }
    private var tint: Color { NDS.selectColor(project.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(items) { item in
                parent.boardCard(item, showProject: false)
                    .onTapGesture(count: 2) { parent.env.selectedTaskID = item.id }
                    .onTapGesture { parent.vm.editingID = item.id }
                    .taskQuickActions(item: item, store: store) { parent.env.selectedTaskID = item.id }
                    .draggable(item.id) {
                        Text(item.title).font(.caption).lineLimit(2)
                            .padding(8).frame(width: 220, alignment: .leading)
                            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        for id in ids { parent.dropCardToProject(id, toProject: project.id, beforeID: item.id) }
                        return true
                    } isTargeted: { setTargeted($0) }
            }
            QuickAddTaskField(placeholder: "Add to \(project.name)", projectID: project.id,
                              sectionID: nil, status: .open, collapseOnBlur: false)
                .environmentObject(store)
            // Tall droppable filler so a card can be dropped onto an empty column.
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 60)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { ids, _ in
                    for id in ids { parent.dropCardToProject(id, toProject: project.id, beforeID: nil) }
                    return true
                } isTargeted: { setTargeted($0) }
        }
        .frame(width: 280, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(8)
        .background(isTargeted ? tint.opacity(0.10) : NDS.columnBg,
                    in: RoundedRectangle(cornerRadius: NDS.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.cardRadius)
            .strokeBorder(tint.opacity(isTargeted ? 0.85 : 0), lineWidth: 1.5))
        .animation(NDS.motion(.easeOut(duration: NDS.motionFast), reduce: reduceMotion), value: isTargeted)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Image(systemName: project.icon ?? "doc.text")
                .scaledFont(11, weight: .semibold).foregroundStyle(tint)
            Button { onOpen(project.id) } label: {
                Text(project.name).font(.callout.weight(.bold)).foregroundStyle(NDS.textPrimary).lineLimit(1)
            }
            .buttonStyle(.plain).help("Open \(project.name)")
            Text("\(items.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            Spacer()
            Button {
                let t = store.createTask(title: "New task", projectID: project.id, status: .open)
                parent.env.selectedTaskID = t.id
            } label: { Image(systemName: "plus") }
            .buttonStyle(.borderless).help("Add a task to \(project.name)")
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Cross-project move (drag a card to another project's column)

@available(macOS 14.0, *)
extension ActionItemsView {
    /// Open, non-triage tasks in a project, ordered by manual sortIndex (drag
    /// order) then the default sort — the membership for one board column.
    func initiativeProjectColumnItems(_ projectID: String) -> [ActionItem] {
        store.items
            .filter { $0.projectID == projectID && $0.status != .completed && !$0.needsTriage }
            .sorted { a, b in
                let sa = a.sortIndex ?? .greatestFiniteMagnitude
                let sb = b.sortIndex ?? .greatestFiniteMagnitude
                if sa != sb { return sa < sb }
                return sort(a, b)
            }
    }

    /// Moves `id` into `projectID` (reassigning its project) and reorders it
    /// just before `beforeID` (or to the end when nil) via a midpoint sortIndex.
    func dropCardToProject(_ id: String, toProject projectID: String, beforeID: String?) {
        guard id != beforeID, store.items.contains(where: { $0.id == id }) else { return }
        let col = initiativeProjectColumnItems(projectID).filter { $0.id != id }
        let targetIndex: Int = {
            if let beforeID, let idx = col.firstIndex(where: { $0.id == beforeID }) { return idx }
            return col.count
        }()
        let prev = targetIndex > 0 ? col[targetIndex - 1].sortIndex : nil
        let next = targetIndex < col.count ? col[targetIndex].sortIndex : nil
        let newIndex: Double = {
            switch (prev, next) {
            case let (p?, n?): return (p + n) / 2
            case let (p?, nil): return p + 1
            case let (nil, n?): return n - 1
            case (nil, nil): return 0
            }
        }()
        if store.items.first(where: { $0.id == id })?.projectID != projectID {
            if let p = store.project(id: projectID), !store.pageHasDatabase(p) {
                store.setProjectDatabaseEnabled(projectID, true)
            }
            store.setProject(id, projectID: projectID)
        }
        store.setSortIndex(id, sortIndex: newIndex)
    }
}
