import XCTest
@testable import Checkpoint

final class HomeProtectionControlsTests: XCTestCase {
    func testFirstCheckpointLaunchpadRequiresReadyProtectedGoalWithoutPractice() {
        let presentation = HomeStudyBeaconPresentation(
            hasPracticeForActiveGoal: false,
            hasReadyCheckpointSet: true,
            isProtectionActive: true
        )

        XCTAssertEqual(presentation, .firstCheckpointLaunchpad)
        XCTAssertFalse(presentation.showsNextFocus)
    }

    func testActiveGoalPracticePreventsLaunchpadFromReturningInALaterWeek() {
        XCTAssertEqual(
            HomeStudyBeaconPresentation(
                hasPracticeForActiveGoal: true,
                hasReadyCheckpointSet: true,
                isProtectionActive: true
            ),
            .weeklySignal
        )
    }

    func testFirstCheckpointLaunchpadDoesNotReplaceWeeklySignalWhenNotActionable() {
        let states: [HomeStudyBeaconPresentation] = [
            HomeStudyBeaconPresentation(
                hasPracticeForActiveGoal: false,
                hasReadyCheckpointSet: false,
                isProtectionActive: true
            ),
            HomeStudyBeaconPresentation(
                hasPracticeForActiveGoal: false,
                hasReadyCheckpointSet: true,
                isProtectionActive: false
            )
        ]

        XCTAssertEqual(states, [.weeklySignal, .weeklySignal])
        XCTAssertTrue(states.allSatisfy(\.showsNextFocus))
    }

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
