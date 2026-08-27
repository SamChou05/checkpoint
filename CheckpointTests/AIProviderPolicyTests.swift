import XCTest
@testable import Checkpoint

// MARK: - AI provider policy

final class AIProviderPolicyTests: XCTestCase {
    @MainActor
    func testPersistedApplePreferenceMigratesBackToBackendAutomatic() {
        let suiteName = "AIProviderPolicyMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CheckpointStore(defaults: defaults)
        store.updateAIProviderPreference(.appleFoundation)
        XCTAssertEqual(store.aiProviderPreference, .appleFoundation)

        let reloadedStore = CheckpointStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.aiProviderPreference, .automatic)
    }

    func testAutomaticProviderUsesBackendWithoutTryingApple() async {
        let goal = makeGoal()
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: StaticQuestionEngine(
                provider: .backend,
                questions: (1...5).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "backend") }
            ),
            appleFoundationEngine: appleEngine
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .automatic
        )

        XCTAssertEqual(batch.provider, .backend)
        XCTAssertEqual(batch.questions.first?.sourcePrompt, "backend")
        XCTAssertNil(batch.failure)
        XCTAssertFalse(batch.usedFallback)
        XCTAssertTrue(appleEngine.receivedRequests.isEmpty)
    }

    func testAutomaticProviderReturnsServiceUnavailableWhenNoAIProviderIsAvailable() async {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            backendEngine: UnavailableQuestionEngine(provider: .backend),
            appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal),
            preference: .automatic
        )

        XCTAssertEqual(batch.provider, .backend)
        XCTAssertTrue(batch.questions.isEmpty)
        XCTAssertEqual(batch.failure, .serviceUnavailable)
        XCTAssertFalse(batch.usedFallback)
    }

    func testAutomaticProviderReturnsServiceUnavailableWhenConfiguredProvidersAreUnavailable() async {
        let goal = makeGoal()
        let appleEngine = CapturingQuestionEngine(provider: .appleFoundation)
        let engine = HybridQuestionEngine(
            backendEngine: UnavailableQuestionEngine(provider: .backend),
            appleFoundationEngine: appleEngine
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .automatic
        )

        XCTAssertEqual(batch.provider, .backend)
        XCTAssertTrue(batch.questions.isEmpty)
        XCTAssertEqual(batch.failure, .serviceUnavailable)
        XCTAssertFalse(batch.usedFallback)
        XCTAssertTrue(appleEngine.receivedRequests.isEmpty)
    }

    func testSafetyInterventionProducesCalmNonRetryingEditPath() async {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            backendEngine: SafetyInterventionQuestionEngine(provider: .backend),
            appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .automatic
        )

        XCTAssertTrue(batch.questions.isEmpty)
        XCTAssertEqual(batch.failure, .safetyIntervention)
        XCTAssertEqual(batch.failure?.title, "Choose a different topic")
        XCTAssertTrue(batch.failure?.allowsEditingTopics == true)
        XCTAssertFalse(batch.failure?.allowsRetryWithoutChanges == true)
        XCTAssertTrue(batch.failure?.message.contains("Edit the goal or topics") == true)
    }

    func testBackendMapsControlled422ToSafetyIntervention() throws {
        let controlledResponse = try JSONSerialization.data(
            withJSONObject: [
                "error": "This request could not be processed safely.",
                "code": "safety_intervention"
            ]
        )

        XCTAssertEqual(
            BackendQuestionEngine.generationError(for: 422, responseBody: controlledResponse),
            .safetyIntervention
        )
        XCTAssertEqual(
            BackendQuestionEngine.generationError(
                for: 422,
                responseBody: Data(#"{"code":"different_error"}"#.utf8)
            ),
            .badResponse
        )
    }

    func testExplicitBackendPreferenceCanUseBackendWhenConfigured() async {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            backendEngine: StaticQuestionEngine(
                provider: .backend,
                questions: (1...5).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "backend") }
            ),
            appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .backend
        )

        XCTAssertEqual(batch.provider, .backend)
        XCTAssertEqual(batch.questions.first?.sourcePrompt, "backend")
        XCTAssertNil(batch.failure)
    }

    func testBackendProviderReturnsQualityRejectedForShortBatch() async {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            backendEngine: StaticQuestionEngine(
                provider: .backend,
                questions: (1...3).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "backend") }
            ),
            appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, targetCount: 5, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .backend
        )

        XCTAssertEqual(batch.provider, .backend)
        XCTAssertTrue(batch.questions.isEmpty)
        XCTAssertEqual(batch.failure, .qualityRejected)
        XCTAssertFalse(batch.usedFallback)
    }

    func testBackendProviderReturnsQualityRejectedForInvalidBatch() async {
        let goal = makeGoal()
        let invalidQuestions = (1...5).map { index in
            makeQuestion(
                goal: goal,
                index: index,
                prompt: "Invalid provider question \(index)",
                choices: ["Only", "three", "choices"],
                sourcePrompt: "backend"
            )
        }
        let engine = HybridQuestionEngine(
            backendEngine: StaticQuestionEngine(provider: .backend, questions: invalidQuestions),
            appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, targetCount: 5, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .backend
        )

        XCTAssertEqual(batch.provider, .backend)
        XCTAssertTrue(batch.questions.isEmpty)
        XCTAssertEqual(batch.failure, .qualityRejected)
        XCTAssertFalse(batch.usedFallback)
    }

    func testBatchIsAcceptedOnlyWhenFiveValidatedQuestionsRemain() async {
        let goal = makeGoal()
        let endpoint = URL(string: "https://example.com/ai")
        let fourQuestionEngine = HybridQuestionEngine(
            backendEngine: StaticQuestionEngine(
                provider: .backend,
                questions: (1...4).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "backend") }
            ),
            appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
        )
        let fiveQuestionEngine = HybridQuestionEngine(
            backendEngine: StaticQuestionEngine(
                provider: .backend,
                questions: (1...5).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "backend") }
            ),
            appleFoundationEngine: UnavailableQuestionEngine(provider: .appleFoundation)
        )

        let shortBatch = await fourQuestionEngine.generateQuestionBatch(
            for: makeRequest(goal: goal, targetCount: 5, backendEndpoint: endpoint),
            preference: .backend
        )
        let readyBatch = await fiveQuestionEngine.generateQuestionBatch(
            for: makeRequest(goal: goal, targetCount: 5, backendEndpoint: endpoint),
            preference: .backend
        )

        XCTAssertTrue(shortBatch.questions.isEmpty)
        XCTAssertEqual(shortBatch.failure, .qualityRejected)
        XCTAssertEqual(readyBatch.questions.count, 5)
        XCTAssertNil(readyBatch.failure)
    }

    func testBackendPreferenceWithoutEndpointReturnsServiceUnavailable() async {
        let goal = makeGoal()
        let batch = await HybridQuestionEngine().generateQuestionBatch(
            for: makeRequest(goal: goal, targetCount: 5),
            preference: .backend
        )

        XCTAssertEqual(batch.provider, .backend)
        XCTAssertTrue(batch.questions.isEmpty)
        XCTAssertEqual(batch.failure, .serviceUnavailable)
        XCTAssertFalse(batch.usedFallback)
    }

}
