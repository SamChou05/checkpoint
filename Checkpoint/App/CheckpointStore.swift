import Foundation
import Observation

private enum QuestionRefreshReason {
    case manual
    case automaticCoreRefill
    case levelUpRefill

    var countsTowardRefreshUsage: Bool {
        self != .levelUpRefill
    }

    var diagnosticsTitle: String {
        switch self {
        case .manual:
            return "Manual refresh"
        case .automaticCoreRefill:
            return "Automatic core refill"
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
                activatePersistenceForAppDataIfNeeded()
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
    var persistenceRecoveryMessage: String?
    var unlockSession: UnlockSession?
    var activeCheckpointRun: ActiveCheckpointRun?
    var checkpointRetryCooldownUntil: Date?
    var isOnboardingPresented = false
    var isCreatingGoalProfile = false
    var membershipTier: MembershipTier = .starter
    var pendingMembershipFeature: MembershipFeature?
    var questionRefreshesUsed = 0
    var lastAutomaticQuestionRefreshAt: Date?
    var questionBankSyncIntents: [QuestionBankSyncIntent] = []
    private(set) var hasNoPersistedAppData = true
    private(set) var requiresPersistenceEraseRecovery = false

    @ObservationIgnored private let questionEngine: HybridQuestionEngine
    @ObservationIgnored private let questionBankClient: any QuestionBankSyncing
    @ObservationIgnored private let durableQuestionBankEnabled: Bool
    @ObservationIgnored private let snapshotPersistence: AppSnapshotPersistence
    @ObservationIgnored private var permitsPersistenceWrites = false
    @ObservationIgnored private var dataLifecycleID = UUID()
    @ObservationIgnored private var backgroundGenerationGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private var questionBankTopOffGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private var questionBankPollingGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private var questionBankPollingTokens: [Goal.ID: UUID] = [:]
    @ObservationIgnored private var questionBankSynchronizationGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private let questionBankPollingDelaysNanoseconds: [UInt64]
    @ObservationIgnored private var durableQuestionBankUnavailableForLifecycle = false
    @ObservationIgnored private static let initialCheckpointReadyTargetCount = 5
    @ObservationIgnored private static let urgentRefillTargetMultiplier = 2
    @ObservationIgnored static let maximumQuestionGenerationTraceCount = 20
    @ObservationIgnored private static let maximumQuestionGenerationPreviewCount = 12
    @ObservationIgnored static let maximumStoredQuestionCountPerGoal = 500
    @ObservationIgnored static let maximumStoredAttemptCountPerGoal = 2_000
    @ObservationIgnored static let maximumStoredUnlockEventCountPerGoal = 1_000
    @ObservationIgnored static let maximumStoredQuestionReportCountPerGoal = 250
    @ObservationIgnored static let maximumStoredIssueReportCount = 100
    @ObservationIgnored private static let levelUpRecentAttemptWindow = 10
    @ObservationIgnored private static let levelUpMinimumAttemptCount = 5
    @ObservationIgnored private static let levelUpAccuracyThreshold = 0.90
    @ObservationIgnored private static let maximumExactQuestionAskCount = 2
    @ObservationIgnored private static let failedCheckpointCooldown: TimeInterval = 5 * 60
    @ObservationIgnored private static let maximumClaimsPerSync = 4
    @ObservationIgnored private static let defaultQuestionBankPollingDelaysNanoseconds: [UInt64] =
        [1, 2, 4, 8, 16, 30, 60].map { $0 * 1_000_000_000 }

    // MARK: - Lifecycle

    init(
        questionEngine: HybridQuestionEngine = HybridQuestionEngine(),
        questionBankClient: (any QuestionBankSyncing)? = nil,
        defaults: UserDefaults = .standard,
        persistenceDirectory: URL? = nil,
        fileManager: FileManager = .default,
        questionBankPollingDelaysNanoseconds: [UInt64]? = nil
    ) {
        self.questionEngine = questionEngine
        self.questionBankClient = questionBankClient ?? BackendQuestionBankClient()
        self.durableQuestionBankEnabled = questionBankClient != nil
            || questionEngine.supportsDurableQuestionBanks
        if let questionBankPollingDelaysNanoseconds {
            let positivePollingDelays = questionBankPollingDelaysNanoseconds.filter { $0 > 0 }
            self.questionBankPollingDelaysNanoseconds = positivePollingDelays.isEmpty
                ? Self.defaultQuestionBankPollingDelaysNanoseconds
                : positivePollingDelays
        } else {
            self.questionBankPollingDelaysNanoseconds = Self.defaultQuestionBankPollingDelaysNanoseconds
        }
        self.snapshotPersistence = AppSnapshotPersistence(
            defaults: defaults,
            persistenceDirectory: persistenceDirectory,
            fileManager: fileManager
        )
        requiresPersistenceEraseRecovery = snapshotPersistence.requiresEraseRecovery
        load()
        requiresPersistenceEraseRecovery = snapshotPersistence.requiresEraseRecovery
        reconcileLoadedUnlockSession()
        recoverInterruptedCheckpointRun()
        clearExpiredCheckpointRetryCooldown()
        recoverTransientQuestionGenerationState()
        isOnboardingPresented = goal == nil && !requiresPersistenceEraseRecovery
        publishShieldContext()
        if !hasNoPersistedAppData {
            SharedAppGroup.publishCheckpointReadiness(
                permitsPersistenceWrites && hasReadyCheckpointSet
            )
        }
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

        return goal.derivedSkillMap?.topicNames.first
    }

    var activeDerivedSkillMap: GoalSkillMap? {
        goal?.derivedSkillMap
    }

    var isBuildingActiveSkillMap: Bool {
        guard let goal, goal.derivedSkillMap == nil else {
            return false
        }

        return questionBatchState == .generating ||
            backgroundGenerationGoalIDs.contains(goal.id) ||
            questionBankTopOffGoalIDs.contains(goal.id) ||
            questionBankSyncIntents.contains { $0.goalID == goal.id }
    }

    var activeSkillMapNeedsAttention: Bool {
        guard let goal, goal.derivedSkillMap == nil else {
            return false
        }

        return !isBuildingActiveSkillMap
    }

    func confirmActiveDerivedSkillMap() {
        guard let topics = goal?.derivedSkillMap?.topics else { return }
        _ = reviewActiveDerivedSkillMap(topics: topics)
    }

    @discardableResult
    func reviewActiveDerivedSkillMap(topics proposedTopics: [SkillMapTopic]) -> Bool {
        guard var updatedGoal = goal,
              let existingMap = updatedGoal.derivedSkillMap else {
            return false
        }
        let starterPracticeWasConsumed = hasConsumedStarterPractice

        let reviewedTopics = reviewedSkillMapTopics(
            proposedTopics,
            preserving: existingMap
        )
        guard (3...6).contains(reviewedTopics.count) else {
            return false
        }

        let previousMap = existingMap
        let contentChanged = skillMapContentSignature(
            topics: existingMap.topics
        ) != skillMapContentSignature(topics: reviewedTopics)
        if !contentChanged {
            let metadataChanged = existingMap.status != .reviewed ||
                existingMap.topics != reviewedTopics
            guard metadataChanged else { return true }

            var reviewedMap = existingMap
            reviewedMap.topics = reviewedTopics
            reviewedMap.status = .reviewed
            reviewedMap.updatedAt = Date()
            updatedGoal.derivedSkillMap = reviewedMap
            storeGoalProfile(updatedGoal)
            save()
            publishShieldContext()
            return true
        }

        let reviewedSkillIDs = Set(reviewedTopics.map(\.id))
        updatedGoal.derivedSkillMap = GoalSkillMap(
            topics: reviewedTopics,
            status: .reviewed,
            version: existingMap.version + 1,
            provenance: .userEdited,
            createdAt: existingMap.createdAt,
            updatedAt: Date()
        )
        storeGoalProfile(updatedGoal)

        for index in questions.indices where questions[index].goalID == updatedGoal.id {
            guard let previousSkill = skillMapTopic(
                matching: questions[index],
                in: previousMap
            ) else {
                continue
            }

            guard reviewedSkillIDs.contains(previousSkill.id),
                  let reviewedSkill = reviewedTopics.first(where: { $0.id == previousSkill.id }) else {
                questions[index].status = .retired
                questions[index].nextReviewAt = nil
                continue
            }

            questions[index] = canonicalizedQuestion(
                questions[index],
                for: reviewedSkill
            )
        }

        let existingCompetencies = competencies.filter { ($0.goalID ?? updatedGoal.id) == updatedGoal.id }
        let goalQuestions = questions.filter { $0.goalID == updatedGoal.id }
        replaceCompetencies(
            for: updatedGoal.id,
            with: reconciledCompetencies(
                existing: existingCompetencies,
                goal: updatedGoal,
                questions: goalQuestions
            )
        )
        invalidateQuestionBankSynchronization(for: updatedGoal.id)
        if applyStarterGenerationLimitIfNeeded(
            starterPracticeWasConsumed: starterPracticeWasConsumed
        ) {
            return true
        }
        save()
        publishShieldContext()

        let retainedQuestionIDs = Set(
            questions.lazy
                .filter { $0.goalID == updatedGoal.id && self.isSelectableQuestion($0) }
                .map(\.id)
        )
        if retainedQuestionIDs.isEmpty {
            prepareInitialQuestionsInBackground(for: updatedGoal)
        } else {
            topOffQuestionBankInBackground(
                for: updatedGoal,
                starterQuestionIDs: retainedQuestionIDs
            )
        }
        return true
    }

    @discardableResult
    func repairActiveSkillMap(topicNames rawTopicNames: [String]) -> Bool {
        guard var updatedGoal = goal,
              updatedGoal.derivedSkillMap == nil,
              !questionBankTopOffGoalIDs.contains(updatedGoal.id),
              let topicNames = SkillMapTopic.validatedNames(rawTopicNames) else {
            return false
        }
        let starterPracticeWasConsumed = hasConsumedStarterPractice

        let repairedMap = GoalSkillMap(
            topics: topicNames.map { name in
                skillMapTopicWithDefaultObjective(name: name)
            },
            status: .reviewed,
            provenance: .userEdited
        )
        updatedGoal.derivedSkillMap = repairedMap
        storeGoalProfile(updatedGoal)
        canonicalizeStoredQuestions(for: updatedGoal)

        let existingCompetencies = competencies.filter {
            ($0.goalID ?? updatedGoal.id) == updatedGoal.id
        }
        replaceCompetencies(
            for: updatedGoal.id,
            with: reconciledCompetencies(
                existing: existingCompetencies,
                goal: updatedGoal,
                questions: questions.filter { $0.goalID == updatedGoal.id }
            )
        )
        invalidateQuestionBankSynchronization(for: updatedGoal.id)

        if applyStarterGenerationLimitIfNeeded(
            starterPracticeWasConsumed: starterPracticeWasConsumed
        ) {
            return true
        }

        questionRefreshesUsed = 0
        questionBatchState = .generating
        lastAIErrorMessage = nil
        lastQuestionGenerationFailure = nil
        save()
        publishShieldContext()
        prepareInitialQuestionsInBackground(for: updatedGoal)
        return true
    }

    private func applyStarterGenerationLimitIfNeeded(
        starterPracticeWasConsumed: Bool
    ) -> Bool {
        guard !isMember, starterPracticeWasConsumed else { return false }

        questionBatchState = hasReadyCheckpointSet ? .ready : .idle
        checkpointNotice = starterQuestionLimitMessage
        requestMembership(for: .freshQuestionGeneration)
        save()
        publishShieldContext()
        return true
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

        if backgroundGenerationGoalIDs.contains(profile.id)
            || questionBankTopOffGoalIDs.contains(profile.id)
            || questionBankSyncIntents.contains(where: { $0.goalID == profile.id }) {
            return readyCount > 0 ? "Preparing more practice" : "Preparing practice"
        }

        return readyCount > 0 ? "Practice set low" : "No practice ready yet"
    }

    var isPreparingActiveGoalQuestions: Bool {
        goal != nil
            && !hasReadyCheckpointSet
            && (questionBatchState == .generating
                || isQuestionBankTopOffInProgress
                || hasPendingActiveQuestionBankSync)
    }

    var isQuestionGenerationBlockingPractice: Bool {
        questionBatchState == .failed && !hasReadyCheckpointSet
    }

    var questionGenerationStatusText: String {
        if isQuestionBankTopOffInProgress || hasPendingActiveQuestionBankSync {
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

    private var hasPendingActiveQuestionBankSync: Bool {
        guard let goalID = goal?.id else { return false }
        return questionBankSyncIntents.contains { $0.goalID == goalID }
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

    func canUse(_: MembershipFeature) -> Bool {
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
        sourceDocuments: [GoalSourceDocument] = [],
        preferredQuestionStyle: QuestionFormat,
        minimumQuestionDifficulty: Int? = nil,
        createsNewProfile: Bool? = nil,
        waitForQuestionGeneration: Bool = true
    ) async {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrentLevel = currentLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFocusAreas = focusAreas.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSourceDocuments = GoalSourceDocument.normalizedDocuments(sourceDocuments)

        guard !normalizedTitle.isEmpty else {
            reportBlankGoalTitle()
            return
        }

        if createsNewProfile == false, goal != nil {
            await updateActiveGoal(
                title: normalizedTitle,
                deadline: deadline,
                category: category,
                currentLevel: normalizedCurrentLevel,
                focusAreas: normalizedFocusAreas,
                sourceDocuments: normalizedSourceDocuments,
                preferredQuestionStyle: preferredQuestionStyle,
                minimumQuestionDifficulty: minimumQuestionDifficulty,
                waitForQuestionGeneration: waitForQuestionGeneration
            )
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
            sourceDocuments: normalizedSourceDocuments,
            preferredQuestionStyle: preferredQuestionStyle,
            minimumQuestionDifficulty: minimumQuestionDifficulty ?? activeQuestionDifficulty
        )

        let previousGoalID = goal?.id
        let shouldCreateNewProfile = createsNewProfile ?? (isMember && previousGoalID != nil)

        guard !shouldCreateNewProfile || canCreateAdditionalGoalProfile else {
            checkpointNotice = goalProfileLimitMessage
            save()
            return
        }

        questionRefreshesUsed = 0
        questionBatchState = .generating

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
        if permitsPersistenceWrites {
            SharedAppGroup.publishUnlockExpiration(nil)
        }
        save()
        publishShieldContext()

        if waitForQuestionGeneration {
            await generateInitialQuestionBatch(for: newGoal)
        } else {
            prepareInitialQuestionsInBackground(for: newGoal)
        }
    }

    func updateActiveGoal(
        title: String,
        deadline: Date,
        category: GoalCategory? = nil,
        currentLevel: String,
        focusAreas: String,
        sourceDocuments: [GoalSourceDocument] = [],
        preferredQuestionStyle: QuestionFormat,
        minimumQuestionDifficulty: Int? = nil,
        waitForQuestionGeneration: Bool = true
    ) async {
        guard let currentGoal = goal else { return }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            reportBlankGoalTitle()
            return
        }

        let normalizedCurrentLevel = currentLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFocusAreas = focusAreas.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSourceDocuments = GoalSourceDocument.normalizedDocuments(sourceDocuments)
        let starterPracticeWasConsumed = hasConsumedStarterPractice
        let normalizedDifficulty = UnlockPolicy.normalizedQuestionDifficulty(
            minimumQuestionDifficulty ?? currentGoal.minimumQuestionDifficulty
        )
        let resolvedCategory = category ?? currentGoal.category
        let skillContextChanged =
            normalizedTitle != currentGoal.title ||
            resolvedCategory != currentGoal.category ||
            normalizedCurrentLevel != currentGoal.currentLevel ||
            normalizedFocusAreas != currentGoal.focusAreas ||
            normalizedSourceDocuments != currentGoal.sourceDocuments
        let generationContextChanged =
            skillContextChanged ||
            preferredQuestionStyle != currentGoal.preferredQuestionStyle ||
            normalizedDifficulty != currentGoal.minimumQuestionDifficulty
        let canRegenerateForEdit = isMember || !starterPracticeWasConsumed

        let updatedGoal = Goal(
            id: currentGoal.id,
            title: normalizedTitle,
            deadline: max(deadline, Date()),
            category: resolvedCategory,
            currentLevel: normalizedCurrentLevel,
            focusAreas: normalizedFocusAreas,
            sourceDocuments: normalizedSourceDocuments,
            derivedSkillMap: skillContextChanged ? nil : currentGoal.derivedSkillMap,
            preferredQuestionStyle: preferredQuestionStyle,
            minimumQuestionDifficulty: normalizedDifficulty,
            createdAt: currentGoal.createdAt
        )

        goal = updatedGoal
        upsertGoalProfile(updatedGoal)
        isOnboardingPresented = false
        isCreatingGoalProfile = false
        pendingMembershipFeature = nil

        guard generationContextChanged else {
            save()
            publishShieldContext()
            return
        }

        questionBankSyncIntents.removeAll { $0.goalID == updatedGoal.id }
        questionBankPollingGoalIDs.remove(updatedGoal.id)
        questionBankPollingTokens.removeValue(forKey: updatedGoal.id)
        questionBankSynchronizationGoalIDs.remove(updatedGoal.id)

        if hasReadyCheckpointSet {
            checkpointNotice = "Goal updated. Your current questions stay available; future questions will use these changes."
            questionBatchState = .ready
            save()
            publishShieldContext()
            return
        }

        guard canRegenerateForEdit else {
            checkpointNotice = "Goal updated. Pro can prepare more questions after your Free set is used."
            requestMembership(for: .freshQuestionGeneration)
            save()
            publishShieldContext()
            return
        }

        questionBatchState = .generating
        lastAIErrorMessage = nil
        lastQuestionGenerationFailure = nil
        checkpointNotice = nil
        save()
        publishShieldContext()

        if waitForQuestionGeneration {
            await generateInitialQuestionBatch(for: updatedGoal)
        } else {
            prepareInitialQuestionsInBackground(for: updatedGoal)
        }
    }

    private func prepareInitialQuestionsInBackground(for newGoal: Goal) {
        Task { [weak self] in
            await self?.generateInitialQuestionBatch(for: newGoal)
        }
    }

    private func reportBlankGoalTitle() {
        questionBatchState = .failed
        lastAIErrorMessage = "Enter a goal before generating questions."
        save()
    }

    private func generateInitialQuestionBatch(for newGoal: Goal) async {
        let lifecycleID = dataLifecycleID
        guard goalProfiles.contains(where: { $0.id == newGoal.id }) || goal?.id == newGoal.id else { return }
        guard !backgroundGenerationGoalIDs.contains(newGoal.id) else { return }
        backgroundGenerationGoalIDs.insert(newGoal.id)
        defer { backgroundGenerationGoalIDs.remove(newGoal.id) }

        if goal?.id == newGoal.id {
            questionBatchState = .generating
            beginQuestionGeneration(for: newGoal.id)
        }

        let generationGoal = await goalByPreparingSkillMapIfNeeded(
            for: newGoal,
            lifecycleID: lifecycleID
        )
        guard lifecycleID == dataLifecycleID, permitsPersistenceWrites else { return }

        if shouldUseDurableQuestionBank {
            let syncOutcome = await synchronizeDurableQuestionBank(
                for: generationGoal,
                minimumLocalQuestionCount: questionBankTargetCount
            )
            guard lifecycleID == dataLifecycleID, permitsPersistenceWrites else { return }
            guard let latestGoal = storedGoalProfile(withID: newGoal.id) else { return }

            if !hasSameGenerationContext(latestGoal, generationGoal) {
                backgroundGenerationGoalIDs.remove(newGoal.id)
                if goal?.id == newGoal.id {
                    finishQuestionGeneration(for: newGoal.id)
                }
                await generateInitialQuestionBatch(for: latestGoal)
                return
            }

            if syncOutcome.serviceSupported {
                if goal?.id == newGoal.id {
                    questionBatchState = readyQuestionCount(for: newGoal) >= unlockPolicy.questionsPerSession
                        ? .ready
                        : (hasPendingActiveQuestionBankSync ? .idle : .failed)
                    finishQuestionGeneration(for: newGoal.id)
                }
                save()
                publishShieldContext()
                schedulePendingQuestionBankPolling(for: newGoal)
                return
            }
        }

        let checkpointReadyRequest = generationRequest(
            goal: generationGoal,
            existingQuestions: [],
            competencies: competencies.filter {
                ($0.goalID ?? generationGoal.id) == generationGoal.id
            },
            reportedQuestions: [],
            targetCount: unlockPolicy.questionsPerSession
        )

        let startedAt = Date()
        let providerPreference = aiProviderPreference
        let batch = await questionEngine.generateQuestionBatch(
            for: checkpointReadyRequest,
            preference: providerPreference
        )

        guard lifecycleID == dataLifecycleID, permitsPersistenceWrites else { return }

        guard var resolvedGoal = storedGoalProfile(withID: newGoal.id) else {
            return
        }

        guard hasSameGenerationContext(resolvedGoal, generationGoal) else {
            backgroundGenerationGoalIDs.remove(newGoal.id)
            if goal?.id == newGoal.id {
                finishQuestionGeneration(for: newGoal.id)
            }
            await generateInitialQuestionBatch(for: resolvedGoal)
            return
        }

        var acceptedQuestions = canonicalizedQuestions(batch.questions, for: resolvedGoal)
        let hasReadyInitialSet = acceptedQuestions.count >= unlockPolicy.questionsPerSession
        var committedQuestions: [CheckpointQuestion] = []
        if hasReadyInitialSet {
            resolvedGoal = commitInferredSkillMapIfNeeded(
                for: resolvedGoal,
                questions: acceptedQuestions
            )
            acceptedQuestions = canonicalizedQuestions(acceptedQuestions, for: resolvedGoal)
            let existingCompetencies = competencies.filter {
                ($0.goalID ?? resolvedGoal.id) == resolvedGoal.id
            }
            questions.removeAll { $0.goalID == newGoal.id }
            questions.append(contentsOf: acceptedQuestions)
            replaceCompetencies(
                for: resolvedGoal.id,
                with: reconciledCompetencies(
                    existing: existingCompetencies,
                    goal: resolvedGoal,
                    questions: acceptedQuestions
                )
            )
            committedQuestions = acceptedQuestions
        }
        applyQuestionGenerationOutcome(
            batch,
            didAcceptQuestions: hasReadyInitialSet
        )
        recordQuestionGenerationTrace(
            phase: "Initial ready batch",
            request: checkpointReadyRequest,
            providerPreference: providerPreference,
            batch: batch,
            addedQuestions: committedQuestions,
            startedAt: startedAt,
            errorMessage: lastAIErrorMessage
        )
        if goal?.id == newGoal.id {
            questionBatchState = hasReadyCheckpointSet ? .ready : .failed
            finishQuestionGeneration(for: newGoal.id)
        }
        save()
        publishShieldContext()

        if !committedQuestions.isEmpty {
            topOffQuestionBankInBackground(
                for: resolvedGoal,
                starterQuestionIDs: Set(committedQuestions.map(\.id))
            )
        }
    }

    private func applyQuestionGenerationOutcome(
        _ batch: QuestionBatch,
        didAcceptQuestions: Bool
    ) {
        lastQuestionProvider = batch.provider
        if didAcceptQuestions {
            lastQuestionGenerationFailure = nil
            lastAIErrorMessage = nil
            return
        }

        let failure = batch.failure ?? .qualityRejected
        lastQuestionGenerationFailure = failure
        lastAIErrorMessage = failure.message
    }

    private func goalByPreparingSkillMapIfNeeded(
        for targetGoal: Goal,
        lifecycleID: UUID
    ) async -> Goal {
        guard targetGoal.derivedSkillMap == nil else { return targetGoal }

        let inferenceRequest = generationRequest(
            goal: targetGoal,
            existingQuestions: questions.filter { $0.goalID == targetGoal.id },
            competencies: competencies.filter { ($0.goalID ?? targetGoal.id) == targetGoal.id },
            reportedQuestions: questionReports.filter { $0.goalID == targetGoal.id },
            targetCount: unlockPolicy.questionsPerSession
        )

        let inferredMap: GoalSkillMap
        do {
            inferredMap = try await questionEngine.inferSkillMap(for: inferenceRequest)
        } catch {
            return targetGoal
        }

        guard lifecycleID == dataLifecycleID,
              permitsPersistenceWrites,
              var latestGoal = storedGoalProfile(withID: targetGoal.id),
              latestGoal.derivedSkillMap == nil,
              hasSameGenerationContext(latestGoal, targetGoal),
              let normalizedMap = normalizedSkillMap(inferredMap) else {
            return storedGoalProfile(withID: targetGoal.id) ?? targetGoal
        }

        latestGoal.derivedSkillMap = normalizedMap
        storeGoalProfile(latestGoal)
        replaceCompetencies(
            for: latestGoal.id,
            with: reconciledCompetencies(
                existing: competencies.filter { ($0.goalID ?? latestGoal.id) == latestGoal.id },
                goal: latestGoal,
                questions: questions.filter { $0.goalID == latestGoal.id }
            )
        )
        save()
        publishShieldContext()
        return latestGoal
    }

    private func normalizedSkillMap(_ skillMap: GoalSkillMap) -> GoalSkillMap? {
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

    private func defaultObjective(
        for skillID: SkillMapTopic.ID,
        name: String
    ) -> SkillMapObjective {
        SkillMapObjective(id: skillID, name: name)
    }

    private func skillMapTopicWithDefaultObjective(
        id: SkillMapTopic.ID = UUID(),
        name: String
    ) -> SkillMapTopic {
        SkillMapTopic(
            id: id,
            name: name,
            objectives: [defaultObjective(for: id, name: name)]
        )
    }

    private func hasSameGenerationContext(_ lhs: Goal, _ rhs: Goal) -> Bool {
        lhs.title == rhs.title &&
            lhs.category == rhs.category &&
            lhs.currentLevel == rhs.currentLevel &&
            lhs.focusAreas == rhs.focusAreas &&
            lhs.sourceDocuments == rhs.sourceDocuments &&
            lhs.preferredQuestionStyle == rhs.preferredQuestionStyle &&
            lhs.minimumQuestionDifficulty == rhs.minimumQuestionDifficulty &&
            skillMapGenerationSignature(lhs.derivedSkillMap) == skillMapGenerationSignature(rhs.derivedSkillMap)
    }

    private func skillMapGenerationSignature(_ skillMap: GoalSkillMap?) -> String {
        guard let skillMap else { return "none" }
        return skillMapContentSignature(topics: skillMap.topics)
    }

    private func skillMapContentSignature(topics: [SkillMapTopic]) -> String {
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

    func retryInitialQuestionGeneration() async {
        guard let goal else { return }
        await generateInitialQuestionBatch(for: goal)
    }

    @discardableResult
    func prepareQuestionsForProtectionStart() async -> Bool {
        guard let goal else {
            checkpointNotice = "Create a goal before starting app protection."
            return false
        }

        if hasReadyCheckpointSet {
            return persistReadyCheckpointForProtection()
        }

        guard !backgroundGenerationGoalIDs.contains(goal.id),
              questionBatchState != .generating else {
            checkpointNotice = "Your first checkpoint is still being prepared. Protection will stay off until it is ready."
            return false
        }

        if !hasConsumedStarterPractice {
            await generateInitialQuestionBatch(for: goal)
        } else if isMember {
            _ = await refreshQuestionBatchIfNeeded()
        } else {
            checkpointNotice = starterQuestionLimitMessage
            requestMembership(for: .freshQuestionGeneration)
        }

        guard hasReadyCheckpointSet else {
            let detail = lastQuestionGenerationFailure?.message
                ?? lastAIErrorMessage
                ?? "Try preparing your questions again."
            checkpointNotice = "Protection stayed off because a full checkpoint is not ready. \(detail)"
            save()
            return false
        }

        return persistReadyCheckpointForProtection()
    }

    private func persistReadyCheckpointForProtection() -> Bool {
        checkpointNotice = nil
        guard save(), hasReadyCheckpointSet, SharedAppGroup.checkpointReady == true else {
            if checkpointNotice == nil {
                checkpointNotice = "Protection stayed off because the ready checkpoint could not be saved."
            }
            return false
        }
        return true
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
        let lifecycleID = dataLifecycleID
        var expectedContextRevision = questionBankContextRevision(for: targetGoal)
        defer {
            questionBankTopOffGoalIDs.remove(targetGoal.id)
            if goal?.id == targetGoal.id {
                finishQuestionBankTopOff(for: targetGoal.id)
            }
            if lifecycleID == dataLifecycleID,
               permitsPersistenceWrites,
               let latestGoal = storedGoalProfile(withID: targetGoal.id),
               questionBankContextRevision(for: latestGoal) != expectedContextRevision,
               questionBankDeficit(for: latestGoal) > 0 {
                let retainedQuestionIDs = Set(
                    questions.lazy
                        .filter { $0.goalID == latestGoal.id && self.isSelectableQuestion($0) }
                        .map(\.id)
                )
                topOffQuestionBankInBackground(
                    for: latestGoal,
                    starterQuestionIDs: retainedQuestionIDs
                )
            }
        }

        guard goalProfiles.contains(where: { $0.id == targetGoal.id }) || goal?.id == targetGoal.id else { return }
        guard isMember
                || !starterQuestionIDs.isEmpty
                || questionBankSyncIntents.contains(where: { $0.goalID == targetGoal.id }) else {
            if goal?.id == targetGoal.id {
                checkpointNotice = starterQuestionLimitMessage
                requestMembership(for: .freshQuestionGeneration)
                save()
            }
            return
        }

        if shouldUseDurableQuestionBank {
            let syncOutcome = await synchronizeDurableQuestionBank(
                for: targetGoal,
                minimumLocalQuestionCount: questionBankTargetCount
            )
            if syncOutcome.serviceSupported {
                if goal?.id == targetGoal.id,
                   !backgroundGenerationGoalIDs.contains(targetGoal.id) {
                    questionBatchState = readyQuestionCount(for: targetGoal) >= unlockPolicy.questionsPerSession
                        ? .ready
                        : (hasPendingActiveQuestionBankSync ? .idle : .failed)
                }
                save()
                publishShieldContext()
                schedulePendingQuestionBankPolling(for: targetGoal)
                return
            }
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

        guard lifecycleID == dataLifecycleID, permitsPersistenceWrites else { return }

        guard var resolvedTargetGoal = availableGoalProfiles.first(where: { $0.id == targetGoal.id }) ?? (goal?.id == targetGoal.id ? goal : nil),
              hasSameGenerationContext(resolvedTargetGoal, targetGoal) else {
            save()
            publishShieldContext()
            return
        }

        resolvedTargetGoal = commitInferredSkillMapIfNeeded(
            for: resolvedTargetGoal,
            questions: existingQuestions + batch.questions,
            requiresAllCandidateTopicsToFit: existingCompetencies.contains { $0.attempts > 0 }
        )
        canonicalizeStoredQuestions(for: resolvedTargetGoal)

        let currentGoalQuestions = questions.filter { $0.goalID == targetGoal.id }
        let existingKeys = Set(currentGoalQuestions.map { questionKey($0) })
        let canonicalBatchQuestions = canonicalizedQuestions(
            batch.questions,
            for: resolvedTargetGoal
        )
        let newQuestions = canonicalBatchQuestions.filter {
            $0.difficulty >= resolvedTargetGoal.minimumQuestionDifficulty
                && !existingKeys.contains(questionKey($0))
        }
        questions.append(contentsOf: newQuestions)
        let goalQuestions = questions.filter { $0.goalID == targetGoal.id }
        let currentCompetencies = competencies.filter {
            ($0.goalID ?? resolvedTargetGoal.id) == resolvedTargetGoal.id
        }
        replaceCompetencies(
            for: resolvedTargetGoal.id,
            with: reconciledCompetencies(
                existing: currentCompetencies,
                goal: resolvedTargetGoal,
                questions: goalQuestions
            )
        )
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
        if goal?.id == targetGoal.id,
           !backgroundGenerationGoalIDs.contains(targetGoal.id) {
            questionBatchState = readyQuestionCount(for: resolvedTargetGoal) >= unlockPolicy.questionsPerSession
                ? .ready
                : .failed
        }
        // Treat this batch's inferred map as accepted; only later edits trigger another top-off.
        expectedContextRevision = questionBankContextRevision(for: resolvedTargetGoal)
        save()
        publishShieldContext()
    }

    func refreshQuestionBatch() async {
        await refreshQuestionBatch(reason: .manual)
    }

    private func refreshQuestionBatch(reason: QuestionRefreshReason, targetCount: Int? = nil) async {
        let lifecycleID = dataLifecycleID
        guard let goal else { return }
        guard isMember else {
            checkpointNotice = starterQuestionLimitMessage
            lastAIErrorMessage = starterQuestionLimitMessage
            requestMembership(for: .freshQuestionGeneration)
            save()
            return
        }

        if shouldUseDurableQuestionBank {
            let readyBeforeSync = readyQuestionCount(for: goal)
            if !hasReadyCheckpointSet {
                questionBatchState = .generating
            }
            beginQuestionGeneration(for: goal.id)

            let minimumLocalQuestionCount = targetCount.map {
                min(questionBankTargetCount, readyBeforeSync + max(1, $0))
            } ?? questionBankTargetCount
            let syncOutcome = await synchronizeDurableQuestionBank(
                for: goal,
                minimumLocalQuestionCount: minimumLocalQuestionCount
            )
            guard lifecycleID == dataLifecycleID,
                  permitsPersistenceWrites,
                  self.goal?.id == goal.id else {
                return
            }

            if syncOutcome.serviceSupported {
                if reason.countsTowardRefreshUsage {
                    questionRefreshesUsed += 1
                }
                questionBatchState = hasReadyCheckpointSet
                    ? .ready
                    : (hasPendingActiveQuestionBankSync ? .idle : .failed)
                finishQuestionGeneration(for: goal.id)
                save()
                publishShieldContext()
                schedulePendingQuestionBankPolling(for: goal)
                return
            }
            finishQuestionGeneration(for: goal.id)
        }

        questionBatchState = .generating
        beginQuestionGeneration(for: goal.id)
        if reason.countsTowardRefreshUsage {
            questionRefreshesUsed += 1
        }

        let refreshRequest = generationRequest(
            goal: goal,
            existingQuestions: activeQuestions,
            competencies: activeCompetencies,
            reportedQuestions: activeQuestionReports,
            targetCount: targetCount
        )
        let providerPreference = aiProviderPreference
        let startedAt = Date()
        let batch = await questionEngine.generateQuestionBatch(
            for: refreshRequest,
            preference: providerPreference
        )
        guard lifecycleID == dataLifecycleID, permitsPersistenceWrites else { return }
        guard var currentGoal = self.goal, currentGoal.id == goal.id else {
            if questionBatchState != .generating {
                questionGenerationStartedAt = nil
            }
            return
        }
        currentGoal = commitInferredSkillMapIfNeeded(
            for: currentGoal,
            questions: activeQuestions + batch.questions,
            requiresAllCandidateTopicsToFit: activeCompetencies.contains { $0.attempts > 0 }
        )
        canonicalizeStoredQuestions(for: currentGoal)
        let generatedQuestions = canonicalizedQuestions(batch.questions, for: currentGoal)
        let existingKeys = Set(activeQuestions.map { questionKey($0) })
        let newQuestions = generatedQuestions.filter { !existingKeys.contains(questionKey($0)) }
        questions.append(contentsOf: newQuestions)
        replaceActiveCompetencies(
            with: reconciledCompetencies(
                existing: activeCompetencies,
                goal: currentGoal,
                questions: activeQuestions
            )
        )
        applyQuestionGenerationOutcome(
            batch,
            didAcceptQuestions: !newQuestions.isEmpty
        )
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
        let lifecycleID = dataLifecycleID
        guard permitsPersistenceWrites,
              let goal,
              questionBatchState != .generating else {
            return false
        }

        if shouldUseDurableQuestionBank,
           questionBankSyncIntents.contains(where: { $0.goalID == goal.id }) {
            let syncOutcome = await synchronizeDurableQuestionBank(
                for: goal,
                minimumLocalQuestionCount: questionBankTargetCount
            )
            guard lifecycleID == dataLifecycleID,
                  permitsPersistenceWrites,
                  self.goal?.id == goal.id else {
                return false
            }
            if syncOutcome.serviceSupported {
                questionBatchState = hasReadyCheckpointSet
                    ? .ready
                    : (hasPendingActiveQuestionBankSync ? .idle : .failed)
                save()
                publishShieldContext()
                schedulePendingQuestionBankPolling(for: goal)
                return true
            }
            if !isMember, !hasConsumedStarterPractice, activeQuestions.isEmpty {
                await generateInitialQuestionBatch(for: goal)
                return hasReadyCheckpointSet
            }
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
            guard lifecycleID == dataLifecycleID,
                  permitsPersistenceWrites,
                  self.goal?.id == goal.id else {
                return false
            }
            scheduleQuestionBankMaintenanceIfNeeded(for: goal)
        } else {
            lastAutomaticQuestionRefreshAt = Date()
            questionRefreshesUsed += 1
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
        nextQuestion(excluding: [], avoidingSimilarityTo: [])
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

    // MARK: - Attempts and unlocks

    @discardableResult
    func submitAnswer(
        question: CheckpointQuestion,
        answer: String,
        result: AnswerResult,
        grantsUnlock: Bool = true,
        unlockMinutesOverride: Int? = nil
    ) -> Int {
        guard let questionGoal = storedGoalProfile(withID: question.goalID)
                ?? (goal?.id == question.goalID ? goal : nil) else {
            return 0
        }

        let unlockMinutes = unlockMinutesOverride ?? (grantsUnlock ? unlockMinutes(for: result) : 0)
        let attempt = CheckpointAttempt(
            questionID: question.id,
            goalID: question.goalID,
            prompt: question.prompt,
            answer: answer,
            result: result,
            unlockMinutes: unlockMinutes
        )

        attempts.insert(attempt, at: 0)
        updateQuestion(question, result: result)
        updateCompetency(for: question, result: result)
        if result != .correct,
           activeCheckpointRun?.questionIDs.contains(question.id) == true {
            var missedQuestionIDs = activeCheckpointRun?.missedQuestionIDs ?? []
            missedQuestionIDs.insert(question.id)
            activeCheckpointRun?.missedQuestionIDs = missedQuestionIDs
        }

        if unlockMinutes > 0 {
            recordUnlockSession(minutes: unlockMinutes, goalID: question.goalID)
        }

        scheduleQuestionBankMaintenanceIfNeeded(for: questionGoal)
        save()
        publishShieldContext()
        return unlockMinutes
    }

    func startUnlockSession(
        minutes: Int,
        expiresAt: Date? = nil,
        goalID: Goal.ID? = nil
    ) {
        let unlockMinutes = UnlockPolicy.normalizedCorrectAnswerUnlockMinutes(minutes)
        guard unlockMinutes > 0, let goalID = goalID ?? goal?.id else { return }

        recordUnlockSession(minutes: unlockMinutes, goalID: goalID, expiresAt: expiresAt)
        save()
        publishShieldContext()
    }

    private func recordUnlockSession(
        minutes: Int,
        goalID: Goal.ID,
        expiresAt: Date? = nil
    ) {
        let now = Date()
        unlockSession = UnlockSession(
            startedAt: now,
            expiresAt: expiresAt ?? (
                Calendar.current.date(byAdding: .minute, value: minutes, to: now) ?? now
            )
        )
        unlockEvents.insert(UnlockEvent(goalID: goalID, minutes: minutes, createdAt: now), at: 0)
        SharedAppGroup.publishUnlockExpiration(unlockSession?.expiresAt)
    }

    func clearUnlockSession() {
        guard unlockSession != nil else { return }
        unlockSession = nil
        guard permitsPersistenceWrites else { return }
        SharedAppGroup.publishUnlockExpiration(nil)
        save()
    }

    func eraseAllData(backendIdentityDefaults: UserDefaults = .standard) {
        permitsPersistenceWrites = false
        requiresPersistenceEraseRecovery = true
        hasNoPersistedAppData = false
        dataLifecycleID = UUID()
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
        questionGenerationStartedAt = nil
        lastQuestionGenerationDuration = nil
        isQuestionBankTopOffInProgress = false
        questionBankTopOffStartedAt = nil
        lastQuestionBankTopOffDuration = nil
        checkpointNotice = nil
        unlockSession = nil
        activeCheckpointRun = nil
        checkpointRetryCooldownUntil = nil
        questionRefreshesUsed = 0
        lastAutomaticQuestionRefreshAt = nil
        isCreatingGoalProfile = false
        pendingMembershipFeature = nil
        backgroundGenerationGoalIDs = []
        questionBankTopOffGoalIDs = []
        questionBankPollingGoalIDs = []
        questionBankPollingTokens = [:]
        questionBankSynchronizationGoalIDs = []
        durableQuestionBankUnavailableForLifecycle = false
        questionBankSyncIntents = []
        isOnboardingPresented = true
        persistenceRecoveryMessage = nil
        do {
            try snapshotPersistence.erase()
            requiresPersistenceEraseRecovery = false
            hasNoPersistedAppData = true
        } catch {
            requiresPersistenceEraseRecovery = snapshotPersistence.requiresEraseRecovery
            hasNoPersistedAppData = false
            isOnboardingPresented = false
            reportPersistenceEraseFailure()
        }
        BackendClientIdentity.clearInstallID(defaults: backendIdentityDefaults)
    }

    // MARK: - Checkpoint sessions

    func takePendingShieldSession(pendingAttemptID: String? = nil) -> CheckpointSession? {
        guard let pendingAttempt = SharedAppGroup.currentPendingShieldAttempt else { return nil }
        if let pendingAttemptID, pendingAttempt.id != pendingAttemptID {
            return nil
        }
        if let cooldownMessage = checkpointRetryCooldownMessage(source: .blockedApp) {
            checkpointNotice = cooldownMessage
            return nil
        }

        guard let session = checkpointSession(source: .blockedApp) else { return nil }
        guard canBeginCheckpointRun() else { return nil }
        guard SharedAppGroup.consumePendingShieldAttempt(matchingID: pendingAttemptID) != nil else {
            return nil
        }
        beginCheckpointRun(session)
        return session
    }

    func startManualCheckpointSession() -> CheckpointSession? {
        guard let session = checkpointSession(source: .manual) else { return nil }
        guard canBeginCheckpointRun() else { return nil }
        beginCheckpointRun(session)
        return session
    }

    func startPreviewCheckpointSession() -> CheckpointSession? {
        checkpointSession(source: .manual, purpose: .preview)
    }

    func preparePendingShieldSession(pendingAttemptID: String? = nil) async -> CheckpointSession? {
        guard let pendingAttempt = SharedAppGroup.currentPendingShieldAttempt else { return nil }
        if let pendingAttemptID, pendingAttempt.id != pendingAttemptID {
            return nil
        }

        if let cooldownMessage = checkpointRetryCooldownMessage(source: .blockedApp) {
            checkpointNotice = cooldownMessage
            return nil
        }

        if let session = takePendingShieldSession(pendingAttemptID: pendingAttemptID) {
            return session
        }

        // Blocked-app handoffs consume cached questions; generation never runs on this path.
        checkpointNotice = "A full cached checkpoint was not ready, so protection cannot continue yet. Open Checkpoint to prepare questions, then start protection again."
        save()
        return nil
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
        return startManualCheckpointSession()
    }

    func preparePreviewCheckpointSession() async -> CheckpointSession? {
        if goal != nil && needsQuestionRefill(minimumQuestionCount: unlockPolicy.questionsPerSession) {
            _ = await refreshQuestionBatchIfNeeded()
        }

        if let session = startPreviewCheckpointSession() {
            return session
        }

        guard await refreshQuestionBatchIfNeeded() else { return nil }
        return startPreviewCheckpointSession()
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
        let session = CheckpointSession(
            questions: selectedQuestions,
            requiredCorrectAnswers: StopBlockingPolicy.requiredCorrectAnswers,
            purpose: .stopBlocking
        )
        guard canBeginCheckpointRun() else { return nil }
        beginCheckpointRun(session)
        return session
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
        markQuestionsMissedDueNow(questionIDs)
        save()
        publishShieldContext()
    }

    func startCheckpointRetryCooldown(now: Date = Date()) {
        applyCheckpointRetryCooldown(now: now)
        save()
        publishShieldContext()
    }

    private func markQuestionsMissedDueNow(_ questionIDs: Set<CheckpointQuestion.ID>) {
        let now = Date()
        for index in questions.indices where questionIDs.contains(questions[index].id) {
            guard questions[index].status != .retired else { continue }
            questions[index].status = .incorrect
            questions[index].nextReviewAt = now
        }
    }

    private func applyCheckpointRetryCooldown(now: Date = Date()) {
        checkpointRetryCooldownUntil = now.addingTimeInterval(Self.failedCheckpointCooldown)
        checkpointNotice = "Checkpoint stays protected. Take a short reset, then try again in \(checkpointRetryCooldownRemainingText)."
    }

    @discardableResult
    func resolveCheckpointRun(
        sessionID: CheckpointSession.ID,
        didPass: Bool,
        missedQuestionIDs: Set<CheckpointQuestion.ID> = []
    ) -> Bool {
        guard let activeRun = activeCheckpointRun,
              activeRun.sessionID == sessionID else { return false }
        activeCheckpointRun = nil

        if didPass {
            checkpointRetryCooldownUntil = nil
            checkpointNotice = nil
            save()
            publishShieldContext()
            return true
        }

        markQuestionsMissedDueNow(
            missedQuestionIDs.union(activeRun.missedQuestionIDs ?? [])
        )
        applyCheckpointRetryCooldown()
        save()
        publishShieldContext()
        return true
    }

    @discardableResult
    func abandonCheckpointRun(
        sessionID: CheckpointSession.ID,
        missedQuestionIDs: Set<CheckpointQuestion.ID> = []
    ) -> Bool {
        resolveCheckpointRun(
            sessionID: sessionID,
            didPass: false,
            missedQuestionIDs: missedQuestionIDs
        )
    }

    func discardCheckpointRunBeforePresentation(sessionID: CheckpointSession.ID) {
        guard activeCheckpointRun?.sessionID == sessionID else { return }
        activeCheckpointRun = nil
        save()
    }

    private func beginCheckpointRun(_ session: CheckpointSession) {
        guard session.purpose != .preview else { return }
        activeCheckpointRun = ActiveCheckpointRun(session: session)
        save()
    }

    private func canBeginCheckpointRun() -> Bool {
        guard activeCheckpointRun == nil else {
            checkpointNotice = "Finish the current checkpoint before starting another one."
            save()
            return false
        }
        return true
    }

    // MARK: - Settings updates

    func updateUnlockMinutes(_ minutes: Int) {
        unlockPolicy.unlockMinutes = UnlockPolicy.normalizedCorrectAnswerUnlockMinutes(minutes)
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
        durableQuestionBankUnavailableForLifecycle = false
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
        if let skillMap = storedGoalProfile(withID: question.goalID)?.derivedSkillMap,
           let skill = skillMapTopic(matching: question, in: skillMap) {
            updateCompetency(
                topic: skill.name,
                goalID: question.goalID,
                skillID: skill.id,
                questionDifficulty: question.difficulty,
                result: result
            )
            return
        }

        for topic in competencyTopics(from: question.topic) {
            updateCompetency(topic: topic, goalID: question.goalID, questionDifficulty: question.difficulty, result: result)
        }
    }

    private func updateCompetency(
        topic: String,
        goalID: Goal.ID,
        skillID: UUID? = nil,
        questionDifficulty: Int,
        result: AnswerResult
    ) {
        let targetGoal = storedGoalProfile(withID: goalID)
        let mappedSkill = targetGoal?.derivedSkillMap.flatMap { skillMap in
            skillID.flatMap { requestedSkillID in
                skillMap.topics.first { $0.id == requestedSkillID }
            } ?? skillMapTopic(matching: topic, in: skillMap)
        }
        if targetGoal?.derivedSkillMap != nil, mappedSkill == nil {
            return
        }

        let canonicalTopic = mappedSkill?.name ?? topic
        let topicKey = competencyTopicKey(canonicalTopic)
        let matchesQuestionGoal: (TopicCompetency) -> Bool = { competency in
            let matchesSkill = mappedSkill.map { competency.skillID == $0.id } ?? false
            let matchesTopic = self.competencyTopicKey(competency.topic) == topicKey
            return (matchesSkill || matchesTopic) &&
                (competency.goalID == goalID || (competency.goalID == nil && self.goal?.id == goalID))
        }

        if !competencies.contains(where: matchesQuestionGoal) {
            competencies.append(
                .initial(
                    topic: canonicalTopic,
                    goalID: goalID,
                    skillID: mappedSkill?.id
                )
            )
        }

        guard let index = competencies.firstIndex(where: matchesQuestionGoal) else { return }
        competencies[index].goalID = goalID
        competencies[index].skillID = mappedSkill?.id
        competencies[index].topic = canonicalTopic

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
        guard question.status != .retired,
              question.timesAsked < Self.maximumExactQuestionAskCount else {
            return false
        }

        guard let skillMap = storedGoalProfile(withID: question.goalID)?.derivedSkillMap else {
            return true
        }
        return skillMapTopic(matching: question, in: skillMap) != nil
    }

    private static func correctAnswerReviewDelayDays(for correctStreak: Int) -> Int {
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

    private func competency(for question: CheckpointQuestion) -> TopicCompetency {
        if let skillMap = storedGoalProfile(withID: question.goalID)?.derivedSkillMap,
           let skill = skillMapTopic(matching: question, in: skillMap) {
            return competencies.first {
                ($0.goalID == question.goalID || ($0.goalID == nil && goal?.id == question.goalID)) &&
                    $0.skillID == skill.id
            } ?? .initial(topic: skill.name, goalID: question.goalID, skillID: skill.id)
        }

        return competency(for: question.topic)
    }

    private func questionSkillKey(_ question: CheckpointQuestion) -> String {
        if let skillMap = storedGoalProfile(withID: question.goalID)?.derivedSkillMap,
           let skill = skillMapTopic(matching: question, in: skillMap) {
            return skill.id.uuidString
        }

        return questionTopicKey(question.topic)
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

    private func storeGoalProfile(_ profile: Goal) {
        upsertGoalProfile(profile)
        if goal?.id == profile.id {
            goal = profile
        }
    }

    private func removeGoalData(for goalID: Goal.ID, includeLegacyCompetencies: Bool = false) {
        questions.removeAll { $0.goalID == goalID }
        attempts.removeAll { $0.goalID == goalID }
        competencies.removeAll { $0.goalID == goalID || (includeLegacyCompetencies && $0.goalID == nil) }
        questionReports.removeAll { $0.goalID == goalID }
        unlockEvents.removeAll { $0.goalID == goalID }
        questionBankSyncIntents.removeAll { $0.goalID == goalID }
        questionBankPollingGoalIDs.remove(goalID)
        questionBankPollingTokens.removeValue(forKey: goalID)
        questionBankSynchronizationGoalIDs.remove(goalID)
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
        replaceCompetencies(for: goalID, with: updatedCompetencies)
    }

    private func replaceCompetencies(
        for goalID: Goal.ID,
        with updatedCompetencies: [TopicCompetency]
    ) {
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

    @discardableResult
    private func save() -> Bool {
        if !permitsPersistenceWrites, goal != nil {
            _ = activatePersistenceForAppDataIfNeeded()
        }
        guard permitsPersistenceWrites else { return false }
        _ = enforceRetentionLimits()
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
            activeCheckpointRun: activeCheckpointRun,
            checkpointRetryCooldownUntil: checkpointRetryCooldownUntil,
            membershipTier: membershipTier,
            questionRefreshesUsed: questionRefreshesUsed,
            lastAutomaticQuestionRefreshAt: lastAutomaticQuestionRefreshAt,
            questionBankSyncIntents: questionBankSyncIntents
        )

        do {
            try snapshotPersistence.save(snapshot)
            SharedAppGroup.publishCheckpointReadiness(hasReadyCheckpointSet)
            return true
        } catch {
            let message = "Checkpoint could not save the latest local changes. Keep the app open and try again after freeing device storage."
            persistenceRecoveryMessage = message
            if checkpointNotice == nil {
                checkpointNotice = message
            }
            return false
        }
    }

    @discardableResult
    private func enforceRetentionLimits() -> Bool {
        let retainedQuestions = retainedQuestionsForPersistence(questions)
        let retainedAttempts = retainingFirstPerGoal(
            attempts,
            limit: Self.maximumStoredAttemptCountPerGoal,
            goalID: \CheckpointAttempt.goalID
        )
        let retainedUnlockEvents = retainingFirstPerGoal(
            unlockEvents,
            limit: Self.maximumStoredUnlockEventCountPerGoal,
            goalID: \UnlockEvent.goalID
        )
        let retainedQuestionReports = retainingFirstPerGoal(
            questionReports,
            limit: Self.maximumStoredQuestionReportCountPerGoal,
            goalID: \QuestionQualityReport.goalID
        )
        let retainedIssueReports = Array(issueReports.prefix(Self.maximumStoredIssueReportCount))
        let retainedQuestionGenerationTraces = Array(
            questionGenerationTraces.prefix(Self.maximumQuestionGenerationTraceCount)
        )
        let changed = retainedQuestions != questions ||
            retainedAttempts != attempts ||
            retainedUnlockEvents != unlockEvents ||
            retainedQuestionReports != questionReports ||
            retainedIssueReports != issueReports ||
            retainedQuestionGenerationTraces != questionGenerationTraces

        questions = retainedQuestions
        attempts = retainedAttempts
        unlockEvents = retainedUnlockEvents
        questionReports = retainedQuestionReports
        issueReports = retainedIssueReports
        questionGenerationTraces = retainedQuestionGenerationTraces
        return changed
    }

    private func retainedQuestionsForPersistence(
        _ storedQuestions: [CheckpointQuestion]
    ) -> [CheckpointQuestion] {
        var seenGoalIDs: Set<Goal.ID> = []
        let orderedGoalIDs = storedQuestions.compactMap { question -> Goal.ID? in
            seenGoalIDs.insert(question.goalID).inserted ? question.goalID : nil
        }

        return orderedGoalIDs.flatMap { goalID in
            let goalQuestions = storedQuestions.filter { $0.goalID == goalID }
            let usableQuestions = goalQuestions.filter {
                $0.status != .retired && $0.timesAsked < Self.maximumExactQuestionAskCount
            }
            let otherNonRetiredQuestions = goalQuestions.filter {
                $0.status != .retired && $0.timesAsked >= Self.maximumExactQuestionAskCount
            }
            let newestRetiredQuestions = goalQuestions
                .filter { $0.status == .retired }
                .sorted { lhs, rhs in
                    let lhsDate = lhs.lastAskedAt ?? .distantPast
                    let rhsDate = rhs.lastAskedAt ?? .distantPast
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }

            return Array(
                (usableQuestions + otherNonRetiredQuestions + newestRetiredQuestions)
                    .prefix(Self.maximumStoredQuestionCountPerGoal)
            )
        }
    }

    private func retainingFirstPerGoal<Element>(
        _ elements: [Element],
        limit: Int,
        goalID: KeyPath<Element, Goal.ID>
    ) -> [Element] {
        var retainedCounts: [Goal.ID: Int] = [:]
        return elements.filter { element in
            let id = element[keyPath: goalID]
            let count = retainedCounts[id, default: 0]
            guard count < limit else { return false }
            retainedCounts[id] = count + 1
            return true
        }
    }

    private func publishShieldContext() {
        guard permitsPersistenceWrites else { return }
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

    private func reconcileLoadedUnlockSession(now: Date = Date()) {
        guard let unlockSession else { return }

        if SharedAppGroup.desiredShieldActive,
           let sharedExpiration = SharedAppGroup.unlockExpiration,
           sharedExpiration > now {
            if unlockSession.expiresAt != sharedExpiration {
                self.unlockSession?.expiresAt = sharedExpiration
                save()
            }
            return
        }

        self.unlockSession = nil
        if let sharedExpiration = SharedAppGroup.unlockExpiration,
           (sharedExpiration <= now || !SharedAppGroup.desiredShieldActive) {
            SharedAppGroup.publishUnlockExpiration(nil)
        }
        save()
    }

    private func recoverInterruptedCheckpointRun(now: Date = Date()) {
        guard let interruptedRun = activeCheckpointRun else { return }
        activeCheckpointRun = nil

        if interruptedRun.purpose == .temporaryUnlock,
           SharedAppGroup.desiredShieldActive,
           let sharedExpiration = SharedAppGroup.unlockExpiration,
           sharedExpiration > now {
            if unlockSession?.isActive != true {
                recordUnlockSession(
                    minutes: unlockPolicy.unlockMinutes,
                    goalID: interruptedRun.goalID,
                    expiresAt: sharedExpiration
                )
            }
            checkpointRetryCooldownUntil = nil
            checkpointNotice = nil
            save()
            publishShieldContext()
            return
        }

        if unlockSession?.isActive == true || !SharedAppGroup.desiredShieldActive {
            save()
            return
        }

        markQuestionsMissedDueNow(interruptedRun.missedQuestionIDs ?? [])
        applyCheckpointRetryCooldown(now: now)
        checkpointNotice = "The previous checkpoint was interrupted. Protection stayed on; try again in \(checkpointRetryCooldownRemainingText)."
        save()
        publishShieldContext()
    }

    private func recoverTransientQuestionGenerationState() {
        if questionBatchState == .generating {
            questionGenerationStartedAt = nil
            lastQuestionGenerationDuration = nil
            questionBatchState = activeQuestions.isEmpty ? .idle : .ready
            save()

            if activeQuestions.isEmpty,
               let goal,
               !questionBankSyncIntents.contains(where: { $0.goalID == goal.id }) {
                prepareInitialQuestionsInBackground(for: goal)
            }
        } else if questionBatchState == .failed, hasReadyCheckpointSet {
            questionBatchState = .ready
            save()
        }
    }

    private func resumeQuestionBankMaintenanceIfNeeded() {
        let pendingGoalIDs = Set(questionBankSyncIntents.map(\.goalID))
        for pendingGoal in availableGoalProfiles where pendingGoalIDs.contains(pendingGoal.id) {
            guard !backgroundGenerationGoalIDs.contains(pendingGoal.id),
                  !questionBankTopOffGoalIDs.contains(pendingGoal.id) else {
                continue
            }
            topOffQuestionBankInBackground(for: pendingGoal)
        }

        guard let goal,
              isMember,
              !pendingGoalIDs.contains(goal.id),
              questionBatchState != .generating,
              !backgroundGenerationGoalIDs.contains(goal.id),
              !questionBankTopOffGoalIDs.contains(goal.id),
              readyQuestionCount(for: goal) <= ProductLimits.autoRefreshThreshold,
              questionBankDeficit(for: goal) > 0 else {
            return
        }

        topOffQuestionBankInBackground(for: goal)
    }

    private func load() {
        let snapshot: AppSnapshot
        let recoveryMessage: String?
        switch snapshotPersistence.load() {
        case .empty:
            return
        case .loaded(let loadedSnapshot):
            permitsPersistenceWrites = true
            hasNoPersistedAppData = false
            snapshot = loadedSnapshot
            recoveryMessage = nil
        case .recovered(let recoveredSnapshot, let message):
            permitsPersistenceWrites = true
            hasNoPersistedAppData = false
            snapshot = recoveredSnapshot
            recoveryMessage = message
        case .failed(let message):
            hasNoPersistedAppData = false
            persistenceRecoveryMessage = message
            checkpointNotice = message
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
        lastAIErrorMessage = snapshot.lastAIErrorMessage
        lastQuestionGenerationFailure = snapshot.lastQuestionGenerationFailure
        let savedProviderPreference = snapshot.aiProviderPreference ?? .automatic
        aiProviderPreference = [.automatic, .backend].contains(savedProviderPreference)
            ? savedProviderPreference
            : .automatic
        lastQuestionProvider = snapshot.lastQuestionProvider ?? .automatic
        backendEndpoint = snapshot.backendEndpoint ?? ""
        unlockSession = snapshot.unlockSession
        activeCheckpointRun = snapshot.activeCheckpointRun
        checkpointRetryCooldownUntil = snapshot.checkpointRetryCooldownUntil
        membershipTier = snapshot.membershipTier ?? .starter
        pendingMembershipFeature = nil
        questionRefreshesUsed = snapshot.questionRefreshesUsed ?? 0
        lastAutomaticQuestionRefreshAt = snapshot.lastAutomaticQuestionRefreshAt
        questionBankSyncIntents = snapshot.questionBankSyncIntents ?? []
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
        let retentionChanged = enforceRetentionLimits()
        if let recoveryMessage {
            persistenceRecoveryMessage = recoveryMessage
            checkpointNotice = recoveryMessage
        }
        let derivedSkillMapsChanged = migrateLegacyDerivedSkillMapsIfNeeded()
        if retentionChanged || derivedSkillMapsChanged {
            save()
        }
    }

    @discardableResult
    private func activatePersistenceForAppDataIfNeeded() -> Bool {
        guard !permitsPersistenceWrites else { return true }

        if requiresPersistenceEraseRecovery {
            do {
                try snapshotPersistence.erase()
                requiresPersistenceEraseRecovery = false
                hasNoPersistedAppData = true
                let eraseFailureMessage = persistenceEraseFailureMessage
                if persistenceRecoveryMessage == eraseFailureMessage {
                    persistenceRecoveryMessage = nil
                }
                if checkpointNotice == eraseFailureMessage {
                    checkpointNotice = nil
                }
            } catch {
                requiresPersistenceEraseRecovery = snapshotPersistence.requiresEraseRecovery
                hasNoPersistedAppData = false
                reportPersistenceEraseFailure()
                return false
            }
        }

        permitsPersistenceWrites = true
        hasNoPersistedAppData = false
        dataLifecycleID = UUID()
        return true
    }

    private var persistenceEraseFailureMessage: String {
        "Checkpoint could not finish erasing its local backup. Try Erase all data again before adding a new goal."
    }

    private func reportPersistenceEraseFailure() {
        let message = persistenceEraseFailureMessage
        persistenceRecoveryMessage = message
        if checkpointNotice == nil {
            checkpointNotice = message
        }
    }

    private func storedGoalProfile(withID goalID: Goal.ID) -> Goal? {
        goalProfiles.first(where: { $0.id == goalID }) ?? (goal?.id == goalID ? goal : nil)
    }

    private func commitInferredSkillMapIfNeeded(
        for targetGoal: Goal,
        questions: [CheckpointQuestion],
        requiresAllCandidateTopicsToFit: Bool = false
    ) -> Goal {
        let rawTopics = questions
            .filter { $0.status != .retired }
            .flatMap { competencyTopics(from: $0.topic) }
        let candidateTopics = skillMapTopicCandidates(
            for: targetGoal,
            rawTopics: rawTopics
        )
        guard targetGoal.derivedSkillMap == nil,
              candidateTopics.count >= 3,
              !requiresAllCandidateTopicsToFit || candidateTopics.count <= 6 else {
            return targetGoal
        }

        var updatedGoal = targetGoal
        updatedGoal.derivedSkillMap = GoalSkillMap(
            topics: candidateTopics.prefix(6).map { name in
                skillMapTopicWithDefaultObjective(name: name)
            },
            status: .suggested,
            provenance: .questionTopics
        )
        storeGoalProfile(updatedGoal)
        return updatedGoal
    }

    private func inferredSkillMap(
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

    private func inferredSkillMap(
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

    private func skillMapTopicCandidates(
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

    private func reviewedSkillMapTopics(
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

    private func skillMapTopic(
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

    private func skillMapTopic(
        matching question: CheckpointQuestion,
        in skillMap: GoalSkillMap
    ) -> SkillMapTopic? {
        if let skillID = question.skillID {
            return skillMap.topics.first { $0.id == skillID }
        }

        return skillMapTopic(matching: question.topic, in: skillMap)
    }

    private func canonicalizedQuestion(
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

    private func canonicalizedQuestions(
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

    private func canonicalizeStoredQuestions(for targetGoal: Goal) {
        guard let skillMap = targetGoal.derivedSkillMap else { return }

        for index in questions.indices where questions[index].goalID == targetGoal.id {
            guard let skill = skillMapTopic(
                matching: questions[index],
                in: skillMap
            ) else {
                questions[index].status = .retired
                questions[index].nextReviewAt = nil
                continue
            }
            questions[index] = canonicalizedQuestion(questions[index], for: skill)
        }
    }

    @discardableResult
    private func migrateLegacyDerivedSkillMapsIfNeeded() -> Bool {
        var didChange = false

        for storedProfile in availableGoalProfiles {
            var profile = storedProfile
            if var skillMap = profile.derivedSkillMap {
                let seededTopics = skillMap.topics.map { skill -> SkillMapTopic in
                    guard skill.objectives.isEmpty else { return skill }
                    var seededSkill = skill
                    seededSkill.objectives = [defaultObjective(for: skill.id, name: skill.name)]
                    return seededSkill
                }
                if seededTopics != skillMap.topics {
                    skillMap.topics = seededTopics
                    skillMap.version += 1
                    skillMap.updatedAt = Date()
                    profile.derivedSkillMap = skillMap
                    storeGoalProfile(profile)
                    didChange = true
                }

                let previousQuestions = questions.filter { $0.goalID == profile.id }
                canonicalizeStoredQuestions(for: profile)
                if previousQuestions != questions.filter({ $0.goalID == profile.id }) {
                    didChange = true
                }

                let existingCompetencies = competencies.filter {
                    $0.goalID == profile.id || ($0.goalID == nil && profile.id == goal?.id)
                }
                let updatedCompetencies = reconciledCompetencies(
                    existing: existingCompetencies,
                    goal: profile,
                    questions: questions.filter { $0.goalID == profile.id }
                )
                if existingCompetencies != updatedCompetencies {
                    replaceCompetencies(for: profile.id, with: updatedCompetencies)
                    didChange = true
                }
                continue
            }

            let explicitFocusTopics = GoalQuestionContext.meaningfulFocusTopics(
                from: profile.focusAreas
            )
            if let validatedFocusTopics = SkillMapTopic.validatedNames(explicitFocusTopics) {
                var updatedProfile = profile
                updatedProfile.derivedSkillMap = GoalSkillMap(
                    topics: validatedFocusTopics.map { name in
                        skillMapTopicWithDefaultObjective(name: name)
                    },
                    status: .reviewed,
                    provenance: .explicitFocusAreas
                )
                storeGoalProfile(updatedProfile)
                canonicalizeStoredQuestions(for: updatedProfile)
                let existingCompetencies = competencies.filter {
                    $0.goalID == updatedProfile.id ||
                        ($0.goalID == nil && updatedProfile.id == goal?.id)
                }
                replaceCompetencies(
                    for: updatedProfile.id,
                    with: reconciledCompetencies(
                        existing: existingCompetencies,
                        goal: updatedProfile,
                        questions: questions.filter { $0.goalID == updatedProfile.id }
                    )
                )
                didChange = true
                continue
            }

            let profileCompetencies = competencies.filter {
                $0.goalID == profile.id || ($0.goalID == nil && profile.id == goal?.id)
            }
            let practicedTopics = profileCompetencies
                .filter { $0.attempts > 0 }
                .sorted { $0.attempts > $1.attempts }
                .map(\.topic)
            let questionTopics = questions
                .filter { $0.goalID == profile.id && $0.status != .retired }
                .map(\.topic)
            let rawTopics = practicedTopics + questionTopics
            let candidateTopics = skillMapTopicCandidates(
                for: profile,
                rawTopics: rawTopics
            )

            guard candidateTopics.count <= 6,
                  let inferredMap = inferredSkillMap(
                for: profile,
                rawTopics: rawTopics
            ) else {
                let context = GoalQuestionContext(goal: profile)
                let broadKeys = Set([
                    competencyTopicKey(profile.title),
                    competencyTopicKey(context.learningTarget)
                ])
                for index in competencies.indices
                where (competencies[index].goalID == profile.id ||
                       (competencies[index].goalID == nil && profile.id == goal?.id)) &&
                    broadKeys.contains(competencyTopicKey(competencies[index].topic)) {
                    if competencies[index].attempts == 0 {
                        competencies[index].topic = ""
                    } else {
                        competencies[index].topic = "General progress"
                    }
                    didChange = true
                }
                competencies.removeAll { $0.topic.isEmpty }
                continue
            }

            var updatedProfile = profile
            updatedProfile.derivedSkillMap = inferredMap
            storeGoalProfile(updatedProfile)
            canonicalizeStoredQuestions(for: updatedProfile)
            replaceCompetencies(
                for: updatedProfile.id,
                with: reconciledCompetencies(
                    existing: profileCompetencies,
                    goal: updatedProfile,
                    questions: questions.filter { $0.goalID == updatedProfile.id }
                )
            )
            didChange = true
        }

        return didChange
    }

    private func initialCompetencies(for goal: Goal, questions: [CheckpointQuestion]) -> [TopicCompetency] {
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

    private func reconciledCompetencies(
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
                return self.skillMapTopic(matching: candidate.topic, in: skillMap)?.id == skill.id
            }

            return self.competencyTopicKey(candidate.topic) == self.competencyTopicKey(competency.topic)
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

    private struct DurableQuestionBankSyncOutcome {
        var serviceSupported: Bool
        var addedQuestionCount: Int
    }

    private var shouldUseDurableQuestionBank: Bool {
        durableQuestionBankEnabled
            && !durableQuestionBankUnavailableForLifecycle
            && resolvedBackendEndpoint != nil
            && aiProviderPreference != .appleFoundation
            && aiProviderPreference != .localTemplates
    }

    private func synchronizeDurableQuestionBank(
        for targetGoal: Goal,
        minimumLocalQuestionCount: Int? = nil
    ) async -> DurableQuestionBankSyncOutcome {
        guard !questionBankSynchronizationGoalIDs.contains(targetGoal.id) else {
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }
        questionBankSynchronizationGoalIDs.insert(targetGoal.id)
        defer { questionBankSynchronizationGoalIDs.remove(targetGoal.id) }

        let lifecycleID = dataLifecycleID
        let desiredCount = min(100, max(questionBankTargetCount, minimumLocalQuestionCount ?? 0))
        // Skill weights make each bank revision finite; do not replenish stale weights.
        let lowWatermark = 0
        let contextRevision = questionBankContextRevision(for: targetGoal)
        var intent = upsertQuestionBankSyncIntent(
            for: targetGoal,
            contextRevision: contextRevision,
            desiredCount: desiredCount,
            lowWatermark: lowWatermark
        )

        let initialDeficit = questionBankDeficit(
            for: targetGoal,
            targetCount: minimumLocalQuestionCount ?? questionBankTargetCount
        )
        guard initialDeficit > 0 else {
            removeQuestionBankSyncIntent(for: targetGoal.id)
            save()
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }

        let ensureRequest = generationRequest(
            goal: targetGoal,
            existingQuestions: questions.filter { $0.goalID == targetGoal.id },
            competencies: competencies.filter { ($0.goalID ?? targetGoal.id) == targetGoal.id },
            reportedQuestions: questionReports.filter { $0.goalID == targetGoal.id },
            targetCount: min(BackendQuestionBankClient.maximumClaimCount, max(1, initialDeficit))
        )

        let preparation: QuestionBankPreparationReceipt
        do {
            preparation = try await questionBankClient.ensureQuestionBank(
                for: ensureRequest,
                contextRevision: contextRevision,
                desiredCount: desiredCount,
                lowWatermark: lowWatermark
            )
        } catch QuestionBankAPIError.bankNotFound {
            durableQuestionBankUnavailableForLifecycle = true
            removeQuestionBankSyncIntent(for: targetGoal.id)
            save()
            return DurableQuestionBankSyncOutcome(serviceSupported: false, addedQuestionCount: 0)
        } catch let error as QuestionBankAPIError {
            switch error {
            case .backendNotConfigured, .invalidRequest, .unauthorized, .contextConflict, .badResponse:
                removeQuestionBankSyncIntent(for: targetGoal.id)
            case .bankNotFound:
                break
            case .claimConflict, .rateLimited, .serviceUnavailable:
                markQuestionBankSyncAttempt(for: targetGoal.id)
            }
            lastAIErrorMessage = error.localizedDescription
            save()
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        } catch {
            markQuestionBankSyncAttempt(for: targetGoal.id)
            lastAIErrorMessage = error.localizedDescription
            save()
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }

        guard lifecycleID == dataLifecycleID,
              permitsPersistenceWrites,
              let currentGoal = storedGoalProfile(withID: targetGoal.id) else {
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }
        let currentContextRevision = questionBankContextRevision(for: currentGoal)
        guard currentContextRevision == contextRevision else {
            _ = upsertQuestionBankSyncIntent(
                for: currentGoal,
                contextRevision: currentContextRevision,
                desiredCount: desiredCount,
                lowWatermark: lowWatermark
            )
            save()
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }

        if intent.bankID != preparation.bankID {
            intent.bankID = preparation.bankID
            intent.claimID = UUID().uuidString
        }
        intent.lastAttemptAt = Date()
        replaceQuestionBankSyncIntent(intent)
        save()

        guard preparation.readyCount > 0 else {
            if preparation.status == .empty {
                // Sanitizer rejections can leave a finite bank below target; empty ends polling.
                removeQuestionBankSyncIntent(for: targetGoal.id)
                save()
            }
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }

        var totalAdded = 0
        var claimAttemptCount = 0
        while claimAttemptCount < Self.maximumClaimsPerSync {
            guard let latestGoal = storedGoalProfile(withID: targetGoal.id),
                  questionBankContextRevision(for: latestGoal) == intent.contextRevision else {
                _ = upsertQuestionBankSyncIntent(
                    for: currentGoal,
                    desiredCount: desiredCount,
                    lowWatermark: lowWatermark
                )
                save()
                break
            }

            let localTarget = minimumLocalQuestionCount ?? questionBankTargetCount
            let deficit = questionBankDeficit(for: latestGoal, targetCount: localTarget)
            guard deficit > 0 else {
                removeQuestionBankSyncIntent(for: targetGoal.id)
                save()
                break
            }

            guard let bankID = intent.bankID else { break }
            let claimLimit = min(BackendQuestionBankClient.maximumClaimCount, deficit)
            let claimRequest = generationRequest(
                goal: latestGoal,
                existingQuestions: questions.filter { $0.goalID == latestGoal.id },
                competencies: competencies.filter { ($0.goalID ?? latestGoal.id) == latestGoal.id },
                reportedQuestions: questionReports.filter { $0.goalID == latestGoal.id },
                targetCount: claimLimit
            )

            let claim: QuestionBankClaimReceipt
            do {
                claim = try await questionBankClient.claimQuestions(
                    from: bankID,
                    claimID: intent.claimID,
                    limit: claimLimit,
                    for: claimRequest
                )
            } catch let error as QuestionBankAPIError where error == .bankNotFound || error == .contextConflict {
                intent.bankID = nil
                intent.claimID = UUID().uuidString
                intent.lastAttemptAt = Date()
                replaceQuestionBankSyncIntent(intent)
                save()
                break
            } catch {
                markQuestionBankSyncAttempt(for: targetGoal.id)
                lastAIErrorMessage = error.localizedDescription
                save()
                break
            }

            guard lifecycleID == dataLifecycleID,
                  permitsPersistenceWrites,
                  var resolvedGoal = storedGoalProfile(withID: targetGoal.id) else {
                break
            }
            let resolvedContextRevision = questionBankContextRevision(for: resolvedGoal)
            guard resolvedContextRevision == intent.contextRevision else {
                _ = upsertQuestionBankSyncIntent(
                    for: resolvedGoal,
                    desiredCount: desiredCount,
                    lowWatermark: lowWatermark
                )
                save()
                break
            }

            let claimedQuestions = claim.questions.map { question -> CheckpointQuestion in
                var scopedQuestion = question
                scopedQuestion.goalID = targetGoal.id
                return scopedQuestion
            }
            let sanitizedClaimedQuestions = QuestionBatchSanitizer.sanitize(
                claimedQuestions,
                for: claimRequest
            )
            resolvedGoal = commitInferredSkillMapIfNeeded(
                for: resolvedGoal,
                questions: questions.filter { $0.goalID == targetGoal.id } + sanitizedClaimedQuestions,
                requiresAllCandidateTopicsToFit: competencies.contains {
                    ($0.goalID ?? targetGoal.id) == targetGoal.id && $0.attempts > 0
                }
            )
            canonicalizeStoredQuestions(for: resolvedGoal)
            let canonicalClaimQuestions = canonicalizedQuestions(sanitizedClaimedQuestions, for: resolvedGoal)
            let currentQuestions = questions.filter { $0.goalID == targetGoal.id }
            let existingIDs = Set(currentQuestions.map(\.id))
            let existingRemoteIDs = Set(currentQuestions.compactMap(\.remoteID))
            let existingKeys = Set(currentQuestions.map { questionKey($0) })
            let newQuestions = canonicalClaimQuestions.filter { question in
                !existingIDs.contains(question.id)
                    && question.remoteID.map { !existingRemoteIDs.contains($0) } != false
                    && !existingKeys.contains(questionKey(question))
            }
            questions.append(contentsOf: newQuestions)
            let goalQuestions = questions.filter { $0.goalID == targetGoal.id }
            let currentCompetencies = competencies.filter {
                ($0.goalID ?? resolvedGoal.id) == resolvedGoal.id
            }
            replaceCompetencies(
                for: resolvedGoal.id,
                with: reconciledCompetencies(
                    existing: currentCompetencies,
                    goal: resolvedGoal,
                    questions: goalQuestions
                )
            )

            totalAdded += newQuestions.count
            if !newQuestions.isEmpty {
                lastQuestionProvider = .backend
                lastQuestionGenerationFailure = nil
                lastAIErrorMessage = nil
            }

            let updatedRevision = questionBankContextRevision(for: resolvedGoal)
            if updatedRevision != intent.contextRevision {
                intent = upsertQuestionBankSyncIntent(
                    for: resolvedGoal,
                    contextRevision: updatedRevision,
                    desiredCount: desiredCount,
                    lowWatermark: lowWatermark
                )
            } else {
                // Keep the old claim ID until its questions and replacement share one snapshot.
                intent.claimID = UUID().uuidString
                intent.lastAttemptAt = Date()
                replaceQuestionBankSyncIntent(intent)
            }

            if questionBankDeficit(for: resolvedGoal, targetCount: localTarget) == 0 {
                removeQuestionBankSyncIntent(for: targetGoal.id)
            }
            save()
            publishShieldContext()

            claimAttemptCount += 1
            guard !claim.questions.isEmpty,
                  questionBankSyncIntents.contains(where: { $0.goalID == targetGoal.id }),
                  updatedRevision == contextRevision else {
                break
            }
        }

        return DurableQuestionBankSyncOutcome(
            serviceSupported: true,
            addedQuestionCount: totalAdded
        )
    }

    private func schedulePendingQuestionBankPolling(for targetGoal: Goal) {
        guard shouldUseDurableQuestionBank,
              let initialIntent = questionBankSyncIntents.first(where: { $0.goalID == targetGoal.id }),
              !questionBankPollingGoalIDs.contains(targetGoal.id) else {
            return
        }

        let pollingToken = UUID()
        questionBankPollingGoalIDs.insert(targetGoal.id)
        questionBankPollingTokens[targetGoal.id] = pollingToken
        let lifecycleID = dataLifecycleID
        let contextRevision = initialIntent.contextRevision
        Task { [weak self] in
            var pollingAttempt = 0
            while !Task.isCancelled {
                guard let delay = self?.questionBankPollingDelaysNanoseconds[
                    min(
                        pollingAttempt,
                        (self?.questionBankPollingDelaysNanoseconds.count ?? 1) - 1
                    )
                ] else {
                    return
                }
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    self?.finishQuestionBankPolling(for: targetGoal.id, token: pollingToken)
                    return
                }
                guard let self else { return }
                guard lifecycleID == self.dataLifecycleID,
                      self.permitsPersistenceWrites,
                      self.shouldUseDurableQuestionBank,
                      self.questionBankPollingTokens[targetGoal.id] == pollingToken,
                      let currentGoal = self.storedGoalProfile(withID: targetGoal.id),
                      let currentIntent = self.questionBankSyncIntents.first(where: {
                          $0.goalID == targetGoal.id
                      }) else {
                    self.finishQuestionBankPolling(for: targetGoal.id, token: pollingToken)
                    return
                }
                guard currentIntent.contextRevision == contextRevision else {
                    self.finishQuestionBankPolling(for: targetGoal.id, token: pollingToken)
                    self.schedulePendingQuestionBankPolling(for: currentGoal)
                    return
                }

                let outcome = await self.synchronizeDurableQuestionBank(
                    for: currentGoal,
                    minimumLocalQuestionCount: self.questionBankTargetCount
                )
                if let latestIntent = self.questionBankSyncIntents.first(where: {
                    $0.goalID == targetGoal.id
                }),
                   latestIntent.contextRevision != contextRevision,
                   let latestGoal = self.storedGoalProfile(withID: targetGoal.id) {
                    self.finishQuestionBankPolling(for: targetGoal.id, token: pollingToken)
                    self.schedulePendingQuestionBankPolling(for: latestGoal)
                    return
                }
                guard outcome.serviceSupported else {
                    if !self.hasConsumedStarterPractice {
                        await self.generateInitialQuestionBatch(for: currentGoal)
                    } else if self.isMember {
                        await self.refreshQuestionBatch(reason: .automaticCoreRefill)
                    }
                    self.finishQuestionBankPolling(for: targetGoal.id, token: pollingToken)
                    return
                }

                if self.goal?.id == currentGoal.id {
                    self.questionBatchState = self.readyQuestionCount(for: currentGoal) >= self.unlockPolicy.questionsPerSession
                        ? .ready
                        : .idle
                }
                self.save()
                self.publishShieldContext()

                if !self.questionBankSyncIntents.contains(where: { $0.goalID == currentGoal.id }) {
                    self.finishQuestionBankPolling(for: targetGoal.id, token: pollingToken)
                    return
                }
                pollingAttempt += 1
            }
            self?.finishQuestionBankPolling(for: targetGoal.id, token: pollingToken)
        }
    }

    private func finishQuestionBankPolling(for goalID: Goal.ID, token: UUID) {
        guard questionBankPollingTokens[goalID] == token else { return }
        questionBankPollingTokens.removeValue(forKey: goalID)
        questionBankPollingGoalIDs.remove(goalID)
    }

    private func upsertQuestionBankSyncIntent(
        for targetGoal: Goal,
        desiredCount: Int,
        lowWatermark: Int
    ) -> QuestionBankSyncIntent {
        upsertQuestionBankSyncIntent(
            for: targetGoal,
            contextRevision: questionBankContextRevision(for: targetGoal),
            desiredCount: desiredCount,
            lowWatermark: lowWatermark
        )
    }

    private func upsertQuestionBankSyncIntent(
        for targetGoal: Goal,
        contextRevision: String,
        desiredCount: Int,
        lowWatermark: Int
    ) -> QuestionBankSyncIntent {
        if let index = questionBankSyncIntents.firstIndex(where: { $0.goalID == targetGoal.id }) {
            var intent = questionBankSyncIntents[index]
            if intent.contextRevision != contextRevision {
                intent.contextRevision = contextRevision
                intent.bankID = nil
                intent.claimID = UUID().uuidString
                intent.createdAt = Date()
            }
            intent.desiredCount = desiredCount
            intent.lowWatermark = lowWatermark
            questionBankSyncIntents[index] = intent
            save()
            return intent
        }

        let intent = QuestionBankSyncIntent(
            goalID: targetGoal.id,
            contextRevision: contextRevision,
            desiredCount: desiredCount,
            lowWatermark: lowWatermark
        )
        questionBankSyncIntents.append(intent)
        save()
        return intent
    }

    private func replaceQuestionBankSyncIntent(_ intent: QuestionBankSyncIntent) {
        if let index = questionBankSyncIntents.firstIndex(where: { $0.goalID == intent.goalID }) {
            questionBankSyncIntents[index] = intent
        } else {
            questionBankSyncIntents.append(intent)
        }
    }

    private func markQuestionBankSyncAttempt(for goalID: Goal.ID) {
        guard let index = questionBankSyncIntents.firstIndex(where: { $0.goalID == goalID }) else { return }
        questionBankSyncIntents[index].lastAttemptAt = Date()
    }

    private func removeQuestionBankSyncIntent(for goalID: Goal.ID) {
        questionBankSyncIntents.removeAll { $0.goalID == goalID }
    }

    private func invalidateQuestionBankSynchronization(for goalID: Goal.ID) {
        questionBankSyncIntents.removeAll { $0.goalID == goalID }
        questionBankPollingTokens.removeValue(forKey: goalID)
        questionBankPollingGoalIDs.remove(goalID)
        durableQuestionBankUnavailableForLifecycle = false
    }

    private func questionBankContextRevision(for goal: Goal) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let goalCompetencies = competencies.filter {
            ($0.goalID ?? goal.id) == goal.id
        }
        let skillAllocationSignature = desiredSkillAllocation(
            for: goal,
            competencies: goalCompetencies
        )
        .map { "\($0.key.uuidString):\($0.value)" }
        .sorted()
        .joined(separator: "|")
        let components = [
            goal.title,
            goal.currentLevel,
            goal.focusAreas,
            String(goal.minimumQuestionDifficulty),
            goal.preferredQuestionStyle.rawValue,
            goal.derivedSkillMap.map {
                skillMapContentSignature(topics: $0.topics)
            } ?? "",
            skillAllocationSignature
        ] + goal.sourceDocuments.flatMap { document in
            [document.id.uuidString, document.name, document.text]
        }

        for component in components {
            for byte in component.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            hash ^= 255
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    // MARK: - Question generation requests

    private func generationRequest(
        goal: Goal,
        existingQuestions: [CheckpointQuestion],
        competencies: [TopicCompetency],
        reportedQuestions: [QuestionQualityReport],
        targetCount: Int? = nil
    ) -> QuestionGenerationRequest {
        let resolvedTargetCount = targetCount ?? questionBankTargetCount
        return QuestionGenerationRequest(
            goal: goal,
            existingQuestions: existingQuestions,
            competencies: competencies,
            reportedQuestions: reportedQuestions,
            targetCount: resolvedTargetCount,
            minimumDifficulty: goal.minimumQuestionDifficulty,
            desiredSkillAllocation: desiredSkillAllocation(
                for: goal,
                competencies: competencies
            ),
            backendEndpoint: resolvedBackendEndpoint,
            backendAuthorizationToken: resolvedBackendAuthorizationToken
        )
    }

    private func desiredSkillAllocation(
        for targetGoal: Goal,
        competencies: [TopicCompetency]
    ) -> [SkillMapTopic.ID: Int] {
        guard let skillMap = targetGoal.derivedSkillMap,
              !skillMap.topics.isEmpty else {
            return [:]
        }

        var competencyBySkillID: [SkillMapTopic.ID: TopicCompetency] = [:]
        for competency in competencies {
            guard let skillID = competency.skillID else { continue }
            if let existing = competencyBySkillID[skillID] {
                competencyBySkillID[skillID] = mergedCompetency(existing, with: competency)
            } else {
                competencyBySkillID[skillID] = competency
            }
        }
        var allocation: [SkillMapTopic.ID: Int] = [:]
        for skill in skillMap.topics {
            let competency = competencyBySkillID[skill.id]
                ?? .initial(topic: skill.name, goalID: targetGoal.id, skillID: skill.id)
            if competency.attempts == 0 {
                // Give new skills a strong exploration prior independent of the local cache.
                allocation[skill.id] = 12
                continue
            }

            let weaknessBonus = Int(
                ceil(Double(max(0, 100 - competency.masteryPercent)) / 10.0)
            )
            let uncertaintyBonus = max(0, 4 - min(4, competency.attempts))
            let weight = min(16, max(3, 3 + weaknessBonus + uncertaintyBonus))
            allocation[skill.id] = weight
        }
        return allocation
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
