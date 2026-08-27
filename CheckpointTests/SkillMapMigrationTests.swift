import XCTest
@testable import Checkpoint

final class SkillMapMigrationTests: CheckpointWorkflowTestCase {
    @MainActor
    func testReviewingInferredSkillMapPreservesIdentityMasteryAndTopOffProgress() async throws {
        let backendEngine = SkillMapQuestionEngine(
            provider: .backend,
            topics: ["argument flaws", "conditional logic", "inference", "reading structure"],
            largeRequestDelayNanoseconds: 250_000_000
        )
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
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice,
            waitForQuestionGeneration: true
        )

        let suggestedMap = try XCTUnwrap(store.goal?.derivedSkillMap)
        let originalSkill = try XCTUnwrap(
            suggestedMap.topics.first(where: { $0.name == "argument flaws" })
        )
        let firstQuestion = try XCTUnwrap(
            store.activeQuestions.first(where: { $0.topic == originalSkill.name })
        )
        _ = store.submitAnswer(
            question: firstQuestion,
            answer: firstQuestion.expectedAnswer,
            result: .correct
        )

        var reviewedTopics = suggestedMap.topics
        let renamedIndex = try XCTUnwrap(
            reviewedTopics.firstIndex(where: { $0.id == originalSkill.id })
        )
        reviewedTopics[renamedIndex].name = "causal argument analysis"

        XCTAssertTrue(store.reviewActiveDerivedSkillMap(topics: reviewedTopics))

        let reviewedGoal = try XCTUnwrap(store.goal)
        let reviewedMap = try XCTUnwrap(reviewedGoal.derivedSkillMap)
        let renamedSkill = try XCTUnwrap(
            reviewedMap.topics.first(where: { $0.id == originalSkill.id })
        )
        XCTAssertEqual(reviewedMap.status, .reviewed)
        XCTAssertEqual(renamedSkill.name, "causal argument analysis")
        XCTAssertTrue(renamedSkill.aliases.contains("argument flaws"))
        XCTAssertEqual(Set(reviewedMap.topics.map(\.id)), Set(suggestedMap.topics.map(\.id)))
        XCTAssertEqual(reviewedGoal.focusAreas, "")
        XCTAssertTrue(
            store.activeQuestions
                .filter { $0.id == firstQuestion.id }
                .allSatisfy { $0.topic == renamedSkill.name }
        )

        var renamedCompetency = try XCTUnwrap(
            store.sortedCompetencies.first(where: { $0.skillID == originalSkill.id })
        )
        XCTAssertEqual(renamedCompetency.topic, renamedSkill.name)
        XCTAssertEqual(renamedCompetency.attempts, 1)
        XCTAssertEqual(renamedCompetency.correct, 1)

        try? await Task.sleep(nanoseconds: 800_000_000)

        renamedCompetency = try XCTUnwrap(
            store.sortedCompetencies.first(where: { $0.skillID == originalSkill.id })
        )
        XCTAssertEqual(renamedCompetency.attempts, 1)
        XCTAssertEqual(renamedCompetency.correct, 1)
        XCTAssertFalse(store.isQuestionBankTopOffInProgress)
        XCTAssertEqual(backendEngine.receivedRequests.count, 3)
        XCTAssertGreaterThan(store.activeQuestions.count, UnlockPolicy.default.questionsPerSession)

        let restoredStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        let restoredMap = try XCTUnwrap(restoredStore.goal?.derivedSkillMap)
        let restoredCompetency = try XCTUnwrap(
            restoredStore.sortedCompetencies.first(where: { $0.skillID == originalSkill.id })
        )
        XCTAssertEqual(restoredMap.status, .reviewed)
        XCTAssertEqual(Set(restoredMap.topics.map(\.id)), Set(suggestedMap.topics.map(\.id)))
        XCTAssertEqual(restoredCompetency.topic, renamedSkill.name)
        XCTAssertEqual(restoredCompetency.attempts, 1)
        XCTAssertEqual(restoredCompetency.correct, 1)
    }

    @MainActor
    func testBroadInferenceFailureCreatesNoPlaceholderCompetency() async throws {
        let backendEngine = SkillMapQuestionEngine(provider: .backend, topics: ["LSAT"])
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
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice,
            waitForQuestionGeneration: true
        )

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(store.goal?.derivedSkillMap)
        XCTAssertTrue(store.sortedCompetencies.isEmpty)
        XCTAssertNil(store.activeGoalFocusText)
        XCTAssertTrue(store.activeSkillMapNeedsAttention)
    }

    @MainActor
    func testLegacyBlankFocusGoalMigratesQuestionTopicsIntoStableSkillMap() throws {
        let legacyGoal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice
        )
        let seededStore = CheckpointStore(defaults: defaults)
        seededStore.goal = legacyGoal
        seededStore.goalProfiles = [legacyGoal]
        seededStore.questions = [
            makeQuestion(goal: legacyGoal, index: 1, topic: "argument flaws"),
            makeQuestion(goal: legacyGoal, index: 2, topic: "conditional logic"),
            makeQuestion(goal: legacyGoal, index: 3, topic: "inference"),
            makeQuestion(goal: legacyGoal, index: 4, topic: "reading structure")
        ]
        seededStore.competencies = [
            TopicCompetency.initial(topic: legacyGoal.title, goalID: legacyGoal.id),
            TopicCompetency(
                goalID: legacyGoal.id,
                topic: "argument flaws",
                estimatedLevel: 2.5,
                attempts: 2,
                correct: 1,
                partial: 0,
                incorrect: 1,
                currentStreak: 0,
                lastResult: .incorrect,
                lastPracticedAt: Date()
            )
        ]
        seededStore.updateAIProviderPreference(.backend)

        let restoredStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )

        let migratedMap = try XCTUnwrap(restoredStore.goal?.derivedSkillMap)
        XCTAssertEqual(
            Set(migratedMap.topicNames),
            ["argument flaws", "conditional logic", "inference", "reading structure"]
        )
        XCTAssertFalse(restoredStore.sortedCompetencies.contains { $0.topic == legacyGoal.title })
        XCTAssertTrue(restoredStore.sortedCompetencies.allSatisfy { $0.skillID != nil })
        let practicedCompetency = try XCTUnwrap(
            restoredStore.sortedCompetencies.first(where: { $0.topic == "argument flaws" })
        )
        XCTAssertEqual(practicedCompetency.attempts, 2)
        XCTAssertEqual(practicedCompetency.correct, 1)
        XCTAssertEqual(practicedCompetency.incorrect, 1)
    }

    @MainActor
    func testLegacyQuestionTopicMigrationAcceptsShortSkillNames() throws {
        let legacyGoal = Goal(
            title: "Prepare for a technical assessment",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice
        )
        let shortTopics = ["AI", "R", "C"]
        let seededStore = CheckpointStore(defaults: defaults)
        seededStore.goal = legacyGoal
        seededStore.goalProfiles = [legacyGoal]
        seededStore.questions = shortTopics.enumerated().map { index, topic in
            makeQuestion(goal: legacyGoal, index: index, topic: topic)
        }
        seededStore.updateAIProviderPreference(.backend)

        let restoredStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        let migratedMap = try XCTUnwrap(restoredStore.goal?.derivedSkillMap)

        XCTAssertEqual(migratedMap.topicNames, shortTopics)
        XCTAssertEqual(migratedMap.provenance, .questionTopics)
        XCTAssertTrue(restoredStore.activeQuestions.allSatisfy { $0.skillID != nil })
    }

    @MainActor
    func testLegacyExplicitFocusAreasMigrateIntoReviewedStableSkillMap() throws {
        let focusTopics = ["argument analysis", "conditional logic", "reading structure"]
        let legacyGoal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: focusTopics.joined(separator: ", "),
            preferredQuestionStyle: .multipleChoice
        )
        let seededStore = CheckpointStore(defaults: defaults)
        seededStore.goal = legacyGoal
        seededStore.goalProfiles = [legacyGoal]
        seededStore.questions = focusTopics.enumerated().map { index, topic in
            makeQuestion(goal: legacyGoal, index: index, topic: topic)
        }
        var practiced = TopicCompetency.initial(
            topic: focusTopics[0],
            goalID: legacyGoal.id
        )
        practiced.attempts = 3
        practiced.correct = 2
        practiced.incorrect = 1
        seededStore.competencies = [practiced]
        seededStore.updateAIProviderPreference(.backend)

        let restoredStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        let migratedMap = try XCTUnwrap(restoredStore.goal?.derivedSkillMap)

        XCTAssertEqual(migratedMap.topicNames, focusTopics)
        XCTAssertEqual(migratedMap.status, .reviewed)
        XCTAssertEqual(migratedMap.provenance, .explicitFocusAreas)
        XCTAssertTrue(migratedMap.topics.allSatisfy { skill in
            skill.objectives.count == 1 && skill.objectives.first?.id == skill.id
        })
        XCTAssertTrue(restoredStore.activeQuestions.allSatisfy { question in
            question.skillID != nil && question.objectiveID == question.skillID
        })
        XCTAssertEqual(
            restoredStore.competencies.first(where: { $0.topic == focusTopics[0] })?.attempts,
            3
        )

        let stableMap = migratedMap
        restoredStore.updateAIProviderPreference(.backend)
        let secondRestore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        XCTAssertEqual(secondRestore.goal?.derivedSkillMap, stableMap)
    }

    @MainActor
    func testLegacySkillMapSeedsStableObjectivesAndCanonicalQuestionTags() throws {
        let topics = ["argument analysis", "conditional logic", "reading structure"].map {
            SkillMapTopic(name: $0)
        }
        let legacyMap = GoalSkillMap(
            topics: topics,
            status: .suggested,
            version: 1,
            provenance: .questionTopics
        )
        let goal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "",
            derivedSkillMap: legacyMap,
            preferredQuestionStyle: .multipleChoice
        )
        let seededStore = CheckpointStore(defaults: defaults)
        seededStore.goal = goal
        seededStore.goalProfiles = [goal]
        seededStore.questions = (0..<5).map { index in
            makeQuestion(
                goal: goal,
                index: index,
                topic: topics[index % topics.count].name
            )
        }
        seededStore.updateAIProviderPreference(.backend)

        let restoredStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        let restoredMap = try XCTUnwrap(restoredStore.goal?.derivedSkillMap)
        XCTAssertEqual(restoredMap.version, 2)
        XCTAssertTrue(restoredMap.topics.allSatisfy { skill in
            skill.objectives.count == 1 && skill.objectives.first?.id == skill.id
        })
        XCTAssertTrue(restoredStore.activeQuestions.allSatisfy { question in
            question.skillID != nil && question.objectiveID == question.skillID
        })

        let stableObjectiveIDs = restoredMap.topics.flatMap(\.objectives).map(\.id)
        restoredStore.updateAIProviderPreference(.backend)
        let secondRestore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        XCTAssertEqual(secondRestore.goal?.derivedSkillMap?.version, 2)
        XCTAssertEqual(
            secondRestore.goal?.derivedSkillMap?.topics.flatMap(\.objectives).map(\.id),
            stableObjectiveIDs
        )
    }

    @MainActor
    func testTopOffCommitsSkillMapAsSoonAsCombinedTopicsAreConcrete() async throws {
        let backendEngine = PhasedSkillMapQuestionEngine(
            provider: .backend,
            topicsByRequest: [
                ["LSAT"],
                ["argument flaws", "conditional logic", "inference", "reading structure"]
            ],
            largeRequestDelayNanoseconds: 150_000_000
        )
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
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice,
            waitForQuestionGeneration: true
        )

        XCTAssertNil(store.goal?.derivedSkillMap)
        XCTAssertTrue(store.isBuildingActiveSkillMap)

        try? await Task.sleep(nanoseconds: 350_000_000)

        let resolvedMap = try XCTUnwrap(store.goal?.derivedSkillMap)
        XCTAssertEqual(
            Set(resolvedMap.topicNames),
            ["argument flaws", "conditional logic", "inference", "reading structure"]
        )
        XCTAssertFalse(store.isBuildingActiveSkillMap)
        XCTAssertFalse(GoalQuestionContext(goal: try XCTUnwrap(store.goal)).needsGeneratedSkillMap)
        XCTAssertEqual(
            Set(store.sortedCompetencies.compactMap(\.skillID)),
            Set(resolvedMap.topics.map(\.id))
        )
        XCTAssertFalse(store.activeQuestions.isEmpty)
        XCTAssertTrue(
            store.activeQuestions
                .filter { $0.status != .retired }
                .allSatisfy { resolvedMap.topicNames.contains($0.topic) }
        )
        XCTAssertTrue(
            store.activeQuestions
                .filter { $0.topic == "LSAT" }
                .allSatisfy { $0.status == .retired }
        )

        let restoredStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(restoredStore.goal?.derivedSkillMap).topics.map(\.id)),
            Set(resolvedMap.topics.map(\.id))
        )
    }

    @MainActor
    func testRepairingSkillMapKeepsGoalAndHistoryForStarter() async throws {
        let backendEngine = SkillMapQuestionEngine(
            provider: .backend,
            topics: ["argument flaws", "conditional logic", "inference", "reading structure"]
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.backend)
        let originalGoal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice
        )
        let originalQuestion = makeQuestion(goal: originalGoal, index: 1, topic: "LSAT")
        let originalAttempt = makeAttempt(
            goal: originalGoal,
            questionID: originalQuestion.id,
            result: .incorrect,
            createdAt: Date()
        )
        store.goal = originalGoal
        store.goalProfiles = [originalGoal]
        store.questions = [originalQuestion]
        store.attempts = [originalAttempt]
        store.competencies = [
            TopicCompetency(
                goalID: originalGoal.id,
                topic: "General progress",
                estimatedLevel: 2,
                attempts: 1,
                correct: 0,
                partial: 0,
                incorrect: 1,
                currentStreak: 0,
                lastResult: .incorrect,
                lastPracticedAt: Date()
            )
        ]

        XCTAssertTrue(
            store.repairActiveSkillMap(
                topicNames: ["argument flaws", "conditional logic", "inference", "reading structure"]
            )
        )
        XCTAssertEqual(store.goal?.id, originalGoal.id)
        XCTAssertEqual(store.attempts, [originalAttempt])
        XCTAssertEqual(store.pendingMembershipFeature, .freshQuestionGeneration)

        try? await Task.sleep(nanoseconds: 200_000_000)

        let repairedGoal = try XCTUnwrap(store.goal)
        let repairedMap = try XCTUnwrap(repairedGoal.derivedSkillMap)
        XCTAssertEqual(repairedGoal.id, originalGoal.id)
        XCTAssertEqual(repairedMap.status, .reviewed)
        XCTAssertEqual(repairedGoal.focusAreas, "")
        XCTAssertEqual(store.attempts, [originalAttempt])
        XCTAssertTrue(backendEngine.receivedRequests.isEmpty)
        let preservedHistory = try XCTUnwrap(
            store.competencies.first(where: { $0.topic == "General progress" })
        )
        XCTAssertEqual(preservedHistory.attempts, 1)
        XCTAssertEqual(preservedHistory.incorrect, 1)
        XCTAssertEqual(
            store.questions.first(where: { $0.id == originalQuestion.id })?.status,
            .retired
        )
        XCTAssertTrue(store.nextQuestions(limit: 5).allSatisfy {
            repairedMap.topicNames.contains($0.topic)
        })
    }

    @MainActor
    func testSwappingSkillNamesCannotRouteAnswersThroughOldAliases() throws {
        let firstSkill = SkillMapTopic(name: "argument flaws")
        let secondSkill = SkillMapTopic(name: "conditional logic")
        let thirdSkill = SkillMapTopic(name: "reading structure")
        let initialMap = GoalSkillMap(topics: [firstSkill, secondSkill, thirdSkill])
        let goal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "",
            focusAreas: "",
            derivedSkillMap: initialMap,
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.competencies = initialMap.topics.map {
            TopicCompetency.initial(topic: $0.name, goalID: goal.id, skillID: $0.id)
        }

        var swappedTopics = initialMap.topics
        swappedTopics[0].name = secondSkill.name
        swappedTopics[1].name = firstSkill.name
        XCTAssertTrue(store.reviewActiveDerivedSkillMap(topics: swappedTopics))

        let reviewedGoal = try XCTUnwrap(store.goal)
        let reviewedMap = try XCTUnwrap(reviewedGoal.derivedSkillMap)
        XCTAssertFalse(
            reviewedMap.topics
                .first(where: { $0.id == firstSkill.id })?
                .aliases
                .contains(firstSkill.name) ?? true
        )
        XCTAssertFalse(
            reviewedMap.topics
                .first(where: { $0.id == secondSkill.id })?
                .aliases
                .contains(secondSkill.name) ?? true
        )

        let question = makeQuestion(
            goal: reviewedGoal,
            index: 50,
            topic: firstSkill.name
        )
        store.questions.append(question)
        _ = store.submitAnswer(
            question: question,
            answer: question.expectedAnswer,
            result: .correct
        )

        XCTAssertEqual(
            store.competencies.first(where: { $0.skillID == firstSkill.id })?.attempts,
            0
        )
        XCTAssertEqual(
            store.competencies.first(where: { $0.skillID == secondSkill.id })?.attempts,
            1
        )
    }

    @MainActor
    func testLegacyMigrationSplitsCompoundTopicsWithoutLosingMastery() throws {
        let legacyGoal = Goal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice
        )
        let seededStore = CheckpointStore(defaults: defaults)
        seededStore.goal = legacyGoal
        seededStore.goalProfiles = [legacyGoal]
        seededStore.questions = [
            makeQuestion(goal: legacyGoal, index: 1, topic: "arrays, recursion"),
            makeQuestion(goal: legacyGoal, index: 2, topic: "graphs"),
            makeQuestion(goal: legacyGoal, index: 3, topic: "hashing")
        ]
        var arrays = TopicCompetency.initial(topic: "arrays", goalID: legacyGoal.id)
        arrays.attempts = 2
        arrays.correct = 2
        var recursion = TopicCompetency.initial(topic: "recursion", goalID: legacyGoal.id)
        recursion.attempts = 1
        recursion.incorrect = 1
        seededStore.competencies = [arrays, recursion]
        seededStore.updateAIProviderPreference(.backend)

        let restoredStore = CheckpointStore(defaults: defaults)
        let migratedMap = try XCTUnwrap(restoredStore.goal?.derivedSkillMap)
        XCTAssertEqual(Set(migratedMap.topicNames), ["arrays", "recursion", "graphs", "hashing"])
        XCTAssertTrue(migratedMap.topicNames.allSatisfy { !$0.contains(",") })
        XCTAssertEqual(
            restoredStore.competencies.first(where: { $0.topic == "arrays" })?.attempts,
            2
        )
        XCTAssertEqual(
            restoredStore.competencies.first(where: { $0.topic == "recursion" })?.incorrect,
            1
        )
    }

    @MainActor
    func testLegacyMigrationWithMoreThanSixTopicsPreservesAllHistory() throws {
        let legacyGoal = Goal(
            title: "Learn computer science",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .custom,
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice
        )
        let topicNames = [
            "arrays", "recursion", "graphs", "hashing", "sorting", "trees", "dynamic programming"
        ]
        let seededStore = CheckpointStore(defaults: defaults)
        seededStore.goal = legacyGoal
        seededStore.goalProfiles = [legacyGoal]
        seededStore.questions = topicNames.enumerated().map { index, topic in
            makeQuestion(goal: legacyGoal, index: index + 1, topic: topic)
        }
        seededStore.competencies = topicNames.map { topic in
            var competency = TopicCompetency.initial(topic: topic, goalID: legacyGoal.id)
            competency.attempts = 1
            competency.correct = 1
            return competency
        }
        seededStore.updateAIProviderPreference(.backend)

        let restoredStore = CheckpointStore(defaults: defaults)

        XCTAssertNil(restoredStore.goal?.derivedSkillMap)
        XCTAssertEqual(Set(restoredStore.sortedCompetencies.map(\.topic)), Set(topicNames))
        XCTAssertTrue(restoredStore.sortedCompetencies.allSatisfy { $0.attempts == 1 })
        XCTAssertTrue(restoredStore.activeSkillMapNeedsAttention)
    }

    @MainActor
    func testInitialGenerationRestartsAfterSameGoalDifficultyChanges() async throws {
        let backendEngine = SkillMapQuestionEngine(
            provider: .backend,
            topics: ["argument flaws", "conditional logic", "inference", "reading structure"],
            requestDelayNanoseconds: 150_000_000
        )
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
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2,
            waitForQuestionGeneration: false
        )
        let originalGoalID = try XCTUnwrap(store.goal?.id)
        store.updateMinimumQuestionDifficulty(4)

        try? await Task.sleep(nanoseconds: 650_000_000)

        XCTAssertEqual(store.goal?.id, originalGoalID)
        XCTAssertEqual(store.goal?.minimumQuestionDifficulty, 4)
        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertTrue(store.activeQuestions.allSatisfy { $0.difficulty >= 4 })
        XCTAssertTrue(
            backendEngine.receivedRequests.contains {
                $0.targetCount == UnlockPolicy.default.questionsPerSession && $0.minimumDifficulty == 2
            }
        )
        XCTAssertTrue(
            backendEngine.receivedRequests.contains {
                $0.targetCount == UnlockPolicy.default.questionsPerSession && $0.minimumDifficulty == 4
            }
        )
    }

    func testSkillMapValidationUsesPersistedNameNormalization() {
        XCTAssertNil(
            SkillMapTopic.validatedNames(["Algebra", "Algebra.", "Geometry"])
        )
    }

    @MainActor
    func testGoalFocusTextUsesUserFocusAreasWhenProvided() {
        let store = CheckpointStore(defaults: defaults)

        store.goal = makeGoal()

        XCTAssertEqual(store.activeGoalFocusText, "arrays, recursion, hash maps")
    }

    @MainActor
    func testGoalFocusTextHidesWhenNoFocusOrGeneratedSkillMapExists() {
        let store = CheckpointStore(defaults: defaults)
        store.goal = Goal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "",
            focusAreas: "",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertNil(store.activeGoalFocusText)
    }

    @MainActor
    func testSkillMapIgnoresPlaceholderFocusAreas() async {
        let backendEngine = SkillMapQuestionEngine(
            provider: .backend,
            topics: ["process scheduling", "virtual memory", "concurrency", "file systems"]
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: backendEngine,
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )

        await store.createGoal(
            title: "Pass operating systems exam",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "",
            focusAreas: "???, asdf, none",
            preferredQuestionStyle: .multipleChoice,
            waitForQuestionGeneration: true
        )

        let topics = Set(store.sortedCompetencies.map(\.topic))
        XCTAssertFalse(topics.contains("asdf"))
        XCTAssertEqual(
            topics,
            ["process scheduling", "virtual memory", "concurrency", "file systems"]
        )
        XCTAssertTrue(backendEngine.receivedRequests.first?.questionContext.needsGeneratedSkillMap ?? false)
    }

}
