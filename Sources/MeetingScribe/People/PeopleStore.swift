import Foundation
import VaultKit
import OSLog
import Combine

/// The Phase A people graph: a `@MainActor` singleton holding every `Person`
/// and `Encounter` in memory, backed by JSON-on-disk under the workspace
/// storage dir. Mirrors the `TagStore` / `QuickNoteStore` conventions —
/// schema-versioned `SchemaEnvelope` payloads, `SharedCoders`, and
/// `ErrorReporter` on failure.
///
/// Disk layout (the human-readable "archive layer" the second-brain audit
/// calls for — readable in Finder if the app vanished):
///
///   <storageDir>/people/<slug>/person.json    canonical record
///   <storageDir>/people/<slug>/person.md       regenerated mirror
///   <storageDir>/encounters/<id>.json           one file per encounter
@MainActor
final class PeopleStore: ObservableObject {
    static let shared = PeopleStore()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "People")
    static let personSchemaVersion = 1
    static let encounterSchemaVersion = 1
    static let suggestionSchemaVersion = 1
    static let metaSchemaVersion = 1

    static let peopleFolder = "people"
    static let encountersFolder = "encounters"
    static let suggestionsFolder = "people-suggestions"

    /// Fuzzy-match thresholds for ingesting an extracted mention (audit §5.2).
    static let autoLinkThreshold = 0.85   // ≥ → silently link to existing person
    static let possibleMatchThreshold = 0.6 // ≥ (and < auto) → "is this X?" suggestion

    @Published private(set) var people: [Person] = []
    @Published private(set) var encounters: [Encounter] = []
    /// Pending auto-extraction suggestions awaiting confirm/dismiss (Phase B).
    @Published private(set) var suggestions: [PersonSuggestion] = []

    /// Signatures the user dismissed — never re-suggest these.
    private var dismissedSignatures: Set<String> = []
    /// Meeting IDs already run through extraction — so backfill doesn't pay the
    /// LLM cost again on every launch.
    private var extractedMeetingIDs: Set<String> = []

    /// SQLite + FTS5 query/index layer (audit §6). JSON stays canonical; this is
    /// a derived index. NOT touched during init (it must not reach into
    /// PeopleTagStore while that singleton may itself be initializing).
    private let db = SecondBrainDB()
    private var didBuildIndex = false

    init() {
        // Load OFF the main thread. With a large people graph (auto-extraction
        // can accumulate hundreds–thousands of person records), reading every
        // person.json synchronously here blocked app launch — `PeopleStore.shared`
        // is created during `MeetingScribeApp.body`, so the whole UI hung
        // ("not responding") until the read finished. `load()` now publishes its
        // results back on the main thread when ready.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.load() }

        // Keep a single combined cache file in sync so the NEXT launch reads one
        // file instead of thousands. Debounced; snapshots values on the main
        // thread, writes off-main.
        cacheCancellable = Publishers.CombineLatest3($people, $encounters, $suggestions)
            .dropFirst()                          // ignore the initial empty state
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] p, e, s in
                guard let self else { return }
                let snapshot = Cache(people: p, encounters: e, suggestions: s,
                                     dismissedSignatures: Array(self.dismissedSignatures),
                                     extractedMeetingIDs: Array(self.extractedMeetingIDs))
                DispatchQueue.global(qos: .utility).async { self.writeCache(snapshot) }
            }
    }

    private var cacheCancellable: AnyCancellable?

    // MARK: - Index (SQLite/FTS5)

    private func tagNameResolver(_ id: String) -> String? { PeopleTagStore.shared.tag(by: id)?.name }
    func encounterCount(for personID: String) -> Int { encounters.reduce(0) { $1.personID == personID ? $0 + 1 : $0 } }

    /// Rebuild the whole index from canonical in-memory data. Idempotent.
    func rebuildIndex() {
        db.rebuild(people: people, encounters: encounters, tagName: tagNameResolver)
    }

    /// Build the index once per session (called from the People tab on appear).
    func rebuildIndexIfNeeded() {
        guard !didBuildIndex else { return }
        didBuildIndex = true
        rebuildIndex()
    }

    private func syncIndex(_ person: Person) {
        db.upsertPerson(person, encounterCount: encounterCount(for: person.id), tagName: tagNameResolver)
    }

    // MARK: - Unified vault FTS (meetings + voice notes)

    /// Index a meeting into vault_fts so GlobalSearch can find it.
    /// Call after the pipeline finishes (transcript + summary ready).
    func indexMeeting(_ meeting: Meeting, summary: String, tags: String?) {
        let epoch = Int64(meeting.startDate.timeIntervalSince1970)
        let body = summary.isEmpty ? nil : summary
        db.upsertVaultContent(entityID: meeting.id,
                              entityKind: "meeting",
                              title: meeting.displayTitle,
                              body: body,
                              dateEpoch: epoch,
                              tags: tags)
    }

    /// Index a voice note into vault_fts.
    func indexVoiceNote(id: String, title: String, transcript: String?, createdAt: Date) {
        let epoch = Int64(createdAt.timeIntervalSince1970)
        db.upsertVaultContent(entityID: id,
                              entityKind: "voice_note",
                              title: title,
                              body: transcript,
                              dateEpoch: epoch,
                              tags: nil)
    }

    /// Remove a meeting from vault_fts (e.g. on delete).
    func deindexMeeting(id: String) {
        db.deleteVaultContent(entityID: id, entityKind: "meeting")
    }

    /// FTS5-backed recall (BM25 + recency) across indexed vault content —
    /// meetings, voice notes, and people. This is the engine global search now
    /// runs on instead of an in-memory `contains()` scan. (C2-1)
    func searchVault(_ query: String, limit: Int = 50) -> [VaultSearchResult] {
        db.searchAll(query: query, limit: limit)
    }

    /// How many meetings are currently in the FTS index. 0 with meetings on disk
    /// signals the index was rebuilt/reset and needs a meeting backfill. (C2-1)
    func indexedMeetingCount() -> Int { db.vaultContentCount(kind: "meeting") }

    // MARK: - Paths

    private var peopleRoot: URL {
        AppSettings.shared.storageDir.appendingPathComponent(Self.peopleFolder, isDirectory: true)
    }

    private var encountersRoot: URL {
        AppSettings.shared.storageDir.appendingPathComponent(Self.encountersFolder, isDirectory: true)
    }

    private func directory(for person: Person) -> URL {
        peopleRoot.appendingPathComponent(person.slug, isDirectory: true)
    }

    private func fileURL(for encounter: Encounter) -> URL {
        encountersRoot.appendingPathComponent("\(encounter.id).json")
    }

    private var suggestionsRoot: URL {
        AppSettings.shared.storageDir.appendingPathComponent(Self.suggestionsFolder, isDirectory: true)
    }

    private func fileURL(for suggestion: PersonSuggestion) -> URL {
        suggestionsRoot.appendingPathComponent("\(suggestion.id).json")
    }

    private var metaURL: URL {
        suggestionsRoot.appendingPathComponent("_meta.json")
    }

    // MARK: - Load

    /// Reads all records (runs off the main thread — see `init`), then publishes
    /// the `@Published` arrays back on the main thread so SwiftUI observers
    /// update safely.
    ///
    /// FAST PATH: a single combined cache file (`_people-cache.json`) is read in
    /// one shot. Reading thousands of individual `person.json` files at launch
    /// took *minutes* on machines where every file `open()` is intercepted by a
    /// scanner — which made People look empty after relaunch. The per-person
    /// files remain canonical; the cache is a derived, always-rewritten mirror.
    private func load() {
        if let cache = readCache() {
            publishLoaded(people: cache.people, encounters: cache.encounters,
                          suggestions: cache.suggestions,
                          dismissed: Set(cache.dismissedSignatures),
                          extracted: Set(cache.extractedMeetingIDs))
            return
        }
        // No cache (first run / upgrade): one-time slow per-file scan, then seed
        // the cache so every later launch is instant.
        let loadedPeople = loadPeople().sorted(by: Self.recencyThenName)
        let loadedEncounters = loadEncounters().sorted { $0.date > $1.date }
        let meta = loadMetaValues()
        let loadedSuggestions = loadSuggestions().sorted { $0.meetingDate > $1.meetingDate }
        publishLoaded(people: loadedPeople, encounters: loadedEncounters,
                      suggestions: loadedSuggestions,
                      dismissed: meta.dismissed, extracted: meta.extracted)
        writeCache(Cache(people: loadedPeople, encounters: loadedEncounters,
                         suggestions: loadedSuggestions,
                         dismissedSignatures: Array(meta.dismissed),
                         extractedMeetingIDs: Array(meta.extracted)))
    }

    private func publishLoaded(people: [Person], encounters: [Encounter],
                               suggestions: [PersonSuggestion],
                               dismissed: Set<String>, extracted: Set<String>) {
        let publish: () -> Void = { [weak self] in
            guard let self else { return }
            self.people = people.sorted(by: Self.recencyThenName)
            self.encounters = encounters.sorted { $0.date > $1.date }
            self.dismissedSignatures = dismissed
            self.extractedMeetingIDs = extracted
            self.suggestions = suggestions.sorted { $0.meetingDate > $1.meetingDate }
            // One-time cleanup of the duplicate backlog created before the load
            // fix (re-imports duplicated because the list wasn't loaded yet to
            // dedupe against). Runs once; the manual "Merge duplicates" action
            // calls the same path and is safe to re-run.
            if !UserDefaults.standard.bool(forKey: "peopleDedupV1") {
                UserDefaults.standard.set(true, forKey: "peopleDedupV1")
                let r = self.deduplicate()
                if r.removed > 0 { self.log.info("One-time dedup removed \(r.removed, privacy: .public) duplicate(s)") }
            }
            // E3-4: if the derived index was corrupt and got recreated empty on
            // open, repopulate it now from the canonical JSON we just loaded.
            if self.db.needsRebuild {
                self.rebuildIndex()
                self.didBuildIndex = true
                self.db.clearNeedsRebuild()
            }
        }
        if Thread.isMainThread { publish() } else { DispatchQueue.main.async(execute: publish) }
    }

    // MARK: - Combined cache (single-file fast path)

    private struct Cache: Codable {
        var people: [Person]
        var encounters: [Encounter]
        var suggestions: [PersonSuggestion]
        var dismissedSignatures: [String]
        var extractedMeetingIDs: [String]
    }

    private var cacheURL: URL { peopleRoot.deletingLastPathComponent().appendingPathComponent("_people-cache.json") }

    private func readCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? SharedCoders.decoder().decode(Cache.self, from: data)
    }

    private func writeCache(_ cache: Cache) {
        do {
            let data = try SharedCoders.encoder(pretty: false, sorted: false).encode(cache)
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            log.error("Failed to write people cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadPeople() -> [Person] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: peopleRoot,
                                                includingPropertiesForKeys: [.isDirectoryKey],
                                                options: [.skipsHiddenFiles])) ?? []
        var result: [Person] = []
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let url = dir.appendingPathComponent("person.json")
            guard let data = try? Data(contentsOf: url) else { continue }
            if let p: Person = try? SchemaEnvelope.decode(
                Person.self, from: data,
                currentVersion: Self.personSchemaVersion,
                decoder: SharedCoders.decoder()
            ) {
                result.append(p)
            }
        }
        return result
    }

    private func loadEncounters() -> [Encounter] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: encountersRoot,
                                                 includingPropertiesForKeys: nil,
                                                 options: [.skipsHiddenFiles])) ?? []
        var result: [Encounter] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let e: Encounter = try? SchemaEnvelope.decode(
                Encounter.self, from: data,
                currentVersion: Self.encounterSchemaVersion,
                decoder: SharedCoders.decoder()
            ) {
                result.append(e)
            }
        }
        return result
    }

    private func loadSuggestions() -> [PersonSuggestion] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: suggestionsRoot,
                                                 includingPropertiesForKeys: nil,
                                                 options: [.skipsHiddenFiles])) ?? []
        var result: [PersonSuggestion] = []
        for url in files where url.pathExtension == "json" && url.lastPathComponent != "_meta.json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let s: PersonSuggestion = try? SchemaEnvelope.decode(
                PersonSuggestion.self, from: data,
                currentVersion: Self.suggestionSchemaVersion,
                decoder: SharedCoders.decoder()
            ) {
                result.append(s)
            }
        }
        return result
    }

    private struct Meta: Codable {
        var dismissedSignatures: [String]
        var extractedMeetingIDs: [String]
    }

    private func loadMetaValues() -> (dismissed: Set<String>, extracted: Set<String>) {
        guard let data = try? Data(contentsOf: metaURL),
              let meta: Meta = try? SchemaEnvelope.decode(
                Meta.self, from: data,
                currentVersion: Self.metaSchemaVersion,
                decoder: SharedCoders.decoder()) else { return ([], []) }
        return (Set(meta.dismissedSignatures), Set(meta.extractedMeetingIDs))
    }

    private func persistMeta() {
        let meta = Meta(dismissedSignatures: Array(dismissedSignatures),
                        extractedMeetingIDs: Array(extractedMeetingIDs))
        do {
            try FileManager.default.createDirectory(at: suggestionsRoot, withIntermediateDirectories: true)
            let envelope = SchemaEnvelope(version: Self.metaSchemaVersion, data: meta)
            let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(envelope)
            try data.write(to: metaURL, options: .atomic)
        } catch {
            log.error("Failed to persist people meta: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage, context: ["phase": "persist-people-meta"])
        }
    }

    // MARK: - Person CRUD

    @discardableResult
    func createPerson(displayName: String,
                      company: String = "",
                      role: String = "",
                      email: String = "",
                      phone: String = "",
                      bio: String = "",
                      tagIDs: Set<String> = []) -> Person {
        let person = Person(displayName: displayName,
                            company: company,
                            role: role,
                            emails: email.isEmpty ? [] : [email],
                            phones: phone.isEmpty ? [] : [phone],
                            bio: bio,
                            tagIDs: tagIDs)
        people.append(person)
        people.sort(by: Self.recencyThenName)
        writePerson(person)
        return person
    }

    /// Persists an edited person. If the display name changed enough to change
    /// the slug, the old directory is removed so we don't orphan a folder.
    func updatePerson(_ updated: Person) {
        var next = updated
        next.updatedAt = Date()
        if let idx = people.firstIndex(where: { $0.id == next.id }) {
            let old = people[idx]
            if old.slug != next.slug {
                try? FileManager.default.removeItem(at: directory(for: old))
            }
            people[idx] = next
        } else {
            people.append(next)
        }
        people.sort(by: Self.recencyThenName)
        writePerson(next)
    }

    func deletePerson(_ person: Person) {
        people.removeAll { $0.id == person.id }
        try? FileManager.default.removeItem(at: directory(for: person))
        // Cascade: drop the person's encounters too.
        for e in encounters where e.personID == person.id {
            try? FileManager.default.removeItem(at: fileURL(for: e))
        }
        encounters.removeAll { $0.personID == person.id }
        // Drop reciprocal relationships pointing at the deleted person.
        for idx in people.indices where people[idx].relationships.contains(where: { $0.toPersonID == person.id }) {
            people[idx].relationships.removeAll { $0.toPersonID == person.id }
            writePerson(people[idx])
        }
        if didBuildIndex { db.deletePerson(person.id) }
    }

    func person(by id: String) -> Person? {
        people.first { $0.id == id }
    }

    private func writePerson(_ person: Person) {
        do {
            let dir = directory(for: person)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let envelope = SchemaEnvelope(version: Self.personSchemaVersion, data: person)
            let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(envelope)
            try data.write(to: dir.appendingPathComponent("person.json"), options: .atomic)
            try? markdownMirror(for: person)
                .write(to: dir.appendingPathComponent("person.md"), atomically: true, encoding: .utf8)
        } catch {
            log.error("Failed to persist person: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage,
                                        context: ["phase": "persist-person"])
        }
        if didBuildIndex { syncIndex(person) }
    }

    /// Off-main writer for bulk import — encodes + writes person.json without
    /// touching the actor (markdown mirror is regenerated on the next edit).
    nonisolated private static func persistPersonFile(_ person: Person, peopleRoot: URL) {
        let dir = peopleRoot.appendingPathComponent(person.slug, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let envelope = SchemaEnvelope(version: personSchemaVersion, data: person)
            let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(envelope)
            try data.write(to: dir.appendingPathComponent("person.json"), options: .atomic)
        } catch {
            // Best-effort; the in-memory record + index are authoritative for UI.
        }
    }

    // MARK: - Encounter CRUD

    @discardableResult
    func addEncounter(to personID: String,
                      eventName: String,
                      eventTagID: String? = nil,
                      date: Date = Date(),
                      location: String? = nil,
                      notes: String = "",
                      meetingID: String? = nil) -> Encounter {
        let encounter = Encounter(personID: personID,
                                  eventTagID: eventTagID,
                                  eventName: eventName,
                                  date: date,
                                  location: location,
                                  notes: notes,
                                  meetingID: meetingID)
        encounters.append(encounter)
        encounters.sort { $0.date > $1.date }
        writeEncounter(encounter)
        // Propagate the event tag onto the person and bump recency in a single
        // write, so "find everyone I met at <event>" works off `person.tagIDs`.
        if let idx = people.firstIndex(where: { $0.id == personID }) {
            if let eventTagID { people[idx].tagIDs.insert(eventTagID) }
            if (people[idx].lastInteractionAt ?? .distantPast) < date {
                people[idx].lastInteractionAt = date
            }
            writePerson(people[idx])
            people.sort(by: Self.recencyThenName)
        }
        return encounter
    }

    func deleteEncounter(_ encounter: Encounter) {
        encounters.removeAll { $0.id == encounter.id }
        try? FileManager.default.removeItem(at: fileURL(for: encounter))
        // Encounter count changed → refresh that person's relevance in the index.
        if didBuildIndex, let p = person(by: encounter.personID) { syncIndex(p) }
    }

    /// Encounters for a person, most recent first.
    func encounters(for personID: String) -> [Encounter] {
        encounters.filter { $0.personID == personID }.sorted { $0.date > $1.date }
    }

    private func writeEncounter(_ encounter: Encounter) {
        do {
            try FileManager.default.createDirectory(at: encountersRoot, withIntermediateDirectories: true)
            let envelope = SchemaEnvelope(version: Self.encounterSchemaVersion, data: encounter)
            let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(envelope)
            try data.write(to: fileURL(for: encounter), options: .atomic)
        } catch {
            log.error("Failed to persist encounter: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage,
                                        context: ["phase": "persist-encounter"])
        }
    }

    // MARK: - Import & merge (Phase C)

    /// Imports external person records, deduping against existing people.
    /// Match precedence: contact identifier → shared email → shared phone →
    /// exact normalized name. Merges union-style (never deletes existing data);
    /// only fills empty scalar fields. Returns (created, merged) counts.
    @discardableResult
    func importPeople(_ candidates: [PersonImport]) -> (created: Int, merged: Int) {
        var created = 0
        var merged = 0
        var affectedIDs: Set<String> = []
        // All in-memory (fast); disk writes are deferred off-main below so a
        // multi-thousand contact import doesn't block the UI.
        for c in candidates {
            let name = c.trimmedName
            guard !name.isEmpty else { continue }
            if let idx = matchIndex(for: c) {
                mergeImport(c, into: idx)
                affectedIDs.insert(people[idx].id)
                merged += 1
            } else {
                var person = Person(displayName: name,
                                    company: c.company,
                                    role: c.role,
                                    emails: dedupeEmails(c.emails),
                                    phones: c.phones,
                                    birthday: c.birthday,
                                    addresses: c.addresses,
                                    contactIdentifier: c.contactIdentifier,
                                    importSources: [c.source])
                if let data = c.photoData {
                    person = saveImportPhoto(data, ext: c.photoExt, into: person)
                }
                people.append(person)
                affectedIDs.insert(person.id)
                created += 1
            }
        }
        guard created > 0 || merged > 0 else { return (0, 0) }
        people.sort(by: Self.recencyThenName)
        log.info("Imported people: \(created) created, \(merged) merged")

        // Persist changed records off-main; refresh the index on-main (fast).
        let changed = people.filter { affectedIDs.contains($0.id) }
        let root = peopleRoot
        Task.detached(priority: .utility) {
            for p in changed { Self.persistPersonFile(p, peopleRoot: root) }
        }
        if didBuildIndex { rebuildIndex() }
        return (created, merged)
    }

    private func matchIndex(for c: PersonImport) -> Int? {
        if let cid = c.contactIdentifier,
           let i = people.firstIndex(where: { $0.contactIdentifier == cid }) { return i }
        let emails = Set(c.emails.map(PersonMatching.normalizeEmail))
        if !emails.isEmpty,
           let i = people.firstIndex(where: { !emails.isDisjoint(with: Set($0.emails.map(PersonMatching.normalizeEmail))) }) {
            return i
        }
        let phones = Set(c.phones.map(PersonMatching.normalizePhone).filter { $0.count >= 7 })
        if !phones.isEmpty,
           let i = people.firstIndex(where: { !phones.isDisjoint(with: Set($0.phones.map(PersonMatching.normalizePhone))) }) {
            return i
        }
        let name = PersonMatching.normalizeName(c.trimmedName)
        return people.firstIndex(where: { PersonMatching.normalizeName($0.displayName) == name })
    }

    private func mergeImport(_ c: PersonImport, into idx: Int) {
        var p = people[idx]
        p.emails = dedupeEmails(p.emails + c.emails)
        p.phones = dedupePhones(p.phones + c.phones)
        p.addresses = Array(NSOrderedSet(array: p.addresses + c.addresses).array as? [String] ?? p.addresses)
        if p.company.isEmpty { p.company = c.company }
        if p.role.isEmpty { p.role = c.role }
        if p.birthday == nil { p.birthday = c.birthday }
        if p.contactIdentifier == nil { p.contactIdentifier = c.contactIdentifier }
        p.importSources.insert(c.source)
        p.updatedAt = Date()
        if let data = c.photoData, p.photoRelativePaths.isEmpty {
            p = saveImportPhoto(data, ext: c.photoExt, into: p)
        }
        people[idx] = p
        // Note: caller (importPeople) persists + reindexes in batch.
    }

    private func dedupeEmails(_ emails: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for e in emails {
            let t = e.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(PersonMatching.normalizeEmail(t)).inserted else { continue }
            out.append(t)
        }
        return out
    }

    private func dedupePhones(_ phones: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in phones {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = PersonMatching.normalizePhone(t)
            guard !t.isEmpty, seen.insert(key.isEmpty ? t : key).inserted else { continue }
            out.append(t)
        }
        return out
    }

    // MARK: - Profile: memories & photos (Phase C)

    @discardableResult
    func addMemory(to personID: String, text: String, occurredOn: Date? = nil) -> Memory? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = people.firstIndex(where: { $0.id == personID }) else { return nil }
        let memory = Memory(text: trimmed, occurredOn: occurredOn)
        people[idx].memories.insert(memory, at: 0)
        people[idx].updatedAt = Date()
        writePerson(people[idx])
        return memory
    }

    func deleteMemory(_ memory: Memory, from personID: String) {
        guard let idx = people.firstIndex(where: { $0.id == personID }) else { return }
        people[idx].memories.removeAll { $0.id == memory.id }
        writePerson(people[idx])
    }

    /// Append a long-form note to a person — typically a chat analysis
    /// the user wanted to save. Newer notes go to the front so the most
    /// recent analysis renders first on the detail view. Returns the
    /// created note (with assigned id + timestamp) for the caller to
    /// echo back.
    @discardableResult
    func addAttachedNote(to personID: String,
                         title: String,
                         body: String,
                         kind: String = "custom") -> AttachedNote? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty,
              let idx = people.firstIndex(where: { $0.id == personID }) else { return nil }
        let note = AttachedNote(
            title: trimmedTitle.isEmpty ? "Untitled note" : trimmedTitle,
            body: trimmedBody,
            kind: kind.isEmpty ? "custom" : kind)
        people[idx].attachedNotes.insert(note, at: 0)
        people[idx].updatedAt = Date()
        writePerson(people[idx])
        return note
    }

    func deleteAttachedNote(_ note: AttachedNote, from personID: String) {
        guard let idx = people.firstIndex(where: { $0.id == personID }) else { return }
        people[idx].attachedNotes.removeAll { $0.id == note.id }
        writePerson(people[idx])
    }

    /// Drop any existing AttachedNote of the given kind for this person.
    /// Used by the "Refresh all-time analysis" flow so we don't end up
    /// with two cached "summary-all" notes after a rerun.
    func deleteCachedAllTimeNote(personID: String, kind: String) {
        guard let idx = people.firstIndex(where: { $0.id == personID }) else { return }
        let before = people[idx].attachedNotes.count
        people[idx].attachedNotes.removeAll { $0.kind == kind }
        if people[idx].attachedNotes.count != before {
            writePerson(people[idx])
        }
    }

    /// Copies image bytes into `<person>/photos/<uuid>.<ext>` and records the
    /// relative path. Returns the updated person.
    @discardableResult
    private func saveImportPhoto(_ data: Data, ext: String, into person: Person) -> Person {
        var p = person
        let rel = "photos/\(UUID().uuidString).\(ext)"
        let url = directory(for: p).appendingPathComponent(rel)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            p.photoRelativePaths.append(rel)
        } catch {
            log.error("Failed to write person photo: \(error.localizedDescription, privacy: .public)")
        }
        return p
    }

    /// Attaches a photo (from the file picker) to an existing person.
    @discardableResult
    func attachPhoto(to personID: String, data: Data, ext: String) -> Bool {
        guard let idx = people.firstIndex(where: { $0.id == personID }) else { return false }
        let updated = saveImportPhoto(data, ext: ext.isEmpty ? "jpg" : ext.lowercased(), into: people[idx])
        people[idx] = updated
        writePerson(updated)
        return true
    }

    func removePhoto(_ relativePath: String, from personID: String) {
        guard let idx = people.firstIndex(where: { $0.id == personID }) else { return }
        let url = directory(for: people[idx]).appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
        people[idx].photoRelativePaths.removeAll { $0 == relativePath }
        writePerson(people[idx])
    }

    /// Absolute URL for one of a person's attached photos.
    func photoURL(for person: Person, relativePath: String) -> URL {
        directory(for: person).appendingPathComponent(relativePath)
    }

    // MARK: - Relationships (§4.4)

    /// Adds a relationship A→B and mirrors the reciprocal B→A (bidirectional).
    func addRelationship(from a: String, to b: String, label: String) {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a != b, !label.isEmpty,
              let ai = people.firstIndex(where: { $0.id == a }),
              let bi = people.firstIndex(where: { $0.id == b }) else { return }
        if !people[ai].relationships.contains(where: { $0.toPersonID == b }) {
            people[ai].relationships.append(Relationship(toPersonID: b, label: label))
            writePerson(people[ai])
        }
        if !people[bi].relationships.contains(where: { $0.toPersonID == a }) {
            people[bi].relationships.append(Relationship(toPersonID: a, label: label))
            writePerson(people[bi])
        }
    }

    /// Removes a relationship and its reciprocal.
    func removeRelationship(_ relationship: Relationship, from personID: String) {
        guard let pi = people.firstIndex(where: { $0.id == personID }) else { return }
        let other = relationship.toPersonID
        people[pi].relationships.removeAll { $0.id == relationship.id }
        writePerson(people[pi])
        if let oi = people.firstIndex(where: { $0.id == other }) {
            people[oi].relationships.removeAll { $0.toPersonID == personID }
            writePerson(people[oi])
        }
    }

    // MARK: - Merge duplicates (§12.3)

    /// Merges `loser` into `keeper` (union everything, reassign encounters),
    /// then deletes `loser`. Used by the duplicate-review surface.
    func mergePeople(keep keeperID: String, remove loserID: String) {
        guard keeperID != loserID,
              let ki = people.firstIndex(where: { $0.id == keeperID }),
              let loser = people.first(where: { $0.id == loserID }) else { return }
        var k = people[ki]
        k.emails = dedupeEmails(k.emails + loser.emails)
        k.phones = dedupePhones(k.phones + loser.phones)
        k.addresses = Array(NSOrderedSet(array: k.addresses + loser.addresses).array as? [String] ?? k.addresses)
        k.favorites = Array(NSOrderedSet(array: k.favorites + loser.favorites).array as? [String] ?? k.favorites)
        k.tagIDs.formUnion(loser.tagIDs)
        k.meetingMentions.formUnion(loser.meetingMentions)
        k.memories += loser.memories
        k.photoRelativePaths += loser.photoRelativePaths
        k.importSources.formUnion(loser.importSources)
        if k.company.isEmpty { k.company = loser.company }
        if k.role.isEmpty { k.role = loser.role }
        if k.bio.isEmpty { k.bio = loser.bio }
        if k.birthday == nil { k.birthday = loser.birthday }
        if k.contactIdentifier == nil { k.contactIdentifier = loser.contactIdentifier }
        for rel in loser.relationships where rel.toPersonID != keeperID
            && !k.relationships.contains(where: { $0.toPersonID == rel.toPersonID }) {
            k.relationships.append(rel)
        }
        people[ki] = k
        // Reassign the loser's encounters to the keeper.
        for i in encounters.indices where encounters[i].personID == loserID {
            encounters[i].personID = keeperID
            writeEncounter(encounters[i])
        }
        // Repoint anyone who had a relationship to the loser.
        for i in people.indices {
            var changed = false
            for j in people[i].relationships.indices where people[i].relationships[j].toPersonID == loserID {
                people[i].relationships[j].toPersonID = keeperID
                changed = true
            }
            if changed { writePerson(people[i]) }
        }
        writePerson(k)
        deletePerson(loser)
    }

    // MARK: - Bulk de-duplication

    /// Finds every set of duplicate people, **merges** each set's information
    /// into a single record (union of emails/phones/tags/memories/etc.), and
    /// **deletes the extras**. Returns (groups merged, records removed).
    ///
    /// Identity key (strongest first):
    ///   • same `contactIdentifier` — exact same contact (e.g. an Apple Contacts
    ///     re-import that created copies), or
    ///   • same normalized name + compatible email/phone (no conflicting one).
    /// Runs the merge in memory, then batches disk deletes/writes off-main.
    @discardableResult
    func deduplicate() -> (merged: Int, removed: Int) {
        // 1. Group by identity key.
        var groups: [String: [Person]] = [:]
        for p in people { groups[Self.identityKey(p), default: []].append(p) }

        var keepers: [String: Person] = [:]     // keeperID -> merged record
        var loserToKeeper: [String: String] = [:]
        for (_, members) in groups where members.count > 1 {
            // Keep the most-complete record (tie-break: earliest createdAt).
            var keeper = members.max {
                let a = Self.completeness($0), b = Self.completeness($1)
                return a != b ? a < b : $0.createdAt > $1.createdAt
            }!
            for m in members where m.id != keeper.id {
                keeper = mergeFields(keeper, m)
                loserToKeeper[m.id] = keeper.id
            }
            keepers[keeper.id] = keeper
        }
        guard !loserToKeeper.isEmpty else { return (0, 0) }

        // 2. Rebuild the people list (drop losers, swap in merged keepers).
        let removedSlugs = people.filter { loserToKeeper[$0.id] != nil }.map { $0.slug }
        var next = people.compactMap { p -> Person? in
            if loserToKeeper[p.id] != nil { return nil }
            return keepers[p.id] ?? p
        }
        // 3. Repoint relationships at merged-away people; drop self/dupes.
        for i in next.indices {
            var seen = Set<String>(); var out: [Relationship] = []
            for var r in next[i].relationships {
                if let k = loserToKeeper[r.toPersonID] { r.toPersonID = k }
                guard r.toPersonID != next[i].id, seen.insert(r.toPersonID).inserted else { continue }
                out.append(r)
            }
            next[i].relationships = out
        }
        // 4. Reassign any encounters off losers onto keepers.
        for i in encounters.indices where loserToKeeper[encounters[i].personID] != nil {
            encounters[i].personID = loserToKeeper[encounters[i].personID]!
        }

        let keepersToWrite = Array(keepers.values)
        people = next.sorted(by: Self.recencyThenName)

        // Write the combined cache IMMEDIATELY (don't rely on the debounced
        // writer) so a relaunch reflects the dedupe even if the app is quit
        // right after — otherwise the stale pre-dedupe cache would reload.
        let cacheSnapshot = Cache(people: people, encounters: encounters, suggestions: suggestions,
                                  dismissedSignatures: Array(dismissedSignatures),
                                  extractedMeetingIDs: Array(extractedMeetingIDs))
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.writeCache(cacheSnapshot) }

        // 5. Persist off-main: delete loser folders, rewrite merged keepers.
        let root = peopleRoot
        Task.detached(priority: .utility) {
            for slug in removedSlugs {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(slug, isDirectory: true))
            }
            for k in keepersToWrite { Self.persistPersonFile(k, peopleRoot: root) }
        }
        if didBuildIndex { rebuildIndex() }
        log.info("Deduplicated people: merged \(keepers.count) group(s), removed \(loserToKeeper.count) duplicate(s)")
        return (keepers.count, loserToKeeper.count)
    }

    /// How many duplicate records would be removed (for a confirm prompt) —
    /// cheap, in-memory, no writes.
    func duplicateCount() -> Int {
        var groups: [String: Int] = [:]
        for p in people { groups[Self.identityKey(p), default: 0] += 1 }
        return groups.values.reduce(0) { $0 + max(0, $1 - 1) }
    }

    private static func identityKey(_ p: Person) -> String {
        if let cid = p.contactIdentifier?.trimmingCharacters(in: .whitespaces), !cid.isEmpty {
            return "cid:\(cid)"
        }
        let name = PersonMatching.normalizeName(p.displayName)
        let email = p.emails.map(PersonMatching.normalizeEmail).filter { !$0.isEmpty }.sorted().first ?? ""
        let phone = p.phones.map(PersonMatching.normalizePhone).filter { $0.count >= 7 }.sorted().first ?? ""
        return "n:\(name)|e:\(email)|p:\(phone)"
    }

    /// Higher = richer record (used to choose the keeper).
    private static func completeness(_ p: Person) -> Int {
        var s = 0
        s += p.emails.count + p.phones.count + p.addresses.count + p.memories.count
        s += p.tagIDs.count + p.meetingMentions.count + p.relationships.count + p.photoRelativePaths.count
        if !p.company.isEmpty { s += 1 }
        if !p.role.isEmpty { s += 1 }
        if !p.bio.isEmpty { s += 1 }
        if p.birthday != nil { s += 1 }
        if p.contactIdentifier != nil { s += 1 }
        return s
    }

    /// Union `other`'s information into `keeper` (fills empty scalars, merges
    /// collections) without losing anything.
    private func mergeFields(_ keeper: Person, _ other: Person) -> Person {
        var k = keeper
        k.emails = dedupeEmails(k.emails + other.emails)
        k.phones = dedupePhones(k.phones + other.phones)
        k.addresses = Array(NSOrderedSet(array: k.addresses + other.addresses).array as? [String] ?? k.addresses)
        k.favorites = Array(NSOrderedSet(array: k.favorites + other.favorites).array as? [String] ?? k.favorites)
        k.tagIDs.formUnion(other.tagIDs)
        k.meetingMentions.formUnion(other.meetingMentions)
        k.importSources.formUnion(other.importSources)
        k.memories += other.memories
        k.photoRelativePaths += other.photoRelativePaths
        for rel in other.relationships where !k.relationships.contains(where: { $0.toPersonID == rel.toPersonID }) {
            k.relationships.append(rel)
        }
        if k.company.isEmpty { k.company = other.company }
        if k.role.isEmpty { k.role = other.role }
        if k.bio.isEmpty { k.bio = other.bio }
        if k.birthday == nil { k.birthday = other.birthday }
        if k.contactIdentifier == nil { k.contactIdentifier = other.contactIdentifier }
        k.createdAt = min(k.createdAt, other.createdAt)
        switch (k.lastInteractionAt, other.lastInteractionAt) {
        case let (a?, b?): k.lastInteractionAt = max(a, b)
        case (nil, let b?): k.lastInteractionAt = b
        default: break
        }
        k.updatedAt = Date()
        return k
    }

    /// Likely-duplicate pairs not safe to auto-merge (fuzzy name match or a
    /// shared email that slipped past import dedup). Bucketed by first letter to
    /// avoid a full O(n²) sweep. Returns highest-confidence pairs first.
    func duplicateCandidates(maxPairs: Int = 50) -> [(a: Person, b: Person, score: Double)] {
        var buckets: [Character: [Person]] = [:]
        for p in people {
            let key = PersonMatching.normalizeName(p.displayName).first ?? "?"
            buckets[key, default: []].append(p)
        }
        var pairs: [(a: Person, b: Person, score: Double)] = []
        for group in buckets.values where group.count > 1 {
            for i in 0..<group.count {
                for j in (i + 1)..<group.count {
                    let nameScore = NameSimilarity.score(group[i].displayName, group[j].displayName)
                    if shareEmail(group[i], group[j]) {
                        pairs.append((group[i], group[j], 1.0))
                    } else if nameScore >= 0.85 && nameScore < 1.0 {
                        pairs.append((group[i], group[j], nameScore))
                    }
                }
            }
        }
        return Array(pairs.sorted { $0.score > $1.score }.prefix(maxPairs))
    }

    private func shareEmail(_ a: Person, _ b: Person) -> Bool {
        let ae = Set(a.emails.map(PersonMatching.normalizeEmail))
        return !ae.isEmpty && !ae.isDisjoint(with: Set(b.emails.map(PersonMatching.normalizeEmail)))
    }

    // MARK: - Backlinks

    /// Adds a meeting to a person's `meetingMentions` (idempotent) and persists.
    func addMeetingMention(_ meetingID: String, toPersonID personID: String) {
        guard let idx = people.firstIndex(where: { $0.id == personID }) else { return }
        guard !people[idx].meetingMentions.contains(meetingID) else { return }
        people[idx].meetingMentions.insert(meetingID)
        writePerson(people[idx])
    }

    // MARK: - Auto-extraction (Phase B)

    func hasExtracted(_ meetingID: String) -> Bool { extractedMeetingIDs.contains(meetingID) }

    func markExtracted(_ meetingID: String) {
        guard !extractedMeetingIDs.contains(meetingID) else { return }
        extractedMeetingIDs.insert(meetingID)
        persistMeta()
    }

    /// Ingests the people an extraction pass found in a meeting. Each mention is
    /// fuzzy-matched against existing people:
    ///   • ≥ 0.85 → auto-linked to that person's backlinks (no review).
    ///   • 0.6–0.85 → "is this <existing>?" suggestion.
    ///   • < 0.6 → "add as new person?" suggestion.
    /// Dismissed signatures and already-pending signatures are skipped.
    /// Returns (autoLinked, suggested) counts for logging.
    @discardableResult
    func ingestExtraction(_ extracted: [ExtractedPerson], meeting: Meeting) -> (autoLinked: Int, suggested: Int) {
        var autoLinked = 0
        var suggested = 0
        for mention in extracted {
            let name = mention.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            // Best fuzzy match against existing people (name + aliases).
            var bestPerson: Person?
            var bestScore = 0.0
            for person in people {
                var score = NameSimilarity.score(name, person.displayName)
                for alias in mention.aliases {
                    score = max(score, NameSimilarity.score(alias, person.displayName))
                }
                if score > bestScore { bestScore = score; bestPerson = person }
            }

            if bestScore >= Self.autoLinkThreshold, let match = bestPerson {
                if !match.meetingMentions.contains(meeting.id) {
                    addMeetingMention(meeting.id, toPersonID: match.id)
                    autoLinked += 1
                }
                continue
            }

            // Not confident enough to auto-link → queue a suggestion (unless
            // dismissed before or already pending for this meeting+name).
            let sig = "\(meeting.id)::\(name.lowercased())"
            if dismissedSignatures.contains(sig) { continue }
            if suggestions.contains(where: { $0.signature == sig }) { continue }

            let isPossible = bestScore >= Self.possibleMatchThreshold
            let suggestion = PersonSuggestion(
                meetingID: meeting.id,
                meetingTitle: meeting.displayTitle,
                meetingDate: meeting.startDate,
                extractedName: name,
                aliases: mention.aliases,
                context: mention.primaryContext,
                summary: mention.oneLineSummary,
                confidence: mention.confidence,
                matchedPersonID: isPossible ? bestPerson?.id : nil,
                matchedPersonName: isPossible ? bestPerson?.displayName : nil,
                matchScore: isPossible ? bestScore : nil
            )
            suggestions.append(suggestion)
            suggestions.sort { $0.meetingDate > $1.meetingDate }
            writeSuggestion(suggestion)
            suggested += 1
        }
        if autoLinked > 0 || suggested > 0 {
            log.info("Ingested extraction for meeting \(meeting.id, privacy: .public): \(autoLinked) auto-linked, \(suggested) suggested")
        }
        return (autoLinked, suggested)
    }

    /// Confirm a suggestion: link to the matched person, or create a new one,
    /// then record the meeting as a backlink. Removes the suggestion.
    @discardableResult
    func confirmSuggestion(_ suggestion: PersonSuggestion) -> Person? {
        let person: Person
        if let matchedID = suggestion.matchedPersonID, let existing = self.person(by: matchedID) {
            person = existing
        } else {
            person = createPerson(displayName: suggestion.extractedName,
                                  bio: suggestion.summary)
        }
        addMeetingMention(suggestion.meetingID, toPersonID: person.id)
        removeSuggestion(suggestion)
        return self.person(by: person.id)
    }

    /// Dismiss a suggestion and remember it so re-extraction won't resurface it.
    func dismissSuggestion(_ suggestion: PersonSuggestion) {
        dismissedSignatures.insert(suggestion.signature)
        persistMeta()
        removeSuggestion(suggestion)
    }

    private func removeSuggestion(_ suggestion: PersonSuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
        try? FileManager.default.removeItem(at: fileURL(for: suggestion))
    }

    private func writeSuggestion(_ suggestion: PersonSuggestion) {
        do {
            try FileManager.default.createDirectory(at: suggestionsRoot, withIntermediateDirectories: true)
            let envelope = SchemaEnvelope(version: Self.suggestionSchemaVersion, data: suggestion)
            let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(envelope)
            try data.write(to: fileURL(for: suggestion), options: .atomic)
        } catch {
            log.error("Failed to persist suggestion: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage, context: ["phase": "persist-suggestion"])
        }
    }

    // MARK: - Search

    /// Filters people. With a query, results come back ranked by FTS5; with no
    /// query they're ranked by relevance (§12.4). Low-signal "ghost" contacts
    /// are hidden from the unfiltered list unless `includeGhosts` is true.
    func filteredPeople(query: String, tagID: String?, includeGhosts: Bool = false) -> [Person] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [Person]
        if !q.isEmpty {
            let byID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let ranked = db.searchPersonIDs(q).compactMap { byID[$0] }
            // Fall back to in-memory substring match if the index is cold/empty.
            result = ranked.isEmpty ? people.filter { $0.matches(q.lowercased()) } : ranked
        } else {
            result = people.sorted { lhs, rhs in
                let l = lhs.relevanceScore(encounterCount: encounterCount(for: lhs.id))
                let r = rhs.relevanceScore(encounterCount: encounterCount(for: rhs.id))
                return l != r ? l > r : Self.recencyThenName(lhs, rhs)
            }
        }
        if let tagID { result = result.filter { $0.tagIDs.contains(tagID) } }
        // Hide ghosts only on the full, unfiltered list — an explicit query or
        // tag filter means the user wants to see matches regardless.
        if !includeGhosts && q.isEmpty && tagID == nil {
            result = result.filter { !$0.isGhost(encounterCount: encounterCount(for: $0.id)) }
        }
        return result
    }

    /// Count of low-signal contacts currently hidden from the unfiltered list.
    var ghostCount: Int {
        people.reduce(0) { $1.isGhost(encounterCount: encounterCount(for: $1.id)) ? $0 + 1 : $0 }
    }

    /// The set of tag ids actually applied to at least one person — drives the
    /// filter chips in the list view.
    func usedTagIDs() -> Set<String> {
        people.reduce(into: Set<String>()) { $0.formUnion($1.tagIDs) }
    }

    /// Removes a (people) tag id from every person and encounter — called when
    /// the tag is deleted from `PeopleTagStore`.
    func removeTagFromAll(_ tagID: String) {
        for idx in people.indices where people[idx].tagIDs.contains(tagID) {
            people[idx].tagIDs.remove(tagID)
            writePerson(people[idx])
        }
        for e in encounters where e.eventTagID == tagID {
            var updated = e
            updated.eventTagID = nil
            if let i = encounters.firstIndex(where: { $0.id == e.id }) { encounters[i] = updated }
            writeEncounter(updated)
        }
    }

    // MARK: - Helpers

    private static func recencyThenName(_ a: Person, _ b: Person) -> Bool {
        switch (a.lastInteractionAt, b.lastInteractionAt) {
        case let (l?, r?) where l != r: return l > r
        case (.some, .none): return true
        case (.none, .some): return false
        default: return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    private func markdownMirror(for person: Person) -> String {
        var lines = ["# \(person.displayName)", ""]
        if !person.role.isEmpty || !person.company.isEmpty {
            let sub = [person.role, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
            lines.append("*\(sub)*"); lines.append("")
        }
        for email in person.emails where !email.isEmpty { lines.append("- ✉️ \(email)") }
        for phone in person.phones where !phone.isEmpty { lines.append("- 📞 \(phone)") }
        for address in person.addresses where !address.isEmpty { lines.append("- 📍 \(address)") }
        if let bday = person.birthday {
            let bf = DateFormatter(); bf.dateFormat = "MMMM d"
            lines.append("- 🎂 \(bf.string(from: bday))")
        }
        if !person.favorites.isEmpty {
            lines.append(""); lines.append("**Favorites:** " + person.favorites.joined(separator: ", "))
        }
        if !person.bio.isEmpty { lines.append(""); lines.append(person.bio) }
        if !person.memories.isEmpty {
            lines.append(""); lines.append("## Memories")
            let mf = DateFormatter(); mf.dateStyle = .medium
            for m in person.memories {
                let when = m.occurredOn.map { " (\(mf.string(from: $0)))" } ?? ""
                lines.append("- \(m.text)\(when)")
            }
        }
        let mine = encounters(for: person.id)
        if !mine.isEmpty {
            lines.append(""); lines.append("## Encounters")
            let f = DateFormatter(); f.dateStyle = .medium
            for e in mine {
                let where_ = e.location.map { " @ \($0)" } ?? ""
                lines.append("- **\(e.eventName)** — \(f.string(from: e.date))\(where_)")
                if !e.notes.isEmpty { lines.append("  \(e.notes)") }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

private extension Person {
    /// `q` is expected to already be lowercased.
    func matches(_ q: String) -> Bool {
        if displayName.lowercased().contains(q) { return true }
        if company.lowercased().contains(q) { return true }
        if role.lowercased().contains(q) { return true }
        if emails.contains(where: { $0.lowercased().contains(q) }) { return true }
        return false
    }
}
