import Accessibility
import SwiftUI

struct HomeView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let workflow: CheckpointWorkflowCoordinator
    private let refreshesQuestionsOnActivation: Bool
    private let reduceMotionOverride: Bool?
    private let referenceDateOverride: Date?
    private let isVisible: Bool
    private let isSceneActive: Bool
    private let isCoveredByParentModal: Bool
    private let parentModalOwnsQuestionReadiness: Bool
    private let parentModalOwnsProtectionErrors: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.checkpointGoalSelection) private var selectGoal
    @Environment(\.checkpointProgressSkillEvidenceNavigation)
    private var navigateToProgressSkillEvidence
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRestrictedAppsPresented = false
    @State private var isWeeklyReviewPresented = false
    @State private var isAcceptingLevelIncrease = false
    @State private var isRetryingInitialQuestions = false
    @State private var isQuestionsReadyConfirmationVisible = false
    @State private var questionsReadyConfirmationDismissTask: Task<Void, Never>?
    @State private var lastActivationRefreshAt: Date?
    @State private var liveReferenceDate = Date()
    @State private var accessibilityAnnouncementQueue = AccessibilityAnnouncementDeliveryQueue()
    @State private var protectionStartErrorFeedback = ProtectionStartErrorFeedbackState()
    @State private var suppressedQuestionReadyGoalID: Goal.ID?

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
        isVisible: Bool = true,
        isSceneActive: Bool = true,
        isCoveredByParentModal: Bool = false,
        parentModalOwnsQuestionReadiness: Bool = false,
        parentModalOwnsProtectionErrors: Bool = false
    ) {
        self.store = store
        self.screenTime = screenTime
        self.workflow = workflow
        self.refreshesQuestionsOnActivation = refreshesQuestionsOnActivation
        self.reduceMotionOverride = reduceMotionOverride
        referenceDateOverride = referenceDate
        self.isVisible = isVisible
        self.isSceneActive = isSceneActive
        self.isCoveredByParentModal = isCoveredByParentModal
        self.parentModalOwnsQuestionReadiness = parentModalOwnsQuestionReadiness
        self.parentModalOwnsProtectionErrors = parentModalOwnsProtectionErrors
    }

    private struct QuestionPreparationSnapshot: Equatable {
        let goalID: Goal.ID?
        let isPreparing: Bool
        let hasReadyCheckpointSet: Bool
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    checkpointNoticePanel

                    if let goal = store.goal {
                        goalScopedContent(goal)
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
                    value: homeStudyBeaconPresentation
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
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 112)
            }
            .checkpointScreenBackground()
            .navigationTitle("Checkpoint")
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $isRestrictedAppsPresented) {
                RestrictedAppsView(screenTime: screenTime)
            }
            .sheet(isPresented: $isWeeklyReviewPresented) {
                WeeklyReviewView(
                    store: store,
                    initialMetricsID: (store.weeklyActiveGoalMetrics ?? store.weeklyTotalMetrics).id
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
                      !isRestrictedAppsPresented else { return }
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
            .onDisappear {
                hideQuestionsReadyConfirmation()
            }
        }
    }

    private func goalScopedContent(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if isTemporarilyUnblocked {
                activeBreakCard
                    .transition(homeActiveBreakTransition)
                goalHero(goal)
                homeNextFocusPanel
                homeStudyBeaconSection
            } else {
                goalHero(goal)

                if homeStudyBeaconPresentation.showsNextFocus {
                    homeNextFocusPanel
                        .transition(homeNextFocusTransition)
                }

                if isHealthyProtectionState {
                    homeStudyBeaconSection

                    if homeStudyBeaconPresentation == .weeklySignal {
                        compactProtectionRow
                    }
                } else {
                    screenTimePanel
                    homeStudyBeaconSection
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
            readyDisclosure: homeStudyBeaconPresentation == .firstCheckpointLaunchpad
                ? .suppressedByFirstCheckpointLaunchpad
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
            .buttonStyle(.plain)
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
        if reduceMotion {
            isQuestionsReadyConfirmationVisible = isVisible
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isQuestionsReadyConfirmationVisible = isVisible
            }
        }
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
            isCoveredByLocalPresentation: isRestrictedAppsPresented
                || isWeeklyReviewPresented
        )
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
            .buttonStyle(.plain)
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
        let metrics = store.weeklyActiveGoalMetrics ?? store.weeklyTotalMetrics

        return LightStudyBeaconSection(
            metrics: metrics,
            competencies: store.activeProgressCompetencies,
            insight: metrics.weeklySignalInsight
        ) {
            isWeeklyReviewPresented = true
        }
    }

    @ViewBuilder
    private var homeStudyBeaconSection: some View {
        Group {
            switch homeStudyBeaconPresentation {
            case .firstCheckpointLaunchpad:
                HomeFirstCheckpointLaunchpad(
                    requiredCorrectAnswers: store.unlockPolicy.requiredCorrectAnswers,
                    questionCount: store.unlockPolicy.questionsPerSession,
                    unlockMinutes: store.unlockPolicy.unlockMinutes,
                    protectedAppsSummary: screenTime.restrictedAppsSummary
                ) {
                    isRestrictedAppsPresented = true
                }
                .transition(homeStudyBeaconTransition)

            case .weeklySignal:
                studyBeaconPanel
                    .transition(homeStudyBeaconTransition)
            }
        }
    }

    private var homeStudyBeaconPresentation: HomeStudyBeaconPresentation {
        HomeStudyBeaconPresentation(
            hasPracticeForActiveGoal: !store.activeAttempts.isEmpty,
            hasReadyCheckpointSet: store.hasReadyCheckpointSet,
            isProtectionActive: isHealthyProtectionState
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
            protectedAppsSummary: screenTime.restrictedAppsSummary
        ) {
            isRestrictedAppsPresented = true
        } endBreakEarly: {
            workflow.endBreakEarly()
        }
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
        .buttonStyle(.plain)
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
