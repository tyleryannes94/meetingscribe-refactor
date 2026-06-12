import XCTest
@testable import MeetingScribe

/// Guards the one identity layer (P1-1): parsing, email-first resolution, and
/// the two live bugs it fixes — substring "Dan"→"Daniel" matches and empty
/// follow-up recipients.
final class PersonResolverTests: XCTestCase {

    // MARK: - Parsing

    func testParseNameAndAngleEmail() {
        let id = PersonResolver.parse("Jane Smith <Jane@Acme.com>")
        XCTAssertEqual(id.name, "Jane Smith")
        XCTAssertEqual(id.email, "jane@acme.com")   // normalized lowercase
        XCTAssertTrue(id.hasEmail)
        XCTAssertTrue(id.hasName)
    }

    func testParseBareEmail() {
        let id = PersonResolver.parse("jane@acme.com")
        XCTAssertEqual(id.email, "jane@acme.com")
        XCTAssertEqual(id.name, "")
        XCTAssertTrue(id.hasEmail)
        XCTAssertFalse(id.hasName)
    }

    func testParseBareName() {
        let id = PersonResolver.parse("Jane Smith")
        XCTAssertEqual(id.name, "Jane Smith")
        XCTAssertEqual(id.email, "")
        XCTAssertFalse(id.hasEmail)
    }

    func testParseEmptyIsEmpty() {
        let id = PersonResolver.parse("   ")
        XCTAssertFalse(id.hasEmail)
        XCTAssertFalse(id.hasName)
    }

    // MARK: - Resolution

    private func person(_ name: String, _ emails: [String]) -> Person {
        Person(displayName: name, emails: emails)
    }

    func testResolveByEmailWins() {
        let jane = person("Jane Smith", ["jane@acme.com"])
        let other = person("Different Name", ["jane@acme.com"]) // same email, wrong name
        // Email match should hit `other` first (same email), proving email-keyed.
        let id = PersonResolver.resolve("whoever <JANE@acme.com>", in: [other, jane])
        XCTAssertEqual(id, other.id)
    }

    func testResolveByExactNameFallback() {
        let jane = person("Jane Smith", [])
        let id = PersonResolver.resolve("jane smith", in: [jane])
        XCTAssertEqual(id, jane.id)
    }

    /// The headline regression: "Dan" must NOT resolve to "Daniel".
    func testNoSubstringMatch() {
        let daniel = person("Daniel Vasquez", ["daniel@acme.com"])
        XCTAssertNil(PersonResolver.resolve("Dan", in: [daniel]))
        XCTAssertNil(PersonResolver.resolve("Dan <dan@elsewhere.com>", in: [daniel]))
    }

    func testUnknownAttendeeResolvesNil() {
        let jane = person("Jane Smith", ["jane@acme.com"])
        XCTAssertNil(PersonResolver.resolve("Stranger <stranger@x.com>", in: [jane]))
    }

    // MARK: - Owner resolution

    func testOwnerSelfTokensResolveNil() {
        let jane = person("Jane Smith", ["jane@acme.com"])
        for token in ["Me", "I", "myself", "self"] {
            XCTAssertNil(PersonResolver.resolveOwner(token, in: [jane]), "\(token) should not resolve")
        }
    }

    func testOwnerResolvesByName() {
        let jane = person("Jane Smith", ["jane@acme.com"])
        XCTAssertEqual(PersonResolver.resolveOwner("Jane Smith", in: [jane]), jane.id)
    }

    func testOwnerNilForEmpty() {
        XCTAssertNil(PersonResolver.resolveOwner(nil, in: []))
        XCTAssertNil(PersonResolver.resolveOwner("", in: []))
    }

    // MARK: - Follow-up recipient bug (email is in the string, parse it out)

    func testEmailExtractedFromInviteString() {
        // The old resolver compared the raw string to displayName and never
        // parsed the email — so invite-sourced meetings had empty recipients.
        let id = PersonResolver.parse("Jane Smith <jane@acme.com>")
        XCTAssertEqual(id.email, "jane@acme.com")
    }

    // MARK: - Bulk resolution

    func testResolvedAttendeesFiltersUnknowns() {
        let jane = person("Jane Smith", ["jane@acme.com"])
        let attendees = ["Jane Smith <jane@acme.com>", "Stranger <x@y.com>", "Dan"]
        let resolved = PersonResolver.resolvedAttendees(attendees, in: [jane])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.personID, jane.id)
    }
}
