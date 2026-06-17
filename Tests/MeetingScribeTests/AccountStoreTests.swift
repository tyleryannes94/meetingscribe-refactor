import XCTest
@testable import MeetingScribe

/// Tests for the multi-user account store that gates the phone web UI.
@MainActor
final class AccountStoreTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        // Each test gets its own isolated storage dir so the singleton
        // AccountStore reads/writes to a clean accounts.json.
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")

        // Drop the singleton's in-memory state from a prior test/fixture so
        // we don't inherit accounts from someone else's storageDir.
        AccountStore.shared.reloadFromDisk()
    }

    override func tearDownWithError() throws {
        // Leave the singleton clean for the next test.
        for a in AccountStore.shared.accounts {
            AccountStore.shared.deleteAccount(id: a.id)
        }
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    // MARK: - Password hashing

    func testHashIsDeterministicWithSameSalt() {
        let salt = PasswordHasher.newSalt()
        let a = PasswordHasher.hash(password: "correcthorsebatterystaple", saltBase64: salt)
        let b = PasswordHasher.hash(password: "correcthorsebatterystaple", saltBase64: salt)
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
    }

    func testHashChangesWithSalt() {
        let s1 = PasswordHasher.newSalt()
        let s2 = PasswordHasher.newSalt()
        XCTAssertNotEqual(s1, s2)
        let a = PasswordHasher.hash(password: "correcthorsebatterystaple", saltBase64: s1)
        let b = PasswordHasher.hash(password: "correcthorsebatterystaple", saltBase64: s2)
        XCTAssertNotEqual(a, b)
    }

    func testConstantTimeEqualHandlesLengthMismatch() {
        XCTAssertFalse(PasswordHasher.constantTimeEqual("abc", "abcd"))
        XCTAssertTrue(PasswordHasher.constantTimeEqual("abc", "abc"))
        XCTAssertFalse(PasswordHasher.constantTimeEqual("abc", "abd"))
    }

    // MARK: - Account create / authenticate

    func testCreateAndAuthenticate() {
        let store = AccountStore.shared
        let created = store.createAccount(email: "Tyler@Example.com",
                                          password: "password1234",
                                          displayName: "Tyler")
        XCTAssertNotNil(created)
        XCTAssertEqual(created?.email, "tyler@example.com",
                       "email should normalize to lowercase + trimmed")
        XCTAssertEqual(created?.displayName, "Tyler")

        let ok = store.authenticate(email: "tyler@example.com", password: "password1234")
        XCTAssertEqual(ok?.id, created?.id)

        let wrong = store.authenticate(email: "tyler@example.com", password: "Password1234")
        XCTAssertNil(wrong)
    }

    func testCreateRejectsInvalidInputs() {
        let store = AccountStore.shared
        XCTAssertNil(store.createAccount(email: "no-at-sign", password: "password1234"))
        XCTAssertNil(store.createAccount(email: "ok@example.com", password: "short"),
                     "password must be ≥ 8 chars")
        XCTAssertNil(store.createAccount(email: "   ", password: "password1234"))
    }

    func testDuplicateEmailRejected() {
        let store = AccountStore.shared
        _ = store.createAccount(email: "tyler@example.com", password: "password1234")
        XCTAssertNil(store.createAccount(email: "TYLER@example.com", password: "password1234"),
                     "normalized email collision should be detected")
    }

    func testAuthenticateUnknownEmailReturnsNil() {
        let store = AccountStore.shared
        XCTAssertNil(store.authenticate(email: "nobody@example.com",
                                        password: "password1234"))
    }

    // MARK: - Session lifecycle

    func testSessionLifecycle() {
        let store = AccountStore.shared
        let account = store.createAccount(email: "tyler@example.com",
                                          password: "password1234")!
        let session = store.issueSession(for: account.id, deviceLabel: "iPhone")
        XCTAssertEqual(session.accountID, account.id)
        XCTAssertEqual(session.deviceLabel, "iPhone")

        let validated = store.validate(sessionToken: session.id)
        XCTAssertEqual(validated?.id, account.id)

        store.revoke(sessionToken: session.id)
        XCTAssertNil(store.validate(sessionToken: session.id))
    }

    func testDeleteAccountRevokesSessions() {
        let store = AccountStore.shared
        let account = store.createAccount(email: "tyler@example.com",
                                          password: "password1234")!
        let s1 = store.issueSession(for: account.id, deviceLabel: "iPhone")
        let s2 = store.issueSession(for: account.id, deviceLabel: "iPad")
        store.deleteAccount(id: account.id)
        XCTAssertNil(store.validate(sessionToken: s1.id))
        XCTAssertNil(store.validate(sessionToken: s2.id))
        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testUpdatePasswordKeepsExistingSessions() {
        // matches macOS/keychain semantics — a password change doesn't sign
        // current devices out; revokeAllSessions() is the explicit way.
        let store = AccountStore.shared
        let account = store.createAccount(email: "tyler@example.com",
                                          password: "password1234")!
        let session = store.issueSession(for: account.id)
        let ok = store.updatePassword(id: account.id, newPassword: "anotherStrongPw")
        XCTAssertTrue(ok)
        XCTAssertNotNil(store.validate(sessionToken: session.id),
                        "session should still be valid after password change")
        // Old password no longer works.
        XCTAssertNil(store.authenticate(email: "tyler@example.com", password: "password1234"))
        // New password does.
        XCTAssertNotNil(store.authenticate(email: "tyler@example.com",
                                            password: "anotherStrongPw"))
    }

    func testRevokeAllSessionsForAccount() {
        let store = AccountStore.shared
        let account = store.createAccount(email: "tyler@example.com",
                                          password: "password1234")!
        let s1 = store.issueSession(for: account.id)
        let s2 = store.issueSession(for: account.id)
        store.revokeAllSessions(forAccountID: account.id)
        XCTAssertNil(store.validate(sessionToken: s1.id))
        XCTAssertNil(store.validate(sessionToken: s2.id))
    }

    func testSessionTokensAreUnique() {
        // Sanity check on the RNG path — millions of calls would be needed
        // for a real collision but a quick smoke covers an obvious mistake.
        var seen = Set<String>()
        for _ in 0..<200 {
            seen.insert(PasswordHasher.newSessionToken())
        }
        XCTAssertEqual(seen.count, 200)
    }
}
