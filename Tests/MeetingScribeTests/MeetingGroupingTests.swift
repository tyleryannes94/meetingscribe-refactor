import XCTest
@testable import MeetingScribe

/// Meetings smart grouping (§3A): NOW / TODAY / UPCOMING TODAY / UPCOMING /
/// PAST · RECORDED, classified against a fixed `now` for determinism.
final class MeetingGroupingTests: XCTestCase {

    private let cal = Calendar.current
    private lazy var now: Date = cal.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 12))!

    private func meeting(_ id: String, _ date: Date) -> Meeting {
        Meeting(id: id, title: id, startDate: date, endDate: date, attendees: [],
                notes: nil, location: nil, conferenceURL: nil, calendarName: nil,
                seriesID: nil, userDescription: nil, userTitle: nil)
    }
    private func at(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
    }

    func testClassifiesEachSection() {
        let meetings = [
            meeting("past", at(2, 9)),          // earlier day → pastRecorded
            meeting("todayAM", at(9, 10)),      // today, before now → today
            meeting("todayPM", at(9, 14)),      // today, after now → upcomingToday
            meeting("tomorrow", at(10, 9)),     // future day → upcoming
            meeting("live", at(9, 11)),         // today, but it's the live one → now
        ]
        let groups = MeetingGrouping.group(meetings, liveMeetingID: "live", now: now, calendar: cal)
        let map = Dictionary(uniqueKeysWithValues: groups.map { ($0.section, $0.meetings.map(\.id)) })

        XCTAssertEqual(map[.now], ["live"])
        XCTAssertEqual(map[.today], ["todayAM"])
        XCTAssertEqual(map[.upcomingToday], ["todayPM"])
        XCTAssertEqual(map[.upcoming], ["tomorrow"])
        XCTAssertEqual(map[.pastRecorded], ["past"])
    }

    func testSectionOrderAndSorting() {
        let meetings = [
            meeting("p1", at(1, 9)), meeting("p2", at(5, 9)),     // past: newest first → p2, p1
            meeting("u1", at(11, 9)), meeting("u2", at(10, 9)),   // upcoming: soonest first → u2, u1
        ]
        let groups = MeetingGrouping.group(meetings, now: now, calendar: cal)
        // Section display order: (now), today, upcomingToday, upcoming, pastRecorded
        XCTAssertEqual(groups.map(\.section), [.upcoming, .pastRecorded])
        XCTAssertEqual(groups.first(where: { $0.section == .upcoming })?.meetings.map(\.id), ["u2", "u1"])
        XCTAssertEqual(groups.first(where: { $0.section == .pastRecorded })?.meetings.map(\.id), ["p2", "p1"])
    }

    func testDeduplicatesByIDAndOmitsEmptySections() {
        let live = meeting("live", at(9, 11))
        // Same meeting present twice (e.g. in both past + upcoming lists).
        let groups = MeetingGrouping.group([live, live], liveMeetingID: "live", now: now, calendar: cal)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].section, .now)
        XCTAssertEqual(groups[0].meetings.count, 1)
    }
}
