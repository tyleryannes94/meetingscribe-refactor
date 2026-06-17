import Foundation
import OSLog

/// The app-wide second-brain index (P0-A / audit C-3, C-4).
///
/// `SecondBrainDB` — the SQLite + FTS5 + embeddings layer that powers every AI
/// recall feature — used to be a `private let` owned by `PeopleStore`. That made
/// the entire index structurally invisible to every *other* store: decisions and
/// tasks could never be embedded, full-text searched, or surfaced by the chat
/// assistant, because nothing outside `PeopleStore` could reach the database.
///
/// This service lifts the database out into a single shared owner so any store
/// can index its entities into the same vault. `PeopleStore` keeps its
/// person-specific indexing logic (it is still the right owner of *what* a person
/// row contains) but now talks to `VaultIndexService.shared` instead of a private
/// instance. New stores (`ActionItemStore`, `DecisionStore`, encounters) call the
/// high-level `index*` entry points below.
///
/// The forwarding methods deliberately mirror `SecondBrainDB`'s signatures so the
/// migration is a one-line change at each existing owner rather than a rewrite of
/// every call site.
@available(macOS 14.0, *)
@MainActor
final class VaultIndexService {
    static let shared = VaultIndexService()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "VaultIndex")

    /// The one and only second-brain database for the process.
    private let db = SecondBrainDB()

    private init() {}

    // MARK: - Rebuild / corruption recovery (owned by PeopleStore today)

    /// True when the derived index failed `quick_check` on open and was recreated
    /// empty; the owner repopulates from canonical JSON via `rebuild`.
    var needsRebuild: Bool { db.needsRebuild }
    func clearNeedsRebuild() { db.clearNeedsRebuild() }

    func rebuild(people: [Person], encounters: [Encounter], tagName: (String) -> String?) {
        db.rebuild(people: people, encounters: encounters, tagName: tagName)
    }

    // MARK: - Person index (forwarded)

    func upsertPerson(_ p: Person, encounterCount: Int, tagName: (String) -> String?) {
        db.upsertPerson(p, encounterCount: encounterCount, tagName: tagName)
    }
    func deletePerson(_ id: String) { db.deletePerson(id) }
    func searchPersonIDs(_ query: String) -> [String] { db.searchPersonIDs(query) }

    // MARK: - Vault content (forwarded)

    func upsertVaultContent(entityID: String, entityKind: String, title: String?,
                            body: String?, dateEpoch: Int64?, tags: String?) {
        db.upsertVaultContent(entityID: entityID, entityKind: entityKind, title: title,
                              body: body, dateEpoch: dateEpoch, tags: tags)
    }
    func deleteVaultContent(entityID: String, entityKind: String) {
        db.deleteVaultContent(entityID: entityID, entityKind: entityKind)
    }
    func searchAll(query: String, limit: Int = 50) -> [VaultSearchResult] {
        db.searchAll(query: query, limit: limit)
    }
    func vaultContentCount(kind: String) -> Int { db.vaultContentCount(kind: kind) }
    func vaultContentMeta(entityID: String, entityKind: String) -> (title: String?, dateEpoch: Int64?)? {
        db.vaultContentMeta(entityID: entityID, entityKind: entityKind)
    }

    // MARK: - Embeddings (forwarded)

    func upsertEmbedding(entityID: String, entityKind: String, vector: [Float]) {
        db.upsertEmbedding(entityID: entityID, entityKind: entityKind, vector: vector)
    }
    func deleteEmbedding(entityID: String, entityKind: String) {
        db.deleteEmbedding(entityID: entityID, entityKind: entityKind)
    }
    func allEmbeddings() -> [(entityID: String, entityKind: String, vector: [Float])] {
        db.allEmbeddings()
    }
    func embeddedEntityIDs(kind: String) -> Set<String> { db.embeddedEntityIDs(kind: kind) }
    func relatedMeetings(toID id: String, limit: Int = 5, minScore: Float = 0.45) -> [(id: String, score: Float)] {
        db.relatedMeetings(toID: id, limit: limit, minScore: minScore)
    }

    /// Compute + store an embedding for already-indexed content. No-op when the
    /// embedding model / Ollama isn't available (recall just stays lexical).
    func embedAndStore(entityID: String, entityKind: String, text: String) async {
        guard let vec = await EmbeddingService.embed(text) else { return }
        db.upsertEmbedding(entityID: entityID, entityKind: entityKind, vector: vec)
    }

    // MARK: - High-level entry points (NEW — the point of the extraction)

    /// Index a meeting into the vault so search + recall can find it. The
    /// embedding is computed separately (fire-and-forget) by the caller.
    func indexMeeting(_ meeting: Meeting, summary: String, tags: String?) {
        db.upsertVaultContent(entityID: meeting.id, entityKind: "meeting",
                              title: meeting.displayTitle,
                              body: summary.isEmpty ? nil : summary,
                              dateEpoch: Int64(meeting.startDate.timeIntervalSince1970),
                              tags: tags)
    }

    /// Index a voice note into the vault.
    func indexVoiceNote(id: String, title: String, transcript: String?, createdAt: Date) {
        db.upsertVaultContent(entityID: id, entityKind: "voice_note",
                              title: title, body: transcript,
                              dateEpoch: Int64(createdAt.timeIntervalSince1970), tags: nil)
    }

    /// Index (or, when soft-deleted, de-index) an action item, and materialize
    /// its person/project join edges (P0-F). Tasks are the highest-frequency
    /// writes and were entirely dark to AI recall before this. FTS only here —
    /// embeddings for tasks land in Phase 1 (1-A).
    func indexTask(_ item: ActionItem) {
        guard item.deletedAt == nil else {
            removeFromIndex(entityID: item.id, entityKind: "action_item")
            db.removeTaskPersons(taskID: item.id)
            return
        }
        let body = [item.title, item.notes ?? "", item.owner ?? ""]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        db.upsertVaultContent(entityID: item.id, entityKind: "action_item",
                              title: item.title, body: body,
                              dateEpoch: Int64(item.meetingDate.timeIntervalSince1970),
                              tags: nil)
        // P0-F: person → task and person → project reverse edges.
        db.removeTaskPersons(taskID: item.id)
        if let pid = item.ownerPersonID {
            db.upsertTaskPerson(taskID: item.id, personID: pid, role: "owner")
            if let projectID = item.projectID {
                db.upsertPersonProject(personID: pid, projectID: projectID)
            }
        }
    }

    /// Index a decision (title + rationale) into the vault. Requires the v4
    /// schema, which drops the old `entity_kind` CHECK constraint that previously
    /// rejected any kind outside the original five.
    func indexDecision(_ decision: Decision) {
        let body = [decision.text, decision.rationale ?? ""]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        db.upsertVaultContent(entityID: decision.id, entityKind: "decision",
                              title: decision.text, body: body,
                              dateEpoch: Int64(decision.date.timeIntervalSince1970),
                              tags: nil)
        // P0-F: materialize the decision → person edge (populated once the
        // post-meeting pipeline cross-links attendees in Phase 3).
        db.setDecisionPersons(decisionID: decision.id, personIDs: decision.personIDs)
    }

    /// Index an encounter ("I met this person here"). `personName` is folded into
    /// the title so a search for the person surfaces the encounter.
    func indexEncounter(_ encounter: Encounter, personName: String? = nil) {
        let title = personName.map { "\($0) — \(encounter.eventName)" } ?? encounter.eventName
        let body = [encounter.eventName, encounter.notes, encounter.location ?? ""]
            .filter { !$0.isEmpty }.joined(separator: "\n")
        db.upsertVaultContent(entityID: encounter.id, entityKind: "encounter",
                              title: title, body: body,
                              dateEpoch: Int64(encounter.date.timeIntervalSince1970),
                              tags: nil)
    }

    /// Remove an entity from both the FTS index and the embedding store.
    func removeFromIndex(entityID: String, entityKind: String) {
        db.deleteVaultContent(entityID: entityID, entityKind: entityKind)
        db.deleteEmbedding(entityID: entityID, entityKind: entityKind)
    }

    // MARK: - Cross-entity join tables (P0-F, forwarded)

    /// Replace the resolved-attendee rows for a meeting (idempotent on re-finalize).
    func setMeetingPersons(meetingID: String, personRoles: [(personID: String, role: String?)]) {
        db.setMeetingPersons(meetingID: meetingID, personRoles: personRoles)
    }

    /// O(log n) person edges, powering per-person commitment ledgers, backlinks,
    /// and the relational context strip (Phases 2/4/5).
    func personsForMeeting(_ meetingID: String) -> [String] { db.personsForMeeting(meetingID) }
    func decisionsForPerson(_ personID: String) -> [String] { db.decisionsForPerson(personID) }
    func projectsForPerson(_ personID: String) -> [String] { db.projectsForPerson(personID) }
    func tasksForPerson(_ personID: String) -> [String] { db.tasksForPerson(personID) }
}
