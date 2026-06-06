import SwiftUI
import AppKit

/// Phase 6 — a task opened as a full Notion-style page: big editable title, a
/// property block, subtasks, and a rich markdown body. This is the "open a
/// database row as a full page" experience.
@available(macOS 14.0, *)
struct TaskPageView: View {
    @ObservedObject var store: ActionItemStore
    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var router: WorkspaceRouter
    let itemID: String
    var breadcrumb: String = "Tasks"
    let onClose: () -> Void

    /// Recent contacts surfaced first for the assignee→person link menu.
    private var personPickerList: [Person] {
        people.people
            .sorted { ($0.lastInteractionAt ?? .distantPast) > ($1.lastInteractionAt ?? .distantPast) }
            .prefix(50).map { $0 }
    }

    @State private var titleDraft = ""
    @State private var assigneeDraft = ""
    @State private var noteDraft = ""
    @State private var lastSavedNote = ""
    @State private var newSubtask = ""
    @State private var newLabel = ""
    @State private var saveTimer: Timer?
    @State private var dueShown = false
    @State private var startShown = false

    private var item: ActionItem? { store.items.first { $0.id == itemID } }

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    breadcrumbBar(item)
                    titleRow(item)
                        .padding(.top, 10)
                    properties(item)
                        .padding(.top, 14)
                    Divider().overlay(NDS.divider).padding(.vertical, 18)
                    subtasks(item)
                    bodyEditor
                        .padding(.top, 18)
                }
                .notionPageColumn()
            }
            .background(NDS.bg)
            .onAppear { load(item) }
            .onChange(of: itemID) { _, _ in
                flush()
                if let i = store.items.first(where: { $0.id == itemID }) { load(i) }
            }
            .onChange(of: noteDraft) { _, _ in scheduleSave() }
            .onDisappear { flush() }
        } else {
            VStack(spacing: 8) {
                Text("Task not found").font(.headline)
                Button("Back") { onClose() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Header

    private func breadcrumbBar(_ item: ActionItem) -> some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text(breadcrumb).font(NDS.small)
                }
                .foregroundStyle(NDS.textSecondary)
            }
            .buttonStyle(.plain)
            Spacer()
            if let url = item.externalURL, let u = URL(string: url) {
                Button { NSWorkspace.shared.open(u) } label: {
                    NotionChip(item.source?.capitalized ?? "Source", systemImage: "arrow.up.right")
                }
                .buttonStyle(.plain)
            }
            if let url = item.notionURL, let u = URL(string: url) {
                Button { NSWorkspace.shared.open(u) } label: {
                    NotionChip("Notion", color: NDS.selectColor("purple"), systemImage: "arrow.up.right")
                }
                .buttonStyle(.plain)
            }
            Menu {
                Button(role: .destructive) {
                    let title = item.title
                    store.delete(itemID)
                    onClose()
                    ToastCenter.shared.show("Deleted “\(title)”", undoTitle: "Undo") {
                        store.restore(itemID)
                    }
                } label: {
                    Label("Delete task", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(NDS.textSecondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    private func titleRow(_ item: ActionItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { store.setStatus(itemID, status: item.status == .completed ? .open : .completed) } label: {
                Image(systemName: item.status.systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(statusColor(item.status))
            }
            .buttonStyle(.plain)
            TextField("Untitled", text: $titleDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(NDS.title)
                .onChange(of: titleDraft) { _, v in
                    if v != item.title { store.setTitle(itemID, title: v) }
                }
        }
    }

    // MARK: Properties

    @ViewBuilder
    private func properties(_ item: ActionItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            NotionPropertyRow(icon: "circle.dotted", label: "Status") {
                Menu {
                    ForEach(ActionItem.Status.allCases) { s in
                        Button { store.setStatus(itemID, status: s) } label: { Label(s.label, systemImage: s.systemImage) }
                    }
                } label: {
                    NotionChip(item.status.label, color: statusColor(item.status), systemImage: item.status.systemImage)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            NotionPropertyRow(icon: "flag", label: "Priority") {
                Menu {
                    ForEach(ActionItem.Priority.allCases) { p in
                        Button(p.label) { store.setPriority(itemID, priority: p) }
                    }
                } label: { NotionChip(item.priority.label, color: priorityColor(item.priority)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            NotionPropertyRow(icon: "person", label: "Assignee") {
                HStack(spacing: 6) {
                    TextField("Empty", text: $assigneeDraft)
                        .textFieldStyle(.plain).font(NDS.body)
                        .onSubmit {
                            // Free-text edit clears any stale hard link unless it
                            // still matches the linked person's name.
                            let name = assigneeDraft.isEmpty ? nil : assigneeDraft
                            if let pid = item.ownerPersonID,
                               people.person(by: pid)?.displayName == assigneeDraft {
                                store.setOwnerPerson(itemID, personID: pid, ownerName: name)
                            } else {
                                store.setOwnerPerson(itemID, personID: nil, ownerName: name)
                            }
                        }
                    // Link to a Person record (exact, navigable).
                    Menu {
                        if item.ownerPersonID != nil {
                            Button("Unlink person") {
                                store.setOwnerPerson(itemID, personID: nil,
                                                     ownerName: assigneeDraft.isEmpty ? nil : assigneeDraft)
                            }
                            Divider()
                        }
                        ForEach(personPickerList) { p in
                            Button(p.displayName) {
                                assigneeDraft = p.displayName
                                store.setOwnerPerson(itemID, personID: p.id, ownerName: p.displayName)
                            }
                        }
                    } label: {
                        Image(systemName: item.ownerPersonID == nil
                              ? "person.crop.circle.badge.plus"
                              : "person.crop.circle.badge.checkmark")
                            .foregroundStyle(item.ownerPersonID == nil ? NDS.textTertiary : NDS.brand)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Link this assignee to a person")
                    if let pid = item.ownerPersonID, people.person(by: pid) != nil {
                        Button { router.openPerson(pid) } label: {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderless).help("Open person")
                    }
                }
            }
            NotionPropertyRow(icon: "calendar.badge.clock", label: "Start") {
                dateButton(item.startDate, show: $startShown) { store.setStartDate(itemID, startDate: $0) }
            }
            NotionPropertyRow(icon: "calendar", label: "Due") {
                dateButton(item.dueDate, show: $dueShown) { store.setDueDate(itemID, dueDate: $0) }
            }
            NotionPropertyRow(icon: "folder", label: "Project") {
                Menu {
                    Button("No project") { store.setProject(itemID, projectID: nil) }
                    Divider()
                    ForEach(store.projects) { p in Button(p.name) { store.setProject(itemID, projectID: p.id) } }
                } label: {
                    if let p = store.project(for: item) { NotionChip(p.name, color: NDS.selectColor(p.name), systemImage: "folder.fill") }
                    else { Text("Empty").font(NDS.body).foregroundStyle(NDS.textTertiary) }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if let pid = item.projectID, !store.sections(forProject: pid).isEmpty {
                NotionPropertyRow(icon: "rectangle.split.1x2", label: "Section") {
                    Menu {
                        Button("No section") { store.setSection(itemID, sectionID: nil) }
                        Divider()
                        ForEach(store.sections(forProject: pid)) { s in
                            Button(s.name) { store.setSection(itemID, sectionID: s.id) }
                        }
                    } label: {
                        if let sid = item.sectionID, let s = store.sections(forProject: pid).first(where: { $0.id == sid }) {
                            NotionChip(s.name)
                        } else { Text("Empty").font(NDS.body).foregroundStyle(NDS.textTertiary) }
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
            NotionPropertyRow(icon: "tag", label: "Labels") {
                labelsField(item)
            }
            if !item.isManual {
                NotionPropertyRow(icon: "calendar.badge.checkmark", label: "From meeting") {
                    if item.meetingID.isEmpty {
                        Text(item.meetingTitle).font(NDS.body).foregroundStyle(NDS.textSecondary).lineLimit(1)
                    } else {
                        // Clickable → opens the source meeting (was dead text). (A3/UX4-1)
                        Button {
                            NotificationCenter.default.post(
                                name: .meetingScribeOpenEntity, object: nil,
                                userInfo: ["url": WorkspaceLink.url(kind: .meeting, id: item.meetingID).absoluteString])
                        } label: {
                            HStack(spacing: 4) {
                                Text(item.meetingTitle).font(NDS.body).foregroundStyle(NDS.brand).lineLimit(1)
                                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(NDS.brand)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func labelsField(_ item: ActionItem) -> some View {
        let assigned = store.labels(for: item)
        return HStack(spacing: 6) {
            ForEach(assigned) { l in
                NotionChip(l.name, color: Color(hex: l.colorHex) ?? .gray)
            }
            Menu {
                ForEach(store.labels) { l in
                    Button { store.toggleLabel(itemID, labelID: l.id) } label: {
                        Label(l.name, systemImage: item.labels.contains(l.id) ? "checkmark" : "tag")
                    }
                }
                if !store.labels.isEmpty { Divider() }
                Button("New label “\(newLabel)”") {
                    let n = newLabel.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { let l = store.createLabel(name: n); store.toggleLabel(itemID, labelID: l.id); newLabel = "" }
                }
                .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            } label: {
                Image(systemName: "plus.circle").font(.system(size: 12)).foregroundStyle(NDS.textTertiary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            TextField("New label", text: $newLabel, onCommit: {
                let n = newLabel.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { let l = store.createLabel(name: n); store.toggleLabel(itemID, labelID: l.id); newLabel = "" }
            })
            .textFieldStyle(.plain).font(NDS.small).frame(width: 90)
        }
    }

    private func dateButton(_ date: Date?, show: Binding<Bool>, set: @escaping (Date?) -> Void) -> some View {
        Button { show.wrappedValue = true } label: {
            if let date {
                Text(date.formatted(date: .abbreviated, time: .omitted)).font(NDS.body).foregroundStyle(NDS.textPrimary)
            } else {
                Text("Empty").font(NDS.body).foregroundStyle(NDS.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: show) {
            VStack(alignment: .leading, spacing: 10) {
                DatePicker("", selection: Binding(get: { date ?? Date() }, set: { set($0) }), displayedComponents: [.date])
                    .datePickerStyle(.graphical).labelsHidden()
                HStack {
                    Button("Clear", role: .destructive) { set(nil); show.wrappedValue = false }
                    Spacer()
                    Button("Done") { show.wrappedValue = false }.keyboardShortcut(.defaultAction)
                }
            }.padding(14).frame(width: 280)
        }
    }

    // MARK: Subtasks

    @ViewBuilder
    private func subtasks(_ item: ActionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NotionEyebrow(text: "Subtasks", count: item.subtaskProgress.total > 0 ? item.subtaskProgress.total : nil)
                if item.subtaskProgress.total > 0 {
                    Text("\(item.subtaskProgress.done) done")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
            }
            ForEach(item.subtaskList) { sub in
                HStack(spacing: 9) {
                    Button { store.toggleSubtask(itemID, subtaskID: sub.id) } label: {
                        Image(systemName: sub.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(sub.done ? NDS.selectColor("green") : NDS.textTertiary)
                    }.buttonStyle(.plain)
                    Text(sub.title).font(NDS.body)
                        .strikethrough(sub.done).foregroundStyle(sub.done ? NDS.textTertiary : NDS.textPrimary)
                    Spacer()
                    NotionIconButton(systemName: "xmark") { store.deleteSubtask(itemID, subtaskID: sub.id) }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(NDS.textTertiary)
                TextField("Add subtask…", text: $newSubtask, onCommit: addSubtask)
                    .textFieldStyle(.plain).font(NDS.body).onSubmit(addSubtask)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotionEyebrow(text: "Notes")
            RichMarkdownEditor(text: $noteDraft, placeholder: "Type / for blocks, or just start writing…")
                .frame(minHeight: 240, maxHeight: 520)
        }
    }

    // MARK: Helpers

    private func addSubtask() {
        let t = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addSubtask(itemID, title: t)
        newSubtask = ""
    }

    private func load(_ item: ActionItem) {
        titleDraft = item.title
        assigneeDraft = item.owner ?? ""
        noteDraft = item.notes ?? ""
        lastSavedNote = noteDraft
    }
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in flush() }
        }
    }
    private func flush() {
        saveTimer?.invalidate(); saveTimer = nil
        guard noteDraft != lastSavedNote else { return }
        store.setNotes(itemID, notes: noteDraft.isEmpty ? nil : noteDraft)
        lastSavedNote = noteDraft
    }

    private func statusColor(_ s: ActionItem.Status) -> Color {
        switch s {
        case .open: return NDS.selectColor("blue")
        case .inProgress: return NDS.selectColor("orange")
        case .completed: return NDS.selectColor("green")
        }
    }
    private func priorityColor(_ p: ActionItem.Priority) -> Color {
        switch p {
        case .low: return NDS.palette[0].color
        case .medium: return NDS.selectColor("blue")
        case .high: return NDS.selectColor("orange")
        case .urgent: return NDS.selectColor("red")
        }
    }
}
