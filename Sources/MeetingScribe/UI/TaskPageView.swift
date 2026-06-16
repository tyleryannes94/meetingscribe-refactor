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
    @EnvironmentObject var manager: MeetingManager
    let itemID: String
    var breadcrumb: String = "Tasks"
    let onClose: () -> Void
    /// Routes a breadcrumb segment tap up the hierarchy (3-6).
    var onNavigate: (TasksRoute) -> Void = { _ in }

    /// Recent contacts surfaced first for the assignee→person link menu.
    private var personPickerList: [Person] {
        people.people
            .sorted { ($0.lastInteractionAt ?? .distantPast) > ($1.lastInteractionAt ?? .distantPast) }
            .prefix(50).map { $0 }
    }

    /// Other tasks (not self, not already a blocker) offered as dependencies.
    private func blockerCandidates(_ item: ActionItem) -> [ActionItem] {
        let existing = Set(item.blockedByIDs ?? [])
        return store.items
            .filter { $0.id != item.id && !existing.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(50).map { $0 }
    }

    @State private var titleDraft = ""
    @State private var assigneeDraft = ""
    @State private var noteDraft = ""
    @State private var lastSavedNote = ""
    @State private var newSubtask = ""
    /// Keeps the "Add subtask" field focused across rapid entries (P0-1).
    @FocusState private var subtaskFocused: Bool
    @State private var newLabel = ""
    @State private var saveTimer: Timer?
    @State private var dueShown = false
    @State private var startShown = false
    /// Inline source-meeting peek popover (4-4).
    @State private var meetingPeekShown = false

    private var item: ActionItem? { store.items.first { $0.id == itemID } }

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    breadcrumbBar(item)
                    titleRow(item)
                        .padding(.top, 10)
                    if !item.isManual {
                        provenanceStrip(item).padding(.top, 12)
                    }
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

    /// Context › Initiative › Project trail (3-6), each segment routing up.
    private func crumbItems(_ item: ActionItem) -> [BreadcrumbItem] {
        var crumbs: [BreadcrumbItem] = [
            BreadcrumbItem(label: breadcrumb, systemImage: "chevron.left", action: onClose)
        ]
        let project = item.projectID.flatMap { pid in store.projects.first { $0.id == pid } }
        let initiative = project?.initiativeID.flatMap { iid in store.initiative(id: iid) }
        if let cid = store.effectiveContextID(for: item), let ctx = store.context(id: cid) {
            crumbs.append(BreadcrumbItem(label: ctx.name, color: store.contextColor(id: cid),
                                         action: nil))
        }
        if let initiative {
            crumbs.append(BreadcrumbItem(label: initiative.name, systemImage: initiative.icon ?? "flag.fill",
                                         action: { onNavigate(.initiative(initiative.id)) }))
        }
        if let project {
            crumbs.append(BreadcrumbItem(label: project.name, systemImage: project.icon ?? "doc.text",
                                         action: { onNavigate(.project(project.id)) }))
        }
        return crumbs
    }

    private func breadcrumbBar(_ item: ActionItem) -> some View {
        HStack(spacing: 6) {
            BreadcrumbBar(items: crumbItems(item))
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
                // Save this task's shape as a reusable template (5-4).
                Button {
                    let t = store.createTemplate(name: item.title, from: item)
                    ToastCenter.shared.show("Saved “\(t.name)” as a template")
                } label: {
                    Label("Save as template", systemImage: "doc.on.doc")
                }
                Divider()
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
                    .scaledFont(22)
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
            NotionPropertyRow(icon: "repeat", label: "Repeat") {
                Menu {
                    Button("Don't repeat") { store.setRecurrence(itemID, nil) }
                    Divider()
                    ForEach(RecurrenceRule.Frequency.allCases) { f in
                        Button(f.label) { store.setRecurrence(itemID, RecurrenceRule(frequency: f)) }
                    }
                    // Custom intervals (5-3d).
                    Menu("Custom interval") {
                        Button("Every 2 days") { store.setRecurrence(itemID, RecurrenceRule(frequency: .daily, interval: 2)) }
                        Button("Every 2 weeks") { store.setRecurrence(itemID, RecurrenceRule(frequency: .weekly, interval: 2)) }
                        Button("Every 3 weeks") { store.setRecurrence(itemID, RecurrenceRule(frequency: .weekly, interval: 3)) }
                        Button("Every 2 months") { store.setRecurrence(itemID, RecurrenceRule(frequency: .monthly, interval: 2)) }
                        Button("Every quarter") { store.setRecurrence(itemID, RecurrenceRule(frequency: .monthly, interval: 3)) }
                    }
                    // Series-wide change (5-3c): only meaningful once part of a series.
                    if item.seriesID != nil, let r = item.recurrence {
                        Divider()
                        Button("Apply “\(r.label)” to this & all future") {
                            store.setRecurrenceForSeries(itemID, r)
                        }
                    }
                } label: {
                    NotionChip(item.recurrence?.label ?? "None",
                               color: item.recurrence == nil ? NDS.textTertiary : NDS.brand,
                               systemImage: "repeat")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            NotionPropertyRow(icon: "exclamationmark.octagon", label: "Blocked by") {
                HStack(spacing: 6) {
                    let blockers = store.blockers(for: item)
                    if store.isBlocked(item) {
                        NotionChip("Blocked", color: .red, systemImage: "exclamationmark.octagon")
                    } else if !blockers.isEmpty {
                        NotionChip("\(blockers.count) linked", color: NDS.textTertiary)
                    } else {
                        Text("None").font(NDS.body).foregroundStyle(NDS.textTertiary)
                    }
                    Menu {
                        if !blockers.isEmpty {
                            ForEach(blockers) { b in
                                Button { store.toggleBlocker(itemID, blockerID: b.id) } label: {
                                    Label("Remove “\(b.title)”", systemImage: "minus.circle")
                                }
                            }
                            Divider()
                        }
                        ForEach(blockerCandidates(item)) { t in
                            Button(t.title) { store.toggleBlocker(itemID, blockerID: t.id) }
                        }
                    } label: {
                        Image(systemName: "plus.circle").foregroundStyle(NDS.textTertiary)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Add or remove a blocking task")
                }
            }
            NotionPropertyRow(icon: "gauge.medium", label: "Estimate") {
                Menu {
                    Button("None") { store.setEstimate(itemID, nil) }
                    Divider()
                    ForEach([1.0, 2, 3, 5, 8, 13], id: \.self) { v in
                        Button("\(Int(v)) pt\(v == 1 ? "" : "s")") { store.setEstimate(itemID, v) }
                    }
                } label: {
                    NotionChip(item.estimate.map { "\(Int($0)) pt\($0 == 1 ? "" : "s")" } ?? "None",
                               color: item.estimate == nil ? NDS.textTertiary : NDS.brand,
                               systemImage: "gauge.medium")
                }
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
            if let pid = item.projectID {
                // Sprint / cycle (6-1).
                NotionPropertyRow(icon: "circle.dashed", label: "Sprint") {
                    Menu {
                        Button("No sprint") { store.setTaskSprint(itemID, sprintID: nil) }
                        Divider()
                        ForEach(store.sprints(forProject: pid)) { s in
                            Button(s.name) { store.setTaskSprint(itemID, sprintID: s.id) }
                        }
                        Divider()
                        Button("New sprint…") {
                            let s = store.createSprint(forProject: pid, name: "Sprint \((store.sprints(forProject: pid).count) + 1)")
                            store.setTaskSprint(itemID, sprintID: s.id)
                        }
                    } label: {
                        if let sid = item.sprintID, let s = store.sprint(sid, inProject: pid) {
                            NotionChip(s.name, color: NDS.brand, systemImage: "circle.dashed")
                        } else {
                            Text("Empty").font(NDS.body).foregroundStyle(NDS.textTertiary)
                        }
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
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
                        // 4-4: peek at the meeting inline instead of jumping tabs.
                        Button { meetingPeekShown = true } label: {
                            HStack(spacing: 4) {
                                Text(item.meetingTitle).font(NDS.body).foregroundStyle(NDS.brand).lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(NDS.brand)
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $meetingPeekShown, arrowEdge: .bottom) {
                            MeetingPeekPanel(meetingID: item.meetingID, onOpenFull: { openSourceMeeting(item) })
                        }
                    }
                }
            }
            customPropertiesSection(item)
        }
    }

    /// User-defined database properties for the task's project (NP-1), plus an
    /// "Add property" menu. Empty when the task isn't in a project.
    @ViewBuilder
    private func customPropertiesSection(_ item: ActionItem) -> some View {
        if let pid = item.projectID {
            ForEach(store.propertyDefs(forProject: pid)) { def in
                CustomPropertyRow(store: store, projectID: pid, itemID: itemID,
                                  def: def, value: item.properties?[def.id])
            }
            Menu {
                ForEach(PropertyType.allCases) { t in
                    Button { store.addProperty(toProject: pid, name: t.label, type: t) } label: {
                        Label(t.label, systemImage: t.systemImage)
                    }
                }
            } label: {
                Label("Add property", systemImage: "plus")
                    .font(NDS.small).foregroundStyle(NDS.textTertiary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
                Image(systemName: "plus.circle").scaledFont(12).foregroundStyle(NDS.textTertiary)
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
            // 2-5: type-ahead date entry with a graphical calendar fallback.
            DateTypeAheadField(date: Binding(get: { date }, set: { set($0) }),
                               onCommit: { show.wrappedValue = false })
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
                Image(systemName: "plus").scaledFont(11).foregroundStyle(NDS.textTertiary)
                TextField("Add subtask…", text: $newSubtask, onCommit: addSubtask)
                    .textFieldStyle(.plain).font(NDS.body)
                    .focused($subtaskFocused)
                    .onSubmit(addSubtask)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NotionEyebrow(text: "Notes")
                Spacer()
                // 4-3: pull the source meeting's summary into the task notes.
                if let item, !item.isManual {
                    Button { insertMeetingContext(item) } label: {
                        Label("Insert meeting notes", systemImage: "calendar.badge.plus")
                            .font(NDS.small)
                    }
                    .buttonStyle(.borderless).foregroundStyle(NDS.brand)
                }
            }
            RichMarkdownEditor(text: $noteDraft, placeholder: "Type / for blocks, or just start writing…")
                .frame(minHeight: 240, maxHeight: 520)
        }
    }

    /// Meeting provenance banner (4-5): a brand-accented card linking the task
    /// back to the call it came from.
    private func provenanceStrip(_ item: ActionItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").foregroundStyle(NDS.brand)
            Text("From \(item.meetingTitle)").font(NDS.small).foregroundStyle(NDS.textSecondary).lineLimit(1)
            Spacer()
            Button("View") { meetingPeekShown = true }
                .font(NDS.small).buttonStyle(.plain).foregroundStyle(NDS.brand)
        }
        .padding(10)
        .background(NDS.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(NDS.brand).frame(width: 3).padding(.vertical, 4)
        }
    }

    /// Opens the full source meeting in the Meetings tab (4-4 "Open full meeting").
    private func openSourceMeeting(_ item: ActionItem) {
        meetingPeekShown = false
        if let m = manager.meeting(id: item.meetingID) {
            router.openMeeting(m)
        } else {
            NotificationCenter.default.post(
                name: .meetingScribeOpenEntity, object: nil,
                userInfo: ["url": WorkspaceLink.url(kind: .meeting, id: item.meetingID).absoluteString])
        }
    }

    /// Appends the source meeting's summary excerpt to the task notes (4-3).
    private func insertMeetingContext(_ item: ActionItem) {
        guard let summary = manager.summaryText(forMeetingID: item.meetingID), !summary.isEmpty else {
            ToastCenter.shared.show("No summary found for that meeting yet")
            return
        }
        let block = "\n\n---\n**From:** \(item.meetingTitle)\n\n\(summary.prefix(2000))"
        noteDraft += block
        scheduleSave()
        ToastCenter.shared.show("Inserted meeting notes")
    }

    // MARK: Helpers

    private func addSubtask() {
        let t = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addSubtask(itemID, title: t)
        newSubtask = ""
        // Refocus so several subtasks can be added back-to-back (P0-1).
        Task { @MainActor in subtaskFocused = true }
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

    private func statusColor(_ s: ActionItem.Status) -> Color { NDS.status(s) }
    private func priorityColor(_ p: ActionItem.Priority) -> Color { NDS.priority(p) }
}
