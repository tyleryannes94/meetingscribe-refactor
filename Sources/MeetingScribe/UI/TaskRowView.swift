import SwiftUI
import AppKit

// MARK: - Row component

@available(macOS 14.0, *)
struct ActionItemRow: View {
    let item: ActionItem
    let projects: [Project]
    let projectName: String?
    let allLabels: [TaskLabel]
    let assignedLabels: [TaskLabel]
    let isPushing: Bool
    let isExpanded: Bool
    /// Color of the task's workspace context, for the left accent bar (1-5).
    var contextColor: Color? = nil
    /// Single-tap: toggles the inline detail editor (P0-2).
    let onToggleExpand: () -> Void
    /// Double-click / "Open as page": opens the full task page (P0-2).
    let onOpenPage: () -> Void
    let onStatus: (ActionItem.Status) -> Void
    let onPriority: (ActionItem.Priority) -> Void
    let onDue: (Date?) -> Void
    let onStart: (Date?) -> Void
    let onTitle: (String) -> Void
    let onOwner: (String?) -> Void
    let onNotes: (String?) -> Void
    let onProject: (String?) -> Void
    let onCreateProject: (String) -> Void
    let sections: [ProjectSection]
    let onSection: (String?) -> Void
    let onToggleLabel: (String) -> Void
    let onCreateLabel: (String) -> Void
    let onAddSubtask: (String) -> Void
    let onToggleSubtask: (String) -> Void
    let onDeleteSubtask: (String) -> Void
    let onDelete: () -> Void
    let onPush: () -> Void
    let onOpenNotion: (String) -> Void
    let onPushLinear: () -> Void
    let onOpenLinear: (String) -> Void

    @EnvironmentObject private var router: WorkspaceRouter
    @State private var hovering = false
    /// Drives the one-click completion celebration beat (D3-2).
    @State private var celebrate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var titleDraft: String = ""
    @State private var ownerDraft: String = ""
    @State private var notesDraft: String = ""
    @State private var datePickerShown = false
    @State private var startPickerShown = false
    @State private var newSubtask: String = ""
    @State private var newLabelName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if isExpanded {
                detailEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: NDS.rowRadius)
                .fill(hovering ? NDS.rowHover : Color.clear)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(NDS.divider).frame(height: 1)
                .padding(.horizontal, 4)
                .opacity(hovering ? 0 : 1)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        // Quick-move context menu — right-click or long-press to move task
        // to another project without navigating to the task detail.
        .contextMenu {
            Button { onStatus(item.status == .completed ? .open : .completed) } label: {
                Label(item.status == .completed ? "Mark open" : "Mark done",
                      systemImage: item.status == .completed ? "circle" : "checkmark.circle.fill")
            }
            Menu("Set priority") {
                ForEach(ActionItem.Priority.allCases) { p in
                    Button(p.label) { onPriority(p) }
                }
            }
            Menu("Labels") {
                if allLabels.isEmpty {
                    Text("No labels yet — add one below in the task")
                } else {
                    let assigned = Set(assignedLabels.map(\.id))
                    ForEach(allLabels) { l in
                        Button { onToggleLabel(l.id) } label: {
                            Label(l.name, systemImage: assigned.contains(l.id) ? "checkmark" : "tag")
                        }
                    }
                }
            }
            Divider()
            if !projects.isEmpty {
                Menu("Move to project") {
                    Button("No project") { onProject(nil) }
                    Divider()
                    ForEach(projects) { proj in
                        Button(proj.name) { onProject(proj.id) }
                    }
                }
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var mainRow: some View {
        HStack(spacing: 10) {
            // Workspace-context accent bar (1-5): a slim colored rail keying the
            // task to Work / Personal / … . Omitted when uncontextualized.
            if let contextColor {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(contextColor)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
            }
            statusButton
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout)
                    .strikethrough(item.status == .completed)
                    .foregroundStyle(item.status == .completed ? .secondary : .primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let owner = item.owner, !owner.isEmpty {
                        // P2-3: when the owner resolves to a Person, the chip
                        // navigates there (avatar + name); otherwise it's a plain label.
                        if let pid = item.ownerPersonID {
                            Button { router.openPerson(pid) } label: {
                                HStack(spacing: 4) {
                                    MSAvatar(name: owner, size: 14)
                                    Text(owner).font(.caption2)
                                }
                                .foregroundStyle(NDS.brand)
                            }
                            .buttonStyle(.plain)
                            .help("Open \(owner) in People")
                        } else {
                            Label(owner, systemImage: "person.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let projectName {
                        Label(projectName, systemImage: "folder.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .foregroundStyle(NDS.brand)
                            .lineLimit(1)
                    }
                    if !item.isManual {
                        Label(item.meetingTitle, systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if item.subtaskProgress.total > 0 {
                        Label("\(item.subtaskProgress.done)/\(item.subtaskProgress.total)",
                              systemImage: "checklist")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if item.externalURL != nil, let src = item.source {
                        Text(src.capitalized).font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(assignedLabels) { l in
                        labelChip(l)
                    }
                }
            }
            Spacer(minLength: 0)
            priorityDot
            dueChip
            syncButtons
            Menu {
                Button("Edit details") { onToggleExpand() }
                Button("Open as page") { onOpenPage() }
                Menu("Move to project") {
                    Button("No project") { onProject(nil) }
                    Divider()
                    ForEach(projects) { p in
                        Button(p.name) { onProject(p.id) }
                    }
                    Divider()
                    Button("New project named \"\(item.meetingTitle.isEmpty ? item.title : item.meetingTitle)\"") {
                        onCreateProject(item.meetingTitle.isEmpty ? item.title : item.meetingTitle)
                    }
                }
                if !sections.isEmpty {
                    Menu("Move to section") {
                        Button("No section") { onSection(nil) }
                        Divider()
                        ForEach(sections) { s in
                            Button(s.name) { onSection(s.id) }
                        }
                    }
                }
                Button(role: .destructive) { onDelete() } label: { Text("Delete") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
        // Double-click opens the full page; single-tap expands inline (P0-2).
        // The 2-count gesture must precede the 1-count so SwiftUI can disambiguate.
        .onTapGesture(count: 2) { onOpenPage() }
        .onTapGesture { onToggleExpand() }
    }

    private var statusButton: some View {
        // D3-2: one click completes (was a menu click). The full status set
        // moves to the right-click context menu so in-progress is still reachable.
        Button {
            let willComplete = item.status != .completed
            onStatus(willComplete ? .completed : .open)
            if willComplete && !reduceMotion {
                celebrate = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { celebrate = false }
            }
        } label: {
            ZStack {
                // A ring that pops outward once on completion — the Things-3 beat.
                if celebrate {
                    Circle()
                        .stroke(NDS.mint, lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .scaleEffect(celebrate ? 2.1 : 0.6)
                        .opacity(celebrate ? 0 : 0.9)
                        .animation(.easeOut(duration: 0.5), value: celebrate)
                }
                Image(systemName: item.status.systemImage)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .scaleEffect(celebrate ? 1.35 : 1.0)
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.5), value: celebrate)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 22)
        .help(item.status == .completed ? "Mark open" : "Mark done")
        .contextMenu {
            ForEach(ActionItem.Status.allCases) { s in
                Button { onStatus(s) } label: { Label(s.label, systemImage: s.systemImage) }
            }
        }
    }

    private var statusColor: Color { NDS.status(item.status) }

    /// Compact priority dot for the collapsed row (2-7): a 10×10 color disc with
    /// a tooltip + right-click menu, replacing the verbose always-on capsule.
    /// The full labeled picker stays in the expanded detail editor / task page.
    private var priorityDot: some View {
        Circle()
            .fill(priorityColor)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(priorityColor.opacity(0.35), lineWidth: 2).frame(width: 14, height: 14))
            .frame(width: 16, height: 16)
            .help("Priority: \(item.priority.label)")
            .contextMenu {
                ForEach(ActionItem.Priority.allCases) { p in
                    Button(p.label) { onPriority(p) }
                }
            }
    }

    private var priorityColor: Color { NDS.priority(item.priority) }
    private var priorityIcon: String {
        switch item.priority {
        case .low: return "arrow.down"
        case .medium: return "minus"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.2"
        }
    }

    private var dueChip: some View {
        Button {
            datePickerShown = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar").font(.caption2)
                Text(dueText).font(.caption2.monospacedDigit())
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(dueBackground, in: Capsule())
            .foregroundStyle(dueColor)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $datePickerShown) {
            // 2-5: type-ahead date entry ("fri", "+3d", …) with a calendar fallback.
            DateTypeAheadField(date: Binding(get: { item.dueDate }, set: { onDue($0) }),
                               onCommit: { datePickerShown = false })
        }
    }

    private var dueText: String {
        guard let due = item.dueDate else { return "Set due" }
        let cal = Calendar.current
        if cal.isDateInToday(due) { return "Today" }
        if cal.isDateInTomorrow(due) { return "Tomorrow" }
        if cal.isDateInYesterday(due) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: due)
    }

    private var dueColor: Color {
        guard let due = item.dueDate else { return .secondary }
        if item.status == .completed { return .secondary }
        if due < Calendar.current.startOfDay(for: Date()) { return .red }
        return .primary
    }

    private var dueBackground: Color {
        guard let due = item.dueDate else { return Color.secondary.opacity(0.08) }
        if item.status == .completed { return Color.secondary.opacity(0.08) }
        if due < Calendar.current.startOfDay(for: Date()) { return .red.opacity(0.14) }
        return Color.secondary.opacity(0.12)
    }

    private var linearURL: String? {
        item.source == "linear" ? item.externalURL : nil
    }

    /// Push-to-Linear and Push-to-Notion buttons, side by side. While a push
    /// is in flight (either target) we collapse to a single spinner.
    /// Show the Linear button only when this task is already linked to Linear,
    /// or the project is wired for Linear (app key + project's linearProjectID).
    /// Hides integration noise on the ~90% of tasks with no sync target (2-8).
    private var showsLinear: Bool {
        if linearURL != nil { return true }
        let project = projects.first { $0.id == item.projectID }
        return !((AppSettings.shared.linearAPIKey ?? "").isEmpty) && project?.linearProjectID != nil
    }
    /// Show the Notion button only when already linked, or Notion is configured
    /// app-wide (key + action-items database).
    private var showsNotion: Bool {
        if item.notionURL != nil { return true }
        let s = AppSettings.shared
        return !((s.notionAPIKey ?? "").isEmpty) && s.notionActionItemsDatabaseID != nil
    }

    @ViewBuilder
    private var syncButtons: some View {
        if isPushing {
            ProgressView().controlSize(.small).frame(width: 24)
        } else if showsLinear || showsNotion {
            if showsLinear { linearButton }
            if showsNotion { notionButton }
        } else {
            Color.clear.frame(width: 0)
        }
    }

    @ViewBuilder
    private var linearButton: some View {
        if let url = linearURL {
            Button {
                onOpenLinear(url)
            } label: {
                Image(systemName: "l.square.fill")
                    .foregroundStyle(NDS.brand)
            }
            .buttonStyle(.plain)
            .help("Open in Linear")
        } else {
            Button {
                onPushLinear()
            } label: {
                Image(systemName: "l.square")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Push to Linear")
        }
    }

    @ViewBuilder
    private var notionButton: some View {
        if let url = item.notionURL {
            Button {
                onOpenNotion(url)
            } label: {
                Image(systemName: "arrow.up.right.square.fill")
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
            .help("Open in Notion")
        } else {
            Button {
                onPush()
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Push to Notion")
        }
    }

    private func labelChip(_ l: TaskLabel) -> some View {
        let c = Color(hex: l.colorHex) ?? .gray
        return Text(l.name)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(c.opacity(0.18), in: Capsule())
            .foregroundStyle(c)
            .lineLimit(1)
    }

    @ViewBuilder
    private var detailEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.4)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("Title", text: $titleDraft, onCommit: {
                        if titleDraft != item.title { onTitle(titleDraft) }
                    })
                    .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assignee").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("e.g. Me, Alice", text: $ownerDraft, onCommit: {
                        onOwner(ownerDraft)
                    })
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                }
            }
            datesRow
            labelsRow
            subtasksSection
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                TextEditor(text: $notesDraft)
                    .font(.caption)
                    .frame(minHeight: 60, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))
                    .onChange(of: notesDraft) { _, new in
                        onNotes(new)
                    }
            }
            HStack(spacing: 8) {
                if let url = linearURL {
                    Text("Linked to Linear")
                        .font(.caption2).foregroundStyle(NDS.brand)
                    Button("Open") { onOpenLinear(url) }
                        .controlSize(.small)
                } else {
                    Button {
                        onPushLinear()
                    } label: {
                        Label("Push to Linear", systemImage: "l.square")
                    }
                    .controlSize(.small)
                }
                if let url = item.notionURL {
                    Text("Linked to Notion")
                        .font(.caption2).foregroundStyle(.purple)
                    Button("Re-sync") { onPush() }
                        .controlSize(.small)
                    Button("Open") { onOpenNotion(url) }
                        .controlSize(.small)
                } else {
                    Button {
                        onPush()
                    } label: {
                        Label("Push to Notion", systemImage: "arrow.up.right.square")
                    }
                    .controlSize(.small)
                }
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .onAppear {
            titleDraft = item.title
            ownerDraft = item.owner ?? ""
            notesDraft = item.notes ?? ""
        }
    }

    // MARK: - Detail editor sub-sections

    private var datesRow: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Button {
                    startPickerShown = true
                } label: {
                    Label(dateLabel(item.startDate, placeholder: "Set start"), systemImage: "calendar.badge.clock")
                        .font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .popover(isPresented: $startPickerShown) {
                    datePopover(current: item.startDate, onSet: onStart, onClose: { startPickerShown = false })
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Due").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Button {
                    datePickerShown = true
                } label: {
                    Label(dateLabel(item.dueDate, placeholder: "Set due"), systemImage: "calendar")
                        .font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .popover(isPresented: $datePickerShown) {
                    datePopover(current: item.dueDate, onSet: onDue, onClose: { datePickerShown = false })
                }
            }
            Spacer()
        }
    }

    private func dateLabel(_ d: Date?, placeholder: String) -> String {
        guard let d else { return placeholder }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }

    private func datePopover(current: Date?, onSet: @escaping (Date?) -> Void, onClose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("", selection: Binding(get: { current ?? Date() }, set: { onSet($0) }),
                       displayedComponents: [.date])
                .datePickerStyle(.graphical).labelsHidden()
            HStack {
                Button("Clear", role: .destructive) { onSet(nil); onClose() }
                Spacer()
                Button("Done") { onClose() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(14).frame(width: 280)
    }

    private var labelsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Labels").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(assignedLabels) { l in labelChip(l) }
                Menu {
                    ForEach(allLabels) { l in
                        Button {
                            onToggleLabel(l.id)
                        } label: {
                            Label(l.name, systemImage: item.labels.contains(l.id) ? "checkmark" : "tag")
                        }
                    }
                    Divider()
                    Button("New label “\(newLabelName.isEmpty ? "…" : newLabelName)”") {
                        let n = newLabelName.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { onCreateLabel(n); newLabelName = "" }
                    }
                    .disabled(newLabelName.trimmingCharacters(in: .whitespaces).isEmpty)
                } label: {
                    Image(systemName: "tag.circle").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                TextField("New label name", text: $newLabelName, onCommit: {
                    let n = newLabelName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { onCreateLabel(n); newLabelName = "" }
                })
                .textFieldStyle(.roundedBorder).frame(width: 140).controlSize(.small)
            }
        }
    }

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Subtasks").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                if item.subtaskProgress.total > 0 {
                    Text("\(item.subtaskProgress.done)/\(item.subtaskProgress.total)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            ForEach(item.subtaskList) { sub in
                HStack(spacing: 8) {
                    Button {
                        onToggleSubtask(sub.id)
                    } label: {
                        Image(systemName: sub.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(sub.done ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    Text(sub.title).font(.caption)
                        .strikethrough(sub.done)
                        .foregroundStyle(sub.done ? .secondary : .primary)
                    Spacer()
                    Button {
                        onDeleteSubtask(sub.id)
                    } label: {
                        Image(systemName: "xmark.circle").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "plus.circle").foregroundStyle(.secondary).font(.caption)
                TextField("Add subtask…", text: $newSubtask, onCommit: addSubtask)
                    .textFieldStyle(.plain).font(.caption)
                    .onSubmit(addSubtask)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func addSubtask() {
        let t = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        onAddSubtask(t)
        newSubtask = ""
    }
}
