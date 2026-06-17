import Foundation

/// Enumerates "syncable" files under the vault. The big idea: the vault is
/// plain markdown + JSON, so a sync engine can be a dumb file mirror with
/// last-write-wins per file (mtime is the authority). No CRDTs, no
/// per-record diffing — the vault was designed for this.
///
/// Skipped paths:
/// - rebuildable caches (`.meeting-index.json`, `_people-cache.json`, etc.)
/// - the per-vault auth state (`accounts.json`, `sync-peers.json`) so one Mac
///   can't sign people out of another or hijack the other side's peer config
/// - the `_remote/` quarantine namespace from `docs/CROSS_DEVICE_SYNC_MASTER_PLAN.md`
/// - hidden files (anything starting with `.`)
enum SyncIndex {

    /// One file's sync metadata.
    struct Entry: Codable, Equatable {
        /// Path RELATIVE to the vault root, with forward slashes (e.g.
        /// `meetings/2026/2026-06/q3-planning/notes.md`). Always relative so
        /// it's portable between Macs whose `storageDir` paths differ.
        let path: String
        /// File modification time on the producing side. Authoritative for
        /// last-write-wins conflict resolution.
        let mtime: Date
        /// File size in bytes — surfaced to the client so it can budget
        /// downloads.
        let size: Int
    }

    /// Files we never sync. Order matters: any path matching one of these
    /// prefixes is excluded. Both leading slash and no-leading-slash forms
    /// are handled by the matcher.
    static let excludedPrefixes: [String] = [
        "_remote/",                  // quarantine namespace from rsync-style sync
        ".meeting-index.json",       // rebuildable index
        "_people-cache.json",        // rebuildable cache
        "_recent.json",              // rebuildable iPhone Shortcut stub
        "accounts.json",             // per-vault auth state — local-only
        "sync-peers.json",           // peer config — local-only
        ".processed_ids.json",       // iCloud inbox ledger — local-only
    ]

    /// Enumerate every syncable file under `vaultRoot`, optionally filtering
    /// by `since` (only files with `mtime > since`). Returns relative paths.
    static func entries(under vaultRoot: URL, since: Date? = nil) -> [Entry] {
        let fm = FileManager.default
        guard let it = fm.enumerator(at: vaultRoot,
                                     includingPropertiesForKeys: [.contentModificationDateKey,
                                                                  .isRegularFileKey,
                                                                  .fileSizeKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                     errorHandler: nil) else { return [] }
        var out: [Entry] = []
        let rootPath = vaultRoot.standardized.path
        while let url = it.nextObject() as? URL {
            // Compute the relative path early so we can prefix-skip whole subtrees.
            let abs = url.standardized.path
            guard abs.hasPrefix(rootPath) else { continue }
            var rel = String(abs.dropFirst(rootPath.count))
            while rel.hasPrefix("/") { rel.removeFirst() }
            if isExcluded(rel) {
                it.skipDescendants()
                continue
            }
            guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey,
                                                                .contentModificationDateKey,
                                                                .fileSizeKey]),
                  vals.isRegularFile == true,
                  let mtime = vals.contentModificationDate else { continue }
            if let since, mtime <= since { continue }
            let size = vals.fileSize ?? 0
            out.append(Entry(path: rel, mtime: mtime, size: size))
        }
        return out
    }

    /// True iff `relativePath` (vault-root-relative, forward slashes) hits
    /// one of the skip prefixes.
    static func isExcluded(_ relativePath: String) -> Bool {
        var p = relativePath
        while p.hasPrefix("/") { p.removeFirst() }
        // Forbid path-escape via the relative-path mechanism — a `..` somewhere
        // would let a misbehaving peer write outside the vault.
        if p.contains("..") { return true }
        for prefix in excludedPrefixes {
            if p == prefix { return true }
            if p.hasPrefix(prefix) { return true }
        }
        return false
    }

    /// Resolve a vault-relative path to an absolute URL, refusing anything
    /// that escapes the vault root. Used by the server side to map an
    /// inbound `path` parameter to a real file location.
    static func absoluteURL(forRelative path: String, under vaultRoot: URL) -> URL? {
        guard !isExcluded(path) else { return nil }
        let cleaned = path.split(separator: "/").map(String.init).joined(separator: "/")
        guard !cleaned.isEmpty else { return nil }
        let candidate = vaultRoot.appendingPathComponent(cleaned).standardized
        // Confirm the resolved path still sits under the root — defends
        // against absolute paths or `..` segments slipping through.
        guard candidate.path.hasPrefix(vaultRoot.standardized.path) else { return nil }
        return candidate
    }
}
