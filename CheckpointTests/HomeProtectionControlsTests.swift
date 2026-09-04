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

    func testActiveBreakPresentationRoundsUpPartialSeconds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let presentation = HomeActiveBreakPresentation(
            startedAt: now.addingTimeInterval(-10 * 60),
            expiresAt: now.addingTimeInterval(9 * 60 + 0.2),
            relockReadiness: .ready,
            areProtectedAppsAvailable: true,
            at: now
        )

        XCTAssertEqual(presentation.phase, .active)
        XCTAssertEqual(presentation.secondsRemaining, 541)
        XCTAssertEqual(presentation.countdownText, "09:01")
        XCTAssertEqual(presentation.accessibilityValue, "9 minutes, 1 second")
    }

    func testActiveBreakPresentationKeepsExactMinuteBoundary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let presentation = HomeActiveBreakPresentation(
            startedAt: now.addingTimeInterval(-21 * 60),
            expiresAt: now.addingTimeInterval(9 * 60),
            relockReadiness: .ready,
            areProtectedAppsAvailable: true,
            at: now
        )

        XCTAssertEqual(presentation.secondsRemaining, 540)
        XCTAssertEqual(presentation.countdownText, "09:00")
        XCTAssertEqual(presentation.accessibilityValue, "9 minutes")
    }

    func testActiveBreakPresentationSupportsLongBreaksWithoutDroppingHours() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let presentation = HomeActiveBreakPresentation(
            startedAt: now,
            expiresAt: now.addingTimeInterval(90 * 60 + 5),
            relockReadiness: .ready,
            areProtectedAppsAvailable: true,
            at: now
        )

        XCTAssertEqual(presentation.countdownText, "90:05")
        XCTAssertEqual(presentation.accessibilityValue, "90 minutes, 5 seconds")
    }

    func testActiveBreakPresentationUsesEndingForExpiredOrMissingBreak() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for expiresAt in [nil, now, now.addingTimeInterval(-1)] {
            let presentation = HomeActiveBreakPresentation(
                startedAt: now.addingTimeInterval(-30 * 60),
                expiresAt: expiresAt,
                relockReadiness: .ready,
                areProtectedAppsAvailable: false,
                at: now
            )

            XCTAssertEqual(presentation.phase, .ending)
            XCTAssertEqual(presentation.countdownText, "Ending")
            XCTAssertEqual(presentation.accessibilityValue, "Ending")
            XCTAssertEqual(presentation.automaticResumeText, "Protection is resuming now.")
        }
    }

    func testActiveBreakPresentationUsesSingularAccessibilityUnits() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let presentation = HomeActiveBreakPresentation(
            startedAt: now.addingTimeInterval(-30),
            expiresAt: now.addingTimeInterval(61),
            relockReadiness: .ready,
            areProtectedAppsAvailable: true,
            at: now
        )

        XCTAssertEqual(presentation.phase, .active)
        XCTAssertEqual(presentation.countdownText, "01:01")
        XCTAssertEqual(presentation.accessibilityValue, "1 minute, 1 second")
    }

    func testActiveBreakPresentationMarksTheFinalMinuteAsEndingSoon() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let presentation = HomeActiveBreakPresentation(
            startedAt: now.addingTimeInterval(-29 * 60),
            expiresAt: now.addingTimeInterval(60),
            relockReadiness: .ready,
            areProtectedAppsAvailable: true,
            at: now
        )

        XCTAssertEqual(presentation.phase, .endingSoon)
        XCTAssertEqual(presentation.statusText, "Ending soon")
        XCTAssertEqual(presentation.title, "Protection returns soon")
    }

    func testActiveBreakPresentationCalculatesRemainingProgressFromActualSession() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let presentation = HomeActiveBreakPresentation(
            startedAt: now.addingTimeInterval(-10 * 60),
            expiresAt: now.addingTimeInterval(20 * 60),
            relockReadiness: .ready,
            areProtectedAppsAvailable: true,
            at: now
        )

        XCTAssertEqual(presentation.remainingFraction ?? 0, 2.0 / 3.0, accuracy: 0.000_001)
    }

    func testActiveBreakPresentationClampsProgressAtSessionBounds() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let expiry = start.addingTimeInterval(30 * 60)

        let beforeStart = HomeActiveBreakPresentation(
            startedAt: start,
            expiresAt: expiry,
            relockReadiness: .ready,
            areProtectedAppsAvailable: true,
            at: start.addingTimeInterval(-60)
        )
        let afterExpiry = HomeActiveBreakPresentation(
            startedAt: start,
            expiresAt: expiry,
            relockReadiness: .ready,
            areProtectedAppsAvailable: false,
            at: expiry.addingTimeInterval(60)
        )

        XCTAssertEqual(beforeStart.remainingFraction, 1)
        XCTAssertEqual(afterExpiry.remainingFraction, 0)
    }

    func testActiveBreakPresentationDoesNotInventProgressWithoutValidStart() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiry = now.addingTimeInterval(30 * 60)

        XCTAssertNil(
            HomeActiveBreakPresentation(
                startedAt: nil,
                expiresAt: expiry,
                relockReadiness: .ready,
                areProtectedAppsAvailable: true,
                at: now
            )
                .remainingFraction
        )
        XCTAssertNil(
            HomeActiveBreakPresentation(
                startedAt: expiry,
                expiresAt: expiry,
                relockReadiness: .ready,
                areProtectedAppsAvailable: true,
                at: now
            )
                .remainingFraction
        )
    }

    func testActiveBreakCopyMatchesReadyAndWaitingRelockOutcomes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activeReady = makeBreakPresentation(
            now: now,
            secondsRemaining: 10 * 60,
            relockReadiness: .ready
        )
        let activeWaiting = makeBreakPresentation(
            now: now,
            secondsRemaining: 10 * 60,
            relockReadiness: .waitingForCheckpoint
        )
        let endingSoonReady = makeBreakPresentation(
            now: now,
            secondsRemaining: 30,
            relockReadiness: .ready
        )
        let endingSoonWaiting = makeBreakPresentation(
            now: now,
            secondsRemaining: 30,
            relockReadiness: .waitingForCheckpoint
        )

        XCTAssertEqual(activeReady.title, "Enjoy the time you earned")
        XCTAssertTrue(activeReady.automaticResumeText.hasPrefix("Protection resumes automatically at "))
        XCTAssertTrue(activeReady.endBreakActionHint.contains("turns protection back on"))

        XCTAssertEqual(activeWaiting.title, "Enjoy the time you earned")
        XCTAssertTrue(activeWaiting.automaticResumeText.contains("only if another checkpoint is ready"))
        XCTAssertEqual(
            activeWaiting.endBreakActionHint,
            "Ends this break. Protection stays off; prepare another checkpoint, then restart it"
        )

        XCTAssertEqual(endingSoonReady.title, "Protection returns soon")
        XCTAssertEqual(endingSoonWaiting.title, "Your break ends soon")
    }

    func testActiveBreakTerminalStateRemovesAvailabilityAndEarlyEndClaims() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ready = makeBreakPresentation(
            now: now,
            secondsRemaining: 0,
            relockReadiness: .ready,
            areProtectedAppsAvailable: true
        )
        let waiting = makeBreakPresentation(
            now: now,
            secondsRemaining: 0,
            relockReadiness: .waitingForCheckpoint,
            areProtectedAppsAvailable: true
        )

        XCTAssertEqual(ready.title, "Protection is resuming")
        XCTAssertEqual(ready.automaticResumeText, "Protection is resuming now.")
        XCTAssertEqual(waiting.title, "Your break is ending")
        XCTAssertEqual(
            waiting.automaticResumeText,
            "Protection is staying off. Prepare another checkpoint, then restart it."
        )

        for presentation in [ready, waiting] {
            XCTAssertEqual(presentation.protectedAppsTitle, "App protection")
            XCTAssertEqual(presentation.protectedAppsSystemImage, "shield.fill")
            XCTAssertFalse(presentation.showsEndBreakAction)
        }
    }

    func testActiveBreakAvailabilityRequiresControllerConfirmation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let confirmed = makeBreakPresentation(
            now: now,
            secondsRemaining: 10 * 60,
            relockReadiness: .ready,
            areProtectedAppsAvailable: true
        )
        let unconfirmed = makeBreakPresentation(
            now: now,
            secondsRemaining: 10 * 60,
            relockReadiness: .needsAttention,
            areProtectedAppsAvailable: false
        )

        XCTAssertEqual(confirmed.protectedAppsTitle, "Protected apps are available")
        XCTAssertEqual(unconfirmed.protectedAppsTitle, "App protection")
        XCTAssertTrue(unconfirmed.automaticResumeText.contains("Protection needs attention"))
        XCTAssertEqual(
            unconfirmed.endBreakActionHint,
            "Ends this break. Protection stays off; finish its setup, then restart it"
        )
    }

    func testActiveBreakRelockReadinessRequiresPersistedAndInMemoryReadiness() {
        XCTAssertEqual(
            HomeActiveBreakRelockReadiness.resolve(
                hasRequiredScreenTimeAuthorization: true,
                hasSelection: true,
                hasReadyCheckpointSet: true,
                sharedCheckpointReady: true
            ),
            .ready
        )
        XCTAssertEqual(
            HomeActiveBreakRelockReadiness.resolve(
                hasRequiredScreenTimeAuthorization: true,
                hasSelection: true,
                hasReadyCheckpointSet: true,
                sharedCheckpointReady: nil
            ),
            .ready
        )

        for state in [
            HomeActiveBreakRelockReadiness.resolve(
                hasRequiredScreenTimeAuthorization: true,
                hasSelection: true,
                hasReadyCheckpointSet: false,
                sharedCheckpointReady: true
            ),
            HomeActiveBreakRelockReadiness.resolve(
                hasRequiredScreenTimeAuthorization: true,
                hasSelection: true,
                hasReadyCheckpointSet: true,
                sharedCheckpointReady: false
            )
        ] {
            XCTAssertEqual(state, .waitingForCheckpoint)
        }

        XCTAssertEqual(
            HomeActiveBreakRelockReadiness.resolve(
                hasRequiredScreenTimeAuthorization: false,
                hasSelection: true,
                hasReadyCheckpointSet: true,
                sharedCheckpointReady: true
            ),
            .needsAttention
        )
    }

    func testActiveBreakAccessibilityValueIncludesCriticalRelockOutcome() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let waiting = makeBreakPresentation(
            now: now,
            secondsRemaining: 30,
            relockReadiness: .waitingForCheckpoint
        )

        XCTAssertEqual(
            waiting.countdownAccessibilityValue,
            "30 seconds. \(waiting.automaticResumeText)"
        )
        XCTAssertTrue(waiting.countdownAccessibilityValue.contains("Protection turns back on only if"))
    }

    func testActiveBreakTimelineStopsAfterTheExactExpiration() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiration = now.addingTimeInterval(2.4)
        var iterator = HomeActiveBreakTimelineSchedule(expiresAt: expiration)
            .entries(from: now, mode: .normal)
            .makeIterator()

        XCTAssertEqual(iterator.next(), now)
        XCTAssertEqual(iterator.next(), now.addingTimeInterval(1))
        XCTAssertEqual(iterator.next(), now.addingTimeInterval(2))
        XCTAssertEqual(iterator.next(), expiration)
        XCTAssertNil(iterator.next())
    }

    func testActiveBreakTimelineIsStaticWithoutAFutureExpiration() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for expiration in [nil, now.addingTimeInterval(-1)] {
            var iterator = HomeActiveBreakTimelineSchedule(expiresAt: expiration)
                .entries(from: now, mode: .normal)
                .makeIterator()

            XCTAssertEqual(iterator.next(), now)
            XCTAssertNil(iterator.next())
        }
    }

    func testActiveBreakMotionPolicyRespectsReduceMotion() {
        XCTAssertEqual(HomeActiveBreakMotionPolicy(reduceMotion: false).style, .animated)
        XCTAssertEqual(HomeActiveBreakMotionPolicy(reduceMotion: true).style, .identity)
    }

    private func makeBreakPresentation(
        now: Date,
        secondsRemaining: TimeInterval,
        relockReadiness: HomeActiveBreakRelockReadiness,
        areProtectedAppsAvailable: Bool = true
    ) -> HomeActiveBreakPresentation {
        HomeActiveBreakPresentation(
            startedAt: now.addingTimeInterval(-30 * 60),
            expiresAt: now.addingTimeInterval(secondsRemaining),
            relockReadiness: relockReadiness,
            areProtectedAppsAvailable: areProtectedAppsAvailable,
            at: now
        )
    }
}
