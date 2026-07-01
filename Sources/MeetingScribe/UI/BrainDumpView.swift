import SwiftUI

/// Root of the Brain Dump page (TopLevelSection.brainDump, ⌘6).
///
/// Three-column shell:
///   [ composer + activity log | sources panel | review panel ]
///
/// Empty when no sessions exist (BrainDumpEmptyState); otherwise renders the
/// active session. Session picker + "+ New session" + "Plan with AI" live in
/// the header.
@available(macOS 14.0, *)
struct BrainDumpView: View {
    @EnvironmentObject var store: BrainDumpStore
    @EnvironmentObject var actionItems: ActionItemStore
    @EnvironmentObject var router: WorkspaceRouter

    /// When embedded inside Tasks, returns to the task list. Brain Dump is now a
    /// page *within* Tasks (no longer a top-level nav item), so the header shows
    /// a "Tasks" back chip whenever this is set.
    var onExit: (() -> Void)? = nil

    /// Human description of the Tasks page the user opened Brain Dump from
    /// (e.g. "Project: Analytics"). Fed to the planner so proposals are
    /// grounded in what the user is looking at.
    var pageContext: String? = nil

    @StateObject private var planRunner = BrainDumpPlanRunner()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(NDS.divider)
            if let session = store.activeSession {
                sessionBody(session)
            } else if !store.isLoaded {
                ProgressView().controlSize(.small) // design-lint:allow
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BrainDumpEmptyState {
                    _ = store.createSession()
                }
            }
        }
        .background(NDS.bg)
        .task(id: router.pendingBrainDumpSessionID) {
            consumePendingDeepLink()
        }
        .task(id: store.pendingPlanSessionID) {
            consumePendingPlan()
        }
        .onAppear { consumePendingDeepLink(); consumePendingPlan() }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let onExit {
                Button(action: onExit) {
                    Label("Tasks", systemImage: "chevron.left").font(NDS.small)
                }
                .buttonStyle(.plain).foregroundStyle(NDS.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Brain Dump").scaledFont(22, weight: .heavy, kind: .display)
                Text("Type, paste, search. The planner turns it into tasks and calendar focus blocks.")
                    .font(NDS.small).foregroundStyle(NDS.textSecondary)
            }
            Spacer()
            // Starting fresh is the primary action; past sessions stay one click
            // away in the picker beside it.
            if !store.sessions.isEmpty {
                sessionPicker
            }
            Button {
                _ = store.createSession()
            } label: {
                Label("New brain dump", systemImage: "plus")
            }
            .buttonStyle(MSPrimaryButtonStyle())
            .help("Start a fresh brain dump. Your past sessions stay in the picker.")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var sessionPicker: some View {
        Menu {
            Section("Recent brain dumps") {
                ForEach(store.recentSessions()) { s in
                    Button {
                        store.activeSessionID = s.id
                    } label: {
                        HStack {
                            if s.id == store.activeSessionID { Image(systemName: "checkmark") }
                            Text(s.displayTitle)
                            Spacer()
                            Text(Self.shortDate(s.updatedAt))
                                .font(NDS.tiny).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider()
            let archived = store.recentSessions(includingArchived: true)
                .filter { $0.state == .archived }
            if !archived.isEmpty {
                Menu("Archived") {
                    ForEach(archived) { s in
                        Button(s.displayTitle) { store.activeSessionID = s.id }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Past sessions")
                Text("(\(store.sessions.count))").foregroundStyle(.secondary)
                Image(systemName: "chevron.down").scaledFont(10)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.rowRadius))
            .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius)
                .strokeBorder(NDS.hairline, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Session body

    @ViewBuilder
    private func sessionBody(_ session: BrainDumpSession) -> some View {
        // Two columns now (composer + review). Sources moved into a modal opened
        // from the composer toolbar, so the page reads as "write ▸ review" instead
        // of three competing panels.
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                BrainDumpComposerView(session: session, planRunner: planRunner, pageContext: pageContext)
                if !planRunner.events.isEmpty {
                    Divider().overlay(NDS.divider)
                    BrainDumpActivityLog(events: planRunner.events)
                        .frame(maxHeight: 120)
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(NDS.divider)
            BrainDumpReviewPanel(session: session)
                .frame(width: 380)
        }
    }

    // MARK: - Helpers

    private func consumePendingDeepLink() {
        guard let id = router.pendingBrainDumpSessionID else { return }
        store.activeSessionID = id
        router.pendingBrainDumpSessionID = nil
    }

    /// Auto-run the planner on a session the Tasks dashboard's quick capture
    /// just created (so "Plan with AI" there flows straight into proposals).
    private func consumePendingPlan() {
        guard let id = store.pendingPlanSessionID else { return }
        store.activeSessionID = id
        store.pendingPlanSessionID = nil
        planRunner.run(sessionID: id, store: store,
                       actionItems: actionItems, contexts: actionItems.contexts,
                       pageContext: pageContext)
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(d) { f.dateFormat = "h:mm a" }
        else { f.dateFormat = "MMM d" }
        return f.string(from: d)
    }
}
