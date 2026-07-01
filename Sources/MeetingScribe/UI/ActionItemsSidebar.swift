import SwiftUI
import AppKit

/// Pinned-projects storage (3-7): up to 5 project ids kept as a CSV string in
/// `@AppStorage` so the rail and every tree node stay reactively in sync (an
/// `[String]` isn't `@AppStorage`-able; project ids are UUIDs → comma-safe).
enum PinnedProjects {
    static let key = "tasks.pinnedProjectsCSV"
    static let max = 5
    static func ids(_ csv: String) -> [String] {
        csv.split(separator: ",").map(String.init)
    }
    static func isPinned(_ id: String, _ csv: String) -> Bool { ids(csv).contains(id) }
    static func toggle(_ id: String, in csv: inout String) {
        var arr = ids(csv)
        if let i = arr.firstIndex(of: id) { arr.remove(at: i) }
        else if arr.count < max { arr.append(id) }
        csv = arr.joined(separator: ",")
    }
}

// MARK: - Project rail (left sidebar)

@available(macOS 14.0, *)
struct ProjectRail: View {
    @ObservedObject var store: ActionItemStore
    /// People facet (P2-2 / P2-6): observed so owner buckets recount live as
    /// records change. Defaulted so the call site needs no new plumbing.
    @ObservedObject private var peopleStore = PeopleStore.shared
    let meetings: [Meeting]
    /// Shared Tasks selection (A0-3) — replaces three threaded `@Binding`s.
    @EnvironmentObject var env: TasksEnvironment
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
    /// Archived initiatives/pages are hidden until the user opts in (P0-4).
    @State private var showArchived = false
    /// Pinned projects (3-7), shared with the page-tree nodes via UserDefaults.
    @AppStorage(PinnedProjects.key) private var pinnedCSV = ""
    /// Keyboard navigation focus for the rail (6-6).
    @FocusState private var railFocused: Bool

    /// Flat, ordered list of keyboard-navigable rail destinations (6-6).
    private var navRoutes: [TasksRoute] {
        var routes: [TasksRoute] = [.today, .home, .triage, .allTasks, .noProject]
        if store.items.contains(where: { !$0.needsTriage && $0.recurrence != nil }) { routes.append(.recurring) }
        routes += visibleInitiatives.map { .initiative($0.id) }
        routes += store.standaloneTopProjects().map { .project($0.id) }
        return routes
    }

    /// Move the rail selection by `delta` (6-6) — arrows drive the cursor and
    /// navigate immediately, so the existing selection highlight is the cursor.
    private func moveRailFocus(_ delta: Int) {
        let routes = navRoutes
        guard !routes.isEmpty else { return }
        let cur = routes.firstIndex(of: env.route) ?? 0
        let next = min(max(cur + delta, 0), routes.count - 1)
        env.go(routes[next])
    }

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
                    Text("New project").scaledFont(13, weight: .semibold)
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
                    contextSwitcher
                    pinnedSection
                    zoneLabel("Smart views")
                    // Today — the default landing and daily scratchpad (1-3).
                    railItem(title: "Today", icon: "sun.max.fill",
                             count: todayBadgeCount,
                             id: ActionItemsView.todaySentinel)
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
                    // Recurring smart list (5-3).
                    let recurringCount = store.items.filter { !$0.needsTriage && $0.recurrence != nil }.count
                    if recurringCount > 0 {
                        railItem(title: "Recurring", icon: "repeat",
                                 count: recurringCount, id: ActionItemsView.recurringSentinel)
                    }
                    // From meetings: confirmed meeting-originated action items.
                    let fromMeetingsCount = store.items.filter {
                        !$0.meetingID.isEmpty && !$0.needsTriage && $0.deletedAt == nil && $0.status != .completed
                    }.count
                    if fromMeetingsCount > 0 {
                        railItem(title: "From meetings", icon: "bubble.left.and.bubble.right.fill",
                                 count: fromMeetingsCount, id: ActionItemsView.fromMeetingsSentinel)
                    }

                    // Waiting-on lifecycle (P2-6).
                    waitingSection

                    // Zone 2: the user's own structured workspace (3-4).
                    Divider().overlay(NDS.divider).padding(.horizontal, 10).padding(.top, 8)
                    zoneLabel("My work")

                    // Initiatives (top tier) — each expands to its projects.
                    HStack {
                        sectionLabel("Initiatives")
                        Spacer()
                        NotionIconButton(systemName: "plus", help: "New initiative") { creatingInitiative = true }
                            .padding(.trailing, 6)
                    }
                    if visibleInitiatives.isEmpty && !creatingInitiative {
                        Text(env.activeContextID == nil ? "Group projects into initiatives"
                                                        : "No initiatives in this context")
                            .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            .padding(.horizontal, 12).padding(.vertical, 2)
                    }
                    ForEach(visibleInitiatives) { ini in
                        InitiativeNode(store: store, initiative: ini,
                                       expandedInitiatives: $expandedInitiatives,
                                       expandedPages: $expandedPages)
                    }
                    if creatingInitiative {
                        TextField("Initiative name", text: $newInitiativeName, onCommit: commitInitiative)
                            .textFieldStyle(.roundedBorder).font(NDS.body)
                            .padding(.horizontal, 8).padding(.top, 6)
                    }

                    HStack {
                        sectionLabel("Projects")
                        Spacer()
                        NotionIconButton(systemName: "plus", help: "New project") { creating = true }
                            .padding(.trailing, 6)
                    }
                    if store.standaloneTopProjects().isEmpty && !creating {
                        Text("No projects yet").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                            .padding(.horizontal, 12).padding(.vertical, 2)
                    }
                    ForEach(store.standaloneTopProjects()) { p in
                        PageTreeNode(store: store, project: p, depth: 0,
                                     expanded: $expandedPages)
                    }
                    if creating {
                        TextField("Page name", text: $newName, onCommit: commitNew)
                            .textFieldStyle(.roundedBorder).font(NDS.body)
                            .padding(.horizontal, 8).padding(.top, 6)
                    }

                    archivedSection

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
            // Keyboard navigation (6-6): ⌘1 focuses the rail; arrows / j-k move
            // the selection through the flat destination list.
            .focusable()
            .focused($railFocused)
            .onKeyPress(.downArrow) { moveRailFocus(1); return .handled }
            .onKeyPress(.upArrow) { moveRailFocus(-1); return .handled }
            .onKeyPress(KeyEquivalent("j")) { moveRailFocus(1); return .handled }
            .onKeyPress(KeyEquivalent("k")) { moveRailFocus(-1); return .handled }
            .background {
                Button("") { railFocused = true }
                    .keyboardShortcut("1", modifiers: .command).opacity(0).frame(width: 0, height: 0)
            }
        }
        .background(NDS.sidebarBg)
    }

    private func sectionLabel(_ s: String) -> some View {
        NotionEyebrow(text: s)
            .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pinned-projects shortcuts at the very top of the rail (3-7).
    @ViewBuilder
    private var pinnedSection: some View {
        let pinned = PinnedProjects.ids(pinnedCSV).compactMap { store.project(id: $0) }
        if !pinned.isEmpty {
            zoneLabel("Pinned")
            ForEach(pinned) { p in
                let selected = env.selectedProjectID == p.id && env.selectedInitiativeID == nil && env.selectedMeetingID == nil
                SidebarRow(selected: selected) {
                    env.selectedMeetingID = nil; env.selectedInitiativeID = nil; env.selectedProjectID = p.id
                } content: {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill").scaledFont(11)
                            .foregroundStyle(NDS.brand).frame(width: 16)
                        Text(p.name).lineLimit(1).font(NDS.body).help(p.name)
                        Spacer()
                    }
                }
                .contextMenu {
                    Button("Unpin") { PinnedProjects.toggle(p.id, in: &pinnedCSV) }
                }
            }
        }
    }

    /// Zone heading (3-4): "Smart views" vs "My work". Heavier than a section
    /// eyebrow so the two halves of the rail read as distinct.
    private func zoneLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(NDS.tiny.weight(.semibold))
            .foregroundStyle(NDS.textTertiary)
            .tracking(0.8)
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Saved-view rail entries (5-1), shown under Smart Views.
    @ViewBuilder
    private var savedViewsSection: some View {
        let views = store.sortedSavedViews()
        if !views.isEmpty {
            zoneLabel("Views")
            ForEach(views) { v in
                railItem(title: v.name, icon: v.icon ?? "line.3.horizontal.decrease.circle",
                         count: 0, id: ActionItemsView.savedViewSentinel(v.id))
            }
        }
    }

    // MARK: - Context switcher (1-2)

    /// Initiatives visible under the active context filter (1-2). "All" shows
    /// every active initiative; a context shows only its own.
    private var visibleInitiatives: [Initiative] {
        store.sortedInitiatives().filter {
            env.activeContextID == nil || $0.contextID == env.activeContextID
        }
    }

    /// Overdue + due-today across the active context — the "Today" rail badge (1-3).
    private var todayBadgeCount: Int {
        let inScope: (ActionItem) -> Bool = { item in
            env.activeContextID == nil || store.effectiveContextID(for: item) == env.activeContextID
        }
        return store.overdueTasks.filter(inScope).count + store.myDayTasks.filter(inScope).count
    }

    /// Compact `All | Work | Personal | …` pill row that scopes the whole rail
    /// and the main task list to one life context (1-2).
    @ViewBuilder
    private var contextSwitcher: some View {
        let ctxs = store.sortedContexts()
        if !ctxs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    contextPill(title: "All", color: nil, active: env.activeContextID == nil) {
                        env.activeContextID = nil
                    }
                    ForEach(ctxs) { c in
                        contextPill(title: c.name, color: store.contextColor(id: c.id),
                                    active: env.activeContextID == c.id) {
                            env.activeContextID = (env.activeContextID == c.id) ? nil : c.id
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
    }

    private func contextPill(title: String, color: Color?, active: Bool,
                             _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(NDS.tiny.weight(active ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? (color ?? NDS.brand).opacity(0.18) : NDS.fieldBg, in: Capsule())
                .foregroundStyle(active ? (color ?? NDS.brand) : NDS.textSecondary)
                .overlay(Capsule().strokeBorder(active ? (color ?? NDS.brand).opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// "Show archived" affordance (P0-4): a low-key toggle, shown only when
    /// something is actually archived, that reveals archived initiatives and
    /// standalone pages beneath the active workspace tree.
    @ViewBuilder
    private var archivedSection: some View {
        let archInitiatives = store.archivedInitiatives()
        let archProjects = store.archivedTopProjects()
        if !archInitiatives.isEmpty || !archProjects.isEmpty {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showArchived.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "archivebox")
                        .scaledFont(10).foregroundStyle(NDS.textTertiary)
                    Text(showArchived ? "Hide archived" : "Show archived")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    Spacer(minLength: 4)
                    Text("\(archInitiatives.count + archProjects.count)")
                        .font(NDS.tiny.monospacedDigit()).foregroundStyle(NDS.textTertiary)
                }
                .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showArchived {
                ForEach(archInitiatives) { ini in
                    InitiativeNode(store: store, initiative: ini,
                                   expandedInitiatives: $expandedInitiatives,
                                   expandedPages: $expandedPages)
                }
                ForEach(archProjects) { p in
                    PageTreeNode(store: store, project: p, depth: 0,
                                 expanded: $expandedPages)
                }
            }
        }
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
        env.selectedMeetingID = nil
        env.selectedInitiativeID = nil
        env.selectedProjectID = p.id
    }

    private func commitInitiative() {
        let n = newInitiativeName.trimmingCharacters(in: .whitespaces)
        creatingInitiative = false
        newInitiativeName = ""
        guard !n.isEmpty else { return }
        let i = store.createInitiative(name: n)
        env.selectedProjectID = nil
        env.selectedMeetingID = nil
        env.selectedInitiativeID = i.id
    }

    private func meetingItem(_ m: Meeting) -> some View {
        let selected = env.selectedMeetingID == m.id
        let openTasks = store.items(for: m.id).filter { $0.status != .completed }.count
        return SidebarRow(selected: selected) {
            env.selectedProjectID = nil
            env.selectedInitiativeID = nil
            env.selectedMeetingID = m.id
        } content: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .scaledFont(13)
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(m.displayTitle).lineLimit(1).font(NDS.body).help(m.displayTitle)
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
        let selected = env.selectedMeetingID == nil && env.selectedInitiativeID == nil && env.selectedProjectID == id
        return SidebarRow(selected: selected) {
            env.selectedMeetingID = nil
            env.selectedInitiativeID = nil
            env.selectedProjectID = id
        } content: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .scaledFont(13)
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                    .frame(width: 16)
                Text(title).lineLimit(1).font(NDS.body).help(title)
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
                    if env.selectedProjectID == id { env.selectedProjectID = nil }
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
        let unassignedCount = store.unassignedOwnerTasks().count
        if !buckets.isEmpty || unassignedCount > 0 {
            disclosureHeader(title: "People",
                             count: buckets.count + (unassignedCount > 0 ? 1 : 0),
                             expanded: $peopleExpanded)
            if peopleExpanded {
                ForEach(buckets.prefix(8), id: \.person.id) { bucket in
                    personRow(bucket.person, open: bucket.open)
                }
                if buckets.count > 8 {
                    Text("+\(buckets.count - 8) more")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                        .padding(.horizontal, 12).padding(.vertical, 2)
                }
                // T12: Unassigned-owners review bucket — tasks whose owner text
                // didn't resolve to a Person. Fix the link, or add the person.
                if unassignedCount > 0 {
                    unassignedOwnersRow(count: unassignedCount)
                }
            }
        }
    }

    private func unassignedOwnersRow(count: Int) -> some View {
        let sentinel = ActionItemsView.unassignedOwnersSentinel
        let selected = env.selectedMeetingID == nil && env.selectedInitiativeID == nil
            && env.selectedProjectID == sentinel
        return SidebarRow(selected: selected) {
            env.selectedMeetingID = nil
            env.selectedInitiativeID = nil
            env.selectedProjectID = sentinel
        } content: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .scaledFont(14)
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.gold)
                    .frame(width: 16)
                Text("Unassigned").lineLimit(1).font(NDS.body)
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                Spacer()
                Text("\(count)").font(NDS.tiny.monospacedDigit())
                    .foregroundStyle(NDS.textTertiary)
            }
            .help("Tasks with an owner name that didn't match a person")
        }
    }

    private func personRow(_ person: Person, open: Int) -> some View {
        let sentinel = ActionItemsView.personSentinel(person.id)
        let selected = env.selectedMeetingID == nil && env.selectedInitiativeID == nil && env.selectedProjectID == sentinel
        return SidebarRow(selected: selected) {
            env.selectedMeetingID = nil
            env.selectedInitiativeID = nil
            env.selectedProjectID = sentinel
        } content: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .scaledFont(14)
                    .foregroundStyle(selected ? NDS.textPrimary : NDS.textSecondary)
                    .frame(width: 16)
                Text(person.displayName).lineLimit(1).font(NDS.body).help(person.displayName)
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
        let selected = env.selectedProjectID == ActionItemsView.waitingSentinel
            && env.selectedMeetingID == nil && env.selectedInitiativeID == nil
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
            env.selectedMeetingID = nil
            env.selectedInitiativeID = nil
            env.selectedProjectID = ActionItemsView.waitingSentinel
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
                Text(item.title).lineLimit(1).font(NDS.body).help(item.title)
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
    @EnvironmentObject var env: TasksEnvironment
    @Binding var expanded: Set<String>
    @State private var hovering = false
    @State private var addingChild = false
    @State private var childName = ""
    /// Shared pinned-projects storage (3-7).
    @AppStorage(PinnedProjects.key) private var pinnedCSV = ""

    private var isSelected: Bool { env.selectedMeetingID == nil && env.selectedInitiativeID == nil && env.selectedProjectID == project.id }
    private var children: [Project] { store.childProjects(of: project.id) }
    private var isOpen: Bool { expanded.contains(project.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row
            if isOpen {
                ForEach(children) { c in
                    PageTreeNode(store: store, project: c, depth: depth + 1,
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
            Text(project.name).font(NDS.body).lineLimit(1).help(project.name)
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
        .onTapGesture { env.selectedMeetingID = nil; env.selectedInitiativeID = nil; env.selectedProjectID = project.id }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Add sub-page") { addingChild = true; expanded.insert(project.id) }
            let pinned = PinnedProjects.isPinned(project.id, pinnedCSV)
            Button(pinned ? "Unpin" : "Pin to top") {
                PinnedProjects.toggle(project.id, in: &pinnedCSV)
            }
            .disabled(!pinned && PinnedProjects.ids(pinnedCSV).count >= PinnedProjects.max)
            Button(role: .destructive) {
                if env.selectedProjectID == project.id { env.selectedProjectID = nil }
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
        env.selectedMeetingID = nil
        env.selectedInitiativeID = nil
        env.selectedProjectID = p.id
    }
}

// MARK: - Initiative node (sidebar; expands to its projects)

@available(macOS 14.0, *)
struct InitiativeNode: View {
    @ObservedObject var store: ActionItemStore
    let initiative: Initiative
    @EnvironmentObject var env: TasksEnvironment
    @Binding var expandedInitiatives: Set<String>
    @Binding var expandedPages: Set<String>
    @State private var hovering = false
    // Inline rename + icon picker (3-5).
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var showIconPicker = false

    private var isOpen: Bool { expandedInitiatives.contains(initiative.id) }
    private var isSelected: Bool { env.selectedInitiativeID == initiative.id }
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

                Button { showIconPicker = true } label: {
                    Image(systemName: initiative.icon ?? "flag.fill")
                        .scaledFont(12).foregroundStyle(NDS.brand).frame(width: 15)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showIconPicker, arrowEdge: .bottom) { iconPicker }
                if renaming {
                    TextField("Name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder).font(NDS.body).frame(maxWidth: 150)
                        .onSubmit(commitRename)
                } else {
                    Text(initiative.name).font(NDS.body.weight(.medium)).lineLimit(1).help(initiative.name)
                        .foregroundStyle(isSelected ? NDS.textPrimary : NDS.textSecondary)
                }
                Spacer(minLength: 4)
                if hovering {
                    Button {
                        let p = store.createProject(name: "Untitled")
                        store.setProjectInitiative(p.id, initiativeID: initiative.id)
                        expandedInitiatives.insert(initiative.id)
                        env.selectedInitiativeID = nil; env.selectedMeetingID = nil; env.selectedProjectID = p.id
                    } label: {
                        Image(systemName: "plus").scaledFont(10, weight: .bold).foregroundStyle(NDS.textTertiary)
                    }
                    .buttonStyle(.plain).help("Add project to initiative")
                } else {
                    completionRing
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
                env.selectedMeetingID = nil; env.selectedProjectID = nil; env.selectedInitiativeID = initiative.id
                if !isOpen { expandedInitiatives.insert(initiative.id) }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                Button("Rename") { nameDraft = initiative.name; renaming = true }
                Button("Change icon…") { showIconPicker = true }
                Button(initiative.status == .archived ? "Unarchive" : "Archive") {
                    store.setInitiativeStatus(initiative.id,
                        status: initiative.status == .archived ? .active : .archived)
                }
                // Assign this initiative (and its tasks, by inheritance) to a
                // workspace context (1-2 / 3-5).
                Menu("Context") {
                    Button {
                        store.setInitiativeContext(initiative.id, contextID: nil)
                    } label: {
                        if initiative.contextID == nil { Label("None", systemImage: "checkmark") }
                        else { Text("None") }
                    }
                    Divider()
                    ForEach(store.sortedContexts()) { c in
                        Button {
                            store.setInitiativeContext(initiative.id, contextID: c.id)
                        } label: {
                            if initiative.contextID == c.id { Label(c.name, systemImage: "checkmark") }
                            else { Text(c.name) }
                        }
                    }
                }
                Button(role: .destructive) {
                    if env.selectedInitiativeID == initiative.id { env.selectedInitiativeID = nil }
                    let name = initiative.name
                    if let undo = store.deleteInitiativeWithUndo(initiative.id) {
                        ToastCenter.shared.show("Deleted “\(name)”", undoTitle: "Undo", undo: undo)
                    }
                } label: { Label("Delete initiative", systemImage: "trash") }
            }

            if isOpen {
                ForEach(projects) { p in
                    PageTreeNode(store: store, project: p, depth: 1,
                                 expanded: $expandedPages)
                }
                if projects.isEmpty {
                    Text("No projects yet").font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                        .padding(.leading, 36).padding(.vertical, 2)
                }
            }
        }
    }

    private func commitRename() {
        let n = nameDraft.trimmingCharacters(in: .whitespaces)
        renaming = false
        guard !n.isEmpty, n != initiative.name else { return }
        store.renameInitiative(initiative.id, name: n)
    }

    /// A tiny completion arc for the initiative (6-5), using the store's
    /// already-computed done/total. Hidden when the initiative has no tasks.
    @ViewBuilder
    private var completionRing: some View {
        let (done, total) = store.completion(forInitiative: initiative.id)
        if total > 0 {
            let frac = Double(done) / Double(total)
            ZStack {
                Circle().stroke(NDS.fieldBg, lineWidth: 2)
                Circle().trim(from: 0, to: frac)
                    .stroke(NDS.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 13, height: 13)
            .help("\(done)/\(total) tasks complete")
        }
    }

    /// Searchable SF Symbol picker for the initiative icon (VD-16, 3-5).
    private var iconPicker: some View {
        SymbolPicker(
            selection: Binding(
                get: { initiative.icon ?? "flag.fill" },
                set: { store.setInitiativeIcon(initiative.id, icon: $0) }
            )
        )
    }
}
