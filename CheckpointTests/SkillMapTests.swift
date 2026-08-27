import XCTest
@testable import Checkpoint

final class SkillMapTests: CheckpointWorkflowTestCase {
    // MARK: - Skill maps and adaptive scheduling

    @MainActor
    func testInitialGenerationPersistsFirstClassSkillMapBeforeRequestingQuestions() async throws {
        let inferredMap = GoalSkillMap(
            topics: [
                SkillMapTopic(
                    name: "argument analysis",
                    objectives: [SkillMapObjective(name: "Identify conclusions")]
                ),
                SkillMapTopic(
                    name: "conditional logic",
                    objectives: [SkillMapObjective(name: "Translate conditionals")]
                ),
                SkillMapTopic(
                    name: "reading structure",
                    objectives: [SkillMapObjective(name: "Trace passage structure")]
                ),
                SkillMapTopic(
                    name: "evidence evaluation",
                    objectives: [SkillMapObjective(name: "Evaluate support")]
                )
            ],
            status: .suggested,
            provenance: .backendInferred
        )
        let backendEngine = FirstClassSkillMapQuestionEngine(skillMap: inferredMap)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.backend)

        await store.createGoal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Strong reader who has not studied formal logic",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertEqual(backendEngine.events.prefix(2), ["inference", "generation"])
        let firstRequest = try XCTUnwrap(backendEngine.receivedRequests.first)
        let storedMap = try XCTUnwrap(store.goal?.derivedSkillMap)
        XCTAssertEqual(storedMap.provenance, .backendInferred)
        XCTAssertEqual(firstRequest.goal.derivedSkillMap, storedMap)
        XCTAssertEqual(Set(firstRequest.desiredSkillAllocation.values), [12])
        XCTAssertEqual(
            Set(firstRequest.desiredSkillAllocation.keys),
            Set(storedMap.topics.map(\.id))
        )
        XCTAssertTrue(
            store.activeQuestions.allSatisfy { question in
                question.skillID != nil &&
                    storedMap.topics.contains { $0.id == question.skillID }
            }
        )
    }

    @MainActor
    func testConfirmingUnchangedSkillMapUpdatesMetadataWithoutRegenerating() async throws {
        let topics = ["argument analysis", "conditional logic", "reading structure"].map {
            SkillMapTopic(name: $0, objectives: [SkillMapObjective(name: $0)])
        }
        let suggestedMap = GoalSkillMap(
            topics: topics,
            status: .suggested,
            version: 4,
            provenance: .backendInferred
        )
        let goal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "timed sections",
            derivedSkillMap: suggestedMap,
            preferredQuestionStyle: .multipleChoice
        )
        let backendEngine = CapturingQuestionEngine(provider: .backend)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = (0..<5).map { index in
            let skill = topics[index % topics.count]
            return makeQuestion(
                goal: goal,
                index: index,
                topic: skill.name,
                skillID: skill.id
            )
        }

        store.confirmActiveDerivedSkillMap()

        let confirmedGoal = try XCTUnwrap(store.goal)
        let confirmedMap = try XCTUnwrap(confirmedGoal.derivedSkillMap)
        XCTAssertEqual(confirmedMap.status, .reviewed)
        XCTAssertEqual(confirmedMap.version, suggestedMap.version)
        XCTAssertEqual(confirmedMap.provenance, .backendInferred)
        XCTAssertEqual(confirmedGoal.focusAreas, goal.focusAreas)

        let idempotentMap = confirmedMap
        XCTAssertTrue(store.reviewActiveDerivedSkillMap(topics: confirmedMap.topics))
        XCTAssertTrue(store.reviewActiveDerivedSkillMap(topics: confirmedMap.topics))
        XCTAssertEqual(store.goal?.derivedSkillMap, idempotentMap)

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(backendEngine.receivedRequests.isEmpty)
        XCTAssertFalse(store.isQuestionBankTopOffInProgress)
    }

    @MainActor
    func testAdaptiveSkillWeightsIgnoreInventoryAndRetainMasteredMaintenance() async throws {
        let weakSkill = SkillMapTopic(
            name: "argument analysis",
            objectives: [SkillMapObjective(name: "argument analysis")]
        )
        let newSkill = SkillMapTopic(
            name: "conditional logic",
            objectives: [SkillMapObjective(name: "conditional logic")]
        )
        let masteredSkill = SkillMapTopic(
            name: "reading structure",
            objectives: [SkillMapObjective(name: "reading structure")]
        )
        let skillMap = GoalSkillMap(
            topics: [weakSkill, newSkill, masteredSkill],
            status: .reviewed,
            provenance: .userEdited
        )
        let goal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "timed sections",
            derivedSkillMap: skillMap,
            preferredQuestionStyle: .multipleChoice
        )
        let backendEngine = CapturingQuestionEngine(provider: .backend)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateMembershipTier(.member)
        store.updateAIProviderPreference(.backend)
        store.goal = goal
        store.goalProfiles = [goal]
        var weak = TopicCompetency.initial(
            topic: weakSkill.name,
            goalID: goal.id,
            skillID: weakSkill.id
        )
        weak.attempts = 10
        weak.incorrect = 10
        var mastered = TopicCompetency.initial(
            topic: masteredSkill.name,
            estimatedLevel: 5,
            goalID: goal.id,
            skillID: masteredSkill.id
        )
        mastered.attempts = 10
        mastered.correct = 10
        store.competencies = [
            weak,
            .initial(topic: newSkill.name, goalID: goal.id, skillID: newSkill.id),
            mastered
        ]
        store.questions = (0..<12).map { index in
            makeQuestion(
                goal: goal,
                index: index,
                topic: weakSkill.name,
                skillID: weakSkill.id
            )
        }

        await store.refreshQuestionBatch()
        let firstWeights = try XCTUnwrap(backendEngine.receivedRequests.first?.desiredSkillAllocation)
        await store.refreshQuestionBatch()
        let secondWeights = try XCTUnwrap(backendEngine.receivedRequests.last?.desiredSkillAllocation)

        XCTAssertEqual(firstWeights, secondWeights)
        XCTAssertGreaterThan(firstWeights[weakSkill.id, default: 0], firstWeights[newSkill.id, default: 0])
        XCTAssertGreaterThan(firstWeights[newSkill.id, default: 0], firstWeights[masteredSkill.id, default: 0])
        XCTAssertGreaterThan(firstWeights[masteredSkill.id, default: 0], 0)
    }

    @MainActor
    func testDurableBankRevisionTracksSkillWeightsButNotQuestionInventory() async throws {
        let skills = ["argument analysis", "conditional logic", "reading structure"].map {
            SkillMapTopic(name: $0, objectives: [SkillMapObjective(name: $0)])
        }
        let skillMap = GoalSkillMap(
            topics: skills,
            status: .reviewed,
            provenance: .userEdited
        )
        let goal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "timed sections",
            derivedSkillMap: skillMap,
            preferredQuestionStyle: .multipleChoice
        )
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "weighted-bank",
                status: .queued,
                readyCount: 0,
                targetCount: ProductLimits.memberQuestionBankTargetCount
            )
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: bankClient,
            defaults: defaults,
            questionBankPollingDelaysNanoseconds: [60_000_000_000]
        )
        store.updateMembershipTier(.member)
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")
        store.goal = goal
        store.goalProfiles = [goal]
        store.competencies = skills.map {
            .initial(topic: $0.name, goalID: goal.id, skillID: $0.id)
        }
        store.questions = [
            makeQuestion(
                goal: goal,
                index: 1,
                topic: skills[0].name,
                skillID: skills[0].id
            )
        ]

        await store.refreshQuestionBatch()
        let originalRequest = try XCTUnwrap(bankClient.ensureRequests.last)

        store.questions.append(
            makeQuestion(
                goal: goal,
                index: 2,
                topic: skills[1].name,
                skillID: skills[1].id
            )
        )
        await store.refreshQuestionBatch()
        let inventoryChangedRequest = try XCTUnwrap(bankClient.ensureRequests.last)

        var mastered = try XCTUnwrap(store.competencies.first { $0.skillID == skills[0].id })
        mastered.attempts = 10
        mastered.correct = 10
        store.competencies.removeAll { $0.skillID == skills[0].id }
        store.competencies.append(mastered)
        await store.refreshQuestionBatch()
        let weightsChangedRequest = try XCTUnwrap(bankClient.ensureRequests.last)

        XCTAssertEqual(originalRequest.contextRevision, inventoryChangedRequest.contextRevision)
        XCTAssertNotEqual(inventoryChangedRequest.contextRevision, weightsChangedRequest.contextRevision)
        XCTAssertEqual(
            originalRequest.contextRevision.count,
            weightsChangedRequest.contextRevision.count
        )
    }

    @MainActor
    func testSkillMapEditRetiresRemovedSkillAndPreservesStableIdentityHistory() throws {
        let retainedSkill = SkillMapTopic(
            name: "argument analysis",
            objectives: [SkillMapObjective(name: "Identify conclusions")]
        )
        let removedSkill = SkillMapTopic(
            name: "conditional logic",
            objectives: [SkillMapObjective(name: "Translate conditionals")]
        )
        let thirdSkill = SkillMapTopic(
            name: "reading structure",
            objectives: [SkillMapObjective(name: "Trace passage structure")]
        )
        let initialMap = GoalSkillMap(
            topics: [retainedSkill, removedSkill, thirdSkill],
            status: .suggested,
            provenance: .backendInferred
        )
        let goal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "",
            derivedSkillMap: initialMap,
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.goal = goal
        store.goalProfiles = [goal]
        let retainedQuestion = makeQuestion(
            goal: goal,
            index: 1,
            topic: retainedSkill.name,
            skillID: retainedSkill.id,
            objectiveID: retainedSkill.objectives[0].id,
            objective: retainedSkill.objectives[0].name
        )
        let removedQuestion = makeQuestion(
            goal: goal,
            index: 2,
            topic: removedSkill.name,
            skillID: removedSkill.id,
            objectiveID: removedSkill.objectives[0].id,
            objective: removedSkill.objectives[0].name
        )
        let thirdQuestion = makeQuestion(
            goal: goal,
            index: 3,
            topic: thirdSkill.name,
            skillID: thirdSkill.id
        )
        store.questions = [retainedQuestion, removedQuestion, thirdQuestion]
        var retainedCompetency = TopicCompetency.initial(
            topic: retainedSkill.name,
            goalID: goal.id,
            skillID: retainedSkill.id
        )
        retainedCompetency.attempts = 4
        retainedCompetency.correct = 3
        var removedCompetency = TopicCompetency.initial(
            topic: removedSkill.name,
            goalID: goal.id,
            skillID: removedSkill.id
        )
        removedCompetency.attempts = 2
        removedCompetency.incorrect = 2
        store.competencies = [
            retainedCompetency,
            removedCompetency,
            .initial(topic: thirdSkill.name, goalID: goal.id, skillID: thirdSkill.id)
        ]

        var renamedSkill = retainedSkill
        renamedSkill.name = "causal argument analysis"
        let replacementSkill = SkillMapTopic(name: "evidence evaluation")

        XCTAssertTrue(
            store.reviewActiveDerivedSkillMap(
                topics: [renamedSkill, thirdSkill, replacementSkill]
            )
        )

        let reviewedMap = try XCTUnwrap(store.goal?.derivedSkillMap)
        XCTAssertEqual(reviewedMap.version, initialMap.version + 1)
        XCTAssertEqual(reviewedMap.provenance, .userEdited)
        XCTAssertTrue(store.reviewActiveDerivedSkillMap(topics: reviewedMap.topics))
        XCTAssertEqual(store.goal?.derivedSkillMap?.version, reviewedMap.version)
        XCTAssertEqual(
            reviewedMap.topics.first(where: { $0.id == replacementSkill.id })?.objectives.map(\.name),
            [replacementSkill.name]
        )
        let canonicalRetainedQuestion = try XCTUnwrap(
            store.questions.first { $0.id == retainedQuestion.id }
        )
        XCTAssertEqual(canonicalRetainedQuestion.skillID, retainedSkill.id)
        XCTAssertEqual(canonicalRetainedQuestion.topic, renamedSkill.name)
        XCTAssertEqual(
            store.questions.first { $0.id == removedQuestion.id }?.status,
            .retired
        )
        XCTAssertFalse(store.nextQuestions(limit: 5).contains { $0.id == removedQuestion.id })
        XCTAssertEqual(
            store.competencies.first(where: { $0.skillID == retainedSkill.id })?.attempts,
            4
        )
        XCTAssertNil(store.competencies.first { $0.skillID == removedSkill.id })
        XCTAssertEqual(
            store.competencies.first(where: { $0.skillID == replacementSkill.id })?.attempts,
            0
        )
    }

    @MainActor
    func testConsumedStarterSkillMapReviewPersistsWithoutRegenerating() async throws {
        let skills = ["argument analysis", "conditional logic", "reading structure"].map {
            SkillMapTopic(name: $0, objectives: [SkillMapObjective(name: $0)])
        }
        let goal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "",
            derivedSkillMap: GoalSkillMap(
                topics: skills,
                status: .reviewed,
                provenance: .backendInferred
            ),
            preferredQuestionStyle: .multipleChoice
        )
        let backendEngine = CapturingQuestionEngine(provider: .backend)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.goal = goal
        store.goalProfiles = [goal]
        let consumedQuestion = makeQuestion(
            goal: goal,
            index: 1,
            topic: skills[0].name,
            skillID: skills[0].id,
            timesAsked: 1
        )
        let removedQuestion = makeQuestion(
            goal: goal,
            index: 2,
            topic: skills[1].name,
            skillID: skills[1].id
        )
        store.questions = [consumedQuestion, removedQuestion]
        let replacement = SkillMapTopic(name: "evidence evaluation")

        XCTAssertTrue(
            store.reviewActiveDerivedSkillMap(
                topics: [skills[0], skills[2], replacement]
            )
        )

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(
            store.goal?.derivedSkillMap?.topics.map(\.id),
            [skills[0].id, skills[2].id, replacement.id]
        )
        XCTAssertEqual(
            store.questions.first(where: { $0.id == removedQuestion.id })?.status,
            .retired
        )
        XCTAssertEqual(store.pendingMembershipFeature, .freshQuestionGeneration)
        XCTAssertNotNil(store.checkpointNotice)
        XCTAssertTrue(backendEngine.receivedRequests.isEmpty)
        XCTAssertFalse(store.isQuestionBankTopOffInProgress)
        XCTAssertNotEqual(store.questionBatchState, .generating)
    }

    @MainActor
    func testConsumedStarterSkillMapRepairPersistsWithoutRegenerating() async throws {
        let goal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice
        )
        let backendEngine = CapturingQuestionEngine(provider: .backend)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.goal = goal
        store.goalProfiles = [goal]
        let retainedQuestion = makeQuestion(
            goal: goal,
            index: 1,
            topic: "argument analysis",
            timesAsked: 1
        )
        let retiredQuestion = makeQuestion(
            goal: goal,
            index: 2,
            topic: "unrelated trivia"
        )
        store.questions = [retainedQuestion, retiredQuestion]

        XCTAssertTrue(
            store.repairActiveSkillMap(
                topicNames: ["argument analysis", "conditional logic", "reading structure"]
            )
        )

        try? await Task.sleep(nanoseconds: 100_000_000)
        let repairedMap = try XCTUnwrap(store.goal?.derivedSkillMap)
        XCTAssertEqual(repairedMap.status, .reviewed)
        XCTAssertEqual(repairedMap.provenance, .userEdited)
        XCTAssertEqual(
            store.questions.first(where: { $0.id == retiredQuestion.id })?.status,
            .retired
        )
        XCTAssertEqual(
            store.questions.first(where: { $0.id == retainedQuestion.id })?.skillID,
            repairedMap.topics.first?.id
        )
        XCTAssertTrue(store.competencies.allSatisfy { $0.skillID != nil })
        XCTAssertEqual(store.pendingMembershipFeature, .freshQuestionGeneration)
        XCTAssertNotNil(store.checkpointNotice)
        XCTAssertTrue(backendEngine.receivedRequests.isEmpty)
        XCTAssertFalse(store.isQuestionBankTopOffInProgress)
        XCTAssertNotEqual(store.questionBatchState, .generating)
    }

}
