import Foundation

/// One actionable follow-up extracted from a meeting summary. Persisted in
/// `<storageDir>/action_items.json` and rendered by the Action Items tab.
///
/// Lifecycle:
///   1. `ActionItemExtractor` parses `summary.md` after a meeting's summary
///      is written. New items get appended (deduped by `signature`).
///   2. User edits priority / due date / status / notes in the UI.
///   3. Optional: user clicks "Push to Notion" — the item is created as a
///      page in the configured Notion database; `notionPageID` + `notionURL`
///      are stored so subsequent edits can update the same page.
struct ActionItem: Identifiable, Codable, Hashable {
    var id: String
    /// Meeting this item came from. Cross-referenced via Meeting.id.
    var meetingID: String
    /// Denormalized so the Action Items tab can render without touching
    /// the meetings list.
    var meetingTitle: String
    var meetingDate: Date

    var title: String
    var owner: String?
    /// Optional hard link to a Person record (PeopleStore.person(by:)). Kept
    /// alongside the free-text `owner` so non-person owners still work and old
    /// JSON decodes (synthesized Codable uses decodeIfPresent). Enables exact,
    /// bidirectional person↔task navigation.
    var ownerPersonID: String?
    var notes: String?
    var status: Status
    var priority: Priority
    var dueDate: Date?

    /// Optional link to a Project/feature page. Optional so existing
    /// action_items.json (written before projects existed) still decodes —
    /// synthesized Codable uses decodeIfPresent for optionals.
    var projectID: String?

    // MARK: - Phase 5 task-tracker fields (all optional → old JSON still decodes)

    /// When work should begin (Asana/Linear style start date).
    var startDate: Date?
    /// IDs into ActionItemStore.labels.
    var labelIDs: [String]?
    /// Nested checklist / subtasks.
    var subtasks: [Subtask]?
    /// Section within a project (Asana-style). nil = the default section.
    var sectionID: String?
    /// Manual ordering weight within a status column / section. Lower = higher
    /// up. Defaults large so legacy items sort by the computed sort.
    var sortIndex: Double?
    /// Origin: nil/"local" = created in-app, "meeting" = extracted from a
    /// summary, "linear" / "notion" = imported from an external system.
    var source: String?
    /// Stable id from the external system, for sync dedup.
    var externalID: String?
    /// Deep link back to the source issue/page.
    var externalURL: String?

    /// Filled in after a successful Notion push.
    var notionPageID: String?
    var notionURL: String?

    /// Soft-delete tombstone (P0-3). nil ⇒ live; non-nil ⇒ in Trash and
    /// recoverable until purged (default 30 days). Optional + defaulted so old
    /// action_items.json decodes and the synthesized memberwise init still
    /// accepts the existing call sites that omit it.
    var deletedAt: Date? = nil

    /// When the task was marked completed (P2-4). Distinct from `updatedAt`
    /// (which any edit bumps), so "done today / this week" surfaces and
    /// reporting are accurate. Set on the open→completed transition, cleared on
    /// reopen. Optional + defaulted for back-compat.
    var completedAt: Date? = nil

    /// Repeat rule (P2-5). When set, completing the task spawns the next
    /// instance with the dates rolled forward. nil = one-shot.
    var recurrence: RecurrenceRule? = nil
    /// Groups instances of a recurring task (the original's id). nil = not part
    /// of a series.
    var seriesID: String? = nil

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Convenience

    var subtaskList: [Subtask] { subtasks ?? [] }
    var labels: [String] { labelIDs ?? [] }
    /// In Trash (soft-deleted) and excluded from all normal views.
    var isTrashed: Bool { deletedAt != nil }
    /// A task with no originating meeting (created manually or imported).
    var isManual: Bool { meetingID.isEmpty }
    var subtaskProgress: (done: Int, total: Int) {
        let list = subtaskList
        return (list.filter { $0.done }.count, list.count)
    }

    enum Status: String, Codable, CaseIterable, Identifiable {
        case open, inProgress, completed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .open: return "Open"
            case .inProgress: return "In Progress"
            case .completed: return "Completed"
            }
        }
        var systemImage: String {
            switch self {
            case .open: return "circle"
            case .inProgress: return "circle.lefthalf.filled"
            case .completed: return "checkmark.circle.fill"
            }
        }
    }

    enum Priority: String, Codable, CaseIterable, Identifiable {
        case low, medium, high, urgent
        var id: String { rawValue }
        var label: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .urgent: return "Urgent"
            }
        }
        /// Sort weight — higher is more urgent. Used by the table.
        var weight: Int {
            switch self {
            case .low: return 0
            case .medium: return 1
            case .high: return 2
            case .urgent: return 3
            }
        }
    }

    /// A stable hash of the meeting + title used for dedup when re-extracting.
    /// Two extracted lines that share the same meeting + normalized title
    /// are treated as the same action item — preserving user edits across
    /// re-extracts (transcribe-now, etc).
    var signature: String {
        let t = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(meetingID)::\(t)"
    }
}

/// One checklist item nested under an ActionItem.
struct Subtask: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var done: Bool = false
}

/// A reusable colored label (Trello/Notion-style). Persisted in
/// `<storageDir>/task_labels.json`.
struct TaskLabel: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Hex like "#4F8DFD".
    var colorHex: String

    /// A small built-in palette so new labels look intentional.
    static let palette: [String] = [
        "#EB5757", "#F2994A", "#F2C94C", "#27AE60",
        "#2D9CDB", "#2F80ED", "#9B51E0", "#BB6BD9",
        "#828282", "#EB5B8C"
    ]
}
