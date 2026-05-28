import Foundation
import VaultKit
import OSLog

/// Tags for **people** — a namespace entirely separate from meeting tags
/// (`TagStore`). Event/group/role tags like "Purple Party 2026" or "College
/// friends" live here and are persisted to `<storageDir>/people-tags.json`, so
/// creating a people tag never pollutes the meeting tag list and vice versa.
///
/// Reuses the `MeetingTag` value type (a generic id/name/symbol/color shape) so
/// the existing `TagChip` / `EventTagSelector` views work unchanged — only the
/// store and on-disk file differ.
@available(macOS 14.0, *)
@MainActor
final class PeopleTagStore: ObservableObject {
    static let shared = PeopleTagStore()

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "PeopleTags")
    static let schemaVersion = 1

    @Published private(set) var allTags: [MeetingTag] = []

    private var fileURL: URL { AppSettings.shared.storageDir.appendingPathComponent("people-tags.json") }

    private struct Persisted: Codable { var tags: [MeetingTag] }

    init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            // First run: lift any tags existing people already use out of the
            // meeting-tag file so they survive the split to a separate namespace.
            allTags = migratedFromMeetingTags()
            persist()
            return
        }
        guard let decoded: Persisted = try? SchemaEnvelope.decode(
            Persisted.self, from: data, currentVersion: Self.schemaVersion,
            decoder: SharedCoders.decoder()) else {
            allTags = migratedFromMeetingTags()
            persist()
            return
        }
        allTags = decoded.tags
    }

    /// Copy the meeting tags that existing people / encounters already reference
    /// (by id) into the people namespace, preserving their name/color so nothing
    /// the user already tagged loses its label. Returns [] when there's nothing
    /// to migrate (fresh installs start with an empty people-tag list).
    private func migratedFromMeetingTags() -> [MeetingTag] {
        var usedIDs = Set(PeopleStore.shared.people.flatMap { $0.tagIDs })
        usedIDs.formUnion(PeopleStore.shared.encounters.compactMap { $0.eventTagID })
        guard !usedIDs.isEmpty else { return [] }

        let meetingTagsURL = AppSettings.shared.storageDir.appendingPathComponent("tags.json")
        guard let data = try? Data(contentsOf: meetingTagsURL) else { return [] }
        // tags.json's payload has extra keys (meetingTags/seriesTags); the
        // decoder ignores them when decoding into `Persisted { tags }`.
        guard let decoded: Persisted = try? SchemaEnvelope.decode(
            Persisted.self, from: data, currentVersion: TagStore.schemaVersion,
            decoder: SharedCoders.decoder()) else { return [] }
        let migrated = decoded.tags.filter { usedIDs.contains($0.id) }
        if !migrated.isEmpty {
            log.info("Migrated \(migrated.count) people tags out of the meeting-tag namespace")
        }
        return migrated
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: AppSettings.shared.storageDir,
                                                    withIntermediateDirectories: true)
            let envelope = SchemaEnvelope(version: Self.schemaVersion, data: Persisted(tags: allTags))
            let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(envelope)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Failed to persist people tags: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage, context: ["phase": "persist-people-tags"])
        }
    }

    // MARK: - CRUD

    func tag(by id: String) -> MeetingTag? { allTags.first { $0.id == id } }

    @discardableResult
    func createTag(name: String, symbol: String? = nil, colorHex: String? = nil,
                   kind: TagKind? = nil, startDate: Date? = nil,
                   endDate: Date? = nil, locationHint: String? = nil) -> MeetingTag {
        // Reuse an existing tag with the same name rather than duplicating —
        // backfilling kind/date/location if it didn't have them yet.
        if let idx = allTags.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            var t = allTags[idx]
            if t.kind == nil { t.kind = kind }
            if t.startDate == nil { t.startDate = startDate }
            if t.endDate == nil { t.endDate = endDate }
            if t.locationHint == nil { t.locationHint = locationHint }
            allTags[idx] = t
            persist()
            return t
        }
        let tag = MeetingTag(name: name, symbol: symbol, colorHex: colorHex,
                             kind: kind, startDate: startDate, endDate: endDate, locationHint: locationHint)
        allTags.append(tag)
        persist()
        return tag
    }

    func renameTag(id: String, to newName: String) {
        guard let idx = allTags.firstIndex(where: { $0.id == id }) else { return }
        allTags[idx].name = newName
        persist()
    }

    /// Update an event tag's classification, date range, and location.
    func setEventDetails(id: String, kind: TagKind, startDate: Date?, endDate: Date?, locationHint: String?) {
        guard let idx = allTags.firstIndex(where: { $0.id == id }) else { return }
        allTags[idx].kind = kind
        allTags[idx].startDate = startDate
        allTags[idx].endDate = endDate
        allTags[idx].locationHint = locationHint
        persist()
    }

    /// Deletes a people tag and strips it from every person + encounter.
    func deleteTag(id: String) {
        allTags.removeAll { $0.id == id }
        persist()
        PeopleStore.shared.removeTagFromAll(id)
    }
}
