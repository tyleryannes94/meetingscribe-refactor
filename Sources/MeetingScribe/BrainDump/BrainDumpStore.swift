import Foundation
import SwiftUI
import VaultKit
import OSLog

/// Persists Brain Dump sessions to `<storageDir>/brain_dump_sessions.json` and
/// publishes them for SwiftUI. Mirrors `ActionItemStore`'s shape: a single
/// `@MainActor ObservableObject`, off-main hydration on init, debounced writes
/// through the shared `TaskPersistenceCoordinator`.
///
/// Also listens for `DarwinNotifier.vaultChanged` so a session created from
/// outside the app — the `submit_brain_dump` MCP tool, the CLI sync helper —
/// shows up live in the running UI without a relaunch.
@MainActor
final class BrainDumpStore: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "BrainDump")

    /// All sessions (non-archived first, then archived). The picker filters
    /// these into recent / archived buckets.
    @Published private(set) var sessions: [BrainDumpSession] = []

    /// Currently focused session in the UI. Persisted as a UserDefaults
    /// preference so a relaunch lands you where you were.
    @Published var activeSessionID: String? {
        didSet {
            guard activeSessionID != oldValue else { return }
            AppSettings.shared.lastBrainDumpSessionID = activeSessionID
        }
    }

    /// True until the initial off-main decode finishes publishing. Lets
    /// SwiftUI show a skeleton instead of "empty state" during the first
    /// fraction of a second after launch.
    @Published private(set) var isLoaded = false

    private var fileURL: URL {
        AppSettings.shared.storageDir.appendingPathComponent("brain_dump_sessions.json")
    }

    private var loadTask: Task<Void, Never>?

    init() {
        // Off-main hydration matches the ActionItemStore pattern — JSON decode
        // of dozens of small sessions is fast, but we still don't want to block
        // first paint behind it.
        let url = fileURL
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            let decoded = Self.loadFromDisk(at: url)
            await MainActor.run {
                guard let self else { return }
                self.sessions = decoded
                self.isLoaded = true
                // Restore the last active session if it still exists.
                if let last = AppSettings.shared.lastBrainDumpSessionID,
                   self.sessions.contains(where: { $0.id == last }) {
                    self.activeSessionID = last
                } else {
                    self.activeSessionID = self.sessions
                        .filter { $0.state != .archived }
                        .first?.id
                }
            }
        }

        // Reload on outside writes (MCP, CLI sync). Observer is process-lived,
        // matching how MeetingManager / PeopleStore observe vaultChanged.
        DarwinNotifier.observe(DarwinNotifier.vaultChanged) { [weak self] in
            Task { @MainActor in self?.reloadFromDisk() }
        }
    }

    /// Test/UI helper: await the initial off-main decode. Mirrors
    /// `ActionItemStore.awaitInitialLoad`.
    func awaitInitialLoad() async {
        await loadTask?.value
    }

    // MARK: - Disk I/O

    private static func loadFromDisk(at url: URL) -> [BrainDumpSession] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(BrainDumpSessionEnvelope.self, from: data)
            return BrainDumpSchemaMigrations.migrate(envelope: envelope).data
        } catch {
            // Fall back to the .bak file if the live file is corrupt — matches
            // how TaskPersistenceCoordinator's `.bak` write-ahead is meant to
            // be consumed.
            let backup = url.appendingPathExtension("bak")
            guard FileManager.default.fileExists(atPath: backup.path),
                  let data = try? Data(contentsOf: backup) else {
                return []
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let envelope = try? decoder.decode(BrainDumpSessionEnvelope.self, from: data) {
                return BrainDumpSchemaMigrations.migrate(envelope: envelope).data
            }
            return []
        }
    }

    private func reloadFromDisk() {
        let url = fileURL
        Task.detached(priority: .userInitiated) { [weak self] in
            let decoded = Self.loadFromDisk(at: url)
            await MainActor.run {
                guard let self else { return }
                // Only update if something actually changed — avoids spurious
                // SwiftUI rebuilds on every vaultChanged ping.
                guard self.sessions != decoded else { return }
                self.sessions = decoded
            }
        }
    }

    private func persistDebounced() {
        let envelope = BrainDumpSessionEnvelope(
            schemaVersion: BrainDumpSchemaMigrations.currentVersion,
            data: sessions
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(envelope)
            TaskPersistenceCoordinator.shared.write(data, to: fileURL)
        } catch {
            log.error("brain dump encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Lookups

    func session(_ id: String) -> BrainDumpSession? {
        sessions.first { $0.id == id }
    }

    var activeSession: BrainDumpSession? {
        guard let id = activeSessionID else { return nil }
        return session(id)
    }

    /// Sessions to show in the picker, newest first. Excludes archived by
    /// default so a years-old draft doesn't crowd the menu.
    func recentSessions(includingArchived: Bool = false, limit: Int = 20) -> [BrainDumpSession] {
        sessions
            .filter { includingArchived || $0.state != .archived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Mutations

    @discardableResult
    func createSession(title: String? = nil,
                       body: String = "",
                       sources: [BrainDumpSource] = [],
                       originContextID: String? = nil) -> BrainDumpSession {
        let session = BrainDumpSession(
            title: title,
            body: body,
            sources: sources,
            originContextID: originContextID
        )
        sessions.insert(session, at: 0)
        activeSessionID = session.id
        persistDebounced()
        SecondBrainEventBus.shared.publish(.brainDumpSessionCreated(sessionID: session.id))
        return session
    }

    /// Update the composer body. Bumps `updatedAt` and persists debounced.
    /// Lifecycle state transitions back to `.draft` if the user resumes typing
    /// on an archived/reviewing session — they're clearly working again.
    func updateBody(_ id: String, _ text: String) {
        mutate(id) { s in
            s.body = text
            if s.state == .archived { s.state = .draft }
        }
    }

    func setTitle(_ id: String, _ title: String?) {
        mutate(id) { $0.title = title?.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func setState(_ id: String, _ state: BrainDumpSession.SessionState) {
        mutate(id) { $0.state = state }
    }

    func setOriginContext(_ id: String, _ contextID: String?) {
        mutate(id) { $0.originContextID = contextID }
    }

    func setLinkedProjects(_ id: String, _ projectIDs: [String]) {
        mutate(id) { $0.linkedProjectIDs = projectIDs }
    }

    // MARK: - Sources

    func attachSource(_ sessionID: String, _ source: BrainDumpSource) {
        mutate(sessionID) { s in
            // Dedup by id so an inline retry of a URL fetch replaces the
            // loading placeholder instead of stacking up.
            if let idx = s.sources.firstIndex(where: { $0.id == source.id }) {
                s.sources[idx] = source
            } else {
                s.sources.append(source)
            }
        }
    }

    func removeSource(_ sessionID: String, sourceID: String) {
        mutate(sessionID) { s in
            s.sources.removeAll { $0.id == sourceID }
        }
    }

    // MARK: - Drafts

    func appendDraft(_ sessionID: String, _ draft: BrainDumpDraft) {
        mutate(sessionID) { s in
            s.drafts.append(draft)
            if s.state == .draft { s.state = .reviewing }
        }
    }

    func replaceDrafts(_ sessionID: String, _ drafts: [BrainDumpDraft]) {
        mutate(sessionID) { s in
            s.drafts = drafts
            s.state = drafts.isEmpty ? .draft : .reviewing
        }
    }

    func updateDraft(_ sessionID: String, _ draftID: UUID, _ transform: (inout BrainDumpDraft) -> Void) {
        mutate(sessionID) { s in
            guard let i = s.drafts.firstIndex(where: { $0.id == draftID }) else { return }
            transform(&s.drafts[i])
        }
    }

    func setDraftState(_ sessionID: String, _ draftID: UUID, _ newState: DraftState) {
        updateDraft(sessionID, draftID) { draft in
            switch draft {
            case .task(var t):
                t.state = newState
                draft = .task(t)
            case .calendarBlock(var b):
                b.state = newState
                draft = .calendarBlock(b)
            }
        }
    }

    // MARK: - Whole-session

    func archive(_ id: String) {
        mutate(id) { $0.state = .archived }
    }

    func deleteSession(_ id: String) {
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = sessions.first { $0.state != .archived }?.id
        }
        persistDebounced()
    }

    // MARK: - Internal mutate helper

    private func mutate(_ id: String, _ transform: (inout BrainDumpSession) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        var s = sessions[idx]
        transform(&s)
        s.updatedAt = Date()
        sessions[idx] = s
        persistDebounced()
        SecondBrainEventBus.shared.publish(.brainDumpUpdated(sessionID: id))
    }
}
