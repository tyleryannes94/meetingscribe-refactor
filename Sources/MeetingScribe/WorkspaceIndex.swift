import Foundation

/// Phase 4 — the manager is the single place that knows about every linkable
/// thing, so entity enumeration, backlink scanning, and global search all live
/// here as an extension.
@available(macOS 14.0, *)
extension MeetingManager {

    /// Everything that can be @-mentioned or jumped to. Cheap — reads only
    /// in-memory state (no disk).
    func workspaceEntities() -> [WorkspaceEntity] {
        var out: [WorkspaceEntity] = []
        for m in pastMeetings {
            out.append(WorkspaceEntity(kind: .meeting, rawID: m.id,
                                       title: m.displayTitle,
                                       subtitle: Self.entityDateString(m.startDate),
                                       date: m.startDate))
        }
        for n in quickNotes {
            out.append(WorkspaceEntity(kind: .voiceNote, rawID: n.id,
                                       title: n.title,
                                       subtitle: n.snippet.isEmpty ? Self.entityDateString(n.createdAt) : n.snippet,
                                       date: n.createdAt))
        }
        for p in actionItems.projects {
            out.append(WorkspaceEntity(kind: .project, rawID: p.id,
                                       title: p.name,
                                       subtitle: p.status.label,
                                       date: p.updatedAt))
        }
        for i in actionItems.items {
            out.append(WorkspaceEntity(kind: .actionItem, rawID: i.id,
                                       title: i.title,
                                       subtitle: i.meetingTitle,
                                       date: i.dueDate ?? i.meetingDate))
        }
        // People are first-class linkable entities too — the search palette
        // and any future @-mention picker want them in the same catalog.
        for person in PeopleStore.shared.people {
            let subtitle = [person.role, person.company]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            out.append(WorkspaceEntity(
                kind: .person, rawID: person.id,
                title: person.displayName,
                subtitle: subtitle.isEmpty ? (person.primaryEmail.isEmpty ? "Person" : person.primaryEmail) : subtitle,
                date: person.lastInteractionAt ?? person.updatedAt))
        }
        return out
    }

    /// Resolves a `meetingscribe://` link back to the underlying Meeting (if
    /// it's a meeting link). Voice notes / projects / action items are routed
    /// by section, not opened as a meeting.
    func meeting(forEntityID rawID: String) -> Meeting? {
        pastMeetings.first { $0.id == rawID }
    }

    /// Async backlink scan: which meetings' notes/summaries — and which
    /// project bodies — contain a link to this meeting. Reads files off the
    /// main actor so a large library doesn't hitch the UI.
    func backlinks(toMeetingID id: String) async -> [WorkspaceEntity] {
        let target = WorkspaceLink.url(kind: .meeting, id: id).absoluteString
        // Resolve directories on the main actor (tag lookup is main-actor),
        // then hand plain Sendable structs to the detached reader.
        let probes: [BacklinkProbe] = pastMeetings.compactMap { m in
            guard m.id != id else { return nil }
            let dir = store.directory(for: m, primaryTag: tagStore.primaryTag(for: m))
            return BacklinkProbe(id: m.id, title: m.displayTitle, date: m.startDate, dir: dir)
        }
        let projects = actionItems.projects.map {
            ProjectProbe(id: $0.id, name: $0.name, body: $0.body, date: $0.updatedAt)
        }

        return await Task.detached(priority: .utility) {
            var out: [WorkspaceEntity] = []
            for p in probes {
                let notes = (try? String(contentsOf: p.dir.appendingPathComponent("notes.md"), encoding: .utf8)) ?? ""
                let summary = (try? String(contentsOf: p.dir.appendingPathComponent("summary.md"), encoding: .utf8)) ?? ""
                if notes.contains(target) || summary.contains(target) {
                    out.append(WorkspaceEntity(kind: .meeting, rawID: p.id,
                                               title: p.title,
                                               subtitle: "Linked from notes",
                                               date: p.date))
                }
            }
            for p in projects where p.body.contains(target) {
                out.append(WorkspaceEntity(kind: .project, rawID: p.id,
                                           title: p.name,
                                           subtitle: "Linked from project",
                                           date: p.date))
            }
            return out
        }.value
    }

    /// Fast, in-memory global search across meetings, voice notes, projects,
    /// action items, people (including memories + attached notes), and tags.
    /// Ranked: title prefix > title contains > body/other contains.
    ///
    /// Special query syntax:
    ///   - `#tag-name`  → only return entities tagged with that name.
    ///   - Natural-language queries longer than 3 words always append a
    ///     "chatQuery" result at the bottom that routes the text to the
    ///     in-app Chat. Lets the user say "review texts with Horst" and
    ///     either click the person directly OR fall through to the chat.
    func search(_ query: String, limit: Int = 40) -> [WorkspaceEntity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Tag-prefixed search: "#sprint" → all entities carrying that tag.
        if trimmed.hasPrefix("#"), trimmed.count > 1 {
            let raw = String(trimmed.dropFirst())
            return tagSearch(raw, limit: limit)
        }

        let q = trimmed.lowercased()
        // Token-by-token search lets us match "horst carreño" against
        // "Horst Carreño-Bauer" even though the literal substring
        // "horst carreño" doesn't appear (the ñ-byte sequence and the
        // word boundary tripped the old single-string contains() test).
        // Split on whitespace and dashes; drop empties.
        let qTokens = q.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
            .filter { !$0.isEmpty }

        // Diacritic-folded query for the final fallback. macOS's
        // `folding(options:.diacriticInsensitive)` strips accents so
        // "horst carreño-bauer" matches "carreno" too. Note: this only
        // helps the FALLBACK score — the cheaper prefix/contains tests
        // happen first.
        let qFolded = q.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                locale: .current)

        /// Returns nil when nothing matched, or a score where LOWER is
        /// better (sorted ascending). 0 = title prefix, 1 = title
        /// contains, 2 = title tokenwise, 3 = haystack contains,
        /// 4 = haystack tokenwise, 5 = diacritic-folded title match.
        func score(title: String, haystacks: [String]) -> Int? {
            let t = title.lowercased()
            if t.hasPrefix(q) { return 0 }
            if t.contains(q) { return 1 }
            // Token match against the title: ALL query tokens must appear
            // somewhere in the title. Catches "horst bauer" → "Horst
            // Carreño-Bauer" and "carreno bauer" → ditto.
            if qTokens.count > 1, qTokens.allSatisfy({ t.contains($0) }) {
                return 2
            }
            for h in haystacks where h.lowercased().contains(q) { return 3 }
            // Token match across any haystack field.
            if qTokens.count > 1 {
                let joined = haystacks.map { $0.lowercased() }.joined(separator: " ")
                if qTokens.allSatisfy({ joined.contains($0) }) { return 4 }
            }
            // Diacritic-insensitive fallback for names like "Carreño"
            // where a user might type "carreno". Cheap (one fold per
            // call) and only runs if everything above missed.
            let tFolded = t.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                    locale: .current)
            if tFolded.contains(qFolded) { return 5 }
            return nil
        }

        var scored: [(Int, WorkspaceEntity)] = []
        for m in pastMeetings {
            if let s = score(title: m.displayTitle, haystacks: m.attendees + [m.userDescription ?? ""]) {
                scored.append((s, WorkspaceEntity(kind: .meeting, rawID: m.id,
                                                  title: m.displayTitle,
                                                  subtitle: Self.entityDateString(m.startDate),
                                                  date: m.startDate)))
            }
        }
        for n in quickNotes {
            if let s = score(title: n.title, haystacks: [n.snippet]) {
                scored.append((s, WorkspaceEntity(kind: .voiceNote, rawID: n.id,
                                                  title: n.title,
                                                  subtitle: n.snippet.isEmpty ? Self.entityDateString(n.createdAt) : n.snippet,
                                                  date: n.createdAt)))
            }
        }
        for p in actionItems.projects {
            if let s = score(title: p.name, haystacks: [p.body]) {
                scored.append((s, WorkspaceEntity(kind: .project, rawID: p.id,
                                                  title: p.name,
                                                  subtitle: p.status.label,
                                                  date: p.updatedAt)))
            }
        }
        for i in actionItems.items {
            if let s = score(title: i.title, haystacks: [i.meetingTitle, i.owner ?? "", i.notes ?? ""]) {
                scored.append((s, WorkspaceEntity(kind: .actionItem, rawID: i.id,
                                                  title: i.title,
                                                  subtitle: i.meetingTitle,
                                                  date: i.dueDate ?? i.meetingDate)))
            }
        }

        // People — plain in-memory contains() pass. We previously tried
        // (a) a custom scorer here and (b) delegating to
        // PeopleStore.filteredPeople which uses an FTS5 index. Both
        // dropped specific contacts (notably "Horst Carreño-Bauer"):
        // the FTS path returned arbitrary other people because
        // search_index was stale / mis-tokenized, and the custom scorer
        // had some subtle bug I couldn't reproduce. Plain in-memory
        // matching against the live `people` array is unambiguous —
        // if a person's name / email / phone / company / role / bio /
        // memories / attachedNotes contain the query string (case
        // insensitive, diacritic insensitive), they appear.
        let store = PeopleStore.shared
        let qFoldedPeople = q.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                      locale: .current)
        func matchesPerson(_ p: Person) -> Bool {
            let fields: [String] = [
                p.displayName, p.company, p.role, p.bio,
                p.emails.joined(separator: " "),
                p.phones.joined(separator: " "),
                p.memories.map(\.text).joined(separator: " "),
                p.attachedNotes.map { $0.title + " " + $0.body }.joined(separator: " ")
            ]
            for f in fields where !f.isEmpty {
                let lower = f.lowercased()
                if lower.contains(q) { return true }
                // Width-insensitive too in case Apple Contacts somewhere
                // produced full-width letters (Ｈorst etc.) — vanishingly
                // unlikely but a one-line guard.
                let folded = lower.folding(
                    options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                    locale: .current)
                if folded.contains(qFoldedPeople) { return true }
            }
            return false
        }

        for person in store.people where matchesPerson(person) {
            // Score 0 if the name itself starts with the query, 1 if the
            // name contains it elsewhere, 2 otherwise (email/memory match).
            let lowerName = person.displayName.lowercased()
            let s: Int
            if lowerName.hasPrefix(q) { s = 0 }
            else if lowerName.contains(q) { s = 1 }
            else { s = 2 }
            let subtitle = [person.role, person.company]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            scored.append((s, WorkspaceEntity(
                kind: .person, rawID: person.id,
                title: person.displayName,
                subtitle: subtitle.isEmpty ? (person.primaryEmail.isEmpty ? "Person" : person.primaryEmail) : subtitle,
                date: person.lastInteractionAt ?? person.updatedAt)))
            for note in person.attachedNotes {
                if let ns = score(title: note.title, haystacks: [note.body, person.displayName, note.kind]) {
                    scored.append((ns, WorkspaceEntity(
                        kind: .attachedNote,
                        rawID: "\(person.id)::\(note.id)",
                        title: note.title,
                        subtitle: "\(note.kind.uppercased()) · \(person.displayName)",
                        date: note.createdAt)))
                }
            }
        }

        var ranked = scored
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                let ld = lhs.1.date ?? .distantPast
                let rd = rhs.1.date ?? .distantPast
                return ld > rd
            }
            .prefix(limit)
            .map { $0.1 }

        // Natural-language passthrough: if the query reads like a question
        // ("review the texts with Horst", "what's pending with Acme"), give
        // the user a one-click route to send it to the in-app Chat. We
        // only show it when the query has at least 3 words so single-token
        // lookups don't get a noisy extra row.
        if trimmed.split(whereSeparator: { $0.isWhitespace }).count >= 3 {
            ranked.append(WorkspaceEntity(
                kind: .chatQuery,
                rawID: trimmed,
                title: "Ask Chat: \(trimmed)",
                subtitle: "Run this as a natural-language query in the assistant",
                date: nil))
        }
        return ranked
    }

    /// Tag-prefixed search. Matches the literal tag name (case-insensitive)
    /// across both meeting tags and people tags. Returns the meetings,
    /// people, and projects carrying that tag.
    private func tagSearch(_ name: String, limit: Int) -> [WorkspaceEntity] {
        let needle = name.lowercased()
        var out: [WorkspaceEntity] = []

        // Meetings.
        for m in pastMeetings {
            let names = tagStore.tags(for: m).map { $0.name.lowercased() }
            if names.contains(where: { $0 == needle || $0.contains(needle) }) {
                out.append(WorkspaceEntity(kind: .meeting, rawID: m.id,
                                           title: m.displayTitle,
                                           subtitle: "Tagged #\(name) · " + Self.entityDateString(m.startDate),
                                           date: m.startDate))
            }
        }

        // People (people use PeopleTagStore — separate from meeting tags).
        let peopleTags = PeopleTagStore.shared.allTags
        let matchedPeopleTagIDs = Set(peopleTags
            .filter { $0.name.lowercased() == needle || $0.name.lowercased().contains(needle) }
            .map { $0.id })
        for person in PeopleStore.shared.people {
            if !person.tagIDs.isDisjoint(with: matchedPeopleTagIDs) {
                let subtitle = [person.role, person.company]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                out.append(WorkspaceEntity(
                    kind: .person, rawID: person.id,
                    title: person.displayName,
                    subtitle: "Tagged #\(name)" + (subtitle.isEmpty ? "" : " · \(subtitle)"),
                    date: person.lastInteractionAt ?? person.updatedAt))
            }
        }

        return Array(out.prefix(limit))
    }

    static func entityDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: date)
    }
}

/// Sendable carriers for the detached backlink scan.
private struct BacklinkProbe: Sendable {
    let id: String
    let title: String
    let date: Date
    let dir: URL
}

private struct ProjectProbe: Sendable {
    let id: String
    let name: String
    let body: String
    let date: Date
}
