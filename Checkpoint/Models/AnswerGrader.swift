import Foundation

struct AnswerEvaluation: Equatable, Sendable {
    var result: AnswerResult
    var feedback: String
}

enum MultipleChoiceAnswerNormalizer {
    static func key(for text: String) -> String {
        let normalized = normalizedText(text)
        return compact(
            strippingChoiceLabel(
                from: strippingAnswerPrefix(from: normalized)
            )
        )
    }

    static func choiceIndex(from text: String) -> Int? {
        let normalized = strippingAnswerPrefix(from: normalizedText(text))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let textWithoutLabel = strippingChoiceLabel(from: normalized)
        guard textWithoutLabel != normalized || normalized.count == 1 else { return nil }

        let characters = Array(normalized)
        let first = characters.count >= 3 && (characters[0] == "(" || characters[0] == "[")
            ? characters[1]
            : characters[0]

        switch first {
        case "a", "1": return 0
        case "b", "2": return 1
        case "c", "3": return 2
        case "d", "4": return 3
        default: return nil
        }
    }

    static func choiceMentionedAsCorrect(
        in explanation: String,
        choices: [String],
        collapsingWhitespaceForPhraseMatching: Bool = false
    ) -> String? {
        let phraseMatchingText = collapsingWhitespaceForPhraseMatching
            ? explanation.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            : explanation
        let explanationWords = normalizedText(phraseMatchingText)
        guard explanationWords.contains("correct")
            || explanationWords.contains("best answer")
            || explanationWords.contains("right answer") else {
            return nil
        }

        let normalizedExplanation = key(for: explanation)
        let mentionedChoices = choices.filter { choice in
            let choiceKey = key(for: choice)
            return choiceKey.count >= 12 && normalizedExplanation.contains(choiceKey)
        }

        guard mentionedChoices.count == 1 else { return nil }
        return mentionedChoices[0]
    }

    static func strippingAnswerPrefix(from text: String) -> String {
        let prefixes = [
            "correct answer",
            "correct choice",
            "correct option",
            "answer",
            "choice",
            "option"
        ]

        for prefix in prefixes where text.hasPrefix(prefix) {
            let remainder = String(text.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n:-."))
            guard !remainder.isEmpty else { return text }
            return remainder
        }

        return text
    }

    static func strippingChoiceLabel(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(trimmed)
        let labels = Set("abcd1234")

        if characters.count >= 3,
           (characters[0] == "(" || characters[0] == "["),
           labels.contains(characters[1]),
           (characters[2] == ")" || characters[2] == "]") {
            return String(characters.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if characters.count >= 2,
           labels.contains(characters[0]),
           [".", ")", ":", "]"].contains(String(characters[1])) {
            return String(characters.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compact(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

enum AnswerGrader {
    static func correctAnswerText(
        for question: CheckpointQuestion,
        after result: AnswerResult
    ) -> String? {
        guard result != .correct else { return nil }

        let expectedAnswer = nonEmptyText(question.expectedAnswer)
        guard question.format == .multipleChoice else {
            return expectedAnswer
        }

        let resolvedChoices = question.choices.filter { choice in
            evaluate(answer: choice, question: question).result == .correct
        }

        guard resolvedChoices.count == 1,
              let resolvedChoice = resolvedChoices.first else {
            return expectedAnswer
        }

        return nonEmptyText(resolvedChoice) ?? expectedAnswer
    }

    static func evaluate(answer: String, question: CheckpointQuestion) -> AnswerEvaluation {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAnswer.isEmpty else {
            return AnswerEvaluation(result: .unclear, feedback: "No answer entered yet.")
        }

        switch question.format {
        case .reflection:
            return evaluateReflection(trimmedAnswer)
        case .multipleChoice:
            return evaluateMultipleChoice(answer: trimmedAnswer, question: question)
        case .shortAnswer, .codeTrace:
            return evaluateObjective(answer: trimmedAnswer, expectedAnswer: question.expectedAnswer)
        }
    }

    private static func evaluateReflection(_ answer: String) -> AnswerEvaluation {
        let wordCount = tokens(in: answer).count

        if wordCount >= 8 {
            return AnswerEvaluation(result: .correct, feedback: "Specific enough to count as progress.")
        }

        if wordCount >= 4 {
            return AnswerEvaluation(result: .partial, feedback: "Close, but it needs a clearer next step.")
        }

        return AnswerEvaluation(result: .incorrect, feedback: "Too vague to count yet.")
    }

    private static func evaluateMultipleChoice(answer: String, question: CheckpointQuestion) -> AnswerEvaluation {
        if question.verificationVersion == 1 {
            let correct = question.choices.contains(question.expectedAnswer)
                && answer == question.expectedAnswer
            return AnswerEvaluation(
                result: correct ? .correct : .incorrect,
                feedback: correct ? "Correct choice." : "That choice is not correct yet."
            )
        }
        let answerKey = MultipleChoiceAnswerNormalizer.key(for: answer)
        let expectedKey = MultipleChoiceAnswerNormalizer.key(for: question.expectedAnswer)
        let indexedExpectedChoice = MultipleChoiceAnswerNormalizer.choiceIndex(
            from: question.expectedAnswer
        ).flatMap { index in
            question.choices.indices.contains(index) ? question.choices[index] : nil
        }
        let matchingExpectedChoice = indexedExpectedChoice ?? question.choices.first {
            let choiceKey = MultipleChoiceAnswerNormalizer.key(for: $0)
            return choiceKey == expectedKey || (choiceKey.count >= 12 && expectedKey.contains(choiceKey))
        }
        let explanationChoice = MultipleChoiceAnswerNormalizer.choiceMentionedAsCorrect(
            in: question.explanation,
            choices: question.choices
        )
        let resolvedExpectedKey = (explanationChoice ?? matchingExpectedChoice).map {
            MultipleChoiceAnswerNormalizer.key(for: $0)
        } ?? expectedKey
        let allowsRawExpectedFallback = explanationChoice == nil

        if answerKey == resolvedExpectedKey || (allowsRawExpectedFallback && answerKey == expectedKey) {
            return AnswerEvaluation(result: .correct, feedback: "Correct choice.")
        }

        return AnswerEvaluation(result: .incorrect, feedback: "That choice is not correct yet.")
    }

    private static func evaluateObjective(answer: String, expectedAnswer: String) -> AnswerEvaluation {
        let compactAnswer = compact(answer)
        let compactExpected = compact(expectedAnswer)

        if !compactExpected.isEmpty,
           (compactAnswer == compactExpected || compactAnswer.contains(compactExpected)) {
            return AnswerEvaluation(result: .correct, feedback: "Matches the expected answer.")
        }

        let answerTokens = Set(tokens(in: answer))
        let expectedTokens = Set(tokens(in: expectedAnswer))

        guard !answerTokens.isEmpty, !expectedTokens.isEmpty else {
            return AnswerEvaluation(result: .unclear, feedback: "Not enough signal to grade.")
        }

        let overlap = Double(answerTokens.intersection(expectedTokens).count) / Double(expectedTokens.count)

        if overlap >= 0.65 {
            return AnswerEvaluation(result: .correct, feedback: "Close enough to the expected answer.")
        }

        if overlap >= 0.35 {
            return AnswerEvaluation(result: .partial, feedback: "Partially matches, but misses key details.")
        }

        return AnswerEvaluation(result: .incorrect, feedback: "Does not match the expected answer yet.")
    }

    private static func tokens(in text: String) -> [String] {
        let cleaned = text
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : " "
            }

        return String(cleaned)
            .split(separator: " ")
            .map(String.init)
            .filter { !stopWords.contains($0) }
    }

    private static func compact(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func nonEmptyText(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
        "in", "is", "it", "of", "on", "or", "that", "the", "to", "with"
    ]
}
