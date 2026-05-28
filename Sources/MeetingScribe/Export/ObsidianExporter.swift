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
    @discardableResult
    static func writeMarkdownFile(for meeting: Meeting, to meetingFolderURL: URL) -> URL? {
        let fm = FileManager.default

        func readFile(_ name: String) -> String {
            let url = meetingFolderURL.appendingPathComponent(name)
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }

        let summary    = readFile("summary.md")
        let transcript = readFile("transcript.md")
        let userNotes  = readFile("notes.md")

        // Duration in whole minutes
        let durationMinutes = Int(meeting.endDate.timeIntervalSince(meeting.startDate) / 60)

        // Tags — derive from the folder name (one level up from meeting slug)
        let tagFolderName = meetingFolderURL.deletingLastPathComponent().lastPathComponent
        let tagList = tagFolderName == "Untagged" ? "" : tagFolderName

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let dateStr = iso.string(from: meeting.startDate)

        // Build YAML frontmatter + body using the requested template
        var md = ""
        md += "---\n"
        md += "id: \(meeting.id)\n"
        md += "title: \(meeting.displayTitle)\n"
        md += "date: \(dateStr)\n"
        md += "duration: \(durationMinutes)m\n"
        md += "tags: \(tagList)\n"
        md += "---\n\n"

        md += "## Summary\n\n"
        let summaryTrimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        md += summaryTrimmed.isEmpty ? "Pending transcription…" : summaryTrimmed
        md += "\n\n"

        md += "## Action Items\n\n"
        // Parse action items from the summary/transcript or fall back to "None yet."
        let actionItemsURL = meetingFolderURL.appendingPathComponent("action-items.json")
        var actionItemsText = "None yet."
        if fm.fileExists(atPath: actionItemsURL.path),
           let data = try? Data(contentsOf: actionItemsURL),
           let items = try? JSONDecoder().decode([[String: String]].self, from: data),
           !items.isEmpty {
            actionItemsText = items
                .compactMap { $0["title"] ?? $0["text"] ?? $0["body"] }
                .map { "- [ ] \($0)" }
                .joined(separator: "\n")
        }
        md += actionItemsText + "\n\n"

        md += "## Transcript\n\n"
        md += transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        md += "\n\n"

        md += "## Notes\n\n"
        md += userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        md += "\n"

        let dest = meetingFolderURL.appendingPathComponent("\(meeting.slug).md")
        do {
            try md.write(to: dest, atomically: true, encoding: .utf8)
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - Obsidian-vault export (external)

    /// Build the markdown document for `meeting`. `tags` are emitted both in
    /// frontmatter and as inline `#hashtags`; attendees become `[[wikilinks]]`
    /// so they resolve to (or create) per-person notes in the vault.
    static func markdown(for meeting: Meeting,
                         summary: String,
                         notes: String,
                         transcript: String,
                         tags: [String]) -> String {
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
