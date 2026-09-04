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
        let activeBreak = try XCTUnwrap(store.unlockSession)
        let sharedBreakExpiration = try XCTUnwrap(SharedAppGroup.unlockExpiration)

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
        XCTAssertEqual(store.unlockSession?.expiresAt, activeBreak.expiresAt)
        XCTAssertEqual(SharedAppGroup.unlockExpiration, sharedBreakExpiration)

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

        XCTAssertEqual(
            activatePreparedGoal(in: store, to: firstGoal.id),
            .activated(from: secondGoal.id, to: firstGoal.id)
        )

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

        XCTAssertEqual(
            activatePreparedGoal(in: store, to: secondGoal.id),
            .activated(from: firstGoal.id, to: secondGoal.id)
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.goal?.id, secondGoal.id)
        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertEqual(Set(store.activeQuestions.map(\.id)), Set(secondQuestions.map(\.id)))
        XCTAssertEqual(store.usableQuestionCount(for: secondGoal), secondQuestions.count)
        XCTAssertTrue(appleEngine.receivedRequests.isEmpty)
    }

    @MainActor
    func testGoalActivationPreflightIsPureAndDescribesTargetReadiness() {
        let store = CheckpointStore(defaults: defaults)
        store.updateMembershipTier(.member)
        let firstGoal = makeGoal()
        let secondGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice
        )
        store.goal = firstGoal
        store.goalProfiles = [firstGoal, secondGoal]
        store.questions = (1...store.unlockPolicy.questionsPerSession).map { index in
            makeQuestion(goal: secondGoal, index: index, topic: "integrals")
        }
        store.questionBatchState = .failed
        store.checkpointNotice = "Keep the current recovery state."

        let originalGoalID = store.goal?.id
        let originalQuestionIDs = store.questions.map(\.id)
        let originalShieldContext = SharedAppGroup.currentShieldContext()

        let preflight = store.prepareGoalActivation(to: secondGoal.id)

        guard case let .eligible(plan) = preflight else {
            return XCTFail("Expected an eligible activation plan, got \(preflight)")
        }
        XCTAssertEqual(plan.sourceGoalID, firstGoal.id)
        XCTAssertEqual(plan.targetGoalID, secondGoal.id)
        XCTAssertEqual(plan.targetTitle, secondGoal.title)
        XCTAssertEqual(
            plan.readiness,
            .ready(
                selectableCount: store.unlockPolicy.questionsPerSession,
                requiredCount: store.unlockPolicy.questionsPerSession
            )
        )
        XCTAssertEqual(store.goal?.id, originalGoalID)
        XCTAssertEqual(store.questions.map(\.id), originalQuestionIDs)
        XCTAssertEqual(store.questionBatchState, .failed)
        XCTAssertEqual(store.checkpointNotice, "Keep the current recovery state.")
        XCTAssertNil(store.pendingMembershipPresentation)
        XCTAssertEqual(SharedAppGroup.currentShieldContext(), originalShieldContext)
    }

    @MainActor
    func testGoalActivationReadinessUsesExactDistinctSessionSelection() {
        let store = CheckpointStore(defaults: defaults)
        store.updateMembershipTier(.member)
        let firstGoal = makeGoal()
        let secondGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice
        )
        store.goal = firstGoal
        store.goalProfiles = [firstGoal, secondGoal]
        store.questions = (1...store.unlockPolicy.questionsPerSession).map { index in
            makeQuestion(
                goal: secondGoal,
                index: index,
                topic: "integrals",
                prompt: "What is the derivative of x squared?"
            )
        }

        XCTAssertEqual(
            store.usableQuestionCount(for: secondGoal),
            store.unlockPolicy.questionsPerSession,
            "The raw inventory is full even though it cannot form a distinct checkpoint."
        )

        let preflight = store.prepareGoalActivation(to: secondGoal.id)

        guard case let .eligible(plan) = preflight else {
            return XCTFail("Expected an eligible activation plan, got \(preflight)")
        }
        XCTAssertEqual(
            plan.readiness,
            .incomplete(
                selectableCount: 1,
                requiredCount: store.unlockPolicy.questionsPerSession
            )
        )
        XCTAssertEqual(store.goal?.id, firstGoal.id)
    }

    @MainActor
    func testSelectingAlreadyActiveGoalAfterDowngradeIsAnIdempotentNoOp() async throws {
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: appleEngine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)

        let goal = makeGoal()
        let inactiveGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice
        )
        store.goal = goal
        store.goalProfiles = [goal, inactiveGoal]
        store.membershipTier = .starter
        store.attempts = [makeAttempt(goal: goal, result: .correct, createdAt: Date())]
        store.questionBatchState = .failed
        store.checkpointNotice = "Keep this recovery context."
        let unlockExpiration = Date().addingTimeInterval(300)
        store.unlockSession = UnlockSession(
            startedAt: unlockExpiration.addingTimeInterval(-60),
            expiresAt: unlockExpiration
        )
        SharedAppGroup.publishProtectionState(
            isActive: true,
            unlockExpiration: unlockExpiration
        )
        let protectionSnapshot = SharedAppGroup.currentProtectionSnapshot()

        XCTAssertEqual(store.prepareGoalActivation(to: goal.id), .alreadyActive)
        XCTAssertEqual(store.goal?.id, goal.id)
        XCTAssertEqual(store.questionBatchState, .failed)
        XCTAssertEqual(store.checkpointNotice, "Keep this recovery context.")
        XCTAssertEqual(store.unlockSession?.expiresAt, unlockExpiration)
        XCTAssertEqual(SharedAppGroup.currentProtectionSnapshot(), protectionSnapshot)
        XCTAssertNil(store.pendingMembershipPresentation)

        try await Task.sleep(nanoseconds: 100_000_000)
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

        XCTAssertEqual(
            activatePreparedGoal(in: store, to: secondGoal.id),
            .activated(from: firstGoal.id, to: secondGoal.id)
        )
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

        XCTAssertEqual(
            activatePreparedGoal(in: store, to: secondGoal.id),
            .activated(from: firstGoal.id, to: secondGoal.id)
        )

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
        XCTAssertEqual(
            activatePreparedGoal(in: store, to: firstGoal.id),
            .activated(from: secondGoal.id, to: firstGoal.id)
        )

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
    func testDeletingActiveGoalSwitchesToReadyReplacementAndPreservesBreak() throws {
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
        store.questions = [makeQuestion(goal: activeGoal, index: 1, topic: "arrays")]
            + (1...store.unlockPolicy.questionsPerSession).map { index in
                makeQuestion(goal: replacementGoal, index: index + 100, topic: "integrals")
            }
        store.startUnlockSession(minutes: 5)
        let breakExpiration = try XCTUnwrap(store.unlockSession?.expiresAt)
        let request = GoalProfileMutationRequest(
            operation: .delete(goalID: activeGoal.id)
        )
        let preflight = store.prepareGoalProfileMutation(request)
        guard case let .eligible(plan) = preflight else {
            return XCTFail("Expected an eligible deletion plan, got \(preflight)")
        }

        XCTAssertEqual(
            store.commitGoalProfileMutation(using: plan),
            .committed(resultingGoalID: replacementGoal.id)
        )

        XCTAssertEqual(store.goal?.id, replacementGoal.id)
        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertEqual(store.unlockSession?.expiresAt, breakExpiration)
        XCTAssertEqual(SharedAppGroup.unlockExpiration, breakExpiration)
        XCTAssertTrue(store.questions.allSatisfy { $0.goalID == replacementGoal.id })
        XCTAssertEqual(SharedAppGroup.currentShieldContext().goalTitle, replacementGoal.title)
    }

    @MainActor
    func testDeletingActiveGoalTopsOffPartialReplacementWithoutOrphaningHistory() async throws {
        let engine = TargetCountQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: engine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        let activeGoal = makeGoal()
        let replacementGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice,
            createdAt: activeGoal.createdAt.addingTimeInterval(60)
        )
        let replacementQuestions = (1...4).map { index in
            makeQuestion(
                goal: replacementGoal,
                index: index + 100,
                topic: index.isMultiple(of: 2) ? "derivatives" : "integrals"
            )
        }
        let linkedQuestion = try XCTUnwrap(replacementQuestions.first)
        let linkedAttempt = makeAttempt(
            goal: replacementGoal,
            questionID: linkedQuestion.id,
            result: .incorrect,
            createdAt: Date()
        )
        let linkedReport = makeQuestionReport(
            for: linkedQuestion,
            note: "Keep this report linked"
        )
        store.goal = activeGoal
        store.goalProfiles = [activeGoal, replacementGoal]
        store.questions = (1...5).map {
            makeQuestion(goal: activeGoal, index: $0, topic: "arrays")
        } + replacementQuestions
        store.attempts = [linkedAttempt]
        store.questionReports = [linkedReport]
        let replacementQuestionIDs = Set(replacementQuestions.map(\.id))
        let request = GoalProfileMutationRequest(
            operation: .delete(goalID: activeGoal.id)
        )
        guard case let .eligible(plan) = store.prepareGoalProfileMutation(request) else {
            return XCTFail("Expected an eligible active-goal deletion")
        }
        XCTAssertEqual(
            plan.resultingReadiness,
            .incomplete(selectableCount: 4, requiredCount: 5)
        )

        XCTAssertEqual(
            store.commitGoalProfileMutation(using: plan),
            .committed(resultingGoalID: replacementGoal.id)
        )

        XCTAssertEqual(store.goal?.id, replacementGoal.id)
        XCTAssertTrue(store.isQuestionBankTopOffInProgress)
        XCTAssertTrue(
            replacementQuestionIDs.isSubset(of: Set(store.questions.map(\.id))),
            "Scheduling the replacement top-off must not clear its partial bank."
        )

        for _ in 0..<100 {
            if !engine.receivedRequests.isEmpty,
               !store.isQuestionBankTopOffInProgress {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let topOffRequest = try XCTUnwrap(engine.receivedRequests.first)
        XCTAssertEqual(
            Set(topOffRequest.existingQuestions.map(\.id)),
            replacementQuestionIDs
        )
        XCTAssertEqual(
            topOffRequest.targetCount,
            store.questionBankTargetCount - replacementQuestions.count
        )
        XCTAssertTrue(
            replacementQuestionIDs.isSubset(of: Set(store.questions.map(\.id)))
        )
        XCTAssertGreaterThan(
            store.questions.filter { $0.goalID == replacementGoal.id }.count,
            replacementQuestions.count
        )
        XCTAssertTrue(store.attempts.contains { $0.id == linkedAttempt.id })
        XCTAssertTrue(store.questionReports.contains { $0.id == linkedReport.id })
        XCTAssertNotNil(
            store.questions.first {
                $0.id == linkedQuestion.id && $0.goalID == replacementGoal.id
            }
        )
        XCTAssertTrue(
            store.questionGenerationTraces.contains { $0.phase == "Question bank top-off" }
        )
    }

    @MainActor
    func testDeletingActiveGoalTopsOffExactDeficitWhenReplacementInventoryIsFull() async throws {
        let engine = TargetCountQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: engine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        let activeGoal = makeGoal()
        let replacementGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice,
            createdAt: activeGoal.createdAt.addingTimeInterval(60)
        )
        let duplicateStemQuestions = (1...store.questionBankTargetCount).map { index in
            makeQuestion(
                goal: replacementGoal,
                index: index + 300,
                topic: "integrals",
                prompt: "What is the derivative of x squared?"
            )
        }
        store.goal = activeGoal
        store.goalProfiles = [activeGoal, replacementGoal]
        store.questions = (1...store.unlockPolicy.questionsPerSession).map {
            makeQuestion(goal: activeGoal, index: $0, topic: "arrays")
        } + duplicateStemQuestions
        let request = GoalProfileMutationRequest(
            operation: .delete(goalID: activeGoal.id)
        )
        guard case let .eligible(plan) = store.prepareGoalProfileMutation(request) else {
            return XCTFail("Expected an eligible active-goal deletion")
        }

        XCTAssertEqual(
            plan.resultingReadiness,
            .incomplete(selectableCount: 1, requiredCount: 5)
        )
        XCTAssertEqual(
            store.commitGoalProfileMutation(using: plan),
            .committed(resultingGoalID: replacementGoal.id)
        )

        for _ in 0..<100 {
            if !engine.receivedRequests.isEmpty,
               !store.isQuestionBankTopOffInProgress {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let topOffRequest = try XCTUnwrap(engine.receivedRequests.first)
        XCTAssertEqual(topOffRequest.existingQuestions.count, store.questionBankTargetCount)
        XCTAssertEqual(
            topOffRequest.targetCount,
            store.unlockPolicy.questionsPerSession - 1,
            "The exact checkpoint deficit must trigger generation even when raw inventory is full."
        )
        XCTAssertTrue(store.checkpointReadiness(for: replacementGoal).hasFullCheckpoint)
        XCTAssertEqual(store.questionBatchState, .ready)
    }

    @MainActor
    func testLapsedMemberDeletionPreservesConsumedReplacementWithoutGenerating() async throws {
        let engine = CapturingQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: engine
            ),
            defaults: defaults
        )
        let activeGoal = makeGoal()
        let replacementGoal = Goal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice,
            createdAt: activeGoal.createdAt.addingTimeInterval(60)
        )
        let replacementQuestions = (1...3).map { index in
            makeQuestion(
                goal: replacementGoal,
                index: index + 200,
                topic: "integrals"
            )
        }
        let practicedQuestion = try XCTUnwrap(replacementQuestions.first)
        let replacementAttempt = makeAttempt(
            goal: replacementGoal,
            questionID: practicedQuestion.id,
            result: .correct,
            createdAt: Date()
        )
        let replacementReport = makeQuestionReport(
            for: practicedQuestion,
            note: "Preserve this replacement report"
        )
        store.aiProviderPreference = .appleFoundation
        store.membershipTier = .starter
        store.goal = activeGoal
        store.goalProfiles = [activeGoal, replacementGoal]
        store.questions = (1...5).map {
            makeQuestion(goal: activeGoal, index: $0, topic: "arrays")
        } + replacementQuestions
        store.attempts = [replacementAttempt]
        store.questionReports = [replacementReport]
        let replacementQuestionIDs = Set(replacementQuestions.map(\.id))
        let request = GoalProfileMutationRequest(
            operation: .delete(goalID: activeGoal.id)
        )
        guard case let .eligible(plan) = store.prepareGoalProfileMutation(request) else {
            return XCTFail("Expected the lapsed member to be able to delete a saved goal")
        }

        XCTAssertEqual(
            store.commitGoalProfileMutation(using: plan),
            .committed(resultingGoalID: replacementGoal.id)
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.membershipTier, .starter)
        XCTAssertEqual(store.goal?.id, replacementGoal.id)
        XCTAssertEqual(
            Set(store.questions.filter { $0.goalID == replacementGoal.id }.map(\.id)),
            replacementQuestionIDs
        )
        XCTAssertTrue(store.attempts.contains { $0.id == replacementAttempt.id })
        XCTAssertTrue(store.questionReports.contains { $0.id == replacementReport.id })
        XCTAssertFalse(store.isQuestionBankTopOffInProgress)
        XCTAssertFalse(store.isPreparingActiveGoalQuestions)
        XCTAssertTrue(engine.receivedRequests.isEmpty)
        XCTAssertEqual(
            store.pendingMembershipPresentation,
            .feature(.freshQuestionGeneration)
        )
        XCTAssertEqual(
            store.checkpointNotice,
            "\(activeGoal.title) was deleted. Free includes an initial practice set for your first goal. Pro keeps new checkpoints available after that set runs low."
        )
    }

    @MainActor
    func testContextChangingGoalEditPreservesQuestionsReferencedByHistory() async throws {
        let engine = TargetCountQuestionEngine(provider: .appleFoundation)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: engine
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.appleFoundation)
        store.updateMembershipTier(.member)
        let sourceGoal = makeGoal()
        let existingQuestions = (1...4).map {
            makeQuestion(goal: sourceGoal, index: $0, topic: "arrays")
        }
        let linkedQuestion = try XCTUnwrap(existingQuestions.first)
        let linkedAttempt = makeAttempt(
            goal: sourceGoal,
            questionID: linkedQuestion.id,
            result: .correct,
            createdAt: Date()
        )
        let linkedReport = makeQuestionReport(
            for: linkedQuestion,
            note: "Historical quality note"
        )
        store.goal = sourceGoal
        store.goalProfiles = [sourceGoal]
        store.questions = existingQuestions
        store.attempts = [linkedAttempt]
        store.questionReports = [linkedReport]
        let existingQuestionIDs = Set(existingQuestions.map(\.id))
        let request = GoalProfileMutationRequest(
            createdAt: Date(),
            operation: .edit(
                expectedGoalID: sourceGoal.id,
                draft: GoalProfileDraft(
                    title: sourceGoal.title,
                    deadline: sourceGoal.deadline,
                    category: sourceGoal.category,
                    currentLevel: sourceGoal.currentLevel,
                    focusAreas: "derivatives, integrals, limits",
                    sourceDocuments: sourceGoal.sourceDocuments,
                    preferredQuestionStyle: sourceGoal.preferredQuestionStyle,
                    minimumQuestionDifficulty: sourceGoal.minimumQuestionDifficulty
                )
            )
        )
        guard case let .eligible(plan) = store.prepareGoalProfileMutation(request) else {
            return XCTFail("Expected an eligible context-changing edit")
        }

        XCTAssertEqual(
            store.commitGoalProfileMutation(using: plan),
            .committed(resultingGoalID: sourceGoal.id)
        )

        for _ in 0..<100 {
            if !engine.receivedRequests.isEmpty,
               !store.isPreparingActiveGoalQuestions,
               !store.isQuestionBankTopOffInProgress {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let retainedQuestion = try XCTUnwrap(
            store.questions.first {
                $0.id == linkedQuestion.id && $0.goalID == sourceGoal.id
            }
        )
        let retainedQuestionIDs = Set(store.questions.map(\.id))
        let topOffRequest = try XCTUnwrap(engine.receivedRequests.first)
        XCTAssertEqual(store.goal?.focusAreas, "derivatives, integrals, limits")
        XCTAssertEqual(
            Set(topOffRequest.existingQuestions.map(\.id)),
            existingQuestionIDs
        )
        XCTAssertTrue(existingQuestionIDs.isSubset(of: retainedQuestionIDs))
        XCTAssertTrue(retainedQuestionIDs.contains(linkedAttempt.questionID))
        XCTAssertTrue(retainedQuestionIDs.contains(linkedReport.questionID))
        XCTAssertTrue(store.attempts.contains { $0.id == linkedAttempt.id })
        XCTAssertTrue(store.questionReports.contains { $0.id == linkedReport.id })
        XCTAssertEqual(retainedQuestion.prompt, linkedQuestion.prompt)

        if let skillMap = store.goal?.derivedSkillMap,
           SkillMapReconciler.skillMapTopic(
               matching: retainedQuestion,
               in: skillMap
           ) == nil {
            XCTAssertEqual(
                retainedQuestion.status,
                .retired,
                "A historical question outside the edited context must be retained but retired."
            )
        }
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

    func testGoalDeletionConfirmationPresentationUsesExactProtectionCopy() {
        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        let sourceGoal = Goal(
            title: "Prepare for interviews",
            deadline: deadline,
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "systems",
            preferredQuestionStyle: .multipleChoice
        )
        let replacementGoal = Goal(
            title: "Prepare for calculus final",
            deadline: deadline.addingTimeInterval(86_400),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "integrals",
            preferredQuestionStyle: .multipleChoice
        )
        let request = GoalProfileMutationRequest(
            operation: .delete(goalID: sourceGoal.id)
        )
        let readyPlan = GoalProfileMutationPlan(
            request: request,
            sourceGoal: sourceGoal,
            sourceReadiness: .ready(selectableCount: 5, requiredCount: 5),
            targetGoal: sourceGoal,
            resultingActiveGoal: replacementGoal,
            resultingReadiness: .ready(selectableCount: 5, requiredCount: 5)
        )
        let unreadyPlan = GoalProfileMutationPlan(
            request: request,
            sourceGoal: sourceGoal,
            sourceReadiness: .ready(selectableCount: 5, requiredCount: 5),
            targetGoal: sourceGoal,
            resultingActiveGoal: replacementGoal,
            resultingReadiness: .incomplete(selectableCount: 3, requiredCount: 5)
        )
        let finalGoalPlan = GoalProfileMutationPlan(
            request: request,
            sourceGoal: sourceGoal,
            sourceReadiness: .ready(selectableCount: 5, requiredCount: 5),
            targetGoal: sourceGoal,
            resultingActiveGoal: nil,
            resultingReadiness: nil
        )
        let goals = [sourceGoal, replacementGoal]

        let ready = GoalDeletionConfirmationPresentation(
            confirmation: GoalProfileMutationConfirmation(
                plan: readyPlan,
                consent: .deletion,
                activeBreakAtRequest: true
            ),
            goals: goals
        )
        XCTAssertEqual(ready.title, "Delete current goal?")
        XCTAssertEqual(
            ready.message,
            "Delete “Prepare for interviews” and make “Prepare for calculus final” current? All progress for the deleted goal will be removed. This can't be undone."
        )
        XCTAssertEqual(ready.confirmationButtonTitle, "Delete goal")
        XCTAssertEqual(ready.cancelButtonTitle, "Keep goal")

        let duringBreak = GoalDeletionConfirmationPresentation(
            confirmation: GoalProfileMutationConfirmation(
                plan: unreadyPlan,
                consent: .deletionAndProtection(.preventsRelockAfterBreak),
                activeBreakAtRequest: true
            ),
            goals: goals
        )
        XCTAssertEqual(duringBreak.title, "Delete goal before this break ends?")
        XCTAssertEqual(
            duringBreak.message,
            "Your current break will continue. Protection will return when it ends only if “Prepare for calculus final” has a full checkpoint ready; otherwise it will turn off and you'll need to start it again. Right now, it has 3 of 5 questions ready. Deleting “Prepare for interviews” can't be undone."
        )
        XCTAssertEqual(duringBreak.confirmationButtonTitle, "Delete goal")
        XCTAssertEqual(duringBreak.cancelButtonTitle, "Keep goal")

        let finalGoal = GoalDeletionConfirmationPresentation(
            confirmation: GoalProfileMutationConfirmation(
                plan: finalGoalPlan,
                consent: .deletionAndProtection(.turnsOffImmediately),
                activeBreakAtRequest: true
            ),
            goals: [sourceGoal]
        )
        XCTAssertEqual(finalGoal.title, "Delete goal and end this break?")
        XCTAssertEqual(
            finalGoal.message,
            "Delete “Prepare for interviews” and all of its progress? Because this is your only goal, app protection and your current break will end. This can't be undone."
        )
        XCTAssertEqual(finalGoal.confirmationButtonTitle, "Delete and end break")
        XCTAssertEqual(finalGoal.cancelButtonTitle, "Keep goal")
    }

}
