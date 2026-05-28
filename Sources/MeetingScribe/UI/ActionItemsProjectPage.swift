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
    @State private var nameDraft: String = ""
    @State private var bodyDraft: String = ""
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Menu {
                    ForEach(["doc.text", "folder.fill", "star.fill", "flag.fill", "bolt.fill",
                             "target", "lightbulb.fill", "rocket", "chart.bar.fill", "person.2.fill"], id: \.self) { ic in
                        Button { store.setProjectIcon(project.id, icon: ic) } label: { Label(ic, systemImage: ic) }
                    }
                } label: {
                    Image(systemName: project.icon ?? "doc.text")
                        .font(.system(size: 26)).foregroundStyle(NDS.selectColor(project.name))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                TextField("Untitled", text: $nameDraft, onCommit: {
                    store.setProjectName(project.id, name: nameDraft)
                })
                .textFieldStyle(.plain)
                .font(NDS.pageTitle)
                Spacer()
                if store.items(forProject: project.id).count > 0 {
                    Text("\(store.items(forProject: project.id).count) tasks")
                        .font(NDS.small).foregroundStyle(NDS.textTertiary)
                }
                if !bodyFills {
                    Button { withAnimation { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12)).foregroundStyle(NDS.textTertiary)
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
                            .font(.system(size: 26)).foregroundStyle(NDS.brand)
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
                                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(NDS.textTertiary)
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

// MARK: - Meeting notes page (a meeting as an editable workspace page)

@available(macOS 14.0, *)
struct MeetingNotesPage: View {
    let meeting: Meeting
    @ObservedObject var store: ActionItemStore
    @EnvironmentObject var manager: MeetingManager

    @State private var noteDraft: String = ""
    @State private var lastSaved: String = ""
    @State private var saveTimer: Timer?

    private var items: [ActionItem] { store.items(for: meeting.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider().opacity(0.5)

                Label("Notes", systemImage: "note.text")
                    .font(.headline)
                RichMarkdownEditor(text: $noteDraft,
                                   placeholder: "Write meeting notes in markdown…")
                    .frame(minHeight: 220, maxHeight: 460)

                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                    Text("Action items from this call").font(.headline)
                    Text("\(items.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
                .padding(.top, 6)
                if items.isEmpty {
                    Text("No action items extracted for you from this meeting.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        compactItemRow(item)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 18)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { load() }
        .onChange(of: meeting.id) { _, _ in flush(); load() }
        .onChange(of: noteDraft) { _, _ in scheduleSave() }
        .onDisappear { flush() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.displayTitle).font(.system(size: 26, weight: .bold))
            Text(Self.dateLine(meeting)).font(.callout).foregroundStyle(.secondary)
            if !meeting.attendees.isEmpty {
                Text(meeting.attendees.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let url = meeting.conferenceURL, let u = URL(string: url) {
                Link(destination: u) { Label(url, systemImage: "link").font(.caption) }
            }
        }
    }

    private func compactItemRow(_ item: ActionItem) -> some View {
        HStack(spacing: 10) {
            Button {
                store.setStatus(item.id, status: item.status == .completed ? .open : .completed)
            } label: {
                Image(systemName: item.status.systemImage)
                    .foregroundStyle(item.status == .completed ? .green
                                     : item.status == .inProgress ? .orange : .blue)
            }
            .buttonStyle(.plain)
            Text(item.title).font(.callout)
                .strikethrough(item.status == .completed)
                .foregroundStyle(item.status == .completed ? .secondary : .primary)
            Spacer()
            Menu {
                ForEach(ActionItem.Priority.allCases) { p in
                    Button(p.label) { store.setPriority(item.id, priority: p) }
                }
            } label: {
                Text(item.priority.label).font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Menu {
                Button("No project") { store.setProject(item.id, projectID: nil) }
                Divider()
                ForEach(store.projects) { p in
                    Button(p.name) { store.setProject(item.id, projectID: p.id) }
                }
            } label: {
                if let name = store.project(for: item)?.name {
                    Label(name, systemImage: "folder.fill").font(.caption2)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "folder.badge.plus").foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private func load() {
        let n = manager.userNotes(for: meeting)
        noteDraft = n; lastSaved = n
    }
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in flush() }
        }
    }
    private func flush() {
        saveTimer?.invalidate(); saveTimer = nil
        guard noteDraft != lastSaved else { return }
        manager.saveUserNotes(noteDraft, for: meeting)
        lastSaved = noteDraft
    }

    private static func dateLine(_ m: Meeting) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d  ·  h:mm a"
        return f.string(from: m.startDate)
    }
}
