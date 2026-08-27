import Foundation

@MainActor
struct CheckpointQuestionSelector {
    private let questions: [CheckpointQuestion]
    private let goalProfiles: [Goal]
    private let currentGoal: Goal?
    private let competencies: [TopicCompetency]
    private let activeQuestionDifficulty: Int
    private let maximumExactQuestionAskCount: Int

    init(
        questions: [CheckpointQuestion],
        goalProfiles: [Goal],
        currentGoal: Goal?,
        competencies: [TopicCompetency],
        activeQuestionDifficulty: Int,
        maximumExactQuestionAskCount: Int
    ) {
        self.questions = questions
        self.goalProfiles = goalProfiles
        self.currentGoal = currentGoal
        self.competencies = competencies
        self.activeQuestionDifficulty = activeQuestionDifficulty
        self.maximumExactQuestionAskCount = maximumExactQuestionAskCount
    }

    private var activeQuestions: [CheckpointQuestion] {
        guard let goalID = currentGoal?.id else { return [] }
        return questions.filter { $0.goalID == goalID }
    }

    private var activeCompetencies: [TopicCompetency] {
        guard let goalID = currentGoal?.id else { return [] }
        return competencies.filter { $0.goalID == goalID || $0.goalID == nil }
    }

    private var visibleActiveCompetencies: [TopicCompetency] {
        SkillMapReconciler.mergedCompetenciesForDisplay(activeCompetencies)
    }

    private var activeDerivedSkillMap: GoalSkillMap? {
        currentGoal?.derivedSkillMap
    }

    private func storedGoalProfile(withID goalID: Goal.ID) -> Goal? {
        goalProfiles.first(where: { $0.id == goalID }) ?? (currentGoal?.id == goalID ? currentGoal : nil)
    }

    func nextQuestion() -> CheckpointQuestion? {
        nextQuestion(excluding: [], avoidingSimilarityTo: [])
    }

    func nextQuestions(limit: Int, allowsEarlyCorrectReuse: Bool = false) -> [CheckpointQuestion] {
        let maximumSessionQuestionCount = max(
            UnlockPolicy.maximumQuestionsPerSession,
            StopBlockingPolicy.questionsPerSession
        )
        let targetCount = min(maximumSessionQuestionCount, max(1, limit))
        var selectedQuestions: [CheckpointQuestion] = []
        var excludedQuestionIDs = Set<CheckpointQuestion.ID>()

        while selectedQuestions.count < targetCount,
              let question = nextQuestion(
                excluding: excludedQuestionIDs,
                avoidingSimilarityTo: selectedQuestions,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse,
                prefersMasteredMaintenance: selectedQuestions.count == targetCount - 1,
                forcesSkillBreadth: shouldForceSkillBreadth(
                    for: selectedQuestions,
                    targetCount: targetCount
                )
              ) {
            selectedQuestions.append(question)
            excludedQuestionIDs.insert(question.id)
        }

        return selectedQuestions
    }

    private func nextQuestion(
        excluding excludedQuestionIDs: Set<CheckpointQuestion.ID>,
        avoidingSimilarityTo selectedQuestions: [CheckpointQuestion],
        allowsEarlyCorrectReuse: Bool = false,
        prefersMasteredMaintenance: Bool = false,
        forcesSkillBreadth: Bool = false
    ) -> CheckpointQuestion? {
        let availableQuestions = activeQuestions.filter { !excludedQuestionIDs.contains($0.id) }
        let preferredQuestions = availableQuestions.filter(meetsDifficultyFloor)
        if prefersMasteredMaintenance,
           let maintenanceQuestion = masteredMaintenanceQuestion(
               from: preferredQuestions,
               avoidingSimilarityTo: selectedQuestions
           ) ?? masteredMaintenanceQuestion(
               from: availableQuestions,
               avoidingSimilarityTo: selectedQuestions
           ) {
            return maintenanceQuestion
        }
        if forcesSkillBreadth,
           let breadthQuestion = skillBreadthQuestion(
               from: preferredQuestions,
               avoidingSimilarityTo: selectedQuestions
           ) ?? skillBreadthQuestion(
               from: availableQuestions,
               avoidingSimilarityTo: selectedQuestions
           ) {
            return breadthQuestion
        }
        return prioritizedNonCorrectQuestion(
            from: preferredQuestions,
            avoidingSimilarityTo: selectedQuestions
        )
            ?? prioritizedNonCorrectQuestion(
                from: availableQuestions,
                avoidingSimilarityTo: selectedQuestions
            )
            ?? prioritizedCorrectQuestion(
                from: preferredQuestions,
                avoidingSimilarityTo: selectedQuestions,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
            )
            ?? prioritizedCorrectQuestion(
                from: availableQuestions,
                avoidingSimilarityTo: selectedQuestions,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
            )
    }

    private func prioritizedNonCorrectQuestion(
        from availableQuestions: [CheckpointQuestion],
        avoidingSimilarityTo selectedQuestions: [CheckpointQuestion]
    ) -> CheckpointQuestion? {
        let now = Date()
        let selectableQuestions = availableQuestions
            .filter(isSelectableQuestion)
            .filter { $0.status != .correct }

        if let missed = preferredSessionQuestion(
            from: selectableQuestions
                .filter({ $0.status == .incorrect && ($0.nextReviewAt ?? .distantPast) <= now })
                .sorted(by: sortByReviewPriority),
            avoidingSimilarityTo: selectedQuestions
        ) {
            return missed
        }

        if let due = preferredSessionQuestion(
            from: selectableQuestions
                .filter({ ($0.nextReviewAt ?? .distantFuture) <= now })
                .sorted(by: sortByReviewPriority),
            avoidingSimilarityTo: selectedQuestions
        ) {
            return due
        }

        if let weakAreaQuestion = preferredSessionQuestion(
            from: selectableQuestions
                .filter { $0.status == .new }
                .sorted(by: sortByAdaptivePriority),
            avoidingSimilarityTo: selectedQuestions,
            preferringNewTopic: true
        ) {
            return weakAreaQuestion
        }

        if let reviewQuestion = preferredSessionQuestion(
            from: selectableQuestions
                .filter({ $0.status != .correct })
                .sorted(by: sortByReviewPriority),
            avoidingSimilarityTo: selectedQuestions
        ) {
            return reviewQuestion
        }

        return nil
    }

    private func prioritizedCorrectQuestion(
        from availableQuestions: [CheckpointQuestion],
        avoidingSimilarityTo selectedQuestions: [CheckpointQuestion],
        allowsEarlyCorrectReuse: Bool = false
    ) -> CheckpointQuestion? {
        let now = Date()
        let selectableQuestions = availableQuestions
            .filter(isSelectableQuestion)
            .filter { $0.status == .correct }

        let reusableCorrectQuestions = preferredSessionQuestion(
            from: selectableQuestions
                .filter { canReuseCorrectQuestion($0, now: now) }
                .sorted(by: sortByCorrectReusePriority),
            avoidingSimilarityTo: selectedQuestions
        )

        if let reusableCorrectQuestions {
            return reusableCorrectQuestions
        }

        guard allowsEarlyCorrectReuse else { return nil }

        return preferredSessionQuestion(
            from: selectableQuestions.sorted(by: sortByCorrectReusePriority),
            avoidingSimilarityTo: selectedQuestions
        )
    }

    private func preferredSessionQuestion(
        from orderedQuestions: [CheckpointQuestion],
        avoidingSimilarityTo selectedQuestions: [CheckpointQuestion],
        preferringNewTopic: Bool = false
    ) -> CheckpointQuestion? {
        guard !orderedQuestions.isEmpty else { return nil }

        let selectedSkillKeys = Set(selectedQuestions.map(questionSkillKey))
        let isNewSkill: (CheckpointQuestion) -> Bool = { question in
            !selectedSkillKeys.contains(self.questionSkillKey(question))
        }
        if activeDerivedSkillMap == nil,
           preferringNewTopic,
           let question = orderedQuestions.first(where: isNewSkill) {
            return question
        }

        return orderedQuestions.first
    }

    private func shouldForceSkillBreadth(
        for selectedQuestions: [CheckpointQuestion],
        targetCount: Int
    ) -> Bool {
        guard let skillMap = activeDerivedSkillMap,
              selectedQuestions.count < targetCount,
              !selectedQuestions.isEmpty else {
            return false
        }

        let distinctSkillCount = Set(selectedQuestions.map(questionSkillKey)).count
        let breadthFloor = min(3, skillMap.topics.count, targetCount)
        guard distinctSkillCount < breadthFloor else { return false }

        if selectedQuestions.count == 1 {
            return distinctSkillCount < min(2, breadthFloor)
        }
        return selectedQuestions.count >= 3
    }

    private func skillBreadthQuestion(
        from availableQuestions: [CheckpointQuestion],
        avoidingSimilarityTo selectedQuestions: [CheckpointQuestion]
    ) -> CheckpointQuestion? {
        let selectedSkillKeys = Set(selectedQuestions.map(questionSkillKey))
        let breadthCandidates = availableQuestions.filter {
            !selectedSkillKeys.contains(questionSkillKey($0))
        }
        return prioritizedNonCorrectQuestion(
            from: breadthCandidates,
            avoidingSimilarityTo: selectedQuestions
        )
    }

    private func masteredMaintenanceQuestion(
        from availableQuestions: [CheckpointQuestion],
        avoidingSimilarityTo selectedQuestions: [CheckpointQuestion]
    ) -> CheckpointQuestion? {
        guard activeDerivedSkillMap != nil else { return nil }
        let now = Date()
        let selectedSkillKeys = Set(selectedQuestions.map(questionSkillKey))
        return availableQuestions
            .filter(isSelectableQuestion)
            .filter { question in
                guard question.status == .correct,
                      canReuseCorrectQuestion(question, now: now),
                      !selectedSkillKeys.contains(questionSkillKey(question)) else {
                    return false
                }
                let competency = competency(for: question)
                return competency.attempts >= 3 && competency.masteryPercent >= 75
            }
            .sorted(by: sortByCorrectReusePriority)
            .first
    }

    func sortByReviewPriority(_ lhs: CheckpointQuestion, _ rhs: CheckpointQuestion) -> Bool {
        let lhsCompetency = competency(for: lhs)
        let rhsCompetency = competency(for: rhs)
        if lhsCompetency.masteryPercent != rhsCompetency.masteryPercent {
            return lhsCompetency.masteryPercent < rhsCompetency.masteryPercent
        }
        if lhsCompetency.attempts != rhsCompetency.attempts {
            return lhsCompetency.attempts < rhsCompetency.attempts
        }
        if lhs.difficulty != rhs.difficulty {
            return lhs.difficulty < rhs.difficulty
        }
        return (lhs.nextReviewAt ?? .distantPast) < (rhs.nextReviewAt ?? .distantPast)
    }

    private func sortByCorrectReusePriority(_ lhs: CheckpointQuestion, _ rhs: CheckpointQuestion) -> Bool {
        let lhsReviewDate = lhs.nextReviewAt ?? .distantPast
        let rhsReviewDate = rhs.nextReviewAt ?? .distantPast

        if lhsReviewDate != rhsReviewDate {
            return lhsReviewDate < rhsReviewDate
        }

        let lhsLastAskedAt = lhs.lastAskedAt ?? .distantPast
        let rhsLastAskedAt = rhs.lastAskedAt ?? .distantPast

        if lhsLastAskedAt != rhsLastAskedAt {
            return lhsLastAskedAt < rhsLastAskedAt
        }

        return lhs.timesCorrect < rhs.timesCorrect
    }

    private func canReuseCorrectQuestion(_ question: CheckpointQuestion, now: Date) -> Bool {
        guard question.status == .correct else { return true }
        guard let nextReviewAt = question.nextReviewAt else { return true }
        return nextReviewAt <= now
    }

    func isReadyQuestionBankCandidate(
        _ question: CheckpointQuestion,
        now: Date,
        allowsEarlyCorrectReuse: Bool = false
    ) -> Bool {
        guard isSelectableQuestion(question) else { return false }

        switch question.status {
        case .new, .due, .skipped:
            return true
        case .incorrect:
            return (question.nextReviewAt ?? .distantPast) <= now
        case .correct:
            return allowsEarlyCorrectReuse || canReuseCorrectQuestion(question, now: now)
        case .retired:
            return false
        }
    }

    func isSelectableQuestion(_ question: CheckpointQuestion) -> Bool {
        guard question.status != .retired,
              question.timesAsked < maximumExactQuestionAskCount else {
            return false
        }

        guard let skillMap = storedGoalProfile(withID: question.goalID)?.derivedSkillMap else {
            return true
        }
        return SkillMapReconciler.skillMapTopic(matching: question, in: skillMap) != nil
    }

    static func correctAnswerReviewDelayDays(for correctStreak: Int) -> Int {
        switch correctStreak {
        case ...1:
            return 3
        case 2:
            return 7
        default:
            return 14
        }
    }

    private func sortByAdaptivePriority(_ lhs: CheckpointQuestion, _ rhs: CheckpointQuestion) -> Bool {
        let lhsCompetency = competency(for: lhs)
        let rhsCompetency = competency(for: rhs)

        if lhsCompetency.attempts != rhsCompetency.attempts {
            return lhsCompetency.attempts < rhsCompetency.attempts
        }

        if lhsCompetency.masteryPercent != rhsCompetency.masteryPercent {
            return lhsCompetency.masteryPercent < rhsCompetency.masteryPercent
        }

        let lhsTargetDistance = abs(Double(lhs.difficulty) - targetDifficulty(for: lhsCompetency))
        let rhsTargetDistance = abs(Double(rhs.difficulty) - targetDifficulty(for: rhsCompetency))

        if lhsTargetDistance != rhsTargetDistance {
            return lhsTargetDistance < rhsTargetDistance
        }

        return lhs.difficulty < rhs.difficulty
    }

    func meetsDifficultyFloor(_ question: CheckpointQuestion) -> Bool {
        isSelectableQuestion(question) && question.difficulty >= activeQuestionDifficulty
    }

    private func competency(for topic: String) -> TopicCompetency {
        let topicKeys = Set(
            SkillMapReconciler.competencyTopics(from: topic)
                .map(SkillMapReconciler.competencyTopicKey)
        )
        let matchingCompetencies = visibleActiveCompetencies.filter { topicKeys.contains(SkillMapReconciler.competencyTopicKey($0.topic)) }

        return matchingCompetencies.min {
            if $0.masteryPercent == $1.masteryPercent {
                return $0.topic < $1.topic
            }
            return $0.masteryPercent < $1.masteryPercent
        } ?? .initial(topic: SkillMapReconciler.competencyTopics(from: topic).first ?? topic, goalID: currentGoal?.id)
    }

    private func competency(for question: CheckpointQuestion) -> TopicCompetency {
        if let skillMap = storedGoalProfile(withID: question.goalID)?.derivedSkillMap,
           let skill = SkillMapReconciler.skillMapTopic(matching: question, in: skillMap) {
            return competencies.first {
                ($0.goalID == question.goalID || ($0.goalID == nil && currentGoal?.id == question.goalID)) &&
                    $0.skillID == skill.id
            } ?? .initial(topic: skill.name, goalID: question.goalID, skillID: skill.id)
        }

        return competency(for: question.topic)
    }

    private func questionSkillKey(_ question: CheckpointQuestion) -> String {
        if let skillMap = storedGoalProfile(withID: question.goalID)?.derivedSkillMap,
           let skill = SkillMapReconciler.skillMapTopic(matching: question, in: skillMap) {
            return skill.id.uuidString
        }

        return SkillMapReconciler.questionTopicKey(question.topic)
    }

    private func targetDifficulty(for competency: TopicCompetency) -> Double {
        min(5.0, max(1.0, competency.estimatedLevel + 0.5))
    }
}
