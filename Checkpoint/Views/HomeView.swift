import Accessibility
import SwiftUI

struct HomeWeeklyReviewDestination: Identifiable, Equatable {
    let metricsID: String
    let referenceDate: Date
    let calendar: Calendar

    var id: String { metricsID }
}

struct HomeView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let workflow: CheckpointWorkflowCoordinator
    private let refreshesQuestionsOnActivation: Bool
    private let reduceMotionOverride: Bool?
    private let referenceDateOverride: Date?
    private let calendar: Calendar
    private let isVisible: Bool
    private let isSceneActive: Bool
    private let isCoveredByParentModal: Bool
    private let parentModalOwnsQuestionReadiness: Bool
    private let parentModalOwnsProtectionErrors: Bool
    private let earnedBreakHandoff: EarnedBreakHandoffToken?
    private let resolveEarnedBreakHandoff: @MainActor (
        EarnedBreakHandoffToken,
        EarnedBreakHandoffDisposition
    ) -> Bool
    private let onEarnedBreakHandoffDelivered: @MainActor (
        EarnedBreakHandoffDeliveryEffect
    ) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.checkpointGoalSelection) private var selectGoal
    @Environment(\.checkpointProgressSkillEvidenceNavigation)
    private var navigateToProgressSkillEvidence
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isRestrictedAppsPresented = false
    @State private var weeklyReviewDestination: HomeWeeklyReviewDestination?
    @State private var isAcceptingLevelIncrease = false
    @State private var isRetryingInitialQuestions = false
    @State private var isQuestionsReadyConfirmationVisible = false
    @State private var questionsReadyConfirmationDismissTask: Task<Void, Never>?
    @State private var lastActivationRefreshAt: Date?
    @State private var liveReferenceDate = Date()
    @State private var accessibilityAnnouncementQueue = AccessibilityAnnouncementDeliveryQueue()
    @State private var protectionStartErrorFeedback = ProtectionStartErrorFeedbackState()
    @State private var suppressedQuestionReadyGoalID: Goal.ID?
    @State private var earnedBreakHandoffDelivery: EarnedBreakHandoffDeliveryState
    @State private var earnedBreakRevealSequence = 0
    @State private var earnedBreakCelebrationSequence = 0

    private static let activationRefreshDebounceInterval: TimeInterval = 20
    private static let questionsReadyConfirmationText = "Your questions are ready."
    private static let questionsReadyConfirmationDurationNanoseconds: UInt64 = 4_000_000_000

    init(
        store: CheckpointStore,
        screenTime: ScreenTimeController,
        workflow: CheckpointWorkflowCoordinator,
        refreshesQuestionsOnActivation: Bool = true,
        reduceMotionOverride: Bool? = nil,
        referenceDate: Date? = nil,
        calendar: Calendar = .current,
        isVisible: Bool = true,
        isSceneActive: Bool = true,
        isCoveredByParentModal: Bool = false,
        parentModalOwnsQuestionReadiness: Bool = false,
        parentModalOwnsProtectionErrors: Bool = false,
        earnedBreakHandoff: EarnedBreakHandoffToken? = nil,
        resolveEarnedBreakHandoff: @escaping @MainActor (
            EarnedBreakHandoffToken,
            EarnedBreakHandoffDisposition
        ) -> Bool = { _, _ in false },
        onEarnedBreakHandoffDelivered: @escaping @MainActor (
            EarnedBreakHandoffDeliveryEffect
        ) -> Void = { _ in }
    ) {
        self.store = store
        self.screenTime = screenTime
        self.workflow = workflow
        self.refreshesQuestionsOnActivation = refreshesQuestionsOnActivation
        self.reduceMotionOverride = reduceMotionOverride
        referenceDateOverride = referenceDate
        self.calendar = calendar
        self.isVisible = isVisible
        self.isSceneActive = isSceneActive
        self.isCoveredByParentModal = isCoveredByParentModal
        self.parentModalOwnsQuestionReadiness = parentModalOwnsQuestionReadiness
        self.parentModalOwnsProtectionErrors = parentModalOwnsProtectionErrors
        self.earnedBreakHandoff = earnedBreakHandoff
        self.resolveEarnedBreakHandoff = resolveEarnedBreakHandoff
        self.onEarnedBreakHandoffDelivered = onEarnedBreakHandoffDelivered
        _earnedBreakHandoffDelivery = State(
            initialValue: EarnedBreakHandoffDeliveryState(token: earnedBreakHandoff)
        )
    }

    private struct QuestionPreparationSnapshot: Equatable {
        let goalID: Goal.ID?
        let isPreparing: Bool
        let hasReadyCheckpointSet: Bool
    }

    private struct EarnedBreakDeliveryTaskID: Equatable, Hashable {
        let handoff: EarnedBreakHandoffToken?
        let activeGoalID: Goal.ID?
        let canonicalUnlockStartedAt: Date?
        let canonicalUnlockExpiresAt: Date?
        let isTemporaryUnlockAvailable: Bool
        let isExposed: Bool
    }

    private enum ScrollAnchor: Hashable {
        case activeBreak
    }

    var body: some View {
        GeometryReader { geometry in
            homeContent(viewportWidth: geometry.size.width)
        }
    }

    private func homeContent(viewportWidth: CGFloat) -> some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: homeSectionSpacing(viewportWidth: viewportWidth)
                    ) {
                        checkpointNoticePanel

                        if let goal = store.goal {
                            goalScopedContent(goal, viewportWidth: viewportWidth)
                                .id(goal.id)
                                .transition(goalIdentityMotionPolicy.transition)
                        } else {
                            emptyState
                        }
                    }
                    .animation(
                        CheckpointMotion.animation(
                            CheckpointMotion.reveal,
                            reduceMotion: reduceMotion
                        ),
                        value: homeStudyBeaconPresentation.kind
                    )
                    .animation(
                        CheckpointMotion.animation(
                            CheckpointMotion.reveal,
                            reduceMotion: reduceMotion
                        ),
                        value: isTemporarilyUnblocked
                    )
                    .animation(
                        goalIdentityMotionPolicy.animation,
                        value: store.goal?.id
                    )
                    .padding(.horizontal, homeHorizontalMargin(viewportWidth: viewportWidth))
                    .padding(.top, homeTopMargin(viewportWidth: viewportWidth))
                    .padding(.bottom, 112)
                }
                .checkpointScreenBackground()
                .navigationTitle("Checkpoint")
                .toolbarTitleDisplayMode(.inline)
                .sheet(isPresented: $isRestrictedAppsPresented) {
                    RestrictedAppsView(screenTime: screenTime)
                }
                .sheet(item: $weeklyReviewDestination) { destination in
                    WeeklyReviewView(
                        store: store,
                        initialMetricsID: destination.metricsID,
                        referenceDate: destination.referenceDate,
                        displayCalendar: destination.calendar,
                        displayTimeZone: destination.calendar.timeZone,
                        reduceMotionOverride: reduceMotion,
                        initialWeekReferenceDate: destination.referenceDate
                    )
                }
                .onAppear {
                    refreshDeadlineReferenceDate()
                    handleQuestionRefreshOnActivation()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        refreshDeadlineReferenceDate()
                        handleQuestionRefreshOnActivation()
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                ) { _ in
                    refreshDeadlineReferenceDate()
                }
                .onChange(of: questionPreparationSnapshot) { previous, current in
                    guard previous.goalID == current.goalID else {
                        suppressedQuestionReadyGoalID = nil
                        hideQuestionsReadyConfirmation()
                        return
                    }

                    if !previous.hasReadyCheckpointSet,
                       current.hasReadyCheckpointSet {
                        if ProtectionStartReadinessAnnouncementPolicy.shouldSuppress(
                            for: current.goalID,
                            locallySuppressedGoalID: suppressedQuestionReadyGoalID,
                            parentPresentationOwnsReadiness: parentModalOwnsQuestionReadiness,
                            startingProtectionReadinessGoalID: workflow.startingProtectionReadinessGoalID,
                            pendingResult: workflow.pendingProtectionStartResult
                        ) {
                            suppressedQuestionReadyGoalID = nil
                            return
                        }
                        guard previous.isPreparing else { return }
                        showQuestionsReadyConfirmation()
                    } else if previous.isPreparing,
                              !current.isPreparing,
                              !current.hasReadyCheckpointSet,
                              suppressedQuestionReadyGoalID == current.goalID {
                        suppressedQuestionReadyGoalID = nil
                    }
                }
                .onChange(of: screenTime.userFacingErrorMessage) { _, message in
                    let isStartFeedbackPending = workflow.isStartingProtection
                        || workflow.pendingProtectionStartResult?.protectionErrorMessage == message
                    guard protectionStartErrorFeedback.shouldDeliverPassiveError(
                        message,
                        isStartFeedbackPending: isStartFeedbackPending
                    ), let message else { return }
                    guard isVisible,
                          !parentModalOwnsProtectionErrors,
                          !isCoveredByLocalPresentation else { return }
                    announceOrQueue(
                        AccessibilityAnnouncementRequest(
                            message: message,
                            context: .screenTimeError(message)
                        )
                    )
                }
                .onChange(of: workflow.pendingProtectionStartResult) { _, _ in
                    deliverPendingProtectionStartResultIfPossible()
                }
                .onChange(of: parentModalOwnsQuestionReadiness) { _, ownsReadiness in
                    guard ownsReadiness else { return }
                    accessibilityAnnouncementQueue.discard()
                    hideQuestionsReadyConfirmation()
                }
                .onChange(of: ownsQuestionReadinessFeedback) { _, ownsFeedback in
                    if !ownsFeedback {
                        hideQuestionsReadyConfirmation()
                    } else {
                        deliverPendingAccessibilityAnnouncement()
                        deliverPendingProtectionStartResultIfPossible()
                    }
                }
                .onChange(of: earnedBreakRevealSequence) { previous, current in
                    guard current > previous else { return }
                    scrollToEarnedBreak(using: scrollProxy)
                }
                .task(id: earnedBreakDeliveryTaskID) {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    deliverEarnedBreakHandoffIfPossible()
                }
                .sensoryFeedback(.success, trigger: earnedBreakCelebrationSequence)
                .onDisappear {
                    hideQuestionsReadyConfirmation()
                }
                .environment(\.homeWeeklySignalViewportWidth, viewportWidth)
            }
        }
    }

    private func goalScopedContent(_ goal: Goal, viewportWidth: CGFloat) -> some View {
        VStack(
            alignment: .leading,
            spacing: usesCompactHomeMargins(viewportWidth: viewportWidth) ? 14 : 24
        ) {
            if isTemporarilyUnblocked {
                activeBreakCard
                    .transition(homeActiveBreakTransition)
                goalHero(goal)
                if homeStudyBeaconPresentation.showsNextFocus {
                    homeNextFocusPanel
                    homeStudyBeaconSection
                }
            } else {
                goalHero(goal)

                switch homeStudyBeaconPresentation {
                case .firstWinJourney:
                    homeStudyBeaconSection

                case .weeklySignal:
                    homeNextFocusPanel
                        .transition(homeNextFocusTransition)

                    if isHealthyProtectionState {
                        homeStudyBeaconSection
                        compactProtectionRow
                    } else {
                        screenTimePanel
                        homeStudyBeaconSection
                    }
                }
            }

            levelRecommendationPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func goalHero(_ goal: Goal) -> some View {
        let presentation = HomeGoalOverviewPresentation(
            goal: goal,
            readiness: store.checkpointReadiness(for: goal),
            isGenerationBlockingPractice: store.isQuestionGenerationBlockingPractice,
            generationFailure: store.lastQuestionGenerationFailure,
            isRetryingGeneration: isRetryingInitialQuestions,
            readyDisclosure: homeStudyBeaconPresentation.suppressesReadyGoalDisclosure
                ? .suppressedByFirstWinJourney
                : .visible,
            isNewlyPrepared: isQuestionsReadyConfirmationVisible,
            unlockPolicy: store.unlockPolicy,
            availableGoalCount: store.availableGoalProfiles.count,
            generationStatusText: store.questionGenerationStatusText,
            referenceDate: referenceDate
        )

        return HomeGoalOverviewCard(
            presentation: presentation,
            reduceMotion: reduceMotion,
            layout: usesCompactFirstWinHomeLayout ? .firstWinCompact : .standard,
            retryQuestions: retryInitialQuestionGeneration,
            editGoal: store.presentActiveGoalEditor
        ) {
            goalManagementControl(
                currentGoal: goal,
                action: presentation.goalAction
            )
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func goalManagementControl(
        currentGoal: Goal,
        action: HomeGoalOverviewGoalAction
    ) -> some View {
        switch action {
        case .none:
            EmptyView()
        case .editGoal:
            Button {
                store.presentActiveGoalEditor()
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 44)
                    .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(CheckpointPressButtonStyle())
            .accessibilityLabel("Edit goal")
            .accessibilityValue(currentGoal.title)
            .accessibilityHint("Opens this goal's details")
        case .switchGoal:
            goalSwitcherMenu(currentGoal: currentGoal)
        }
    }

    @ViewBuilder
    private func goalSwitcherMenu(currentGoal: Goal) -> some View {
        if store.availableGoalProfiles.count > 1 {
            let presentation = GoalSwitchMenuPresentation(store: store)
            Menu {
                ForEach(presentation.options) { option in
                    Button {
                        selectGoal(option.id)
                    } label: {
                        Label(option.menuTitle, systemImage: option.systemImage)
                    }
                    .disabled(option.isCurrent || option.state == .unavailable)
                    .accessibilityValue(option.accessibilityValue)
                }

                Divider()

                if !store.isMember || !store.hasReachedGoalProfileLimit {
                    Button {
                        store.presentGoalProfileCreator()
                    } label: {
                        Label("New goal", systemImage: "plus")
                    }
                }
            } label: {
                GoalSwitcherCapsuleLabel(title: "Switch")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch goal")
            .accessibilityValue(currentGoal.title)
            .accessibilityHint("Changes the active goal throughout Checkpoint")
        }
    }

    private var questionPreparationSnapshot: QuestionPreparationSnapshot {
        QuestionPreparationSnapshot(
            goalID: store.goal?.id,
            isPreparing: store.isPreparingActiveGoalQuestions,
            hasReadyCheckpointSet: store.hasReadyCheckpointSet
        )
    }

    private func showQuestionsReadyConfirmation() {
        guard isVisible,
              let goalID = store.goal?.id else { return }
        let request = AccessibilityAnnouncementRequest(
            message: Self.questionsReadyConfirmationText,
            context: .goalReady(goalID)
        )
        guard let request = accessibilityAnnouncementQueue.submit(
            request,
            isOwner: ownsQuestionReadinessFeedback
        ) else { return }

        presentQuestionsReadyConfirmation()
        AccessibilityNotification.Announcement(request.message).post()
    }

    private func presentQuestionsReadyConfirmation() {
        questionsReadyConfirmationDismissTask?.cancel()
        setQuestionsReadyConfirmationVisible(true)

        questionsReadyConfirmationDismissTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: Self.questionsReadyConfirmationDurationNanoseconds
            )
            guard !Task.isCancelled else { return }

            setQuestionsReadyConfirmationVisible(false)
            questionsReadyConfirmationDismissTask = nil
        }
    }

    private func setQuestionsReadyConfirmationVisible(_ isVisible: Bool) {
        isQuestionsReadyConfirmationVisible = isVisible
    }

    private func hideQuestionsReadyConfirmation() {
        questionsReadyConfirmationDismissTask?.cancel()
        questionsReadyConfirmationDismissTask = nil
        isQuestionsReadyConfirmationVisible = false
    }

    private var ownsQuestionReadinessFeedback: Bool {
        TabContentAnnouncementOwnership.isActive(
            isVisible: isVisible,
            isSceneActive: isSceneActive,
            isCoveredByParentPresentation: isCoveredByParentModal,
            isCoveredByLocalPresentation: isCoveredByLocalPresentation
        )
    }

    private var isCoveredByLocalPresentation: Bool {
        isRestrictedAppsPresented || weeklyReviewDestination != nil
    }

    private func earnedBreakDeliveryContext(now: Date) -> EarnedBreakHandoffDeliveryContext {
        EarnedBreakHandoffDeliveryContext(
            activeGoalID: store.goal?.id,
            canonicalUnlockStartedAt: store.unlockSession?.startedAt,
            canonicalUnlockExpiresAt: store.unlockSession?.expiresAt,
            isTemporaryUnlockAvailable: isTemporarilyUnblocked
                && screenTime.setupState == .temporarilyUnlocked,
            isExposed: ownsQuestionReadinessFeedback,
            now: now
        )
    }

    private var earnedBreakDeliveryTaskID: EarnedBreakDeliveryTaskID {
        EarnedBreakDeliveryTaskID(
            handoff: earnedBreakHandoff,
            activeGoalID: store.goal?.id,
            canonicalUnlockStartedAt: store.unlockSession?.startedAt,
            canonicalUnlockExpiresAt: store.unlockSession?.expiresAt,
            isTemporaryUnlockAvailable: isTemporarilyUnblocked
                && screenTime.setupState == .temporarilyUnlocked,
            isExposed: ownsQuestionReadinessFeedback
        )
    }

    private func deliverEarnedBreakHandoffIfPossible() {
        earnedBreakHandoffDelivery.receive(earnedBreakHandoff)
        let context = earnedBreakDeliveryContext(
            now: referenceDateOverride ?? Date()
        )
        guard let effect = earnedBreakHandoffDelivery.attemptDelivery(
            in: context,
            authoritativeResolve: resolveEarnedBreakHandoff
        ) else { return }

        earnedBreakRevealSequence += effect.revealSequenceIncrement
        earnedBreakCelebrationSequence += effect.celebrationSequenceIncrement
        onEarnedBreakHandoffDelivered(effect)
        AccessibilityNotification.Announcement(effect.accessibilityAnnouncement).post()
    }

    private func scrollToEarnedBreak(using scrollProxy: ScrollViewProxy) {
        guard isTemporarilyUnblocked,
              !voiceOverEnabled,
              !switchControlEnabled else { return }

        if reduceMotion {
            scrollProxy.scrollTo(ScrollAnchor.activeBreak, anchor: .top)
        } else {
            withAnimation(CheckpointMotion.reveal) {
                scrollProxy.scrollTo(ScrollAnchor.activeBreak, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private var levelRecommendationPanel: some View {
        if store.questionLevelRecommendation != nil {
            Button {
                acceptLevelRecommendation()
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if isAcceptingLevelIncrease {
                            ProgressView()
                                .tint(CheckpointTheme.amber)
                        } else {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(CheckpointTheme.amber)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(CheckpointTheme.amber.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready for more depth")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)

                        Text(isAcceptingLevelIncrease ? "Preparing harder questions" : "Use harder questions")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckpointTheme.amber)
                }
                .padding(14)
                .background(CheckpointTheme.panelRaised.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(CheckpointPressButtonStyle(role: .surface))
            .disabled(isAcceptingLevelIncrease)
            .accessibilityHint("Updates the current goal to use harder questions")
        }
    }

    private func acceptLevelRecommendation() {
        Task {
            guard !isAcceptingLevelIncrease else { return }
            isAcceptingLevelIncrease = true
            await store.acceptQuestionLevelRecommendation()
            isAcceptingLevelIncrease = false
        }
    }

    @ViewBuilder
    private var checkpointNoticePanel: some View {
        if let notice = store.checkpointNotice {
            SectionPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CheckpointTheme.amber)

                        Text(notice)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 10) {
                        SecondaryActionButton(title: "Dismiss", systemImage: "xmark") {
                            store.clearCheckpointNotice()
                        }
                    }
                }
            }
        }
    }

    private var studyBeaconPanel: some View {
        let asOf = referenceDateOverride ?? Date()
        let metrics = store.weeklyActiveGoalMetrics(asOf: asOf, calendar: calendar)
            ?? store.weeklyTotalMetrics(asOf: asOf, calendar: calendar)

        return LightStudyBeaconSection(
            metrics: metrics,
            competencies: store.activeProgressCompetencies,
            insight: metrics.weeklySignalInsight,
            reduceMotionOverride: reduceMotion,
            referenceDate: asOf,
            calendar: calendar
        ) {
            weeklyReviewDestination = HomeWeeklyReviewDestination(
                metricsID: metrics.id,
                referenceDate: asOf,
                calendar: calendar
            )
        }
    }

    @ViewBuilder
    private var homeStudyBeaconSection: some View {
        Group {
            switch homeStudyBeaconPresentation {
            case let .firstWinJourney(presentation):
                HomeFirstWinJourneyCard(
                    presentation: presentation,
                    reduceMotion: reduceMotion,
                    manageApps: {
                        isRestrictedAppsPresented = true
                    },
                    startProtection: prepareAndStartProtection
                )
                .transition(homeStudyBeaconTransition)

            case .weeklySignal:
                studyBeaconPanel
                    .transition(homeStudyBeaconTransition)
            }
        }
    }

    private var homeStudyBeaconPresentation: HomeStudyBeaconPresentation {
        let readiness = store.goal.map { store.checkpointReadiness(for: $0) }
            ?? .incomplete(
                selectableCount: 0,
                requiredCount: store.unlockPolicy.questionsPerSession
            )
        let isPreparingCheckpoint: Bool
        if case .preparing = readiness {
            isPreparingCheckpoint = true
        } else {
            isPreparingCheckpoint = false
        }
        let firstWinJourney = HomeFirstWinJourneyPresentation(
            hasReadyCheckpointSet: readiness.hasFullCheckpoint,
            isPreparingCheckpoint: isPreparingCheckpoint,
            isCheckpointBlockedByGeneration: store.isQuestionGenerationBlockingPractice,
            selectableQuestionCount: readiness.selectableCount,
            requiredQuestionCount: readiness.requiredCount,
            authorizationState: screenTime.authorizationState,
            setupState: screenTime.setupState,
            hasSelection: screenTime.hasSelection,
            isProtectionActive: isHealthyProtectionState,
            isStartingProtection: workflow.isStartingProtection,
            protectionErrorMessage: screenTime.userFacingErrorMessage,
            protectedAppsSummary: screenTime.restrictedAppsSummary,
            requiredCorrectAnswers: store.unlockPolicy.requiredCorrectAnswers,
            questionCount: store.unlockPolicy.questionsPerSession,
            unlockMinutes: store.unlockPolicy.unlockMinutes
        )

        return HomeStudyBeaconPresentation(
            hasPracticeForActiveGoal: !store.activeAttempts.isEmpty,
            firstWinJourney: firstWinJourney
        )
    }

    private var homeStudyBeaconTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.985))
    }

    private var homeNextFocusPanel: some View {
        Group {
            if let focusState = store.studyFocusState {
                let target = store.goal.flatMap {
                    ProgressSkillEvidenceRoutingPolicy.target(
                        for: focusState,
                        goalID: $0.id
                    )
                }

                switch focusState {
                case .recommendation, .awaitingQuestion, .caughtUp:
                    StudyFocusCard(state: focusState, style: .compact) {
                        guard let target else { return }
                        navigateToProgressSkillEvidence(target)
                    }
                    .transition(homeNextFocusTransition)
                }
            }
        }
        .animation(
            CheckpointMotion.animation(
                CheckpointMotion.reveal,
                reduceMotion: reduceMotion
            ),
            value: store.studyFocusState
        )
    }

    private var homeNextFocusTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.985))
    }

    private var activeBreakCard: some View {
        HomeActiveBreakCard(
            startedAt: store.unlockSession?.startedAt,
            expiresAt: activeBreakExpiration,
            relockReadiness: activeBreakRelockReadiness,
            areProtectedAppsAvailable: screenTime.setupState == .temporarilyUnlocked,
            protectedAppsSummary: screenTime.restrictedAppsSummary,
            revealTrigger: earnedBreakRevealSequence,
            reduceMotionOverride: reduceMotion
        ) {
            isRestrictedAppsPresented = true
        } endBreakEarly: {
            workflow.endBreakEarly()
        }
        .id(ScrollAnchor.activeBreak)
    }

    private var homeActiveBreakTransition: AnyTransition {
        HomeActiveBreakMotionPolicy(reduceMotion: reduceMotion).transition
    }

    private var activeBreakExpiration: Date? {
        SharedAppGroup.unlockExpiration ?? store.unlockSession?.expiresAt
    }

    private var activeBreakRelockReadiness: HomeActiveBreakRelockReadiness {
        HomeActiveBreakRelockReadiness.resolve(
            hasRequiredScreenTimeAuthorization: screenTime.hasRequiredScreenTimeAuthorization,
            hasSelection: screenTime.hasSelection,
            hasReadyCheckpointSet: store.hasReadyCheckpointSet,
            sharedCheckpointReady: SharedAppGroup.checkpointReady
        )
    }

    private var screenTimePanel: some View {
        SectionPanel("Protected apps") {
            VStack(alignment: .leading, spacing: 12) {
                Text(screenTime.restrictedAppsSummary)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if screenTime.isShieldingEnabled {
                    HStack(spacing: 10) {
                        HomeProtectionActionButton(title: "Change apps", systemImage: "checklist") {
                            isRestrictedAppsPresented = true
                        }

                        StatusBadge(text: "Protection on", tint: CheckpointTheme.teal)
                    }

                    screenTimeErrorMessage
                } else {
                    screenTimeErrorMessage

                    switch screenTime.setupState {
                    case .notStarted, .failed:
                        PrimaryActionButton(title: "Set up app protection", systemImage: "shield") {
                            isRestrictedAppsPresented = true
                        }
                    case .authorized:
                        if screenTime.hasSelection {
                            PrimaryActionButton(
                                title: workflow.isStartingProtection ? "Checking checkpoint" : "Start protection",
                                systemImage: "shield",
                                isLoading: workflow.isStartingProtection
                            ) {
                                prepareAndStartProtection()
                            }
                            .disabled(workflow.isStartingProtection || store.isPreparingActiveGoalQuestions)

                            if !store.hasReadyCheckpointSet {
                                Text("Protection turns on only after a full checkpoint is ready, so you can always earn access to your apps.")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            PrimaryActionButton(title: "Choose apps", systemImage: "checklist") {
                                isRestrictedAppsPresented = true
                            }
                        }
                    case .unavailable:
                        EmptyView()
                    case .shieldActive, .temporarilyUnlocked:
                        EmptyView()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var screenTimeErrorMessage: some View {
        if let errorMessage = screenTime.userFacingErrorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var compactProtectionRow: some View {
        Button {
            isRestrictedAppsPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 40, height: 40)
                    .background(CheckpointTheme.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Protection on")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)

                    Text(screenTime.restrictedAppsSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CheckpointTheme.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text("Manage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(CheckpointTheme.panelRaised.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(CheckpointPressButtonStyle(role: .surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protection on. \(screenTime.restrictedAppsSummary)")
        .accessibilityHint("Manage protected apps")
    }

    private var emptyState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Begin with one goal.")
                    .font(.title2.bold())
                    .foregroundStyle(CheckpointTheme.text)

                Text("Checkpoint will prepare short practice sets for that goal and place them before the apps you want to use more intentionally.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryActionButton(title: "Create goal", systemImage: "plus") {
                    store.presentGoalProfileCreator()
                }
            }
        }
    }

    private func handleQuestionRefreshOnActivation() {
        guard refreshesQuestionsOnActivation else { return }

        let now = Date()
        if let lastActivationRefreshAt,
           now.timeIntervalSince(lastActivationRefreshAt) < Self.activationRefreshDebounceInterval {
            return
        }
        lastActivationRefreshAt = now

        Task {
            _ = await store.refreshQuestionBatchIfNeeded()
            await store.prepareProtectionReviewQuestionBankIfNeeded()
        }
    }

    private var goalIdentityMotionPolicy: GoalIdentityMotionPolicy {
        GoalIdentityMotionPolicy(reduceMotion: reduceMotion)
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? accessibilityReduceMotion
    }

    private var usesCompactFirstWinHomeLayout: Bool {
        guard homeStudyBeaconPresentation.kind == .firstWinJourney else {
            return false
        }

        return dynamicTypeSize == .xSmall ||
            dynamicTypeSize == .small ||
            dynamicTypeSize == .medium ||
            dynamicTypeSize == .large
    }

    private func usesCompactHomeMargins(viewportWidth: CGFloat) -> Bool {
        usesCompactFirstWinHomeLayout || (
            homeStudyBeaconPresentation.kind == .weeklySignal &&
                HomeWeeklySignalLayoutPolicy.usesCompactHomeMargins(
                    viewportWidth: viewportWidth
                )
        )
    }

    private func homeHorizontalMargin(viewportWidth: CGFloat) -> CGFloat {
        usesCompactHomeMargins(viewportWidth: viewportWidth) ? 16 : 24
    }

    private func homeTopMargin(viewportWidth: CGFloat) -> CGFloat {
        if usesCompactFirstWinHomeLayout {
            return 8
        }
        return usesCompactHomeMargins(viewportWidth: viewportWidth) ? 12 : 20
    }

    private func homeSectionSpacing(viewportWidth: CGFloat) -> CGFloat {
        usesCompactHomeMargins(viewportWidth: viewportWidth) ? 16 : 24
    }

    private var referenceDate: Date {
        referenceDateOverride ?? liveReferenceDate
    }

    private func refreshDeadlineReferenceDate() {
        guard referenceDateOverride == nil else { return }
        liveReferenceDate = Date()
    }

    private func retryInitialQuestionGeneration() {
        Task {
            guard !isRetryingInitialQuestions else { return }
            isRetryingInitialQuestions = true
            await store.retryInitialQuestionGeneration()
            isRetryingInitialQuestions = false
        }
    }

    private func prepareAndStartProtection() {
        Task {
            if !store.hasReadyCheckpointSet {
                suppressedQuestionReadyGoalID = store.goal?.id
            }

            let didStart = await workflow.startProtection()
            if !didStart,
               !store.isPreparingActiveGoalQuestions,
               !store.hasReadyCheckpointSet {
                suppressedQuestionReadyGoalID = nil
            }
        }
    }

    private func deliverPendingProtectionStartResultIfPossible() {
        guard let result = ProtectionStartResultDelivery.takeCurrent(
            from: workflow,
            isOwner: ownsQuestionReadinessFeedback,
            currentGoalID: store.goal?.id,
            isShieldingEnabled: screenTime.isShieldingEnabled,
            protectionShouldRemainActive: SharedAppGroup.desiredShieldActive,
            checkpointNotice: store.checkpointNotice,
            protectionErrorMessage: screenTime.userFacingErrorMessage
        ) else { return }

        protectionStartErrorFeedback.recordDeliveredResult(result)
        AccessibilityNotification.Announcement(
            ProtectionStartResultAnnouncement.message(for: result)
        ).post()
    }

    private func announceOrQueue(_ request: AccessibilityAnnouncementRequest) {
        guard let request = accessibilityAnnouncementQueue.submit(
            request,
            isOwner: ownsQuestionReadinessFeedback
        ) else { return }
        AccessibilityNotification.Announcement(request.message).post()
    }

    private func deliverPendingAccessibilityAnnouncement() {
        guard let request = accessibilityAnnouncementQueue.takePending(
            isOwner: ownsQuestionReadinessFeedback
        ), accessibilityAnnouncementIsCurrent(request) else { return }

        if case .goalReady = request.context {
            presentQuestionsReadyConfirmation()
        }
        AccessibilityNotification.Announcement(request.message).post()
    }

    private func accessibilityAnnouncementIsCurrent(
        _ request: AccessibilityAnnouncementRequest
    ) -> Bool {
        switch request.context {
        case let .goalReady(goalID):
            store.goal?.id == goalID && store.hasReadyCheckpointSet
        case let .screenTimeError(message):
            screenTime.userFacingErrorMessage == message
        case .settingsProtectionState, .settingsMessage:
            false
        }
    }

    private var isTemporarilyUnblocked: Bool {
        SharedAppGroup.desiredShieldActive &&
            (screenTime.setupState == .temporarilyUnlocked || store.activeUnlockMinutesRemaining > 0)
    }

    private var isHealthyProtectionState: Bool {
        screenTime.isShieldingEnabled &&
            !isTemporarilyUnblocked &&
            screenTime.userFacingErrorMessage == nil
    }
}
