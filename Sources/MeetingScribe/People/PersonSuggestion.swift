import Foundation

/// A person the auto-extraction pipeline found in a meeting transcript but
/// wasn't confident enough to link automatically. Surfaced in the Today tab
/// for one-click confirm / dismiss (audit §5.2, Phase B).
///
/// Two flavors, distinguished by `matchedPersonID`:
///   • **possible match** (0.6 ≤ score < 0.85) — `matchedPersonID` set; confirm
///     links this mention to that existing person.
///   • **new person** (score < 0.6) — `matchedPersonID` nil; confirm creates a
///     new person from the extracted name + summary.
struct PersonSuggestion: Identifiable, Codable, Hashable {
    var id: String
    var meetingID: String
    var meetingTitle: String
    var meetingDate: Date
    /// The name as it appeared in the transcript.
    var extractedName: String
    var aliases: [String]
    /// "speaker" | "attendee" | "third_party" — the model's guess.
    var context: String
    /// One-line paraphrase of what they said/did — seeds a new person's bio.
    var summary: String
    /// The model's confidence that this is a real person mention (0...1).
    var confidence: Double
    /// Set when this is a possible match to an existing person.
    var matchedPersonID: String?
    var matchedPersonName: String?
    /// Fuzzy-match score against `matchedPersonID` (0...1).
    var matchScore: Double?
    var createdAt: Date

    init(id: String = UUID().uuidString,
         meetingID: String,
         meetingTitle: String,
         meetingDate: Date,
         extractedName: String,
         aliases: [String] = [],
         context: String = "",
         summary: String = "",
         confidence: Double = 0.7,
         matchedPersonID: String? = nil,
         matchedPersonName: String? = nil,
         matchScore: Double? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.meetingDate = meetingDate
        self.extractedName = extractedName
        self.aliases = aliases
        self.context = context
        self.summary = summary
        self.confidence = confidence
        self.matchedPersonID = matchedPersonID
        self.matchedPersonName = matchedPersonName
        self.matchScore = matchScore
        self.createdAt = createdAt
    }

    /// Stable identity for de-duping across re-extractions of the same meeting,
    /// and for remembering dismissals: meeting + normalized name.
    var signature: String {
        "\(meetingID)::\(extractedName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    var isPossibleMatch: Bool { matchedPersonID != nil }
}
