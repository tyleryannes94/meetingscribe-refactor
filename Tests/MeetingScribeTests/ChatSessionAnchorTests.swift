import XCTest
@testable import MeetingScribe

/// Tests for the chat session's sticky entity anchor (PR #315 + #332).
///
/// Behavior:
/// - `setContext(_:label:)` with a non-empty label becomes a sticky anchor.
/// - `setContext(_:label:)` with no label and an active anchor is a no-op
///   (top-level navigation must not blow away the conversation's grounding).
/// - `setContext(_:label:)` with no label and no anchor tracks the current
///   section.
/// - Opening Chat on a different entity replaces the anchor.
/// - `clearAnchor()` unpins without wiping the conversation.
/// - `reset()` clears both messages and anchor.
@MainActor
final class ChatSessionAnchorTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatSessionAnchorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(tempRoot.path, forKey: "storageDir")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "storageDir")
    }

    /// A label-less section call on a fresh session tracks the page context
    /// but doesn't set a sticky anchor.
    func testSectionContextWithoutAnchor() {
        let s = ChatSession()
        s.setContext("Tasks workspace", label: "")
        XCTAssertEqual(s.pageContext, "Tasks workspace")
        XCTAssertTrue(s.contextLabel.isEmpty, "no anchor → no breadcrumb pill")
    }

    /// A labeled call (person/meeting detail) becomes the sticky anchor.
    /// The breadcrumb pill takes the label.
    func testLabeledContextEstablishesAnchor() {
        let s = ChatSession()
        s.setContext("Person tab — viewing Horst (id: p-1).", label: "Horst")
        XCTAssertEqual(s.contextLabel, "Horst")
        XCTAssertTrue(s.pageContext.contains("Horst"))
    }

    /// Once an anchor is set, a section-only update (no label) must NOT clear
    /// the anchor or change the breadcrumb pill. This is the bug the original
    /// PR #315 fixed — section navigation was blowing away the Horst grounding.
    func testSectionContextDoesNotOverrideActiveAnchor() {
        let s = ChatSession()
        s.setContext("Person tab — viewing Horst (id: p-1).", label: "Horst")
        let pageBefore = s.pageContext
        let labelBefore = s.contextLabel

        // Simulate navigating to Tasks: MainWindow.onChange(of: section) calls
        // setContext with the section blurb and no label.
        s.setContext("Tasks workspace — initiatives, projects, tasks.", label: "")

        XCTAssertEqual(s.contextLabel, labelBefore, "anchor pill must persist")
        XCTAssertEqual(s.pageContext, pageBefore, "page context must remain the anchor")
    }

    /// Opening Chat on a different entity replaces the anchor.
    func testNewLabeledContextReplacesAnchor() {
        let s = ChatSession()
        s.setContext("Person tab — viewing Horst (id: p-1).", label: "Horst")
        s.setContext("Meeting — Q3 planning (id: m-2).", label: "Q3 planning")

        XCTAssertEqual(s.contextLabel, "Q3 planning")
        XCTAssertTrue(s.pageContext.contains("Q3 planning"))
        XCTAssertFalse(s.pageContext.contains("Horst"))
    }

    /// `clearAnchor()` removes the sticky anchor; subsequent section-only
    /// updates can then track the current page again.
    func testClearAnchorAllowsSectionTracking() {
        let s = ChatSession()
        s.setContext("Person tab — viewing Horst (id: p-1).", label: "Horst")
        s.clearAnchor()

        XCTAssertTrue(s.contextLabel.isEmpty)
        XCTAssertTrue(s.pageContext.isEmpty)

        s.setContext("Tasks workspace", label: "")
        XCTAssertEqual(s.pageContext, "Tasks workspace",
                       "with the anchor cleared, section navigation should track again")
        XCTAssertTrue(s.contextLabel.isEmpty)
    }

    /// `reset()` clears messages AND the anchor — used by the "new chat" button.
    func testResetClearsAnchor() {
        let s = ChatSession()
        s.setContext("Person tab — viewing Horst (id: p-1).", label: "Horst")
        s.reset()

        XCTAssertTrue(s.contextLabel.isEmpty)
        XCTAssertTrue(s.pageContext.isEmpty)
    }

    /// Anchor persists across `ChatSession` instances (relaunch path).
    func testAnchorPersistsAcrossInstances() {
        let first = ChatSession()
        first.setContext("Person tab — viewing Horst (id: p-1).", label: "Horst")

        let second = ChatSession()
        XCTAssertEqual(second.contextLabel, "Horst",
                       "anchor should reload from VaultCache")
        XCTAssertTrue(second.pageContext.contains("Horst"))

        second.reset()   // clean up persisted state for the next test run
    }

    /// After clearAnchor() + persist, a new instance starts blank.
    func testClearedAnchorDoesNotReloadOnNextLaunch() {
        let first = ChatSession()
        first.setContext("Person tab — viewing Horst (id: p-1).", label: "Horst")
        first.clearAnchor()

        let second = ChatSession()
        XCTAssertTrue(second.contextLabel.isEmpty)
        XCTAssertTrue(second.pageContext.isEmpty)
    }
}
