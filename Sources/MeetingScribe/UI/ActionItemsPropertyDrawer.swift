import SwiftUI

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Detail pane (extracted so the body stays under SwiftUI's
    // type-check budget; consumed by the NavigationSplitView detail — 6-7).

    @ViewBuilder
    var detailPane: some View {
        // Brain Dump is now a page *within* Tasks (no longer a top-level nav
        // item) — when toggled on it takes over the detail pane.
        if env.showingBrainDump {
            BrainDumpView(onExit: { env.showingBrainDump = false },
                          pageContext: brainDumpPageContext)
        } else {
            // Drive BOTH widths off the real container size so the inspector
            // drawer can never overflow the right edge — the prior plain-HStack
            // version let the list/board's intrinsic min-width push the drawer
            // off-screen on normal windows. The drawer takes a clamped share of
            // the width and the content gets exactly the remainder (and clips
            // its own overflow rather than forcing the HStack wider).
            GeometryReader { geo in
                let editing = vm.editingID != nil
                    && store.items.contains { $0.id == vm.editingID }
                let drawerW = editing ? min(380, max(260, geo.size.width * 0.42)) : 0
                HStack(spacing: 0) {
                    detailContent
                        .frame(width: max(0, geo.size.width - drawerW),
                               height: geo.size.height)
                        .clipped()
                    if editing {
                        propertyDrawer
                            .frame(width: drawerW, height: geo.size.height)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        // A0-2: route on the typed `TasksRoute` projection instead of
        // sentinel-string comparisons. Guards that fail fall through to
        // `taskDatabasePane`.
        switch env.route {
        case .task(let tid) where store.items.contains(where: { $0.id == tid }):
            TaskPageView(store: store, itemID: tid,
                         breadcrumb: taskBreadcrumb,
                         onClose: { env.selectedTaskID = nil },
                         onNavigate: { env.go($0) })
        case .initiative(let iid) where store.initiative(id: iid) != nil:
            initiativeRollup(iid)
        case .triage:
            TriageInboxView(store: store,
                            onOpenMeeting: { mid in
                                env.selectedMeetingID = mid
                                env.selectedProjectID = nil
                            },
                            onReextract: { manager.backfillActionItemsIfNeeded(force: true) })
        case .home:
            tasksDashboard
        case .today:
            todayPane
        case .savedView(let vid) where store.savedView(id: vid) != nil:
            savedViewPane(vid)
        case .recurring:
            recurringPane
        case .myTasks:
            myTasksPane
        case .meeting(let mid) where manager.pastMeetings.contains(where: { $0.id == mid }):
            Color.clear.onAppear {
                if let m = manager.pastMeetings.first(where: { $0.id == mid }) {
                    router.openMeeting(m)
                }
                env.selectedMeetingID = nil
            }
        default:
            taskDatabasePane
        }
    }

    /// A short description of the Tasks page the user is on, handed to the Brain
    /// Dump planner so its proposals are grounded in what they're viewing
    /// (defaults new tasks to the open project/initiative, relates to the open
    /// task, etc.). nil for surfaces with no useful anchor.
    var brainDumpPageContext: String? {
        switch env.route {
        case .project(let pid):
            guard let p = store.project(id: pid) else { return nil }
            let open = store.items.filter { $0.projectID == pid && $0.deletedAt == nil && $0.status != .completed }
            let initiative = p.initiativeID.flatMap { store.initiative(id: $0)?.name }
            var s = "Project: \(p.name) (\(open.count) open task\(open.count == 1 ? "" : "s"))"
            if let initiative { s += " · Initiative: \(initiative)" }
            return s
        case .initiative(let iid):
            return store.initiative(id: iid).map { "Initiative: \($0.name)" }
        case .task(let tid):
            return store.items.first { $0.id == tid }.map { "Viewing task: \($0.title)" }
        case .today:
            return "The Today view — today's priorities and anything overdue."
        case .myTasks:
            return "My Tasks — tasks assigned to the user."
        case .waitingOn:
            return "Waiting-on — tasks delegated to others."
        default:
            return nil
        }
    }

    // MARK: - Property drawer (6-3)

    /// A drawer that slides in from the right when a row's "expand" is toggled
    /// (`vm.editingID`), instead of pushing the row open in place. Lives as a
    /// sibling of the main content inside an HStack so:
    ///   • on roomy windows it pins to exactly 360pt and the main content takes
    ///     the rest,
    ///   • on tight windows the `.frame(maxWidth: 360)` lets it shrink to fit
    ///     instead of overflowing past the pane's left edge,
    ///   • `.layoutPriority(1)` guarantees it gets its preferred width before
    ///     main content asks for "all available", so the drawer doesn't get
    ///     starved on narrow panes.
    @ViewBuilder
    var propertyDrawer: some View {
        if let eid = vm.editingID, store.items.contains(where: { $0.id == eid }) {
            HStack(spacing: 0) {
                Divider().overlay(NDS.divider)
                VStack(spacing: 0) {
                    // Comp inspector chrome: "TASK INSPECTOR" eyebrow + Full view.
                    HStack {
                        NotionEyebrow(text: "Task inspector")
                        Spacer()
                        Button {
                            env.selectedTaskID = eid
                            vm.editingID = nil
                        } label: {
                            Label("Full view", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(NDS.small)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain).foregroundStyle(NDS.accent)
                        Button { vm.editingID = nil } label: {
                            Image(systemName: "xmark").foregroundStyle(NDS.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    Divider().overlay(NDS.divider)
                    TaskPageView(store: store, itemID: eid, breadcrumb: "Tasks",
                                 onClose: { vm.editingID = nil },
                                 onNavigate: { env.go($0); vm.editingID = nil },
                                 compact: true)
                }
                .background(NDS.bg)
            }
            // Width is set by `detailPane`'s GeometryReader so the drawer always
            // fits inside the container; just fill it here.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .shadow(color: .black.opacity(0.12), radius: 12, x: -4, y: 0)
            .transition(.move(edge: .trailing))
        }
    }
}
