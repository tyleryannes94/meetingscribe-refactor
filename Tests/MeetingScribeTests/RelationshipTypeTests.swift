import XCTest
@testable import MeetingScribe

/// Phase 1 keystone coverage (master plan E5-5). The `RelationshipType` enum
/// and the new `Person` fields are the foundation every later phase branches
/// off, so they get locked down here before Phase 2 builds on them.
///
/// The most important guarantee: the tolerant `try?`-everywhere `Person`
/// decoder must silently map an unknown/misspelled raw value to `.unset`
/// rather than dropping the whole person — otherwise a future build that adds
/// a relationship type would corrupt person.json on an older build.
final class RelationshipTypeTests: XCTestCase {

    // MARK: Raw value stability (on-disk contract)

    /// These raw strings are the on-disk contract. Renaming a case without a
    /// migration would silently reclassify existing people, so pin them.
    func testRawValuesAreStable() {
        XCTAssertEqual(RelationshipType.romanticPartner.rawValue, "romantic_partner")
        XCTAssertEqual(RelationshipType.familyMember.rawValue, "family_member")
        XCTAssertEqual(RelationshipType.closeFriend.rawValue, "close_friend")
        XCTAssertEqual(RelationshipType.friend.rawValue, "friend")
        XCTAssertEqual(RelationshipType.colleague.rawValue, "colleague")
        XCTAssertEqual(RelationshipType.acquaintance.rawValue, "acquaintance")
        XCTAssertEqual(RelationshipType.unset.rawValue, "unset")
    }

    /// Every case round-trips through Codable unchanged.
    func testAllCasesRoundTripThroughCodable() throws {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        for type in RelationshipType.allCases {
            let data = try enc.encode(type)
            let back = try dec.decode(RelationshipType.self, from: data)
            XCTAssertEqual(back, type, "\(type) did not round-trip")
        }
    }

    // MARK: Tolerant Person decode

    /// A person.json carrying an unknown relationship type (e.g. a value a
    /// future build wrote) must decode to `.unset`, not throw.
    func testUnknownRawValueFallsBackToUnset() throws {
        let json = """
        { "id": "p1", "displayName": "Future Person",
          "relationshipType": "situationship_2027" }
        """.data(using: .utf8)!
        let person = try JSONDecoder().decode(Person.self, from: json)
        XCTAssertEqual(person.relationshipType, .unset)
    }

    /// A person.json with no relationship type at all (older build) decodes to
    /// `.unset`.
    func testMissingRelationshipTypeDefaultsToUnset() throws {
        let json = """
        { "id": "p2", "displayName": "Legacy Person" }
        """.data(using: .utf8)!
        let person = try JSONDecoder().decode(Person.self, from: json)
        XCTAssertEqual(person.relationshipType, .unset)
    }

    /// A known raw value decodes to the right case.
    func testKnownRawValueDecodes() throws {
        let json = """
        { "id": "p3", "displayName": "Partner",
          "relationshipType": "romantic_partner" }
        """.data(using: .utf8)!
        let person = try JSONDecoder().decode(Person.self, from: json)
        XCTAssertEqual(person.relationshipType, .romanticPartner)
    }

    // MARK: Cadence semantics

    /// Closer relationships should be nudged more often than looser ones.
    /// This ordering is what drives the per-type notification cadence in
    /// Phase 2, so guard the monotonicity rather than each magic number.
    func testDefaultCadenceTightensWithCloseness() {
        let partner = RelationshipType.romanticPartner.defaultCheckInDays
        let family = RelationshipType.familyMember.defaultCheckInDays
        let close = RelationshipType.closeFriend.defaultCheckInDays
        let friend = RelationshipType.friend.defaultCheckInDays
        let colleague = RelationshipType.colleague.defaultCheckInDays
        let acquaintance = RelationshipType.acquaintance.defaultCheckInDays

        XCTAssertLessThan(partner, family)
        XCTAssertLessThan(family, close)
        XCTAssertLessThan(close, friend)
        XCTAssertLessThan(friend, colleague)
        XCTAssertLessThan(colleague, acquaintance)
        XCTAssertGreaterThan(partner, 0, "cadence must be a positive number of days")
    }

    /// P2-8 — the aspirational goal field round-trips through the tolerant
    /// Person decoder, and is absent (nil) for older records.
    func testCheckInGoalDaysRoundTrips() throws {
        var p = Person(displayName: "Sam", relationshipType: .closeFriend)
        p.checkInGoalDays = 14
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Person.self, from: data)
        XCTAssertEqual(back.checkInGoalDays, 14)

        let legacy = #"{ "id": "x", "displayName": "Legacy" }"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(Person.self, from: legacy).checkInGoalDays)
    }

    /// D1-6 — reconnect thresholds are looser than the daily-ish check-in
    /// cadence and tighten with closeness.
    func testReconnectThresholdsAreLooserThanCadenceAndOrdered() {
        XCTAssertGreaterThanOrEqual(RelationshipType.romanticPartner.reconnectThresholdDays,
                                    RelationshipType.romanticPartner.defaultCheckInDays)
        XCTAssertLessThan(RelationshipType.romanticPartner.reconnectThresholdDays,
                          RelationshipType.familyMember.reconnectThresholdDays)
        XCTAssertLessThan(RelationshipType.friend.reconnectThresholdDays,
                          RelationshipType.colleague.reconnectThresholdDays)
    }

    /// `effectiveCheckInDays` uses the user override when present, else the
    /// type default.
    func testEffectiveCheckInDaysHonoursOverride() {
        var p = Person(displayName: "Pat", relationshipType: .friend)
        XCTAssertEqual(p.effectiveCheckInDays, RelationshipType.friend.defaultCheckInDays)
        p.checkInCadenceDays = 3
        XCTAssertEqual(p.effectiveCheckInDays, 3)
    }

    // MARK: Depth-content gating

    /// Only intimate relationship types unlock coaching/reflection depth
    /// content; professional/loose ties do not.
    func testDepthContentGatedToIntimateTypes() {
        for type in RelationshipType.allCases {
            let expected = (type == .romanticPartner || type == .familyMember || type == .closeFriend)
            XCTAssertEqual(type.supportsDepthContent, expected,
                           "\(type).supportsDepthContent should be \(expected)")
        }
    }

    // MARK: Label inference (E2-10 forward migration)

    func testLabelInferenceMapsCommonLabels() {
        XCTAssertEqual(RelationshipType.inferred(fromLabel: "spouse"), .romanticPartner)
        XCTAssertEqual(RelationshipType.inferred(fromLabel: "Wife"), .romanticPartner)
        XCTAssertEqual(RelationshipType.inferred(fromLabel: "my husband"), .romanticPartner)
        XCTAssertEqual(RelationshipType.inferred(fromLabel: "Mom"), .familyMember)
        XCTAssertEqual(RelationshipType.inferred(fromLabel: "brother"), .familyMember)
        XCTAssertEqual(RelationshipType.inferred(fromLabel: "manager"), .colleague)
        XCTAssertEqual(RelationshipType.inferred(fromLabel: "coworker"), .colleague)
    }

    /// "best friend" must classify as closeFriend, not get short-circuited by
    /// the bare "friend" rule.
    func testLabelInferencePrefersCloseFriendOverFriend() {
        XCTAssertEqual(RelationshipType.inferred(fromLabel: "best friend"), .closeFriend)
        XCTAssertEqual(RelationshipType.inferred(fromLabel: "friend"), .friend)
    }

    func testLabelInferenceReturnsNilForUnknownLabel() {
        XCTAssertNil(RelationshipType.inferred(fromLabel: "acquaintance from the gym"))
        XCTAssertNil(RelationshipType.inferred(fromLabel: ""))
    }

    /// Every case has a non-empty display name, emoji, and color token so the
    /// UI never renders a blank chip.
    func testEveryCaseHasPresentationMetadata() {
        for type in RelationshipType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type) missing displayName")
            XCTAssertFalse(type.emoji.isEmpty, "\(type) missing emoji")
            XCTAssertFalse(type.colorName.isEmpty, "\(type) missing colorName")
        }
    }
}
