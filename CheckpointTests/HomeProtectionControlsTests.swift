import XCTest
@testable import Checkpoint

final class HomeProtectionControlsTests: XCTestCase {
    func testHomeKeepsFirstWinJourneyUntilTheActiveGoalHasPractice() {
        let journey = makeFirstWinJourney()
        let beforePractice = HomeStudyBeaconPresentation(
            hasPracticeForActiveGoal: false,
            firstWinJourney: journey
        )
        let afterPractice = HomeStudyBeaconPresentation(
            hasPracticeForActiveGoal: true,
            firstWinJourney: journey
        )

        XCTAssertEqual(beforePractice, .firstWinJourney(journey))
        XCTAssertEqual(beforePractice.kind, .firstWinJourney)
        XCTAssertFalse(beforePractice.showsNextFocus)
        XCTAssertTrue(beforePractice.suppressesReadyGoalDisclosure)

        XCTAssertEqual(afterPractice, .weeklySignal)
        XCTAssertEqual(afterPractice.kind, .weeklySignal)
        XCTAssertTrue(afterPractice.showsNextFocus)
        XCTAssertFalse(afterPractice.suppressesReadyGoalDisclosure)
    }

    func testFirstWinJourneyResolvesEveryOperationalPhaseDeterministically() {
        struct Fixture {
            let name: String
            var ready = true
            var preparing = false
            var generationBlocked = false
            var selectableCount = 5
            var authorizationState = ScreenTimeController.AuthorizationState.approved
            var setupState = ScreenTimeController.SetupState.authorized
            var hasSelection = true
            var protectionActive = false
            var startingProtection = false
            var errorMessage: String? = nil
            let expectedPhase: HomeFirstWinJourneyPhase
            let expectedAction: HomeFirstWinJourneyAction?
            let expectedCurrentNode: HomeFirstWinJourneyNodeID?
            let expectedCompletedCount: Int
        }

        let fixtures = [
            Fixture(
                name: "unavailable",
                authorizationState: .unavailable,
                setupState: .unavailable,
                hasSelection: false,
                expectedPhase: .screenTimeUnavailable,
                expectedAction: nil,
                expectedCurrentNode: .protectedApps,
                expectedCompletedCount: 1
            ),
            Fixture(
                name: "authorization required",
                authorizationState: .notDetermined,
                setupState: .notStarted,
                hasSelection: false,
                expectedPhase: .screenTimeAuthorizationRequired,
                expectedAction: nil,
                expectedCurrentNode: .protectedApps,
                expectedCompletedCount: 1
            ),
            Fixture(
                name: "requesting authorization",
                authorizationState: .requesting,
                setupState: .notStarted,
                hasSelection: false,
                expectedPhase: .requestingScreenTime,
                expectedAction: nil,
                expectedCurrentNode: .protectedApps,
                expectedCompletedCount: 1
            ),
            Fixture(
                name: "permission required",
                authorizationState: .denied,
                setupState: .failed,
                hasSelection: false,
                errorMessage: "Screen Time access is denied.",
                expectedPhase: .screenTimePermissionRequired,
                expectedAction: nil,
                expectedCurrentNode: .protectedApps,
                expectedCompletedCount: 1
            ),
            Fixture(
                name: "choose apps",
                hasSelection: false,
                expectedPhase: .chooseApps,
                expectedAction: .chooseApps,
                expectedCurrentNode: .protectedApps,
                expectedCompletedCount: 1
            ),
            Fixture(
                name: "protection error",
                errorMessage: "Review the selected apps.",
                expectedPhase: .protectionNeedsAttention,
                expectedAction: .reviewProtection,
                expectedCurrentNode: .protection,
                expectedCompletedCount: 2
            ),
            Fixture(
                name: "question generation failure",
                ready: false,
                generationBlocked: true,
                selectableCount: 0,
                expectedPhase: .checkpointNeedsAttention,
                expectedAction: nil,
                expectedCurrentNode: .checkpoint,
                expectedCompletedCount: 1
            ),
            Fixture(
                name: "preparing checkpoint",
                ready: false,
                preparing: true,
                selectableCount: 2,
                expectedPhase: .preparingCheckpoint,
                expectedAction: nil,
                expectedCurrentNode: .checkpoint,
                expectedCompletedCount: 1
            ),
            Fixture(
                name: "checkpoint incomplete",
                ready: false,
                selectableCount: 1,
                expectedPhase: .checkpointNotReady,
                expectedAction: .prepareAndProtect,
                expectedCurrentNode: .checkpoint,
                expectedCompletedCount: 1
            ),
            Fixture(
                name: "starting protection",
                startingProtection: true,
                expectedPhase: .startingProtection,
                expectedAction: .startProtection(isLoading: true),
                expectedCurrentNode: .protection,
                expectedCompletedCount: 2
            ),
            Fixture(
                name: "ready to protect",
                expectedPhase: .readyToProtect,
                expectedAction: .startProtection(isLoading: false),
                expectedCurrentNode: .protection,
                expectedCompletedCount: 2
            ),
            Fixture(
                name: "first checkpoint ready",
                protectionActive: true,
                expectedPhase: .firstCheckpointReady,
                expectedAction: .reviewSelection,
                expectedCurrentNode: nil,
                expectedCompletedCount: 3
            )
        ]

        for fixture in fixtures {
            let presentation = makeFirstWinJourney(
                ready: fixture.ready,
                preparing: fixture.preparing,
                generationBlocked: fixture.generationBlocked,
                selectableCount: fixture.selectableCount,
                authorizationState: fixture.authorizationState,
                setupState: fixture.setupState,
                hasSelection: fixture.hasSelection,
                protectionActive: fixture.protectionActive,
                startingProtection: fixture.startingProtection,
                errorMessage: fixture.errorMessage
            )

            XCTAssertEqual(presentation.phase, fixture.expectedPhase, fixture.name)
            XCTAssertEqual(presentation.action, fixture.expectedAction, fixture.name)
            XCTAssertEqual(
                presentation.nodes.first(where: \.isCurrent)?.id,
                fixture.expectedCurrentNode,
                fixture.name
            )
            XCTAssertEqual(
                presentation.completedStepCount,
                fixture.expectedCompletedCount,
                fixture.name
            )
            XCTAssertEqual(presentation.nodes.map(\.id), HomeFirstWinJourneyNodeID.allCases)
        }
    }

    func testFirstCheckpointReadyUsesTheRealUnlockPromise() {
        let presentation = makeFirstWinJourney(
            protectionActive: true,
            requiredCorrectAnswers: 4,
            questionCount: 5,
            unlockMinutes: 30
        )

        XCTAssertEqual(presentation.progressText, "SETUP COMPLETE")
        XCTAssertEqual(presentation.title, "Open a protected app or website")
        XCTAssertEqual(
            presentation.detail,
            "Clear 4 of 5 questions to earn a 30-minute break."
        )
        XCTAssertEqual(presentation.action, .reviewSelection)
    }

    func testFirstWinJourneyCopySupportsWebsiteOnlySelections() {
        XCTAssertEqual(HomeFirstWinJourneyNodeID.protectedApps.title, "Apps & websites")
        XCTAssertEqual(HomeFirstWinJourneyNodeID.protectedApps.compactTitle, "Apps & sites")
        XCTAssertEqual(HomeFirstWinJourneyAction.chooseApps.title, "Choose apps & sites")
        XCTAssertEqual(
            HomeFirstWinJourneyAction.chooseApps.accessibilityHint,
            "Opens the app and website picker"
        )
        XCTAssertEqual(
            HomeFirstWinJourneyAction.startProtection(isLoading: false).accessibilityHint,
            "Places your checkpoint before the apps and websites you select"
        )

        let ready = makeFirstWinJourney()
        XCTAssertEqual(
            ready.detail,
            "Your checkpoint and protected selection are ready."
        )

        let starting = makeFirstWinJourney(startingProtection: true)
        XCTAssertEqual(
            starting.detail,
            "Checkpoint is verifying your question set and protected selection."
        )
    }

    private func makeFirstWinJourney(
        ready: Bool = true,
        preparing: Bool = false,
        generationBlocked: Bool = false,
        selectableCount: Int = 5,
        authorizationState: ScreenTimeController.AuthorizationState = .approved,
        setupState: ScreenTimeController.SetupState = .authorized,
        hasSelection: Bool = true,
        protectionActive: Bool = false,
        startingProtection: Bool = false,
        errorMessage: String? = nil,
        requiredCorrectAnswers: Int = 4,
        questionCount: Int = 5,
        unlockMinutes: Int = 30
    ) -> HomeFirstWinJourneyPresentation {
        HomeFirstWinJourneyPresentation(
            hasReadyCheckpointSet: ready,
            isPreparingCheckpoint: preparing,
            isCheckpointBlockedByGeneration: generationBlocked,
            selectableQuestionCount: selectableCount,
            requiredQuestionCount: questionCount,
            authorizationState: authorizationState,
            setupState: setupState,
            hasSelection: hasSelection,
            isProtectionActive: protectionActive,
            isStartingProtection: startingProtection,
            protectionErrorMessage: errorMessage,
            protectedAppsSummary: "3 apps and 2 websites selected",
            requiredCorrectAnswers: requiredCorrectAnswers,
            questionCount: questionCount,
            unlockMinutes: unlockMinutes
        )
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
