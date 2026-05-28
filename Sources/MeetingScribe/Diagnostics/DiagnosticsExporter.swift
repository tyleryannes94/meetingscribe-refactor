import Foundation
import OSLog

/// Builds a self-contained `diagnostics-<timestamp>.zip` so a user filing
/// a bug can drag one file into a GitHub issue. No data leaves the machine
/// automatically; the user always presses the button (audit 8.2).
///
/// What's in the bundle:
///   • `app.log` — last N MB of structured app events
///   • `transcription-log.json` — every whisper/afconvert invocation
///   • `ollama.log` — last N MB of the local Ollama serve log
///   • `recent-errors.json` — last 100 errors funneled through ErrorReporter
///   • `system-info.txt` — OS version, model, locale, free disk
///   • `settings-redacted.json` — every Setting that isn't a secret
///     (Keychain items are NEVER included; UserDefaults values are filtered
///     by an allowlist below)
@available(macOS 14.0, *)
@MainActor
enum DiagnosticsExporter {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe",
                                    category: "Diagnostics")

    /// Settings keys that are safe to include in the redacted dump.
    /// Anything not on this list is excluded. New settings default-deny.
    private static let allowlist: Set<String> = [
        "storageDir",
        "whisperBinary",
        "whisperModel",
        "ollamaURL",
        "ollamaModel",
        "autoRecord",
        "captureMic",
        "captureSystem",
        "filterToConferenceLinks",
        "notifyAtMeetingStart",
        "detectZoomImpromptu",
        "dictationHotkeyKeyCode",
        "dictationHotkeyModifiers",
        "dictationAutoPaste",
        "dictationUsePolished",
        "dictationSwapHotkeyKeyCode",
        "dictationSwapHotkeyModifiers",
        "enabledCalendarIDs",
        "whisperUseGPU",
        "whisperFlashAttention",
        "lastTaskSync",
        "googleDriveFolderName",
        "googleDriveFolderID",
        "notionActionItemsDatabaseID",
        "googleClientID"          // public half of the OAuth pair
    ]

    /// Build the bundle and return the path to the zip.
    static func exportBundle() throws -> URL {
        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            return f.string(from: Date())
        }()
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meetingscribe-diagnostics-\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        // 1. app.log
        let appLogURL = AppLog.fileURL
        if FileManager.default.fileExists(atPath: appLogURL.path) {
            try? FileManager.default.copyItem(at: appLogURL,
                                              to: stagingDir.appendingPathComponent("app.log"))
        }

        // 2. transcription-log.json
        let transcriptionLogURL = AppSettings.shared.storageDir
            .appendingPathComponent("logs/transcription.json")
        if FileManager.default.fileExists(atPath: transcriptionLogURL.path) {
            try? FileManager.default.copyItem(at: transcriptionLogURL,
                                              to: stagingDir.appendingPathComponent("transcription-log.json"))
        }

        // 3. ollama.log (per-user)
        let ollamaLog = AppSettings.shared.storageDir
            .appendingPathComponent("logs/ollama.log")
        if FileManager.default.fileExists(atPath: ollamaLog.path) {
            try? FileManager.default.copyItem(at: ollamaLog,
                                              to: stagingDir.appendingPathComponent("ollama.log"))
        }

        // 4. recent-errors.json (from ErrorReporter)
        let errors = ErrorReporter.shared.snapshot().map { e -> [String: Any] in
            [
                "category": e.category.rawValue,
                "userMessage": e.userMessage,
                "debugDetail": e.debugDetail ?? "",
                "timestamp": ISO8601DateFormatter().string(from: e.timestamp),
                "context": e.context
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: errors, options: [.prettyPrinted, .sortedKeys]) {
            try data.write(to: stagingDir.appendingPathComponent("recent-errors.json"))
        }

        // 5. system-info.txt
        let info = systemInfo()
        try info.write(to: stagingDir.appendingPathComponent("system-info.txt"),
                       atomically: true, encoding: .utf8)

        // 6. settings-redacted.json
        let dict = redactedSettings()
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try data.write(to: stagingDir.appendingPathComponent("settings-redacted.json"))
        }

        // 7. README inside the zip so a maintainer knows what's where.
        let readme = """
        MeetingScribe diagnostics bundle — generated \(Date())

        Files:
          app.log                  — structured app events (errors, warnings, info)
          transcription-log.json   — every whisper / afconvert invocation
          ollama.log               — local Ollama serve output (per-user)
          recent-errors.json       — last 100 errors via ErrorReporter
          system-info.txt          — OS version, model, locale, free disk
          settings-redacted.json   — user settings (allowlisted, no secrets)

        NO API keys, refresh tokens, or audio recordings are included in
        this bundle. Drag this zip into a GitHub issue at
        https://github.com/tyleryannes94/meetingscribe/issues
        """
        try readme.write(to: stagingDir.appendingPathComponent("README.txt"),
                         atomically: true, encoding: .utf8)

        // Zip into the user's storage dir so they can find it via Finder.
        let outDir = AppSettings.shared.storageDir
            .appendingPathComponent("diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let zipURL = outDir.appendingPathComponent("diagnostics-\(stamp).zip")
        try ditto(source: stagingDir, destination: zipURL)
        AppLog.info("Diagnostics", "Bundle generated", ["path": zipURL.path])
        return zipURL
    }

    private static func systemInfo() -> String {
        let p = ProcessInfo.processInfo
        var lines: [String] = []
        lines.append("MeetingScribe diagnostics")
        lines.append("Generated: \(Date())")
        lines.append("")
        lines.append("macOS: \(p.operatingSystemVersionString)")
        let arch: String
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #else
        arch = "unknown"
        #endif
        lines.append("Arch: \(arch)")
        lines.append("Cores: \(p.activeProcessorCount) / \(p.processorCount)")
        lines.append("Memory: \(p.physicalMemory / 1_073_741_824) GB")
        lines.append("Locale: \(Locale.current.identifier)")
        lines.append("Hostname: \(p.hostName)")
        lines.append("")
        if let bundle = Bundle.main.infoDictionary {
            let v = bundle["CFBundleShortVersionString"] as? String ?? "?"
            let b = bundle["CFBundleVersion"] as? String ?? "?"
            lines.append("App version: \(v) (\(b))")
        }
        if let free = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? Int64 {
            lines.append("Free disk: \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))")
        }
        return lines.joined(separator: "\n")
    }

    /// Returns only the allowlisted UserDefaults keys, never anything from
    /// the Keychain. New settings default-deny.
    private static func redactedSettings() -> [String: Any] {
        let defaults = UserDefaults.standard
        var out: [String: Any] = [:]
        for key in allowlist {
            if let v = defaults.object(forKey: key) { out[key] = v }
        }
        return out
    }

    /// Use macOS's `ditto` to zip. Preserves resource forks and extended
    /// attributes correctly (a plain `zip` doesn't).
    private static func ditto(source: URL, destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent",
                          source.path, destination.path]
        let err = Pipe(); proc.standardError = err; proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            throw NSError(domain: "DiagnosticsExporter",
                          code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ditto failed: \(msg)"])
        }
    }
}
