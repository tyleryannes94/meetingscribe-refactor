import Foundation

/// Page-tailored top-right toolbar (redesign §1). Pure model: a route (+ whether
/// a meeting is recording) maps to an ordered list of labelled buttons and
/// dividers. `MainWindow` renders these; the actual click handlers stay in the
/// view. Keeping it data makes the per-page button sets testable and one place
/// to change.
enum ToolbarModel {

    enum Action: Equatable {
        case search, voiceNote, record, newMeeting
        case importCalendar, importPeople
        case addPerson, filter, newTask, newVoiceNote
        case stopRecording
    }

    enum Style: Equatable { case ghost, primary, recording }

    struct Button: Equatable, Identifiable {
        let action: Action
        let label: String
        let systemImage: String
        var style: Style = .ghost
        var id: String { "\(action)" }
    }

    enum Item: Equatable, Identifiable {
        case button(Button)
        case divider
        var id: String {
            switch self {
            case .button(let b): return b.id
            case .divider:       return "divider"
            }
        }
    }

    /// The ordered toolbar items for a section. When a meeting is recording, a
    /// red `Stop recording` button is injected as the leftmost item (replacing
    /// any separate stop UI inside the meeting detail).
    static func items(for section: TopLevelSection, isRecordingMeeting: Bool = false) -> [Item] {
        var items: [Item] = baseItems(for: section)
        if isRecordingMeeting {
            let stop = Button(action: .stopRecording, label: "Stop recording",
                              systemImage: "stop.circle.fill", style: .recording)
            items.insert(.button(stop), at: 0)
        }
        return items
    }

    private static func baseItems(for section: TopLevelSection) -> [Item] {
        let search = Button(action: .search, label: "Search", systemImage: "magnifyingglass")
        func primary(_ a: Action, _ label: String, _ icon: String) -> Item {
            .button(Button(action: a, label: label, systemImage: icon, style: .primary))
        }
        func ghost(_ a: Action, _ label: String, _ icon: String) -> Item {
            .button(Button(action: a, label: label, systemImage: icon))
        }
        switch section {
        case .today:
            return [.button(search), .divider,
                    ghost(.voiceNote, "Voice note", "mic"),
                    ghost(.record, "Record", "record.circle"),
                    primary(.newMeeting, "New meeting", "plus")]
        case .meetings:
            return [.button(search),
                    ghost(.importCalendar, "Import calendar", "calendar.badge.plus"), .divider,
                    ghost(.record, "Record", "record.circle"),
                    primary(.newMeeting, "New meeting", "plus")]
        case .people:
            return [.button(search),
                    ghost(.importPeople, "Import", "square.and.arrow.down"), .divider,
                    primary(.addPerson, "Add person", "person.badge.plus")]
        case .actions:
            return [.button(search),
                    ghost(.filter, "Filter", "line.3.horizontal.decrease"), .divider,
                    primary(.newTask, "New task", "plus")]
        case .notes:
            return [.button(search), .divider,
                    primary(.newVoiceNote, "New voice note", "mic.badge.plus")]
        }
    }
}

/// Which recording indicator is shown (redesign §2). The rule, in one tested
/// place the UI consumes: **meeting** recording is in-app only (a docked bar)
/// and never a system-level hover overlay; **voice notes** use the floating
/// hover pill.
enum RecordingPresentation {
    /// The docked in-app meeting bar shows only while a meeting is recording AND
    /// the user is NOT on the Meetings tab (its detail header already shows the
    /// live state there).
    static func showsMeetingDock(isRecordingMeeting: Bool, section: TopLevelSection) -> Bool {
        isRecordingMeeting && section != .meetings
    }

    /// Voice notes use the floating hover pill. Meetings must NEVER trigger it.
    static func showsVoiceHoverPill(isRecordingVoiceNote: Bool) -> Bool {
        isRecordingVoiceNote
    }
}
