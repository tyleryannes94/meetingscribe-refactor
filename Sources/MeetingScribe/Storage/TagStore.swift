import Foundation
import VaultKit
import OSLog

/// Persists tags + per-meeting and per-recurring-series tag assignments.
/// Lives at `<storageDir>/tags.json` so it travels with the rest of the notes.
/// Schema-versioned via `SchemaEnvelope` so future field changes are
/// non-breaking (audit 2.3).
@MainActor
final class TagStore: ObservableObject {
    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Tags")
    static let schemaVersion = 1

    private struct Persisted: Codable {
        var tags: [MeetingTag]
        /// EKEvent.eventIdentifier (or Meeting.id) → [tag id]
        var meetingTags: [String: [String]]
        /// EKEvent.calendarItemIdentifier (recurring series) → [tag id]
        /// Used to auto-apply tags to all future occurrences of a recurring event.
        var seriesTags: [String: [String]]
    }

    @Published private(set) var allTags: [MeetingTag] = MeetingTag.presets
    private var meetingTags: [String: [String]] = [:]
    private var seriesTags: [String: [String]] = [:]

    private var fileURL: URL { AppSettings.shared.storageDir.appendingPathComponent("tags.json") }

    init() {
        // Read OFF the main thread (the file open can stall on slow/scanned
        // disks and would block app launch); decode + merge back on the main actor.
        let url = fileURL
        Task.detached(priority: .userInitiated) { [weak self] in
            let data = try? Data(contentsOf: url)
            await MainActor.run { self?.applyLoaded(data) }
        }
    }

    private func applyLoaded(_ data: Data?) {
        guard let data else {
            persist()   // first run — write presets
            return
        }
        // SchemaEnvelope.decode accepts both legacy raw payloads (older
        // builds wrote { tags: [], meetingTags: {}, seriesTags: {} } at
        // the top level) and the new versioned envelope.
        guard let decoded: Persisted = try? SchemaEnvelope.decode(
            Persisted.self, from: data, currentVersion: Self.schemaVersion,
            decoder: SharedCoders.decoder()
        ) else {
            persist()
            return
        }
        // Merge presets with persisted tags (preserve user-renamed presets
        // but add any missing presets so feature additions show up).
        var merged = decoded.tags
        let existingIds = Set(merged.map { $0.id })
        for preset in MeetingTag.presets where !existingIds.contains(preset.id) {
            merged.append(preset)
        }
        allTags = merged
        meetingTags = decoded.meetingTags
        seriesTags = decoded.seriesTags
    }

    private func persist() {
        let p = Persisted(tags: allTags, meetingTags: meetingTags, seriesTags: seriesTags)
        do {
            try FileManager.default.createDirectory(at: AppSettings.shared.storageDir,
                                                    withIntermediateDirectories: true)
            let envelope = SchemaEnvelope(version: Self.schemaVersion, data: p)
            let data = try SharedCoders.encoder(pretty: true, sorted: true).encode(envelope)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Failed to persist tags: \(error.localizedDescription, privacy: .public)")
            ErrorReporter.shared.report(error, category: .storage,
                                        context: ["phase": "persist-tags"])
        }
    }

    // MARK: - Tag CRUD

    func createTag(name: String, symbol: String? = nil, colorHex: String? = nil) -> MeetingTag {
        let tag = MeetingTag(name: name, symbol: symbol, colorHex: colorHex)
        allTags.append(tag)
        persist()
        return tag
    }

    func renameTag(id: String, to newName: String) {
        guard let idx = allTags.firstIndex(where: { $0.id == id }) else { return }
        allTags[idx].name = newName
        persist()
    }

    func deleteTag(id: String) {
        allTags.removeAll { $0.id == id }
        for key in meetingTags.keys {
            meetingTags[key]?.removeAll { $0 == id }
        }
        for key in seriesTags.keys {
            seriesTags[key]?.removeAll { $0 == id }
        }
        persist()
    }

    func tag(by id: String) -> MeetingTag? {
        allTags.first { $0.id == id }
    }

    // MARK: - Assignments

    /// Returns the tag IDs assigned to a meeting, merging series-level tags.
    func tagIDs(for meeting: Meeting) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in meetingTags[meeting.id, default: []] where seen.insert(id).inserted {
            result.append(id)
        }
        if let series = meeting.seriesID {
            for id in seriesTags[series, default: []] where seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }

    func tags(for meeting: Meeting) -> [MeetingTag] {
        tagIDs(for: meeting).compactMap { tag(by: $0) }
    }

    func primaryTag(for meeting: Meeting) -> MeetingTag? {
        tags(for: meeting).first
    }

    /// Adds a tag to this meeting. If `propagateToSeries` is true and the
    /// meeting has a recurring series id, also stores the tag at the series
    /// level so future occurrences inherit it.
    func setTags(_ ids: [String], for meeting: Meeting, propagateToSeries: Bool) {
        meetingTags[meeting.id] = Array(Set(ids))
        if propagateToSeries, let series = meeting.seriesID {
            seriesTags[series] = Array(Set(ids))
        }
        persist()
    }

    func addTag(_ tagId: String, to meeting: Meeting, propagateToSeries: Bool) {
        var ids = tagIDs(for: meeting)
        if !ids.contains(tagId) { ids.append(tagId) }
        setTags(ids, for: meeting, propagateToSeries: propagateToSeries)
    }

    func removeTag(_ tagId: String, from meeting: Meeting, propagateToSeries: Bool) {
        var ids = tagIDs(for: meeting)
        ids.removeAll { $0 == tagId }
        setTags(ids, for: meeting, propagateToSeries: propagateToSeries)
    }
}
