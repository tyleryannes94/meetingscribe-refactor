import Foundation

/// Schema-version migration table for `brain_dump_sessions.json`.
///
/// Mirrors the shape of `TaskSchemaMigrations` so the next schema bump is a
/// single case here. v1 is the initial shape; there's nothing to migrate yet.
enum BrainDumpSchemaMigrations {
    static let currentVersion = 1

    /// Bring an envelope at any prior version forward to the current version.
    /// No-op when already current.
    static func migrate(envelope: BrainDumpSessionEnvelope) -> BrainDumpSessionEnvelope {
        var e = envelope
        // Future bumps: switch on e.schemaVersion and transform e.data in place.
        e.schemaVersion = currentVersion
        return e
    }
}
