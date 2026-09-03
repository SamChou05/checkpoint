import XCTest
@testable import Checkpoint

final class ProgressMetricsTests: CheckpointWorkflowTestCase {
    // MARK: - Progress metrics and issue reports

    @MainActor
    func testWeeklyMetricsAggregateAcrossGoalsThisWeek() {
        let store = CheckpointStore(defaults: defaults)
        let goal = makeGoal()
        let otherGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "integrals",
            preferredQuestionStyle: .multipleChoice
        )
        let now = Date()
        let lastWeek = Calendar.current.date(byAdding: .day, value: -8, to: now) ?? Date.distantPast

        store.goal = goal
        store.goalProfiles = [goal, otherGoal]
        store.attempts = [
            makeAttempt(goal: goal, result: .correct, createdAt: now),
            makeAttempt(goal: goal, result: .incorrect, createdAt: now),
            makeAttempt(goal: goal, result: .correct, createdAt: lastWeek),
            makeAttempt(goal: otherGoal, result: .correct, createdAt: now)
        ]
        store.unlockEvents = [
            UnlockEvent(goalID: goal.id, minutes: 30, createdAt: now),
            UnlockEvent(goalID: otherGoal.id, minutes: 15, createdAt: now),
            UnlockEvent(goalID: goal.id, minutes: 30, createdAt: lastWeek)
        ]

        XCTAssertEqual(store.weeklyTotalMetrics.questionsAnswered, 3)
        XCTAssertEqual(store.weeklyTotalMetrics.accuracyText, "66%")
        XCTAssertEqual(store.weeklyTotalMetrics.missedAnswers, 1)
        XCTAssertEqual(store.weeklyTotalMetrics.checkpointStreakDays, 1)
        XCTAssertEqual(store.weeklyTotalMetrics.checkpointStreakText, "1 day")
        XCTAssertEqual(store.weeklyTotalMetrics.checkpointsCleared, 2)
        XCTAssertTrue(store.weeklyTotalMetrics.hasWeeklyReviewActivity)

        guard let activeMetrics = store.weeklyActiveGoalMetrics else {
            XCTFail("Expected active goal weekly metrics.")
            return
        }
        XCTAssertEqual(activeMetrics.questionsAnswered, 2)
        XCTAssertEqual(activeMetrics.accuracyText, "50%")
        XCTAssertEqual(activeMetrics.missedAnswers, 1)
        XCTAssertEqual(activeMetrics.checkpointStreakDays, 1)
        XCTAssertEqual(activeMetrics.checkpointsCleared, 1)

        let otherGoalMetrics = store.weeklyGoalMetrics.first { $0.id == otherGoal.id.uuidString }
        XCTAssertEqual(otherGoalMetrics?.questionsAnswered, 1)
        XCTAssertEqual(otherGoalMetrics?.accuracyText, "100%")
        XCTAssertEqual(otherGoalMetrics?.checkpointsCleared, 1)
    }

    @MainActor
    func testWeeklyCheckpointStreakUsesClearedCheckpointDays() {
        let store = CheckpointStore(defaults: defaults)
        let goal = makeGoal()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date()).addingTimeInterval(60)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let fourDaysAgo = calendar.date(byAdding: .day, value: -4, to: today) ?? today

        store.goal = goal
        store.goalProfiles = [goal]
        store.unlockEvents = [
            UnlockEvent(goalID: goal.id, minutes: 30, createdAt: yesterday),
            UnlockEvent(goalID: goal.id, minutes: 30, createdAt: twoDaysAgo),
            UnlockEvent(goalID: goal.id, minutes: 30, createdAt: fourDaysAgo)
        ]

        XCTAssertEqual(store.weeklyActiveGoalMetrics?.checkpointStreakDays, 2)
        XCTAssertEqual(store.weeklyActiveGoalMetrics?.checkpointStreakText, "2 days")

        store.unlockEvents = [
            UnlockEvent(goalID: goal.id, minutes: 30, createdAt: fourDaysAgo)
        ]

        XCTAssertEqual(store.weeklyActiveGoalMetrics?.checkpointStreakDays, 0)
    }

    @MainActor
    func testWeeklyImpactDetailsHighlightAttainableLearningValue() throws {
        let goal = makeGoal()
        let otherGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "integrals",
            preferredQuestionStyle: .multipleChoice
        )
        let calendar = Calendar.current
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: Date()))
        let firstPracticeDay = week.start.addingTimeInterval(60 * 60)
        let secondPracticeDay = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 1, to: firstPracticeDay)
        )
        let priorWeek = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -1, to: firstPracticeDay)
        )
        let recoveredFromLastWeekID = UUID()
        let recoveredWithinWeekID = UUID()

        let attempts = [
            makeAttempt(
                goal: goal,
                questionID: recoveredFromLastWeekID,
                result: .incorrect,
                createdAt: priorWeek
            ),
            makeAttempt(
                goal: goal,
                questionID: recoveredFromLastWeekID,
                result: .correct,
                createdAt: firstPracticeDay
            ),
            makeAttempt(
                goal: goal,
                questionID: recoveredWithinWeekID,
                result: .partial,
                createdAt: firstPracticeDay.addingTimeInterval(60)
            ),
            makeAttempt(
                goal: goal,
                questionID: recoveredWithinWeekID,
                result: .correct,
                createdAt: secondPracticeDay
            ),
            makeAttempt(
                goal: goal,
                result: .correct,
                createdAt: secondPracticeDay.addingTimeInterval(60)
            ),
            makeAttempt(
                goal: otherGoal,
                result: .correct,
                createdAt: firstPracticeDay
            )
        ]
        let unlockEvents = [
            UnlockEvent(goalID: goal.id, minutes: 30, createdAt: firstPracticeDay),
            UnlockEvent(goalID: goal.id, minutes: 15, createdAt: secondPracticeDay),
            UnlockEvent(goalID: otherGoal.id, minutes: 30, createdAt: firstPracticeDay)
        ]
        let details = WeeklyMetricsCalculator(
            attempts: attempts,
            unlockEvents: unlockEvents,
            competencies: []
        ).impactDetails(goalID: goal.id)

        XCTAssertEqual(details.practiceDays.count, 7)
        XCTAssertEqual(details.practiceDays.map(\.questionsAnswered).reduce(0, +), 4)
        XCTAssertEqual(details.activePracticeDays, 2)
        XCTAssertEqual(details.recoveredQuestions, 2)
        XCTAssertEqual(details.earnedBreakMinutes, 45)
        XCTAssertEqual(details.earnedBreakTimeText, "45m")
        XCTAssertEqual(details.previousWeekQuestions, 1)
        XCTAssertEqual(
            details.questionTrendText(currentQuestions: 4),
            "3 more questions than this point last week"
        )
    }

    @MainActor
    func testWeeklyImpactTrendComparesMatchingElapsedPeriods() throws {
        let goal = makeGoal()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 12))
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: now))
        let previousWeekStart = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -1, to: week.start)
        )
        let comparableAttempt = previousWeekStart.addingTimeInterval(60 * 60)
        let laterPriorWeekAttempt = previousWeekStart.addingTimeInterval(4 * 24 * 60 * 60)

        let details = WeeklyMetricsCalculator(
            attempts: [
                makeAttempt(goal: goal, result: .correct, createdAt: comparableAttempt),
                makeAttempt(goal: goal, result: .correct, createdAt: laterPriorWeekAttempt)
            ],
            unlockEvents: [],
            competencies: []
        ).impactDetails(goalID: goal.id, asOf: now, calendar: calendar)

        XCTAssertEqual(details.previousWeekQuestions, 1)
    }

    @MainActor
    func testRecoveredMissRequiresTheLatestAttemptToRemainCorrect() throws {
        let goal = makeGoal()
        let calendar = Calendar.current
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: Date()))
        let questionID = UUID()
        let initialMiss = week.start.addingTimeInterval(60)
        let recovery = initialMiss.addingTimeInterval(60)
        let laterMiss = recovery.addingTimeInterval(60)

        let details = WeeklyMetricsCalculator(
            attempts: [
                makeAttempt(goal: goal, questionID: questionID, result: .incorrect, createdAt: initialMiss),
                makeAttempt(goal: goal, questionID: questionID, result: .correct, createdAt: recovery),
                makeAttempt(goal: goal, questionID: questionID, result: .partial, createdAt: laterMiss)
            ],
            unlockEvents: [],
            competencies: []
        ).impactDetails(goalID: goal.id)

        XCTAssertEqual(details.recoveredQuestions, 0)
    }

    func testWeeklyImpactTimeFormattingRemainsCompact() {
        let base = WeeklyImpactDetails(
            practiceDays: [],
            earnedBreakMinutes: 60,
            recoveredQuestions: 0,
            activePracticeDays: 0,
            previousWeekQuestions: 0
        )

        XCTAssertEqual(base.earnedBreakTimeText, "1h")

        var mixed = base
        mixed.earnedBreakMinutes = 75
        XCTAssertEqual(mixed.earnedBreakTimeText, "1h 15m")
    }

    @MainActor
    func testWeeklySkillHighlightsRequireARealDifference() {
        let goal = makeGoal()
        var first = TopicCompetency.initial(topic: "Positioning", goalID: goal.id)
        first.attempts = 4
        first.correct = 2
        first.incorrect = 2

        let singleSkill = WeeklyMetricsCalculator(
            attempts: [],
            unlockEvents: [],
            competencies: [first]
        ).summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true
        )

        XCTAssertNil(singleSkill.strongestSkill)
        XCTAssertNil(singleSkill.reviewSkill)

        var tied = TopicCompetency.initial(topic: "Research", goalID: goal.id)
        tied.attempts = first.attempts
        tied.correct = first.correct
        tied.incorrect = first.incorrect

        let tiedSkills = WeeklyMetricsCalculator(
            attempts: [],
            unlockEvents: [],
            competencies: [first, tied]
        ).summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true
        )

        XCTAssertNil(tiedSkills.strongestSkill)
        XCTAssertNil(tiedSkills.reviewSkill)
    }

    @MainActor
    func testCompoundQuestionTopicUpdatesCanonicalSkills() {
        let store = CheckpointStore(defaults: defaults)
        let goal = Goal(
            title: "Pass operating systems exam",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "interrupts, system calls",
            preferredQuestionStyle: .multipleChoice
        )
        let question = makeQuestion(
            goal: goal,
            index: 1,
            topic: "interrupts, system calls",
            difficulty: 3
        )
        store.goal = goal
        store.questions = [question]

        store.submitAnswer(
            question: question,
            answer: question.expectedAnswer,
            result: .correct,
            grantsUnlock: false
        )

        let topics = store.sortedCompetencies.map(\.topic)
        XCTAssertEqual(topics, ["interrupts", "system calls"])
        XCTAssertTrue(store.sortedCompetencies.allSatisfy { $0.attempts == 1 })
        XCTAssertTrue(store.sortedCompetencies.allSatisfy { $0.masteryPercent < 100 })
    }

    @MainActor
    func testIssueReportsPersistAndRejectBlankMessages() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal

        XCTAssertFalse(store.submitIssueReport(category: .generalFeedback, message: "   ", contact: ""))
        XCTAssertEqual(store.issueReportCount, 0)

        XCTAssertTrue(
            store.submitIssueReport(
                category: .appBlocking,
                message: "  The shield did not appear after I opened a blocked app.  ",
                contact: "sam@example.com "
            )
        )
        XCTAssertEqual(store.issueReportCount, 1)

        let report = try XCTUnwrap(store.issueReports.first)
        XCTAssertEqual(report.category, .appBlocking)
        XCTAssertEqual(report.message, "The shield did not appear after I opened a blocked app.")
        XCTAssertEqual(report.contact, "sam@example.com")
        XCTAssertEqual(report.goalID, goal.id)
        XCTAssertEqual(report.goalTitle, goal.title)

        let reloadedStore = CheckpointStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.issueReports, store.issueReports)
    }

}
