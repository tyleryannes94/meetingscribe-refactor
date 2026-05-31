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
        }
    }

    /// The meeting shown in the canonical Meetings-tab detail pane. Set from
    /// anywhere via `openMeeting`; `MeetingsView` renders whatever is selected.
    @Published var selectedMeetingID: String?

    /// Invoked for a `.chatQuery` entity so the host (MainWindow) can reveal the
    /// chat rail before the query is dispatched. The router doesn't own the
    /// rail's visibility, so it delegates that one concern back out.
    var openChat: ((String) -> Void)?

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.sectionKey) ?? ""
        self.section = TopLevelSection(rawValue: raw) ?? .today
    }

    /// Switch the active top-level section.
    func select(_ s: TopLevelSection) { section = s }

    /// Canonical meeting open: select it, then switch to the Meetings tab.
    func openMeeting(_ meeting: Meeting) {
        selectedMeetingID = meeting.id
        section = .meetings
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
            section = .people
            NotificationCenter.default.post(name: .meetingScribeOpenPerson,
                                            object: nil, userInfo: ["id": id])
        case .attachedNote:
            // rawID is "<personId>::<noteId>" — route to the person.
            let personId = id.split(separator: "::").first.map(String.init) ?? id
            section = .people
            NotificationCenter.default.post(name: .meetingScribeOpenPerson,
                                            object: nil, userInfo: ["id": personId])
        case .chatQuery:
            openChat?(id)
        case .tag:
            section = .people
            NotificationCenter.default.post(name: .meetingScribeFilterByTag,
                                            object: nil, userInfo: ["name": id])
        }
    }
}
