import Foundation

enum QuestionGenerationError: LocalizedError {
    case providerUnavailable
    case backendNotConfigured
    case badResponse
    case noQuestionsGenerated

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "The selected AI provider is unavailable on this device."
        case .backendNotConfigured:
            return "No backend endpoint is configured."
        case .badResponse:
            return "The question provider returned an invalid response."
        case .noQuestionsGenerated:
            return "No questions were generated."
        }
    }
}

struct QuestionGenerationRequest {
    var goal: Goal
    var existingQuestions: [CheckpointQuestion]
    var competencies: [TopicCompetency]
    var reportedQuestions: [QuestionQualityReport]
    var targetCount: Int
    var backendEndpoint: URL?
}

struct QuestionBatch {
    var questions: [CheckpointQuestion]
    var provider: AIProviderKind
    var usedFallback: Bool
}

protocol QuestionGenerating {
    var provider: AIProviderKind { get }
    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion]
}

struct HybridQuestionEngine {
    private let localEngine = LocalDraftQuestionEngine()
    private let backendEngine = BackendQuestionEngine()
    private let appleFoundationEngine = AppleFoundationQuestionEngine()

    func generateQuestionBatch(
        for request: QuestionGenerationRequest,
        preference: AIProviderKind
    ) async -> QuestionBatch {
        let providers = providerOrder(for: preference)
        var firstError: Error?

        for provider in providers {
            do {
                let questions = try await provider.generateQuestions(for: request)
                let sanitizedQuestions = QuestionBatchSanitizer.sanitize(questions, for: request)

                if !sanitizedQuestions.isEmpty {
                    return QuestionBatch(
                        questions: sanitizedQuestions,
                        provider: provider.provider,
                        usedFallback: provider.provider != preference && preference != .automatic
                    )
                }

                firstError = firstError ?? QuestionGenerationError.noQuestionsGenerated
            } catch {
                firstError = firstError ?? error
            }
        }

        let localQuestions = (try? await localEngine.generateQuestions(for: request)) ?? []
        let fallbackQuestions = QuestionBatchSanitizer.sanitize(localQuestions, for: request)

        return QuestionBatch(
            questions: fallbackQuestions,
            provider: .localTemplates,
            usedFallback: firstError != nil
        )
    }

    private func providerOrder(for preference: AIProviderKind) -> [any QuestionGenerating] {
        switch preference {
        case .automatic:
            return [appleFoundationEngine, backendEngine, localEngine]
        case .appleFoundation:
            return [appleFoundationEngine, localEngine]
        case .backend:
            return [backendEngine, localEngine]
        case .localTemplates:
            return [localEngine]
        }
    }
}

enum QuestionBatchSanitizer {
    static func sanitize(_ questions: [CheckpointQuestion], for request: QuestionGenerationRequest) -> [CheckpointQuestion] {
        let existingPrompts = Set(request.existingQuestions.map { canonicalPrompt($0.prompt) })
        let reportedPrompts = Set(request.reportedQuestions.map { canonicalPrompt($0.prompt) })
        var seenPrompts = existingPrompts.union(reportedPrompts)
        var sanitizedQuestions: [CheckpointQuestion] = []

        for question in questions {
            var sanitizedQuestion = question
            sanitizedQuestion.prompt = clipped(question.prompt.trimmingCharacters(in: .whitespacesAndNewlines), maxLength: 360)
            sanitizedQuestion.expectedAnswer = clipped(question.expectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines), maxLength: 280)
            sanitizedQuestion.choices = sanitizedChoices(question.choices, expectedAnswer: sanitizedQuestion.expectedAnswer)
            sanitizedQuestion.explanation = clipped(question.explanation.trimmingCharacters(in: .whitespacesAndNewlines), maxLength: 420)
            sanitizedQuestion.topic = clipped(collapsedWhitespace(question.topic), maxLength: 48)
            sanitizedQuestion.difficulty = min(5, max(1, question.difficulty))
            sanitizedQuestion.format = .multipleChoice
            sanitizedQuestion.status = .new
            sanitizedQuestion.timesAsked = 0
            sanitizedQuestion.timesCorrect = 0
            sanitizedQuestion.lastAskedAt = nil
            sanitizedQuestion.nextReviewAt = nil

            let promptKey = canonicalPrompt(sanitizedQuestion.prompt)

            guard isUsable(sanitizedQuestion), !seenPrompts.contains(promptKey) else {
                continue
            }

            seenPrompts.insert(promptKey)
            sanitizedQuestions.append(sanitizedQuestion)

            if sanitizedQuestions.count >= request.targetCount {
                break
            }
        }

        return sanitizedQuestions
    }

    private static func isUsable(_ question: CheckpointQuestion) -> Bool {
        question.prompt.count >= 12
            && !question.expectedAnswer.isEmpty
            && question.format == .multipleChoice
            && question.choices.count >= 2
            && question.choices.contains(where: { canonicalPrompt($0) == canonicalPrompt(question.expectedAnswer) })
            && !question.explanation.isEmpty
            && !question.topic.isEmpty
    }

    private static func sanitizedChoices(_ choices: [String], expectedAnswer: String) -> [String] {
        let clippedChoices = choices
            .map { clipped(collapsedWhitespace($0), maxLength: 140) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        var uniqueChoices: [String] = []

        for choice in clippedChoices {
            let key = canonicalPrompt(choice)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            uniqueChoices.append(choice)
        }

        let expectedKey = canonicalPrompt(expectedAnswer)
        let expectedChoice = uniqueChoices.first { canonicalPrompt($0) == expectedKey } ?? expectedAnswer
        let distractors = uniqueChoices.filter { canonicalPrompt($0) != expectedKey }
        let finalChoices = [expectedChoice] + Array(distractors.prefix(4))

        return finalChoices.shuffled()
    }

    private static func canonicalPrompt(_ prompt: String) -> String {
        collapsedWhitespace(prompt).lowercased()
    }

    private static func collapsedWhitespace(_ string: String) -> String {
        string
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clipped(_ string: String, maxLength: Int) -> String {
        guard string.count > maxLength else {
            return string
        }

        return String(string.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LocalDraftQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind = .localTemplates

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        let goal = request.goal
        let topics = goal.focusAreas
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let focusTopics = topics.isEmpty ? defaultTopics(for: goal.category) : topics

        return focusTopics.prefix(8).enumerated().flatMap { index, topic in
            let competency = request.competencies.first(where: { $0.topic == topic })
            let targetDifficulty = targetDifficulty(for: competency, fallback: index + 1)
            return questions(for: goal, topic: topic, difficulty: targetDifficulty)
        }
    }

    private func defaultTopics(for category: GoalCategory) -> [String] {
        switch category {
        case .codingInterview:
            return ["arrays", "recursion", "Big-O", "hash maps"]
        case .examPrep:
            return ["weakest topic", "missed questions", "timed practice", "review plan"]
        case .languageLearning:
            return ["vocabulary", "grammar", "translation", "listening recall"]
        case .fitness:
            return ["next workout", "minimum session", "recovery", "consistency"]
        case .writing:
            return ["next sentence", "outline", "revision", "publishing"]
        case .custom:
            return ["next step", "blocked area", "quick proof", "review"]
        }
    }

    private func targetDifficulty(for competency: TopicCompetency?, fallback: Int) -> Int {
        guard let competency else {
            return min(fallback, 5)
        }

        return min(5, max(1, Int((competency.estimatedLevel + 0.5).rounded())))
    }

    private func questions(for goal: Goal, topic: String, difficulty: Int) -> [CheckpointQuestion] {
        switch goal.category {
        case .codingInterview:
            return [
                multipleChoiceQuestion(
                    goal: goal,
                    prompt: "Which answer best describes what to watch for when solving a \(topic) problem?",
                    expectedAnswer: "A concrete tradeoff such as time, space, recursion depth, lookup cost, or ordering constraints.",
                    choices: [
                        "A concrete tradeoff such as time, space, recursion depth, lookup cost, or ordering constraints.",
                        "Only whether the code uses the fewest possible lines.",
                        "Only the name of the data structure in the prompt.",
                        "Whether the solution feels familiar from memory."
                    ],
                    explanation: "A useful coding checkpoint should identify the constraint that changes the solution strategy.",
                    topic: topic,
                    difficulty: difficulty
                ),
                multipleChoiceQuestion(
                    goal: goal,
                    prompt: "Which 10-minute practice rep would create the clearest progress on \(topic)?",
                    expectedAnswer: "Solve one focused example and write the time and space complexity.",
                    choices: [
                        "Solve one focused example and write the time and space complexity.",
                        "Open a long tutorial without choosing a stopping point.",
                        "Think about practicing later when there is more time.",
                        "Read the problem title and move on."
                    ],
                    explanation: "The best checkpoint action has a small finish line and produces evidence of practice.",
                    topic: topic,
                    difficulty: difficulty
                )
            ]
        default:
            return [
                multipleChoiceQuestion(
                    goal: goal,
                    prompt: "Which option is the strongest next step for \(topic)?",
                    expectedAnswer: "A specific action with a clear finish line.",
                    choices: [
                        "A specific action with a clear finish line.",
                        "A vague intention to try harder later.",
                        "A broad topic to think about someday.",
                        "A distraction that feels related to the goal."
                    ],
                    explanation: "Checkpoint should push the user toward an action that can be completed or checked.",
                    topic: topic,
                    difficulty: difficulty
                ),
                multipleChoiceQuestion(
                    goal: goal,
                    prompt: "What would count as visible progress on \(topic) today?",
                    expectedAnswer: "A measurable action or proof of progress.",
                    choices: [
                        "A measurable action or proof of progress.",
                        "Feeling motivated without doing anything concrete.",
                        "Avoiding the topic until the deadline gets closer.",
                        "Opening another app to reset."
                    ],
                    explanation: "Visible progress makes the goal trackable and easier to resume.",
                    topic: topic,
                    difficulty: difficulty
                )
            ]
        }
    }

    private func multipleChoiceQuestion(
        goal: Goal,
        prompt: String,
        expectedAnswer: String,
        choices: [String],
        explanation: String,
        topic: String,
        difficulty: Int
    ) -> CheckpointQuestion {
        CheckpointQuestion(
            goalID: goal.id,
            prompt: prompt,
            expectedAnswer: expectedAnswer,
            choices: choices,
            explanation: explanation,
            topic: topic,
            difficulty: difficulty,
            format: .multipleChoice,
            sourcePrompt: sourcePrompt(for: goal)
        )
    }

    private func sourcePrompt(for goal: Goal) -> String {
        """
        Provider: local templates
        Goal: \(goal.title)
        Category: \(goal.category.rawValue)
        Level: \(goal.currentLevel)
        Focus areas: \(goal.focusAreas)
        Deadline: \(goal.deadline.formatted(date: .abbreviated, time: .omitted))
        """
    }
}
