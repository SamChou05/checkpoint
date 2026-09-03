import XCTest
@testable import Checkpoint

final class HomeProtectionControlsTests: XCTestCase {
    func testBreakRemainingPresentationRoundsUpPartialMinutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let presentation = BreakRemainingPresentation(
            expiresAt: now.addingTimeInterval(9 * 60 + 1),
            at: now
        )

        XCTAssertEqual(presentation.minutesRemaining, 10)
        XCTAssertEqual(presentation.text, "10m")
        XCTAssertEqual(presentation.accessibilityValue, "10 minutes")
    }

    func testBreakRemainingPresentationKeepsExactMinuteBoundary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let presentation = BreakRemainingPresentation(
            expiresAt: now.addingTimeInterval(9 * 60),
            at: now
        )

        XCTAssertEqual(presentation.minutesRemaining, 9)
        XCTAssertEqual(presentation.text, "9m")
        XCTAssertEqual(presentation.accessibilityValue, "9 minutes")
    }

    func testBreakRemainingPresentationUsesEndingForExpiredOrMissingBreak() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for expiresAt in [nil, now, now.addingTimeInterval(-1)] {
            let presentation = BreakRemainingPresentation(
                expiresAt: expiresAt,
                at: now
            )

            XCTAssertNil(presentation.minutesRemaining)
            XCTAssertEqual(presentation.text, "Ending")
            XCTAssertEqual(presentation.accessibilityValue, "Ending")
        }
    }

    func testBreakRemainingPresentationUsesSingularAccessibilityMinute() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let presentation = BreakRemainingPresentation(
            expiresAt: now.addingTimeInterval(1),
            at: now
        )

        XCTAssertEqual(presentation.text, "1m")
        XCTAssertEqual(presentation.accessibilityValue, "1 minute")
    }
}
