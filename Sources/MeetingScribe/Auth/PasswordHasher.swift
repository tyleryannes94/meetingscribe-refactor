import Foundation
import CommonCrypto

/// PBKDF2-SHA256 password hashing using CommonCrypto (ships with macOS — no
/// extra dependency). Bcrypt/argon2 would be stronger but aren't in the
/// platform; PBKDF2 at 200k iterations is what 1Password / Bitwarden ship for
/// vault unlock, so it's fine here.
///
/// The verify path uses constant-time comparison via the existing
/// `constantTimeEqual` in `WebAPI` (reused) so the timing of a wrong-password
/// reject doesn't leak how many bytes matched.
enum PasswordHasher {
    static let defaultIterations: Int = 200_000
    /// 32-byte derived key — SHA-256 output width.
    static let derivedKeyLength: Int = 32
    /// 16-byte salt — 128 bits of randomness per user.
    static let saltLength: Int = 16

    /// Derive a base64-encoded PBKDF2 hash of `password` with the given salt.
    /// Returns nil only if PBKDF2 itself fails (it won't with sane inputs;
    /// CommonCrypto returns kCCParamError on a zero-length salt or password,
    /// which we guard against).
    static func hash(password: String, saltBase64: String,
                     iterations: Int = defaultIterations) -> String? {
        guard !password.isEmpty,
              let salt = Data(base64Encoded: saltBase64), !salt.isEmpty else {
            return nil
        }
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: derivedKeyLength)

        let result = salt.withUnsafeBytes { saltPtr -> Int32 in
            guard let saltBase = saltPtr.baseAddress else { return Int32(kCCParamError) }
            return CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes, passwordBytes.count,
                saltBase.assumingMemoryBound(to: UInt8.self), salt.count,
                CCPBKDFAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derivedKeyLength)
        }
        guard result == kCCSuccess else { return nil }
        return Data(derived).base64EncodedString()
    }

    /// Random salt suitable for `hash(password:salt:)`.
    static func newSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltLength, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// Random opaque session token — base64-url, 32 bytes / 256 bits of
    /// entropy. Web cookies dislike `+` and `/` so we map those to `-` and `_`,
    /// matching the JWT/URL-safe convention.
    static func newSessionToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Constant-time string compare so wrong-password verification doesn't
    /// leak how many bytes matched. Duplicated from `WebAPI`'s private helper
    /// so the auth code stands alone.
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count {
            diff |= aBytes[i] ^ bBytes[i]
        }
        return diff == 0
    }
}
