import SwiftUI
import AppKit

// MARK: - Project rail (left sidebar)

@available(macOS 14.0, *)
struct ProjectRail: View {
    @ObservedObject var store: ActionItemStore
    /// People facet (P2-2 / P2-6): observed so owner buckets recount live as
    /// records change. Defaulted so the call site needs no new plumbing.
    @ObservedObject private var peopleStore = PeopleStore.shared
    let meetings: [Meeting]
    @Binding var selectedProjectID: String?
    @Binding var selectedMeetingID: String?
    @Binding var selectedInitiativeID: String?
    /// Collapsible state for the People facet section.
    @State private var peopleExpanded = true
    /// Collapsible state for the Waiting-on (delegated) section.
    @State private var waitingExpanded = true
    @State private var newName: String = ""
    @State private var creating = false
    @State private var creatingInitiative = false
    @State private var newInitiativeName = ""
    @State private var expandedPages: Set<String> = []
    @State private var expandedInitiatives: Set<String> = []
    /// Meeting notes are collapsed by default so the rail leads with the user's
    /// initiatives / projects / tasks rather than a long dump of every meeting.
    @State private var meetingNotesExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("📁").scaledFont(15)
                Text("Projects")   // D1-4: was "Workspace" (collided with the nav group)
                    .scaledFont(14, weight: .bold)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 8)

            // Prominent, obvious primary action.
            Button { creating = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.pencil").scaledFont(12, weight: .semibold)
                    Text("New page").scaledFont(13, weight: .semibold)
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(NDS.brand, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    railItem(title: "Home", icon: "house.fill", count: 0,
                             id: ActionItemsView.homeSentinel)
                    // Triage inbox — meeting-extracted items awaiting review (§5B).
                    railItem(title: "Triage inbox", icon: "tray.and.arrow.down.fill",
                             count: store.pendingTriage.count,
                             id: ActionItemsView.triageSentinel)
                    railItem(title: "All tasks", icon: "tray.full",
                             count: store.items.filter { $0.status != .completed }.count,
                             id: nil)
                    railItem(title: "Unsorted tasks", icon: "tray",
                             count: store.items.filter { $0.projectID == nil && $0.status != .completed }.count,
                             id: ActionItemsView.noProjectSentinel)

                    // People facet (P2-2) + Waiting-on lifecycle (P2-6).
                    peopleSection
                    waitingSection

                    // Initiatives (top tier) — each expands to its projects.
                    HStack {
                        sectionLabel("Initiatives")
                        Spacer()
                        NotionIconButton(systemName: "plus", help: "New initiative") { creatingInitiative = true }
                            .padding(.trailing, 6)
                    }
                    if store.initiatives.isEmpty && !creatingInitiative {
                        Text("Group projects into initiatives").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            .padding(.horizontal, 12).padding(.vertical, 2)
                    }
                    ForEach(store.sortedInitiatives()) { ini in
                        InitiativeNode(store: store, initiative: ini,
                                       selectedProjectID: $selectedProjectID,
                                       selectedMeetingID: $selectedMeetingID,
                                       selectedInitiativeID: $selectedInitiativeID,
                                       expandedInitiatives: $expandedInitiatives,
                                       expandedPages: $expandedPages)
                    }
                    if creatingInitiative {
                        TextField("Initiative name", text: $newInitiativeName, onCommit: commitInitiative)
                            .textFieldStyle(.roundedBorder).font(NDS.body)
                            .padding(.horizontal, 8).padding(.top, 6)
                    }

                    HStack {
                        sectionLabel("Pages")
                        Spacer()
                        NotionIconButton(systemName: "plus", help: "New top-level page") { creating = true }
                            .padding(.trailing, 6)
                    }
                    if store.standaloneTopProjects().isEmpty && !creating {
                        Text("No pages yet").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            .padding(.horizontal, 12).padding(.vertical, 2)
                    }
                    ForEach(store.standaloneTopProjects()) { p in
                        PageTreeNode(store: store, project: p, depth: 0,
                                     selectedProjectID: $selectedProjectID,
                                     selectedMeetingID: $selectedMeetingID,
                                     selectedInitiativeID: $selectedInitiativeID,
                                     expanded: $expandedPages)
                    }
                    if creating {
                        TextField("Page name", text: $newName, onCommit: commitNew)
                            .textFieldStyle(.roundedBorder).font(NDS.body)
                            .padding(.horizontal, 8).padding(.top, 6)
                    }

                    // Collapsible "Meeting notes" — collapsed by default so the
                    // rail isn't dominated by every past meeting. Expand to browse.
                    meetingNotesHeader
                    if meetingNotesExpanded {
                        if meetings.isEmpty {
                            Text("No meetings yet").font(.caption2).foregroundStyle(.tertiary)
                                .padding(.horizontal, 10).padding(.vertical, 2)
                        }
                        ForEach(meetings.prefix(25)) { m in
                            meetingItem(m)
                        }
                        if meetings.count > 25 {
                            Text("+\(meetings.count - 25) more — open from the Meetings tab")
                                .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                        }
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 12)
            }
        }
        .background(NDS.sidebarBg)
    }

    private func sectionLabel(_ s: String) -> some View {
        NotionEyebrow(text: s)
            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Tappable header for the collapsible Meeting notes section.
    private var meetingNotesHeader: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { meetingNotesExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .scaledFont(8, weight: .bold)
                    .rotationEffect(.degrees(meetingNotesExpanded ? 90 : 0))
                    .foregroundStyle(NDS.textTertiary)
                NotionEyebrow(text: "Meeting notes")
                Spacer(minLength: 4)
                if !meetings.isEmpty {
                    Text("\(meetings.count)").font(NDS.tiny.monospacedDigit())
                        .foregroundStyle(NDS.textTertiary)
                }
            }
            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commitNew() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        creating = false
        newName = ""
        guard !n.isEmpty else { return }
        let p = store.createProject(name: n)
        selectedMeetingID = nil
        selectedInitiativeID = nil
        selectedProjectID = p.id
    }

    private func commitInitiative() {
        let n = newInitiativeName.trimmingCharacters(in: .whitespaces)
        creatingInitiative = false
        newInitiativeName = ""
        guard !n.isEmpty else { return }
        let i = store.createInitiative(name: n)
        selectedProjectID = nil
        selectedMeetingID = nil
        selectedInitiativeID = i.id
    }

    private func meetingItem(_ m: Meeting) -> some View {
        let selected = selectedMeetingID == m.id
        let openTasks = store.items(for: m.id).filter { $0.status != .completed }.count
        return SidebarRow(selected: selected) {
            selectedProjectID = nil
            selectedInitiativeID = nil
            selectedMeetingID = m.id
        } content: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .scaledFont(13)
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(m.displayTitle).lineLimit(1).font(NDS.body)
                    Text(Self.shortDate(m.startDate)).font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
                Spacer()
                if openTasks > 0 {
                    Text("\(openTasks)").font(NDS.tiny.monospacedDigit())
                        .foregroundStyle(NDS.textTertiary)
                }
            }
        }
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        return f.string(from: d)
    }

    private func railItem(title: String, icon: String, count: Int, id: String?) -> some View {
        let selected = selectedMeetingID == nil && selectedInitiativeID == nil && selectedProjectID == id
        return SidebarRow(selected: selected) {
            selectedMeetingID = nil
            selectedInitiativeID = nil
            selectedProjectID = id
        } content: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .scaledFont(13)
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                    .frame(width: 16)
                Text(title).lineLimit(1).font(NDS.body)
                Spacer()
                if count > 0 {
                    Text("\(count)").font(NDS.tiny.monospacedDigit())
                        .foregroundStyle(NDS.textTertiary)
                }
            }
        }
        .contextMenu {
            if let id, id != ActionItemsView.noProjectSentinel {
                Button(role: .destructive) {
                    if selectedProjectID == id { selectedProjectID = nil }
                    let name = store.project(id: id)?.name ?? "project"
                    if let undo = store.deleteProjectWithUndo(id) {
                        ToastCenter.shared.show("Deleted “\(name)”", undoTitle: "Undo", undo: undo)
                    }
                } label: { Label("Delete project", systemImage: "trash") }
            }
        }
    }

    // MARK: - People facet (P2-2)

    /// People who own at least one open task, with their open-task count,
    /// highest first. Only resolved (`ownerPersonID`-linked) owners appear.
    private var ownerBuckets: [(person: Person, open: Int)] {
        var counts: [String: Int] = [:]
        for item in store.items where item.status != .completed {
            guard let pid = item.ownerPersonID, !pid.isEmpty else { continue }
            counts[pid, default: 0] += 1
        }
        return counts.compactMap { pid, c -> (person: Person, open: Int)? in
            guard let p = peopleStore.person(by: pid) else { return nil }
            return (p, c)
        }
        .sorted { $0.open > $1.open }
    }

    @ViewBuilder
    private var peopleSection: some View {
        let buckets = ownerBuckets
        if !buckets.isEmpty {
            disclosureHeader(title: "People", count: buckets.count, expanded: $peopleExpanded)
            if peopleExpanded {
                ForEach(buckets.prefix(8), id: \.person.id) { bucket in
                    personRow(bucket.person, open: bucket.open)
                }
                if buckets.count > 8 {
                    Text("+\(buckets.count - 8) more")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                        .padding(.horizontal, 12).padding(.vertical, 2)
                }
            }
        }
    }

    private func personRow(_ person: Person, open: Int) -> some View {
        let sentinel = ActionItemsView.personSentinel(person.id)
        let selected = selectedMeetingID == nil && selectedInitiativeID == nil && selectedProjectID == sentinel
        return SidebarRow(selected: selected) {
            selectedMeetingID = nil
            selectedInitiativeID = nil
            selectedProjectID = sentinel
        } content: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .scaledFont(14)
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                    .frame(width: 16)
                Text(person.displayName).lineLimit(1).font(NDS.body)
                Spacer()
                if open > 0 {
                    Text("\(open)").font(NDS.tiny.monospacedDigit())
                        .foregroundStyle(NDS.textTertiary)
                }
            }
        }
    }

    // MARK: - Waiting-on lifecycle (P2-6)

    /// Open tasks you've delegated (you're waiting on someone), oldest first so
    /// the most-aged commitments rise to the top.
    private var waitingTasks: [ActionItem] {
        store.items
            .filter { $0.delegated == true && $0.status != .completed }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @ViewBuilder
    private var waitingSection: some View {
        let tasks = waitingTasks
        if !tasks.isEmpty {
            // Header doubles as a scope: tapping the label filters the main list
            // to delegated tasks; the chevron toggles the inline list.
            waitingHeader(count: tasks.count)
            if waitingExpanded {
                ForEach(tasks.prefix(12)) { waitingRow($0) }
            }
        }
    }

    private func waitingHeader(count: Int) -> some View {
        let selected = selectedProjectID == ActionItemsView.waitingSentinel
            && selectedMeetingID == nil && selectedInitiativeID == nil
        return HStack(spacing: 3) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { waitingExpanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .scaledFont(8, weight: .bold)
                    .rotationEffect(.degrees(waitingExpanded ? 90 : 0))
                    .foregroundStyle(NDS.textTertiary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            Image(systemName: "hourglass")
                .scaledFont(11)
                .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                .frame(width: 15)
            Text("Waiting on").font(NDS.body)
                .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
            Spacer(minLength: 4)
            Text("\(count)").font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? NDS.rowSelected : .clear,
                    in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedMeetingID = nil
            selectedInitiativeID = nil
            selectedProjectID = ActionItemsView.waitingSentinel
        }
        .padding(.top, 6)
    }

    private func waitingRow(_ item: ActionItem) -> some View {
        WaitingRow(item: item) { nudge(item) }
    }

    /// Copies a person-addressed follow-up line to the clipboard so the user can
    /// drop it into mail/Slack with one click (P2-6 nudge affordance).
    private func nudge(_ item: ActionItem) {
        let name = (item.owner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = name.isEmpty ? "Hi," : "Hi \(name),"
        let line = "\(greeting) following up on “\(item.title)” — any update on this?"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(line, forType: .string)
        ToastCenter.shared.show("Nudge copied to clipboard")
    }

    /// Shared collapsible section header (chevron + title + count).
    private func disclosureHeader(title: String, count: Int, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .scaledFont(8, weight: .bold)
                    .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                    .foregroundStyle(NDS.textTertiary)
                NotionEyebrow(text: title)
                Spacer(minLength: 4)
                Text("\(count)").font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary)
            }
            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One row in the "Waiting on" sidebar bucket: owner + age badge + a hover-only
/// Nudge button that copies a follow-up line (P2-6).
@available(macOS 14.0, *)
private struct WaitingRow: View {
    let item: ActionItem
    let onNudge: () -> Void
    @State private var hovering = false

    private var ageDays: Int {
        Calendar.current.dateComponents([.day], from: item.createdAt, to: Date()).day ?? 0
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass.tophalf.filled")
                .scaledFont(11).foregroundStyle(NDS.textTertiary).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).lineLimit(1).font(NDS.body)
                let owner = (item.owner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                Text(owner.isEmpty ? "Unassigned" : owner)
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
            Spacer(minLength: 4)
            if hovering {
                Button(action: onNudge) {
                    Image(systemName: "bell.badge")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(NDS.brand)
                }
                .buttonStyle(.plain).help("Copy a follow-up nudge")
            } else if ageDays > 0 {
                Text("\(ageDays)d").font(NDS.tiny.monospacedDigit())
                    .foregroundStyle(ageDays >= 7 ? NDS.selectColor("orange") : NDS.textTertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? NDS.rowHover : .clear,
                    in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// A Notion-style sidebar row: hover + selected highlight, tight padding.
@available(macOS 14.0, *)
struct SidebarRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? NDS.rowSelected : (hovering ? NDS.rowHover : .clear),
                            in: RoundedRectangle(cornerRadius: NDS.rowRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// One node in the sidebar page tree. Renders its row (disclosure + icon +
/// name + open-task count) and, when expanded, recursively renders child
/// pages indented beneath it.
@available(macOS 14.0, *)
struct PageTreeNode: View {
    @ObservedObject var store: ActionItemStore
    let project: Project
    let depth: Int
    @Binding var selectedProjectID: String?
    @Binding var selectedMeetingID: String?
    @Binding var selectedInitiativeID: String?
    @Binding var expanded: Set<String>
    @State private var hovering = false
    @State private var addingChild = false
    @State private var childName = ""

    private var isSelected: Bool { selectedMeetingID == nil && selectedInitiativeID == nil && selectedProjectID == project.id }
    private var children: [Project] { store.childProjects(of: project.id) }
    private var isOpen: Bool { expanded.contains(project.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row
            if isOpen {
                ForEach(children) { c in
                    PageTreeNode(store: store, project: c, depth: depth + 1,
                                 selectedProjectID: $selectedProjectID,
                                 selectedMeetingID: $selectedMeetingID,
                                 selectedInitiativeID: $selectedInitiativeID,
                                 expanded: $expanded)
                }
                if addingChild {
                    TextField("Sub-page name", text: $childName, onCommit: commitChild)
                        .textFieldStyle(.roundedBorder).font(NDS.small)
                        .padding(.leading, CGFloat(depth + 1) * 13 + 24).padding(.trailing, 8).padding(.vertical, 2)
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 3) {
            // Disclosure triangle (sibling button — not nested in the row tap).
            Button {
                if isOpen { expanded.remove(project.id) } else { expanded.insert(project.id) }
            } label: {
                Image(systemName: "chevron.right")
                    .scaledFont(9, weight: .bold)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .foregroundStyle(NDS.textTertiary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .opacity(children.isEmpty ? 0 : 1)
            .disabled(children.isEmpty)

            Image(systemName: project.icon ?? "doc.text")
                .scaledFont(12)
                .foregroundStyle(isSelected ? NDS.textPrimary : NDS.textSecondary)
                .frame(width: 15)
            Text(project.name).font(NDS.body).lineLimit(1)
                .foregroundStyle(isSelected ? NDS.textPrimary : NDS.textSecondary)
            Spacer(minLength: 4)
            if hovering {
                Button { addingChild = true; expanded.insert(project.id) } label: {
                    Image(systemName: "plus").scaledFont(10, weight: .bold).foregroundStyle(NDS.textTertiary)
                }
                .buttonStyle(.plain).help("Add sub-page")
            } else {
                let open = store.openCount(forProject: project.id)
                if open > 0 {
                    Text("\(open)").font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary)
                }
            }
        }
        .padding(.leading, CGFloat(depth) * 13 + 8)
        .padding(.trailing, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? NDS.rowSelected : (hovering ? NDS.rowHover : .clear),
                    in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .contentShape(Rectangle())
        .onTapGesture { selectedMeetingID = nil; selectedInitiativeID = nil; selectedProjectID = project.id }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Add sub-page") { addingChild = true; expanded.insert(project.id) }
            Button(role: .destructive) {
                if selectedProjectID == project.id { selectedProjectID = nil }
                let name = project.name
                if let undo = store.deleteProjectKeepingChildrenWithUndo(project.id) {
                    ToastCenter.shared.show("Deleted “\(name)”", undoTitle: "Undo", undo: undo)
                }
            } label: { Label("Delete page", systemImage: "trash") }
        }
    }

    private func commitChild() {
        let n = childName.trimmingCharacters(in: .whitespaces)
        addingChild = false; childName = ""
        guard !n.isEmpty else { return }
        let p = store.createProject(name: n, parentID: project.id)
        selectedMeetingID = nil
        selectedInitiativeID = nil
        selectedProjectID = p.id
    }
}

// MARK: - Initiative node (sidebar; expands to its projects)

@available(macOS 14.0, *)
struct InitiativeNode: View {
    @ObservedObject var store: ActionItemStore
    let initiative: Initiative
    @Binding var selectedProjectID: String?
    @Binding var selectedMeetingID: String?
    @Binding var selectedInitiativeID: String?
    @Binding var expandedInitiatives: Set<String>
    @Binding var expandedPages: Set<String>
    @State private var hovering = false

    private var isOpen: Bool { expandedInitiatives.contains(initiative.id) }
    private var isSelected: Bool { selectedInitiativeID == initiative.id }
    private var projects: [Project] { store.projects(forInitiative: initiative.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Button {
                    if isOpen { expandedInitiatives.remove(initiative.id) } else { expandedInitiatives.insert(initiative.id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .scaledFont(9, weight: .bold)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(NDS.textTertiary).frame(width: 14, height: 14)
                }
                .buttonStyle(.plain).opacity(projects.isEmpty ? 0.3 : 1)

                Image(systemName: initiative.icon ?? "flag.fill")
                    .scaledFont(12).foregroundStyle(NDS.brand).frame(width: 15)
                Text(initiative.name).font(NDS.body.weight(.medium)).lineLimit(1)
                    .foregroundStyle(isSelected ? NDS.textPrimary : NDS.textSecondary)
                Spacer(minLength: 4)
                if hovering {
                    Button {
                        let p = store.createProject(name: "Untitled")
                        store.setProjectInitiative(p.id, initiativeID: initiative.id)
                        expandedInitiatives.insert(initiative.id)
                        selectedInitiativeID = nil; selectedMeetingID = nil; selectedProjectID = p.id
                    } label: {
                        Image(systemName: "plus").scaledFont(10, weight: .bold).foregroundStyle(NDS.textTertiary)
                    }
                    .buttonStyle(.plain).help("Add project to initiative")
                } else {
                    let open = store.openCount(forInitiative: initiative.id)
                    if open > 0 { Text("\(open)").font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? NDS.brand.opacity(0.14) : (hovering ? NDS.rowHover : .clear),
                        in: RoundedRectangle(cornerRadius: NDS.rowRadius))
            .contentShape(Rectangle())
            // Single tap selects AND auto-expands children — no separate chevron needed.
            .onTapGesture {
                selectedMeetingID = nil; selectedProjectID = nil; selectedInitiativeID = initiative.id
                if !isOpen { expandedInitiatives.insert(initiative.id) }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                Button(role: .destructive) {
                    if selectedInitiativeID == initiative.id { selectedInitiativeID = nil }
                    let name = initiative.name
                    if let undo = store.deleteInitiativeWithUndo(initiative.id) {
                        ToastCenter.shared.show("Deleted “\(name)”", undoTitle: "Undo", undo: undo)
                    }
                } label: { Label("Delete initiative", systemImage: "trash") }
            }

            if isOpen {
                ForEach(projects) { p in
                    PageTreeNode(store: store, project: p, depth: 1,
                                 selectedProjectID: $selectedProjectID,
                                 selectedMeetingID: $selectedMeetingID,
                                 selectedInitiativeID: $selectedInitiativeID,
                                 expanded: $expandedPages)
                }
                if projects.isEmpty {
                    Text("No projects yet").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                        .padding(.leading, 36).padding(.vertical, 2)
                }
            }
        }
    }
}
