import XCTest
@testable import MeetingScribe
@testable import VaultKit

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

    // MARK: - ENG-A: batch-repair gate

    /// An empty live transcript must always trigger the batch pass.
    func testNeedsBatchRepairWhenLiveEmpty() {
        XCTAssertTrue(MeetingPipelineController.needsBatchRepair(
            liveIsEmpty: true, droppedChunks: 0, coverageSeconds: 0, recordedDuration: 0))
    }

    /// The bug ENG-A fixes: a non-empty live transcript that dropped chunks
    /// under backpressure must still be repaired by a batch pass.
    func testNeedsBatchRepairWhenChunksDropped() {
        XCTAssertTrue(MeetingPipelineController.needsBatchRepair(
            liveIsEmpty: false, droppedChunks: 2, coverageSeconds: 1800, recordedDuration: 1800),
            "dropped chunks must force a batch repair even with a non-empty transcript")
    }

    /// Coverage more than one chunk short of the recording length (e.g. a chunk
    /// that failed whisper produced no segment) must be repaired.
    func testNeedsBatchRepairWhenCoverageShort() {
        // 30-minute recording, live only covers 20 minutes → 10-min gap > 5-min tolerance.
        XCTAssertTrue(MeetingPipelineController.needsBatchRepair(
            liveIsEmpty: false, droppedChunks: 0, coverageSeconds: 1200, recordedDuration: 1800))
    }

    /// A short recording (under one 5-minute chunk) must always run the batch
    /// pass: the live transcript is only the unvalidated in-flight flush, which
    /// can mis-transcribe good audio (the "you" bug on a 55s ad-hoc recording).
    func testNeedsBatchRepairForShortRecording() {
        XCTAssertTrue(MeetingPipelineController.needsBatchRepair(
            liveIsEmpty: false, droppedChunks: 0, coverageSeconds: 55, recordedDuration: 55),
            "a sub-5-minute recording must run the authoritative batch pass")
    }

    /// A complete live transcript (full coverage, no drops) must NOT trigger a
    /// redundant batch pass — the whole point of the live path.
    func testNoBatchWhenLiveComplete() {
        // Coverage within one chunk of the end is just the in-flight tail.
        XCTAssertFalse(MeetingPipelineController.needsBatchRepair(
            liveIsEmpty: false, droppedChunks: 0, coverageSeconds: 1750, recordedDuration: 1800))
    }

    /// When the recording length is unknown (0), coverage can't be judged short,
    /// so only emptiness / drops can force a batch.
    func testNoCoverageJudgementWhenDurationUnknown() {
        XCTAssertFalse(MeetingPipelineController.needsBatchRepair(
            liveIsEmpty: false, droppedChunks: 0, coverageSeconds: 10, recordedDuration: 0))
    }
}
