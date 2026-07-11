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
    var unlockEvents: [UnlockEvent] = []
    var questionReports: [QuestionQualityReport] = []
    var issueReports: [UserIssueReport] = []
    var questionGenerationTraces: [QuestionGenerationTrace] = []
    var unlockPolicy: UnlockPolicy = .default
    var questionBatchState: QuestionBatchState = .idle
    var aiProviderPreference: AIProviderKind = .automatic
    var lastQuestionProvider: AIProviderKind = .automatic
    var backendEndpoint = ""
    var lastAIErrorMessage: String?
    var lastQuestionGenerationFailure: QuestionGenerationFailureKind?
    var questionGenerationStartedAt: Date?
    var lastQuestionGenerationDuration: TimeInterval?
    var isQuestionBankTopOffInProgress = false
    var questionBankTopOffStartedAt: Date?
    var lastQuestionBankTopOffDuration: TimeInterval?
    var checkpointNotice: String?
    var unlockSession: UnlockSession?
    var checkpointRetryCooldownUntil: Date?
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
    @ObservationIgnored private static let urgentRefillTargetMultiplier = 2
    @ObservationIgnored private static let maximumQuestionGenerationTraceCount = 20
    @ObservationIgnored private static let maximumQuestionGenerationPreviewCount = 12
    @ObservationIgnored private static let levelUpRecentAttemptWindow = 10
    @ObservationIgnored private static let levelUpMinimumAttemptCount = 5
    @ObservationIgnored private static let levelUpAccuracyThreshold = 0.90
    @ObservationIgnored private static let maximumExactQuestionAskCount = 2
    @ObservationIgnored private static let failedCheckpointCooldown: TimeInterval = 5 * 60
    @ObservationIgnored private static let questionBankTopOffWaitIntervalNanoseconds: UInt64 = 100_000_000
    @ObservationIgnored private static let questionBankTopOffWaitAttemptCount = 10

    // MARK: - Lifecycle

    init(
        questionEngine: HybridQuestionEngine = HybridQuestionEngine(),
        defaults: UserDefaults = .standard
    ) {
        self.questionEngine = questionEngine
        self.defaults = defaults
        load()
        clearExpiredCheckpointRetryCooldown()
        recoverTransientQuestionGenerationState()
        isOnboardingPresented = goal == nil
        publishShieldContext()
        removeLegacyLocalQuestionBankIfNeeded()
        resumeQuestionBankMaintenanceIfNeeded()
    }

    // MARK: - Derived state

    var activeUnlockMinutesRemaining: Int {
        guard let unlockSession, unlockSession.isActive else { return 0 }
        return max(0, Int(ceil(unlockSession.expiresAt.timeIntervalSinceNow / 60)))
    }

    var checkpointRetryCooldownRemainingSeconds: Int {
        guard let checkpointRetryCooldownUntil else { return 0 }
        return max(0, Int(ceil(checkpointRetryCooldownUntil.timeIntervalSinceNow)))
    }

    var checkpointRetryCooldownRemainingText: String {
        Self.formattedRetryCooldownDuration(TimeInterval(checkpointRetryCooldownRemainingSeconds))
    }

    var isCheckpointRetryCooldownActive: Bool {
        checkpointRetryCooldownRemainingSeconds > 0
    }

    var questionsAnsweredThisWeekCount: Int {
        weeklyTotalMetrics.questionsAnswered
    }

    var questionAccuracyThisWeekText: String {
        weeklyTotalMetrics.accuracyText
    }

    var weeklyTotalMetrics: WeeklyMetricsSummary {
        weeklyMetricsSummary(
            id: WeeklyMetricsSummary.allGoalsID,
            title: "All goals",
            goalID: nil,
            isCurrentGoal: false
        )
    }

    var weeklyActiveGoalMetrics: WeeklyMetricsSummary? {
        guard let goal else { return nil }
        return weeklyMetricsSummary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true
        )
    }

    var weeklyGoalMetrics: [WeeklyMetricsSummary] {
        availableGoalProfiles.map { profile in
            weeklyMetricsSummary(
                id: profile.id.uuidString,
                title: profile.title,
                goalID: profile.id,
                isCurrentGoal: profile.id == goal?.id
            )
        }
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

    var issueReportCount: Int {
        issueReports.count
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

    private var attemptsThisWeek: [CheckpointAttempt] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return attempts.filter { week.contains($0.createdAt) }
    }

    var activeCompetencies: [TopicCompetency] {
        guard let goalID = goal?.id else { return [] }
        return competencies.filter { $0.goalID == goalID || $0.goalID == nil }
    }

    var visibleActiveCompetencies: [TopicCompetency] {
        mergedCompetenciesForDisplay(activeCompetencies)
    }

    private func weeklyMetricsSummary(
        id: String,
        title: String,
        goalID: Goal.ID?,
        isCurrentGoal: Bool
    ) -> WeeklyMetricsSummary {
        let weeklyAttempts = attemptsThisWeek.filter { attempt in
            guard let goalID else { return true }
            return attempt.goalID == goalID
        }
        let correctAnswers = weeklyAttempts.filter { $0.result == .correct }.count
        let missedAnswers = weeklyAttempts.filter { $0.result != .correct }.count
        let competencies = visibleCompetencies(for: goalID)
        let scopedUnlockEvents = unlockEvents.filter { event in
            guard let goalID else { return true }
            return event.goalID == goalID
        }
        let weeklyUnlockEvents = scopedUnlockEvents.filter { event in
            guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return false }
            return week.contains(event.createdAt)
        }
        let skillHighlights = skillHighlights(for: competencies)

        return WeeklyMetricsSummary(
            id: id,
            title: title,
            questionsAnswered: weeklyAttempts.count,
            correctAnswers: correctAnswers,
            missedAnswers: missedAnswers,
            checkpointStreakDays: checkpointStreakDays(for: scopedUnlockEvents),
            checkpointsCleared: weeklyUnlockEvents.count,
            strongestSkill: skillHighlights.strongest,
            reviewSkill: skillHighlights.review,
            isCurrentGoal: isCurrentGoal
        )
    }

    private func checkpointStreakDays(for unlockEvents: [UnlockEvent]) -> Int {
        let calendar = Calendar.current
        let clearedDays = Set(unlockEvents.map { calendar.startOfDay(for: $0.createdAt) })
        guard !clearedDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        guard var cursor = clearedDays.contains(today) ? today : (clearedDays.contains(yesterday) ? yesterday : nil) else {
            return 0
        }

        var streak = 0
        while clearedDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }

        return streak
    }

    private func skillHighlights(
        for competencies: [TopicCompetency]
    ) -> (strongest: String?, review: String?) {
        let practicedCompetencies = competencies.filter { $0.attempts > 0 }
        guard !practicedCompetencies.isEmpty else { return (nil, nil) }

        let sortedCompetencies = practicedCompetencies.sorted { lhs, rhs in
            if lhs.masteryPercent == rhs.masteryPercent {
                return lhs.topic.localizedCaseInsensitiveCompare(rhs.topic) == .orderedAscending
            }

            return lhs.masteryPercent < rhs.masteryPercent
        }

        return (sortedCompetencies.last?.topic, sortedCompetencies.first?.topic)
    }

    private func visibleCompetencies(for goalID: Goal.ID?) -> [TopicCompetency] {
        guard let goalID else {
            return mergedCompetenciesForDisplay(competencies)
        }

        return mergedCompetenciesForDisplay(
            competencies.filter { $0.goalID == goalID || $0.goalID == nil }
        )
    }

    private func averageMasteryPercent(for competencies: [TopicCompetency]) -> Int {
        guard !competencies.isEmpty else { return 0 }
        let total = competencies.reduce(0) { $0 + $1.masteryPercent }
        return total / competencies.count
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
        !isMember
            && goal != nil
            && hasConsumedStarterPractice
            && readyQuestionCount <= ProductLimits.autoRefreshThreshold
    }

    var usableQuestionCount: Int {
        activeQuestions.filter(isSelectableQuestion).filter(meetsDifficultyFloor).count
    }

    private var hasConsumedStarterPractice: Bool {
        !activeAttempts.isEmpty
            || activeQuestions.contains { question in
                question.timesAsked > 0 || question.status == .retired
            }
    }

    var readyQuestionCount: Int {
        guard let goal else { return 0 }
        return readyQuestionCount(for: goal)
    }

    var hasReadyCheckpointSet: Bool {
        goal != nil && nextQuestions(limit: unlockPolicy.questionsPerSession).count >= unlockPolicy.questionsPerSession
    }

    func usableQuestionCount(for profile: Goal) -> Int {
        questions.filter { question in
            question.goalID == profile.id
                && isSelectableQuestion(question)
                && question.difficulty >= profile.minimumQuestionDifficulty
        }.count
    }

    private func readyQuestionCount(for profile: Goal, allowsEarlyCorrectReuse: Bool = false) -> Int {
        let now = Date()
        return questions.filter { question in
            question.goalID == profile.id
                && question.difficulty >= profile.minimumQuestionDifficulty
                && isReadyQuestionBankCandidate(
                    question,
                    now: now,
                    allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
                )
        }.count
    }

    private func questionBankDeficit(
        for profile: Goal,
        targetCount: Int? = nil,
        allowsEarlyCorrectReuse: Bool = false
    ) -> Int {
        max(
            0,
            (targetCount ?? questionBankTargetCount) - readyQuestionCount(
                for: profile,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
            )
        )
    }

    func questionBankReadinessWarning(for profile: Goal) -> String? {
        let readyCount = readyQuestionCount(for: profile)

        guard readyCount < unlockPolicy.questionsPerSession else { return nil }

        if backgroundGenerationGoalIDs.contains(profile.id) || questionBankTopOffGoalIDs.contains(profile.id) {
            return readyCount > 0 ? "Preparing more practice" : "Preparing practice"
        }

        return readyCount > 0 ? "Practice set low" : "No practice ready yet"
    }

    var isPreparingActiveGoalQuestions: Bool {
        goal != nil
            && !hasReadyCheckpointSet
            && (questionBatchState == .generating || isQuestionBankTopOffInProgress)
    }

    var isQuestionGenerationBlockingPractice: Bool {
        questionBatchState == .failed && !hasReadyCheckpointSet
    }

    var questionGenerationStatusText: String {
        if isQuestionBankTopOffInProgress {
            if hasReadyCheckpointSet {
                return "Practice is ready."
            }
            return usableQuestionCount > 0
                ? "Getting your next checkpoint ready."
                : "Getting your checkpoint ready. You can leave this screen."
        }

        switch questionBatchState {
        case .generating:
            if hasReadyCheckpointSet {
                return "Practice is ready."
            }
            if usableQuestionCount > 0 {
                return "Getting your next checkpoint ready."
            }
            return "Getting your first checkpoint ready. Your goal is saved, so you can leave this screen."
        case .failed:
            return lastQuestionGenerationFailure?.message
                ?? "Your checkpoint isn't ready yet. Try again in a little while."
        case .ready:
            return "Practice is ready."
        case .idle:
            return usableQuestionCount > 0 ? "Practice is ready." : "Your first checkpoint isn't ready yet."
        }
    }

    var studyAssistSummary: String {
        guard isMember else {
            return "Free includes your first goal. Pro keeps new checkpoints available as you keep practicing."
        }

        if let focus = studyFocusRecommendation {
            return focus
        }

        return "Your practice rhythm is steady. Keep completing sets and missed topics will surface automatically."
    }

    var studyFocusRecommendation: String? {
        guard isMember, goal != nil else { return nil }

        if let missedTopic = activeQuestions
            .filter({ $0.status == .incorrect })
            .sorted(by: sortByReviewPriority)
            .first?
            .topic {
            return "\(missedTopic) has a few missed questions ready for review."
        }

        guard let competency = sortedCompetencies.first else { return nil }

        if competency.attempts == 0 {
            return "Start with \(competency.topic) to build your progress."
        }

        return "\(competency.topic) would benefit from another pass."
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

    @discardableResult
    func switchActiveGoal(to goalID: Goal.ID) -> Bool {
        guard let selectedGoal = availableGoalProfiles.first(where: { $0.id == goalID }) else { return false }
        guard selectedGoal.id == goal?.id || canUse(.goalProfiles) else {
            requestMembership(for: .goalProfiles)
            return false
        }

        goal = selectedGoal
        if hasLegacyLocalQuestionBank(for: selectedGoal) {
            clearQuestionBank(for: selectedGoal.id)
        }

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
                await self?.prepareProtectionReviewQuestionBankIfNeeded()
            }
        } else {
            prepareInitialQuestionsInBackground(for: selectedGoal)
        }
        return true
    }

    @discardableResult
    func deleteGoalProfile(_ goalID: Goal.ID) -> Bool {
        guard let deletedGoal = availableGoalProfiles.first(where: { $0.id == goalID }) else { return false }

        let wasActiveGoal = goal?.id == goalID
        backgroundGenerationGoalIDs.remove(goalID)
        questionBankTopOffGoalIDs.remove(goalID)
        removeGoalData(for: goalID, includeLegacyCompetencies: wasActiveGoal)
        goalProfiles.removeAll { $0.id == goalID }

        if wasActiveGoal {
            let replacementGoal = goalProfiles
                .sorted { $0.createdAt > $1.createdAt }
                .first
            goal = replacementGoal
            unlockSession = nil
            SharedAppGroup.publishUnlockExpiration(nil)

            if let replacementGoal {
                let hasReplacementQuestions = questions.contains { question in
                    question.goalID == replacementGoal.id && question.status != .retired
                }
                let isPreparingReplacementQuestions = backgroundGenerationGoalIDs.contains(replacementGoal.id)
                    || questionBankTopOffGoalIDs.contains(replacementGoal.id)
                questionBatchState = hasReplacementQuestions ? .ready : .generating
                isQuestionBankTopOffInProgress = questionBankTopOffGoalIDs.contains(replacementGoal.id)
                questionBankTopOffStartedAt = isQuestionBankTopOffInProgress ? questionBankTopOffStartedAt ?? Date() : nil

                if !hasReplacementQuestions && !isPreparingReplacementQuestions {
                    prepareInitialQuestionsInBackground(for: replacementGoal)
                }
            } else {
                questionBatchState = .idle
                isQuestionBankTopOffInProgress = false
                questionBankTopOffStartedAt = nil
                isOnboardingPresented = true
            }
        }

        checkpointNotice = "\(deletedGoal.title) was deleted."
        pendingMembershipFeature = nil
        isCreatingGoalProfile = false
        save()
        publishShieldContext()
        return true
    }

    private func removeLegacyLocalQuestionBankIfNeeded() {
        guard let goal,
              hasLegacyLocalQuestionBank(for: goal) else {
            return
        }

        clearQuestionBank(for: goal.id)
        questionBatchState = .generating
        isQuestionBankTopOffInProgress = false
        questionBankTopOffStartedAt = nil
        lastAIErrorMessage = nil
        lastQuestionGenerationFailure = nil
        save()
        publishShieldContext()
        prepareInitialQuestionsInBackground(for: goal)
    }

    private func hasLegacyLocalQuestionBank(for profile: Goal) -> Bool {
        lastQuestionProvider == .localTemplates
            && questions.contains { question in
                question.goalID == profile.id && question.status != .retired
            }
    }

    private func clearQuestionBank(for goalID: Goal.ID) {
        questions.removeAll { $0.goalID == goalID }
        competencies.removeAll { $0.goalID == goalID }
    }

    // MARK: - Plan access

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
        guard membershipTier != tier else {
            if pendingMembershipFeature != nil {
                pendingMembershipFeature = nil
                save()
                publishShieldContext()
            }
            return
        }

        membershipTier = tier
        pendingMembershipFeature = nil
        save()
        publishShieldContext()

        if tier == .member, goal != nil {
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
            checkpointNotice = "Free includes one goal. Pro unlocks up to 5 goals with separate progress for each."
            requestMembership(for: .goalProfiles)
            save()
            return
        }

        let newGoal = Goal(
            title: normalizedTitle,
            deadline: max(deadline, Date()),
            category: category ?? .custom,
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
            removeGoalData(for: previousGoalID, includeLegacyCompetencies: true)
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
        lastQuestionGenerationFailure = nil
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
            targetCount: unlockPolicy.questionsPerSession
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
        let hasReadyInitialSet = batch.questions.count >= unlockPolicy.questionsPerSession
        if !hasReadyInitialSet {
            let failure = batch.failure ?? .qualityRejected
            lastQuestionGenerationFailure = failure
            lastAIErrorMessage = failure.message
        } else {
            lastQuestionGenerationFailure = nil
            lastAIErrorMessage = nil
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
            questionBatchState = hasReadyInitialSet ? .ready : .failed
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

    private func initialBatchProviderPreference(for _: QuestionGenerationRequest) -> AIProviderKind {
        aiProviderPreference
    }

    private func generateCheckpointReadyBatch(
        for request: QuestionGenerationRequest,
        preference: AIProviderKind
    ) async -> QuestionBatch {
        await questionEngine.generateQuestionBatch(
            for: request,
            preference: preference
        )
    }

    func retryInitialQuestionGeneration() async {
        guard let goal else { return }
        await generateInitialQuestionBatch(for: goal)
    }

    private func topOffQuestionBankInBackground(
        for goal: Goal,
        starterQuestionIDs: Set<CheckpointQuestion.ID> = []
    ) {
        guard !questionBankTopOffGoalIDs.contains(goal.id) else { return }

        questionBankTopOffGoalIDs.insert(goal.id)
        if self.goal?.id == goal.id {
            beginQuestionBankTopOff(for: goal.id)
        }

        Task { [weak self] in
            await self?.topOffQuestionBank(for: goal, starterQuestionIDs: starterQuestionIDs)
        }
    }

    private func scheduleQuestionBankMaintenanceIfNeeded(for targetGoal: Goal) {
        guard isMember,
              readyQuestionCount(for: targetGoal) <= ProductLimits.autoRefreshThreshold,
              questionBankDeficit(for: targetGoal) > 0,
              !questionBankTopOffGoalIDs.contains(targetGoal.id) else {
            return
        }

        topOffQuestionBankInBackground(for: targetGoal)
    }

    private func topOffQuestionBank(
        for targetGoal: Goal,
        starterQuestionIDs: Set<CheckpointQuestion.ID>
    ) async {
        defer {
            questionBankTopOffGoalIDs.remove(targetGoal.id)
            if goal?.id == targetGoal.id {
                finishQuestionBankTopOff(for: targetGoal.id)
            }
        }

        guard goalProfiles.contains(where: { $0.id == targetGoal.id }) || goal?.id == targetGoal.id else { return }
        guard isMember || !starterQuestionIDs.isEmpty else {
            if goal?.id == targetGoal.id {
                checkpointNotice = starterQuestionLimitMessage
                requestMembership(for: .freshQuestionGeneration)
                save()
            }
            return
        }

        let existingQuestions = questions.filter { $0.goalID == targetGoal.id }
        let existingCompetencies = competencies.filter { ($0.goalID ?? targetGoal.id) == targetGoal.id }
        let remainingTargetCount = questionBankDeficit(for: targetGoal)

        guard remainingTargetCount > 0 else { return }

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

        guard let currentTargetGoal = availableGoalProfiles.first(where: { $0.id == targetGoal.id }) ?? (goal?.id == targetGoal.id ? goal : nil),
              currentTargetGoal.minimumQuestionDifficulty == targetGoal.minimumQuestionDifficulty else {
            save()
            publishShieldContext()
            return
        }

        let existingKeys = Set(existingQuestions.map { questionKey($0) })
        let newQuestions = batch.questions.filter {
            $0.difficulty >= currentTargetGoal.minimumQuestionDifficulty
                && !existingKeys.contains(questionKey($0))
        }
        questions.append(contentsOf: newQuestions)
        let goalQuestions = questions.filter { $0.goalID == targetGoal.id }
        competencies.removeAll { $0.goalID == targetGoal.id }
        competencies.append(contentsOf: initialCompetencies(for: targetGoal, questions: goalQuestions))
        if !newQuestions.isEmpty {
            lastQuestionProvider = batch.provider
            lastQuestionGenerationFailure = nil
            lastAIErrorMessage = nil
        } else if let failure = batch.failure {
            lastQuestionGenerationFailure = failure
            lastAIErrorMessage = failure.message
        }
        recordQuestionGenerationTrace(
            phase: "Question bank top-off",
            request: topOffRequest,
            providerPreference: aiProviderPreference,
            batch: batch,
            addedQuestions: newQuestions,
            retiredQuestionCount: 0,
            startedAt: startedAt,
            errorMessage: lastAIErrorMessage
        )
        if goal?.id == targetGoal.id {
            questionBatchState = readyQuestionCount(for: currentTargetGoal) >= unlockPolicy.questionsPerSession
                ? .ready
                : .failed
        }
        save()
        publishShieldContext()
    }

    func refreshQuestionBatch() async {
        await refreshQuestionBatch(reason: .manual)
    }

    private func refreshQuestionBatch(reason: QuestionRefreshReason, targetCount: Int? = nil) async {
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
            reportedQuestions: activeQuestionReports,
            targetCount: targetCount
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
            let failure = batch.failure ?? .qualityRejected
            lastQuestionGenerationFailure = failure
            lastAIErrorMessage = failure.message
        } else {
            lastQuestionGenerationFailure = nil
            lastAIErrorMessage = nil
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
        questionBatchState = hasReadyCheckpointSet ? .ready : .failed
        finishQuestionGeneration(for: goal.id)
        save()
        publishShieldContext()
    }

    @discardableResult
    func refreshQuestionBatchIfNeeded(
        minimumUsableQuestionCount: Int? = nil,
        allowsEarlyCorrectReuse: Bool = false
    ) async -> Bool {
        guard let goal,
              questionBatchState != .generating else {
            return false
        }

        let refillMinimum = minimumUsableQuestionCount ?? unlockPolicy.questionsPerSession
        let needsCoreRefill = needsQuestionRefill(
            minimumQuestionCount: refillMinimum,
            allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
        )
        guard needsCoreRefill || !isQuestionBankTopOffInProgress else {
            return false
        }

        let shouldRefreshProactively = isMember
            && readyQuestionCount <= ProductLimits.autoRefreshThreshold
            && questionBankDeficit(for: goal, allowsEarlyCorrectReuse: allowsEarlyCorrectReuse) > 0
            && canRefreshAfterCooldown

        guard needsCoreRefill || shouldRefreshProactively else { return false }

        guard isMember else {
            if hasConsumedStarterPractice {
                checkpointNotice = starterQuestionLimitMessage
                lastAIErrorMessage = starterQuestionLimitMessage
                requestMembership(for: .freshQuestionGeneration)
                save()
            }
            return false
        }

        if needsCoreRefill {
            let readyCount = readyQuestionCount(
                for: goal,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
            )
            let urgentTargetCount = max(
                Self.initialCheckpointReadyTargetCount * Self.urgentRefillTargetMultiplier,
                refillMinimum - readyCount
            )
            await refreshQuestionBatch(
                reason: .automaticCoreRefill,
                targetCount: urgentTargetCount
            )
            scheduleQuestionBankMaintenanceIfNeeded(for: goal)
        } else {
            lastAutomaticQuestionRefreshAt = Date()
            if QuestionRefreshReason.automaticProactiveRefill.countsAsRefresh(isMember: isMember) {
                questionRefreshesUsed += 1
            }
            save()
            topOffQuestionBankInBackground(for: goal)
        }
        return true
    }

    @discardableResult
    func prepareProtectionReviewQuestionBankIfNeeded() async -> Bool {
        guard isMember else { return false }
        return await refreshQuestionBatchIfNeeded(
            minimumUsableQuestionCount: StopBlockingPolicy.questionsPerSession,
            allowsEarlyCorrectReuse: true
        )
    }

    // MARK: - Question selection

    func nextQuestion() -> CheckpointQuestion? {
        nextQuestion(excluding: [])
    }

    func nextCheckpointSession() -> CheckpointSession? {
        nextCheckpointSession(requiresFullSet: false)
    }

    private func nextCheckpointSession(requiresFullSet: Bool) -> CheckpointSession? {
        let questionCount = unlockPolicy.questionsPerSession
        let selectedQuestions = nextQuestions(limit: questionCount)
        guard !selectedQuestions.isEmpty else { return nil }
        guard !requiresFullSet || selectedQuestions.count >= questionCount else { return nil }

        return CheckpointSession(
            questions: selectedQuestions,
            requiredCorrectAnswers: unlockPolicy.requiredCorrectAnswers
        )
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
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
              ) {
            selectedQuestions.append(question)
            excludedQuestionIDs.insert(question.id)
        }

        return selectedQuestions
    }

    private func needsQuestionRefill(
        minimumQuestionCount: Int,
        allowsEarlyCorrectReuse: Bool = false
    ) -> Bool {
        usableQuestionCount < minimumQuestionCount
            || nextQuestions(
                limit: minimumQuestionCount,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
            ).count < minimumQuestionCount
    }

    private func nextQuestion(
        excluding excludedQuestionIDs: Set<CheckpointQuestion.ID>,
        allowsEarlyCorrectReuse: Bool = false
    ) -> CheckpointQuestion? {
        let availableQuestions = activeQuestions.filter { !excludedQuestionIDs.contains($0.id) }
        let preferredQuestions = availableQuestions.filter(meetsDifficultyFloor)
        return prioritizedNonCorrectQuestion(from: preferredQuestions)
            ?? prioritizedNonCorrectQuestion(from: availableQuestions)
            ?? prioritizedCorrectQuestion(from: preferredQuestions, allowsEarlyCorrectReuse: allowsEarlyCorrectReuse)
            ?? prioritizedCorrectQuestion(from: availableQuestions, allowsEarlyCorrectReuse: allowsEarlyCorrectReuse)
    }

    private func prioritizedNonCorrectQuestion(from availableQuestions: [CheckpointQuestion]) -> CheckpointQuestion? {
        let now = Date()
        let selectableQuestions = availableQuestions
            .filter(isSelectableQuestion)
            .filter { $0.status != .correct }

        if let missed = selectableQuestions
            .filter({ $0.status == .incorrect && ($0.nextReviewAt ?? .distantPast) <= now })
            .sorted(by: sortByReviewPriority)
            .first {
            return missed
        }

        if let due = selectableQuestions
            .filter({ ($0.nextReviewAt ?? .distantFuture) <= now })
            .sorted(by: sortByReviewPriority)
            .first {
            return due
        }

        let weakAreaQuestion = selectableQuestions
            .filter { $0.status == .new }
            .sorted(by: sortByAdaptivePriority)
            .first

        if let weakAreaQuestion {
            return weakAreaQuestion
        }

        if let reviewQuestion = selectableQuestions
            .filter({ $0.status != .correct })
            .sorted(by: sortByReviewPriority)
            .first {
            return reviewQuestion
        }

        return nil
    }

    private func prioritizedCorrectQuestion(
        from availableQuestions: [CheckpointQuestion],
        allowsEarlyCorrectReuse: Bool = false
    ) -> CheckpointQuestion? {
        let now = Date()
        let selectableQuestions = availableQuestions
            .filter(isSelectableQuestion)
            .filter { $0.status == .correct }

        let reusableCorrectQuestions = selectableQuestions
            .filter { canReuseCorrectQuestion($0, now: now) }
            .sorted(by: sortByCorrectReusePriority)
            .first

        if let reusableCorrectQuestions {
            return reusableCorrectQuestions
        }

        guard allowsEarlyCorrectReuse else { return nil }

        return selectableQuestions
            .sorted(by: sortByCorrectReusePriority)
            .first
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
            recordUnlockSession(minutes: unlockMinutes, goalID: goal.id)
        }

        scheduleQuestionBankMaintenanceIfNeeded(for: goal)
        save()
        publishShieldContext()
        return unlockMinutes
    }

    func startUnlockSession(minutes: Int) {
        let unlockMinutes = UnlockPolicy.normalizedCorrectAnswerUnlockMinutes(minutes)
        guard unlockMinutes > 0, let goalID = goal?.id else { return }

        recordUnlockSession(minutes: unlockMinutes, goalID: goalID)
        save()
        publishShieldContext()
    }

    private func recordUnlockSession(minutes: Int, goalID: Goal.ID) {
        let now = Date()
        unlockSession = UnlockSession(
            startedAt: now,
            expiresAt: Calendar.current.date(byAdding: .minute, value: minutes, to: now) ?? now
        )
        unlockEvents.insert(UnlockEvent(goalID: goalID, minutes: minutes, createdAt: now), at: 0)
        SharedAppGroup.publishUnlockExpiration(unlockSession?.expiresAt)
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
        unlockEvents = []
        questionReports = []
        issueReports = []
        questionGenerationTraces = []
        unlockPolicy = .default
        questionBatchState = .idle
        aiProviderPreference = .automatic
        lastQuestionProvider = .automatic
        backendEndpoint = ""
        lastAIErrorMessage = nil
        lastQuestionGenerationFailure = nil
        isQuestionBankTopOffInProgress = false
        questionBankTopOffStartedAt = nil
        lastQuestionBankTopOffDuration = nil
        checkpointNotice = nil
        unlockSession = nil
        checkpointRetryCooldownUntil = nil
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
        guard SharedAppGroup.pendingShieldAttemptDate != nil else { return nil }
        if let cooldownMessage = checkpointRetryCooldownMessage(source: .blockedApp) {
            checkpointNotice = cooldownMessage
            return nil
        }

        guard let session = checkpointSession(source: .blockedApp) else { return nil }
        guard SharedAppGroup.consumePendingShieldAttempt() != nil else { return nil }
        return session
    }

    func startManualCheckpointSession() -> CheckpointSession? {
        checkpointSession(source: .manual)
    }

    func startPreviewCheckpointSession() -> CheckpointSession? {
        checkpointSession(source: .manual, purpose: .preview)
    }

    func preparePendingShieldSession() async -> CheckpointSession? {
        guard SharedAppGroup.pendingShieldAttemptDate != nil else { return nil }

        if let cooldownMessage = checkpointRetryCooldownMessage(source: .blockedApp) {
            checkpointNotice = cooldownMessage
            return nil
        }

        if goal != nil && needsQuestionRefill(minimumQuestionCount: unlockPolicy.questionsPerSession) {
            _ = await refreshQuestionBatchIfNeeded()
        }

        if let session = takePendingShieldSession() {
            return session
        }

        if let goalID = goal?.id {
            await waitForQuestionBankTopOffIfNeeded(for: goalID)
            if let session = takePendingShieldSession() {
                return session
            }
        }

        guard await refreshQuestionBatchIfNeeded() else { return nil }
        return takePendingShieldSession()
    }

    func prepareManualCheckpointSession() async -> CheckpointSession? {
        if let cooldownMessage = checkpointRetryCooldownMessage(source: .manual) {
            checkpointNotice = cooldownMessage
            return nil
        }

        if goal != nil && needsQuestionRefill(minimumQuestionCount: unlockPolicy.questionsPerSession) {
            _ = await refreshQuestionBatchIfNeeded()
        }

        if let session = startManualCheckpointSession() {
            return session
        }

        guard await refreshQuestionBatchIfNeeded() else { return nil }
        return checkpointSession(source: .manual)
    }

    func preparePreviewCheckpointSession() async -> CheckpointSession? {
        if goal != nil && needsQuestionRefill(minimumQuestionCount: unlockPolicy.questionsPerSession) {
            _ = await refreshQuestionBatchIfNeeded()
        }

        if let session = startPreviewCheckpointSession() {
            return session
        }

        guard await refreshQuestionBatchIfNeeded() else { return nil }
        return checkpointSession(source: .manual, purpose: .preview)
    }

    func prepareStopBlockingSession() async -> CheckpointSession? {
        if let cooldownMessage = checkpointRetryCooldownMessage(source: .manual) {
            checkpointNotice = cooldownMessage
            return nil
        }

        if let session = startStopBlockingSession() {
            return session
        }

        guard await refreshQuestionBatchIfNeeded(
            minimumUsableQuestionCount: StopBlockingPolicy.questionsPerSession,
            allowsEarlyCorrectReuse: true
        ) else {
            return nil
        }

        return startStopBlockingSession()
    }

    func startStopBlockingSession() -> CheckpointSession? {
        if let cooldownMessage = checkpointRetryCooldownMessage(source: .manual) {
            checkpointNotice = cooldownMessage
            return nil
        }

        guard goal != nil else {
            checkpointNotice = "Create a goal before stopping blocking."
            return nil
        }

        let selectedQuestions = nextQuestions(
            limit: StopBlockingPolicy.questionsPerSession,
            allowsEarlyCorrectReuse: true
        )
        guard selectedQuestions.count >= StopBlockingPolicy.questionsPerSession else {
            checkpointNotice = "Checkpoint is preparing enough questions for the protection review. Try again in a moment or lower the minimum level."
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

    @discardableResult
    func submitIssueReport(category: IssueReportCategory, message: String, contact: String) -> Bool {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return false }

        let report = UserIssueReport(
            goalID: goal?.id,
            goalTitle: goal?.title ?? "No goal",
            category: category,
            message: trimmedMessage,
            contact: contact.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        issueReports.insert(report, at: 0)
        save()
        return true
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

    func startCheckpointRetryCooldown(now: Date = Date()) {
        checkpointRetryCooldownUntil = now.addingTimeInterval(Self.failedCheckpointCooldown)
        checkpointNotice = "Checkpoint stays protected. Take a short reset, then try again in \(checkpointRetryCooldownRemainingText)."
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
            lastQuestionGenerationFailure = nil

            if isMember {
                questionBatchState = .generating
                shouldRegenerate = true
            } else if hadActiveQuestions && usableQuestionCount < unlockPolicy.questionsPerSession {
                checkpointNotice = "Harder questions selected. Pro can prepare new checkpoints at this difficulty."
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
            checkpointNotice = "Nice progress. Pro can keep preparing harder checkpoints for this goal."
            requestMembership(for: .freshQuestionGeneration)
            save()
            return
        }

        activeGoal.minimumQuestionDifficulty = recommendation.nextLevel
        goal = activeGoal
        retireActiveQuestionsBelowDifficulty(recommendation.nextLevel)
        lastAIErrorMessage = nil
        lastQuestionGenerationFailure = nil
        save()
        publishShieldContext()

        await refreshQuestionBatch(reason: .levelUpRefill)
    }

    func updateAIProviderPreference(_ provider: AIProviderKind) {
        aiProviderPreference = provider == .localTemplates ? .automatic : provider
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
            if questions[index].status == .retired {
                questions[index].nextReviewAt = nil
            } else {
                let delayDays = Self.correctAnswerReviewDelayDays(for: questions[index].timesCorrect)
                questions[index].nextReviewAt = Calendar.current.date(byAdding: .day, value: delayDays, to: Date())
            }
        case .partial:
            questions[index].timesCorrect = max(0, questions[index].timesCorrect - 1)
            questions[index].status = .due
            questions[index].nextReviewAt = Calendar.current.date(byAdding: .hour, value: 12, to: Date())
        case .incorrect, .unclear:
            questions[index].timesCorrect = 0
            questions[index].status = .incorrect
            questions[index].nextReviewAt = Calendar.current.date(byAdding: .hour, value: 2, to: Date())
        }

        if questions[index].timesAsked >= Self.maximumExactQuestionAskCount {
            questions[index].status = .retired
            questions[index].nextReviewAt = nil
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

    private func isReadyQuestionBankCandidate(
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

    private func isSelectableQuestion(_ question: CheckpointQuestion) -> Bool {
        question.status != .retired && question.timesAsked < Self.maximumExactQuestionAskCount
    }

    private static func correctAnswerReviewDelayDays(for correctStreak: Int) -> Int {
        switch correctStreak {
        case ..<1:
            return 3
        case 1:
            return 3
        case 2:
            return 7
        default:
            return 14
        }
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
        isSelectableQuestion(question) && question.difficulty >= activeQuestionDifficulty
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

    // MARK: - Profile helpers

    private func upsertGoalProfile(_ profile: Goal) {
        if let index = goalProfiles.firstIndex(where: { $0.id == profile.id }) {
            goalProfiles[index] = profile
        } else {
            goalProfiles.append(profile)
        }
    }

    private func removeGoalData(for goalID: Goal.ID, includeLegacyCompetencies: Bool = false) {
        questions.removeAll { $0.goalID == goalID }
        attempts.removeAll { $0.goalID == goalID }
        competencies.removeAll { $0.goalID == goalID || (includeLegacyCompetencies && $0.goalID == nil) }
        questionReports.removeAll { $0.goalID == goalID }
        unlockEvents.removeAll { $0.goalID == goalID }
    }

    private func beginQuestionGeneration(for goalID: Goal.ID) {
        guard goal?.id == goalID else { return }
        questionGenerationStartedAt = Date()
        lastQuestionGenerationDuration = nil
        lastQuestionGenerationFailure = nil
        lastAIErrorMessage = nil
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
            unlockEvents: unlockEvents,
            questionReports: questionReports,
            issueReports: issueReports,
            questionGenerationTraces: questionGenerationTraces,
            unlockPolicy: unlockPolicy,
            questionBatchState: questionBatchState,
            lastAIErrorMessage: lastAIErrorMessage,
            lastQuestionGenerationFailure: lastQuestionGenerationFailure,
            aiProviderPreference: aiProviderPreference,
            lastQuestionProvider: lastQuestionProvider,
            backendEndpoint: backendEndpoint,
            unlockSession: unlockSession,
            checkpointRetryCooldownUntil: checkpointRetryCooldownUntil,
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
        if purpose != .preview, let cooldownMessage = checkpointRetryCooldownMessage(source: source) {
            checkpointNotice = cooldownMessage
            return nil
        }

        if let session = nextCheckpointSession(requiresFullSet: true) {
            checkpointNotice = nil
            return CheckpointSession(
                questions: session.questions,
                requiredCorrectAnswers: session.requiredCorrectAnswers,
                purpose: purpose
            )
        }

        checkpointNotice = checkpointSessionUnavailableMessage(source: source)
        if !isMember,
           goal != nil,
           hasConsumedStarterPractice,
           usableQuestionCount < unlockPolicy.questionsPerSession {
            requestMembership(for: .freshQuestionGeneration)
            save()
        }
        return nil
    }

    private func checkpointSessionUnavailableMessage(source: CheckpointSessionSource) -> String {
        if goal == nil {
            return source == .blockedApp
                ? "Checkpoint opened from a protected app, but no goal is set yet."
                : "Create a goal before starting a practice set."
        }

        if activeQuestions.isEmpty {
            if !isMember, hasConsumedStarterPractice {
                return "Your Free checkpoints are complete. Pro keeps new practice ready when you need more."
            }

            if questionBatchState == .generating {
                return "Checkpoint is still preparing your first practice set. Try again in a moment."
            }

            if questionBatchState == .failed {
                return lastQuestionGenerationFailure?.message
                    ?? "Your checkpoint isn't ready yet. Try again or add a few topics to your goal."
            }

            return source == .blockedApp
                ? "Checkpoint opened from a protected app, but no questions are ready yet."
                : "No questions are ready yet."
        }

        if !isMember && hasConsumedStarterPractice && usableQuestionCount == 0 {
            return "Your first Free practice set has done its job. Pro keeps new checkpoints coming."
        }

        return "Checkpoint is preparing more questions. Try again in a moment or choose an easier starting level in your goal settings."
    }

    private func checkpointRetryCooldownMessage(source: CheckpointSessionSource) -> String? {
        clearExpiredCheckpointRetryCooldown()

        guard isCheckpointRetryCooldownActive else { return nil }

        switch source {
        case .blockedApp:
            return "Take a short reset. Try this checkpoint again in \(checkpointRetryCooldownRemainingText)."
        case .manual:
            return "Try another checkpoint in \(checkpointRetryCooldownRemainingText)."
        }
    }

    private func clearExpiredCheckpointRetryCooldown(now: Date = Date()) {
        guard let checkpointRetryCooldownUntil,
              checkpointRetryCooldownUntil <= now else {
            return
        }

        self.checkpointRetryCooldownUntil = nil
        save()
    }

    private func recoverTransientQuestionGenerationState() {
        if questionBatchState == .generating {
            questionGenerationStartedAt = nil
            lastQuestionGenerationDuration = nil
            questionBatchState = activeQuestions.isEmpty ? .idle : .ready
            save()

            if activeQuestions.isEmpty, let goal {
                prepareInitialQuestionsInBackground(for: goal)
            }
        } else if questionBatchState == .failed, hasReadyCheckpointSet {
            questionBatchState = .ready
            save()
        }
    }

    private func resumeQuestionBankMaintenanceIfNeeded() {
        guard let goal,
              isMember,
              questionBatchState != .generating,
              !backgroundGenerationGoalIDs.contains(goal.id),
              !questionBankTopOffGoalIDs.contains(goal.id),
              readyQuestionCount(for: goal) <= ProductLimits.autoRefreshThreshold,
              questionBankDeficit(for: goal) > 0 else {
            return
        }

        topOffQuestionBankInBackground(for: goal)
    }

    private func waitForQuestionBankTopOffIfNeeded(for goalID: Goal.ID) async {
        var attempts = 0
        while questionBankTopOffGoalIDs.contains(goalID),
              attempts < Self.questionBankTopOffWaitAttemptCount {
            try? await Task.sleep(nanoseconds: Self.questionBankTopOffWaitIntervalNanoseconds)
            attempts += 1
        }
    }

    private func load() {
        guard
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(AppSnapshot.self, from: data)
        else { return }

        questions = snapshot.questions
        attempts = snapshot.attempts
        competencies = snapshot.competencies
        unlockEvents = snapshot.unlockEvents ?? []
        questionReports = snapshot.questionReports ?? []
        issueReports = snapshot.issueReports ?? []
        questionGenerationTraces = snapshot.questionGenerationTraces ?? []
        unlockPolicy = snapshot.unlockPolicy ?? .default
        questionBatchState = snapshot.questionBatchState ?? .idle
        lastAIErrorMessage = snapshot.lastAIErrorMessage
        lastQuestionGenerationFailure = snapshot.lastQuestionGenerationFailure
        let savedProviderPreference = snapshot.aiProviderPreference ?? .automatic
        aiProviderPreference = [.automatic, .backend].contains(savedProviderPreference)
            ? savedProviderPreference
            : .automatic
        lastQuestionProvider = snapshot.lastQuestionProvider ?? .automatic
        backendEndpoint = snapshot.backendEndpoint ?? ""
        unlockSession = snapshot.unlockSession
        checkpointRetryCooldownUntil = snapshot.checkpointRetryCooldownUntil
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
            seedTopics = questionTopics.isEmpty ? context.contentTopics : questionTopics
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

    private static func formattedRetryCooldownDuration(_ duration: TimeInterval) -> String {
        let remainingSeconds = max(0, Int(ceil(duration)))
        if remainingSeconds >= 60 {
            let minutes = Int(ceil(Double(remainingSeconds) / 60.0))
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }

        return remainingSeconds == 1 ? "1 second" : "\(remainingSeconds) seconds"
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
            failure: batch.failure,
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
        Failure: \(trace.failure?.rawValue ?? "None")
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
        var candidates = [
            storedValue,
            ProcessInfo.processInfo.environment[environmentKey]
        ]
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            candidates.append(Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)
        }

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
        "Free includes an initial practice set for your first goal. Pro keeps new checkpoints available after that set runs low."
    }
}
