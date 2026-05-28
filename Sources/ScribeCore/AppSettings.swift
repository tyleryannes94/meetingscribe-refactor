import Foundation

/// Minimal AppSettings surface for Scribe Core daemon.
/// Reads the same UserDefaults keys as the main MeetingScribe app so the
/// vault location stays in sync across both processes.
enum AppSettings {
    private static let storageDirKey = "storageDir"

    /// Default storage location when nothing valid is configured.
    /// Mirrors AppSettings.defaultStorageURL in the main app target.
    static var defaultStorageURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault",
            isDirectory: true
        )
    }

    /// Read from UserDefaults, fall back to iCloud Drive default.
    /// Uses the same "storageDir" key written by the main MeetingScribe app.
    static var vaultURL: URL {
        if let stored = UserDefaults.standard.string(forKey: storageDirKey),
           !stored.isEmpty {
            return URL(fileURLWithPath: stored)
        }
        return defaultStorageURL
    }

    /// Alias for vaultURL — mirrors the `storageDir` property name used in
    /// the main app target.
    static var storageDir: URL { vaultURL }

    static var whisperBinary: String {
        UserDefaults.standard.string(forKey: "whisperBinary") ?? "/usr/local/bin/whisper-cli"
    }
    static var whisperModel: String {
        UserDefaults.standard.string(forKey: "whisperModel") ?? ""
    }
    static var whisperUseGPU: Bool {
        UserDefaults.standard.object(forKey: "whisperUseGPU") as? Bool ?? true
    }
    static var whisperFlashAttention: Bool {
        UserDefaults.standard.object(forKey: "whisperFlashAttention") as? Bool ?? false
    }
    static var whisperDiarizationEnabled: Bool {
        UserDefaults.standard.object(forKey: "whisperDiarizationEnabled") as? Bool ?? false
    }
    static var notifyAtMeetingStart: Bool {
        UserDefaults.standard.object(forKey: "notifyAtMeetingStart") as? Bool ?? true
    }
    static var autoExtractPeople: Bool {
        UserDefaults.standard.object(forKey: "autoExtractPeople") as? Bool ?? true
    }

    static var ollamaURL: URL {
        if let s = UserDefaults.standard.string(forKey: "ollamaURL"),
           let u = URL(string: s) { return u }
        return URL(string: "http://127.0.0.1:11434")!
    }
    static var captureMic: Bool {
        UserDefaults.standard.object(forKey: "captureMic") as? Bool ?? true
    }
    static var captureSystem: Bool {
        UserDefaults.standard.object(forKey: "captureSystem") as? Bool ?? true
    }
    static var filterToConferenceLinks: Bool {
        UserDefaults.standard.object(forKey: "filterToConferenceLinks") as? Bool ?? true
    }
    static var detectZoomImpromptu: Bool {
        UserDefaults.standard.object(forKey: "detectZoomImpromptu") as? Bool ?? true
    }
    static var enabledCalendarIDs: Set<String> {
        let arr = UserDefaults.standard.array(forKey: "enabledCalendarIDs") as? [String] ?? []
        return Set(arr)
    }
}
