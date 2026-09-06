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

private struct GoalScopedQuestionID: Hashable {
    let goalID: Goal.ID
    let questionID: CheckpointQuestion.ID
}

private enum GoalProfileQuestionPreparation {
    case initial(Goal)
    case topOff(Goal, starterQuestionIDs: Set<CheckpointQuestion.ID>)
}

private struct GoalProfileMutationRollbackState {
    let goal: Goal?
    let goalProfiles: [Goal]
    let questions: [CheckpointQuestion]
    let attempts: [CheckpointAttempt]
    let competencies: [TopicCompetency]
    let focusWins: [FocusWin]
    let unlockEvents: [UnlockEvent]
    let questionReports: [QuestionQualityReport]
    let issueReports: [UserIssueReport]
    let questionGenerationTraces: [QuestionGenerationTrace]
    let questionBatchState: QuestionBatchState
    let lastAIErrorMessage: String?
    let lastQuestionGenerationFailure: QuestionGenerationFailureKind?
    let questionGenerationStartedAt: Date?
    let lastQuestionGenerationDuration: TimeInterval?
    let isQuestionBankTopOffInProgress: Bool
    let questionBankTopOffStartedAt: Date?
    let lastQuestionBankTopOffDuration: TimeInterval?
    let checkpointNotice: String?
    let unlockSession: UnlockSession?
    let isOnboardingPresented: Bool
    let isCreatingGoalProfile: Bool
    let pendingMembershipPresentation: MembershipPresentationContext?
    let membershipActivationHandoff: MembershipActivationHandoff?
    let questionRefreshesUsed: Int
    let questionBankSyncIntents: [QuestionBankSyncIntent]
    let skillMapEvolutionIntents: [SkillMapEvolutionIntent]
    let backgroundGenerationGoalIDs: Set<Goal.ID>
    let questionBankTopOffGoalIDs: Set<Goal.ID>
    let questionBankPollingGoalIDs: Set<Goal.ID>
    let questionBankPollingTokens: [Goal.ID: UUID]
    let questionBankSynchronizationGoalIDs: Set<Goal.ID>
    let skillMapEvolutionGoalIDs: Set<Goal.ID>
    let permitsPersistenceWrites: Bool
    let hasNoPersistedAppData: Bool
    let requiresPersistenceEraseRecovery: Bool
    let dataLifecycleID: UUID
}

enum IssueReportDraftSaveResult: Equatable {
    case saved
    case emptyMessage
    case messageTooLong
    case notRetained
    case persistenceFailed
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
    var focusWins: [FocusWin] = []
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
    var pendingMembershipPresentation: MembershipPresentationContext?
    private(set) var membershipActivationHandoff: MembershipActivationHandoff?
    var pendingMembershipActivationContinuation: MembershipActivationContinuation? {
        guard let membershipActivationHandoff,
              membershipActivationHandoff.phase == .offered
                || membershipActivationHandoff.phase == .awaitingEntitlement else {
            return nil
        }
        return membershipActivationHandoff.request.continuation
    }
    var completedMembershipActivationContinuation: MembershipActivationContinuation? {
        guard let membershipActivationHandoff,
              membershipActivationHandoff.phase == .activationReady
                || membershipActivationHandoff.phase == .resumeRequested else {
            return nil
        }
        return resolvedMembershipActivationContinuation()?.continuation
    }
    var pendingMembershipFeature: MembershipFeature? {
        get { pendingMembershipPresentation?.feature }
        set {
            pendingMembershipPresentation = newValue.map(MembershipPresentationContext.feature)
            membershipActivationHandoff = nil
        }
    }
    var questionRefreshesUsed = 0
    var lastAutomaticQuestionRefreshAt: Date?
    var questionBankSyncIntents: [QuestionBankSyncIntent] = []
    var skillMapEvolutionIntents: [SkillMapEvolutionIntent] = []
    private(set) var hasNoPersistedAppData = true
    private(set) var requiresPersistenceEraseRecovery = false

    @ObservationIgnored private let questionEngine: HybridQuestionEngine
    @ObservationIgnored private let questionBankClient: any QuestionBankSyncing
    @ObservationIgnored private let durableQuestionBankEnabled: Bool
    @ObservationIgnored private let snapshotPersistence: AppSnapshotPersistence
    @ObservationIgnored private var membershipEntitlementWasVerifiedThisLaunch = false
    @ObservationIgnored private var shouldPresentMembershipActivationHandoff = false
    @ObservationIgnored private var claimedMembershipActivationRequestID: UUID?
    @ObservationIgnored private var permitsPersistenceWrites = false
    @ObservationIgnored private var dataLifecycleID = UUID()
    private var backgroundGenerationGoalIDs: Set<Goal.ID> = []
    private var questionBankTopOffGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private var questionBankPollingGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private var questionBankPollingTokens: [Goal.ID: UUID] = [:]
    @ObservationIgnored private var questionBankSynchronizationGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private var skillMapEvolutionGoalIDs: Set<Goal.ID> = []
    @ObservationIgnored private let questionBankPollingDelaysNanoseconds: [UInt64]
    @ObservationIgnored private var durableQuestionBankUnavailableForLifecycle = false
    @ObservationIgnored private static let initialCheckpointReadyTargetCount = 5
    @ObservationIgnored private static let urgentRefillTargetMultiplier = 2
    @ObservationIgnored static let maximumQuestionGenerationTraceCount = 20
    @ObservationIgnored private static let maximumQuestionGenerationPreviewCount = 12
    @ObservationIgnored static let maximumStoredQuestionCountPerGoal = 500
    @ObservationIgnored static let maximumStoredAttemptCountPerGoal = 2_000
    @ObservationIgnored static let maximumStoredFocusWinCountPerGoal = 500
    @ObservationIgnored static let maximumFocusWinNoteLength = 280
    @ObservationIgnored static let maximumStoredUnlockEventCountPerGoal = 1_000
    @ObservationIgnored static let maximumStoredQuestionReportCountPerGoal = 250
    @ObservationIgnored nonisolated static let maximumStoredIssueReportCount = 100
    @ObservationIgnored nonisolated static let maximumIssueReportMessageLength = 1_000
    @ObservationIgnored private static let levelUpRecentAttemptWindow = 10
    @ObservationIgnored private static let levelUpMinimumAttemptCount = 5
    @ObservationIgnored private static let levelUpAccuracyThreshold = 0.90
    @ObservationIgnored private static let maximumExactQuestionAskCount = 2
    @ObservationIgnored private static let maximumClaimsPerSync = 4
    @ObservationIgnored private static let maximumEmptyFillCycleRetries = 1
    @ObservationIgnored private static let evolutionMinimumAttempts = 10
    @ObservationIgnored private static let evolutionMinimumMasteryPercent = 85
    @ObservationIgnored private static let evolutionMinimumCorrectStreak = 3
    @ObservationIgnored private static let evolutionRecentAttemptCount = 4
    @ObservationIgnored private static let evolutionMinimumRecentEvidenceCount = 4
    @ObservationIgnored private static let evolutionMinimumRecentScore = 0.85
    @ObservationIgnored private static let evolutionMinimumObjectiveScore = 0.75
    @ObservationIgnored private static let evolutionMaximumSkillsPerCycle = 2
    @ObservationIgnored private static let evolutionEvidenceMaximumAge: TimeInterval = 30 * 24 * 60 * 60
    @ObservationIgnored private static let evolutionRetryBackoff: TimeInterval = 6 * 60 * 60
    @ObservationIgnored private static let evolutionRecentAttemptLimitPerSkill = 15
    @ObservationIgnored private static let evolutionMaximumInvalidResponseAttempts = 2
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
        resumeSkillMapEvolutionIfNeeded()
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
        CheckpointRetryPolicy.formattedDuration(TimeInterval(checkpointRetryCooldownRemainingSeconds))
    }

    var isCheckpointRetryCooldownActive: Bool {
        checkpointRetryCooldownRemainingSeconds > 0
    }

    private func weeklyMetricsCalculator(
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyMetricsCalculator {
        WeeklyMetricsCalculator(
            attempts: attempts,
            unlockEvents: unlockEvents,
            asOf: asOf,
            calendar: calendar
        )
    }

    var weeklyTotalMetrics: WeeklyMetricsSummary {
        weeklyTotalMetrics(asOf: Date(), calendar: .current)
    }

    func weeklyTotalMetrics(
        asOf: Date,
        calendar: Calendar
    ) -> WeeklyMetricsSummary {
        let profiles = availableGoalProfiles
        let aggregateSkillCompetencies = profiles.count == 1
            ? currentMetricCompetencies(for: profiles[0])
            : []

        return weeklyMetricsCalculator(asOf: asOf, calendar: calendar).summary(
            id: WeeklyMetricsSummary.allGoalsID,
            title: "All goals",
            goalID: nil,
            isCurrentGoal: false,
            skillCompetencies: aggregateSkillCompetencies
        )
    }

    var weeklyActiveGoalMetrics: WeeklyMetricsSummary? {
        weeklyActiveGoalMetrics(asOf: Date(), calendar: .current)
    }

    func weeklyActiveGoalMetrics(
        asOf: Date,
        calendar: Calendar
    ) -> WeeklyMetricsSummary? {
        guard let goal else { return nil }
        return weeklyMetricsCalculator(asOf: asOf, calendar: calendar).summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true,
            skillCompetencies: currentMetricCompetencies(for: goal)
        )
    }

    var weeklyGoalMetrics: [WeeklyMetricsSummary] {
        weeklyGoalMetrics(asOf: Date(), calendar: .current)
    }

    func weeklyGoalMetrics(
        asOf: Date,
        calendar: Calendar
    ) -> [WeeklyMetricsSummary] {
        availableGoalProfiles.map { profile in
            weeklyMetricsCalculator(asOf: asOf, calendar: calendar).summary(
                id: profile.id.uuidString,
                title: profile.title,
                goalID: profile.id,
                isCurrentGoal: profile.id == goal?.id,
                skillCompetencies: currentMetricCompetencies(for: profile)
            )
        }
    }

    private func currentMetricCompetencies(for profile: Goal) -> [TopicCompetency] {
        let scopedCompetencies = competencies.filter { competency in
            competency.goalID == profile.id ||
                (competency.goalID == nil && profile.id == goal?.id)
        }

        guard let skillMap = profile.derivedSkillMap else {
            return SkillMapReconciler.mergedCompetenciesForDisplay(scopedCompetencies)
        }

        return SkillMapReconciler.orderedCompetencies(
            for: skillMap,
            from: scopedCompetencies,
            goalID: profile.id
        )
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

    var issueReportDrafts: [UserIssueReport] {
        issueReports.sorted(by: Self.issueReportComesBefore)
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
        let goalCompetencies = competencies.filter { $0.goalID == goalID || $0.goalID == nil }
        guard let skillMap = goal?.derivedSkillMap else { return goalCompetencies }
        let activeSkillIDs = Set(skillMap.topics.map(\.id))
        return goalCompetencies.filter { competency in
            if let skillID = competency.skillID {
                return activeSkillIDs.contains(skillID)
            }
            return SkillMapReconciler.skillMapTopic(
                matching: competency.topic,
                in: skillMap
            ) != nil
        }
    }

    var visibleActiveCompetencies: [TopicCompetency] {
        SkillMapReconciler.mergedCompetenciesForDisplay(activeCompetencies)
    }

    var activeProgressCompetencies: [TopicCompetency] {
        guard let goal,
              let skillMap = activeDerivedSkillMap else {
            return sortedCompetencies
        }

        return SkillMapReconciler.orderedCompetencies(
            for: skillMap,
            from: activeCompetencies,
            goalID: goal.id
        )
    }

    var activeQuestionReports: [QuestionQualityReport] {
        guard let goalID = goal?.id else { return [] }
        return questionReports.filter { $0.goalID == goalID }
    }

    func questionReport(
        for questionID: CheckpointQuestion.ID,
        goalID: Goal.ID
    ) -> QuestionQualityReport? {
        questionReports.first {
            $0.questionID == questionID && $0.goalID == goalID
        }
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

    var archivedActiveSkillTopics: [ArchivedSkillMapTopic] {
        goal?.derivedSkillMap?.archivedTopics.sorted {
            if $0.archivedAt == $1.archivedAt {
                return $0.topic.name < $1.topic.name
            }
            return $0.archivedAt > $1.archivedAt
        } ?? []
    }

    func updateActiveSkillMapEvolutionEnabled(_ isEnabled: Bool) {
        guard var updatedGoal = goal, var skillMap = updatedGoal.derivedSkillMap else { return }
        guard skillMap.evolutionEnabled != isEnabled else { return }
        skillMap.evolutionEnabled = isEnabled
        skillMap.updatedAt = Date()
        updatedGoal.derivedSkillMap = skillMap
        storeGoalProfile(updatedGoal)
        if !isEnabled {
            removeSkillMapEvolutionIntent(for: updatedGoal.id)
        }
        save()
        publishShieldContext()
        if isEnabled {
            _ = scheduleSkillMapEvolutionIfNeeded(for: updatedGoal)
        }
    }

    var isBuildingActiveSkillMap: Bool {
        guard let goal, goal.derivedSkillMap == nil else {
            return false
        }

        return questionBatchState == .generating ||
            backgroundGenerationGoalIDs.contains(goal.id) ||
            questionBankTopOffGoalIDs.contains(goal.id) ||
            hasPendingQuestionBankSync(for: goal)
    }

    var activeSkillMapNeedsAttention: Bool {
        guard let goal, goal.derivedSkillMap == nil else {
            return false
        }

        return !isBuildingActiveSkillMap
    }

    func confirmActiveDerivedSkillMap() {
        guard let goal, let skillMap = goal.derivedSkillMap else { return }
        _ = reviewDerivedSkillMap(
            topics: skillMap.topics,
            forGoalID: goal.id,
            expectedMap: skillMap
        )
    }

    @discardableResult
    func reviewActiveDerivedSkillMap(topics proposedTopics: [SkillMapTopic]) -> Bool {
        guard let goal, let skillMap = goal.derivedSkillMap else { return false }
        return reviewDerivedSkillMap(
            topics: proposedTopics,
            forGoalID: goal.id,
            expectedMap: skillMap
        )
    }

    @discardableResult
    func reviewDerivedSkillMap(
        topics proposedTopics: [SkillMapTopic],
        forGoalID expectedGoalID: Goal.ID,
        expectedMap: GoalSkillMap
    ) -> Bool {
        guard var updatedGoal = goal,
              updatedGoal.id == expectedGoalID,
              let existingMap = updatedGoal.derivedSkillMap,
              existingMap == expectedMap else {
            return false
        }
        let starterPracticeWasConsumed = hasConsumedStarterPractice

        let reviewedTopics = SkillMapReconciler.reviewedSkillMapTopics(
            proposedTopics,
            preserving: existingMap
        )
        let archivedSkillIDs = Set(existingMap.archivedTopics.map(\.id))
        guard (3...6).contains(reviewedTopics.count),
              !SkillMapReconciler.hasArchivedSkillCollision(
                topics: reviewedTopics,
                archivedTopics: existingMap.archivedTopics
              ),
              !SkillMapReconciler.hasRemovedSkillNameCollision(
                topics: reviewedTopics,
                existingTopics: existingMap.topics
              ) else {
            return false
        }

        let rollbackState = goalProfileMutationRollbackState()
        let previousMap = existingMap
        let contentChanged = SkillMapReconciler.skillMapContentSignature(
            topics: existingMap.topics
        ) != SkillMapReconciler.skillMapContentSignature(topics: reviewedTopics)
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
            guard save() else {
                restoreGoalProfileMutationState(rollbackState)
                return false
            }
            publishShieldContext()
            return true
        }

        let reviewedSkillIDs = Set(reviewedTopics.map(\.id))
        let newlyArchivedTopics = existingMap.topics.compactMap { topic -> ArchivedSkillMapTopic? in
            guard !reviewedSkillIDs.contains(topic.id), !archivedSkillIDs.contains(topic.id) else {
                return nil
            }
            return archivedSkillEntry(
                for: topic,
                goalID: updatedGoal.id,
                reason: .userRemoved,
                successorSkillIDs: []
            )
        }
        updatedGoal.derivedSkillMap = GoalSkillMap(
            topics: reviewedTopics,
            archivedTopics: existingMap.archivedTopics + newlyArchivedTopics,
            status: .reviewed,
            version: existingMap.version + 1,
            provenance: .userEdited,
            evolutionEnabled: existingMap.evolutionEnabled,
            lastEvolvedAt: existingMap.lastEvolvedAt,
            createdAt: existingMap.createdAt,
            updatedAt: Date()
        )
        storeGoalProfile(updatedGoal)
        removeSkillMapEvolutionIntent(for: updatedGoal.id)

        for index in questions.indices where questions[index].goalID == updatedGoal.id {
            guard let previousSkill = SkillMapReconciler.skillMapTopic(
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

            questions[index] = SkillMapReconciler.canonicalizedQuestion(
                questions[index],
                for: reviewedSkill
            )
        }

        let existingCompetencies = competencies.filter { ($0.goalID ?? updatedGoal.id) == updatedGoal.id }
        let goalQuestions = questions.filter { $0.goalID == updatedGoal.id }
        replaceCompetencies(
            for: updatedGoal.id,
            with: SkillMapReconciler.reconciledCompetencies(
                existing: existingCompetencies,
                goal: updatedGoal,
                questions: goalQuestions
            )
        )
        invalidateQuestionBankSynchronization(for: updatedGoal.id)
        let reachedStarterLimit = !isMember && starterPracticeWasConsumed
        if reachedStarterLimit {
            questionBatchState = hasReadyCheckpointSet ? .ready : .idle
            checkpointNotice = starterQuestionLimitMessage
            requestMembership(for: .freshQuestionGeneration)
        }
        guard save() else {
            restoreGoalProfileMutationState(rollbackState)
            return false
        }
        publishShieldContext()
        guard !reachedStarterLimit else { return true }

        let selector = questionSelector
        let retainedQuestionIDs = Set(
            questions.lazy
                .filter { $0.goalID == updatedGoal.id && selector.isSelectableQuestion($0) }
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
                SkillMapReconciler.skillMapTopicWithDefaultObjective(name: name)
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
            with: SkillMapReconciler.reconciledCompetencies(
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

    var activeFocusWins: [FocusWin] {
        guard let goalID = goal?.id else { return [] }
        return focusWins(for: goalID)
    }

    func focusWins(for goalID: Goal.ID) -> [FocusWin] {
        focusWins
            .filter { $0.goalID == goalID }
            .sorted(by: Self.focusWinComesBefore)
    }

    @discardableResult
    func recordFocusWin(
        note rawNote: String,
        goalID: Goal.ID,
        loggedAt: Date = Date()
    ) -> Bool {
        guard availableGoalProfiles.contains(where: { $0.id == goalID }) else {
            return false
        }

        let note = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, note.count <= Self.maximumFocusWinNoteLength else {
            return false
        }

        let previousFocusWins = focusWins
        let focusWin = FocusWin(goalID: goalID, note: note, loggedAt: loggedAt)
        focusWins.insert(focusWin, at: 0)
        guard save() else {
            focusWins = previousFocusWins
            return false
        }
        return focusWins.contains(where: { $0.id == focusWin.id })
    }

    @discardableResult
    func deleteFocusWin(id focusWinID: FocusWin.ID, goalID: Goal.ID) -> Bool {
        guard availableGoalProfiles.contains(where: { $0.id == goalID }),
              focusWins.contains(where: { $0.id == focusWinID && $0.goalID == goalID }) else {
            return false
        }

        let previousFocusWins = focusWins
        focusWins.removeAll { $0.id == focusWinID && $0.goalID == goalID }
        guard save() else {
            focusWins = previousFocusWins
            return false
        }
        return true
    }

    var isMember: Bool {
        membershipTier == .member
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

    var usableQuestionCount: Int {
        let selector = questionSelector
        return activeQuestions
            .filter(selector.isSelectableQuestion)
            .filter(selector.meetsDifficultyFloor)
            .count
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
        guard let goal else { return false }
        return checkpointReadiness(for: goal).hasFullCheckpoint
    }

    func usableQuestionCount(for profile: Goal) -> Int {
        let selector = questionSelector
        return questions.filter { question in
            question.goalID == profile.id
                && selector.isSelectableQuestion(question)
                && question.difficulty >= profile.minimumQuestionDifficulty
        }.count
    }

    private func readyQuestionCount(for profile: Goal, allowsEarlyCorrectReuse: Bool = false) -> Int {
        let now = Date()
        let selector = questionSelector
        return questions.filter { question in
            question.goalID == profile.id
                && question.difficulty >= profile.minimumQuestionDifficulty
                && selector.isReadyQuestionBankCandidate(
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
        let inventoryDeficit = max(
            0,
            (targetCount ?? questionBankTargetCount) - readyQuestionCount(
                for: profile,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
            )
        )
        let exactCheckpointDeficit = max(
            0,
            unlockPolicy.questionsPerSession - questionSelector(for: profile).nextQuestions(
                limit: unlockPolicy.questionsPerSession,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse,
                enforcesDifficultyFloor: true
            ).count
        )
        return max(
            inventoryDeficit,
            max(
                exactCheckpointDeficit,
                skillQuestionCoverageDeficit(
                    for: profile,
                    allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
                )
            )
        )
    }

    private func skillQuestionCoverageDeficit(
        for profile: Goal,
        allowsEarlyCorrectReuse: Bool = false
    ) -> Int {
        skillQuestionCoverageDeficitBySkillID(
            for: profile,
            allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
        ).values.reduce(0, +)
    }

    private func skillQuestionCoverageDeficitBySkillID(
        for profile: Goal,
        allowsEarlyCorrectReuse: Bool = false
    ) -> [SkillMapTopic.ID: Int] {
        guard let skillMap = profile.derivedSkillMap else { return [:] }

        let targetDifficulties = Dictionary(uniqueKeysWithValues:
            adaptiveSkillPlans(for: profile).map { ($0.skillID, $0.targetDifficulty) }
        )

        let selector = questionSelector
        let now = Date()
        var readyCountBySkillID: [SkillMapTopic.ID: Int] = [:]
        var readyObjectiveIDsBySkillID: [SkillMapTopic.ID: Set<SkillMapObjective.ID>] = [:]
        for question in questions where question.goalID == profile.id &&
            question.difficulty >= profile.minimumQuestionDifficulty &&
            selector.isReadyQuestionBankCandidate(
                question,
                now: now,
                allowsEarlyCorrectReuse: allowsEarlyCorrectReuse
            ) {
            guard let skill = SkillMapReconciler.skillMapTopic(matching: question, in: skillMap) else {
                continue
            }
            guard question.difficulty >= (targetDifficulties[skill.id] ?? profile.minimumQuestionDifficulty) else {
                continue
            }
            readyCountBySkillID[skill.id, default: 0] += 1
            let canonicalQuestion = SkillMapReconciler.canonicalizedQuestion(
                question,
                for: skill
            )
            if let objectiveID = canonicalQuestion.objectiveID {
                readyObjectiveIDsBySkillID[skill.id, default: []].insert(objectiveID)
            }
        }
        return Dictionary(uniqueKeysWithValues: skillMap.topics.map { skill in
            let skillFloorDeficit = max(0, 2 - readyCountBySkillID[skill.id, default: 0])
            let coveredObjectiveIDs = readyObjectiveIDsBySkillID[skill.id, default: []]
            let objectiveDeficit = skill.objectives.filter {
                !coveredObjectiveIDs.contains($0.id)
            }.count
            // One new question can satisfy both the skill floor and one missing
            // objective, so the required count is the larger of the two deficits.
            return (skill.id, max(skillFloorDeficit, objectiveDeficit))
        })
    }

    func questionBankReadinessWarning(for profile: Goal) -> String? {
        let readyCount = readyQuestionCount(for: profile)

        guard readyCount < unlockPolicy.questionsPerSession else { return nil }

        if isQuestionPreparationInProgress(for: profile) {
            return readyCount > 0 ? "Preparing more practice" : "Preparing practice"
        }

        return readyCount > 0 ? "Practice set low" : "No practice ready yet"
    }

    private func isQuestionPreparationInProgress(for profile: Goal) -> Bool {
        (goal?.id == profile.id && questionBatchState == .generating)
            || backgroundGenerationGoalIDs.contains(profile.id)
            || questionBankTopOffGoalIDs.contains(profile.id)
            || hasPendingQuestionBankSync(for: profile)
    }

    var isPreparingActiveGoalQuestions: Bool {
        goal != nil
            && !hasReadyCheckpointSet
            && (questionBatchState == .generating
                || isQuestionBankTopOffInProgress
                || hasPendingActiveQuestionBankSync)
    }

    var isMaintainingActiveGoalQuestions: Bool {
        guard isMember, let goal else { return false }
        return isQuestionPreparationInProgress(for: goal)
            || isQuestionBankTopOffInProgress
            || hasPendingActiveQuestionBankSync
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
        guard let goal else { return false }
        return hasPendingQuestionBankSync(for: goal)
    }

    private func hasPendingQuestionBankSync(for targetGoal: Goal) -> Bool {
        guard let intent = questionBankSyncIntents.first(where: {
            $0.goalID == targetGoal.id
        }) else {
            return false
        }
        return !isQuestionBankSyncIntentBlocked(intent, for: targetGoal)
    }

    private func hasBlockedQuestionBankSyncIntent(for targetGoal: Goal) -> Bool {
        guard let intent = questionBankSyncIntents.first(where: {
            $0.goalID == targetGoal.id
        }) else {
            return false
        }
        return isQuestionBankSyncIntentBlocked(intent, for: targetGoal)
    }

    private func isQuestionBankSyncIntentBlocked(
        _ intent: QuestionBankSyncIntent,
        for targetGoal: Goal
    ) -> Bool {
        intent.contextRevision == questionBankContextRevision(for: targetGoal) &&
            normalizedQuestionBankBlockedReason(intent.generationBlockedReason) != nil
    }

    private func normalizedQuestionBankBlockedReason(_ rawReason: String?) -> String? {
        guard let reason = rawReason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else {
            return nil
        }
        return reason
    }

    var studyFocusRecommendation: StudyFocusRecommendation? {
        guard canUse(.adaptiveStudyAssist),
              let skillMap = activeDerivedSkillMap,
              skillMap.status == .reviewed,
              let question = nextQuestion() else {
            return nil
        }

        let mappedSkill = SkillMapReconciler.skillMapTopic(
            matching: question,
            in: skillMap
        )
        let skillName = mappedSkill?.name ?? question.topic
        let skillNameKey = SkillMapReconciler.competencyTopicKey(skillName)
        let hasPracticeHistory = activeProgressCompetencies.contains { candidate in
            if let mappedSkill, candidate.skillID == mappedSkill.id {
                return candidate.attempts > 0
            }
            return candidate.attempts > 0 &&
                SkillMapReconciler.competencyTopicKey(candidate.topic) == skillNameKey
        }

        return StudyFocusRecommendation(
            question: question,
            skillID: mappedSkill?.id ?? question.skillID,
            skillName: skillName,
            hasPracticeHistory: hasPracticeHistory
        )
    }

    var studyFocusState: StudyFocusState? {
        guard canUse(.adaptiveStudyAssist),
              activeDerivedSkillMap?.status == .reviewed,
              !isPreparingActiveGoalQuestions,
              !isQuestionGenerationBlockingPractice else {
            return nil
        }
        if let recommendation = studyFocusRecommendation {
            return .recommendation(recommendation)
        }

        return usableQuestionCount > 0 ? .caughtUp : .awaitingQuestion
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

    func checkpointReadiness(for targetGoal: Goal) -> GoalCheckpointReadiness {
        let requiredCount = unlockPolicy.questionsPerSession
        if hasLegacyLocalQuestionBank(for: targetGoal) {
            return isQuestionPreparationInProgress(for: targetGoal)
                ? .preparing(selectableCount: 0, requiredCount: requiredCount)
                : .incomplete(selectableCount: 0, requiredCount: requiredCount)
        }

        let selectableCount = questionSelector(for: targetGoal).nextQuestions(
            limit: requiredCount,
            enforcesDifficultyFloor: true
        ).count

        if selectableCount >= requiredCount {
            return .ready(
                selectableCount: selectableCount,
                requiredCount: requiredCount
            )
        }
        if isQuestionPreparationInProgress(for: targetGoal) {
            return .preparing(
                selectableCount: selectableCount,
                requiredCount: requiredCount
            )
        }
        return .incomplete(
            selectableCount: selectableCount,
            requiredCount: requiredCount
        )
    }

    func prepareGoalProfileMutation(
        _ request: GoalProfileMutationRequest
    ) -> GoalProfileMutationPreflight {
        switch request.operation {
        case let .create(draft):
            let candidate = resolvedGoal(
                from: draft,
                id: request.id,
                createdAt: request.createdAt,
                minimumDeadline: request.createdAt
            )
            guard !candidate.title.isEmpty else { return .invalidTitle }

            if let existingGoal = availableGoalProfiles.first(where: {
                $0.id == request.id
            }) {
                let replayCandidate = resolvedGoal(
                    from: draft,
                    id: request.id,
                    createdAt: request.createdAt,
                    minimumDeadline: request.createdAt,
                    existingGoal: existingGoal
                )
                guard let currentGoal = goal,
                      currentGoal.id == request.id,
                      currentGoal == existingGoal,
                      replayCandidate == existingGoal else {
                    return .staleRequest
                }
                return .alreadyCommitted
            }
            guard goal == nil || canUse(.goalProfiles) else {
                return .membershipRequired
            }
            guard goal == nil || canCreateAdditionalGoalProfile else {
                return .profileLimitReached
            }

            return .eligible(
                GoalProfileMutationPlan(
                    request: request,
                    sourceGoal: goal,
                    sourceReadiness: nil,
                    targetGoal: candidate,
                    resultingActiveGoal: candidate,
                    resultingReadiness: checkpointReadiness(for: candidate)
                )
            )

        case let .edit(expectedGoalID, draft):
            guard let currentGoal = goal,
                  currentGoal.id == expectedGoalID else {
                return .staleRequest
            }

            let candidate = resolvedGoal(
                from: draft,
                id: currentGoal.id,
                createdAt: currentGoal.createdAt,
                minimumDeadline: request.createdAt,
                existingGoal: currentGoal
            )
            guard !candidate.title.isEmpty else { return .invalidTitle }
            guard candidate != currentGoal else { return .alreadyCommitted }

            return .eligible(
                GoalProfileMutationPlan(
                    request: request,
                    sourceGoal: currentGoal,
                    sourceReadiness: checkpointReadiness(for: currentGoal),
                    targetGoal: candidate,
                    resultingActiveGoal: candidate,
                    resultingReadiness: checkpointReadiness(for: candidate)
                )
            )

        case let .delete(goalID):
            guard let targetGoal = availableGoalProfiles.first(where: {
                $0.id == goalID
            }) else {
                return .targetNotFound
            }

            let sourceGoal = goal
            let resultingGoal: Goal?
            if sourceGoal?.id == goalID {
                resultingGoal = availableGoalProfiles
                    .filter { $0.id != goalID }
                    .sorted {
                        if $0.createdAt == $1.createdAt {
                            return $0.id.uuidString < $1.id.uuidString
                        }
                        return $0.createdAt > $1.createdAt
                    }
                    .first
            } else {
                resultingGoal = sourceGoal
            }
            let resultingReadiness = sourceGoal?.id == goalID
                ? resultingGoal.map(checkpointReadiness(for:))
                : nil

            return .eligible(
                GoalProfileMutationPlan(
                    request: request,
                    sourceGoal: sourceGoal,
                    sourceReadiness: nil,
                    targetGoal: targetGoal,
                    resultingActiveGoal: resultingGoal,
                    resultingReadiness: resultingReadiness
                )
            )
        }
    }

    func commitGoalProfileMutation(
        using plan: GoalProfileMutationPlan
    ) -> GoalProfileMutationCommitResult {
        switch prepareGoalProfileMutation(plan.request) {
        case let .eligible(validatedPlan):
            guard validatedPlan == plan else { return .stalePlan }
        case .alreadyCommitted:
            return .alreadyCommitted
        case .invalidTitle:
            return .invalidTitle
        case .membershipRequired:
            return .membershipRequired
        case .profileLimitReached:
            return .profileLimitReached
        case .targetNotFound:
            return .targetNotFound
        case .staleRequest:
            return .stalePlan
        }

        guard activatePersistenceForAppDataIfNeeded() else {
            return .persistenceFailed
        }
        let rollbackState = goalProfileMutationRollbackState()
        var questionPreparation: GoalProfileQuestionPreparation?
        var shouldClearSharedUnlockExpiration = false
        var clearedMembershipActivationResume = false

        switch plan.request.operation {
        case .create:
            clearedMembershipActivationResume = commitGoalCreation(plan.targetGoal)
            questionPreparation = .initial(plan.targetGoal)

        case .edit:
            questionPreparation = commitGoalEdit(
                from: plan.sourceGoal,
                to: plan.targetGoal
            )

        case .delete:
            let deletionResult = commitGoalDeletion(plan)
            questionPreparation = deletionResult.questionPreparation
            shouldClearSharedUnlockExpiration = deletionResult.clearsUnlockExpiration
        }

        guard save(mirroringRecovery: clearedMembershipActivationResume) else {
            restoreGoalProfileMutationState(rollbackState)
            return .persistenceFailed
        }

        if shouldClearSharedUnlockExpiration {
            SharedAppGroup.publishUnlockExpiration(nil)
        }
        publishShieldContext()

        switch questionPreparation {
        case let .initial(goalToPrepare):
            prepareInitialQuestionsInBackground(for: goalToPrepare)
        case let .topOff(goalToPrepare, starterQuestionIDs):
            topOffQuestionBankInBackground(
                for: goalToPrepare,
                starterQuestionIDs: starterQuestionIDs
            )
        case nil:
            break
        }

        return .committed(resultingGoalID: goal?.id)
    }

    private func resolvedGoal(
        from draft: GoalProfileDraft,
        id: Goal.ID,
        createdAt: Date,
        minimumDeadline: Date,
        existingGoal: Goal? = nil
    ) -> Goal {
        let normalizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLevel = draft.currentLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFocus = draft.focusAreas.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDocuments = GoalSourceDocument.normalizedDocuments(draft.sourceDocuments)
        var preservedSkillMap = existingGoal?.derivedSkillMap

        if let existingGoal,
           normalizedTitle != existingGoal.title
            || draft.category != existingGoal.category
            || normalizedLevel != existingGoal.currentLevel
            || normalizedFocus != existingGoal.focusAreas
            || normalizedDocuments != existingGoal.sourceDocuments {
            preservedSkillMap = nil
        }

        return Goal(
            id: id,
            title: normalizedTitle,
            deadline: max(draft.deadline, minimumDeadline),
            category: draft.category,
            currentLevel: normalizedLevel,
            focusAreas: normalizedFocus,
            sourceDocuments: normalizedDocuments,
            derivedSkillMap: preservedSkillMap,
            preferredQuestionStyle: draft.preferredQuestionStyle,
            minimumQuestionDifficulty: draft.minimumQuestionDifficulty,
            createdAt: createdAt
        )
    }

    private func commitGoalCreation(_ newGoal: Goal) -> Bool {
        let isFirstGoal = goal == nil
        let sourceGoalID = goal?.id
        questionRefreshesUsed = 0
        questionBatchState = .generating
        goal = newGoal
        isQuestionBankTopOffInProgress = false
        questionBankTopOffStartedAt = nil
        questions.removeAll { $0.goalID == newGoal.id }
        competencies.removeAll { $0.goalID == newGoal.id }
        competencies.append(
            contentsOf: SkillMapReconciler.initialCompetencies(
                for: newGoal,
                questions: []
            )
        )
        lastAIErrorMessage = nil
        lastQuestionGenerationFailure = nil
        questionGenerationStartedAt = nil
        lastQuestionGenerationDuration = nil
        checkpointNotice = nil
        if isFirstGoal {
            unlockSession = nil
        }
        isOnboardingPresented = false
        isCreatingGoalProfile = false
        pendingMembershipPresentation = nil
        return clearMembershipActivationResumeIfMatching(
            .createGoalProfile(sourceGoalID: sourceGoalID)
        )
    }

    private func commitGoalEdit(
        from currentGoal: Goal?,
        to updatedGoal: Goal
    ) -> GoalProfileQuestionPreparation? {
        guard let currentGoal else { return nil }
        let starterPracticeWasConsumed = hasConsumedStarterPractice
        let skillContextChanged =
            updatedGoal.title != currentGoal.title
                || updatedGoal.category != currentGoal.category
                || updatedGoal.currentLevel != currentGoal.currentLevel
                || updatedGoal.focusAreas != currentGoal.focusAreas
                || updatedGoal.sourceDocuments != currentGoal.sourceDocuments
        let generationContextChanged =
            skillContextChanged
                || updatedGoal.preferredQuestionStyle != currentGoal.preferredQuestionStyle
                || updatedGoal.minimumQuestionDifficulty != currentGoal.minimumQuestionDifficulty
        let canRegenerateForEdit = isMember || !starterPracticeWasConsumed

        goal = updatedGoal
        isOnboardingPresented = false
        isCreatingGoalProfile = false
        pendingMembershipPresentation = nil

        guard generationContextChanged else { return nil }

        questionBankSyncIntents.removeAll { $0.goalID == updatedGoal.id }
        skillMapEvolutionIntents.removeAll { $0.goalID == updatedGoal.id }
        questionBankPollingGoalIDs.remove(updatedGoal.id)
        questionBankPollingTokens.removeValue(forKey: updatedGoal.id)

        if checkpointReadiness(for: updatedGoal).hasFullCheckpoint {
            checkpointNotice = "Goal updated. Your current questions stay available; future questions will use these changes."
            questionBatchState = .ready
            return nil
        }

        guard canRegenerateForEdit else {
            questionBatchState = .idle
            checkpointNotice = "Goal updated. Pro can prepare more questions after your Free set is used."
            pendingMembershipPresentation = .feature(.freshQuestionGeneration)
            return nil
        }

        questionBatchState = .generating
        lastAIErrorMessage = nil
        lastQuestionGenerationFailure = nil
        checkpointNotice = nil
        guard !backgroundGenerationGoalIDs.contains(updatedGoal.id),
              !questionBankTopOffGoalIDs.contains(updatedGoal.id) else {
            return nil
        }
        let selector = questionSelector(for: updatedGoal)
        let retainedQuestionIDs = Set(
            questions.lazy
                .filter { $0.goalID == updatedGoal.id && selector.isSelectableQuestion($0) }
                .map(\.id)
        )
        if retainedQuestionIDs.isEmpty {
            return .initial(updatedGoal)
        }
        return .topOff(
            updatedGoal,
            starterQuestionIDs: retainedQuestionIDs
        )
    }

    private func commitGoalDeletion(
        _ plan: GoalProfileMutationPlan
    ) -> (
        questionPreparation: GoalProfileQuestionPreparation?,
        clearsUnlockExpiration: Bool
    ) {
        let deletedGoal = plan.targetGoal
        let wasActiveGoal = plan.sourceGoal?.id == deletedGoal.id

        backgroundGenerationGoalIDs.remove(deletedGoal.id)
        questionBankTopOffGoalIDs.remove(deletedGoal.id)
        removeGoalData(
            for: deletedGoal.id,
            includeLegacyCompetencies: wasActiveGoal
        )
        goalProfiles.removeAll { $0.id == deletedGoal.id }

        guard wasActiveGoal else {
            checkpointNotice = "\(deletedGoal.title) was deleted."
            pendingMembershipPresentation = nil
            isCreatingGoalProfile = false
            return (nil, false)
        }

        goal = plan.resultingActiveGoal
        questionGenerationStartedAt = nil
        lastQuestionGenerationDuration = nil
        lastAIErrorMessage = nil
        lastQuestionGenerationFailure = nil

        var questionPreparation: GoalProfileQuestionPreparation?
        var replacementNeedsMembership = false
        var replacementPreparationIsBlocked = false
        var clearsUnlockExpiration = false

        if let replacementGoal = plan.resultingActiveGoal {
            if hasLegacyLocalQuestionBank(for: replacementGoal) {
                clearQuestionBank(for: replacementGoal.id)
            }

            let readiness = checkpointReadiness(for: replacementGoal)
            questionBatchState = readiness.hasFullCheckpoint ? .ready : .generating
            isQuestionBankTopOffInProgress = questionBankTopOffGoalIDs.contains(
                replacementGoal.id
            )
            questionBankTopOffStartedAt = isQuestionBankTopOffInProgress
                ? questionBankTopOffStartedAt ?? Date()
                : nil

            let isAlreadyPreparing = backgroundGenerationGoalIDs.contains(
                replacementGoal.id
            ) || questionBankTopOffGoalIDs.contains(replacementGoal.id)
            if !readiness.hasFullCheckpoint && !isAlreadyPreparing {
                if hasBlockedQuestionBankSyncIntent(for: replacementGoal) {
                    questionBatchState = .failed
                    replacementPreparationIsBlocked = true
                } else if isMember || !hasConsumedStarterPractice {
                    let selector = questionSelector(for: replacementGoal)
                    let retainedQuestionIDs = Set(
                        questions.lazy
                            .filter {
                                $0.goalID == replacementGoal.id
                                    && selector.isSelectableQuestion($0)
                            }
                            .map(\.id)
                    )
                    questionPreparation = retainedQuestionIDs.isEmpty
                        ? .initial(replacementGoal)
                        : .topOff(
                            replacementGoal,
                            starterQuestionIDs: retainedQuestionIDs
                        )
                } else {
                    questionBatchState = .idle
                    replacementNeedsMembership = true
                }
            }
        } else {
            questionBatchState = .idle
            isQuestionBankTopOffInProgress = false
            questionBankTopOffStartedAt = nil
            unlockSession = nil
            isOnboardingPresented = true
            clearsUnlockExpiration = true
        }

        if replacementNeedsMembership {
            checkpointNotice = "\(deletedGoal.title) was deleted. \(starterQuestionLimitMessage)"
            pendingMembershipPresentation = .feature(.freshQuestionGeneration)
        } else if replacementPreparationIsBlocked {
            checkpointNotice = "\(deletedGoal.title) was deleted. Practice for \(plan.resultingActiveGoal?.title ?? "the replacement goal") still needs attention before protection can restart."
            pendingMembershipPresentation = nil
        } else {
            checkpointNotice = "\(deletedGoal.title) was deleted."
            pendingMembershipPresentation = nil
        }
        isCreatingGoalProfile = false
        return (questionPreparation, clearsUnlockExpiration)
    }

    private func goalProfileMutationRollbackState() -> GoalProfileMutationRollbackState {
        GoalProfileMutationRollbackState(
            goal: goal,
            goalProfiles: goalProfiles,
            questions: questions,
            attempts: attempts,
            competencies: competencies,
            focusWins: focusWins,
            unlockEvents: unlockEvents,
            questionReports: questionReports,
            issueReports: issueReports,
            questionGenerationTraces: questionGenerationTraces,
            questionBatchState: questionBatchState,
            lastAIErrorMessage: lastAIErrorMessage,
            lastQuestionGenerationFailure: lastQuestionGenerationFailure,
            questionGenerationStartedAt: questionGenerationStartedAt,
            lastQuestionGenerationDuration: lastQuestionGenerationDuration,
            isQuestionBankTopOffInProgress: isQuestionBankTopOffInProgress,
            questionBankTopOffStartedAt: questionBankTopOffStartedAt,
            lastQuestionBankTopOffDuration: lastQuestionBankTopOffDuration,
            checkpointNotice: checkpointNotice,
            unlockSession: unlockSession,
            isOnboardingPresented: isOnboardingPresented,
            isCreatingGoalProfile: isCreatingGoalProfile,
            pendingMembershipPresentation: pendingMembershipPresentation,
            membershipActivationHandoff: membershipActivationHandoff,
            questionRefreshesUsed: questionRefreshesUsed,
            questionBankSyncIntents: questionBankSyncIntents,
            skillMapEvolutionIntents: skillMapEvolutionIntents,
            backgroundGenerationGoalIDs: backgroundGenerationGoalIDs,
            questionBankTopOffGoalIDs: questionBankTopOffGoalIDs,
            questionBankPollingGoalIDs: questionBankPollingGoalIDs,
            questionBankPollingTokens: questionBankPollingTokens,
            questionBankSynchronizationGoalIDs: questionBankSynchronizationGoalIDs,
            skillMapEvolutionGoalIDs: skillMapEvolutionGoalIDs,
            permitsPersistenceWrites: permitsPersistenceWrites,
            hasNoPersistedAppData: hasNoPersistedAppData,
            requiresPersistenceEraseRecovery: requiresPersistenceEraseRecovery,
            dataLifecycleID: dataLifecycleID
        )
    }

    private func restoreGoalProfileMutationState(
        _ state: GoalProfileMutationRollbackState
    ) {
        goalProfiles = state.goalProfiles
        goal = state.goal
        questions = state.questions
        attempts = state.attempts
        competencies = state.competencies
        focusWins = state.focusWins
        unlockEvents = state.unlockEvents
        questionReports = state.questionReports
        issueReports = state.issueReports
        questionGenerationTraces = state.questionGenerationTraces
        questionBatchState = state.questionBatchState
        lastAIErrorMessage = state.lastAIErrorMessage
        lastQuestionGenerationFailure = state.lastQuestionGenerationFailure
        questionGenerationStartedAt = state.questionGenerationStartedAt
        lastQuestionGenerationDuration = state.lastQuestionGenerationDuration
        isQuestionBankTopOffInProgress = state.isQuestionBankTopOffInProgress
        questionBankTopOffStartedAt = state.questionBankTopOffStartedAt
        lastQuestionBankTopOffDuration = state.lastQuestionBankTopOffDuration
        checkpointNotice = state.checkpointNotice
        unlockSession = state.unlockSession
        isOnboardingPresented = state.isOnboardingPresented
        isCreatingGoalProfile = state.isCreatingGoalProfile
        pendingMembershipPresentation = state.pendingMembershipPresentation
        membershipActivationHandoff = state.membershipActivationHandoff
        questionRefreshesUsed = state.questionRefreshesUsed
        questionBankSyncIntents = state.questionBankSyncIntents
        skillMapEvolutionIntents = state.skillMapEvolutionIntents
        backgroundGenerationGoalIDs = state.backgroundGenerationGoalIDs
        questionBankTopOffGoalIDs = state.questionBankTopOffGoalIDs
        questionBankPollingGoalIDs = state.questionBankPollingGoalIDs
        questionBankPollingTokens = state.questionBankPollingTokens
        questionBankSynchronizationGoalIDs = state.questionBankSynchronizationGoalIDs
        skillMapEvolutionGoalIDs = state.skillMapEvolutionGoalIDs
        permitsPersistenceWrites = state.permitsPersistenceWrites
        hasNoPersistedAppData = state.hasNoPersistedAppData
        requiresPersistenceEraseRecovery = state.requiresPersistenceEraseRecovery
        dataLifecycleID = state.dataLifecycleID
    }

    func prepareGoalActivation(to targetGoalID: Goal.ID) -> GoalActivationPreflight {
        guard let targetGoal = availableGoalProfiles.first(where: {
            $0.id == targetGoalID
        }) else {
            return .targetNotFound
        }
        guard targetGoal.id != goal?.id else {
            return .alreadyActive
        }
        guard canUse(.goalProfiles) else {
            return .membershipRequired
        }

        return .eligible(
            GoalActivationPlan(
                sourceGoalID: goal?.id,
                targetGoalID: targetGoal.id,
                targetTitle: targetGoal.title,
                readiness: checkpointReadiness(for: targetGoal)
            )
        )
    }

    func activateGoal(using plan: GoalActivationPlan) -> GoalActivationResult {
        guard plan.sourceGoalID == goal?.id else {
            return .stalePlan
        }

        switch prepareGoalActivation(to: plan.targetGoalID) {
        case let .eligible(validatedPlan):
            guard validatedPlan.sourceGoalID == plan.sourceGoalID else {
                return .stalePlan
            }
            return commitGoalActivation(using: validatedPlan)
        case .alreadyActive:
            return .alreadyActive
        case .targetNotFound:
            return .targetNotFound
        case .membershipRequired:
            return .membershipRequired
        }
    }

    func presentGoalProfileCreator() {
        guard goal == nil || canUse(.goalProfiles) else {
            requestMembership(
                for: .goalProfiles,
                continuation: .createGoalProfile(sourceGoalID: goal?.id)
            )
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

    private func commitGoalActivation(
        using plan: GoalActivationPlan
    ) -> GoalActivationResult {
        guard let selectedGoal = availableGoalProfiles.first(where: {
            $0.id == plan.targetGoalID
        }) else {
            return .targetNotFound
        }

        let rollbackState = goalProfileMutationRollbackState()

        goal = selectedGoal
        if hasLegacyLocalQuestionBank(for: selectedGoal) {
            clearQuestionBank(for: selectedGoal.id)
        }

        let hasActiveQuestions = !activeQuestions.isEmpty
        questionBatchState = hasActiveQuestions ? .ready : .generating
        isQuestionBankTopOffInProgress = questionBankTopOffGoalIDs.contains(selectedGoal.id)
        questionBankTopOffStartedAt = isQuestionBankTopOffInProgress ? questionBankTopOffStartedAt ?? Date() : nil
        checkpointNotice = nil
        let clearedMembershipActivationResume = clearMembershipActivationResumeIfMatching(
            .activateGoal(
                sourceGoalID: plan.sourceGoalID,
                targetGoalID: selectedGoal.id
            )
        )
        guard save(mirroringRecovery: clearedMembershipActivationResume) else {
            restoreGoalProfileMutationState(rollbackState)
            return .persistenceFailed
        }
        publishShieldContext()

        if hasActiveQuestions {
            _ = scheduleSkillMapEvolutionIfNeeded(for: selectedGoal)
            Task { [weak self] in
                _ = await self?.refreshQuestionBatchIfNeeded()
                await self?.prepareProtectionReviewQuestionBankIfNeeded()
            }
        } else {
            _ = scheduleSkillMapEvolutionIfNeeded(for: selectedGoal)
            prepareInitialQuestionsInBackground(for: selectedGoal)
        }
        return .activated(from: plan.sourceGoalID, to: selectedGoal.id)
    }

    @discardableResult
    func deleteGoalProfile(_ goalID: Goal.ID) -> Bool {
        let request = GoalProfileMutationRequest(
            operation: .delete(goalID: goalID)
        )
        guard case let .eligible(plan) = prepareGoalProfileMutation(request),
              case .committed = commitGoalProfileMutation(using: plan) else {
            return false
        }
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

    func requestMembership(
        for feature: MembershipFeature,
        continuation: MembershipActivationContinuation? = nil
    ) {
        if let membershipActivationHandoff {
            if membershipActivationHandoff.phase != .resumeRequested {
                pendingMembershipPresentation = membershipActivationHandoff.request.context
            }
            return
        }

        let context = MembershipPresentationContext.feature(feature)
        pendingMembershipPresentation = context
        shouldPresentMembershipActivationHandoff = false
        let request = MembershipActivationRequest(
            context: context,
            continuation: continuation
        )
        if !transitionMembershipActivationHandoff(.request(request)),
           continuation != nil {
            pendingMembershipPresentation = nil
        }
    }

    func requestMembershipOverview() {
        guard membershipActivationHandoff == nil else {
            if membershipActivationHandoff?.phase != .resumeRequested {
                pendingMembershipPresentation = membershipActivationHandoff?.request.context
            }
            return
        }
        pendingMembershipPresentation = .overview
        shouldPresentMembershipActivationHandoff = false
        guard !isMember else { return }
        let request = MembershipActivationRequest(context: .overview)
        _ = transitionMembershipActivationHandoff(.request(request))
    }

    func membershipCheckoutStarted() -> Bool {
        guard membershipActivationHandoff != nil else { return true }
        return transitionMembershipActivationHandoff(.checkoutStarted)
    }

    func membershipCheckoutFinished(hasUnresolvedPurchase: Bool) {
        _ = transitionMembershipActivationHandoff(
            .checkoutFinished(hasUnresolvedPurchase: hasUnresolvedPurchase)
        )
    }

    @discardableResult
    func dismissMembershipPrompt(hasUnresolvedPurchase: Bool = false) -> Bool {
        guard transitionMembershipActivationHandoff(
            .dismissed(hasUnresolvedPurchase: hasUnresolvedPurchase)
        ) else {
            return false
        }
        pendingMembershipPresentation = nil
        shouldPresentMembershipActivationHandoff = false
        if membershipActivationHandoff == nil {
            claimedMembershipActivationRequestID = nil
        }
        return true
    }

    func reconcileMembershipEntitlement(
        isUnlocked: Bool,
        activationSource: MembershipActivationSource = .entitlementRefresh
    ) {
        membershipEntitlementWasVerifiedThisLaunch = true
        let resolvedTier: MembershipTier = isUnlocked ? .member : .starter
        if isUnlocked {
            _ = transitionMembershipActivationHandoff(
                .entitlementVerified(source: activationSource)
            )
            shouldPresentMembershipActivationHandoff =
                membershipActivationHandoff?.phase == .activationReady
                    || (membershipActivationHandoff?.phase == .resumeRequested
                        && claimedMembershipActivationRequestID
                            != membershipActivationHandoff?.request.id)
        } else if membershipTier == .member {
            _ = transitionMembershipActivationHandoff(.entitlementRevoked)
            shouldPresentMembershipActivationHandoff = false
        }
        guard resolvedTier != membershipTier else { return }
        applyMembershipTier(
            resolvedTier,
            dismissesMembershipPrompt: !isUnlocked && pendingMembershipPresentation != nil
        )
    }

    func updateMembershipTier(_ tier: MembershipTier) {
        membershipEntitlementWasVerifiedThisLaunch = tier == .member
        if tier == .starter {
            _ = transitionMembershipActivationHandoff(.entitlementRevoked)
            shouldPresentMembershipActivationHandoff = false
        }
        applyMembershipTier(tier, dismissesMembershipPrompt: true)
    }

    @discardableResult
    func completeMembershipCheckout(
        source: MembershipActivationSource = .entitlementRefresh
    ) -> MembershipActivationContinuation? {
        guard membershipEntitlementWasVerifiedThisLaunch, isMember else { return nil }
        _ = transitionMembershipActivationHandoff(
            .entitlementVerified(source: source)
        )
        shouldPresentMembershipActivationHandoff =
            membershipActivationHandoff?.phase == .activationReady
                || (membershipActivationHandoff?.phase == .resumeRequested
                    && claimedMembershipActivationRequestID
                        != membershipActivationHandoff?.request.id)
        return resolvedMembershipActivationContinuation()?.continuation
    }

    func membershipActivationPresentation(
        fallbackContext: MembershipPresentationContext,
        fallbackSource: MembershipActivationSource
    ) -> MembershipActivationPresentation {
        membershipActivationPresentationIfVerified(
            fallbackContext: fallbackContext,
            fallbackSource: fallbackSource
        ) ?? MembershipActivationPresentation(
            context: fallbackContext,
            source: fallbackSource,
            continuation: nil
        )
    }

    func membershipActivationPresentationIfVerified(
        fallbackContext: MembershipPresentationContext,
        fallbackSource: MembershipActivationSource
    ) -> MembershipActivationPresentation? {
        guard membershipEntitlementWasVerifiedThisLaunch,
              isMember,
              let membershipActivationHandoff,
              membershipActivationHandoff.phase == .activationReady
                || membershipActivationHandoff.phase == .resumeRequested else {
            return nil
        }

        let resolution = resolvedMembershipActivationContinuation()
        return MembershipActivationPresentation(
            id: membershipActivationHandoff.request.id,
            context: membershipActivationHandoff.request.context,
            source: membershipActivationHandoff.source ?? fallbackSource,
            continuation: resolution?.continuation,
            destinationTitle: resolution?.destinationTitle
        )
    }

    func requestMembershipActivationResume() -> MembershipActivationResumeResult {
        guard membershipEntitlementWasVerifiedThisLaunch,
              isMember,
              membershipActivationHandoff?.phase == .activationReady,
              resolvedMembershipActivationContinuation() != nil else {
            return .actionUnavailable
        }
        let persisted = transitionMembershipActivationHandoff(.resumeRequested)
        if persisted {
            pendingMembershipPresentation = nil
            shouldPresentMembershipActivationHandoff = false
            claimedMembershipActivationRequestID = nil
            return .requested
        }
        return .persistenceFailed
    }

    func claimMembershipActivationContinuationForResume() -> MembershipActivationContinuation? {
        guard membershipEntitlementWasVerifiedThisLaunch,
              isMember,
              let membershipActivationHandoff,
              membershipActivationHandoff.phase == .resumeRequested else {
            return nil
        }
        guard claimedMembershipActivationRequestID != membershipActivationHandoff.request.id else {
            shouldPresentMembershipActivationHandoff = false
            return nil
        }
        guard let resolution = resolvedMembershipActivationContinuation() else {
            _ = returnMembershipActivationResumeToReceipt()
            return nil
        }
        claimedMembershipActivationRequestID = membershipActivationHandoff.request.id
        shouldPresentMembershipActivationHandoff = false
        return resolution.continuation
    }

    @discardableResult
    func returnMembershipActivationResumeToReceipt() -> Bool {
        guard membershipActivationHandoff?.phase == .resumeRequested else { return true }
        guard transitionMembershipActivationHandoff(.resumeFailed) else { return false }
        pendingMembershipPresentation = nil
        claimedMembershipActivationRequestID = nil
        shouldPresentMembershipActivationHandoff = true
        return true
    }

    @discardableResult
    func cancelResumedMembershipGoalCreation() -> Bool {
        guard let membershipActivationHandoff,
              membershipActivationHandoff.phase == .resumeRequested,
              case .createGoalProfile = membershipActivationHandoff.request.continuation else {
            return true
        }
        guard transitionMembershipActivationHandoff(.abandoned) else { return false }
        claimedMembershipActivationRequestID = nil
        shouldPresentMembershipActivationHandoff = false
        return true
    }

    @discardableResult
    func cancelResumedMembershipGoalSwitch(to targetGoalID: Goal.ID) -> Bool {
        guard let membershipActivationHandoff,
              membershipActivationHandoff.phase == .resumeRequested,
              case let .activateGoal(_, requestedTargetGoalID) =
                membershipActivationHandoff.request.continuation,
              requestedTargetGoalID == targetGoalID else {
            return true
        }
        guard transitionMembershipActivationHandoff(.abandoned) else { return false }
        claimedMembershipActivationRequestID = nil
        shouldPresentMembershipActivationHandoff = false
        return true
    }

    @discardableResult
    func completeResumedMembershipGoalSwitch(to targetGoalID: Goal.ID) -> Bool {
        guard let membershipActivationHandoff,
              membershipActivationHandoff.phase == .resumeRequested,
              case let .activateGoal(_, requestedTargetGoalID) =
                membershipActivationHandoff.request.continuation,
              requestedTargetGoalID == targetGoalID else {
            return true
        }
        guard transitionMembershipActivationHandoff(.consumed) else { return false }
        claimedMembershipActivationRequestID = nil
        shouldPresentMembershipActivationHandoff = false
        return true
    }

    @discardableResult
    func completeResumedMembershipNextFocusReveal(
        for sourceGoalID: Goal.ID
    ) -> Bool {
        guard let membershipActivationHandoff,
              membershipActivationHandoff.phase == .resumeRequested,
              case let .revealNextFocus(requestedSourceGoalID) =
                membershipActivationHandoff.request.continuation,
              requestedSourceGoalID == sourceGoalID else {
            return true
        }
        guard transitionMembershipActivationHandoff(.consumed) else { return false }
        claimedMembershipActivationRequestID = nil
        shouldPresentMembershipActivationHandoff = false
        return true
    }

    func reconcileMembershipActivationAfterLaunch(
        isUnlocked: Bool,
        hasUnresolvedPurchase: Bool
    ) {
        guard membershipEntitlementWasVerifiedThisLaunch,
              isUnlocked == isMember,
              membershipActivationHandoff != nil else { return }

        if isUnlocked {
            _ = transitionMembershipActivationHandoff(
                .entitlementVerified(source: .entitlementRefresh)
            )
        } else if hasUnresolvedPurchase {
            _ = transitionMembershipActivationHandoff(.checkoutStarted)
        } else if membershipActivationHandoff?.phase == .awaitingEntitlement {
            // StoreKit can terminate the process while its purchase sheet is
            // still open, before it returns a result that creates a pending
            // marker. Keep the paid action retryable so a later transaction
            // update can still deliver its exact continuation.
            _ = transitionMembershipActivationHandoff(
                .checkoutFinished(hasUnresolvedPurchase: false)
            )
        } else {
            _ = transitionMembershipActivationHandoff(.abandoned)
        }
        shouldPresentMembershipActivationHandoff = membershipActivationHandoff != nil
    }

    var membershipActivationContextReadyForPresentation: MembershipPresentationContext? {
        guard let membershipActivationHandoff,
              membershipActivationHandoff.phase != .resumeRequested else {
            return nil
        }
        if membershipActivationHandoff.phase == .activationReady,
           (!membershipEntitlementWasVerifiedThisLaunch || !isMember) {
            return nil
        }
        return membershipActivationHandoff.request.context
    }

    var hasMembershipActivationResumeRequest: Bool {
        membershipActivationHandoff?.phase == .resumeRequested
    }

    var hasMembershipActivationReceipt: Bool {
        membershipActivationHandoff?.phase == .activationReady
            || membershipActivationHandoff?.phase == .resumeRequested
    }

    var hasResumedMembershipGoalCreation: Bool {
        guard membershipActivationHandoff?.phase == .resumeRequested,
              case .createGoalProfile = membershipActivationHandoff?.request.continuation else {
            return false
        }
        return true
    }

    var hasDeferredMembershipActivationPresentation: Bool {
        shouldPresentMembershipActivationHandoff && membershipActivationHandoff != nil
    }

    func presentMembershipActivationHandoffIfAvailable() -> Bool {
        guard shouldPresentMembershipActivationHandoff,
              pendingMembershipPresentation == nil,
              let context = membershipActivationContextReadyForPresentation else {
            return false
        }
        pendingMembershipPresentation = context
        shouldPresentMembershipActivationHandoff = false
        return true
    }

    private func resolvedMembershipActivationContinuation() -> (
        continuation: MembershipActivationContinuation,
        destinationTitle: String?
    )? {
        guard let continuation = membershipActivationHandoff?.request.continuation else {
            return nil
        }
        switch continuation {
        case let .createGoalProfile(sourceGoalID):
            guard goal?.id == sourceGoalID,
                  canCreateAdditionalGoalProfile else {
                return nil
            }
            return (continuation, nil)
        case let .activateGoal(sourceGoalID, targetGoalID):
            guard goal?.id == sourceGoalID,
                  targetGoalID != sourceGoalID,
                  let targetGoal = availableGoalProfiles.first(where: {
                      $0.id == targetGoalID
                  }) else {
                return nil
            }
            let destinationTitle = GoalDisplayTitleResolver(
                goals: availableGoalProfiles
            ).title(for: targetGoal)
            return (continuation, destinationTitle)
        case let .revealNextFocus(sourceGoalID):
            guard goal?.id == sourceGoalID,
                  activeDerivedSkillMap?.status == .reviewed,
                  studyFocusState != nil
                    || (canUse(.adaptiveStudyAssist)
                        && isPreparingActiveGoalQuestions
                        && !isQuestionGenerationBlockingPractice) else {
                return nil
            }
            return (continuation, nil)
        }
    }

    @discardableResult
    private func clearMembershipActivationResumeIfMatching(
        _ continuation: MembershipActivationContinuation
    ) -> Bool {
        guard membershipActivationHandoff?.phase == .resumeRequested,
              membershipActivationHandoff?.request.continuation == continuation else {
            return false
        }
        membershipActivationHandoff = nil
        claimedMembershipActivationRequestID = nil
        shouldPresentMembershipActivationHandoff = false
        return true
    }

    @discardableResult
    private func transitionMembershipActivationHandoff(
        _ event: MembershipActivationHandoffEvent
    ) -> Bool {
        let next = MembershipActivationHandoffReducer.reduce(
            membershipActivationHandoff,
            event: event
        )
        guard next != membershipActivationHandoff else { return true }
        let previous = membershipActivationHandoff
        membershipActivationHandoff = next
        guard persistMembershipActivationHandoff() else {
            membershipActivationHandoff = previous
            return false
        }
        return true
    }

    @discardableResult
    private func persistMembershipActivationHandoff() -> Bool {
        save(mirroringRecovery: true)
    }

    private func applyMembershipTier(
        _ tier: MembershipTier,
        dismissesMembershipPrompt: Bool
    ) {
        guard membershipTier != tier else {
            if dismissesMembershipPrompt, pendingMembershipPresentation != nil {
                pendingMembershipPresentation = nil
                save()
                publishShieldContext()
            }
            return
        }

        membershipTier = tier
        if dismissesMembershipPrompt {
            pendingMembershipPresentation = nil
        }
        save()
        publishShieldContext()

        if tier == .member, goal != nil {
            resumeSkillMapEvolutionIfNeeded()
            if let goal {
                _ = scheduleSkillMapEvolutionIfNeeded(for: goal)
            }
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
        competencies.append(contentsOf: SkillMapReconciler.initialCompetencies(for: newGoal, questions: []))
        lastAIErrorMessage = nil
        lastQuestionGenerationFailure = nil
        checkpointNotice = nil
        if previousGoalID == nil {
            unlockSession = nil
        }
        isOnboardingPresented = false
        isCreatingGoalProfile = false
        let clearedMembershipActivationResume = clearMembershipActivationResumeIfMatching(
            .createGoalProfile(sourceGoalID: previousGoalID)
        )
        if previousGoalID == nil, permitsPersistenceWrites {
            SharedAppGroup.publishUnlockExpiration(nil)
        }
        save(mirroringRecovery: clearedMembershipActivationResume)
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
        pendingMembershipPresentation = nil

        guard generationContextChanged else {
            save()
            publishShieldContext()
            return
        }

        questionBankSyncIntents.removeAll { $0.goalID == updatedGoal.id }
        skillMapEvolutionIntents.removeAll { $0.goalID == updatedGoal.id }
        questionBankPollingGoalIDs.remove(updatedGoal.id)
        questionBankPollingTokens.removeValue(forKey: updatedGoal.id)

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

    private func generateInitialQuestionBatch(
        for newGoal: Goal,
        requiredActiveGoalID: Goal.ID? = nil
    ) async {
        let lifecycleID = dataLifecycleID
        guard requiredActiveGoalID == nil
                || (!Task.isCancelled && goal?.id == requiredActiveGoalID) else {
            return
        }
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
            lifecycleID: lifecycleID,
            requiredActiveGoalID: requiredActiveGoalID
        )
        guard hasQuestionGenerationMutationAuthority(
            lifecycleID: lifecycleID,
            requiredActiveGoalID: requiredActiveGoalID
        ) else {
            clearCancelledRequiredQuestionGeneration(
                for: newGoal.id,
                lifecycleID: lifecycleID,
                requiredActiveGoalID: requiredActiveGoalID
            )
            return
        }

        if shouldUseDurableQuestionBank {
            let syncOutcome = await synchronizeDurableQuestionBank(
                for: generationGoal,
                minimumLocalQuestionCount: questionBankTargetCount,
                requiredActiveGoalID: requiredActiveGoalID
            )
            guard hasQuestionGenerationMutationAuthority(
                lifecycleID: lifecycleID,
                requiredActiveGoalID: requiredActiveGoalID
            ) else {
                clearCancelledRequiredQuestionGeneration(
                    for: newGoal.id,
                    lifecycleID: lifecycleID,
                    requiredActiveGoalID: requiredActiveGoalID
                )
                return
            }
            guard let latestGoal = storedGoalProfile(withID: newGoal.id) else { return }

            if !SkillMapReconciler.hasSameGenerationContext(latestGoal, generationGoal) {
                backgroundGenerationGoalIDs.remove(newGoal.id)
                if goal?.id == newGoal.id {
                    finishQuestionGeneration(for: newGoal.id)
                }
                await generateInitialQuestionBatch(
                    for: latestGoal,
                    requiredActiveGoalID: requiredActiveGoalID
                )
                return
            }

            if syncOutcome.serviceSupported {
                if goal?.id == newGoal.id {
                    questionBatchState = checkpointReadiness(for: latestGoal).hasFullCheckpoint
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

        let existingGoalQuestions = questions.filter {
            $0.goalID == generationGoal.id
        }
        let checkpointReadyRequest = generationRequest(
            goal: generationGoal,
            existingQuestions: existingGoalQuestions,
            competencies: competencies.filter {
                ($0.goalID ?? generationGoal.id) == generationGoal.id
            },
            reportedQuestions: questionReports.filter {
                $0.goalID == generationGoal.id
            },
            targetCount: unlockPolicy.questionsPerSession
        )

        let startedAt = Date()
        let providerPreference = aiProviderPreference
        let batch = await questionEngine.generateQuestionBatch(
            for: checkpointReadyRequest,
            preference: providerPreference
        )

        guard hasQuestionGenerationMutationAuthority(
            lifecycleID: lifecycleID,
            requiredActiveGoalID: requiredActiveGoalID
        ) else {
            clearCancelledRequiredQuestionGeneration(
                for: newGoal.id,
                lifecycleID: lifecycleID,
                requiredActiveGoalID: requiredActiveGoalID
            )
            return
        }

        guard var resolvedGoal = storedGoalProfile(withID: newGoal.id) else {
            return
        }

        guard SkillMapReconciler.hasSameGenerationContext(resolvedGoal, generationGoal) else {
            backgroundGenerationGoalIDs.remove(newGoal.id)
            if goal?.id == newGoal.id {
                finishQuestionGeneration(for: newGoal.id)
            }
            await generateInitialQuestionBatch(
                for: resolvedGoal,
                requiredActiveGoalID: requiredActiveGoalID
            )
            return
        }

        var acceptedQuestions = SkillMapReconciler.canonicalizedQuestions(batch.questions, for: resolvedGoal)
        let hasReadyInitialSet = acceptedQuestions.count >= unlockPolicy.questionsPerSession
        var committedQuestions: [CheckpointQuestion] = []
        if hasReadyInitialSet {
            resolvedGoal = commitInferredSkillMapIfNeeded(
                for: resolvedGoal,
                questions: acceptedQuestions
            )
            acceptedQuestions = SkillMapReconciler.canonicalizedQuestions(acceptedQuestions, for: resolvedGoal)
            let existingCompetencies = competencies.filter {
                ($0.goalID ?? resolvedGoal.id) == resolvedGoal.id
            }
            for index in questions.indices where questions[index].goalID == newGoal.id {
                questions[index].status = .retired
                questions[index].nextReviewAt = nil
            }
            questions.append(contentsOf: acceptedQuestions)
            replaceCompetencies(
                for: resolvedGoal.id,
                with: SkillMapReconciler.reconciledCompetencies(
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
        lifecycleID: UUID,
        requiredActiveGoalID: Goal.ID?
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

        guard hasQuestionGenerationMutationAuthority(
                  lifecycleID: lifecycleID,
                  requiredActiveGoalID: requiredActiveGoalID
              ),
              var latestGoal = storedGoalProfile(withID: targetGoal.id),
              latestGoal.derivedSkillMap == nil,
              SkillMapReconciler.hasSameGenerationContext(latestGoal, targetGoal),
              let normalizedMap = SkillMapReconciler.normalizedSkillMap(inferredMap) else {
            return storedGoalProfile(withID: targetGoal.id) ?? targetGoal
        }

        latestGoal.derivedSkillMap = normalizedMap
        storeGoalProfile(latestGoal)
        replaceCompetencies(
            for: latestGoal.id,
            with: SkillMapReconciler.reconciledCompetencies(
                existing: competencies.filter { ($0.goalID ?? latestGoal.id) == latestGoal.id },
                goal: latestGoal,
                questions: questions.filter { $0.goalID == latestGoal.id }
            )
        )
        save()
        publishShieldContext()
        return latestGoal
    }

    func retryInitialQuestionGeneration() async {
        guard let goal else { return }
        // A blocked bank cycle is terminal for automatic work, but this explicit
        // action is the user's opt-in to start a fresh server cycle.
        invalidateQuestionBankSynchronization(for: goal.id)
        save()
        await generateInitialQuestionBatch(for: goal)
    }

    @discardableResult
    func prepareQuestionsForProtectionStart(
        expectedGoalID: Goal.ID?
    ) async -> Bool {
        guard !Task.isCancelled,
              goal?.id == expectedGoalID else { return false }
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
            await generateInitialQuestionBatch(
                for: goal,
                requiredActiveGoalID: expectedGoalID
            )
        } else if isMember {
            _ = await refreshQuestionBatchIfNeeded(
                requiredActiveGoalID: expectedGoalID
            )
        } else {
            checkpointNotice = starterQuestionLimitMessage
            requestMembership(for: .freshQuestionGeneration)
        }

        guard !Task.isCancelled,
              self.goal?.id == expectedGoalID else {
            return false
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
        guard !questionBankTopOffGoalIDs.contains(goal.id),
              !hasBlockedQuestionBankSyncIntent(for: goal) else {
            return
        }

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
              !hasBlockedQuestionBankSyncIntent(for: targetGoal),
              (readyQuestionCount(for: targetGoal) <= ProductLimits.autoRefreshThreshold ||
                skillQuestionCoverageDeficit(for: targetGoal) > 0),
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
                let selector = questionSelector
                let retainedQuestionIDs = Set(
                    questions.lazy
                        .filter { $0.goalID == latestGoal.id && selector.isSelectableQuestion($0) }
                        .map(\.id)
                )
                if isMember {
                    topOffQuestionBankInBackground(
                        for: latestGoal,
                        starterQuestionIDs: retainedQuestionIDs
                    )
                } else if goal?.id == latestGoal.id {
                    let starterPracticeWasConsumed = hasConsumedStarterPractice
                    if !applyStarterGenerationLimitIfNeeded(
                        starterPracticeWasConsumed: starterPracticeWasConsumed
                    ) {
                        if retainedQuestionIDs.isEmpty {
                            prepareInitialQuestionsInBackground(for: latestGoal)
                        } else {
                            topOffQuestionBankInBackground(
                                for: latestGoal,
                                starterQuestionIDs: retainedQuestionIDs
                            )
                        }
                    }
                }
            }
        }

        guard goalProfiles.contains(where: { $0.id == targetGoal.id }) || goal?.id == targetGoal.id else { return }
        guard isMember
                || !starterQuestionIDs.isEmpty
                || questionBankSyncIntents.contains(where: { $0.goalID == targetGoal.id }) else {
            if goal?.id == targetGoal.id {
                questionBatchState = hasReadyCheckpointSet ? .ready : .idle
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
                    let latestGoal = storedGoalProfile(withID: targetGoal.id) ?? targetGoal
                    questionBatchState = checkpointReadiness(for: latestGoal).hasFullCheckpoint
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
              SkillMapReconciler.hasSameGenerationContext(resolvedTargetGoal, targetGoal) else {
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
        let existingKeys = Set(currentGoalQuestions.map { SkillMapReconciler.questionKey($0) })
        let canonicalBatchQuestions = SkillMapReconciler.canonicalizedQuestions(
            batch.questions,
            for: resolvedTargetGoal
        )
        let newQuestions = canonicalBatchQuestions.filter {
            $0.difficulty >= resolvedTargetGoal.minimumQuestionDifficulty
                && !existingKeys.contains(SkillMapReconciler.questionKey($0))
        }
        questions.append(contentsOf: newQuestions)
        let goalQuestions = questions.filter { $0.goalID == targetGoal.id }
        let currentCompetencies = competencies.filter {
            ($0.goalID ?? resolvedTargetGoal.id) == resolvedTargetGoal.id
        }
        replaceCompetencies(
            for: resolvedTargetGoal.id,
            with: SkillMapReconciler.reconciledCompetencies(
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
            questionBatchState = checkpointReadiness(for: resolvedTargetGoal).hasFullCheckpoint
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

    private func refreshQuestionBatch(
        reason: QuestionRefreshReason,
        targetCount: Int? = nil,
        requiredActiveGoalID: Goal.ID? = nil
    ) async {
        let lifecycleID = dataLifecycleID
        guard hasQuestionGenerationMutationAuthority(
                  lifecycleID: lifecycleID,
                  requiredActiveGoalID: requiredActiveGoalID
              ),
              let goal else {
            return
        }
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
                minimumLocalQuestionCount: minimumLocalQuestionCount,
                requiredActiveGoalID: requiredActiveGoalID
            )
            guard hasQuestionGenerationMutationAuthority(
                      lifecycleID: lifecycleID,
                      requiredActiveGoalID: requiredActiveGoalID
                  ),
                  self.goal?.id == goal.id else {
                clearCancelledRequiredQuestionGeneration(
                    for: goal.id,
                    lifecycleID: lifecycleID,
                    requiredActiveGoalID: requiredActiveGoalID
                )
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
        guard hasQuestionGenerationMutationAuthority(
            lifecycleID: lifecycleID,
            requiredActiveGoalID: requiredActiveGoalID
        ) else {
            clearCancelledRequiredQuestionGeneration(
                for: goal.id,
                lifecycleID: lifecycleID,
                requiredActiveGoalID: requiredActiveGoalID
            )
            return
        }
        guard var currentGoal = self.goal, currentGoal.id == goal.id else {
            if questionBatchState != .generating {
                questionGenerationStartedAt = nil
            }
            return
        }
        if reason.countsTowardRefreshUsage {
            questionRefreshesUsed += 1
        }
        currentGoal = commitInferredSkillMapIfNeeded(
            for: currentGoal,
            questions: activeQuestions + batch.questions,
            requiresAllCandidateTopicsToFit: activeCompetencies.contains { $0.attempts > 0 }
        )
        canonicalizeStoredQuestions(for: currentGoal)
        let generatedQuestions = SkillMapReconciler.canonicalizedQuestions(batch.questions, for: currentGoal)
        let existingKeys = Set(activeQuestions.map { SkillMapReconciler.questionKey($0) })
        let newQuestions = generatedQuestions.filter { !existingKeys.contains(SkillMapReconciler.questionKey($0)) }
        questions.append(contentsOf: newQuestions)
        replaceActiveCompetencies(
            with: SkillMapReconciler.reconciledCompetencies(
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
        allowsEarlyCorrectReuse: Bool = false,
        requiredActiveGoalID: Goal.ID? = nil
    ) async -> Bool {
        let lifecycleID = dataLifecycleID
        guard hasQuestionGenerationMutationAuthority(
                  lifecycleID: lifecycleID,
                  requiredActiveGoalID: requiredActiveGoalID
              ),
              let goal,
              questionBatchState != .generating else {
            return false
        }

        if shouldUseDurableQuestionBank,
           questionBankSyncIntents.contains(where: { $0.goalID == goal.id }) {
            let syncOutcome = await synchronizeDurableQuestionBank(
                for: goal,
                minimumLocalQuestionCount: questionBankTargetCount,
                requiredActiveGoalID: requiredActiveGoalID
            )
            guard hasQuestionGenerationMutationAuthority(
                      lifecycleID: lifecycleID,
                      requiredActiveGoalID: requiredActiveGoalID
                  ),
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
                await generateInitialQuestionBatch(
                    for: goal,
                    requiredActiveGoalID: requiredActiveGoalID
                )
                guard hasQuestionGenerationMutationAuthority(
                    lifecycleID: lifecycleID,
                    requiredActiveGoalID: requiredActiveGoalID
                ) else {
                    return false
                }
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
                targetCount: urgentTargetCount,
                requiredActiveGoalID: requiredActiveGoalID
            )
            guard hasQuestionGenerationMutationAuthority(
                      lifecycleID: lifecycleID,
                      requiredActiveGoalID: requiredActiveGoalID
                  ),
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

    private var questionSelector: CheckpointQuestionSelector {
        questionSelector(for: goal)
    }

    private func questionSelector(for targetGoal: Goal?) -> CheckpointQuestionSelector {
        let resolvedProfiles: [Goal]
        if let targetGoal {
            resolvedProfiles = goalProfiles.filter { $0.id != targetGoal.id } + [targetGoal]
        } else {
            resolvedProfiles = goalProfiles
        }

        return CheckpointQuestionSelector(
            questions: questions,
            goalProfiles: resolvedProfiles,
            currentGoal: targetGoal,
            competencies: competencies,
            activeQuestionDifficulty: targetGoal?.minimumQuestionDifficulty
                ?? unlockPolicy.minimumQuestionDifficulty,
            maximumExactQuestionAskCount: Self.maximumExactQuestionAskCount,
            adaptiveDifficultyBySkillID: Dictionary(uniqueKeysWithValues:
                targetGoal.map { adaptiveSkillPlans(for: $0).map { ($0.skillID, $0.targetDifficulty) } } ?? []
            ),
            requiresVerifiedQuestions: targetGoal.map { usesVerifiedLearning(for: $0) } ?? false
        )
    }

    func nextQuestion() -> CheckpointQuestion? {
        questionSelector.nextQuestion()
    }

    func nextCheckpointSession() -> CheckpointSession? {
        nextCheckpointSession(requiresFullSet: false)
    }

    private func nextCheckpointSession(requiresFullSet: Bool) -> CheckpointSession? {
        let questionCount = unlockPolicy.questionsPerSession
        let selectedQuestions = nextQuestions(
            limit: questionCount,
            enforcesDifficultyFloor: requiresFullSet
        )
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
        enforcesDifficultyFloor: Bool = false
    ) -> [CheckpointQuestion] {
        questionSelector.nextQuestions(
            limit: limit,
            allowsEarlyCorrectReuse: allowsEarlyCorrectReuse,
            enforcesDifficultyFloor: enforcesDifficultyFloor
        )
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
        let mappedSkill = questionGoal.derivedSkillMap.flatMap {
            SkillMapReconciler.skillMapTopic(matching: question, in: $0)
        }
        let reviewSnapshot = attemptReviewSnapshot(
            for: question,
            result: result,
            canonicalTopic: mappedSkill?.name ?? question.topic,
            answer: answer
        )
        let attempt = CheckpointAttempt(
            questionID: question.id,
            goalID: question.goalID,
            skillID: mappedSkill?.id ?? question.skillID,
            objectiveID: question.objectiveID,
            questionDifficulty: question.difficulty,
            questionVerificationVersion: question.verificationVersion,
            prompt: question.prompt,
            answer: answer,
            result: result,
            unlockMinutes: unlockMinutes,
            reviewSnapshot: reviewSnapshot
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

        let isEvolutionPending = scheduleSkillMapEvolutionIfNeeded(for: questionGoal)
        if !isEvolutionPending {
            scheduleQuestionBankMaintenanceIfNeeded(for: questionGoal)
        }
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

    func eraseAllData(
        backendIdentityDefaults: UserDefaults = .standard,
        presentsOnboardingAfterErase: Bool = true
    ) {
        permitsPersistenceWrites = false
        requiresPersistenceEraseRecovery = true
        hasNoPersistedAppData = false
        dataLifecycleID = UUID()
        goal = nil
        goalProfiles = []
        questions = []
        attempts = []
        competencies = []
        focusWins = []
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
        pendingMembershipPresentation = nil
        membershipActivationHandoff = nil
        shouldPresentMembershipActivationHandoff = false
        claimedMembershipActivationRequestID = nil
        backgroundGenerationGoalIDs = []
        questionBankTopOffGoalIDs = []
        questionBankPollingGoalIDs = []
        questionBankPollingTokens = [:]
        questionBankSynchronizationGoalIDs = []
        skillMapEvolutionGoalIDs = []
        durableQuestionBankUnavailableForLifecycle = false
        questionBankSyncIntents = []
        skillMapEvolutionIntents = []
        isOnboardingPresented = presentsOnboardingAfterErase
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
            allowsEarlyCorrectReuse: true,
            enforcesDifficultyFloor: true
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

    @discardableResult
    func saveIssueReportDraft(
        category: IssueReportCategory,
        message: String,
        includesCurrentGoal: Bool,
        createdAt: Date = Date()
    ) -> IssueReportDraftSaveResult {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return .emptyMessage }
        guard trimmedMessage.count <= Self.maximumIssueReportMessageLength else {
            return .messageTooLong
        }
        guard activatePersistenceForAppDataIfNeeded() else {
            return .persistenceFailed
        }

        let includedGoal = includesCurrentGoal ? goal : nil
        let previousIssueReports = issueReports

        let report = UserIssueReport(
            goalID: includedGoal?.id,
            goalTitle: includedGoal?.title ?? "",
            includesGoalContext: includedGoal != nil,
            category: category,
            message: trimmedMessage,
            contact: "",
            createdAt: createdAt
        )

        issueReports.append(report)
        issueReports = Array(
            issueReports
                .sorted(by: Self.issueReportComesBefore)
                .prefix(Self.maximumStoredIssueReportCount)
        )
        guard issueReports.contains(where: { $0.id == report.id }) else {
            issueReports = previousIssueReports
            return .notRetained
        }
        guard save() else {
            issueReports = previousIssueReports
            return .persistenceFailed
        }
        return .saved
    }

    @discardableResult
    func deleteIssueReportDraft(id reportID: UserIssueReport.ID) -> Bool {
        guard issueReports.contains(where: { $0.id == reportID }),
              activatePersistenceForAppDataIfNeeded() else {
            return false
        }

        let previousIssueReports = issueReports
        issueReports.removeAll { $0.id == reportID }
        guard save() else {
            issueReports = previousIssueReports
            return false
        }
        return true
    }

    @discardableResult
    func removeQuestionFromFuturePractice(
        questionID: CheckpointQuestion.ID,
        goalID: Goal.ID,
        reason: QuestionReportReason,
        reportedAt: Date = Date()
    ) -> Bool {
        guard let targetGoal = storedGoalProfile(withID: goalID)
                ?? (goal?.id == goalID ? goal : nil),
              let matchingAttempt = attempts.first(where: {
                  $0.questionID == questionID && $0.goalID == goalID
              }) else {
            return false
        }

        let previousQuestions = questions
        let previousQuestionReports = questionReports
        let questionIndex = questions.firstIndex {
            $0.id == questionID && $0.goalID == goalID
        }
        let prompt = questionIndex.map { questions[$0].prompt } ?? matchingAttempt.prompt
        let existingReport = questionReport(for: questionID, goalID: goalID)
        let report = QuestionQualityReport(
            id: existingReport?.id ?? UUID(),
            questionID: questionID,
            goalID: goalID,
            prompt: prompt,
            reason: reason,
            note: existingReport?.note ?? "",
            createdAt: existingReport?.createdAt ?? reportedAt
        )

        questionReports.removeAll {
            $0.questionID == questionID && $0.goalID == goalID
        }
        questionReports.insert(report, at: 0)
        if let questionIndex {
            questions[questionIndex].status = .retired
            questions[questionIndex].nextReviewAt = nil
        }

        guard save() else {
            questions = previousQuestions
            questionReports = previousQuestionReports
            return false
        }

        if questionIndex != nil {
            scheduleQuestionBankMaintenanceIfNeeded(for: targetGoal)
        }
        return questionReport(for: questionID, goalID: goalID) != nil
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
        checkpointRetryCooldownUntil = now.addingTimeInterval(CheckpointRetryPolicy.cooldownDuration)
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
        } else {
            markQuestionsMissedDueNow(
                missedQuestionIDs.union(activeRun.missedQuestionIDs ?? [])
            )
            applyCheckpointRetryCooldown()
        }
        save()
        publishShieldContext()
        resumeSkillMapEvolutionAfterCheckpointRun(goalID: activeRun.goalID)
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
        guard let activeRun = activeCheckpointRun,
              activeRun.sessionID == sessionID else { return }
        activeCheckpointRun = nil
        save()
        resumeSkillMapEvolutionAfterCheckpointRun(goalID: activeRun.goalID)
    }

    private func resumeSkillMapEvolutionAfterCheckpointRun(goalID: Goal.ID) {
        guard let targetGoal = storedGoalProfile(withID: goalID) else { return }
        if !scheduleSkillMapEvolutionIfNeeded(for: targetGoal) {
            scheduleQuestionBankMaintenanceIfNeeded(for: targetGoal)
        }
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
            if normalizedDifficulty != previousDifficulty {
                removeSkillMapEvolutionIntent(for: activeGoal.id)
            }
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

        let wasRetired = questions[index].status == .retired
        questions[index].timesAsked += 1
        questions[index].lastAskedAt = Date()
        guard !wasRetired else {
            questions[index].nextReviewAt = nil
            return
        }

        switch result {
        case .correct:
            questions[index].timesCorrect += 1
            questions[index].status = questions[index].timesCorrect >= 3 ? .retired : .correct
            if questions[index].status == .retired {
                questions[index].nextReviewAt = nil
            } else {
                let delayDays = CheckpointQuestionSelector.correctAnswerReviewDelayDays(for: questions[index].timesCorrect)
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
           let skill = SkillMapReconciler.skillMapTopic(matching: question, in: skillMap) {
            updateCompetency(
                topic: skill.name,
                goalID: question.goalID,
                skillID: skill.id,
                questionDifficulty: question.difficulty,
                result: result
            )
            return
        }

        for topic in SkillMapReconciler.competencyTopics(from: question.topic) {
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
            } ?? SkillMapReconciler.skillMapTopic(matching: topic, in: skillMap)
        }
        if targetGoal?.derivedSkillMap != nil, mappedSkill == nil {
            return
        }

        let canonicalTopic = mappedSkill?.name ?? topic
        let topicKey = SkillMapReconciler.competencyTopicKey(canonicalTopic)
        let matchesQuestionGoal: (TopicCompetency) -> Bool = { competency in
            let matchesSkill = mappedSkill.map { competency.skillID == $0.id } ?? false
            let matchesTopic = SkillMapReconciler.competencyTopicKey(competency.topic) == topicKey
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

    // MARK: - Adaptive skill-map evolution

    @discardableResult
    func evaluateSkillMapEvolutionIfNeeded() -> Bool {
        guard let goal else { return false }
        return scheduleSkillMapEvolutionIfNeeded(for: goal)
    }

    @discardableResult
    private func scheduleSkillMapEvolutionIfNeeded(for requestedGoal: Goal) -> Bool {
        guard isMember,
              permitsPersistenceWrites,
              let targetGoal = storedGoalProfile(withID: requestedGoal.id),
              let skillMap = targetGoal.derivedSkillMap,
              skillMap.status == .reviewed,
              skillMap.evolutionEnabled else {
            return false
        }

        if let existingIntent = skillMapEvolutionIntents.first(where: { $0.goalID == targetGoal.id }) {
            if !isSkillMapEvolutionIntentCurrent(existingIntent, for: targetGoal) {
                removeSkillMapEvolutionIntent(id: existingIntent.id)
                save()
            } else {
                if skillMapEvolutionGoalIDs.contains(targetGoal.id) {
                    return true
                }

                let eligibleSkills = evolutionEligibleSkills(for: targetGoal)
                guard !eligibleSkills.isEmpty else {
                    // Keep same-map failure state dormant so a temporary miss cannot
                    // reset the invalid-response retry cap when mastery returns.
                    return false
                }
                let eligibleSkillIDs = Set(eligibleSkills.map(\.id))
                var intentToProcess = existingIntent
                let existingTargetIDs = Set(existingIntent.masteredSkillIDs)
                let hasValidExistingTarget = (1...Self.evolutionMaximumSkillsPerCycle)
                    .contains(existingIntent.masteredSkillIDs.count) &&
                    existingTargetIDs.count == existingIntent.masteredSkillIDs.count &&
                    existingTargetIDs.isSubset(of: eligibleSkillIDs)
                if !hasValidExistingTarget {
                    let replacementTargetIDs = Array(
                        eligibleSkills.prefix(Self.evolutionMaximumSkillsPerCycle).map(\.id)
                    )
                    intentToProcess.masteredSkillIDs = replacementTargetIDs
                    if Set(replacementTargetIDs) != existingTargetIDs {
                        // Invalid-response failures belong to the exact requested
                        // predecessor set. A newly eligible target gets a fresh budget.
                        intentToProcess.lastAttemptAt = nil
                        intentToProcess.lastFailure = nil
                        intentToProcess.invalidResponseAttemptCount = 0
                    }
                    if let index = skillMapEvolutionIntents.firstIndex(where: {
                        $0.id == intentToProcess.id
                    }) {
                        skillMapEvolutionIntents[index] = intentToProcess
                    }
                    save()
                }

                guard canAttemptSkillMapEvolution(intentToProcess) else {
                    return false
                }
                if activeCheckpointRun?.goalID == targetGoal.id {
                    return true
                }
                if !skillMapEvolutionGoalIDs.contains(targetGoal.id) {
                    Task { [weak self] in
                        await self?.processSkillMapEvolutionIntent(intentToProcess.id)
                    }
                }
                return true
            }
        }
        guard !skillMapEvolutionGoalIDs.contains(targetGoal.id) else {
            return true
        }

        let eligibleSkills = evolutionEligibleSkills(for: targetGoal)
        guard !eligibleSkills.isEmpty else { return false }

        let intent = SkillMapEvolutionIntent(
            goalID: targetGoal.id,
            baseVersion: skillMap.version,
            baseMapFingerprint: SkillMapReconciler.skillMapFingerprint(topics: skillMap.topics),
            masteredSkillIDs: Array(
                eligibleSkills.prefix(Self.evolutionMaximumSkillsPerCycle).map(\.id)
            )
        )
        skillMapEvolutionIntents.removeAll { $0.goalID == targetGoal.id }
        skillMapEvolutionIntents.append(intent)
        save()

        if activeCheckpointRun?.goalID != targetGoal.id {
            Task { [weak self] in
                await self?.processSkillMapEvolutionIntent(intent.id)
            }
        }
        return true
    }

    private func evolutionEligibleSkills(for targetGoal: Goal) -> [SkillMapTopic] {
        guard let skillMap = targetGoal.derivedSkillMap else { return [] }
        let competencyBySkillID = Dictionary(uniqueKeysWithValues:
            mergedEvolutionCompetencies(for: Set(skillMap.topics.map(\.id)), goalID: targetGoal.id)
                .compactMap { competency in competency.skillID.map { ($0, competency) } }
        )

        return skillMap.topics.compactMap { skill -> (SkillMapTopic, TopicCompetency)? in
            guard let competency = competencyBySkillID[skill.id],
                  competency.attempts >= Self.evolutionMinimumAttempts,
                  competency.masteryPercent >= Self.evolutionMinimumMasteryPercent,
                  competency.currentStreak >= Self.evolutionMinimumCorrectStreak,
                  hasStrongRecentEvolutionEvidence(for: skill, goalID: targetGoal.id) else {
                return nil
            }
            return (skill, competency)
        }
        .sorted { lhs, rhs in
            if lhs.1.masteryPercent != rhs.1.masteryPercent {
                return lhs.1.masteryPercent > rhs.1.masteryPercent
            }
            if lhs.1.estimatedLevel != rhs.1.estimatedLevel {
                return lhs.1.estimatedLevel > rhs.1.estimatedLevel
            }
            if lhs.1.attempts != rhs.1.attempts {
                return lhs.1.attempts > rhs.1.attempts
            }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }
        .map(\.0)
    }

    private func hasStrongRecentEvolutionEvidence(
        for skill: SkillMapTopic,
        goalID: Goal.ID
    ) -> Bool {
        let evidenceAttempts = recentEvolutionAttempts(for: skill, goalID: goalID)
        let recentAttempts = evidenceAttempts.prefix(Self.evolutionRecentAttemptCount)
        guard recentAttempts.count >= Self.evolutionMinimumRecentEvidenceCount,
              recentAttempts.contains(where: { ($0.questionDifficulty ?? 0) >= 4 }) else {
            return false
        }

        let nonCorrectCount = recentAttempts.filter { $0.result != .correct }.count
        guard nonCorrectCount <= 1 else { return false }
        let score = recentAttempts.reduce(0.0) { partialResult, attempt in
            switch attempt.result {
            case .correct:
                return partialResult + 1
            case .partial:
                return partialResult + 0.5
            case .incorrect, .unclear:
                return partialResult
            }
        } / Double(recentAttempts.count)
        guard score >= Self.evolutionMinimumRecentScore,
              !skill.objectives.isEmpty else {
            return false
        }

        return skill.objectives.allSatisfy { objective in
            let objectiveAttempts = evidenceAttempts.filter { $0.objectiveID == objective.id }
            guard !objectiveAttempts.isEmpty else { return false }
            let objectiveScore = objectiveAttempts.reduce(0.0) { partialResult, attempt in
                switch attempt.result {
                case .correct:
                    return partialResult + 1
                case .partial:
                    return partialResult + 0.5
                case .incorrect, .unclear:
                    return partialResult
                }
            } / Double(objectiveAttempts.count)
            return objectiveScore >= Self.evolutionMinimumObjectiveScore
        }
    }

    private func recentEvolutionAttempts(
        for skill: SkillMapTopic,
        goalID: Goal.ID
    ) -> [CheckpointAttempt] {
        let excludedQuestions = Set(questionReports.filter { $0.goalID == goalID }.map(\.questionID))
        return Array(AdaptiveLearningPolicy.distinctAttempts(for: skill, goalID: goalID, attempts: attempts.filter { !excludedQuestions.contains($0.questionID) })
            .suffix(Self.evolutionRecentAttemptLimitPerSkill).reversed())
    }

    private func canAttemptSkillMapEvolution(
        _ intent: SkillMapEvolutionIntent,
        now: Date = Date()
    ) -> Bool {
        guard intent.lastFailure != .safetyIntervention,
              intent.invalidResponseAttemptCount < Self.evolutionMaximumInvalidResponseAttempts else {
            return false
        }
        guard let lastAttemptAt = intent.lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= Self.evolutionRetryBackoff
    }

    private func isSkillMapEvolutionIntentCurrent(
        _ intent: SkillMapEvolutionIntent,
        for targetGoal: Goal
    ) -> Bool {
        guard let skillMap = targetGoal.derivedSkillMap,
              skillMap.status == .reviewed,
              skillMap.evolutionEnabled,
              skillMap.version == intent.baseVersion,
              SkillMapReconciler.skillMapFingerprint(topics: skillMap.topics) == intent.baseMapFingerprint else {
            return false
        }
        return true
    }

    private func isSkillMapEvolutionIntentCurrentAndEligible(
        _ intent: SkillMapEvolutionIntent,
        for targetGoal: Goal
    ) -> Bool {
        guard isSkillMapEvolutionIntentCurrent(intent, for: targetGoal) else {
            return false
        }
        guard (1...Self.evolutionMaximumSkillsPerCycle).contains(intent.masteredSkillIDs.count),
              Set(intent.masteredSkillIDs).count == intent.masteredSkillIDs.count else {
            return false
        }
        let eligibleSkillIDs = Set(evolutionEligibleSkills(for: targetGoal).map(\.id))
        return Set(intent.masteredSkillIDs).isSubset(of: eligibleSkillIDs)
    }

    private func processSkillMapEvolutionIntent(_ intentID: SkillMapEvolutionIntent.ID) async {
        guard let intent = skillMapEvolutionIntents.first(where: { $0.id == intentID }),
              !skillMapEvolutionGoalIDs.contains(intent.goalID),
              isMember,
              canAttemptSkillMapEvolution(intent),
              activeCheckpointRun?.goalID != intent.goalID else {
            return
        }
        skillMapEvolutionGoalIDs.insert(intent.goalID)
        defer { skillMapEvolutionGoalIDs.remove(intent.goalID) }

        let lifecycleID = dataLifecycleID
        guard let targetGoal = storedGoalProfile(withID: intent.goalID) else {
            removeSkillMapEvolutionIntent(id: intentID)
            save()
            return
        }
        guard isSkillMapEvolutionIntentCurrent(intent, for: targetGoal) else {
            removeSkillMapEvolutionIntent(id: intentID)
            save()
            continueAfterSkillMapEvolutionRequestFailure(
                goalID: intent.goalID,
                lifecycleID: lifecycleID
            )
            return
        }
        guard isSkillMapEvolutionIntentCurrentAndEligible(intent, for: targetGoal) else {
            continueAfterSkillMapEvolutionRequestFailure(
                goalID: intent.goalID,
                lifecycleID: lifecycleID
            )
            return
        }

        if let index = skillMapEvolutionIntents.firstIndex(where: { $0.id == intentID }) {
            skillMapEvolutionIntents[index].lastAttemptAt = Date()
            skillMapEvolutionIntents[index].lastFailure = nil
            save()
        }
        let masteredSkillIDs = Set(intent.masteredSkillIDs)
        let masteredSkillsByID = Dictionary(
            uniqueKeysWithValues: (targetGoal.derivedSkillMap?.topics ?? [])
                .filter { masteredSkillIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )
        let request = SkillMapEvolutionRequest(
            goal: targetGoal,
            baseMapFingerprint: intent.baseMapFingerprint,
            masteredSkillIDs: intent.masteredSkillIDs,
            competencies: mergedEvolutionCompetencies(
                for: masteredSkillIDs,
                goalID: targetGoal.id
            ),
            recentAttempts: intent.masteredSkillIDs
                .compactMap { masteredSkillsByID[$0] }
                .flatMap { recentEvolutionAttempts(for: $0, goalID: targetGoal.id) }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                },
            backendEndpoint: resolvedBackendEndpoint,
            backendAuthorizationToken: resolvedBackendAuthorizationToken
        )

        let proposal: SkillMapEvolutionProposal
        do {
            proposal = try await questionEngine.evolveSkillMap(for: request)
        } catch let error as QuestionGenerationError where error == .badResponse {
            recordInvalidSkillMapEvolutionResponse(
                intentID: intentID,
                for: targetGoal,
                schedulesBankMaintenance: false
            )
            continueAfterSkillMapEvolutionRequestFailure(
                goalID: intent.goalID,
                lifecycleID: lifecycleID
            )
            return
        } catch let error as QuestionGenerationError where error == .providerFailure {
            // Bedrock/provider failures can be transient outages. Preserve the
            // ordinary persisted backoff without consuming the malformed-response cap.
            continueAfterSkillMapEvolutionRequestFailure(
                goalID: intent.goalID,
                lifecycleID: lifecycleID
            )
            return
        } catch let error as QuestionGenerationError where error == .safetyIntervention {
            if let index = skillMapEvolutionIntents.firstIndex(where: { $0.id == intentID }) {
                skillMapEvolutionIntents[index].lastFailure = .safetyIntervention
            }
            save()
            continueAfterSkillMapEvolutionRequestFailure(
                goalID: intent.goalID,
                lifecycleID: lifecycleID
            )
            return
        } catch {
            continueAfterSkillMapEvolutionRequestFailure(
                goalID: intent.goalID,
                lifecycleID: lifecycleID
            )
            return
        }

        guard lifecycleID == dataLifecycleID,
              permitsPersistenceWrites,
              isMember,
              skillMapEvolutionIntents.contains(where: { $0.id == intentID }),
              let currentGoal = storedGoalProfile(withID: intent.goalID) else {
            return
        }
        if activeCheckpointRun?.goalID == intent.goalID {
            if let index = skillMapEvolutionIntents.firstIndex(where: { $0.id == intentID }) {
                // The proposal cannot be applied while the current run still references
                // predecessor questions. Make it immediately retryable when that run resolves.
                skillMapEvolutionIntents[index].lastAttemptAt = nil
                skillMapEvolutionIntents[index].lastFailure = nil
                save()
            }
            return
        }
        guard isSkillMapEvolutionIntentCurrent(intent, for: currentGoal) else {
            removeSkillMapEvolutionIntent(id: intentID)
            save()
            continueAfterSkillMapEvolutionRequestFailure(
                goalID: intent.goalID,
                lifecycleID: lifecycleID
            )
            return
        }
        guard isSkillMapEvolutionIntentCurrentAndEligible(intent, for: currentGoal) else {
            continueAfterSkillMapEvolutionRequestFailure(
                goalID: intent.goalID,
                lifecycleID: lifecycleID
            )
            return
        }
        _ = applySkillMapEvolution(
            proposal,
            intent: intent,
            to: currentGoal
        )
    }

    private func mergedEvolutionCompetencies(
        for skillIDs: Set<SkillMapTopic.ID>,
        goalID: Goal.ID
    ) -> [TopicCompetency] {
        var mergedBySkillID: [SkillMapTopic.ID: TopicCompetency] = [:]
        for competency in competencies {
            guard (competency.goalID ?? goalID) == goalID,
                  let skillID = competency.skillID,
                  skillIDs.contains(skillID) else {
                continue
            }
            if let existing = mergedBySkillID[skillID] {
                mergedBySkillID[skillID] = SkillMapReconciler.mergedCompetency(
                    existing,
                    with: competency
                )
            } else {
                mergedBySkillID[skillID] = competency
            }
        }
        guard let targetGoal = storedGoalProfile(withID: goalID) else { return [] }
        return skillIDs.compactMap { skillID in
            guard var competency = mergedBySkillID[skillID],
                  let skill = targetGoal.derivedSkillMap?.topics.first(where: { $0.id == skillID }) else { return nil }
            let recent = recentEvolutionAttempts(for: skill, goalID: goalID)
            guard recent.count >= Self.evolutionMinimumAttempts else { return nil }
            // Curriculum advancement reflects recent transfer evidence. Lifetime
            // mistakes remain in history without permanently holding a skill back.
            competency.attempts = recent.count
            competency.correct = recent.filter { $0.result == .correct }.count
            competency.partial = recent.filter { $0.result == .partial }.count
            competency.incorrect = recent.count - competency.correct - competency.partial
            competency.currentStreak = min(competency.currentStreak, recent.prefix { $0.result == .correct }.count)
            let averageDifficulty = Double(recent.reduce(0) { $0 + ($1.questionDifficulty ?? 1) }) / Double(recent.count)
            competency.estimatedLevel = min(5, averageDifficulty + 0.5)
            return competency
        }
    }

    @discardableResult
    private func applySkillMapEvolution(
        _ proposal: SkillMapEvolutionProposal,
        intent: SkillMapEvolutionIntent,
        to currentGoal: Goal
    ) -> Bool {
        guard var currentMap = currentGoal.derivedSkillMap,
              isSkillMapEvolutionIntentCurrentAndEligible(intent, for: currentGoal),
              currentMap.version == intent.baseVersion,
              SkillMapReconciler.skillMapFingerprint(topics: currentMap.topics) == intent.baseMapFingerprint else {
            removeSkillMapEvolutionIntent(id: intent.id)
            save()
            scheduleQuestionBankMaintenanceIfNeeded(for: currentGoal)
            return false
        }
        guard proposal.baseVersion == intent.baseVersion,
              proposal.baseMapFingerprint == intent.baseMapFingerprint,
              proposal.topics.count == currentMap.topics.count,
              (3...6).contains(proposal.topics.count),
              (1...Self.evolutionMaximumSkillsPerCycle).contains(proposal.replacements.count) else {
            recordInvalidSkillMapEvolutionResponse(intentID: intent.id, for: currentGoal)
            return false
        }

        let predecessorIDs = Set(proposal.replacements.map(\.predecessorSkillID))
        let successorIDs = Set(proposal.replacements.map(\.successorSkillID))
        let intendedPredecessorIDs = Set(intent.masteredSkillIDs)
        let currentByID = Dictionary(uniqueKeysWithValues: currentMap.topics.map { ($0.id, $0) })
        let returnedByID = Dictionary(uniqueKeysWithValues: proposal.topics.map { ($0.id, $0) })
        let historicalIDs = Set(currentMap.archivedTopics.map(\.id))
        guard predecessorIDs == intendedPredecessorIDs,
              predecessorIDs.count == proposal.replacements.count,
              successorIDs.count == proposal.replacements.count,
              predecessorIDs.allSatisfy({ currentByID[$0] != nil }),
              successorIDs.isDisjoint(with: Set(currentByID.keys)),
              successorIDs.isDisjoint(with: historicalIDs),
              Set(returnedByID.keys).count == proposal.topics.count else {
            recordInvalidSkillMapEvolutionResponse(intentID: intent.id, for: currentGoal)
            return false
        }

        let retainedIDs = Set(currentByID.keys).subtracting(predecessorIDs)
        let expectedReturnedIDs = retainedIDs.union(successorIDs)
        guard Set(returnedByID.keys) == expectedReturnedIDs else {
            recordInvalidSkillMapEvolutionResponse(intentID: intent.id, for: currentGoal)
            return false
        }
        for retainedID in retainedIDs {
            guard let retained = currentByID[retainedID],
                  let returned = returnedByID[retainedID],
                  retained.name == returned.name,
                  retained.objectives == returned.objectives else {
                recordInvalidSkillMapEvolutionResponse(intentID: intent.id, for: currentGoal)
                return false
            }
        }

        let replacementBySuccessorID = Dictionary(
            uniqueKeysWithValues: proposal.replacements.map { ($0.successorSkillID, $0) }
        )
        var evolvedTopics: [SkillMapTopic] = []
        for returnedTopic in proposal.topics {
            if let retained = currentByID[returnedTopic.id] {
                evolvedTopics.append(retained)
                continue
            }
            guard let replacement = replacementBySuccessorID[returnedTopic.id],
                  let predecessor = currentByID[replacement.predecessorSkillID] else {
                recordInvalidSkillMapEvolutionResponse(intentID: intent.id, for: currentGoal)
                return false
            }
            var successor = returnedTopic
            successor.aliases = []
            successor.stage = predecessor.stage + 1
            successor.predecessorIDs = [predecessor.id]
            evolvedTopics.append(successor)
        }
        let successorsHaveValidObjectives = evolvedTopics
            .filter { successorIDs.contains($0.id) }
            .allSatisfy { (2...5).contains($0.objectives.count) }
        guard SkillMapTopic.validatedNames(evolvedTopics.map(\.name)) != nil,
              successorsHaveValidObjectives else {
            recordInvalidSkillMapEvolutionResponse(intentID: intent.id, for: currentGoal)
            return false
        }
        let retiredNameKeys = Set(
            currentMap.archivedTopics.map {
                SkillMapReconciler.skillMapEvolutionNameKey($0.topic.name)
            } + predecessorIDs.compactMap {
                currentByID[$0].map { SkillMapReconciler.skillMapEvolutionNameKey($0.name) }
            }
        )
        let successorNamesAreNew = evolvedTopics
            .filter { successorIDs.contains($0.id) }
            .allSatisfy {
                !retiredNameKeys.contains(SkillMapReconciler.skillMapEvolutionNameKey($0.name))
            }
        guard successorNamesAreNew else {
            recordInvalidSkillMapEvolutionResponse(intentID: intent.id, for: currentGoal)
            return false
        }

        let evolutionDate = Date()
        var archivedTopics = currentMap.archivedTopics
        for replacement in proposal.replacements {
            guard let predecessor = currentByID[replacement.predecessorSkillID] else { continue }
            archivedTopics.append(
                archivedSkillEntry(
                    for: predecessor,
                    goalID: currentGoal.id,
                    reason: .mastered,
                    successorSkillIDs: [replacement.successorSkillID],
                    archivedAt: evolutionDate
                )
            )
        }

        var updatedGoal = currentGoal
        currentMap.topics = evolvedTopics
        currentMap.archivedTopics = archivedTopics
        currentMap.version = intent.baseVersion + 1
        currentMap.provenance = .adaptiveEvolution
        currentMap.status = .reviewed
        currentMap.lastEvolvedAt = evolutionDate
        currentMap.updatedAt = evolutionDate
        updatedGoal.derivedSkillMap = currentMap
        storeGoalProfile(updatedGoal)

        for index in questions.indices where questions[index].goalID == updatedGoal.id {
            guard let priorSkill = SkillMapReconciler.skillMapTopic(
                matching: questions[index],
                in: currentGoal.derivedSkillMap ?? currentMap
            ), predecessorIDs.contains(priorSkill.id) else {
                continue
            }
            questions[index].status = .retired
            questions[index].nextReviewAt = nil
        }

        replaceCompetencies(
            for: updatedGoal.id,
            with: SkillMapReconciler.reconciledCompetencies(
                existing: competencies.filter { ($0.goalID ?? updatedGoal.id) == updatedGoal.id },
                goal: updatedGoal,
                questions: questions.filter { $0.goalID == updatedGoal.id }
            )
        )
        removeSkillMapEvolutionIntent(id: intent.id)
        invalidateQuestionBankSynchronization(for: updatedGoal.id)
        let transitionSummary = proposal.replacements.compactMap { replacement -> String? in
            guard let predecessor = currentByID[replacement.predecessorSkillID],
                  let successor = evolvedTopics.first(where: { $0.id == replacement.successorSkillID }) else {
                return nil
            }
            return "\(predecessor.name) → \(successor.name)"
        }
        checkpointNotice = transitionSummary.isEmpty
            ? "Your skill map advanced. New questions are being prepared."
            : "Skill map advanced: \(transitionSummary.joined(separator: "; ")). New questions are being prepared."
        save()
        publishShieldContext()
        if evolutionEligibleSkills(for: updatedGoal).isEmpty {
            topOffQuestionBankInBackground(for: updatedGoal)
        } else {
            Task { [weak self] in
                await Task.yield()
                guard let self,
                      let latestGoal = self.storedGoalProfile(withID: updatedGoal.id) else {
                    return
                }
                if !self.scheduleSkillMapEvolutionIfNeeded(for: latestGoal) {
                    self.topOffQuestionBankInBackground(for: latestGoal)
                }
            }
        }
        return true
    }

    private func recordInvalidSkillMapEvolutionResponse(
        intentID: SkillMapEvolutionIntent.ID,
        for targetGoal: Goal,
        schedulesBankMaintenance: Bool = true
    ) {
        if let index = skillMapEvolutionIntents.firstIndex(where: { $0.id == intentID }) {
            if skillMapEvolutionIntents[index].lastAttemptAt == nil {
                skillMapEvolutionIntents[index].lastAttemptAt = Date()
            }
            skillMapEvolutionIntents[index].lastFailure = .invalidResponse
            skillMapEvolutionIntents[index].invalidResponseAttemptCount += 1
        }
        save()
        if schedulesBankMaintenance {
            scheduleQuestionBankMaintenanceIfNeeded(for: targetGoal)
        }
    }

    private func continueAfterSkillMapEvolutionRequestFailure(
        goalID: Goal.ID,
        lifecycleID: UUID
    ) {
        guard lifecycleID == dataLifecycleID,
              permitsPersistenceWrites,
              let currentGoal = storedGoalProfile(withID: goalID) else {
            return
        }
        // The request has completed, so a current replacement intent may now be
        // scheduled without violating the per-goal single-flight fence.
        skillMapEvolutionGoalIDs.remove(goalID)
        if !scheduleSkillMapEvolutionIfNeeded(for: currentGoal) {
            scheduleQuestionBankMaintenanceIfNeeded(for: currentGoal)
        }
    }

    private func archivedSkillEntry(
        for topic: SkillMapTopic,
        goalID: Goal.ID,
        reason: ArchivedSkillReason,
        successorSkillIDs: [SkillMapTopic.ID],
        archivedAt: Date = Date()
    ) -> ArchivedSkillMapTopic {
        let matchingCompetencies = competencies.filter {
            ($0.goalID ?? goalID) == goalID && $0.skillID == topic.id
        }
        let competency = matchingCompetencies.first.map { firstCompetency in
            matchingCompetencies.dropFirst().reduce(firstCompetency) { partialResult, duplicate in
                SkillMapReconciler.mergedCompetency(partialResult, with: duplicate)
            }
        }
        let snapshot = competency.map {
            ArchivedSkillMasterySnapshot(
                estimatedLevel: $0.estimatedLevel,
                masteryPercent: $0.masteryPercent,
                attempts: $0.attempts,
                correct: $0.correct,
                partial: $0.partial,
                incorrect: $0.incorrect,
                currentStreak: $0.currentStreak
            )
        }
        return ArchivedSkillMapTopic(
            topic: topic,
            reason: reason,
            archivedAt: archivedAt,
            successorSkillIDs: successorSkillIDs,
            mastery: snapshot
        )
    }

    private func resumeSkillMapEvolutionIfNeeded() {
        guard isMember else { return }
        let availableGoalIDs = Set(availableGoalProfiles.map(\.id))
        let previousIntentCount = skillMapEvolutionIntents.count
        skillMapEvolutionIntents.removeAll { !availableGoalIDs.contains($0.goalID) }
        if skillMapEvolutionIntents.count != previousIntentCount {
            save()
        }
        let activeGoalID = goal?.id
        for intent in skillMapEvolutionIntents where intent.goalID != activeGoalID {
            guard let targetGoal = storedGoalProfile(withID: intent.goalID) else {
                continue
            }
            guard isSkillMapEvolutionIntentCurrent(intent, for: targetGoal) else {
                removeSkillMapEvolutionIntent(id: intent.id)
                save()
                continue
            }
            guard canAttemptSkillMapEvolution(intent),
                  isSkillMapEvolutionIntentCurrentAndEligible(intent, for: targetGoal) else {
                continue
            }
            Task { [weak self] in
                await self?.processSkillMapEvolutionIntent(intent.id)
            }
        }
        if let goal {
            _ = scheduleSkillMapEvolutionIfNeeded(for: goal)
        }
    }

    private func hasReadySkillMapEvolutionIntent(for targetGoal: Goal) -> Bool {
        guard isMember,
              let intent = skillMapEvolutionIntents.first(where: { $0.goalID == targetGoal.id }),
              canAttemptSkillMapEvolution(intent) else {
            return false
        }
        return isSkillMapEvolutionIntentCurrentAndEligible(intent, for: targetGoal)
    }

    private func removeSkillMapEvolutionIntent(for goalID: Goal.ID) {
        skillMapEvolutionIntents.removeAll { $0.goalID == goalID }
    }

    private func removeSkillMapEvolutionIntent(id: SkillMapEvolutionIntent.ID) {
        skillMapEvolutionIntents.removeAll { $0.id == id }
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
        focusWins.removeAll { $0.goalID == goalID }
        questionReports.removeAll { $0.goalID == goalID }
        unlockEvents.removeAll { $0.goalID == goalID }
        questionBankSyncIntents.removeAll { $0.goalID == goalID }
        skillMapEvolutionIntents.removeAll { $0.goalID == goalID }
        skillMapEvolutionGoalIDs.remove(goalID)
        questionBankPollingGoalIDs.remove(goalID)
        questionBankPollingTokens.removeValue(forKey: goalID)
        questionBankSynchronizationGoalIDs.remove(goalID)
    }

    private func hasQuestionGenerationMutationAuthority(
        lifecycleID: UUID,
        requiredActiveGoalID: Goal.ID?
    ) -> Bool {
        guard lifecycleID == dataLifecycleID,
              permitsPersistenceWrites else {
            return false
        }
        guard let requiredActiveGoalID else { return true }
        return !Task.isCancelled && goal?.id == requiredActiveGoalID
    }

    private func clearCancelledRequiredQuestionGeneration(
        for goalID: Goal.ID,
        lifecycleID: UUID,
        requiredActiveGoalID: Goal.ID?
    ) {
        guard Task.isCancelled,
              lifecycleID == dataLifecycleID,
              permitsPersistenceWrites,
              let requiredActiveGoalID,
              goalID == requiredActiveGoalID,
              goal?.id == requiredActiveGoalID else {
            return
        }

        questionBatchState = hasReadyCheckpointSet ? .ready : .idle
        questionGenerationStartedAt = nil
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

    @discardableResult
    private func migrateLegacyIssueReports() -> Bool {
        var changed = false

        for index in issueReports.indices where issueReports[index].includesGoalContext == nil {
            issueReports[index].goalID = nil
            issueReports[index].goalTitle = ""
            issueReports[index].contact = ""
            issueReports[index].includesGoalContext = false
            changed = true
        }

        return changed
    }

    // MARK: - Persistence and app group state

    @discardableResult
    private func save(
        reportsFailure: Bool = true,
        mirroringRecovery: Bool = false
    ) -> Bool {
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
            focusWins: focusWins,
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
            membershipActivationHandoff: membershipActivationHandoff,
            questionRefreshesUsed: questionRefreshesUsed,
            lastAutomaticQuestionRefreshAt: lastAutomaticQuestionRefreshAt,
            questionBankSyncIntents: questionBankSyncIntents,
            skillMapEvolutionIntents: skillMapEvolutionIntents
        )

        do {
            if mirroringRecovery {
                try snapshotPersistence.saveMirrored(snapshot)
            } else {
                try snapshotPersistence.save(snapshot)
            }
            SharedAppGroup.publishCheckpointReadiness(hasReadyCheckpointSet)
            return true
        } catch {
            if reportsFailure {
                let message = "Checkpoint could not save the latest local changes. Keep the app open and try again after freeing device storage."
                persistenceRecoveryMessage = message
                if checkpointNotice == nil {
                    checkpointNotice = message
                }
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
        let retainedFocusWins = retainingFirstPerGoal(
            focusWins.sorted(by: Self.focusWinComesBefore),
            limit: Self.maximumStoredFocusWinCountPerGoal,
            goalID: \FocusWin.goalID
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
        let retainedIssueReports = Array(
            issueReports
                .sorted(by: Self.issueReportComesBefore)
                .prefix(Self.maximumStoredIssueReportCount)
        )
        let retainedQuestionGenerationTraces = Array(
            questionGenerationTraces.prefix(Self.maximumQuestionGenerationTraceCount)
        )
        let changed = retainedQuestions != questions ||
            retainedAttempts != attempts ||
            retainedFocusWins != focusWins ||
            retainedUnlockEvents != unlockEvents ||
            retainedQuestionReports != questionReports ||
            retainedIssueReports != issueReports ||
            retainedQuestionGenerationTraces != questionGenerationTraces

        questions = retainedQuestions
        attempts = retainedAttempts
        focusWins = retainedFocusWins
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

    nonisolated private static func focusWinComesBefore(_ lhs: FocusWin, _ rhs: FocusWin) -> Bool {
        if lhs.loggedAt != rhs.loggedAt {
            return lhs.loggedAt > rhs.loggedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated private static func issueReportComesBefore(
        _ lhs: UserIssueReport,
        _ rhs: UserIssueReport
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
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
               !questionBankSyncIntents.contains(where: { $0.goalID == goal.id }),
               !hasReadySkillMapEvolutionIntent(for: goal) {
                prepareInitialQuestionsInBackground(for: goal)
            }
        } else if questionBatchState == .failed, hasReadyCheckpointSet {
            questionBatchState = .ready
            save()
        }
    }

    private func resumeQuestionBankMaintenanceIfNeeded() {
        let allIntentGoalIDs = Set(questionBankSyncIntents.map(\.goalID))
        let pendingGoalIDs = Set(
            availableGoalProfiles.compactMap { profile in
                hasPendingQuestionBankSync(for: profile) ? profile.id : nil
            }
        )
        let evolvingGoalIDs = Set(
            availableGoalProfiles.compactMap { profile in
                hasReadySkillMapEvolutionIntent(for: profile) ? profile.id : nil
            }
        )
        for pendingGoal in availableGoalProfiles
        where pendingGoalIDs.contains(pendingGoal.id) && !evolvingGoalIDs.contains(pendingGoal.id) {
            guard !backgroundGenerationGoalIDs.contains(pendingGoal.id),
                  !questionBankTopOffGoalIDs.contains(pendingGoal.id) else {
                continue
            }
            topOffQuestionBankInBackground(for: pendingGoal)
        }

        guard let goal,
              isMember,
              !allIntentGoalIDs.contains(goal.id),
              !evolvingGoalIDs.contains(goal.id),
              questionBatchState != .generating,
              !backgroundGenerationGoalIDs.contains(goal.id),
              !questionBankTopOffGoalIDs.contains(goal.id),
              (readyQuestionCount(for: goal) <= ProductLimits.autoRefreshThreshold ||
                skillQuestionCoverageDeficit(for: goal) > 0),
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
        focusWins = snapshot.focusWins ?? []
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
        pendingMembershipPresentation = nil
        membershipActivationHandoff = snapshot.membershipActivationHandoff
        questionRefreshesUsed = snapshot.questionRefreshesUsed ?? 0
        lastAutomaticQuestionRefreshAt = snapshot.lastAutomaticQuestionRefreshAt
        questionBankSyncIntents = snapshot.questionBankSyncIntents ?? []
        skillMapEvolutionIntents = snapshot.skillMapEvolutionIntents ?? []
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
        let legacyIssueReportsChanged = migrateLegacyIssueReports()
        let retentionChanged = enforceRetentionLimits()
        if let recoveryMessage {
            persistenceRecoveryMessage = recoveryMessage
            checkpointNotice = recoveryMessage
        }
        let derivedSkillMapsChanged = migrateLegacyDerivedSkillMapsIfNeeded()
        let attemptMetadataChanged = backfillAttemptMetadataIfNeeded()
        if retentionChanged ||
            legacyIssueReportsChanged ||
            derivedSkillMapsChanged ||
            attemptMetadataChanged {
            let migrationSaved = save()
            if legacyIssueReportsChanged && migrationSaved {
                // A second verified save replaces the recovery backup that may
                // still contain goal context captured by an earlier build.
                _ = save()
            }
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
            .flatMap { SkillMapReconciler.competencyTopics(from: $0.topic) }
        let candidateTopics = SkillMapReconciler.skillMapTopicCandidates(
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
                SkillMapReconciler.skillMapTopicWithDefaultObjective(name: name)
            },
            status: .suggested,
            provenance: .questionTopics
        )
        storeGoalProfile(updatedGoal)
        return updatedGoal
    }

    private func canonicalizeStoredQuestions(for targetGoal: Goal) {
        guard let skillMap = targetGoal.derivedSkillMap else { return }

        for index in questions.indices where questions[index].goalID == targetGoal.id {
            guard let skill = SkillMapReconciler.skillMapTopic(
                matching: questions[index],
                in: skillMap
            ) else {
                questions[index].status = .retired
                questions[index].nextReviewAt = nil
                continue
            }
            questions[index] = SkillMapReconciler.canonicalizedQuestion(questions[index], for: skill)
        }
    }

    @discardableResult
    private func backfillAttemptMetadataIfNeeded() -> Bool {
        var didChange = false
        let questionByScopedID = Dictionary(
            questions.map { question in
                (
                    GoalScopedQuestionID(
                        goalID: question.goalID,
                        questionID: question.id
                    ),
                    question
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        for index in attempts.indices {
            let questionID = GoalScopedQuestionID(
                goalID: attempts[index].goalID,
                questionID: attempts[index].questionID
            )
            guard let question = questionByScopedID[questionID] else { continue }
            let targetGoal = storedGoalProfile(withID: attempts[index].goalID)
            let mappedSkill = targetGoal?.derivedSkillMap.flatMap {
                SkillMapReconciler.skillMapTopic(matching: question, in: $0)
            }

            if attempts[index].skillID == nil, let skillID = mappedSkill?.id ?? question.skillID {
                attempts[index].skillID = skillID
                didChange = true
            }
            if attempts[index].objectiveID == nil, let objectiveID = question.objectiveID {
                attempts[index].objectiveID = objectiveID
                didChange = true
            }
            if attempts[index].questionDifficulty == nil {
                attempts[index].questionDifficulty = question.difficulty
                didChange = true
            }
            if attempts[index].reviewSnapshot == nil {
                attempts[index].reviewSnapshot = attemptReviewSnapshot(
                    for: question,
                    result: attempts[index].result,
                    canonicalTopic: mappedSkill?.name ?? question.topic
                )
                didChange = true
            }
        }
        return didChange
    }

    private func attemptReviewSnapshot(
        for question: CheckpointQuestion,
        result: AnswerResult,
        canonicalTopic: String,
        answer: String? = nil
    ) -> CheckpointAttemptReviewSnapshot {
        CheckpointAttemptReviewSnapshot(
            topic: canonicalTopic,
            format: question.format,
            referenceAnswer: AnswerGrader.correctAnswerText(for: question, after: result),
            explanation: answer.map { question.feedbackExplanation(for: $0) } ?? question.explanation
        )
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
                    seededSkill.objectives = [SkillMapReconciler.defaultObjective(for: skill.id, name: skill.name)]
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
                let updatedCompetencies = SkillMapReconciler.reconciledCompetencies(
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
                        SkillMapReconciler.skillMapTopicWithDefaultObjective(name: name)
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
                    with: SkillMapReconciler.reconciledCompetencies(
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
            let candidateTopics = SkillMapReconciler.skillMapTopicCandidates(
                for: profile,
                rawTopics: rawTopics
            )

            guard candidateTopics.count <= 6,
                  let inferredMap = SkillMapReconciler.inferredSkillMap(
                for: profile,
                rawTopics: rawTopics
            ) else {
                let context = GoalQuestionContext(goal: profile)
                let broadKeys = Set([
                    SkillMapReconciler.competencyTopicKey(profile.title),
                    SkillMapReconciler.competencyTopicKey(context.learningTarget)
                ])
                for index in competencies.indices
                where (competencies[index].goalID == profile.id ||
                       (competencies[index].goalID == nil && profile.id == goal?.id)) &&
                    broadKeys.contains(SkillMapReconciler.competencyTopicKey(competencies[index].topic)) {
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
                with: SkillMapReconciler.reconciledCompetencies(
                    existing: profileCompetencies,
                    goal: updatedProfile,
                    questions: questions.filter { $0.goalID == updatedProfile.id }
                )
            )
            didChange = true
        }

        return didChange
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
        minimumLocalQuestionCount: Int? = nil,
        requiredActiveGoalID: Goal.ID? = nil
    ) async -> DurableQuestionBankSyncOutcome {
        let lifecycleID = dataLifecycleID
        guard hasQuestionGenerationMutationAuthority(
            lifecycleID: lifecycleID,
            requiredActiveGoalID: requiredActiveGoalID
        ) else {
            return DurableQuestionBankSyncOutcome(
                serviceSupported: true,
                addedQuestionCount: 0
            )
        }
        guard !questionBankSynchronizationGoalIDs.contains(targetGoal.id) else {
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }
        questionBankSynchronizationGoalIDs.insert(targetGoal.id)
        defer { questionBankSynchronizationGoalIDs.remove(targetGoal.id) }

        let localTarget = minimumLocalQuestionCount ?? questionBankTargetCount
        let initialDeficit = questionBankDeficit(
            for: targetGoal,
            targetCount: localTarget
        )
        guard initialDeficit > 0 else {
            removeQuestionBankSyncIntent(for: targetGoal.id)
            save()
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }
        let requestedDesiredCount = remoteQuestionBankDesiredCount(
            for: targetGoal,
            localDeficit: initialDeficit
        )
        // Skill weights make each bank revision finite; do not replenish stale weights.
        let lowWatermark = 0
        let contextRevision = questionBankContextRevision(for: targetGoal)
        if let existingIntent = questionBankSyncIntents.first(where: {
            $0.goalID == targetGoal.id
        }), isQuestionBankSyncIntentBlocked(existingIntent, for: targetGoal) {
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }
        var intent = upsertQuestionBankSyncIntent(
            for: targetGoal,
            contextRevision: contextRevision,
            desiredCount: requestedDesiredCount,
            lowWatermark: lowWatermark
        )
        // A context's remote fill target is monotonic even as local claims reduce
        // the deficit; a later poll must not shrink a bank already being prepared.
        let desiredCount = intent.desiredCount

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
                contextRevision: intent.bankContextRevision ?? intent.contextRevision,
                desiredCount: desiredCount,
                lowWatermark: lowWatermark
            )
        } catch QuestionBankAPIError.bankNotFound {
            guard hasQuestionGenerationMutationAuthority(
                lifecycleID: lifecycleID,
                requiredActiveGoalID: requiredActiveGoalID
            ) else {
                return DurableQuestionBankSyncOutcome(
                    serviceSupported: true,
                    addedQuestionCount: 0
                )
            }
            durableQuestionBankUnavailableForLifecycle = true
            removeQuestionBankSyncIntent(for: targetGoal.id)
            save()
            return DurableQuestionBankSyncOutcome(serviceSupported: false, addedQuestionCount: 0)
        } catch let error as QuestionBankAPIError {
            guard hasQuestionGenerationMutationAuthority(
                lifecycleID: lifecycleID,
                requiredActiveGoalID: requiredActiveGoalID
            ) else {
                return DurableQuestionBankSyncOutcome(
                    serviceSupported: true,
                    addedQuestionCount: 0
                )
            }
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
            guard hasQuestionGenerationMutationAuthority(
                lifecycleID: lifecycleID,
                requiredActiveGoalID: requiredActiveGoalID
            ) else {
                return DurableQuestionBankSyncOutcome(
                    serviceSupported: true,
                    addedQuestionCount: 0
                )
            }
            markQuestionBankSyncAttempt(for: targetGoal.id)
            lastAIErrorMessage = error.localizedDescription
            save()
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }

        guard hasQuestionGenerationMutationAuthority(
                  lifecycleID: lifecycleID,
                  requiredActiveGoalID: requiredActiveGoalID
              ),
              let currentGoal = storedGoalProfile(withID: targetGoal.id) else {
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }
        let currentContextRevision = questionBankContextRevision(for: currentGoal)
        guard currentContextRevision == contextRevision else {
            refreshQuestionBankSyncIntentForCurrentDeficit(
                for: currentGoal,
                contextRevision: currentContextRevision,
                localTarget: localTarget,
                lowWatermark: lowWatermark
            )
            save()
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }

        if intent.bankID != preparation.bankID {
            intent.bankID = preparation.bankID
            intent.claimID = UUID().uuidString
        }
        intent.generationBlockedReason = normalizedQuestionBankBlockedReason(
            preparation.generationBlockedReason
        )
        intent.lastAttemptAt = Date()
        replaceQuestionBankSyncIntent(intent)
        save()

        guard preparation.readyCount > 0 else {
            if preparation.status == .empty,
               intent.generationBlockedReason == nil {
                // The server has spent this finite bank, but client-side validation may
                // have rejected some claimed rows. Give that local deficit one fresh,
                // crash-resumable fill cycle instead of silently stranding first use.
                // Persistently stop after the bounded retry so validation drift cannot
                // create an unbounded background/provider-cost loop.
                let emptyRetryCount = intent.emptyFillCycleRetryCount ?? 0
                if emptyRetryCount < Self.maximumEmptyFillCycleRetries {
                    intent.bankContextRevision = newQuestionBankContextRevision(
                        baseRevision: intent.contextRevision
                    )
                    intent.bankID = nil
                    intent.claimID = UUID().uuidString
                    intent.desiredCount = remoteQuestionBankDesiredCount(
                        for: targetGoal,
                        localDeficit: initialDeficit
                    )
                    intent.emptyFillCycleRetryCount = emptyRetryCount + 1
                    intent.createdAt = Date()
                    intent.lastAttemptAt = nil
                    replaceQuestionBankSyncIntent(intent)
                } else {
                    intent.generationBlockedReason = "client_validation_limit"
                    replaceQuestionBankSyncIntent(intent)
                }
                save()
            }
            return DurableQuestionBankSyncOutcome(serviceSupported: true, addedQuestionCount: 0)
        }

        var totalAdded = 0
        var claimAttemptCount = 0
        while claimAttemptCount < Self.maximumClaimsPerSync {
            guard let latestGoal = storedGoalProfile(withID: targetGoal.id) else { break }
            let latestContextRevision = questionBankContextRevision(for: latestGoal)
            guard latestContextRevision == intent.contextRevision else {
                refreshQuestionBankSyncIntentForCurrentDeficit(
                    for: latestGoal,
                    contextRevision: latestContextRevision,
                    localTarget: localTarget,
                    lowWatermark: lowWatermark
                )
                save()
                break
            }

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
                guard hasQuestionGenerationMutationAuthority(
                    lifecycleID: lifecycleID,
                    requiredActiveGoalID: requiredActiveGoalID
                ) else {
                    return DurableQuestionBankSyncOutcome(
                        serviceSupported: true,
                        addedQuestionCount: totalAdded
                    )
                }
                intent.bankID = nil
                intent.claimID = UUID().uuidString
                intent.lastAttemptAt = Date()
                replaceQuestionBankSyncIntent(intent)
                save()
                break
            } catch {
                guard hasQuestionGenerationMutationAuthority(
                    lifecycleID: lifecycleID,
                    requiredActiveGoalID: requiredActiveGoalID
                ) else {
                    return DurableQuestionBankSyncOutcome(
                        serviceSupported: true,
                        addedQuestionCount: totalAdded
                    )
                }
                markQuestionBankSyncAttempt(for: targetGoal.id)
                lastAIErrorMessage = error.localizedDescription
                save()
                break
            }

            guard hasQuestionGenerationMutationAuthority(
                      lifecycleID: lifecycleID,
                      requiredActiveGoalID: requiredActiveGoalID
                  ),
                  var resolvedGoal = storedGoalProfile(withID: targetGoal.id) else {
                break
            }
            if let blockedReason = normalizedQuestionBankBlockedReason(
                claim.generationBlockedReason
            ) {
                intent.generationBlockedReason = blockedReason
            }
            let resolvedContextRevision = questionBankContextRevision(for: resolvedGoal)
            guard resolvedContextRevision == intent.contextRevision else {
                refreshQuestionBankSyncIntentForCurrentDeficit(
                    for: resolvedGoal,
                    contextRevision: resolvedContextRevision,
                    localTarget: localTarget,
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
            let canonicalClaimQuestions = SkillMapReconciler.canonicalizedQuestions(sanitizedClaimedQuestions, for: resolvedGoal)
            let currentQuestions = questions.filter { $0.goalID == targetGoal.id }
            let existingIDs = Set(currentQuestions.map(\.id))
            let existingRemoteIDs = Set(currentQuestions.compactMap(\.remoteID))
            let existingKeys = Set(currentQuestions.map { SkillMapReconciler.questionKey($0) })
            let newQuestions = canonicalClaimQuestions.filter { question in
                !existingIDs.contains(question.id)
                    && question.remoteID.map { !existingRemoteIDs.contains($0) } != false
                    && !existingKeys.contains(SkillMapReconciler.questionKey(question))
            }
            questions.append(contentsOf: newQuestions)
            let goalQuestions = questions.filter { $0.goalID == targetGoal.id }
            let currentCompetencies = competencies.filter {
                ($0.goalID ?? resolvedGoal.id) == resolvedGoal.id
            }
            replaceCompetencies(
                for: resolvedGoal.id,
                with: SkillMapReconciler.reconciledCompetencies(
                    existing: currentCompetencies,
                    goal: resolvedGoal,
                    questions: goalQuestions
                )
            )

            totalAdded += newQuestions.count
            if !newQuestions.isEmpty {
                intent.emptyFillCycleRetryCount = 0
                lastQuestionProvider = .backend
                lastQuestionGenerationFailure = nil
                lastAIErrorMessage = nil
            }

            let updatedRevision = questionBankContextRevision(for: resolvedGoal)
            if updatedRevision != intent.contextRevision {
                refreshQuestionBankSyncIntentForCurrentDeficit(
                    for: resolvedGoal,
                    contextRevision: updatedRevision,
                    localTarget: localTarget,
                    lowWatermark: lowWatermark
                )
                guard let refreshedIntent = questionBankSyncIntents.first(where: {
                    $0.goalID == resolvedGoal.id
                }) else {
                    save()
                    break
                }
                intent = refreshedIntent
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
                  updatedRevision == contextRevision,
                  !(intent.generationBlockedReason != nil && claim.readyCount == 0) else {
                break
            }
        }

        return DurableQuestionBankSyncOutcome(
            serviceSupported: true,
            addedQuestionCount: totalAdded
        )
    }

    func remoteQuestionBankDesiredCount(
        for targetGoal: Goal,
        localDeficit: Int
    ) -> Int {
        guard let skillMap = targetGoal.derivedSkillMap,
              !skillMap.topics.isEmpty else {
            return min(100, max(1, localDeficit))
        }
        let goalCompetencies = competencies.filter {
            ($0.goalID ?? targetGoal.id) == targetGoal.id
        }
        let weights = desiredSkillAllocation(
            for: targetGoal,
            competencies: goalCompetencies
        )
        let skillIDs = skillMap.topics.map(\.id)
        let positiveWeightSkillCount = skillIDs.filter { weights[$0, default: 0] > 0 }.count
        let coverageDeficits = skillQuestionCoverageDeficitBySkillID(for: targetGoal)
        let objectiveCounts = Dictionary(uniqueKeysWithValues: skillMap.topics.map {
            ($0.id, $0.objectives.count)
        })
        let minimumDesiredCount = min(
            100,
            max(1, localDeficit, positiveWeightSkillCount)
        )
        for desiredCount in minimumDesiredCount...100 {
            let targets = apportionedSkillCounts(
                skillIDs: skillIDs,
                weights: weights,
                desiredCount: desiredCount
            )
            if skillIDs.allSatisfy({
                targets[$0, default: 0] >= max(
                    coverageDeficits[$0, default: 0],
                    objectiveCounts[$0, default: 0]
                )
            }) {
                return desiredCount
            }
        }
        return 100
    }

    private func apportionedSkillCounts(
        skillIDs: [SkillMapTopic.ID],
        weights: [SkillMapTopic.ID: Int],
        desiredCount: Int
    ) -> [SkillMapTopic.ID: Int] {
        guard desiredCount > 0, !skillIDs.isEmpty else { return [:] }

        let resolvedWeights = Dictionary(uniqueKeysWithValues: skillIDs.map {
            ($0, max(0, weights[$0, default: 0]))
        })
        let positiveSkillIDs = skillIDs.filter { resolvedWeights[$0, default: 0] > 0 }
        var targets = Dictionary(uniqueKeysWithValues: skillIDs.map { ($0, 0) })
        guard !positiveSkillIDs.isEmpty else { return targets }

        if desiredCount < positiveSkillIDs.count {
            let orderByID = Dictionary(uniqueKeysWithValues: skillIDs.enumerated().map { ($1, $0) })
            let ranked = positiveSkillIDs.sorted { lhs, rhs in
                let lhsWeight = resolvedWeights[lhs, default: 0]
                let rhsWeight = resolvedWeights[rhs, default: 0]
                if lhsWeight != rhsWeight { return lhsWeight > rhsWeight }
                return orderByID[lhs, default: 0] < orderByID[rhs, default: 0]
            }
            for skillID in ranked.prefix(desiredCount) {
                targets[skillID] = 1
            }
            return targets
        }

        for skillID in positiveSkillIDs {
            targets[skillID] = 1
        }
        let remainingCount = desiredCount - positiveSkillIDs.count
        let weightTotal = positiveSkillIDs.reduce(0) {
            $0 + resolvedWeights[$1, default: 0]
        }
        guard remainingCount > 0, weightTotal > 0 else { return targets }

        let orderByID = Dictionary(uniqueKeysWithValues: skillIDs.enumerated().map { ($1, $0) })
        var fractionalRemainders: [SkillMapTopic.ID: Double] = [:]
        for skillID in positiveSkillIDs {
            let exact = Double(remainingCount * resolvedWeights[skillID, default: 0]) /
                Double(weightTotal)
            let addition = Int(exact)
            targets[skillID, default: 0] += addition
            fractionalRemainders[skillID] = exact - Double(addition)
        }
        let remainder = desiredCount - targets.values.reduce(0, +)
        let ranked = positiveSkillIDs.sorted { lhs, rhs in
            let lhsRemainder = fractionalRemainders[lhs, default: 0]
            let rhsRemainder = fractionalRemainders[rhs, default: 0]
            if lhsRemainder != rhsRemainder { return lhsRemainder > rhsRemainder }
            return orderByID[lhs, default: 0] < orderByID[rhs, default: 0]
        }
        for skillID in ranked.prefix(remainder) {
            targets[skillID, default: 0] += 1
        }
        return targets
    }

    private func refreshQuestionBankSyncIntentForCurrentDeficit(
        for targetGoal: Goal,
        contextRevision: String,
        localTarget: Int,
        lowWatermark: Int
    ) {
        let deficit = questionBankDeficit(for: targetGoal, targetCount: localTarget)
        guard deficit > 0 else {
            removeQuestionBankSyncIntent(for: targetGoal.id)
            return
        }
        _ = upsertQuestionBankSyncIntent(
            for: targetGoal,
            contextRevision: contextRevision,
            desiredCount: remoteQuestionBankDesiredCount(
                for: targetGoal,
                localDeficit: deficit
            ),
            lowWatermark: lowWatermark
        )
    }

    private func schedulePendingQuestionBankPolling(for targetGoal: Goal) {
        guard shouldUseDurableQuestionBank,
              let initialIntent = questionBankSyncIntents.first(where: { $0.goalID == targetGoal.id }),
              !isQuestionBankSyncIntentBlocked(initialIntent, for: targetGoal),
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
                guard !self.isQuestionBankSyncIntentBlocked(currentIntent, for: currentGoal) else {
                    self.finishQuestionBankPolling(for: targetGoal.id, token: pollingToken)
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
                    self.questionBatchState = self.checkpointReadiness(for: currentGoal).hasFullCheckpoint
                        ? .ready
                        : (self.hasPendingQuestionBankSync(for: currentGoal) ? .idle : .failed)
                }
                self.save()
                self.publishShieldContext()

                if let latestIntent = self.questionBankSyncIntents.first(where: {
                    $0.goalID == currentGoal.id
                }), self.isQuestionBankSyncIntentBlocked(latestIntent, for: currentGoal) {
                    self.finishQuestionBankPolling(for: targetGoal.id, token: pollingToken)
                    return
                }
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
                intent.bankContextRevision = newQuestionBankContextRevision(
                    baseRevision: contextRevision
                )
                intent.bankID = nil
                intent.claimID = UUID().uuidString
                intent.createdAt = Date()
                intent.lastAttemptAt = nil
                intent.generationBlockedReason = nil
                intent.emptyFillCycleRetryCount = 0
                intent.desiredCount = desiredCount
            } else {
                intent.desiredCount = max(intent.desiredCount, desiredCount)
            }
            intent.lowWatermark = lowWatermark
            questionBankSyncIntents[index] = intent
            save()
            return intent
        }

        let intent = QuestionBankSyncIntent(
            goalID: targetGoal.id,
            contextRevision: contextRevision,
            bankContextRevision: newQuestionBankContextRevision(
                baseRevision: contextRevision
            ),
            desiredCount: desiredCount,
            lowWatermark: lowWatermark
        )
        questionBankSyncIntents.append(intent)
        save()
        return intent
    }

    private func newQuestionBankContextRevision(baseRevision: String) -> String {
        "\(baseRevision):\(UUID().uuidString)"
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
        // Baseline targets equal the existing minimum, so receiving the first
        // reviewed item need not restart an otherwise identical in-flight bank.
        let currentPlans = adaptiveSkillPlans(for: goal)
        let revisionPlans = isMember && currentPlans.isEmpty
            ? AdaptiveLearningPolicy.plans(for: goal, attempts: []) : currentPlans
        let components = [
            isMember ? "verified-learning-v1" : "starter",
            goal.title,
            goal.currentLevel,
            goal.focusAreas,
            String(goal.minimumQuestionDifficulty),
            goal.preferredQuestionStyle.rawValue,
            goal.derivedSkillMap.map {
                SkillMapReconciler.skillMapContentSignature(topics: $0.topics)
            } ?? "",
            skillAllocationSignature
        ] + revisionPlans.map(\.revisionKey).sorted()
            + goal.sourceDocuments.flatMap { document in
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
        let generationCompetencies: [TopicCompetency]
        if let skillMap = goal.derivedSkillMap {
            let activeSkillIDs = Set(skillMap.topics.map(\.id))
            generationCompetencies = competencies.filter { competency in
                guard let skillID = competency.skillID else { return true }
                return activeSkillIDs.contains(skillID)
            }
        } else {
            generationCompetencies = competencies
        }
        return QuestionGenerationRequest(
            goal: goal,
            existingQuestions: existingQuestions,
            competencies: generationCompetencies,
            reportedQuestions: reportedQuestions,
            targetCount: resolvedTargetCount,
            minimumDifficulty: goal.minimumQuestionDifficulty,
            desiredSkillAllocation: desiredSkillAllocation(
                for: goal,
                competencies: generationCompetencies
            ),
            adaptiveSkillPlans: adaptiveSkillPlans(for: goal),
            requiresVerifiedQuestions: usesVerifiedLearning(for: goal),
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

        let recentPlans = Dictionary(uniqueKeysWithValues: adaptiveSkillPlans(for: targetGoal).map { ($0.skillID, $0) })
        var competencyBySkillID: [SkillMapTopic.ID: TopicCompetency] = [:]
        for competency in competencies {
            guard let skillID = competency.skillID else { continue }
            if let existing = competencyBySkillID[skillID] {
                competencyBySkillID[skillID] = SkillMapReconciler.mergedCompetency(existing, with: competency)
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

            let recent = recentPlans[skill.id]
            let mastery = (recent?.evidenceCount ?? 0) >= 4
                ? (recent?.recentAccuracyPercent ?? competency.masteryPercent)
                : competency.masteryPercent
            let weaknessBonus = Int(ceil(Double(max(0, 100 - mastery)) / 10.0))
            let uncertaintyBonus = max(0, 4 - min(4, competency.attempts))
            let weight = min(
                16,
                max(
                    3,
                    skill.objectives.count,
                    3 + weaknessBonus + uncertaintyBonus
                )
            )
            allocation[skill.id] = weight
        }
        return allocation
    }

    private func usesVerifiedLearning(for targetGoal: Goal) -> Bool {
        guard isMember else { return false }
        // Older services do not yet supply reviewed inventory. Activate per goal
        // once the service has delivered it; retained attempts preserve activation.
        return questions.contains { $0.goalID == targetGoal.id && $0.verificationVersion == 1 }
            || attempts.contains { $0.goalID == targetGoal.id && $0.questionVerificationVersion == 1 }
    }

    private func adaptiveSkillPlans(for targetGoal: Goal) -> [AdaptiveSkillPlan] {
        guard usesVerifiedLearning(for: targetGoal) else { return [] }
        let excludedQuestions = Set(questionReports.filter { $0.goalID == targetGoal.id }.map(\.questionID))
        return AdaptiveLearningPolicy.plans(for: targetGoal, attempts: attempts.filter { !excludedQuestions.contains($0.questionID) })
    }

    func adaptiveLearningPlan(for competency: TopicCompetency) -> AdaptiveSkillPlan? {
        guard let goal, let skillID = competency.skillID else { return nil }
        return adaptiveSkillPlans(for: goal).first { $0.skillID == skillID }
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
