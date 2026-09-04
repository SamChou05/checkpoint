import SwiftUI
import XCTest
@testable import Checkpoint

final class HomeFirstCheckpointRenderingTests: XCTestCase {
    @MainActor
    func testGoalSwitchMenuPresentationDescribesIdentityReadinessAndAccess() throws {
        let suiteName = "GoalSwitchMenuPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = fixedGoalSwitchCalendar
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = fixedGoalSwitchTimeZone
        let currentGoal = Goal(
            title: "Learn Swift",
            deadline: fixedGoalSwitchDate(month: 1, day: 10),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays",
            preferredQuestionStyle: .multipleChoice
        )
        let readyGoal = Goal(
            title: "Learn Swift",
            deadline: fixedGoalSwitchDate(month: 1, day: 20),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "concurrency",
            preferredQuestionStyle: .multipleChoice
        )
        let notReadyGoal = Goal(
            title: "Write clearly",
            deadline: fixedGoalSwitchDate(month: 2, day: 10),
            category: .writing,
            currentLevel: "Intermediate",
            focusAreas: "structure",
            preferredQuestionStyle: .shortAnswer
        )
        let preparingGoal = Goal(
            title: "Study calculus",
            deadline: fixedGoalSwitchDate(month: 3, day: 10),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "integrals",
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = .member
        store.goal = currentGoal
        store.goalProfiles = [currentGoal, readyGoal, notReadyGoal, preparingGoal]
        store.questions = (1...store.unlockPolicy.questionsPerSession).map {
            makeQuestion(goal: readyGoal, index: $0, topic: "concurrency")
        } + (101...102).map {
            makeQuestion(goal: notReadyGoal, index: $0, topic: "structure")
        } + [
            makeQuestion(goal: preparingGoal, index: 201, topic: "integrals")
        ]
        store.questionBankSyncIntents = [
            QuestionBankSyncIntent(
                goalID: preparingGoal.id,
                contextRevision: "pending-preparation",
                desiredCount: 10,
                lowWatermark: 5
            )
        ]

        let presentation = GoalSwitchMenuPresentation(
            store: store,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let current = try XCTUnwrap(presentation.options.first { $0.id == currentGoal.id })
        let ready = try XCTUnwrap(presentation.options.first { $0.id == readyGoal.id })
        let notReady = try XCTUnwrap(presentation.options.first { $0.id == notReadyGoal.id })
        let preparing = try XCTUnwrap(presentation.options.first { $0.id == preparingGoal.id })

        XCTAssertEqual(current.title, "Learn Swift · due Jan 10")
        XCTAssertEqual(ready.title, "Learn Swift · due Jan 20")
        XCTAssertNotEqual(current.title, ready.title)
        XCTAssertEqual(current.state, .current)
        XCTAssertEqual(current.menuTitle, "Learn Swift · due Jan 10")
        XCTAssertEqual(current.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(current.accessibilityValue, "Current goal")
        XCTAssertEqual(ready.state, .ready)
        XCTAssertEqual(ready.menuTitle, "Learn Swift · due Jan 20 · Ready")
        XCTAssertEqual(ready.systemImage, "circle")
        XCTAssertEqual(ready.accessibilityValue, "Checkpoint ready")
        XCTAssertEqual(notReady.state, .notReady(selectableCount: 2, requiredCount: 5))
        XCTAssertEqual(notReady.menuTitle, "Write clearly · Not ready")
        XCTAssertEqual(notReady.systemImage, "exclamationmark.circle")
        XCTAssertEqual(notReady.accessibilityValue, "Not ready, 2 of 5 questions ready")
        XCTAssertEqual(preparing.state, .preparing(selectableCount: 1, requiredCount: 5))
        XCTAssertEqual(preparing.menuTitle, "Study calculus · Preparing")
        XCTAssertEqual(preparing.systemImage, "hourglass")
        XCTAssertEqual(preparing.accessibilityValue, "Preparing, 1 of 5 questions ready")

        store.membershipTier = .starter
        let lockedPresentation = GoalSwitchMenuPresentation(
            store: store,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let locked = try XCTUnwrap(
            lockedPresentation.options.first { $0.id == readyGoal.id }
        )
        XCTAssertEqual(locked.state, .locked)
        XCTAssertEqual(locked.menuTitle, "Learn Swift · due Jan 20 · Pro")
        XCTAssertEqual(locked.systemImage, "lock.fill")
        XCTAssertEqual(locked.accessibilityValue, "Requires Pro")
    }

    @MainActor
    func testGoalSwitchConfirmationPresentationUsesExactProtectionCopy() {
        let calendar = fixedGoalSwitchCalendar
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = fixedGoalSwitchTimeZone
        let sourceGoal = Goal(
            title: "Learn Swift",
            deadline: fixedGoalSwitchDate(month: 1, day: 10),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays",
            preferredQuestionStyle: .multipleChoice
        )
        let targetGoal = Goal(
            title: "Learn Swift",
            deadline: fixedGoalSwitchDate(month: 1, day: 20),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "concurrency",
            preferredQuestionStyle: .multipleChoice
        )
        let immediate = GoalSwitchConfirmationPresentation(
            confirmation: GoalSwitchConfirmation(
                sourceGoalID: sourceGoal.id,
                sourceTitle: sourceGoal.title,
                targetGoalID: targetGoal.id,
                targetTitle: targetGoal.title,
                readiness: .incomplete(selectableCount: 2, requiredCount: 5),
                impact: .turnsOffImmediately
            ),
            goals: [sourceGoal, targetGoal],
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertEqual(immediate.sourceTitle, "Learn Swift · due Jan 10")
        XCTAssertEqual(immediate.targetTitle, "Learn Swift · due Jan 20")
        XCTAssertEqual(immediate.title, "Switch goal and turn off protection?")
        XCTAssertEqual(immediate.readinessText, "2 of 5 questions ready")
        XCTAssertEqual(
            immediate.message,
            "Learn Swift · due Jan 20 has 2 of 5 questions ready. Switching now turns off app protection. Start protection again after a full checkpoint is ready."
        )
        XCTAssertEqual(immediate.confirmationButtonTitle, "Switch and turn off")
        XCTAssertEqual(immediate.cancelButtonTitle, "Keep current goal")

        let activeBreak = GoalSwitchConfirmationPresentation(
            confirmation: GoalSwitchConfirmation(
                sourceGoalID: sourceGoal.id,
                sourceTitle: sourceGoal.title,
                targetGoalID: targetGoal.id,
                targetTitle: targetGoal.title,
                readiness: .preparing(selectableCount: 1, requiredCount: 5),
                impact: .preventsRelockAfterBreak
            ),
            goals: [sourceGoal, targetGoal],
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertEqual(activeBreak.title, "Switch goal before this break ends?")
        XCTAssertEqual(activeBreak.readinessText, "1 of 5 questions ready")
        XCTAssertEqual(
            activeBreak.message,
            "Your break will continue, but protection won't return when it ends because Learn Swift · due Jan 20 has only 1 of 5 questions ready. Start protection again after a full checkpoint is ready."
        )
        XCTAssertEqual(activeBreak.confirmationButtonTitle, "Switch goal")
        XCTAssertEqual(activeBreak.cancelButtonTitle, "Keep current goal")
    }

    @MainActor
    func testGoalIdentityMotionPolicyHonorsReduceMotion() {
        let standard = GoalIdentityMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .crossfade)
        XCTAssertNotNil(standard.animation)

        let reduced = GoalIdentityMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
    }

    @MainActor
    func testGoalOverviewResolvesCheckpointStateWithReadinessPrecedence() {
        let ready = makeGoalOverviewPresentation(
            readiness: .ready(selectableCount: 5, requiredCount: 5),
            isGenerationBlockingPractice: true,
            generationFailure: .qualityRejected
        )
        XCTAssertEqual(
            ready.checkpointState,
            .ready(
                requiredCount: 5,
                disclosure: .visible,
                isNewlyPrepared: false
            )
        )

        let contradictoryPreparing = makeGoalOverviewPresentation(
            readiness: .preparing(selectableCount: 5, requiredCount: 5),
            isGenerationBlockingPractice: true,
            generationFailure: .serviceUnavailable
        )
        XCTAssertEqual(
            contradictoryPreparing.checkpointState,
            .ready(
                requiredCount: 5,
                disclosure: .visible,
                isNewlyPrepared: false
            )
        )

        let suppressedReady = makeGoalOverviewPresentation(
            readiness: .ready(selectableCount: 5, requiredCount: 5),
            readyDisclosure: .suppressedByFirstCheckpointLaunchpad,
            isNewlyPrepared: true
        )
        XCTAssertEqual(
            suppressedReady.checkpointState,
            .ready(
                requiredCount: 5,
                disclosure: .suppressedByFirstCheckpointLaunchpad,
                isNewlyPrepared: true
            )
        )

        let preparing = makeGoalOverviewPresentation(
            readiness: .preparing(selectableCount: 2, requiredCount: 5),
            generationStatusText: "Getting your next checkpoint ready."
        )
        XCTAssertEqual(
            preparing.checkpointState,
            .preparing(
                selectableCount: 2,
                requiredCount: 5,
                detail: "Getting your next checkpoint ready."
            )
        )

        let recovery = makeGoalOverviewPresentation(
            readiness: .incomplete(selectableCount: 0, requiredCount: 5),
            isGenerationBlockingPractice: true,
            generationFailure: .qualityRejected
        )
        XCTAssertEqual(
            recovery.checkpointState,
            .recovery(
                title: QuestionGenerationFailureKind.qualityRejected.title,
                message: QuestionGenerationFailureKind.qualityRejected.message,
                actions: [.retry(isInProgress: false), .editGoal]
            )
        )

        let incomplete = makeGoalOverviewPresentation(
            readiness: .incomplete(selectableCount: 2, requiredCount: 5),
            isGenerationBlockingPractice: false,
            generationFailure: .qualityRejected
        )
        XCTAssertEqual(
            incomplete.checkpointState,
            .incomplete(selectableCount: 2, requiredCount: 5)
        )
    }

    @MainActor
    func testGoalOverviewRecoveryActionsMatchFailureCapabilities() {
        let cases: [(
            failure: QuestionGenerationFailureKind?,
            expectedActions: [HomeGoalOverviewRecoveryAction]
        )] = [
            (.serviceUnavailable, [.retry(isInProgress: false)]),
            (.transientProviderFailure, [.retry(isInProgress: false)]),
            (.qualityRejected, [.retry(isInProgress: false), .editGoal]),
            (.safetyIntervention, [.editGoal]),
            (nil, [.retry(isInProgress: false)])
        ]

        for item in cases {
            let presentation = makeGoalOverviewPresentation(
                readiness: .incomplete(selectableCount: 0, requiredCount: 5),
                isGenerationBlockingPractice: true,
                generationFailure: item.failure
            )
            guard case let .recovery(title, message, actions) = presentation.checkpointState else {
                return XCTFail("Expected a recovery state for \(String(describing: item.failure))")
            }

            XCTAssertFalse(title.isEmpty)
            XCTAssertFalse(message.isEmpty)
            XCTAssertEqual(actions, item.expectedActions)
        }

        let retrying = makeGoalOverviewPresentation(
            readiness: .incomplete(selectableCount: 0, requiredCount: 5),
            isGenerationBlockingPractice: true,
            generationFailure: .serviceUnavailable,
            isRetryingGeneration: true
        )
        guard case let .recovery(_, _, retryingActions) = retrying.checkpointState else {
            return XCTFail("Expected a retrying recovery state")
        }
        XCTAssertEqual(retryingActions, [.retry(isInProgress: true)])
        XCTAssertEqual(retryingActions.first?.title, "Trying again")
        XCTAssertEqual(retryingActions.first?.isEnabled, false)
    }

    @MainActor
    func testGoalOverviewActionDispatcherRoutesEnabledActions() {
        var retryCount = 0
        var editCount = 0
        let dispatcher = HomeGoalOverviewActionDispatcher(
            retryQuestions: { retryCount += 1 },
            editGoal: { editCount += 1 }
        )

        dispatcher.perform(.retry(isInProgress: false))
        dispatcher.perform(.editGoal)
        dispatcher.perform(.retry(isInProgress: true))

        XCTAssertEqual(retryCount, 1)
        XCTAssertEqual(editCount, 1)
    }

    @MainActor
    func testGoalOverviewGoalActionAndPassTargetUseProductPolicy() {
        XCTAssertEqual(
            makeGoalOverviewPresentation(availableGoalCount: 0).goalAction,
            .none
        )
        XCTAssertEqual(
            makeGoalOverviewPresentation(availableGoalCount: 1).goalAction,
            .editGoal
        )
        XCTAssertEqual(
            makeGoalOverviewPresentation(availableGoalCount: 2).goalAction,
            .switchGoal
        )

        let customPolicy = UnlockPolicy(
            unlockMinutes: 30,
            partialUnlockMinutes: 15,
            unlockOnPartial: false,
            questionsPerSession: 10,
            requiredCorrectAnswers: 7,
            minimumQuestionDifficulty: 3
        )
        let customTarget = makeGoalOverviewPresentation(unlockPolicy: customPolicy)
        XCTAssertEqual(customTarget.passTargetText, "7 of 10 correct")
        XCTAssertEqual(
            customTarget.passTargetAccessibilityLabel,
            "Pass target, 7 correct answers out of 10 questions."
        )
    }

    @MainActor
    func testGoalOverviewDeadlineUsesCalendarDaysAndRelevantYear() {
        var calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = locale
        calendar.timeZone = timeZone

        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
            calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: hour)
            )!
        }

        let dueToday = makeGoalOverviewPresentation(
            deadline: date(2027, 9, 4, 23),
            referenceDate: date(2027, 9, 4, 1),
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        ).deadline
        XCTAssertEqual(dueToday.state, .dueToday)
        XCTAssertEqual(dueToday.text, "Due today")
        XCTAssertEqual(dueToday.accessibilityLabel, "Due today, September 4, 2027.")

        let overdueAcrossDST = makeGoalOverviewPresentation(
            deadline: date(2027, 3, 13, 12),
            referenceDate: date(2027, 3, 15, 12),
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        ).deadline
        XCTAssertEqual(overdueAcrossDST.state, .overdue(days: 2))
        XCTAssertEqual(overdueAcrossDST.text, "Overdue · Mar 13")
        XCTAssertEqual(
            overdueAcrossDST.accessibilityLabel,
            "Overdue by 2 days. Due March 13, 2027."
        )

        let upcoming = makeGoalOverviewPresentation(
            deadline: date(2027, 10, 3, 12),
            referenceDate: date(2027, 9, 4, 12),
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        ).deadline
        XCTAssertEqual(upcoming.state, .upcoming(daysRemaining: 29))
        XCTAssertEqual(upcoming.text, "Due Oct 3")
        XCTAssertEqual(
            upcoming.accessibilityLabel,
            "Due in 29 days. Due October 3, 2027."
        )

        let nextYear = makeGoalOverviewPresentation(
            deadline: date(2028, 1, 1, 12),
            referenceDate: date(2027, 12, 31, 12),
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        ).deadline
        XCTAssertEqual(nextYear.state, .upcoming(daysRemaining: 1))
        XCTAssertEqual(nextYear.text, "Due Jan 1, 2028")
        XCTAssertEqual(
            nextYear.accessibilityLabel,
            "Due in 1 day. Due January 1, 2028."
        )
    }

    @MainActor
    func testGoalOverviewMotionPolicyHonorsReduceMotion() {
        let standard = HomeGoalOverviewMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .animated)
        XCTAssertNotNil(standard.animation)

        let reduced = HomeGoalOverviewMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
    }

    @MainActor
    func testGoalOverviewRendersAcrossKeyLayoutsAndStates() throws {
        let fixtures = [
            HomeGoalSwitchRenderFixture(
                name: "home-goal-overview-ready-overdue-single-light",
                width: 393,
                height: 1_000,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .singleReadyOverdue,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 15)
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-overview-cross-year-overdue-xxxlarge",
                width: 375,
                height: 1_400,
                colorScheme: .light,
                dynamicTypeSize: .xxxLarge,
                state: .singleReadyOverdue,
                referenceDate: fixedGoalSwitchDate(
                    year: 2028,
                    month: 1,
                    day: 15
                )
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-switch-ready-dark",
                width: 393,
                height: 1_000,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                state: .ready,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 5)
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-overview-ready-first-checkpoint-launchpad",
                width: 393,
                height: 1_200,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .ready,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 5),
                isProtectionActive: true
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-overview-preparing-compact-dark",
                width: 320,
                height: 1_000,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                state: .preparing,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 5)
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-switch-preparing-accessibility5",
                width: 393,
                height: 1_800,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                state: .preparing,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 5)
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-overview-failure-accessibility5-reduced-motion",
                width: 393,
                height: 2_200,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                state: .failed,
                reduceMotion: true,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 5)
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-switch-starter-locked-reduced-motion",
                width: 393,
                height: 1_000,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .starterLocked,
                reduceMotion: true,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 5)
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-overview-incomplete-single-light",
                width: 393,
                height: 1_000,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .incomplete,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 5)
            )
        ]

        resetSharedAppGroupState()
        defer { resetSharedAppGroupState() }

        for fixture in fixtures {
            let storeSuiteName = "HomeGoalSwitchRenderingTests.Store.\(UUID().uuidString)"
            let screenTimeSuiteName = "HomeGoalSwitchRenderingTests.ScreenTime.\(UUID().uuidString)"
            let storeDefaults = try XCTUnwrap(UserDefaults(suiteName: storeSuiteName))
            let screenTimeDefaults = try XCTUnwrap(UserDefaults(suiteName: screenTimeSuiteName))
            defer {
                storeDefaults.removePersistentDomain(forName: storeSuiteName)
                screenTimeDefaults.removePersistentDomain(forName: screenTimeSuiteName)
            }

            let store = makeGoalSwitchRenderStore(
                defaults: storeDefaults,
                state: fixture.state
            )
            let screenTime = ScreenTimeController(
                defaults: screenTimeDefaults,
                authorizer: HomeRenderScreenTimeAuthorizer()
            )
            if fixture.isProtectionActive {
                screenTime.setupState = .shieldActive
                screenTime.isShieldingEnabled = true
                screenTime.restrictedAppsSummary = "3 apps and 2 websites selected"
            }
            let workflow = CheckpointWorkflowCoordinator(
                store: store,
                protection: screenTime
            )
            let image = HostedViewRenderer.image(
                for: HomeView(
                    store: store,
                    screenTime: screenTime,
                    workflow: workflow,
                    refreshesQuestionsOnActivation: false,
                    reduceMotionOverride: fixture.reduceMotion,
                    referenceDate: fixture.referenceDate
                )
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: fixture.reduceMotion ? 0.05 : 0.35,
                renderScale: 0.5
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 1, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 1, fixture.name)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = XCTAttachment.Lifetime.keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testFirstCheckpointLaunchpadRendersAcrossKeyLayouts() {
        let fixtures = [
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-accessibility",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: launchpadSurface
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                // Preserve point geometry while keeping the full render suite's retained attachments bounded.
                renderScale: 0.5
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 1)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testEarnedBreakCardRendersAcrossKeyLayouts() {
        let fixtures = [
            HomeBreakRenderFixture(
                name: "earned-break-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-dark-ending-soon",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                secondsRemaining: 46
            ),
            HomeBreakRenderFixture(
                name: "earned-break-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-accessibility-2",
                width: 393,
                height: 1_100,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-accessibility-5-dark",
                width: 393,
                height: 2_200,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-reduce-motion",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                secondsRemaining: 0,
                relockReadiness: .waitingForCheckpoint,
                areProtectedAppsAvailable: false,
                reduceMotion: true
            )
        ]

        for fixture in fixtures {
            let now = Date()
            let image = HostedViewRenderer.image(
                for: ScrollView {
                    HomeActiveBreakCard(
                        startedAt: now.addingTimeInterval(-12 * 60),
                        expiresAt: now.addingTimeInterval(TimeInterval(fixture.secondsRemaining)),
                        relockReadiness: fixture.relockReadiness,
                        areProtectedAppsAvailable: fixture.areProtectedAppsAvailable,
                        protectedAppsSummary: "3 apps, 1 category, 2 sites selected",
                        reduceMotionOverride: fixture.reduceMotion,
                        manageApps: {},
                        endBreakEarly: {}
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
                .checkpointScreenBackground()
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                // Preserve point geometry while keeping the full render suite's retained attachments bounded.
                renderScale: 0.5
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 1)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = XCTAttachment.Lifetime.keepAlways
            add(attachment)
        }
    }

    @MainActor
    private var launchpadSurface: some View {
        ScrollView {
            HomeFirstCheckpointLaunchpad(
                requiredCorrectAnswers: 4,
                questionCount: 5,
                unlockMinutes: 30,
                protectedAppsSummary: "3 apps and 2 websites selected",
                reviewApps: {}
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 36)
        }
        .checkpointScreenBackground()
    }

    @MainActor
    private func makeGoalOverviewPresentation(
        deadline: Date? = nil,
        readiness: GoalCheckpointReadiness = .ready(
            selectableCount: 5,
            requiredCount: 5
        ),
        isGenerationBlockingPractice: Bool = false,
        generationFailure: QuestionGenerationFailureKind? = nil,
        isRetryingGeneration: Bool = false,
        readyDisclosure: HomeGoalOverviewReadyDisclosure = .visible,
        isNewlyPrepared: Bool = false,
        unlockPolicy: UnlockPolicy = .default,
        availableGoalCount: Int = 1,
        generationStatusText: String = "Getting your checkpoint ready.",
        referenceDate: Date? = nil,
        calendar: Calendar? = nil,
        locale: Locale = Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone? = nil
    ) -> HomeGoalOverviewPresentation {
        let resolvedCalendar = calendar ?? fixedGoalSwitchCalendar
        let resolvedTimeZone = timeZone ?? resolvedCalendar.timeZone
        let goal = Goal(
            title: "Build a durable learning habit",
            deadline: deadline ?? fixedGoalSwitchDate(month: 1, day: 10),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "system design",
            preferredQuestionStyle: .multipleChoice
        )

        return HomeGoalOverviewPresentation(
            goal: goal,
            readiness: readiness,
            isGenerationBlockingPractice: isGenerationBlockingPractice,
            generationFailure: generationFailure,
            isRetryingGeneration: isRetryingGeneration,
            readyDisclosure: readyDisclosure,
            isNewlyPrepared: isNewlyPrepared,
            unlockPolicy: unlockPolicy,
            availableGoalCount: availableGoalCount,
            generationStatusText: generationStatusText,
            referenceDate: referenceDate ?? fixedGoalSwitchDate(month: 1, day: 5),
            calendar: resolvedCalendar,
            locale: locale,
            timeZone: resolvedTimeZone
        )
    }

    @MainActor
    private func makeGoalSwitchRenderStore(
        defaults: UserDefaults,
        state: HomeGoalSwitchRenderState
    ) -> CheckpointStore {
        let firstGoal = Goal(
            title: "Build a polished, production-ready learning system",
            deadline: fixedGoalSwitchDate(month: 1, day: 10),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "system design, reliability, communication",
            preferredQuestionStyle: .multipleChoice
        )
        let secondGoal = Goal(
            title: firstGoal.title,
            deadline: fixedGoalSwitchDate(month: 1, day: 20),
            category: .writing,
            currentLevel: "Intermediate",
            focusAreas: "structure, editing, clarity",
            preferredQuestionStyle: .shortAnswer
        )
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = state == .starterLocked ? .starter : .member
        store.goal = firstGoal
        store.goalProfiles = switch state {
        case .singleReadyOverdue, .failed, .incomplete:
            [firstGoal]
        case .ready, .preparing, .starterLocked:
            [firstGoal, secondGoal]
        }

        switch state {
        case .ready, .singleReadyOverdue, .starterLocked:
            store.questions = (1...store.unlockPolicy.questionsPerSession).map {
                makeQuestion(goal: firstGoal, index: $0, topic: "system design")
            }
            store.questionBatchState = .ready
        case .preparing:
            store.questions = (1...2).map {
                makeQuestion(goal: firstGoal, index: $0, topic: "system design")
            }
            store.questionBatchState = .generating
        case .failed:
            store.questions = []
            store.questionBatchState = .failed
            store.lastQuestionGenerationFailure = .qualityRejected
        case .incomplete:
            store.questions = [
                makeQuestion(goal: firstGoal, index: 1, topic: "system design")
            ]
            store.questionBatchState = .idle
        }

        return store
    }

    private var fixedGoalSwitchTimeZone: TimeZone {
        TimeZone(secondsFromGMT: 0)!
    }

    private var fixedGoalSwitchCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = fixedGoalSwitchTimeZone
        return calendar
    }

    private func fixedGoalSwitchDate(
        year: Int = 2027,
        month: Int,
        day: Int,
        hour: Int = 12
    ) -> Date {
        fixedGoalSwitchCalendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour)
        )!
    }
}

private struct HomeLaunchpadRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
}

private struct HomeBreakRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var secondsRemaining: Int
    var relockReadiness: HomeActiveBreakRelockReadiness = .ready
    var areProtectedAppsAvailable = true
    var reduceMotion = false
}

private struct HomeGoalSwitchRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var state: HomeGoalSwitchRenderState
    var reduceMotion = false
    var referenceDate: Date
    var isProtectionActive = false
}

private enum HomeGoalSwitchRenderState {
    case ready
    case singleReadyOverdue
    case preparing
    case failed
    case incomplete
    case starterLocked
}

@MainActor
private final class HomeRenderScreenTimeAuthorizer: ScreenTimeAuthorizing {
    var authorizationStatus: ScreenTimeAuthorizationStatus { .approved }

    func requestAuthorization() async throws {}
}
