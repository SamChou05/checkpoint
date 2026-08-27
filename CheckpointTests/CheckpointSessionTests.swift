import XCTest
@testable import Checkpoint

final class CheckpointSessionTests: CheckpointWorkflowTestCase {
    // MARK: - Checkpoint selection, grading, and cooldowns

    @MainActor
    func testCheckpointSessionUsesFiveDistinctQuestionsByDefault() throws {
        let store = makeSeededStore(questionCount: 7)

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(session.unlockThreshold, 4)
        XCTAssertEqual(session.purpose, .temporaryUnlock)
        XCTAssertEqual(Set(session.questions.map(\.id)).count, 5)
    }

    @MainActor
    func testCheckpointSessionSpreadsFreshQuestionsAcrossTopicsBeforeRepeatingOne() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.updateQuestionsPerSession(5)
        store.questions = [
            makeQuestion(goal: goal, index: 1, topic: "arrays"),
            makeQuestion(goal: goal, index: 2, topic: "arrays"),
            makeQuestion(goal: goal, index: 3, topic: "recursion"),
            makeQuestion(goal: goal, index: 4, topic: "hash maps"),
            makeQuestion(goal: goal, index: 5, topic: "trees")
        ]

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(Set(session.questions.prefix(4).map(\.topic)).count, 4)
    }

    @MainActor
    func testPreviewCheckpointSessionDoesNotUseUnlockPurpose() throws {
        let store = makeSeededStore(questionCount: 7)

        let session = try XCTUnwrap(store.startPreviewCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(session.unlockThreshold, 4)
        XCTAssertEqual(session.purpose, .preview)
    }

    @MainActor
    func testStopBlockingSessionRequiresEighteenOfTwentyQuestions() throws {
        let store = makeSeededStore(questionCount: 24)

        let session = try XCTUnwrap(store.startStopBlockingSession())

        XCTAssertEqual(session.questions.count, StopBlockingPolicy.questionsPerSession)
        XCTAssertEqual(session.unlockThreshold, StopBlockingPolicy.requiredCorrectAnswers)
        XCTAssertEqual(session.purpose, .stopBlocking)
        XCTAssertFalse(session.hasMetUnlockThreshold(correctAnswerCount: 17))
        XCTAssertTrue(session.hasMetUnlockThreshold(correctAnswerCount: 18))
        XCTAssertEqual(Set(session.questions.map(\.id)).count, StopBlockingPolicy.questionsPerSession)
    }

    @MainActor
    func testStopBlockingSessionNeedsTwentyReadyQuestions() {
        let store = makeSeededStore(questionCount: 19)

        XCTAssertNil(store.startStopBlockingSession())
        XCTAssertEqual(
            store.checkpointNotice,
            "Checkpoint is preparing enough questions for the protection review. Try again in a moment or lower the minimum level."
        )
    }

    @MainActor
    func testStopBlockingSessionUsesCachedCorrectQuestionsBeforeRefilling() async throws {
        let goal = makeGoal()
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        let nextReviewAt = Date().addingTimeInterval(60 * 60 * 24 * 3)
        let newQuestions = (1...15).map { makeQuestion(goal: goal, index: $0) }
        let coolingDownCorrectQuestions = (16...20).map { index in
            makeQuestion(
                goal: goal,
                index: index,
                status: .correct,
                timesCorrect: 1,
                lastAskedAt: Date().addingTimeInterval(-60),
                nextReviewAt: nextReviewAt
            )
        }
        store.questions = newQuestions + coolingDownCorrectQuestions

        let preparedSession = await store.prepareStopBlockingSession()
        let session = try XCTUnwrap(preparedSession)

        XCTAssertEqual(session.questions.count, StopBlockingPolicy.questionsPerSession)
        XCTAssertEqual(session.unlockThreshold, StopBlockingPolicy.requiredCorrectAnswers)
        XCTAssertTrue(coolingDownCorrectQuestions.allSatisfy { correctQuestion in
            session.questions.contains { $0.id == correctQuestion.id }
        })
        XCTAssertTrue(appleEngine.receivedRequests.isEmpty)
    }

    @MainActor
    func testStopBlockingPreparationRefillsBeforeChallenge() async throws {
        let goal = makeGoal()
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (2...20).map { makeQuestion(goal: goal, index: $0) }

        let preparedSession = await store.prepareStopBlockingSession()
        let session = try XCTUnwrap(preparedSession)

        XCTAssertEqual(session.questions.count, StopBlockingPolicy.questionsPerSession)
        XCTAssertEqual(session.unlockThreshold, StopBlockingPolicy.requiredCorrectAnswers)
        XCTAssertNotNil(appleEngine.receivedRequest)
        XCTAssertNil(store.checkpointNotice)
    }

    @MainActor
    func testStarterKeepsCoreCheckpointAvailable() throws {
        let store = makeSeededStore(questionCount: 6)

        let session = try XCTUnwrap(store.nextCheckpointSession())
        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(session.unlockThreshold, 4)
    }

    @MainActor
    func testCheckpointSessionPrioritizesMissedAndDueQuestionsBeforeNewQuestions() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.updateQuestionsPerSession(5)

        let missed = makeQuestion(
            goal: goal,
            index: 1,
            topic: "recursion",
            status: .incorrect,
            nextReviewAt: Date().addingTimeInterval(-60)
        )
        let due = makeQuestion(
            goal: goal,
            index: 2,
            topic: "arrays",
            status: .due,
            nextReviewAt: Date().addingTimeInterval(-30)
        )
        let new = makeQuestion(goal: goal, index: 3, topic: "hash maps")
        let fillerOne = makeQuestion(goal: goal, index: 4, topic: "Big-O")
        let fillerTwo = makeQuestion(goal: goal, index: 5, topic: "trees")
        store.questions = [new, fillerOne, due, fillerTwo, missed]

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(session.questions.prefix(2).map(\.id), [missed.id, due.id])
    }

    @MainActor
    func testCheckpointSessionRespectsMinimumQuestionDifficultyWhenPossible() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.updateQuestionsPerSession(5)
        store.updateMinimumQuestionDifficulty(3)

        let lowDue = makeQuestion(
            goal: goal,
            index: 1,
            status: .incorrect,
            nextReviewAt: Date().addingTimeInterval(-60),
            difficulty: 1
        )
        let highNew = makeQuestion(goal: goal, index: 2, difficulty: 3)
        let higherNew = makeQuestion(goal: goal, index: 3, topic: "recursion", difficulty: 4)
        let highNewThree = makeQuestion(goal: goal, index: 4, topic: "hash maps", difficulty: 3)
        let highNewFour = makeQuestion(goal: goal, index: 5, topic: "Big-O", difficulty: 4)
        let highNewFive = makeQuestion(goal: goal, index: 6, topic: "trees", difficulty: 5)
        store.questions = [lowDue, highNew, higherNew, highNewThree, highNewFour, highNewFive]

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertTrue(session.questions.allSatisfy { $0.difficulty >= 3 })
    }

    @MainActor
    func testCheckpointSessionDoesNotImmediatelyReuseRecentlyCorrectQuestions() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.updateQuestionsPerSession(5)

        let recentCorrect = makeQuestion(
            goal: goal,
            index: 1,
            status: .correct,
            timesCorrect: 1,
            lastAskedAt: Date().addingTimeInterval(-60),
            nextReviewAt: Date().addingTimeInterval(60 * 60 * 24 * 3)
        )
        let freshQuestions = (2...5).map { makeQuestion(goal: goal, index: $0) }
        store.questions = [recentCorrect] + freshQuestions

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 4)
        XCTAssertFalse(session.questions.contains { $0.id == recentCorrect.id })
    }

    @MainActor
    func testCheckpointSessionDoesNotReuseCorrectQuestionWhileFreshQuestionsRemain() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.updateQuestionsPerSession(5)
        let lastAskedAt = Date().addingTimeInterval(-60 * 60)

        let dueCorrect = makeQuestion(
            goal: goal,
            index: 1,
            status: .correct,
            timesAsked: 1,
            timesCorrect: 1,
            lastAskedAt: lastAskedAt,
            nextReviewAt: Date().addingTimeInterval(-60)
        )
        let freshQuestions = (2...6).map { makeQuestion(goal: goal, index: $0) }
        store.questions = [dueCorrect] + freshQuestions

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(Set(session.questions.map(\.id)), Set(freshQuestions.map(\.id)))
        XCTAssertFalse(session.questions.contains { $0.id == dueCorrect.id })
    }

    @MainActor
    func testCheckpointSessionReusesDueCorrectQuestionOnlyAfterFreshQuestionsAreUsed() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.updateQuestionsPerSession(5)

        let dueCorrect = makeQuestion(
            goal: goal,
            index: 1,
            status: .correct,
            timesAsked: 1,
            timesCorrect: 1,
            lastAskedAt: Date().addingTimeInterval(-60 * 60),
            nextReviewAt: Date().addingTimeInterval(-60)
        )
        let freshQuestions = (2...5).map { makeQuestion(goal: goal, index: $0) }
        store.questions = [dueCorrect] + freshQuestions

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(session.questions.last?.id, dueCorrect.id)
    }

    @MainActor
    func testCheckpointSessionUsesFreshLowerDifficultyBeforeRepeatingCorrectQuestion() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.updateQuestionsPerSession(5)
        store.updateMinimumQuestionDifficulty(5)

        let dueCorrect = makeQuestion(
            goal: goal,
            index: 1,
            status: .correct,
            timesAsked: 1,
            timesCorrect: 1,
            nextReviewAt: Date().addingTimeInterval(-60),
            difficulty: 5
        )
        let freshQuestions = (2...6).map { makeQuestion(goal: goal, index: $0, difficulty: 3) }
        store.questions = [dueCorrect] + freshQuestions

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(Set(session.questions.map(\.id)), Set(freshQuestions.map(\.id)))
        XCTAssertFalse(session.questions.contains { $0.id == dueCorrect.id })
    }

    @MainActor
    func testCheckpointSessionSkipsExactQuestionsAskedTwiceEvenIfStatusIsNotRetired() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.updateQuestionsPerSession(5)

        let exhaustedQuestion = makeQuestion(
            goal: goal,
            index: 1,
            status: .new,
            timesAsked: 2
        )
        let freshQuestions = (2...5).map { makeQuestion(goal: goal, index: $0) }
        store.questions = [exhaustedQuestion] + freshQuestions

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(store.usableQuestionCount, 4)
        XCTAssertEqual(session.questions.count, 4)
        XCTAssertFalse(session.questions.contains { $0.id == exhaustedQuestion.id })
    }

    @MainActor
    func testCorrectAnswerSchedulesLongerReviewDelay() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        let question = makeQuestion(goal: goal, index: 1)
        store.questions = [question]
        let beforeAnswer = Date()

        store.submitAnswer(
            question: question,
            answer: question.expectedAnswer,
            result: .correct,
            grantsUnlock: false
        )

        let updatedQuestion = try XCTUnwrap(store.questions.first)
        let nextReviewAt = try XCTUnwrap(updatedQuestion.nextReviewAt)
        XCTAssertEqual(updatedQuestion.status, .correct)
        XCTAssertGreaterThan(nextReviewAt.timeIntervalSince(beforeAnswer), 60 * 60 * 24 * 2.9)
    }

    @MainActor
    func testUnlockAllowsOneMissInDefaultFiveQuestionSession() throws {
        let store = makeSeededStore(questionCount: 5)
        let session = try XCTUnwrap(store.nextCheckpointSession())
        var correctAnswerCount = 0

        for (index, question) in session.questions.enumerated() {
            let isFinalQuestion = index == session.questions.indices.last
            let result: AnswerResult = isFinalQuestion ? .incorrect : .correct
            if result == .correct {
                correctAnswerCount += 1
            }
            let shouldUnlock = isFinalQuestion && session.hasMetUnlockThreshold(correctAnswerCount: correctAnswerCount)
            let unlockMinutes = store.submitAnswer(
                question: question,
                answer: result == .correct ? question.expectedAnswer : "Wrong answer",
                result: result,
                grantsUnlock: false,
                unlockMinutesOverride: shouldUnlock ? store.unlockPolicy.unlockMinutes : nil
            )

            if isFinalQuestion {
                XCTAssertTrue(shouldUnlock)
                XCTAssertEqual(unlockMinutes, store.unlockPolicy.unlockMinutes)
                XCTAssertEqual(store.activeUnlockMinutesRemaining, store.unlockPolicy.unlockMinutes)
                XCTAssertNotNil(store.unlockSession)
            } else {
                XCTAssertEqual(unlockMinutes, 0)
                XCTAssertNil(store.unlockSession)
            }
        }

        XCTAssertEqual(store.attempts.count, 5)
        XCTAssertEqual(store.attempts.filter { $0.unlockMinutes > 0 }.count, 1)
        XCTAssertEqual(store.unlockEvents.count, 1)
        XCTAssertEqual(store.unlockEvents.first?.minutes, store.unlockPolicy.unlockMinutes)
    }

    @MainActor
    func testStartUnlockSessionRecordsInsightUnlockEvent() throws {
        let store = makeSeededStore(questionCount: 5)

        store.startUnlockSession(minutes: store.unlockPolicy.unlockMinutes)

        XCTAssertEqual(store.unlockEvents.count, 1)
        XCTAssertEqual(store.unlockEvents.first?.minutes, store.unlockPolicy.unlockMinutes)
        XCTAssertEqual(store.weeklyActiveGoalMetrics?.checkpointsCleared, 1)
        XCTAssertEqual(store.weeklyActiveGoalMetrics?.checkpointStreakDays, 1)
    }

    @MainActor
    func testCheckpointSessionKnowsWhenThresholdIsImpossible() throws {
        let store = makeSeededStore(questionCount: 5)
        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertTrue(session.canStillMeetUnlockThreshold(correctAnswerCount: 2, answeredQuestionCount: 3))
        XCTAssertFalse(session.canStillMeetUnlockThreshold(correctAnswerCount: 1, answeredQuestionCount: 3))
    }

    @MainActor
    func testIncorrectAnswerKeepsLockedAndSchedulesReview() throws {
        let store = makeSeededStore(questionCount: 5)
        let question = try XCTUnwrap(store.questions.first)

        let unlockMinutes = store.submitAnswer(
            question: question,
            answer: "Wrong answer",
            result: .incorrect,
            grantsUnlock: true
        )

        let updatedQuestion = try XCTUnwrap(store.questions.first { $0.id == question.id })
        let updatedCompetency = try XCTUnwrap(store.competencies.first { $0.topic == question.topic })

        XCTAssertEqual(unlockMinutes, 0)
        XCTAssertNil(store.unlockSession)
        XCTAssertEqual(updatedQuestion.status, .incorrect)
        XCTAssertGreaterThan(updatedQuestion.nextReviewAt ?? .distantPast, Date())
        XCTAssertEqual(updatedCompetency.incorrect, 1)
    }

    @MainActor
    func testIncorrectAnswerResetsQuestionCorrectStreak() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        let question = makeQuestion(goal: goal, index: 1, timesCorrect: 2)
        store.questions = [question]
        store.competencies = [.initial(topic: question.topic, goalID: goal.id)]

        store.submitAnswer(
            question: question,
            answer: "Wrong answer",
            result: .incorrect,
            grantsUnlock: false
        )

        let updatedQuestion = try XCTUnwrap(store.questions.first { $0.id == question.id })
        XCTAssertEqual(updatedQuestion.timesCorrect, 0)
        XCTAssertEqual(updatedQuestion.status, .incorrect)
    }

    @MainActor
    func testSecondAskRetiresExactQuestionAfterCorrectAnswer() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        let question = makeQuestion(
            goal: goal,
            index: 1,
            status: .correct,
            timesAsked: 1,
            timesCorrect: 1,
            nextReviewAt: Date().addingTimeInterval(-60)
        )
        store.questions = [question]
        store.competencies = [.initial(topic: question.topic, goalID: goal.id)]

        store.submitAnswer(
            question: question,
            answer: question.expectedAnswer,
            result: .correct,
            grantsUnlock: false
        )

        let updatedQuestion = try XCTUnwrap(store.questions.first { $0.id == question.id })
        XCTAssertEqual(updatedQuestion.timesAsked, 2)
        XCTAssertEqual(updatedQuestion.timesCorrect, 2)
        XCTAssertEqual(updatedQuestion.status, .retired)
        XCTAssertNil(updatedQuestion.nextReviewAt)
    }

    @MainActor
    func testSecondAskRetiresExactQuestionAfterIncorrectAnswer() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        let question = makeQuestion(
            goal: goal,
            index: 1,
            status: .incorrect,
            timesAsked: 1,
            nextReviewAt: Date().addingTimeInterval(-60)
        )
        store.questions = [question]
        store.competencies = [.initial(topic: question.topic, goalID: goal.id)]

        store.submitAnswer(
            question: question,
            answer: "Wrong answer",
            result: .incorrect,
            grantsUnlock: false
        )

        let updatedQuestion = try XCTUnwrap(store.questions.first { $0.id == question.id })
        XCTAssertEqual(updatedQuestion.timesAsked, 2)
        XCTAssertEqual(updatedQuestion.timesCorrect, 0)
        XCTAssertEqual(updatedQuestion.status, .retired)
        XCTAssertNil(updatedQuestion.nextReviewAt)
    }

    @MainActor
    func testPartialAnswerReducesQuestionRetirementStreak() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        let question = makeQuestion(goal: goal, index: 1, timesCorrect: 2)
        store.questions = [question]
        store.competencies = [.initial(topic: question.topic, goalID: goal.id)]

        store.submitAnswer(
            question: question,
            answer: "Close answer",
            result: .partial,
            grantsUnlock: false
        )

        let updatedQuestion = try XCTUnwrap(store.questions.first { $0.id == question.id })
        XCTAssertEqual(updatedQuestion.timesCorrect, 1)
        XCTAssertEqual(updatedQuestion.status, .due)
    }

    @MainActor
    func testClearingUnlockSessionRemovesStoredTimer() throws {
        let store = makeSeededStore(questionCount: 5)
        let question = try XCTUnwrap(store.questions.first)

        store.submitAnswer(
            question: question,
            answer: question.expectedAnswer,
            result: .correct,
            grantsUnlock: true
        )

        XCTAssertNotNil(store.unlockSession)
        XCTAssertNotNil(SharedAppGroup.unlockExpiration)

        store.clearUnlockSession()

        XCTAssertNil(store.unlockSession)
        XCTAssertEqual(store.activeUnlockMinutesRemaining, 0)
        XCTAssertNil(SharedAppGroup.unlockExpiration)
    }

    @MainActor
    func testFailedSessionMakesMissedQuestionsDueForNextAttempt() throws {
        let store = makeSeededStore(questionCount: 6)
        let missedQuestions = Array(store.questions.prefix(2))
        let missedQuestionIDs = Set(missedQuestions.map(\.id))

        for question in missedQuestions {
            store.submitAnswer(
                question: question,
                answer: "Wrong answer",
                result: .incorrect,
                grantsUnlock: false
            )
        }

        XCTAssertTrue(missedQuestions.allSatisfy { question in
            let updatedQuestion = store.questions.first { $0.id == question.id }
            return (updatedQuestion?.nextReviewAt ?? .distantPast) > Date()
        })

        store.makeMissedQuestionsDueNow(missedQuestionIDs)

        let nextSession = try XCTUnwrap(store.nextCheckpointSession())
        XCTAssertEqual(Set(nextSession.questions.prefix(2).map(\.id)), missedQuestionIDs)
        XCTAssertTrue(missedQuestionIDs.allSatisfy { questionID in
            let updatedQuestion = store.questions.first { $0.id == questionID }
            return (updatedQuestion?.nextReviewAt ?? .distantFuture) <= Date()
        })
    }

    @MainActor
    func testAnswerRemainsAttributedToTheQuestionGoalAfterActiveGoalChanges() throws {
        let firstGoal = makeGoal()
        let secondGoal = Goal(
            title: "Pass the calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 20),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "integrals",
            preferredQuestionStyle: .multipleChoice
        )
        let question = makeQuestion(goal: firstGoal, index: 1)
        let store = CheckpointStore(defaults: defaults)
        store.goal = firstGoal
        store.questions = [question]
        store.goal = secondGoal

        let unlockMinutes = store.submitAnswer(
            question: question,
            answer: question.expectedAnswer,
            result: .correct
        )

        XCTAssertGreaterThan(unlockMinutes, 0)
        XCTAssertEqual(store.attempts.first?.goalID, firstGoal.id)
        XCTAssertEqual(store.unlockEvents.first?.goalID, firstGoal.id)
        XCTAssertEqual(store.goal?.id, secondGoal.id)
    }

    @MainActor
    func testFailedCheckpointCooldownBlocksImmediateRetryButNotPreview() throws {
        let store = makeSeededStore(questionCount: 6)

        store.startCheckpointRetryCooldown()

        XCTAssertTrue(store.isCheckpointRetryCooldownActive)
        XCTAssertNil(store.startManualCheckpointSession())
        XCTAssertTrue(store.checkpointNotice?.contains("Try another checkpoint") ?? false)
        XCTAssertNotNil(store.startPreviewCheckpointSession())

        SharedAppGroup.markPendingShieldAttempt()
        XCTAssertNil(store.takePendingShieldSession())
        XCTAssertNotNil(SharedAppGroup.pendingShieldAttemptDate)
        XCTAssertTrue(store.checkpointNotice?.contains("Try this checkpoint") ?? false)
    }

    @MainActor
    func testExpiredFailedCheckpointCooldownClearsAndAllowsRetry() throws {
        let store = makeSeededStore(questionCount: 6)
        store.checkpointRetryCooldownUntil = Date().addingTimeInterval(-1)

        let session = try XCTUnwrap(store.startManualCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertNil(store.checkpointRetryCooldownUntil)
        XCTAssertFalse(store.isCheckpointRetryCooldownActive)
    }

    @MainActor
    func testAbandoningCheckpointRunStartsCooldownAndClearsPersistedRun() throws {
        let store = makeSeededStore(questionCount: 6)
        let session = try XCTUnwrap(store.startManualCheckpointSession())

        XCTAssertEqual(store.activeCheckpointRun?.sessionID, session.id)

        store.abandonCheckpointRun(
            sessionID: session.id,
            missedQuestionIDs: [session.questions[0].id]
        )

        XCTAssertNil(store.activeCheckpointRun)
        XCTAssertTrue(store.isCheckpointRetryCooldownActive)
        XCTAssertEqual(
            store.questions.first(where: { $0.id == session.questions[0].id })?.status,
            .incorrect
        )
    }

    @MainActor
    func testInterruptedCheckpointRunStartsCooldownOnRelaunchWhenProtectionIsActive() throws {
        let store = makeSeededStore(questionCount: 6)
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)
        let session = try XCTUnwrap(store.startManualCheckpointSession())
        XCTAssertEqual(store.activeCheckpointRun?.sessionID, session.id)

        let relaunchedStore = CheckpointStore(defaults: defaults)

        XCTAssertNil(relaunchedStore.activeCheckpointRun)
        XCTAssertTrue(relaunchedStore.isCheckpointRetryCooldownActive)
        XCTAssertTrue(relaunchedStore.checkpointNotice?.contains("interrupted") ?? false)
        XCTAssertTrue(SharedAppGroup.desiredShieldActive)
    }

    func testEmptyCheckpointSessionCannotBecomeActiveRun() {
        let session = CheckpointSession(
            questions: [],
            requiredCorrectAnswers: 4,
            purpose: .temporaryUnlock
        )

        XCTAssertNil(ActiveCheckpointRun(session: session))
    }

    @MainActor
    func testFailedCheckpointCooldownPersistsAcrossRelaunch() {
        let store = makeSeededStore(questionCount: 6)
        store.startCheckpointRetryCooldown()

        let relaunchedStore = CheckpointStore(defaults: defaults)

        XCTAssertTrue(relaunchedStore.isCheckpointRetryCooldownActive)
        XCTAssertNil(relaunchedStore.startManualCheckpointSession())
        XCTAssertTrue(relaunchedStore.checkpointNotice?.contains("Try another checkpoint") ?? false)
    }

    @MainActor
    func testExpiredUnlockSessionIsPrunedOnRelaunch() {
        let store = makeSeededStore(questionCount: 6)
        let expiredAt = Date().addingTimeInterval(-300)
        store.unlockSession = UnlockSession(
            startedAt: Date().addingTimeInterval(-600),
            expiresAt: expiredAt
        )
        store.updateUnlockMinutes(store.unlockPolicy.unlockMinutes)
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: expiredAt)

        let relaunchedStore = CheckpointStore(defaults: defaults)

        XCTAssertNil(relaunchedStore.unlockSession)
        XCTAssertNil(SharedAppGroup.unlockExpiration)
        XCTAssertTrue(SharedAppGroup.desiredShieldActive)
    }

    @MainActor
    func testExpiredLocalUnlockDoesNotEraseNewerSharedBreak() {
        let store = makeSeededStore(questionCount: 6)
        store.unlockSession = UnlockSession(
            startedAt: Date().addingTimeInterval(-600),
            expiresAt: Date().addingTimeInterval(-300)
        )
        store.updateUnlockMinutes(store.unlockPolicy.unlockMinutes)
        let newerSharedExpiration = Date().addingTimeInterval(300)
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: newerSharedExpiration
        )

        let relaunchedStore = CheckpointStore(defaults: defaults)

        XCTAssertEqual(relaunchedStore.unlockSession?.expiresAt, newerSharedExpiration)
        XCTAssertEqual(SharedAppGroup.unlockExpiration, newerSharedExpiration)
        XCTAssertTrue(SharedAppGroup.desiredShieldActive)
    }

    @MainActor
    func testCanonicalEndedBreakClearsStaleFutureLocalUnlock() {
        let store = makeSeededStore(questionCount: 6)
        store.startUnlockSession(minutes: 5)
        XCTAssertTrue(store.unlockSession?.isActive == true)
        SharedAppGroup.publishProtectionState(isActive: true, unlockExpiration: nil)

        let relaunchedStore = CheckpointStore(defaults: defaults)

        XCTAssertNil(relaunchedStore.unlockSession)
        XCTAssertNil(SharedAppGroup.unlockExpiration)
        XCTAssertTrue(SharedAppGroup.desiredShieldActive)
    }

}
