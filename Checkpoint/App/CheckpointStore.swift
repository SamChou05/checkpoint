import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class PurchaseController {
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoadingProducts = false
    var purchaseMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    var isProUnlocked: Bool {
        purchasedProductIDs.contains { ProProductID.all.contains($0) }
    }

    func startListeningForTransactions() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            products = try await Product.products(for: ProProductID.all)
                .sorted { $0.price < $1.price }
            purchaseMessage = nil
        } catch {
            purchaseMessage = "Could not load App Store products yet."
        }
    }

    @discardableResult
    func refreshEntitlements() async -> Bool {
        var activeProductIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProProductID.all.contains(transaction.productID) else {
                continue
            }

            activeProductIDs.insert(transaction.productID)
        }

        purchasedProductIDs = activeProductIDs
        return isProUnlocked
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseMessage = "The App Store could not verify this purchase."
                    return false
                }

                await transaction.finish()
                purchaseMessage = nil
                return await refreshEntitlements()
            case .pending:
                purchaseMessage = "Purchase is pending approval."
                return false
            case .userCancelled:
                purchaseMessage = nil
                return false
            @unknown default:
                purchaseMessage = "The App Store returned an unknown purchase state."
                return false
            }
        } catch {
            purchaseMessage = "Purchase failed. Try again from the App Store sheet."
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            purchaseMessage = nil
            return await refreshEntitlements()
        } catch {
            purchaseMessage = "Could not restore purchases yet."
            return false
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult,
              ProProductID.all.contains(transaction.productID) else {
            return
        }

        await transaction.finish()
        _ = await refreshEntitlements()
    }
}

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
    var checkpointNotice: String?
    var unlockSession: UnlockSession?
    var emergencyPassesRemaining = 1
    var isOnboardingPresented = false
    var subscriptionTier: SubscriptionTier = .free
    var questionRefreshesUsed = 0
    var pendingPaywallFeature: ProFeature?
    var lastAutomaticQuestionRefreshAt: Date?

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

    var isPro: Bool {
        subscriptionTier == .pro
    }

    var remainingFreeQuestionRefreshes: Int {
        max(0, FreemiumLimits.freeQuestionRefreshLimit - questionRefreshesUsed)
    }

    var questionRefreshStatusText: String {
        isPro ? "Unlimited" : "\(remainingFreeQuestionRefreshes) free refreshes left"
    }

    var questionBankTargetCount: Int {
        isPro ? FreemiumLimits.proQuestionBankTargetCount : FreemiumLimits.freeQuestionBankTargetCount
    }

    var canRefreshQuestionBatch: Bool {
        isPro || questionRefreshesUsed < FreemiumLimits.freeQuestionRefreshLimit
    }

    var usableQuestionCount: Int {
        questions.filter(meetsDifficultyFloor).count
    }

    var questionBankHealthText: String {
        guard goal != nil else { return "No active goal yet" }

        if usableQuestionCount < unlockPolicy.questionsPerSession {
            return "Needs refill"
        }

        if usableQuestionCount <= FreemiumLimits.proAutoRefreshThreshold {
            return "Getting low"
        }

        return "Ready"
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

        if let missedTopic = questions
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

    func updateSubscriptionTier(_ tier: SubscriptionTier) {
        subscriptionTier = tier
        if tier == .free {
            normalizeFreeTierLimits()
        }
        save()
        publishShieldContext()
    }

    func createGoal(
        title: String,
        deadline: Date,
        category: GoalCategory,
        currentLevel: String,
        focusAreas: String,
        preferredQuestionStyle: QuestionFormat
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
            category: category,
            currentLevel: normalizedCurrentLevel,
            focusAreas: normalizedFocusAreas,
            preferredQuestionStyle: preferredQuestionStyle
        )

        goal = newGoal
        questionRefreshesUsed = 0
        let batch = await questionEngine.generateQuestionBatch(
            for: generationRequest(goal: newGoal, existingQuestions: [], competencies: [], reportedQuestions: []),
            preference: aiProviderPreference
        )

        questions = batch.questions
        lastQuestionProvider = batch.provider
        lastAIErrorMessage = batch.usedFallback ? "Checkpoint used the best available question path for this device." : nil
        competencies = initialCompetencies(for: newGoal, questions: questions)
        questionReports = []
        questionBatchState = .ready
        attempts = []
        checkpointNotice = nil
        unlockSession = nil
        isOnboardingPresented = false
        SharedAppGroup.publishUnlockExpiration(nil)
        save()
        publishShieldContext()
    }

    func refreshQuestionBatch() async {
        guard let goal else { return }

        guard canRefreshQuestionBatch else {
            lastAIErrorMessage = "Free includes \(FreemiumLimits.freeQuestionRefreshLimit) question refreshes per goal. Pro keeps refreshes unlimited."
            requestUpgrade(for: .unlimitedQuestionRefreshes)
            save()
            return
        }

        questionBatchState = .generating
        questionRefreshesUsed += 1

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
            lastAIErrorMessage = "No new usable questions were added. Try refining the goal or refreshing later."
        } else {
            lastAIErrorMessage = batch.usedFallback ? "Checkpoint used the best available question path for this device." : nil
        }
        questionBatchState = .ready
        save()
        publishShieldContext()
    }

    @discardableResult
    func refreshQuestionBatchIfNeeded() async -> Bool {
        guard isPro,
              goal != nil,
              questionBatchState != .generating,
              usableQuestionCount <= FreemiumLimits.proAutoRefreshThreshold,
              canRefreshAfterCooldown else {
            return false
        }

        lastAutomaticQuestionRefreshAt = Date()
        await refreshQuestionBatch()
        return true
    }

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
        let availableQuestions = questions.filter { !excludedQuestionIDs.contains($0.id) }
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
        isOnboardingPresented = true
        save()
        publishShieldContext()
    }

    func takePendingShieldSession() -> CheckpointSession? {
        guard SharedAppGroup.consumePendingShieldAttempt() != nil else { return nil }
        return checkpointSession(source: .blockedApp)
    }

    func startManualCheckpointSession() -> CheckpointSession? {
        checkpointSession(source: .manual)
    }

    func startStopBlockingSession() -> CheckpointSession? {
        guard goal != nil else {
            checkpointNotice = "Create a goal before stopping blocking."
            return nil
        }

        let selectedQuestions = nextQuestions(limit: StopBlockingPolicy.questionsPerSession)
        guard selectedQuestions.count >= StopBlockingPolicy.questionsPerSession else {
            checkpointNotice = "Stopping blocking needs 10 ready questions. Refresh questions or lower the minimum level."
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
        unlockPolicy.minimumQuestionDifficulty = UnlockPolicy.normalizedQuestionDifficulty(difficulty)
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

    private func meetsDifficultyFloor(_ question: CheckpointQuestion) -> Bool {
        question.status != .retired && question.difficulty >= unlockPolicy.minimumQuestionDifficulty
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

    private func checkpointSession(source: CheckpointSessionSource) -> CheckpointSession? {
        if let session = nextCheckpointSession() {
            checkpointNotice = nil
            return session
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

        if questions.isEmpty {
            return source == .blockedApp
                ? "Checkpoint opened from a blocked app, but no questions are ready yet."
                : "No questions are ready yet."
        }

        return "No usable checkpoint questions are available. Refresh the question batch or lower the minimum level."
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
        subscriptionTier = snapshot.subscriptionTier ?? .free
        questionRefreshesUsed = snapshot.questionRefreshesUsed ?? 0
        lastAutomaticQuestionRefreshAt = snapshot.lastAutomaticQuestionRefreshAt

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
            targetCount: questionBankTargetCount,
            minimumDifficulty: unlockPolicy.minimumQuestionDifficulty,
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
