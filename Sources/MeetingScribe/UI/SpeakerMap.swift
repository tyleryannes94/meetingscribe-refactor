import Foundation

/// Per-meeting speaker→person mapping (P1-3): "Speaker 2 = Jane". Persisted as a
/// small sidecar so transcript labels can render as real people and talk-time /
/// extracted items can be attributed. A derived cache under Application Support
/// (safe to delete; rebuilt by re-mapping).
enum SpeakerMap {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingScribe/speakers", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private static func url(_ meetingID: String) -> URL {
        let safe = meetingID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? meetingID
        return dir.appendingPathComponent("\(safe).json")
    }

    /// label → personID for a meeting.
    static func load(_ meetingID: String) -> [String: String] {
        guard let data = try? Data(contentsOf: url(meetingID)),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }
    static func save(_ map: [String: String], for meetingID: String) {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: url(meetingID), options: .atomic)
        }
    }
}
