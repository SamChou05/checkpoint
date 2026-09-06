import XCTest
@testable import Checkpoint

final class AdaptiveSchedulingTests: CheckpointWorkflowTestCase {
    @MainActor
    func testSkillFirstSchedulerStartsWithLeastAttemptedDistinctSkills() throws {
        let skills = ["arrays", "recursion", "graphs", "hash maps"].map {
            SkillMapTopic(name: $0, objectives: [SkillMapObjective(name: $0)])
        }
        let skillMap = GoalSkillMap(
            topics: skills,
            status: .reviewed,
            provenance: .userEdited
        )
        let goal = Goal(
            title: "Prepare for coding interviews",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: skills.map(\.name).joined(separator: ", "),
            derivedSkillMap: skillMap,
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.updateQuestionsPerSession(5)
        var practiced = TopicCompetency.initial(
            topic: skills[0].name,
            goalID: goal.id,
            skillID: skills[0].id
        )
        practiced.attempts = 6
        practiced.correct = 3
        store.competencies = [practiced] + skills.dropFirst().map {
            .initial(topic: $0.name, goalID: goal.id, skillID: $0.id)
        }
        store.questions = skills.enumerated().flatMap { skillIndex, skill in
            (0..<2).map { questionIndex in
                makeQuestion(
                    goal: goal,
                    index: (skillIndex * 10) + questionIndex,
                    topic: skill.name,
                    skillID: skill.id
                )
            }
        }

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertNotEqual(session.questions.first?.skillID, practiced.skillID)
        XCTAssertEqual(Set(session.questions.prefix(2).compactMap(\.skillID)).count, 2)
        XCTAssertEqual(Set(session.questions.prefix(3).compactMap(\.skillID)).count, 2)
        XCTAssertEqual(Set(session.questions.compactMap(\.skillID)).count, 3)
    }

    @MainActor
    func testSkillFirstSchedulerRepeatsDueWeakSkillWithinBreadthFloor() throws {
        let skills = ["algebra", "geometry", "statistics"].map {
            SkillMapTopic(name: $0, objectives: [SkillMapObjective(name: $0)])
        }
        let skillMap = GoalSkillMap(
            topics: skills,
            status: .reviewed,
            provenance: .userEdited
        )
        let goal = Goal(
            title: "Prepare for math final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "",
            derivedSkillMap: skillMap,
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.updateQuestionsPerSession(5)
        var weak = TopicCompetency.initial(
            topic: skills[0].name,
            goalID: goal.id,
            skillID: skills[0].id
        )
        weak.attempts = 8
        weak.incorrect = 8
        store.competencies = [weak] + skills.dropFirst().map {
            .initial(topic: $0.name, goalID: goal.id, skillID: $0.id)
        }
        let dueWeakQuestions = (0..<3).map { index in
            makeQuestion(
                goal: goal,
                index: index,
                topic: skills[0].name,
                skillID: skills[0].id,
                status: .incorrect,
                nextReviewAt: Date().addingTimeInterval(-60)
            )
        }
        let breadthQuestions = skills.dropFirst().enumerated().map { index, skill in
            makeQuestion(
                goal: goal,
                index: 10 + index,
                topic: skill.name,
                skillID: skill.id
            )
        }
        store.questions = dueWeakQuestions + breadthQuestions

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(session.questions.filter { $0.skillID == skills[0].id }.count, 3)
        XCTAssertEqual(Set(session.questions.compactMap(\.skillID)).count, 3)
    }

    @MainActor
    func testSkillFirstSchedulerUsesOneDueMasteredMaintenanceQuestion() throws {
        let skills = ["algebra", "geometry", "statistics"].map {
            SkillMapTopic(name: $0, objectives: [SkillMapObjective(name: $0)])
        }
        let skillMap = GoalSkillMap(
            topics: skills,
            status: .reviewed,
            provenance: .userEdited
        )
        let goal = Goal(
            title: "Prepare for math final",
            deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: skills.map(\.name).joined(separator: ", "),
            derivedSkillMap: skillMap,
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.updateQuestionsPerSession(5)
        var mastered = TopicCompetency.initial(
            topic: skills[0].name,
            estimatedLevel: 5,
            goalID: goal.id,
            skillID: skills[0].id
        )
        mastered.attempts = 10
        mastered.correct = 10
        store.competencies = [mastered] + skills.dropFirst().map {
            .initial(topic: $0.name, goalID: goal.id, skillID: $0.id)
        }
        let maintenanceQuestion = makeQuestion(
            goal: goal,
            index: 1,
            topic: skills[0].name,
            skillID: skills[0].id,
            status: .correct,
            timesAsked: 1,
            timesCorrect: 1,
            lastAskedAt: Date().addingTimeInterval(-60 * 60 * 24 * 7),
            nextReviewAt: Date().addingTimeInterval(-60)
        )
        let freshQuestions = (2...7).map { index in
            let skill = skills[1 + (index % 2)]
            return makeQuestion(
                goal: goal,
                index: index,
                topic: skill.name,
                skillID: skill.id
            )
        }
        store.questions = freshQuestions + [maintenanceQuestion]

        let session = try XCTUnwrap(store.nextCheckpointSession())

        XCTAssertEqual(session.questions.count, 5)
        XCTAssertEqual(session.questions.last?.id, maintenanceQuestion.id)
        XCTAssertEqual(session.questions.filter { $0.id == maintenanceQuestion.id }.count, 1)
    }

    @MainActor
    func testSchedulerPrefersUnattemptedObjectivesWithinSelectedSkill() throws {
        let broadSkill = SkillMapTopic(
            name: "systems design",
            objectives: (0..<5).map { SkillMapObjective(name: "objective \($0)") }
        )
        let skills = [
            broadSkill,
            SkillMapTopic(
                name: "communication",
                objectives: [SkillMapObjective(name: "explain tradeoffs")]
            ),
            SkillMapTopic(
                name: "prioritization",
                objectives: [SkillMapObjective(name: "rank constraints")]
            )
        ]
        let goal = Goal(
            title: "Practice product architecture",
            deadline: Date().addingTimeInterval(30 * 24 * 60 * 60),
            category: .custom,
            currentLevel: "Beginner",
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
        store.competencies = skills.map {
            .initial(topic: $0.name, goalID: goal.id, skillID: $0.id)
        }
        store.questions = broadSkill.objectives.enumerated().map { index, objective in
            makeQuestion(
                goal: goal,
                index: 7_000 + index,
                topic: broadSkill.name,
                skillID: broadSkill.id,
                objectiveID: objective.id,
                objective: objective.name,
                status: .new,
                timesAsked: index == 0 ? 1 : 0,
                difficulty: index == 0 ? 1 : 5
            )
        }

        let selected = store.nextQuestions(limit: 4)

        XCTAssertEqual(selected.count, 4)
        XCTAssertEqual(
            Set(selected.compactMap(\.objectiveID)),
            Set(broadSkill.objectives.dropFirst().map(\.id))
        )
    }

}

extension AdaptiveSchedulingTests {
    @MainActor
    func testAutomaticSkillDifficultyProgressesIndependentlyThroughFourStages() throws {
        let skills = ["arrays", "graphs", "recursion"].map {
            SkillMapTopic(name: $0, objectives: [SkillMapObjective(name: "Apply \($0)"), SkillMapObjective(name: "Explain \($0)")])
        }
        var goal = makeGoal()
        goal.derivedSkillMap = GoalSkillMap(topics: skills)
        var attempts: [CheckpointAttempt] = []
        let start = Date().addingTimeInterval(-3600)
        for level in 1...4 {
            for index in 0..<5 {
                attempts.append(adaptiveAttempt(goal: goal, skill: skills[0], index: attempts.count, difficulty: level, correct: true, at: start.addingTimeInterval(Double(attempts.count))))
                if index < 4 {
                    XCTAssertEqual(AdaptiveLearningPolicy.plans(for: goal, attempts: attempts)[0].targetDifficulty, level)
                }
            }
            let plans = AdaptiveLearningPolicy.plans(for: goal, attempts: attempts)
            XCTAssertEqual(plans[0].targetDifficulty, level + 1)
            XCTAssertEqual(plans[1].targetDifficulty, 1)
            XCTAssertEqual(plans[2].targetDifficulty, 1)
        }
        let request = QuestionGenerationRequest(goal: goal, existingQuestions: [], competencies: [], reportedQuestions: [], targetCount: 5, minimumDifficulty: 1, adaptiveSkillPlans: AdaptiveLearningPolicy.plans(for: goal, attempts: attempts), backendEndpoint: nil)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(BackendQuestionRequest(request: request))) as? [String: Any])
        let wirePlans = try XCTUnwrap(payload["adaptiveSkillPlans"] as? [[String: Any]])
        XCTAssertEqual(wirePlans.first?["targetDifficulty"] as? Int, 5)
    }

    @MainActor
    func testRepeatedAnswersAndForeignOrOldEvidenceCannotAdvanceASkill() {
        let skill = SkillMapTopic(name: "Logic", objectives: [SkillMapObjective(name: "Apply logic")])
        var goal = makeGoal()
        goal.derivedSkillMap = GoalSkillMap(topics: [skill])
        let now = Date()
        let first = adaptiveAttempt(goal: goal, skill: skill, index: 0, difficulty: 1, correct: false, at: now.addingTimeInterval(-60))
        var attempts = (0..<20).map { index -> CheckpointAttempt in
            var attempt = first
            attempt.id = UUID()
            attempt.createdAt = now.addingTimeInterval(-Double(20 - index))
            attempt.result = .correct
            return attempt
        }
        attempts.append(first)
        var foreign = adaptiveAttempt(goal: goal, skill: skill, index: 1, difficulty: 5, correct: true, at: now)
        foreign.goalID = UUID()
        attempts.append(foreign)
        attempts.append(adaptiveAttempt(goal: goal, skill: skill, index: 2, difficulty: 5, correct: true, at: now.addingTimeInterval(-31 * 86400)))
        let plan = AdaptiveLearningPolicy.plans(for: goal, attempts: attempts, now: now)[0]
        XCTAssertEqual(plan.targetDifficulty, 1)
        XCTAssertEqual(plan.evidenceCount, 1)
        XCTAssertEqual(plan.recentAccuracyPercent, 0)
        XCTAssertEqual(plan.recentMistakes.first?.selectedAnswer, "Tempting wrong answer")
    }

    @MainActor
    func testRecentRecoveryOverridesEarlierMistakesAndStruggleStepsBack() {
        let skill = SkillMapTopic(name: "Logic", objectives: [SkillMapObjective(name: "Apply logic"), SkillMapObjective(name: "Find assumption")])
        var goal = makeGoal()
        goal.minimumQuestionDifficulty = 2
        goal.derivedSkillMap = GoalSkillMap(topics: [skill])
        let start = Date().addingTimeInterval(-3600)
        var attempts = (0..<20).map { adaptiveAttempt(goal: goal, skill: skill, index: $0, difficulty: 2, correct: false, at: start.addingTimeInterval(Double($0))) }
        for index in 20..<25 {
            attempts.append(adaptiveAttempt(goal: goal, skill: skill, index: index, difficulty: 2, correct: true, at: start.addingTimeInterval(Double(index))))
        }
        XCTAssertEqual(AdaptiveLearningPolicy.plans(for: goal, attempts: attempts)[0].targetDifficulty, 3)
        for index in 25..<29 {
            attempts.append(adaptiveAttempt(goal: goal, skill: skill, index: index, difficulty: 3, correct: false, at: start.addingTimeInterval(Double(index))))
        }
        let plan = AdaptiveLearningPolicy.plans(for: goal, attempts: attempts)[0]
        XCTAssertEqual(plan.targetDifficulty, 2)
        XCTAssertEqual(Set(plan.focusObjectiveIDs), Set(skill.objectives.map(\.id)))
    }

    @MainActor
    func testAdaptiveSelectionDoesNotLetOldEasyInventoryHideReadyChallenge() throws {
        let skill = SkillMapTopic(name: "arrays", objectives: [SkillMapObjective(name: "Find pairs"), SkillMapObjective(name: "Analyze bounds")])
        var goal = makeGoal()
        goal.derivedSkillMap = GoalSkillMap(topics: [skill])
        let easy = makeQuestion(goal: goal, index: 1, topic: skill.name, skillID: skill.id, objectiveID: skill.objectives[0].id, difficulty: 1)
        let challenge = makeQuestion(goal: goal, index: 2, topic: skill.name, skillID: skill.id, objectiveID: skill.objectives[1].id, difficulty: 4)
        let selector = CheckpointQuestionSelector(questions: [easy, challenge], goalProfiles: [goal], currentGoal: goal, competencies: [.initial(topic: skill.name, goalID: goal.id, skillID: skill.id)], activeQuestionDifficulty: 1, maximumExactQuestionAskCount: 2, adaptiveDifficultyBySkillID: [skill.id: 4])
        XCTAssertEqual(selector.nextQuestion()?.id, challenge.id)
    }

    private func adaptiveAttempt(goal: Goal, skill: SkillMapTopic, index: Int, difficulty: Int, correct: Bool, at date: Date) -> CheckpointAttempt {
        CheckpointAttempt(questionID: UUID(), goalID: goal.id, skillID: skill.id, objectiveID: skill.objectives[index % skill.objectives.count].id, questionDifficulty: difficulty, questionVerificationVersion: 1, prompt: "Apply this concept to scenario \(index)", answer: correct ? "Supported answer" : "Tempting wrong answer", result: correct ? .correct : .incorrect, unlockMinutes: 0, reviewSnapshot: CheckpointAttemptReviewSnapshot(topic: skill.name, format: .multipleChoice, referenceAnswer: "Supported answer", explanation: "Reasoning"), createdAt: date)
    }

    @MainActor
    func testUnverifiedCacheAndLegacyAnswersCannotDriveProPracticeOrAdvancement() {
        let skill = SkillMapTopic(name: "Logic", objectives: [SkillMapObjective(name: "Apply logic")])
        var goal = makeGoal()
        goal.derivedSkillMap = GoalSkillMap(topics: [skill])
        let attempts = (0..<10).map { index -> CheckpointAttempt in
            var attempt = adaptiveAttempt(goal: goal, skill: skill, index: index, difficulty: 5, correct: true, at: Date().addingTimeInterval(-60))
            attempt.questionVerificationVersion = index.isMultiple(of: 2) ? nil : 0
            return attempt
        }
        XCTAssertEqual(AdaptiveLearningPolicy.plans(for: goal, attempts: attempts)[0].evidenceCount, 0)
        XCTAssertEqual(AdaptiveLearningPolicy.plans(for: goal, attempts: attempts)[0].targetDifficulty, 1)
        let legacy = makeQuestion(goal: goal, index: 1, verificationVersion: 0, skillID: skill.id)
        let checked = makeQuestion(goal: goal, index: 2, skillID: skill.id)
        let selector = CheckpointQuestionSelector(questions: [legacy, checked], goalProfiles: [goal], currentGoal: goal, competencies: [], activeQuestionDifficulty: 1, maximumExactQuestionAskCount: 2, requiresVerifiedQuestions: true)
        XCTAssertFalse(selector.isSelectableQuestion(legacy))
        XCTAssertEqual(selector.nextQuestion()?.id, checked.id)
    }

    @MainActor
    func testProRolloutKeepsLegacyServiceUsableUntilReviewedInventoryArrives() throws {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = .member
        store.goal = goal
        store.goalProfiles = [goal]
        let legacy = makeQuestion(goal: goal, index: 1, verificationVersion: 0)
        store.questions = [legacy]
        XCTAssertEqual(store.nextQuestion()?.id, legacy.id)
        let reviewed = makeQuestion(goal: goal, index: 2)
        store.questions.append(reviewed)
        XCTAssertEqual(store.nextQuestion()?.id, reviewed.id)
        _ = store.submitAnswer(question: reviewed, answer: reviewed.expectedAnswer, result: .correct, grantsUnlock: false)
        store.questions = [legacy]
        XCTAssertNil(store.nextQuestion(), "Retained reviewed evidence must prevent reverting to unverified practice.")
    }
}
