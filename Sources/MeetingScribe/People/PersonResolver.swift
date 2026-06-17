import Foundation

/// A parsed attendee/owner string broken into its name and email parts.
struct AttendeeIdentity: Equatable {
    /// The original string, verbatim.
    let raw: String
    /// Display name (may be empty for a bare email).
    let name: String
    /// Email, normalized (lowercased, trimmed). Empty if none was present.
    let email: String

    var hasEmail: Bool { !email.isEmpty }
    var hasName: Bool { !name.isEmpty }
}

/// One email-keyed identity layer (P1-1, merges P2-1/P2-10).
///
/// Before this, the same `"Name <email>"` parsing was re-implemented at least
/// six times with diverging rules — producing three live bugs: empty follow-up
/// recipients (the email in the string was never parsed out), `"Dan"` matching
/// every `"Daniel"` (substring matching), and hollow bulk-added people (no edge).
///
/// `PersonResolver` is the single place attendee and task-owner strings become
/// `Person` records. Matching is **email-first, exact-name-second — never
/// substring** — so identity is keyed on the join column that actually exists.
///
/// The type is intentionally pure (no `@MainActor`, no store access): it takes a
/// `[Person]` snapshot so it is trivially unit-testable and callable from any
/// context. `PeopleStore` exposes the store-aware conveniences on top of it.
enum PersonResolver {

    // MARK: - Parsing

    /// Canonical parse of an attendee string. Handles the three shapes the app
    /// sees: `"Jane Smith <jane@acme.com>"`, a bare `"jane@acme.com"`, and a
    /// bare `"Jane Smith"`.
    static func parse(_ raw: String) -> AttendeeIdentity {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AttendeeIdentity(raw: raw, name: "", email: "") }

        // "Name <email>" — angle-bracketed email is the unambiguous case.
        if let lt = trimmed.firstIndex(of: "<"),
           let gt = trimmed.firstIndex(of: ">"), lt < gt {
            let name = String(trimmed[..<lt]).trimmingCharacters(in: .whitespacesAndNewlines)
            let emailRaw = String(trimmed[trimmed.index(after: lt)..<gt])
            let email = PersonMatching.normalizeEmail(emailRaw)
            return AttendeeIdentity(raw: raw, name: name, email: email.contains("@") ? email : "")
        }

        // Bare email: a single token containing "@" and no spaces.
        if trimmed.contains("@"), !trimmed.contains(" ") {
            return AttendeeIdentity(raw: raw, name: "", email: PersonMatching.normalizeEmail(trimmed))
        }

        // Otherwise it's a bare display name.
        return AttendeeIdentity(raw: raw, name: trimmed, email: "")
    }

    /// The localpart of an email ("jane" from "jane@acme.com"), useful as a
    /// last-resort display name.
    static func localPart(of email: String) -> String {
        String(email.split(separator: "@").first ?? "")
    }

    // MARK: - Resolution

    /// Resolve an attendee string to a `Person` id using **email first, exact
    /// normalized name second**. Returns `nil` when there is no confident match
    /// — deliberately conservative; substring matching is never used.
    static func resolve(_ raw: String, in people: [Person]) -> String? {
        let id = parse(raw)
        return resolve(identity: id, in: people)
    }

    /// Resolve an already-parsed identity.
    static func resolve(identity id: AttendeeIdentity, in people: [Person]) -> String? {
        if id.hasEmail {
            if let p = people.first(where: { person in
                person.emails.contains { PersonMatching.normalizeEmail($0) == id.email }
            }) {
                return p.id
            }
        }
        if id.hasName {
            let target = PersonMatching.normalizeName(id.name)
            if let p = people.first(where: { PersonMatching.normalizeName($0.displayName) == target }) {
                return p.id
            }
            // 1-E: fall back to exact (normalized) alias match — "Ty" → "Tyler".
            // Still exact, never substring, so it can't reintroduce the "Dan
            // matches Daniel" bug.
            if let p = people.first(where: { person in
                person.aliases.contains { PersonMatching.normalizeName($0) == target }
            }) {
                return p.id
            }
        }
        return nil
    }

    /// Resolve a free-text task owner ("Jane", "jane@acme.com", "Jane Smith") to
    /// a `Person` id. Self-references ("me", "I", "myself") resolve to `nil` —
    /// the current user is not a contact, and `ActionItemExtractor.isMine`
    /// already owns that distinction.
    static func resolveOwner(_ owner: String?, in people: [Person]) -> String? {
        guard let owner else { return nil }
        let trimmed = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if selfTokens.contains(trimmed.lowercased()) { return nil }
        return resolve(trimmed, in: people)
    }

    /// Tokens that mean "the user", which never map to a Person record.
    static let selfTokens: Set<String> = ["me", "i", "myself", "my", "self"]

    /// T10 / 04 §4.5: does `item` belong to `person`? Hard link wins. Otherwise
    /// falls back to the exact email-/name-/alias-resolution used on write.
    /// Never substring. Single source of truth for "is this task this person's?"
    static func taskBelongs(_ item: ActionItem, to person: Person) -> Bool {
        if let pid = item.ownerPersonID { return pid == person.id }
        return resolveOwner(item.owner, in: [person]) == person.id
    }

    // MARK: - Bulk helpers

    /// The subset of a meeting's attendees that resolve to an existing Person,
    /// as `(personID, identity)` pairs. The auto-link join used at finalize.
    static func resolvedAttendees(_ attendees: [String], in people: [Person]) -> [(personID: String, identity: AttendeeIdentity)] {
        attendees.compactMap { raw in
            let id = parse(raw)
            guard let pid = resolve(identity: id, in: people) else { return nil }
            return (pid, id)
        }
    }
}
