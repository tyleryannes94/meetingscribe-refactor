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

    /// Invoked for a `.chatQuery` entity so the host (MainWindow) can reveal the
    /// chat rail before the query is dispatched. The router doesn't own the
    /// rail's visibility, so it delegates that one concern back out.
    var openChat: ((String) -> Void)?

    // MARK: - Back / forward navigation history (global, browser-style)

    /// A point in the navigation history: which top-level section was showing
    /// and, for the Meetings tab, which meeting was open.
    private struct NavState: Equatable {
        var section: TopLevelSection
        var meetingID: String?
    }

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
        self.currentState = NavState(section: initial, meetingID: nil)
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
        let new = NavState(section: section, meetingID: selectedMeetingID)
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
        suppressHistory = true
        selectedMeetingID = state.meetingID
        section = state.section
        updateHistoryFlags()
    }

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

    /// Open a person in the People tab. Person routing is notification-based
    /// (PeopleListView observes it), so this needs no manager.
    func openPerson(_ id: String) {
        section = .people
        NotificationCenter.default.post(name: .meetingScribeOpenPerson,
                                        object: nil, userInfo: ["id": id])
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
            section = .notes
            NotificationCenter.default.post(name: .meetingScribeOpenVoiceNote,
                                            object: nil, userInfo: ["id": id])
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
            section = .people
            NotificationCenter.default.post(name: .meetingScribeFilterByTag,
                                            object: nil, userInfo: ["name": id])
        }
    }
}
