import Foundation
import Combine
import OSLog

/// Orchestrates a single round-trip with one peer: pull remote changes since
/// our last successful pull, then push local changes since our last successful
/// push. Last-write-wins per file by `mtime` — the same model the master plan
/// (`docs/CROSS_DEVICE_SYNC_MASTER_PLAN.md`) lays out for the additive merge
/// engine, but for plain user files instead of model-aware merges.
///
/// Not auto-scheduled by this PR — Settings drives it via "Sync now". A timer
/// is a follow-up.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "SyncEngine")
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 600
        return URLSession(configuration: cfg)
    }()

    /// Per-peer in-flight gate so two manual "Sync now" taps don't race.
    @Published private(set) var runningPeerIDs: Set<String> = []

    private init() {}

    /// Run one full round-trip with `peer`. Pulls first (cheap reads), then
    /// pushes any local mutations. Updates the peer's `lastPullAt` /
    /// `lastPushAt` / `lastSyncAt` / `lastError` and persists them.
    func syncNow(peerID: String) async {
        guard !runningPeerIDs.contains(peerID) else { return }
        runningPeerIDs.insert(peerID)
        defer { runningPeerIDs.remove(peerID) }

        let store = SyncPeerStore.shared
        guard var peer = store.peers.first(where: { $0.id == peerID }) else { return }

        var localError: String?
        let vaultRoot = AppSettings.shared.storageDir

        // Pull
        do {
            let pulled = try await pull(from: peer, into: vaultRoot)
            peer.lastPullAt = Date()
            log.info("Pulled \(pulled, privacy: .public) file(s) from \(peer.label, privacy: .public)")
        } catch {
            localError = "Pull failed: \(error.localizedDescription)"
            log.error("Pull failed: \(error.localizedDescription, privacy: .public)")
        }

        // Push — even if pull failed, attempt push so a half-success still
        // makes forward progress on one direction.
        do {
            let pushed = try await push(to: peer, from: vaultRoot)
            peer.lastPushAt = Date()
            log.info("Pushed \(pushed, privacy: .public) file(s) to \(peer.label, privacy: .public)")
        } catch {
            let msg = "Push failed: \(error.localizedDescription)"
            localError = localError.map { "\($0); \(msg)" } ?? msg
            log.error("Push failed: \(error.localizedDescription, privacy: .public)")
        }

        peer.lastError = localError
        if localError == nil { peer.lastSyncAt = Date() }
        store.updatePeer(peer)
    }

    // MARK: - Pull

    private func pull(from peer: SyncPeer, into vaultRoot: URL) async throws -> Int {
        // 1) Ask the peer what changed since our last pull.
        let since = peer.lastPullAt
        let remoteEntries = try await fetchChanges(from: peer, since: since)

        // 2) For each remote entry that is genuinely newer than what we have
        //    locally, download it. Last-write-wins: if local is newer we skip.
        var downloaded = 0
        for entry in remoteEntries {
            let absURL = SyncIndex.absoluteURL(forRelative: entry.path, under: vaultRoot)
            guard let absURL else { continue }
            if let localValues = try? absURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let localMTime = localValues.contentModificationDate,
               localMTime >= entry.mtime {
                continue   // local is at least as new — leave it alone
            }
            try await fetchAndWrite(entry, peer: peer, into: absURL)
            downloaded += 1
        }
        return downloaded
    }

    private func fetchChanges(from peer: SyncPeer, since: Date?) async throws -> [SyncIndex.Entry] {
        var comps = URLComponents(string: peer.baseURL + "/api/sync/changes")
        if let since {
            let df = ISO8601DateFormatter()
            df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            comps?.queryItems = [URLQueryItem(name: "since", value: df.string(from: since))]
        }
        guard let url = comps?.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(peer.sharedSecret)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        try Self.assertOK(response, data: data)
        struct Reply: Decodable { let entries: [SyncIndex.Entry] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Reply.self, from: data).entries) ?? []
    }

    private func fetchAndWrite(_ entry: SyncIndex.Entry,
                               peer: SyncPeer,
                               into absURL: URL) async throws {
        var comps = URLComponents(string: peer.baseURL + "/api/sync/file")
        comps?.queryItems = [URLQueryItem(name: "path", value: entry.path)]
        guard let url = comps?.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(peer.sharedSecret)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        try Self.assertOK(response, data: data)
        try FileManager.default.createDirectory(at: absURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // Write atomically so a power loss mid-write doesn't leave a half file.
        try data.write(to: absURL, options: .atomic)
        // Stamp the file's mtime so subsequent runs see the authoritative
        // remote mtime rather than our local clock.
        try FileManager.default.setAttributes(
            [.modificationDate: entry.mtime], ofItemAtPath: absURL.path)
    }

    // MARK: - Push

    private func push(to peer: SyncPeer, from vaultRoot: URL) async throws -> Int {
        let since = peer.lastPushAt
        let localChanges = SyncIndex.entries(under: vaultRoot, since: since)
        // Ask the peer for the SAME window so we know its file mtimes for the
        // last-write-wins compare. We still send anything strictly newer.
        let remote = try await fetchChanges(from: peer, since: since)
        let remoteByPath = Dictionary(uniqueKeysWithValues: remote.map { ($0.path, $0) })

        var uploaded = 0
        for entry in localChanges {
            if let remoteEntry = remoteByPath[entry.path], remoteEntry.mtime >= entry.mtime {
                continue   // remote is at least as new — let pull handle it
            }
            try await uploadFile(entry, peer: peer, vaultRoot: vaultRoot)
            uploaded += 1
        }
        return uploaded
    }

    private func uploadFile(_ entry: SyncIndex.Entry, peer: SyncPeer, vaultRoot: URL) async throws {
        guard let absURL = SyncIndex.absoluteURL(forRelative: entry.path, under: vaultRoot) else {
            return
        }
        let data = try Data(contentsOf: absURL)
        var comps = URLComponents(string: peer.baseURL + "/api/sync/file")
        comps?.queryItems = [URLQueryItem(name: "path", value: entry.path)]
        guard let url = comps?.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(peer.sharedSecret)", forHTTPHeaderField: "Authorization")
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        req.setValue(df.string(from: entry.mtime), forHTTPHeaderField: "X-MS-Mtime")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (respData, response) = try await session.upload(for: req, from: data)
        try Self.assertOK(response, data: respData)
    }

    // MARK: -

    private static func assertOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "SyncEngine", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(msg.prefix(200))"])
        }
    }
}
