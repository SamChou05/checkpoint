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
    func testWeeklyMetricsRespectAnInjectedClockAndCalendar() throws {
        let store = CheckpointStore(defaults: defaults)
        let goal = makeGoal()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let asOf = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2024, month: 2, day: 14, hour: 12))
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: asOf))

        store.goal = goal
        store.goalProfiles = [goal]
        store.attempts = [
            makeAttempt(
                goal: goal,
                result: .correct,
                createdAt: week.start.addingTimeInterval(60 * 60)
            )
        ]

        XCTAssertEqual(
            store.weeklyTotalMetrics(asOf: asOf, calendar: calendar).questionsAnswered,
            1
        )
        XCTAssertEqual(
            store.weeklyActiveGoalMetrics(asOf: asOf, calendar: calendar)?.questionsAnswered,
            1
        )
        XCTAssertEqual(
            store.weeklyGoalMetrics(asOf: asOf, calendar: calendar).first?.questionsAnswered,
            1
        )
    }

    @MainActor
    func testWeeklyMetricsExcludeRecordsAfterTheInjectedClock() throws {
        let goal = makeGoal()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let asOf = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: asOf))
        let currentDate = asOf.addingTimeInterval(-3_600)
        let futureDate = asOf.addingTimeInterval(3_600)
        let sharedQuestionID = UUID()
        let calculator = WeeklyMetricsCalculator(
            attempts: [
                makeAttempt(goal: goal, result: .correct, createdAt: currentDate),
                makeAttempt(
                    goal: goal,
                    questionID: sharedQuestionID,
                    result: .incorrect,
                    createdAt: week.start.addingTimeInterval(-3_600)
                ),
                makeAttempt(
                    goal: goal,
                    questionID: sharedQuestionID,
                    result: .correct,
                    createdAt: futureDate
                )
            ],
            unlockEvents: [
                UnlockEvent(goalID: goal.id, minutes: 15, createdAt: currentDate),
                UnlockEvent(goalID: goal.id, minutes: 30, createdAt: futureDate)
            ],
            asOf: asOf,
            calendar: calendar
        )

        let summary = calculator.summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true,
            skillCompetencies: []
        )
        let details = calculator.impactDetails(goalID: goal.id)

        XCTAssertEqual(summary.questionsAnswered, 1)
        XCTAssertEqual(summary.correctAnswers, 1)
        XCTAssertEqual(summary.checkpointsCleared, 1)
        XCTAssertEqual(summary.checkpointStreakDays, 1)
        XCTAssertEqual(details.earnedBreakMinutes, 15)
        XCTAssertEqual(details.activePracticeDays, 1)
        XCTAssertEqual(details.recoveredQuestions, 0)
    }

    func testWeeklyDateLabelsUseTheInjectedTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let monday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))
        )
        let formatter = WeeklyReviewDateLabelFormatter(
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertEqual(formatter.narrowWeekday(for: monday), "M")
        XCTAssertEqual(formatter.wideWeekday(for: monday), "Monday")
        XCTAssertEqual(formatter.detailDate(for: monday), "Monday, Aug 31")
        XCTAssertEqual(formatter.uppercaseDetailDate(for: monday), "MONDAY, AUG 31")

        let october = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))
        )
        let turkishFormatter = WeeklyReviewDateLabelFormatter(
            calendar: calendar,
            locale: Locale(identifier: "tr_TR"),
            timeZone: calendar.timeZone
        )
        XCTAssertEqual(
            turkishFormatter.uppercaseDetailDate(for: october),
            "6 EKİ SALI"
        )
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
            unlockEvents: unlockEvents
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
        let exactComparableAttempt = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -1, to: now)
        )
        let laterPriorWeekAttempt = previousWeekStart.addingTimeInterval(4 * 24 * 60 * 60)

        let details = WeeklyMetricsCalculator(
            attempts: [
                makeAttempt(goal: goal, result: .correct, createdAt: comparableAttempt),
                makeAttempt(goal: goal, result: .correct, createdAt: exactComparableAttempt),
                makeAttempt(goal: goal, result: .correct, createdAt: laterPriorWeekAttempt)
            ],
            unlockEvents: []
        ).impactDetails(goalID: goal.id, asOf: now, calendar: calendar)

        XCTAssertEqual(
            details.previousWeekQuestions,
            2,
            "The matching local cutoff should be inclusive while later prior-week activity stays out."
        )
    }

    @MainActor
    func testArchivedWeeklyImpactTrendIncludesTheFullSundayAcrossDST() throws {
        let goal = makeGoal()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let archivedWeekReference = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 12))
        )
        let archivedWeek = try XCTUnwrap(
            calendar.dateInterval(of: .weekOfYear, for: archivedWeekReference)
        )
        let priorWeekStart = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -1, to: archivedWeek.start)
        )
        let priorSunday = try XCTUnwrap(
            calendar.date(
                bySettingHour: 23,
                minute: 30,
                second: 0,
                of: try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: priorWeekStart))
            )
        )
        let archivedSunday = try XCTUnwrap(
            calendar.date(
                bySettingHour: 23,
                minute: 30,
                second: 0,
                of: try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: archivedWeek.start))
            )
        )
        let effectiveAsOf = try XCTUnwrap(
            calendar.date(byAdding: .second, value: -1, to: archivedWeek.end)
        )

        let details = WeeklyMetricsCalculator(
            attempts: [
                makeAttempt(goal: goal, result: .correct, createdAt: priorSunday),
                makeAttempt(goal: goal, result: .correct, createdAt: archivedSunday),
                makeAttempt(goal: goal, result: .correct, createdAt: archivedWeek.end)
            ],
            unlockEvents: [],
            asOf: effectiveAsOf,
            calendar: calendar
        ).impactDetails(goalID: goal.id)

        XCTAssertEqual(
            details.previousWeekQuestions,
            1,
            "A completed spring-forward week should compare against the prior week's full Sunday."
        )
        XCTAssertEqual(details.practiceDays.last?.questionsAnswered, 1)
        XCTAssertEqual(details.practiceDays.reduce(0) { $0 + $1.questionsAnswered }, 1)
        XCTAssertEqual(
            details.questionTrendText(currentQuestions: 1, isCurrentWeek: false),
            "Level with the week before"
        )
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
            unlockEvents: []
        ).impactDetails(goalID: goal.id)

        XCTAssertEqual(details.recoveredQuestions, 0)
    }

    @MainActor
    func testAllGoalsRecoveryKeepsQuestionIdentityScopedToItsGoal() throws {
        let firstGoal = makeGoal()
        let secondGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(86_400 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "integrals",
            preferredQuestionStyle: .multipleChoice
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: now))
        let sharedQuestionID = UUID()
        let miss = week.start.addingTimeInterval(60 * 60)
        let unrelatedCorrectAnswer = miss.addingTimeInterval(60)

        let details = WeeklyMetricsCalculator(
            attempts: [
                makeAttempt(
                    goal: firstGoal,
                    questionID: sharedQuestionID,
                    result: .incorrect,
                    createdAt: miss
                ),
                makeAttempt(
                    goal: secondGoal,
                    questionID: sharedQuestionID,
                    result: .correct,
                    createdAt: unrelatedCorrectAnswer
                )
            ],
            unlockEvents: [],
            asOf: now,
            calendar: calendar
        ).impactDetails(goalID: nil)

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
    func testWeeklyImpactBucketsDailyAccuracyAndUnlockedTimeWithinScope() throws {
        let goal = makeGoal()
        let otherGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(86_400 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "integrals",
            preferredQuestionStyle: .multipleChoice
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let asOf = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: asOf))
        let monday = week.start.addingTimeInterval(9 * 60 * 60)
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        let afterAsOf = asOf.addingTimeInterval(60 * 60)
        let calculator = WeeklyMetricsCalculator(
            attempts: [
                makeAttempt(goal: goal, result: .correct, createdAt: monday),
                makeAttempt(goal: goal, result: .incorrect, createdAt: monday.addingTimeInterval(60)),
                makeAttempt(goal: goal, result: .partial, createdAt: monday.addingTimeInterval(120)),
                makeAttempt(goal: goal, result: .correct, createdAt: tuesday),
                makeAttempt(goal: otherGoal, result: .correct, createdAt: monday),
                makeAttempt(goal: goal, result: .correct, createdAt: afterAsOf)
            ],
            unlockEvents: [
                UnlockEvent(goalID: goal.id, minutes: 15, createdAt: monday),
                UnlockEvent(goalID: goal.id, minutes: 30, createdAt: monday.addingTimeInterval(60)),
                UnlockEvent(goalID: goal.id, minutes: 20, createdAt: tuesday),
                UnlockEvent(goalID: otherGoal.id, minutes: 60, createdAt: monday),
                UnlockEvent(goalID: goal.id, minutes: 30, createdAt: afterAsOf)
            ],
            asOf: asOf,
            calendar: calendar
        )

        let scopedDetails = calculator.impactDetails(goalID: goal.id)
        let scopedMonday = try XCTUnwrap(
            scopedDetails.practiceDays.first {
                calendar.isDate($0.date, inSameDayAs: monday)
            }
        )
        let scopedTuesday = try XCTUnwrap(
            scopedDetails.practiceDays.first {
                calendar.isDate($0.date, inSameDayAs: tuesday)
            }
        )

        XCTAssertEqual(scopedMonday.questionsAnswered, 3)
        XCTAssertEqual(scopedMonday.correctAnswers, 1)
        XCTAssertEqual(scopedMonday.accuracyPercent, 33)
        XCTAssertEqual(scopedMonday.checkpointsCleared, 2)
        XCTAssertEqual(scopedMonday.earnedBreakMinutes, 45)
        XCTAssertEqual(scopedMonday.earnedBreakTimeText, "45m")
        XCTAssertTrue(scopedMonday.hasActivity)
        XCTAssertEqual(scopedTuesday.questionsAnswered, 1)
        XCTAssertEqual(scopedTuesday.correctAnswers, 1)
        XCTAssertEqual(scopedTuesday.checkpointsCleared, 1)
        XCTAssertEqual(scopedTuesday.earnedBreakMinutes, 20)
        XCTAssertEqual(scopedDetails.earnedBreakMinutes, 65)
        XCTAssertEqual(scopedDetails.practiceDays.map(\.questionsAnswered).reduce(0, +), 4)
        XCTAssertEqual(scopedDetails.practiceDays.map(\.checkpointsCleared).reduce(0, +), 3)

        let allGoalsDetails = calculator.impactDetails(goalID: nil)
        let allGoalsMonday = try XCTUnwrap(
            allGoalsDetails.practiceDays.first {
                calendar.isDate($0.date, inSameDayAs: monday)
            }
        )
        XCTAssertEqual(allGoalsMonday.questionsAnswered, 4)
        XCTAssertEqual(allGoalsMonday.correctAnswers, 2)
        XCTAssertEqual(allGoalsMonday.accuracyPercent, 50)
        XCTAssertEqual(allGoalsMonday.checkpointsCleared, 3)
        XCTAssertEqual(allGoalsMonday.earnedBreakMinutes, 105)
        XCTAssertEqual(allGoalsDetails.earnedBreakMinutes, 125)
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
            unlockEvents: []
        ).summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true,
            skillCompetencies: [first]
        )

        XCTAssertNil(singleSkill.strongestSkill)
        XCTAssertNil(singleSkill.reviewSkill)
        XCTAssertTrue(singleSkill.skillSnapshotSignals.isEmpty)
        XCTAssertNil(singleSkill.weeklySignalInsight)

        var tied = TopicCompetency.initial(topic: "Research", goalID: goal.id)
        tied.attempts = first.attempts
        tied.correct = first.correct
        tied.incorrect = first.incorrect

        let tiedSkills = WeeklyMetricsCalculator(
            attempts: [],
            unlockEvents: []
        ).summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true,
            skillCompetencies: [first, tied]
        )

        XCTAssertNil(tiedSkills.strongestSkill)
        XCTAssertNil(tiedSkills.reviewSkill)
        XCTAssertTrue(tiedSkills.skillSnapshotSignals.isEmpty)
    }

    @MainActor
    func testWeeklySkillSnapshotDescribesCurrentRangeWithoutInventingARecommendation() {
        let goal = makeGoal()
        var lowest = TopicCompetency.initial(topic: "Positioning", goalID: goal.id)
        lowest.attempts = 4
        lowest.correct = 1
        lowest.incorrect = 3

        var highest = TopicCompetency.initial(topic: "Research synthesis", goalID: goal.id)
        highest.attempts = 4
        highest.correct = 4

        let missedWeek = WeeklyMetricsCalculator(
            attempts: [makeAttempt(goal: goal, result: .incorrect, createdAt: Date())],
            unlockEvents: []
        ).summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true,
            skillCompetencies: [highest, lowest]
        )

        XCTAssertEqual(
            missedWeek.skillSnapshotSignals,
            [
                .lowestCurrentEstimate("Positioning"),
                .highestCurrentEstimate("Research synthesis")
            ]
        )
        XCTAssertEqual(
            missedWeek.weeklySignalInsight,
            .lowestCurrentEstimate("Positioning")
        )
        XCTAssertEqual(
            missedWeek.weeklySignalInsight?.text,
            "Lowest current estimate: Positioning."
        )
        XCTAssertFalse(missedWeek.weeklySignalInsight?.text.localizedCaseInsensitiveContains("review next") == true)

        let correctWeek = WeeklyMetricsCalculator(
            attempts: [makeAttempt(goal: goal, result: .correct, createdAt: Date())],
            unlockEvents: []
        ).summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true,
            skillCompetencies: [highest, lowest]
        )

        XCTAssertEqual(
            correctWeek.weeklySignalInsight,
            .highestCurrentEstimate("Research synthesis")
        )
        XCTAssertEqual(
            correctWeek.weeklySignalInsight?.accessibilityLabel,
            "Highest current mastery estimate, Research synthesis"
        )
    }

    @MainActor
    func testWeeklySkillSnapshotRemainsScopedToTheSelectedGoal() {
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
        var currentLow = TopicCompetency.initial(topic: "Positioning", goalID: goal.id)
        currentLow.attempts = 4
        currentLow.correct = 1
        currentLow.incorrect = 3
        var currentHigh = TopicCompetency.initial(topic: "Research", goalID: goal.id)
        currentHigh.attempts = 4
        currentHigh.correct = 4
        var otherLow = TopicCompetency.initial(topic: "Derivatives", goalID: otherGoal.id)
        otherLow.attempts = 4
        otherLow.correct = 1
        otherLow.incorrect = 3
        var otherHigh = TopicCompetency.initial(topic: "Integrals", goalID: otherGoal.id)
        otherHigh.attempts = 4
        otherHigh.correct = 4

        store.goal = goal
        store.goalProfiles = [goal, otherGoal]
        store.competencies = [otherHigh, currentHigh, otherLow, currentLow]

        let metrics = store.weeklyGoalMetrics.first { $0.id == goal.id.uuidString }
        let otherMetrics = store.weeklyGoalMetrics.first { $0.id == otherGoal.id.uuidString }

        XCTAssertEqual(
            metrics?.skillSnapshotSignals,
            [
                .lowestCurrentEstimate("Positioning"),
                .highestCurrentEstimate("Research")
            ]
        )
        XCTAssertEqual(
            otherMetrics?.skillSnapshotSignals,
            [
                .lowestCurrentEstimate("Derivatives"),
                .highestCurrentEstimate("Integrals")
            ]
        )
        XCTAssertTrue(
            store.weeklyTotalMetrics.skillSnapshotSignals.isEmpty,
            "All-goals summaries must not rank unrelated goal skill maps against each other."
        )
    }

    @MainActor
    func testWeeklyGoalPulseRetainsIdentityAndIncludesQuietGoals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US")
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))
        )
        let sharedDeadline = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 30, to: now)
        )
        let firstGoal = Goal(
            title: "Finish the launch review",
            deadline: sharedDeadline,
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "positioning",
            preferredQuestionStyle: .reflection,
            createdAt: now.addingTimeInterval(-200)
        )
        let currentGoal = Goal(
            title: "Finish the launch review",
            deadline: sharedDeadline,
            category: .custom,
            currentLevel: "Advanced",
            focusAreas: "evidence",
            preferredQuestionStyle: .shortAnswer,
            createdAt: now.addingTimeInterval(-100)
        )
        let quietGoal = Goal(
            title: "Build conversational Spanish",
            deadline: try XCTUnwrap(calendar.date(byAdding: .day, value: 90, to: now)),
            category: .languageLearning,
            currentLevel: "Beginner",
            focusAreas: "speaking",
            preferredQuestionStyle: .shortAnswer,
            createdAt: now
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: now))
        let firstDate = week.start.addingTimeInterval(60 * 60)
        let currentDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 1, to: firstDate)
        )
        let attempts = [
            makeAttempt(goal: firstGoal, result: .correct, createdAt: firstDate),
            makeAttempt(goal: firstGoal, result: .incorrect, createdAt: firstDate),
            makeAttempt(goal: currentGoal, result: .correct, createdAt: currentDate)
        ]
        let unlockEvents = [
            UnlockEvent(goalID: firstGoal.id, minutes: 30, createdAt: firstDate),
            UnlockEvent(goalID: currentGoal.id, minutes: 15, createdAt: currentDate)
        ]
        let calculator = WeeklyMetricsCalculator(
            attempts: attempts,
            unlockEvents: unlockEvents,
            asOf: now,
            calendar: calendar
        )
        let goals = [firstGoal, currentGoal, quietGoal]
        let metrics = goals.map { goal in
            calculator.summary(
                id: goal.id.uuidString,
                title: goal.title,
                goalID: goal.id,
                isCurrentGoal: goal.id == currentGoal.id,
                skillCompetencies: []
            )
        }

        let presentation = WeeklyGoalPulsePresentation(
            goals: goals,
            metrics: metrics,
            attempts: attempts,
            unlockEvents: unlockEvents,
            activeGoalID: currentGoal.id,
            asOf: now,
            calendar: calendar,
            locale: locale,
            timeZone: calendar.timeZone
        )

        XCTAssertEqual(presentation.items.map(\.id), [currentGoal.id, firstGoal.id, quietGoal.id])
        XCTAssertEqual(Set(presentation.items.map(\.title)).count, 3)
        XCTAssertTrue(presentation.items[0].title.contains("profile 2"))
        XCTAssertTrue(presentation.items[1].title.contains("profile 1"))
        XCTAssertTrue(presentation.items[0].isCurrentGoal)
        XCTAssertEqual(presentation.items[0].questionShare, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(presentation.items[1].questionShare, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(presentation.items[2].questionShare, 0, accuracy: 0.001)
        XCTAssertEqual(presentation.items[2].activityText, "No checkpoint activity this week")
        XCTAssertEqual(presentation.items[2].supportingText, "Ready for your next checkpoint")
        XCTAssertTrue(presentation.items[0].accessibilityLabel.contains("current goal"))
        XCTAssertEqual(
            presentation.items.map(\.questionShare).reduce(0, +),
            1,
            accuracy: 0.001
        )
    }

    func testWeeklyReviewSelectionFeedbackOnlyReportsAnActualScopeChange() {
        XCTAssertFalse(
            WeeklyReviewScopeInteractionPolicy.reportsSelectionFeedback(
                selectedMetricsID: WeeklyMetricsSummary.allGoalsID,
                currentMetricsID: WeeklyMetricsSummary.allGoalsID
            )
        )
        XCTAssertTrue(
            WeeklyReviewScopeInteractionPolicy.reportsSelectionFeedback(
                selectedMetricsID: UUID().uuidString,
                currentMetricsID: WeeklyMetricsSummary.allGoalsID
            )
        )
    }

    @MainActor
    func testWeeklyReviewPeriodPolicyNormalizesAndClampsArchiveBounds() throws {
        let goal = makeGoal()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))
        )
        let currentWeek = try XCTUnwrap(
            calendar.dateInterval(of: .weekOfYear, for: referenceDate)
        )
        let earliestWeekStart = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -4, to: currentWeek.start)
        )
        let earliestSunday = try XCTUnwrap(
            calendar.date(
                bySettingHour: 20,
                minute: 0,
                second: 0,
                of: try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: earliestWeekStart))
            )
        )
        let selectedWeekStart = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -2, to: currentWeek.start)
        )
        let selectedWednesday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 2, to: selectedWeekStart)
        )
        let futureRecordDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 2, to: currentWeek.end)
        )

        let policy = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: selectedWednesday,
            attempts: [
                makeAttempt(goal: goal, result: .correct, createdAt: futureRecordDate)
            ],
            unlockEvents: [
                UnlockEvent(goalID: goal.id, minutes: 20, createdAt: earliestSunday),
                UnlockEvent(goalID: goal.id, minutes: 30, createdAt: futureRecordDate)
            ],
            calendar: calendar,
            reduceMotion: false
        )

        XCTAssertEqual(policy.currentWeekStart, currentWeek.start)
        XCTAssertEqual(policy.earliestWeekStart, earliestWeekStart)
        XCTAssertEqual(policy.selectedWeekStart, selectedWeekStart)
        XCTAssertFalse(policy.isCurrentWeek)
        XCTAssertTrue(policy.canGoPrevious)
        XCTAssertTrue(policy.canGoNext)
        XCTAssertEqual(policy.motionStyle, .directional)

        let beforeHistory = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -8, to: currentWeek.start)
        )
        let clampedToHistory = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: beforeHistory,
            attempts: [],
            unlockEvents: [
                UnlockEvent(goalID: goal.id, minutes: 20, createdAt: earliestSunday)
            ],
            calendar: calendar,
            reduceMotion: false
        )
        XCTAssertEqual(clampedToHistory.selectedWeekStart, earliestWeekStart)

        let clampedToCurrent = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: futureRecordDate,
            attempts: [],
            unlockEvents: [
                UnlockEvent(goalID: goal.id, minutes: 20, createdAt: earliestSunday)
            ],
            calendar: calendar,
            reduceMotion: false
        )
        XCTAssertEqual(clampedToCurrent.selectedWeekStart, currentWeek.start)
        XCTAssertTrue(clampedToCurrent.isCurrentWeek)

        let futureOnly = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: beforeHistory,
            attempts: [
                makeAttempt(goal: goal, result: .correct, createdAt: futureRecordDate)
            ],
            unlockEvents: [
                UnlockEvent(goalID: goal.id, minutes: 30, createdAt: futureRecordDate)
            ],
            calendar: calendar,
            reduceMotion: false
        )
        XCTAssertEqual(futureOnly.earliestWeekStart, currentWeek.start)
        XCTAssertEqual(futureOnly.selectedWeekStart, currentWeek.start)
        XCTAssertFalse(futureOnly.canGoPrevious)
        XCTAssertFalse(futureOnly.canGoNext)
    }

    @MainActor
    func testWeeklyReviewPeriodDestinationsAndFeedbackRespectBoundaries() throws {
        let goal = makeGoal()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))
        )
        let currentWeekStart = try XCTUnwrap(
            calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
        )
        let earliestWeekStart = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -3, to: currentWeekStart)
        )
        let selectedWeekStart = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)
        )
        let earliestAttempt = makeAttempt(
            goal: goal,
            result: .correct,
            createdAt: earliestWeekStart.addingTimeInterval(3_600)
        )
        let policy = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: selectedWeekStart,
            attempts: [earliestAttempt],
            unlockEvents: [],
            calendar: calendar,
            reduceMotion: false
        )
        let expectedPrevious = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -1, to: selectedWeekStart)
        )
        let expectedNext = currentWeekStart

        XCTAssertEqual(policy.destination(for: .previous), expectedPrevious)
        XCTAssertEqual(policy.destination(for: .next), expectedNext)
        XCTAssertTrue(policy.reportsSelectionFeedback(for: .previous))
        XCTAssertTrue(policy.reportsSelectionFeedback(for: .next))

        let earliestPolicy = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: earliestWeekStart,
            attempts: [earliestAttempt],
            unlockEvents: [],
            calendar: calendar,
            reduceMotion: false
        )
        XCTAssertNil(earliestPolicy.destination(for: .previous))
        XCTAssertNotNil(earliestPolicy.destination(for: .next))
        XCTAssertFalse(
            earliestPolicy.reportsSelectionFeedback(for: .previous),
            "A boundary tap with no destination should not fire feedback."
        )
        XCTAssertTrue(earliestPolicy.reportsSelectionFeedback(for: .next))

        let currentPolicy = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: referenceDate,
            attempts: [earliestAttempt],
            unlockEvents: [],
            calendar: calendar,
            reduceMotion: false
        )
        XCTAssertNil(currentPolicy.destination(for: .next))
        XCTAssertNotNil(currentPolicy.destination(for: .previous))
        XCTAssertFalse(
            currentPolicy.reportsSelectionFeedback(for: .next),
            "A boundary tap with no destination should not fire feedback."
        )
        XCTAssertTrue(currentPolicy.reportsSelectionFeedback(for: .previous))
    }

    @MainActor
    func testWeeklyReviewPeriodUsesNowForCurrentAndWeekEndForArchive() throws {
        let goal = makeGoal()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12, minute: 34))
        )
        let currentWeekStart = try XCTUnwrap(
            calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
        )
        let archivedWeekStart = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)
        )
        let history = [
            makeAttempt(
                goal: goal,
                result: .correct,
                createdAt: archivedWeekStart.addingTimeInterval(3_600)
            )
        ]
        let current = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: referenceDate,
            attempts: history,
            unlockEvents: [],
            calendar: calendar,
            reduceMotion: false
        )
        let archived = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: archivedWeekStart,
            attempts: history,
            unlockEvents: [],
            calendar: calendar,
            reduceMotion: true
        )
        let archivedInterval = try XCTUnwrap(
            calendar.dateInterval(of: .weekOfYear, for: archivedWeekStart)
        )
        let finalArchivedInstant = Date(
            timeIntervalSinceReferenceDate:
                archivedInterval.end.timeIntervalSinceReferenceDate.nextDown
        )

        XCTAssertTrue(current.isCurrentWeek)
        XCTAssertEqual(current.effectiveAsOf, referenceDate)
        XCTAssertEqual(current.motionStyle, .directional)
        XCTAssertFalse(archived.isCurrentWeek)
        XCTAssertEqual(archived.effectiveAsOf, finalArchivedInstant)
        XCTAssertEqual(archived.motionStyle, .identity)

        let archivedSunday = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 6, to: archivedWeekStart)
        )
        XCTAssertTrue(
            WeeklyPracticeSelectionPolicy.canSelect(
                day: WeeklyPracticeDay(date: archivedSunday, questionsAnswered: 0),
                referenceDate: archived.effectiveAsOf
            ),
            "Every day in a completed archived week should be selectable."
        )
    }

    @MainActor
    func testWeeklyReviewPeriodPresentationUsesCurrentAndArchiveCopy() throws {
        let goal = makeGoal()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US")
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))
        )
        let currentWeekStart = try XCTUnwrap(
            calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
        )
        let archivedWeekStart = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: -2, to: currentWeekStart)
        )
        let history = [
            makeAttempt(
                goal: goal,
                result: .correct,
                createdAt: archivedWeekStart.addingTimeInterval(3_600)
            )
        ]
        let currentPolicy = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: referenceDate,
            attempts: history,
            unlockEvents: [],
            calendar: calendar,
            reduceMotion: false
        )
        let archivedPolicy = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: archivedWeekStart,
            attempts: history,
            unlockEvents: [],
            calendar: calendar,
            reduceMotion: false
        )
        let current = WeeklyReviewPeriodPresentation(
            policy: currentPolicy,
            calendar: calendar,
            locale: locale,
            timeZone: calendar.timeZone
        )
        let archived = WeeklyReviewPeriodPresentation(
            policy: archivedPolicy,
            calendar: calendar,
            locale: locale,
            timeZone: calendar.timeZone
        )

        XCTAssertEqual(current.eyebrowText, "THIS WEEK")
        XCTAssertEqual(current.rangeText, "Aug 31–Sep 6")
        XCTAssertEqual(
            current.accessibilityLabel,
            "Week of Monday, August 31 through Sunday, September 6"
        )
        XCTAssertEqual(
            current.summaryText,
            "A quiet read on what your checkpoints turned into."
        )
        XCTAssertEqual(current.emptyTitle, "Your signal starts with one checkpoint")
        XCTAssertEqual(
            current.emptyDetail,
            "Questions, recovered misses, and earned breaks will collect here without any extra setup."
        )

        XCTAssertEqual(archived.eyebrowText, "WEEKLY ARCHIVE")
        XCTAssertEqual(archived.rangeText, "Aug 17–23, 2026")
        XCTAssertEqual(
            archived.accessibilityLabel,
            "Week of Monday, August 17, 2026 through Sunday, August 23, 2026"
        )
        XCTAssertEqual(
            archived.summaryText,
            "A complete read on what your checkpoints turned into that week."
        )
        XCTAssertEqual(archived.emptyTitle, "No checkpoint activity that week")
        XCTAssertEqual(
            archived.emptyDetail,
            "Try another week or goal to keep exploring your history."
        )
    }

    @MainActor
    func testWeeklyReviewPeriodPresentationDisambiguatesACrossYearCurrentWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12))
        )
        let policy = WeeklyReviewPeriodPolicy(
            referenceDate: referenceDate,
            selectedWeekReferenceDate: referenceDate,
            attempts: [],
            unlockEvents: [],
            calendar: calendar,
            reduceMotion: false
        )
        let presentation = WeeklyReviewPeriodPresentation(
            policy: policy,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertEqual(presentation.rangeText, "Dec 28, 2026–Jan 3, 2027")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Week of Monday, December 28, 2026 through Sunday, January 3, 2027"
        )
    }

    func testWeeklyPracticeSelectionReconcilesToAnElapsedActivityDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: referenceDate))
        let days = try (0..<7).map { offset in
            WeeklyPracticeDay(
                date: try XCTUnwrap(
                    calendar.date(byAdding: .day, value: offset, to: week.start)
                ),
                questionsAnswered: offset == 0 || offset == 2 ? offset + 1 : 0
            )
        }
        let mondayID = days[0].id
        let wednesdayID = days[2].id
        let fridayID = days[4].id

        XCTAssertEqual(
            WeeklyPracticeSelectionPolicy.reconciledSelection(
                preferredDayID: mondayID,
                days: days,
                referenceDate: referenceDate
            ),
            mondayID
        )
        XCTAssertEqual(
            WeeklyPracticeSelectionPolicy.reconciledSelection(
                preferredDayID: fridayID,
                days: days,
                referenceDate: referenceDate
            ),
            wednesdayID,
            "A future preferred day should fall back to the latest elapsed activity day."
        )
        XCTAssertFalse(
            WeeklyPracticeSelectionPolicy.canSelect(
                day: days[4],
                referenceDate: referenceDate
            )
        )
        XCTAssertFalse(
            WeeklyPracticeSelectionPolicy.reportsSelectionFeedback(
                selectedDayID: wednesdayID,
                currentDayID: wednesdayID
            )
        )
        XCTAssertTrue(
            WeeklyPracticeSelectionPolicy.reportsSelectionFeedback(
                selectedDayID: mondayID,
                currentDayID: wednesdayID
            )
        )

        let emptyDays = days.map {
            WeeklyPracticeDay(date: $0.date, questionsAnswered: 0)
        }
        XCTAssertEqual(
            WeeklyPracticeSelectionPolicy.reconciledSelection(
                preferredDayID: nil,
                days: emptyDays,
                referenceDate: referenceDate
            ),
            days[3].id,
            "Without activity, the detail should settle on today instead of a future day."
        )
        XCTAssertNil(
            WeeklyPracticeSelectionPolicy.reconciledSelection(
                preferredDayID: nil,
                days: [],
                referenceDate: referenceDate
            )
        )
    }

    func testWeeklyPracticeDetailPresentsActivityEmptyAndFutureStates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let formatter = WeeklyReviewDateLabelFormatter(
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 12))
        )
        let tuesday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )
        let activity = WeeklyPracticeDayDetailPresentation(
            day: WeeklyPracticeDay(
                date: tuesday,
                questionsAnswered: 3,
                correctAnswers: 2,
                checkpointsCleared: 2,
                earnedBreakMinutes: 75
            ),
            referenceDate: referenceDate,
            dateLabelFormatter: formatter
        )

        XCTAssertEqual(activity.dateText, "Tuesday, Sep 1")
        XCTAssertEqual(activity.dateEyebrowText, "TUESDAY, SEP 1")
        XCTAssertEqual(activity.activityText, "3 questions · 66% correct")
        XCTAssertEqual(activity.breakText, "2 breaks · 1h 15m unlocked")
        XCTAssertEqual(
            activity.accessibilityLabel,
            "Tuesday, Sep 1. 3 questions · 66% correct. 2 breaks · 1h 15m unlocked"
        )
        XCTAssertTrue(activity.hasActivity)
        XCTAssertFalse(activity.isFuture)

        let singular = WeeklyPracticeDayDetailPresentation(
            day: WeeklyPracticeDay(
                date: tuesday,
                questionsAnswered: 1,
                correctAnswers: 1,
                checkpointsCleared: 1,
                earnedBreakMinutes: 15
            ),
            referenceDate: referenceDate,
            dateLabelFormatter: formatter
        )
        XCTAssertEqual(singular.activityText, "1 question · 100% correct")
        XCTAssertEqual(singular.breakText, "1 break · 15m unlocked")

        let empty = WeeklyPracticeDayDetailPresentation(
            day: WeeklyPracticeDay(date: tuesday, questionsAnswered: 0),
            referenceDate: referenceDate,
            dateLabelFormatter: formatter
        )
        XCTAssertEqual(empty.activityText, "No questions answered")
        XCTAssertEqual(empty.breakText, "No break earned")
        XCTAssertFalse(empty.hasActivity)

        let friday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))
        )
        let future = WeeklyPracticeDayDetailPresentation(
            day: WeeklyPracticeDay(date: friday, questionsAnswered: 4),
            referenceDate: referenceDate,
            dateLabelFormatter: formatter
        )
        XCTAssertTrue(future.isFuture)
        XCTAssertEqual(future.activityText, "Not yet")
        XCTAssertEqual(future.breakText, "This day is still ahead.")
    }

    func testWeeklyPracticeLayoutAndMotionRespectAccessibilityContracts() {
        XCTAssertEqual(WeeklyPracticeChartLayoutPolicy.minimumDayWidth, 44)
        XCTAssertFalse(
            WeeklyPracticeChartLayoutPolicy.requiresHorizontalScrolling(
                availableWidth: 308,
                dayCount: 7
            )
        )
        XCTAssertTrue(
            WeeklyPracticeChartLayoutPolicy.requiresHorizontalScrolling(
                availableWidth: 307,
                dayCount: 7
            )
        )
        XCTAssertFalse(
            WeeklyPracticeChartLayoutPolicy.requiresHorizontalScrolling(
                availableWidth: 0,
                dayCount: 0
            )
        )
        XCTAssertEqual(
            WeeklyPracticeSelectionMotionPolicy(reduceMotion: false).style,
            .animated
        )
        XCTAssertEqual(
            WeeklyPracticeSelectionMotionPolicy(reduceMotion: true).style,
            .identity
        )
    }

    @MainActor
    func testWeeklySkillSnapshotExcludesArchivedAndOffMapSkills() throws {
        let store = CheckpointStore(defaults: defaults)
        let positioning = SkillMapTopic(
            name: "Positioning",
            aliases: ["Market framing"]
        )
        let synthesis = SkillMapTopic(name: "Research synthesis")
        let archived = SkillMapTopic(name: "Legacy segmentation")
        var goal = makeGoal()
        goal.derivedSkillMap = GoalSkillMap(
            topics: [positioning, synthesis],
            archivedTopics: [
                ArchivedSkillMapTopic(
                    topic: archived,
                    reason: .mastered,
                    archivedAt: Date(),
                    successorSkillIDs: [positioning.id],
                    mastery: nil
                )
            ],
            status: .reviewed
        )

        var aliasedCurrent = TopicCompetency.initial(
            topic: "Market framing",
            goalID: goal.id
        )
        aliasedCurrent.attempts = 4
        aliasedCurrent.correct = 1
        aliasedCurrent.incorrect = 3

        var strongestCurrent = TopicCompetency.initial(
            topic: synthesis.name,
            goalID: goal.id,
            skillID: synthesis.id
        )
        strongestCurrent.attempts = 4
        strongestCurrent.correct = 3
        strongestCurrent.incorrect = 1

        var archivedExtreme = TopicCompetency.initial(
            topic: archived.name,
            goalID: goal.id,
            skillID: archived.id
        )
        archivedExtreme.attempts = 20
        archivedExtreme.correct = 20

        var offMapExtreme = TopicCompetency.initial(
            topic: "Market framing",
            goalID: goal.id,
            skillID: UUID()
        )
        offMapExtreme.attempts = 20
        offMapExtreme.incorrect = 20

        store.goal = goal
        store.goalProfiles = [goal]
        store.competencies = [
            archivedExtreme,
            offMapExtreme,
            strongestCurrent,
            aliasedCurrent
        ]

        let goalMetrics = try XCTUnwrap(store.weeklyActiveGoalMetrics)
        XCTAssertEqual(
            goalMetrics.skillSnapshotSignals,
            [
                .lowestCurrentEstimate("Positioning"),
                .highestCurrentEstimate("Research synthesis")
            ]
        )
        XCTAssertEqual(store.weeklyTotalMetrics.skillSnapshotSignals, goalMetrics.skillSnapshotSignals)
    }

    func testWeeklySignalFallbacksStayFactual() {
        var metrics = WeeklyMetricsSummary(
            id: WeeklyMetricsSummary.allGoalsID,
            title: "All goals",
            questionsAnswered: 0,
            correctAnswers: 0,
            missedAnswers: 0,
            checkpointStreakDays: 0,
            checkpointsCleared: 2,
            strongestSkill: nil,
            reviewSkill: nil
        )

        XCTAssertEqual(metrics.weeklySignalInsight, .checkpointsCleared(2))
        XCTAssertEqual(metrics.weeklySignalInsight?.text, "2 checkpoints cleared this week.")

        metrics.checkpointsCleared = 0
        metrics.questionsAnswered = 3
        XCTAssertEqual(metrics.weeklySignalInsight, .answersLogged)

        metrics.questionsAnswered = 0
        metrics.checkpointStreakDays = 4
        XCTAssertEqual(metrics.weeklySignalInsight, .checkpointStreak(4))
        XCTAssertEqual(metrics.weeklySignalInsight?.accessibilityLabel, "4-day checkpoint streak")
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

        var needsPractice = TopicCompetency.initial(topic: "Reliability")
        needsPractice.attempts = 10
        needsPractice.incorrect = 10

        var building = TopicCompetency.initial(topic: "Performance")
        building.attempts = 10
        building.correct = 6
        building.incorrect = 4

        let summary = ProgressDashboardSummary(
            competencies: [notStarted, calibrating, needsPractice, building, strong],
            attemptDates: [lastPracticedAt]
        )

        XCTAssertEqual(summary.totalSkillCount, 5)
        XCTAssertEqual(summary.practicedSkillCount, 4)
        XCTAssertEqual(summary.strongSkillCount, 1)
        XCTAssertEqual(summary.calibratingSkillCount, 1)
        XCTAssertEqual(summary.developingSkillCount, 3)
        XCTAssertEqual(
            summary.strongSkillCount
                + summary.developingSkillCount
                + summary.unpracticedSkillCount,
            summary.totalSkillCount
        )
        XCTAssertEqual(
            summary.skillSignalSummaryText,
            "1 strong · 3 developing · 1 awaiting a first signal"
        )
        XCTAssertEqual(summary.lastPracticedAt, lastPracticedAt)
        XCTAssertEqual(summary.coverageProgress, 4.0 / 5.0, accuracy: 0.001)
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
        XCTAssertEqual(summary.developingSkillCount, 0)
        XCTAssertEqual(summary.skillSignalSummaryText, "2 strong")
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
    func testFeedbackDraftsPersistAndRejectBlankMessages() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .generalFeedback,
                message: "   ",
                includesCurrentGoal: false
            ),
            .emptyMessage
        )
        XCTAssertEqual(store.issueReportCount, 0)

        XCTAssertEqual(
            store.saveIssueReportDraft(
                category: .appBlocking,
                message: "  The shield did not appear after I opened a blocked app.  ",
                includesCurrentGoal: true
            ),
            .saved
        )
        XCTAssertEqual(store.issueReportCount, 1)

        let report = try XCTUnwrap(store.issueReports.first)
        XCTAssertEqual(report.category, .appBlocking)
        XCTAssertEqual(report.message, "The shield did not appear after I opened a blocked app.")
        XCTAssertEqual(report.contact, "")
        XCTAssertEqual(report.goalID, goal.id)
        XCTAssertEqual(report.goalTitle, goal.title)

        let reloadedStore = CheckpointStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.issueReports, store.issueReports)
    }

}
