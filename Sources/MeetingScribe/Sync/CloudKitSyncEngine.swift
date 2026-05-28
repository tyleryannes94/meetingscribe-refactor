import Foundation
import CloudKit

/// iCloud sync engine (STUB).
///
/// The real implementation will be built on `CKSyncEngine` (macOS 15+), which
/// handles the change-token bookkeeping, batching, and conflict plumbing that
/// we'd otherwise hand-roll on top of `CKDatabase` operations. Until we raise
/// the deployment target and wire it up, this is an inert actor that just
/// tracks status so the Settings UI and call sites can be built against a
/// stable shape.
///
/// Design intent (for when this is implemented):
///   • One `CKSyncEngine` over the private database, custom zone "MeetingScribe".
///   • Records: meetings, action items, projects, people, encounters.
///   • `CKSyncEngineDelegate` maps fetched changes → local stores and local
///     mutations → `CKSyncEngine.State.Serialization` we persist alongside the
///     data so we resume from the right change token after a relaunch.
actor CloudKitSyncEngine {

    private(set) var status: SyncStatus = .idle
    private var running = false

    /// Whether the user has opted into iCloud sync (mirrors the Settings toggle).
    private let containerIdentifier: String

    init(containerIdentifier: String = "iCloud.com.tyleryannes.MeetingScribe") {
        self.containerIdentifier = containerIdentifier
    }

    /// Begin syncing. No-op stub today.
    func startSync() async {
        guard !running else { return }
        running = true
        status = .syncing
        // TODO(CKSyncEngine): construct CKSyncEngine with our saved state
        // serialization, register the delegate, and kick a first fetch.
        // For now we immediately report "up to date" so the UI has a terminal
        // state to show rather than spinning forever.
        status = .upToDate
    }

    /// Stop syncing and tear down the engine. No-op stub today.
    func stopSync() async {
        running = false
        status = .idle
        // TODO(CKSyncEngine): cancel in-flight operations and release the engine.
    }

    /// Force a fetch/push cycle. No-op stub today.
    func syncNow() async {
        guard running else { return }
        // TODO(CKSyncEngine): call sendChanges()/fetchChanges() on the engine.
    }

    /// Quick check that an iCloud account is available before we offer sync.
    /// Real implementation should also surface restricted/no-account states.
    func accountIsAvailable() async -> Bool {
        let status = try? await CKContainer(identifier: containerIdentifier).accountStatus()
        return status == .available
    }
}
