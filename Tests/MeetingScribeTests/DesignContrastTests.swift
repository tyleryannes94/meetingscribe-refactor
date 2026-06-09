import XCTest
@testable import MeetingScribe

/// AV-3 — guards the contrast-retuned text tokens. The tuples mirror the values
/// in `NotionDesign.swift` (NDS.bg / textPrimary / textSecondary / textTertiary);
/// if the design changes them, update here too. Asserts each text color, once
/// composited over the page background, clears a sensible WCAG ratio so the
/// faint-gray-text regression can't come back silently.
final class DesignContrastTests: XCTestCase {

    // Dark scheme (the app's primary surface).
    private let bgDark:  (Double, Double, Double) = (28, 27, 25)
    private let primaryDark:   (Double, Double, Double, Double) = (242, 239, 230, 1)
    private let secondaryDark: (Double, Double, Double, Double) = (210, 204, 190, 0.78)
    private let tertiaryDark:  (Double, Double, Double, Double) = (210, 204, 190, 0.58)

    // Light scheme.
    private let bgLight:  (Double, Double, Double) = (248, 247, 245)
    private let primaryLight:   (Double, Double, Double, Double) = (26, 25, 23, 1)
    private let secondaryLight: (Double, Double, Double, Double) = (26, 25, 23, 0.64)
    private let tertiaryLight:  (Double, Double, Double, Double) = (26, 25, 23, 0.52)

    private func ratio(_ fg: (Double, Double, Double, Double),
                       _ bg: (Double, Double, Double)) -> Double {
        NDS.contrastRatio(NDS.composite(fg, over: bg), bg)
    }

    func testWcagHelperMatchesKnownPair() {
        // Pure black on pure white is the canonical 21:1.
        let r = NDS.contrastRatio((0, 0, 0), (255, 255, 255))
        XCTAssertEqual(r, 21, accuracy: 0.1)
    }

    func testPrimaryTextClearsAA() {
        XCTAssertGreaterThan(ratio(primaryDark, bgDark), 4.5)
        XCTAssertGreaterThan(ratio(primaryLight, bgLight), 4.5)
    }

    func testSecondaryTextClearsAA() {
        XCTAssertGreaterThan(ratio(secondaryDark, bgDark), 4.5)
        XCTAssertGreaterThan(ratio(secondaryLight, bgLight), 4.5)
    }

    func testTertiaryTextClearsLargeTextAA() {
        // Tertiary is used for de-emphasized / larger captions; require the 3:1
        // large-text AA floor (and confirm the retune actually raised it).
        XCTAssertGreaterThan(ratio(tertiaryDark, bgDark), 3.0)
        XCTAssertGreaterThan(ratio(tertiaryLight, bgLight), 3.0)
    }
}
