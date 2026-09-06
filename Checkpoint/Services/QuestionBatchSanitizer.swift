import Foundation

enum QuestionBatchSanitizer {
    static let stemFingerprintVersion = 2

    /// Preserve subject case, indentation, quoted spaces and punctuation.
    /// Cosmetic prose equivalence is a semantic-review decision.
    static func questionStemKeys(_ prompt: String) -> Set<Data> {
        let key = exactQuestionStemKey(prompt)
        return key.isEmpty ? [] : [key]
    }

    static func hasSameQuestionStem(_ lhs: String, _ rhs: String) -> Bool {
        !questionStemKeys(lhs).isDisjoint(with: questionStemKeys(rhs))
    }

    /// Compact wire identity for comparing the complete local history without
    /// sending old question text back to the generation model.
    static func questionStemFingerprint(_ prompt: String) -> String? {
        guard let key = questionStemKeys(prompt).first else { return nil }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    static func sanitize(_ questions: [CheckpointQuestion], for request: QuestionGenerationRequest) -> [CheckpointQuestion] {
        let existingPrompts = Set(request.existingQuestions.flatMap { promptKeys($0.prompt) })
        let reportedPrompts = Set(request.reportedQuestions.flatMap { promptKeys($0.prompt) })
        var seenPrompts = existingPrompts.union(reportedPrompts)
        let existingCoverage = Set(request.existingQuestions.flatMap(questionCoverageKeys))
        let reportedCoverage = Set(request.reportedQuestions.flatMap { report in
            questionCoverageKeys(
                prompt: report.prompt,
                expectedAnswer: "",
                topic: ""
            )
        })
        var seenCoverage = existingCoverage.union(reportedCoverage)
        var sanitizedQuestions: [CheckpointQuestion] = []

        for question in questions {
            guard !request.requiresVerifiedQuestions || question.verificationVersion == 1 else { continue }
            var sanitizedQuestion = question
            let prompt = promptWithoutTrailingChoiceEcho(question.prompt, choices: question.choices)
            guard prompt.count <= 360 else { continue }
            sanitizedQuestion.prompt = prompt
            let expectedAnswer = MultipleChoiceAnswerNormalizer.text(for: question.expectedAnswer)
            guard expectedAnswer.count <= 280 else { continue }
            let choiceResolution: (expectedAnswer: String, choices: [String])?
            if question.verificationVersion == 1 {
                // A reviewed answer is the exact choice text. Legacy label/cue
                // heuristics must never reinterpret numbers inside that text.
                choiceResolution = question.choices.count == 4
                    && hasUniqueChoices(question.choices)
                    && question.choices.contains { answerKey($0) == answerKey(question.expectedAnswer) }
                    && question.choices.allSatisfy { !$0.isEmpty && $0.count <= 140 }
                    ? (question.expectedAnswer, question.choices.shuffled()) : nil
            } else {
                choiceResolution = sanitizedChoices(
                    question.choices,
                    expectedAnswer: expectedAnswer,
                    explanation: question.explanation
                )
            }
            guard let choiceResolution else {
                continue
            }
            sanitizedQuestion.expectedAnswer = choiceResolution.expectedAnswer
            if question.verificationVersion == 1,
               answerKey(choiceResolution.expectedAnswer) != answerKey(question.expectedAnswer) { continue }
            sanitizedQuestion.choices = choiceResolution.choices
            sanitizedQuestion.choiceExplanations = question.choiceExplanations.filter {
                let entry = $0
                return sanitizedQuestion.choices.contains { Data($0.utf8) == Data(entry.key.utf8) }
                    && (12...280).contains(entry.value.count)
            }
            sanitizedQuestion.explanation = QuestionText.clipped(
                question.explanation.trimmingCharacters(in: .whitespacesAndNewlines),
                maxLength: 420
            )
            sanitizedQuestion.topic = QuestionText.clipped(
                QuestionText.collapsedWhitespace(question.topic),
                maxLength: 48
            )
            sanitizedQuestion.difficulty = min(5, max(1, question.difficulty))
            sanitizedQuestion.format = .multipleChoice
            sanitizedQuestion.status = .new
            sanitizedQuestion.timesAsked = 0
            sanitizedQuestion.timesCorrect = 0
            sanitizedQuestion.lastAskedAt = nil
            sanitizedQuestion.nextReviewAt = nil

            let promptKeys = promptKeys(sanitizedQuestion.prompt)
            let coverageKeys = questionCoverageKeys(sanitizedQuestion)

            guard sanitizedQuestion.difficulty >= request.minimumDifficulty,
                  isUsable(sanitizedQuestion, for: request),
                  seenPrompts.isDisjoint(with: promptKeys),
                  seenCoverage.isDisjoint(with: coverageKeys) else {
                continue
            }

            seenPrompts.formUnion(promptKeys)
            seenCoverage.formUnion(coverageKeys)
            sanitizedQuestions.append(sanitizedQuestion)

            if sanitizedQuestions.count >= request.targetCount {
                break
            }
        }

        return sanitizedQuestions
    }

    private static func questionCoverageKeys(_ question: CheckpointQuestion) -> Set<Data> {
        var keys = questionCoverageKeys(
            prompt: question.prompt,
            expectedAnswer: question.expectedAnswer,
            topic: question.topic
        )

        let choiceSetKey = question.choices
            .map(choiceUniquenessKey)
            .filter { !$0.isEmpty }
            .sorted { $0.lexicographicallyPrecedes($1) }
            .reduce(into: Data()) { result, key in
                result.append(Data("\(key.count):".utf8))
                result.append(key)
            }
        if question.choices.count == 4, !choiceSetKey.isEmpty {
            keys.insert(Data("choice-set:".utf8) + choiceSetKey)
        }

        return keys
    }

    private static func questionCoverageKeys(
        prompt: String,
        expectedAnswer: String,
        topic: String
    ) -> Set<Data> {
        var keys: Set<Data> = []
        let topicKey = choiceUniquenessKey(topic)
        let answerKey = choiceUniquenessKey(expectedAnswer)

        if MultipleChoiceAnswerNormalizer.text(for: topic).count >= 3,
           MultipleChoiceAnswerNormalizer.text(for: expectedAnswer).count >= 16 {
            keys.insert(Data("topic-answer:\(topicKey.count):".utf8) + topicKey + answerKey)
        }

        return keys
    }

    private static func isUsable(_ question: CheckpointQuestion, for request: QuestionGenerationRequest) -> Bool {
        question.prompt.count >= 12
            && !question.expectedAnswer.isEmpty
            && question.format == .multipleChoice
            && question.choices.count == 4
            && hasUniqueChoices(question.choices)
            && question.choices.filter { answerKey($0) == answerKey(question.expectedAnswer) }.count == 1
            && !question.explanation.isEmpty
            && !question.topic.isEmpty
            && !isGenericAssessmentMetaQuestion(question)
            && !isStudyStrategyPrompt(question.prompt, context: request.questionContext)
            && !containsEmbeddedAnswerOptions(question.prompt)
            && (question.verificationVersion == 1 || !explanationSupportsDifferentChoice(
                expectedAnswer: question.expectedAnswer,
                choices: question.choices,
                explanation: question.explanation
            ))
    }

    private static func isGenericAssessmentMetaQuestion(_ question: CheckpointQuestion) -> Bool {
        let expectedKey = genericProseKey(question.expectedAnswer)
        let exactGenericAnswerSignals = [
            "answerthatfollowsfromthestatedfacts",
            "answerfollowsfromthestatedfacts",
            "respectsthetopicsconstraints",
            "specificfactsorrulesofthetopic",
            "fitsallstatedconstraintswithoutaddingnewassumptions"
        ]
        if exactGenericAnswerSignals.contains(where: expectedKey.contains) {
            return true
        }

        let genericDistractorSignals = [
            "changesthetopictostudyplanning",
            "ignorequalifiers",
            "ignoresqualifiers",
            "addsunsupportedassumptions",
            "soundsfamiliar",
            "picktheanswerthatusesthemostfamiliarwords",
            "broadeststatement",
            "moredramatic",
            "unrelatedbuteasiertoremember"
        ]
        let genericDistractorCount = question.choices.reduce(into: 0) { count, choice in
            let key = genericProseKey(choice)
            if genericDistractorSignals.contains(where: key.contains) {
                count += 1
            }
        }

        return genericDistractorCount >= 2
    }

    private static func isStudyStrategyPrompt(_ prompt: String, context: GoalQuestionContext) -> Bool {
        guard !context.allowsStudyStrategyQuestions else { return false }

        // Match explicit coaching requests. General words such as "next step"
        // or "motivation" can be the subject itself; the reviewer judges context.
        let patterns = [
            #"\bhow (?:should|can|could) (?:you|i|we) study\b"#,
            #"\b(?:your|my|our) (?:study|practice) (?:plan|schedule|strategy|routine)\b"#,
            #"\b(?:study|practice) (?:rep|reps|plan|schedule|strategy)\b.{0,100}\b(?:your|you|my|me|progress|prepare)\b"#,
            #"\bafter (?:missing|failing)\b.{0,80}\b(?:question|quiz|item|test)\b.{0,80}\b(?:study|practice|review|next)\b"#
        ]
        return patterns.contains { prompt.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    static func promptWithoutTrailingChoiceEcho(_ prompt: String, choices: [String]) -> String {
        let cleaned = QuestionText.subjectContent(prompt)
        guard choices.count == 4 else { return cleaned }
        let keys = choices.map(MultipleChoiceAnswerNormalizer.key(for:))
        guard keys.allSatisfy({ !$0.isEmpty }) else { return cleaned }
        let lines = cleaned.components(separatedBy: "\n")
        let nonempty = lines.enumerated().filter { !$0.element.trimmingCharacters(in: .whitespaces).isEmpty }
        guard nonempty.count > 4 else { return cleaned }
        let trailing = Array(nonempty.suffix(4))
        for (index, line) in trailing.enumerated() {
            let text = line.element.trimmingCharacters(in: .whitespaces)
            let label = ["A", "B", "C", "D"][index] + String(index + 1)
            let pattern = #"^(?:[\#(label)][).:]|\([\#(label)]\)|\[[\#(label)]\])\s+"#
            let withoutLabel = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            guard MultipleChoiceAnswerNormalizer.key(for: text) == keys[index]
                    || MultipleChoiceAnswerNormalizer.key(for: withoutLabel) == keys[index] else { return cleaned }
        }
        let prefix = QuestionText.subjectContent(lines.prefix(trailing[0].offset).joined(separator: "\n"))
        return prefix.isEmpty ? cleaned : prefix
    }

    private static func promptKeys(_ prompt: String) -> Set<Data> {
        questionStemKeys(prompt)
    }

    private static func containsEmbeddedAnswerOptions(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        if normalized.contains("options:") { return true }

        if normalized.range(
            of: #"(?i)\b(?:option|choice)\s+[a-d1-4][\).:]"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        return prompt.range(
            of: #"(?s)(?:^|\s)1[\).]\s+.+\s+2[\).]\s+"#,
            options: .regularExpression
        ) != nil || prompt.range(
            of: #"(?s)(?:^|\s)A[\).]\s+.+\s+B[\).]\s+"#,
            options: .regularExpression
        ) != nil || prompt.components(separatedBy: "( )").count - 1 >= 2
    }

    private static func explanationSupportsDifferentChoice(
        expectedAnswer: String,
        choices: [String],
        explanation: String
    ) -> Bool {
        guard let supportedChoice = explanationSupportedChoice(explanation, choices: choices) else {
            return false
        }

        return choiceUniquenessKey(supportedChoice) != choiceUniquenessKey(expectedAnswer)
    }

    private static func explanationSupportedChoice(_ explanation: String, choices: [String]) -> String? {
        let normalizedExplanation = QuestionText.collapsedWhitespace(explanation)
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        let shortOutputChoices: Set<String> = ["positive", "negative", "zero", "undefined", "true", "false"]
        var supportedChoices: [String] = []

        for choice in choices {
            let normalizedChoice = QuestionText.collapsedWhitespace(choice)
                .folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .lowercased()
            guard shortOutputChoices.contains(normalizedChoice) else { continue }

            let pattern = #"\b(?:which|that|it|this|result|sign|value)\s+(?:is|are|equals?)\s+\#(NSRegularExpression.escapedPattern(for: normalizedChoice))\b"#
            if normalizedExplanation.range(of: pattern, options: .regularExpression) != nil {
                supportedChoices.append(choice)
            }
        }

        if let explicitlyCorrectChoice = MultipleChoiceAnswerNormalizer.choiceMentionedAsCorrect(
            in: explanation,
            choices: choices,
            collapsingWhitespaceForPhraseMatching: true
        ) {
            supportedChoices.append(explicitlyCorrectChoice)
        }

        let supportedKeys = Set(supportedChoices.map(choiceUniquenessKey))
        guard supportedKeys.count == 1 else { return nil }
        return supportedChoices.first
    }

    private static func sanitizedChoices(
        _ choices: [String],
        expectedAnswer: String,
        explanation: String
    ) -> (expectedAnswer: String, choices: [String])? {
        let normalizedChoices = choices
            .map { MultipleChoiceAnswerNormalizer.text(for: $0) }
            .filter { !$0.isEmpty }

        guard choices.count == 4, hasUniqueChoices(normalizedChoices) else { return nil }
        var seen: Set<Data> = []
        var uniqueChoices: [String] = []

        for choice in normalizedChoices {
            let key = choiceUniquenessKey(choice)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            uniqueChoices.append(choice)
        }

        guard uniqueChoices.count == 4, uniqueChoices.allSatisfy({ $0.count <= 140 }) else { return nil }

        let indexedChoice = MultipleChoiceAnswerNormalizer.choiceIndex(from: expectedAnswer).flatMap { index in
            uniqueChoices.indices.contains(index) ? uniqueChoices[index] : nil
        }
        let expectedKey = answerKey(expectedAnswer)
        let exactChoice = uniqueChoices.first { answerKey($0) == expectedKey }
        if exactChoice == nil, uniqueChoices.contains(MultipleChoiceAnswerNormalizer.text(for: expectedAnswer)) {
            return nil
        }
        let matchedChoice = exactChoice ?? indexedChoice ?? uniqueChoices.first { choice in
            let choiceKey = answerKey(choice)
            return choiceKey == expectedKey || (choice.count >= 12 && expectedKey.range(of: choiceKey) != nil)
        }

        guard let matchedChoice else { return nil }

        let explanationChoice = MultipleChoiceAnswerNormalizer.choiceMentionedAsCorrect(
            in: explanation,
            choices: uniqueChoices,
            collapsingWhitespaceForPhraseMatching: true
        )
        let expectedChoice = explanationChoice ?? matchedChoice
        let finalExpectedKey = answerKey(expectedChoice)
        let distractors = uniqueChoices.filter { answerKey($0) != finalExpectedKey }
        guard distractors.count == 3 else { return nil }

        let finalChoices = [expectedChoice] + Array(distractors.prefix(3))
        guard hasUniqueChoices(finalChoices) else { return nil }

        return (expectedAnswer: expectedChoice, choices: finalChoices.shuffled())
    }

    private static func hasUniqueChoices(_ choices: [String]) -> Bool {
        MultipleChoiceAnswerNormalizer.hasUnambiguousChoices(choices)
    }

    private static func answerKey(_ text: String) -> Data {
        MultipleChoiceAnswerNormalizer.key(for: text)
    }

    private static func choiceUniquenessKey(_ text: String) -> Data {
        MultipleChoiceAnswerNormalizer.key(for: text)
    }

    private static func genericProseKey(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func exactQuestionStemKey(_ prompt: String) -> Data {
        let text = prompt.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{000B}\u{000C}"))
        return Data(text.utf8)
    }
}
