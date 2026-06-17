import Foundation
import VaultKit
import OSLog

/// Lifecycle state of a decision (P0-E). A decision starts `open`; a later
/// decision can `supersede` it, or it can be `resolved` once acted on.
enum DecisionStatus: String, Codable, CaseIterable, Hashable {
    case open
    case superseded
    case resolved
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
    var meetingID: String
    var meetingTitle: String
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
    /// Lifecycle state.
    var status: DecisionStatus
    /// When to revisit this decision, if ever.
    var revisitDate: Date?

    init(id: String,
         meetingID: String,
         meetingTitle: String,
         date: Date,
         text: String,
         rationale: String? = nil,
         personIDs: [String] = [],
         projectID: String? = nil,
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
        self.status = status
        self.revisitDate = revisitDate
    }
}

extension Decision {
    /// Custom decode so legacy records (and the v1 schema, which had only
    /// id/meetingID/meetingTitle/date/text) load without throwing on the new
    /// keys. Kept in an extension so the memberwise initializer above survives.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        meetingID = try c.decode(String.self, forKey: .meetingID)
        meetingTitle = try c.decode(String.self, forKey: .meetingTitle)
        date = try c.decode(Date.self, forKey: .date)
        text = try c.decode(String.self, forKey: .text)
        rationale = try c.decodeIfPresent(String.self, forKey: .rationale)
        personIDs = try c.decodeIfPresent([String].self, forKey: .personIDs) ?? []
        projectID = try c.decodeIfPresent(String.self, forKey: .projectID)
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

    /// On-disk schema version (P0-E). Bumped from the implicit v1 (raw array,
    /// minimal struct) to v2 (enriched struct, enveloped).
    static let schemaVersion = 2

    private var fileURL: URL { AppSettings.shared.storageDir.appendingPathComponent("decisions.json") }

    init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoded: [Decision]
        do {
            decoded = try SchemaEnvelope.decode([Decision].self, from: data,
                                                currentVersion: Self.schemaVersion,
                                                migrate: DecisionSchemaMigrations.decisions)
        } catch {
            log.error("Failed to decode decisions.json: \(error.localizedDescription, privacy: .public)")
            return
        }
        decisions = decoded.sorted { $0.date > $1.date }
    }

    private func save() {
        let env = SchemaEnvelope(version: Self.schemaVersion, data: decisions)
        guard let data = try? SharedCoders.encoder(pretty: true, sorted: true).encode(env) else { return }
        try? data.write(to: fileURL, options: .atomic)
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
