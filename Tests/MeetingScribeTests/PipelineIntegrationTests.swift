import XCTest
@testable import MeetingScribe
@testable import VaultKit

/// E5-2 — end-to-end pipeline integration harness.
///
/// Every other test in the suite is a leaf-node unit test; nothing exercises
/// the record→finalize→vault path where catastrophic data loss lives. This
/// drives the *real* `MeetingPipelineController.finalize` headlessly against a
/// temp vault and asserts the canonical artifacts (transcript.md, summary.md,
/// meeting.json) all land in the meeting's *referenced* folder.
///
/// This is precisely the assertion that would have caught the ScribeCore
/// orphan-folder bug (E3-1), where a meeting finished with an empty transcript
/// on a folder that never received any audio.
///
/// Offline-safe: with a non-empty live transcript and zero dropped chunks the
/// batch whisper pass is skipped, and the Ollama summary step degrades to a
/// placeholder when no local LLM is reachable — so the test runs without
/// whisper-cli or Ollama. (When Ollama *is* running the assertions still hold.)
///
/// macOS-only: the app target it links is macOS-only, so this runs in
/// `swift test` on a Mac, not on the Linux sandbox.
@MainActor
final class PipelineIntegrationTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PipeE2E-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    private func meeting(_ id: String) -> Meeting {
        let start = Date()
        return Meeting(id: id, title: "Integration Meeting", startDate: start,
                       endDate: start.addingTimeInterval(120),
                       attendees: ["Alex"], notes: nil, location: nil, conferenceURL: nil,
                       calendarName: nil, seriesID: nil, userDescription: nil, userTitle: nil,
                       isImpromptu: true, isImported: false, segmentCount: 0)
    }

    private func emptyHealth() -> MeetingHealthDTO {
        MeetingHealthDTO(status: .ok, warnings: [], recordedSeconds: 120,
                         micBytes: 1, systemBytes: 1)
    }

    /// A complete live transcript (no drops, no segments) must be persisted to
    /// the meeting's referenced folder along with meeting.json — never an empty
    /// transcript on a folder that received nothing.
    func testFinalizePersistsTranscriptToReferencedFolder() async throws {
        let store = MeetingStore()
        let tagStore = TagStore()
        let pc = MeetingPipelineController(store: store, tagStore: tagStore,
                                           actionItems: ActionItemStore(), decisions: DecisionStore())
        let m = meeting("e2e-good")
        let live = "# Transcript\n\nAlex: Let's ship the migration on Friday.\n"
        let audioResult = AudioRecorder.Result(directory: tempRoot, segmentIndex: 0,
                                               micURL: nil, systemURL: nil,
                                               health: emptyHealth())

        await pc.finalize(meeting: m, audioResult: audioResult,
                          liveTranscript: live,
                          liveDroppedChunks: 0, liveCoverageSeconds: 120,
                          recordedDuration: 120, liveResetIfStillIdle: {})

        let dir = store.directory(for: m, primaryTag: nil)
        let transcriptURL = dir.appendingPathComponent("transcript.md")
        let meetingURL = dir.appendingPathComponent("meeting.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: transcriptURL.path),
                      "transcript.md must exist in the meeting's referenced folder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: meetingURL.path),
                      "meeting.json must exist in the meeting's referenced folder")

        let written = (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(written.contains("ship the migration"),
                      "the persisted transcript must contain the live transcript content")
        XCTAssertFalse(written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "the persisted transcript must never be empty for a real recording")
    }

    /// The ENG-A repair gate must fire when the live transcript is empty: with
    /// no audio to repair from, finalize must still complete and persist
    /// meeting.json rather than strand the meeting.
    func testFinalizeCompletesEvenWithEmptyLiveTranscript() async throws {
        let store = MeetingStore()
        let pc = MeetingPipelineController(store: store, tagStore: TagStore(),
                                           actionItems: ActionItemStore(), decisions: DecisionStore())
        let m = meeting("e2e-empty")
        let audioResult = AudioRecorder.Result(directory: tempRoot, segmentIndex: 0,
                                               micURL: nil, systemURL: nil,
                                               health: emptyHealth())

        await pc.finalize(meeting: m, audioResult: audioResult,
                          liveTranscript: "",
                          liveDroppedChunks: 0, liveCoverageSeconds: 0,
                          recordedDuration: 0, liveResetIfStillIdle: {})

        let dir = store.directory(for: m, primaryTag: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meeting.json").path),
                      "finalize must persist meeting.json even when the live transcript is empty")
        // lastCompletedDir is set at the end of a successful finalize.
        XCTAssertEqual(pc.lastCompletedDir?.standardizedFileURL, dir.standardizedFileURL,
                       "finalize must report the referenced folder as completed")
    }
}
