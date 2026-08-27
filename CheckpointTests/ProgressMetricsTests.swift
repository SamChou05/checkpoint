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
