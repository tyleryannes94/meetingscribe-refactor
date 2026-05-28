import Foundation
import AppKit
import CryptoKit
import OSLog

/// Imports contacts ("names and emails") from one or more Google accounts
/// (personal + work) via the People API — saved contacts (`connections`) and
/// autocomplete contacts you've emailed (`otherContacts`). Reuses the Drive
/// OAuth client (Settings → Google Drive) and the loopback PKCE flow.
///
/// One-time prerequisite in your Google Cloud project: enable the **People
/// API** and add the contacts read-only scopes to the OAuth consent screen.
@available(macOS 14.0, *)
@MainActor
final class GmailContactsService: ObservableObject {
    static let shared = GmailContactsService()
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "GmailContacts")

    struct Account: Codable, Identifiable, Hashable {
        var email: String
        var refreshToken: String
        var id: String { email }
    }

    @Published private(set) var accounts: [Account] = []
    @Published var isWorking = false
    @Published var lastStatus: String?

    private let scopes = [
        "https://www.googleapis.com/auth/contacts.readonly",
        "https://www.googleapis.com/auth/contacts.other.readonly",
        "https://www.googleapis.com/auth/userinfo.email"
    ].joined(separator: " ")

    init() { accounts = Self.loadAccounts() }

    var hasCredentials: Bool {
        AppSettings.shared.googleClientID != nil && AppSettings.shared.googleClientSecret != nil
    }

    enum GmailError: LocalizedError {
        case notConfigured, oauth(String), http(Int, String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add your Google OAuth client ID + secret in Settings → Google Drive first (the same client is reused), and enable the People API in your Google Cloud project."
            case .oauth(let m): return "Google sign-in failed: \(m)"
            case .http(let c, let m): return "People API HTTP \(c): \(String(m.prefix(300)))"
            }
        }
    }

    // MARK: - Accounts persistence (Keychain)

    private static func loadAccounts() -> [Account] {
        guard let json = KeychainStore.read(.googlePeopleAccounts),
              let data = json.data(using: .utf8),
              let accts = try? JSONDecoder().decode([Account].self, from: data) else { return [] }
        return accts
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts), let json = String(data: data, encoding: .utf8) {
            KeychainStore.write(.googlePeopleAccounts, json)
        }
    }

    func removeAccount(_ email: String) {
        accounts.removeAll { $0.email == email }
        saveAccounts()
    }

    // MARK: - Connect

    func connectAccount() async {
        guard let clientID = AppSettings.shared.googleClientID,
              let clientSecret = AppSettings.shared.googleClientSecret else {
            lastStatus = GmailError.notConfigured.localizedDescription
            return
        }
        isWorking = true
        lastStatus = "Opening browser for Google sign-in…"
        defer { isWorking = false }

        let loopback = GoogleOAuthLoopback()
        do {
            let port = try await loopback.start()
            let redirect = "http://127.0.0.1:\(port)"
            let verifier = Self.randomCodeVerifier()
            let challenge = Self.codeChallenge(for: verifier)

            var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            comps.queryItems = [
                .init(name: "client_id", value: clientID),
                .init(name: "redirect_uri", value: redirect),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: scopes),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "access_type", value: "offline"),
                .init(name: "prompt", value: "consent")
            ]
            NSWorkspace.shared.open(comps.url!)

            let code = try await withThrowingTaskGroup(of: String.self) { group -> String in
                group.addTask { try await loopback.waitForCode() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 180_000_000_000)
                    throw GmailError.oauth("Timed out waiting for Google sign-in.")
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }

            let tokens = try await exchangeCode(code, verifier: verifier, redirect: redirect,
                                                clientID: clientID, clientSecret: clientSecret)
            guard let refresh = tokens.refreshToken else {
                throw GmailError.oauth("Google didn't return a refresh token. Remove the app at myaccount.google.com → Security → Third-party access, then reconnect.")
            }
            let email = try await fetchAccountEmail(accessToken: tokens.accessToken)
            accounts.removeAll { $0.email == email } // re-auth replaces
            accounts.append(Account(email: email, refreshToken: refresh))
            saveAccounts()
            lastStatus = "Connected \(email)."
            log.info("Connected Google account")
        } catch {
            loopback.stop()
            lastStatus = (error as? GmailError)?.localizedDescription ?? error.localizedDescription
        }
    }

    // MARK: - Import

    /// Pulls contacts from every connected account and returns import candidates
    /// (the caller feeds them to `PeopleStore.importPeople`).
    func importAllContacts() async -> [PersonImport] {
        guard hasCredentials else { lastStatus = GmailError.notConfigured.localizedDescription; return [] }
        isWorking = true
        defer { isWorking = false }
        var all: [PersonImport] = []
        for account in accounts {
            do {
                let token = try await accessToken(for: account)
                all += try await fetchConnections(token: token)
                all += try await fetchOtherContacts(token: token)
            } catch {
                lastStatus = (error as? GmailError)?.localizedDescription ?? error.localizedDescription
                log.error("Import failed for an account: \(self.lastStatus ?? "", privacy: .public)")
            }
        }
        lastStatus = "Fetched \(all.count) contacts from \(accounts.count) account(s)."
        return all
    }

    private func fetchConnections(token: String) async throws -> [PersonImport] {
        try await paginate(base: "https://people.googleapis.com/v1/people/me/connections",
                           query: [.init(name: "personFields", value: "names,emailAddresses,phoneNumbers,organizations")],
                           token: token, arrayKey: "connections")
    }

    private func fetchOtherContacts(token: String) async throws -> [PersonImport] {
        try await paginate(base: "https://people.googleapis.com/v1/otherContacts",
                           query: [.init(name: "readMask", value: "names,emailAddresses,phoneNumbers")],
                           token: token, arrayKey: "otherContacts")
    }

    private func paginate(base: String, query: [URLQueryItem], token: String, arrayKey: String) async throws -> [PersonImport] {
        var out: [PersonImport] = []
        var pageToken: String?
        repeat {
            var comps = URLComponents(string: base)!
            comps.queryItems = query + [.init(name: "pageSize", value: "1000")]
                + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(code) else {
                throw GmailError.http(code, String(data: data, encoding: .utf8) ?? "")
            }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            for item in (obj[arrayKey] as? [[String: Any]] ?? []) {
                if let c = Self.mapPerson(item) { out.append(c) }
            }
            pageToken = obj["nextPageToken"] as? String
        } while pageToken != nil
        return out
    }

    private static func mapPerson(_ obj: [String: Any]) -> PersonImport? {
        let names = obj["names"] as? [[String: Any]] ?? []
        let emailObjs = obj["emailAddresses"] as? [[String: Any]] ?? []
        let phoneObjs = obj["phoneNumbers"] as? [[String: Any]] ?? []
        let orgs = obj["organizations"] as? [[String: Any]] ?? []

        let name = (names.first?["displayName"] as? String) ?? ""
        let emails = emailObjs.compactMap { $0["value"] as? String }
        let phones = phoneObjs.compactMap { $0["value"] as? String }
        guard !name.isEmpty || !emails.isEmpty else { return nil }
        return PersonImport(
            displayName: name.isEmpty ? (emails.first ?? "Unknown") : name,
            emails: emails,
            phones: phones,
            company: (orgs.first?["name"] as? String) ?? "",
            role: (orgs.first?["title"] as? String) ?? "",
            source: "gmail"
        )
    }

    // MARK: - Tokens

    private func accessToken(for account: Account) async throws -> String {
        guard let clientID = AppSettings.shared.googleClientID,
              let clientSecret = AppSettings.shared.googleClientSecret else { throw GmailError.notConfigured }
        let body = Self.form([
            "client_id": clientID, "client_secret": clientSecret,
            "refresh_token": account.refreshToken, "grant_type": "refresh_token"
        ])
        return try await tokenRequest(body: body).accessToken
    }

    private func exchangeCode(_ code: String, verifier: String, redirect: String,
                              clientID: String, clientSecret: String) async throws -> TokenResponse {
        let body = Self.form([
            "code": code, "client_id": clientID, "client_secret": clientSecret,
            "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier
        ])
        return try await tokenRequest(body: body)
    }

    private struct TokenResponse { let accessToken: String; let refreshToken: String? }

    private func tokenRequest(body: String) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw GmailError.oauth(String(data: data, encoding: .utf8) ?? "HTTP \(code)")
        }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let access = obj["access_token"] as? String else { throw GmailError.oauth("No access token.") }
        return TokenResponse(accessToken: access, refreshToken: obj["refresh_token"] as? String)
    }

    private func fetchAccountEmail(accessToken: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (obj["email"] as? String) ?? "account-\(accounts.count + 1)"
    }

    // MARK: - PKCE

    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }
    private static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    private static func form(_ params: [String: String]) -> String {
        params.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $1)" }
            .joined(separator: "&")
    }
}
