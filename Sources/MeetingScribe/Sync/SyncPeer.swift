import Foundation

/// A configured peer this Mac syncs with. Lives in
/// `<storageDir>/sync-peers.json` alongside the rest of the vault. Each peer
/// has a randomly generated shared secret used for the dedicated `/api/sync/*`
/// auth path — separate from the per-user account sessions so a sync token
/// can't accidentally be reused to log into the UI.
struct SyncPeer: Codable, Identifiable, Equatable {
    let id: String
    /// Human label shown in Settings ("Work MacBook").
    var label: String
    /// `http://100.x.y.z:8765` — Tailscale IP preferred; LAN works too. The
    /// engine appends `/api/sync/...` paths to this.
    var baseURL: String
    /// Random shared secret presented as `Authorization: Bearer …` on every
    /// sync request. The peer side stores the same secret and constant-time
    /// compares.
    var sharedSecret: String
    /// Last time we successfully pulled from this peer. Sent as the `since`
    /// parameter on the next pull so the remote only has to enumerate
    /// files newer than this.
    var lastPullAt: Date?
    /// Last time we successfully pushed to this peer.
    var lastPushAt: Date?
    /// Last successful round-trip — surfaced in Settings as the "Synced N ago"
    /// timestamp.
    var lastSyncAt: Date?
    /// Last error string, if the most recent attempt failed. Cleared on the
    /// next successful sync.
    var lastError: String?

    static func newSecret() -> String {
        // 32 bytes / 256 bits of CSPRNG output, mapped to URL-safe base64 so
        // it slides into headers and Settings text fields without escaping.
        // (Once PR #340 lands, this can call PasswordHasher.newSessionToken
        // directly; kept inline here so the sync branch is self-contained.)
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Constant-time string compare for shared-secret verification.
    /// Internal to keep this file dependency-free while PR #340's
    /// `PasswordHasher.constantTimeEqual` is still on a separate branch.
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        guard ab.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in ab.indices { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }
}

/// On-disk shape — versioned in case we add fields later.
struct SyncPeersFile: Codable {
    var version: Int
    var peers: [SyncPeer]

    static let currentVersion = 1
    static let empty = SyncPeersFile(version: SyncPeersFile.currentVersion, peers: [])
}
