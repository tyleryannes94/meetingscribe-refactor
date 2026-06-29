import Foundation
import Security
import OSLog

/// Typed wrapper around the macOS Keychain for secrets we previously
/// stashed in UserDefaults (Notion / Linear API keys, Google OAuth client
/// secret + refresh token). UserDefaults is a plaintext plist; the Keychain
/// is encrypted at rest, gated by the user's login session, and excluded
/// from Time Machine.
///
/// Keys live under the bundle's service id with a per-secret account name.
/// Items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — they don't
/// sync to iCloud Keychain, and they're never readable when the Mac is
/// locked. (We don't gate them with biometric/passcode because the chat
/// + sync paths run unattended; the user already trusts a running session
/// with their other secrets.)
///
/// First read of each known secret transparently migrates any value
/// found in UserDefaults into the Keychain and clears the UserDefaults
/// entry, so existing installs upgrade without user action.
public enum KeychainStore {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe",
                                    category: "Keychain")
    private static let service = "com.tyleryannes.MeetingScribe.secrets"

    /// Canonical list of secret accounts. Adding a secret here keeps
    /// the migration table in one place.
    public enum Account: String, CaseIterable {
        case notionAPIKey
        case linearAPIKey
        case googleClientSecret
        case googleRefreshToken
        case anthropicAPIKey      // reserved for re-enabling Anthropic chat path
        case googlePeopleAccounts // Phase C: JSON array of Gmail/People accounts
        case tavilyAPIKey         // Brain Dump web search provider
    }

    // MARK: - Read / write

    public static func read(_ account: Account) -> String? {
        if let s = readKeychain(account: account.rawValue) {
            return s
        }
        // Migration path: if a legacy UserDefaults entry exists, lift it
        // into the keychain and clear the defaults entry. Only runs the
        // first time the value is read after the upgrade.
        if let migrated = migrateFromUserDefaults(account: account) {
            return migrated
        }
        return nil
    }

    public static func write(_ account: Account, _ value: String?) {
        if let v = value, !v.isEmpty {
            writeKeychain(account: account.rawValue, value: v)
        } else {
            deleteKeychain(account: account.rawValue)
        }
        // Defensive: ensure no stale UserDefaults copy lingers.
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey(for: account))
    }

    public static func delete(_ account: Account) { write(account, nil) }

    /// Migrate every known secret in one pass. Safe to call repeatedly.
    /// Called once at app launch from `MeetingScribeApp.startServices`.
    public static func migrateAllFromUserDefaults() {
        for account in Account.allCases {
            _ = read(account)   // triggers migration as a side-effect
        }
    }

    // MARK: - Internals

    private static func legacyDefaultsKey(for account: Account) -> String {
        // Map keychain account names back to the historical UserDefaults
        // keys used in Models/Settings.swift. Keep this stable.
        switch account {
        case .notionAPIKey:        return "notionAPIKey"
        case .linearAPIKey:        return "linearAPIKey"
        case .googleClientSecret:  return "googleClientSecret"
        case .googleRefreshToken:  return "googleRefreshToken"
        case .anthropicAPIKey:     return "anthropicAPIKey"
        case .googlePeopleAccounts: return "googlePeopleAccounts"
        case .tavilyAPIKey:        return "tavilyAPIKey"
        }
    }

    private static func migrateFromUserDefaults(account: Account) -> String? {
        let key = legacyDefaultsKey(for: account)
        guard let legacy = UserDefaults.standard.string(forKey: key),
              !legacy.isEmpty else { return nil }
        writeKeychain(account: account.rawValue, value: legacy)
        UserDefaults.standard.removeObject(forKey: key)
        log.info("Migrated \(account.rawValue, privacy: .public) from UserDefaults to Keychain.")
        return legacy
    }

    private static func readKeychain(account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        // Some users have synced keychain items from an earlier (UserDefaults)
        // era — don't restrict by sync attribute on read.
        var item: AnyObject?
        let status = withUnsafeMutablePointer(to: &item) {
            SecItemCopyMatching(query as CFDictionary, $0)
        }
        guard status == errSecSuccess, let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                log.warning("Keychain read \(account, privacy: .public) status=\(status)")
            }
            _ = query   // silence unused warning when above path takes early return
            return nil
        }
        return s
    }

    private static func writeKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        // Try update first; if no existing item, add.
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var add = baseQuery
            for (k, v) in attrs { add[k] = v }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                log.error("Keychain add \(account, privacy: .public) status=\(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            log.error("Keychain update \(account, privacy: .public) status=\(updateStatus)")
        }
    }

    private static func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.warning("Keychain delete \(account, privacy: .public) status=\(status)")
        }
    }
}
