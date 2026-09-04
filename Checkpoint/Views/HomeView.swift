import Accessibility
import SwiftUI

struct HomeView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let workflow: CheckpointWorkflowCoordinator
    private let refreshesQuestionsOnActivation: Bool
    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.checkpointGoalSelection) private var selectGoal
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRestrictedAppsPresented = false
    @State private var isWeeklyReviewPresented = false
    @State private var isAcceptingLevelIncrease = false
    @State private var isRetryingInitialQuestions = false
    @State private var isQuestionsReadyConfirmationVisible = false
    @State private var questionsReadyConfirmationDismissTask: Task<Void, Never>?
    @State private var lastActivationRefreshAt: Date?

    private static let activationRefreshDebounceInterval: TimeInterval = 20
    private static let questionsReadyConfirmationText = "Your questions are ready."
    private static let questionsReadyConfirmationDurationNanoseconds: UInt64 = 4_000_000_000

    init(
        store: CheckpointStore,
        screenTime: ScreenTimeController,
        workflow: CheckpointWorkflowCoordinator,
        refreshesQuestionsOnActivation: Bool = true,
        reduceMotionOverride: Bool? = nil
    ) {
        self.store = store
        self.screenTime = screenTime
        self.workflow = workflow
        self.refreshesQuestionsOnActivation = refreshesQuestionsOnActivation
        self.reduceMotionOverride = reduceMotionOverride
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
                handleQuestionRefreshOnActivation()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    handleQuestionRefreshOnActivation()
                }
            }
            .onChange(of: questionPreparationSnapshot) { previous, current in
                guard previous.goalID == current.goalID else {
                    hideQuestionsReadyConfirmation()
                    return
                }

                if previous.isPreparing,
                   !current.isPreparing,
                   current.hasReadyCheckpointSet {
                    showQuestionsReadyConfirmation()
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
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    currentFocusIdentity
                    Spacer(minLength: 12)
                    goalSwitcherMenu(currentGoal: goal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    currentFocusIdentity
                    goalSwitcherMenu(currentGoal: goal)
                }
            }

            Text(goal.title)
                .font(.title2.bold())
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            dueDateLabel(goal.deadline)

            Text("\(store.unlockPolicy.requiredCorrectAnswers) of \(store.unlockPolicy.questionsPerSession) to unlock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)

            if store.isPreparingActiveGoalQuestions {
                questionPreparationStatus(for: goal)
                .padding(12)
                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 12))
            } else if store.isQuestionGenerationBlockingPractice {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CheckpointTheme.amber)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.lastQuestionGenerationFailure?.title ?? "Questions aren't ready")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(CheckpointTheme.text)

                            Text(store.questionGenerationStatusText)
                                .font(.footnote)
                                .foregroundStyle(CheckpointTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            questionRecoveryActions
                        }

                        VStack(spacing: 10) {
                            questionRecoveryActions
                        }
                    }
                }
                .padding(12)
                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 12))
            } else if isQuestionsReadyConfirmationVisible {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                        .accessibilityHidden(true)

                    Text(Self.questionsReadyConfirmationText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)

                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Self.questionsReadyConfirmationText)
                .transition(questionsReadyConfirmationTransition)
            }
        }
        .padding(.horizontal, 4)
    }

    private var currentFocusIdentity: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 36, height: 36)
                .background(CheckpointTheme.teal.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            Text("CURRENT FOCUS")
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityAddTraits(.isHeader)
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
                GoalSwitcherCapsuleLabel()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch goal")
            .accessibilityValue(currentGoal.title)
            .accessibilityHint("Changes the active goal throughout Checkpoint")
        }
    }

    private func questionPreparationStatus(for goal: Goal) -> some View {
        let readiness = store.checkpointReadiness(for: goal)
        let selectableCount = readiness.selectableCount
        let requiredCount = readiness.requiredCount

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(CheckpointTheme.teal)

                Text(store.questionGenerationStatusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProgressView(
                value: Double(selectableCount),
                total: Double(max(1, requiredCount))
            )
            .tint(CheckpointTheme.teal)

            Text("\(selectableCount) of \(requiredCount) checkpoint questions ready")
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(store.questionGenerationStatusText) \(selectableCount) of \(requiredCount) checkpoint questions ready."
        )
    }

    private func dueDateLabel(_ deadline: Date) -> some View {
        Text("Due \(deadline.formatted(.dateTime.month(.abbreviated).day()))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.muted)
            .lineLimit(1)
    }

    @ViewBuilder
    private var questionRecoveryActions: some View {
        if store.lastQuestionGenerationFailure?.allowsRetryWithoutChanges != false {
            SecondaryActionButton(
                title: isRetryingInitialQuestions ? "Trying again" : "Try again",
                systemImage: "arrow.clockwise"
            ) {
                retryInitialQuestionGeneration()
            }
            .disabled(isRetryingInitialQuestions)
        }

        if store.lastQuestionGenerationFailure?.allowsEditingTopics == true {
            SecondaryActionButton(title: "Edit topics", systemImage: "pencil") {
                store.presentActiveGoalEditor()
            }
        }
    }

    private var questionPreparationSnapshot: QuestionPreparationSnapshot {
        QuestionPreparationSnapshot(
            goalID: store.goal?.id,
            isPreparing: store.isPreparingActiveGoalQuestions,
            hasReadyCheckpointSet: store.hasReadyCheckpointSet
        )
    }

    private var questionsReadyConfirmationTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.98))
    }

    private func showQuestionsReadyConfirmation() {
        questionsReadyConfirmationDismissTask?.cancel()
        setQuestionsReadyConfirmationVisible(true)
        AccessibilityNotification.Announcement(Self.questionsReadyConfirmationText).post()

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
                switch focusState {
                case .recommendation, .awaitingQuestion, .caughtUp:
                    homeStudyFocusCard(focusState)
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

    private func homeStudyFocusCard(_ state: StudyFocusState) -> some View {
        let tint = state.isRecommendation ? CheckpointTheme.blue : CheckpointTheme.teal

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    homeStudyFocusIcon(systemImage: state.systemImage, tint: tint)
                    homeStudyFocusCopy(state: state, tint: tint)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    homeStudyFocusIcon(systemImage: state.systemImage, tint: tint)
                    homeStudyFocusCopy(state: state, tint: tint)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }

    private func homeStudyFocusIcon(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private func homeStudyFocusCopy(state: StudyFocusState, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("NEXT FOCUS")
                .font(.caption2.weight(.bold))
                .tracking(0.85)
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(state.detail)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
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
            await workflow.startProtection()
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
