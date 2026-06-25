import SwiftUI

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Detail pane (extracted so the body stays under SwiftUI's
    // type-check budget; consumed by the NavigationSplitView detail — 6-7).

    @ViewBuilder
    var detailPane: some View {
        // Real HStack split (not overlay) so the drawer participates in
        // layout: main content shrinks to make room, the drawer never
        // overflows the pane, and the whole thing re-balances when the
        // window resizes either direction. The previous overlay + fixed
        // 360pt frame clipped past the pane on narrow windows; the
        // GeometryReader-driven attempt was reading unexpected sizes
        // on wide windows and rendering the drawer far wider than 360.
        HStack(spacing: 0) {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            propertyDrawer
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
                                 onNavigate: { env.go($0); vm.editingID = nil })
                }
                .background(NDS.bg)
            }
            .frame(maxWidth: 380, maxHeight: .infinity)
            .layoutPriority(1)
            .shadow(color: .black.opacity(0.12), radius: 12, x: -4, y: 0)
            .transition(.move(edge: .trailing))
        }
    }
}
