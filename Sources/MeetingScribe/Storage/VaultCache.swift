import Foundation
import VaultKit

/// A small, safe cache layer for per-surface launch snapshots and other derived
/// data (V5 PC-3). Gives the ad-hoc JSON caches the safety SQLite already has:
/// a versioned envelope, atomic writes, optional TTL, and corruption-recovery
/// (a bad/old/garbage file just reads back as `nil`, never throws). This is the
/// foundation the Launch Snapshot (PC-1) renders from on frame 0.
enum VaultCache {
    /// Root: `<storageDir>/_cache/`. Travels with the vault but is fully
    /// disposable — every entry is derived from canonical data.
    static func cacheRoot() -> URL {
        AppSettings.shared.storageDir.appendingPathComponent("_cache", isDirectory: true)
    }

    private struct Envelope<T: Codable>: Codable {
        var version: Int
        var savedAt: Date
        var payload: T
    }

    private static func url(for name: String) -> URL {
        cacheRoot().appendingPathComponent("\(name).json")
    }

    /// Persist `value` atomically under `name`, stamped with `version` + now.
    /// Best-effort: failures are swallowed (the cache is never authoritative).
    static func save<T: Codable>(_ value: T, name: String, version: Int, now: Date = Date()) {
        let env = Envelope(version: version, savedAt: now, payload: value)
        do {
            try FileManager.default.createDirectory(at: cacheRoot(), withIntermediateDirectories: true)
            let data = try SharedCoders.encoder(pretty: false, sorted: false).encode(env)
            try data.write(to: url(for: name), options: .atomic)
        } catch {
            // Disposable cache — drop silently.
        }
    }

    /// Load the snapshot for `name`. Returns nil if missing, corrupt, a stale
    /// schema (`version` mismatch), or older than `maxAge` (when provided).
    static func load<T: Codable>(_ type: T.Type, name: String, version: Int,
                                 maxAge: TimeInterval? = nil, now: Date = Date()) -> T? {
        guard let data = try? Data(contentsOf: url(for: name)),
              let env = try? SharedCoders.decoder().decode(Envelope<T>.self, from: data),
              env.version == version else { return nil }
        if let maxAge, now.timeIntervalSince(env.savedAt) > maxAge { return nil }
        return env.payload
    }

    /// Drop a single cached entry (e.g. after an invalidating edit).
    static func invalidate(name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}
