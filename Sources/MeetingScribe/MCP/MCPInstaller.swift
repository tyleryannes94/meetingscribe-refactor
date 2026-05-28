import Foundation
import AppKit
import OSLog

/// Locates the MeetingScribeMCP binary and manages its registration with
/// Claude Desktop's `claude_desktop_config.json` file.
@MainActor
final class MCPInstaller: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "MCPInstaller")

    @Published private(set) var installedInClaudeDesktop: Bool = false
    @Published private(set) var notionInstalledInClaudeDesktop: Bool = false
    @Published private(set) var lastError: String?

    /// Path to the MeetingScribeMCP binary inside our .app bundle.
    var binaryURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/MeetingScribeMCP")
    }
    /// Path to the bundled NotionMCP binary.
    var notionBinaryURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/NotionMCP")
    }

    /// True if the bundled binaries actually exist at their expected paths.
    var binaryExists: Bool { FileManager.default.isExecutableFile(atPath: binaryURL.path) }
    var notionBinaryExists: Bool { FileManager.default.isExecutableFile(atPath: notionBinaryURL.path) }

    /// Path to Claude Desktop's config JSON. Path may not yet exist if the
    /// user has never opened Claude Desktop.
    var claudeDesktopConfigURL: URL {
        URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Claude/claude_desktop_config.json").expandingTildeInPath)
    }

    /// The MCP server entry we register in Claude Desktop's config.
    /// Passes the current storage path via env var so the MCP server reads
    /// from the same folder the app writes to (even if the user moved it).
    var serverEntry: [String: Any] {
        [
            "command": binaryURL.path,
            "env": [
                "MEETINGSCRIBE_STORAGE": AppSettings.shared.storageDir.path
            ]
        ]
    }

    init() { refreshStatus() }

    /// Re-reads Claude Desktop's config to update `installedInClaudeDesktop`.
    func refreshStatus() {
        installedInClaudeDesktop = checkInstalled(key: "meetingscribe", expected: binaryURL.path)
        notionInstalledInClaudeDesktop = checkInstalled(key: "notion", expected: notionBinaryURL.path)
    }

    private func checkInstalled(key: String, expected: String) -> Bool {
        let path = claudeDesktopConfigURL.path
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: claudeDesktopConfigURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any],
              let ours = servers[key] as? [String: Any],
              let cmd = ours["command"] as? String else {
            return false
        }
        return cmd == expected
    }

    /// Writes (or updates) Claude Desktop's config to add our server. Returns
    /// the path that was written. The user still needs to restart Claude Desktop
    /// for it to pick up the new server.
    func installInClaudeDesktop() throws -> URL {
        let url = claudeDesktopConfigURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }
        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        servers["meetingscribe"] = serverEntry
        root["mcpServers"] = servers
        let pretty = try JSONSerialization.data(withJSONObject: root,
                                                options: [.prettyPrinted, .sortedKeys])
        try pretty.write(to: url, options: .atomic)
        refreshStatus()
        return url
    }

    /// Removes the meetingscribe entry from Claude Desktop's config.
    func uninstallFromClaudeDesktop() throws {
        try removeServer(key: "meetingscribe")
    }

    /// Writes (or updates) the `notion` server entry. The user's Notion
    /// integration token is passed via the `env` block — store it on first
    /// install. Pass nil to leave the existing one in place.
    @discardableResult
    func installNotionInClaudeDesktop(notionAPIKey: String?) throws -> URL {
        let url = claudeDesktopConfigURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }
        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        var env = (servers["notion"] as? [String: Any])?["env"] as? [String: Any] ?? [:]
        if let key = notionAPIKey, !key.isEmpty { env["NOTION_API_KEY"] = key }
        servers["notion"] = [
            "command": notionBinaryURL.path,
            "env": env
        ]
        root["mcpServers"] = servers
        let pretty = try JSONSerialization.data(withJSONObject: root,
                                                options: [.prettyPrinted, .sortedKeys])
        try pretty.write(to: url, options: .atomic)
        refreshStatus()
        return url
    }

    func uninstallNotionFromClaudeDesktop() throws {
        try removeServer(key: "notion")
    }

    private func removeServer(key: String) throws {
        let url = claudeDesktopConfigURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if var servers = root["mcpServers"] as? [String: Any] {
            servers.removeValue(forKey: key)
            root["mcpServers"] = servers
        }
        let pretty = try JSONSerialization.data(withJSONObject: root,
                                                options: [.prettyPrinted, .sortedKeys])
        try pretty.write(to: url, options: .atomic)
        refreshStatus()
    }

    /// JSON snippet the user can paste into any MCP-aware client.
    func configSnippet() -> String {
        let snippet: [String: Any] = [
            "mcpServers": [
                "meetingscribe": serverEntry
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: snippet,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    func copyConfigSnippetToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(configSnippet(), forType: .string)
    }

    func revealBinaryInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([binaryURL])
    }

    enum SelfTestResult: Equatable {
        case ok(String)
        case failure(String)
    }

    /// Runs `<binary> --self-test` style: send initialize + tools/list, return
    /// whether the server responded sensibly. Used by the Settings page's
    /// "Test connection" button.
    func selfTest() async -> SelfTestResult {
        guard binaryExists else { return .failure("MCP binary not bundled at \(binaryURL.path)") }
        let proc = Process()
        proc.executableURL = binaryURL
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr
        do { try proc.run() } catch { return .failure(error.localizedDescription) }

        let messages = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#
        ]
        for m in messages {
            stdin.fileHandleForWriting.write(Data((m + "\n").utf8))
        }
        // Give the process a moment, then close stdin so it exits.
        try? await Task.sleep(nanoseconds: 500_000_000)
        try? stdin.fileHandleForWriting.close()

        let outData = stdout.fileHandleForReading.availableData
        proc.terminate()
        let out = String(data: outData, encoding: .utf8) ?? ""
        // Expect two JSON lines back.
        let lines = out.split(separator: "\n").filter { !$0.isEmpty }
        if lines.count >= 2 { return .ok("Server responded ✓ (\(lines.count) messages)") }
        let errOut = String(data: stderr.fileHandleForReading.availableData, encoding: .utf8) ?? ""
        return .failure("Unexpected response. stdout=\(out.prefix(200)) stderr=\(errOut.prefix(200))")
    }
}
