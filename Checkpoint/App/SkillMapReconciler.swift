import Foundation

@MainActor
struct SkillMapReconciler {
    static func normalizedSkillMap(_ skillMap: GoalSkillMap) -> GoalSkillMap? {
        guard let names = SkillMapTopic.validatedNames(
            skillMap.topics.map(\.name),
            allowedCount: 3...6
        ),
        Set(skillMap.topics.map(\.id)).count == skillMap.topics.count else {
            return nil
        }

        var normalizedMap = skillMap
        normalizedMap.version = max(1, skillMap.version)
        normalizedMap.topics = zip(skillMap.topics, names).map { pair in
            let (topic, name) = pair
            var normalizedTopic = topic
            normalizedTopic.name = name
            if normalizedTopic.objectives.isEmpty {
                normalizedTopic.objectives = [defaultObjective(for: topic.id, name: name)]
            }
            return normalizedTopic
        }
        return normalizedMap
    }

    static func defaultObjective(
        for skillID: SkillMapTopic.ID,
        name: String
    ) -> SkillMapObjective {
        SkillMapObjective(id: skillID, name: name)
    }

    static func skillMapTopicWithDefaultObjective(
        id: SkillMapTopic.ID = UUID(),
        name: String
    ) -> SkillMapTopic {
        SkillMapTopic(
            id: id,
            name: name,
            objectives: [defaultObjective(for: id, name: name)]
        )
    }

    static func hasSameGenerationContext(_ lhs: Goal, _ rhs: Goal) -> Bool {
        lhs.title == rhs.title &&
            lhs.category == rhs.category &&
            lhs.currentLevel == rhs.currentLevel &&
            lhs.focusAreas == rhs.focusAreas &&
            lhs.sourceDocuments == rhs.sourceDocuments &&
            lhs.preferredQuestionStyle == rhs.preferredQuestionStyle &&
            lhs.minimumQuestionDifficulty == rhs.minimumQuestionDifficulty &&
            skillMapGenerationSignature(lhs.derivedSkillMap) == skillMapGenerationSignature(rhs.derivedSkillMap)
    }

    private static func skillMapGenerationSignature(_ skillMap: GoalSkillMap?) -> String {
        guard let skillMap else { return "none" }
        return skillMapContentSignature(topics: skillMap.topics)
    }

    static func skillMapContentSignature(topics: [SkillMapTopic]) -> String {
        topics.map { skill in
            let objectives = skill.objectives
                .map { "\($0.id.uuidString):\($0.name)" }
                .sorted()
                .joined(separator: ",")
            return "\(skill.id.uuidString):\(skill.name):\(objectives)"
        }
        .sorted()
        .joined(separator: "|")
    }

    private static func inferredSkillMap(
        for targetGoal: Goal,
        questions: [CheckpointQuestion]
    ) -> GoalSkillMap? {
        inferredSkillMap(
            for: targetGoal,
            rawTopics: questions
                .filter { $0.status != .retired }
                .flatMap { competencyTopics(from: $0.topic) }
        )
    }

    static func inferredSkillMap(
        for targetGoal: Goal,
        rawTopics: [String]
    ) -> GoalSkillMap? {
        let topicNames = skillMapTopicCandidates(
            for: targetGoal,
            rawTopics: rawTopics
        )
        guard topicNames.count >= 3 else { return nil }

        return GoalSkillMap(
            topics: topicNames.prefix(6).map { name in
                skillMapTopicWithDefaultObjective(name: name)
            },
            status: .suggested,
            provenance: .questionTopics
        )
    }

    static func skillMapTopicCandidates(
        for targetGoal: Goal,
        rawTopics: [String]
    ) -> [String] {
        let context = GoalQuestionContext(goal: targetGoal)
        let broadKeys = Set([
            competencyTopicKey(targetGoal.title),
            competencyTopicKey(context.learningTarget),
            competencyTopicKey("General progress")
        ])
        let genericKeys: Set<String> = [
            "general",
            "overview",
            "basics",
            "fundamentals",
            "introduction",
            "practice",
            "review"
        ]
        return uniqueCompetencyTopics(rawTopics.flatMap(competencyTopics))
            .filter { topic in
                let key = competencyTopicKey(topic)
                return !topic.isEmpty &&
                    topic.count <= 48 &&
                    !broadKeys.contains(key) &&
                    !genericKeys.contains(key)
            }
    }

    static func reviewedSkillMapTopics(
        _ proposedTopics: [SkillMapTopic],
        preserving existingMap: GoalSkillMap
    ) -> [SkillMapTopic] {
        guard let names = SkillMapTopic.validatedNames(
            proposedTopics.map(\.name),
            allowedCount: 3...6
        ),
        Set(proposedTopics.map(\.id)).count == proposedTopics.count else {
            return []
        }

        let acceptedNameKeys = Set(names.map(competencyTopicKey))
        return zip(proposedTopics, names).map { pair in
            let (proposedTopic, name) = pair
            let key = competencyTopicKey(name)
            let existingTopic = existingMap.topics.first(where: { $0.id == proposedTopic.id })
            var aliases = existingTopic?.aliases ?? proposedTopic.aliases
            if let existingTopic,
               competencyTopicKey(existingTopic.name) != key {
                aliases.append(existingTopic.name)
            }
            aliases = uniqueCompetencyTopics(aliases)
                .filter { alias in
                    let aliasKey = competencyTopicKey(alias)
                    return aliasKey != key && !acceptedNameKeys.contains(aliasKey)
                }
            let objectives: [SkillMapObjective]
            if !proposedTopic.objectives.isEmpty {
                objectives = proposedTopic.objectives
            } else if let existingTopic, !existingTopic.objectives.isEmpty {
                objectives = existingTopic.objectives
            } else {
                objectives = [defaultObjective(for: proposedTopic.id, name: name)]
            }

            return SkillMapTopic(
                id: proposedTopic.id,
                name: name,
                aliases: aliases,
                objectives: objectives
            )
        }
    }

    static func skillMapTopic(
        matching rawTopic: String,
        in skillMap: GoalSkillMap
    ) -> SkillMapTopic? {
        let rawKeys = Set(competencyTopics(from: rawTopic).map(competencyTopicKey))
        if let exactNameMatch = skillMap.topics.first(where: {
            rawKeys.contains(competencyTopicKey($0.name))
        }) {
            return exactNameMatch
        }

        return skillMap.topics.first { skill in
            !rawKeys.isDisjoint(with: Set(skill.aliases.map(competencyTopicKey)))
        }
    }

    static func skillMapTopic(
        matching question: CheckpointQuestion,
        in skillMap: GoalSkillMap
    ) -> SkillMapTopic? {
        if let skillID = question.skillID {
            return skillMap.topics.first { $0.id == skillID }
        }

        return skillMapTopic(matching: question.topic, in: skillMap)
    }

    static func canonicalizedQuestion(
        _ question: CheckpointQuestion,
        for skill: SkillMapTopic
    ) -> CheckpointQuestion {
        var canonicalQuestion = question
        canonicalQuestion.skillID = skill.id
        canonicalQuestion.topic = skill.name

        let matchedObjective = question.objectiveID.flatMap { objectiveID in
            skill.objectives.first { $0.id == objectiveID }
        } ?? question.objective.flatMap { rawObjective in
            let objectiveKey = competencyTopicKey(rawObjective)
            return skill.objectives.first {
                competencyTopicKey($0.name) == objectiveKey
            }
        } ?? (skill.objectives.count == 1 ? skill.objectives.first : nil)

        canonicalQuestion.objectiveID = matchedObjective?.id
        canonicalQuestion.objective = matchedObjective?.name
        return canonicalQuestion
    }

    static func canonicalizedQuestions(
        _ candidateQuestions: [CheckpointQuestion],
        for targetGoal: Goal
    ) -> [CheckpointQuestion] {
        guard let skillMap = targetGoal.derivedSkillMap else {
            return candidateQuestions
        }

        return candidateQuestions.compactMap { question in
            guard let skill = skillMapTopic(matching: question, in: skillMap) else {
                return nil
            }
            return canonicalizedQuestion(question, for: skill)
        }
    }

    static func initialCompetencies(for goal: Goal, questions: [CheckpointQuestion]) -> [TopicCompetency] {
        let questionTopics = questions
            .filter { $0.status != .retired }
            .flatMap { competencyTopics(from: $0.topic) }
        let context = GoalQuestionContext(goal: goal)

        if let skillMap = goal.derivedSkillMap {
            return skillMap.topics.map { skill in
                .initial(
                    topic: skill.name,
                    estimatedLevel: estimatedStartingLevel(for: skill.name, goal: goal),
                    goalID: goal.id,
                    skillID: skill.id
                )
            }
        }

        guard !context.needsGeneratedSkillMap else { return [] }
        let contextTopics = context.contentTopics.flatMap(competencyTopics)
        let seedTopics = contextTopics + questionTopics
        let topics = uniqueCompetencyTopics(seedTopics).sorted()

        return topics.map { topic in
            .initial(topic: topic, estimatedLevel: estimatedStartingLevel(for: topic, goal: goal), goalID: goal.id)
        }
    }

    static func reconciledCompetencies(
        existing: [TopicCompetency],
        goal: Goal,
        questions: [CheckpointQuestion]
    ) -> [TopicCompetency] {
        let newCompetencies = initialCompetencies(for: goal, questions: questions)
        let matches: (TopicCompetency, TopicCompetency) -> Bool = { candidate, competency in
            if let skillID = competency.skillID {
                if let candidateSkillID = candidate.skillID {
                    return candidateSkillID == skillID
                }

                guard let skillMap = goal.derivedSkillMap,
                      let skill = skillMap.topics.first(where: { $0.id == skillID }) else {
                    return false
                }
                return Self.skillMapTopic(matching: candidate.topic, in: skillMap)?.id == skill.id
            }

            return Self.competencyTopicKey(candidate.topic) == Self.competencyTopicKey(competency.topic)
        }

        let reconciled = newCompetencies.map { competency in
            let matchingCompetencies = existing.filter { matches($0, competency) }

            guard var existingCompetency = matchingCompetencies.first else {
                return competency
            }

            for duplicate in matchingCompetencies.dropFirst() {
                existingCompetency = mergedCompetency(existingCompetency, with: duplicate)
            }

            existingCompetency.topic = competency.topic
            existingCompetency.goalID = competency.goalID
            existingCompetency.skillID = competency.skillID
            return existingCompetency
        }

        let unmatchedPracticedCompetencies = existing.filter { candidate in
            candidate.attempts > 0 &&
                (goal.derivedSkillMap == nil || candidate.skillID == nil) &&
                !newCompetencies.contains(where: { matches(candidate, $0) })
        }
        return reconciled + unmatchedPracticedCompetencies
    }

    static func mergedCompetenciesForDisplay(_ competencies: [TopicCompetency]) -> [TopicCompetency] {
        var mergedByTopic: [String: TopicCompetency] = [:]

        for competency in competencies {
            let topics = competencyTopics(from: competency.topic)
            for topic in topics {
                let key = competencyTopicKey(topic)
                var normalizedCompetency = competency
                normalizedCompetency.topic = topic

                if let existing = mergedByTopic[key] {
                    mergedByTopic[key] = mergedCompetency(existing, with: normalizedCompetency)
                } else {
                    mergedByTopic[key] = normalizedCompetency
                }
            }
        }

        return Array(mergedByTopic.values)
    }

    static func mergedCompetency(_ lhs: TopicCompetency, with rhs: TopicCompetency) -> TopicCompetency {
        var merged = lhs
        let totalAttempts = lhs.attempts + rhs.attempts
        if totalAttempts > 0 {
            let weightedLevel = (lhs.estimatedLevel * Double(lhs.attempts)) + (rhs.estimatedLevel * Double(rhs.attempts))
            merged.estimatedLevel = weightedLevel / Double(totalAttempts)
        } else {
            merged.estimatedLevel = max(lhs.estimatedLevel, rhs.estimatedLevel)
        }
        merged.attempts = totalAttempts
        merged.correct = lhs.correct + rhs.correct
        merged.partial = lhs.partial + rhs.partial
        merged.incorrect = lhs.incorrect + rhs.incorrect
        merged.currentStreak = max(lhs.currentStreak, rhs.currentStreak)

        switch (lhs.lastPracticedAt, rhs.lastPracticedAt) {
        case let (lhsDate?, rhsDate?) where rhsDate > lhsDate:
            merged.lastPracticedAt = rhsDate
            merged.lastResult = rhs.lastResult
        case (nil, let rhsDate?):
            merged.lastPracticedAt = rhsDate
            merged.lastResult = rhs.lastResult
        default:
            break
        }

        return merged
    }

    static func competencyTopics(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n")
        let topics = text
            .components(separatedBy: separators)
            .map(normalizedCompetencyTopic)
            .filter { !$0.isEmpty }

        let fallback = normalizedCompetencyTopic(text)
        return uniqueCompetencyTopics(topics.isEmpty ? [fallback] : topics)
    }

    private static func uniqueCompetencyTopics(_ topics: [String]) -> [String] {
        var seenKeys = Set<String>()
        var uniqueTopics: [String] = []

        for topic in topics {
            let normalizedTopic = normalizedCompetencyTopic(topic)
            let key = competencyTopicKey(normalizedTopic)
            guard !normalizedTopic.isEmpty, !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            uniqueTopics.append(normalizedTopic)
        }

        return uniqueTopics
    }

    private static func normalizedCompetencyTopic(_ topic: String) -> String {
        topic
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .:-"))
    }

    static func competencyTopicKey(_ topic: String) -> String {
        normalizedCompetencyTopic(topic).lowercased()
    }

    static func questionTopicKey(_ topic: String) -> String {
        competencyTopics(from: topic)
            .map(competencyTopicKey)
            .sorted()
            .joined(separator: "+")
    }

    static func questionKey(_ question: CheckpointQuestion) -> String {
        "\(questionTopicKey(question.topic))::\(question.prompt.lowercased())"
    }

    private static func estimatedStartingLevel(for topic: String, goal: Goal) -> Double {
        let levelText = goal.currentLevel.lowercased()
        var estimate = max(1.5, Double(goal.minimumQuestionDifficulty) - 0.5)

        if containsAny(["expert", "advanced", "strong", "very comfortable"], in: levelText) {
            estimate = 3.7
        } else if containsAny(["intermediate", "comfortable", "familiar", "decent"], in: levelText) {
            estimate = 2.5
        } else if containsAny(["beginner", "basic", "new", "starting", "weak"], in: levelText) {
            estimate = 1.4
        }

        for segment in topicSegments(from: levelText) where containsTopic(topic, in: segment) {
            if containsAny(["shaky", "weak", "confused", "struggle", "bad at", "not good"], in: segment) {
                estimate -= 0.45
            }

            if containsAny(["comfortable", "strong", "good at", "confident", "solid"], in: segment) {
                estimate += 0.35
            }
        }

        return min(5.0, max(1.0, estimate))
    }

    private static func containsTopic(_ topic: String, in text: String) -> Bool {
        let normalizedTopic = normalizedSignal(topic)
        let normalizedText = normalizedSignal(text)
        return !normalizedTopic.isEmpty && normalizedText.contains(normalizedTopic)
    }

    private static func containsAny(_ needles: [String], in text: String) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func normalizedSignal(_ text: String) -> String {
        text
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func topicSegments(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ".,;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
