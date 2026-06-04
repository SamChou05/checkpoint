import Foundation
import Observation

private enum QuestionRefreshReason {
    case manual
    case automaticCoreRefill
    case automaticProactiveRefill
    case levelUpRefill

    func countsAsRefresh(isMember: Bool) -> Bool {
        self == .manual || self == .automaticProactiveRefill || (self == .automaticCoreRefill && isMember)
    }

    func providerPreference(defaultPreference: AIProviderKind) -> AIProviderKind {
        return defaultPreference
    }

    var diagnosticsTitle: String {
        switch self {
        case .manual:
            return "Manual refresh"
        case .automaticCoreRefill:
            return "Automatic core refill"
        case .automaticProactiveRefill:
            return "Automatic proactive refill"
        case .levelUpRefill:
            return "Question level increase"
        }
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
    var questionGenerationTraces: [QuestionGenerationTrace] = []
    var unlockPolicy: UnlockPolicy = .default
    var questionBatchState: QuestionBatchState = .idle
    var aiProviderPreference: AIProviderKind = .automatic
    var lastQuestionProvider: AIProviderKind = .localTemplates
    var backendEndpoint = ""
    var lastAIErrorMessage: String?
    var questionGenerationStartedAt: Date?
    var lastQuestionGenerationDuration: TimeInterval?
    var isQuestionBankTopOffInProgress = false
    var questionBankTopOffStartedAt: Date?
    var lastQuestionBankTopOffDuration: TimeInterval?
    var checkpointNotice: String?
    var unlockSession: UnlockSession?
    var emergencyPassesRemaining = 1
    var isOnboardingPresented = false
    var isCreatingGoalProfile = false
    var membershipTier: MembershipTier = .starter
    var pendingMembershipFeature: MembershipFeature?
    var questionRefreshesUsed = 0
    var lastAutomaticQuestionRefreshAt: Date?

    @ObservationIgnored private let questionEngine: HybridQuestionEngine
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let snapshotKey = "checkpoint.snapshot.v1"
    @ObservationIgnored private var backgroundGenerationGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private var questionBankTopOffGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private static let initialCheckpointReadyTargetCount = 5
    @ObservationIgnored private static let maximumQuestionGenerationTraceCount = 20
    @ObservationIgnored private static let maximumQuestionGenerationPreviewCount = 12
    @ObservationIgnored private static let levelUpRecentAttemptWindow = 10
    @ObservationIgnored private static let levelUpMinimumAttemptCount = 5
    @ObservationIgnored private static let levelUpAccuracyThreshold = 0.90

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

    var questionsAnsweredThisWeekCount: Int {
        activeAttemptsThisWeek.count
    }

    var questionAccuracyThisWeekText: String {
        guard !activeAttemptsThisWeek.isEmpty else { return "0%" }
        let correct = activeAttemptsThisWeek.filter { $0.result == .correct }.count
        return "\(Int((Double(correct) / Double(activeAttemptsThisWeek.count)) * 100))%"
    }

    var averageMasteryText: String {
        let competencies = visibleActiveCompetencies
        guard !competencies.isEmpty else { return "0%" }
        let total = competencies.reduce(0) { $0 + $1.masteryPercent }
        return "\(total / competencies.count)%"
    }

    var sortedCompetencies: [TopicCompetency] {
        visibleActiveCompetencies.sorted {
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

    private var activeAttemptsThisWeek: [CheckpointAttempt] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return activeAttempts.filter { week.contains($0.createdAt) }
    }

    var activeCompetencies: [TopicCompetency] {
        guard let goalID = goal?.id else { return [] }
        return competencies.filter { $0.goalID == goalID || $0.goalID == nil }
    }

    var visibleActiveCompetencies: [TopicCompetency] {
        mergedCompetenciesForDisplay(activeCompetencies)
    }

    var activeQuestionReports: [QuestionQualityReport] {
        guard let goalID = goal?.id else { return [] }
        return questionReports.filter { $0.goalID == goalID }
    }

    var activeGoalFocusText: String? {
        guard let goal else { return nil }

        let context = GoalQuestionContext(goal: goal)
        if context.hasUserFocusAreas {
            let focusText = context.contentTopics.joined(separator: ", ")
            return focusText.isEmpty ? nil : focusText
        }

        return sortedCompetencies.first?.topic
    }

    var questionGenerationDiagnosticsSummary: String {
        guard let latestTrace = questionGenerationTraces.first else {
            return "No generation runs recorded yet"
        }

        return "\(latestTrace.generatedQuestionCount) generated, \(latestTrace.addedQuestionCount) added by \(latestTrace.resolvedProvider.rawValue)"
    }

    var questionGenerationDiagnosticsExportText: String {
        guard !questionGenerationTraces.isEmpty else {
            return "No question generation diagnostics recorded."
        }

        return questionGenerationTraces.map(Self.exportText(for:)).joined(separator: "\n\n---\n\n")
    }

    var availableGoalProfiles: [Goal] {
        let profiles = goalProfiles.isEmpty ? goal.map { [$0] } ?? [] : goalProfiles
        return profiles.sorted {
            if $0.id == goal?.id { return true }
            if $1.id == goal?.id { return false }
            return $0.createdAt > $1.createdAt
        }
    }

    var isMember: Bool {
        membershipTier == .member
    }

    var hasFullProductAccess: Bool {
        isMember
    }

    var questionBankTargetCount: Int {
        isMember ? ProductLimits.memberQuestionBankTargetCount : ProductLimits.starterQuestionBankTargetCount
    }

    var goalProfileLimit: Int {
        isMember ? ProductLimits.memberGoalProfileLimit : ProductLimits.starterGoalProfileLimit
    }

    var canCreateAdditionalGoalProfile: Bool {
        availableGoalProfiles.count < goalProfileLimit
    }

    var hasReachedGoalProfileLimit: Bool {
        !canCreateAdditionalGoalProfile
    }

    var goalProfileCapacityText: String {
        "\(availableGoalProfiles.count)/\(goalProfileLimit) goals"
    }

    var goalProfileLimitMessage: String {
        "You can keep up to \(goalProfileLimit) active goals. Edit an existing goal before adding another."
    }

    var canRefreshQuestionBatch: Bool {
        isMember
    }

    var shouldShowStarterMembershipPrompt: Bool {
        !isMember && goal != nil && usableQuestionCount <= ProductLimits.autoRefreshThreshold
    }

    var usableQuestionCount: Int {
        activeQuestions.filter(meetsDifficultyFloor).count
    }

    func usableQuestionCount(for profile: Goal) -> Int {
        questions.filter { question in
            question.goalID == profile.id
                && question.status != .retired
                && question.difficulty >= profile.minimumQuestionDifficulty
        }.count
    }

    func questionBankSummary(for profile: Goal) -> String {
        let readyCount = usableQuestionCount(for: profile)

        if backgroundGenerationGoalIDs.contains(profile.id) || questionBankTopOffGoalIDs.contains(profile.id) {
            return readyCount > 0 ? "\(readyCount) ready, preparing more" : "Preparing questions"
        }

        return readyCount == 1 ? "1 ready question" : "\(readyCount) ready questions"
    }

    var isPreparingActiveGoalQuestions: Bool {
        goal != nil && (questionBatchState == .generating || isQuestionBankTopOffInProgress)
    }

    var questionGenerationStatusText: String {
        if isQuestionBankTopOffInProgress {
            let elapsedText = questionBankTopOffStartedAt.map { " Started \(Self.formattedDuration(Date().timeIntervalSince($0))) ago." } ?? ""
            return "\(usableQuestionCount) ready; building the question bank in the background.\(elapsedText)"
        }

        switch questionBatchState {
        case .generating:
            let readyText = usableQuestionCount > 0
                ? "\(usableQuestionCount) ready; preparing more"
                : "Preparing first checkpoints"
            let elapsedText = questionGenerationStartedAt.map { " Started \(Self.formattedDuration(Date().timeIntervalSince($0))) ago." } ?? ""
            return "\(readyText) in the background.\(elapsedText)"
        case .failed:
            return lastAIErrorMessage ?? "Question preparation did not finish. Checkpoint will try again when possible."
        case .ready:
            if let duration = lastQuestionGenerationDuration {
                return "\(usableQuestionCount) ready. Last prepared in \(Self.formattedDuration(duration))."
            }
            return "\(usableQuestionCount) ready."
        case .idle:
            return usableQuestionCount > 0 ? "\(usableQuestionCount) ready." : "No checkpoints prepared yet."
        }
    }

    var studyAssistSummary: String {
        guard isMember else {
            return "Your first goal is included. Membership keeps fresh checkpoints ready when your starter set runs low."
        }

        if let focus = studyFocusRecommendation {
            return focus
        }

        if usableQuestionCount <= ProductLimits.autoRefreshThreshold {
            return "Your practice set is getting low. Checkpoint will add fresh questions when possible."
        }

        return "Your practice set is healthy. Keep answering checkpoints and missed topics will surface automatically."
    }

    var studyFocusRecommendation: String? {
        guard isMember, goal != nil else { return nil }

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

    var questionLevelRecommendation: QuestionLevelRecommendation? {
        guard let goal,
              goal.minimumQuestionDifficulty < 5,
              !isPreparingActiveGoalQuestions else {
            return nil
        }

        let recentAttempts = Array(activeAttempts.prefix(Self.levelUpRecentAttemptWindow))
        let attemptsAtCurrentLevel = recentAttempts.filter { attempt in
            guard let question = questions.first(where: { $0.id == attempt.questionID }) else {
                return true
            }

            return question.difficulty >= goal.minimumQuestionDifficulty
        }

        guard attemptsAtCurrentLevel.count >= Self.levelUpMinimumAttemptCount else { return nil }

        let correctCount = attemptsAtCurrentLevel.filter { $0.result == .correct }.count
        let accuracy = Double(correctCount) / Double(attemptsAtCurrentLevel.count)
        guard accuracy >= Self.levelUpAccuracyThreshold else { return nil }

        return QuestionLevelRecommendation(
            currentQuestionLevel: goal.minimumQuestionDifficulty,
            nextLevel: goal.minimumQuestionDifficulty + 1,
            accuracyPercent: Int((accuracy * 100).rounded()),
            answeredCount: attemptsAtCurrentLevel.count
        )
    }

    // MARK: - Goal profiles

    func presentGoalProfileCreator() {
        guard goal == nil || canUse(.goalProfiles) else {
            requestMembership(for: .goalProfiles)
            return
        }

        guard canCreateAdditionalGoalProfile else {
            checkpointNotice = goalProfileLimitMessage
            save()
            return
        }

        isCreatingGoalProfile = true
        isOnboardingPresented = true
    }

    func presentActiveGoalEditor() {
        guard goal == nil || canUse(.goalProfiles) else {
            requestMembership(for: .goalProfiles)
            return
        }

        isCreatingGoalProfile = false
        isOnboardingPresented = true
    }

    func switchActiveGoal(to goalID: Goal.ID) {
        guard let selectedGoal = availableGoalProfiles.first(where: { $0.id == goalID }) else { return }
        guard selectedGoal.id == goal?.id || canUse(.goalProfiles) else {
            requestMembership(for: .goalProfiles)
            return
        }

        goal = selectedGoal
        let hasActiveQuestions = !activeQuestions.isEmpty
        questionBatchState = hasActiveQuestions ? .ready : .generating
        isQuestionBankTopOffInProgress = questionBankTopOffGoalIDs.contains(selectedGoal.id)
        questionBankTopOffStartedAt = isQuestionBankTopOffInProgress ? questionBankTopOffStartedAt ?? Date() : nil
        checkpointNotice = nil
        save()
        publishShieldContext()

        if hasActiveQuestions {
            Task { [weak self] in
                _ = await self?.refreshQuestionBatchIfNeeded()
            }
        } else {
            prepareInitialQuestionsInBackground(for: selectedGoal)
        }
    }

    // MARK: - Membership

    func canUse(_ feature: MembershipFeature) -> Bool {
        isMember
    }

    func requestMembership(for feature: MembershipFeature) {
        pendingMembershipFeature = feature
    }

    func dismissMembershipPrompt() {
        pendingMembershipFeature = nil
    }

    func updateMembershipTier(_ tier: MembershipTier) {
        membershipTier = tier
        pendingMembershipFeature = nil
        save()
        publishShieldContext()

        if tier == .member {
            Task { [weak self] in
                _ = await self?.refreshQuestionBatchIfNeeded()
            }
        }
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
        createsNewProfile: Bool? = nil,
        waitForQuestionGeneration: Bool = true
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

        if goal != nil && !isMember {
            checkpointNotice = "Your first goal is included. Membership lets you change goals and keep separate checkpoint sets ready."
            requestMembership(for: .goalProfiles)
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
        let shouldCreateNewProfile = createsNewProfile ?? (isMember && previousGoalID != nil)
        let shouldReplaceActiveProfile = !shouldCreateNewProfile && previousGoalID != nil

        guard !shouldCreateNewProfile || canCreateAdditionalGoalProfile else {
            checkpointNotice = goalProfileLimitMessage
            save()
            return
        }

        questionRefreshesUsed = 0
        questionBatchState = .generating
        if shouldReplaceActiveProfile, let previousGoalID {
            removeGoalData(for: previousGoalID)
            goalProfiles.removeAll { $0.id == previousGoalID }
        }

        goal = newGoal
        isQuestionBankTopOffInProgress = false
        questionBankTopOffStartedAt = nil
        upsertGoalProfile(newGoal)
        questions.removeAll { $0.goalID == newGoal.id }
        competencies.removeAll { $0.goalID == newGoal.id }
        competencies.append(contentsOf: initialCompetencies(for: newGoal, questions: []))
        lastAIErrorMessage = nil
        checkpointNotice = nil
        unlockSession = nil
        isOnboardingPresented = false
        isCreatingGoalProfile = false
        SharedAppGroup.publishUnlockExpiration(nil)
        save()
        publishShieldContext()

        if waitForQuestionGeneration {
            await generateInitialQuestionBatch(for: newGoal)
        } else {
            prepareInitialQuestionsInBackground(for: newGoal)
        }
    }

    private func prepareInitialQuestionsInBackground(for newGoal: Goal) {
        Task { [weak self] in
            await self?.generateInitialQuestionBatch(for: newGoal)
        }
    }

    private func generateInitialQuestionBatch(for newGoal: Goal) async {
        guard goalProfiles.contains(where: { $0.id == newGoal.id }) || goal?.id == newGoal.id else { return }
        guard !backgroundGenerationGoalIDs.contains(newGoal.id) else { return }
        backgroundGenerationGoalIDs.insert(newGoal.id)
        defer { backgroundGenerationGoalIDs.remove(newGoal.id) }

        if goal?.id == newGoal.id {
            questionBatchState = .generating
            beginQuestionGeneration(for: newGoal.id)
        }

        let checkpointReadyRequest = generationRequest(
            goal: newGoal,
            existingQuestions: [],
            competencies: [],
            reportedQuestions: [],
            targetCount: Self.initialCheckpointReadyTargetCount
        )

        let startedAt = Date()
        let providerPreference = initialBatchProviderPreference(for: checkpointReadyRequest)
        let batch = await generateCheckpointReadyBatch(
            for: checkpointReadyRequest,
            preference: providerPreference
        )

        questions.removeAll { $0.goalID == newGoal.id }
        questions.append(contentsOf: batch.questions)
        competencies.removeAll { $0.goalID == newGoal.id }
        competencies.append(contentsOf: initialCompetencies(for: newGoal, questions: batch.questions))
        lastQuestionProvider = batch.provider
        if batch.questions.isEmpty {
            lastAIErrorMessage = "No usable questions were generated. Try adding focus topics or lowering the question level."
        } else {
            lastAIErrorMessage = batch.usedFallback ? "Checkpoint used the best available question path for this device." : nil
        }
        recordQuestionGenerationTrace(
            phase: "Initial ready batch",
            request: checkpointReadyRequest,
            providerPreference: providerPreference,
            batch: batch,
            addedQuestions: batch.questions,
            startedAt: startedAt,
            errorMessage: lastAIErrorMessage
        )
        if goal?.id == newGoal.id {
            questionBatchState = batch.questions.isEmpty ? .failed : .ready
            finishQuestionGeneration(for: newGoal.id)
        }
        save()
        publishShieldContext()

        if !batch.questions.isEmpty {
            topOffQuestionBankInBackground(
                for: newGoal,
                starterQuestionIDs: Set(batch.questions.map(\.id))
            )
        }
    }

    private func initialBatchProviderPreference(for request: QuestionGenerationRequest) -> AIProviderKind {
        if request.questionContext.needsGeneratedSkillMap {
            return aiProviderPreference
        }

        return .localTemplates
    }

    private func generateCheckpointReadyBatch(
        for request: QuestionGenerationRequest,
        preference: AIProviderKind
    ) async -> QuestionBatch {
        if preference == .localTemplates, aiProviderPreference != .localTemplates {
            let seedBatch = await questionEngine.generateQuestionBatch(
                for: request,
                preference: .localTemplates
            )
            if !seedBatch.questions.isEmpty {
                return seedBatch
            }
        }

        return await questionEngine.generateQuestionBatch(
            for: request,
            preference: preference
        )
    }

    private func topOffQuestionBankInBackground(
        for goal: Goal,
        starterQuestionIDs: Set<CheckpointQuestion.ID> = []
    ) {
        Task { [weak self] in
            await self?.topOffQuestionBank(for: goal, starterQuestionIDs: starterQuestionIDs)
        }
    }

    private func topOffQuestionBank(
        for targetGoal: Goal,
        starterQuestionIDs: Set<CheckpointQuestion.ID>
    ) async {
        guard goalProfiles.contains(where: { $0.id == targetGoal.id }) || goal?.id == targetGoal.id else { return }
        guard isMember || !starterQuestionIDs.isEmpty else {
            if goal?.id == targetGoal.id {
                checkpointNotice = starterQuestionLimitMessage
                requestMembership(for: .freshQuestionGeneration)
                save()
            }
            return
        }
        guard !questionBankTopOffGoalIDs.contains(targetGoal.id) else { return }
        questionBankTopOffGoalIDs.insert(targetGoal.id)
        defer { questionBankTopOffGoalIDs.remove(targetGoal.id) }

        if goal?.id == targetGoal.id {
            beginQuestionBankTopOff(for: targetGoal.id)
        }

        let existingQuestions = questions.filter { $0.goalID == targetGoal.id }
        let existingCompetencies = competencies.filter { ($0.goalID ?? targetGoal.id) == targetGoal.id }
        let starterQuestionsCanBeReplaced = aiProviderPreference != .localTemplates && !starterQuestionIDs.isEmpty
        let usableExistingCount = existingQuestions.filter {
            $0.difficulty >= targetGoal.minimumQuestionDifficulty
                && $0.status != .retired
                && (!starterQuestionsCanBeReplaced || !starterQuestionIDs.contains($0.id))
        }.count
        let remainingTargetCount = max(0, questionBankTargetCount - usableExistingCount)

        guard remainingTargetCount > 0 else {
            if goal?.id == targetGoal.id {
                finishQuestionBankTopOff(for: targetGoal.id)
            }
            return
        }

        let topOffRequest = generationRequest(
            goal: targetGoal,
            existingQuestions: existingQuestions,
            competencies: existingCompetencies,
            reportedQuestions: questionReports.filter { $0.goalID == targetGoal.id },
            targetCount: remainingTargetCount
        )
        let startedAt = Date()
        let batch = await questionEngine.generateQuestionBatch(
            for: topOffRequest,
            preference: aiProviderPreference
        )

        let existingKeys = Set(existingQuestions.map { questionKey($0) })
        let newQuestions = batch.questions.filter { !existingKeys.contains(questionKey($0)) }
        questions.append(contentsOf: newQuestions)
        let usableGeneratedCount = newQuestions.filter {
            $0.difficulty >= targetGoal.minimumQuestionDifficulty && $0.status != .retired
        }.count
        let canReplaceStarterBridge = batch.provider != .localTemplates
            && usableGeneratedCount >= unlockPolicy.questionsPerSession

        var retiredStarterQuestionCount = 0
        if canReplaceStarterBridge {
            for index in questions.indices where starterQuestionIDs.contains(questions[index].id) {
                questions[index].status = .retired
                retiredStarterQuestionCount += 1
            }
        }
        let goalQuestions = questions.filter { $0.goalID == targetGoal.id }
        competencies.removeAll { $0.goalID == targetGoal.id }
        competencies.append(contentsOf: initialCompetencies(for: targetGoal, questions: goalQuestions))
        if !newQuestions.isEmpty {
            lastQuestionProvider = batch.provider
            lastAIErrorMessage = batch.usedFallback ? "Checkpoint used the best available question path for this device." : nil
        }
        recordQuestionGenerationTrace(
            phase: "Question bank top-off",
            request: topOffRequest,
            providerPreference: aiProviderPreference,
            batch: batch,
            addedQuestions: newQuestions,
            retiredQuestionCount: retiredStarterQuestionCount,
            startedAt: startedAt,
            errorMessage: lastAIErrorMessage
        )
        if goal?.id == targetGoal.id {
            questionBatchState = goalQuestions.isEmpty ? .failed : .ready
            finishQuestionBankTopOff(for: targetGoal.id)
        }
        save()
        publishShieldContext()
    }

    func refreshQuestionBatch() async {
        await refreshQuestionBatch(reason: .manual)
    }

    private func refreshQuestionBatch(reason: QuestionRefreshReason) async {
        guard let goal else { return }
        guard isMember else {
            checkpointNotice = starterQuestionLimitMessage
            lastAIErrorMessage = starterQuestionLimitMessage
            requestMembership(for: .freshQuestionGeneration)
            save()
            return
        }

        questionBatchState = .generating
        beginQuestionGeneration(for: goal.id)
        if reason.countsAsRefresh(isMember: isMember) {
            questionRefreshesUsed += 1
        }

        let refreshRequest = generationRequest(
            goal: goal,
            existingQuestions: activeQuestions,
            competencies: activeCompetencies,
            reportedQuestions: activeQuestionReports
        )
        let providerPreference = reason.providerPreference(defaultPreference: aiProviderPreference)
        let startedAt = Date()
        let batch = await questionEngine.generateQuestionBatch(
            for: refreshRequest,
            preference: providerPreference
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
        recordQuestionGenerationTrace(
            phase: reason.diagnosticsTitle,
            request: refreshRequest,
            providerPreference: providerPreference,
            batch: batch,
            addedQuestions: newQuestions,
            startedAt: startedAt,
            errorMessage: lastAIErrorMessage
        )
        questionBatchState = .ready
        finishQuestionGeneration(for: goal.id)
        save()
        publishShieldContext()
    }

    @discardableResult
    func refreshQuestionBatchIfNeeded(minimumUsableQuestionCount: Int? = nil) async -> Bool {
        guard goal != nil,
              questionBatchState != .generating,
              !isQuestionBankTopOffInProgress else {
            return false
        }

        let refillMinimum = minimumUsableQuestionCount ?? unlockPolicy.questionsPerSession
        let needsCoreRefill = usableQuestionCount < refillMinimum && canRefreshAfterCooldown
        let shouldRefreshProactively = isMember
            && usableQuestionCount <= ProductLimits.autoRefreshThreshold
            && canRefreshAfterCooldown

        guard needsCoreRefill || shouldRefreshProactively else { return false }

        guard isMember else {
            checkpointNotice = starterQuestionLimitMessage
            lastAIErrorMessage = starterQuestionLimitMessage
            requestMembership(for: .freshQuestionGeneration)
            save()
            return false
        }

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
        let maximumSessionQuestionCount = max(
            UnlockPolicy.maximumQuestionsPerSession,
            StopBlockingPolicy.questionsPerSession
        )
        let targetCount = min(maximumSessionQuestionCount, max(1, limit))
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

    func startUnlockSession(minutes: Int) {
        let unlockMinutes = UnlockPolicy.normalizedCorrectAnswerUnlockMinutes(minutes)
        guard unlockMinutes > 0 else { return }

        let now = Date()
        unlockSession = UnlockSession(
            startedAt: now,
            expiresAt: Calendar.current.date(byAdding: .minute, value: unlockMinutes, to: now) ?? now
        )
        SharedAppGroup.publishUnlockExpiration(unlockSession?.expiresAt)
        save()
        publishShieldContext()
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
        questionGenerationTraces = []
        unlockPolicy = .default
        questionBatchState = .idle
        aiProviderPreference = .automatic
        lastQuestionProvider = .localTemplates
        backendEndpoint = ""
        lastAIErrorMessage = nil
        isQuestionBankTopOffInProgress = false
        questionBankTopOffStartedAt = nil
        lastQuestionBankTopOffDuration = nil
        checkpointNotice = nil
        unlockSession = nil
        emergencyPassesRemaining = 1
        questionRefreshesUsed = 0
        lastAutomaticQuestionRefreshAt = nil
        isCreatingGoalProfile = false
        pendingMembershipFeature = nil
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

    func clearQuestionGenerationDiagnostics() {
        questionGenerationTraces = []
        save()
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
        unlockPolicy.questionsPerSession = UnlockPolicy.normalizedQuestionsPerSession(count)
        unlockPolicy.requiredCorrectAnswers = UnlockPolicy.normalizedRequiredCorrectAnswers(
            unlockPolicy.requiredCorrectAnswers,
            questionsPerSession: unlockPolicy.questionsPerSession
        )
        save()
        publishShieldContext()
    }

    func updateRequiredCorrectAnswers(_ count: Int) {
        unlockPolicy.requiredCorrectAnswers = UnlockPolicy.normalizedRequiredCorrectAnswers(
            count,
            questionsPerSession: unlockPolicy.questionsPerSession
        )
        save()
        publishShieldContext()
    }

    func updateMinimumQuestionDifficulty(_ difficulty: Int) {
        let shouldRegenerate = applyMinimumQuestionDifficulty(difficulty)
        guard shouldRegenerate else { return }

        Task { [weak self] in
            await self?.refreshQuestionBatch(reason: .levelUpRefill)
        }
    }

    func updateMinimumQuestionDifficultyAndRegenerate(_ difficulty: Int) async {
        let shouldRegenerate = applyMinimumQuestionDifficulty(difficulty)
        guard shouldRegenerate else { return }

        await refreshQuestionBatch(reason: .levelUpRefill)
    }

    @discardableResult
    private func applyMinimumQuestionDifficulty(_ difficulty: Int) -> Bool {
        let normalizedDifficulty = UnlockPolicy.normalizedQuestionDifficulty(difficulty)
        let previousDifficulty = activeQuestionDifficulty
        let hadActiveQuestions = !activeQuestions.isEmpty

        if var activeGoal = goal {
            activeGoal.minimumQuestionDifficulty = normalizedDifficulty
            goal = activeGoal
        } else {
            unlockPolicy.minimumQuestionDifficulty = normalizedDifficulty
        }

        let didRaiseActiveGoalDifficulty = goal != nil && normalizedDifficulty > previousDifficulty
        var shouldRegenerate = false

        if didRaiseActiveGoalDifficulty {
            retireActiveQuestionsBelowDifficulty(normalizedDifficulty)
            lastAIErrorMessage = nil

            if isMember {
                questionBatchState = .generating
                shouldRegenerate = true
            } else if hadActiveQuestions && usableQuestionCount < unlockPolicy.questionsPerSession {
                checkpointNotice = "Question level updated. Membership can prepare a fresh harder question bank when your current set is below that level."
                requestMembership(for: .freshQuestionGeneration)
            }
        }

        save()
        publishShieldContext()
        return shouldRegenerate
    }

    func acceptQuestionLevelRecommendation() async {
        guard let recommendation = questionLevelRecommendation,
              var activeGoal = goal else {
            return
        }

        guard isMember else {
            checkpointNotice = "Nice progress. Membership can keep preparing harder checkpoints for this goal."
            requestMembership(for: .freshQuestionGeneration)
            save()
            return
        }

        activeGoal.minimumQuestionDifficulty = recommendation.nextLevel
        goal = activeGoal
        retireActiveQuestionsBelowDifficulty(recommendation.nextLevel)
        lastAIErrorMessage = nil
        save()
        publishShieldContext()

        await refreshQuestionBatch(reason: .levelUpRefill)
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
            questions[index].timesCorrect = max(0, questions[index].timesCorrect - 1)
            questions[index].status = .due
            questions[index].nextReviewAt = Calendar.current.date(byAdding: .hour, value: 12, to: Date())
        case .incorrect, .unclear:
            questions[index].timesCorrect = 0
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
        for topic in competencyTopics(from: question.topic) {
            updateCompetency(topic: topic, goalID: question.goalID, questionDifficulty: question.difficulty, result: result)
        }
    }

    private func updateCompetency(
        topic: String,
        goalID: Goal.ID,
        questionDifficulty: Int,
        result: AnswerResult
    ) {
        let topicKey = competencyTopicKey(topic)
        let matchesQuestionGoal: (TopicCompetency) -> Bool = { competency in
            self.competencyTopicKey(competency.topic) == topicKey
                && (competency.goalID == goalID || (competency.goalID == nil && self.goal?.id == goalID))
        }

        if !competencies.contains(where: matchesQuestionGoal) {
            competencies.append(.initial(topic: topic, goalID: goalID))
        }

        guard let index = competencies.firstIndex(where: matchesQuestionGoal) else { return }
        competencies[index].goalID = goalID
        competencies[index].topic = topic

        competencies[index].attempts += 1
        competencies[index].lastResult = result
        competencies[index].lastPracticedAt = Date()

        let difficultyGap = Double(questionDifficulty) - competencies[index].estimatedLevel

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
        let topicKeys = Set(competencyTopics(from: topic).map(competencyTopicKey))
        let matchingCompetencies = visibleActiveCompetencies.filter { topicKeys.contains(competencyTopicKey($0.topic)) }

        return matchingCompetencies.min {
            if $0.masteryPercent == $1.masteryPercent {
                return $0.topic < $1.topic
            }
            return $0.masteryPercent < $1.masteryPercent
        } ?? .initial(topic: competencyTopics(from: topic).first ?? topic, goalID: goal?.id)
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

    private func beginQuestionGeneration(for goalID: Goal.ID) {
        guard goal?.id == goalID else { return }
        questionGenerationStartedAt = Date()
        lastQuestionGenerationDuration = nil
    }

    private func finishQuestionGeneration(for goalID: Goal.ID) {
        guard goal?.id == goalID else { return }
        if let questionGenerationStartedAt {
            lastQuestionGenerationDuration = Date().timeIntervalSince(questionGenerationStartedAt)
        }
        questionGenerationStartedAt = nil
    }

    private func beginQuestionBankTopOff(for goalID: Goal.ID) {
        guard goal?.id == goalID else { return }
        isQuestionBankTopOffInProgress = true
        questionBankTopOffStartedAt = Date()
        lastQuestionBankTopOffDuration = nil
    }

    private func finishQuestionBankTopOff(for goalID: Goal.ID) {
        guard goal?.id == goalID else { return }
        if let questionBankTopOffStartedAt {
            lastQuestionBankTopOffDuration = Date().timeIntervalSince(questionBankTopOffStartedAt)
        }
        isQuestionBankTopOffInProgress = false
        questionBankTopOffStartedAt = nil
    }

    private func replaceActiveCompetencies(with updatedCompetencies: [TopicCompetency]) {
        guard let goalID = goal?.id else { return }
        competencies.removeAll { ($0.goalID ?? goalID) == goalID }
        competencies.append(contentsOf: updatedCompetencies)
    }

    private func retireActiveQuestionsBelowDifficulty(_ difficulty: Int) {
        guard let goalID = goal?.id else { return }

        for index in questions.indices where questions[index].goalID == goalID && questions[index].difficulty < difficulty {
            questions[index].status = .retired
        }
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
            questionGenerationTraces: questionGenerationTraces,
            unlockPolicy: unlockPolicy,
            questionBatchState: questionBatchState,
            aiProviderPreference: aiProviderPreference,
            lastQuestionProvider: lastQuestionProvider,
            backendEndpoint: backendEndpoint,
            unlockSession: unlockSession,
            emergencyPassesRemaining: emergencyPassesRemaining,
            membershipTier: membershipTier,
            questionRefreshesUsed: questionRefreshesUsed,
            lastAutomaticQuestionRefreshAt: lastAutomaticQuestionRefreshAt
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    private func publishShieldContext() {
        SharedAppGroup.publishShieldContext(
            goalTitle: goal?.title,
            promptPreview: nil
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
        if !isMember, goal != nil, usableQuestionCount < unlockPolicy.questionsPerSession {
            requestMembership(for: .freshQuestionGeneration)
            save()
        }
        return nil
    }

    private func checkpointSessionUnavailableMessage(source: CheckpointSessionSource) -> String {
        if goal == nil {
            return source == .blockedApp
                ? "Checkpoint opened from a blocked app, but no goal is set yet."
                : "Create a goal before starting a checkpoint."
        }

        if activeQuestions.isEmpty {
            if !isMember {
                return "Your starter checkpoints are complete. Membership keeps fresh questions ready when you need more."
            }

            return source == .blockedApp
                ? "Checkpoint opened from a blocked app, but no questions are ready yet."
                : "No questions are ready yet."
        }

        if !isMember && usableQuestionCount == 0 {
            return "Your starter question set has done its job. Membership keeps fresh checkpoints coming."
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
        questionGenerationTraces = snapshot.questionGenerationTraces ?? []
        unlockPolicy = snapshot.unlockPolicy ?? .default
        questionBatchState = snapshot.questionBatchState ?? .idle
        aiProviderPreference = snapshot.aiProviderPreference ?? .automatic
        lastQuestionProvider = snapshot.lastQuestionProvider ?? .localTemplates
        backendEndpoint = snapshot.backendEndpoint ?? ""
        unlockSession = snapshot.unlockSession
        emergencyPassesRemaining = snapshot.emergencyPassesRemaining
        membershipTier = snapshot.membershipTier ?? .starter
        pendingMembershipFeature = nil
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

    }

    private func initialCompetencies(for goal: Goal, questions: [CheckpointQuestion]) -> [TopicCompetency] {
        let questionTopics = questions
            .filter { $0.status != .retired }
            .flatMap { competencyTopics(from: $0.topic) }
        let context = GoalQuestionContext(goal: goal)
        let seedTopics: [String]

        if context.needsGeneratedSkillMap {
            seedTopics = questionTopics
        } else {
            let contextTopics = context.contentTopics.flatMap(competencyTopics)
            seedTopics = contextTopics + questionTopics
        }

        let topics = uniqueCompetencyTopics(seedTopics).sorted()

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
        let existingByTopic = Dictionary(grouping: existing, by: { competencyTopicKey($0.topic) })

        return newCompetencies.map { competency in
            guard var existingCompetency = existingByTopic[competencyTopicKey(competency.topic)]?.first else {
                return competency
            }

            existingCompetency.topic = competency.topic
            existingCompetency.goalID = competency.goalID
            return existingCompetency
        }
    }

    private func mergedCompetenciesForDisplay(_ competencies: [TopicCompetency]) -> [TopicCompetency] {
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

    private func mergedCompetency(_ lhs: TopicCompetency, with rhs: TopicCompetency) -> TopicCompetency {
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

    private func competencyTopics(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n")
        let topics = text
            .components(separatedBy: separators)
            .map(normalizedCompetencyTopic)
            .filter { !$0.isEmpty }

        let fallback = normalizedCompetencyTopic(text)
        return uniqueCompetencyTopics(topics.isEmpty ? [fallback] : topics)
    }

    private func uniqueCompetencyTopics(_ topics: [String]) -> [String] {
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

    private func normalizedCompetencyTopic(_ topic: String) -> String {
        topic
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .:-"))
    }

    private func competencyTopicKey(_ topic: String) -> String {
        normalizedCompetencyTopic(topic).lowercased()
    }

    private func questionTopicKey(_ topic: String) -> String {
        competencyTopics(from: topic)
            .map(competencyTopicKey)
            .sorted()
            .joined(separator: "+")
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "under 1s"
        }

        return "\(Int(duration.rounded()))s"
    }

    private func recordQuestionGenerationTrace(
        phase: String,
        request: QuestionGenerationRequest,
        providerPreference: AIProviderKind,
        batch: QuestionBatch,
        addedQuestions: [CheckpointQuestion],
        retiredQuestionCount: Int = 0,
        startedAt: Date,
        errorMessage: String?
    ) {
        let previewQuestions = Array((addedQuestions.isEmpty ? batch.questions : addedQuestions)
            .prefix(Self.maximumQuestionGenerationPreviewCount))
            .map(Self.questionPreview)

        let trace = QuestionGenerationTrace(
            phase: phase,
            goalID: request.goal.id,
            goalTitle: request.goal.title,
            providerPreference: providerPreference,
            resolvedProvider: batch.provider,
            usedFallback: batch.usedFallback,
            targetCount: request.targetCount,
            existingQuestionCount: request.existingQuestions.count,
            reportedQuestionCount: request.reportedQuestions.count,
            competencyCount: request.competencies.count,
            minimumDifficulty: request.minimumDifficulty,
            generatedQuestionCount: batch.questions.count,
            addedQuestionCount: addedQuestions.count,
            retiredQuestionCount: retiredQuestionCount,
            duration: Date().timeIntervalSince(startedAt),
            sourcePrompt: batch.questions.first?.sourcePrompt ?? request.sourcePrompt(provider: batch.provider),
            errorMessage: errorMessage,
            questions: previewQuestions
        )

        questionGenerationTraces.insert(trace, at: 0)
        if questionGenerationTraces.count > Self.maximumQuestionGenerationTraceCount {
            questionGenerationTraces = Array(questionGenerationTraces.prefix(Self.maximumQuestionGenerationTraceCount))
        }
    }

    private static func questionPreview(_ question: CheckpointQuestion) -> QuestionGenerationQuestionPreview {
        QuestionGenerationQuestionPreview(
            prompt: question.prompt,
            expectedAnswer: question.expectedAnswer,
            choices: question.choices,
            explanation: question.explanation,
            topic: question.topic,
            difficulty: question.difficulty
        )
    }

    private static func exportText(for trace: QuestionGenerationTrace) -> String {
        let date = ISO8601DateFormatter().string(from: trace.createdAt)
        let questionText = trace.questions.enumerated().map { index, question in
            """
            Question \(index + 1)
            Topic: \(question.topic)
            Difficulty: \(question.difficulty)
            Prompt: \(question.prompt)
            Choices: \(question.choices.joined(separator: " | "))
            Expected answer: \(question.expectedAnswer)
            Explanation: \(question.explanation)
            """
        }.joined(separator: "\n\n")

        return """
        \(trace.phase) at \(date)
        Goal: \(trace.goalTitle)
        Provider preference: \(trace.providerPreference.rawValue)
        Resolved provider: \(trace.resolvedProvider.rawValue)
        Used fallback: \(trace.usedFallback)
        Target count: \(trace.targetCount)
        Existing questions: \(trace.existingQuestionCount)
        Reported questions: \(trace.reportedQuestionCount)
        Competencies: \(trace.competencyCount)
        Minimum difficulty: \(trace.minimumDifficulty)
        Generated: \(trace.generatedQuestionCount)
        Added: \(trace.addedQuestionCount)
        Retired: \(trace.retiredQuestionCount)
        Duration: \(formattedDuration(trace.duration))
        Error: \(trace.errorMessage ?? "None")

        Source prompt:
        \(trace.sourcePrompt)

        Generated question previews:
        \(questionText.isEmpty ? "None" : questionText)
        """
    }

    private func questionKey(_ question: CheckpointQuestion) -> String {
        "\(questionTopicKey(question.topic))::\(question.prompt.lowercased())"
    }

    private func estimatedStartingLevel(for topic: String, goal: Goal) -> Double {
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
        reportedQuestions: [QuestionQualityReport],
        targetCount: Int? = nil
    ) -> QuestionGenerationRequest {
        QuestionGenerationRequest(
            goal: goal,
            existingQuestions: existingQuestions,
            competencies: competencies,
            reportedQuestions: reportedQuestions,
            targetCount: targetCount ?? questionBankTargetCount,
            minimumDifficulty: goal.minimumQuestionDifficulty,
            backendEndpoint: resolvedBackendEndpoint,
            backendAuthorizationToken: resolvedBackendAuthorizationToken
        )
    }

    private var resolvedBackendEndpoint: URL? {
        guard let endpoint = firstConfiguredBackendValue(
            storedValue: backendEndpoint,
            infoKey: "CheckpointAIBackendEndpoint",
            environmentKey: "CHECKPOINT_AI_BACKEND_ENDPOINT"
        ) else {
            return nil
        }

        return URL(string: endpoint)
    }

    private var resolvedBackendAuthorizationToken: String? {
        firstConfiguredBackendValue(
            storedValue: nil,
            infoKey: "CheckpointAIBackendToken",
            environmentKey: "CHECKPOINT_AI_BACKEND_TOKEN"
        )
    }

    private func firstConfiguredBackendValue(
        storedValue: String?,
        infoKey: String,
        environmentKey: String
    ) -> String? {
        let candidates = [
            storedValue,
            ProcessInfo.processInfo.environment[environmentKey],
            Bundle.main.object(forInfoDictionaryKey: infoKey) as? String
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { value in
                !value.isEmpty && !value.contains("$(")
            }
    }

    private var canRefreshAfterCooldown: Bool {
        guard let lastAutomaticQuestionRefreshAt else { return true }
        return Date().timeIntervalSince(lastAutomaticQuestionRefreshAt) >= ProductLimits.autoRefreshCooldown
    }

    private var starterQuestionLimitMessage: String {
        "Your first goal includes a starter question set. Membership keeps fresh checkpoints ready after that set runs low."
    }
}
