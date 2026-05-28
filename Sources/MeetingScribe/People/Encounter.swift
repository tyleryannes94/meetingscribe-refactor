import Foundation

/// A single "I met this person here" record — the "Purple Party 2026" moment.
/// Encounters are stored separately from `Person` (one JSON file each under
/// `<storageDir>/encounters/`) so a person's record stays small and encounters
/// can be queried independently in later phases.
struct Encounter: Identifiable, Codable, Hashable {
    var id: String
    /// The person this encounter belongs to.
    var personID: String
    /// The event tag (a `MeetingTag` id), e.g. the tag named "Purple Party 2026".
    /// Optional — an encounter can be a one-off with no reusable tag.
    var eventTagID: String?
    /// Denormalized event name for fast display without a tag lookup.
    var eventName: String
    var date: Date
    var location: String?
    /// Freeform — "wore a purple shirt, works in renewable energy".
    var notes: String
    /// Cross-references to artifacts that captured this encounter (Phase B+).
    var meetingID: String?
    var voiceNoteID: String?
    var createdAt: Date

    init(id: String = UUID().uuidString,
         personID: String,
         eventTagID: String? = nil,
         eventName: String,
         date: Date = Date(),
         location: String? = nil,
         notes: String = "",
         meetingID: String? = nil,
         voiceNoteID: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.personID = personID
        self.eventTagID = eventTagID
        self.eventName = eventName
        self.date = date
        self.location = location
        self.notes = notes
        self.meetingID = meetingID
        self.voiceNoteID = voiceNoteID
        self.createdAt = createdAt
    }
}
