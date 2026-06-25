import XCTest
@testable import MeetingScribe

/// Page-tailored toolbar (§1) + recording-indicator rule (§2).
final class ToolbarModelTests: XCTestCase {

    private func actions(_ items: [ToolbarModel.Item]) -> [ToolbarModel.Action] {
        items.compactMap { if case .button(let b) = $0 { return b.action } else { return nil } }
    }

    func testEachPageHasItsPrimaryAndSearch() {
        XCTAssertEqual(actions(ToolbarModel.items(for: .today)),
                       [.search, .voiceNote, .newMeeting])
        XCTAssertEqual(actions(ToolbarModel.items(for: .meetings)),
                       [.search, .importCalendar, .newMeeting])
        XCTAssertEqual(actions(ToolbarModel.items(for: .people)),
                       [.search, .importPeople, .addPerson])
        XCTAssertEqual(actions(ToolbarModel.items(for: .actions)),
                       [.search, .filter, .newTask])
        XCTAssertEqual(actions(ToolbarModel.items(for: .notes)),
                       [.search, .newVoiceNote])
    }

    func testPrimaryStyleOnTheLeadingActionButton() {
        // Decisions and Integrations are read-only landing pages — only a Search
        // button, no primary CTA. The "exactly one primary" rule applies to the
        // action-driving sections.
        let sectionsWithPrimary: [TopLevelSection] = [.today, .meetings, .people, .actions, .notes]
        for section in sectionsWithPrimary {
            let buttons = ToolbarModel.items(for: section).compactMap {
                item -> ToolbarModel.Button? in
                if case .button(let b) = item { return b } else { return nil }
            }
            XCTAssertEqual(buttons.filter { $0.style == .primary }.count, 1,
                           "\(section) should have exactly one primary button")
        }
    }

    func testRecordingInjectsStopAsLeftmost() {
        let items = ToolbarModel.items(for: .today, isRecordingMeeting: true)
        guard case .button(let first) = items.first else { return XCTFail("expected a button") }
        XCTAssertEqual(first.action, .stopRecording)
        XCTAssertEqual(first.style, .recording)
        // The normal set still follows.
        XCTAssertTrue(actions(items).contains(.newMeeting))
    }

    func testRecordingPresentationRules() {
        // Meeting dock: only while recording a meeting and not on Meetings tab.
        XCTAssertTrue(RecordingPresentation.showsMeetingDock(isRecordingMeeting: true, section: .today))
        XCTAssertFalse(RecordingPresentation.showsMeetingDock(isRecordingMeeting: true, section: .meetings))
        XCTAssertFalse(RecordingPresentation.showsMeetingDock(isRecordingMeeting: false, section: .today))
        // Voice hover pill tracks voice-note recording only.
        XCTAssertTrue(RecordingPresentation.showsVoiceHoverPill(isRecordingVoiceNote: true))
        XCTAssertFalse(RecordingPresentation.showsVoiceHoverPill(isRecordingVoiceNote: false))
    }
}
