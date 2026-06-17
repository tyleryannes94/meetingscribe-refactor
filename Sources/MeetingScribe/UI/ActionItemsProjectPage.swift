import SwiftUI
import AppKit

// MARK: - Project page header (editable name + markdown body)

@available(macOS 14.0, *)
struct ProjectPageHeader: View {
    @ObservedObject var store: ActionItemStore
    @EnvironmentObject var manager: MeetingManager
    let project: Project
    /// When true (database-less page), the body editor is the page's main
    /// content and fills available height — write sections (`#`) and to-dos
    /// (`- [ ]`) freely. When false, it's a compact description above a database.
    var bodyFills: Bool = false
    /// Breadcrumb navigation callbacks (VD-12).
    var onOpenInitiative: ((String) -> Void)? = nil
    var onOpenProject: ((String) -> Void)? = nil
    @State private var nameDraft: String = ""
    @State private var bodyDraft: String = ""
    @State private var expanded = true
    @State private var showTargetPicker = false
    @State private var targetDraft = Date()
    @State private var showIconPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            breadcrumbBar
            HStack(spacing: 11) {
                Button { showIconPicker = true } label: {
                    Image(systemName: project.icon ?? "doc.text")
                        .scaledFont(26).foregroundStyle(NDS.selectColor(project.name))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showIconPicker, arrowEdge: .bottom) {
                    SymbolPicker(
                        selection: Binding(
                            get: { project.icon ?? "doc.text" },
                            set: { store.setProjectIcon(project.id, icon: $0) }
                        ),
                        tint: NDS.selectColor(project.name)
                    )
                }
                TextField("Untitled", text: $nameDraft, onCommit: {
                    store.setProjectName(project.id, name: nameDraft)
                })
                .textFieldStyle(.plain)
                .font(NDS.pageTitle)
                Spacer()
                let progress = store.completion(forProject: project.id)
                if progress.total > 0 {
                    HStack(spacing: 6) {
                        ProgressView(value: Double(progress.done), total: Double(progress.total))
                            .frame(width: 72).controlSize(.small).tint(NDS.brand)
                        Text("\(progress.done)/\(progress.total)")
                            .font(NDS.small).foregroundStyle(NDS.textTertiary)
                    }
                }
                targetDateControl
                if !bodyFills {
                    Button { withAnimation { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .scaledFont(12).foregroundStyle(NDS.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            metaRow
            if expanded || bodyFills {
                RichMarkdownEditor(text: Binding(
                    get: { bodyDraft },
                    set: { bodyDraft = $0; store.setProjectBody(project.id, body: $0) }
                ), placeholder: bodyFills
                    ? "Write freely — type / for headings, to-dos, and more…"
                    : "Add a description — type / for blocks…")
                .frame(minHeight: bodyFills ? 220 : 90, maxHeight: bodyFills ? .infinity : 240)
            }
        }
        .padding(.horizontal, 32).padding(.top, 22).padding(.bottom, 12)
        .frame(maxHeight: bodyFills ? .infinity : nil, alignment: .top)
        .onAppear { nameDraft = project.name; bodyDraft = project.body }
        .onChange(of: project.id) { _, _ in nameDraft = project.name; bodyDraft = project.body }
    }

    private var targetDateControl: some View {
        Button {
            targetDraft = project.targetDate ?? Date()
            showTargetPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "target").scaledFont(11)
                Text(project.targetDate.map(targetLabel) ?? "Set target")
            }
            .font(NDS.small).foregroundStyle(targetColor)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTargetPicker) {
            VStack(alignment: .leading, spacing: 10) {
                DatePicker("Target date", selection: $targetDraft, displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden()
                HStack {
                    if project.targetDate != nil {
                        Button("Clear") {
                            store.setProjectTargetDate(project.id, nil); showTargetPicker = false
                        }
                    }
                    Spacer()
                    Button("Done") {
                        store.setProjectTargetDate(project.id, Calendar.current.startOfDay(for: targetDraft))
                        showTargetPicker = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14).frame(width: 280)
        }
    }

    private func targetLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        if days == 0 { return "Due today" }
        if days < 0 { return "\(-days)d overdue" }
        return "\(days)d left"
    }

    private var targetColor: Color {
        guard let d = project.targetDate else { return NDS.textTertiary }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: d)
        if due < today { return .red }
        if due == today { return .orange }
        return NDS.textSecondary
    }

    @ViewBuilder
    private var breadcrumbBar: some View {
        let crumbs = breadcrumbItems
        if !crumbs.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { _, c in
                    Button {
                        if c.isInitiative { onOpenInitiative?(c.id) } else { onOpenProject?(c.id) }
                    } label: {
                        Text(c.name).font(NDS.small).foregroundStyle(NDS.textTertiary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "chevron.right").scaledFont(8).foregroundStyle(NDS.textTertiary)
                }
            }
        }
    }

    /// Ancestor chain (Initiative › parent pages…) above the current project.
    private var breadcrumbItems: [(id: String, name: String, isInitiative: Bool)] {
        var result: [(String, String, Bool)] = []
        if let iid = project.initiativeID, let initiative = store.initiative(id: iid) {
            result.append((iid, initiative.name, true))
        }
        var chain: [Project] = []
        var pid = project.parentID
        var hops = 0
        while let p = pid, hops < 50, let proj = store.project(id: p) {
            chain.insert(proj, at: 0)
            pid = proj.parentID
            hops += 1
        }
        for p in chain { result.append((p.id, p.name, false)) }
        return result
    }

    private var metaRow: some View {
        let linked = store.meetingIDs(forProject: project.id)
            .compactMap { id in manager.pastMeetings.first { $0.id == id } }
        return HStack(spacing: 10) {
            // Initiative selector
            Menu {
                Button("No initiative") { store.setProjectInitiative(project.id, initiativeID: nil) }
                Divider()
                ForEach(store.sortedInitiatives()) { ini in
                    Button(ini.name) { store.setProjectInitiative(project.id, initiativeID: ini.id) }
                }
            } label: {
                if let iid = project.initiativeID, let ini = store.initiative(id: iid) {
                    NotionChip(ini.name, color: NDS.brand, systemImage: "flag.fill")
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "flag").font(.caption2)
                        Text("Add to initiative").font(NDS.small)
                    }.foregroundStyle(NDS.textTertiary)
                }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            // Linked meetings
            Menu {
                if linked.isEmpty { Text("No meetings linked") }
                ForEach(linked) { m in
                    Button("✓ \(m.displayTitle)") { store.unlinkMeeting(m.id, fromProject: project.id) }
                }
                Divider()
                Text("Link a meeting").font(.caption)
                ForEach(manager.pastMeetings.prefix(20)) { m in
                    if !linked.contains(where: { $0.id == m.id }) {
                        Button(m.displayTitle) { store.linkMeeting(m.id, toProject: project.id) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "link").font(.caption2)
                    Text(linked.isEmpty ? "Link meetings" : "\(linked.count) meeting\(linked.count == 1 ? "" : "s")")
                        .font(NDS.small)
                }.foregroundStyle(linked.isEmpty ? NDS.textTertiary : NDS.textSecondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            if manager.linearConfigured {
                LinearLinkControl(store: store, project: project)
            }
            Spacer()
        }
    }
}

// MARK: - Linear project link control

@available(macOS 14.0, *)
struct LinearLinkControl: View {
    @ObservedObject var store: ActionItemStore
    @EnvironmentObject var manager: MeetingManager
    let project: Project
    @State private var showPicker = false
    @State private var projects: [TaskSyncService.LinearProjectRef] = []
    @State private var loading = false

    var body: some View {
        if let lid = project.linearProjectID {
            Menu {
                Button("Sync issues now") {
                    Task { await manager.importLinearProject(localProjectID: project.id, linearProjectID: lid) }
                }
                Button("Unlink", role: .destructive) {
                    store.setProjectLinearID(project.id, linearProjectID: nil)
                }
            } label: {
                NotionChip(manager.isSyncingTasks ? "Linear…" : "Linear",
                           color: NDS.selectColor("purple"), systemImage: "arrow.triangle.2.circlepath")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        } else {
            Button { showPicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "link.badge.plus").font(.caption2)
                    Text("Link Linear").font(NDS.small)
                }.foregroundStyle(NDS.textTertiary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker) { picker }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Link a Linear project").font(.headline)
            Text("Imports its issues under this project and keeps them in sync.")
                .font(.caption2).foregroundStyle(.secondary)
            if loading {
                HStack { ProgressView().controlSize(.small); Text("Loading…").font(.caption) }
            } else if projects.isEmpty {
                Text("No Linear projects found. Check your key in Settings → Integrations.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(projects) { p in
                            Button {
                                showPicker = false
                                Task { await manager.importLinearProject(localProjectID: project.id, linearProjectID: p.id) }
                            } label: {
                                HStack { Text(p.name).font(NDS.body); Spacer() }
                                    .padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(14).frame(width: 320)
        .task {
            loading = true
            projects = await manager.fetchLinearProjectList()
            loading = false
        }
    }
}

// MARK: - Initiative page (overview + its projects)

@available(macOS 14.0, *)
struct InitiativePage: View {
    @ObservedObject var store: ActionItemStore
    let initiativeID: String
    var onOpenProject: (String) -> Void
    @State private var nameDraft = ""
    @State private var bodyDraft = ""

    private var initiative: Initiative? { store.initiative(id: initiativeID) }

    var body: some View {
        if let ini = initiative {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 11) {
                        Image(systemName: ini.icon ?? "flag.fill")
                            .scaledFont(26).foregroundStyle(NDS.brand)
                        TextField("Untitled initiative", text: $nameDraft, onCommit: {
                            store.renameInitiative(initiativeID, name: nameDraft)
                        })
                        .textFieldStyle(.plain).font(NDS.title)
                        Spacer()
                        NotionChip("\(store.openCount(forInitiative: initiativeID)) open", color: NDS.selectColor("blue"))
                    }
                    RichMarkdownEditor(text: Binding(
                        get: { bodyDraft },
                        set: { bodyDraft = $0; store.setInitiativeBody(initiativeID, body: $0) }
                    ), placeholder: "Describe this initiative — goals, scope, timeline…")
                    .frame(minHeight: 100, maxHeight: 240)

                    let projects = store.projects(forInitiative: initiativeID)
                    HStack {
                        NotionEyebrow(text: "Projects", count: projects.count)
                        Spacer()
                        Button {
                            let p = store.createProject(name: "Untitled")
                            store.setProjectInitiative(p.id, initiativeID: initiativeID)
                            onOpenProject(p.id)
                        } label: { Label("Add project", systemImage: "plus") }
                        .buttonStyle(.borderless).controlSize(.small)
                    }
                    if projects.isEmpty {
                        Text("No projects yet. Add one to start organizing work under this initiative.")
                            .font(NDS.small).foregroundStyle(NDS.textTertiary)
                    } else {
                        VStack(spacing: 1) {
                            ForEach(projects) { p in
                                Button { onOpenProject(p.id) } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: p.icon ?? "doc.text").foregroundStyle(NDS.selectColor(p.name))
                                        Text(p.name).font(NDS.body)
                                        Spacer()
                                        let open = store.openCount(forProject: p.id)
                                        if open > 0 { Text("\(open) open").font(NDS.tiny).foregroundStyle(NDS.textTertiary) }
                                        Image(systemName: "chevron.right").scaledFont(10).foregroundStyle(NDS.textTertiary)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NDS.hairline, lineWidth: 1))
                    }
                }
                .notionPageColumn()
            }
            .background(NDS.bg)
            .onAppear { nameDraft = ini.name; bodyDraft = ini.body }
            .onChange(of: initiativeID) { _, _ in nameDraft = ini.name; bodyDraft = ini.body }
        }
    }
}
