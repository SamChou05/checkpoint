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

}
