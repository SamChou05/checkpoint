import Foundation

enum QuestionBatchSanitizer {
    /// Exact stem identities used to keep one question from appearing twice even
    /// when a provider changes casing, terminal punctuation, or adds a wrapper.
    /// This intentionally does not use fuzzy similarity: closely related questions
    /// that test a different angle remain valid.
    static func questionStemKeys(_ prompt: String) -> Set<String> {
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
        for byte in key.utf8 {
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
            sanitizedQuestion.prompt = QuestionText.clipped(
                question.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                maxLength: 360
            )
            let expectedAnswer = QuestionText.clipped(
                question.expectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines),
                maxLength: 280
            )
            let choiceResolution: (expectedAnswer: String, choices: [String])?
            if question.verificationVersion == 1 {
                // A reviewed answer is the exact choice text. Legacy label/cue
                // heuristics must never reinterpret numbers inside that text.
                choiceResolution = question.choices.count == 4
                    && hasUniqueChoices(question.choices)
                    && question.choices.contains(question.expectedAnswer)
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
               choiceResolution.expectedAnswer != question.expectedAnswer { continue }
            sanitizedQuestion.choices = choiceResolution.choices
            sanitizedQuestion.choiceExplanations = question.choiceExplanations.filter {
                sanitizedQuestion.choices.contains($0.key) && (12...280).contains($0.value.count)
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

    private static func questionCoverageKeys(_ question: CheckpointQuestion) -> Set<String> {
        var keys = questionCoverageKeys(
            prompt: question.prompt,
            expectedAnswer: question.expectedAnswer,
            topic: question.topic
        )

        let choiceSetKey = question.choices
            .map(choiceUniquenessKey)
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "|")
        if question.choices.count == 4, !choiceSetKey.isEmpty {
            keys.insert("choice-set:\(choiceSetKey)")
        }

        return keys
    }

    private static func questionCoverageKeys(
        prompt: String,
        expectedAnswer: String,
        topic: String
    ) -> Set<String> {
        var keys: Set<String> = []
        let topicKey = choiceUniquenessKey(topic)
        let answerKey = choiceUniquenessKey(expectedAnswer)

        if topicKey.count >= 3,
           answerKey.count >= 16 {
            keys.insert("topic-answer:\(topicKey):\(answerKey)")
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
            && !question.choices.contains { isBareAnswerLabel($0) }
            && !isBareAnswerLabel(question.expectedAnswer)
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
        let expectedKey = answerKey(question.expectedAnswer)
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
            let key = answerKey(choice)
            if genericDistractorSignals.contains(where: key.contains) {
                count += 1
            }
        }

        return genericDistractorCount >= 2
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

    private static func promptKeys(_ prompt: String) -> Set<String> {
        questionStemKeys(prompt)
    }

    private static func isBareAnswerLabel(_ text: String) -> Bool {
        var normalized = QuestionText.collapsedWhitespace(text)
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in ["answer", "choice", "option"] where normalized.hasPrefix(prefix) {
            normalized.removeFirst(prefix.count)
            normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n:-."))
            break
        }

        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "[]().: "))
        return ["a", "b", "c", "d"].contains(normalized)
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
        let clippedChoices = choices
            .map { QuestionText.clipped(QuestionText.collapsedWhitespace($0), maxLength: 140) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        var uniqueChoices: [String] = []

        for choice in clippedChoices {
            let key = choiceUniquenessKey(choice)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            uniqueChoices.append(choice)
        }

        guard uniqueChoices.count == 4 else { return nil }

        let indexedChoice = MultipleChoiceAnswerNormalizer.choiceIndex(from: expectedAnswer).flatMap { index in
            uniqueChoices.indices.contains(index) ? uniqueChoices[index] : nil
        }
        let expectedKey = answerKey(expectedAnswer)
        let matchedChoice = indexedChoice ?? uniqueChoices.first { choice in
            let choiceKey = answerKey(choice)
            return choiceKey == expectedKey || (choiceKey.count >= 12 && expectedKey.contains(choiceKey))
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
        var seen: Set<String> = []

        for choice in choices {
            let key = choiceUniquenessKey(choice)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
        }

        return true
    }

    private static func answerKey(_ text: String) -> String {
        MultipleChoiceAnswerNormalizer.key(for: text)
    }

    private static func choiceUniquenessKey(_ text: String) -> String {
        let semanticKey = semanticChoiceKey(text)
        return semanticKey.isEmpty ? answerKey(text) : semanticKey
    }

    private static func semanticChoiceKey(_ text: String) -> String {
        var normalized = text
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        normalized = MultipleChoiceAnswerNormalizer.strippingAnswerPrefix(from: normalized)
        normalized = MultipleChoiceAnswerNormalizer.strippingChoiceLabel(from: normalized)

        let tokens = normalized
            .split { !$0.isLetter && !$0.isNumber }
            .compactMap { semanticChoiceToken(String($0)) }

        return tokens.joined(separator: "")
    }

    private static func semanticChoiceToken(_ token: String) -> String? {
        let normalized = singularizedSemanticToken(token)

        let stopWords: Set<String> = [
            "a",
            "an",
            "as",
            "by",
            "choice",
            "for",
            "it",
            "of",
            "option",
            "that",
            "the",
            "this",
            "those",
            "to",
            "which",
            "with"
        ]

        guard !stopWords.contains(normalized) else { return nil }
        return normalized
    }

    private static func singularizedSemanticToken(_ token: String) -> String {
        guard token.count > 4 else { return token }

        if token.hasSuffix("ies") {
            return String(token.dropLast(3)) + "y"
        }

        if token.hasSuffix("s"), !token.hasSuffix("ss") {
            return String(token.dropLast())
        }

        return token
    }

    private static func canonicalPrompt(_ prompt: String) -> String {
        QuestionText.collapsedWhitespace(prompt)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .trimmingCharacters(
                in: .whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: ".?!:;\"'“”‘’")
                )
            )
    }

    private static func exactQuestionStemKey(_ prompt: String) -> String {
        var normalized = QuestionText.collapsedWhitespace(
            prompt.precomposedStringWithCanonicalMapping
        )
        .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .lowercased()
        normalized = normalized.precomposedStringWithCanonicalMapping

        let presentationPrefixes = [
            #"^(?:question|item)\s+\d+\s*[:.)-]\s*"#,
            #"^(?:choose|select|identify|pick)\s+(?:the\s+)?(?:correct|best)\s+(?:answer|choice|option)(?:\s+(?:to|for)\s+(?:this\s+)?(?:question|item|example))?\s*[:-]\s*"#
        ]
        for pattern in presentationPrefixes {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        normalized = normalized.replacingOccurrences(
            of: #"\s+([,.;:?!])"#,
            with: "$1",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\s*(<=|>=|!=|==|[+\-−×÷=*/^%±∓<>=≤≥≠⋅·])\s*"#,
            with: "$1",
            options: .regularExpression
        )
        while let finalCharacter = normalized.last,
              " .?!".contains(finalCharacter) {
            normalized.removeLast()
        }
        return normalized
    }
}
