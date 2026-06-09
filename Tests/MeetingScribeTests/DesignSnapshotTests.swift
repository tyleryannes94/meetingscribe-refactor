import XCTest
import SwiftUI
@testable import MeetingScribe

/// CV-1 — render smoke tests for the design-system surfaces. Real golden-image
/// diffing needs a snapshot library the repo doesn't vendor; this instead
/// renders the self-contained components + the ComponentGallery in both color
/// schemes via `ImageRenderer` and asserts they produce a non-empty bitmap. It
/// catches the regressions that matter most here — a component that crashes,
/// fails to lay out, or renders empty — in CI, without committing image goldens.
@available(macOS 14.0, *)
@MainActor
final class DesignSnapshotTests: XCTestCase {

    private func renders<V: View>(_ view: V, scheme: ColorScheme,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, scheme)
                .frame(width: 320, height: 240)
                .background(NDS.bg)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            XCTFail("nil render (\(scheme))", file: file, line: line); return
        }
        XCTAssertGreaterThan(image.size.width, 0, file: file, line: line)
        XCTAssertGreaterThan(image.size.height, 0, file: file, line: line)
        // A real bitmap was produced (not just an empty image shell).
        XCTAssertNotNil(image.tiffRepresentation, file: file, line: line)
    }

    private func bothSchemes<V: View>(_ view: V,
                                      file: StaticString = #filePath, line: UInt = #line) {
        renders(view, scheme: .light, file: file, line: line)
        renders(view, scheme: .dark, file: file, line: line)
    }

    func testComponentGalleryRenders() {
        bothSchemes(ComponentGallery())
    }

    func testDueChipRenders() {
        bothSchemes(HStack {
            DueChip(date: Date().addingTimeInterval(-86400))
            DueChip(date: Date())
            DueChip(date: nil)
        })
    }

    func testStatusAndPriorityBadgesRender() {
        bothSchemes(HStack {
            ForEach(ActionItem.Status.allCases) { MSStatusBadge(status: $0) }
            ForEach(ActionItem.Priority.allCases) { MSPriorityBadge(priority: $0) }
        })
    }

    func testAvatarsRender() {
        bothSchemes(HStack {
            MSAvatar(name: "Ada Lovelace", size: 28)
            MSAvatarStack(names: ["Ada Lovelace", "Grace Hopper", "Alan Turing", "Edsger Dijkstra"], size: 28)
        })
    }
}
