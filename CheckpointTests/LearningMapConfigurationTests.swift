import XCTest
@testable import Checkpoint

final class LearningMapConfigurationTests: CheckpointWorkflowTestCase {
    func testLegacyMapsAndObjectivesDecodeWithCompatibleDefaults() throws {
        let legacy = #"{"topics":[{"name":"Arrays"},{"name":"Recursion"},{"name":"Maps"}],"evolutionEnabled":false}"#.data(using: .utf8)!
        let map = try JSONDecoder().decode(GoalSkillMap.self, from: legacy)
        XCTAssertEqual(map.growthMode, .manual)
        XCTAssertFalse(map.evolutionEnabled)
        XCTAssertEqual(map.topics[0].detail, "")
        XCTAssertEqual(map.topics[0].practiceEmphasis, .balanced)
        XCTAssertEqual(map.topics[0].challenge, .adaptive)
        XCTAssertFalse(map.topics[0].isPaused)
        let objective = try JSONDecoder().decode(SkillMapObjective.self, from: #"{"name":"Trace the loop"}"#.data(using: .utf8)!)
        XCTAssertEqual(objective.detail, "")
    }

    func testConfigurationAndPendingSuggestionRoundTrip() throws {
        var topics = makeTopics()
        topics[0].detail = "Reason about contiguous storage"
        topics[0].practiceEmphasis = .focus
        topics[0].challenge = .stretch
        topics[1].isPaused = true
        topics[0].objectives[0].detail = "Include empty input"
        var map = GoalSkillMap(topics: topics, growthMode: .reviewSuggestions)
        map.pendingEvolutionSuggestion = PendingSkillMapEvolutionSuggestion(
            baseVersion: map.version,
            baseMapFingerprint: "fingerprint",
            topics: topics,
            replacements: [PendingSkillMapReplacement(predecessorSkillID: topics[0].id, successorSkillID: UUID())]
        )
        let restored = try JSONDecoder().decode(GoalSkillMap.self, from: JSONEncoder().encode(map))
        XCTAssertEqual(restored, map)
        XCTAssertEqual(restored.growthMode, .reviewSuggestions)
        XCTAssertTrue(restored.evolutionEnabled)
    }

    @MainActor
    func testValidationRejectsAllPausedAndDuplicateFocusPointIdentities() {
        var topics = makeTopics()
        for index in topics.indices { topics[index].isPaused = true }
        XCTAssertNotNil(SkillMapReconciler.learningMapValidationError(topics: topics))
        topics[0].isPaused = false
        XCTAssertNil(SkillMapReconciler.learningMapValidationError(topics: topics))
        topics[1].objectives[0].id = topics[0].objectives[0].id
        XCTAssertNotNil(SkillMapReconciler.learningMapValidationError(topics: topics))
    }

    @MainActor
    func testConfigurationChangesGenerationSignatureWithoutChangingLegacyFingerprint() {
        let topics = makeTopics()
        var configured = topics
        configured[0].detail = "Prefer applied examples"
        configured[0].objectives[0].detail = "Test edge cases"
        configured[0].challenge = .stretch
        configured[1].isPaused = true
        XCTAssertNotEqual(SkillMapReconciler.skillMapContentSignature(topics: topics), SkillMapReconciler.skillMapContentSignature(topics: configured))
        XCTAssertEqual(SkillMapReconciler.skillMapFingerprint(topics: topics), SkillMapReconciler.skillMapFingerprint(topics: configured))
    }

    @MainActor
    func testRenamePreservesHistoryAndRejectsStaleSave() throws {
        let fixture = makeFixture()
        let original = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        var topics = original.topics
        topics[0].name = "Array traversal"
        topics[0].practiceEmphasis = .focus
        XCTAssertTrue(fixture.store.updateLearningMap(goalID: fixture.goal.id, expectedMap: original, topics: topics, growthMode: .manual))
        let edited = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        XCTAssertEqual(edited.topics[0].id, original.topics[0].id)
        XCTAssertEqual(edited.topics[0].practiceEmphasis, .focus)
        XCTAssertTrue(edited.topics[0].aliases.contains(original.topics[0].name))
        XCTAssertEqual(fixture.store.competencies.first { $0.skillID == topics[0].id }?.attempts, 10)
        XCTAssertFalse(fixture.store.questions.filter { $0.skillID == topics[0].id }.contains { $0.status == .retired })
        XCTAssertFalse(fixture.store.updateLearningMap(goalID: fixture.goal.id, expectedMap: original, topics: original.topics, growthMode: .automatic))
        XCTAssertEqual(fixture.store.goal?.derivedSkillMap, edited)
    }

    @MainActor
    func testReplacementArchivesOldBranchWithoutAwardingMastery() throws {
        let fixture = makeFixture()
        let original = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        var topics = original.topics
        let predecessor = topics[0]
        topics[0] = SkillMapTopic(name: "Dynamic programming", objectives: [SkillMapObjective(name: "Define a state")], stage: predecessor.stage + 1, predecessorIDs: [predecessor.id])
        XCTAssertTrue(fixture.store.updateLearningMap(goalID: fixture.goal.id, expectedMap: original, topics: topics, growthMode: .manual))
        let map = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        let archived = try XCTUnwrap(map.archivedTopics.first)
        XCTAssertEqual(archived.reason, .userReplaced)
        XCTAssertEqual(archived.successorSkillIDs, [topics[0].id])
        XCTAssertEqual(archived.mastery?.attempts, 10)
        XCTAssertEqual(fixture.store.competencies.first { $0.skillID == topics[0].id }?.attempts, 0)
        XCTAssertTrue(fixture.store.questions.filter { $0.skillID == predecessor.id }.allSatisfy { $0.status == .retired })
    }

    @MainActor
    func testFocusPointEditsRetireStaleQuestionsAndPreserveSkillEvidence() throws {
        let fixture = makeFixture()
        let original = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        var topics = original.topics
        topics[0].objectives[0].detail = "Include sorted and unsorted input"
        XCTAssertTrue(fixture.store.updateLearningMap(goalID: fixture.goal.id, expectedMap: original, topics: topics, growthMode: .manual))
        XCTAssertTrue(fixture.store.questions.filter { $0.skillID == topics[0].id }.allSatisfy { $0.status == .retired })
        XCTAssertEqual(fixture.store.competencies.first { $0.skillID == topics[0].id }?.attempts, 10)
    }

    @MainActor
    func testPauseAndEmphasisAffectQuestionSelection() {
        var topics = makeTopics()
        topics[0].isPaused = true
        topics[2].practiceEmphasis = .focus
        var goal = makeGoal()
        goal.derivedSkillMap = GoalSkillMap(topics: topics)
        let questions = topics.enumerated().map { index, topic in
            makeQuestion(goal: goal, index: index, topic: topic.name, skillID: topic.id, objectiveID: topic.objectives[0].id)
        }
        let selector = CheckpointQuestionSelector(questions: questions, goalProfiles: [goal], currentGoal: goal, competencies: [], activeQuestionDifficulty: 1, maximumExactQuestionAskCount: 5)
        XCTAssertFalse(selector.isSelectableQuestion(questions[0]))
        XCTAssertEqual(selector.nextQuestion()?.skillID, topics[2].id)
        XCTAssertFalse(selector.nextQuestions(limit: 3).contains { $0.skillID == topics[0].id })
    }

    func testChallengeProducesRealDifficultyTargetsAndExcludesPausedSkills() {
        var topics = makeTopics()
        topics[0].challenge = .foundations
        topics[1].challenge = .stretch
        topics[2].isPaused = true
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 2
        goal.derivedSkillMap = GoalSkillMap(topics: topics)
        let plans = AdaptiveLearningPolicy.plans(for: goal, attempts: [])
        XCTAssertEqual(plans.first { $0.skillID == topics[0].id }?.targetDifficulty, 2)
        XCTAssertEqual(plans.first { $0.skillID == topics[1].id }?.targetDifficulty, 3)
        XCTAssertNil(plans.first { $0.skillID == topics[2].id })
    }

    @MainActor
    func testConfiguredAllocationReachesGenerationAndExcludesPausedSkills() async throws {
        let fixture = makeFixture()
        let original = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        var topics = original.topics
        fixture.store.competencies = original.topics.map {
            TopicCompetency.initial(topic: $0.name, goalID: fixture.goal.id, skillID: $0.id)
        }
        fixture.store.attempts = []
        topics[0].practiceEmphasis = .focus
        topics[1].practiceEmphasis = .maintain
        topics[1].challenge = .foundations
        topics[2].isPaused = true
        XCTAssertTrue(fixture.store.updateLearningMap(goalID: fixture.goal.id, expectedMap: original, topics: topics, growthMode: .manual))
        let generated = await waitUntil { !fixture.engine.generationRequests.isEmpty }
        XCTAssertTrue(generated)
        let request = try XCTUnwrap(fixture.engine.generationRequests.last)
        XCTAssertNil(request.desiredSkillAllocation[topics[2].id])
        XCTAssertGreaterThan(try XCTUnwrap(request.desiredSkillAllocation[topics[0].id]), try XCTUnwrap(request.desiredSkillAllocation[topics[1].id]))
        XCTAssertEqual(request.adaptiveSkillPlans.first { $0.skillID == topics[1].id }?.targetDifficulty, fixture.goal.minimumQuestionDifficulty)
        XCTAssertEqual(request.goal.derivedSkillMap?.topics[0].practiceEmphasis, .focus)
    }

    @MainActor
    func testReviewModePersistsProposalWithoutAdvancingThenAcceptsExactRevision() async throws {
        let fixture = makeFixture(growthMode: .reviewSuggestions)
        let original = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let proposed = await waitUntil { fixture.store.goal?.derivedSkillMap?.pendingEvolutionSuggestion != nil }
        XCTAssertTrue(proposed)
        let suggestedMap = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        XCTAssertEqual(suggestedMap.version, original.version)
        XCTAssertEqual(suggestedMap.topics, original.topics)
        XCTAssertTrue(suggestedMap.archivedTopics.isEmpty)
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        XCTAssertFalse(fixture.store.acceptLearningMapSuggestion(goalID: fixture.goal.id, expectedMap: original))
        XCTAssertTrue(fixture.store.acceptLearningMapSuggestion(goalID: fixture.goal.id, expectedMap: suggestedMap))
        let advanced = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        XCTAssertEqual(advanced.version, original.version + 1)
        XCTAssertNil(advanced.pendingEvolutionSuggestion)
        XCTAssertEqual(advanced.archivedTopics.first?.reason, .mastered)
        XCTAssertFalse(fixture.store.acceptLearningMapSuggestion(goalID: fixture.goal.id, expectedMap: suggestedMap))
    }

    @MainActor
    func testDismissalKeepsCurrentPlanAndDoesNotRepeatSuggestion() async throws {
        let fixture = makeFixture(growthMode: .reviewSuggestions)
        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let proposed = await waitUntil { fixture.store.goal?.derivedSkillMap?.pendingEvolutionSuggestion != nil }
        XCTAssertTrue(proposed)
        let original = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        XCTAssertTrue(fixture.store.dismissLearningMapSuggestion(goalID: fixture.goal.id, expectedMap: original))
        XCTAssertEqual(fixture.store.goal?.derivedSkillMap?.topics, original.topics)
        XCTAssertNil(fixture.store.goal?.derivedSkillMap?.pendingEvolutionSuggestion)
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        XCTAssertEqual(fixture.engine.evolutionRequests.count, 1)
    }

    @MainActor
    func testManualModeAndPausedSkillsNeverAdvance() throws {
        let fixture = makeFixture(growthMode: .manual)
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        var goal = fixture.goal
        goal.derivedSkillMap?.growthMode = .automatic
        goal.derivedSkillMap?.topics[0].isPaused = true
        fixture.store.goal = goal
        fixture.store.goalProfiles = [goal]
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
    }

    @MainActor
    func testPausedSkillIsExcludedFromSharedNextFocusRecommendation() throws {
        let fixture = makeFixture()
        var goal = fixture.goal
        goal.derivedSkillMap?.topics[0].isPaused = true
        goal.derivedSkillMap?.topics[1].practiceEmphasis = .focus
        fixture.store.goal = goal
        fixture.store.goalProfiles = [goal]
        let recommendation = try XCTUnwrap(fixture.store.studyFocusRecommendation)
        XCTAssertEqual(recommendation.skillID, goal.derivedSkillMap?.topics[1].id)
    }

    @MainActor
    func testEditingDoesNotChangeTheLiveSessionAndRetiredQuestionStaysRetired() throws {
        let fixture = makeFixture()
        let session = CheckpointSession(questions: fixture.store.questions, requiredCorrectAnswers: 1)
        fixture.store.activeCheckpointRun = ActiveCheckpointRun(session: session)
        let runningBeforeEdit = fixture.store.activeCheckpointRun
        let original = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        var topics = original.topics
        let question = try XCTUnwrap(session.questions.first)
        let topicIndex = try XCTUnwrap(topics.firstIndex { $0.id == question.skillID })
        topics[topicIndex].detail = "New practice scope"
        XCTAssertTrue(fixture.store.updateLearningMap(goalID: fixture.goal.id, expectedMap: original, topics: topics, growthMode: .manual))
        XCTAssertEqual(fixture.store.activeCheckpointRun, runningBeforeEdit)
        _ = fixture.store.submitAnswer(question: question, answer: question.expectedAnswer, result: .correct, grantsUnlock: false)
        XCTAssertEqual(fixture.store.questions.first { $0.id == question.id }?.status, .retired)
        XCTAssertEqual(fixture.store.activeCheckpointRun?.questionIDs, session.questions.map(\.id))
    }

    @MainActor
    func testMaximalMapReservesFocusCoverageWithoutExpandingFiniteRequestForEmphasis() {
        let fixture = makeFixture()
        var goal = fixture.goal
        goal.derivedSkillMap?.topics = (0..<6).map { index in
            SkillMapTopic(
                name: "Configured skill \(index)",
                objectives: (0..<5).map { SkillMapObjective(name: "Focus \(index)-\($0)") },
                practiceEmphasis: index == 0 ? .maintain : .focus
            )
        }
        fixture.store.goal = goal
        fixture.store.goalProfiles = [goal]
        XCTAssertEqual(fixture.store.remoteQuestionBankDesiredCount(for: goal, localDeficit: 40), 40)
        XCTAssertEqual(fixture.store.remoteQuestionBankDesiredCount(for: goal, localDeficit: 1), 30)
        for index in 1..<6 { goal.derivedSkillMap?.topics[index].isPaused = true }
        fixture.store.goal = goal
        fixture.store.goalProfiles = [goal]
        XCTAssertEqual(fixture.store.remoteQuestionBankDesiredCount(for: goal, localDeficit: 1), 5)
    }

    func testReviewPreferenceNeverEncodesLegacyPermissionToAutoAdvance() throws {
        let map = GoalSkillMap(topics: makeTopics(), growthMode: .reviewSuggestions)
        let data = try JSONEncoder().encode(map)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["evolutionEnabled"] as? Bool, false)
        let decoded = try JSONDecoder().decode(GoalSkillMap.self, from: data)
        XCTAssertEqual(decoded.growthMode, .reviewSuggestions)
        XCTAssertTrue(decoded.evolutionEnabled)
    }

    @MainActor
    func testEditedFocusPointNamesNormalizeWithoutReplacingTheirIdentity() {
        let original = GoalSkillMap(topics: makeTopics())
        var topics = original.topics
        let objectiveID = topics[0].objectives[0].id
        topics[0].objectives[0].name = "  Compare   approaches  "
        topics[0].objectives[0].detail = "  Check edge cases  "
        let reviewed = SkillMapReconciler.reviewedSkillMapTopics(topics, preserving: original)
        XCTAssertEqual(reviewed[0].objectives[0].id, objectiveID)
        XCTAssertEqual(reviewed[0].objectives[0].name, "Compare approaches")
        XCTAssertEqual(reviewed[0].objectives[0].detail, "Check edge cases")
    }

    @MainActor
    func testDescriptionPunctuationCannotHideAChangedGenerationContext() {
        var first = makeTopics()
        first[0].name = "Array:traversal"
        first[0].detail = "Practice carefully"
        var second = first
        second[0].name = "Array"
        second[0].detail = "traversal:Practice carefully"
        XCTAssertNotEqual(
            SkillMapReconciler.skillMapContentSignature(topics: first),
            SkillMapReconciler.skillMapContentSignature(topics: second)
        )
    }

    @MainActor
    func testSuggestionPreflightExplainsLiveCheckpointAndExpiredEvidence() async throws {
        let fixture = makeFixture(growthMode: .reviewSuggestions)
        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let proposed = await waitUntil { fixture.store.goal?.derivedSkillMap?.pendingEvolutionSuggestion != nil }
        XCTAssertTrue(proposed)
        let map = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        XCTAssertNil(fixture.store.learningMapSuggestionAcceptanceIssue(goalID: fixture.goal.id, expectedMap: map))
        let session = CheckpointSession(questions: fixture.store.questions, requiredCorrectAnswers: 1)
        fixture.store.activeCheckpointRun = ActiveCheckpointRun(session: session)
        XCTAssertEqual(fixture.store.learningMapSuggestionAcceptanceIssue(goalID: fixture.goal.id, expectedMap: map), .checkpointInProgress)
        fixture.store.activeCheckpointRun = nil
        for index in fixture.store.attempts.indices {
            fixture.store.attempts[index].createdAt = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        }
        XCTAssertEqual(fixture.store.learningMapSuggestionAcceptanceIssue(goalID: fixture.goal.id, expectedMap: map), .needsPractice)
        XCTAssertFalse(fixture.store.acceptLearningMapSuggestion(goalID: fixture.goal.id, expectedMap: map))
        XCTAssertEqual(fixture.store.goal?.derivedSkillMap, map)
        fixture.store.membershipTier = .starter
        XCTAssertEqual(fixture.store.learningMapSuggestionAcceptanceIssue(goalID: fixture.goal.id, expectedMap: map), .membershipRequired)
    }

    private func makeTopics() -> [SkillMapTopic] {
        ["Arrays", "Recursion", "Hash maps"].map {
            SkillMapTopic(name: $0, objectives: [SkillMapObjective(name: "Apply \($0)"), SkillMapObjective(name: "Explain \($0)")])
        }
    }

    @MainActor
    private func makeFixture(growthMode: SkillMapGrowthMode = .manual) -> (store: CheckpointStore, goal: Goal, engine: ConfigurationQuestionEngine) {
        let engine = ConfigurationQuestionEngine()
        let topics = makeTopics()
        var goal = makeGoal()
        goal.derivedSkillMap = GoalSkillMap(topics: topics, status: .reviewed, growthMode: growthMode)
        let store = CheckpointStore(questionEngine: HybridQuestionEngine(backendEngine: engine, appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)), defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.updateAIProviderPreference(.backend)
        store.membershipTier = .member
        store.questions = topics.enumerated().map { index, topic in
            makeQuestion(goal: goal, index: index, topic: topic.name, skillID: topic.id, objectiveID: topic.objectives[0].id, objective: topic.objectives[0].name, difficulty: 3)
        }
        store.competencies = topics.enumerated().map { index, topic in
            var competency = TopicCompetency.initial(topic: topic.name, estimatedLevel: index == 0 ? 5 : 1.5, goalID: goal.id, skillID: topic.id)
            if index == 0 {
                competency.attempts = 10
                competency.correct = 10
                competency.currentStreak = 10
                competency.lastResult = .correct
                competency.lastPracticedAt = Date()
            }
            return competency
        }
        store.attempts = (0..<10).map { index in
            CheckpointAttempt(questionID: UUID(), goalID: goal.id, skillID: topics[0].id, objectiveID: topics[0].objectives[index % 2].id, questionDifficulty: 4, questionVerificationVersion: 1, prompt: "Distinct evidence \(index)", answer: "Correct", result: .correct, unlockMinutes: 0, createdAt: Date().addingTimeInterval(-Double(index * 60)))
        }
        return (store, goal, engine)
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}

private final class ConfigurationQuestionEngine: QuestionGenerating, SkillMapEvolving, @unchecked Sendable {
    let provider: AIProviderKind = .backend
    private(set) var generationRequests: [QuestionGenerationRequest] = []
    private(set) var evolutionRequests: [SkillMapEvolutionRequest] = []

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        generationRequests.append(request)
        return []
    }

    func evolveSkillMap(for request: SkillMapEvolutionRequest) async throws -> SkillMapEvolutionProposal {
        evolutionRequests.append(request)
        guard let map = request.goal.derivedSkillMap else { throw QuestionGenerationError.badResponse }
        var topics = map.topics
        var replacements: [SkillMapEvolutionReplacement] = []
        for predecessor in request.masteredSkillIDs {
            guard let index = topics.firstIndex(where: { $0.id == predecessor }) else { throw QuestionGenerationError.badResponse }
            let successor = SkillMapTopic(name: "Applied \(topics[index].name)", objectives: [SkillMapObjective(name: "Analyze a novel example"), SkillMapObjective(name: "Compare approaches")])
            topics[index] = successor
            replacements.append(SkillMapEvolutionReplacement(predecessorSkillID: predecessor, successorSkillID: successor.id))
        }
        return SkillMapEvolutionProposal(baseMapFingerprint: request.baseMapFingerprint, baseVersion: map.version, topics: topics, replacements: replacements)
    }
}
