import Foundation

/// Writes a portability manifest (`EXPORT.md`) at the vault root — the
/// local-first "leave anytime" guarantee (C3-8). Documents the on-disk layout
/// so the vault is legible and usable without MeetingScribe: every meeting is a
/// folder of plain Markdown + audio, every person a JSON+Markdown record.
enum VaultManifest {
    static let filename = "EXPORT.md"

    /// Write the manifest if it's missing. Cheap to call repeatedly — it only
    /// touches disk on first run for a given vault.
    static func ensure(at root: URL) {
        let dest = root.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? body.write(to: dest, atomically: true, encoding: .utf8)
    }

    /// Rewrite the manifest unconditionally (e.g. a Settings "regenerate" action).
    @discardableResult
    static func write(at root: URL) -> URL? {
        let dest = root.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try body.write(to: dest, atomically: true, encoding: .utf8)
            return dest
        } catch { return nil }
    }

    private static let body = """
    # Your MeetingScribe vault

    This folder is **yours**. Everything MeetingScribe stores lives here as open,
    human-readable files — no proprietary database, no lock-in. You can open it in
    Obsidian, grep it, back it up, or walk away with it at any time.

    ## Layout

    - `*/` — one folder per meeting, grouped by tag, named `YYYY-MM-DD-HHMM-Title`.
      - `<slug>.md` — the canonical note (YAML frontmatter + summary, action items,
        notes, transcript). Obsidian-native; attendees and people are `[[wikilinks]]`.
      - `summary.md`, `transcript.md`, `notes.md` — the raw sections.
      - `audio/` — the recorded `mic.m4a` / `system.m4a` and a `manifest.json`.
    - `people/<slug>/` — one folder per person: `person.json` (structured) plus a
      readable `.md` mirror.
    - `encounters/` — one JSON per logged encounter.
    - `_inbox/` — drop-folder for captures from iPhone Shortcuts / other sources.

    ## Frontmatter

    Meeting notes carry `title`, `date`, `calendar`, `attendees`, and `tags`, so they
    work directly with Obsidian Properties and Bases.

    ## Leaving

    Nothing here depends on the app. Copy this folder anywhere and your meetings,
    transcripts, audio, and people come with you.
    """
}
