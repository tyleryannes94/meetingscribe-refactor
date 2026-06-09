import Foundation

/// Central registry for Projects/Tasks JSON schema migrations (P0-5 / BE-18).
///
/// The persistence layer is already enveloped (`SchemaEnvelope`) and now passes
/// a typed `migrate` closure into every decode — but until this type existed no
/// closure was wired and all on-disk versions were pinned to `1`, so backward
/// compatibility relied *entirely* on "every new field is optional". That works
/// for additions but cannot rename a field, change a type, or split a struct
/// (e.g. moving `status` into a generic select property in a later phase).
///
/// This type makes the seam real and testable: when a file's on-disk schema
/// version is older than the code's current version, the matching transform
/// runs — after a one-time backup of the file — so structural changes can land
/// without breaking existing installs.
///
/// Each transform is `(payload, from, to) -> payload`. They are identity today
/// (no structural change has shipped), but the wiring + backup are in place and
/// unit-tested, so the *first* real migration is a one-line `steps` entry rather
/// than a persistence refactor.
enum TaskSchemaMigrations {

    // MARK: Per-type entry points (wired into ActionItemStore.decodeArray)

    static func actionItems(_ items: [ActionItem], from: Int, to: Int) -> [ActionItem] {
        migrate(items, from: from, to: to, steps: [:])
    }
    static func projects(_ projects: [Project], from: Int, to: Int) -> [Project] {
        migrate(projects, from: from, to: to, steps: [:])
    }
    static func labels(_ labels: [TaskLabel], from: Int, to: Int) -> [TaskLabel] {
        migrate(labels, from: from, to: to, steps: [:])
    }
    static func sections(_ sections: [ProjectSection], from: Int, to: Int) -> [ProjectSection] {
        migrate(sections, from: from, to: to, steps: [:])
    }
    static func initiatives(_ initiatives: [Initiative], from: Int, to: Int) -> [Initiative] {
        migrate(initiatives, from: from, to: to, steps: [:])
    }

    // MARK: Engine

    /// Applies an ordered chain of single-version steps from `from` to `to`.
    /// `steps[v]` transforms the payload at version `v` into version `v+1`;
    /// missing steps are identity. Walking one version at a time keeps each
    /// transform small and composable as the schema evolves.
    static func migrate<T>(_ payload: T, from: Int, to: Int,
                           steps: [Int: (T) -> T]) -> T {
        guard from < to else { return payload }
        var value = payload
        var v = max(from, 0)
        while v < to {
            if let step = steps[v] { value = step(value) }
            v += 1
        }
        return value
    }

    /// One-time, best-effort backup of a file that is about to be migrated, so a
    /// faulty transform can never destroy the only copy. Writes a sibling
    /// `<name>.v<from>-pre<to>.bak`; no-ops if a backup already exists. Never
    /// throws into the caller.
    static func backupBeforeMigration(_ url: URL, from: Int, to: Int) {
        let backup = url.deletingPathExtension()
            .appendingPathExtension("v\(from)-pre\(to).bak")
        guard !FileManager.default.fileExists(atPath: backup.path),
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.copyItem(at: url, to: backup)
    }
}
