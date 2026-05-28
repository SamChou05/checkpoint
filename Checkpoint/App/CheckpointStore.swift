import Foundation
import Observation

private enum QuestionRefreshReason {
    case manual
    case automaticCoreRefill
    case automaticProactiveRefill

    var canBypassFreeLimit: Bool {
        self == .automaticCoreRefill
    }

    func countsAsRefresh(isPro: Bool) -> Bool {
        self == .manual || self == .automaticProactiveRefill || (self == .automaticCoreRefill && isPro)
    }

    func providerPreference(defaultPreference: AIProviderKind, isPro: Bool) -> AIProviderKind {
        if self == .automaticCoreRefill && !isPro {
            return .localTemplates
        }

        return defaultPreference
    }
}

@MainActor
@Observable
final class CheckpointStore {
    // MARK: - Stored state

    var goal: Goal? {
        didSet {
            if let goal {
                upsertGoalProfile(goal)
            }
        }
    }
    var goalProfiles: [Goal] = []
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
    var checkpointNotice: String?
    var unlockSession: UnlockSession?
    var emergencyPassesRemaining = 1
    var isOnboardingPresented = false
    var isCreatingGoalProfile = false
    var subscriptionTier: SubscriptionTier = .free
    var questionRefreshesUsed = 0
    var pendingPaywallFeature: ProFeature?
    var lastAutomaticQuestionRefreshAt: Date?

    @ObservationIgnored private let questionEngine: HybridQuestionEngine
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let snapshotKey = "checkpoint.snapshot.v1"

    // MARK: - Lifecycle

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

    // MARK: - Derived state

    var activeUnlockMinutesRemaining: Int {
        guard let unlockSession, unlockSession.isActive else { return 0 }
        return max(0, Int(ceil(unlockSession.expiresAt.timeIntervalSinceNow / 60)))
    }

    var completedTodayCount: Int {
        activeAttempts.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    var conversionRateText: String {
        guard !activeAttempts.isEmpty else { return "0%" }
        let successful = activeAttempts.filter { $0.result == .correct || $0.result == .partial }.count
        return "\(Int((Double(successful) / Double(activeAttempts.count)) * 100))%"
    }

    var averageMasteryText: String {
        guard !activeCompetencies.isEmpty else { return "0%" }
        let total = activeCompetencies.reduce(0) { $0 + $1.masteryPercent }
        return "\(total / activeCompetencies.count)%"
    }

    var sortedCompetencies: [TopicCompetency] {
        activeCompetencies.sorted {
            if $0.masteryPercent == $1.masteryPercent {
                return $0.topic < $1.topic
            }
            return $0.masteryPercent < $1.masteryPercent
        }
    }

    var reportedQuestionCount: Int {
        activeQuestionReports.count
    }

    var activeQuestionDifficulty: Int {
        goal?.minimumQuestionDifficulty ?? unlockPolicy.minimumQuestionDifficulty
    }

    var activeQuestions: [CheckpointQuestion] {
        guard let goalID = goal?.id else { return [] }
        return questions.filter { $0.goalID == goalID }
    }

    var activeAttempts: [CheckpointAttempt] {
        guard let goalID = goal?.id else { return [] }
        return attempts.filter { $0.goalID == goalID }
    }

    var activeCompetencies: [TopicCompetency] {
        guard let goalID = goal?.id else { return [] }
        return competencies.filter { $0.goalID == goalID || $0.goalID == nil }
    }

    var activeQuestionReports: [QuestionQualityReport] {
        guard let goalID = goal?.id else { return [] }
        return questionReports.filter { $0.goalID == goalID }
    }

    var availableGoalProfiles: [Goal] {
        let profiles = goalProfiles.isEmpty ? goal.map { [$0] } ?? [] : goalProfiles
        return profiles.sorted {
            if $0.id == goal?.id { return true }
            if $1.id == goal?.id { return false }
            return $0.createdAt > $1.createdAt
        }
    }

    var isPro: Bool {
        subscriptionTier == .pro
    }

    var questionBankTargetCount: Int {
        isPro ? FreemiumLimits.proQuestionBankTargetCount : FreemiumLimits.freeQuestionBankTargetCount
    }

    var canRefreshQuestionBatch: Bool {
        isPro || questionRefreshesUsed < FreemiumLimits.freeQuestionRefreshLimit
    }

    var usableQuestionCount: Int {
        activeQuestions.filter(meetsDifficultyFloor).count
    }

    var proAssistSummary: String {
        guard isPro else {
            return "Pro can quietly add fresh questions and point you toward the next useful topic."
        }

        if let focus = proFocusRecommendation {
            return focus
        }

        if usableQuestionCount <= FreemiumLimits.proAutoRefreshThreshold {
            return "Your practice set is getting low. Checkpoint will add fresh questions when possible."
        }

        return "Your practice set is healthy. Keep answering checkpoints and missed topics will surface automatically."
    }

    var proFocusRecommendation: String? {
        guard isPro, goal != nil else { return nil }

        if let missedTopic = activeQuestions
            .filter({ $0.status == .incorrect })
            .sorted(by: sortByReviewPriority)
            .first?
            .topic {
            return "Focus next on \(missedTopic); recent misses are ready for review."
        }

        guard let competency = sortedCompetencies.first else { return nil }

        if competency.attempts == 0 {
            return "Start with \(competency.topic); it has the least evidence so far."
        }

        return "Focus next on \(competency.topic); it is your lowest mastery area at \(competency.masteryPercent)%."
    }

    // MARK: - Pro access

    func canUse(_ feature: ProFeature) -> Bool {
        switch feature {
        case .advancedStrictness,
             .automaticBankRefill,
             .unlimitedQuestionRefreshes,
             .largerQuestionBanks,
             .deeperAnalytics,
             .multipleGoals,
             .importsAndSync:
            return isPro
        }
    }

    func requestUpgrade(for feature: ProFeature) {
        pendingPaywallFeature = feature
    }

    func dismissPaywall() {
        pendingPaywallFeature = nil
    }

    // MARK: - Goal profiles

    func presentGoalProfileCreator() {
        guard goal == nil || canUse(.multipleGoals) else {
            requestUpgrade(for: .multipleGoals)
            return
        }

        isCreatingGoalProfile = true
        isOnboardingPresented = true
    }

    func presentActiveGoalEditor() {
        isCreatingGoalProfile = false
        isOnboardingPresented = true
    }

    func switchActiveGoal(to goalID: Goal.ID) {
        guard goalID == goal?.id || canUse(.multipleGoals) else {
            requestUpgrade(for: .multipleGoals)
            return
        }

        guard let selectedGoal = availableGoalProfiles.first(where: { $0.id == goalID }) else { return }
        goal = selectedGoal
        questionBatchState = activeQuestions.isEmpty ? .idle : .ready
        checkpointNotice = nil
        save()
        publishShieldContext()
    }

    func updateSubscriptionTier(_ tier: SubscriptionTier) {
        subscriptionTier = tier
        if tier == .free {
            normalizeFreeTierLimits()
        }
        save()
        publishShieldContext()
    }

    // MARK: - Goal creation and refresh

    func createGoal(
        title: String,
        deadline: Date,
        category: GoalCategory? = nil,
        currentLevel: String,
        focusAreas: String,
        preferredQuestionStyle: QuestionFormat,
        minimumQuestionDifficulty: Int? = nil,
        createsNewProfile: Bool? = nil
    ) async {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrentLevel = currentLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFocusAreas = focusAreas.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTitle.isEmpty else {
            questionBatchState = .failed
            lastAIErrorMessage = "Enter a goal before generating questions."
            save()
            return
        }

        let newGoal = Goal(
            title: normalizedTitle,
            deadline: max(deadline, Date()),
            category: category ?? inferredGoalCategory(
                title: normalizedTitle,
                currentLevel: normalizedCurrentLevel,
                focusAreas: normalizedFocusAreas
            ),
            currentLevel: normalizedCurrentLevel,
            focusAreas: normalizedFocusAreas,
            preferredQuestionStyle: preferredQuestionStyle,
            minimumQuestionDifficulty: minimumQuestionDifficulty ?? activeQuestionDifficulty
        )

        let previousGoalID = goal?.id
        let shouldCreateNewProfile = createsNewProfile ?? (isPro && previousGoalID != nil)
        let shouldReplaceActiveProfile = !shouldCreateNewProfile && previousGoalID != nil
        questionRefreshesUsed = 0
        questionBatchState = .generating
        let batch = await questionEngine.generateQuestionBatch(
            for: generationRequest(goal: newGoal, existingQuestions: [], competencies: [], reportedQuestions: []),
            preference: aiProviderPreference
        )

        goal = newGoal
        if shouldReplaceActiveProfile, let previousGoalID {
            removeGoalData(for: previousGoalID)
            goalProfiles.removeAll { $0.id == previousGoalID }
            upsertGoalProfile(newGoal)
            if !isPro {
                goalProfiles = [newGoal]
            }
        }

        questions.append(contentsOf: batch.questions)
        lastQuestionProvider = batch.provider
        lastAIErrorMessage = batch.usedFallback ? "Checkpoint used the best available question path for this device." : nil
        competencies.append(contentsOf: initialCompetencies(for: newGoal, questions: batch.questions))
        questionBatchState = .ready
        checkpointNotice = nil
        unlockSession = nil
        isOnboardingPresented = false
        isCreatingGoalProfile = false
        SharedAppGroup.publishUnlockExpiration(nil)
        save()
        publishShieldContext()
    }

    func refreshQuestionBatch() async {
        await refreshQuestionBatch(reason: .manual)
    }

    private func refreshQuestionBatch(reason: QuestionRefreshReason) async {
        guard let goal else { return }

        guard reason.canBypassFreeLimit || canRefreshQuestionBatch else {
            lastAIErrorMessage = "Free includes \(FreemiumLimits.freeQuestionRefreshLimit) question refreshes per goal. Pro keeps refreshes unlimited."
            requestUpgrade(for: .unlimitedQuestionRefreshes)
            save()
            return
        }

        questionBatchState = .generating
        if reason.countsAsRefresh(isPro: isPro) {
            questionRefreshesUsed += 1
        }

        let batch = await questionEngine.generateQuestionBatch(
            for: generationRequest(
                goal: goal,
                existingQuestions: activeQuestions,
                competencies: activeCompetencies,
                reportedQuestions: activeQuestionReports
            ),
            preference: reason.providerPreference(defaultPreference: aiProviderPreference, isPro: isPro)
        )
        let generatedQuestions = batch.questions
        let existingKeys = Set(activeQuestions.map { questionKey($0) })
        let newQuestions = generatedQuestions.filter { !existingKeys.contains(questionKey($0)) }
        questions.append(contentsOf: newQuestions)
        replaceActiveCompetencies(with: mergeCompetencies(existing: activeCompetencies, goal: goal, questions: activeQuestions))
        lastQuestionProvider = batch.provider
        if newQuestions.isEmpty {
            lastAIErrorMessage = "No new usable questions were added. Try refining the goal or refreshing later."
        } else {
            lastAIErrorMessage = batch.usedFallback ? "Checkpoint used the best available question path for this device." : nil
        }
        questionBatchState = .ready
        save()
        publishShieldContext()
    }

    @discardableResult
    func refreshQuestionBatchIfNeeded(minimumUsableQuestionCount: Int? = nil) async -> Bool {
        guard goal != nil,
              questionBatchState != .generating else {
            return false
        }

        let refillMinimum = minimumUsableQuestionCount ?? unlockPolicy.questionsPerSession
        let needsCoreRefill = usableQuestionCount < refillMinimum && canRefreshAfterCooldown
        let shouldRefreshProactively = isPro
            && usableQuestionCount <= FreemiumLimits.proAutoRefreshThreshold
            && canRefreshAfterCooldown

        guard needsCoreRefill || shouldRefreshProactively else { return false }

        lastAutomaticQuestionRefreshAt = Date()
        await refreshQuestionBatch(reason: needsCoreRefill ? .automaticCoreRefill : .automaticProactiveRefill)
        return true
    }

    // MARK: - Question selection

    func nextQuestion() -> CheckpointQuestion? {
        nextQuestion(excluding: [])
    }

    func nextCheckpointSession() -> CheckpointSession? {
        let selectedQuestions = nextQuestions(limit: unlockPolicy.questionsPerSession)
        guard !selectedQuestions.isEmpty else { return nil }
        return CheckpointSession(
            questions: selectedQuestions,
            requiredCorrectAnswers: min(unlockPolicy.requiredCorrectAnswers, selectedQuestions.count)
        )
    }

    func nextQuestions(limit: Int) -> [CheckpointQuestion] {
        let targetCount = min(10, max(1, limit))
        var selectedQuestions: [CheckpointQuestion] = []
        var excludedQuestionIDs = Set<CheckpointQuestion.ID>()

        while selectedQuestions.count < targetCount,
              let question = nextQuestion(excluding: excludedQuestionIDs) {
            selectedQuestions.append(question)
            excludedQuestionIDs.insert(question.id)
        }

        return selectedQuestions
    }

    private func nextQuestion(excluding excludedQuestionIDs: Set<CheckpointQuestion.ID>) -> CheckpointQuestion? {
        let availableQuestions = activeQuestions.filter { !excludedQuestionIDs.contains($0.id) }
        let preferredQuestions = availableQuestions.filter(meetsDifficultyFloor)
        return prioritizedQuestion(from: preferredQuestions) ?? prioritizedQuestion(from: availableQuestions)
    }

    private func prioritizedQuestion(from availableQuestions: [CheckpointQuestion]) -> CheckpointQuestion? {
        let now = Date()

        if let missed = availableQuestions
            .filter({ $0.status == .incorrect && ($0.nextReviewAt ?? .distantPast) <= now })
            .sorted(by: sortByReviewPriority)
            .first {
            return missed
        }

        if let due = availableQuestions
            .filter({ ($0.nextReviewAt ?? .distantFuture) <= now && $0.status != .retired })
            .sorted(by: sortByReviewPriority)
            .first {
            return due
        }

        let weakAreaQuestion = availableQuestions
            .filter { $0.status == .new }
            .sorted(by: sortByAdaptivePriority)
            .first

        if let weakAreaQuestion {
            return weakAreaQuestion
        }

        return availableQuestions
            .filter { $0.status == .new }
            .sorted(by: sortByAdaptivePriority)
            .first ?? availableQuestions.filter { $0.status != .retired }.randomElement()
    }

    // MARK: - Attempts and unlocks

    @discardableResult
    func submitAnswer(
        question: CheckpointQuestion,
        answer: String,
        result: AnswerResult,
        grantsUnlock: Bool = true,
        unlockMinutesOverride: Int? = nil
    ) -> Int {
        guard let goal else { return 0 }

        let unlockMinutes = unlockMinutesOverride ?? (grantsUnlock ? unlockMinutes(for: result) : 0)
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

    @discardableResult
    func useEmergencyPass() -> Int {
        guard emergencyPassesRemaining > 0 else { return 0 }
        emergencyPassesRemaining -= 1
        let now = Date()
        let unlockMinutes = unlockPolicy.emergencyUnlockMinutes
        unlockSession = UnlockSession(
            startedAt: now,
            expiresAt: Calendar.current.date(byAdding: .minute, value: unlockMinutes, to: now) ?? now
        )
        SharedAppGroup.publishUnlockExpiration(unlockSession?.expiresAt)
        save()
        return unlockMinutes
    }

    func clearUnlockSession() {
        unlockSession = nil
        SharedAppGroup.publishUnlockExpiration(nil)
        save()
    }

    func resetDemoData() {
        goal = nil
        goalProfiles = []
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
        checkpointNotice = nil
        unlockSession = nil
        emergencyPassesRemaining = 1
        questionRefreshesUsed = 0
        pendingPaywallFeature = nil
        lastAutomaticQuestionRefreshAt = nil
        isCreatingGoalProfile = false
        isOnboardingPresented = true
        save()
        publishShieldContext()
    }

    // MARK: - Checkpoint sessions

    func takePendingShieldSession() -> CheckpointSession? {
        guard SharedAppGroup.consumePendingShieldAttempt() != nil else { return nil }
        return checkpointSession(source: .blockedApp)
    }

    func startManualCheckpointSession() -> CheckpointSession? {
        checkpointSession(source: .manual)
    }

    func startPreviewCheckpointSession() -> CheckpointSession? {
        checkpointSession(source: .manual, purpose: .preview)
    }

    func preparePendingShieldSession() async -> CheckpointSession? {
        guard SharedAppGroup.pendingShieldAttemptDate != nil else { return nil }

        if goal != nil && usableQuestionCount < unlockPolicy.questionsPerSession {
            _ = await refreshQuestionBatchIfNeeded()
        }

        if let session = takePendingShieldSession() {
            return session
        }

        guard await refreshQuestionBatchIfNeeded() else { return nil }
        return checkpointSession(source: .blockedApp)
    }

    func prepareManualCheckpointSession() async -> CheckpointSession? {
        if goal != nil && usableQuestionCount < unlockPolicy.questionsPerSession {
            _ = await refreshQuestionBatchIfNeeded()
        }

        if let session = startManualCheckpointSession() {
            return session
        }

        guard await refreshQuestionBatchIfNeeded() else { return nil }
        return checkpointSession(source: .manual)
    }

    func preparePreviewCheckpointSession() async -> CheckpointSession? {
        if goal != nil && usableQuestionCount < unlockPolicy.questionsPerSession {
            _ = await refreshQuestionBatchIfNeeded()
        }

        if let session = startPreviewCheckpointSession() {
            return session
        }

        guard await refreshQuestionBatchIfNeeded() else { return nil }
        return checkpointSession(source: .manual, purpose: .preview)
    }

    func prepareStopBlockingSession() async -> CheckpointSession? {
        if let session = startStopBlockingSession() {
            return session
        }

        guard await refreshQuestionBatchIfNeeded(minimumUsableQuestionCount: StopBlockingPolicy.questionsPerSession) else {
            return nil
        }

        return startStopBlockingSession()
    }

    func startStopBlockingSession() -> CheckpointSession? {
        guard goal != nil else {
            checkpointNotice = "Create a goal before stopping blocking."
            return nil
        }

        let selectedQuestions = nextQuestions(limit: StopBlockingPolicy.questionsPerSession)
        guard selectedQuestions.count >= StopBlockingPolicy.questionsPerSession else {
            checkpointNotice = "Checkpoint is preparing enough questions for the stop challenge. Try again in a moment or lower the minimum level."
            return nil
        }

        checkpointNotice = nil
        return CheckpointSession(
            questions: selectedQuestions,
            requiredCorrectAnswers: StopBlockingPolicy.requiredCorrectAnswers,
            purpose: .stopBlocking
        )
    }

    func clearCheckpointNotice() {
        checkpointNotice = nil
    }

    // MARK: - Question reporting

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

    func makeMissedQuestionsDueNow(_ questionIDs: Set<CheckpointQuestion.ID>) {
        guard !questionIDs.isEmpty else { return }
        let now = Date()

        for index in questions.indices where questionIDs.contains(questions[index].id) {
            guard questions[index].status != .retired else { continue }
            questions[index].status = .incorrect
            questions[index].nextReviewAt = now
        }

        save()
        publishShieldContext()
    }

    // MARK: - Settings updates

    func updateUnlockMinutes(_ minutes: Int) {
        unlockPolicy.unlockMinutes = UnlockPolicy.normalizedCorrectAnswerUnlockMinutes(minutes)
        save()
    }

    func updatePartialUnlockEnabled(_ isEnabled: Bool) {
        unlockPolicy.unlockOnPartial = isEnabled
        save()
    }

    func updateQuestionsPerSession(_ count: Int) {
        guard canUse(.advancedStrictness) else {
            requestUpgrade(for: .advancedStrictness)
            return
        }

        unlockPolicy.questionsPerSession = min(10, max(1, count))
        unlockPolicy.requiredCorrectAnswers = min(
            unlockPolicy.questionsPerSession,
            unlockPolicy.requiredCorrectAnswers
        )
        save()
        publishShieldContext()
    }

    func updateRequiredCorrectAnswers(_ count: Int) {
        guard canUse(.advancedStrictness) else {
            requestUpgrade(for: .advancedStrictness)
            return
        }

        unlockPolicy.requiredCorrectAnswers = min(unlockPolicy.questionsPerSession, max(1, count))
        save()
        publishShieldContext()
    }

    func updateMinimumQuestionDifficulty(_ difficulty: Int) {
        let normalizedDifficulty = UnlockPolicy.normalizedQuestionDifficulty(difficulty)
        if var activeGoal = goal {
            activeGoal.minimumQuestionDifficulty = normalizedDifficulty
            goal = activeGoal
        } else {
            unlockPolicy.minimumQuestionDifficulty = normalizedDifficulty
        }
        save()
        publishShieldContext()
    }

    func updateAIProviderPreference(_ provider: AIProviderKind) {
        aiProviderPreference = provider
        save()
    }

    func updateBackendEndpoint(_ endpoint: String) {
        backendEndpoint = endpoint
        save()
    }

    // MARK: - Adaptive scheduler

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
        let matchesQuestionGoal: (TopicCompetency) -> Bool = { competency in
            competency.topic == question.topic
                && (competency.goalID == question.goalID || (competency.goalID == nil && self.goal?.id == question.goalID))
        }

        if !competencies.contains(where: matchesQuestionGoal) {
            competencies.append(.initial(topic: question.topic, goalID: question.goalID))
        }

        guard let index = competencies.firstIndex(where: matchesQuestionGoal) else { return }
        competencies[index].goalID = question.goalID

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

    private func meetsDifficultyFloor(_ question: CheckpointQuestion) -> Bool {
        question.status != .retired && question.difficulty >= activeQuestionDifficulty
    }

    private func competency(for topic: String) -> TopicCompetency {
        activeCompetencies.first(where: { $0.topic == topic }) ?? .initial(topic: topic, goalID: goal?.id)
    }

    private func targetDifficulty(for competency: TopicCompetency) -> Double {
        min(5.0, max(1.0, competency.estimatedLevel + 0.5))
    }

    private func inferredGoalCategory(
        title: String,
        currentLevel: String,
        focusAreas: String
    ) -> GoalCategory {
        let signal = [title, currentLevel, focusAreas].joined(separator: " ").lowercased()

        if containsAny(["coding interview", "leetcode", "algorithm", "data structure", "system design", "programming interview"], in: signal) {
            return .codingInterview
        }

        if containsAny(["exam", "test", "final", "midterm", "quiz", "lsat", "sat", "act", "mcat", "gre", "calculus"], in: signal) {
            return .examPrep
        }

        if containsAny(["language", "spanish", "french", "japanese", "korean", "mandarin", "grammar", "vocabulary"], in: signal) {
            return .languageLearning
        }

        if containsAny(["fitness", "workout", "running", "marathon", "strength", "gym"], in: signal) {
            return .fitness
        }

        if containsAny(["writing", "essay", "blog", "book", "draft", "publish"], in: signal) {
            return .writing
        }

        return .custom
    }

    // MARK: - Profile helpers

    private func upsertGoalProfile(_ profile: Goal) {
        if let index = goalProfiles.firstIndex(where: { $0.id == profile.id }) {
            goalProfiles[index] = profile
        } else {
            goalProfiles.append(profile)
        }
    }

    private func removeGoalData(for goalID: Goal.ID) {
        questions.removeAll { $0.goalID == goalID }
        attempts.removeAll { $0.goalID == goalID }
        competencies.removeAll { $0.goalID == goalID || $0.goalID == nil }
        questionReports.removeAll { $0.goalID == goalID }
    }

    private func replaceActiveCompetencies(with updatedCompetencies: [TopicCompetency]) {
        guard let goalID = goal?.id else { return }
        competencies.removeAll { ($0.goalID ?? goalID) == goalID }
        competencies.append(contentsOf: updatedCompetencies)
    }

    private func migrateLegacyCompetenciesToActiveGoal() {
        guard let goalID = goal?.id else { return }

        for index in competencies.indices where competencies[index].goalID == nil {
            competencies[index].goalID = goalID
        }
    }

    // MARK: - Persistence and app group state

    private func save() {
        let snapshot = AppSnapshot(
            goal: goal,
            goalProfiles: availableGoalProfiles,
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
            emergencyPassesRemaining: emergencyPassesRemaining,
            subscriptionTier: subscriptionTier,
            questionRefreshesUsed: questionRefreshesUsed,
            lastAutomaticQuestionRefreshAt: lastAutomaticQuestionRefreshAt
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

    private func checkpointSession(
        source: CheckpointSessionSource,
        purpose: CheckpointSessionPurpose = .temporaryUnlock
    ) -> CheckpointSession? {
        if let session = nextCheckpointSession() {
            checkpointNotice = nil
            return CheckpointSession(
                questions: session.questions,
                requiredCorrectAnswers: session.requiredCorrectAnswers,
                purpose: purpose
            )
        }

        checkpointNotice = checkpointSessionUnavailableMessage(source: source)
        return nil
    }

    private func checkpointSessionUnavailableMessage(source: CheckpointSessionSource) -> String {
        if goal == nil {
            return source == .blockedApp
                ? "Checkpoint opened from a blocked app, but no goal is set yet."
                : "Create a goal before starting a checkpoint."
        }

        if activeQuestions.isEmpty {
            return source == .blockedApp
                ? "Checkpoint opened from a blocked app, but no questions are ready yet."
                : "No questions are ready yet."
        }

        return "Checkpoint is preparing more questions. Try again in a moment or lower the minimum level."
    }

    private func load() {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(AppSnapshot.self, from: data)
        else { return }

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
        subscriptionTier = snapshot.subscriptionTier ?? .free
        questionRefreshesUsed = snapshot.questionRefreshesUsed ?? 0
        lastAutomaticQuestionRefreshAt = snapshot.lastAutomaticQuestionRefreshAt
        goalProfiles = snapshot.goalProfiles ?? snapshot.goal.map { [$0] } ?? []
        goal = snapshot.goal

        if snapshot.goalProfiles == nil,
           var legacyGoal = goal,
           snapshot.unlockPolicy != nil {
            legacyGoal.minimumQuestionDifficulty = unlockPolicy.minimumQuestionDifficulty
            goal = legacyGoal
            goalProfiles = [legacyGoal]
        }

        migrateLegacyCompetenciesToActiveGoal()

        if subscriptionTier == .free {
            normalizeFreeTierLimits()
        }
    }

    private func initialCompetencies(for goal: Goal, questions: [CheckpointQuestion]) -> [TopicCompetency] {
        let focusTopics = goal.focusAreas
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let questionTopics = questions.map(\.topic)
        let topics = Array(Set(focusTopics + questionTopics)).sorted()

        return topics.map { topic in
            .initial(topic: topic, estimatedLevel: estimatedStartingLevel(for: topic, goal: goal), goalID: goal.id)
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

    // MARK: - Question generation requests

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
            targetCount: questionBankTargetCount,
            minimumDifficulty: goal.minimumQuestionDifficulty,
            backendEndpoint: URL(string: backendEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    private func normalizeFreeTierLimits() {
        unlockPolicy.questionsPerSession = UnlockPolicy.default.questionsPerSession
        unlockPolicy.requiredCorrectAnswers = UnlockPolicy.default.requiredCorrectAnswers
    }

    private var canRefreshAfterCooldown: Bool {
        guard let lastAutomaticQuestionRefreshAt else { return true }
        return Date().timeIntervalSince(lastAutomaticQuestionRefreshAt) >= FreemiumLimits.proAutoRefreshCooldown
    }
}
