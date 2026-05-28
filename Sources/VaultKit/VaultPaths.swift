import Foundation

public struct VaultPaths {
    /// Canonical vault location — defaults to iCloud Drive
    public static var defaultVaultURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault", isDirectory: true)
    }

    /// SQLite derived index — always in Application Support, never synced
    public static var databaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MeetingScribe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("secondbrain.db")
    }

    /// Inbox for iPhone Shortcut drops
    public static func inboxURL(vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent("_inbox", isDirectory: true)
    }

    /// Processed inbox items
    public static func processedInboxURL(vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent("_inbox/processed", isDirectory: true)
    }

    /// Recent meetings stub for iPhone Shortcuts
    public static func recentJSONURL(vaultURL: URL) -> URL {
        vaultURL.appendingPathComponent("_recent.json")
    }
}
