import SwiftUI

@available(macOS 14.0, *)
extension ActionItemsView {
    // MARK: - Detail pane (extracted so the body stays under SwiftUI's
    // type-check budget; consumed by the NavigationSplitView detail — 6-7).

    @ViewBuilder
    var detailPane: some View {
        // GeometryReader wraps the detail content so the trailing property
        // drawer can size itself responsively against the actual available
        // width — fixed 360pt overflowed and got clipped when the window was
        // resized narrow (UX-Q2). Switch routing stays unchanged.
        GeometryReader { geo in
            Group {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .trailing) { propertyDrawer(availableWidth: geo.size.width) }
        }
    }

    // MARK: - Property drawer (6-3)

    /// A drawer that slides in from the right when a row's "expand" is toggled
    /// (`vm.editingID`), instead of pushing the row open in place. Width adapts
    /// to the available pane width so it never overflows a narrow window: on a
    /// roomy pane it sits at a comfortable 360pt, on a tight pane it shrinks
    /// (down to 280pt), and on an extremely tight pane it covers the full pane
    /// so its contents never get clipped.
    @ViewBuilder
    func propertyDrawer(availableWidth: CGFloat) -> some View {
        if let eid = vm.editingID, store.items.contains(where: { $0.id == eid }) {
            HStack(spacing: 0) {
                Divider().overlay(NDS.divider)
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            env.selectedTaskID = eid
                            vm.editingID = nil
                        } label: {
                            Label("Open full page", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(NDS.small)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain).foregroundStyle(NDS.brand)
                        Spacer()
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
                .frame(width: Self.drawerWidth(forAvailable: availableWidth))
                .background(NDS.bg)
                .shadow(color: .black.opacity(0.12), radius: 12, x: -4, y: 0)
            }
            .transition(.move(edge: .trailing))
        }
    }

    /// Drawer width as a function of the detail pane's available width. The
    /// breakpoints keep the drawer usable from huge windows down to a phone-
    /// width Mac window without ever spilling past the pane.
    static func drawerWidth(forAvailable available: CGFloat) -> CGFloat {
        // available can briefly be 0 during the first layout pass.
        guard available > 0 else { return 360 }
        if available >= 720 { return 360 }
        if available >= 460 { return max(300, available - 140) }
        return available
    }
}
