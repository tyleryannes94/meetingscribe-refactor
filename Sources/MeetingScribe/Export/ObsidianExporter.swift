import Foundation
import AppKit

/// Converts a meeting into Obsidian-flavored markdown — YAML frontmatter,
/// `[[wikilinks]]` for the people who attended, and `#tags` — then writes it to
/// the configured vault (or prompts with a save panel when no vault is set).
///
/// In addition to the optional external-vault export, `writeMarkdownFile(for:to:)`
/// always writes a `{slug}.md` file directly inside the meeting's own folder
/// (alongside `meeting.json`). This is called automatically after every
/// meeting save / transcription.
enum ObsidianExporter {

    // MARK: - In-folder automatic markdown

    /// Builds the canonical meeting markdown and writes it to `{meetingFolder}/{slug}.md`.
    /// Reads transcript, summary, notes, and action items from the files already present
    /// in `meetingFolderURL`. Safe to call repeatedly — atomically overwrites.
    ///
    /// C3-1: this now routes through the rich `markdown(for:)` builder so the
    /// on-disk file is the Obsidian-native one — `attendees:` frontmatter, real
    /// `[[wikilinks]]`, inline `#tags`, and a `## People` section. `tags` must
    /// be the meeting's real tag names (from TagStore); the previous behavior
    /// scraped them from the folder name, which shipped the date-partition
    /// segment (e.g. `2026-05`) as a bogus tag.
    @discardableResult
    static func writeMarkdownFile(for meeting: Meeting,
                                  to meetingFolderURL: URL,
                                  tags: [String]? = nil) -> URL? {
        func readFile(_ name: String) -> String {
            let url = meetingFolderURL.appendingPathComponent(name)
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }

        let summary    = readFile("summary.md")
        let transcript = readFile("transcript.md")
        let userNotes  = readFile("notes.md")
        let resolvedTags = tags ?? folderTagFallback(meetingFolderURL)
        let actionItems = readActionItems(in: meetingFolderURL)

        let md = markdown(for: meeting,
                          summary: summary,
                          notes: userNotes,
                          transcript: transcript,
                          tags: resolvedTags,
                          actionItems: actionItems)

        let dest = meetingFolderURL.appendingPathComponent("\(meeting.slug).md")
        do {
            try md.write(to: dest, atomically: true, encoding: .utf8)
            return dest
        } catch {
            return nil
        }
    }

    /// Action-item titles read from the meeting folder's `action-items.json`.
    private static func readActionItems(in meetingFolderURL: URL) -> [String] {
        let url = meetingFolderURL.appendingPathComponent("action-items.json")
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            return []
        }
        return items.compactMap { $0["title"] ?? $0["text"] ?? $0["body"] }
    }

    /// Fallback when the caller didn't supply tags: use the parent folder name,
    /// but never a date-partition segment like `2026-05` or the `Untagged`
    /// bucket (those are layout artifacts, not real tags). (C3-1)
    private static func folderTagFallback(_ meetingFolderURL: URL) -> [String] {
        let name = meetingFolderURL.deletingLastPathComponent().lastPathComponent
        if name == "Untagged" || name.isEmpty { return [] }
        // YYYY or YYYY-MM date partition → not a tag.
        if name.range(of: #"^\d{4}(-\d{2})?$"#, options: .regularExpression) != nil { return [] }
        return [name]
    }

    // MARK: - Obsidian-vault export (external)

    /// Build the markdown document for `meeting`. `tags` are emitted both in
    /// frontmatter and as inline `#hashtags`; attendees become `[[wikilinks]]`
    /// so they resolve to (or create) per-person notes in the vault.
    static func markdown(for meeting: Meeting,
                         summary: String,
                         notes: String,
                         transcript: String,
                         tags: [String],
                         actionItems: [String] = []) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let dateStr = iso.string(from: meeting.startDate)

        let people = meeting.attendees
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let allTags = (["meeting"] + tags).map(sanitizeTag).uniqued()

        var out = ""

        // --- Frontmatter ---
        out += "---\n"
        out += "title: \"\(meeting.displayTitle.replacingOccurrences(of: "\"", with: "'"))\"\n"
        out += "date: \(dateStr)\n"
        if let cal = meeting.calendarName { out += "calendar: \"\(cal)\"\n" }
        if !people.isEmpty {
            out += "attendees:\n"
            for p in people { out += "  - \"\(p)\"\n" }
        }
        out += "tags: [\(allTags.joined(separator: ", "))]\n"
        out += "---\n\n"

        // --- Title + tag line ---
        out += "# \(meeting.displayTitle)\n\n"
        out += allTags.map { "#\($0)" }.joined(separator: " ") + "\n\n"

        // --- People (wikilinks) ---
        if !people.isEmpty {
            out += "## People\n\n"
            out += people.map { "- [[\($0)]]" }.joined(separator: "\n") + "\n\n"
        }

        // --- Body sections ---
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += "## Summary\n\n\(summary)\n\n"
        }
        if !actionItems.isEmpty {
            out += "## Action Items\n\n"
            out += actionItems.map { "- [ ] \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += "## Notes\n\n\(notes)\n\n"
        }
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += "## Transcript\n\n\(transcript)\n"
        }
        return out
    }

    /// Write `markdown` into the vault configured in `ExportSettings`. If no
    /// vault path is set (or it no longer exists), fall back to a save panel.
    /// Returns the written file URL, or nil if the user cancelled / it failed.
    @MainActor
    @discardableResult
    static func export(_ markdown: String, filename: String,
                       settings: ExportSettings = ExportSettings()) -> URL? {
        let safeName = filename.isEmpty ? "meeting" : filename
        let fm = FileManager.default

        if let vault = settings.vaultURL,
           fm.fileExists(atPath: vault.path) {
            let dest = vault.appendingPathComponent("\(safeName).md")
            do {
                try markdown.write(to: dest, atomically: true, encoding: .utf8)
                return dest
            } catch {
                NSSound.beep()
                return nil
            }
        }

        // No vault configured — let the user pick where to drop it.
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeName).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Helpers

    /// Obsidian tags can't contain spaces; collapse to kebab/camel.
    private static func sanitizeTag(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let collapsed = trimmed.replacingOccurrences(of: " ", with: "-")
        return collapsed.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "/" }
    }
}

private extension Array where Element == String {
    /// Order-preserving de-dup.
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted && !$0.isEmpty }
    }
}
