import Foundation
import OSLog

/// Moving the vault off iCloud-synced storage (where files get evicted to the
/// cloud and aren't always downloaded) onto fast local storage, with an
/// additive backup to an iCloud folder so nothing is ever lost.
///
/// Safety posture: migration COPIES (never deletes the source) and backup is
/// ADDITIVE (never deletes anything in the destination). Both are idempotent —
/// re-running skips files already present with a matching size/mtime — so a
/// partial run can simply be retried.
enum VaultStorageManager {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "VaultStorage")

    /// Truly-local default: Application Support survives app updates and is NOT
    /// synced/evicted by iCloud.
    static var localDefaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MeetingScribe/Vault", isDirectory: true)
    }

    /// Default iCloud backup target.
    static var defaultBackupURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/MeetingScribe Backups", isDirectory: true)
    }

    /// True when `url` lives under the iCloud Mobile Documents tree (so we can
    /// suggest moving it local).
    static func isInICloud(_ url: URL) -> Bool {
        url.path.contains("/Library/Mobile Documents/")
    }

    static let audioExtensions: Set<String> = ["m4a", "wav", "caf", "aiff", "aif", "mp3", "flac"]

    struct Progress: Sendable { var files: Int; var bytes: Int64 }

    enum VaultError: LocalizedError {
        case sameLocation
        case sourceMissing(String)
        var errorDescription: String? {
            switch self {
            case .sameLocation: return "Source and destination are the same folder."
            case .sourceMissing(let p): return "Nothing to copy — \(p) doesn't exist."
            }
        }
    }

    // MARK: - Migration (copy, non-destructive)

    /// Copies the entire vault from `src` to `dst` without deleting the source.
    /// Returns how much was copied. Skips files already present at `dst` with the
    /// same size, so it's safe to re-run after an interruption.
    @discardableResult
    static func copyVault(from src: URL, to dst: URL,
                          onProgress: (@Sendable (Progress) -> Void)? = nil) throws -> Progress {
        let fm = FileManager.default
        guard src.standardizedFileURL != dst.standardizedFileURL else { throw VaultError.sameLocation }
        guard fm.fileExists(atPath: src.path) else { throw VaultError.sourceMissing(src.path) }
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)

        var progress = Progress(files: 0, bytes: 0)
        guard let en = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                     options: []) else { return progress }
        for case let item as URL in en {
            let rel = item.path.replacingOccurrences(of: src.path, with: "")
            let target = URL(fileURLWithPath: dst.path + rel)
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            let srcSize = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            // Skip if an identically-sized copy already exists (idempotent re-run).
            if let dstSize = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
               dstSize == srcSize {
                continue
            }
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            // copyItem will download an iCloud-evicted placeholder on read.
            try fm.copyItem(at: item, to: target)
            progress.files += 1
            progress.bytes += srcSize
            onProgress?(progress)
        }
        log.info("Vault copy complete: \(progress.files) files, \(progress.bytes) bytes → \(dst.path, privacy: .public)")
        return progress
    }

    // MARK: - Backup (additive mirror)

    /// Additively backs up `vault` into `dst`. Never deletes anything in `dst`.
    /// When `includeAudio` is false, audio files are skipped so the cloud backup
    /// stays small (transcripts/notes/JSON only). Idempotent: copies only files
    /// that are missing or newer at the destination.
    @discardableResult
    static func backup(vault: URL, to dst: URL, includeAudio: Bool,
                       onProgress: (@Sendable (Progress) -> Void)? = nil) throws -> Progress {
        let fm = FileManager.default
        guard fm.fileExists(atPath: vault.path) else { throw VaultError.sourceMissing(vault.path) }
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)

        var progress = Progress(files: 0, bytes: 0)
        guard let en = fm.enumerator(at: vault, includingPropertiesForKeys:
            [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: []) else { return progress }
        for case let item as URL in en {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            if !includeAudio, audioExtensions.contains(item.pathExtension.lowercased()) { continue }
            let rel = item.path.replacingOccurrences(of: vault.path, with: "")
            let target = URL(fileURLWithPath: dst.path + rel)

            let srcVals = try? item.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let srcSize = srcVals?.fileSize.map(Int64.init) ?? 0
            let srcMod = srcVals?.contentModificationDate ?? .distantPast
            if let dstVals = try? target.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
               dstVals.fileSize.map(Int64.init) == srcSize,
               (dstVals.contentModificationDate ?? .distantPast) >= srcMod {
                continue   // already backed up and unchanged
            }
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            do {
                try fm.copyItem(at: item, to: target)
                progress.files += 1
                progress.bytes += srcSize
                onProgress?(progress)
            } catch {
                log.error("Backup copy failed for \(rel, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        log.info("Backup complete: \(progress.files) files, \(progress.bytes) bytes → \(dst.path, privacy: .public)")
        return progress
    }

    /// Best-effort scheduled backup: runs at most once per 24h when enabled.
    static func runScheduledBackupIfDue() async {
        let s = AppSettings.shared
        guard s.backupEnabled else { return }
        let now = Date().timeIntervalSince1970
        if s.lastBackupAt > 0, now - s.lastBackupAt < 86_400 { return }
        do {
            _ = try backup(vault: s.storageDir, to: s.backupDir, includeAudio: s.backupIncludeAudio)
            s.lastBackupAt = now
        } catch {
            log.error("Scheduled backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
