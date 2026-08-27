import Foundation
@testable import Checkpoint

// MARK: - Fixtures

func makeGoal() -> Goal {
    Goal(
        title: "Pass technical interviews",
        deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
        category: .codingInterview,
        currentLevel: "Intermediate, but shaky on recursion",
        focusAreas: "arrays, recursion, hash maps",
        preferredQuestionStyle: .multipleChoice
    )
}

func makeInterviewGoal(title: String) -> Goal {
    Goal(
        title: title,
        deadline: Date().addingTimeInterval(60 * 60 * 24 * 30),
        category: .codingInterview,
        currentLevel: "",
        focusAreas: "",
        preferredQuestionStyle: .multipleChoice
    )
}

func hasUniqueTestChoices(_ choices: [String]) -> Bool {
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

func makeLSATGoal() -> Goal {
    Goal(
        title: "Study for the LSAT",
        deadline: Date().addingTimeInterval(60 * 60 * 24 * 45),
        category: .examPrep,
        currentLevel: "Strong on logical reasoning, weak on timed reading sections",
        focusAreas: "logical reasoning, reading comprehension",
        preferredQuestionStyle: .multipleChoice
    )
}

func makeQuestion(
    goal: Goal,
    index: Int,
    topic: String = "arrays",
    prompt: String? = nil,
    expectedAnswer: String? = nil,
    choices: [String]? = nil,
    explanation: String? = nil,
    skillID: SkillMapTopic.ID? = nil,
    objectiveID: SkillMapObjective.ID? = nil,
    objective: String? = nil,
    status: QuestionStatus = .new,
    timesAsked: Int = 0,
    timesCorrect: Int = 0,
    lastAskedAt: Date? = nil,
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
        skillID: skillID,
        objectiveID: objectiveID,
        objective: objective,
        difficulty: difficulty,
        format: .multipleChoice,
        status: status,
        timesAsked: timesAsked,
        timesCorrect: timesCorrect,
        lastAskedAt: lastAskedAt,
        nextReviewAt: nextReviewAt,
        sourcePrompt: sourcePrompt
    )
}

func makeQuestionReport(
    for question: CheckpointQuestion,
    note: String
) -> QuestionQualityReport {
    QuestionQualityReport(
        questionID: question.id,
        goalID: question.goalID,
        prompt: question.prompt,
        reason: .confusing,
        note: note
    )
}

func makeAttempt(
    goal: Goal,
    questionID: CheckpointQuestion.ID = UUID(),
    result: AnswerResult,
    createdAt: Date
) -> CheckpointAttempt {
    var attempt = CheckpointAttempt(
        questionID: questionID,
        goalID: goal.id,
        prompt: "Metric question",
        answer: "Metric answer",
        result: result,
        unlockMinutes: 0
    )
    attempt.createdAt = createdAt
    return attempt
}

func makeRequest(
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

func resetSharedAppGroupState() {
    let defaults = SharedAppGroup.defaults
    SharedAppGroup.removeAllPendingShieldAttempts()
    [
        SharedAppGroup.pendingShieldAttemptDateKey,
        SharedAppGroup.pendingShieldAttemptProtectionRevisionKey,
        SharedAppGroup.pendingShieldAttemptDataKey,
        SharedAppGroup.pendingShieldAttemptCurrentIDKey,
        SharedAppGroup.shieldGoalTitleKey,
        SharedAppGroup.shieldPromptPreviewKey,
        SharedAppGroup.shieldAttemptCountKey,
        SharedAppGroup.shieldConfigurationRenderDateKey,
        SharedAppGroup.shieldConfigurationRenderCountKey,
        SharedAppGroup.lastUnlockExpirationKey,
        SharedAppGroup.desiredShieldActiveKey,
        SharedAppGroup.checkpointReadyKey,
        SharedAppGroup.screenTimeSelectionKey,
        SharedAppGroup.screenTimeSelectionSemanticsVersionKey,
        SharedAppGroup.protectionConfigurationRevisionKey,
        SharedAppGroup.protectionRevisionKey,
        SharedAppGroup.protectionUpdatedAtKey,
        SharedAppGroup.unlockRelockMonitorScheduledAtKey,
        SharedAppGroup.unlockRelockMonitorIntervalStartKey,
        SharedAppGroup.unlockRelockMonitorExpectedEndKey,
        SharedAppGroup.unlockRelockExtensionIntervalStartCountKey,
        SharedAppGroup.unlockRelockExtensionIntervalEndCountKey,
        SharedAppGroup.unlockRelockExtensionLastEventDateKey,
        SharedAppGroup.unlockRelockExtensionLastResultKey
    ].forEach { defaults.removeObject(forKey: $0) }
    defaults.synchronize()
    SharedAppGroup.removeShieldContextFile()
    SharedAppGroup.removeScreenTimeSelectionFile()
    SharedAppGroup.removeProtectionSnapshotFile()
}
