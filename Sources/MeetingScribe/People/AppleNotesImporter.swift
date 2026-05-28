import Foundation
import OSLog

/// Imports people from Apple Notes (Phase 7-B, no-Wi-Fi path).
///
/// The idea: on your iPhone, drop one note per person into a dedicated Notes
/// folder. Because Apple Notes syncs through iCloud, the same note appears on
/// the Mac, where MeetingScribe reads it via AppleScript and turns it into a
/// `Person`. No local network, no server — just iCloud sync you already have.
///
/// Note format (the title is the person's name; the body is `Key: value` lines):
///
///     Jane Doe                ← note title (or a "Name:" line)
///     Role: Head of Product
///     Company: Acme
///     Email: jane@acme.com
///     Phone: +1 555 123 4567
///     Tags: customer, conf2026
///     Notes: met at the booth, follow up in Q3
///
/// Any line that isn't a recognized `Key:` becomes part of the bio. Re-importing
/// is safe: existing people (matched by email or name) are updated, not
/// duplicated.
///
/// Requires Automation (Apple Events) permission to control Notes — granted on
/// first run. The app is not sandboxed and ships `NSAppleEventsUsageDescription`.
@MainActor
enum AppleNotesImporter {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "AppleNotesImport")

    /// Default Notes folder to read from.
    static let defaultFolder = "MeetingScribe"

    /// Recognized `Key:` prefixes inside a note body.
    private static let knownKeys: Set<String> = [
        "name", "role", "title", "company", "org", "organization",
        "email", "emails", "phone", "phones", "tags", "tag", "notes", "note", "bio"
    ]

    struct Candidate {
        var name: String
        var role: String = ""
        var company: String = ""
        var emails: [String] = []
        var phones: [String] = []
        var bio: String = ""
        var tagNames: [String] = []
    }

    struct ImportResult {
        var created: Int = 0
        var updated: Int = 0
        var scanned: Int = 0
        var error: String?
    }

    // MARK: - Fetch + parse

    /// Reads notes from `folder` via AppleScript and parses them into candidates.
    /// Returns an error string (for display) if Notes access fails or the folder
    /// is missing.
    static func fetchCandidates(folder: String = defaultFolder) -> (candidates: [Candidate], error: String?) {
        let safeFolder = folder.replacingOccurrences(of: "\"", with: "")
                               .replacingOccurrences(of: "\\", with: "")
        let source = """
        tell application "Notes"
            if not (exists folder "\(safeFolder)") then return "__NO_FOLDER__"
            set output to ""
            repeat with n in notes of folder "\(safeFolder)"
                set output to output & "===MS-NOTE===" & (name of n) & "
        ---MS-BODY---
        " & (plaintext of n) & "
        "
            end repeat
            return output
        end tell
        """
        guard let script = NSAppleScript(source: source) else {
            return ([], "Couldn't build the Apple Notes script.")
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            let msg = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Apple Notes access failed."
            log.error("Apple Notes script failed (\(code)): \(msg, privacy: .public)")
            if code == -1743 {
                return ([], "MeetingScribe isn't allowed to control Notes. Grant it in System Settings → Privacy & Security → Automation, then try again.")
            }
            return ([], msg)
        }
        let raw = descriptor.stringValue ?? ""
        if raw.trimmingCharacters(in: .whitespacesAndNewlines) == "__NO_FOLDER__" {
            return ([], "No Apple Notes folder named “\(folder)”. Create it on your iPhone (or Mac) and add one note per person.")
        }
        return (parse(raw), nil)
    }

    static func parse(_ raw: String) -> [Candidate] {
        raw.components(separatedBy: "===MS-NOTE===")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { block in
                let parts = block.components(separatedBy: "---MS-BODY---")
                let title = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let body = parts.count > 1 ? parts[1] : ""
                return candidate(title: title, body: body)
            }
    }

    private static func candidate(title: String, body: String) -> Candidate? {
        var fields: [String: String] = [:]
        var extraLines: [String] = []
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if knownKeys.contains(key) {
                    fields[key] = value
                    continue
                }
            }
            extraLines.append(trimmed)
        }

        let name = (fields["name"] ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        var bioParts: [String] = []
        if let n = fields["notes"] ?? fields["note"] ?? fields["bio"], !n.isEmpty { bioParts.append(n) }
        bioParts.append(contentsOf: extraLines)

        return Candidate(
            name: name,
            role: fields["role"] ?? fields["title"] ?? "",
            company: fields["company"] ?? fields["org"] ?? fields["organization"] ?? "",
            emails: splitList(fields["email"] ?? fields["emails"] ?? ""),
            phones: splitList(fields["phone"] ?? fields["phones"] ?? ""),
            bio: bioParts.joined(separator: "\n"),
            tagNames: splitList(fields["tags"] ?? fields["tag"] ?? "")
        )
    }

    private static func splitList(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Import into the People store

    /// Fetches and imports, deduping against existing people (match by shared
    /// email or exact normalized name). Existing people are updated in place.
    @discardableResult
    static func importToStore(folder: String = defaultFolder,
                              store: PeopleStore = .shared,
                              tagStore: PeopleTagStore = .shared) -> ImportResult {
        let (candidates, error) = fetchCandidates(folder: folder)
        if let error { return ImportResult(error: error) }
        guard !candidates.isEmpty else {
            return ImportResult(scanned: 0, error: "No notes found in “\(folder)”.")
        }

        var created = 0, updated = 0
        for c in candidates {
            let tagIDs = Set(c.tagNames.map { tagStore.createTag(name: $0).id })
            if let existing = match(c, in: store.people) {
                var p = existing
                p.emails = mergedUnique(p.emails, c.emails)
                p.phones = mergedUnique(p.phones, c.phones)
                if p.company.isEmpty { p.company = c.company }
                if p.role.isEmpty { p.role = c.role }
                if !c.bio.isEmpty, !p.bio.contains(c.bio) {
                    p.bio = p.bio.isEmpty ? c.bio : p.bio + "\n" + c.bio
                }
                p.tagIDs.formUnion(tagIDs)
                p.importSources.insert("apple-notes")
                store.updatePerson(p)
                updated += 1
            } else {
                store.createPerson(displayName: c.name,
                                   company: c.company,
                                   role: c.role,
                                   email: c.emails.first ?? "",
                                   phone: c.phones.first ?? "",
                                   bio: c.bio,
                                   tagIDs: tagIDs)
                created += 1
            }
        }
        log.info("Apple Notes import: \(created) created, \(updated) updated, \(candidates.count) scanned")
        return ImportResult(created: created, updated: updated, scanned: candidates.count)
    }

    private static func match(_ c: Candidate, in people: [Person]) -> Person? {
        let emails = Set(c.emails.map(PersonMatching.normalizeEmail).filter { !$0.isEmpty })
        if !emails.isEmpty,
           let hit = people.first(where: { !emails.isDisjoint(with: Set($0.emails.map(PersonMatching.normalizeEmail))) }) {
            return hit
        }
        let name = PersonMatching.normalizeName(c.name)
        return people.first(where: { PersonMatching.normalizeName($0.displayName) == name })
    }

    private static func mergedUnique(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for v in a + b {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
            out.append(t)
        }
        return out
    }
}
