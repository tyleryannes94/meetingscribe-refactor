import Foundation
import VaultKit

/// One recorded mutation in the Projects/Tasks data plane (P1 / BE-5).
///
/// The change log is the append-only seam the rest of the roadmap reads:
/// undo/redo (BE-6), conflict-free cross-device sync (BE-8, via the
/// `lamport`/`deviceID` ordering), and the automation/rules engine (BE-12).
/// It records *history* and does not change current-state behaviour, so it is
/// safe to land additively ahead of those consumers.
struct TaskChangeEvent: Codable, Identifiable, Hashable, Sendable {
    enum Entity: String, Codable, Sendable { case task, project, section, label, initiative }
    enum Op: String, Codable, Sendable { case create, update, delete, restore, merge }

    var id: String = UUID().uuidString
    var entity: Entity
    var entityID: String
    var op: Op
    /// Short human-readable description, e.g. "status → completed".
    var summary: String
    /// Monotonic per-device counter — the causal-ordering seed a future sync
    /// resolver (BE-8) uses for deterministic last-writer-per-field merges.
    var lamport: Int
    /// Stable per-install id, so events from different devices are
    /// distinguishable once sync exists.
    var deviceID: String
    var timestamp: Date = Date()
}

/// In-memory + on-disk journal of task mutations. Keeps a bounded tail in
/// memory (`recent`) for an activity view and ordering, and persists it through
/// the off-main coordinator so logging never blocks the UI. Bounded by design —
/// the file stays small regardless of how long the app runs.
@MainActor
final class TaskChangeLog: ObservableObject {
    static let shared = TaskChangeLog()

    /// Newest-last bounded tail of recorded events.
    @Published private(set) var recent: [TaskChangeEvent] = []

    /// Max events retained (memory + disk). Old events fall off the front.
    private let cap = 500
    private static let schemaVersion = 1

    private let deviceID: String
    private var lamport: Int

    private var url: URL {
        AppSettings.shared.storageDir.appendingPathComponent("task_changes.json")
    }
    private var loadTask: Task<Void, Never>?

    init() {
        // Stable per-install identifiers, persisted in UserDefaults.
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "tasks.deviceID") {
            deviceID = existing
        } else {
            let new = UUID().uuidString
            defaults.set(new, forKey: "tasks.deviceID")
            deviceID = new
        }
        lamport = defaults.integer(forKey: "tasks.lamport")

        let url = self.url
        loadTask = Task.detached(priority: .utility) { [weak self] in
            let events: [TaskChangeEvent] = Self.decode(url)
            await MainActor.run {
                guard let self else { return }
                self.recent = Array(events.suffix(self.cap))
                // Keep the counter monotonic across launches even if UserDefaults
                // lagged behind the persisted log.
                self.lamport = max(self.lamport, events.last?.lamport ?? 0)
            }
        }
    }

    /// Test/seam hook: await the off-main initial load.
    func awaitInitialLoad() async { await loadTask?.value }

    nonisolated private static func decode(_ url: URL) -> [TaskChangeEvent] {
        guard let data = try? Data(contentsOf: url),
              let arr: [TaskChangeEvent] = try? SchemaEnvelope.decode(
                [TaskChangeEvent].self, from: data,
                currentVersion: schemaVersion,
                decoder: SharedCoders.decoder())
        else { return [] }
        return arr
    }

    /// Record a mutation. Bumps the Lamport clock, appends to the bounded tail,
    /// and persists off-main. Returns the recorded event (useful for tests).
    @discardableResult
    func record(_ op: TaskChangeEvent.Op, entity: TaskChangeEvent.Entity,
                id: String, summary: String) -> TaskChangeEvent {
        lamport += 1
        UserDefaults.standard.set(lamport, forKey: "tasks.lamport")
        let event = TaskChangeEvent(entity: entity, entityID: id, op: op,
                                    summary: summary, lamport: lamport, deviceID: deviceID)
        recent.append(event)
        if recent.count > cap { recent.removeFirst(recent.count - cap) }
        persist()
        return event
    }

    private func persist() {
        do {
            let env = SchemaEnvelope(version: Self.schemaVersion, data: recent)
            let data = try SharedCoders.encoder(pretty: false, sorted: false).encode(env)
            TaskPersistenceCoordinator.shared.write(data, to: url)
        } catch {
            // The log is best-effort; a failure here must never break a mutation.
        }
    }
}
