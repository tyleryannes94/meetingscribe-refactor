import Foundation
import Network
import AppKit
import CryptoKit
import OSLog

/// Google Drive export. Handles the OAuth 2.0 "installed app" flow (PKCE +
/// loopback redirect — no embedded secrets in the redirect, works for an
/// open-source app where each user supplies their own client), token refresh,
/// and uploading markdown files to a folder in the user's Drive.
///
/// Scope is `drive.file` — the app can only see/modify files it creates, the
/// least-privilege option. The one-time prerequisite (an OAuth client in
/// Google Cloud Console) is documented in Settings → Google Drive.
@available(macOS 14.0, *)
@MainActor
final class GoogleDriveService: ObservableObject {
    static let shared = GoogleDriveService()
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "GoogleDrive")

    @Published private(set) var isConnected: Bool
    @Published private(set) var isWorking = false
    @Published var lastStatus: String?

    private var accessToken: String?
    private var accessTokenExpiry: Date = .distantPast

    private let scope = "https://www.googleapis.com/auth/drive.file"

    init() {
        isConnected = AppSettings.shared.googleRefreshToken != nil
    }

    var hasCredentials: Bool {
        AppSettings.shared.googleClientID != nil && AppSettings.shared.googleClientSecret != nil
    }

    enum DriveError: LocalizedError {
        case notConfigured
        case notConnected
        case oauth(String)
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add a Google OAuth client ID and secret in Settings → Google Drive first."
            case .notConnected:  return "Not connected to Google Drive. Click Connect in Settings → Google Drive."
            case .oauth(let m):  return "Google sign-in failed: \(m)"
            case .http(let c, let m): return "Google Drive API HTTP \(c): \(String(m.prefix(300)))"
            }
        }
    }

    // MARK: - Connect / disconnect

    func connect() async {
        guard let clientID = AppSettings.shared.googleClientID,
              let clientSecret = AppSettings.shared.googleClientSecret else {
            lastStatus = DriveError.notConfigured.localizedDescription
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
                .init(name: "scope", value: scope),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "access_type", value: "offline"),
                .init(name: "prompt", value: "consent")
            ]
            NSWorkspace.shared.open(comps.url!)

            // Race the redirect against a timeout so an abandoned sign-in
            // doesn't leave the task (and listener) hanging forever.
            let code = try await withThrowingTaskGroup(of: String.self) { group -> String in
                group.addTask { try await loopback.waitForCode() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 180_000_000_000)
                    throw DriveError.oauth("Timed out waiting for Google sign-in.")
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            let tokens = try await exchangeCode(code, verifier: verifier, redirect: redirect,
                                                clientID: clientID, clientSecret: clientSecret)
            guard let refresh = tokens.refreshToken else {
                throw DriveError.oauth("Google didn't return a refresh token. Remove the app's access at myaccount.google.com → Security → Third-party access, then reconnect.")
            }
            AppSettings.shared.googleRefreshToken = refresh
            accessToken = tokens.accessToken
            accessTokenExpiry = Date().addingTimeInterval(tokens.expiresIn - 60)
            isConnected = true
            lastStatus = "Connected to Google Drive."
            AppLog.info("GoogleDrive", "Connected")
        } catch {
            loopback.stop()
            isConnected = AppSettings.shared.googleRefreshToken != nil
            lastStatus = (error as? DriveError)?.localizedDescription ?? error.localizedDescription
            AppLog.error("GoogleDrive", "Connect failed", error: error)
        }
    }

    func disconnect() {
        AppSettings.shared.googleRefreshToken = nil
        AppSettings.shared.googleDriveFolderID = nil
        accessToken = nil
        accessTokenExpiry = .distantPast
        isConnected = false
        lastStatus = "Disconnected."
    }

    // MARK: - Export

    /// Uploads a markdown document to the configured Drive folder. Returns the
    /// file's Drive URL.
    @discardableResult
    func exportMarkdown(filename: String, content: String) async throws -> String {
        guard hasCredentials else { throw DriveError.notConfigured }
        guard AppSettings.shared.googleRefreshToken != nil else { throw DriveError.notConnected }
        isWorking = true
        defer { isWorking = false }
        let token = try await validAccessToken()
        let folderID = try await ensureFolder(token: token)
        let name = filename.hasSuffix(".md") ? filename : filename + ".md"
        let url = try await uploadMultipart(name: name, mimeType: "text/markdown",
                                            data: Data(content.utf8),
                                            parents: folderID.map { [$0] } ?? [],
                                            token: token)
        lastStatus = "Exported “\(name)” to Google Drive."
        AppLog.info("GoogleDrive", "Exported", ["file": name])
        return url
    }

    // MARK: - Tokens

    private func validAccessToken() async throws -> String {
        if let t = accessToken, Date() < accessTokenExpiry { return t }
        guard let refresh = AppSettings.shared.googleRefreshToken,
              let clientID = AppSettings.shared.googleClientID,
              let clientSecret = AppSettings.shared.googleClientSecret else {
            throw DriveError.notConnected
        }
        let body = Self.form([
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ])
        let tokens = try await tokenRequest(body: body)
        accessToken = tokens.accessToken
        accessTokenExpiry = Date().addingTimeInterval(tokens.expiresIn - 60)
        return tokens.accessToken
    }

    private func exchangeCode(_ code: String, verifier: String, redirect: String,
                              clientID: String, clientSecret: String) async throws -> TokenResponse {
        let body = Self.form([
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ])
        return try await tokenRequest(body: body)
    }

    private struct TokenResponse { let accessToken: String; let refreshToken: String?; let expiresIn: TimeInterval }

    private func tokenRequest(body: String) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw DriveError.oauth(String(data: data, encoding: .utf8) ?? "HTTP \(code)")
        }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let access = obj["access_token"] as? String else {
            throw DriveError.oauth("No access token in response.")
        }
        return TokenResponse(accessToken: access,
                             refreshToken: obj["refresh_token"] as? String,
                             expiresIn: (obj["expires_in"] as? Double) ?? 3300)
    }

    // MARK: - Drive API

    private func ensureFolder(token: String) async throws -> String? {
        if let cached = AppSettings.shared.googleDriveFolderID { return cached }
        let folderName = AppSettings.shared.googleDriveFolderName
        // Look for an existing app-created folder of this name.
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            .init(name: "q", value: "name='\(folderName)' and mimeType='application/vnd.google-apps.folder' and trashed=false"),
            .init(name: "fields", value: "files(id,name)"),
            .init(name: "spaces", value: "drive")
        ]
        var listReq = URLRequest(url: comps.url!)
        listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (listData, listResp) = try await URLSession.shared.data(for: listReq)
        if let http = listResp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
           let obj = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
           let files = obj["files"] as? [[String: Any]], let first = files.first,
           let id = first["id"] as? String {
            AppSettings.shared.googleDriveFolderID = id
            return id
        }
        // Create it.
        var createReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        createReq.httpMethod = "POST"
        createReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": folderName,
            "mimeType": "application/vnd.google-apps.folder"
        ])
        let (createData, createResp) = try await URLSession.shared.data(for: createReq)
        let code = (createResp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code),
              let obj = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let id = obj["id"] as? String else {
            throw DriveError.http(code, String(data: createData, encoding: .utf8) ?? "")
        }
        AppSettings.shared.googleDriveFolderID = id
        return id
    }

    private func uploadMultipart(name: String, mimeType: String, data: Data,
                                 parents: [String], token: String) async throws -> String {
        let boundary = "meetingscribe-\(UUID().uuidString)"
        var metadata: [String: Any] = ["name": name]
        if !parents.isEmpty { metadata["parents"] = parents }
        let metaData = try JSONSerialization.data(withJSONObject: metadata)

        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metaData)
        append("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (respData, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw DriveError.http(code, String(data: respData, encoding: .utf8) ?? "")
        }
        let obj = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any] ?? [:]
        return (obj["webViewLink"] as? String) ?? "https://drive.google.com/"
    }

    // MARK: - PKCE helpers

    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
    private static func form(_ params: [String: String]) -> String {
        params.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Minimal loopback HTTP listener that captures the OAuth redirect's `code`.
final class GoogleOAuthLoopback: @unchecked Sendable {
    private var listener: NWListener?
    private var portCont: CheckedContinuation<UInt16, Error>?
    private var codeCont: CheckedContinuation<String, Error>?
    private var finished = false
    private let lock = NSLock()

    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let p = listener.port?.rawValue { self?.resumePort(.success(p)) }
            case .failed(let err):
                self?.resumePort(.failure(err))
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        return try await withCheckedThrowingContinuation { cont in
            self.portCont = cont
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in self.codeCont = cont }
    }

    func stop() { listener?.cancel(); listener = nil }

    private func resumePort(_ result: Result<UInt16, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard let c = portCont else { return }
        portCont = nil
        c.resume(with: result)
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let line = data.flatMap { String(data: $0, encoding: .utf8) }?
                .split(separator: "\r\n").first.map(String.init) ?? ""
            let code = Self.queryItem("code", in: line)
            let err = Self.queryItem("error", in: line)
            let html = """
            <html><body style="font-family:-apple-system;text-align:center;padding-top:90px;color:#222">
            <h2>MeetingScribe is connected ✓</h2><p>You can close this tab and return to the app.</p></body></html>
            """
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })

            self.lock.lock()
            let alreadyDone = self.finished
            if !alreadyDone { self.finished = true }
            let c = self.codeCont
            self.codeCont = nil
            self.lock.unlock()

            guard !alreadyDone, let c else { return }
            if let code {
                c.resume(returning: code)
            } else {
                c.resume(throwing: NSError(domain: "GoogleOAuth", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: err ?? "No authorization code returned."]))
            }
            self.listener?.cancel()
        }
    }

    private static func queryItem(_ name: String, in requestLine: String) -> String? {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let path = String(parts[1])
        guard let q = path.firstIndex(of: "?") else { return nil }
        var comps = URLComponents()
        comps.percentEncodedQuery = String(path[path.index(after: q)...])
        return comps.queryItems?.first { $0.name == name }?.value
    }
}
