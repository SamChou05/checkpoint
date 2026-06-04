import XCTest
@testable import Checkpoint

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

final class CheckpointWorkflowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "CheckpointTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        resetSharedAppGroupState()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        resetSharedAppGroupState()
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    @MainActor
    func testLocalTemplatesCreateUsableNoCostQuestionBank() async {
        let store = CheckpointStore(defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate on arrays, weak at recursion",
            focusAreas: "arrays, recursion, hash maps",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertEqual(store.lastQuestionProvider, .localTemplates)
        XCTAssertGreaterThanOrEqual(store.questions.count, 5)
        XCTAssertTrue(store.backendEndpoint.isEmpty)
        XCTAssertTrue(store.questions.allSatisfy { question in
            question.format == .multipleChoice
                && question.choices.count == 4
                && hasUniqueTestChoices(question.choices)
                && question.choices.contains(question.expectedAnswer)
                && !question.explanation.isEmpty
                && !question.topic.isEmpty
        })
    }

    @MainActor
    func testCreateGoalRejectsBlankTitle() async {
        let store = CheckpointStore(defaults: defaults)

        await store.createGoal(
            title: "   ",
            deadline: Date().addingTimeInterval(-60),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertNil(store.goal)
        XCTAssertEqual(store.questionBatchState, .failed)
        XCTAssertEqual(store.lastAIErrorMessage, "Enter a goal before generating questions.")
    }

    @MainActor
    func testStarterCanCreateFirstGoalAndStarterQuestionBank() async throws {
        let store = CheckpointStore(defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)

        await store.createGoal(
            title: "Pass the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate logical reasoning",
            focusAreas: "logical reasoning",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertEqual(store.membershipTier, .starter)
        XCTAssertFalse(store.isMember)
        XCTAssertFalse(store.hasFullProductAccess)
        XCTAssertFalse(store.canRefreshQuestionBatch)
        XCTAssertEqual(store.questionBankTargetCount, ProductLimits.starterQuestionBankTargetCount)
        XCTAssertNotNil(store.goal)
        XCTAssertGreaterThanOrEqual(store.activeQuestions.count, 5)
        XCTAssertNil(store.pendingMembershipFeature)
    }

    @MainActor
    func testStarterRequestsMembershipForSecondGoal() async throws {
        let store = CheckpointStore(defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays",
            preferredQuestionStyle: .multipleChoice
        )
        let firstGoal = try XCTUnwrap(store.goal)

        await store.createGoal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "integrals",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertEqual(store.goal?.id, firstGoal.id)
        XCTAssertEqual(store.availableGoalProfiles.count, 1)
        XCTAssertEqual(store.pendingMembershipFeature, .goalProfiles)
        XCTAssertTrue(store.checkpointNotice?.contains("first goal is included") ?? false)
    }

    @MainActor
    func testStarterRequestsMembershipWhenCoreQuestionsAreUsedUp() async throws {
        let goal = makeGoal()
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.goal = goal
        store.questions = [makeQuestion(goal: goal, index: 1, status: .retired)]

        let session = await store.prepareManualCheckpointSession()

        XCTAssertNil(session)
        XCTAssertNil(localEngine.receivedRequest)
        XCTAssertEqual(store.pendingMembershipFeature, .freshQuestionGeneration)
        XCTAssertTrue(store.checkpointNotice?.contains("Membership keeps fresh checkpoints") ?? false)
    }

    @MainActor
    func testCreateGoalCanReturnBeforeInitialQuestionsFinish() async {
        let delayedEngine = DelayedQuestionEngine(
            provider: .localTemplates,
            delayNanoseconds: 150_000_000
        )
        let engine = HybridQuestionEngine(
            localEngine: delayedEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)

        await store.createGoal(
            title: "Pass the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate logical reasoning",
            focusAreas: "logical reasoning",
            preferredQuestionStyle: .multipleChoice,
            waitForQuestionGeneration: false
        )

        XCTAssertNotNil(store.goal)
        XCTAssertFalse(store.isOnboardingPresented)
        XCTAssertEqual(store.questionBatchState, .generating)
        XCTAssertTrue(store.questionGenerationStatusText.contains("background"))
        XCTAssertTrue(store.questions.isEmpty)

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertGreaterThanOrEqual(store.questions.count, 5)
        XCTAssertNotNil(store.lastQuestionGenerationDuration)
    }

    @MainActor
    func testCreateGoalWarmStartsLocalQuestionsWhileAIContinues() async throws {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            localEngine: GoalAwareQuestionEngine(provider: .localTemplates),
            backendEngine: DelayedQuestionEngine(provider: .backend, delayNanoseconds: 500_000_000),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.automatic)

        await store.createGoal(
            title: goal.title,
            deadline: goal.deadline,
            category: goal.category,
            currentLevel: goal.currentLevel,
            focusAreas: goal.focusAreas,
            preferredQuestionStyle: goal.preferredQuestionStyle,
            waitForQuestionGeneration: false
        )

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertTrue(store.isQuestionBankTopOffInProgress)
        XCTAssertGreaterThanOrEqual(store.activeQuestions.count, 5)
        XCTAssertTrue(store.questionGenerationStatusText.contains("building the question bank"))

        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertFalse(store.isQuestionBankTopOffInProgress)
        XCTAssertGreaterThan(store.activeQuestions.count, 6)
        XCTAssertEqual(store.activeQuestions.filter { $0.status == .retired }.count, 5)
        XCTAssertTrue(
            try XCTUnwrap(store.nextCheckpointSession()).questions.allSatisfy {
                $0.prompt.contains("delayed question")
            }
        )
        XCTAssertNotNil(store.lastQuestionGenerationDuration)
        XCTAssertNotNil(store.lastQuestionBankTopOffDuration)
    }

    @MainActor
    func testSwitchingToGoalWithoutQuestionsStartsBackgroundPreparation() async {
        let delayedEngine = DelayedQuestionEngine(
            provider: .localTemplates,
            delayNanoseconds: 150_000_000
        )
        let engine = HybridQuestionEngine(
            localEngine: delayedEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)
        let firstGoal = makeGoal()
        let secondGoal = Goal(
            title: "Pass operating systems exam",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 21),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "interrupts, system calls",
            preferredQuestionStyle: .multipleChoice
        )
        store.goal = firstGoal
        store.goalProfiles = [firstGoal, secondGoal]

        store.switchActiveGoal(to: secondGoal.id)

        XCTAssertEqual(store.goal?.id, secondGoal.id)
        XCTAssertEqual(store.questionBatchState, .generating)
        XCTAssertTrue(store.questionGenerationStatusText.contains("background"))
        XCTAssertTrue(store.activeQuestions.isEmpty)

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertGreaterThanOrEqual(store.activeQuestions.count, 5)
        XCTAssertNotNil(store.lastQuestionGenerationDuration)
    }

    @MainActor
    func testCreateGoalInfersCategoryFromNaturalLanguageContext() async throws {
        let store = CheckpointStore(defaults: defaults)

        await store.createGoal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            currentLevel: "Strong on logic games, weak on timed reading sections",
            focusAreas: "logical reasoning, reading comprehension",
            preferredQuestionStyle: .multipleChoice
        )

        let goal = try XCTUnwrap(store.goal)
        XCTAssertEqual(goal.category, .examPrep)
    }

    @MainActor
    func testGoalWithoutFocusAreasUsesProviderQuestionTopicsForInitialSkillMap() async throws {
        let backendEngine = SkillMapQuestionEngine(
            provider: .backend,
            topics: ["argument flaws", "conditional logic", "inference", "reading structure"]
        )
        let localEngine = SkillMapQuestionEngine(
            provider: .localTemplates,
            topics: ["generic fallback"]
        )
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                localEngine: localEngine,
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

        let initialRequest = try XCTUnwrap(backendEngine.receivedRequests.first)
        XCTAssertTrue(initialRequest.questionContext.needsGeneratedSkillMap)
        XCTAssertEqual(initialRequest.targetCount, 5)
        XCTAssertTrue(localEngine.receivedRequests.isEmpty)
        XCTAssertEqual(
            Set(store.sortedCompetencies.map(\.topic)),
            ["argument flaws", "conditional logic", "inference", "reading structure"]
        )
        XCTAssertEqual(store.activeGoalFocusText, "argument flaws")
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
        let store = CheckpointStore(defaults: defaults)

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
        XCTAssertFalse(topics.isEmpty)
        XCTAssertTrue(topics.allSatisfy { $0.hasPrefix("operating systems") })
    }

    @MainActor
    func testWeeklyMetricsOnlyUseCurrentGoalAttemptsFromThisWeek() {
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
        let lastWeek = Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? Date.distantPast

        store.goal = goal
        store.attempts = [
            makeAttempt(goal: goal, result: .correct, createdAt: Date()),
            makeAttempt(goal: goal, result: .incorrect, createdAt: Date()),
            makeAttempt(goal: goal, result: .correct, createdAt: lastWeek),
            makeAttempt(goal: otherGoal, result: .correct, createdAt: Date())
        ]

        XCTAssertEqual(store.questionsAnsweredThisWeekCount, 2)
        XCTAssertEqual(store.questionAccuracyThisWeekText, "50%")
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

    @MainActor
    func testSwitchingActiveGoalRebuildsPracticeSetAndSkillMap() async throws {
        let engine = GoalAwareQuestionEngine(provider: .localTemplates)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                localEngine: engine,
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays, recursion",
            preferredQuestionStyle: .multipleChoice
        )

        let firstGoal = try XCTUnwrap(store.goal)
        let firstQuestion = try XCTUnwrap(store.questions.first)
        XCTAssertEqual(Set(store.competencies.map(\.topic)), ["arrays", "recursion"])

        _ = store.submitAnswer(question: firstQuestion, answer: firstQuestion.expectedAnswer, result: .correct)
        store.reportQuestion(firstQuestion, reason: .confusing, note: "stale")

        XCTAssertFalse(store.attempts.isEmpty)
        XCTAssertFalse(store.questionReports.isEmpty)
        XCTAssertNotNil(store.unlockSession)
        XCTAssertNotNil(SharedAppGroup.unlockExpiration)

        await store.createGoal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Comfortable with derivatives, weak on integrals",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice
        )

        let secondGoal = try XCTUnwrap(store.goal)
        XCTAssertNotEqual(secondGoal.id, firstGoal.id)
        XCTAssertEqual(secondGoal.title, "Prepare for calculus final")
        XCTAssertTrue(store.activeQuestions.allSatisfy { $0.goalID == secondGoal.id })
        XCTAssertEqual(Set(store.activeQuestions.map(\.topic)), ["derivatives", "integrals"])
        XCTAssertEqual(Set(store.sortedCompetencies.map(\.topic)), ["derivatives", "integrals"])
        XCTAssertTrue(store.activeAttempts.isEmpty)
        XCTAssertTrue(store.activeQuestionReports.isEmpty)
        XCTAssertNil(store.unlockSession)
        XCTAssertNil(SharedAppGroup.unlockExpiration)

        let session = try XCTUnwrap(store.nextCheckpointSession())
        XCTAssertTrue(session.questions.allSatisfy { $0.goalID == secondGoal.id })
        XCTAssertTrue(session.questions.allSatisfy { ["derivatives", "integrals"].contains($0.topic) })
    }

    @MainActor
    func testGoalProfilesPreserveSeparateQuestionPoolsSkillMapsAndDifficulty() async throws {
        let engine = GoalAwareQuestionEngine(provider: .localTemplates)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                localEngine: engine,
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Advanced on arrays, weak at recursion",
            focusAreas: "arrays, recursion",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 4
        )

        let firstGoal = try XCTUnwrap(store.goal)
        let firstQuestion = try XCTUnwrap(store.activeQuestions.first)
        _ = store.submitAnswer(question: firstQuestion, answer: firstQuestion.expectedAnswer, result: .correct)
        store.reportQuestion(firstQuestion, reason: .confusing, note: "too vague")

        await store.createGoal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Comfortable with derivatives, weak on integrals",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )

        let secondGoal = try XCTUnwrap(store.goal)
        XCTAssertNotEqual(secondGoal.id, firstGoal.id)
        XCTAssertEqual(store.availableGoalProfiles.count, 2)
        XCTAssertEqual(store.activeQuestionDifficulty, 2)
        XCTAssertTrue(store.activeQuestions.allSatisfy { $0.goalID == secondGoal.id })
        XCTAssertEqual(Set(store.sortedCompetencies.map(\.topic)), ["derivatives", "integrals"])
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
        XCTAssertEqual(Set(store.sortedCompetencies.map(\.topic)), ["arrays", "recursion"])
        XCTAssertEqual(store.activeAttempts.count, 1)
        XCTAssertEqual(store.activeQuestionReports.count, 1)

        let session = try XCTUnwrap(store.nextCheckpointSession())
        XCTAssertTrue(session.questions.allSatisfy { $0.goalID == firstGoal.id })
        XCTAssertTrue(session.questions.allSatisfy { $0.difficulty >= 4 })
    }

    @MainActor
    func testSwitchingGoalUsesCachedQuestionBankWithoutRegeneration() async throws {
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                localEngine: localEngine,
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateAIProviderPreference(.localTemplates)
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
        let secondQuestions = (1...12).map { index in
            makeQuestion(goal: secondGoal, index: index, topic: "integrals", difficulty: 2)
        }

        store.goal = firstGoal
        store.goalProfiles = [firstGoal, secondGoal]
        store.questions = firstQuestions + secondQuestions

        store.switchActiveGoal(to: secondGoal.id)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.goal?.id, secondGoal.id)
        XCTAssertEqual(store.questionBatchState, .ready)
        XCTAssertEqual(Set(store.activeQuestions.map(\.id)), Set(secondQuestions.map(\.id)))
        XCTAssertEqual(store.usableQuestionCount(for: secondGoal), secondQuestions.count)
        XCTAssertTrue(localEngine.receivedRequests.isEmpty)
    }

    @MainActor
    func testMemberGoalProfileLimitPreventsExtraGoalAndGeneration() async throws {
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                localEngine: localEngine,
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
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
        XCTAssertTrue(localEngine.receivedRequests.isEmpty)
    }

    @MainActor
    func testGoalProfilesPersistAcrossStoreReloads() async throws {
        let engine = GoalAwareQuestionEngine(provider: .localTemplates)
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                localEngine: engine,
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )
        store.updateMembershipTier(.member)

        await store.createGoal(
            title: "Pass technical interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Advanced on arrays",
            focusAreas: "arrays, recursion",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 4
        )
        let firstGoal = try XCTUnwrap(store.goal)

        await store.createGoal(
            title: "Prepare for calculus final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "derivatives, integrals",
            preferredQuestionStyle: .multipleChoice,
            minimumQuestionDifficulty: 2
        )
        let secondGoal = try XCTUnwrap(store.goal)
        store.switchActiveGoal(to: firstGoal.id)

        let restoredStore = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                localEngine: engine,
                backendEngine: ThrowingQuestionEngine(provider: .backend),
                appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
            ),
            defaults: defaults
        )

        XCTAssertEqual(restoredStore.goal?.id, firstGoal.id)
        XCTAssertEqual(Set(restoredStore.availableGoalProfiles.map(\.id)), Set([firstGoal.id, secondGoal.id]))
        XCTAssertEqual(restoredStore.activeQuestionDifficulty, 4)
        XCTAssertTrue(restoredStore.activeQuestions.allSatisfy { $0.goalID == firstGoal.id })
        XCTAssertEqual(Set(restoredStore.sortedCompetencies.map(\.topic)), ["arrays", "recursion"])
    }

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
            "Checkpoint is preparing enough questions for the stop challenge. Try again in a moment or lower the minimum level."
        )
    }

    @MainActor
    func testStopBlockingPreparationRefillsBeforeChallenge() async throws {
        let goal = makeGoal()
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (2...20).map { makeQuestion(goal: goal, index: $0) }

        let preparedSession = await store.prepareStopBlockingSession()
        let session = try XCTUnwrap(preparedSession)

        XCTAssertEqual(session.questions.count, StopBlockingPolicy.questionsPerSession)
        XCTAssertEqual(session.unlockThreshold, StopBlockingPolicy.requiredCorrectAnswers)
        XCTAssertNotNil(localEngine.receivedRequest)
        XCTAssertNil(store.checkpointNotice)
    }

    @MainActor
    func testStarterKeepsCoreCheckpointAvailable() throws {
        let store = makeSeededStore(questionCount: 6)

        let session = try XCTUnwrap(store.nextCheckpointSession())
        XCTAssertFalse(store.hasFullProductAccess)
        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(session.unlockThreshold, 4)
        XCTAssertFalse(store.canRefreshQuestionBatch)
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
            status: .correct,
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
    func testIncorrectAnswerResetsQuestionRetirementStreak() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        var question = makeQuestion(goal: goal, index: 1, timesCorrect: 2)
        store.questions = [question]
        store.competencies = [.initial(topic: question.topic, goalID: goal.id)]

        store.submitAnswer(
            question: question,
            answer: "Wrong answer",
            result: .incorrect,
            grantsUnlock: false
        )

        var updatedQuestion = try XCTUnwrap(store.questions.first { $0.id == question.id })
        XCTAssertEqual(updatedQuestion.timesCorrect, 0)
        XCTAssertEqual(updatedQuestion.status, .incorrect)

        for expectedCorrectStreak in 1...2 {
            question = updatedQuestion
            store.submitAnswer(
                question: question,
                answer: question.expectedAnswer,
                result: .correct,
                grantsUnlock: false
            )
            updatedQuestion = try XCTUnwrap(store.questions.first { $0.id == question.id })
            XCTAssertEqual(updatedQuestion.timesCorrect, expectedCorrectStreak)
            XCTAssertEqual(updatedQuestion.status, .correct)
        }

        store.submitAnswer(
            question: updatedQuestion,
            answer: updatedQuestion.expectedAnswer,
            result: .correct,
            grantsUnlock: false
        )

        updatedQuestion = try XCTUnwrap(store.questions.first { $0.id == question.id })
        XCTAssertEqual(updatedQuestion.timesCorrect, 3)
        XCTAssertEqual(updatedQuestion.status, .retired)
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
    func testPendingShieldAttemptCreatesOneCheckpointSessionThenClears() throws {
        let store = makeSeededStore(questionCount: 6)

        SharedAppGroup.markPendingShieldAttempt()

        XCTAssertNotNil(SharedAppGroup.pendingShieldAttemptDate)
        let session = try XCTUnwrap(store.takePendingShieldSession())
        XCTAssertEqual(session.questions.count, 5)
        XCTAssertNil(SharedAppGroup.pendingShieldAttemptDate)
        XCTAssertNil(store.takePendingShieldSession())
    }

    @MainActor
    func testShieldConfigurationDiagnosticsAreRecorded() {
        XCTAssertEqual(SharedAppGroup.shieldConfigurationRenderCount, 0)
        XCTAssertNil(SharedAppGroup.shieldConfigurationRenderDate)

        SharedAppGroup.markShieldConfigurationRendered()

        XCTAssertEqual(SharedAppGroup.shieldConfigurationRenderCount, 1)
        XCTAssertNotNil(SharedAppGroup.shieldConfigurationRenderDate)
    }

    @MainActor
    func testPendingShieldAttemptWithoutQuestionsShowsRecoveryNotice() {
        let store = CheckpointStore(defaults: defaults)
        store.goal = makeGoal()

        SharedAppGroup.markPendingShieldAttempt()

        XCTAssertNil(store.takePendingShieldSession())
        XCTAssertTrue(store.checkpointNotice?.contains("Membership keeps fresh questions") ?? false)
        XCTAssertEqual(store.pendingMembershipFeature, .freshQuestionGeneration)
        XCTAssertNil(store.takePendingShieldSession())
    }

    @MainActor
    func testManualCheckpointWithoutGoalShowsRecoveryNotice() {
        let store = CheckpointStore(defaults: defaults)

        XCTAssertNil(store.startManualCheckpointSession())
        XCTAssertEqual(store.checkpointNotice, "Create a goal before starting a checkpoint.")

        store.clearCheckpointNotice()
        XCTAssertNil(store.checkpointNotice)
    }

    @MainActor
    func testScreenTimeSelectionStartsEmpty() {
        let screenTime = ScreenTimeController(defaults: defaults)

        XCTAssertFalse(screenTime.hasSelection)
        XCTAssertEqual(screenTime.restrictedAppsSummary, "No blocked apps selected")
    }

    @MainActor
    func testScreenTimeSelectionDefaultsToWholeCategoryMode() {
        #if os(iOS) && canImport(FamilyControls)
        let screenTime = ScreenTimeController(defaults: defaults)

        XCTAssertTrue(screenTime.selection.includeEntireCategory)
        #endif
    }

    @MainActor
    func testRestoredScreenTimeSelectionMigratesToWholeCategoryMode() {
        #if os(iOS) && canImport(FamilyControls)
        let legacySelection = FamilyActivitySelection()
        let data = try? JSONEncoder().encode(legacySelection)
        defaults.set(data, forKey: SharedAppGroup.screenTimeSelectionKey)

        let screenTime = ScreenTimeController(defaults: defaults)

        XCTAssertTrue(screenTime.selection.includeEntireCategory)
        #endif
    }

    @MainActor
    func testApplyShieldWithoutSelectionShowsError() {
        let screenTime = ScreenTimeController(defaults: defaults)

        screenTime.applyShield()

        XCTAssertFalse(screenTime.isShieldingEnabled)
        XCTAssertEqual(
            screenTime.lastErrorMessage,
            "Choose at least one blocked app, category, or website before starting app blocking."
        )
        XCTAssertFalse(SharedAppGroup.desiredShieldActive)
    }

    @MainActor
    func testStarterAllowsAdvancedStrictnessChanges() {
        let store = CheckpointStore(defaults: defaults)

        store.updateQuestionsPerSession(8)
        store.updateRequiredCorrectAnswers(7)

        XCTAssertEqual(store.unlockPolicy.questionsPerSession, 8)
        XCTAssertEqual(store.unlockPolicy.requiredCorrectAnswers, 7)
    }

    @MainActor
    func testMemberRefreshesAfterOldRefreshCounter() async throws {
        let goal = makeGoal()
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = [makeQuestion(goal: goal, index: 1)]
        store.questionRefreshesUsed = 2

        await store.refreshQuestionBatch()

        let request = try XCTUnwrap(localEngine.receivedRequest)
        XCTAssertEqual(request.targetCount, ProductLimits.memberQuestionBankTargetCount)
        XCTAssertEqual(store.questionRefreshesUsed, 2 + 1)
        XCTAssertEqual(store.questions.count, 2)
    }

    @MainActor
    func testMemberRefreshUsesLargerQuestionBankTarget() async throws {
        let goal = makeGoal()
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = [makeQuestion(goal: goal, index: 99)]
        store.questionRefreshesUsed = 2

        await store.refreshQuestionBatch()

        let request = try XCTUnwrap(localEngine.receivedRequest)
        XCTAssertEqual(request.targetCount, ProductLimits.memberQuestionBankTargetCount)
        XCTAssertEqual(store.questionRefreshesUsed, 2 + 1)
        XCTAssertEqual(store.questions.count, 2)
    }

    @MainActor
    func testMemberProactivelyRefreshesLowReadyQuestionBank() async throws {
        let goal = makeGoal()
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (1...store.unlockPolicy.questionsPerSession).map { makeQuestion(goal: goal, index: $0) }

        let didRefresh = await store.refreshQuestionBatchIfNeeded()

        let request = try XCTUnwrap(localEngine.receivedRequest)
        XCTAssertTrue(didRefresh)
        XCTAssertEqual(request.targetCount, ProductLimits.memberQuestionBankTargetCount)
        XCTAssertEqual(store.questions.count, store.unlockPolicy.questionsPerSession + 1)
        XCTAssertEqual(store.questionRefreshesUsed, 1)
    }

    @MainActor
    func testMemberQuietlyRefillsWhenQuestionsAreUsedUp() async throws {
        let goal = makeGoal()
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.backend)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = [makeQuestion(goal: goal, index: 99, status: .retired)]
        store.questionRefreshesUsed = 2

        let preparedSession = await store.prepareManualCheckpointSession()
        let session = try XCTUnwrap(preparedSession)

        let request = try XCTUnwrap(localEngine.receivedRequest)
        XCTAssertEqual(request.targetCount, ProductLimits.memberQuestionBankTargetCount)
        XCTAssertEqual(session.questions.count, 1)
        XCTAssertEqual(store.questionRefreshesUsed, 2 + 1)
        XCTAssertNil(store.checkpointNotice)
    }

    @MainActor
    func testStudyAssistAutoRefreshesLowBankAndRespectsCooldown() async throws {
        let goal = makeGoal()
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = [makeQuestion(goal: goal, index: 99)]

        let didRefresh = await store.refreshQuestionBatchIfNeeded()

        let request = try XCTUnwrap(localEngine.receivedRequest)
        XCTAssertTrue(didRefresh)
        XCTAssertEqual(request.targetCount, ProductLimits.memberQuestionBankTargetCount)
        XCTAssertEqual(store.questions.count, 2)
        XCTAssertEqual(store.questionRefreshesUsed, 1)
        XCTAssertNotNil(store.lastAutomaticQuestionRefreshAt)

        let didRefreshAgain = await store.refreshQuestionBatchIfNeeded()

        XCTAssertFalse(didRefreshAgain)
        XCTAssertEqual(store.questions.count, 2)
        XCTAssertEqual(store.questionRefreshesUsed, 1)
    }

    @MainActor
    func testStudyAssistRecommendationUsesWeakestTopic() {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.updateMembershipTier(.member)
        store.goal = goal
        var arrays = TopicCompetency.initial(topic: "arrays", estimatedLevel: 1.4)
        arrays.attempts = 4
        arrays.correct = 1
        arrays.incorrect = 3
        var recursion = TopicCompetency.initial(topic: "recursion", estimatedLevel: 2.8)
        recursion.attempts = 4
        recursion.correct = 4
        store.competencies = [recursion, arrays]

        XCTAssertTrue(store.studyAssistSummary.contains("arrays"))
        XCTAssertTrue(store.studyAssistSummary.contains("\(arrays.masteryPercent)%"))
    }

    @MainActor
    func testQuestionLevelRecommendationAppearsAfterStrongRecentAccuracy() throws {
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 2
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0, difficulty: 2) }

        for question in store.questions {
            store.submitAnswer(
                question: question,
                answer: question.expectedAnswer,
                result: .correct,
                grantsUnlock: false
            )
        }

        let recommendation = try XCTUnwrap(store.questionLevelRecommendation)
        XCTAssertEqual(recommendation.currentQuestionLevel, 2)
        XCTAssertEqual(recommendation.nextLevel, 3)
        XCTAssertEqual(recommendation.accuracyPercent, 100)
        XCTAssertEqual(recommendation.answeredCount, 5)
    }

    @MainActor
    func testAcceptingQuestionLevelRecommendationRegeneratesHarderQuestions() async throws {
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 2
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questionRefreshesUsed = 2
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0, difficulty: 2) }
        let originalQuestionIDs = Set(store.questions.map(\.id))

        for question in store.questions {
            store.submitAnswer(
                question: question,
                answer: question.expectedAnswer,
                result: .correct,
                grantsUnlock: false
            )
        }

        await store.acceptQuestionLevelRecommendation()

        let request = try XCTUnwrap(localEngine.receivedRequest)
        XCTAssertEqual(store.goal?.minimumQuestionDifficulty, 3)
        XCTAssertEqual(request.minimumDifficulty, 3)
        XCTAssertTrue(store.questions.filter { originalQuestionIDs.contains($0.id) }.allSatisfy { $0.status == .retired })
        XCTAssertTrue(store.activeQuestions.contains { $0.difficulty >= 3 && !originalQuestionIDs.contains($0.id) })
        XCTAssertEqual(store.questionRefreshesUsed, 2)
    }

    @MainActor
    func testManualQuestionDifficultyIncreaseRegeneratesHarderQuestions() async throws {
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 2
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questionRefreshesUsed = 1
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0, difficulty: 2) }
        let originalQuestionIDs = Set(store.questions.map(\.id))

        await store.updateMinimumQuestionDifficultyAndRegenerate(4)

        let request = try XCTUnwrap(localEngine.receivedRequest)
        XCTAssertEqual(store.goal?.minimumQuestionDifficulty, 4)
        XCTAssertEqual(request.minimumDifficulty, 4)
        XCTAssertTrue(request.sourcePrompt(provider: .localTemplates).contains("Hard reasoning"))
        XCTAssertTrue(store.questions.filter { originalQuestionIDs.contains($0.id) }.allSatisfy { $0.status == .retired })
        XCTAssertTrue(store.activeQuestions.contains { $0.difficulty >= 4 && !originalQuestionIDs.contains($0.id) })
        XCTAssertEqual(store.questionRefreshesUsed, 1)
    }

    @MainActor
    func testManualQuestionDifficultyDecreaseKeepsExistingHarderQuestions() async throws {
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 4
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)
        store.goal = goal
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0, difficulty: 4) }

        await store.updateMinimumQuestionDifficultyAndRegenerate(2)

        XCTAssertNil(localEngine.receivedRequest)
        XCTAssertEqual(store.goal?.minimumQuestionDifficulty, 2)
        XCTAssertTrue(store.activeQuestions.allSatisfy { $0.status != .retired })
    }

    @MainActor
    func testStarterLevelRecommendationRequestsMembershipBeforeChangingDifficulty() async throws {
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 2
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.goal = goal
        store.questions = (1...5).map { makeQuestion(goal: goal, index: $0, difficulty: 2) }

        for question in store.questions {
            store.submitAnswer(
                question: question,
                answer: question.expectedAnswer,
                result: .correct,
                grantsUnlock: false
            )
        }

        await store.acceptQuestionLevelRecommendation()

        XCTAssertNil(localEngine.receivedRequest)
        XCTAssertEqual(store.goal?.minimumQuestionDifficulty, 2)
        XCTAssertEqual(store.pendingMembershipFeature, .freshQuestionGeneration)
        XCTAssertTrue(store.checkpointNotice?.contains("Membership") ?? false)
    }

    @MainActor
    private func makeSeededStore(questionCount: Int) -> CheckpointStore {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.questions = (1...questionCount).map { makeQuestion(goal: goal, index: $0) }
        store.competencies = [
            .initial(topic: "arrays", estimatedLevel: 1.2),
            .initial(topic: "recursion", estimatedLevel: 2.0),
            .initial(topic: "hash maps", estimatedLevel: 1.6)
        ]
        return store
    }
}

final class AIProviderPolicyTests: XCTestCase {
    func testAutomaticProviderUsesConfiguredBackendBeforeLocalFallback() async {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            localEngine: StaticQuestionEngine(
                provider: .localTemplates,
                questions: (1...5).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "local") }
            ),
            backendEngine: StaticQuestionEngine(
                provider: .backend,
                questions: (1...5).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "backend") }
            ),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .automatic
        )

        XCTAssertEqual(batch.provider, .backend)
        XCTAssertEqual(batch.questions.first?.sourcePrompt, "backend")
    }

    func testAutomaticProviderFallsBackToLocalWhenLLMsUnavailable() async {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            localEngine: StaticQuestionEngine(
                provider: .localTemplates,
                questions: [makeQuestion(goal: goal, index: 1, sourcePrompt: "local")]
            ),
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal),
            preference: .automatic
        )

        XCTAssertEqual(batch.provider, .localTemplates)
        XCTAssertEqual(batch.questions.first?.sourcePrompt, "local")
    }

    func testExplicitBackendPreferenceCanUseBackendWhenConfigured() async {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            localEngine: StaticQuestionEngine(
                provider: .localTemplates,
                questions: (1...5).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "local") }
            ),
            backendEngine: StaticQuestionEngine(
                provider: .backend,
                questions: (1...5).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "backend") }
            ),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .backend
        )

        XCTAssertEqual(batch.provider, .backend)
        XCTAssertEqual(batch.questions.first?.sourcePrompt, "backend")
    }

    func testProviderFallsBackWhenSanitizedBatchIsTooShort() async {
        let goal = makeGoal()
        let engine = HybridQuestionEngine(
            localEngine: StaticQuestionEngine(
                provider: .localTemplates,
                questions: (1...5).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "local") }
            ),
            backendEngine: StaticQuestionEngine(
                provider: .backend,
                questions: (1...3).map { makeQuestion(goal: goal, index: $0, sourcePrompt: "backend") }
            ),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )

        let batch = await engine.generateQuestionBatch(
            for: makeRequest(goal: goal, targetCount: 5, backendEndpoint: URL(string: "https://example.com/ai")),
            preference: .backend
        )

        XCTAssertEqual(batch.provider, .localTemplates)
        XCTAssertTrue(batch.usedFallback)
        XCTAssertEqual(batch.questions.count, 5)
        XCTAssertTrue(batch.questions.allSatisfy { $0.sourcePrompt == "local" })
    }

    func testBackendPreferenceWithoutEndpointFallsBackToLocalTemplates() async {
        let goal = makeGoal()
        let batch = await HybridQuestionEngine().generateQuestionBatch(
            for: makeRequest(goal: goal, targetCount: 5),
            preference: .backend
        )

        XCTAssertEqual(batch.provider, .localTemplates)
        XCTAssertTrue(batch.usedFallback)
        XCTAssertGreaterThanOrEqual(batch.questions.count, 5)
    }

    func testSanitizerRejectsDuplicateReportedAndInvalidProviderQuestions() {
        let goal = makeGoal()
        let existingQuestion = makeQuestion(goal: goal, index: 1, prompt: "Already stored prompt")
        let reportedQuestion = QuestionQualityReport(
            questionID: UUID(),
            goalID: goal.id,
            prompt: "Reported prompt",
            reason: .irrelevant,
            note: ""
        )
        let request = makeRequest(
            goal: goal,
            existingQuestions: [existingQuestion],
            reportedQuestions: [reportedQuestion],
            targetCount: 2
        )

        let duplicateExisting = makeQuestion(goal: goal, index: 2, prompt: "Already stored prompt")
        let duplicateReported = makeQuestion(goal: goal, index: 3, prompt: "Reported prompt")
        let invalidQuestion = makeQuestion(
            goal: goal,
            index: 4,
            expectedAnswer: "",
            choices: ["A", "B", "C"]
        )
        let validQuestion = makeQuestion(
            goal: goal,
            index: 5,
            prompt: "Which answer proves this provider payload is usable?",
            difficulty: 99
        )

        let sanitized = QuestionBatchSanitizer.sanitize(
            [duplicateExisting, duplicateReported, invalidQuestion, validQuestion],
            for: request
        )

        XCTAssertEqual(sanitized.map(\.prompt), [validQuestion.prompt])
        XCTAssertEqual(sanitized.first?.difficulty, 5)
        XCTAssertEqual(sanitized.first?.format, .multipleChoice)
    }

    func testSanitizerRejectsQuestionsBelowMinimumDifficulty() {
        let goal = makeGoal()
        let lowQuestion = makeQuestion(goal: goal, index: 1, difficulty: 2)
        let highQuestion = makeQuestion(goal: goal, index: 2, difficulty: 4)
        let request = makeRequest(goal: goal, minimumDifficulty: 3)

        let sanitized = QuestionBatchSanitizer.sanitize([lowQuestion, highQuestion], for: request)

        XCTAssertEqual(sanitized.map(\.id), [highQuestion.id])
    }

    func testSanitizerResolvesExpectedAnswerLabelToVisibleChoice() throws {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which labeled answer should be treated as correct?",
            expectedAnswer: "B",
            choices: [
                "A. The incorrect distractor",
                "B. The correct labeled answer",
                "C. Another distractor",
                "D. Final distractor"
            ],
            difficulty: 2
        )

        let sanitizedQuestion = try XCTUnwrap(QuestionBatchSanitizer.sanitize([question], for: request).first)

        XCTAssertEqual(sanitizedQuestion.expectedAnswer, "B. The correct labeled answer")
        XCTAssertEqual(sanitizedQuestion.choices.count, 4)
        XCTAssertTrue(hasUniqueTestChoices(sanitizedQuestion.choices))
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "B. The correct labeled answer", question: sanitizedQuestion).result,
            .correct
        )
    }

    func testSanitizerRejectsDuplicateMultipleChoiceAnswers() {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which answer choice should be rejected for duplicate options?",
            expectedAnswer: "A. The same answer",
            choices: [
                "A. The same answer",
                "The same answer",
                "B. A different answer",
                "C. Another different answer"
            ],
            difficulty: 2
        )

        let sanitized = QuestionBatchSanitizer.sanitize([question], for: request)

        XCTAssertTrue(sanitized.isEmpty)
    }

    func testSanitizerRejectsQuestionsWithFewerThanFourUniqueAnswers() {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which answer choice should be rejected for too few unique options?",
            expectedAnswer: "The only supported answer",
            choices: [
                "The only supported answer",
                "A plausible distractor",
                "A plausible distractor",
                "A second distractor"
            ],
            difficulty: 2
        )

        let sanitized = QuestionBatchSanitizer.sanitize([question], for: request)

        XCTAssertTrue(sanitized.isEmpty)
    }

    func testSanitizerUsesExplanationWhenItContradictsExpectedAnswer() throws {
        let goal = makeGoal()
        let request = makeRequest(goal: goal)
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which answer matches the explanation?",
            expectedAnswer: "The tempting but wrong answer",
            choices: [
                "The tempting but wrong answer",
                "The answer supported by the argument",
                "An unrelated answer",
                "A too-broad answer"
            ],
            explanation: "The answer supported by the argument is correct because it follows from the stated evidence.",
            difficulty: 2
        )

        let sanitizedQuestion = try XCTUnwrap(QuestionBatchSanitizer.sanitize([question], for: request).first)

        XCTAssertEqual(sanitizedQuestion.expectedAnswer, "The answer supported by the argument")
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "The answer supported by the argument", question: sanitizedQuestion).result,
            .correct
        )
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "The tempting but wrong answer", question: sanitizedQuestion).result,
            .incorrect
        )
    }

    func testMultipleChoiceGraderUsesExplanationForPersistedAnswerMismatch() {
        let goal = makeGoal()
        let question = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which persisted answer should the grader trust?",
            expectedAnswer: "The tempting but wrong answer",
            choices: [
                "The tempting but wrong answer",
                "The answer supported by the argument",
                "An unrelated answer",
                "A too-broad answer"
            ],
            explanation: "The answer supported by the argument is correct because it follows from the stated evidence.",
            difficulty: 2
        )

        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "The answer supported by the argument", question: question).result,
            .correct
        )
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "The tempting but wrong answer", question: question).result,
            .incorrect
        )
    }

    func testMultipleChoiceGraderDoesNotTreatLeadingArticleAsChoiceLabel() {
        let goal = makeGoal()
        let question = makeQuestion(
            goal: goal,
            index: 1,
            expectedAnswer: "A legal rule should be flexible in unusual cases",
            choices: [
                "An unrelated answer",
                "A legal rule should be flexible in unusual cases",
                "A broader answer that ignores the facts",
                "A narrower answer that denies flexibility"
            ]
        )

        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "A legal rule should be flexible in unusual cases", question: question).result,
            .correct
        )
        XCTAssertEqual(
            AnswerGrader.evaluate(answer: "An unrelated answer", question: question).result,
            .incorrect
        )
    }

    func testQuestionContextExtractsLearningTargetFromNaturalLanguageGoal() {
        let goal = makeLSATGoal()
        let request = makeRequest(goal: goal)

        XCTAssertEqual(request.questionContext.learningTarget, "LSAT")
        XCTAssertEqual(request.questionContext.contentTopics, ["Logical Reasoning", "Reading Comprehension"])

        let sourcePrompt = request.sourcePrompt(provider: .backend)
        XCTAssertTrue(sourcePrompt.contains("Here is the user's goal: Study for the LSAT"))
        XCTAssertTrue(sourcePrompt.contains("The actual learning target to test is: LSAT"))
        XCTAssertTrue(sourcePrompt.contains("The user's focus topics are: Logical Reasoning, Reading Comprehension"))
        XCTAssertTrue(sourcePrompt.contains("Difficulty guidance for this batch: Foundations"))
        XCTAssertTrue(sourcePrompt.contains("Generate 5 level 1 of 5 difficulty multiple-choice questions about LSAT"))
        XCTAssertTrue(sourcePrompt.contains("Ask about LSAT itself, not study plans"))
    }

    func testQuestionContextDoesNotMatchExamAcronymsInsideLongerWords() {
        let goal = Goal(
            title: "Practice recursion",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "recursion",
            preferredQuestionStyle: .multipleChoice
        )

        XCTAssertEqual(GoalQuestionContext(goal: goal).learningTarget, "recursion")
    }

    func testSanitizerRejectsStudyStrategyQuestionsForAcademicTargets() {
        let goal = makeLSATGoal()
        let request = makeRequest(goal: goal)
        let studyStrategyQuestion = makeQuestion(
            goal: goal,
            index: 1,
            prompt: "Which 10-minute study rep would create the clearest progress on LSAT logical reasoning?",
            difficulty: 3
        )
        let contentQuestion = makeQuestion(
            goal: goal,
            index: 2,
            prompt: "LSAT Logical Reasoning: Which answer identifies the flaw in the argument?",
            difficulty: 3
        )

        let sanitized = QuestionBatchSanitizer.sanitize(
            [studyStrategyQuestion, contentQuestion],
            for: request
        )

        XCTAssertEqual(sanitized.map(\.prompt), [contentQuestion.prompt])
    }

    func testLocalLSATTemplatesAskExamStyleQuestionsInsteadOfStudyAdvice() async throws {
        let goal = makeLSATGoal()
        let request = makeRequest(goal: goal, targetCount: 8, minimumDifficulty: 2)

        let questions = try await LocalDraftQuestionEngine().generateQuestions(for: request)
        let promptText = questions.map(\.prompt).joined(separator: " ")

        XCTAssertGreaterThanOrEqual(questions.count, 6)
        XCTAssertTrue(promptText.contains("LSAT Logical Reasoning"))
        XCTAssertTrue(promptText.contains("LSAT Reading Comprehension"))
        XCTAssertFalse(promptText.localizedCaseInsensitiveContains("study rep"))
        XCTAssertFalse(promptText.localizedCaseInsensitiveContains("next step"))
    }

    func testLocalTemplatesRespectMinimumDifficulty() async throws {
        let goal = makeGoal()
        let request = makeRequest(goal: goal, minimumDifficulty: 4)

        let questions = try await LocalDraftQuestionEngine().generateQuestions(for: request)

        XCTAssertFalse(questions.isEmpty)
        XCTAssertTrue(questions.allSatisfy { $0.difficulty >= 4 })
    }

    func testLocalTemplatesVaryQuestionWordingByDifficulty() async throws {
        let goal = makeGoal()
        let basicRequest = makeRequest(goal: goal, minimumDifficulty: 1)
        let hardRequest = makeRequest(goal: goal, minimumDifficulty: 5)

        let basicQuestions = try await LocalDraftQuestionEngine().generateQuestions(for: basicRequest)
        let hardQuestions = try await LocalDraftQuestionEngine().generateQuestions(for: hardRequest)
        let basicPrompt = try XCTUnwrap(basicQuestions.first?.prompt)
        let hardPrompt = try XCTUnwrap(hardQuestions.first?.prompt)

        XCTAssertTrue(basicPrompt.contains("Level 1 foundations"))
        XCTAssertTrue(hardPrompt.contains("Level 5 expert synthesis"))
        XCTAssertNotEqual(basicPrompt, hardPrompt)
    }

    @MainActor
    func testStorePassesGoalContextAndDifficultyToQuestionEngine() async throws {
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let suiteName = "AIProviderPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMinimumQuestionDifficulty(4)

        await store.createGoal(
            title: "  Pass calculus final  ",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 14),
            category: .examPrep,
            currentLevel: "Advanced at derivatives, weak on integrals",
            focusAreas: "integrals, limits",
            preferredQuestionStyle: .multipleChoice
        )

        let request = try XCTUnwrap(localEngine.receivedRequests.first)
        XCTAssertEqual(request.goal.title, "Pass calculus final")
        XCTAssertEqual(request.goal.currentLevel, "Advanced at derivatives, weak on integrals")
        XCTAssertEqual(request.goal.focusAreas, "integrals, limits")
        XCTAssertEqual(request.minimumDifficulty, 4)
        XCTAssertEqual(request.targetCount, 5)

        let sourcePrompt = try XCTUnwrap(store.questions.first?.sourcePrompt)
        XCTAssertTrue(sourcePrompt.contains("Here is the user's goal: Pass calculus final"))
        XCTAssertTrue(sourcePrompt.contains("The actual learning target to test is: calculus final"))
        XCTAssertTrue(sourcePrompt.contains("The user's focus topics are: integrals, limits"))
        XCTAssertTrue(sourcePrompt.contains("The requested question difficulty floor is: level 4 of 5"))
        XCTAssertTrue(sourcePrompt.contains("Difficulty guidance for this batch: Hard reasoning"))
        XCTAssertTrue(sourcePrompt.contains("Generate 5 level 4 of 5 difficulty multiple-choice questions about calculus final"))
        XCTAssertFalse(sourcePrompt.contains("current level/context"))
    }

    @MainActor
    func testQuestionGenerationDiagnosticsCapturePromptAndGeneratedQuestions() async throws {
        let goal = makeGoal()
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let suiteName = "AIProviderPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)
        store.goal = goal

        await store.refreshQuestionBatch()

        let trace = try XCTUnwrap(store.questionGenerationTraces.first)
        XCTAssertEqual(trace.phase, "Manual refresh")
        XCTAssertEqual(trace.goalID, goal.id)
        XCTAssertEqual(trace.providerPreference, .localTemplates)
        XCTAssertEqual(trace.resolvedProvider, .localTemplates)
        XCTAssertEqual(trace.targetCount, ProductLimits.memberQuestionBankTargetCount)
        XCTAssertEqual(trace.generatedQuestionCount, 1)
        XCTAssertEqual(trace.addedQuestionCount, 1)
        XCTAssertTrue(trace.sourcePrompt.contains("Here is the user's goal: \(goal.title)"))
        XCTAssertEqual(trace.questions.first?.prompt, store.questions.first?.prompt)
        XCTAssertTrue(store.questionGenerationDiagnosticsExportText.contains("Source prompt:"))
    }

    @MainActor
    func testQuestionGenerationDiagnosticsPersistAndClear() async throws {
        let goal = makeGoal()
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let suiteName = "AIProviderPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)
        store.updateMembershipTier(.member)
        store.goal = goal

        await store.refreshQuestionBatch()

        let restoredStore = CheckpointStore(questionEngine: engine, defaults: defaults)
        XCTAssertEqual(restoredStore.questionGenerationTraces.count, 1)

        restoredStore.clearQuestionGenerationDiagnostics()

        let clearedStore = CheckpointStore(questionEngine: engine, defaults: defaults)
        XCTAssertTrue(clearedStore.questionGenerationTraces.isEmpty)
    }

    func testBackendRequestEncodesGoalContextCompetenciesAndDifficulty() throws {
        let goal = makeGoal()
        let existingQuestion = makeQuestion(goal: goal, index: 1, prompt: "Existing prompt")
        let report = QuestionQualityReport(
            questionID: UUID(),
            goalID: goal.id,
            prompt: "Reported prompt",
            reason: .tooEasy,
            note: "Too basic"
        )
        let request = QuestionGenerationRequest(
            goal: goal,
            existingQuestions: [existingQuestion],
            competencies: [.initial(topic: "recursion", estimatedLevel: 2.4)],
            reportedQuestions: [report],
            targetCount: 12,
            minimumDifficulty: 3,
            backendEndpoint: URL(string: "https://example.com/ai")
        )

        let data = try JSONEncoder().encode(BackendQuestionRequest(request: request))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let goalPayload = try XCTUnwrap(payload["goal"] as? [String: Any])
        let competencies = try XCTUnwrap(payload["competencies"] as? [[String: Any]])
        let existingPrompts = try XCTUnwrap(payload["existingPrompts"] as? [String])
        let reportedPrompts = try XCTUnwrap(payload["reportedPrompts"] as? [String])

        XCTAssertEqual(goalPayload["title"] as? String, goal.title)
        XCTAssertEqual(goalPayload["category"] as? String, goal.category.rawValue)
        XCTAssertEqual(goalPayload["focusAreas"] as? String, goal.focusAreas)
        XCTAssertEqual(goalPayload["learningTarget"] as? String, "technical interviews")
        XCTAssertEqual(goalPayload["contentTopics"] as? [String], ["arrays", "recursion", "hash maps"])
        XCTAssertNotNil(goalPayload["questionDirective"] as? String)
        XCTAssertEqual(goalPayload["needsSkillMap"] as? Bool, false)
        XCTAssertEqual(payload["targetCount"] as? Int, 12)
        XCTAssertEqual(payload["minimumDifficulty"] as? Int, 3)
        XCTAssertTrue((payload["difficultyGuidance"] as? String)?.contains("Medium application") ?? false)
        XCTAssertEqual(competencies.first?["topic"] as? String, "recursion")
        XCTAssertEqual(existingPrompts, ["Existing prompt"])
        XCTAssertEqual(reportedPrompts, ["Reported prompt"])

        let sourcePrompt = request.sourcePrompt(provider: .backend)
        XCTAssertTrue(sourcePrompt.contains("Here is the user's goal: \(goal.title)"))
        XCTAssertTrue(sourcePrompt.contains("The actual learning target to test is: technical interviews"))
        XCTAssertTrue(sourcePrompt.contains("The user's focus topics are: arrays, recursion, hash maps"))
        XCTAssertTrue(sourcePrompt.contains("The requested question difficulty floor is: level 3 of 5"))
        XCTAssertTrue(sourcePrompt.contains("Difficulty guidance for this batch: Medium application"))
        XCTAssertTrue(sourcePrompt.contains("Generate 12 level 3 of 5 difficulty multiple-choice questions about technical interviews"))
        XCTAssertTrue(sourcePrompt.contains("Use these competency notes to target weak areas: recursion"))
        XCTAssertTrue(sourcePrompt.contains("Avoid these existing prompts: Existing prompt"))
        XCTAssertTrue(sourcePrompt.contains("Avoid these reported prompts: Reported prompt"))
        XCTAssertFalse(sourcePrompt.contains("current level/context"))
    }

    func testBackendClientIdentityPersistsAnonymousInstallID() throws {
        let suiteName = "BackendClientIdentityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstID = BackendClientIdentity.installID(defaults: defaults)
        let secondID = BackendClientIdentity.installID(defaults: defaults)

        XCTAssertEqual(firstID, secondID)
        XCTAssertNotNil(UUID(uuidString: firstID))

        defaults.set("not-a-valid-uuid", forKey: "checkpoint.backend.install.id.v1")
        let repairedID = BackendClientIdentity.installID(defaults: defaults)
        XCTAssertNotEqual(repairedID, "not-a-valid-uuid")
        XCTAssertNotNil(UUID(uuidString: repairedID))
    }

    @MainActor
    func testStoreUsesInternalBackendEnvironmentConfiguration() async throws {
        setenv("CHECKPOINT_AI_BACKEND_ENDPOINT", "https://example.com/questions", 1)
        setenv("CHECKPOINT_AI_BACKEND_TOKEN", "dev-token", 1)
        defer {
            unsetenv("CHECKPOINT_AI_BACKEND_ENDPOINT")
            unsetenv("CHECKPOINT_AI_BACKEND_TOKEN")
        }

        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let suiteName = "AIProviderPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)

        await store.createGoal(
            title: "Study for the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 14),
            category: .examPrep,
            currentLevel: "Intermediate logical reasoning",
            focusAreas: "logical reasoning",
            preferredQuestionStyle: .multipleChoice
        )

        let request = try XCTUnwrap(localEngine.receivedRequest)
        XCTAssertEqual(request.backendEndpoint?.absoluteString, "https://example.com/questions")
        XCTAssertEqual(request.backendAuthorizationToken, "dev-token")
    }

    @MainActor
    func testInitialGoalGenerationUsesSmallerWarmStartTarget() async throws {
        let localEngine = CapturingQuestionEngine(provider: .localTemplates)
        let engine = HybridQuestionEngine(
            localEngine: localEngine,
            backendEngine: ThrowingQuestionEngine(provider: .backend),
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let suiteName = "AIProviderPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.localTemplates)

        await store.createGoal(
            title: "Pass the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 14),
            category: .examPrep,
            currentLevel: "Intermediate logical reasoning",
            focusAreas: "logical reasoning",
            preferredQuestionStyle: .multipleChoice
        )

        let request = try XCTUnwrap(localEngine.receivedRequests.first)
        XCTAssertEqual(request.targetCount, 5)
    }

    @MainActor
    func testInitialGoalGenerationTopsOffRemainingQuestionBankInBackground() async throws {
        let backendEngine = CapturingQuestionEngine(provider: .backend)
        let engine = HybridQuestionEngine(
            localEngine: GoalAwareQuestionEngine(provider: .localTemplates),
            backendEngine: backendEngine,
            appleFoundationEngine: ThrowingQuestionEngine(provider: .appleFoundation)
        )
        let suiteName = "AIProviderPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CheckpointStore(questionEngine: engine, defaults: defaults)
        store.updateAIProviderPreference(.automatic)

        await store.createGoal(
            title: "Pass the LSAT",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 14),
            category: .examPrep,
            currentLevel: "Intermediate logical reasoning",
            focusAreas: "logical reasoning",
            preferredQuestionStyle: .multipleChoice
        )

        try? await Task.sleep(nanoseconds: 150_000_000)

        let request = try XCTUnwrap(backendEngine.receivedRequests.first)
        XCTAssertEqual(request.targetCount, ProductLimits.starterQuestionBankTargetCount)
        XCTAssertEqual(request.existingQuestions.count, 5)
    }
}

final class UnlockPolicyTests: XCTestCase {
    func testCorrectAnswerUnlockOptionsUsePracticalShortBreaks() {
        XCTAssertEqual(UnlockPolicy.default.unlockMinutes, 30)
        XCTAssertEqual(UnlockPolicy.correctAnswerUnlockMinuteOptions, [5, 10, 15, 30])
        XCTAssertTrue(UnlockPolicy.correctAnswerUnlockMinuteOptions.contains(30))
    }

    func testLegacyTinyUnlockDurationsNormalizeToCurrentOptions() throws {
        let data = Data(
            """
            {
              "unlockMinutes": 3,
              "partialUnlockMinutes": 2,
              "unlockOnPartial": true,
              "questionsPerSession": 5,
              "requiredCorrectAnswers": 4
            }
            """.utf8
        )

        let policy = try JSONDecoder().decode(UnlockPolicy.self, from: data)

        XCTAssertEqual(policy.unlockMinutes, 5)
        XCTAssertEqual(policy.partialUnlockMinutes, 5)
    }

    func testLegacyTinyCheckpointCountsNormalizeToFiveQuestionBaseline() throws {
        let data = Data(
            """
            {
              "unlockMinutes": 30,
              "partialUnlockMinutes": 15,
              "unlockOnPartial": true,
              "questionsPerSession": 3,
              "requiredCorrectAnswers": 3
            }
            """.utf8
        )

        let policy = try JSONDecoder().decode(UnlockPolicy.self, from: data)

        XCTAssertEqual(policy.questionsPerSession, 5)
        XCTAssertEqual(policy.requiredCorrectAnswers, 4)
    }
}

private enum TestQuestionGenerationError: Error {
    case unavailable
}

private struct StaticQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind
    let questions: [CheckpointQuestion]

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        questions
    }
}

private struct GoalAwareQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        let resolvedTopics = request.questionContext.contentTopics

        return (1...6).map { index in
            makeQuestion(
                goal: request.goal,
                index: index,
                topic: resolvedTopics[(index - 1) % resolvedTopics.count],
                prompt: "\(request.goal.title) question \(index): Which choice best supports the active goal?",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

private final class SkillMapQuestionEngine: QuestionGenerating, @unchecked Sendable {
    let provider: AIProviderKind
    let topics: [String]
    private(set) var receivedRequests: [QuestionGenerationRequest] = []

    init(provider: AIProviderKind, topics: [String]) {
        self.provider = provider
        self.topics = topics
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        receivedRequests.append(request)

        return (1...max(request.targetCount, topics.count)).map { index in
            let topic = topics[(index - 1) % topics.count]
            return makeQuestion(
                goal: request.goal,
                index: index,
                topic: topic,
                prompt: "\(request.goal.title) \(provider.rawValue) skill-map question \(index) for \(topic)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

private struct DelayedQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind
    let delayNanoseconds: UInt64

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return (1...6).map { index in
            makeQuestion(
                goal: request.goal,
                index: index,
                topic: "logical reasoning",
                prompt: "\(request.goal.title) delayed question \(index)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        }
    }
}

private struct ThrowingQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        throw TestQuestionGenerationError.unavailable
    }
}

private final class CapturingQuestionEngine: QuestionGenerating, @unchecked Sendable {
    let provider: AIProviderKind
    private(set) var receivedRequests: [QuestionGenerationRequest] = []
    var receivedRequest: QuestionGenerationRequest? { receivedRequests.last }

    init(provider: AIProviderKind) {
        self.provider = provider
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        receivedRequests.append(request)
        return [
            makeQuestion(
                goal: request.goal,
                index: 1,
                topic: "integrals",
                prompt: "\(provider.rawValue) generated question at level \(request.minimumDifficulty)",
                difficulty: request.minimumDifficulty,
                sourcePrompt: request.sourcePrompt(provider: provider)
            )
        ]
    }
}

private func makeGoal() -> Goal {
    Goal(
        title: "Pass technical interviews",
        deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
        category: .codingInterview,
        currentLevel: "Intermediate, but shaky on recursion",
        focusAreas: "arrays, recursion, hash maps",
        preferredQuestionStyle: .multipleChoice
    )
}

private func hasUniqueTestChoices(_ choices: [String]) -> Bool {
    Set(choices.map(testChoiceKey)).count == choices.count
}

private func testChoiceKey(_ choice: String) -> String {
    var normalized = choice
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let labelCharacters = ["a", "b", "c", "d", "1", "2", "3", "4"]
    let separatorCharacters = CharacterSet(charactersIn: " \t\n.:-)")
    let characters = Array(normalized)

    if characters.count >= 2,
       labelCharacters.contains(String(characters[0])),
       String(characters[1]).rangeOfCharacter(from: separatorCharacters) != nil {
        normalized.removeFirst()
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n.:-)"))
    } else if characters.count >= 3,
              characters[0] == "(" || characters[0] == "[",
              labelCharacters.contains(String(characters[1])) {
        normalized.removeFirst(2)
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n.:-)]"))
    }

    return normalized.filter { $0.isLetter || $0.isNumber }
}

private func makeLSATGoal() -> Goal {
    Goal(
        title: "Study for the LSAT",
        deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
        category: .examPrep,
        currentLevel: "Strong on logical reasoning, weak on timed reading sections",
        focusAreas: "logical reasoning, reading comprehension",
        preferredQuestionStyle: .multipleChoice
    )
}

private func makeQuestion(
    goal: Goal,
    index: Int,
    topic: String = "arrays",
    prompt: String? = nil,
    expectedAnswer: String? = nil,
    choices: [String]? = nil,
    explanation: String? = nil,
    status: QuestionStatus = .new,
    timesCorrect: Int = 0,
    nextReviewAt: Date? = nil,
    difficulty: Int = 2,
    sourcePrompt: String = "test"
) -> CheckpointQuestion {
    let correctAnswer = expectedAnswer ?? "Correct answer \(index)"
    return CheckpointQuestion(
        goalID: goal.id,
        prompt: prompt ?? "Question \(index): Which option best supports the goal?",
        expectedAnswer: correctAnswer,
        choices: choices ?? [
            correctAnswer,
            "Distractor \(index)A",
            "Distractor \(index)B",
            "Distractor \(index)C"
        ],
        explanation: explanation ?? "Explanation \(index)",
        topic: topic,
        difficulty: difficulty,
        format: .multipleChoice,
        status: status,
        timesCorrect: timesCorrect,
        nextReviewAt: nextReviewAt,
        sourcePrompt: sourcePrompt
    )
}

private func makeAttempt(
    goal: Goal,
    result: AnswerResult,
    createdAt: Date
) -> CheckpointAttempt {
    var attempt = CheckpointAttempt(
        questionID: UUID(),
        goalID: goal.id,
        prompt: "Metric question",
        answer: "Metric answer",
        result: result,
        unlockMinutes: 0
    )
    attempt.createdAt = createdAt
    return attempt
}

private func makeRequest(
    goal: Goal,
    existingQuestions: [CheckpointQuestion] = [],
    reportedQuestions: [QuestionQualityReport] = [],
    targetCount: Int = 5,
    minimumDifficulty: Int = 1,
    backendEndpoint: URL? = nil
) -> QuestionGenerationRequest {
    QuestionGenerationRequest(
        goal: goal,
        existingQuestions: existingQuestions,
        competencies: [],
        reportedQuestions: reportedQuestions,
        targetCount: targetCount,
        minimumDifficulty: minimumDifficulty,
        backendEndpoint: backendEndpoint
    )
}

private func resetSharedAppGroupState() {
    let defaults = SharedAppGroup.defaults
    [
        SharedAppGroup.pendingShieldAttemptDateKey,
        SharedAppGroup.shieldGoalTitleKey,
        SharedAppGroup.shieldPromptPreviewKey,
        SharedAppGroup.shieldAttemptCountKey,
        SharedAppGroup.shieldConfigurationRenderDateKey,
        SharedAppGroup.shieldConfigurationRenderCountKey,
        SharedAppGroup.lastUnlockExpirationKey,
        SharedAppGroup.desiredShieldActiveKey,
        SharedAppGroup.screenTimeSelectionKey
    ].forEach { defaults.removeObject(forKey: $0) }
}
