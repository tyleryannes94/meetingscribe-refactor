import XCTest
@testable import MeetingScribe

/// Regression tests for the action-item extractor. Captures the exact
/// shape of summary.md the Ollama prompt promises to emit (see
/// `OllamaService.buildPrompt`) and a handful of historical variations
/// we've had to be forgiving of in the wild.
final class ActionItemExtractorTests: XCTestCase {

    private func meeting(title: String = "Demo Sync", id: String = "m-1") -> Meeting {
        Meeting(id: id, title: title,
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600),
                attendees: ["Tyler", "Alex"],
                notes: nil, location: nil, conferenceURL: nil,
                calendarName: "Personal", seriesID: nil,
                userDescription: nil, userTitle: nil,
                isImpromptu: false, isImported: false, segmentCount: 1)
    }

    func testExtractsExactPromptShape() {
        let summary = """
        # Demo Sync — Summary

        ## TL;DR
        Nothing to see here.

        ## Action Items
        - [ ] Me — send the deck (due: 2026-05-23)
        - [ ] Tyler — file the JIRA ticket (due: unspecified)
        - [ ] Alex — review the PR (due: 2026-05-24)
        - [x] Me — already finished this (due: unspecified)

        ## Open Questions
        - Will Acme renew?
        """
        let items = ActionItemExtractor.extract(from: summary, meeting: meeting())
        // Mine: "send the deck" (Me) + "file the JIRA ticket" (Tyler) +
        // "already finished this" (Me, completed). Alex's PR review is NOT mine.
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].title, "send the deck")
        XCTAssertEqual(items[1].title, "file the JIRA ticket")
        XCTAssertEqual(items[2].title, "already finished this")
        XCTAssertEqual(items[2].status, .completed)
        XCTAssertEqual(items[0].dueDate.flatMap { ISO8601DateFormatter().string(from: $0) }?.prefix(10),
                       "2026-05-23")
    }

    func testHonorsHyphenAndEmDashSeparators() {
        let summary = """
        ## Action Items
        - [ ] Me - hyphen-separated owner (due: unspecified)
        - [ ] Me — em-dash-separated owner (due: unspecified)
        """
        let items = ActionItemExtractor.extract(from: summary, meeting: meeting())
        XCTAssertEqual(items.count, 2)
    }

    func testDropsItemsOwnedByOthers() {
        let summary = """
        ## Action Items
        - [ ] Alex — Alex's task (due: unspecified)
        - [ ] Bob — Bob's task (due: unspecified)
        """
        let items = ActionItemExtractor.extract(from: summary, meeting: meeting())
        XCTAssertEqual(items.count, 0, "Other people's items should not become mine")
    }

    func testIncludesItemAddressingMeByName() {
        let summary = """
        ## Action Items
        - [ ] Tyler, can you follow up with finance? (due: unspecified)
        """
        let items = ActionItemExtractor.extract(from: summary, meeting: meeting())
        XCTAssertEqual(items.count, 1)
    }

    func testIgnoresNoneSentinel() {
        let summary = """
        ## Action Items
        None.
        """
        let items = ActionItemExtractor.extract(from: summary, meeting: meeting())
        XCTAssertEqual(items.count, 0)
    }

    func testBareDashFallback() {
        // Some summaries drop the checkbox. We accept that too.
        let summary = """
        ## Action Items
        - Me — bare dash, no checkbox (due: unspecified)
        """
        let items = ActionItemExtractor.extract(from: summary, meeting: meeting())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.status, .open)
    }
}
