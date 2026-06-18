import Foundation
import Combine

/// Owns the local user accounts + sessions that gate the phone web UI.
///
/// On-disk file lives next to the rest of the vault state at
/// `<storageDir>/accounts.json`. All mutations are immediately flushed so a
/// crash mid-edit can lose at most one in-flight login, never a created
/// account. Reads are cheap (file is tiny — bytes per user) so we just reload
/// on every mutation rather than caching in-memory state separately.
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    /// Published mirror of the current accounts so SwiftUI surfaces (Settings)
    /// can list them reactively.
    @Published private(set) var accounts: [WebAccount] = []
    /// Sessions are not surfaced as a binding — the API touches them directly.
    private(set) var sessions: [WebSession] = []

    /// Sessions older than this without use are pruned at load time so a
    /// long-abandoned device can't authenticate forever.
    private let sessionMaxIdle: TimeInterval = 90 * 86_400   // 90 days

    private var fileURL: URL {
        AppSettings.shared.storageDir.appendingPathComponent("accounts.json")
    }

    private init() { load() }

    /// Force a re-read from disk. Exposed so tests can swap the underlying
    /// `storageDir` between cases without holding the singleton's cached
    /// state from a prior test fixture; not used by production code.
    func reloadFromDisk() { load() }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            accounts = []
            sessions = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(AccountsFile.self, from: data) else {
            // Corrupt or schema-mismatched — fail closed; the user can
            // recreate. We deliberately do NOT overwrite the file here so they
            // can recover manually.
            accounts = []
            sessions = []
            return
        }
        accounts = file.accounts
        sessions = file.sessions.filter { s in
            Date().timeIntervalSince(s.lastUsedAt) < sessionMaxIdle
        }
        // If we pruned anything on load, persist the pruned state.
        if sessions.count != file.sessions.count { persist() }
    }

    private func persist() {
        let file = AccountsFile(version: AccountsFile.currentVersion,
                                accounts: accounts, sessions: sessions)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // Write atomically so a crash mid-write doesn't leave a half-flushed
        // file — important since this is the file the phone needs to log in.
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Account CRUD

    /// True when no accounts exist yet — the Settings UI uses this to surface
    /// a "create your first account" CTA on top of the panel.
    var isEmpty: Bool { accounts.isEmpty }

    /// Create an account. Returns the new account, or nil if the email is
    /// already in use or the password is too short / empty.
    @discardableResult
    func createAccount(email: String, password: String,
                       displayName: String? = nil) -> WebAccount? {
        let normalized = WebAccount.normalizeEmail(email)
        guard !normalized.isEmpty, normalized.contains("@") else { return nil }
        guard password.count >= 8 else { return nil }
        guard !accounts.contains(where: { $0.email == normalized }) else { return nil }
        let salt = PasswordHasher.newSalt()
        guard let hash = PasswordHasher.hash(password: password, saltBase64: salt) else {
            return nil
        }
        let now = Date()
        let account = WebAccount(
            id: UUID().uuidString,
            email: normalized,
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? defaultDisplayName(from: normalized),
            passwordHash: hash,
            passwordSalt: salt,
            passwordIterations: PasswordHasher.defaultIterations,
            createdAt: now,
            updatedAt: now)
        accounts.append(account)
        persist()
        return account
    }

    /// Delete an account. Also revokes every session belonging to it.
    func deleteAccount(id: String) {
        accounts.removeAll { $0.id == id }
        sessions.removeAll { $0.accountID == id }
        persist()
    }

    /// Change an account's password. Existing sessions stay valid — same
    /// behavior as macOS itself; revoking sessions on a password change is
    /// available via `revokeAllSessions(forAccountID:)`.
    func updatePassword(id: String, newPassword: String) -> Bool {
        guard newPassword.count >= 8,
              let idx = accounts.firstIndex(where: { $0.id == id }) else { return false }
        let salt = PasswordHasher.newSalt()
        guard let hash = PasswordHasher.hash(password: newPassword, saltBase64: salt) else {
            return false
        }
        accounts[idx].passwordHash = hash
        accounts[idx].passwordSalt = salt
        accounts[idx].passwordIterations = PasswordHasher.defaultIterations
        accounts[idx].updatedAt = Date()
        persist()
        return true
    }

    func updateDisplayName(id: String, displayName: String) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accounts[idx].displayName = trimmed
        accounts[idx].updatedAt = Date()
        persist()
    }

    // MARK: - Authentication

    /// Verify (email, password). Returns the account on success, nil on any
    /// failure. The implementation always performs a PBKDF2 round even when
    /// the email is unknown so timing doesn't reveal which emails are
    /// registered.
    func authenticate(email: String, password: String) -> WebAccount? {
        let normalized = WebAccount.normalizeEmail(email)
        let account = accounts.first(where: { $0.email == normalized })
        // Always hash, even on missing-account, so the verify path takes the
        // same wall-clock time as a wrong-password reject.
        let salt = account?.passwordSalt ?? PasswordHasher.newSalt()
        let iterations = account?.passwordIterations ?? PasswordHasher.defaultIterations
        guard let computed = PasswordHasher.hash(password: password,
                                                  saltBase64: salt,
                                                  iterations: iterations) else {
            return nil
        }
        guard let account else { return nil }
        guard PasswordHasher.constantTimeEqual(computed, account.passwordHash) else {
            return nil
        }
        return account
    }

    /// Issue a session for the given account. The returned token goes into the
    /// `ms_session` cookie on the phone.
    func issueSession(for accountID: String, deviceLabel: String? = nil) -> WebSession {
        let token = PasswordHasher.newSessionToken()
        let now = Date()
        let session = WebSession(id: token, accountID: accountID,
                                  createdAt: now, lastUsedAt: now,
                                  deviceLabel: deviceLabel?.trimmingCharacters(in: .whitespacesAndNewlines))
        sessions.append(session)
        persist()
        return session
    }

    /// Look up the account associated with a session token, refreshing its
    /// `lastUsedAt` timestamp. Returns nil for unknown/expired tokens.
    func validate(sessionToken: String) -> WebAccount? {
        guard let idx = sessions.firstIndex(where: {
            PasswordHasher.constantTimeEqual($0.id, sessionToken)
        }) else { return nil }
        // Bump lastUsedAt; persist so the idle-prune at next load sees it.
        sessions[idx].lastUsedAt = Date()
        let accountID = sessions[idx].accountID
        persist()
        return accounts.first(where: { $0.id == accountID })
    }

    func revoke(sessionToken: String) {
        sessions.removeAll { PasswordHasher.constantTimeEqual($0.id, sessionToken) }
        persist()
    }

    func revokeAllSessions(forAccountID id: String) {
        sessions.removeAll { $0.accountID == id }
        persist()
    }

    // MARK: - Helpers

    private func defaultDisplayName(from normalizedEmail: String) -> String {
        let local = normalizedEmail.split(separator: "@").first.map(String.init) ?? normalizedEmail
        return local.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
