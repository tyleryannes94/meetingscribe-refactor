import Foundation

/// A local user account that can sign into the phone web UI.
///
/// Stored in the vault as `accounts.json` so it lives next to the rest of the
/// user's data and rides along with whatever backup the vault is on (iCloud
/// Drive by default per `VaultPaths.defaultVaultURL`). No cloud auth provider —
/// the Mac mini hub IS the auth server, reached over Tailscale.
///
/// Passwords are never stored: we keep a PBKDF2-SHA256 hash + a random per-user
/// salt + the iteration count, so a stolen `accounts.json` doesn't yield the
/// passwords without weeks of GPU work per user.
struct WebAccount: Codable, Identifiable, Equatable {
    /// Stable account id — independent of email so the email can be changed
    /// without breaking sessions or personal-data links.
    let id: String
    /// Normalized (trimmed, lowercased) email.
    var email: String
    /// Friendly name shown in the UI (defaults to the local part of the email).
    var displayName: String
    /// PBKDF2-SHA256 hash of the password, base64-encoded.
    var passwordHash: String
    /// Random per-user salt, base64-encoded.
    var passwordSalt: String
    /// PBKDF2 iteration count. Stored so we can bump it for new users without
    /// breaking existing ones.
    var passwordIterations: Int
    let createdAt: Date
    var updatedAt: Date

    static func normalizeEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Persisted session token. Issued on a successful login and traded back for
/// the existing `ms_token` cookie path so every API endpoint keeps its current
/// auth gate — we just teach the gate to also accept session cookies.
struct WebSession: Codable, Identifiable, Equatable {
    /// Random opaque session token, base64-url-encoded, ~256 bits of entropy.
    /// Used as both the id and the value sent in the `ms_session` cookie.
    let id: String
    let accountID: String
    let createdAt: Date
    var lastUsedAt: Date
    /// Optional human label set by the device on first login ("Tyler's iPhone").
    var deviceLabel: String?
}

/// On-disk shape of `accounts.json` — versioned in case we need to migrate the
/// schema later (e.g. switch KDFs).
struct AccountsFile: Codable {
    var version: Int
    var accounts: [WebAccount]
    var sessions: [WebSession]

    static let currentVersion = 1
    static let empty = AccountsFile(version: AccountsFile.currentVersion,
                                    accounts: [], sessions: [])
}
