import Foundation

/// Tag classification (§4.3). Only people tags set this; meeting tags leave it
/// nil (treated as `.generic`). `event` tags carry a date range + location.
enum TagKind: String, Codable, Hashable, CaseIterable {
    case generic, event, group, role
    var label: String {
        switch self {
        case .generic: return "Tag"
        case .event:   return "Event"
        case .group:   return "Group"
        case .role:    return "Role"
        }
    }
}

struct MeetingTag: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    /// SF Symbol or single emoji for the badge.
    var symbol: String?
    /// Hex color (#RRGGBB) for the badge background.
    var colorHex: String?
    // §4.3 — optional so meeting tags + older records decode unchanged.
    var kind: TagKind?
    var startDate: Date?
    var endDate: Date?
    var locationHint: String?
    /// Per-tag summary instructions appended to the summary prompt for meetings
    /// carrying this tag — e.g. "Lead with risks, then decisions, then next
    /// steps." Optional so older records decode unchanged.
    var summaryTemplate: String?

    var resolvedKind: TagKind { kind ?? .generic }

    init(id: String = UUID().uuidString,
         name: String,
         symbol: String? = nil,
         colorHex: String? = nil,
         kind: TagKind? = nil,
         startDate: Date? = nil,
         endDate: Date? = nil,
         locationHint: String? = nil,
         summaryTemplate: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.locationHint = locationHint
        self.summaryTemplate = summaryTemplate
    }

    /// Folder-safe slug for this tag, used as a directory name.
    var folderName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untagged" }
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return trimmed.components(separatedBy: invalid).joined(separator: "-")
    }

    static let presets: [MeetingTag] = [
        MeetingTag(id: "preset-skio",       name: "Skio",                  symbol: "building.2",   colorHex: "#4F46E5"),
        MeetingTag(id: "preset-recharge",   name: "Recharge",              symbol: "bolt",         colorHex: "#06B6D4"),
        MeetingTag(id: "preset-planning",   name: "Planning Calls",        symbol: "calendar",     colorHex: "#F59E0B"),
        MeetingTag(id: "preset-product",    name: "Product Team Calls",    symbol: "hammer",       colorHex: "#10B981"),
        MeetingTag(id: "preset-huddle",     name: "Slack Huddles",         symbol: "person.wave.2", colorHex: "#A78BFA"),
        MeetingTag(id: "preset-impromptu",  name: "Impromptu Recording",   symbol: "waveform",     colorHex: "#EF4444")
    ]
}
