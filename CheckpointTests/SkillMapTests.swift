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
    func testGoalScopedSkillMapReviewAcceptsExactCurrentRevision() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_780_050_000)
        let skillMap = GoalSkillMap(
            topics: [
                SkillMapTopic(
                    name: "Problem framing",
                    objectives: [SkillMapObjective(name: "Clarify the problem")]
                ),
                SkillMapTopic(
                    name: "State modeling",
                    objectives: [SkillMapObjective(name: "Model state transitions")]
                ),
                SkillMapTopic(
                    name: "Testing strategy",
                    objectives: [SkillMapObjective(name: "Design focused tests")]
                )
            ],
            status: .suggested,
            version: 4,
            provenance: .backendInferred,
            updatedAt: updatedAt
        )
        let goal = Goal(
            title: "Ship a reliable app",
            deadline: updatedAt.addingTimeInterval(86_400 * 30),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "architecture",
            derivedSkillMap: skillMap,
            preferredQuestionStyle: .multipleChoice
        )
        let reviewContext = try XCTUnwrap(SkillMapReviewContext(goal: goal))
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]

        XCTAssertTrue(
            store.reviewDerivedSkillMap(
                topics: reviewContext.skillMap.topics,
                forGoalID: reviewContext.revision.goalID,
                expectedMap: reviewContext.skillMap
            )
        )
        let reviewedGoal = try XCTUnwrap(store.goal)
        let reviewedMap = try XCTUnwrap(reviewedGoal.derivedSkillMap)
        XCTAssertEqual(reviewedGoal.id, goal.id)
        XCTAssertEqual(reviewedMap.topics, skillMap.topics)
        XCTAssertEqual(reviewedMap.status, .reviewed)
        XCTAssertEqual(reviewedMap.version, skillMap.version)
        XCTAssertGreaterThan(reviewedMap.updatedAt, skillMap.updatedAt)
    }

    @MainActor
    func testGoalScopedSkillMapReviewRejectsActiveGoalSwitch() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_780_100_000)
        let firstMap = GoalSkillMap(
            topics: [
                SkillMapTopic(name: "Problem framing"),
                SkillMapTopic(name: "State modeling"),
                SkillMapTopic(name: "Testing strategy")
            ],
            status: .suggested,
            version: 2,
            provenance: .backendInferred,
            updatedAt: updatedAt
        )
        let firstGoal = Goal(
            title: "Ship a reliable app",
            deadline: updatedAt.addingTimeInterval(86_400 * 30),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "architecture",
            derivedSkillMap: firstMap,
            preferredQuestionStyle: .multipleChoice
        )
        let secondMap = GoalSkillMap(
            topics: [
                SkillMapTopic(name: "Vocabulary"),
                SkillMapTopic(name: "Listening"),
                SkillMapTopic(name: "Conversation")
            ],
            status: .suggested,
            version: 7,
            provenance: .explicitFocusAreas,
            updatedAt: updatedAt.addingTimeInterval(20)
        )
        let secondGoal = Goal(
            title: "Build conversational Spanish",
            deadline: updatedAt.addingTimeInterval(86_400 * 60),
            category: .languageLearning,
            currentLevel: "Beginner",
            focusAreas: "speaking",
            derivedSkillMap: secondMap,
            preferredQuestionStyle: .shortAnswer
        )
        let reviewContext = try XCTUnwrap(SkillMapReviewContext(goal: firstGoal))
        let store = CheckpointStore(defaults: defaults)
        store.goal = secondGoal
        store.goalProfiles = [firstGoal, secondGoal]
        let activeSkill = try XCTUnwrap(secondMap.topics.first)
        store.questions = [
            makeQuestion(
                goal: secondGoal,
                index: 901,
                topic: activeSkill.name,
                skillID: activeSkill.id
            )
        ]
        store.competencies = [
            .initial(
                topic: activeSkill.name,
                goalID: secondGoal.id,
                skillID: activeSkill.id
            )
        ]
        store.skillMapEvolutionIntents = [
            SkillMapEvolutionIntent(
                goalID: secondGoal.id,
                baseVersion: secondMap.version,
                baseMapFingerprint: SkillMapReconciler.skillMapFingerprint(
                    topics: secondMap.topics
                ),
                masteredSkillIDs: [activeSkill.id]
            )
        ]
        store.questionBankSyncIntents = [
            QuestionBankSyncIntent(
                goalID: secondGoal.id,
                contextRevision: "second-goal-context",
                desiredCount: 6,
                lowWatermark: 2
            )
        ]
        store.questionBatchState = .ready
        store.isQuestionBankTopOffInProgress = true
        let goalBeforeSave = store.goal
        let profilesBeforeSave = store.goalProfiles
        let questionsBeforeSave = store.questions
        let competenciesBeforeSave = store.competencies
        let evolutionIntentsBeforeSave = store.skillMapEvolutionIntents
        let syncIntentsBeforeSave = store.questionBankSyncIntents
        let batchStateBeforeSave = store.questionBatchState.rawValue
        let topOffStateBeforeSave = store.isQuestionBankTopOffInProgress

        XCTAssertFalse(
            store.reviewDerivedSkillMap(
                topics: reviewContext.skillMap.topics,
                forGoalID: reviewContext.revision.goalID,
                expectedMap: reviewContext.skillMap
            )
        )
        XCTAssertEqual(store.goal, goalBeforeSave)
        XCTAssertEqual(store.goalProfiles, profilesBeforeSave)
        XCTAssertEqual(store.questions, questionsBeforeSave)
        XCTAssertEqual(store.competencies, competenciesBeforeSave)
        XCTAssertEqual(store.skillMapEvolutionIntents, evolutionIntentsBeforeSave)
        XCTAssertEqual(store.questionBankSyncIntents, syncIntentsBeforeSave)
        XCTAssertEqual(store.questionBatchState.rawValue, batchStateBeforeSave)
        XCTAssertEqual(store.isQuestionBankTopOffInProgress, topOffStateBeforeSave)
        XCTAssertFalse(reviewContext.matches(store.goal))
    }

    @MainActor
    func testGoalScopedSkillMapReviewRejectsSameGoalRevisionDrift() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_780_200_000)
        let baseMap = GoalSkillMap(
            topics: [
                SkillMapTopic(name: "Problem framing"),
                SkillMapTopic(name: "State modeling"),
                SkillMapTopic(name: "Testing strategy")
            ],
            status: .suggested,
            version: 5,
            provenance: .backendInferred,
            updatedAt: updatedAt
        )
        let baseGoal = Goal(
            title: "Ship a reliable app",
            deadline: updatedAt.addingTimeInterval(86_400 * 30),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "architecture",
            derivedSkillMap: baseMap,
            preferredQuestionStyle: .multipleChoice
        )
        let reviewContext = try XCTUnwrap(SkillMapReviewContext(goal: baseGoal))
        var versionDrift = baseMap
        versionDrift.version += 1
        var metadataDrift = baseMap
        metadataDrift.updatedAt = updatedAt.addingTimeInterval(1)
        var contentDrift = baseMap
        contentDrift.topics[0].name = "Reframed systems"
        let liveMaps = [versionDrift, metadataDrift, contentDrift]
        let store = CheckpointStore(defaults: defaults)
        let baseSkill = try XCTUnwrap(baseMap.topics.first)
        store.questions = [
            makeQuestion(
                goal: baseGoal,
                index: 902,
                topic: baseSkill.name,
                skillID: baseSkill.id
            )
        ]
        store.competencies = [
            .initial(
                topic: baseSkill.name,
                goalID: baseGoal.id,
                skillID: baseSkill.id
            )
        ]
        store.skillMapEvolutionIntents = [
            SkillMapEvolutionIntent(
                goalID: baseGoal.id,
                baseVersion: baseMap.version,
                baseMapFingerprint: SkillMapReconciler.skillMapFingerprint(
                    topics: baseMap.topics
                ),
                masteredSkillIDs: [baseSkill.id]
            )
        ]
        store.questionBankSyncIntents = [
            QuestionBankSyncIntent(
                goalID: baseGoal.id,
                contextRevision: "base-goal-context",
                desiredCount: 6,
                lowWatermark: 2
            )
        ]
        store.questionBatchState = .ready
        store.isQuestionBankTopOffInProgress = true

        for liveMap in liveMaps {
            var liveGoal = baseGoal
            liveGoal.derivedSkillMap = liveMap
            store.goal = liveGoal
            store.goalProfiles = [liveGoal]
            let goalBeforeSave = store.goal
            let profilesBeforeSave = store.goalProfiles
            let questionsBeforeSave = store.questions
            let competenciesBeforeSave = store.competencies
            let evolutionIntentsBeforeSave = store.skillMapEvolutionIntents
            let syncIntentsBeforeSave = store.questionBankSyncIntents
            let batchStateBeforeSave = store.questionBatchState.rawValue
            let topOffStateBeforeSave = store.isQuestionBankTopOffInProgress

            XCTAssertFalse(
                store.reviewDerivedSkillMap(
                    topics: reviewContext.skillMap.topics,
                    forGoalID: reviewContext.revision.goalID,
                    expectedMap: reviewContext.skillMap
                )
            )
            XCTAssertEqual(store.goal, goalBeforeSave)
            XCTAssertEqual(store.goalProfiles, profilesBeforeSave)
            XCTAssertEqual(store.questions, questionsBeforeSave)
            XCTAssertEqual(store.competencies, competenciesBeforeSave)
            XCTAssertEqual(store.skillMapEvolutionIntents, evolutionIntentsBeforeSave)
            XCTAssertEqual(store.questionBankSyncIntents, syncIntentsBeforeSave)
            XCTAssertEqual(store.questionBatchState.rawValue, batchStateBeforeSave)
            XCTAssertEqual(store.isQuestionBankTopOffInProgress, topOffStateBeforeSave)
            XCTAssertFalse(reviewContext.matches(store.goal))
        }
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
        XCTAssertEqual(
            store.competencies.first { $0.skillID == removedSkill.id }?.attempts,
            2
        )
        XCTAssertEqual(
            reviewedMap.archivedTopics.first { $0.id == removedSkill.id }?.reason,
            .userRemoved
        )
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

    @MainActor
    func testSkillMapReviewRejectsCanonicalArchivedNameReuse() throws {
        let engine = EvolutionQuestionEngine()
        let fixture = makeEvolutionFixture(engine: engine)
        var goal = fixture.goal
        var skillMap = try XCTUnwrap(goal.derivedSkillMap)
        let archivedTopic = SkillMapTopic(
            name: "Higher-order reasoning",
            objectives: [SkillMapObjective(name: "Analyze complex cases")]
        )
        skillMap.archivedTopics = [
            ArchivedSkillMapTopic(
                topic: archivedTopic,
                reason: .mastered,
                archivedAt: Date(),
                successorSkillIDs: [],
                mastery: nil
            )
        ]
        goal.derivedSkillMap = skillMap
        fixture.store.goal = goal
        fixture.store.goalProfiles = [goal]

        var proposedTopics = skillMap.topics
        proposedTopics[0].name = "Higher order reasoning"

        XCTAssertFalse(fixture.store.reviewActiveDerivedSkillMap(topics: proposedTopics))
        XCTAssertEqual(
            fixture.store.goal?.derivedSkillMap?.topics,
            skillMap.topics
        )
    }

    @MainActor
    func testSkillMapReviewRejectsReplacementThatReusesRemovedSkillName() throws {
        let engine = EvolutionQuestionEngine()
        let fixture = makeEvolutionFixture(engine: engine)
        let originalMap = try XCTUnwrap(fixture.goal.derivedSkillMap)
        var proposedTopics = originalMap.topics
        proposedTopics[0] = SkillMapTopic(
            name: "Skill-1 foundations",
            objectives: [SkillMapObjective(name: "Replacement objective")]
        )

        XCTAssertFalse(fixture.store.reviewActiveDerivedSkillMap(topics: proposedTopics))
        XCTAssertEqual(fixture.store.goal?.derivedSkillMap, originalMap)
    }

    // MARK: - Automatic skill progression

    @MainActor
    func testEvolutionRequiresRecentEvidenceAcrossEveryObjective() async {
        let engine = EvolutionQuestionEngine()
        let fixture = makeEvolutionFixture(engine: engine)
        let firstObjectiveID = fixture.skills[0].objectives[0].id
        fixture.store.attempts = fixture.store.attempts.map { attempt in
            var updatedAttempt = attempt
            if attempt.skillID == fixture.skills[0].id {
                updatedAttempt.objectiveID = firstObjectiveID
            }
            return updatedAttempt
        }

        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        XCTAssertTrue(engine.evolutionRequests.isEmpty)
        XCTAssertTrue(fixture.store.skillMapEvolutionIntents.isEmpty)

        fixture.store.attempts = eligibleAttempts(
            for: fixture.skills[0],
            goal: fixture.goal
        ).map { attempt in
            var staleAttempt = attempt
            staleAttempt.createdAt = Date().addingTimeInterval(-(31 * 24 * 60 * 60))
            return staleAttempt
        }
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        XCTAssertTrue(engine.evolutionRequests.isEmpty)

        fixture.store.attempts = eligibleAttempts(
            for: fixture.skills[0],
            goal: fixture.goal
        ).enumerated().map { index, attempt in
            var updatedAttempt = attempt
            updatedAttempt.questionDifficulty = index < 4 ? 3 : (index == 4 ? 4 : 3)
            return updatedAttempt
        }
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        XCTAssertTrue(engine.evolutionRequests.isEmpty)

        fixture.store.attempts = Array(eligibleAttempts(
            for: fixture.skills[0],
            goal: fixture.goal
        ).reversed())
        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didRequestEvolution = await waitUntil { engine.evolutionRequests.count == 1 }
        XCTAssertTrue(didRequestEvolution)
    }

    @MainActor
    func testEvolutionUsesSameCanonicalObjectiveEvidenceForGateAndRequest() async {
        let engine = EvolutionQuestionEngine()
        let fixture = makeEvolutionFixture(engine: engine)
        let skill = fixture.skills[0]
        let legacyAttempts = [
            CheckpointAttempt(
                questionID: UUID(),
                goalID: fixture.goal.id,
                skillID: skill.id,
                objectiveID: nil,
                questionDifficulty: 5,
                prompt: "Legacy missing objective",
                answer: "Missed",
                result: .incorrect,
                unlockMinutes: 0,
                createdAt: Date().addingTimeInterval(120)
            ),
            CheckpointAttempt(
                questionID: UUID(),
                goalID: fixture.goal.id,
                skillID: skill.id,
                objectiveID: UUID(),
                questionDifficulty: 5,
                prompt: "Legacy invalid objective",
                answer: "Missed",
                result: .incorrect,
                unlockMinutes: 0,
                createdAt: Date().addingTimeInterval(60)
            )
        ]
        fixture.store.attempts.insert(contentsOf: legacyAttempts, at: 0)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didRequestEvolution = await waitUntil { engine.evolutionRequests.count == 1 }
        XCTAssertTrue(didRequestEvolution)

        let sentAttempts = engine.evolutionRequests[0].recentAttempts
        XCTAssertEqual(sentAttempts.count, 10)
        XCTAssertTrue(sentAttempts.allSatisfy { attempt in
            attempt.objectiveID.map(Set(skill.objectives.map(\.id)).contains) == true
        })
        XCTAssertFalse(sentAttempts.contains { attempt in
            legacyAttempts.contains { $0.id == attempt.id }
        })
    }

    @MainActor
    func testDuplicateCompetencyCannotReuseOlderCorrectStreakForEvolution() throws {
        let engine = EvolutionQuestionEngine()
        let fixture = makeEvolutionFixture(engine: engine)
        let skill = fixture.skills[0]
        let competencyIndex = try XCTUnwrap(
            fixture.store.competencies.firstIndex { $0.skillID == skill.id }
        )
        fixture.store.competencies[competencyIndex].currentStreak = 0
        fixture.store.competencies[competencyIndex].lastResult = .partial
        fixture.store.competencies[competencyIndex].lastPracticedAt = Date()

        var olderDuplicate = fixture.store.competencies[competencyIndex]
        olderDuplicate.currentStreak = 10
        olderDuplicate.lastResult = .correct
        olderDuplicate.lastPracticedAt = Date().addingTimeInterval(-60)
        fixture.store.competencies.append(olderDuplicate)

        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        XCTAssertTrue(engine.evolutionRequests.isEmpty)
        XCTAssertTrue(fixture.store.skillMapEvolutionIntents.isEmpty)

        var nilDatedCorrect = olderDuplicate
        nilDatedCorrect.lastPracticedAt = nil
        var nilDatedMiss = olderDuplicate
        nilDatedMiss.currentStreak = 0
        nilDatedMiss.lastResult = .incorrect
        nilDatedMiss.lastPracticedAt = nil
        XCTAssertEqual(
            SkillMapReconciler.mergedCompetency(nilDatedCorrect, with: nilDatedMiss).currentStreak,
            0
        )
        XCTAssertEqual(
            SkillMapReconciler.mergedCompetency(nilDatedMiss, with: nilDatedCorrect).currentStreak,
            0
        )
    }

    @MainActor
    func testTenthCorrectAnswerAutomaticallyTriggersEvolution() async throws {
        let engine = EvolutionQuestionEngine()
        let fixture = makeEvolutionFixture(engine: engine)
        let baseVersion = try XCTUnwrap(fixture.goal.derivedSkillMap?.version)
        let predecessor = fixture.skills[0]
        let competencyIndex = try XCTUnwrap(fixture.store.competencies.firstIndex(where: {
            $0.skillID == predecessor.id
        }))
        fixture.store.competencies[competencyIndex].attempts = 9
        fixture.store.competencies[competencyIndex].correct = 9
        fixture.store.competencies[competencyIndex].currentStreak = 9
        fixture.store.attempts = Array(
            eligibleAttempts(for: predecessor, goal: fixture.goal).prefix(9).reversed()
        )
        let thresholdQuestion = makeQuestion(
            goal: fixture.goal,
            index: 999,
            topic: predecessor.name,
            skillID: predecessor.id,
            objectiveID: predecessor.objectives[1].id,
            objective: predecessor.objectives[1].name,
            difficulty: 4
        )

        _ = fixture.store.submitAnswer(
            question: thresholdQuestion,
            answer: thresholdQuestion.expectedAnswer,
            result: .correct,
            grantsUnlock: false
        )

        let didEvolve = await waitUntil {
            fixture.store.goal?.derivedSkillMap?.version == baseVersion + 1
        }
        XCTAssertTrue(didEvolve)
        XCTAssertEqual(engine.evolutionRequests.count, 1)
        XCTAssertTrue(fixture.store.skillMapEvolutionIntents.isEmpty)
    }

    @MainActor
    func testEvolutionIsSingleFlightAndPreservesHistoryWhileRefillingSuccessor() async throws {
        let engine = EvolutionQuestionEngine(delayNanoseconds: 150_000_000)
        let fixture = makeEvolutionFixture(engine: engine)
        let baseVersion = try XCTUnwrap(fixture.goal.derivedSkillMap?.version)
        let predecessor = fixture.skills[0]
        let retainedSkill = fixture.skills[1]
        let predecessorQuestionID = try XCTUnwrap(
            fixture.store.questions.first { $0.skillID == predecessor.id }?.id
        )
        let retainedQuestionID = try XCTUnwrap(
            fixture.store.questions.first { $0.skillID == retainedSkill.id }?.id
        )

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())

        let didEvolve = await waitUntil {
            fixture.store.goal?.derivedSkillMap?.version == baseVersion + 1 &&
                !engine.generationRequests.isEmpty
        }
        XCTAssertTrue(didEvolve)
        XCTAssertEqual(engine.evolutionRequests.count, 1)
        let evolvedMap = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        let archived = try XCTUnwrap(
            evolvedMap.archivedTopics.first { $0.id == predecessor.id }
        )
        let successorID = try XCTUnwrap(archived.successorSkillIDs.first)
        let successor = try XCTUnwrap(evolvedMap.topics.first { $0.id == successorID })

        XCTAssertEqual(evolvedMap.status, .reviewed)
        XCTAssertEqual(evolvedMap.provenance, .adaptiveEvolution)
        XCTAssertEqual(archived.reason, .mastered)
        XCTAssertEqual(archived.mastery?.attempts, 10)
        XCTAssertEqual(successor.stage, predecessor.stage + 1)
        XCTAssertEqual(successor.predecessorIDs, [predecessor.id])
        XCTAssertEqual(
            fixture.store.competencies.first { $0.skillID == predecessor.id }?.attempts,
            10
        )
        XCTAssertEqual(
            fixture.store.competencies.first { $0.skillID == successor.id }?.attempts,
            0
        )
        XCTAssertEqual(
            fixture.store.competencies.first { $0.skillID == retainedSkill.id }?.attempts,
            0
        )
        XCTAssertEqual(
            fixture.store.questions.first { $0.id == predecessorQuestionID }?.status,
            .retired
        )
        XCTAssertNotEqual(
            fixture.store.questions.first { $0.id == retainedQuestionID }?.status,
            .retired
        )
        XCTAssertTrue(fixture.store.skillMapEvolutionIntents.isEmpty)
        XCTAssertNotNil(fixture.store.checkpointNotice)
        XCTAssertFalse(engine.generationRequests.isEmpty)

        let evolutionRequest = try XCTUnwrap(engine.evolutionRequests.first)
        XCTAssertEqual(evolutionRequest.masteredSkillIDs, [predecessor.id])
        XCTAssertEqual(evolutionRequest.competencies.count, 1)
        XCTAssertEqual(evolutionRequest.recentAttempts.count, 10)
        XCTAssertEqual(
            Set(evolutionRequest.recentAttempts.compactMap(\.objectiveID)),
            Set(predecessor.objectives.map(\.id))
        )
    }

    @MainActor
    func testTierDowngradeAndReupgradeDoesNotDuplicateInFlightEvolution() async throws {
        let engine = EvolutionQuestionEngine(delayNanoseconds: 200_000_000)
        let fixture = makeEvolutionFixture(engine: engine)
        let baseVersion = try XCTUnwrap(fixture.goal.derivedSkillMap?.version)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didStartEvolution = await waitUntil { engine.evolutionRequests.count == 1 }
        XCTAssertTrue(didStartEvolution)

        fixture.store.updateMembershipTier(.starter)
        fixture.store.updateMembershipTier(.member)
        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())

        let didFinishEvolution = await waitUntil {
            fixture.store.goal?.derivedSkillMap?.version == baseVersion + 1
        }
        XCTAssertTrue(didFinishEvolution)
        XCTAssertEqual(engine.evolutionRequests.count, 1)
    }

    @MainActor
    func testLateEvolutionResponseIsIgnoredAfterReviewedMapChanges() async throws {
        let engine = EvolutionQuestionEngine(delayNanoseconds: 200_000_000)
        let fixture = makeEvolutionFixture(engine: engine)
        let baseMap = try XCTUnwrap(fixture.goal.derivedSkillMap)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didStartRequest = await waitUntil { engine.evolutionRequests.count == 1 }
        XCTAssertTrue(didStartRequest)

        var editedTopics = baseMap.topics
        editedTopics[1].name = "Skill 2 revised"
        XCTAssertTrue(fixture.store.reviewActiveDerivedSkillMap(topics: editedTopics))
        try? await Task.sleep(nanoseconds: 300_000_000)

        let finalMap = try XCTUnwrap(fixture.store.goal?.derivedSkillMap)
        XCTAssertEqual(finalMap.version, baseMap.version + 1)
        XCTAssertEqual(finalMap.provenance, .userEdited)
        XCTAssertEqual(finalMap.topics[1].name, "Skill 2 revised")
        XCTAssertTrue(finalMap.archivedTopics.isEmpty)
        XCTAssertTrue(fixture.store.skillMapEvolutionIntents.isEmpty)
    }

    @MainActor
    func testNewMissInvalidatesInFlightEvolutionBeforeItCanArchiveSkill() async throws {
        let engine = EvolutionQuestionEngine(delayNanoseconds: 200_000_000)
        let fixture = makeEvolutionFixture(engine: engine)
        let baseMap = try XCTUnwrap(fixture.goal.derivedSkillMap)
        let predecessorQuestion = try XCTUnwrap(
            fixture.store.questions.first { $0.skillID == fixture.skills[0].id }
        )

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didStartRequest = await waitUntil { engine.evolutionRequests.count == 1 }
        XCTAssertTrue(didStartRequest)

        _ = fixture.store.submitAnswer(
            question: predecessorQuestion,
            answer: "Missed",
            result: .incorrect,
            grantsUnlock: false
        )
        XCTAssertEqual(fixture.store.skillMapEvolutionIntents.count, 1)
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(fixture.store.goal?.derivedSkillMap, baseMap)
        XCTAssertTrue(fixture.store.goal?.derivedSkillMap?.archivedTopics.isEmpty == true)
        XCTAssertEqual(engine.evolutionRequests.count, 1)
        XCTAssertEqual(fixture.store.skillMapEvolutionIntents.count, 1)
    }

    @MainActor
    func testPartialTwoSkillEvolutionResponseIsRejectedAtomically() async throws {
        let engine = EvolutionQuestionEngine(replacementLimit: 1)
        let fixture = makeEvolutionFixture(engine: engine, eligibleSkillCount: 2)
        let baseMap = try XCTUnwrap(fixture.goal.derivedSkillMap)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didRejectResponse = await waitUntil {
            engine.evolutionRequests.count == 1 &&
                fixture.store.skillMapEvolutionIntents.first?.lastFailure == .invalidResponse
        }
        XCTAssertTrue(didRejectResponse)

        XCTAssertEqual(engine.evolutionRequests.first?.masteredSkillIDs.count, 2)
        XCTAssertEqual(fixture.store.goal?.derivedSkillMap, baseMap)
        XCTAssertTrue(fixture.store.goal?.derivedSkillMap?.archivedTopics.isEmpty == true)
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(engine.evolutionRequests.count, 1)
        XCTAssertEqual(fixture.store.skillMapEvolutionIntents.count, 1)
    }

    @MainActor
    func testEvolutionFailureKeepsIntentBackedOffAndMaintainsQuestionBank() async {
        let engine = EvolutionQuestionEngine(shouldFailEvolution: true)
        let fixture = makeEvolutionFixture(engine: engine)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didFallBackToBankMaintenance = await waitUntil {
            engine.evolutionRequests.count == 1 && !engine.generationRequests.isEmpty
        }
        XCTAssertTrue(didFallBackToBankMaintenance)
        XCTAssertEqual(fixture.store.skillMapEvolutionIntents.count, 1)
        XCTAssertNotNil(fixture.store.skillMapEvolutionIntents.first?.lastAttemptAt)

        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(engine.evolutionRequests.count, 1)
    }

    @MainActor
    func testInvalidEvolutionResponseKeepsCooldownOnNextAnswer() async throws {
        let engine = EvolutionQuestionEngine(evolutionError: .badResponse)
        let fixture = makeEvolutionFixture(engine: engine)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didPersistFailure = await waitUntil {
            engine.evolutionRequests.count == 1 &&
                fixture.store.skillMapEvolutionIntents.first?.lastFailure == .invalidResponse
        }
        XCTAssertTrue(didPersistFailure)

        let question = try XCTUnwrap(
            fixture.store.questions.first { $0.skillID == fixture.skills[0].id }
        )
        _ = fixture.store.submitAnswer(
            question: question,
            answer: question.expectedAnswer,
            result: .correct,
            grantsUnlock: false
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(engine.evolutionRequests.count, 1)
        XCTAssertEqual(fixture.store.skillMapEvolutionIntents.count, 1)
    }

    func testEvolutionIntentDecodesMissingInvalidResponseCountAsZero() throws {
        let original = SkillMapEvolutionIntent(
            goalID: UUID(),
            baseVersion: 3,
            baseMapFingerprint: "0123456789abcdef",
            masteredSkillIDs: [UUID()]
        )
        let encoded = try JSONEncoder().encode(original)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "invalidResponseAttemptCount")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

        let decoded = try JSONDecoder().decode(SkillMapEvolutionIntent.self, from: legacyData)

        XCTAssertEqual(decoded.invalidResponseAttemptCount, 0)
    }

    @MainActor
    func testRepeatedProviderFailuresRemainTransientAndCanRecover() async throws {
        let engine = EvolutionQuestionEngine(evolutionError: .providerFailure)
        let fixture = makeEvolutionFixture(engine: engine)
        let baseVersion = try XCTUnwrap(fixture.goal.derivedSkillMap?.version)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didRecordFirstFailure = await waitUntil {
            engine.evolutionRequests.count == 1 &&
                fixture.store.skillMapEvolutionIntents.first?.lastAttemptAt != nil
        }
        XCTAssertTrue(didRecordFirstFailure)
        XCTAssertEqual(
            fixture.store.skillMapEvolutionIntents.first?.invalidResponseAttemptCount,
            0
        )

        fixture.store.skillMapEvolutionIntents[0].lastAttemptAt = Date()
            .addingTimeInterval(-(7 * 60 * 60))
        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didRecordSecondFailure = await waitUntil {
            engine.evolutionRequests.count == 2 &&
                fixture.store.skillMapEvolutionIntents.first?.lastAttemptAt != nil
        }
        XCTAssertTrue(didRecordSecondFailure)
        XCTAssertEqual(
            fixture.store.skillMapEvolutionIntents.first?.invalidResponseAttemptCount,
            0
        )

        engine.evolutionError = nil
        fixture.store.skillMapEvolutionIntents[0].lastAttemptAt = Date()
            .addingTimeInterval(-(7 * 60 * 60))
        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didRecover = await waitUntil {
            engine.evolutionRequests.count == 3 &&
                fixture.store.goal?.derivedSkillMap?.version == baseVersion + 1
        }
        XCTAssertTrue(didRecover)
        XCTAssertTrue(fixture.store.skillMapEvolutionIntents.isEmpty)
    }

    @MainActor
    func testTemporaryEvidenceLossDoesNotResetInvalidResponseRetryCount() async throws {
        let engine = EvolutionQuestionEngine(evolutionError: .badResponse)
        let fixture = makeEvolutionFixture(engine: engine)
        let question = try XCTUnwrap(
            fixture.store.questions.first { $0.skillID == fixture.skills[0].id }
        )

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didRecordFirstFailure = await waitUntil {
            engine.evolutionRequests.count == 1 &&
                fixture.store.skillMapEvolutionIntents.first?.invalidResponseAttemptCount == 1
        }
        XCTAssertTrue(didRecordFirstFailure)
        fixture.store.skillMapEvolutionIntents[0].lastAttemptAt = Date()
            .addingTimeInterval(-(7 * 60 * 60))

        _ = fixture.store.submitAnswer(
            question: question,
            answer: "Missed",
            result: .incorrect,
            grantsUnlock: false
        )
        XCTAssertEqual(fixture.store.skillMapEvolutionIntents.count, 1)
        XCTAssertEqual(
            fixture.store.skillMapEvolutionIntents.first?.invalidResponseAttemptCount,
            1
        )

        for _ in 0..<4 {
            _ = fixture.store.submitAnswer(
                question: question,
                answer: question.expectedAnswer,
                result: .correct,
                grantsUnlock: false
            )
        }
        XCTAssertEqual(engine.evolutionRequests.count, 1, "Memorizing the same answer cannot restore mastery evidence.")
        for index in 0..<4 {
            var transferQuestion = question
            transferQuestion.id = UUID()
            transferQuestion.objectiveID = fixture.skills[0].objectives[index % 2].id
            transferQuestion.difficulty = 4
            _ = fixture.store.submitAnswer(question: transferQuestion, answer: transferQuestion.expectedAnswer, result: .correct, grantsUnlock: false)
        }
        let didRecordSecondFailure = await waitUntil {
            engine.evolutionRequests.count == 2 &&
                fixture.store.skillMapEvolutionIntents.first?.invalidResponseAttemptCount == 2
        }
        XCTAssertTrue(didRecordSecondFailure)
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        XCTAssertEqual(engine.evolutionRequests.count, 2)

        fixture.store.updateActiveSkillMapEvolutionEnabled(false)
        fixture.store.updateActiveSkillMapEvolutionEnabled(true)
        let didResetAfterUserToggle = await waitUntil {
            engine.evolutionRequests.count == 3 &&
                fixture.store.skillMapEvolutionIntents.first?.invalidResponseAttemptCount == 1
        }
        XCTAssertTrue(didResetAfterUserToggle)
    }

    @MainActor
    func testEvolutionInvalidRequestPersistsRetryCapAndStaysDormantAfterRelaunch() async throws {
        let invalidRequestError = BackendQuestionEngine.skillMapEvolutionError(
            for: 400,
            responseBody: Data(#"{"code":"invalid_request"}"#.utf8)
        )
        let engine = EvolutionQuestionEngine(evolutionError: invalidRequestError)
        let fixture = makeEvolutionFixture(engine: engine)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didRecordFirstFailure = await waitUntil {
            engine.evolutionRequests.count == 1 &&
                fixture.store.skillMapEvolutionIntents.first?.invalidResponseAttemptCount == 1
        }
        XCTAssertTrue(didRecordFirstFailure)

        fixture.store.skillMapEvolutionIntents[0].lastAttemptAt = Date()
            .addingTimeInterval(-(7 * 60 * 60))
        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didReachRetryCap = await waitUntil {
            engine.evolutionRequests.count == 2 &&
                fixture.store.skillMapEvolutionIntents.first?.invalidResponseAttemptCount == 2
        }
        XCTAssertTrue(didReachRetryCap)
        XCTAssertEqual(fixture.store.skillMapEvolutionIntents.first?.lastFailure, .invalidResponse)
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())

        let snapshotData = try XCTUnwrap(
            defaults.data(forKey: AppSnapshotPersistence.primaryDefaultsKey)
        )
        let persistedIntent = try XCTUnwrap(
            JSONDecoder().decode(AppSnapshotEnvelope.self, from: snapshotData)
                .snapshot.skillMapEvolutionIntents?.first
        )
        XCTAssertEqual(persistedIntent.invalidResponseAttemptCount, 2)
        XCTAssertEqual(persistedIntent.lastFailure, .invalidResponse)

        let resumedEngine = EvolutionQuestionEngine(evolutionError: invalidRequestError)
        let resumedStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: resumedEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(resumedStore.skillMapEvolutionIntents.first?.invalidResponseAttemptCount, 2)
        XCTAssertFalse(resumedStore.evaluateSkillMapEvolutionIfNeeded())
        XCTAssertTrue(resumedEngine.evolutionRequests.isEmpty)
    }

    @MainActor
    func testInvalidResponseCapResetsWhenEligibleTargetChanges() async throws {
        let engine = EvolutionQuestionEngine(evolutionError: .badResponse)
        let fixture = makeEvolutionFixture(engine: engine)
        let baseVersion = try XCTUnwrap(fixture.goal.derivedSkillMap?.version)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didRecordFirstFailure = await waitUntil {
            engine.evolutionRequests.count == 1 &&
                fixture.store.skillMapEvolutionIntents.first?.invalidResponseAttemptCount == 1
        }
        XCTAssertTrue(didRecordFirstFailure)
        fixture.store.skillMapEvolutionIntents[0].lastAttemptAt = Date()
            .addingTimeInterval(-(7 * 60 * 60))

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didCapFirstTarget = await waitUntil {
            engine.evolutionRequests.count == 2 &&
                fixture.store.skillMapEvolutionIntents.first?.invalidResponseAttemptCount == 2
        }
        XCTAssertTrue(didCapFirstTarget)
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())

        let firstSkillQuestion = try XCTUnwrap(
            fixture.store.questions.first { $0.skillID == fixture.skills[0].id }
        )
        _ = fixture.store.submitAnswer(
            question: firstSkillQuestion,
            answer: "Missed",
            result: .incorrect,
            grantsUnlock: false
        )

        let secondSkill = fixture.skills[1]
        let secondCompetencyIndex = try XCTUnwrap(
            fixture.store.competencies.firstIndex { $0.skillID == secondSkill.id }
        )
        fixture.store.competencies[secondCompetencyIndex].estimatedLevel = 5
        fixture.store.competencies[secondCompetencyIndex].attempts = 10
        fixture.store.competencies[secondCompetencyIndex].correct = 10
        fixture.store.competencies[secondCompetencyIndex].partial = 0
        fixture.store.competencies[secondCompetencyIndex].incorrect = 0
        fixture.store.competencies[secondCompetencyIndex].currentStreak = 10
        fixture.store.competencies[secondCompetencyIndex].lastResult = .correct
        fixture.store.competencies[secondCompetencyIndex].lastPracticedAt = Date()
        fixture.store.attempts.append(
            contentsOf: eligibleAttempts(for: secondSkill, goal: fixture.goal)
        )
        engine.evolutionError = nil

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didEvolveSecondTarget = await waitUntil {
            engine.evolutionRequests.count == 3 &&
                fixture.store.goal?.derivedSkillMap?.version == baseVersion + 1
        }
        XCTAssertTrue(didEvolveSecondTarget)
        XCTAssertEqual(engine.evolutionRequests[2].masteredSkillIDs, [secondSkill.id])
        XCTAssertTrue(
            fixture.store.goal?.derivedSkillMap?.archivedTopics.contains {
                $0.id == secondSkill.id
            } == true
        )
        XCTAssertTrue(fixture.store.skillMapEvolutionIntents.isEmpty)
    }

    @MainActor
    func testSafetyEvolutionFailureStaysBlockedUntilMapChanges() async {
        let engine = EvolutionQuestionEngine(evolutionError: .safetyIntervention)
        let fixture = makeEvolutionFixture(engine: engine)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didPersistFailure = await waitUntil {
            engine.evolutionRequests.count == 1 &&
                fixture.store.skillMapEvolutionIntents.first?.lastFailure == .safetyIntervention
        }
        XCTAssertTrue(didPersistFailure)

        fixture.store.skillMapEvolutionIntents[0].lastAttemptAt = Date()
            .addingTimeInterval(-(7 * 60 * 60))
        XCTAssertFalse(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(engine.evolutionRequests.count, 1)
        XCTAssertEqual(fixture.store.skillMapEvolutionIntents.count, 1)
    }

    @MainActor
    func testFailedEvolutionAfterMapEditDoesNotPrepareSupersededBank() async throws {
        let engine = EvolutionQuestionEngine(
            delayNanoseconds: 250_000_000,
            evolutionError: .serviceUnavailable
        )
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "current-bank",
                status: .queued,
                readyCount: 0,
                targetCount: 80
            )
        )
        let fixture = makeEvolutionFixture(engine: engine, questionBankClient: bankClient)
        fixture.store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didStartEvolution = await waitUntil { engine.evolutionRequests.count == 1 }
        XCTAssertTrue(didStartEvolution)

        var replacementTopics = try XCTUnwrap(fixture.goal.derivedSkillMap?.topics)
        replacementTopics[0] = SkillMapTopic(
            name: "Replacement foundations",
            objectives: [SkillMapObjective(name: "Build replacement evidence")]
        )
        XCTAssertTrue(fixture.store.reviewActiveDerivedSkillMap(topics: replacementTopics))
        let didPrepareCurrentBank = await waitUntil { !bankClient.ensureRequests.isEmpty }
        XCTAssertTrue(didPrepareCurrentBank)
        let currentRevision = try XCTUnwrap(bankClient.ensureRequests.first?.contextRevision)

        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(engine.evolutionRequests.count, 1)
        XCTAssertFalse(bankClient.ensureRequests.isEmpty)
        XCTAssertTrue(bankClient.ensureRequests.allSatisfy {
            $0.contextRevision == currentRevision
        })
    }

    @MainActor
    func testEvolutionWaitsForActiveCheckpointAndArchivesAllRunEvidence() async throws {
        let engine = EvolutionQuestionEngine(delayNanoseconds: 100_000_000)
        let fixture = makeEvolutionFixture(engine: engine)
        let baseMap = try XCTUnwrap(fixture.goal.derivedSkillMap)
        let predecessor = fixture.skills[0]
        let competencyIndex = try XCTUnwrap(fixture.store.competencies.firstIndex(where: {
            $0.skillID == predecessor.id
        }))
        fixture.store.competencies[competencyIndex].attempts = 9
        fixture.store.competencies[competencyIndex].correct = 9
        fixture.store.competencies[competencyIndex].currentStreak = 9
        fixture.store.attempts = Array(
            eligibleAttempts(for: predecessor, goal: fixture.goal).prefix(9).reversed()
        )

        let predecessorQuestions = fixture.store.questions.filter {
            $0.skillID == predecessor.id
        }
        XCTAssertEqual(predecessorQuestions.count, 2)
        let session = CheckpointSession(
            questions: predecessorQuestions,
            requiredCorrectAnswers: 2
        )
        fixture.store.activeCheckpointRun = try XCTUnwrap(ActiveCheckpointRun(session: session))

        for question in predecessorQuestions {
            _ = fixture.store.submitAnswer(
                question: question,
                answer: question.expectedAnswer,
                result: .correct,
                grantsUnlock: false
            )
        }

        XCTAssertEqual(engine.evolutionRequests.count, 0)
        XCTAssertEqual(fixture.store.goal?.derivedSkillMap, baseMap)
        XCTAssertTrue(predecessorQuestions.allSatisfy { question in
            fixture.store.questions.first(where: { $0.id == question.id })?.status != .retired
        })

        XCTAssertTrue(fixture.store.resolveCheckpointRun(sessionID: session.id, didPass: true))
        let didEvolve = await waitUntil {
            fixture.store.goal?.derivedSkillMap?.version == baseMap.version + 1
        }
        XCTAssertTrue(didEvolve)
        XCTAssertEqual(engine.evolutionRequests.count, 1)

        let archived = try XCTUnwrap(
            fixture.store.goal?.derivedSkillMap?.archivedTopics.first { $0.id == predecessor.id }
        )
        XCTAssertEqual(archived.mastery?.attempts, 11)
        XCTAssertTrue(predecessorQuestions.allSatisfy { question in
            fixture.store.questions.first(where: { $0.id == question.id })?.status == .retired
        })

        let retiredQuestion = predecessorQuestions[0]
        _ = fixture.store.submitAnswer(
            question: retiredQuestion,
            answer: "Stale answer",
            result: .incorrect,
            grantsUnlock: false
        )
        XCTAssertEqual(
            fixture.store.questions.first(where: { $0.id == retiredQuestion.id })?.status,
            .retired
        )
    }

    @MainActor
    func testLaunchResumesEligiblePersistedEvolutionIntent() async throws {
        let initialEngine = EvolutionQuestionEngine(shouldFailEvolution: true)
        let fixture = makeEvolutionFixture(engine: initialEngine)
        let skillMap = try XCTUnwrap(fixture.goal.derivedSkillMap)
        fixture.store.skillMapEvolutionIntents = [
            SkillMapEvolutionIntent(
                goalID: fixture.goal.id,
                baseVersion: skillMap.version,
                baseMapFingerprint: SkillMapReconciler.skillMapFingerprint(topics: skillMap.topics),
                masteredSkillIDs: [fixture.skills[0].id],
                lastAttemptAt: Date().addingTimeInterval(-(7 * 60 * 60))
            )
        ]
        fixture.store.updateAIProviderPreference(.backend)

        let resumedEngine = EvolutionQuestionEngine()
        let resumedStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: resumedEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )

        let didResumeEvolution = await waitUntil {
            resumedStore.goal?.derivedSkillMap?.version == skillMap.version + 1
        }
        XCTAssertTrue(didResumeEvolution)
        XCTAssertEqual(resumedEngine.evolutionRequests.count, 1)
        XCTAssertEqual(resumedEngine.events.first, "evolution")
        XCTAssertTrue(resumedStore.skillMapEvolutionIntents.isEmpty)
    }

    @MainActor
    func testLaunchDiscoversActiveGoalEvolutionDespiteInactiveBackoffIntent() async throws {
        let seedEngine = EvolutionQuestionEngine()
        let fixture = makeEvolutionFixture(engine: seedEngine)
        let inactiveSkills = [
            SkillMapTopic(name: "Writing", objectives: [SkillMapObjective(name: "Draft clearly")]),
            SkillMapTopic(name: "Editing", objectives: [SkillMapObjective(name: "Revise structure")]),
            SkillMapTopic(name: "Research", objectives: [SkillMapObjective(name: "Assess sources")])
        ]
        let inactiveMap = GoalSkillMap(
            topics: inactiveSkills,
            status: .reviewed,
            version: 2,
            provenance: .userEdited
        )
        let inactiveGoal = Goal(
            title: "Improve writing",
            deadline: Date().addingTimeInterval(30 * 24 * 60 * 60),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "",
            derivedSkillMap: inactiveMap,
            preferredQuestionStyle: .multipleChoice
        )
        fixture.store.goalProfiles = [fixture.goal, inactiveGoal]
        fixture.store.skillMapEvolutionIntents = [
            SkillMapEvolutionIntent(
                goalID: inactiveGoal.id,
                baseVersion: inactiveMap.version,
                baseMapFingerprint: SkillMapReconciler.skillMapFingerprint(topics: inactiveSkills),
                masteredSkillIDs: [inactiveSkills[0].id],
                lastAttemptAt: Date()
            )
        ]
        fixture.store.updateAIProviderPreference(.backend)

        let resumedEngine = EvolutionQuestionEngine()
        let resumedStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: resumedEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )

        let didEvolveActiveGoal = await waitUntil {
            resumedStore.goal?.derivedSkillMap?.version ==
                (fixture.goal.derivedSkillMap?.version ?? 0) + 1
        }
        XCTAssertTrue(didEvolveActiveGoal)
        XCTAssertEqual(resumedEngine.evolutionRequests.count, 1)
        XCTAssertEqual(resumedEngine.evolutionRequests.first?.goal.id, fixture.goal.id)
        XCTAssertTrue(
            resumedStore.skillMapEvolutionIntents.contains { $0.goalID == inactiveGoal.id }
        )
    }

    @MainActor
    func testStaleIntentIsRebuiltForCurrentEligibleMap() async throws {
        let engine = EvolutionQuestionEngine()
        let fixture = makeEvolutionFixture(engine: engine)
        let skillMap = try XCTUnwrap(fixture.goal.derivedSkillMap)
        fixture.store.skillMapEvolutionIntents = [
            SkillMapEvolutionIntent(
                goalID: fixture.goal.id,
                baseVersion: skillMap.version - 1,
                baseMapFingerprint: "stale-map",
                masteredSkillIDs: [fixture.skills[0].id]
            )
        ]

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didStartCurrentRequest = await waitUntil { engine.evolutionRequests.count == 1 }
        XCTAssertTrue(didStartCurrentRequest)
        XCTAssertEqual(
            engine.evolutionRequests.first?.baseMapFingerprint,
            SkillMapReconciler.skillMapFingerprint(topics: skillMap.topics)
        )
    }

    @MainActor
    func testMoreThanTwoEligibleSkillsAdvanceInBoundedConsecutiveCycles() async throws {
        let engine = EvolutionQuestionEngine()
        let fixture = makeEvolutionFixture(engine: engine, eligibleSkillCount: 3)
        let baseVersion = try XCTUnwrap(fixture.goal.derivedSkillMap?.version)

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didFinishCycles = await waitUntil {
            fixture.store.goal?.derivedSkillMap?.version == baseVersion + 2 &&
                fixture.store.goal?.derivedSkillMap?.archivedTopics.count == 3 &&
                engine.generationRequests.count == 1
        }

        XCTAssertTrue(didFinishCycles)
        XCTAssertEqual(engine.evolutionRequests.count, 2)
        XCTAssertEqual(engine.evolutionRequests[0].masteredSkillIDs.count, 2)
        XCTAssertEqual(engine.evolutionRequests[1].masteredSkillIDs.count, 1)
        XCTAssertEqual(engine.events, ["evolution", "evolution", "generation"])
        XCTAssertTrue(fixture.store.skillMapEvolutionIntents.isEmpty)
    }

    @MainActor
    func testChainedEvolutionRequestsOnlyFinalContextLocalBankDeficit() async throws {
        let engine = EvolutionQuestionEngine()
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "evolved-bank",
                status: .queued,
                readyCount: 0,
                targetCount: 10
            )
        )
        let fixture = makeEvolutionFixture(
            engine: engine,
            eligibleSkillCount: 3,
            questionBankClient: bankClient
        )
        var goal = fixture.goal
        var skillMap = try XCTUnwrap(goal.derivedSkillMap)
        let retainedSkill = SkillMapTopic(
            name: "Long-term synthesis",
            objectives: [SkillMapObjective(name: "Connect concepts")]
        )
        skillMap.topics.append(retainedSkill)
        goal.derivedSkillMap = skillMap
        fixture.store.goal = goal
        fixture.store.goalProfiles = [goal]
        fixture.store.competencies.append(
            .initial(
                topic: retainedSkill.name,
                goalID: goal.id,
                skillID: retainedSkill.id
            )
        )
        let retainedQuestions = (0..<70).map { index in
            makeQuestion(
                goal: goal,
                index: 1_000 + index,
                topic: retainedSkill.name,
                skillID: retainedSkill.id,
                objectiveID: retainedSkill.objectives[0].id,
                objective: retainedSkill.objectives[0].name,
                difficulty: 4
            )
        }
        fixture.store.questions.append(contentsOf: retainedQuestions)
        fixture.store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")

        XCTAssertTrue(fixture.store.evaluateSkillMapEvolutionIfNeeded())
        let didPrepareFinalContext = await waitUntil {
            fixture.store.goal?.derivedSkillMap?.version == skillMap.version + 2 &&
                bankClient.ensureRequests.count == 1
        }

        XCTAssertTrue(didPrepareFinalContext)
        XCTAssertEqual(engine.evolutionRequests.count, 2)
        XCTAssertEqual(engine.events, ["evolution", "evolution"])
        XCTAssertEqual(bankClient.ensureRequests.count, 1)
        XCTAssertEqual(bankClient.ensureRequests.first?.desiredCount, 10)
        XCTAssertEqual(
            fixture.store.questions.filter {
                $0.goalID == goal.id && $0.status != .retired
            }.count,
            70
        )

        fixture.store.questions.append(contentsOf: (0..<5).map { index in
            makeQuestion(
                goal: goal,
                index: 2_000 + index,
                topic: retainedSkill.name,
                skillID: retainedSkill.id,
                objectiveID: retainedSkill.objectives[0].id,
                objective: retainedSkill.objectives[0].name,
                difficulty: 4
            )
        })
        let didFinishInitialTopOff = await waitUntil {
            !fixture.store.isQuestionBankTopOffInProgress
        }
        XCTAssertTrue(didFinishInitialTopOff)
        _ = await fixture.store.refreshQuestionBatchIfNeeded()

        XCTAssertGreaterThanOrEqual(bankClient.ensureRequests.count, 2)
        XCTAssertTrue(bankClient.ensureRequests.allSatisfy { $0.desiredCount == 10 })
    }

    @MainActor
    func testRemoteBankSizingSimulatesSkewedAllocationUntilEverySkillHasCoverage() {
        let skills = (0..<6).map { index in
            SkillMapTopic(
                name: "Coverage skill \(index)",
                objectives: [SkillMapObjective(name: "Coverage objective \(index)")]
            )
        }
        let goal = Goal(
            title: "Maintain broad coverage",
            deadline: Date().addingTimeInterval(30 * 24 * 60 * 60),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "",
            derivedSkillMap: GoalSkillMap(
                topics: skills,
                status: .reviewed,
                provenance: .userEdited
            ),
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.membershipTier = .member
        store.competencies = skills.enumerated().map { index, skill in
            var competency = TopicCompetency.initial(
                topic: skill.name,
                estimatedLevel: [0, 4, 5].contains(index) ? 5 : 1,
                goalID: goal.id,
                skillID: skill.id
            )
            if [0, 4, 5].contains(index) {
                competency.attempts = 10
                competency.correct = 10
            } else {
                competency.attempts = 1
                competency.incorrect = 1
            }
            return competency
        }
        store.questions = (0..<79).map { index in
            let skill = skills[index % 5]
            return makeQuestion(
                goal: goal,
                index: 3_000 + index,
                topic: skill.name,
                skillID: skill.id,
                objectiveID: skill.objectives[0].id,
                objective: skill.objectives[0].name,
                difficulty: 4
            )
        }

        // Backend weights are [3,16,16,16,3,3]. A 12-question bank gives
        // the empty last skill only one slot; exact server apportionment first
        // gives it the two locally missing questions at 18.
        XCTAssertEqual(
            store.remoteQuestionBankDesiredCount(for: goal, localDeficit: 2),
            18
        )
    }

    @MainActor
    func testObjectiveCoverageDeficitTriggersMaintenanceAndReservesSkillSlots() async throws {
        let broadSkill = SkillMapTopic(
            name: "Systems analysis",
            objectives: (0..<5).map { SkillMapObjective(name: "Systems objective \($0)") }
        )
        let supportingSkills = [
            SkillMapTopic(
                name: "Communication",
                objectives: [SkillMapObjective(name: "Explain clearly")]
            ),
            SkillMapTopic(
                name: "Prioritization",
                objectives: [SkillMapObjective(name: "Rank tradeoffs")]
            )
        ]
        let skills = [broadSkill] + supportingSkills
        let goal = Goal(
            title: "Build product judgment",
            deadline: Date().addingTimeInterval(30 * 24 * 60 * 60),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "",
            derivedSkillMap: GoalSkillMap(
                topics: skills,
                status: .reviewed,
                provenance: .userEdited
            ),
            preferredQuestionStyle: .multipleChoice
        )
        let bankClient = ScriptedQuestionBankClient(
            preparation: QuestionBankPreparationReceipt(
                bankID: "objective-coverage-bank",
                status: .queued,
                readyCount: 0,
                targetCount: 80
            )
        )
        let store = CheckpointStore(
            questionBankClient: bankClient,
            defaults: defaults,
            questionBankPollingDelaysNanoseconds: [60_000_000_000]
        )
        store.goal = goal
        store.goalProfiles = [goal]
        store.membershipTier = .member
        store.updateAIProviderPreference(.backend)
        store.updateBackendEndpoint("https://api.example.com/prod/v1/questions")
        var masteredBroadSkill = TopicCompetency.initial(
            topic: broadSkill.name,
            estimatedLevel: 5,
            goalID: goal.id,
            skillID: broadSkill.id
        )
        masteredBroadSkill.attempts = 10
        masteredBroadSkill.correct = 10
        masteredBroadSkill.currentStreak = 10
        store.competencies = [masteredBroadSkill] + supportingSkills.map { skill in
            var competency = TopicCompetency.initial(
                topic: skill.name,
                goalID: goal.id,
                skillID: skill.id
            )
            competency.attempts = 1
            competency.incorrect = 1
            return competency
        }
        let broadQuestions = (0..<76).map { index in
            let objective = broadSkill.objectives[index % 4]
            return makeQuestion(
                goal: goal,
                index: 4_000 + index,
                topic: broadSkill.name,
                skillID: broadSkill.id,
                objectiveID: objective.id,
                objective: objective.name,
                difficulty: 4
            )
        }
        let supportingQuestions = supportingSkills.enumerated().flatMap { skillIndex, skill in
            (0..<2).map { questionIndex in
                makeQuestion(
                    goal: goal,
                    index: 5_000 + (skillIndex * 10) + questionIndex,
                    topic: skill.name,
                    skillID: skill.id,
                    objectiveID: skill.objectives[0].id,
                    objective: skill.objectives[0].name,
                    difficulty: 4
                )
            }
        }
        store.questions = broadQuestions + supportingQuestions

        _ = store.submitAnswer(
            question: broadQuestions[0],
            answer: broadQuestions[0].expectedAnswer,
            result: .correct,
            grantsUnlock: false
        )
        let didStartMaintenance = await waitUntil { !bankClient.ensureRequests.isEmpty }
        XCTAssertTrue(didStartMaintenance)
        let expectedDesiredCount = store.remoteQuestionBankDesiredCount(
            for: goal,
            localDeficit: 1
        )
        // Although only the fifth objective is locally missing, the backend's
        // finite bank must receive five slots for this skill to cover all five.
        XCTAssertEqual(expectedDesiredCount, 29)
        XCTAssertEqual(bankClient.ensureRequests.first?.desiredCount, expectedDesiredCount)
    }

    @MainActor
    func testFiveObjectiveLowWeightSkillHasFeasibleRemoteCoverageUnderSkew() {
        let broadSkill = SkillMapTopic(
            name: "Mastered synthesis",
            objectives: (0..<5).map { SkillMapObjective(name: "Synthesis objective \($0)") }
        )
        let weakSkills = (0..<5).map { index in
            SkillMapTopic(
                name: "Weak skill \(index)",
                objectives: [SkillMapObjective(name: "Weak objective \(index)")]
            )
        }
        let skills = [broadSkill] + weakSkills
        let goal = Goal(
            title: "Maintain broad expertise",
            deadline: Date().addingTimeInterval(30 * 24 * 60 * 60),
            category: .custom,
            currentLevel: "Advanced",
            focusAreas: "",
            derivedSkillMap: GoalSkillMap(
                topics: skills,
                status: .reviewed,
                provenance: .userEdited
            ),
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.membershipTier = .member
        var masteredCompetency = TopicCompetency.initial(
            topic: broadSkill.name,
            estimatedLevel: 5,
            goalID: goal.id,
            skillID: broadSkill.id
        )
        masteredCompetency.attempts = 10
        masteredCompetency.correct = 10
        store.competencies = [masteredCompetency] + weakSkills.map { skill in
            var competency = TopicCompetency.initial(
                topic: skill.name,
                goalID: goal.id,
                skillID: skill.id
            )
            competency.attempts = 1
            competency.incorrect = 1
            return competency
        }
        store.questions = (0..<80).map { index in
            let skill = weakSkills[index % weakSkills.count]
            return makeQuestion(
                goal: goal,
                index: 6_000 + index,
                topic: skill.name,
                skillID: skill.id,
                objectiveID: skill.objectives[0].id,
                objective: skill.objectives[0].name,
                difficulty: 4
            )
        }

        // Stable weights are [5,16,16,16,16,16]. Exact server apportionment
        // first gives the empty five-objective skill five slots at 60.
        XCTAssertEqual(
            store.remoteQuestionBankDesiredCount(for: goal, localDeficit: 5),
            60
        )
    }

    @MainActor
    private func makeEvolutionFixture(
        engine: EvolutionQuestionEngine,
        eligibleSkillCount: Int = 1,
        questionBankClient: (any QuestionBankSyncing)? = nil
    ) -> (store: CheckpointStore, goal: Goal, skills: [SkillMapTopic]) {
        let skills = [
            SkillMapTopic(
                name: "Skill 1 foundations",
                objectives: [
                    SkillMapObjective(name: "Objective 1A"),
                    SkillMapObjective(name: "Objective 1B")
                ]
            ),
            SkillMapTopic(
                name: "Skill 2 foundations",
                objectives: [SkillMapObjective(name: "Objective 2A")]
            ),
            SkillMapTopic(
                name: "Skill 3 foundations",
                objectives: [SkillMapObjective(name: "Objective 3A")]
            )
        ]
        let skillMap = GoalSkillMap(
            topics: skills,
            status: .reviewed,
            version: 3,
            provenance: .userEdited
        )
        let goal = Goal(
            title: "Advance technical skills",
            deadline: Date().addingTimeInterval(30 * 24 * 60 * 60),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "",
            derivedSkillMap: skillMap,
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: engine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            questionBankClient: questionBankClient,
            defaults: defaults
        )
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = skills.enumerated().flatMap { skillIndex, skill in
            (0..<2).map { questionIndex in
                let objective = skill.objectives[questionIndex % skill.objectives.count]
                return makeQuestion(
                    goal: goal,
                    index: (skillIndex * 10) + questionIndex,
                    topic: skill.name,
                    skillID: skill.id,
                    objectiveID: objective.id,
                    objective: objective.name,
                    difficulty: questionIndex == 0 ? 4 : 3
                )
            }
        }
        store.updateAIProviderPreference(.backend)
        store.membershipTier = .member
        store.competencies = skills.enumerated().map { index, skill in
            var competency = TopicCompetency.initial(
                topic: skill.name,
                estimatedLevel: index < eligibleSkillCount ? 5 : 1.5,
                goalID: goal.id,
                skillID: skill.id
            )
            if index < eligibleSkillCount {
                competency.attempts = 10
                competency.correct = 10
                competency.currentStreak = 10
                competency.lastResult = .correct
                competency.lastPracticedAt = Date()
            }
            return competency
        }
        store.attempts = Array(skills.prefix(eligibleSkillCount).flatMap {
            eligibleAttempts(for: $0, goal: goal)
        }.reversed())
        return (store, goal, skills)
    }

    private func eligibleAttempts(
        for skill: SkillMapTopic,
        goal: Goal
    ) -> [CheckpointAttempt] {
        (0..<10).map { index in
            let objective = skill.objectives[index % skill.objectives.count]
            return CheckpointAttempt(
                questionID: UUID(),
                goalID: goal.id,
                skillID: skill.id,
                objectiveID: objective.id,
                questionDifficulty: index == 0 ? 4 : 3,
                prompt: "Evolution evidence \(index)",
                answer: "Correct",
                result: .correct,
                unlockMinutes: 0,
                createdAt: Date().addingTimeInterval(-Double(index * 60))
            )
        }
    }

    @MainActor
    private func waitUntil(
        timeoutIterations: Int = 100,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<timeoutIterations {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

}

private final class EvolutionQuestionEngine: QuestionGenerating, SkillMapEvolving, @unchecked Sendable {
    let provider: AIProviderKind = .backend
    let delayNanoseconds: UInt64
    var evolutionError: QuestionGenerationError?
    let replacementLimit: Int?
    private(set) var evolutionRequests: [SkillMapEvolutionRequest] = []
    private(set) var generationRequests: [QuestionGenerationRequest] = []
    private(set) var events: [String] = []

    init(
        delayNanoseconds: UInt64 = 0,
        shouldFailEvolution: Bool = false,
        evolutionError: QuestionGenerationError? = nil,
        replacementLimit: Int? = nil
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.evolutionError = evolutionError ?? (shouldFailEvolution ? .serviceUnavailable : nil)
        self.replacementLimit = replacementLimit
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        events.append("generation")
        generationRequests.append(request)
        return []
    }

    func evolveSkillMap(for request: SkillMapEvolutionRequest) async throws -> SkillMapEvolutionProposal {
        events.append("evolution")
        evolutionRequests.append(request)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let evolutionError {
            throw evolutionError
        }
        guard let currentMap = request.goal.derivedSkillMap else {
            throw QuestionGenerationError.badResponse
        }

        let replacementIDs = Array(
            request.masteredSkillIDs.prefix(replacementLimit ?? request.masteredSkillIDs.count)
        )
        var evolvedTopics = currentMap.topics
        var replacements: [SkillMapEvolutionReplacement] = []
        for predecessorID in replacementIDs {
            guard let topicIndex = evolvedTopics.firstIndex(where: { $0.id == predecessorID }) else {
                throw QuestionGenerationError.badResponse
            }
            let predecessor = evolvedTopics[topicIndex]
            let successor = SkillMapTopic(
                name: "Advanced \(predecessor.name)",
                objectives: [
                    SkillMapObjective(name: "Apply \(predecessor.name)"),
                    SkillMapObjective(name: "Analyze advanced \(predecessor.name)")
                ]
            )
            evolvedTopics[topicIndex] = successor
            replacements.append(
                SkillMapEvolutionReplacement(
                    predecessorSkillID: predecessorID,
                    successorSkillID: successor.id
                )
            )
        }
        return SkillMapEvolutionProposal(
            baseMapFingerprint: request.baseMapFingerprint,
            baseVersion: currentMap.version,
            topics: evolvedTopics,
            replacements: replacements
        )
    }
}
