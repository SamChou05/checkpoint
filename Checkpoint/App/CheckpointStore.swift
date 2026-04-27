import Foundation
import Observation

@MainActor
@Observable
final class CheckpointStore {
    var goal: Goal?
    var questions: [CheckpointQuestion] = []
    var attempts: [CheckpointAttempt] = []
    var competencies: [TopicCompetency] = []
    var questionReports: [QuestionQualityReport] = []
    var unlockPolicy: UnlockPolicy = .default
    var questionBatchState: QuestionBatchState = .idle
    var aiProviderPreference: AIProviderKind = .automatic
    var lastQuestionProvider: AIProviderKind = .localTemplates
    var backendEndpoint = ""
    var lastAIErrorMessage: String?
    var unlockSession: UnlockSession?
    var emergencyPassesRemaining = 1
    var isOnboardingPresented = false

    @ObservationIgnored private let questionEngine: HybridQuestionEngine
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let snapshotKey = "checkpoint.snapshot.v1"

    init(
        questionEngine: HybridQuestionEngine = HybridQuestionEngine(),
        defaults: UserDefaults = .standard
    ) {
        self.questionEngine = questionEngine
        self.defaults = defaults
        load()
        isOnboardingPresented = goal == nil
        publishShieldContext()
    }

    var activeUnlockMinutesRemaining: Int {
        guard let unlockSession, unlockSession.isActive else { return 0 }
        return max(0, Int(ceil(unlockSession.expiresAt.timeIntervalSinceNow / 60)))
    }

    var completedTodayCount: Int {
        attempts.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    var conversionRateText: String {
        guard !attempts.isEmpty else { return "0%" }
        let successful = attempts.filter { $0.result == .correct || $0.result == .partial }.count
        return "\(Int((Double(successful) / Double(attempts.count)) * 100))%"
    }

    var averageMasteryText: String {
        guard !competencies.isEmpty else { return "0%" }
        let total = competencies.reduce(0) { $0 + $1.masteryPercent }
        return "\(total / competencies.count)%"
    }

    var sortedCompetencies: [TopicCompetency] {
        competencies.sorted {
            if $0.masteryPercent == $1.masteryPercent {
                return $0.topic < $1.topic
            }
            return $0.masteryPercent < $1.masteryPercent
        }
    }

    var reportedQuestionCount: Int {
        questionReports.count
    }

    func createGoal(
        title: String,
        deadline: Date,
        category: GoalCategory,
        currentLevel: String,
        focusAreas: String,
        preferredQuestionStyle: QuestionFormat
    ) async {
        let newGoal = Goal(
            title: title,
            deadline: deadline,
            category: category,
            currentLevel: currentLevel,
            focusAreas: focusAreas,
            preferredQuestionStyle: preferredQuestionStyle
        )

        goal = newGoal
        let batch = await questionEngine.generateQuestionBatch(
            for: generationRequest(goal: newGoal, existingQuestions: [], competencies: [], reportedQuestions: []),
            preference: aiProviderPreference
        )

        questions = batch.questions
        lastQuestionProvider = batch.provider
        lastAIErrorMessage = batch.usedFallback ? "Used \(batch.provider.rawValue) because the preferred provider was unavailable." : nil
        competencies = initialCompetencies(for: newGoal, questions: questions)
        questionReports = []
        questionBatchState = .ready
        attempts = []
        unlockSession = nil
        isOnboardingPresented = false
        save()
        publishShieldContext()
    }

    func refreshQuestionBatch() async {
        guard let goal else { return }

        questionBatchState = .generating

        let batch = await questionEngine.generateQuestionBatch(
            for: generationRequest(
                goal: goal,
                existingQuestions: questions,
                competencies: competencies,
                reportedQuestions: questionReports
            ),
            preference: aiProviderPreference
        )
        let generatedQuestions = batch.questions
        let existingKeys = Set(questions.map { questionKey($0) })
        let newQuestions = generatedQuestions.filter { !existingKeys.contains(questionKey($0)) }
        questions.append(contentsOf: newQuestions)
        competencies = mergeCompetencies(existing: competencies, goal: goal, questions: questions)
        lastQuestionProvider = batch.provider
        if newQuestions.isEmpty {
            lastAIErrorMessage = "No new usable questions were added. Try refining the goal or changing providers."
        } else {
            lastAIErrorMessage = batch.usedFallback ? "Used \(batch.provider.rawValue) because the preferred provider was unavailable." : nil
        }
        questionBatchState = .ready
        save()
        publishShieldContext()
    }

    func nextQuestion() -> CheckpointQuestion? {
        let now = Date()

        if let missed = questions
            .filter({ $0.status == .incorrect && ($0.nextReviewAt ?? .distantPast) <= now })
            .sorted(by: sortByReviewPriority)
            .first {
            return missed
        }

        if let due = questions
            .filter({ ($0.nextReviewAt ?? .distantFuture) <= now && $0.status != .retired })
            .sorted(by: sortByReviewPriority)
            .first {
            return due
        }

        let weakAreaQuestion = questions
            .filter { $0.status == .new }
            .sorted(by: sortByAdaptivePriority)
            .first

        if let weakAreaQuestion {
            return weakAreaQuestion
        }

        return questions
            .filter { $0.status == .new }
            .sorted(by: sortByAdaptivePriority)
            .first ?? questions.filter { $0.status != .retired }.randomElement()
    }

    @discardableResult
    func submitAnswer(question: CheckpointQuestion, answer: String, result: AnswerResult) -> Int {
        guard let goal else { return 0 }

        let unlockMinutes = unlockMinutes(for: result)
        let attempt = CheckpointAttempt(
            questionID: question.id,
            goalID: goal.id,
            prompt: question.prompt,
            answer: answer,
            result: result,
            unlockMinutes: unlockMinutes
        )

        attempts.insert(attempt, at: 0)
        updateQuestion(question, result: result)
        updateCompetency(for: question, result: result)

        if unlockMinutes > 0 {
            let now = Date()
            unlockSession = UnlockSession(
                startedAt: now,
                expiresAt: Calendar.current.date(byAdding: .minute, value: unlockMinutes, to: now) ?? now
            )
            SharedAppGroup.publishUnlockExpiration(unlockSession?.expiresAt)
        }

        save()
        publishShieldContext()
        return unlockMinutes
    }

    func useEmergencyPass() {
        guard emergencyPassesRemaining > 0 else { return }
        emergencyPassesRemaining -= 1
        let now = Date()
        unlockSession = UnlockSession(
            startedAt: now,
            expiresAt: Calendar.current.date(byAdding: .minute, value: unlockPolicy.emergencyUnlockMinutes, to: now) ?? now
        )
        SharedAppGroup.publishUnlockExpiration(unlockSession?.expiresAt)
        save()
    }

    func resetDemoData() {
        goal = nil
        questions = []
        attempts = []
        competencies = []
        questionReports = []
        unlockPolicy = .default
        questionBatchState = .idle
        aiProviderPreference = .automatic
        lastQuestionProvider = .localTemplates
        backendEndpoint = ""
        lastAIErrorMessage = nil
        unlockSession = nil
        emergencyPassesRemaining = 1
        isOnboardingPresented = true
        save()
        publishShieldContext()
    }

    func takePendingShieldQuestion() -> CheckpointQuestion? {
        guard SharedAppGroup.consumePendingShieldAttempt() != nil else { return nil }
        return nextQuestion()
    }

    func reportQuestion(_ question: CheckpointQuestion, reason: QuestionReportReason, note: String) {
        guard let goal else { return }

        let report = QuestionQualityReport(
            questionID: question.id,
            goalID: goal.id,
            prompt: question.prompt,
            reason: reason,
            note: note
        )

        questionReports.insert(report, at: 0)

        if let index = questions.firstIndex(where: { $0.id == question.id }) {
            questions[index].status = .retired
        }

        save()
        publishShieldContext()
    }

    func updateUnlockMinutes(_ minutes: Int) {
        unlockPolicy.unlockMinutes = minutes
        save()
    }

    func updatePartialUnlockEnabled(_ isEnabled: Bool) {
        unlockPolicy.unlockOnPartial = isEnabled
        save()
    }

    func updateAIProviderPreference(_ provider: AIProviderKind) {
        aiProviderPreference = provider
        save()
    }

    func updateBackendEndpoint(_ endpoint: String) {
        backendEndpoint = endpoint
        save()
    }

    private func updateQuestion(_ question: CheckpointQuestion, result: AnswerResult) {
        guard let index = questions.firstIndex(where: { $0.id == question.id }) else { return }

        questions[index].timesAsked += 1
        questions[index].lastAskedAt = Date()

        switch result {
        case .correct:
            questions[index].timesCorrect += 1
            questions[index].status = questions[index].timesCorrect >= 3 ? .retired : .correct
            questions[index].nextReviewAt = Calendar.current.date(byAdding: .day, value: questions[index].timesCorrect + 1, to: Date())
        case .partial:
            questions[index].status = .due
            questions[index].nextReviewAt = Calendar.current.date(byAdding: .hour, value: 12, to: Date())
        case .incorrect, .unclear:
            questions[index].status = .incorrect
            questions[index].nextReviewAt = Calendar.current.date(byAdding: .hour, value: 2, to: Date())
        }
    }

    private func unlockMinutes(for result: AnswerResult) -> Int {
        switch result {
        case .correct:
            return unlockPolicy.unlockMinutes
        case .partial:
            return unlockPolicy.unlockOnPartial ? unlockPolicy.partialUnlockMinutes : 0
        case .incorrect, .unclear:
            return 0
        }
    }

    private func updateCompetency(for question: CheckpointQuestion, result: AnswerResult) {
        if !competencies.contains(where: { $0.topic == question.topic }) {
            competencies.append(.initial(topic: question.topic))
        }

        guard let index = competencies.firstIndex(where: { $0.topic == question.topic }) else { return }

        competencies[index].attempts += 1
        competencies[index].lastResult = result
        competencies[index].lastPracticedAt = Date()

        let difficultyGap = Double(question.difficulty) - competencies[index].estimatedLevel

        switch result {
        case .correct:
            competencies[index].correct += 1
            competencies[index].currentStreak += 1
            competencies[index].estimatedLevel += difficultyGap >= 0 ? 0.35 : 0.20
        case .partial:
            competencies[index].partial += 1
            competencies[index].currentStreak = 0
            competencies[index].estimatedLevel += difficultyGap >= 0 ? 0.14 : 0.06
        case .incorrect, .unclear:
            competencies[index].incorrect += 1
            competencies[index].currentStreak = 0
            competencies[index].estimatedLevel -= difficultyGap <= 0 ? 0.25 : 0.12
        }

        competencies[index].estimatedLevel = min(5.0, max(1.0, competencies[index].estimatedLevel))
    }

    private func sortByReviewPriority(_ lhs: CheckpointQuestion, _ rhs: CheckpointQuestion) -> Bool {
        if lhs.difficulty != rhs.difficulty {
            return lhs.difficulty < rhs.difficulty
        }
        return (lhs.nextReviewAt ?? .distantPast) < (rhs.nextReviewAt ?? .distantPast)
    }

    private func sortByAdaptivePriority(_ lhs: CheckpointQuestion, _ rhs: CheckpointQuestion) -> Bool {
        let lhsCompetency = competency(for: lhs.topic)
        let rhsCompetency = competency(for: rhs.topic)

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

    private func competency(for topic: String) -> TopicCompetency {
        competencies.first(where: { $0.topic == topic }) ?? .initial(topic: topic)
    }

    private func targetDifficulty(for competency: TopicCompetency) -> Double {
        min(5.0, max(1.0, competency.estimatedLevel + 0.5))
    }

    private func save() {
        let snapshot = AppSnapshot(
            goal: goal,
            questions: questions,
            attempts: attempts,
            competencies: competencies,
            questionReports: questionReports,
            unlockPolicy: unlockPolicy,
            questionBatchState: questionBatchState,
            aiProviderPreference: aiProviderPreference,
            lastQuestionProvider: lastQuestionProvider,
            backendEndpoint: backendEndpoint,
            unlockSession: unlockSession,
            emergencyPassesRemaining: emergencyPassesRemaining
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    private func publishShieldContext() {
        SharedAppGroup.publishShieldContext(
            goalTitle: goal?.title,
            promptPreview: nextQuestion()?.prompt
        )
    }

    private func load() {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(AppSnapshot.self, from: data)
        else { return }

        goal = snapshot.goal
        questions = snapshot.questions
        attempts = snapshot.attempts
        competencies = snapshot.competencies
        questionReports = snapshot.questionReports ?? []
        unlockPolicy = snapshot.unlockPolicy ?? .default
        questionBatchState = snapshot.questionBatchState ?? .idle
        aiProviderPreference = snapshot.aiProviderPreference ?? .automatic
        lastQuestionProvider = snapshot.lastQuestionProvider ?? .localTemplates
        backendEndpoint = snapshot.backendEndpoint ?? ""
        unlockSession = snapshot.unlockSession
        emergencyPassesRemaining = snapshot.emergencyPassesRemaining
    }

    private func initialCompetencies(for goal: Goal, questions: [CheckpointQuestion]) -> [TopicCompetency] {
        let focusTopics = goal.focusAreas
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let questionTopics = questions.map(\.topic)
        let topics = Array(Set(focusTopics + questionTopics)).sorted()

        return topics.map { topic in
            .initial(topic: topic, estimatedLevel: estimatedStartingLevel(for: topic, goal: goal))
        }
    }

    private func mergeCompetencies(
        existing: [TopicCompetency],
        goal: Goal,
        questions: [CheckpointQuestion]
    ) -> [TopicCompetency] {
        let newCompetencies = initialCompetencies(for: goal, questions: questions)
        let existingByTopic = Dictionary(uniqueKeysWithValues: existing.map { ($0.topic, $0) })

        return newCompetencies.map { competency in
            existingByTopic[competency.topic] ?? competency
        }
    }

    private func questionKey(_ question: CheckpointQuestion) -> String {
        "\(question.topic.lowercased())::\(question.prompt.lowercased())"
    }

    private func estimatedStartingLevel(for topic: String, goal: Goal) -> Double {
        let levelText = goal.currentLevel.lowercased()
        var estimate = 1.5

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

    private func containsTopic(_ topic: String, in text: String) -> Bool {
        let normalizedTopic = normalizedSignal(topic)
        let normalizedText = normalizedSignal(text)
        return !normalizedTopic.isEmpty && normalizedText.contains(normalizedTopic)
    }

    private func containsAny(_ needles: [String], in text: String) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func normalizedSignal(_ text: String) -> String {
        text
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func topicSegments(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ".,;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func generationRequest(
        goal: Goal,
        existingQuestions: [CheckpointQuestion],
        competencies: [TopicCompetency],
        reportedQuestions: [QuestionQualityReport]
    ) -> QuestionGenerationRequest {
        QuestionGenerationRequest(
            goal: goal,
            existingQuestions: existingQuestions,
            competencies: competencies,
            reportedQuestions: reportedQuestions,
            targetCount: 40,
            backendEndpoint: URL(string: backendEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }
}
