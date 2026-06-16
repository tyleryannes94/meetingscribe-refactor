import SwiftUI
import Combine

/// The single source of truth for top-level navigation and entity opening (D1-1).
///
/// Before this, a meeting opened four incompatible ways — the Meetings split
/// pane, a pushed page in Today, a modal sheet from search/deep-links, plus an
/// `asyncAfter(0.18)` dismiss-then-present hack. This router collapses them to
/// ONE canonical surface: every meeting opens in the Meetings tab's detail
/// pane. Search, deep links, and person↔meeting backlinks all call `open`.
@available(macOS 14.0, *)
@MainActor
final class WorkspaceRouter: ObservableObject {
    private static let sectionKey = "mainWindow.lastSelectedSection"

    /// The selected top-level section. Persisted across launches under the same
    /// key the old `@AppStorage` used, so existing users keep their last tab.
    @Published var section: TopLevelSection {
        didSet {
            guard section != oldValue else { return }
            UserDefaults.standard.set(section.rawValue, forKey: Self.sectionKey)
            scheduleHistoryRecord()
        }
    }

    /// The meeting shown in the canonical Meetings-tab detail pane. Set from
    /// anywhere via `openMeeting`; `MeetingsView` renders whatever is selected.
    @Published var selectedMeetingID: String? {
        didSet {
            guard selectedMeetingID != oldValue else { return }
            scheduleHistoryRecord()
        }
    }

    /// The person shown in the People tab (D1-3): a real router property, not a
    /// fire-and-forget NotificationCenter post a lazily-built tab can miss.
    /// `PeopleListView` binds its selection to this and consumes it on appear,
    /// so deep links land even on first visit. Also remembered in history (D1-2).
    @Published var selectedPersonID: String? {
        didSet {
            guard selectedPersonID != oldValue else { return }
            scheduleHistoryRecord()
        }
    }

    /// A one-shot deep-link destination for sections whose target view owns its
    /// own selection state (voice notes, people tag filter). The router sets it;
    /// the destination view consumes it in `.onAppear`/`.onChange` and clears it
    /// via `consume(_:)`. Replaces the NotificationCenter + asyncAfter races.
    @Published var pendingRoute: PendingRoute?

    enum PendingRoute: Equatable {
        case voiceNote(String)
        case tagFilter(String)
    }

    /// Carried from a search hit to the opened meeting's transcript so it lands
    /// pre-highlighted with the find-bar populated (U2-2). Consumed + cleared by
    /// the meeting detail.
    @Published var pendingTranscriptQuery: String?

    /// One-shot: a task to open in the Tasks tab. Set by surfaces outside the
    /// Tasks tab (e.g. the home-page Kanban board), consumed by `ActionItemsView`
    /// which selects the task and clears this. Mirrors the `pendingRoute` pattern.
    @Published var pendingTaskID: String?

    /// Clear the mailbox once a destination view has acted on it.
    func consume(_ route: PendingRoute) {
        if pendingRoute == route { pendingRoute = nil }
    }

    /// Invoked for a `.chatQuery` entity so the host (MainWindow) can reveal the
    /// chat rail before the query is dispatched. The router doesn't own the
    /// rail's visibility, so it delegates that one concern back out.
    var openChat: ((String) -> Void)?

    // MARK: - Back / forward navigation history (global, browser-style)

    /// A point in the navigation history: which top-level section was showing
    /// and, for the Meetings tab, which meeting was open. (3-8) also captures the
    /// Tasks pane's internal selection so back/forward restores it.
    private struct NavState: Equatable {
        var section: TopLevelSection
        var meetingID: String?
        var personID: String?
        var tasks: TasksSelection = .init()
    }

    /// Snapshot of the Tasks pane's selection (3-8). Owned by `TasksEnvironment`;
    /// the router mirrors the current value so it can be saved into history and
    /// restored on back/forward via `tasksRestore`.
    struct TasksSelection: Equatable {
        var project: String?
        var task: String?
        var initiative: String?
        var meeting: String?
    }

    /// Router's mirror of the live Tasks selection (updated by `ActionItemsView`).
    private var currentTasks = TasksSelection()
    /// One-shot: a Tasks selection to restore after a back/forward step. The
    /// Tasks view observes this and applies it to `TasksEnvironment`.
    @Published var tasksRestore: TasksSelection?

    private var backStack: [NavState] = []
    private var forwardStack: [NavState] = []
    private var currentState: NavState
    /// While restoring a history entry we don't want the resulting `section` /
    /// `selectedMeetingID` mutations to push *new* history.
    private var suppressHistory = false
    private var recordScheduled = false

    /// Drives the enabled state of the toolbar back/forward buttons.
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.sectionKey) ?? ""
        let initial = TopLevelSection(rawValue: raw) ?? .today
        self.section = initial
        self.currentState = NavState(section: initial, meetingID: nil, personID: nil)
    }

    /// Coalesce the back-to-back `section` + `selectedMeetingID` mutations of a
    /// single navigation (e.g. `openMeeting` sets both) into one history entry
    /// by recording once the runloop settles.
    private func scheduleHistoryRecord() {
        guard !recordScheduled else { return }
        recordScheduled = true
        DispatchQueue.main.async { [weak self] in self?.recordHistory() }
    }

    private func recordHistory() {
        recordScheduled = false
        defer { suppressHistory = false }
        let new = NavState(section: section, meetingID: selectedMeetingID,
                           personID: selectedPersonID, tasks: currentTasks)
        guard new != currentState else { return }
        if !suppressHistory {
            backStack.append(currentState)
            if backStack.count > 50 { backStack.removeFirst() }
            forwardStack.removeAll()
        }
        currentState = new
        updateHistoryFlags()
    }

    private func updateHistoryFlags() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }

    private func apply(_ state: NavState) {
        // Set current first so the coalesced record sees no change and no-ops.
        currentState = state
        currentTasks = state.tasks
        suppressHistory = true
        selectedMeetingID = state.meetingID
        selectedPersonID = state.personID
        section = state.section
        // Hand the Tasks pane its selection to restore (3-8).
        tasksRestore = state.tasks
        updateHistoryFlags()
    }

    /// Called by `ActionItemsView` whenever the Tasks pane's internal selection
    /// changes, so back/forward can restore it (3-8). Coalesced into one history
    /// entry like section/meeting changes.
    func setTasksSelection(project: String?, task: String?, initiative: String?, meeting: String?) {
        let new = TasksSelection(project: project, task: task, initiative: initiative, meeting: meeting)
        guard new != currentTasks else { return }
        currentTasks = new
        scheduleHistoryRecord()
    }

    /// Clear the restore mailbox once the Tasks view has applied it.
    func consumeTasksRestore() { tasksRestore = nil }

    /// Step back to the previous section/meeting.
    func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(currentState)
        apply(prev)
    }

    /// Step forward (only available right after a `goBack`).
    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentState)
        apply(next)
    }

    /// Switch the active top-level section.
    func select(_ s: TopLevelSection) { section = s }

    /// Canonical meeting open: select it, then switch to the Meetings tab.
    func openMeeting(_ meeting: Meeting) {
        selectedMeetingID = meeting.id
        section = .meetings
    }

    /// Open a person in the People tab (D1-3). Deterministic: sets the router's
    /// `selectedPersonID` (which `PeopleListView` binds to and consumes on
    /// appear) instead of posting a notification a lazily-built tab can miss.
    func openPerson(_ id: String) {
        selectedPersonID = id
        section = .people
    }

    /// Single entry point for opening any workspace entity (search palette,
    /// deep links, person/meeting backlinks). Meetings open in the Meetings
    /// tab detail; other kinds flip to their section. Replaces the old
    /// `MainWindow.routeEntity` + modal sheet + `asyncAfter` hack.
    func open(_ entity: WorkspaceEntity, manager: MeetingManager) {
        route(kind: entity.kind, id: entity.rawID, manager: manager)
    }

    func route(kind: WorkspaceEntityKind, id: String, manager: MeetingManager) {
        switch kind {
        case .meeting:
            if let m = manager.meeting(forEntityID: id) {
                openMeeting(m)
            } else {
                // Not in the loaded index yet — refresh so a subsequent open
                // resolves. (Same fallback the old router used.)
                manager.refreshPastMeetings(force: true)
            }
        case .voiceNote:
            pendingRoute = .voiceNote(id)
            section = .notes
        case .project, .actionItem:
            section = .actions
        case .person:
            openPerson(id)
        case .attachedNote:
            // rawID is "<personId>::<noteId>" — route to the person.
            let personId = id.split(separator: "::").first.map(String.init) ?? id
            openPerson(personId)
        case .chatQuery:
            openChat?(id)
        case .tag:
            pendingRoute = .tagFilter(id)
            section = .people
        }
    }
}
