import Foundation

/// Phase 4 — workspace cross-linking.
///
/// Every linkable thing in the app (a meeting, a voice note, a project, an
/// action item) is represented as a `WorkspaceEntity`. Links between them are
/// stored *inside the markdown itself* as ordinary markdown links pointing at a
/// custom `meetingscribe://` URL, e.g.
///
///     [Weekly sync](meetingscribe://meeting/3F2A…)
///
/// This keeps notes.md / summary.md / project bodies fully portable (they're
/// still valid markdown) while letting the in-app editor render them as
/// clickable links that navigate within the app. Backlinks are computed by
/// scanning those same files for the target URL.
enum WorkspaceEntityKind: String, Codable, Hashable, CaseIterable {
    case meeting, voiceNote, project, actionItem, person, attachedNote, chatQuery, tag
    case decision, documentRef

    var label: String {
        switch self {
        case .meeting:      return "Meeting"
        case .voiceNote:    return "Voice Note"
        case .project:      return "Project"
        case .actionItem:   return "Action Item"
        case .person:       return "Person"
        case .attachedNote: return "Note"
        case .chatQuery:    return "Ask Chat"
        case .tag:          return "Tag"
        case .decision:     return "Decision"
        case .documentRef:  return "Document"
        }
    }

    var systemImage: String {
        switch self {
        case .meeting:      return "calendar"
        case .voiceNote:    return "waveform"
        case .project:      return "folder.fill"
        case .actionItem:   return "checklist"
        case .person:       return "person.circle"
        case .attachedNote: return "doc.text"
        case .chatQuery:    return "sparkles"
        case .tag:          return "tag"
        case .decision:     return "checkmark.seal"
        case .documentRef:  return "paperclip"
        }
    }
}

struct WorkspaceEntity: Identifiable, Hashable, Sendable {
    let kind: WorkspaceEntityKind
    let rawID: String
    let title: String
    let subtitle: String
    let date: Date?
    /// Matched-context snippet for search results (U2-3), match-wrapped with the
    /// U+0001 / U+0002 sentinels. Nil for non-search entities.
    var snippet: String? = nil

    var id: String { "\(kind.rawValue):\(rawID)" }

    /// `meetingscribe://<kind>/<rawID>`
    var linkURL: URL { WorkspaceLink.url(kind: kind, id: rawID) }

    /// Markdown link the editor inserts for an @-mention.
    var markdownLink: String {
        "[\(WorkspaceLink.sanitizeTitle(title))](\(linkURL.absoluteString))"
    }
}

/// URL <-> entity plumbing for the `meetingscribe://` scheme.
enum WorkspaceLink {
    static let scheme = "meetingscribe"

    static func url(kind: WorkspaceEntityKind, id: String) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = kind.rawValue
        // Percent-encode in case an id ever contains an unsafe char.
        let safeID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        c.path = "/" + safeID
        return c.url ?? URL(string: "\(scheme)://\(kind.rawValue)/\(id)")!
    }

    static func parse(_ url: URL) -> (kind: WorkspaceEntityKind, id: String)? {
        guard url.scheme == scheme,
              let host = url.host,
              let kind = WorkspaceEntityKind(rawValue: host) else { return nil }
        var id = url.path
        if id.hasPrefix("/") { id.removeFirst() }
        id = id.removingPercentEncoding ?? id
        guard !id.isEmpty else { return nil }
        return (kind, id)
    }

    /// Square brackets would break the surrounding `[title](url)` markdown.
    static func sanitizeTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "\n", with: " ")
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}

extension Notification.Name {
    /// Posted when a `meetingscribe://` link is clicked or a global-search
    /// result is chosen. userInfo["url"] = the entity URL string.
    static let meetingScribeOpenEntity = Notification.Name("MeetingScribeOpenEntity")
    /// Posted by the ⌘K command to open the global search palette.
    static let meetingScribeOpenSearch = Notification.Name("MeetingScribeOpenSearch")
    /// 3-F: posted by the Friday weekly-review deep link to present WeeklyReviewView.
    static let meetingScribeOpenWeeklyReview = Notification.Name("MeetingScribeOpenWeeklyReview")
    /// Posted by the ⇧⌘P command to add a new person.
    static let meetingScribeAddPerson = Notification.Name("MeetingScribeAddPerson")
    /// Search-palette result of kind .person — userInfo["id"] = the
    /// person's UUID. PeopleListView observes this and selects the row.
    static let meetingScribeOpenPerson = Notification.Name("MeetingScribeOpenPerson")
    /// Search-palette natural-language passthrough — userInfo["text"]
    /// is dropped into the chat sidebar and submitted.
    static let meetingScribeRunChat = Notification.Name("MeetingScribeRunChat")
    /// Search-palette tag click — userInfo["name"] = the tag to filter
    /// the People list by. PeopleListView listens and sets its filter.
    static let meetingScribeFilterByTag = Notification.Name("MeetingScribeFilterByTag")
    /// ⌘1–⌘7 keyboard shortcuts — object is a TopLevelSection value
    /// that MainWindow observes and switches to.
    static let meetingScribeNavigate = Notification.Name("MeetingScribeNavigate")
}
