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
    var lastQuestionProvider: AIProviderKind = .localTemplates
    var backendEndpoint = ""
    private(set) var backendQuestionGenerationConsentGranted = false
    var serverQuestionReserveEnabled = false
    var lastAIErrorMessage: String?
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
    var persistenceRecoveryMessage: String?

    @ObservationIgnored private let questionEngine: HybridQuestionEngine
    @ObservationIgnored private let questionReserveService: any QuestionReserveServing
    @ObservationIgnored private let questionReserveConfigurationOverride: QuestionReserveConfiguration?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let snapshotKey = "checkpoint.snapshot.v1"
    @ObservationIgnored private let snapshotBackupKey = "checkpoint.snapshot.backup.v1"
    @ObservationIgnored private var persistenceWritesBlockedByFutureSchema = false
    @ObservationIgnored private var backgroundGenerationGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private var questionBankTopOffGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private var backgroundGenerationTasks: [Goal.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var questionBankTopOffTasks: [Goal.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var serverQuestionReserveTasks: [Goal.ID: (revision: String, desiredCount: Int, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var pendingQuestionReserveAcknowledgements: [PendingQuestionReserveAcknowledgement] = []
    @ObservationIgnored private static let initialCheckpointReadyTargetCount = 5
    @ObservationIgnored private static let urgentRefillTargetMultiplier = 2
    @ObservationIgnored private static let backendGenerationChunkCount = 20
    @ObservationIgnored private static let onDeviceGenerationChunkCount = 6
    @ObservationIgnored private static let foregroundTopOffBatchLimit = 4
    @ObservationIgnored private static let maximumQuestionGenerationTraceCount = 20
    @ObservationIgnored private static let maximumQuestionGenerationPreviewCount = 12
    @ObservationIgnored private static let levelUpRecentAttemptWindow = 10
    @ObservationIgnored private static let levelUpMinimumAttemptCount = 5
    @ObservationIgnored private static let levelUpAccuracyThreshold = 0.90
    @ObservationIgnored private static let maximumExactQuestionAskCount = 2
    @ObservationIgnored private static let maximumGoalTitleLength = 160
    @ObservationIgnored private static let maximumCurrentLevelLength = 240
    @ObservationIgnored private static let maximumFocusAreasLength = 800
    @ObservationIgnored private static let maximumQuestionReportNoteLength = 280
    @ObservationIgnored private static let failedCheckpointCooldown: TimeInterval = 5 * 60
    @ObservationIgnored private static let questionBankTopOffWaitIntervalNanoseconds: UInt64 = 100_000_000
    @ObservationIgnored private static let questionBankTopOffWaitAttemptCount = 10
    @ObservationIgnored private static let memberServerQuestionReserveCount = 20
    @ObservationIgnored private static let serverReservePullUsableThreshold = 10
    @ObservationIgnored private static let serverReservePullFreshThreshold = 5
    @ObservationIgnored private static let shieldReserveFastPathTimeoutNanoseconds: UInt64 = 1_500_000_000

    // MARK: - Lifecycle

    init(
        questionEngine: HybridQuestionEngine = HybridQuestionEngine(),
        questionReserveService: any QuestionReserveServing = BackendQuestionReserveClient(),
        questionReserveConfiguration: QuestionReserveConfiguration? = nil,
        defaults: UserDefaults = .standard,
        automaticallyStartsQuestionMaintenance: Bool = true
    ) {
        self.questionEngine = questionEngine
        self.questionReserveService = questionReserveService
        self.questionReserveConfigurationOverride = questionReserveConfiguration
        self.defaults = defaults
        load()
        clearExpiredCheckpointRetryCooldown()
        recoverTransientQuestionGenerationState(
            resumesGeneration: automaticallyStartsQuestionMaintenance
        )
        isOnboardingPresented = goal == nil
        publishShieldContext()
        if automaticallyStartsQuestionMaintenance {
            replaceActiveLocalTemplateQuestionBankIfNeeded()
            resumeQuestionBankMaintenanceIfNeeded()
        }
    }

    /// Starts maintenance only after the app has refreshed the user's entitlement.
    /// The app delegate uses a non-starting store so background tasks are registered
    /// before any generation work can begin.
    func prepareQuestionMaintenanceAfterLaunch() async {
        defer { scheduleServerQuestionReserveMaintenance() }
        if let replacementGoal = replaceActiveLocalTemplateQuestionBankIfNeeded(
            startsGeneration: false
        ) {
            await awaitInitialQuestionGeneration(for: replacementGoal)
            return
        }

        guard let goal else { return }
        if activeQuestions.isEmpty {
            if isMember || !goal.hasCompletedInitialQuestionProvisioning {
                await awaitInitialQuestionGeneration(for: goal)
            }
        } else {
            _ = await performBackgroundQuestionMaintenance(maximumBatchCount: 1)
        }
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

    private var activeLearningAttempts: [CheckpointAttempt] {
        activeAttempts.filter(isLearningEvidence)
    }

    private var activeAttemptsThisWeek: [CheckpointAttempt] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return activeLearningAttempts.filter { week.contains($0.createdAt) }
    }

    private var attemptsThisWeek: [CheckpointAttempt] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return attempts.filter(isLearningEvidence).filter { week.contains($0.createdAt) }
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

    var persistenceDiagnosticsSummary: String {
        persistenceRecoveryMessage ?? "Saved learning data loaded normally."
    }

    var questionGenerationDiagnosticsExportText: String {
        guard !questionGenerationTraces.isEmpty else {
            return "No question generation diagnostics recorded."
        }

        return questionGenerationTraces.map(Self.exportText(for:)).joined(separator: "\n\n---\n\n")
    }

    var questionGenerationDiagnosticsSupportText: String {
        guard !questionGenerationTraces.isEmpty else {
            return "No question generation diagnostics recorded."
        }

        return questionGenerationTraces.map(Self.redactedExportText(for:)).joined(separator: "\n\n---\n\n")
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

    var needsBackgroundQuestionMaintenance: Bool {
        if isMember {
            return availableGoalProfiles.contains { profile in
                hasPendingQuestionReportReplacement(for: profile)
                    || (questionBankDeficit(for: profile) > 0
                        && needsProactiveQuestionMaintenance(for: profile))
            }
        }

        guard let goal else { return false }
        return isInterruptedStarterTopOff(for: goal)
            || hasPendingQuestionReportReplacement(for: goal)
    }

    var shouldShowStarterMembershipPrompt: Bool {
        !isMember && goal != nil && readyQuestionCount <= ProductLimits.autoRefreshThreshold
    }

    var usableQuestionCount: Int {
        activeQuestions.filter(isSelectableQuestion).filter(meetsDifficultyFloor).count
    }

    var readyQuestionCount: Int {
        guard let goal else { return 0 }
        return readyQuestionCount(for: goal)
    }

    var freshReadyQuestionCount: Int {
        guard let goal else { return 0 }
        return freshReadyQuestionCount(for: goal)
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

    private func freshReadyQuestionCount(for profile: Goal) -> Int {
        questions.filter { question in
            question.goalID == profile.id
                && question.difficulty >= profile.minimumQuestionDifficulty
                && question.status == .new
                && question.timesAsked == 0
                && isSelectableQuestion(question)
        }.count
    }

    private func questionBankDeficit(
        for profile: Goal,
        targetCount: Int? = nil,
        allowsEarlyCorrectReuse: Bool = false
    ) -> Int {
        let totalReadyDeficit = max(
            0,
            (targetCount ?? questionBankTargetCount) - readyQuestionCount(
                for: profile,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
            )
        )
        let freshReserveDeficit = max(0, desiredFreshQuestionReserve - freshReadyQuestionCount(for: profile))
        return max(totalReadyDeficit, freshReserveDeficit)
    }

    private var desiredFreshQuestionReserve: Int {
        max(10, unlockPolicy.questionsPerSession * 2)
    }

    private func needsProactiveQuestionMaintenance(for profile: Goal) -> Bool {
        readyQuestionCount(for: profile) <= ProductLimits.autoRefreshThreshold
            || freshReadyQuestionCount(for: profile) <= desiredFreshQuestionReserve
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
            let elapsedText = questionBankTopOffStartedAt.map { " Started \(Self.formattedDuration(Date().timeIntervalSince($0))) ago." } ?? ""
            return "Preparing more practice in the background.\(elapsedText)"
        }

        switch questionBatchState {
        case .generating:
            if hasReadyCheckpointSet {
                return "Practice is ready."
            }
            let readyText = usableQuestionCount > 0
                ? "Preparing more practice"
                : "Preparing first practice set"
            let elapsedText = questionGenerationStartedAt.map { " Started \(Self.formattedDuration(Date().timeIntervalSince($0))) ago." } ?? ""
            return "\(readyText) in the background.\(elapsedText)"
        case .failed:
            return lastAIErrorMessage ?? "Question preparation did not finish. Checkpoint will try again when possible."
        case .ready:
            if let duration = lastQuestionGenerationDuration {
                return "Practice is ready. Last prepared in \(Self.formattedDuration(duration))."
            }
            return "Practice is ready."
        case .idle:
            return usableQuestionCount > 0 ? "Practice is ready." : "No practice prepared yet."
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
            return "Next focus: \(missedTopic). Recent misses are ready for review."
        }

        guard let competency = sortedCompetencies.first else { return nil }

        if competency.attempts == 0 {
            return "Start with \(competency.topic). Checkpoint needs more evidence there."
        }

        return "Next focus: \(competency.topic). It is your lowest mastery area at \(competency.masteryPercent)%."
    }

    var questionLevelRecommendation: QuestionLevelRecommendation? {
        guard let goal,
              goal.minimumQuestionDifficulty < 5,
              !isPreparingActiveGoalQuestions else {
            return nil
        }

        let recentAttempts = Array(activeLearningAttempts.prefix(Self.levelUpRecentAttemptWindow))
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
        if shouldReplaceLocalTemplateQuestionBank(for: selectedGoal) {
            clearQuestionBank(for: selectedGoal.id)
        }
        let activeSelectedGoal = goal ?? selectedGoal

        let hasActiveQuestions = usableQuestionCount(for: activeSelectedGoal) > 0
        questionBatchState = hasActiveQuestions ? .ready : .generating
        isQuestionBankTopOffInProgress = questionBankTopOffGoalIDs.contains(selectedGoal.id)
        questionBankTopOffStartedAt = isQuestionBankTopOffInProgress ? questionBankTopOffStartedAt ?? Date() : nil
        checkpointNotice = nil
        save()
        publishShieldContext()
        scheduleServerQuestionReserveMaintenance()

        if hasActiveQuestions {
            Task { [weak self] in
                _ = await self?.refreshQuestionBatchIfNeeded()
                await self?.prepareProtectionReviewQuestionBankIfNeeded()
            }
        } else {
            prepareInitialQuestionsInBackground(for: activeSelectedGoal)
        }
        return true
    }

    @discardableResult
    func deleteGoalProfile(_ goalID: Goal.ID) -> Bool {
        guard let deletedGoal = availableGoalProfiles.first(where: { $0.id == goalID }) else { return false }

        let reserveConfiguration = resolvedQuestionReserveConfiguration
        let wasActiveGoal = goal?.id == goalID
        let canceledReserveTask = cancelQuestionMaintenance(for: goalID)
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
        scheduleServerQuestionReserveDeletion(
            goalIDs: [goalID],
            configuration: reserveConfiguration,
            resetsCredentials: false,
            waitingFor: canceledReserveTask.map { [$0] } ?? []
        )
        scheduleServerQuestionReserveMaintenance()
        return true
    }

    @discardableResult
    private func replaceActiveLocalTemplateQuestionBankIfNeeded(
        startsGeneration: Bool = true
    ) -> Goal? {
        guard let goal,
              shouldReplaceLocalTemplateQuestionBank(for: goal) else {
            return nil
        }

        clearQuestionBank(for: goal.id)
        guard let replacementGoal = self.goal else { return nil }
        questionBatchState = .generating
        isQuestionBankTopOffInProgress = false
        questionBankTopOffStartedAt = nil
        lastAIErrorMessage = nil
        save()
        publishShieldContext()
        if startsGeneration {
            prepareInitialQuestionsInBackground(for: replacementGoal)
        }
        return replacementGoal
    }

    private func shouldReplaceLocalTemplateQuestionBank(for profile: Goal) -> Bool {
        aiProviderPreference != .localTemplates
            && resolvedBackendEndpoint != nil
            && lastQuestionProvider == .localTemplates
            && questions.contains { question in
                question.goalID == profile.id && question.status != .retired
            }
    }

    private func clearQuestionBank(for goalID: Goal.ID) {
        let historicalQuestionIDs = Set(
            attempts.filter { $0.goalID == goalID }.map(\.questionID)
                + questionReports.filter { $0.goalID == goalID }.map(\.questionID)
        )
        questions.removeAll { question in
            question.goalID == goalID && !historicalQuestionIDs.contains(question.id)
        }
        for index in questions.indices where questions[index].goalID == goalID {
            questions[index].status = .retired
            questions[index].nextReviewAt = nil
        }
        setInitialQuestionProvisioningCompleted(false, for: goalID)
        if let profile = availableGoalProfiles.first(where: { $0.id == goalID })
            ?? (goal?.id == goalID ? goal : nil) {
            rebuildCompetencies(for: profile)
        }
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
            // A previous downgrade purge may have been interrupted when the app
            // was suspended or terminated. Re-issuing desiredCount zero is
            // idempotent and prevents persisted Starter launches from stranding
            // cloud reserve work until its TTL expires.
            if tier == .starter, serverQuestionReserveEnabled {
                for profile in availableGoalProfiles {
                    _ = startServerQuestionReserveMaintenance(for: profile, desiredCount: 0)
                }
            }
            if pendingMembershipFeature != nil {
                pendingMembershipFeature = nil
                save()
                publishShieldContext()
            }
            return
        }

        membershipTier = tier
        pendingMembershipFeature = nil
        if tier == .starter {
            for (goalID, task) in backgroundGenerationTasks {
                let profile = availableGoalProfiles.first(where: { $0.id == goalID })
                    ?? (goal?.id == goalID ? goal : nil)
                if profile?.id != goal?.id || profile?.hasCompletedInitialQuestionProvisioning == true {
                    task.cancel()
                }
            }
            questionBankTopOffTasks.values.forEach { $0.cancel() }
            serverQuestionReserveTasks.values.forEach { $0.task.cancel() }
            serverQuestionReserveTasks = [:]
        }
        save()
        publishShieldContext()

        if tier == .member, goal != nil {
            scheduleServerQuestionReserveMaintenance()
            Task { [weak self] in
                _ = await self?.refreshQuestionBatchIfNeeded()
            }
        } else if tier == .starter, serverQuestionReserveEnabled {
            for profile in availableGoalProfiles {
                _ = startServerQuestionReserveMaintenance(for: profile, desiredCount: 0)
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
        let normalizedTitle = Self.boundedText(
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            maximumLength: Self.maximumGoalTitleLength
        )
        let normalizedCurrentLevel = Self.boundedText(
            currentLevel.trimmingCharacters(in: .whitespacesAndNewlines),
            maximumLength: Self.maximumCurrentLevelLength
        )
        let normalizedFocusAreas = Self.boundedText(
            focusAreas.trimmingCharacters(in: .whitespacesAndNewlines),
            maximumLength: Self.maximumFocusAreasLength
        )

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
        var canceledPreviousReserveTask: Task<Void, Never>?
        if shouldReplaceActiveProfile, let previousGoalID {
            canceledPreviousReserveTask = cancelQuestionMaintenance(for: previousGoalID)
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
        checkpointNotice = nil
        unlockSession = nil
        isOnboardingPresented = false
        isCreatingGoalProfile = false
        SharedAppGroup.publishUnlockExpiration(nil)
        save()
        publishShieldContext()
        if shouldReplaceActiveProfile, let previousGoalID {
            scheduleServerQuestionReserveDeletion(
                goalIDs: [previousGoalID],
                configuration: resolvedQuestionReserveConfiguration,
                resetsCredentials: false,
                waitingFor: canceledPreviousReserveTask.map { [$0] } ?? []
            )
        }
        scheduleServerQuestionReserveMaintenance()

        if waitForQuestionGeneration {
            await awaitInitialQuestionGeneration(for: newGoal)
        } else {
            prepareInitialQuestionsInBackground(for: newGoal)
        }
    }

    /// Updates the active goal without changing its identity or deleting learning history.
    /// Question-shaping changes retire the incompatible ready bank and prepare a new
    /// checkpoint-sized set while keeping raw attempts, rich reports, and unlock events for audit.
    func updateGoal(
        title: String,
        deadline: Date,
        category: GoalCategory? = nil,
        currentLevel: String,
        focusAreas: String,
        preferredQuestionStyle: QuestionFormat,
        minimumQuestionDifficulty: Int? = nil,
        waitForQuestionGeneration: Bool = true
    ) async {
        guard let existingGoal = goal else {
            await createGoal(
                title: title,
                deadline: deadline,
                category: category,
                currentLevel: currentLevel,
                focusAreas: focusAreas,
                preferredQuestionStyle: preferredQuestionStyle,
                minimumQuestionDifficulty: minimumQuestionDifficulty,
                createsNewProfile: false,
                waitForQuestionGeneration: waitForQuestionGeneration
            )
            return
        }

        let normalizedTitle = Self.boundedText(
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            maximumLength: Self.maximumGoalTitleLength
        )
        let normalizedCurrentLevel = Self.boundedText(
            currentLevel.trimmingCharacters(in: .whitespacesAndNewlines),
            maximumLength: Self.maximumCurrentLevelLength
        )
        let normalizedFocusAreas = Self.boundedText(
            focusAreas.trimmingCharacters(in: .whitespacesAndNewlines),
            maximumLength: Self.maximumFocusAreasLength
        )

        guard !normalizedTitle.isEmpty else {
            questionBatchState = .failed
            lastAIErrorMessage = "Enter a goal before generating questions."
            save()
            return
        }

        var updatedGoal = Goal(
            id: existingGoal.id,
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
            minimumQuestionDifficulty: minimumQuestionDifficulty ?? existingGoal.minimumQuestionDifficulty,
            hasCompletedInitialQuestionProvisioning: existingGoal.hasCompletedInitialQuestionProvisioning,
            createdAt: existingGoal.createdAt
        )

        let questionContextChanged = GoalQuestionContext(goal: existingGoal) != GoalQuestionContext(goal: updatedGoal)
            || existingGoal.preferredQuestionStyle != updatedGoal.preferredQuestionStyle
        let currentLevelChanged = normalizedCurrentLevel.caseInsensitiveCompare(existingGoal.currentLevel) != .orderedSame
        let difficultyChanged = updatedGoal.minimumQuestionDifficulty != existingGoal.minimumQuestionDifficulty
        let difficultyRaised = updatedGoal.minimumQuestionDifficulty > existingGoal.minimumQuestionDifficulty
        let shouldPrepareReplacementQuestions = questionContextChanged || currentLevelChanged || difficultyChanged

        let interruptedGenerationTask = backgroundGenerationTasks[existingGoal.id]
        let interruptedTopOffTask = questionBankTopOffTasks[existingGoal.id]
        let interruptedQuestionMaintenance = interruptedGenerationTask != nil || interruptedTopOffTask != nil
        interruptedGenerationTask?.cancel()
        interruptedTopOffTask?.cancel()
        if let interruptedGenerationTask {
            await interruptedGenerationTask.value
        }
        if let interruptedTopOffTask {
            await interruptedTopOffTask.value
        }

        if questionContextChanged {
            let previousContextFingerprint = questionContextFingerprint(for: existingGoal)
            for index in questions.indices where questions[index].goalID == existingGoal.id {
                if questions[index].goalContextFingerprint == nil {
                    questions[index].goalContextFingerprint = previousContextFingerprint
                }
                questions[index].status = .retired
                questions[index].nextReviewAt = nil
            }
            for index in questionReports.indices
            where questionReports[index].goalID == existingGoal.id
                && questionReports[index].replacementState == .pending {
                questionReports[index].replacementState = .notEligible
            }
        } else if difficultyRaised {
            retireActiveQuestionsBelowDifficulty(updatedGoal.minimumQuestionDifficulty)
        } else if difficultyChanged {
            retireActiveQuestionsAboveDifficulty(updatedGoal.minimumQuestionDifficulty)
        }

        if shouldPrepareReplacementQuestions {
            // Re-open provisioning only for this in-place refresh. When the subject
            // remains compatible, historical question records still serve as an avoid list.
            updatedGoal.hasCompletedInitialQuestionProvisioning = false
        }

        goal = updatedGoal
        upsertGoalProfile(updatedGoal)
        rebuildCompetencies(for: updatedGoal)
        lastAIErrorMessage = nil
        checkpointNotice = shouldPrepareReplacementQuestions
            ? "Goal updated. Fresh questions are being prepared."
            : "Goal updated."
        isOnboardingPresented = false
        isCreatingGoalProfile = false
        let shouldRecoverReadySet = usableQuestionCount < Self.initialCheckpointReadyTargetCount
            && (isMember || !updatedGoal.hasCompletedInitialQuestionProvisioning)
        if usableQuestionCount >= Self.initialCheckpointReadyTargetCount {
            questionBatchState = .ready
        } else {
            questionBatchState = shouldRecoverReadySet ? .generating : .failed
        }
        save()
        publishShieldContext()
        if shouldPrepareReplacementQuestions {
            scheduleServerQuestionReserveMaintenance()
        }

        if shouldPrepareReplacementQuestions || shouldRecoverReadySet {
            if waitForQuestionGeneration {
                await awaitInitialQuestionGeneration(for: updatedGoal)
            } else {
                prepareInitialQuestionsInBackground(for: updatedGoal)
            }
            return
        }

        guard interruptedQuestionMaintenance else { return }
        if usableQuestionCount < Self.initialCheckpointReadyTargetCount,
           isMember || !updatedGoal.hasCompletedInitialQuestionProvisioning {
            if waitForQuestionGeneration {
                await awaitInitialQuestionGeneration(for: updatedGoal)
            } else {
                prepareInitialQuestionsInBackground(for: updatedGoal)
            }
        } else if needsBackgroundQuestionMaintenance {
            topOffQuestionBankInBackground(for: updatedGoal)
            if waitForQuestionGeneration,
               let resumedTopOffTask = questionBankTopOffTasks[updatedGoal.id] {
                await resumedTopOffTask.value
            }
        }
    }

    private func prepareInitialQuestionsInBackground(for newGoal: Goal) {
        _ = startInitialQuestionGeneration(for: newGoal)
    }

    private func awaitInitialQuestionGeneration(for newGoal: Goal) async {
        let task = startInitialQuestionGeneration(for: newGoal)
        await awaitQuestionMaintenanceTask(task)
    }

    private func startInitialQuestionGeneration(for newGoal: Goal) -> Task<Void, Never> {
        if let existingTask = backgroundGenerationTasks[newGoal.id] {
            return existingTask
        }

        let currentGoal = availableGoalProfiles.first(where: { $0.id == newGoal.id })
            ?? (goal?.id == newGoal.id ? goal : nil)
        guard let currentGoal,
              currentGoal == newGoal,
              isMember || !currentGoal.hasCompletedInitialQuestionProvisioning else {
            return Task {}
        }

        backgroundGenerationGoalIDs.insert(newGoal.id)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.generateInitialQuestionBatch(for: newGoal)
        }
        backgroundGenerationTasks[newGoal.id] = task
        return task
    }

    private func generateInitialQuestionBatch(for newGoal: Goal) async {
        defer {
            backgroundGenerationGoalIDs.remove(newGoal.id)
            backgroundGenerationTasks[newGoal.id] = nil
        }
        guard let currentGoal = availableGoalProfiles.first(where: { $0.id == newGoal.id })
                ?? (goal?.id == newGoal.id ? goal : nil),
              currentGoal == newGoal,
              isMember || !currentGoal.hasCompletedInitialQuestionProvisioning else {
            return
        }

        if goal?.id == newGoal.id {
            questionBatchState = .generating
            beginQuestionGeneration(for: newGoal.id)
        }

        let existingGoalQuestions = questions.filter { $0.goalID == newGoal.id }
        let existingGoalCompetencies = competencies.filter {
            ($0.goalID ?? newGoal.id) == newGoal.id
        }
        let existingGoalReports = questionReports.filter { $0.goalID == newGoal.id }
        let checkpointReadyRequest = generationRequest(
            goal: newGoal,
            existingQuestions: existingGoalQuestions,
            competencies: existingGoalCompetencies,
            reportedQuestions: existingGoalReports,
            targetCount: Self.initialCheckpointReadyTargetCount
        )

        let startedAt = Date()
        let providerPreference = initialBatchProviderPreference(for: checkpointReadyRequest)
        let batch = await generateCheckpointReadyBatch(
            for: checkpointReadyRequest,
            preference: providerPreference
        )

        guard let currentGoal = availableGoalProfiles.first(where: { $0.id == newGoal.id })
                ?? (goal?.id == newGoal.id ? goal : nil),
              currentGoal == newGoal,
              isMember || !currentGoal.hasCompletedInitialQuestionProvisioning else {
            if goal?.id == newGoal.id {
                questionBatchState = activeQuestions.isEmpty ? .idle : .ready
                finishQuestionGeneration(for: newGoal.id)
                save()
                publishShieldContext()
            }
            return
        }

        var currentQuestionKeys = Set(
            questions
                .filter { $0.goalID == newGoal.id }
                .map(questionKey)
        )
        let newQuestions = batch.questions.filter { question in
            guard question.difficulty >= newGoal.minimumQuestionDifficulty else { return false }
            let key = questionKey(question)
            guard !currentQuestionKeys.contains(key) else { return false }
            currentQuestionKeys.insert(key)
            return true
        }.map { questionStampedForCurrentContext($0, goal: newGoal) }
        questions.append(contentsOf: newQuestions)
        rebuildCompetencies(for: newGoal)
        lastQuestionProvider = batch.provider
        if newQuestions.isEmpty {
            lastAIErrorMessage = "No usable questions were generated. Try adding focus topics or lowering the question level."
        } else {
            lastAIErrorMessage = batch.usedFallback ? "Checkpoint used the best available question path for this device." : nil
        }
        recordQuestionGenerationTrace(
            phase: "Initial ready batch",
            request: checkpointReadyRequest,
            providerPreference: providerPreference,
            batch: batch,
            addedQuestions: newQuestions,
            startedAt: startedAt,
            errorMessage: lastAIErrorMessage
        )
        if goal?.id == newGoal.id {
            questionBatchState = usableQuestionCount < Self.initialCheckpointReadyTargetCount ? .failed : .ready
            finishQuestionGeneration(for: newGoal.id)
        }
        save()
        publishShieldContext()

        if !newQuestions.isEmpty {
            topOffQuestionBankInBackground(
                for: newGoal,
                starterQuestionIDs: Set(newQuestions.map(\.id))
            )
        }
    }

    private func initialBatchProviderPreference(for request: QuestionGenerationRequest) -> AIProviderKind {
        consentFilteredProviderPreference(
            aiProviderPreference,
            hasBackendEndpoint: request.backendEndpoint != nil
        )
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

    private func topOffQuestionBankInBackground(
        for goal: Goal,
        starterQuestionIDs: Set<CheckpointQuestion.ID> = [],
        maximumBatches: Int = CheckpointStore.foregroundTopOffBatchLimit,
        allowsStarterQuestionReplacement: Bool = false
    ) {
        _ = startQuestionBankTopOff(
            for: goal,
            starterQuestionIDs: starterQuestionIDs,
            providerPreference: questionBankMaintenanceProviderPreference(for: goal),
            maximumBatches: maximumBatches,
            allowsStarterQuestionReplacement: allowsStarterQuestionReplacement
        )
        QuestionBankBackgroundScheduler.schedule()
    }

    private func startQuestionBankTopOff(
        for targetGoal: Goal,
        starterQuestionIDs: Set<CheckpointQuestion.ID>,
        providerPreference: AIProviderKind,
        maximumBatches: Int,
        allowsStarterQuestionReplacement: Bool = false
    ) -> Task<Void, Never>? {
        if let existingTask = questionBankTopOffTasks[targetGoal.id] {
            return existingTask
        }
        guard !questionBankTopOffGoalIDs.contains(targetGoal.id) else { return nil }

        questionBankTopOffGoalIDs.insert(targetGoal.id)
        if goal?.id == targetGoal.id {
            beginQuestionBankTopOff(for: targetGoal.id)
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.topOffQuestionBank(
                for: targetGoal,
                starterQuestionIDs: starterQuestionIDs,
                providerPreference: providerPreference,
                maximumBatches: maximumBatches,
                allowsStarterQuestionReplacement: allowsStarterQuestionReplacement
            )
        }
        questionBankTopOffTasks[targetGoal.id] = task
        return task
    }

    private func scheduleQuestionBankMaintenanceIfNeeded(for targetGoal: Goal) {
        guard isMember,
              needsProactiveQuestionMaintenance(for: targetGoal),
              questionBankDeficit(for: targetGoal) > 0,
              !questionBankTopOffGoalIDs.contains(targetGoal.id) else {
            return
        }

        topOffQuestionBankInBackground(for: targetGoal)
        QuestionBankBackgroundScheduler.schedule()
    }

    private func scheduleReportedQuestionReplacement(for targetGoal: Goal) {
        guard hasPendingQuestionReportReplacement(for: targetGoal) else { return }
        guard questionBankDeficit(for: targetGoal) > 0 else {
            markQuestionReportReplacementsPrepared(for: targetGoal, count: 1)
            save()
            return
        }
        guard !questionBankTopOffGoalIDs.contains(targetGoal.id) else {
            return
        }

        topOffQuestionBankInBackground(
            for: targetGoal,
            maximumBatches: 1,
            allowsStarterQuestionReplacement: !isMember
        )
    }

    private func topOffQuestionBank(
        for targetGoal: Goal,
        starterQuestionIDs: Set<CheckpointQuestion.ID>,
        providerPreference: AIProviderKind,
        maximumBatches: Int,
        allowsStarterQuestionReplacement: Bool = false
    ) async {
        defer {
            questionBankTopOffGoalIDs.remove(targetGoal.id)
            questionBankTopOffTasks[targetGoal.id] = nil
            if goal?.id == targetGoal.id {
                finishQuestionBankTopOff(for: targetGoal.id)
            }
            markInitialQuestionProvisioningCompleteIfNeeded(for: targetGoal.id)
        }

        guard goalProfiles.contains(where: { $0.id == targetGoal.id }) || goal?.id == targetGoal.id else { return }
        guard isMember
                || allowsStarterQuestionReplacement
                || !targetGoal.hasCompletedInitialQuestionProvisioning else {
            if goal?.id == targetGoal.id {
                checkpointNotice = starterQuestionLimitMessage
                requestMembership(for: .freshQuestionGeneration)
                save()
            }
            return
        }

        var completedBatches = 0
        var madeProgress = false

        while completedBatches < max(1, maximumBatches), !Task.isCancelled {
            guard let currentTargetGoal = availableGoalProfiles.first(where: { $0.id == targetGoal.id })
                    ?? (goal?.id == targetGoal.id ? goal : nil),
                  currentTargetGoal == targetGoal,
                  isMember
                    || allowsStarterQuestionReplacement
                    || !currentTargetGoal.hasCompletedInitialQuestionProvisioning else {
                break
            }

            let remainingTargetCount = allowsStarterQuestionReplacement
                ? min(
                    questionBankDeficit(for: currentTargetGoal),
                    pendingQuestionReportReplacementCount(for: currentTargetGoal)
                )
                : questionBankDeficit(for: currentTargetGoal)
            guard remainingTargetCount > 0 else { break }

            let existingQuestions = questions.filter { $0.goalID == currentTargetGoal.id }
            let existingCompetencies = competencies.filter { ($0.goalID ?? currentTargetGoal.id) == currentTargetGoal.id }
            let requestedCount = min(
                remainingTargetCount,
                generationChunkCount(for: providerPreference)
            )
            let topOffRequest = generationRequest(
                goal: currentTargetGoal,
                existingQuestions: existingQuestions,
                competencies: existingCompetencies,
                reportedQuestions: questionReports.filter { $0.goalID == currentTargetGoal.id },
                targetCount: requestedCount
            )
            let startedAt = Date()
            let batch = await questionEngine.generateQuestionBatch(
                for: topOffRequest,
                preference: providerPreference
            )

            guard !Task.isCancelled,
                  let latestGoal = availableGoalProfiles.first(where: { $0.id == targetGoal.id })
                    ?? (goal?.id == targetGoal.id ? goal : nil),
                  latestGoal == targetGoal else {
                break
            }

            var currentKeys = Set(
                questions
                    .filter { $0.goalID == latestGoal.id }
                    .map(questionKey)
            )
            var newQuestions: [CheckpointQuestion] = []
            for question in batch.questions where question.difficulty >= latestGoal.minimumQuestionDifficulty {
                let key = questionKey(question)
                guard !currentKeys.contains(key) else { continue }
                currentKeys.insert(key)
                newQuestions.append(questionStampedForCurrentContext(question, goal: latestGoal))
            }

            questions.append(contentsOf: newQuestions)
            if !newQuestions.isEmpty {
                markQuestionReportReplacementsPrepared(
                    for: latestGoal,
                    count: newQuestions.count
                )
            }
            let goalQuestions = questions.filter { $0.goalID == latestGoal.id }
            let latestCompetencies = competencies.filter { ($0.goalID ?? latestGoal.id) == latestGoal.id }
            competencies.removeAll { $0.goalID == latestGoal.id }
            competencies.append(contentsOf: mergeCompetencies(
                existing: latestCompetencies,
                goal: latestGoal,
                questions: goalQuestions
            ))

            if !newQuestions.isEmpty {
                madeProgress = true
                lastQuestionProvider = batch.provider
                lastAIErrorMessage = batch.usedFallback ? "Checkpoint used the best available question path for this device." : nil
            }
            recordQuestionGenerationTrace(
                phase: "Question bank top-off",
                request: topOffRequest,
                providerPreference: providerPreference,
                batch: batch,
                addedQuestions: newQuestions,
                retiredQuestionCount: 0,
                startedAt: startedAt,
                errorMessage: lastAIErrorMessage
            )
            completedBatches += 1
            if goal?.id == latestGoal.id {
                questionBatchState = goalQuestions.isEmpty ? .failed : .ready
            }
            save()
            publishShieldContext()

            guard !newQuestions.isEmpty else { break }
        }

        if madeProgress, questionBankDeficit(for: targetGoal) > 0 {
            QuestionBankBackgroundScheduler.schedule()
        }
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
        guard !backgroundGenerationGoalIDs.contains(goal.id),
              !questionBankTopOffGoalIDs.contains(goal.id) else {
            return
        }

        questionBatchState = .generating
        beginQuestionGeneration(for: goal.id)
        if reason.countsAsRefresh(isMember: isMember) {
            questionRefreshesUsed += 1
        }

        let providerPreference = consentFilteredProviderPreference(
            reason.providerPreference(defaultPreference: aiProviderPreference)
        )
        let requestedCount = min(
            targetCount ?? generationChunkCount(for: providerPreference),
            generationChunkCount(for: providerPreference)
        )
        let refreshRequest = generationRequest(
            goal: goal,
            existingQuestions: activeQuestions,
            competencies: activeCompetencies,
            reportedQuestions: activeQuestionReports,
            targetCount: requestedCount
        )
        let startedAt = Date()
        let batch = await questionEngine.generateQuestionBatch(
            for: refreshRequest,
            preference: providerPreference
        )
        let generatedQuestions = batch.questions
        guard let currentGoal = availableGoalProfiles.first(where: { $0.id == goal.id })
                ?? (self.goal?.id == goal.id ? self.goal : nil),
              currentGoal == goal else {
            finishQuestionGeneration(for: goal.id)
            return
        }

        let newQuestions = ingestGeneratedQuestions(generatedQuestions, for: currentGoal)
        let goalQuestions = questions.filter { $0.goalID == goal.id }
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
        questionBatchState = goalQuestions.isEmpty ? .failed : .ready
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

        if questionBankTopOffGoalIDs.contains(goal.id) {
            await waitForQuestionBankTopOffIfNeeded(for: goal.id)
            return !needsQuestionRefill(
                minimumQuestionCount: refillMinimum,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
            )
        }

        let shouldRefreshProactively = isMember
            && needsProactiveQuestionMaintenance(for: goal)
            && questionBankDeficit(for: goal, allowsEarlyCorrectReuse: allowsEarlyCorrectReuse) > 0
            && canRefreshAfterCooldown

        guard needsCoreRefill || shouldRefreshProactively else { return false }

        guard isMember else {
            checkpointNotice = starterQuestionLimitMessage
            lastAIErrorMessage = starterQuestionLimitMessage
            requestMembership(for: .freshQuestionGeneration)
            save()
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
        nextQuestion(
            excluding: [],
            sessionQuestions: [],
            reviewLimit: nil,
            prefersStretch: false,
            now: Date()
        )
    }

    func replacementQuestion(
        excluding excludedQuestionIDs: Set<CheckpointQuestion.ID>,
        alongside sessionQuestions: [CheckpointQuestion]
    ) -> CheckpointQuestion? {
        nextQuestion(
            excluding: excludedQuestionIDs,
            sessionQuestions: sessionQuestions,
            reviewLimit: nil,
            prefersStretch: false,
            now: Date()
        )
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

    func nextQuestions(
        limit: Int,
        allowsEarlyCorrectReuse: Bool = false,
        now: Date = Date()
    ) -> [CheckpointQuestion] {
        let maximumSessionQuestionCount = max(
            UnlockPolicy.maximumQuestionsPerSession,
            StopBlockingPolicy.questionsPerSession
        )
        let targetCount = min(maximumSessionQuestionCount, max(1, limit))
        let usesSessionBlueprint = targetCount >= UnlockPolicy.minimumQuestionsPerSession
        let reviewLimit = usesSessionBlueprint
            ? min(Int(ceil(Double(targetCount) * 0.40)), max(0, targetCount - 3))
            : nil
        var selectedQuestions: [CheckpointQuestion] = []
        var excludedQuestionIDs = Set<CheckpointQuestion.ID>()

        while selectedQuestions.count < targetCount,
              let question = nextQuestion(
                excluding: excludedQuestionIDs,
                sessionQuestions: selectedQuestions,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse,
                reviewLimit: reviewLimit,
                prefersStretch: usesSessionBlueprint && selectedQuestions.count == targetCount - 1,
                now: now
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
        sessionQuestions: [CheckpointQuestion],
        allowsEarlyCorrectReuse: Bool = false,
        reviewLimit: Int?,
        prefersStretch: Bool,
        now: Date
    ) -> CheckpointQuestion? {
        let availableQuestions = activeQuestions.filter { !excludedQuestionIDs.contains($0.id) }
        let preferredQuestions = availableQuestions.filter(meetsDifficultyFloor)
        return prioritizedNonCorrectQuestion(
            from: preferredQuestions,
            sessionQuestions: sessionQuestions,
            reviewLimit: reviewLimit,
            prefersStretch: prefersStretch,
            now: now
        )
            ?? prioritizedNonCorrectQuestion(
                from: availableQuestions,
                sessionQuestions: sessionQuestions,
                reviewLimit: reviewLimit,
                prefersStretch: prefersStretch,
                now: now
            )
            ?? prioritizedCorrectQuestion(
                from: preferredQuestions,
                sessionQuestions: sessionQuestions,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse,
                now: now
            )
            ?? prioritizedCorrectQuestion(
                from: availableQuestions,
                sessionQuestions: sessionQuestions,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse,
                now: now
            )
    }

    private func prioritizedNonCorrectQuestion(
        from availableQuestions: [CheckpointQuestion],
        sessionQuestions: [CheckpointQuestion],
        reviewLimit: Int?,
        prefersStretch: Bool,
        now: Date
    ) -> CheckpointQuestion? {
        let selectableQuestions = availableQuestions
            .filter(isSelectableQuestion)
            .filter { $0.status != .correct }
        let urgentReviewCount = sessionQuestions.filter { isUrgentReviewQuestion($0, now: now) }.count
        let canSelectUrgentReview = reviewLimit.map { urgentReviewCount < $0 } ?? true

        if canSelectUrgentReview {
            if let missed = selectableQuestions
                .filter({ $0.status == .incorrect && ($0.nextReviewAt ?? .distantPast) <= now })
                .sorted(by: { lhs, rhs in
                    sortBySessionDiversity(
                        lhs,
                        rhs,
                        sessionQuestions: sessionQuestions,
                        fallback: sortByReviewPriority
                    )
                })
                .first {
                return missed
            }

            if let due = selectableQuestions
                .filter({ ($0.nextReviewAt ?? .distantFuture) <= now })
                .sorted(by: { lhs, rhs in
                    sortBySessionDiversity(
                        lhs,
                        rhs,
                        sessionQuestions: sessionQuestions,
                        fallback: sortByReviewPriority
                    )
                })
                .first {
                return due
            }
        }

        let freshQuestions = selectableQuestions.filter { $0.status == .new }
        let stretchQuestion = freshQuestions
            .filter(isStretchQuestion)
            .sorted(by: { lhs, rhs in
                sortBySessionDiversity(
                    lhs,
                    rhs,
                    sessionQuestions: sessionQuestions,
                    fallback: sortByAdaptivePriority
                )
            })
            .first
        if prefersStretch, let stretchQuestion {
            return stretchQuestion
        }

        let nonStretchFreshQuestions = freshQuestions.filter { !isStretchQuestion($0) }
        let hasSelectedFreshQuestion = sessionQuestions.contains { $0.status == .new }
        let freshSelectionPool = reviewLimit != nil
            && hasSelectedFreshQuestion
            && !nonStretchFreshQuestions.isEmpty
            ? nonStretchFreshQuestions
            : freshQuestions
        let weakAreaQuestion = freshSelectionPool
            .sorted { lhs, rhs in
                if !hasSelectedFreshQuestion {
                    return sortByWeaknessThenDiversity(
                        lhs,
                        rhs,
                        sessionQuestions: sessionQuestions
                    )
                }
                return sortBySessionDiversity(
                    lhs,
                    rhs,
                    sessionQuestions: sessionQuestions,
                    fallback: sortByAdaptivePriority
                )
            }
            .first

        if let weakAreaQuestion {
            return weakAreaQuestion
        }

        if let reviewQuestion = selectableQuestions
            .filter({ $0.status != .correct })
            .sorted(by: { lhs, rhs in
                sortBySessionDiversity(
                    lhs,
                    rhs,
                    sessionQuestions: sessionQuestions,
                    fallback: sortByReviewPriority
                )
            })
            .first {
            return reviewQuestion
        }

        return nil
    }

    private func prioritizedCorrectQuestion(
        from availableQuestions: [CheckpointQuestion],
        sessionQuestions: [CheckpointQuestion],
        allowsEarlyCorrectReuse: Bool = false,
        now: Date
    ) -> CheckpointQuestion? {
        let selectableQuestions = availableQuestions
            .filter(isSelectableQuestion)
            .filter { $0.status == .correct }

        let reusableCorrectQuestions = selectableQuestions
            .filter { canReuseCorrectQuestion($0, now: now) }
            .sorted { lhs, rhs in
                sortBySessionDiversity(
                    lhs,
                    rhs,
                    sessionQuestions: sessionQuestions,
                    fallback: sortByCorrectReusePriority
                )
            }
            .first

        if let reusableCorrectQuestions {
            return reusableCorrectQuestions
        }

        guard allowsEarlyCorrectReuse else { return nil }

        return selectableQuestions
            .sorted { lhs, rhs in
                sortBySessionDiversity(
                    lhs,
                    rhs,
                    sessionQuestions: sessionQuestions,
                    fallback: sortByCorrectReusePriority
                )
            }
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
        updateCompetency(for: question, result: result, practicedAt: attempt.createdAt)

        if unlockMinutes > 0 {
            recordUnlockSession(minutes: unlockMinutes, goalID: goal.id)
        }

        scheduleQuestionBankMaintenanceIfNeeded(for: goal)
        save()
        publishShieldContext()
        if shouldPullServerQuestionReserve(for: goal) {
            scheduleServerQuestionReserveMaintenance()
        }
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
        let reserveConfiguration = resolvedQuestionReserveConfiguration
        let reserveGoalIDs = Array(availableGoalProfiles.prefix(5).map(\.id))
        let inFlightReserveTasks = serverQuestionReserveTasks.values.map(\.task)
        backgroundGenerationTasks.values.forEach { $0.cancel() }
        questionBankTopOffTasks.values.forEach { $0.cancel() }
        serverQuestionReserveTasks.values.forEach { $0.task.cancel() }
        backgroundGenerationTasks = [:]
        questionBankTopOffTasks = [:]
        serverQuestionReserveTasks = [:]
        backgroundGenerationGoalIDs = []
        questionBankTopOffGoalIDs = []
        goal = nil
        goalProfiles = []
        questions = []
        attempts = []
        competencies = []
        unlockEvents = []
        questionReports = []
        issueReports = []
        questionGenerationTraces = []
        pendingQuestionReserveAcknowledgements = []
        unlockPolicy = .default
        questionBatchState = .idle
        aiProviderPreference = .automatic
        lastQuestionProvider = .localTemplates
        backendEndpoint = ""
        backendQuestionGenerationConsentGranted = false
        serverQuestionReserveEnabled = false
        lastAIErrorMessage = nil
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
        persistenceRecoveryMessage = nil
        persistenceWritesBlockedByFutureSchema = false
        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: snapshotBackupKey)
        save()
        publishShieldContext()
        scheduleServerQuestionReserveDeletion(
            goalIDs: reserveGoalIDs,
            configuration: reserveConfiguration,
            resetsCredentials: true,
            waitingFor: inFlightReserveTasks
        )
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
            await attemptFastServerQuestionReservePullForShield()
            if let session = takePendingShieldSession() {
                return session
            }
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

        if let goal {
            await waitForQuestionBankTopOffIfNeeded(for: goal.id)
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

    func growthSummary(
        for session: CheckpointSession,
        answeredQuestionCount: Int,
        missedQuestionIDs: Set<CheckpointQuestion.ID>
    ) -> CheckpointGrowthSummary {
        let answeredQuestions = Array(
            session.questions.prefix(min(max(0, answeredQuestionCount), session.questions.count))
        )
        let usefulQuestions = answeredQuestions.filter { !hasInvalidatingQuestionReport($0) }
        let correctQuestions = usefulQuestions.filter { !missedQuestionIDs.contains($0.id) }
        let missedQuestions = usefulQuestions.filter { missedQuestionIDs.contains($0.id) }
        let nextQuestion = nextQuestions(limit: 1).first

        return CheckpointGrowthSummary(
            answeredCount: usefulQuestions.count,
            correctCount: correctQuestions.count,
            strengthenedTopic: mostRepresentedTopic(in: correctQuestions),
            reviewTopic: mostRepresentedTopic(in: missedQuestions),
            nextTopic: nextQuestion?.topic,
            nextAvenue: nextQuestion?.avenue,
            deadlineText: goal.map { Goal.deadlineDistanceText(until: $0.deadline) }
        )
    }

    func clearCheckpointNotice() {
        checkpointNotice = nil
    }

    // MARK: - Question reporting

    private func isLearningEvidence(_ attempt: CheckpointAttempt) -> Bool {
        !questionReports.contains {
            $0.goalID == attempt.goalID
                && $0.questionID == attempt.questionID
                && $0.reason.invalidatesLearningEvidence
        }
    }

    func hasReportedQuestion(_ question: CheckpointQuestion) -> Bool {
        questionReports.contains {
            $0.goalID == question.goalID && $0.questionID == question.id
        }
    }

    private func hasInvalidatingQuestionReport(_ question: CheckpointQuestion) -> Bool {
        questionReports.contains {
            $0.goalID == question.goalID
                && $0.questionID == question.id
                && $0.reason.invalidatesLearningEvidence
        }
    }

    func questionReport(for question: CheckpointQuestion) -> QuestionQualityReport? {
        questionReports.first {
            $0.goalID == question.goalID && $0.questionID == question.id
        }
    }

    @discardableResult
    func reportQuestion(_ question: CheckpointQuestion, reason: QuestionReportReason, note: String) -> Bool {
        guard let goal,
              goal.id == question.goalID,
              questions.contains(where: { $0.id == question.id && $0.goalID == goal.id }),
              !hasReportedQuestion(question) else {
            return false
        }

        let priorInvalidReportCount = questionReports.filter {
            $0.goalID == goal.id && $0.reason.invalidatesLearningEvidence
        }.count
        let replacementState: QuestionReportReplacementState?
        if reason.invalidatesLearningEvidence {
            replacementState = isMember
                || priorInvalidReportCount < ProductLimits.starterQuestionQualityReplacementLimit
                ? .pending
                : .notEligible
        } else {
            replacementState = nil
        }

        let report = QuestionQualityReport(
            questionID: question.id,
            goalID: goal.id,
            prompt: Self.boundedText(question.prompt, maximumLength: 280),
            reason: reason,
            note: Self.boundedText(
                note.trimmingCharacters(in: .whitespacesAndNewlines),
                maximumLength: Self.maximumQuestionReportNoteLength
            ),
            expectedAnswer: Self.boundedText(question.expectedAnswer, maximumLength: 280),
            choices: Array(question.choices.prefix(4)).map {
                Self.boundedText($0, maximumLength: 140)
            },
            explanation: Self.boundedText(question.explanation, maximumLength: 420),
            topic: Self.boundedText(question.topic, maximumLength: 48),
            subtopic: Self.boundedText(question.subtopic, maximumLength: 72),
            avenue: question.avenue,
            difficulty: question.difficulty,
            replacementState: replacementState
        )

        questionReports.insert(report, at: 0)

        if reason.invalidatesLearningEvidence,
           let index = questions.firstIndex(where: { $0.id == question.id }) {
            questions[index].status = .retired
            questions[index].nextReviewAt = nil
        }

        rebuildCompetencies(for: goal)

        save()
        publishShieldContext()
        if reason.invalidatesLearningEvidence {
            scheduleReportedQuestionReplacement(for: goal)
        }
        return true
    }

    private func hasPendingQuestionReportReplacement(for profile: Goal) -> Bool {
        pendingQuestionReportReplacementCount(for: profile) > 0
    }

    private func pendingQuestionReportReplacementCount(for profile: Goal) -> Int {
        questionReports.filter {
            $0.goalID == profile.id && $0.replacementState == .pending
        }.count
    }

    private func markQuestionReportReplacementsPrepared(for profile: Goal, count: Int) {
        guard count > 0 else { return }
        let compatibleQuestionIDs = Set(
            questions
                .filter { $0.goalID == profile.id && isQuestion($0, compatibleWith: profile) }
                .map(\.id)
        )
        var remainingCount = count
        for index in questionReports.indices where remainingCount > 0 {
            guard questionReports[index].goalID == profile.id,
                  questionReports[index].replacementState == .pending,
                  compatibleQuestionIDs.contains(questionReports[index].questionID) else {
                continue
            }
            questionReports[index].replacementState = .prepared
            remainingCount -= 1
        }
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

    func clearCheckpointRetryCooldown() {
        guard checkpointRetryCooldownUntil != nil else { return }
        checkpointRetryCooldownUntil = nil
        checkpointNotice = nil
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
                checkpointNotice = "Question level updated. Pro can prepare harder checkpoints for this goal."
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

    var isBackendQuestionGenerationConfigured: Bool {
        rawQuestionReserveConfiguration != nil
    }

    var isServerQuestionReserveConfigured: Bool {
        rawQuestionReserveConfiguration != nil
    }

    func updateBackendQuestionGenerationConsent(_ isGranted: Bool) {
        if isGranted {
            guard rawQuestionReserveConfiguration != nil else { return }
            backendQuestionGenerationConsentGranted = true
            save()
            return
        }

        // Capture the consented configuration before closing the gate so the
        // already-authorized server data can be deleted as part of withdrawal.
        let configuration = resolvedQuestionReserveConfiguration
        let goalIDs = Array(availableGoalProfiles.prefix(5).map(\.id))
        let inFlightReserveTasks = serverQuestionReserveTasks.values.map(\.task)
        backendQuestionGenerationConsentGranted = false
        serverQuestionReserveEnabled = false
        backgroundGenerationTasks.values.forEach { $0.cancel() }
        questionBankTopOffTasks.values.forEach { $0.cancel() }
        serverQuestionReserveTasks.values.forEach { $0.task.cancel() }
        serverQuestionReserveTasks = [:]
        pendingQuestionReserveAcknowledgements = []
        save()
        scheduleServerQuestionReserveDeletion(
            goalIDs: goalIDs,
            configuration: configuration,
            resetsCredentials: true,
            waitingFor: inFlightReserveTasks
        )
    }

    func updateServerQuestionReserveEnabled(_ isEnabled: Bool) {
        if isEnabled {
            guard isMember else {
                checkpointNotice = "Cloud question reserve is included with Pro."
                requestMembership(for: .freshQuestionGeneration)
                save()
                return
            }
            guard rawQuestionReserveConfiguration != nil else { return }
            backendQuestionGenerationConsentGranted = true
            serverQuestionReserveEnabled = true
            save()
            scheduleServerQuestionReserveMaintenance()
            return
        }

        let configuration = resolvedQuestionReserveConfiguration
        let goalIDs = Array(availableGoalProfiles.prefix(5).map(\.id))
        let inFlightReserveTasks = serverQuestionReserveTasks.values.map(\.task)
        serverQuestionReserveEnabled = false
        serverQuestionReserveTasks.values.forEach { $0.task.cancel() }
        serverQuestionReserveTasks = [:]
        pendingQuestionReserveAcknowledgements = []
        save()
        scheduleServerQuestionReserveDeletion(
            goalIDs: goalIDs,
            configuration: configuration,
            resetsCredentials: true,
            waitingFor: inFlightReserveTasks
        )
    }

    func scheduleServerQuestionReserveMaintenance() {
        guard serverQuestionReserveEnabled, isMember else { return }
        for profile in availableGoalProfiles {
            _ = startServerQuestionReserveMaintenance(
                for: profile,
                desiredCount: Self.memberServerQuestionReserveCount
            )
        }
    }

    func performServerQuestionReserveMaintenance() async {
        guard serverQuestionReserveEnabled else { return }
        if !isMember {
            let purgeTasks = availableGoalProfiles.compactMap {
                startServerQuestionReserveMaintenance(for: $0, desiredCount: 0)
            }
            for task in purgeTasks {
                await task.value
            }
            return
        }
        let tasks = availableGoalProfiles.compactMap {
            startServerQuestionReserveMaintenance(
                for: $0,
                desiredCount: Self.memberServerQuestionReserveCount
            )
        }
        for task in tasks {
            await task.value
        }
    }

    private func startServerQuestionReserveMaintenance(
        for profile: Goal,
        desiredCount: Int
    ) -> Task<Void, Never>? {
        guard serverQuestionReserveEnabled,
              let configuration = resolvedQuestionReserveConfiguration else {
            return nil
        }
        if desiredCount > 0, !isMember { return nil }

        let revision = QuestionReserveGoalRevision.value(for: profile)
        if let existing = serverQuestionReserveTasks[profile.id],
           existing.revision == revision,
           existing.desiredCount == desiredCount {
            return existing.task
        }
        serverQuestionReserveTasks[profile.id]?.task.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performServerQuestionReserveMaintenance(
                for: profile,
                expectedRevision: revision,
                desiredCount: desiredCount,
                configuration: configuration
            )
            self.finishServerQuestionReserveTask(
                goalID: profile.id,
                revision: revision,
                desiredCount: desiredCount
            )
        }
        serverQuestionReserveTasks[profile.id] = (
            revision: revision,
            desiredCount: desiredCount,
            task: task
        )
        return task
    }

    private func finishServerQuestionReserveTask(
        goalID: Goal.ID,
        revision: String,
        desiredCount: Int
    ) {
        guard let activeTask = serverQuestionReserveTasks[goalID],
              activeTask.revision == revision,
              activeTask.desiredCount == desiredCount else {
            return
        }
        serverQuestionReserveTasks[goalID] = nil
    }

    private func performServerQuestionReserveMaintenance(
        for requestedGoal: Goal,
        expectedRevision: String,
        desiredCount: Int,
        configuration: QuestionReserveConfiguration
    ) async {
        guard !Task.isCancelled,
              let currentGoal = currentGoalProfile(id: requestedGoal.id),
              QuestionReserveGoalRevision.value(for: currentGoal) == expectedRevision else {
            return
        }

        let syncRequest = generationRequest(
            goal: currentGoal,
            existingQuestions: questions.filter { $0.goalID == currentGoal.id },
            competencies: competencies.filter { ($0.goalID ?? currentGoal.id) == currentGoal.id },
            reportedQuestions: questionReports.filter { $0.goalID == currentGoal.id },
            targetCount: max(1, desiredCount)
        )

        do {
            try await questionReserveService.sync(
                goalID: currentGoal.id,
                goalRevision: expectedRevision,
                desiredReserveCount: desiredCount,
                generationRequest: syncRequest,
                configuration: configuration
            )
        } catch {
            await retryPendingQuestionReserveAcknowledgement(
                for: currentGoal.id,
                configuration: configuration
            )
            return
        }

        if desiredCount == 0 {
            clearPendingQuestionReserveAcknowledgement(for: currentGoal.id)
            return
        }

        // A delivery may already be safely stored locally even when its prior
        // acknowledgement failed. Retry it before the bank-health gate so a
        // healthy local bank cannot leave the server's held batch stranded.
        await retryPendingQuestionReserveAcknowledgement(
            for: currentGoal.id,
            configuration: configuration
        )

        guard !Task.isCancelled,
              let goalAfterSync = currentGoalProfile(id: requestedGoal.id),
              QuestionReserveGoalRevision.value(for: goalAfterSync) == expectedRevision,
              isMember,
              shouldPullServerQuestionReserve(for: goalAfterSync) else {
            return
        }

        let delivery: QuestionReserveDelivery?
        do {
            delivery = try await questionReserveService.pull(
                goalID: goalAfterSync.id,
                goalRevision: expectedRevision,
                configuration: configuration
            )
        } catch {
            return
        }

        guard !Task.isCancelled,
              let delivery,
              let goalAfterPull = currentGoalProfile(id: requestedGoal.id),
              QuestionReserveGoalRevision.value(for: goalAfterPull) == expectedRevision,
              delivery.goalRevision == expectedRevision else {
            return
        }

        let ingestionRequest = generationRequest(
            goal: goalAfterPull,
            existingQuestions: questions.filter { $0.goalID == goalAfterPull.id },
            competencies: competencies.filter { ($0.goalID ?? goalAfterPull.id) == goalAfterPull.id },
            reportedQuestions: questionReports.filter { $0.goalID == goalAfterPull.id },
            targetCount: max(1, delivery.questions.count)
        )
        let compactSource = "Server reserve delivery • revision \(expectedRevision.prefix(12))"
        let deliveredQuestions = delivery.questions.map {
            $0.makeQuestion(
                goalID: goalAfterPull.id,
                sourcePrompt: compactSource
            )
        }
        let sanitizedQuestions = QuestionBatchSanitizer.sanitize(
            deliveredQuestions,
            for: ingestionRequest,
            enforceCoveragePlan: false
        )

        let pendingAcknowledgement = PendingQuestionReserveAcknowledgement(
            goalID: goalAfterPull.id,
            goalRevision: expectedRevision,
            deliveryID: delivery.deliveryID
        )
        guard persistIngestedQuestions(
            sanitizedQuestions,
            for: goalAfterPull,
            pendingAcknowledgement: pendingAcknowledgement
        ) else {
            return
        }

        guard !Task.isCancelled,
              let goalBeforeAcknowledgement = currentGoalProfile(id: requestedGoal.id),
              QuestionReserveGoalRevision.value(for: goalBeforeAcknowledgement) == expectedRevision else {
            return
        }

        await retryPendingQuestionReserveAcknowledgement(
            for: goalBeforeAcknowledgement.id,
            configuration: configuration
        )
    }

    private func shouldPullServerQuestionReserve(for profile: Goal) -> Bool {
        usableQuestionCount(for: profile) < Self.serverReservePullUsableThreshold
            || freshReadyQuestionCount(for: profile) < Self.serverReservePullFreshThreshold
    }

    private func attemptFastServerQuestionReservePullForShield() async {
        guard serverQuestionReserveEnabled,
              isMember,
              let goal,
              shouldPullServerQuestionReserve(for: goal),
              let maintenanceTask = startServerQuestionReserveMaintenance(
                for: goal,
                desiredCount: Self.memberServerQuestionReserveCount
              ) else {
            return
        }

        let completedBeforeTimeout = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await maintenanceTask.value
                return true
            }
            group.addTask {
                try? await Task.sleep(
                    nanoseconds: Self.shieldReserveFastPathTimeoutNanoseconds
                )
                return false
            }
            let completed = await group.next() ?? false
            if !completed {
                maintenanceTask.cancel()
            }
            group.cancelAll()
            return completed
        }

        if !completedBeforeTimeout {
            finishServerQuestionReserveTask(
                goalID: goal.id,
                revision: QuestionReserveGoalRevision.value(for: goal),
                desiredCount: Self.memberServerQuestionReserveCount
            )
        }
    }

    private func persistIngestedQuestions(
        _ candidateQuestions: [CheckpointQuestion],
        for profile: Goal,
        pendingAcknowledgement: PendingQuestionReserveAcknowledgement
    ) -> Bool {
        let previousQuestions = questions
        let previousCompetencies = competencies
        let previousPendingAcknowledgements = pendingQuestionReserveAcknowledgements
        _ = ingestGeneratedQuestions(candidateQuestions, for: profile)
        pendingQuestionReserveAcknowledgements.removeAll {
            $0.goalID == pendingAcknowledgement.goalID
        }
        pendingQuestionReserveAcknowledgements.append(pendingAcknowledgement)
        guard save() else {
            questions = previousQuestions
            competencies = previousCompetencies
            pendingQuestionReserveAcknowledgements = previousPendingAcknowledgements
            return false
        }
        publishShieldContext()
        return true
    }

    private func retryPendingQuestionReserveAcknowledgement(
        for goalID: Goal.ID,
        configuration: QuestionReserveConfiguration
    ) async {
        guard !Task.isCancelled,
              let pendingAcknowledgement = pendingQuestionReserveAcknowledgements.first(where: {
                  $0.goalID == goalID
              }) else {
            return
        }

        do {
            try await questionReserveService.acknowledge(
                goalID: pendingAcknowledgement.goalID,
                goalRevision: pendingAcknowledgement.goalRevision,
                deliveryID: pendingAcknowledgement.deliveryID,
                configuration: configuration
            )
        } catch {
            return
        }

        guard pendingQuestionReserveAcknowledgements.contains(pendingAcknowledgement) else {
            return
        }
        let previousPendingAcknowledgements = pendingQuestionReserveAcknowledgements
        pendingQuestionReserveAcknowledgements.removeAll { $0 == pendingAcknowledgement }
        if !save() {
            pendingQuestionReserveAcknowledgements = previousPendingAcknowledgements
        }
    }

    private func clearPendingQuestionReserveAcknowledgement(for goalID: Goal.ID) {
        guard pendingQuestionReserveAcknowledgements.contains(where: { $0.goalID == goalID }) else {
            return
        }
        let previousPendingAcknowledgements = pendingQuestionReserveAcknowledgements
        pendingQuestionReserveAcknowledgements.removeAll { $0.goalID == goalID }
        if !save() {
            pendingQuestionReserveAcknowledgements = previousPendingAcknowledgements
        }
    }

    @discardableResult
    private func ingestGeneratedQuestions(
        _ candidateQuestions: [CheckpointQuestion],
        for profile: Goal
    ) -> [CheckpointQuestion] {
        var existingIDs = Set(questions.filter { $0.goalID == profile.id }.map(\.id))
        var existingKeys = Set(questions.filter { $0.goalID == profile.id }.map(questionKey))
        var addedQuestions: [CheckpointQuestion] = []
        for question in candidateQuestions where question.difficulty >= profile.minimumQuestionDifficulty {
            let key = questionKey(question)
            guard !existingIDs.contains(question.id), !existingKeys.contains(key) else { continue }
            existingIDs.insert(question.id)
            existingKeys.insert(key)
            addedQuestions.append(questionStampedForCurrentContext(question, goal: profile))
        }
        questions.append(contentsOf: addedQuestions)
        if !addedQuestions.isEmpty {
            rebuildCompetencies(for: profile)
        }
        return addedQuestions
    }

    private func currentGoalProfile(id: Goal.ID) -> Goal? {
        availableGoalProfiles.first(where: { $0.id == id })
            ?? (goal?.id == id ? goal : nil)
    }

    private func scheduleServerQuestionReserveDeletion(
        goalIDs: [Goal.ID],
        configuration: QuestionReserveConfiguration?,
        resetsCredentials: Bool,
        waitingFor tasks: [Task<Void, Never>] = []
    ) {
        let service = questionReserveService
        Task {
            for task in tasks {
                await task.value
            }
            if let configuration, !goalIDs.isEmpty {
                try? await service.delete(goalIDs: goalIDs, configuration: configuration)
            }
            if resetsCredentials {
                await service.resetCredentialsAndRotateIdentity()
            }
        }
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

    private func updateCompetency(
        for question: CheckpointQuestion,
        result: AnswerResult,
        practicedAt: Date = Date()
    ) {
        for topic in competencyTopics(from: question.topic) {
            updateCompetency(
                topic: topic,
                goalID: question.goalID,
                questionDifficulty: question.difficulty,
                result: result,
                practicedAt: practicedAt
            )
        }
    }

    private func updateCompetency(
        topic: String,
        goalID: Goal.ID,
        questionDifficulty: Int,
        result: AnswerResult,
        practicedAt: Date
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
        competencies[index].lastPracticedAt = practicedAt

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

    private func rebuildCompetencies(for profile: Goal) {
        let invalidReportedQuestionIDs = Set(
            questionReports
                .filter { $0.goalID == profile.id && $0.reason.invalidatesLearningEvidence }
                .map(\.questionID)
        )
        let profileQuestions = questions.filter {
            $0.goalID == profile.id && isQuestion($0, compatibleWith: profile)
        }
        let questionsByID = Dictionary(uniqueKeysWithValues: profileQuestions.map { ($0.id, $0) })

        competencies.removeAll {
            $0.goalID == profile.id || ($0.goalID == nil && goal?.id == profile.id)
        }
        competencies.append(contentsOf: initialCompetencies(for: profile, questions: profileQuestions))

        let validAttempts = attempts
            .filter { $0.goalID == profile.id && !invalidReportedQuestionIDs.contains($0.questionID) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }

        for attempt in validAttempts {
            guard let attemptedQuestion = questionsByID[attempt.questionID] else { continue }
            updateCompetency(
                for: attemptedQuestion,
                result: attempt.result,
                practicedAt: attempt.createdAt
            )
        }


        let difficultyFeedback = questionReports
            .filter {
                $0.goalID == profile.id
                    && !$0.reason.invalidatesLearningEvidence
                    && $0.reason.estimatedLevelAdjustment != 0
            }
            .sorted { $0.createdAt < $1.createdAt }

        for report in difficultyFeedback {
            guard let reportedQuestion = questionsByID[report.questionID] else { continue }
            for topic in competencyTopics(from: reportedQuestion.topic) {
                let topicKey = competencyTopicKey(topic)
                guard let index = competencies.firstIndex(where: {
                    competencyTopicKey($0.topic) == topicKey
                        && ($0.goalID == profile.id || $0.goalID == nil)
                }) else { continue }
                competencies[index].estimatedLevel = min(
                    5,
                    max(1, competencies[index].estimatedLevel + report.reason.estimatedLevelAdjustment)
                )
            }
        }
    }

    private func sortByReviewPriority(_ lhs: CheckpointQuestion, _ rhs: CheckpointQuestion) -> Bool {
        if lhs.difficulty != rhs.difficulty {
            return lhs.difficulty < rhs.difficulty
        }
        let lhsReviewAt = lhs.nextReviewAt ?? .distantPast
        let rhsReviewAt = rhs.nextReviewAt ?? .distantPast
        if lhsReviewAt != rhsReviewAt {
            return lhsReviewAt < rhsReviewAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func mostRepresentedTopic(in questions: [CheckpointQuestion]) -> String? {
        guard !questions.isEmpty else { return nil }
        let groupedTopics = Dictionary(grouping: questions) { questionTopicKey($0.topic) }
        return groupedTopics
            .compactMap { key, questions -> (key: String, count: Int, display: String)? in
                guard let display = questions.first?.topic else { return nil }
                return (key, questions.count, display)
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.key < rhs.key
            }
            .first?
            .display
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

        if lhs.timesCorrect != rhs.timesCorrect {
            return lhs.timesCorrect < rhs.timesCorrect
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func sortByWeaknessThenDiversity(
        _ lhs: CheckpointQuestion,
        _ rhs: CheckpointQuestion,
        sessionQuestions: [CheckpointQuestion]
    ) -> Bool {
        let lhsMastery = competency(for: lhs.topic).masteryPercent
        let rhsMastery = competency(for: rhs.topic).masteryPercent
        if lhsMastery != rhsMastery {
            return lhsMastery < rhsMastery
        }
        return sortBySessionDiversity(
            lhs,
            rhs,
            sessionQuestions: sessionQuestions,
            fallback: sortByAdaptivePriority
        )
    }

    private func sortBySessionDiversity(
        _ lhs: CheckpointQuestion,
        _ rhs: CheckpointQuestion,
        sessionQuestions: [CheckpointQuestion],
        fallback: (CheckpointQuestion, CheckpointQuestion) -> Bool
    ) -> Bool {
        let lhsRank = sessionDiversityRank(lhs, comparedWith: sessionQuestions)
        let rhsRank = sessionDiversityRank(rhs, comparedWith: sessionQuestions)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        let lhsRecentAvenueCount = recentAvenueExposureCount(for: lhs.avenue)
        let rhsRecentAvenueCount = recentAvenueExposureCount(for: rhs.avenue)
        if lhsRecentAvenueCount != rhsRecentAvenueCount {
            return lhsRecentAvenueCount < rhsRecentAvenueCount
        }
        return fallback(lhs, rhs)
    }

    private func sessionDiversityRank(
        _ question: CheckpointQuestion,
        comparedWith sessionQuestions: [CheckpointQuestion]
    ) -> Int {
        guard !sessionQuestions.isEmpty else { return 0 }

        let topicKey = questionTopicKey(question.topic)
        let subtopicKey = competencyTopicKey(question.subtopic)
        let topicWasUsed = sessionQuestions.contains { questionTopicKey($0.topic) == topicKey }
        let subtopicWasUsed = sessionQuestions.contains {
            competencyTopicKey($0.subtopic) == subtopicKey
        }
        let avenueWasUsed = sessionQuestions.contains { $0.avenue == question.avenue }
        let exactCoverageWasUsed = sessionQuestions.contains {
            questionTopicKey($0.topic) == topicKey
                && competencyTopicKey($0.subtopic) == subtopicKey
                && $0.avenue == question.avenue
        }

        if !topicWasUsed && !avenueWasUsed { return 0 }
        if !topicWasUsed { return 1 }
        if !subtopicWasUsed && !avenueWasUsed { return 2 }
        if !avenueWasUsed { return 3 }
        if !subtopicWasUsed { return 4 }
        if !exactCoverageWasUsed { return 5 }
        return 6
    }

    private func recentAvenueExposureCount(for avenue: QuestionAvenue) -> Int {
        let recentQuestionIDs = Set(activeAttempts.prefix(20).map(\.questionID))
        return activeQuestions.filter {
            recentQuestionIDs.contains($0.id) && $0.avenue == avenue
        }.count
    }

    private func isUrgentReviewQuestion(_ question: CheckpointQuestion, now: Date) -> Bool {
        if question.status == .incorrect {
            return (question.nextReviewAt ?? .distantPast) <= now
        }
        return question.status != .correct
            && (question.nextReviewAt ?? .distantFuture) <= now
    }

    private func isStretchQuestion(_ question: CheckpointQuestion) -> Bool {
        if Double(question.difficulty) > targetDifficulty(for: competency(for: question.topic)) {
            return true
        }

        switch question.avenue {
        case .comparison, .misconceptionDiagnosis, .edgeCase, .transfer, .interpretation:
            return true
        case .foundationalConcept, .application:
            return false
        }
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

        if lhs.difficulty != rhs.difficulty {
            return lhs.difficulty < rhs.difficulty
        }
        return lhs.id.uuidString < rhs.id.uuidString
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

    private func removeGoalData(for goalID: Goal.ID, includeLegacyCompetencies: Bool = false) {
        questions.removeAll { $0.goalID == goalID }
        attempts.removeAll { $0.goalID == goalID }
        competencies.removeAll { $0.goalID == goalID || (includeLegacyCompetencies && $0.goalID == nil) }
        questionReports.removeAll { $0.goalID == goalID }
        unlockEvents.removeAll { $0.goalID == goalID }
        pendingQuestionReserveAcknowledgements.removeAll { $0.goalID == goalID }
    }

    @discardableResult
    private func cancelQuestionMaintenance(for goalID: Goal.ID) -> Task<Void, Never>? {
        let reserveTask = serverQuestionReserveTasks[goalID]?.task
        backgroundGenerationTasks[goalID]?.cancel()
        questionBankTopOffTasks[goalID]?.cancel()
        reserveTask?.cancel()
        serverQuestionReserveTasks[goalID] = nil
        return reserveTask
    }

    private func awaitQuestionMaintenanceTask(_ task: Task<Void, Never>) async {
        await withTaskCancellationHandler(operation: {
            await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    private func setInitialQuestionProvisioningCompleted(_ isCompleted: Bool, for goalID: Goal.ID) {
        if let index = goalProfiles.firstIndex(where: { $0.id == goalID }) {
            goalProfiles[index].hasCompletedInitialQuestionProvisioning = isCompleted
        }
        if var activeGoal = goal, activeGoal.id == goalID,
           activeGoal.hasCompletedInitialQuestionProvisioning != isCompleted {
            activeGoal.hasCompletedInitialQuestionProvisioning = isCompleted
            goal = activeGoal
        }
    }

    private func markInitialQuestionProvisioningCompleteIfNeeded(for goalID: Goal.ID) {
        let provisionedQuestionCount = questions.filter {
            $0.goalID == goalID && $0.status != .retired
        }.count
        guard provisionedQuestionCount >= ProductLimits.starterQuestionBankTargetCount else { return }
        setInitialQuestionProvisioningCompleted(true, for: goalID)
        save()
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

    private func retireActiveQuestionsAboveDifficulty(_ difficulty: Int) {
        guard let goalID = goal?.id else { return }

        for index in questions.indices
        where questions[index].goalID == goalID
            && questions[index].difficulty > difficulty
            && questions[index].status != .retired {
            questions[index].status = .retired
            questions[index].nextReviewAt = nil
        }
    }

    private func migrateLegacyCompetenciesToActiveGoal() {
        guard let goalID = goal?.id else { return }

        for index in competencies.indices where competencies[index].goalID == nil {
            competencies[index].goalID = goalID
        }
    }

    // MARK: - Persistence and app group state

    @discardableResult
    private func save() -> Bool {
        guard !persistenceWritesBlockedByFutureSchema else { return false }

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
            aiProviderPreference: aiProviderPreference,
            lastQuestionProvider: lastQuestionProvider,
            backendEndpoint: backendEndpoint,
            backendQuestionGenerationConsentGranted: backendQuestionGenerationConsentGranted,
            serverQuestionReserveEnabled: serverQuestionReserveEnabled,
            pendingQuestionReserveAcknowledgements: pendingQuestionReserveAcknowledgements,
            unlockSession: unlockSession,
            checkpointRetryCooldownUntil: checkpointRetryCooldownUntil,
            membershipTier: membershipTier,
            questionRefreshesUsed: questionRefreshesUsed,
            lastAutomaticQuestionRefreshAt: lastAutomaticQuestionRefreshAt,
            schemaVersion: AppSnapshot.currentSchemaVersion,
            savedAt: Date()
        )

        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            persistenceRecoveryMessage = "The latest save could not be encoded. The previous saved state remains available."
            return false
        }

        if let existingData = defaults.data(forKey: snapshotKey),
           decodeSupportedSnapshot(from: existingData) != nil {
            defaults.set(existingData, forKey: snapshotBackupKey)
        }
        defaults.set(data, forKey: snapshotKey)
        return defaults.data(forKey: snapshotKey) == data
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
        if !isMember, goal != nil, usableQuestionCount < unlockPolicy.questionsPerSession {
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
            if !isMember {
                return "Your Free checkpoints are complete. Pro keeps new practice ready when you need more."
            }

            return source == .blockedApp
                ? "Checkpoint opened from a protected app, but no questions are ready yet."
                : "No questions are ready yet."
        }

        if !isMember && usableQuestionCount == 0 {
            return "Your first Free practice set has done its job. Pro keeps new checkpoints coming."
        }

        return "Checkpoint is preparing more questions. Try again in a moment or lower the minimum level."
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

    private func recoverTransientQuestionGenerationState(resumesGeneration: Bool) {
        if questionBatchState == .generating {
            questionGenerationStartedAt = nil
            lastQuestionGenerationDuration = nil
            questionBatchState = activeQuestions.isEmpty ? .idle : .ready
            save()

            if resumesGeneration,
               activeQuestions.isEmpty,
               let goal,
               isMember || !goal.hasCompletedInitialQuestionProvisioning {
                prepareInitialQuestionsInBackground(for: goal)
            }
        } else if questionBatchState == .failed, hasReadyCheckpointSet {
            questionBatchState = .ready
            save()
        }
    }

    private func resumeQuestionBankMaintenanceIfNeeded() {
        guard let goal,
              questionBatchState != .generating,
              !backgroundGenerationGoalIDs.contains(goal.id),
              !questionBankTopOffGoalIDs.contains(goal.id),
              questionBankDeficit(for: goal) > 0 else {
            return
        }

        if isMember, needsProactiveQuestionMaintenance(for: goal) {
            topOffQuestionBankInBackground(for: goal)
            return
        }

        if hasPendingQuestionReportReplacement(for: goal) {
            topOffQuestionBankInBackground(
                for: goal,
                maximumBatches: 1,
                allowsStarterQuestionReplacement: !isMember
            )
            return
        }

        if isInterruptedStarterTopOff(for: goal) {
            let starterQuestionIDs = Set(
                questions
                    .filter { $0.goalID == goal.id && $0.status != .retired }
                    .map(\.id)
            )
            topOffQuestionBankInBackground(for: goal, starterQuestionIDs: starterQuestionIDs)
        }
    }

    @discardableResult
    func performBackgroundQuestionMaintenance(maximumBatchCount: Int) async -> Bool {
        async let reserveMaintenance: Void = performServerQuestionReserveMaintenance()
        async let localMaintenance = performLocalBackgroundQuestionMaintenance(
            maximumBatchCount: maximumBatchCount
        )
        let localMaintenanceSucceeded = await localMaintenance
        await reserveMaintenance
        return localMaintenanceSucceeded
    }

    private func performLocalBackgroundQuestionMaintenance(maximumBatchCount: Int) async -> Bool {
        guard maximumBatchCount > 0 else { return true }

        let candidateGoals: [Goal]
        if isMember {
            candidateGoals = availableGoalProfiles.sorted { lhs, rhs in
                if lhs.id == goal?.id { return true }
                if rhs.id == goal?.id { return false }
                return freshReadyQuestionCount(for: lhs) < freshReadyQuestionCount(for: rhs)
            }
        } else if let goal,
                  isInterruptedStarterTopOff(for: goal)
                    || hasPendingQuestionReportReplacement(for: goal) {
            candidateGoals = [goal]
        } else {
            return true
        }

        var remainingBatchCount = maximumBatchCount
        var attemptedWork = false
        var madeProgress = false
        var goalsThatMadeNoProgress = Set<Goal.ID>()

        while remainingBatchCount > 0, !Task.isCancelled {
            var attemptedRound = false

            for candidate in candidateGoals where remainingBatchCount > 0 && !Task.isCancelled {
                guard !goalsThatMadeNoProgress.contains(candidate.id),
                      let profile = availableGoalProfiles.first(where: { $0.id == candidate.id })
                        ?? (goal?.id == candidate.id ? goal : nil) else {
                    continue
                }

                let existingGenerationTask = backgroundGenerationTasks[profile.id]
                let existingTopOffTask = questionBankTopOffTasks[profile.id]
                let needsNewMaintenance: Bool
                if isMember {
                    needsNewMaintenance = hasPendingQuestionReportReplacement(for: profile)
                        || (questionBankDeficit(for: profile) > 0
                            && needsProactiveQuestionMaintenance(for: profile))
                } else {
                    needsNewMaintenance = profile.id == goal?.id
                        && (isInterruptedStarterTopOff(for: profile)
                            || hasPendingQuestionReportReplacement(for: profile))
                }

                guard existingGenerationTask != nil
                        || existingTopOffTask != nil
                        || needsNewMaintenance else {
                    continue
                }

                let readyCountBefore = readyQuestionCount(for: profile)
                let maintenanceTask: Task<Void, Never>?
                if let existingGenerationTask {
                    maintenanceTask = existingGenerationTask
                } else if let existingTopOffTask {
                    maintenanceTask = existingTopOffTask
                } else {
                    let starterQuestionIDs = isInterruptedStarterTopOff(for: profile)
                        ? Set(questions.filter { $0.goalID == profile.id && $0.status != .retired }.map(\.id))
                        : []
                    maintenanceTask = startQuestionBankTopOff(
                        for: profile,
                        starterQuestionIDs: starterQuestionIDs,
                        providerPreference: questionBankMaintenanceProviderPreference(for: profile),
                        maximumBatches: 1,
                        allowsStarterQuestionReplacement: !isMember
                            && hasPendingQuestionReportReplacement(for: profile)
                    )
                }

                guard let maintenanceTask else {
                    goalsThatMadeNoProgress.insert(profile.id)
                    continue
                }

                attemptedWork = true
                attemptedRound = true
                remainingBatchCount -= 1
                await awaitQuestionMaintenanceTask(maintenanceTask)

                guard !Task.isCancelled else { break }
                if let latestProfile = availableGoalProfiles.first(where: { $0.id == profile.id })
                    ?? (goal?.id == profile.id ? goal : nil),
                   readyQuestionCount(for: latestProfile) > readyCountBefore {
                    madeProgress = true
                } else {
                    goalsThatMadeNoProgress.insert(profile.id)
                }
            }

            guard attemptedRound else { break }
        }

        let stillNeedsWork = candidateGoals.contains { candidate in
            guard let profile = availableGoalProfiles.first(where: { $0.id == candidate.id })
                    ?? (goal?.id == candidate.id ? goal : nil) else {
                return false
            }
            if isMember {
                return hasPendingQuestionReportReplacement(for: profile)
                    || (questionBankDeficit(for: profile) > 0
                        && needsProactiveQuestionMaintenance(for: profile))
            }
            return profile.id == goal?.id
                && (isInterruptedStarterTopOff(for: profile)
                    || hasPendingQuestionReportReplacement(for: profile))
        }
        if stillNeedsWork, !Task.isCancelled {
            QuestionBankBackgroundScheduler.schedule()
        }

        return !Task.isCancelled && (!attemptedWork || madeProgress)
    }

    private func isInterruptedStarterTopOff(for profile: Goal) -> Bool {
        guard !isMember else { return false }
        let profileQuestions = questions.filter { $0.goalID == profile.id && $0.status != .retired }
        return !profile.hasCompletedInitialQuestionProvisioning
            && profileQuestions.count < ProductLimits.starterQuestionBankTargetCount
    }

    private func waitForQuestionBankTopOffIfNeeded(for goalID: Goal.ID) async {
        if let task = questionBankTopOffTasks[goalID] {
            await awaitQuestionMaintenanceTask(task)
            return
        }

        var attempts = 0
        while questionBankTopOffGoalIDs.contains(goalID),
              attempts < Self.questionBankTopOffWaitAttemptCount {
            try? await Task.sleep(nanoseconds: Self.questionBankTopOffWaitIntervalNanoseconds)
            attempts += 1
        }
    }

    private func load() {
        let primaryData = defaults.data(forKey: snapshotKey)
        let backupData = defaults.data(forKey: snapshotBackupKey)
        let snapshot: AppSnapshot
        let primarySnapshot = primaryData.flatMap { decodeSupportedSnapshot(from: $0) }

        if let primaryData,
           let primarySchemaVersion = snapshotSchemaVersion(in: primaryData),
           primarySchemaVersion > AppSnapshot.currentSchemaVersion {
            persistenceWritesBlockedByFutureSchema = true
            persistenceRecoveryMessage = "Saved learning data was created by a newer Checkpoint version. It was left untouched; update the app to open it safely."
            return
        }

        if let primarySnapshot {
            snapshot = primarySnapshot
        } else if let backupData,
                  let backupSchemaVersion = snapshotSchemaVersion(in: backupData),
                  backupSchemaVersion > AppSnapshot.currentSchemaVersion {
            persistenceWritesBlockedByFutureSchema = true
            persistenceRecoveryMessage = "A backup was created by a newer Checkpoint version. It was left untouched; update the app to recover it safely."
            return
        } else if let backupData, let backupSnapshot = decodeSupportedSnapshot(from: backupData) {
            snapshot = backupSnapshot
            defaults.set(backupData, forKey: snapshotKey)
            persistenceRecoveryMessage = "Checkpoint recovered the previous valid saved state after the latest snapshot could not be read."
        } else {
            if primaryData != nil || backupData != nil {
                persistenceRecoveryMessage = "Saved learning data could not be read. The original snapshots were preserved for support."
            }
            return
        }

        questions = snapshot.questions
        attempts = snapshot.attempts
        competencies = snapshot.competencies
        unlockEvents = snapshot.unlockEvents ?? []
        questionReports = snapshot.questionReports ?? []
        issueReports = snapshot.issueReports ?? []
        questionGenerationTraces = snapshot.questionGenerationTraces ?? []
        unlockPolicy = snapshot.unlockPolicy ?? .default
        questionBatchState = snapshot.questionBatchState ?? .idle
        aiProviderPreference = snapshot.aiProviderPreference ?? .automatic
        lastQuestionProvider = snapshot.lastQuestionProvider ?? .localTemplates
        backendEndpoint = snapshot.backendEndpoint ?? ""
        backendQuestionGenerationConsentGranted = snapshot.backendQuestionGenerationConsentGranted ?? false
        serverQuestionReserveEnabled = backendQuestionGenerationConsentGranted
            && (snapshot.serverQuestionReserveEnabled ?? false)
        pendingQuestionReserveAcknowledgements = backendQuestionGenerationConsentGranted
            ? Array((snapshot.pendingQuestionReserveAcknowledgements ?? []).suffix(5))
            : []
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

        let fullyProvisionedGoalIDs = Set(
            Dictionary(grouping: questions.filter { $0.status != .retired }, by: \.goalID)
                .filter { $0.value.count >= ProductLimits.starterQuestionBankTargetCount }
                .map(\.key)
        )
        let incompleteMarkerGoalIDs = availableGoalProfiles
            .filter {
                !$0.hasCompletedInitialQuestionProvisioning
                    && fullyProvisionedGoalIDs.contains($0.id)
            }
            .map(\.id)
        if !incompleteMarkerGoalIDs.isEmpty {
            incompleteMarkerGoalIDs.forEach {
                setInitialQuestionProvisioningCompleted(true, for: $0)
            }
            save()
        }

    }

    private func decodeSupportedSnapshot(from data: Data) -> AppSnapshot? {
        guard let snapshot = try? JSONDecoder().decode(AppSnapshot.self, from: data),
              (snapshot.schemaVersion ?? 0) <= AppSnapshot.currentSchemaVersion else {
            return nil
        }
        return snapshot
    }

    private func snapshotSchemaVersion(in data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary["schemaVersion"] as? Int
    }

    private func initialCompetencies(for goal: Goal, questions: [CheckpointQuestion]) -> [TopicCompetency] {
        let questionTopics = questions
            .filter { isQuestion($0, compatibleWith: goal) }
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

    private static func redactedExportText(for trace: QuestionGenerationTrace) -> String {
        let date = ISO8601DateFormatter().string(from: trace.createdAt)
        return """
        \(trace.phase) at \(date)
        Goal: [redacted]
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

        Learning content, prompts, answers, and explanations: [redacted]
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

    private static func boundedText(_ text: String, maximumLength: Int) -> String {
        let characterClipped = String(text.prefix(max(0, maximumLength)))
        let maximumByteCount = max(0, maximumLength) * 4
        guard characterClipped.utf8.count > maximumByteCount else {
            return characterClipped
        }

        var byteCount = 0
        var bounded = ""
        for character in characterClipped {
            let characterText = String(character)
            let characterByteCount = characterText.utf8.count
            guard byteCount + characterByteCount <= maximumByteCount else { break }
            bounded.append(character)
            byteCount += characterByteCount
        }
        return bounded
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
        let compatibleExistingQuestions = existingQuestions.filter {
            isQuestion($0, compatibleWith: goal)
        }
        let knownQuestionIDs = Set(compatibleExistingQuestions.map(\.id))
        let relevantReportedQuestions = reportedQuestions.filter {
            knownQuestionIDs.contains($0.questionID)
        }
        let context = GoalQuestionContext(goal: goal)
        let relevantTopicKeys = Set(
            (context.needsGeneratedSkillMap ? [] : context.contentTopics)
                .flatMap(competencyTopics)
                .map(competencyTopicKey)
                + compatibleExistingQuestions
                    .flatMap { competencyTopics(from: $0.topic) }
                    .map(competencyTopicKey)
        )
        let relevantCompetencies = competencies.filter { competency in
            relevantTopicKeys.contains(competencyTopicKey(competency.topic))
        }
        return QuestionGenerationRequest(
            goal: goal,
            existingQuestions: compatibleExistingQuestions,
            competencies: relevantCompetencies,
            reportedQuestions: relevantReportedQuestions,
            targetCount: targetCount ?? questionBankTargetCount,
            minimumDifficulty: goal.minimumQuestionDifficulty,
            backendEndpoint: resolvedBackendEndpoint,
            backendAuthorizationToken: resolvedBackendAuthorizationToken
        )
    }

    private func questionContextFingerprint(for goal: Goal) -> String {
        let context = GoalQuestionContext(goal: goal)
        return ([context.learningTarget] + context.contentTopics.sorted())
            .map(normalizedSignal)
            .joined(separator: "|")
    }

    private func isQuestion(_ question: CheckpointQuestion, compatibleWith goal: Goal) -> Bool {
        guard let fingerprint = question.goalContextFingerprint else {
            return true
        }
        return fingerprint == questionContextFingerprint(for: goal)
    }

    private func questionStampedForCurrentContext(
        _ question: CheckpointQuestion,
        goal: Goal
    ) -> CheckpointQuestion {
        var stampedQuestion = question
        stampedQuestion.goalContextFingerprint = questionContextFingerprint(for: goal)
        return stampedQuestion
    }

    private var resolvedBackendEndpoint: URL? {
        guard backendQuestionGenerationConsentGranted else { return nil }
        return rawBackendEndpoint
    }

    private var rawBackendEndpoint: URL? {
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
        guard backendQuestionGenerationConsentGranted else { return nil }
        return rawBackendAuthorizationToken
    }

    private var rawBackendAuthorizationToken: String? {
        firstConfiguredBackendValue(
            storedValue: nil,
            infoKey: "CheckpointAIBackendToken",
            environmentKey: "CHECKPOINT_AI_BACKEND_TOKEN"
        )
    }

    private var resolvedQuestionReserveConfiguration: QuestionReserveConfiguration? {
        guard backendQuestionGenerationConsentGranted else { return nil }
        return rawQuestionReserveConfiguration
    }

    private var rawQuestionReserveConfiguration: QuestionReserveConfiguration? {
        if let questionReserveConfigurationOverride {
            return questionReserveConfigurationOverride
        }
        guard let endpoint = rawBackendEndpoint else { return nil }
        return QuestionReserveConfiguration(
            endpoint: endpoint,
            authorizationToken: rawBackendAuthorizationToken
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

    private func questionBankMaintenanceProviderPreference(for profile: Goal) -> AIProviderKind {
        let providerPreference = consentFilteredProviderPreference(aiProviderPreference)
        if providerPreference == .automatic {
            if resolvedBackendEndpoint != nil {
                return .backend
            }
            if lastQuestionProvider == .localTemplates,
               questions.contains(where: { $0.goalID == profile.id }) {
                return .localTemplates
            }
        }
        return providerPreference
    }

    private func consentFilteredProviderPreference(
        _ providerPreference: AIProviderKind,
        hasBackendEndpoint: Bool? = nil
    ) -> AIProviderKind {
        let canReachBackend = hasBackendEndpoint ?? (resolvedBackendEndpoint != nil)
        if providerPreference == .backend, !canReachBackend {
            return .automatic
        }
        return providerPreference
    }

    private func generationChunkCount(for providerPreference: AIProviderKind) -> Int {
        switch providerPreference {
        case .backend:
            return Self.backendGenerationChunkCount
        case .localTemplates:
            return questionBankTargetCount
        case .automatic, .appleFoundation:
            return Self.onDeviceGenerationChunkCount
        }
    }

    private var starterQuestionLimitMessage: String {
        "Free includes an initial practice set for your first goal. Pro keeps new checkpoints available after that set runs low."
    }
}
