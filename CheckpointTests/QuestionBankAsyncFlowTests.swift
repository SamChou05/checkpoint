import XCTest
@testable import Checkpoint

// MARK: - Asynchronous question bank flow

final class QuestionBankAsyncFlowTests: XCTestCase {
    func testQuestionBankEndpointsAreSiblingsOfGenerationEndpoint() throws {
        let generationEndpoint = try XCTUnwrap(
            URL(string: "https://api.example.com/prod/v1/questions")
        )

        XCTAssertEqual(
            BackendQuestionBankClient.questionBankEndpoint(
                operation: "ensure",
                generationEndpoint: generationEndpoint
            ).absoluteString,
            "https://api.example.com/prod/v1/question-banks/ensure"
        )
        XCTAssertEqual(
            BackendQuestionBankClient.questionBankEndpoint(
                operation: "claim",
                generationEndpoint: generationEndpoint
            ).absoluteString,
            "https://api.example.com/prod/v1/question-banks/claim"
        )
    }

    func testEnsurePayloadIncludesStableGoalIdentityAndWatermarks() throws {
        let goal = makeGoal()
        let request = makeRequest(
            goal: goal,
            targetCount: 80,
            backendEndpoint: URL(string: "https://api.example.com/prod/v1/questions")
        )
        let data = try JSONEncoder().encode(
            BackendQuestionRequest(
                request: request,
                targetCountOverride: 20,
                contextRevision: "0123456789abcdef",
                desiredCount: 80,
                lowWatermark: 10
            )
        )
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let goalPayload = try XCTUnwrap(payload["goal"] as? [String: Any])

        XCTAssertEqual(goalPayload["id"] as? String, goal.id.uuidString)
        XCTAssertEqual(payload["targetCount"] as? Int, 20)
        XCTAssertEqual(payload["contextRevision"] as? String, "0123456789abcdef")
        XCTAssertEqual(payload["desiredCount"] as? Int, 80)
        XCTAssertEqual(payload["lowWatermark"] as? Int, 10)
    }

    func testClaimedRemoteIDBecomesStableLocalQuestionID() throws {
        let goal = makeGoal()
        let remoteID = UUID()
        let data = Data(
            """
            {"questions":[{"remoteID":"\(remoteID.uuidString)","prompt":"Which option is correct?","expectedAnswer":"Correct","choices":["Correct","Wrong 1","Wrong 2","Wrong 3"],"explanation":"Because it is correct.","topic":"arrays","difficulty":2,"format":"Multiple Choice"}]}
            """.utf8
        )

        let response = try JSONDecoder().decode(BackendQuestionResponse.self, from: data)
        let question = try XCTUnwrap(response.questions.first?.makeQuestion(
            goalID: goal.id,
            sourcePrompt: "server bank"
        ))

        XCTAssertEqual(question.id, remoteID)
        XCTAssertEqual(question.remoteID, remoteID.uuidString)
    }

    func testClaimPayloadCarriesPersistedIdempotencyKey() throws {
        let claimID = UUID().uuidString
        let data = try JSONEncoder().encode(
            BackendQuestionBankClaimRequest(
                bankID: "bank-123",
                claimID: claimID,
                limit: BackendQuestionBankClient.maximumClaimCount
            )
        )
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(payload["bankID"] as? String, "bank-123")
        XCTAssertEqual(payload["claimID"] as? String, claimID)
        XCTAssertEqual(payload["limit"] as? Int, BackendQuestionBankClient.maximumClaimCount)
    }

    @MainActor
    func testQueuedInitialBankPersistsIntentWithoutInvokingSynchronousGeneration() async throws {
        let suiteName = "QuestionBankQueuedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "bank-queued",
                status: .queued,
                readyCount: 0,
                targetCount: ProductLimits.starterQuestionBankTargetCount
            )
        )
        let synchronousEngine = CapturingQuestionEngine(provider: .backend)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: synchronousEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: bankClient,
            defaults: defaults
        )
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")

        let goal = makeGoal()
        await store.createGoal(
            title: goal.title,
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            preferredQuestionStyle: goal.preferredQuestionStyle
        )

        XCTAssertTrue(store.activeQuestions.isEmpty)
        XCTAssertTrue(synchronousEngine.receivedRequests.isEmpty)
        let intent = try XCTUnwrap(store.questionBankSyncIntents.first)
        XCTAssertEqual(intent.bankID, "bank-queued")
        XCTAssertFalse(intent.claimID.isEmpty)
        XCTAssertEqual(intent.contextRevision.count, 16)
        XCTAssertEqual(bankClient.ensureRequests.first?.contextRevision, intent.contextRevision)
        XCTAssertEqual(bankClient.ensureRequests.first?.desiredCount, ProductLimits.starterQuestionBankTargetCount)
        XCTAssertEqual(bankClient.ensureRequests.first?.lowWatermark, 0)

        let snapshotData = try XCTUnwrap(defaults.data(forKey: AppSnapshotPersistence.primaryDefaultsKey))
        let snapshot = try JSONDecoder().decode(AppSnapshotEnvelope.self, from: snapshotData).snapshot
        XCTAssertEqual(snapshot.questionBankSyncIntents?.first, intent)
    }

    @MainActor
    func testMemberBankIsFinitePerAdaptiveContextRevision() async throws {
        let suiteName = "QuestionBankFiniteMemberTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "member-bank-queued",
                status: .queued,
                readyCount: 0,
                targetCount: ProductLimits.memberQuestionBankTargetCount
            )
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: CapturingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: bankClient,
            defaults: defaults
        )
        store.updateMembershipTier(.member)
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")

        let goal = makeGoal()
        await store.createGoal(
            title: goal.title,
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            preferredQuestionStyle: goal.preferredQuestionStyle
        )

        let ensure = try XCTUnwrap(bankClient.ensureRequests.first)
        XCTAssertEqual(ensure.desiredCount, ProductLimits.memberQuestionBankTargetCount)
        XCTAssertEqual(ensure.lowWatermark, 0)
    }

    @MainActor
    func testReadyClaimMergesByRemoteIDAndNeverCallsSynchronousEngine() async throws {
        let suiteName = "QuestionBankReadyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let goal = makeGoal()
        let remoteQuestions = (1...5).map { index -> CheckpointQuestion in
            let remoteID = UUID()
            var question = makeQuestion(goal: goal, index: index)
            question.id = remoteID
            question.remoteID = remoteID.uuidString
            return question
        }
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "bank-ready",
                status: .ready,
                readyCount: remoteQuestions.count,
                targetCount: ProductLimits.starterQuestionBankTargetCount
            ),
            defaultClaim: QuestionBankClaimReceipt(
                questions: remoteQuestions,
                status: .empty,
                readyCount: 0,
                targetCount: ProductLimits.starterQuestionBankTargetCount
            )
        )
        let synchronousEngine = CapturingQuestionEngine(provider: .backend)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: synchronousEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: bankClient,
            defaults: defaults
        )
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")

        await store.createGoal(
            title: goal.title,
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            preferredQuestionStyle: goal.preferredQuestionStyle
        )

        XCTAssertEqual(Set(store.activeQuestions.map(\.id)), Set(remoteQuestions.map(\.id)))
        XCTAssertEqual(store.activeQuestions.count, remoteQuestions.count)
        XCTAssertTrue(synchronousEngine.receivedRequests.isEmpty)
        XCTAssertFalse(bankClient.claimIDs.isEmpty)
        XCTAssertEqual(Set(bankClient.claimIDs).count, bankClient.claimIDs.count)
    }

    @MainActor
    func testMissingAsyncRouteFallsBackToSynchronousInitialCompatibilityPath() async throws {
        let suiteName = "QuestionBankRolloutFallbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "unused-bank",
                status: .empty,
                readyCount: 0,
                targetCount: ProductLimits.starterQuestionBankTargetCount
            ),
            ensureError: QuestionBankAPIError.bankNotFound
        )
        let synchronousEngine = TargetCountQuestionEngine(provider: .backend)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: synchronousEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: bankClient,
            defaults: defaults
        )
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")
        let goal = makeGoal()

        await store.createGoal(
            title: goal.title,
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            preferredQuestionStyle: goal.preferredQuestionStyle
        )

        XCTAssertGreaterThanOrEqual(store.activeQuestions.count, UnlockPolicy.default.questionsPerSession)
        XCTAssertEqual(synchronousEngine.receivedRequests.first?.targetCount, UnlockPolicy.default.questionsPerSession)
        XCTAssertTrue(store.questionBankSyncIntents.isEmpty)
    }

    @MainActor
    func testQuestionTopicFallbackUpgradesRemoteBankToStructuredRevision() async throws {
        let suiteName = "QuestionBankSuggestedMapTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let broadGoal = Goal(
            title: "Prepare for systems interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice
        )
        let topics = ["process scheduling", "virtual memory", "concurrency"]
        let remoteQuestions = (1...5).map { index -> CheckpointQuestion in
            let remoteID = UUID()
            var question = makeQuestion(
                goal: broadGoal,
                index: index,
                topic: topics[(index - 1) % topics.count]
            )
            question.id = remoteID
            question.remoteID = remoteID.uuidString
            return question
        }
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "bank-skill-map",
                status: .ready,
                readyCount: remoteQuestions.count,
                targetCount: ProductLimits.starterQuestionBankTargetCount
            ),
            defaultClaim: QuestionBankClaimReceipt(
                questions: remoteQuestions,
                status: .empty,
                readyCount: 0,
                targetCount: ProductLimits.starterQuestionBankTargetCount
            )
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: UnavailableQuestionEngine(provider: .backend),
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: bankClient,
            defaults: defaults
        )
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")

        await store.createGoal(
            title: broadGoal.title,
            deadline: broadGoal.deadline,
            category: broadGoal.category,
            currentLevel: broadGoal.currentLevel,
            focusAreas: broadGoal.focusAreas,
            preferredQuestionStyle: broadGoal.preferredQuestionStyle
        )

        XCTAssertEqual(store.goal?.derivedSkillMap?.status, .suggested)
        XCTAssertGreaterThan(bankClient.claimIDs.count, 1)
        XCTAssertEqual(Set(bankClient.ensureRequests.map(\.contextRevision)).count, 2)
        XCTAssertEqual(store.questionBankSyncIntents.first?.bankID, "bank-skill-map")
    }

    @MainActor
    func testPollingHandsOffWhenSkillWeightsRotateDuringQueuedEnsure() async throws {
        let suiteName = "QuestionBankWeightRotationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let focusTopics = ["argument analysis", "conditional logic", "reading structure"]
        let goal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: focusTopics.joined(separator: ", "),
            preferredQuestionStyle: .multipleChoice
        )
        let remoteQuestions = (1...ProductLimits.starterQuestionBankTargetCount).map { index -> CheckpointQuestion in
            let remoteID = UUID()
            var question = makeQuestion(
                goal: goal,
                index: index,
                topic: focusTopics[(index - 1) % focusTopics.count]
            )
            question.id = remoteID
            question.remoteID = remoteID.uuidString
            return question
        }
        let bankClient = WeightRotatingQuestionBankClient(questions: remoteQuestions)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: UnavailableQuestionEngine(provider: .backend),
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: bankClient,
            defaults: defaults,
            questionBankPollingDelaysNanoseconds: [1]
        )
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")

        await store.createGoal(
            title: goal.title,
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            preferredQuestionStyle: goal.preferredQuestionStyle
        )

        await bankClient.waitForSecondEnsureToStart()
        let competencyIndex = try XCTUnwrap(store.competencies.indices.first)
        store.competencies[competencyIndex].estimatedLevel = 5
        store.competencies[competencyIndex].attempts = 10
        store.competencies[competencyIndex].correct = 10
        await bankClient.releaseSecondEnsure()

        for _ in 0..<1_000 {
            let revisions = await bankClient.ensureContextRevisions()
            if revisions.count >= 4 && store.activeQuestions.count == remoteQuestions.count {
                break
            }
            await Task.yield()
        }

        let revisions = await bankClient.ensureContextRevisions()
        XCTAssertGreaterThanOrEqual(revisions.count, 4)
        XCTAssertEqual(revisions[0], revisions[1])
        XCTAssertNotEqual(revisions[1], revisions[2])
        XCTAssertEqual(revisions[2], revisions[3])
        XCTAssertEqual(store.activeQuestions.count, remoteQuestions.count)
        XCTAssertTrue(store.questionBankSyncIntents.isEmpty)
    }

    @MainActor
    func testPollingContinuesPastInitialBackoffWindowUntilBankIsReady() async throws {
        let suiteName = "QuestionBankLongPollingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let goal = makeGoal()
        let remoteQuestions = (1...ProductLimits.starterQuestionBankTargetCount).map { index -> CheckpointQuestion in
            let remoteID = UUID()
            var question = makeQuestion(goal: goal, index: index)
            question.id = remoteID
            question.remoteID = remoteID.uuidString
            return question
        }
        let bankClient = DelayedReadyQuestionBankClient(
            readyAfterEnsureCall: 7,
            questions: remoteQuestions
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: UnavailableQuestionEngine(provider: .backend),
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: bankClient,
            defaults: defaults,
            questionBankPollingDelaysNanoseconds: [1]
        )
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")

        await store.createGoal(
            title: goal.title,
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            preferredQuestionStyle: goal.preferredQuestionStyle
        )

        for _ in 0..<500 where store.activeQuestions.count < remoteQuestions.count {
            await Task.yield()
        }

        XCTAssertGreaterThanOrEqual(bankClient.ensureCallCount, 7)
        XCTAssertEqual(store.activeQuestions.count, remoteQuestions.count)
        XCTAssertTrue(store.questionBankSyncIntents.isEmpty)
    }

    @MainActor
    func testExhaustedFiniteBankStopsPollingBelowNominalLocalTarget() async throws {
        let suiteName = "QuestionBankFiniteExhaustionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let goal = makeGoal()
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "bank-exhausted",
                status: .empty,
                readyCount: 0,
                targetCount: ProductLimits.starterQuestionBankTargetCount
            )
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: UnavailableQuestionEngine(provider: .backend),
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: bankClient,
            defaults: defaults,
            questionBankPollingDelaysNanoseconds: [1]
        )
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")

        await store.createGoal(
            title: goal.title,
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            preferredQuestionStyle: goal.preferredQuestionStyle
        )

        XCTAssertEqual(bankClient.ensureRequests.count, 1)
        XCTAssertTrue(store.questionBankSyncIntents.isEmpty)
        XCTAssertTrue(bankClient.claimIDs.isEmpty)
    }

    @MainActor
    func testEmptyMemberBankIsTerminalAndStopsPolling() async throws {
        let suiteName = "QuestionBankMemberExhaustionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "bank-member-empty",
                status: .empty,
                readyCount: 0,
                targetCount: ProductLimits.memberQuestionBankTargetCount
            )
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: UnavailableQuestionEngine(provider: .backend),
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: bankClient,
            defaults: defaults,
            questionBankPollingDelaysNanoseconds: [1]
        )
        store.updateMembershipTier(.member)
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")
        let goal = makeGoal()
        store.goal = goal
        store.goalProfiles = [goal]

        await store.refreshQuestionBatch()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertEqual(bankClient.ensureRequests.count, 1)
        XCTAssertTrue(store.questionBankSyncIntents.isEmpty)
        XCTAssertTrue(bankClient.claimIDs.isEmpty)
        XCTAssertEqual(store.questionBatchState, .failed)
    }

    @MainActor
    func testEnsureErrorsStopTerminalPollingButRetainTransientIntent() async throws {
        let terminalSuiteName = "QuestionBankTerminalEnsureErrorTests.\(UUID().uuidString)"
        let terminalDefaults = try XCTUnwrap(UserDefaults(suiteName: terminalSuiteName))
        defer { terminalDefaults.removePersistentDomain(forName: terminalSuiteName) }
        let terminalClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "unused-terminal-bank",
                status: .queued,
                readyCount: 0,
                targetCount: ProductLimits.memberQuestionBankTargetCount
            ),
            ensureError: QuestionBankAPIError.unauthorized
        )
        let terminalStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: UnavailableQuestionEngine(provider: .backend),
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: terminalClient,
            defaults: terminalDefaults,
            questionBankPollingDelaysNanoseconds: [1]
        )
        terminalStore.updateMembershipTier(.member)
        terminalStore.updateAIProviderPreference(.backend)
        terminalStore.updateBackendEndpoint("https://api.example.com/prod/v1/questions")
        let terminalGoal = makeGoal()
        terminalStore.goal = terminalGoal
        terminalStore.goalProfiles = [terminalGoal]

        await terminalStore.refreshQuestionBatch()

        XCTAssertEqual(terminalClient.ensureRequests.count, 1)
        XCTAssertTrue(terminalStore.questionBankSyncIntents.isEmpty)
        XCTAssertEqual(terminalStore.questionBatchState, .failed)
        XCTAssertEqual(
            terminalStore.lastAIErrorMessage,
            QuestionBankAPIError.unauthorized.localizedDescription
        )

        let transientSuiteName = "QuestionBankTransientEnsureErrorTests.\(UUID().uuidString)"
        let transientDefaults = try XCTUnwrap(UserDefaults(suiteName: transientSuiteName))
        defer { transientDefaults.removePersistentDomain(forName: transientSuiteName) }
        let transientClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "unused-transient-bank",
                status: .queued,
                readyCount: 0,
                targetCount: ProductLimits.memberQuestionBankTargetCount
            ),
            ensureError: QuestionBankAPIError.rateLimited
        )
        let transientStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: UnavailableQuestionEngine(provider: .backend),
                appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: transientClient,
            defaults: transientDefaults,
            questionBankPollingDelaysNanoseconds: [60_000_000_000]
        )
        transientStore.updateMembershipTier(.member)
        transientStore.updateAIProviderPreference(.backend)
        transientStore.updateBackendEndpoint("https://api.example.com/prod/v1/questions")
        let transientGoal = makeGoal()
        transientStore.goal = transientGoal
        transientStore.goalProfiles = [transientGoal]

        await transientStore.refreshQuestionBatch()

        XCTAssertEqual(transientClient.ensureRequests.count, 1)
        XCTAssertEqual(transientStore.questionBankSyncIntents.count, 1)
        XCTAssertEqual(transientStore.questionBatchState, .idle)
        XCTAssertEqual(
            transientStore.lastAIErrorMessage,
            QuestionBankAPIError.rateLimited.localizedDescription
        )
    }

    @MainActor
    func testCachedSessionIsServedWithoutAnyQuestionBankNetworkCall() throws {
        let suiteName = "QuestionBankCacheFirstTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let goal = makeGoal()
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "unused-bank",
                status: .queued,
                readyCount: 0,
                targetCount: ProductLimits.memberQuestionBankTargetCount
            )
        )
        let store = CheckpointStore(questionBankClient: bankClient, defaults: defaults)
        store.updateMembershipTier(.member)
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = (1...UnlockPolicy.default.questionsPerSession).map {
            makeQuestion(goal: goal, index: $0)
        }

        let session = try XCTUnwrap(store.startManualCheckpointSession())

        XCTAssertEqual(session.questions.count, UnlockPolicy.default.questionsPerSession)
        XCTAssertTrue(bankClient.ensureRequests.isEmpty)
        XCTAssertTrue(bankClient.claimIDs.isEmpty)
    }
}

private actor WeightRotatingQuestionBankClient: QuestionBankSyncing {
    private var questions: [CheckpointQuestion]
    private var ensureRevisions: [String] = []
    private var secondEnsureStarted = false
    private var secondEnsureStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var secondEnsureRelease: CheckedContinuation<Void, Never>?

    init(questions: [CheckpointQuestion]) {
        self.questions = questions
    }

    func waitForSecondEnsureToStart() async {
        guard !secondEnsureStarted else { return }
        await withCheckedContinuation { continuation in
            secondEnsureStartWaiters.append(continuation)
        }
    }

    func releaseSecondEnsure() {
        secondEnsureRelease?.resume()
        secondEnsureRelease = nil
    }

    func ensureContextRevisions() -> [String] {
        ensureRevisions
    }

    func ensureQuestionBank(
        for request: QuestionGenerationRequest,
        contextRevision: String,
        desiredCount: Int,
        lowWatermark: Int
    ) async throws -> QuestionBankPreparationReceipt {
        ensureRevisions.append(contextRevision)
        let ensureCallCount = ensureRevisions.count
        if ensureCallCount == 2 {
            secondEnsureStarted = true
            let waiters = secondEnsureStartWaiters
            secondEnsureStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                secondEnsureRelease = continuation
            }
        }

        let isReady = ensureCallCount >= 4
        return QuestionBankPreparationReceipt(
            bankID: "bank-weight-rotation",
            status: isReady ? .ready : .queued,
            readyCount: isReady ? questions.count : 0,
            targetCount: desiredCount
        )
    }

    func claimQuestions(
        from bankID: String,
        claimID: String,
        limit: Int,
        for request: QuestionGenerationRequest
    ) async throws -> QuestionBankClaimReceipt {
        let claimedQuestions = Array(questions.prefix(limit))
        questions.removeFirst(claimedQuestions.count)
        return QuestionBankClaimReceipt(
            questions: claimedQuestions,
            status: questions.isEmpty ? .empty : .ready,
            readyCount: questions.count,
            targetCount: ProductLimits.starterQuestionBankTargetCount
        )
    }
}

private final class DelayedReadyQuestionBankClient: QuestionBankSyncing, @unchecked Sendable {
    private let readyAfterEnsureCall: Int
    private var questions: [CheckpointQuestion]
    private(set) var ensureCallCount = 0

    init(readyAfterEnsureCall: Int, questions: [CheckpointQuestion]) {
        self.readyAfterEnsureCall = readyAfterEnsureCall
        self.questions = questions
    }

    func ensureQuestionBank(
        for request: QuestionGenerationRequest,
        contextRevision: String,
        desiredCount: Int,
        lowWatermark: Int
    ) async throws -> QuestionBankPreparationReceipt {
        ensureCallCount += 1
        let isReady = ensureCallCount >= readyAfterEnsureCall
        return QuestionBankPreparationReceipt(
            bankID: "bank-delayed",
            status: isReady ? .ready : .queued,
            readyCount: isReady ? questions.count : 0,
            targetCount: desiredCount
        )
    }

    func claimQuestions(
        from bankID: String,
        claimID: String,
        limit: Int,
        for request: QuestionGenerationRequest
    ) async throws -> QuestionBankClaimReceipt {
        let claimedQuestions = Array(questions.prefix(limit))
        questions.removeFirst(claimedQuestions.count)
        return QuestionBankClaimReceipt(
            questions: claimedQuestions,
            status: questions.isEmpty ? .empty : .ready,
            readyCount: questions.count,
            targetCount: ProductLimits.starterQuestionBankTargetCount
        )
    }
}
