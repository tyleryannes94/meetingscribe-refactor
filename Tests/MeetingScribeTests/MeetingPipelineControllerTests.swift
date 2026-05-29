import XCTest
@testable import MeetingScribe
@testable import MeetingScribeShared

/// Guards the ENG-C race fix: a meeting id claimed in `transcribingIDs` (which
/// `MeetingManager.stopRecording` does synchronously via `beginPipeline` before
/// dispatching the detached finalize) must cause a concurrent "Transcribe Now"
/// to be rejected, so two pipelines never clobber the same transcript.md /
/// summary.md.
@MainActor
final class MeetingPipelineControllerTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pipe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    private func makeController() -> MeetingPipelineController {
        MeetingPipelineController(store: MeetingStore(),
                                  tagStore: TagStore(),
                                  actionItems: ActionItemStore())
    }

    private func meeting(_ id: String) -> Meeting {
        let start = Date()
        return Meeting(id: id, title: "M", startDate: start, endDate: start.addingTimeInterval(60),
                       attendees: [], notes: nil, location: nil, conferenceURL: nil,
                       calendarName: nil, seriesID: nil, userDescription: nil, userTitle: nil,
                       isImpromptu: true, isImported: false, segmentCount: 0)
    }

    func testBeginPipelineClaimsID() {
        let pc = makeController()
        let m = meeting("x")
        XCTAssertFalse(pc.isTranscribing(m))
        pc.beginPipeline(m.id)
        XCTAssertTrue(pc.isTranscribing(m))
    }

    func testTranscribeNowRejectedWhenAlreadyClaimed() {
        let pc = makeController()
        let m = meeting("claimed")
        pc.beginPipeline(m.id)        // finalize claims the id first
        pc.transcribeNow(meeting: m)  // must early-return, not launch a 2nd pipeline
        XCTAssertTrue(pc.isTranscribing(m))
        XCTAssertEqual(pc.transcribingIDs, [m.id],
                       "transcribeNow must not have started or cleared a second pipeline")
    }
}
