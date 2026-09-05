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
            readyDisclosure: .suppressedByFirstWinJourney,
            isNewlyPrepared: true
        )
        XCTAssertEqual(
            suppressedReady.checkpointState,
            .ready(
                requiredCount: 5,
                disclosure: .suppressedByFirstWinJourney,
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

    func testWeeklySignalLayoutPolicyUsesCompactAndDynamicTypeBreakpoints() {
        let compact = HomeWeeklySignalLayoutPolicy(
            viewportWidth: 320,
            dynamicTypeSize: .large
        )
        XCTAssertEqual(compact.layout, .stacked)
        XCTAssertEqual(compact.contentPadding, 16)
        XCTAssertTrue(
            HomeWeeklySignalLayoutPolicy.usesCompactHomeMargins(viewportWidth: 320)
        )

        let regular = HomeWeeklySignalLayoutPolicy(
            viewportWidth: 393,
            dynamicTypeSize: .large
        )
        XCTAssertEqual(regular.layout, .regular)
        XCTAssertEqual(regular.contentPadding, 18)
        XCTAssertFalse(regular.stacksSupportingMetricLabels)
        XCTAssertFalse(
            HomeWeeklySignalLayoutPolicy.usesCompactHomeMargins(viewportWidth: 321)
        )

        for size in [
            DynamicTypeSize.xLarge,
            .xxLarge,
            .xxxLarge,
            .accessibility1,
            .accessibility5
        ] {
            XCTAssertEqual(
                HomeWeeklySignalLayoutPolicy(
                    viewportWidth: 393,
                    dynamicTypeSize: size
                ).layout,
                .stacked,
                "Expected stacked Weekly Signal layout at \(size)"
            )
        }
        XCTAssertFalse(
            HomeWeeklySignalLayoutPolicy(
                viewportWidth: 393,
                dynamicTypeSize: .xxxLarge
            ).stacksSupportingMetricLabels
        )
        XCTAssertTrue(
            HomeWeeklySignalLayoutPolicy(
                viewportWidth: 393,
                dynamicTypeSize: .accessibility1
            ).stacksSupportingMetricLabels
        )
    }

    func testWeeklySignalMotionPolicyHonorsReduceMotion() {
        let standard = HomeWeeklySignalMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .animated)
        XCTAssertNotNil(standard.animation)
        XCTAssertTrue(standard.permitsSignalEffect)

        let reduced = HomeWeeklySignalMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
        XCTAssertFalse(reduced.permitsSignalEffect)
    }

    func testWeeklySignalPresentationDrivesVisibleMetricsAndAccessibilityValue() {
        let longSkill = "Multi-stage causal inference with counterfactual model calibration"
        let metrics = WeeklyMetricsSummary(
            id: "goal-1",
            title: "Algebra foundations",
            questionsAnswered: 12,
            correctAnswers: 9,
            missedAnswers: 3,
            checkpointStreakDays: 4,
            checkpointsCleared: 2,
            strongestSkill: nil,
            reviewSkill: longSkill,
            isCurrentGoal: true
        )
        let presentation = HomeWeeklySignalHeroPresentation(
            metrics: metrics,
            practicedSkillCount: 3,
            insight: .lowestCurrentEstimate(longSkill)
        )

        XCTAssertEqual(HomeWeeklySignalHeroPresentation.actionLabel, "View weekly impact")
        XCTAssertEqual(
            presentation.visibleMetrics.map(\.id),
            [.questions, .accuracy, .breaks, .practicedSkills, .currentStreak]
        )
        XCTAssertEqual(presentation.questions.value, "12")
        XCTAssertEqual(presentation.accuracy?.value, "75%")
        XCTAssertEqual(presentation.breaks.value, "2")
        XCTAssertEqual(presentation.practicedSkills?.value, "3")
        XCTAssertEqual(presentation.currentStreak?.value, "4d")
        XCTAssertEqual(presentation.currentStreak?.label, "CURRENT STREAK")
        XCTAssertEqual(
            presentation.accessibilityValue,
            "For Algebra foundations. 12 questions answered. 75% accuracy. 2 breaks earned. 3 practiced skills. 4-day checkpoint streak. Insight: Lowest current mastery estimate, \(longSkill)."
        )

        let singular = HomeWeeklySignalHeroPresentation(
            metrics: WeeklyMetricsSummary(
                id: "goal-2",
                title: "Writing",
                questionsAnswered: 1,
                correctAnswers: 1,
                missedAnswers: 0,
                checkpointStreakDays: 2,
                checkpointsCleared: 1,
                strongestSkill: nil,
                reviewSkill: nil,
                isCurrentGoal: true
            ),
            practicedSkillCount: 1,
            insight: .answersLogged
        )
        XCTAssertEqual(
            singular.accessibilityValue,
            "For Writing. 1 question answered. 100% accuracy. 1 break earned. 1 practiced skill. 2-day checkpoint streak. Insight: Answers are shaping the skill map."
        )
    }

    func testWeeklySignalEmptyPresentationUsesReturningSafeCopy() {
        let presentation = HomeWeeklySignalHeroPresentation(
            metrics: WeeklyMetricsSummary(
                id: "goal-empty",
                title: "Long-term goal",
                questionsAnswered: 0,
                correctAnswers: 0,
                missedAnswers: 0,
                checkpointStreakDays: 0,
                checkpointsCleared: 0,
                strongestSkill: nil,
                reviewSkill: nil,
                isCurrentGoal: true
            ),
            practicedSkillCount: 4,
            insight: nil
        )

        XCTAssertFalse(presentation.hasActivity)
        XCTAssertTrue(presentation.visibleMetrics.isEmpty)
        XCTAssertEqual(
            presentation.accessibilityValue,
            "For Long-term goal. No checkpoint activity this week. Your next checkpoint will start this week's impact view."
        )

        let breakOnly = HomeWeeklySignalHeroPresentation(
            metrics: WeeklyMetricsSummary(
                id: "goal-break",
                title: "Biology",
                questionsAnswered: 0,
                correctAnswers: 0,
                missedAnswers: 0,
                checkpointStreakDays: 0,
                checkpointsCleared: 1,
                strongestSkill: nil,
                reviewSkill: nil,
                isCurrentGoal: true
            ),
            practicedSkillCount: 0,
            insight: .checkpointsCleared(1)
        )
        XCTAssertEqual(breakOnly.visibleMetrics.map(\.id), [.questions, .breaks])
        XCTAssertNil(breakOnly.accuracy)
        XCTAssertEqual(
            breakOnly.accessibilityValue,
            "For Biology. 0 questions answered. 1 break earned. Insight: 1 checkpoint cleared this week."
        )
    }

    func testWeeklyReviewDestinationFreezesTappedCohort() {
        var calendar = fixedGoalSwitchCalendar
        calendar.firstWeekday = 2
        let referenceDate = fixedGoalSwitchDate(month: 1, day: 4, hour: 9)
        let destination = HomeWeeklyReviewDestination(
            metricsID: "goal-weekly-scope",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(destination.id, "goal-weekly-scope")
        XCTAssertEqual(destination.metricsID, "goal-weekly-scope")
        XCTAssertEqual(destination.referenceDate, referenceDate)
        XCTAssertEqual(destination.calendar, calendar)
    }

    @MainActor
    func testWeeklySignalPresentationTreatsCarriedStreakAsEmptyAtMondayBoundary() {
        var calendar = fixedGoalSwitchCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let sunday = fixedGoalSwitchDate(month: 1, day: 3)
        let mondayMorning = fixedGoalSwitchDate(month: 1, day: 4, hour: 9)
        let mondayNoon = fixedGoalSwitchDate(month: 1, day: 4)
        let goal = Goal(
            title: "Monday study plan",
            deadline: fixedGoalSwitchDate(month: 2, day: 1),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "weekly boundaries",
            preferredQuestionStyle: .multipleChoice
        )
        let sundayClear = UnlockEvent(
            goalID: goal.id,
            minutes: 10,
            createdAt: sunday
        )
        let carriedSummary = WeeklyMetricsCalculator(
            attempts: [],
            unlockEvents: [sundayClear],
            asOf: mondayNoon,
            calendar: calendar
        ).summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true,
            skillCompetencies: []
        )

        XCTAssertEqual(calendar.component(.weekday, from: mondayNoon), 2)
        XCTAssertEqual(carriedSummary.questionsAnswered, 0)
        XCTAssertEqual(carriedSummary.checkpointsCleared, 0)
        XCTAssertEqual(carriedSummary.checkpointStreakDays, 1)
        XCTAssertTrue(carriedSummary.hasWeeklyReviewActivity)

        let carriedPresentation = HomeWeeklySignalHeroPresentation(
            metrics: carriedSummary,
            practicedSkillCount: 0,
            insight: carriedSummary.weeklySignalInsight
        )
        XCTAssertFalse(carriedPresentation.hasActivity)
        XCTAssertTrue(carriedPresentation.visibleMetrics.isEmpty)
        XCTAssertNil(carriedPresentation.insight)
        XCTAssertEqual(
            carriedPresentation.accessibilityValue,
            "For Monday study plan. No checkpoint activity this week. Your next checkpoint will start this week's impact view."
        )

        let activeSummary = WeeklyMetricsCalculator(
            attempts: [
                makeAttempt(
                    goal: goal,
                    result: .correct,
                    createdAt: mondayMorning
                )
            ],
            unlockEvents: [sundayClear],
            asOf: mondayNoon,
            calendar: calendar
        ).summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true,
            skillCompetencies: []
        )
        let activePresentation = HomeWeeklySignalHeroPresentation(
            metrics: activeSummary,
            practicedSkillCount: 0,
            insight: activeSummary.weeklySignalInsight
        )
        XCTAssertTrue(activePresentation.hasActivity)
        XCTAssertEqual(activePresentation.visibleMetrics.map(\.id), [.questions, .accuracy, .breaks])
        XCTAssertEqual(activePresentation.insight, .answersLogged)
    }

    func testWeeklySignalSkillPolicyCountsOnlySkillsPracticedThisWeek() {
        let calendar = fixedGoalSwitchCalendar
        let referenceDate = fixedGoalSwitchDate(month: 1, day: 8)
        let competencies = [
            makeWeeklySignalCompetency(
                topic: "This week",
                lastPracticedAt: fixedGoalSwitchDate(month: 1, day: 7)
            ),
            makeWeeklySignalCompetency(
                topic: "Earlier this week",
                lastPracticedAt: fixedGoalSwitchDate(month: 1, day: 4)
            ),
            makeWeeklySignalCompetency(
                topic: "Previous week",
                lastPracticedAt: fixedGoalSwitchDate(month: 1, day: 1)
            ),
            makeWeeklySignalCompetency(
                topic: "Future",
                lastPracticedAt: fixedGoalSwitchDate(month: 1, day: 9)
            ),
            makeWeeklySignalCompetency(
                topic: "Migrated date without attempts",
                lastPracticedAt: fixedGoalSwitchDate(month: 1, day: 7),
                attempts: 0
            ),
            makeWeeklySignalCompetency(topic: "Never", lastPracticedAt: nil)
        ]

        XCTAssertEqual(
            HomeWeeklySignalSkillPolicy.practicedSkillCount(
                competencies: competencies,
                asOf: referenceDate,
                calendar: calendar
            ),
            2
        )
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
                name: "home-goal-overview-ready-first-win-journey",
                width: 393,
                height: 1_200,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .ready,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 5),
                isProtectionActive: true
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-weekly-signal-populated-protected-dark",
                width: 393,
                height: 1_200,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                state: .practiced,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 5),
                isProtectionActive: true
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-weekly-signal-populated-compact-320-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .practiced,
                referenceDate: fixedGoalSwitchDate(month: 1, day: 5),
                isProtectionActive: true
            ),
            HomeGoalSwitchRenderFixture(
                name: "home-goal-overview-preparing-compact-568-dark",
                width: 320,
                height: 568,
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
                state: fixture.state,
                referenceDate: fixture.referenceDate
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
                    referenceDate: fixture.referenceDate,
                    calendar: fixedGoalSwitchCalendar
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
    func testWeeklySignalHeroRendersAcrossResponsiveAndAccessibleLayouts() throws {
        let referenceDate = fixedGoalSwitchDate(month: 1, day: 8)
        let longSkill = "Multi-stage causal inference with counterfactual model calibration"
        let emptyMetrics = WeeklyMetricsSummary(
            id: "empty-goal",
            title: "Build a durable study habit",
            questionsAnswered: 0,
            correctAnswers: 0,
            missedAnswers: 0,
            checkpointStreakDays: 0,
            checkpointsCleared: 0,
            strongestSkill: nil,
            reviewSkill: nil,
            isCurrentGoal: true
        )
        let populatedMetrics = WeeklyMetricsSummary(
            id: "populated-goal",
            title: "Advanced quantitative reasoning",
            questionsAnswered: 18,
            correctAnswers: 13,
            missedAnswers: 5,
            checkpointStreakDays: 6,
            checkpointsCleared: 3,
            strongestSkill: "Probabilistic modeling",
            reviewSkill: longSkill,
            isCurrentGoal: true
        )
        let practicedCompetencies = [
            makeWeeklySignalCompetency(
                topic: longSkill,
                lastPracticedAt: fixedGoalSwitchDate(month: 1, day: 7)
            ),
            makeWeeklySignalCompetency(
                topic: "Probabilistic modeling",
                lastPracticedAt: fixedGoalSwitchDate(month: 1, day: 6)
            ),
            makeWeeklySignalCompetency(
                topic: "Durable knowledge retrieval under changing constraints",
                lastPracticedAt: fixedGoalSwitchDate(month: 1, day: 5)
            )
        ]
        let fixtures = [
            HomeWeeklySignalRenderFixture(
                name: "home-weekly-signal-populated-compact-320-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                metrics: populatedMetrics,
                competencies: practicedCompetencies,
                insight: .lowestCurrentEstimate(longSkill),
                expectedLayout: .stacked
            ),
            HomeWeeklySignalRenderFixture(
                name: "home-weekly-signal-empty-regular-light",
                width: 393,
                height: 700,
                colorScheme: .light,
                dynamicTypeSize: .large,
                metrics: emptyMetrics,
                competencies: [],
                insight: nil,
                expectedLayout: .regular
            ),
            HomeWeeklySignalRenderFixture(
                name: "home-weekly-signal-populated-regular-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                metrics: populatedMetrics,
                competencies: practicedCompetencies,
                insight: .lowestCurrentEstimate(longSkill),
                expectedLayout: .regular
            ),
            HomeWeeklySignalRenderFixture(
                name: "home-weekly-signal-long-xxxlarge-dark",
                width: 393,
                height: 1_200,
                colorScheme: .dark,
                dynamicTypeSize: .xxxLarge,
                metrics: populatedMetrics,
                competencies: practicedCompetencies,
                insight: .lowestCurrentEstimate(longSkill),
                expectedLayout: .stacked
            ),
            HomeWeeklySignalRenderFixture(
                name: "home-weekly-signal-long-accessibility5-light-reduced",
                width: 393,
                height: 1_800,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                metrics: populatedMetrics,
                competencies: practicedCompetencies,
                insight: .lowestCurrentEstimate(longSkill),
                reduceMotion: true,
                expectedLayout: .stacked
            )
        ]

        for fixture in fixtures {
            let layoutCapture = HomeWeeklySignalLayoutCapture()
            let horizontalMargin: CGFloat =
                HomeWeeklySignalLayoutPolicy.usesCompactHomeMargins(
                    viewportWidth: fixture.width
                ) ? 16 : 24
            let image = HostedViewRenderer.image(
                for: ScrollView {
                    LightStudyBeaconSection(
                        metrics: fixture.metrics,
                        competencies: fixture.competencies,
                        insight: fixture.insight,
                        reduceMotionOverride: fixture.reduceMotion,
                        referenceDate: referenceDate,
                        calendar: fixedGoalSwitchCalendar,
                        layoutReporter: { element, frame in
                            layoutCapture.frames[element] = frame
                        },
                        action: {}
                    )
                    .padding(.horizontal, horizontalMargin)
                    .padding(.vertical, 20)
                }
                .checkpointScreenBackground()
                .environment(\.homeWeeklySignalViewportWidth, fixture.width)
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: fixture.reduceMotion ? 0.05 : 0.35,
                renderScale: 1
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)

            let section = try XCTUnwrap(layoutCapture.frames[.section], fixture.name)
            let actionButton = try XCTUnwrap(
                layoutCapture.frames[.actionButton],
                fixture.name
            )
            let actionAffordance = try XCTUnwrap(
                layoutCapture.frames[.actionAffordance],
                fixture.name
            )
            for frame in [section, actionButton, actionAffordance] {
                XCTAssertFalse(frame.isNull, fixture.name)
                XCTAssertFalse(frame.isInfinite, fixture.name)
                XCTAssertGreaterThan(frame.width, 0, fixture.name)
                XCTAssertGreaterThan(frame.height, 0, fixture.name)
            }
            XCTAssertTrue(
                actionButton.insetBy(dx: -0.5, dy: -0.5).contains(actionAffordance),
                "\(fixture.name) View impact pixels escaped the single weekly-impact Button"
            )
            XCTAssertGreaterThanOrEqual(
                actionAffordance.height,
                43.5,
                "\(fixture.name) View impact affordance is below the 44-point target"
            )
            XCTAssertTrue(
                section.insetBy(dx: -0.5, dy: -0.5).contains(actionButton),
                "\(fixture.name) weekly-impact Button escaped its section"
            )

            if fixture.metrics.hasWeeklyReviewActivity {
                let primaryMetric = try XCTUnwrap(
                    layoutCapture.frames[.primaryMetric],
                    fixture.name
                )
                let supportingMetrics = try XCTUnwrap(
                    layoutCapture.frames[.supportingMetrics],
                    fixture.name
                )
                switch fixture.expectedLayout {
                case .regular:
                    XCTAssertGreaterThanOrEqual(
                        supportingMetrics.minX,
                        primaryMetric.maxX,
                        "\(fixture.name) regular metrics overlap"
                    )
                case .stacked:
                    XCTAssertGreaterThanOrEqual(
                        supportingMetrics.minY,
                        primaryMetric.maxY,
                        "\(fixture.name) stacked metrics overlap"
                    )
                }
                XCTAssertTrue(
                    actionButton.insetBy(dx: -0.5, dy: -0.5).contains(primaryMetric),
                    "\(fixture.name) primary metric escaped the weekly-impact Button"
                )
                XCTAssertTrue(
                    actionButton.insetBy(dx: -0.5, dy: -0.5).contains(supportingMetrics),
                    "\(fixture.name) supporting metrics escaped the weekly-impact Button"
                )
            }

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testFirstWinJourneyRendersAcrossKeyLayoutsAndStates() {
        let fixtures = [
            HomeJourneyRenderFixture(
                name: "first-win-complete-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .complete
            ),
            HomeJourneyRenderFixture(
                name: "first-win-ready-to-protect-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                state: .readyToProtect
            ),
            HomeJourneyRenderFixture(
                name: "first-win-choose-apps-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .chooseApps
            ),
            HomeJourneyRenderFixture(
                name: "first-win-prepare-and-protect-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .checkpointIncomplete
            ),
            HomeJourneyRenderFixture(
                name: "first-win-preparing-accessibility-5",
                width: 393,
                height: 2_400,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                state: .preparing
            ),
            HomeJourneyRenderFixture(
                name: "first-win-needs-attention-dark-reduced-motion",
                width: 393,
                height: 1_100,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                state: .needsAttention,
                reduceMotion: true
            ),
            HomeJourneyRenderFixture(
                name: "first-win-unavailable-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                state: .unavailable
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: journeySurface(for: fixture)
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: fixture.reduceMotion ? 0.05 : 0.35,
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
    func testCommittedEarnedBreakHandoffWaitsForHomeToBecomeExposedBeforeRevealing() throws {
        let storeSuiteName = "HomeEarnedBreakHandoffTests.Store.\(UUID().uuidString)"
        let screenTimeSuiteName = "HomeEarnedBreakHandoffTests.ScreenTime.\(UUID().uuidString)"
        let storeDefaults = try XCTUnwrap(UserDefaults(suiteName: storeSuiteName))
        let screenTimeDefaults = try XCTUnwrap(UserDefaults(suiteName: screenTimeSuiteName))
        defer {
            storeDefaults.removePersistentDomain(forName: storeSuiteName)
            screenTimeDefaults.removePersistentDomain(forName: screenTimeSuiteName)
        }
        resetSharedAppGroupState()
        defer { resetSharedAppGroupState() }

        let initialReferenceDate = Date()
        let store = makeGoalSwitchRenderStore(
            defaults: storeDefaults,
            state: .ready,
            referenceDate: initialReferenceDate
        )
        let goal = try XCTUnwrap(store.goal)
        store.startUnlockSession(
            minutes: 10,
            expiresAt: initialReferenceDate.addingTimeInterval(10 * 60),
            goalID: goal.id
        )
        let unlock = try XCTUnwrap(store.unlockSession)
        let screenTime = ScreenTimeController(
            defaults: screenTimeDefaults,
            authorizer: HomeRenderScreenTimeAuthorizer()
        )
        screenTime.setupState = .temporarilyUnlocked
        screenTime.isShieldingEnabled = false
        screenTime.restrictedAppsSummary = "3 apps and 2 websites selected"
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: unlock.expiresAt
        )
        let workflow = CheckpointWorkflowCoordinator(store: store, protection: screenTime)
        let handoff = EarnedBreakHandoffToken(
            deliveryID: UUID(uuidString: "0A70C393-2327-41AF-B9D7-75210458A220")!,
            checkpointSessionID: UUID(uuidString: "64E71A91-86BD-46A8-A8F6-12DC2C66FD38")!,
            goalID: goal.id,
            startedAt: unlock.startedAt,
            expiresAt: unlock.expiresAt,
            unlockMinutes: 10
        )
        let capture = HomeEarnedBreakHandoffCapture(handoff: handoff)

        let image = HostedViewRenderer.image(
            for: HomeEarnedBreakHandoffHarness(
                store: store,
                screenTime: screenTime,
                workflow: workflow,
                referenceDate: unlock.startedAt.addingTimeInterval(1),
                calendar: fixedGoalSwitchCalendar,
                handoff: handoff,
                capture: capture
            )
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large),
            width: 393,
            height: 852,
            colorScheme: .light,
            settlingTime: 0.7,
            renderScale: 0.5
        )

        XCTAssertNil(capture.queue.pendingToken)
        XCTAssertEqual(capture.effects, [EarnedBreakHandoffDeliveryEffect(token: handoff)])
        XCTAssertEqual(image.size.width, 393, accuracy: 1)
        XCTAssertEqual(image.size.height, 852, accuracy: 1)
        let attachment = XCTAttachment(image: image)
        attachment.name = "earned-break-committed-handoff"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func journeySurface(for fixture: HomeJourneyRenderFixture) -> some View {
        ScrollView {
            HomeFirstWinJourneyCard(
                presentation: makeJourneyPresentation(for: fixture.state),
                reduceMotion: fixture.reduceMotion,
                manageApps: {},
                startProtection: {}
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 36)
        }
        .checkpointScreenBackground()
    }

    private func makeJourneyPresentation(
        for state: HomeJourneyRenderState
    ) -> HomeFirstWinJourneyPresentation {
        let hasReadyCheckpointSet: Bool = switch state {
        case .preparing, .needsAttention, .checkpointIncomplete:
            false
        case .chooseApps, .readyToProtect, .complete, .unavailable:
            true
        }
        let selectableQuestionCount: Int = switch state {
        case .preparing:
            2
        case .needsAttention:
            0
        case .checkpointIncomplete:
            1
        case .chooseApps, .readyToProtect, .complete, .unavailable:
            5
        }

        return HomeFirstWinJourneyPresentation(
            hasReadyCheckpointSet: hasReadyCheckpointSet,
            isPreparingCheckpoint: state == .preparing,
            isCheckpointBlockedByGeneration: state == .needsAttention,
            selectableQuestionCount: selectableQuestionCount,
            requiredQuestionCount: 5,
            authorizationState: state == .unavailable ? .unavailable : .approved,
            setupState: state == .unavailable ? .unavailable : .authorized,
            hasSelection: state != .chooseApps && state != .unavailable,
            isProtectionActive: state == .complete,
            isStartingProtection: false,
            protectionErrorMessage: nil,
            protectedAppsSummary: "3 apps and 2 websites selected",
            requiredCorrectAnswers: 4,
            questionCount: 5,
            unlockMinutes: 30
        )
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
        state: HomeGoalSwitchRenderState,
        referenceDate: Date
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
        case .ready, .preparing, .starterLocked, .practiced:
            [firstGoal, secondGoal]
        }

        switch state {
        case .ready, .singleReadyOverdue, .starterLocked, .practiced:
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

        if state == .practiced {
            store.attempts = [
                makeAttempt(
                    goal: firstGoal,
                    result: .correct,
                    createdAt: referenceDate
                ),
                makeAttempt(
                    goal: firstGoal,
                    result: .incorrect,
                    createdAt: referenceDate.addingTimeInterval(-60)
                )
            ]
        }

        return store
    }

    private func makeWeeklySignalCompetency(
        topic: String,
        lastPracticedAt: Date?,
        attempts: Int? = nil
    ) -> TopicCompetency {
        let resolvedAttempts = attempts ?? (lastPracticedAt == nil ? 0 : 1)
        return TopicCompetency(
            goalID: nil,
            topic: topic,
            estimatedLevel: 2.5,
            attempts: resolvedAttempts,
            correct: resolvedAttempts > 0 ? 1 : 0,
            partial: 0,
            incorrect: 0,
            currentStreak: resolvedAttempts > 0 ? 1 : 0,
            lastResult: resolvedAttempts > 0 ? .correct : nil,
            lastPracticedAt: lastPracticedAt
        )
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

private struct HomeJourneyRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var state: HomeJourneyRenderState
    var reduceMotion = false
}

private struct HomeWeeklySignalRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var metrics: WeeklyMetricsSummary
    var competencies: [TopicCompetency]
    var insight: WeeklySignalInsight?
    var reduceMotion = false
    var expectedLayout: HomeWeeklySignalLayout
}

@MainActor
private final class HomeWeeklySignalLayoutCapture {
    var frames: [HomeWeeklySignalLayoutElement: CGRect] = [:]
}

@MainActor
private final class HomeEarnedBreakHandoffCapture {
    var queue = EarnedBreakHandoffQueue()
    private(set) var effects: [EarnedBreakHandoffDeliveryEffect] = []

    init(handoff: EarnedBreakHandoffToken) {
        queue.issue(handoff)
    }

    func resolve(
        _ handoff: EarnedBreakHandoffToken,
        _ disposition: EarnedBreakHandoffDisposition
    ) -> Bool {
        queue.resolve(handoff, as: disposition)
    }

    func record(_ effect: EarnedBreakHandoffDeliveryEffect) {
        effects.append(effect)
    }
}

@MainActor
private struct HomeEarnedBreakHandoffHarness: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let workflow: CheckpointWorkflowCoordinator
    let referenceDate: Date
    let calendar: Calendar
    let handoff: EarnedBreakHandoffToken
    let capture: HomeEarnedBreakHandoffCapture

    @State private var isCoveredByCheckpointSheet = true

    var body: some View {
        HomeView(
            store: store,
            screenTime: screenTime,
            workflow: workflow,
            refreshesQuestionsOnActivation: false,
            reduceMotionOverride: false,
            referenceDate: referenceDate,
            calendar: calendar,
            isVisible: true,
            isSceneActive: true,
            isCoveredByParentModal: isCoveredByCheckpointSheet,
            earnedBreakHandoff: handoff,
            resolveEarnedBreakHandoff: capture.resolve,
            onEarnedBreakHandoffDelivered: capture.record
        )
        .task {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            isCoveredByCheckpointSheet = false
        }
    }
}

private enum HomeJourneyRenderState: Equatable {
    case chooseApps
    case preparing
    case needsAttention
    case checkpointIncomplete
    case readyToProtect
    case complete
    case unavailable
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

private enum HomeGoalSwitchRenderState: Equatable {
    case ready
    case singleReadyOverdue
    case preparing
    case failed
    case incomplete
    case starterLocked
    case practiced
}

@MainActor
private final class HomeRenderScreenTimeAuthorizer: ScreenTimeAuthorizing {
    var authorizationStatus: ScreenTimeAuthorizationStatus { .approved }

    func requestAuthorization() async throws {}
}
