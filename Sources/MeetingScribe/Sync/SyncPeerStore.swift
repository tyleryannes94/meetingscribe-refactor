import Foundation
import Combine

/// Persists `SyncPeer` records and exposes a Published list so the Settings
/// UI re-renders when peers change. Same on-disk pattern as `AccountStore`:
/// `<storageDir>/sync-peers.json`, atomic writes, eager reload on init.
@MainActor
final class SyncPeerStore: ObservableObject {
    static let shared = SyncPeerStore()

    @Published private(set) var peers: [SyncPeer] = []

    private var fileURL: URL {
        AppSettings.shared.storageDir.appendingPathComponent("sync-peers.json")
    }

    private init() { load() }

    /// Force a re-read from disk — used by tests that need to swap the
    /// underlying `storageDir` between cases.
    func reloadFromDisk() { load() }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            peers = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(SyncPeersFile.self, from: data) else {
            // Corrupt file — fail closed so we don't accidentally overwrite a
            // valid peer config with empty data. Surface in logs only; the
            // user can repair via Settings.
            peers = []
            return
        }
        peers = file.peers
    }

    private func persist() {
        let file = SyncPeersFile(version: SyncPeersFile.currentVersion, peers: peers)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - CRUD

    /// True when no peers exist yet — Settings shows an empty-state nudge.
    var isEmpty: Bool { peers.isEmpty }

    @discardableResult
    func addPeer(label: String, baseURL: String, sharedSecret: String? = nil) -> SyncPeer? {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty,
              !trimmedURL.isEmpty,
              URL(string: trimmedURL) != nil else { return nil }
        let peer = SyncPeer(
            id: UUID().uuidString,
            label: trimmedLabel,
            baseURL: trimmedURL,
            sharedSecret: sharedSecret ?? SyncPeer.newSecret(),
            lastPullAt: nil,
            lastPushAt: nil,
            lastSyncAt: nil,
            lastError: nil)
        peers.append(peer)
        persist()
        return peer
    }

    func deletePeer(id: String) {
        peers.removeAll { $0.id == id }
        persist()
    }

    func updatePeer(_ updated: SyncPeer) {
        guard let idx = peers.firstIndex(where: { $0.id == updated.id }) else { return }
        peers[idx] = updated
        persist()
    }

    /// True iff `secret` matches a configured peer's shared secret in
    /// constant time. Lets the server side accept incoming sync requests
    /// from a peer that holds the secret without enumerating peers in
    /// log output.
    func peerForIncomingSecret(_ secret: String) -> SyncPeer? {
        for peer in peers where SyncPeer.constantTimeEqual(peer.sharedSecret, secret) {
            return peer
        }
        return nil
    }
}
