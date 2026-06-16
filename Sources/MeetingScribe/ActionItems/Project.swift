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
    /// User-defined database columns for this project's tasks (NP-1). Optional
    /// so existing projects.json still decodes.
    var propertyDefs: [PropertyDefinition]?
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
