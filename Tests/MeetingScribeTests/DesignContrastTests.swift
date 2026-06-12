import XCTest
@testable import MeetingScribe

/// AV-3 — guards the contrast-retuned text tokens. The tuples mirror the values
/// in `NotionDesign.swift` (NDS.bg / textPrimary / textSecondary / textTertiary);
/// if the design changes them, update here too. Asserts each text color, once
/// composited over the page background, clears a sensible WCAG ratio so the
/// faint-gray-text regression can't come back silently.
final class DesignContrastTests: XCTestCase {

    // Dark scheme (the app's primary surface) — Bloom plum-ink (designs/bloom.css).
    private let bgDark:  (Double, Double, Double) = (21, 18, 26)
    private let primaryDark:   (Double, Double, Double, Double) = (243, 238, 246, 1)
    private let secondaryDark: (Double, Double, Double, Double) = (243, 238, 246, 0.68)
    private let tertiaryDark:  (Double, Double, Double, Double) = (243, 238, 246, 0.54)

    // Light scheme (fallback).
    private let bgLight:  (Double, Double, Double) = (248, 246, 250)
    private let primaryLight:   (Double, Double, Double, Double) = (28, 22, 38, 1)
    private let secondaryLight: (Double, Double, Double, Double) = (28, 22, 38, 0.66)
    private let tertiaryLight:  (Double, Double, Double, Double) = (28, 22, 38, 0.62)

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

    func testTertiaryTextClearsAA() {
        // D5-2: tertiary is used at 11pt (NDS.tiny), so it must clear the 4.5:1
        // normal-text AA floor, not just the 3:1 large-text floor. The old
        // 0.44/0.50 alphas sat ~3.9:1 on the dark surface; this guard fails if
        // anyone lowers it back below AA.
        XCTAssertGreaterThan(ratio(tertiaryDark, bgDark), 4.5)
        XCTAssertGreaterThan(ratio(tertiaryLight, bgLight), 4.5)
    }
}
