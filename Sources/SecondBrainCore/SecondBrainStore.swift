import Foundation

/// Storage interface for the Second Brain. Defined as a protocol so the macOS
/// app (file-backed today, CloudKit-backed tomorrow) and a future iOS app can
/// supply their own conforming implementations without changing call sites.
///
/// Intentionally `async`-first so a remote/CloudKit-backed implementation
/// fits the same shape as a local one.
public protocol SecondBrainStore: Sendable {
    // MARK: People
    func allPeople() async throws -> [Person]
    func person(id: String) async throws -> Person?
    func upsert(_ person: Person) async throws
    func deletePerson(id: String) async throws

    // MARK: Encounters
    func encounters(forPerson personID: String) async throws -> [Encounter]
    func record(_ encounter: Encounter) async throws
    func deleteEncounter(id: String) async throws
}

public extension SecondBrainStore {
    /// Convenience: people sorted by most-recent update first.
    func peopleByRecency() async throws -> [Person] {
        try await allPeople().sorted { $0.updatedAt > $1.updatedAt }
    }
}

/// An in-memory `SecondBrainStore` — useful for tests, previews, and as a
/// reference implementation of the protocol. Not for production persistence.
public actor InMemorySecondBrainStore: SecondBrainStore {
    private var people: [String: Person] = [:]
    private var encountersByPerson: [String: [Encounter]] = [:]

    public init() {}

    public func allPeople() async throws -> [Person] { Array(people.values) }
    public func person(id: String) async throws -> Person? { people[id] }

    public func upsert(_ person: Person) async throws {
        var p = person
        p.updatedAt = Date()
        people[p.id] = p
    }

    public func deletePerson(id: String) async throws {
        people[id] = nil
        encountersByPerson[id] = nil
    }

    public func encounters(forPerson personID: String) async throws -> [Encounter] {
        (encountersByPerson[personID] ?? []).sorted { $0.date > $1.date }
    }

    public func record(_ encounter: Encounter) async throws {
        encountersByPerson[encounter.personID, default: []].append(encounter)
    }

    public func deleteEncounter(id: String) async throws {
        for (person, list) in encountersByPerson {
            encountersByPerson[person] = list.filter { $0.id != id }
        }
    }
}
