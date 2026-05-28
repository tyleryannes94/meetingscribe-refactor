import Foundation
import VaultKit

struct Meeting: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var attendees: [String]
    /// EKEvent.notes (calendar invite body)
    var notes: String?
    var location: String?
    var conferenceURL: String?
    var calendarName: String?
    /// Recurring-series identifier (EKEvent.calendarItemIdentifier). Same value
    /// across all occurrences of a recurring event — used to apply tags to
    /// every future occurrence of the series.
    var seriesID: String?
    /// User's short description, separate from the calendar notes and from
    /// their freeform notes.md file.
    var userDescription: String?
    /// User-edited title — if set, prefer this over `title` for display.
    var userTitle: String?
    /// Whether this meeting was created manually via "ad-hoc recording" /
    /// hotkey / Zoom auto-detect (vs. pulled from calendar).
    var isImpromptu: Bool = false
    /// Whether this meeting was created by importing an external audio file.
    var isImported: Bool = false
    /// Number of recorded segments.
    ///
    /// **Deprecated as a source of truth.** Authoritative bookkeeping now
    /// lives in `<dir>/audio/manifest.json` (see `AudioManifestStore`). This
    /// field is still written for backward compatibility with older builds
    /// reading via the MCP server, and as a fallback for meetings that
    /// pre-date the manifest. Don't increment it from new code paths —
    /// call `AudioManifestStore.append(...)` instead.
    var segmentCount: Int = 0
    /// Persisted relative path within the storage root (e.g. "Skio/2026-05-19-1030-Sync").
    /// Lets `MeetingStore.directory(for:)` resolve in O(1) without walking
    /// the tree. Optional so older meetings still decode; first read of an
    /// older meeting populates this lazily.
    var relativeFolderPath: String?
    /// End-of-pipeline summary of how the recording went — drives the UI
    /// badge ("no transcript", "fallback used", etc.). Nil for meetings
    /// finalized before health tracking existed.
    var health: MeetingHealthDTO?

    var displayTitle: String {
        if let t = userTitle?.trimmingCharacters(in: .whitespaces), !t.isEmpty {
            return t
        }
        return title
    }

    var isLive: Bool {
        let now = Date()
        return now >= startDate.addingTimeInterval(-60) && now <= endDate
    }

    /// Folder slug — file-system safe, includes date + truncated title.
    var slug: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let datePart = formatter.string(from: startDate)
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let safeTitle = displayTitle
            .components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = String(safeTitle.prefix(60))
        return "\(datePart)-\(truncated.isEmpty ? "Untitled" : truncated)"
    }
}

extension Meeting {
    private enum CodingKeys: String, CodingKey {
        case id, title, startDate, endDate, attendees, notes, location,
             conferenceURL, calendarName, seriesID, userDescription, userTitle,
             isImpromptu, isImported, segmentCount, relativeFolderPath, health
    }

    /// Tolerant decoder. Swift's *synthesized* Codable requires every
    /// non-optional key to be present, so a `meeting.json` written by an older
    /// build (before `segmentCount` / `isImpromptu` / `relativeFolderPath` /
    /// `health` existed) would throw `keyNotFound` and the meeting would
    /// silently disappear from disk scans. Here every newer scalar field is
    /// optional-with-default and `attendees` defaults to empty, so every
    /// historical file still loads. Defining this in an extension preserves
    /// the synthesized memberwise initializer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        attendees = (try? c.decode([String].self, forKey: .attendees)) ?? []
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? nil
        location = (try? c.decodeIfPresent(String.self, forKey: .location)) ?? nil
        conferenceURL = (try? c.decodeIfPresent(String.self, forKey: .conferenceURL)) ?? nil
        calendarName = (try? c.decodeIfPresent(String.self, forKey: .calendarName)) ?? nil
        seriesID = (try? c.decodeIfPresent(String.self, forKey: .seriesID)) ?? nil
        userDescription = (try? c.decodeIfPresent(String.self, forKey: .userDescription)) ?? nil
        userTitle = (try? c.decodeIfPresent(String.self, forKey: .userTitle)) ?? nil
        isImpromptu = (try? c.decode(Bool.self, forKey: .isImpromptu)) ?? false
        isImported = (try? c.decode(Bool.self, forKey: .isImported)) ?? false
        segmentCount = (try? c.decode(Int.self, forKey: .segmentCount)) ?? 0
        relativeFolderPath = (try? c.decodeIfPresent(String.self, forKey: .relativeFolderPath)) ?? nil
        health = (try? c.decodeIfPresent(MeetingHealthDTO.self, forKey: .health)) ?? nil
    }
}

/// High-level state of the live audio pipeline ONLY. Background post-processing
/// (transcription + summarization) is tracked separately via
/// `MeetingManager.transcribingMeetingIDs` so the user can immediately start
/// a new recording even while a previous meeting is still being finalized.
enum RecordingState: Equatable {
    case idle
    case starting   // guards concurrent startRecording calls
    case stopping   // guards concurrent stopRecording calls
    case recording(meeting: Meeting?, startedAt: Date)
    case error(String)
}
