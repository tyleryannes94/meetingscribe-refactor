import Foundation

/// Persists person→preferred-speaker-label mappings globally so that
/// known participants are auto-assigned in future meetings.
struct GlobalSpeakerMap {
    private static let url: URL = {
        let app = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingScribe", isDirectory: true)
        try? FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        return app.appendingPathComponent("global-speakers.json")
    }()

    /// personID → preferred speaker label (e.g. "Them", "Speaker 2")
    static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    static func save(_ map: [String: String]) {
        try? JSONEncoder().encode(map).write(to: url, options: .atomic)
    }

    static func record(personID: String, speakerLabel: String) {
        var map = load()
        map[personID] = speakerLabel
        save(map)
    }

    /// Given attendees (personIDs) and known segment labels, return a mapping
    /// label → personID for all auto-assignable attendees.
    static func autoAssign(personIDs: [String], existingLabels: Set<String>) -> [String: String] {
        let global = load()
        var result: [String: String] = [:]
        for pid in personIDs {
            guard let label = global[pid], existingLabels.contains(label) else { continue }
            result[label] = pid
        }
        return result
    }
}
