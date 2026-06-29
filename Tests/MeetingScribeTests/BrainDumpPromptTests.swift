import XCTest
@testable import MeetingScribe

/// Prompt-drift guards. These are intentionally narrow: they only check that
/// the parts of the system prompt the rest of the planner relies on are
/// present. If they fail, either the prompt regressed or the contract changed.
final class BrainDumpPromptTests: XCTestCase {

    func testSystemPromptIncludesGroundingAndToolCatalog() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let prompt = BrainDumpPrompts.systemPrompt(
            now: now,
            userName: "Tyler",
            contexts: [],
            projects: [(id: "p1", name: "MeetingScribe Refactor"),
                       (id: "p2", name: "Offsite Planning")],
            focusMinutes: 25,
            workdayStartHour: 9,
            workdayEndHour: 18
        )
        XCTAssertTrue(prompt.contains("Today is"), "today's date is grounded")
        XCTAssertTrue(prompt.contains("Tyler"))
        XCTAssertTrue(prompt.contains("MeetingScribe Refactor"),
                      "project inventory is included verbatim")
        // All five tool names must surface so the model can call them.
        for name in ["fetch_url", "web_search", "propose_task",
                     "propose_calendar_block", "link_existing_project"] {
            XCTAssertTrue(prompt.contains(name), "missing tool \(name)")
        }
        XCTAssertTrue(prompt.contains("25 minutes"),
                      "default focus block duration is grounded")
        XCTAssertTrue(prompt.contains("9:00 to 18:00"),
                      "work-hour window is grounded")
        XCTAssertTrue(prompt.contains("OUTPUT CONTRACT"))
    }

    func testSeedUserTurnIncludesBodyAndSources() {
        let urlSource = BrainDumpSource.url(URLSource(
            url: URL(string: "https://example.com/x")!,
            title: "Example article",
            extractedMarkdown: "# Heading\n\nBody body body",
            isLoading: false
        ))
        let session = BrainDumpSession(
            body: "Need to finish the docs.",
            sources: [urlSource]
        )
        let seed = BrainDumpPrompts.seedUserTurn(session: session)
        XCTAssertTrue(seed.contains("BRAIN DUMP:"))
        XCTAssertTrue(seed.contains("Need to finish the docs."))
        XCTAssertTrue(seed.contains("Example article"))
        XCTAssertTrue(seed.contains("Body body body"))
    }

    func testSourceBudgetTruncatesLongMarkdown() {
        let longBody = String(repeating: "A ", count: 10_000) // ~20K chars
        let urlSource = BrainDumpSource.url(URLSource(
            url: URL(string: "https://example.com/x")!,
            title: "Big",
            extractedMarkdown: longBody,
            isLoading: false
        ))
        let session = BrainDumpSession(body: "body", sources: [urlSource])
        let seed = BrainDumpPrompts.seedUserTurn(session: session)
        XCTAssertLessThan(seed.count,
                          BrainDumpPrompts.totalSourceCharBudget + 4096,
                          "seed turn is bounded by the per-source / total-source budgets")
        XCTAssertTrue(seed.contains("truncated"),
                      "truncation marker tells the model context was clipped")
    }
}
