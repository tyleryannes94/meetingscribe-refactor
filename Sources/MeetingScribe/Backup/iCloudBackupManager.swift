import Foundation
import OSLog

/// Writes AES-256-encrypted backup archives of the meeting store into the app's
/// iCloud Drive ubiquity container. The archive payload here is a manifest of
/// the storage directory (a real, end-to-end-encrypted artifact); extending it
/// to bundle the full file tree is a TODO, but the encryption + iCloud-write
/// plumbing is complete.
///
/// Requires the `com.apple.developer.icloud-container-identifiers` entitlement
/// and an iCloud-signed build to resolve a container; without it
/// `ubiquityContainerURL` is nil and `runBackup()` throws `.iCloudUnavailable`.
actor iCloudBackupManager {
    static let shared = iCloudBackupManager()

    enum BackupError: Error, LocalizedError {
        case iCloudUnavailable
        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return "iCloud Drive isn't available. Sign in to iCloud and enable iCloud Drive for MeetingScribe."
            }
        }
    }

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Backup")
    private let containerIdentifier: String?

    init(containerIdentifier: String? = nil) {
        // nil → default ubiquity container for the app's iCloud entitlement.
        self.containerIdentifier = containerIdentifier
    }

    /// The Backups folder inside the ubiquity container's Documents dir, or nil
    /// when iCloud isn't configured for this build.
    private func backupsDirectory() -> URL? {
        guard let base = FileManager.default
            .url(forUbiquityContainerIdentifier: containerIdentifier) else { return nil }
        return base.appendingPathComponent("Documents/Backups", isDirectory: true)
    }

    /// Last successful backup time (persisted in UserDefaults).
    nonisolated var lastBackupDate: Date? {
        UserDefaults.standard.object(forKey: "lastiCloudBackupDate") as? Date
    }

    /// Run a backup now. Builds a storage manifest, encrypts it, and writes a
    /// timestamped `.enc` file into the ubiquity Backups folder.
    @discardableResult
    func runBackup() async throws -> URL {
        guard let dir = backupsDirectory() else { throw BackupError.iCloudUnavailable }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let payload = try buildManifestData()
        let key = try BackupEncryption.loadOrCreateKey()
        let ciphertext = try BackupEncryption.encrypt(payload, using: key)

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dest = dir.appendingPathComponent("backup-\(stamp).enc")
        try ciphertext.write(to: dest, options: .atomic)

        UserDefaults.standard.set(Date(), forKey: "lastiCloudBackupDate")
        log.info("Wrote encrypted backup: \(dest.lastPathComponent, privacy: .public) (\(ciphertext.count) bytes)")
        return dest
    }

    // MARK: - Manifest

    private struct Manifest: Codable {
        let createdAt: Date
        let storagePath: String
        let entries: [Entry]
        struct Entry: Codable { let path: String; let size: Int64 }
    }

    private func buildManifestData() throws -> Data {
        let root = AppSettings.shared.storageDir
        let fm = FileManager.default
        var entries: [Manifest.Entry] = []
        if let en = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in en {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
                entries.append(.init(path: url.lastPathComponent, size: size))
            }
        }
        let manifest = Manifest(createdAt: Date(), storagePath: root.path, entries: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }
}
