import XCTest
@testable import Checkpoint

final class GoalProfileTests: CheckpointWorkflowTestCase {
    // MARK: - Goal profiles

    @MainActor
    func testSwitchingActiveGoalRebuildsPracticeSetAndSkillMap() async throws {
        let engine = GoalAwareQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: engine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays, recursion, hash maps",
            preferredQuestionStyle: .multipleChoice
        )

        let firstGoal = try XCTUnwrap(store.goal)
        let firstQuestion = try XCTUnwrap(store.questions.first)
        XCTAssertEqual(Set(store.competencies.map(\.topic)), ["arrays", "recursion", "hash maps"])

        _ = store.submitAnswer(question: firstQuestion, answer: firstQuestion.expectedAnswer, result: .correct)
        store.questionReports = [makeQuestionReport(for: firstQuestion, note: "stale")]

        XCTAssertFalse(store.attempts.isEmpty)
        XCTAssertFalse(store.questionReports.isEmpty)
        XCTAssertNotNil(store.unlockSession)
        XCTAssertNotNil(SharedAppGroup.unlockExpiration)

        await store.createGoal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Comfortable with derivatives, weak on integrals",
            focusAreas: "derivatives, integrals, limits",
            preferredQuestionStyle: .multipleChoice
        )

        let secondGoal = try XCTUnwrap(store.goal)
        XCTAssertNotEqual(secondGoal.id, firstGoal.id)
        XCTAssertEqual(secondGoal.title, "Prepare for calculus final")
        XCTAssertTrue(store.activeQuestions.allSatisfy { $0.goalID == secondGoal.id })
        XCTAssertEqual(Set(store.activeQuestions.map(\.topic)), ["derivatives", "integrals", "limits"])
        XCTAssertEqual(Set(store.sortedCompetencies.map(\.topic)), ["derivatives", "integrals", "limits"])
        XCTAssertTrue(store.activeAttempts.isEmpty)
        XCTAssertTrue(store.activeQuestionReports.isEmpty)
        XCTAssertNil(store.unlockSession)
        XCTAssertNil(SharedAppGroup.unlockExpiration)

        let session = try XCTUnwrap(store.nextCheckpointSession())
        XCTAssertTrue(session.questions.allSatisfy { $0.goalID == secondGoal.id })
        XCTAssertTrue(session.questions.allSatisfy { ["derivatives", "integrals", "limits"].contains($0.topic) })
    }

    @MainActor
    func testGoalProfilesPreserveSeparateQuestionPoolsSkillMapsAndDifficulty() async throws {
        let engine = GoalAwareQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: engine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Advanced on arrays, weak at recursion",
            focusAreas: "arrays, recursion, hash maps",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 4
        )

        let firstGoal = try XCTUnwrap(store.goal)
        let firstQuestion = try XCTUnwrap(store.activeQuestions.first)
        _ = store.submitAnswer(question: firstQuestion, answer: firstQuestion.expectedAnswer, result: .correct)
        store.questionReports = [makeQuestionReport(for: firstQuestion, note: "too vague")]

        await store.createGoal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Comfortable with derivatives, weak on integrals",
            focusAreas: "derivatives, integrals, limits",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )

        let secondGoal = try XCTUnwrap(store.goal)
        XCTAssertNotEqual(secondGoal.id, firstGoal.id)
        XCTAssertEqual(store.availableGoalProfiles.count, 2)
        XCTAssertEqual(store.activeQuestionDifficulty, 2)
        XCTAssertTrue(store.activeQuestions.allSatisfy { $0.goalID == secondGoal.id })
        XCTAssertEqual(Set(store.sortedCompetencies.map(\.topic)), ["derivatives", "integrals", "limits"])
        XCTAssertTrue(store.activeAttempts.isEmpty)
        XCTAssertTrue(store.activeQuestionReports.isEmpty)

        let firstSourcePrompt = try XCTUnwrap(store.questions.first { $0.goalID == firstGoal.id }?.sourcePrompt)
        let secondSourcePrompt = try XCTUnwrap(store.questions.first { $0.goalID == secondGoal.id }?.sourcePrompt)
        XCTAssertTrue(firstSourcePrompt.contains("level 4 of 5 difficulty multiple-choice questions"))
        XCTAssertTrue(secondSourcePrompt.contains("level 2 of 5 difficulty multiple-choice questions"))

        store.switchActiveGoal(to: firstGoal.id)

        XCTAssertEqual(store.goal?.id, firstGoal.id)
        XCTAssertEqual(store.activeQuestionDifficulty, 4)
        XCTAssertTrue(store.activeQuestions.allSatisfy { $0.goalID == firstGoal.id })
        XCTAssertEqual(Set(store.sortedCompetencies.map(\.topic)), ["arrays", "recursion", "hash maps"])
        XCTAssertEqual(store.activeAttempts.count, 1)
        XCTAssertEqual(store.activeQuestionReports.count, 1)

        let session = try XCTUnwrap(store.nextCheckpointSession())
        XCTAssertTrue(session.questions.allSatisfy { $0.goalID == firstGoal.id })
        XCTAssertTrue(session.questions.allSatisfy { $0.difficulty >= 4 })
    }

    @MainActor
    func testSwitchingGoalUsesCachedQuestionBankWithoutRegeneration() async throws {
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: appleEngine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)

        let firstGoal = makeGoal()
        let secondGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        let firstQuestions = (1...12).map { index in
            makeQuestion(goal: firstGoal, index: index, topic: "arrays", difficulty: 4)
        }
        let secondQuestions = (1...24).map { index in
            makeQuestion(goal: secondGoal, index: index, topic: "integrals", difficulty: 2)
        }

        store.goal = firstGoal
        store.goalProfiles = [firstGoal, secondGoal]
        store.questions = firstQuestions + secondQuestions

        XCTAssertTrue(store.switchActiveGoal(to: secondGoal.id))
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.goal?.id, secondGoal.id)
        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertEqual(Set(store.activeQuestions.map(\.id)), Set(secondQuestions.map(\.id)))
        XCTAssertEqual(store.usableQuestionCount(for: secondGoal), secondQuestions.count)
        XCTAssertTrue(appleEngine.receivedRequests.isEmpty)
    }

    @MainActor
    func testSwitchingGoalPreparesProtectionReviewBankWhenCachedSetIsLow() async throws {
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: appleEngine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)

        let firstGoal = makeGoal()
        let secondGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )

        store.goal = firstGoal
        store.goalProfiles = [firstGoal, secondGoal]
        store.questions = (1...12).map { index in
            makeQuestion(goal: secondGoal, index: index, topic: "integrals", difficulty: 2)
        }

        XCTAssertTrue(store.switchActiveGoal(to: secondGoal.id))
        try? await Task.sleep(nanoseconds: 150_000_000)

        let request = try XCTUnwrap(appleEngine.receivedRequest)
        XCTAssertEqual(request.goal.id, secondGoal.id)
        XCTAssertEqual(request.targetCount, UnlockPolicy.default.questionsPerSession * 2)
    }

    @MainActor
    func testSwitchingActiveGoalPublishesShieldGoalTitle() {
        let store = CheckpointStore(defaults: defaults)
        store.updateMembershipTier(.member)
        let firstGoal = makeGoal()
        let secondGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        store.goal = firstGoal
        store.goalProfiles = [firstGoal, secondGoal]
        let notificationExpectation = expectation(description: "Shield context change notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .checkpointShieldContextDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notificationExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        store.switchActiveGoal(to: secondGoal.id)

        XCTAssertEqual(
            SharedAppGroup.defaults.string(forKey: SharedAppGroup.shieldGoalTitleKey),
            secondGoal.title
        )
        XCTAssertEqual(SharedAppGroup.currentShieldContext().goalTitle, secondGoal.title)
        wait(for: [notificationExpectation], timeout: 0.2)
    }

    @MainActor
    func testMemberGoalProfileLimitPreventsExtraGoalAndGeneration() async throws {
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: appleEngine
            ),
            defaults: defaults
        )
        store.updateMembershipTier(.member)

        let profiles = (0..<ProductLimits.memberGoalProfileLimit).map { index in
            Goal(
                title: "Goal \(index + 1)",
                deadline: Date().addingTimeInterval(60 * 60 * 24 * Double(30 + index)),
                category: .custom,
                currentLevel: "",
                focusAreas: "topic \(index + 1)",
                preferredQuestionStyle: .multipleChoice
            )
        }
        let activeGoal = try XCTUnwrap(profiles.first)
        store.goal = activeGoal
        store.goalProfiles = profiles

        await store.createGoal(
            title: "Goal over the limit",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 90),
            category: .custom,
            currentLevel: "",
            focusAreas: "extra topic",
            preferredQuestionStyle: .multipleChoice,
            createsNewProfile: true
        )

        XCTAssertEqual(store.availableGoalProfiles.count, ProductLimits.memberGoalProfileLimit)
        XCTAssertEqual(store.goal?.id, activeGoal.id)
        XCTAssertEqual(store.goalProfileCapacityText, "\(ProductLimits.memberGoalProfileLimit)/\(ProductLimits.memberGoalProfileLimit) goals")
        XCTAssertEqual(store.checkpointNotice, store.goalProfileLimitMessage)
        XCTAssertTrue(appleEngine.receivedRequests.isEmpty)
    }

    @MainActor
    func testGoalProfilesPersistAcrossStoreReloads() async throws {
        let engine = GoalAwareQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: engine
            ),
            defaults: defaults
        )
        store.updateMembershipTier(.member)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Advanced on arrays",
            focusAreas: "arrays, recursion, hash maps",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 4
        )
        let firstGoal = try XCTUnwrap(store.goal)

        await store.createGoal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals, limits",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        let secondGoal = try XCTUnwrap(store.goal)
        store.switchActiveGoal(to: firstGoal.id)

        let restoredStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: engine
            ),
            defaults: defaults
        )

        XCTAssertEqual(restoredStore.goal?.id, firstGoal.id)
        XCTAssertEqual(Set(restoredStore.availableGoalProfiles.map(\.id)), Set([firstGoal.id, secondGoal.id]))
        XCTAssertEqual(restoredStore.activeQuestionDifficulty, 4)
        XCTAssertTrue(restoredStore.activeQuestions.allSatisfy { $0.goalID == firstGoal.id })
        XCTAssertEqual(Set(restoredStore.sortedCompetencies.map(\.topic)), ["arrays", "recursion", "hash maps"])
    }

    @MainActor
    func testDeletingInactiveGoalRemovesOnlyThatGoalData() throws {
        let store = CheckpointStore(defaults: defaults)
        store.updateMembershipTier(.member)
        let activeGoal = makeGoal()
        let inactiveGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice
        )
        store.goal = activeGoal
        store.goalProfiles = [activeGoal, inactiveGoal]
        store.questions = [
            makeQuestion(goal: activeGoal, index: 1, topic: "arrays"),
            makeQuestion(goal: inactiveGoal, index: 2, topic: "integrals")
        ]
        store.attempts = [
            makeAttempt(goal: activeGoal, result: .correct, createdAt: Date()),
            makeAttempt(goal: inactiveGoal, result: .incorrect, createdAt: Date())
        ]
        store.competencies = [
            TopicCompetency.initial(topic: "arrays", goalID: activeGoal.id),
            TopicCompetency.initial(topic: "integrals", goalID: inactiveGoal.id)
        ]
        store.unlockEvents = [
            UnlockEvent(goalID: activeGoal.id, minutes: 30),
            UnlockEvent(goalID: inactiveGoal.id, minutes: 15)
        ]
        store.focusWins = [
            FocusWin(goalID: activeGoal.id, note: "Active goal win"),
            FocusWin(goalID: inactiveGoal.id, note: "Inactive goal win")
        ]

        XCTAssertTrue(store.deleteGoalProfile(inactiveGoal.id))

        XCTAssertEqual(store.goal?.id, activeGoal.id)
        XCTAssertEqual(store.availableGoalProfiles.map(\.id), [activeGoal.id])
        XCTAssertTrue(store.questions.allSatisfy { $0.goalID == activeGoal.id })
        XCTAssertTrue(store.attempts.allSatisfy { $0.goalID == activeGoal.id })
        XCTAssertTrue(store.competencies.allSatisfy { $0.goalID == activeGoal.id })
        XCTAssertTrue(store.unlockEvents.allSatisfy { $0.goalID == activeGoal.id })
        XCTAssertEqual(store.focusWins.map(\.goalID), [activeGoal.id])
        XCTAssertEqual(SharedAppGroup.currentShieldContext().goalTitle, activeGoal.title)
    }

    @MainActor
    func testDeletingActiveGoalSwitchesToRemainingGoalAndClearsUnlock() throws {
        let store = CheckpointStore(defaults: defaults)
        store.updateMembershipTier(.member)
        let activeGoal = makeGoal()
        let replacementGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice
        )
        store.goal = activeGoal
        store.goalProfiles = [activeGoal, replacementGoal]
        store.questions = [
            makeQuestion(goal: activeGoal, index: 1, topic: "arrays"),
            makeQuestion(goal: replacementGoal, index: 2, topic: "integrals")
        ]
        store.startUnlockSession(minutes: 5)
        XCTAssertNotNil(store.unlockSession)

        XCTAssertTrue(store.deleteGoalProfile(activeGoal.id))

        XCTAssertEqual(store.goal?.id, replacementGoal.id)
        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertNil(store.unlockSession)
        XCTAssertNil(SharedAppGroup.unlockExpiration)
        XCTAssertTrue(store.questions.allSatisfy { $0.goalID == replacementGoal.id })
        XCTAssertEqual(SharedAppGroup.currentShieldContext().goalTitle, replacementGoal.title)
    }

    @MainActor
    func testDeletingOnlyGoalReturnsToGoalSetup() throws {
        let store = CheckpointStore(defaults: defaults)
        let goal = makeGoal()
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = [makeQuestion(goal: goal, index: 1)]
        store.competencies = [TopicCompetency.initial(topic: "arrays", goalID: goal.id)]
        store.startUnlockSession(minutes: 5)

        XCTAssertTrue(store.deleteGoalProfile(goal.id))

        XCTAssertNil(store.goal)
        XCTAssertTrue(store.availableGoalProfiles.isEmpty)
        XCTAssertTrue(store.questions.isEmpty)
        XCTAssertTrue(store.competencies.isEmpty)
        XCTAssertNil(store.unlockSession)
        XCTAssertNil(SharedAppGroup.unlockExpiration)
        XCTAssertEqual(store.questionBatchState, .idle)
        XCTAssertTrue(store.isOnboardingPresented)
        XCTAssertEqual(SharedAppGroup.currentShieldContext().goalTitle, "Checkpoint")
    }

}
