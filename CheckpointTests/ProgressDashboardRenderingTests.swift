import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class ProgressDashboardRenderingTests: XCTestCase {
    @MainActor
    func testProgressStateMotionPolicyHonorsReduceMotion() {
        let standard = ProgressStateMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .choreographed)
        XCTAssertNotNil(standard.animation)

        let reduced = ProgressStateMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
    }

    @MainActor
    func testGoalChangePolicyResetsOnlyGoalScopedPresentation() {
        let firstGoalID = Goal.ID()
        let secondGoalID = Goal.ID()
        XCTAssertFalse(
            ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                from: firstGoalID,
                to: firstGoalID
            )
        )
        XCTAssertFalse(
            ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                from: nil,
                to: nil
            )
        )
        XCTAssertTrue(
            ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                from: firstGoalID,
                to: secondGoalID
            )
        )
        XCTAssertTrue(
            ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                from: nil,
                to: firstGoalID
            )
        )
        XCTAssertTrue(
            ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                from: firstGoalID,
                to: nil
            )
        )

        XCTAssertTrue(
            ProgressGoalSwitchInteractionPolicy.animatesScroll(
                reduceMotion: false,
                assistiveNavigationEnabled: false
            )
        )
        XCTAssertFalse(
            ProgressGoalSwitchInteractionPolicy.animatesScroll(
                reduceMotion: true,
                assistiveNavigationEnabled: false
            )
        )
        XCTAssertFalse(
            ProgressGoalSwitchInteractionPolicy.animatesScroll(
                reduceMotion: false,
                assistiveNavigationEnabled: true
            )
        )
    }

    @MainActor
    func testWeeklyImpactPresentationSummarizesActivityAndExcludesFutureDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: referenceDate))
        let days = try (0..<7).map { offset -> WeeklyPracticeDay in
            let date = try XCTUnwrap(
                calendar.date(byAdding: .day, value: offset, to: week.start)
            )
            switch offset {
            case 0:
                return WeeklyPracticeDay(
                    date: date,
                    questionsAnswered: 4,
                    correctAnswers: 3,
                    checkpointsCleared: 1,
                    earnedBreakMinutes: 30
                )
            case 2:
                return WeeklyPracticeDay(
                    date: date,
                    questionsAnswered: 5,
                    correctAnswers: 3,
                    checkpointsCleared: 1,
                    earnedBreakMinutes: 20
                )
            case 4:
                return WeeklyPracticeDay(
                    date: date,
                    questionsAnswered: 99,
                    correctAnswers: 99
                )
            default:
                return WeeklyPracticeDay(date: date, questionsAnswered: 0)
            }
        }
        let metrics = WeeklyMetricsSummary(
            id: Goal.ID().uuidString,
            title: "Lead a production architecture review",
            questionsAnswered: 9,
            correctAnswers: 6,
            missedAnswers: 3,
            checkpointStreakDays: 2,
            checkpointsCleared: 2,
            strongestSkill: nil,
            reviewSkill: nil,
            isCurrentGoal: true
        )
        let details = WeeklyImpactDetails(
            practiceDays: days,
            earnedBreakMinutes: 50,
            recoveredQuestions: 1,
            activePracticeDays: 2,
            previousWeekQuestions: 4
        )

        let presentation = ProgressWeeklyImpactPresentation(
            metrics: metrics,
            details: details,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertTrue(presentation.hasActivity)
        XCTAssertEqual(
            presentation.summaryText,
            "9 questions · 66% correct · 2 breaks earned"
        )
        XCTAssertEqual(
            presentation.accessibilityValue,
            "9 questions, 66% correct, 2 breaks earned, across 2 active days. "
                + "Activity by day: Monday, 4 questions; Wednesday, 5 questions."
        )
        XCTAssertEqual(
            presentation.days.map(\.state),
            [.active, .inactive, .active, .inactive, .future, .future, .future]
        )
        XCTAssertEqual(presentation.days[0].activityLevel, 0.8, accuracy: 0.001)
        XCTAssertEqual(presentation.days[2].activityLevel, 1, accuracy: 0.001)
        XCTAssertEqual(presentation.days[4].activityLevel, 0, accuracy: 0.001)
    }

    @MainActor
    func testWeeklyImpactEmptyRoutingAndMotionPoliciesStayTruthful() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: referenceDate))
        let days = try (0..<7).map { offset in
            WeeklyPracticeDay(
                date: try XCTUnwrap(
                    calendar.date(byAdding: .day, value: offset, to: week.start)
                ),
                questionsAnswered: 0
            )
        }
        let goalID = Goal.ID()
        let metrics = WeeklyMetricsSummary(
            id: goalID.uuidString,
            title: "Reach conversational Spanish",
            questionsAnswered: 0,
            correctAnswers: 0,
            missedAnswers: 0,
            checkpointStreakDays: 0,
            checkpointsCleared: 0,
            strongestSkill: nil,
            reviewSkill: nil,
            isCurrentGoal: true
        )
        let presentation = ProgressWeeklyImpactPresentation(
            metrics: metrics,
            details: WeeklyImpactDetails(
                practiceDays: days,
                earnedBreakMinutes: 0,
                recoveredQuestions: 0,
                activePracticeDays: 0,
                previousWeekQuestions: 0
            ),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertFalse(presentation.hasActivity)
        XCTAssertEqual(
            presentation.summaryText,
            "Your next checkpoint will start this week’s timeline."
        )
        XCTAssertEqual(
            presentation.accessibilityValue,
            "No checkpoint activity this week."
        )

        var breakOnlyDays = days
        breakOnlyDays[0].checkpointsCleared = 1
        breakOnlyDays[0].earnedBreakMinutes = 15
        var breakOnlyMetrics = metrics
        breakOnlyMetrics.checkpointsCleared = 1
        let breakOnlyPresentation = ProgressWeeklyImpactPresentation(
            metrics: breakOnlyMetrics,
            details: WeeklyImpactDetails(
                practiceDays: breakOnlyDays,
                earnedBreakMinutes: 15,
                recoveredQuestions: 0,
                activePracticeDays: 0,
                previousWeekQuestions: 0
            ),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )
        XCTAssertTrue(breakOnlyPresentation.hasActivity)
        XCTAssertEqual(breakOnlyPresentation.summaryText, "1 break earned this week")
        XCTAssertEqual(
            breakOnlyPresentation.accessibilityValue,
            "0 questions, no accuracy yet, 1 break earned, across 1 active day. "
                + "Activity by day: Monday, 1 break earned."
        )
        XCTAssertEqual(
            breakOnlyPresentation.days[0].activityLevel,
            0.45,
            accuracy: 0.001
        )

        let standard = ProgressWeeklyImpactMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .animated)
        XCTAssertNotNil(standard.animation)
        let reduced = ProgressWeeklyImpactMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)

        XCTAssertEqual(
            ProgressWeeklyImpactRoutingPolicy.destinationGoalID(
                activeGoalID: goalID,
                hasReviewedSkillMap: true
            ),
            goalID
        )
        XCTAssertNil(
            ProgressWeeklyImpactRoutingPolicy.destinationGoalID(
                activeGoalID: goalID,
                hasReviewedSkillMap: false
            )
        )
        XCTAssertNil(
            ProgressWeeklyImpactRoutingPolicy.destinationGoalID(
                activeGoalID: nil,
                hasReviewedSkillMap: true
            )
        )
    }

    @MainActor
    func testProgressDashboardRendersPrimaryStatesAcrossKeyLayouts() throws {
        let reviewedSuiteName = "ProgressDashboardRenderingTests.Reviewed.\(UUID().uuidString)"
        let reviewedEmptySuiteName = "ProgressDashboardRenderingTests.ReviewedEmpty.\(UUID().uuidString)"
        let repairSuiteName = "ProgressDashboardRenderingTests.Repair.\(UUID().uuidString)"
        let buildingSuiteName = "ProgressDashboardRenderingTests.Building.\(UUID().uuidString)"
        let suggestedSuiteName = "ProgressDashboardRenderingTests.Suggested.\(UUID().uuidString)"
        let failureSuiteName = "ProgressDashboardRenderingTests.Failure.\(UUID().uuidString)"
        let reviewedDefaults = try XCTUnwrap(UserDefaults(suiteName: reviewedSuiteName))
        let reviewedEmptyDefaults = try XCTUnwrap(UserDefaults(suiteName: reviewedEmptySuiteName))
        let repairDefaults = try XCTUnwrap(UserDefaults(suiteName: repairSuiteName))
        let buildingDefaults = try XCTUnwrap(UserDefaults(suiteName: buildingSuiteName))
        let suggestedDefaults = try XCTUnwrap(UserDefaults(suiteName: suggestedSuiteName))
        let failureDefaults = try XCTUnwrap(UserDefaults(suiteName: failureSuiteName))
        defer {
            reviewedDefaults.removePersistentDomain(forName: reviewedSuiteName)
            reviewedEmptyDefaults.removePersistentDomain(forName: reviewedEmptySuiteName)
            repairDefaults.removePersistentDomain(forName: repairSuiteName)
            buildingDefaults.removePersistentDomain(forName: buildingSuiteName)
            suggestedDefaults.removePersistentDomain(forName: suggestedSuiteName)
            failureDefaults.removePersistentDomain(forName: failureSuiteName)
        }

        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let reviewedStore = makeReviewedStore(
            defaults: reviewedDefaults,
            referenceDate: referenceDate
        )
        let reviewedEmptyStore = makeReviewedStore(
            defaults: reviewedEmptyDefaults,
            referenceDate: referenceDate,
            includesWeeklyActivity: false
        )
        let repairStore = makeRepairStore(defaults: repairDefaults)
        let buildingStore = makeBuildingStore(defaults: buildingDefaults)
        let suggestedStore = makeSuggestedStore(defaults: suggestedDefaults)
        let failureStore = makeFailureStore(defaults: failureDefaults)
        try assertReviewedFixtureContract(reviewedStore)
        let reviewedMetrics = try XCTUnwrap(
            reviewedStore.weeklyActiveGoalMetrics(
                asOf: referenceDate,
                calendar: .current
            )
        )
        let reviewedEmptyMetrics = try XCTUnwrap(
            reviewedEmptyStore.weeklyActiveGoalMetrics(
                asOf: referenceDate,
                calendar: .current
            )
        )
        XCTAssertEqual(reviewedMetrics.questionsAnswered, 6)
        XCTAssertEqual(reviewedMetrics.checkpointsCleared, 2)
        XCTAssertFalse(reviewedEmptyMetrics.hasWeeklyReviewActivity)
        XCTAssertTrue(repairStore.activeSkillMapNeedsAttention)
        XCTAssertEqual(repairStore.activeProgressCompetencies.count, 1)
        XCTAssertGreaterThan(
            repairStore.activeProgressCompetencies[0].attempts,
            0
        )
        XCTAssertNotNil(repairStore.activeProgressCompetencies[0].lastPracticedAt)
        XCTAssertEqual(repairStore.activeFocusWins.count, 1)
        XCTAssertTrue(buildingStore.isPreparingActiveGoalQuestions)
        XCTAssertEqual(buildingStore.activeFocusWins.count, 1)
        XCTAssertEqual(suggestedStore.activeDerivedSkillMap?.status, .suggested)
        XCTAssertTrue(suggestedStore.hasReadyCheckpointSet)
        XCTAssertTrue(failureStore.isQuestionGenerationBlockingPractice)
        XCTAssertEqual(failureStore.lastQuestionGenerationFailure, .qualityRejected)

        let fixtures = [
            ProgressDashboardRenderFixture(
                name: "progress-reviewed-mixed-light",
                width: 393,
                height: 2_000,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(
                        store: reviewedStore,
                        reduceMotionOverride: false,
                        referenceDateOverride: referenceDate
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-reviewed-mixed-dark",
                width: 393,
                height: 2_000,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(
                        store: reviewedStore,
                        reduceMotionOverride: false,
                        referenceDateOverride: referenceDate
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-reviewed-compact-viewport",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(
                        store: reviewedStore,
                        reduceMotionOverride: false,
                        referenceDateOverride: referenceDate
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-reviewed-accessibility-priority-reduced",
                width: 393,
                height: 2_500,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    CompetencyView(
                        store: reviewedStore,
                        reduceMotionOverride: true,
                        referenceDateOverride: referenceDate
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-reviewed-empty-week-light",
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(
                        store: reviewedEmptyStore,
                        reduceMotionOverride: false,
                        referenceDateOverride: referenceDate
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-skill-rows-accessibility2",
                width: 393,
                height: 2_500,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    ProgressSkillRowsAuditView(
                        competencies: reviewedStore.activeProgressCompetencies
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-repair-primary-order",
                width: 320,
                height: 1_100,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(store: repairStore, reduceMotionOverride: false)
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-building-primary-order",
                width: 393,
                height: 900,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(store: buildingStore, reduceMotionOverride: false)
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-suggested-map-priority",
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(store: suggestedStore, reduceMotionOverride: false)
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-generation-failure-priority-dark",
                width: 393,
                height: 1_100,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(store: failureStore, reduceMotionOverride: false)
                )
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: fixture.content
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func assertReviewedFixtureContract(_ store: CheckpointStore) throws {
        XCTAssertEqual(store.activeDerivedSkillMap?.status, .reviewed)
        XCTAssertEqual(store.availableGoalProfiles.count, 2)
        XCTAssertEqual(
            store.activeProgressCompetencies.map { CompetencyProgressBand.resolve(for: $0) },
            [.notStarted, .calibrating, .needsPractice, .building, .strong]
        )

        guard case let .recommendation(recommendation)? = store.studyFocusState else {
            return XCTFail("The reviewed fixture must expose a real Next Focus recommendation.")
        }
        XCTAssertEqual(recommendation.title, "Reliability and failure recovery")
    }

    @MainActor
    private func makeReviewedStore(
        defaults: UserDefaults,
        referenceDate: Date,
        includesWeeklyActivity: Bool = true
    ) -> CheckpointStore {
        let now = referenceDate
        let topics = [
            SkillMapTopic(name: "Requirements and constraint discovery"),
            SkillMapTopic(name: "Distributed data modeling"),
            SkillMapTopic(name: "Reliability and failure recovery"),
            SkillMapTopic(name: "Performance capacity planning"),
            SkillMapTopic(name: "Technical decision communication")
        ]
        let map = GoalSkillMap(
            topics: topics,
            status: .reviewed,
            provenance: .userEdited,
            updatedAt: now.addingTimeInterval(-86_400)
        )
        let goal = Goal(
            title: "Lead a production architecture review",
            deadline: now.addingTimeInterval(86_400 * 45),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "system design and technical communication",
            derivedSkillMap: map,
            preferredQuestionStyle: .multipleChoice
        )
        let otherGoal = Goal(
            title: "Reach conversational Spanish",
            deadline: now.addingTimeInterval(86_400 * 90),
            category: .languageLearning,
            currentLevel: "Beginner",
            focusAreas: "speaking and listening",
            preferredQuestionStyle: .shortAnswer
        )
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = .member
        store.goal = goal
        store.goalProfiles = [goal, otherGoal]
        store.questionBatchState = .ready
        store.competencies = makeMixedCompetencies(
            goalID: goal.id,
            topics: topics,
            practicedAt: now
        )
        store.questions = topics.enumerated().map { index, topic in
            CheckpointQuestion(
                goalID: goal.id,
                prompt: "Explain a practical decision in \(topic.name.lowercased()).",
                expectedAnswer: "A clear decision with a stated tradeoff.",
                explanation: "Connect the decision to the system constraint.",
                topic: topic.name,
                skillID: topic.id,
                difficulty: 3,
                format: .shortAnswer,
                status: index == 2 ? .incorrect : .new,
                nextReviewAt: index == 2 ? now.addingTimeInterval(-300) : nil,
                sourcePrompt: topic.name
            )
        }
        if includesWeeklyActivity,
           let week = Calendar.current.dateInterval(of: .weekOfYear, for: referenceDate) {
            let availablePracticeDates = (0..<7).compactMap { offset -> Date? in
                guard let day = Calendar.current.date(
                    byAdding: .day,
                    value: offset,
                    to: week.start
                ),
                let practiceDate = Calendar.current.date(
                    byAdding: .hour,
                    value: 9,
                    to: day
                ),
                practiceDate <= referenceDate else { return nil }
                return practiceDate
            }
            let firstDate = availablePracticeDates.first ?? referenceDate
            let secondDate = availablePracticeDates.dropFirst().first
                ?? firstDate.addingTimeInterval(300)
            let thirdDate = availablePracticeDates.dropFirst(2).first
                ?? secondDate.addingTimeInterval(300)
            store.attempts = [
                makeAttempt(goal: goal, result: .correct, createdAt: firstDate),
                makeAttempt(
                    goal: goal,
                    result: .incorrect,
                    createdAt: firstDate.addingTimeInterval(60)
                ),
                makeAttempt(goal: goal, result: .correct, createdAt: secondDate),
                makeAttempt(
                    goal: goal,
                    result: .partial,
                    createdAt: secondDate.addingTimeInterval(60)
                ),
                makeAttempt(goal: goal, result: .correct, createdAt: thirdDate),
                makeAttempt(
                    goal: goal,
                    result: .correct,
                    createdAt: thirdDate.addingTimeInterval(60)
                )
            ]
            store.unlockEvents = [
                UnlockEvent(goalID: goal.id, minutes: 30, createdAt: firstDate),
                UnlockEvent(goalID: goal.id, minutes: 20, createdAt: thirdDate)
            ]
        }
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Explained a consistency tradeoff without losing the room.",
                loggedAt: now
            ),
            FocusWin(
                goalID: goal.id,
                note: "Found the highest-risk failure mode before proposing infrastructure.",
                loggedAt: now.addingTimeInterval(-86_400)
            )
        ]
        return store
    }

    private func makeMixedCompetencies(
        goalID: Goal.ID,
        topics: [SkillMapTopic],
        practicedAt: Date
    ) -> [TopicCompetency] {
        let untouched = TopicCompetency.initial(
            topic: topics[0].name,
            goalID: goalID,
            skillID: topics[0].id
        )

        var calibrating = TopicCompetency.initial(
            topic: topics[1].name,
            estimatedLevel: 2,
            goalID: goalID,
            skillID: topics[1].id
        )
        calibrating.attempts = 4
        calibrating.correct = 3
        calibrating.incorrect = 1
        calibrating.currentStreak = 2
        calibrating.lastResult = .correct
        calibrating.lastPracticedAt = practicedAt

        var needsPractice = TopicCompetency.initial(
            topic: topics[2].name,
            estimatedLevel: 1,
            goalID: goalID,
            skillID: topics[2].id
        )
        needsPractice.attempts = 10
        needsPractice.correct = 2
        needsPractice.partial = 1
        needsPractice.incorrect = 7
        needsPractice.lastResult = .incorrect
        needsPractice.lastPracticedAt = practicedAt.addingTimeInterval(-3_600)

        var building = TopicCompetency.initial(
            topic: topics[3].name,
            estimatedLevel: 2,
            goalID: goalID,
            skillID: topics[3].id
        )
        building.attempts = 10
        building.correct = 6
        building.partial = 1
        building.incorrect = 3
        building.currentStreak = 1
        building.lastResult = .correct
        building.lastPracticedAt = practicedAt.addingTimeInterval(-7_200)

        var strong = TopicCompetency.initial(
            topic: topics[4].name,
            estimatedLevel: 5,
            goalID: goalID,
            skillID: topics[4].id
        )
        strong.attempts = 10
        strong.correct = 10
        strong.currentStreak = 6
        strong.lastResult = .correct
        strong.lastPracticedAt = practicedAt.addingTimeInterval(-10_800)

        return [untouched, calibrating, needsPractice, building, strong]
    }

    @MainActor
    private func makeRepairStore(defaults: UserDefaults) -> CheckpointStore {
        let now = Date()
        let goal = Goal(
            title: "Pass senior technical interviews",
            deadline: now.addingTimeInterval(86_400 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays, system design, communication",
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        var recentCompetency = TopicCompetency.initial(
            topic: "Array problem solving",
            estimatedLevel: 2,
            goalID: goal.id
        )
        recentCompetency.attempts = 4
        recentCompetency.correct = 3
        recentCompetency.incorrect = 1
        recentCompetency.currentStreak = 2
        recentCompetency.lastResult = .correct
        recentCompetency.lastPracticedAt = now.addingTimeInterval(-1_800)
        store.competencies = [recentCompetency]
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Spotted the missing base case before running the code.",
                loggedAt: now
            )
        ]
        return store
    }

    @MainActor
    private func makeSuggestedStore(defaults: UserDefaults) -> CheckpointStore {
        let now = Date()
        let topics = [
            SkillMapTopic(name: "Argument structure"),
            SkillMapTopic(name: "Evidence evaluation"),
            SkillMapTopic(name: "Timed synthesis")
        ]
        let map = GoalSkillMap(
            topics: topics,
            status: .suggested,
            provenance: .backendInferred
        )
        let goal = Goal(
            title: "Raise my analytical writing score",
            deadline: now.addingTimeInterval(86_400 * 60),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "argument analysis and timed writing",
            derivedSkillMap: map,
            preferredQuestionStyle: .shortAnswer
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questionBatchState = .ready
        store.competencies = topics.map {
            TopicCompetency.initial(
                topic: $0.name,
                goalID: goal.id,
                skillID: $0.id
            )
        }
        store.questions = (0..<5).map { index in
            let topic = topics[index % topics.count]
            return CheckpointQuestion(
                goalID: goal.id,
                prompt: "Practice \(topic.name.lowercased()) with example \(index + 1).",
                expectedAnswer: "A focused response that makes the reasoning explicit.",
                explanation: "Connect the claim, evidence, and time constraint.",
                topic: topic.name,
                skillID: topic.id,
                difficulty: 3,
                format: .shortAnswer,
                sourcePrompt: topic.name
            )
        }
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Finished a timed outline without over-editing the introduction.",
                loggedAt: now
            )
        ]
        return store
    }

    @MainActor
    private func makeBuildingStore(defaults: UserDefaults) -> CheckpointStore {
        let now = Date()
        let goal = Goal(
            title: "Build confidence with financial modeling",
            deadline: now.addingTimeInterval(86_400 * 50),
            category: .custom,
            currentLevel: "Beginner",
            focusAreas: "forecasting, scenario analysis, and communication",
            preferredQuestionStyle: .shortAnswer
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questionBatchState = .generating
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Explained the main revenue driver without reaching for jargon.",
                loggedAt: now
            )
        ]
        return store
    }

    @MainActor
    private func makeFailureStore(defaults: UserDefaults) -> CheckpointStore {
        let now = Date()
        let goal = Goal(
            title: "Prepare a confident product strategy interview",
            deadline: now.addingTimeInterval(86_400 * 21),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "product sense and prioritization",
            preferredQuestionStyle: .reflection
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questionBatchState = .failed
        store.lastQuestionGenerationFailure = .qualityRejected
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Made the tradeoff explicit before choosing a roadmap direction.",
                loggedAt: now
            )
        ]
        return store
    }
}

private struct ProgressDashboardRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var content: AnyView
}

private struct ProgressSkillRowsAuditView: View {
    var competencies: [TopicCompetency]

    var body: some View {
        ScrollView {
            SectionPanel("Focus areas") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Each proficiency state remains legible at large text sizes.")
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)

                    ForEach(Array(competencies.enumerated()), id: \.element.id) { index, competency in
                        CompetencyRow(competency: competency)

                        if index < competencies.count - 1 {
                            Divider()
                                .overlay(CheckpointTheme.hairline)
                        }
                    }
                }
            }
            .padding(20)
        }
        .checkpointScreenBackground()
    }
}
