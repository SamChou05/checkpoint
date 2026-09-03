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

    func testCompetencyProgressBandKeepsSparseEvidenceInCalibration() {
        var competency = TopicCompetency.initial(topic: "Concurrency", estimatedLevel: 5)

        XCTAssertEqual(CompetencyProgressBand.resolve(for: competency), .notStarted)

        competency.attempts = 1
        competency.correct = 1
        XCTAssertEqual(CompetencyProgressBand.resolve(for: competency), .calibrating)

        competency.attempts = 9
        competency.correct = 9
        XCTAssertEqual(CompetencyProgressBand.resolve(for: competency), .calibrating)

        competency.attempts = 10
        competency.correct = 10
        XCTAssertEqual(CompetencyProgressBand.resolve(for: competency), .strong)
    }

    func testCompetencyProgressBandUsesMasteryAfterCalibration() {
        var needsPractice = TopicCompetency.initial(topic: "Recursion", estimatedLevel: 1)
        needsPractice.attempts = 10
        needsPractice.incorrect = 10
        XCTAssertEqual(CompetencyProgressBand.resolve(for: needsPractice), .needsPractice)

        var building = TopicCompetency.initial(topic: "Graphs", estimatedLevel: 1)
        building.attempts = 10
        building.correct = 6
        building.incorrect = 4
        XCTAssertEqual(CompetencyProgressBand.resolve(for: building), .building)

        var strong = TopicCompetency.initial(topic: "Arrays", estimatedLevel: 2)
        strong.attempts = 10
        strong.correct = 10
        XCTAssertEqual(CompetencyProgressBand.resolve(for: strong), .strong)
    }

    func testProgressDashboardSummaryCountsOnlyMappedRows() {
        let lastPracticedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let notStarted = TopicCompetency.initial(topic: "Arrays")

        var calibrating = TopicCompetency.initial(topic: "Graphs")
        calibrating.attempts = 2
        calibrating.correct = 2

        var strong = TopicCompetency.initial(topic: "Hash maps", estimatedLevel: 2)
        strong.attempts = 10
        strong.correct = 10

        let summary = ProgressDashboardSummary(
            competencies: [notStarted, calibrating, strong],
            attemptDates: [lastPracticedAt]
        )

        XCTAssertEqual(summary.totalSkillCount, 3)
        XCTAssertEqual(summary.practicedSkillCount, 2)
        XCTAssertEqual(summary.strongSkillCount, 1)
        XCTAssertEqual(summary.calibratingSkillCount, 1)
        XCTAssertEqual(summary.lastPracticedAt, lastPracticedAt)
        XCTAssertEqual(summary.coverageProgress, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertFalse(summary.allSkillsAreStrong)
    }

    @MainActor
    func testProgressSkillRowsPreserveMapOrderAndFillMissingSkills() {
        let goalID = UUID()
        let first = SkillMapTopic(name: "Hash maps")
        let second = SkillMapTopic(name: "Arrays")
        let third = SkillMapTopic(name: "Graphs")
        let skillMap = GoalSkillMap(
            topics: [first, second, third],
            status: .reviewed
        )

        var graphProgress = TopicCompetency.initial(
            topic: "Graph traversal",
            goalID: goalID,
            skillID: third.id
        )
        graphProgress.attempts = 4
        var hashProgress = TopicCompetency.initial(
            topic: "Hash tables",
            goalID: goalID,
            skillID: first.id
        )
        hashProgress.attempts = 2

        let rows = SkillMapReconciler.orderedCompetencies(
            for: skillMap,
            from: [graphProgress, hashProgress],
            goalID: goalID
        )

        XCTAssertEqual(rows.map(\.topic), ["Hash maps", "Arrays", "Graphs"])
        XCTAssertEqual(rows.map(\.skillID), [first.id, second.id, third.id])
        XCTAssertEqual(rows.map(\.attempts), [2, 0, 4])
        XCTAssertTrue(rows.allSatisfy { $0.goalID == goalID })
    }

    @MainActor
    func testProgressSkillRowsDoNotDuplicateExplicitSkillEvidenceFromCompoundLegacyTopic() {
        let goalID = UUID()
        let arrays = SkillMapTopic(name: "Arrays")
        let linkedLists = SkillMapTopic(name: "Linked lists")
        let skillMap = GoalSkillMap(
            topics: [arrays, linkedLists],
            status: .reviewed
        )
        var legacy = TopicCompetency.initial(
            topic: "Arrays, linked lists",
            goalID: goalID,
            skillID: arrays.id
        )
        legacy.attempts = 3
        legacy.correct = 2
        legacy.incorrect = 1

        let displayCompetencies = SkillMapReconciler.mergedCompetenciesForDisplay([legacy])
        let rows = SkillMapReconciler.orderedCompetencies(
            for: skillMap,
            from: [legacy],
            goalID: goalID
        )

        XCTAssertEqual(displayCompetencies.count, 1)
        XCTAssertEqual(rows.map(\.attempts), [3, 0])
        XCTAssertEqual(rows.map(\.correct), [2, 0])
        XCTAssertEqual(rows.map(\.incorrect), [1, 0])
    }

    @MainActor
    func testCompetencyDisplayMergesRenamedRowsByStableSkillIdentity() throws {
        let goalID = UUID()
        let skillID = UUID()
        var legacyName = TopicCompetency.initial(
            topic: "Array basics",
            goalID: goalID,
            skillID: skillID
        )
        legacyName.attempts = 2
        legacyName.correct = 1
        legacyName.incorrect = 1

        var currentName = TopicCompetency.initial(
            topic: "Array mechanics",
            goalID: goalID,
            skillID: skillID
        )
        currentName.attempts = 3
        currentName.correct = 2
        currentName.partial = 1

        let displayCompetencies = SkillMapReconciler.mergedCompetenciesForDisplay([
            legacyName,
            currentName
        ])
        let merged = try XCTUnwrap(displayCompetencies.first)

        XCTAssertEqual(displayCompetencies.count, 1)
        XCTAssertEqual(merged.skillID, skillID)
        XCTAssertEqual(merged.attempts, 5)
        XCTAssertEqual(merged.correct, 3)
        XCTAssertEqual(merged.partial, 1)
        XCTAssertEqual(merged.incorrect, 1)
    }

    @MainActor
    func testCompetencyDisplayKeepsSameNamedDistinctSkillsSeparate() {
        let goalID = UUID()
        var first = TopicCompetency.initial(
            topic: "Model evaluation",
            goalID: goalID,
            skillID: UUID()
        )
        first.attempts = 2
        var second = TopicCompetency.initial(
            topic: "Model evaluation",
            goalID: goalID,
            skillID: UUID()
        )
        second.attempts = 5

        let merged = SkillMapReconciler.mergedCompetenciesForDisplay([first, second])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.compactMap(\.skillID)).count, 2)
        XCTAssertEqual(Set(merged.map(\.attempts)), [2, 5])
    }

    func testProgressDashboardSummaryRecognizesAllStrongSkills() {
        var first = TopicCompetency.initial(topic: "Arrays", estimatedLevel: 2)
        first.attempts = 10
        first.correct = 10

        var second = TopicCompetency.initial(topic: "Graphs", estimatedLevel: 2)
        second.attempts = 10
        second.correct = 10

        let summary = ProgressDashboardSummary(
            competencies: [first, second]
        )

        XCTAssertTrue(summary.allSkillsAreStrong)
        XCTAssertEqual(summary.strongSkillCount, 2)
        XCTAssertEqual(summary.calibratingSkillCount, 0)
    }

    func testProgressDashboardSummaryMergesAttemptAndCompetencyRecency() {
        let olderAttempt = Date(timeIntervalSince1970: 1_700_000_000)
        let newerCompetencyPractice = olderAttempt.addingTimeInterval(3_600)
        var competency = TopicCompetency.initial(topic: "Arrays")
        competency.attempts = 2
        competency.lastPracticedAt = newerCompetencyPractice

        let summary = ProgressDashboardSummary(
            competencies: [competency],
            attemptDates: [olderAttempt]
        )

        XCTAssertEqual(summary.lastPracticedAt, newerCompetencyPractice)
    }

    func testProgressDashboardPresentationHandlesIncompleteAndUndatedHistory() {
        var established = TopicCompetency.initial(topic: "Arrays")
        established.attempts = 10
        established.correct = 6
        let untouched = TopicCompetency.initial(topic: "Graphs")
        let summary = ProgressDashboardSummary(competencies: [established, untouched])
        let narrative = ProgressDashboardNarrative(summary: summary)

        XCTAssertEqual(summary.unpracticedSkillCount, 1)
        XCTAssertEqual(narrative.title, "1 skill still needs a first signal")
        XCTAssertEqual(narrative.detail, "Practice it once to complete your skill coverage.")
        XCTAssertEqual(summary.lastPracticedValue(), "Earlier")
    }

    func testCompetencyRecencyLabelDistinguishesUntouchedAndUndatedHistory() {
        XCTAssertEqual(
            CompetencyRecencyLabel.text(attempts: 0, lastPracticedAt: nil),
            "Not practiced yet"
        )
        XCTAssertEqual(
            CompetencyRecencyLabel.text(attempts: 2, lastPracticedAt: nil),
            "Practiced previously"
        )
    }

    @MainActor
    func testProgressPreparationAndFailureRemainBlockingAfterSkillMapPersists() {
        var goal = makeGoal()
        goal.derivedSkillMap = GoalSkillMap(
            topics: [SkillMapTopic(name: "Arrays")],
            status: .suggested
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]

        store.questionBatchState = .generating
        XCTAssertTrue(store.isPreparingActiveGoalQuestions)
        XCTAssertFalse(store.isQuestionGenerationBlockingPractice)

        store.questionBatchState = .failed
        XCTAssertFalse(store.isPreparingActiveGoalQuestions)
        XCTAssertTrue(store.isQuestionGenerationBlockingPractice)
    }

    func testStudyFocusRecommendationExplainsEachReviewState() throws {
        let goalID = UUID()
        var question = CheckpointQuestion(
            goalID: goalID,
            prompt: "Explain recursion.",
            expectedAnswer: "A function calls itself.",
            explanation: "Recursive calls reduce a problem.",
            topic: "Recursion",
            difficulty: 2,
            format: .shortAnswer,
            status: .incorrect,
            sourcePrompt: "Recursion"
        )

        let missed = try XCTUnwrap(
            StudyFocusRecommendation(
                question: question,
                skillID: nil,
                skillName: "Recursion",
                hasPracticeHistory: true
            )
        )
        XCTAssertEqual(missed.title, "Recursion")
        XCTAssertEqual(missed.detail, "A missed question is ready in your review plan.")

        question.status = .due
        let partial = try XCTUnwrap(
            StudyFocusRecommendation(
                question: question,
                skillID: nil,
                skillName: "Recursion",
                hasPracticeHistory: true
            )
        )
        XCTAssertEqual(partial.title, "Recursion")
        XCTAssertEqual(partial.detail, "A partial answer is ready in your review plan.")

        question.status = .skipped
        let skipped = try XCTUnwrap(
            StudyFocusRecommendation(
                question: question,
                skillID: nil,
                skillName: "Recursion",
                hasPracticeHistory: true
            )
        )
        XCTAssertEqual(skipped.title, "Recursion")

        question.status = .correct
        let maintenance = try XCTUnwrap(
            StudyFocusRecommendation(
                question: question,
                skillID: nil,
                skillName: "Recursion",
                hasPracticeHistory: true
            )
        )
        XCTAssertEqual(maintenance.title, "Recursion")

        question.status = .retired
        XCTAssertNil(
            StudyFocusRecommendation(
                question: question,
                skillID: nil,
                skillName: "Recursion",
                hasPracticeHistory: true
            )
        )
    }

    func testStudyFocusRecommendationDistinguishesNewSkillSignalState() throws {
        let goalID = UUID()
        let question = CheckpointQuestion(
            goalID: goalID,
            prompt: "Explain recursion.",
            expectedAnswer: "A function calls itself.",
            explanation: "Recursive calls reduce a problem.",
            topic: "Recursion",
            difficulty: 2,
            format: .shortAnswer,
            status: .new,
            sourcePrompt: "Recursion"
        )

        let firstSignal = try XCTUnwrap(
            StudyFocusRecommendation(
                question: question,
                skillID: nil,
                skillName: "Recursion",
                hasPracticeHistory: false
            )
        )
        let established = try XCTUnwrap(
            StudyFocusRecommendation(
                question: question,
                skillID: nil,
                skillName: "Recursion",
                hasPracticeHistory: true
            )
        )

        XCTAssertEqual(firstSignal.title, "Recursion")
        XCTAssertTrue(firstSignal.detail.contains("first signal"))
        XCTAssertEqual(established.title, "Recursion")
        XCTAssertTrue(established.detail.contains("sharpen"))
    }

    func testStudyFocusRecommendationDistinguishesReadyAndScheduledReview() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var question = CheckpointQuestion(
            goalID: UUID(),
            prompt: "Explain recursion.",
            expectedAnswer: "A function calls itself.",
            explanation: "Recursive calls reduce a problem.",
            topic: "Recursion",
            difficulty: 2,
            format: .shortAnswer,
            status: .incorrect,
            nextReviewAt: now.addingTimeInterval(-60),
            sourcePrompt: "Recursion"
        )

        let ready = try XCTUnwrap(
            StudyFocusRecommendation(
                question: question,
                skillID: nil,
                skillName: "Recursion",
                hasPracticeHistory: true,
                now: now
            )
        )

        question.nextReviewAt = now.addingTimeInterval(60)
        let scheduled = try XCTUnwrap(
            StudyFocusRecommendation(
                question: question,
                skillID: nil,
                skillName: "Recursion",
                hasPracticeHistory: true,
                now: now
            )
        )

        XCTAssertTrue(ready.detail.contains("ready"))
        XCTAssertFalse(ready.detail.contains("scheduled"))
        XCTAssertTrue(scheduled.detail.contains("scheduled"))
        XCTAssertFalse(scheduled.detail.contains("ready"))
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
