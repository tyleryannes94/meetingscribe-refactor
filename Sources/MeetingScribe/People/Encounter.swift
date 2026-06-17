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
    /// Action items associated with this encounter (2-J) — populated from the
    /// linked meeting's extracted tasks, closing the person ↔ encounter ↔ task
    /// triangle. Optional/defaulted so older per-file encounters still decode.
    var taskIDs: [String] = []
    /// Optional mood (C2-6) — a first-class field (Mood rawValue) instead of a
    /// `[mood:x]` tag buried in notes.
    var mood: String?

    init(id: String = UUID().uuidString,
         personID: String,
         eventTagID: String? = nil,
         eventName: String,
         date: Date = Date(),
         location: String? = nil,
         notes: String = "",
         meetingID: String? = nil,
         voiceNoteID: String? = nil,
         createdAt: Date = Date(),
         taskIDs: [String] = [],
         mood: String? = nil) {
        self.mood = mood
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
        self.taskIDs = taskIDs
    }
}

extension Encounter {
    private enum CodingKeys: String, CodingKey {
        case id, personID, eventTagID, eventName, date, location, notes,
             meetingID, voiceNoteID, createdAt, taskIDs, mood
    }

    /// Tolerant decode so encounters written before `taskIDs` existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        personID = try c.decode(String.self, forKey: .personID)
        eventTagID = try c.decodeIfPresent(String.self, forKey: .eventTagID)
        eventName = (try? c.decode(String.self, forKey: .eventName)) ?? ""
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        location = try c.decodeIfPresent(String.self, forKey: .location)
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        meetingID = try c.decodeIfPresent(String.self, forKey: .meetingID)
        voiceNoteID = try c.decodeIfPresent(String.self, forKey: .voiceNoteID)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        taskIDs = (try? c.decode([String].self, forKey: .taskIDs)) ?? []
        mood = try c.decodeIfPresent(String.self, forKey: .mood)
    }
}
