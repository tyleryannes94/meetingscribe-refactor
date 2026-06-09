import XCTest
@testable import MeetingScribe

/// Shared People services for the redesign: inline add-email (§4A),
/// attendee-chip → Person lookup (§3E), and add-person-to-meeting dedup (§4D).
@MainActor
final class PeopleLinkageTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PeopleLinkageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    private func makeMeeting(attendees: [String]) -> Meeting {
        Meeting(id: "m1", title: "Sync", startDate: Date(), endDate: Date(),
                attendees: attendees, notes: nil, location: nil, conferenceURL: nil,
                calendarName: nil, seriesID: nil, userDescription: nil, userTitle: nil)
    }

    func testAddEmailAppendsAndDedupes() {
        let store = PeopleStore()
        let maya = Person(displayName: "Maya", emails: ["maya@skio.com"])
        store.updatePerson(maya)

        XCTAssertNotNil(store.addEmail("maya.alt@skio.com", to: maya.id))
        XCTAssertEqual(store.person(by: maya.id)?.emails.count, 2)
        // Case/format-different duplicate → no-op.
        XCTAssertNil(store.addEmail("  MAYA@skio.com ", to: maya.id))
        XCTAssertEqual(store.person(by: maya.id)?.emails.count, 2)
    }

    func testAddEmailUnknownPersonOrBlankIsNil() {
        let store = PeopleStore()
        XCTAssertNil(store.addEmail("x@y.com", to: "nope"))
        let p = Person(displayName: "P")
        store.updatePerson(p)
        XCTAssertNil(store.addEmail("   ", to: p.id))
    }

    func testPersonForEmailMatchesNormalized() {
        let store = PeopleStore()
        let maya = Person(displayName: "Maya", emails: ["maya@skio.com"])
        store.updatePerson(maya)

        XCTAssertEqual(store.person(forEmail: "  MAYA@SKIO.COM ")?.id, maya.id)
        XCTAssertNil(store.person(forEmail: "stranger@elsewhere.com"))
        XCTAssertNil(store.person(forEmail: ""))
    }

    func testAddAttendeeDedupHelper() {
        let m = makeMeeting(attendees: ["maya@skio.com"])
        // New attendee appends.
        let added = MeetingManager.meeting(m, addingAttendee: "sam@skio.com")
        XCTAssertEqual(added?.attendees, ["maya@skio.com", "sam@skio.com"])
        // Case-insensitive duplicate → nil.
        XCTAssertNil(MeetingManager.meeting(m, addingAttendee: "MAYA@SKIO.COM"))
        // Blank → nil.
        XCTAssertNil(MeetingManager.meeting(m, addingAttendee: "   "))
    }
}
