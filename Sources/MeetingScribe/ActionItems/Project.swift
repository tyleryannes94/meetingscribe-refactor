import Foundation

/// A Notion-style "page" that groups related action items — a project,
/// feature, initiative, or workstream. Has a markdown body the user can edit
/// (Phase 3 upgrades this to a richer block editor) and links to any number of
/// action items via `ActionItem.projectID`.
///
/// Persisted in `<storageDir>/projects.json` alongside `action_items.json`.
struct Project: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    /// Optional SF Symbol used as the page icon.
    var icon: String?
    /// Optional accent color (hex, e.g. "#4F8DFD").
    var colorHex: String?
    /// Markdown notes body for the page.
    var body: String
    var status: Status
    /// Parent page id for nesting (nil = top-level). Optional so existing
    /// projects.json still decodes.
    var parentID: String?
    /// Manual ordering among siblings.
    var sortIndex: Double?
    /// Whether this page embeds a task database. nil ⇒ infer from whether it
    /// has tasks (back-compat: old projects with tasks show their database).
    var databaseEnabled: Bool?
    /// Parent initiative (top tier of the hierarchy). nil ⇒ standalone project.
    var initiativeID: String?
    /// Meetings/calls linked to this project (Meeting.id values).
    var meetingIDs: [String]?
    /// Linear project id this is associated with (for Linear sync).
    var linearProjectID: String?
    /// Optional target / due date for the project (PM-3). Drives the "due in N
    /// days" header chip. Optional so existing projects.json still decodes.
    var targetDate: Date?
    /// Time-boxed cycles within this project (6-1). Additive + defaulted.
    var sprints: [Sprint]? = nil
    /// User-defined database columns for this project's tasks (NP-1). Optional
    /// so existing projects.json still decodes.
    var propertyDefs: [PropertyDefinition]?
    /// Reference materials pinned to this feature/project — scoping docs, design
    /// files, competitor analyses — as either web/cloud links or local files
    /// (remembered via a file bookmark). Optional so existing projects.json
    /// still decodes.
    var documents: [DocumentReference]?
    var createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable, CaseIterable, Identifiable {
        case active, onHold, completed, archived
        var id: String { rawValue }
        var label: String {
            switch self {
            case .active: return "Active"
            case .onHold: return "On hold"
            case .completed: return "Completed"
            case .archived: return "Archived"
            }
        }
    }

    init(id: String = UUID().uuidString,
         name: String,
         icon: String? = "doc.text",
         colorHex: String? = nil,
         body: String = "",
         status: Status = .active,
         parentID: String? = nil,
         sortIndex: Double? = nil,
         databaseEnabled: Bool? = nil,
         initiativeID: String? = nil,
         meetingIDs: [String]? = nil,
         linearProjectID: String? = nil,
         targetDate: Date? = nil,
         propertyDefs: [PropertyDefinition]? = nil,
         documents: [DocumentReference]? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.body = body
        self.status = status
        self.parentID = parentID
        self.sortIndex = sortIndex
        self.databaseEnabled = databaseEnabled
        self.initiativeID = initiativeID
        self.meetingIDs = meetingIDs
        self.linearProjectID = linearProjectID
        self.targetDate = targetDate
        self.propertyDefs = propertyDefs
        self.documents = documents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A reference document pinned to a project: a scoping doc, a design file, a
/// competitor analysis, etc. The payload is either a web/cloud URL (Figma,
/// Google Docs, Notion, any link) or a local file remembered via a file
/// bookmark so it survives moves/renames. Persisted inside `Project.documents`.
struct DocumentReference: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var kind: DocKind
    var payload: Payload
    var addedAt: Date = Date()

    enum DocKind: String, Codable, CaseIterable, Hashable, Identifiable {
        case scopingDoc, design, competitor, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .scopingDoc: return "Scoping"
            case .design:     return "Design"
            case .competitor: return "Competitor"
            case .other:      return "Doc"
            }
        }
        var systemImage: String {
            switch self {
            case .scopingDoc: return "doc.text"
            case .design:     return "paintbrush"
            case .competitor: return "chart.bar.doc.horizontal"
            case .other:      return "paperclip"
            }
        }
    }

    /// Where the document lives. `.url` for links, `.localFile` for an on-disk
    /// file (the bookmark resolves the path; `displayPath` is shown in the UI).
    enum Payload: Codable, Hashable {
        case url(String)
        case localFile(bookmark: Data, displayPath: String)
    }

    /// A human-readable location for the chip subtitle / chat answers.
    var locationLabel: String {
        switch payload {
        case .url(let s): return s
        case .localFile(_, let path): return (path as NSString).lastPathComponent
        }
    }
}

/// An Asana-style section that groups tasks within a single project.
/// Persisted in `<storageDir>/project_sections.json`. Tasks point at a section
/// via `ActionItem.sectionID` (nil ⇒ the implicit "No section" bucket).
struct ProjectSection: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var projectID: String
    var name: String
    var sortIndex: Double = 0
}
