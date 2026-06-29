import Foundation

/// One AI-proposed artifact awaiting review. The planner emits drafts via the
/// `propose_task` and `propose_calendar_block` tools; the review pane lets the
/// user accept (commits to ActionItemStore / EventKit), edit, or reject.
enum BrainDumpDraft: Codable, Identifiable, Hashable {
    case task(TaskDraft)
    case calendarBlock(CalendarBlockDraft)

    var id: UUID {
        switch self {
        case .task(let d):          return d.id
        case .calendarBlock(let d): return d.id
        }
    }

    var draftState: DraftState {
        switch self {
        case .task(let d):          return d.state
        case .calendarBlock(let d): return d.state
        }
    }

    var title: String {
        switch self {
        case .task(let d):          return d.title
        case .calendarBlock(let d): return d.title
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case kind, payload }
    private enum Kind: String, Codable { case task, calendarBlock }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .task(let d):
            try c.encode(Kind.task, forKey: .kind)
            try c.encode(d, forKey: .payload)
        case .calendarBlock(let d):
            try c.encode(Kind.calendarBlock, forKey: .kind)
            try c.encode(d, forKey: .payload)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .task:          self = .task(try c.decode(TaskDraft.self, forKey: .payload))
        case .calendarBlock: self = .calendarBlock(try c.decode(CalendarBlockDraft.self, forKey: .payload))
        }
    }
}

/// Per-draft lifecycle. `accepted` carries the id of the artifact created in
/// the live store (ActionItem id or EKEvent id) so the review pane can deep
/// link to it after the fact.
enum DraftState: Codable, Hashable {
    case pending
    case accepted(externalID: String)
    case edited
    case rejected

    private enum CodingKeys: String, CodingKey { case state, externalID }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pending:                 try c.encode("pending", forKey: .state)
        case .accepted(let externalID):
            try c.encode("accepted", forKey: .state)
            try c.encode(externalID, forKey: .externalID)
        case .edited:                  try c.encode("edited", forKey: .state)
        case .rejected:                try c.encode("rejected", forKey: .state)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try c.decode(String.self, forKey: .state)
        switch s {
        case "pending":  self = .pending
        case "edited":   self = .edited
        case "rejected": self = .rejected
        case "accepted":
            let id = (try? c.decode(String.self, forKey: .externalID)) ?? ""
            self = .accepted(externalID: id)
        default:         self = .pending
        }
    }
}

/// How a proposed task relates to a task that ALREADY exists. Lets the planner
/// dedup against the live task list instead of blindly creating duplicates:
///   - `.subtask`  — this item is a smaller step of `existingTaskID`; accepting
///                   adds it as a subtask under that task (no new top-level task).
///   - `.merge`    — this item is essentially the same as `existingTaskID`;
///                   accepting folds its detail into that task's notes (no
///                   duplicate created).
///   - `.related`  — distinct but connected; accepting creates the new task AND
///                   cross-links both tasks' notes.
/// Optional on `TaskDraft` (nil ⇒ a plain new task), so older persisted drafts
/// decode unchanged.
struct TaskRelation: Codable, Hashable {
    enum Kind: String, Codable { case subtask, merge, related }
    var kind: Kind
    var existingTaskID: String
    var existingTaskTitle: String
    var reason: String?
}

/// Task draft — what the planner thinks the user should add to their tasks.
/// Mirrors the shape of `ExtractedTaskDraft` so the UI can render either kind
/// of draft with the same card.
struct TaskDraft: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    /// Stored as the raw value so we can decode safely if a model invents one;
    /// the UI maps it to `ActionItem.Priority` with a `.medium` fallback.
    var priorityRaw: String
    var dueDate: Date?
    var suggestedProjectID: String?
    var suggestedProjectName: String?
    /// Tags the planner recommends. Names (not ids) so they survive decode even
    /// if a label is renamed; resolved-or-created at accept time. Optional so
    /// older persisted drafts (which had no tags) still decode.
    var suggestedLabelNames: [String]?
    /// Initiative the suggested project rolls up to — display-only context on
    /// the card (initiatives attach to projects, not tasks). Optional for decode.
    var suggestedInitiativeName: String?
    /// Dedup verdict against the live task list (subtask / merge / related), or
    /// nil for a plain new task. Optional so older persisted drafts decode.
    var relation: TaskRelation?
    /// Notes the planner attached (rationale, source citations, etc.).
    var notes: String?
    /// URLs the planner cited as the source of this task — shown as link chips
    /// on the card so the user can re-check the context before accepting.
    var sourceURLs: [URL]
    var state: DraftState

    init(id: UUID = UUID(),
         title: String,
         priorityRaw: String = "medium",
         dueDate: Date? = nil,
         suggestedProjectID: String? = nil,
         suggestedProjectName: String? = nil,
         suggestedLabelNames: [String]? = nil,
         suggestedInitiativeName: String? = nil,
         relation: TaskRelation? = nil,
         notes: String? = nil,
         sourceURLs: [URL] = [],
         state: DraftState = .pending) {
        self.id = id
        self.title = title
        self.priorityRaw = priorityRaw
        self.dueDate = dueDate
        self.suggestedProjectID = suggestedProjectID
        self.suggestedProjectName = suggestedProjectName
        self.suggestedLabelNames = suggestedLabelNames
        self.suggestedInitiativeName = suggestedInitiativeName
        self.relation = relation
        self.notes = notes
        self.sourceURLs = sourceURLs
        self.state = state
    }

    /// Resolved priority for ActionItemStore.createTask. Falls back to `.medium`
    /// when the model emits a value we don't recognise.
    var priority: ActionItem.Priority {
        ActionItem.Priority(rawValue: priorityRaw.lowercased()) ?? .medium
    }
}

/// Calendar focus-block draft — a chunk of work-hours time the planner thinks
/// the user should commit to a specific outcome. Accepting writes through
/// `CalendarStoreActor.scheduleFollowUp(...)`, falling back to copying an ICS
/// blob to the clipboard if EventKit permission is missing.
struct CalendarBlockDraft: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var start: Date
    var durationMinutes: Int
    /// Optional title of a task draft this block is meant to advance. Used by
    /// the UI to show the linkage card-to-card; not a strong reference (the
    /// task draft's id might not exist yet when the block is proposed).
    var linkedTaskTitle: String?
    var notes: String?
    var state: DraftState

    init(id: UUID = UUID(),
         title: String,
         start: Date,
         durationMinutes: Int = 25,
         linkedTaskTitle: String? = nil,
         notes: String? = nil,
         state: DraftState = .pending) {
        self.id = id
        self.title = title
        self.start = start
        self.durationMinutes = max(5, durationMinutes)
        self.linkedTaskTitle = linkedTaskTitle
        self.notes = notes
        self.state = state
    }

    var end: Date {
        Calendar.current.date(byAdding: .minute, value: durationMinutes, to: start) ?? start
    }
}
