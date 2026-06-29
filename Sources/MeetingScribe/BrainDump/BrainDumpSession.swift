import Foundation

/// One "thinking session" in the Brain Dump page: the user's free-text body, the
/// sources they attached (URLs, web searches, Linear briefs, …), and the AI's
/// proposed task / calendar-block drafts awaiting review.
///
/// Persisted as `<storageDir>/brain_dump_sessions.json` (envelope-wrapped) via
/// the shared `TaskPersistenceCoordinator`, so writes are debounced, off-main,
/// and durable on app terminate. Created either in-app (BrainDumpView) or
/// externally (the `submit_brain_dump` MCP tool — Claude Code drops thoughts
/// into the app and the running session reloads via `DarwinNotifier.vaultChanged`).
struct BrainDumpSession: Identifiable, Codable, Hashable {
    var id: String
    var createdAt: Date
    var updatedAt: Date
    /// User-set or auto-derived (first non-empty line, capped at 60 chars).
    /// `nil` until the user types or sets one.
    var title: String?
    /// The composer text. Auto-saved on every change with a 350 ms debounce.
    var body: String
    /// Sources the user (or AI) attached: pasted URLs that were fetched and
    /// readability-extracted, web searches the AI ran, daily Linear brief,
    /// future Slack brief.
    var sources: [BrainDumpSource]
    /// Suggested tasks + calendar focus-blocks the planner emitted. Each draft
    /// stays here through accept / edit / reject so a session is a full record
    /// of what was suggested, what was accepted, and what was thrown out.
    var drafts: [BrainDumpDraft]
    /// Lifecycle state — drives the empty/composer/review UI mode.
    var state: SessionState
    /// Optional `WorkspaceContext.id` (Work / Personal / …) the user wants this
    /// session pinned to. Used to scope project resolution and calendar hours.
    var originContextID: String?
    /// Projects the user explicitly linked to this session before planning. The
    /// planner sees only these (plus the global project list) when suggesting
    /// `propose_task` projects. Empty = unrestricted.
    var linkedProjectIDs: [String]
    /// Schema version. Bumped via `BrainDumpSchemaMigrations` when the on-disk
    /// shape changes. v1 = initial.
    var schemaVersion: Int

    enum SessionState: String, Codable, Hashable {
        case draft        // composer mode — user typing / attaching
        case planning     // AI tool-loop in flight
        case reviewing    // drafts present, awaiting accept/reject
        case archived     // user closed the session

        var label: String {
            switch self {
            case .draft:     return "Draft"
            case .planning:  return "Planning…"
            case .reviewing: return "Reviewing"
            case .archived:  return "Archived"
            }
        }
    }

    init(id: String = UUID().uuidString,
         createdAt: Date = Date(),
         updatedAt: Date? = nil,
         title: String? = nil,
         body: String = "",
         sources: [BrainDumpSource] = [],
         drafts: [BrainDumpDraft] = [],
         state: SessionState = .draft,
         originContextID: String? = nil,
         linkedProjectIDs: [String] = [],
         schemaVersion: Int = 1) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.title = title
        self.body = body
        self.sources = sources
        self.drafts = drafts
        self.state = state
        self.originContextID = originContextID
        self.linkedProjectIDs = linkedProjectIDs
        self.schemaVersion = schemaVersion
    }

    // MARK: - Convenience

    /// What the session picker shows. Prefers the explicit title, falls back to
    /// the first non-blank line of the body, then a "New session" placeholder.
    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        for line in body.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return String(trimmed.prefix(60)) }
        }
        return "New brain dump"
    }

    /// Drafts the user hasn't acted on yet (pending). Drives the review-pane
    /// counter and the "all done" empty state.
    var pendingDrafts: [BrainDumpDraft] {
        drafts.filter { $0.draftState == .pending }
    }

    /// Drafts the user accepted. Useful for the session summary footer.
    var acceptedDrafts: [BrainDumpDraft] {
        drafts.filter {
            if case .accepted = $0.draftState { return true }
            return false
        }
    }
}

/// On-disk envelope so we can bump the schema later without losing old data.
struct BrainDumpSessionEnvelope: Codable {
    var schemaVersion: Int
    var data: [BrainDumpSession]
}
