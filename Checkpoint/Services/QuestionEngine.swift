import Foundation

enum QuestionGenerationError: LocalizedError, Sendable {
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

struct QuestionGenerationRequest: Sendable {
    var goal: Goal
    var existingQuestions: [CheckpointQuestion]
    var competencies: [TopicCompetency]
    var reportedQuestions: [QuestionQualityReport]
    var targetCount: Int
    var minimumDifficulty: Int
    var backendEndpoint: URL?

    var questionContext: GoalQuestionContext {
        GoalQuestionContext(goal: goal)
    }

    func sourcePrompt(provider: AIProviderKind) -> String {
        let context = questionContext

        return """
        Here is the user's goal: \(goal.title)
        The actual learning target to test is: \(context.learningTarget)
        The user's current level/context is: \(goal.currentLevel.isEmpty ? "Not specified" : goal.currentLevel)
        The user's focus topics are: \(context.contentTopics.joined(separator: ", "))

        Generate \(targetCount) level \(minimumDifficulty) of 5 difficulty multiple-choice questions about \(context.learningTarget).
        Question style guidance: \(context.questionDirective)

        Use these competency notes to target weak areas: \(competencySummary)
        Avoid these existing prompts: \(existingQuestions.map(\.prompt).prefix(10).joined(separator: " | "))
        Avoid these reported prompts: \(reportedQuestions.map(\.prompt).prefix(10).joined(separator: " | "))

        Requirements:
        - Ask about \(context.learningTarget) itself, not study plans, productivity, motivation, app blocking, or what the learner should do next unless the learning target is explicitly study skills.
        - Make every question answerable as a short multiple-choice knowledge check.
        - Each question must include 4 choices, one exact expected answer, a short explanation, a topic, and a 1-to-5 difficulty.
        """
    }

    var competencySummary: String {
        guard !competencies.isEmpty else { return "None yet" }
        return competencies
            .map { "\($0.topic): level \($0.displayLevel) of 5, mastery \($0.masteryPercent)%" }
            .joined(separator: "; ")
    }
}

struct GoalQuestionContext: Equatable, Sendable {
    var learningTarget: String
    var contentTopics: [String]
    var questionDirective: String
    var allowsStudyStrategyQuestions: Bool

    init(goal: Goal) {
        let target = GoalQuestionContext.learningTarget(from: goal)
        learningTarget = target
        contentTopics = GoalQuestionContext.contentTopics(for: goal, learningTarget: target)
        questionDirective = GoalQuestionContext.questionDirective(
            goal: goal,
            learningTarget: target,
            contentTopics: contentTopics
        )
        allowsStudyStrategyQuestions = GoalQuestionContext.allowsStudyStrategyQuestions(
            goal: goal,
            learningTarget: target
        )
    }

    private static func learningTarget(from goal: Goal) -> String {
        let title = collapsedWhitespace(goal.title)
        let lowercasedTitle = title.lowercased()
        let lowercasedTokens = lowercasedTitle
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        let namedTargets: [(needles: [String], canonical: String)] = [
            (["lsat", "law school admission test"], "LSAT"),
            (["mcat", "medical college admission test"], "MCAT"),
            (["gre", "graduate record examination"], "GRE"),
            (["gmat", "graduate management admission test"], "GMAT"),
            (["sat"], "SAT"),
            (["act"], "ACT"),
            (["bar exam"], "Bar Exam")
        ]

        if let target = namedTargets.first(where: { target in
            target.needles.contains { needle in
                needle.contains(" ")
                    ? lowercasedTitle.contains(needle)
                    : lowercasedTokens.contains(needle)
            }
        }) {
            return target.canonical
        }

        let prefixes = [
            "study for the ",
            "study for ",
            "studying for the ",
            "studying for ",
            "prepare for the ",
            "prepare for ",
            "preparing for the ",
            "preparing for ",
            "prep for the ",
            "prep for ",
            "pass the ",
            "pass ",
            "ace the ",
            "ace ",
            "learn ",
            "learning ",
            "master ",
            "practice ",
            "improve my ",
            "improve at ",
            "get better at ",
            "get better with "
        ]

        for prefix in prefixes where lowercasedTitle.hasPrefix(prefix) {
            let index = title.index(title.startIndex, offsetBy: prefix.count)
            return fallbackTarget(String(title[index...]), category: goal.category)
        }

        return fallbackTarget(title, category: goal.category)
    }

    private static func fallbackTarget(_ text: String, category: GoalCategory) -> String {
        var trimmed = collapsedWhitespace(text)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".:;,- "))

        for article in ["a ", "an ", "the "] where trimmed.lowercased().hasPrefix(article) {
            let index = trimmed.index(trimmed.startIndex, offsetBy: article.count)
            trimmed = String(trimmed[index...])
            break
        }

        guard !trimmed.isEmpty else {
            return category.rawValue
        }

        return trimmed
    }

    private static func contentTopics(for goal: Goal, learningTarget: String) -> [String] {
        let rawTopics = goal.focusAreas
            .split(separator: ",")
            .map { collapsedWhitespace(String($0)) }
            .filter { !$0.isEmpty }

        if isLSAT(learningTarget) {
            let mappedTopics = rawTopics.map(lsatTopic)
            return unique(mappedTopics.isEmpty ? ["Logical Reasoning", "Reading Comprehension"] : mappedTopics)
        }

        if !rawTopics.isEmpty {
            return unique(rawTopics)
        }

        switch goal.category {
        case .codingInterview:
            return ["arrays", "recursion", "Big-O", "hash maps"]
        case .examPrep:
            if learningTarget.lowercased().contains("calculus") {
                return ["limits", "derivatives", "integrals", "applications of derivatives"]
            }
            return [learningTarget]
        case .languageLearning:
            return ["vocabulary", "grammar", "translation", "reading comprehension"]
        case .fitness:
            return ["training load", "recovery", "form", "consistency"]
        case .writing:
            return ["argument", "structure", "revision", "evidence"]
        case .custom:
            return [learningTarget]
        }
    }

    private static func questionDirective(
        goal: Goal,
        learningTarget: String,
        contentTopics: [String]
    ) -> String {
        if isLSAT(learningTarget) {
            return "Generate original LSAT-style Logical Reasoning and Reading Comprehension questions for the current LSAT format. Test reasoning from a stimulus or short passage; do not ask how to study for the LSAT."
        }

        switch goal.category {
        case .codingInterview:
            return "Generate concrete coding-interview knowledge checks about \(contentTopics.joined(separator: ", ")): data-structure choice, algorithm behavior, complexity, edge cases, or debugging."
        case .examPrep:
            return "Generate exam-style questions about \(learningTarget), using \(contentTopics.joined(separator: ", ")) as the tested content. Ask for the answer to the subject-matter problem, not study advice."
        case .languageLearning:
            return "Generate language questions that test vocabulary, grammar, translation, or comprehension in \(learningTarget)."
        case .fitness:
            return "Generate training-knowledge questions about \(learningTarget), form, recovery, adaptation, or safe programming."
        case .writing:
            return "Generate writing-craft questions about \(learningTarget), argument structure, clarity, revision, or evidence."
        case .custom:
            return "Generate knowledge-check questions about \(learningTarget) using the listed content topics."
        }
    }

    private static func allowsStudyStrategyQuestions(goal: Goal, learningTarget: String) -> Bool {
        let signal = "\(goal.title) \(learningTarget) \(goal.focusAreas)".lowercased()
        return [
            "study skill",
            "study skills",
            "productivity",
            "time management",
            "focus habit",
            "habit building",
            "learning how to learn"
        ].contains { signal.contains($0) }
    }

    private static func lsatTopic(_ topic: String) -> String {
        let normalizedTopic = topic.lowercased()

        if normalizedTopic.contains("reading") || normalizedTopic.contains("rc") {
            return "Reading Comprehension"
        }

        if normalizedTopic.contains("logical")
            || normalizedTopic.contains("reasoning")
            || normalizedTopic.contains("argument")
            || normalizedTopic.contains("logic game")
            || normalizedTopic.contains("analytical") {
            return "Logical Reasoning"
        }

        return topic
    }

    private static func isLSAT(_ target: String) -> Bool {
        target
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("LSAT") == .orderedSame
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            let key = value.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func collapsedWhitespace(_ string: String) -> String {
        string
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct QuestionBatch: Sendable {
    var questions: [CheckpointQuestion]
    var provider: AIProviderKind
    var usedFallback: Bool
}

protocol QuestionGenerating: Sendable {
    var provider: AIProviderKind { get }
    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion]
}

struct HybridQuestionEngine: Sendable {
    private let localEngine: any QuestionGenerating
    private let backendEngine: any QuestionGenerating
    private let appleFoundationEngine: any QuestionGenerating

    init(
        localEngine: any QuestionGenerating = LocalDraftQuestionEngine(),
        backendEngine: any QuestionGenerating = BackendQuestionEngine(),
        appleFoundationEngine: any QuestionGenerating = AppleFoundationQuestionEngine()
    ) {
        self.localEngine = localEngine
        self.backendEngine = backendEngine
        self.appleFoundationEngine = appleFoundationEngine
    }

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

            guard sanitizedQuestion.difficulty >= request.minimumDifficulty,
                  isUsable(sanitizedQuestion, for: request),
                  !seenPrompts.contains(promptKey) else {
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

    private static func isUsable(_ question: CheckpointQuestion, for request: QuestionGenerationRequest) -> Bool {
        question.prompt.count >= 12
            && !question.expectedAnswer.isEmpty
            && question.format == .multipleChoice
            && question.choices.count >= 2
            && question.choices.contains(where: { canonicalPrompt($0) == canonicalPrompt(question.expectedAnswer) })
            && !question.explanation.isEmpty
            && !question.topic.isEmpty
            && !isStudyStrategyPrompt(question.prompt, context: request.questionContext)
    }

    private static func isStudyStrategyPrompt(_ prompt: String, context: GoalQuestionContext) -> Bool {
        guard !context.allowsStudyStrategyQuestions else { return false }

        let normalizedPrompt = canonicalPrompt(prompt)
        let blockedPhrases = [
            "how should you study",
            "study plan",
            "study rep",
            "study schedule",
            "study strategy",
            "practice rep",
            "clearest progress",
            "next step",
            "visible progress",
            "finish line",
            "try harder",
            "motivation",
            "blocked app",
            "open another app",
            "distraction",
            "what should you do next"
        ]

        return blockedPhrases.contains { normalizedPrompt.contains($0) }
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
        let context = request.questionContext
        let sourcePrompt = request.sourcePrompt(provider: provider)
        let focusTopics = context.contentTopics

        return focusTopics.prefix(8).enumerated().flatMap { index, topic in
            let competency = request.competencies.first(where: { $0.topic == topic })
            let targetDifficulty = max(
                request.minimumDifficulty,
                targetDifficulty(for: competency, fallback: index + 1)
            )
            return questions(
                for: goal,
                context: context,
                topic: topic,
                difficulty: targetDifficulty,
                sourcePrompt: sourcePrompt
            )
        }
    }

    private func targetDifficulty(for competency: TopicCompetency?, fallback: Int) -> Int {
        guard let competency else {
            return min(fallback, 5)
        }

        return min(5, max(1, Int((competency.estimatedLevel + 0.5).rounded())))
    }

    private func questions(
        for goal: Goal,
        context: GoalQuestionContext,
        topic: String,
        difficulty: Int,
        sourcePrompt: String
    ) -> [CheckpointQuestion] {
        if context.learningTarget == "LSAT" {
            return lsatQuestions(for: goal, topic: topic, difficulty: difficulty, sourcePrompt: sourcePrompt)
        }

        switch goal.category {
        case .codingInterview:
            return codingQuestions(for: goal, topic: topic, difficulty: difficulty, sourcePrompt: sourcePrompt)
        case .examPrep where context.learningTarget.lowercased().contains("calculus"):
            return calculusQuestions(for: goal, topic: topic, difficulty: difficulty, sourcePrompt: sourcePrompt)
        case .examPrep:
            return examContentQuestions(
                for: goal,
                context: context,
                topic: topic,
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            )
        default:
            return generalKnowledgeQuestions(
                for: goal,
                context: context,
                topic: topic,
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            )
        }
    }

    private func lsatQuestions(
        for goal: Goal,
        topic: String,
        difficulty: Int,
        sourcePrompt: String
    ) -> [CheckpointQuestion] {
        if topic.localizedCaseInsensitiveContains("Reading") {
            return [
                multipleChoiceQuestion(
                    goal: goal,
                    prompt: "LSAT Reading Comprehension: A passage argues that courts should value predictable rules, but also says rigid rules can produce unfair outcomes in unusual cases. What is the passage's main point?",
                    expectedAnswer: "Legal rules should be predictable while still allowing limited flexibility for unusual facts.",
                    choices: [
                        "Legal rules should be predictable while still allowing limited flexibility for unusual facts.",
                        "Courts should ignore predictability whenever fairness is mentioned.",
                        "Rigid rules are always more just than flexible standards.",
                        "Unusual cases should never affect how courts apply rules."
                    ],
                    explanation: "The passage balances predictability with narrow flexibility, so the best answer captures both sides.",
                    topic: "Reading Comprehension",
                    difficulty: difficulty,
                    sourcePrompt: sourcePrompt
                ),
                multipleChoiceQuestion(
                    goal: goal,
                    prompt: "LSAT Reading Comprehension: An author describes a theory as 'promising but incomplete.' Which choice best describes the author's attitude?",
                    expectedAnswer: "Qualified approval.",
                    choices: [
                        "Qualified approval.",
                        "Total rejection.",
                        "Neutral summary without evaluation.",
                        "Confusion about the theory's claims."
                    ],
                    explanation: "'Promising' is positive, while 'incomplete' limits the approval.",
                    topic: "Reading Comprehension",
                    difficulty: difficulty,
                    sourcePrompt: sourcePrompt
                )
            ]
        }

        return [
            multipleChoiceQuestion(
                goal: goal,
                prompt: "LSAT Logical Reasoning: A city installed brighter streetlights downtown. The next year, reported nighttime thefts increased. Therefore, brighter lighting caused more thefts. What is the main flaw?",
                expectedAnswer: "The argument treats a timing correlation as proof of causation.",
                choices: [
                    "The argument treats a timing correlation as proof of causation.",
                    "The argument proves that lighting can never affect theft.",
                    "The argument relies on a definition of theft that is too narrow.",
                    "The argument assumes every downtown resident reported a theft."
                ],
                explanation: "The increase happened after the lights, but the stimulus gives no evidence that the lights caused it.",
                topic: "Logical Reasoning",
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            ),
            multipleChoiceQuestion(
                goal: goal,
                prompt: "LSAT Logical Reasoning: All applicants with incomplete forms are rejected. Jordan was not rejected. Which assumption is needed to conclude Jordan's form was complete?",
                expectedAnswer: "Every submitted form is either complete or incomplete.",
                choices: [
                    "Every submitted form is either complete or incomplete.",
                    "Jordan submitted the form before the deadline.",
                    "Most applicants with complete forms are accepted.",
                    "Rejected applicants may apply again later."
                ],
                explanation: "The conclusion needs the binary split between complete and incomplete forms.",
                topic: "Logical Reasoning",
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            )
        ]
    }

    private func codingQuestions(
        for goal: Goal,
        topic: String,
        difficulty: Int,
        sourcePrompt: String
    ) -> [CheckpointQuestion] {
        [
            multipleChoiceQuestion(
                goal: goal,
                prompt: "Coding interview: When a \(topic) solution uses a hash map to remember previously seen values, what improvement is it usually trying to make?",
                expectedAnswer: "Reduce repeated searches by trading extra memory for faster lookups.",
                choices: [
                    "Reduce repeated searches by trading extra memory for faster lookups.",
                    "Guarantee the code uses no additional memory.",
                    "Avoid checking edge cases in the input.",
                    "Make the algorithm recursive even when iteration is simpler."
                ],
                explanation: "Hash maps commonly convert repeated lookup work into near-constant-time access with added space.",
                topic: topic,
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            ),
            multipleChoiceQuestion(
                goal: goal,
                prompt: "Coding interview: Which edge case is most important to test for a \(topic) problem before trusting the solution?",
                expectedAnswer: "The smallest valid input and a case with repeated or missing values.",
                choices: [
                    "The smallest valid input and a case with repeated or missing values.",
                    "Only a large random input with no explanation.",
                    "Only the sample case from the prompt.",
                    "A case that ignores the problem constraints."
                ],
                explanation: "Small and constraint-stressing inputs reveal many logic errors quickly.",
                topic: topic,
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            )
        ]
    }

    private func calculusQuestions(
        for goal: Goal,
        topic: String,
        difficulty: Int,
        sourcePrompt: String
    ) -> [CheckpointQuestion] {
        [
            multipleChoiceQuestion(
                goal: goal,
                prompt: "Calculus: If f'(x) changes from positive to negative at x = a, what does that usually indicate?",
                expectedAnswer: "f has a local maximum at x = a.",
                choices: [
                    "f has a local maximum at x = a.",
                    "f has a local minimum at x = a.",
                    "f is constant for every x.",
                    "f is undefined at every nearby point."
                ],
                explanation: "A derivative changing from positive to negative means the function rises before a and falls after a.",
                topic: topic,
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            ),
            multipleChoiceQuestion(
                goal: goal,
                prompt: "Calculus: What does a definite integral of velocity over a time interval represent?",
                expectedAnswer: "Net displacement over that interval.",
                choices: [
                    "Net displacement over that interval.",
                    "The largest instantaneous speed only.",
                    "The slope of the velocity graph at one point.",
                    "The average of the endpoints with no units."
                ],
                explanation: "Integrating velocity with respect to time accumulates signed change in position.",
                topic: topic,
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            )
        ]
    }

    private func examContentQuestions(
        for goal: Goal,
        context: GoalQuestionContext,
        topic: String,
        difficulty: Int,
        sourcePrompt: String
    ) -> [CheckpointQuestion] {
        [
            multipleChoiceQuestion(
                goal: goal,
                prompt: "\(context.learningTarget): Which answer best applies the concept of \(topic) to a test question?",
                expectedAnswer: "Use the facts in the prompt to eliminate choices that do not directly follow.",
                choices: [
                    "Use the facts in the prompt to eliminate choices that do not directly follow.",
                    "Pick the answer that uses the most familiar words.",
                    "Ignore qualifiers because they rarely change the answer.",
                    "Choose the broadest statement even if it goes beyond the prompt."
                ],
                explanation: "Most exam questions reward applying the stated facts and respecting qualifiers.",
                topic: topic,
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            ),
            multipleChoiceQuestion(
                goal: goal,
                prompt: "\(context.learningTarget): A question stem asks for the answer that is 'most strongly supported.' What should the correct answer do?",
                expectedAnswer: "Stay close to what the passage or problem facts actually establish.",
                choices: [
                    "Stay close to what the passage or problem facts actually establish.",
                    "Add a new assumption that sounds plausible.",
                    "Contradict the passage to test an alternative view.",
                    "Use extreme language whenever the topic is familiar."
                ],
                explanation: "Support questions are strongest when the answer is warranted by the supplied information.",
                topic: topic,
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            )
        ]
    }

    private func generalKnowledgeQuestions(
        for goal: Goal,
        context: GoalQuestionContext,
        topic: String,
        difficulty: Int,
        sourcePrompt: String
    ) -> [CheckpointQuestion] {
        [
            multipleChoiceQuestion(
                goal: goal,
                prompt: "\(context.learningTarget): Which statement about \(topic) is the most precise?",
                expectedAnswer: "The statement that can be checked against the specific facts or rules of the topic.",
                choices: [
                    "The statement that can be checked against the specific facts or rules of the topic.",
                    "The broadest statement, even if it ignores details.",
                    "The statement that sounds motivating but cannot be verified.",
                    "The answer that changes the topic to planning."
                ],
                explanation: "Checkpoint questions should test knowledge that can be verified, not vague intent.",
                topic: topic,
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            ),
            multipleChoiceQuestion(
                goal: goal,
                prompt: "\(context.learningTarget): When two answer choices seem plausible for \(topic), which one is usually stronger?",
                expectedAnswer: "The choice that fits all stated constraints without adding new assumptions.",
                choices: [
                    "The choice that fits all stated constraints without adding new assumptions.",
                    "The choice that is more dramatic.",
                    "The choice that ignores exceptions.",
                    "The choice that is unrelated but easier to remember."
                ],
                explanation: "Good knowledge checks reward constraint-aware reasoning inside the target domain.",
                topic: topic,
                difficulty: difficulty,
                sourcePrompt: sourcePrompt
            )
        ]
    }

    private func multipleChoiceQuestion(
        goal: Goal,
        prompt: String,
        expectedAnswer: String,
        choices: [String],
        explanation: String,
        topic: String,
        difficulty: Int,
        sourcePrompt: String
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
            sourcePrompt: sourcePrompt
        )
    }
}
