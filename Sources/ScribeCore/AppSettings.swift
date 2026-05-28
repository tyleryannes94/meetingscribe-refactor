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
}
