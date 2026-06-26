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
    @State private var titleSaveTimer: Timer?
    @State private var lastSavedTitle = ""
    @State private var dueShown = false
    @State private var startShown = false
    /// Inline source-meeting peek popover (4-4).
    @State private var meetingPeekShown = false
    /// v3 inline-edit model: which property's click-to-open popover picker is
    /// showing. Only one is open at a time.
    @State private var openPicker: PropertyPicker?
    @State private var assigneeQuery = ""
    @ObservedObject private var changeLog = TaskChangeLog.shared

    /// The five v3 property pickers that open as popovers (TaskDetail.dc.html).
    enum PropertyPicker: Hashable { case status, priority, due, project, assignee }

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
                    DecisionLogSection(anchor: .task(item.id), compact: true)
                        .padding(.top, 18)
                    bodyEditor
                        .padding(.top, 18)
                    activitySection(item)
                        .padding(.top, 18)
                }
                .notionPageColumn()
            }
            .background(NDS.bg)
            .onAppear { load(item) }
            .onChange(of: itemID) { _, _ in
                flush(); flushTitle()
                if let i = store.items.first(where: { $0.id == itemID }) { load(i) }
            }
            .onChange(of: noteDraft) { _, _ in scheduleSave() }
            .onDisappear { flush(); flushTitle() }
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
                .scaledFont(22, weight: .bold, kind: .display)
                .onChange(of: titleDraft) { _, _ in scheduleTitleSave() }
        }
    }

    // MARK: Properties

    @ViewBuilder
    private func properties(_ item: ActionItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            NotionPropertyRow(icon: "circle.dotted", label: "Status") {
                pickerButton(.status) {
                    NotionChip(item.status.label, color: statusColor(item.status), systemImage: item.status.systemImage)
                }
                .popover(isPresented: pickerBinding(.status), arrowEdge: .bottom) {
                    pickerPopover(ActionItem.Status.allCases.map { s in
                        PickerOption(id: s.rawValue, label: s.label, systemImage: s.systemImage,
                                     color: NDS.status(s), selected: s == item.status) {
                            store.setStatus(itemID, status: s)
                        }
                    })
                }
            }
            NotionPropertyRow(icon: "flag", label: "Priority") {
                pickerButton(.priority) {
                    NotionChip(item.priority.label, color: priorityColor(item.priority),
                               systemImage: NDS.priorityGlyph(item.priority))
                }
                .popover(isPresented: pickerBinding(.priority), arrowEdge: .bottom) {
                    pickerPopover(ActionItem.Priority.allCases.map { p in
                        PickerOption(id: p.rawValue, label: p.label, systemImage: NDS.priorityGlyph(p),
                                     color: NDS.priority(p), selected: p == item.priority) {
                            store.setPriority(itemID, priority: p)
                        }
                    })
                }
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
                    pickerButton(.assignee) {
                        if let pid = item.ownerPersonID, let p = people.person(by: pid) {
                            HStack(spacing: 6) {
                                MSAvatar(name: p.displayName, size: 18)
                                Text(p.displayName).font(NDS.body).foregroundStyle(NDS.textPrimary).lineLimit(1)
                            }
                        } else if let owner = item.owner, !owner.isEmpty {
                            Text(owner).font(NDS.body).foregroundStyle(NDS.textPrimary).lineLimit(1)
                        } else {
                            Text("Empty").font(NDS.body).foregroundStyle(NDS.textTertiary)
                        }
                    }
                    .popover(isPresented: pickerBinding(.assignee), arrowEdge: .bottom) {
                        assigneePopover(item)
                    }
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
                pickerButton(.due) {
                    if let d = item.dueDate {
                        Text(d.formatted(date: .abbreviated, time: .omitted))
                            .font(NDS.body).foregroundStyle(NDS.due(d, status: item.status))
                    } else {
                        Text("Empty").font(NDS.body).foregroundStyle(NDS.textTertiary)
                    }
                }
                .popover(isPresented: pickerBinding(.due), arrowEdge: .bottom) {
                    duePopover(item)
                }
            }
            NotionPropertyRow(icon: "folder", label: "Project") {
                pickerButton(.project) {
                    if let p = store.project(for: item) {
                        NotionChip(p.name, color: NDS.selectColor(p.name), systemImage: "folder.fill")
                    } else {
                        Text("Empty").font(NDS.body).foregroundStyle(NDS.textTertiary)
                    }
                }
                .popover(isPresented: pickerBinding(.project), arrowEdge: .bottom) {
                    pickerPopover(
                        [PickerOption(id: "__none__", label: "No project", systemImage: "folder",
                                      color: NDS.textTertiary, selected: item.projectID == nil) {
                            store.setProject(itemID, projectID: nil)
                        }]
                        + store.projects.map { p in
                            PickerOption(id: p.id, label: p.name, systemImage: "folder.fill",
                                         color: NDS.selectColor(p.name), selected: item.projectID == p.id) {
                                store.setProject(itemID, projectID: p.id)
                            }
                        })
                }
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

    // MARK: v3 popover property pickers

    /// One selectable row inside a property popover.
    private struct PickerOption: Identifiable {
        let id: String
        let label: String
        let systemImage: String?
        let color: Color?
        let selected: Bool
        let action: () -> Void
    }

    /// Binds a property's open/closed state to the single `openPicker` slot so
    /// only one popover shows at a time.
    private func pickerBinding(_ p: PropertyPicker) -> Binding<Bool> {
        Binding(get: { openPicker == p }, set: { openPicker = $0 ? p : nil })
    }

    /// The clickable property value that opens a picker popover.
    private func pickerButton<L: View>(_ p: PropertyPicker, @ViewBuilder label: () -> L) -> some View {
        Button { openPicker = p } label: { label() }
            .buttonStyle(.plain)
    }

    /// A generic single-select popover: icon/dot + label + checkmark on current.
    private func pickerPopover(_ options: [PickerOption]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(options) { opt in
                Button {
                    opt.action()
                    openPicker = nil
                } label: {
                    HStack(spacing: 9) {
                        if let img = opt.systemImage {
                            Image(systemName: img).scaledFont(12)
                                .foregroundStyle(opt.color ?? NDS.textSecondary).frame(width: 16)
                        } else if let c = opt.color {
                            Circle().fill(c).frame(width: 9, height: 9).frame(width: 16)
                        }
                        Text(opt.label).scaledFont(13).foregroundStyle(NDS.textPrimary)
                        Spacer(minLength: 14)
                        if opt.selected {
                            Image(systemName: "checkmark").scaledFont(11, weight: .bold)
                                .foregroundStyle(NDS.accent)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .ndsHover(cornerRadius: 9)
            }
        }
        .padding(6)
        .frame(minWidth: 216)
    }

    /// Due-date popover: quick relative options plus a graphical calendar.
    private func duePopover(_ item: ActionItem) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today) ?? today }
        // Upcoming Friday (end of work week); if today is Fri/Sat/Sun, next Friday.
        let weekdayToday = cal.component(.weekday, from: today) // 1=Sun … 6=Fri
        let daysToFri = ((6 - weekdayToday) + 7) % 7
        let friday = day(daysToFri == 0 ? 7 : daysToFri)
        let quick: [PickerOption] = [
            PickerOption(id: "today", label: "Today", systemImage: "clock", color: NDS.gold,
                         selected: item.dueDate.map { cal.isDate($0, inSameDayAs: today) } ?? false) {
                store.setDueDate(itemID, dueDate: today)
            },
            PickerOption(id: "tomorrow", label: "Tomorrow", systemImage: "clock", color: NDS.textSecondary,
                         selected: item.dueDate.map { cal.isDate($0, inSameDayAs: day(1)) } ?? false) {
                store.setDueDate(itemID, dueDate: day(1))
            },
            PickerOption(id: "friday", label: "This week (Fri)", systemImage: "clock", color: NDS.textSecondary,
                         selected: item.dueDate.map { cal.isDate($0, inSameDayAs: friday) } ?? false) {
                store.setDueDate(itemID, dueDate: friday)
            },
            PickerOption(id: "nextweek", label: "Next week", systemImage: "clock", color: NDS.textSecondary,
                         selected: item.dueDate.map { cal.isDate($0, inSameDayAs: day(7)) } ?? false) {
                store.setDueDate(itemID, dueDate: day(7))
            },
            PickerOption(id: "none", label: "No date", systemImage: "minus.circle", color: NDS.textTertiary,
                         selected: item.dueDate == nil) {
                store.setDueDate(itemID, dueDate: nil)
            }
        ]
        return VStack(alignment: .leading, spacing: 6) {
            pickerPopover(quick)
            Divider().overlay(NDS.divider)
            DateTypeAheadField(date: Binding(get: { item.dueDate },
                                             set: { store.setDueDate(itemID, dueDate: $0) }),
                               onCommit: { openPicker = nil })
                .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .frame(minWidth: 240)
    }

    /// Assignee popover: search + roster, each linking to a Person record.
    private func assigneePopover(_ item: ActionItem) -> some View {
        let q = assigneeQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = q.isEmpty ? personPickerList
            : people.people.filter { $0.displayName.lowercased().contains(q) }.prefix(50).map { $0 }
        return VStack(alignment: .leading, spacing: 6) {
            MSSearchField(placeholder: "Search people…", text: $assigneeQuery, autoFocus: true)
                .padding(.horizontal, 8).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    Button {
                        store.setOwnerPerson(itemID, personID: nil, ownerName: nil)
                        openPicker = nil
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "person.crop.circle.badge.xmark").scaledFont(12)
                                .foregroundStyle(NDS.textTertiary).frame(width: 16)
                            Text("Unassign").scaledFont(13).foregroundStyle(NDS.textPrimary)
                            Spacer(minLength: 14)
                            if item.ownerPersonID == nil && (item.owner ?? "").isEmpty {
                                Image(systemName: "checkmark").scaledFont(11, weight: .bold).foregroundStyle(NDS.accent)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).ndsHover(cornerRadius: 9)
                    ForEach(matches) { p in
                        Button {
                            store.setOwnerPerson(itemID, personID: p.id, ownerName: p.displayName)
                            assigneeQuery = ""
                            openPicker = nil
                        } label: {
                            HStack(spacing: 9) {
                                MSAvatar(name: p.displayName, size: 18)
                                Text(p.displayName).scaledFont(13).foregroundStyle(NDS.textPrimary).lineLimit(1)
                                Spacer(minLength: 14)
                                if item.ownerPersonID == p.id {
                                    Image(systemName: "checkmark").scaledFont(11, weight: .bold).foregroundStyle(NDS.accent)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).ndsHover(cornerRadius: 9)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 260)
    }

    // MARK: Activity

    /// Read-only timeline of this task's recorded mutations (TaskChangeLog).
    @ViewBuilder
    private func activitySection(_ item: ActionItem) -> some View {
        let events = changeLog.recent
            .filter { $0.entity == .task && $0.entityID == itemID && !$0.undone }
            .suffix(40).reversed().map { $0 }
        if !events.isEmpty {
            MSSection("Activity", systemImage: "clock.arrow.circlepath",
                      persistenceKey: "taskPage.activity", defaultExpanded: false) {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(events) { ev in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: activityGlyph(ev.op)).scaledFont(11)
                                .foregroundStyle(NDS.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(NDS.surface2, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ev.summary).scaledFont(12).foregroundStyle(NDS.textPrimary)
                                Text(ev.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .scaledFont(11).foregroundStyle(NDS.textTertiary)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func activityGlyph(_ op: TaskChangeEvent.Op) -> String {
        switch op {
        case .create: return "sparkles"
        case .update: return "pencil"
        case .delete: return "trash"
        case .restore: return "arrow.uturn.backward"
        case .merge: return "arrow.triangle.merge"
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
        MSSection("Subtasks", systemImage: "checklist",
                  count: item.subtaskProgress.total > 0 ? item.subtaskProgress.total : nil,
                  persistenceKey: "taskPage.subtasks",
                  trailing: {
                      if item.subtaskProgress.total > 0 {
                          Text("\(item.subtaskProgress.done) done")
                              .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                      }
                  }) {
            VStack(alignment: .leading, spacing: 8) {
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
    }

    private var bodyEditor: some View {
        MSSection("Notes", systemImage: "note.text",
                  persistenceKey: "taskPage.notes",
                  trailing: {
                      // 4-3: pull the source meeting's summary into the task notes.
                      if let item, !item.isManual {
                          Button { insertMeetingContext(item) } label: {
                              Label("Insert meeting notes", systemImage: "calendar.badge.plus")
                                  .font(NDS.small)
                          }
                          .buttonStyle(.borderless).foregroundStyle(NDS.brand)
                      }
                  }) {
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
        lastSavedTitle = item.title
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
    /// Debounce the title the same way as notes — committing per keystroke ran a
    /// full-collection encode + SQLite FTS reindex + changelog append on the main
    /// actor on every character (the typing-lag freeze).
    private func scheduleTitleSave() {
        titleSaveTimer?.invalidate()
        titleSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in flushTitle() }
        }
    }
    private func flushTitle() {
        titleSaveTimer?.invalidate(); titleSaveTimer = nil
        guard titleDraft != lastSavedTitle else { return }
        store.setTitle(itemID, title: titleDraft)
        lastSavedTitle = titleDraft
    }

    private func statusColor(_ s: ActionItem.Status) -> Color { NDS.status(s) }
    private func priorityColor(_ p: ActionItem.Priority) -> Color { NDS.priority(p) }
}
