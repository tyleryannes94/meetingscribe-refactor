import Foundation
import VaultKit
import OSLog

/// Lifecycle state of a decision (P0-E). A decision starts `open`; a later
/// decision can `supersede` it, or it can be `resolved` once acted on.
/// In the project-centric UI these read as **To make** (open) → **Made**
/// (resolved) / **Superseded**.
enum DecisionStatus: String, Codable, CaseIterable, Hashable {
    case open
    case superseded
    case resolved

    /// Human label used by the project/task/initiative decision sections.
    var label: String {
        switch self {
        case .open:       return "To make"
        case .resolved:   return "Made"
        case .superseded: return "Superseded"
        }
    }
}

/// Where a decision came from. Auto-extracted decisions carry `.meeting`;
/// ones the user logs by hand carry `.manual` (and have no meetingID).
enum DecisionOrigin: String, Codable, Hashable {
    case meeting
    case manual
}

/// One decision made in a meeting, lifted out of that meeting's summary into a
/// queryable cross-meeting ledger. (P1-1 / C1-11 / C2-8)
///
/// P0-E enriches the bare record so it stays useful months later: a `rationale`
/// (the *why*, extracted by a local LLM pass), the `personIDs` it concerns, an
/// owning `projectID`, a lifecycle `status`, and an optional `revisitDate`. All
/// new fields are optional/defaulted and decoded with `decodeIfPresent`, so every
/// pre-existing `decisions.json` still loads.
struct Decision: Identifiable, Codable, Hashable {
    var id: String
    /// Source meeting. nil for a manually-logged decision. (Was non-optional —
    /// optional now so a decision can be created by hand from a project/task.)
    var meetingID: String?
    /// Denormalized source-meeting title. nil for manual decisions.
    var meetingTitle: String?
    var date: Date
    var text: String

    /// The *why* behind the decision, in one sentence — extracted by a local
    /// Ollama pass at summary time. nil until that pass runs (or if it fails).
    var rationale: String?
    /// People this decision concerns (resolved Person ids). Populated by the
    /// post-meeting pipeline from the meeting's attendees (Phase 3).
    var personIDs: [String]
    /// Optional owning Project/feature.
    var projectID: String?
    /// Optional owning Task (ActionItem.id).
    var taskID: String?
    /// Optional owning Initiative (Initiative.id).
    var initiativeID: String?
    /// Whether this was auto-extracted from a meeting or logged manually.
    var origin: DecisionOrigin
    /// Lifecycle state.
    var status: DecisionStatus
    /// When to revisit this decision, if ever.
    var revisitDate: Date?

    init(id: String,
         meetingID: String? = nil,
         meetingTitle: String? = nil,
         date: Date,
         text: String,
         rationale: String? = nil,
         personIDs: [String] = [],
         projectID: String? = nil,
         taskID: String? = nil,
         initiativeID: String? = nil,
         origin: DecisionOrigin = .meeting,
         status: DecisionStatus = .open,
         revisitDate: Date? = nil) {
        self.id = id
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.date = date
        self.text = text
        self.rationale = rationale
        self.personIDs = personIDs
        self.projectID = projectID
        self.taskID = taskID
        self.initiativeID = initiativeID
        self.origin = origin
        self.status = status
        self.revisitDate = revisitDate
    }
}

extension Decision {
    /// Label for the decision's source: the meeting title, or a manual marker
    /// when it was logged by hand (meetingTitle == nil).
    var sourceLabel: String { meetingTitle ?? "Logged manually" }

    /// Custom decode so legacy records (and the v1 schema, which had only
    /// id/meetingID/meetingTitle/date/text) load without throwing on the new
    /// keys. Kept in an extension so the memberwise initializer above survives.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        meetingID = try c.decodeIfPresent(String.self, forKey: .meetingID)
        meetingTitle = try c.decodeIfPresent(String.self, forKey: .meetingTitle)
        date = try c.decode(Date.self, forKey: .date)
        text = try c.decode(String.self, forKey: .text)
        rationale = try c.decodeIfPresent(String.self, forKey: .rationale)
        personIDs = try c.decodeIfPresent([String].self, forKey: .personIDs) ?? []
        projectID = try c.decodeIfPresent(String.self, forKey: .projectID)
        taskID = try c.decodeIfPresent(String.self, forKey: .taskID)
        initiativeID = try c.decodeIfPresent(String.self, forKey: .initiativeID)
        origin = try c.decodeIfPresent(DecisionOrigin.self, forKey: .origin) ?? .meeting
        status = try c.decodeIfPresent(DecisionStatus.self, forKey: .status) ?? .open
        revisitDate = try c.decodeIfPresent(Date.self, forKey: .revisitDate)
    }
}

/// Central registry for the Decision ledger's JSON schema migrations (P0-E),
/// mirroring `TaskSchemaMigrations`. The v1→v2 step is identity — backward
/// compatibility is carried by `Decision.init(from:)`'s `decodeIfPresent` — but
/// the seam is real and stamped so the *next* structural change is a one-line
/// `steps` entry rather than a persistence refactor.
enum DecisionSchemaMigrations {
    static func decisions(_ items: [Decision], from: Int, to: Int) -> [Decision] {
        TaskSchemaMigrations.migrate(items, from: from, to: to, steps: [:])
    }
}

/// The Decision Ledger: a vault-wide, queryable record of decisions extracted
/// from meeting summaries' "Key Decisions" sections, so they stop dying inside
/// one meeting's markdown. Persisted to `<vault>/decisions.json`.
@available(macOS 14.0, *)
@MainActor
final class DecisionStore: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Decisions")
    @Published private(set) var decisions: [Decision] = []

    /// On-disk schema version. v2 added the enriched struct (rationale/people/
    /// project/status/revisit). v3 adds manual decisions: optional meetingID/
    /// meetingTitle plus taskID/initiativeID/origin. Back-compat is carried by
    /// `decodeIfPresent`, so the v2→v3 migration step is identity.
    static let schemaVersion = 3

    private var fileURL: URL { AppSettings.shared.storageDir.appendingPathComponent("decisions.json") }
    private var loadTask: Task<Void, Never>?

    init() {
        // Decode OFF the main thread (mirrors ActionItemStore) — this store is
        // built during MeetingManager init on the app-launch critical path, and a
        // synchronous `Data(contentsOf:)` + decode here used to block first paint,
        // worst on a cold / iCloud-evicted / scanner-intercepted vault.
        let url = fileURL
        let version = Self.schemaVersion
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let data = try? Data(contentsOf: url) else { return }
            let decoded = (try? SchemaEnvelope.decode([Decision].self, from: data,
                                                      currentVersion: version,
                                                      migrate: DecisionSchemaMigrations.decisions))?
                .sorted { $0.date > $1.date }
            guard let decoded else { return }
            await MainActor.run {
                guard let self else { return }
                // Don't clobber a decision logged in the tiny window before the
                // async load resolved.
                if self.decisions.isEmpty { self.decisions = decoded }
            }
        }
    }

    /// Encode on main (cheap for this small array) and hand the bytes to the
    /// shared debounced, coalesced, off-main writer — so rapid edits (status
    /// flips, text edits, the extract pipeline) collapse into one background
    /// atomic write instead of N synchronous full-file writes on the UI thread.
    private func save() {
        let env = SchemaEnvelope(version: Self.schemaVersion, data: decisions)
        guard let data = try? SharedCoders.encoder(pretty: true, sorted: true).encode(env) else { return }
        TaskPersistenceCoordinator.shared.write(data, to: fileURL)
    }

    /// Replace this meeting's decisions with those parsed from its summary.
    /// Idempotent — safe to call again after a re-transcribe.
    func extract(from summary: String, meeting: Meeting) {
        let parsed = Self.parseDecisions(from: summary)
        let existing = decisions.filter { $0.meetingID == meeting.id }
        // No-op if nothing changed, so a backfill pass over unchanged meetings
        // doesn't churn the file.
        if existing.map(\.text) == parsed { return }

        // Preserve any rationale/person links already attached to a decision with
        // the same text (a re-transcribe shouldn't drop enrichment).
        let priorByText = Dictionary(existing.map { ($0.text, $0) }, uniquingKeysWith: { a, _ in a })
        let oldIDs = Set(existing.map(\.id))

        decisions.removeAll { $0.meetingID == meeting.id }
        for text in parsed {
            let prior = priorByText[text]
            decisions.append(Decision(
                id: "\(meeting.id)::\(abs(text.hashValue))",
                meetingID: meeting.id,
                meetingTitle: meeting.displayTitle,
                date: meeting.startDate,
                text: text,
                rationale: prior?.rationale,
                personIDs: prior?.personIDs ?? [],
                projectID: prior?.projectID,
                status: prior?.status ?? .open,
                revisitDate: prior?.revisitDate))
        }
        decisions.sort { $0.date > $1.date }
        save()

        // P0-A / 1-B: keep the vault index in step. De-index decisions that
        // vanished, (re)index the current set for this meeting.
        let newSet = decisions.filter { $0.meetingID == meeting.id }
        let newIDs = Set(newSet.map(\.id))
        for removed in oldIDs.subtracting(newIDs) {
            VaultIndexService.shared.removeFromIndex(entityID: removed, entityKind: "decision")
        }
        for d in newSet {
            VaultIndexService.shared.indexDecision(d)
            SecondBrainEventBus.shared.publish(.decisionExtracted(decision: d, meetingID: meeting.id))
        }
    }

    /// 3-A: cross-link a meeting's decisions to its attendees (resolved Person
    /// ids). Only fills decisions that have no people yet, so re-runs are safe.
    /// Reindexing materializes the `decision_persons` join edge (P0-F).
    func crossLinkPersons(meetingID: String, personIDs: [String]) {
        guard !personIDs.isEmpty else { return }
        var changed = false
        for i in decisions.indices
        where decisions[i].meetingID == meetingID && decisions[i].personIDs.isEmpty {
            decisions[i].personIDs = personIDs
            VaultIndexService.shared.indexDecision(decisions[i])
            changed = true
        }
        if changed { save() }
    }

    /// Re-index every decision (one-time backfill when the vault index is missing
    /// decisions, e.g. after the P0 upgrade or an index rebuild).
    func backfillVaultIndexIfNeeded() {
        guard VaultIndexService.shared.vaultContentCount(kind: "decision") == 0,
              !decisions.isEmpty else { return }
        for d in decisions { VaultIndexService.shared.indexDecision(d) }
        log.info("Backfilled \(self.decisions.count, privacy: .public) decision(s) into the vault index")
    }

    /// Best-effort: ask the local model for a one-sentence rationale per decision
    /// in this meeting and store it (P0-E). Non-blocking and failure-tolerant —
    /// decisions remain usable with a nil rationale if Ollama is unavailable or
    /// the response can't be parsed.
    func extractRationales(forMeeting meetingID: String, summary: String,
                           using summarizer: OllamaService) async {
        let targets = decisions.filter { $0.meetingID == meetingID && ($0.rationale ?? "").isEmpty }
        guard !targets.isEmpty else { return }
        let numbered = targets.enumerated()
            .map { "\($0.offset + 1). \($0.element.text)" }
            .joined(separator: "\n")
        let prompt = """
        Below are decisions made in a meeting. For each, give the rationale — the \
        single most important reason it was made — in one concise sentence. Use \
        only what the summary supports; if the reason isn't stated, infer the most \
        likely one briefly. Return ONLY a JSON array of strings, one per decision, \
        in the same order. No prose, no keys.

        Meeting summary:
        \(summary.prefix(6000))

        Decisions:
        \(numbered)
        """
        guard let raw = try? await summarizer.generate(prompt: prompt, temperature: 0.1),
              let rationales = Self.parseRationaleArray(raw), !rationales.isEmpty else { return }

        var changed = false
        for (i, target) in targets.enumerated() where i < rationales.count {
            let r = rationales[i].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !r.isEmpty, let idx = decisions.firstIndex(where: { $0.id == target.id }) else { continue }
            decisions[idx].rationale = r
            VaultIndexService.shared.indexDecision(decisions[idx])
            changed = true
        }
        if changed { save() }
    }

    /// Extract a JSON array of strings from a model response, tolerating code
    /// fences and surrounding prose.
    static func parseRationaleArray(_ raw: String) -> [String]? {
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]"), start < end else { return nil }
        let slice = String(raw[start...end])
        guard let data = slice.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return arr
    }

    // MARK: - Manual decisions (project / task / initiative)

    /// Log a decision by hand and attach it to a project, task, and/or
    /// initiative. Manual decisions carry a `manual::` id and a nil meetingID,
    /// so the meeting auto-extraction pipeline never touches them.
    @discardableResult
    func addManual(text: String,
                   rationale: String? = nil,
                   projectID: String? = nil,
                   taskID: String? = nil,
                   initiativeID: String? = nil) -> Decision {
        let d = Decision(
            id: "manual::\(UUID().uuidString)",
            meetingID: nil,
            meetingTitle: nil,
            date: Date(),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            rationale: rationale,
            projectID: projectID,
            taskID: taskID,
            initiativeID: initiativeID,
            origin: .manual,
            status: .open)
        decisions.insert(d, at: 0)
        decisions.sort { $0.date > $1.date }
        save()
        VaultIndexService.shared.indexDecision(d)
        return d
    }

    /// Mutate one decision in place, persist, and reindex.
    private func update(_ id: String, _ mutate: (inout Decision) -> Void) {
        guard let i = decisions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&decisions[i])
        save()
        VaultIndexService.shared.indexDecision(decisions[i])
    }

    func setStatus(_ id: String, _ status: DecisionStatus) {
        update(id) { $0.status = status }
    }

    func setRevisit(_ id: String, _ date: Date?) {
        update(id) { $0.revisitDate = date }
    }

    func setText(_ id: String, text: String, rationale: String? = nil) {
        update(id) {
            $0.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let rationale { $0.rationale = rationale }
        }
    }

    /// Re-attach a decision. Each parameter is a *double* optional: omit it to
    /// leave the link unchanged, pass `.some(nil)` to clear it, pass `.some(id)`
    /// to set it.
    func link(_ id: String,
              projectID: String?? = nil,
              taskID: String?? = nil,
              initiativeID: String?? = nil) {
        update(id) {
            if let projectID { $0.projectID = projectID }
            if let taskID { $0.taskID = taskID }
            if let initiativeID { $0.initiativeID = initiativeID }
        }
    }

    func delete(_ id: String) {
        guard decisions.contains(where: { $0.id == id }) else { return }
        decisions.removeAll { $0.id == id }
        save()
        VaultIndexService.shared.removeFromIndex(entityID: id, entityKind: "decision")
    }

    // MARK: - Queries

    func decisions(forProject id: String) -> [Decision] {
        decisions.filter { $0.projectID == id }
    }

    func decisions(forTask id: String) -> [Decision] {
        decisions.filter { $0.taskID == id }
    }

    func decisions(forInitiative id: String) -> [Decision] {
        decisions.filter { $0.initiativeID == id }
    }

    /// Pull the bulleted lines under a "## Key Decisions" (or "## Decisions")
    /// heading, dropping the "None." placeholder.
    static func parseDecisions(from summary: String) -> [String] {
        var inSection = false
        var out: [String] = []
        for raw in summary.components(separatedBy: .newlines) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") {
                let lower = t.lowercased()
                inSection = lower.contains("key decision") || lower.hasSuffix("decisions")
                continue
            }
            guard inSection else { continue }
            if t.hasPrefix("- ") || t.hasPrefix("* ") {
                let txt = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let low = txt.lowercased()
                if !txt.isEmpty, low != "none.", low != "none" { out.append(txt) }
            }
        }
        return out
    }
}
