import Foundation

/// A single touchpoint with a `Person` — a meeting, call, email thread, or
/// note. Encounters are how the Second Brain reconstructs "when did I last talk
/// to X, and about what."
public struct Encounter: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case meeting, call, email, message, note
    }

    public var id: String
    /// `Person.id` this encounter is about.
    public var personID: String
    public var kind: Kind
    public var date: Date
    /// Optional link back to the source object (e.g. a meeting id).
    public var sourceID: String?
    public var title: String
    public var summary: String?

    public init(
        id: String = UUID().uuidString,
        personID: String,
        kind: Kind,
        date: Date = Date(),
        sourceID: String? = nil,
        title: String,
        summary: String? = nil
    ) {
        self.id = id
        self.personID = personID
        self.kind = kind
        self.date = date
        self.sourceID = sourceID
        self.title = title
        self.summary = summary
    }
}
