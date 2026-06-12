import Foundation

/// In-call "mark moment" highlights (C1-2): Fathom's signature gesture, local.
/// During a recording the user flags important moments; each mark is the
/// elapsed second into the recording plus an optional short label. Persisted as
/// a small sidecar next to the speaker map so highlights survive relaunch and
/// can seed a "Highlights" anchor list atop the finished summary.
struct MeetingMark: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// Seconds from the recording start — same clock the transcript/audio use.
    var second: Double
    /// Optional 4-word label ("pricing decision"); empty when the user just flagged.
    var label: String = ""

    /// `m:ss` / `h:mm:ss` rendering of `second`.
    var timestamp: String {
        let s = max(0, Int(second))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }
}

enum MeetingMarks {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingScribe/marks", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private static func url(_ meetingID: String) -> URL {
        let safe = meetingID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? meetingID
        return dir.appendingPathComponent("\(safe).json")
    }

    static func load(_ meetingID: String) -> [MeetingMark] {
        guard let data = try? Data(contentsOf: url(meetingID)),
              let marks = try? JSONDecoder().decode([MeetingMark].self, from: data) else { return [] }
        return marks.sorted { $0.second < $1.second }
    }

    static func save(_ marks: [MeetingMark], for meetingID: String) {
        if let data = try? JSONEncoder().encode(marks.sorted { $0.second < $1.second }) {
            try? data.write(to: url(meetingID), options: .atomic)
        }
    }

    /// Append one mark at `second` and persist; returns the updated list.
    @discardableResult
    static func add(second: Double, label: String = "", to meetingID: String) -> [MeetingMark] {
        var marks = load(meetingID)
        marks.append(MeetingMark(second: second, label: label))
        save(marks, for: meetingID)
        return marks
    }
}
