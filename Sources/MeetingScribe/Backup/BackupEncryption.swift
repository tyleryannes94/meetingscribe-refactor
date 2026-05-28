import Foundation
import CryptoKit
import Security

/// AES-256-GCM encryption for backup archives, plus keychain-backed management
/// of the symmetric key. The key is generated once and stored in the login
/// keychain; archives written to iCloud are ciphertext only.
enum BackupEncryption {
    enum CryptoError: Error, LocalizedError {
        case keychain(OSStatus)
        case keyEncoding
        var errorDescription: String? {
            switch self {
            case .keychain(let s): return "Keychain error (\(s)) accessing the backup key."
            case .keyEncoding:     return "Backup key in the keychain is malformed."
            }
        }
    }

    // MARK: - Encrypt / decrypt

    /// AES-GCM seal. Returns the `combined` form (nonce ‖ ciphertext ‖ tag).
    static func encrypt(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.keyEncoding }
        return combined
    }

    /// AES-GCM open of a `combined` blob produced by `encrypt`.
    static func decrypt(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    // MARK: - Key management (login keychain)

    private static let service = "com.tyleryannes.MeetingScribe.backup"
    private static let account = "backup-aes256-key"

    /// Fetch the existing backup key, or generate + persist a new 256-bit one.
    static func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try readKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        try storeKey(key)
        return key
    }

    private static func readKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else { throw CryptoError.keyEncoding }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw CryptoError.keychain(status)
        }
    }

    private static func storeKey(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        // Replace any stale entry first.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw CryptoError.keychain(status) }
    }
}
