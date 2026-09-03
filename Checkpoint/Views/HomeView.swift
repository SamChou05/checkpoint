import Accessibility
import SwiftUI

struct HomeView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let workflow: CheckpointWorkflowCoordinator

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
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
                        if isTemporarilyUnblocked {
                            screenTimePanel
                            goalHero(goal)
                            studyBeaconPanel
                        } else {
                            goalHero(goal)

                            if isHealthyProtectionState {
                                studyBeaconPanel
                                compactProtectionRow
                            } else {
                                screenTimePanel
                                studyBeaconPanel
                            }
                        }

                        levelRecommendationPanel
                    } else {
                        emptyState
                    }
                }
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

    @ViewBuilder
    private func goalHero(_ goal: Goal) -> some View {
        if store.isPreparingActiveGoalQuestions ||
            store.isQuestionGenerationBlockingPractice ||
            isQuestionsReadyConfirmationVisible {
            expandedGoalHero(goal)
        } else {
            compactGoalHeader(goal)
        }
    }

    @ViewBuilder
    private func compactGoalHeader(_ goal: Goal) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                compactGoalIdentity(goal)
                dueDateLabel(goal.deadline)
                    .padding(.leading, 47)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .center, spacing: 11) {
                compactGoalIdentity(goal)

                Spacer(minLength: 10)

                dueDateLabel(goal.deadline)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func compactGoalIdentity(_ goal: Goal) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "scope")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 36, height: 36)
                .background(CheckpointTheme.teal.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENT FOCUS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(CheckpointTheme.muted)

                compactGoalTitle(goal)
            }
        }
    }

    @ViewBuilder
    private func compactGoalTitle(_ goal: Goal) -> some View {
        if store.availableGoalProfiles.count > 1 {
            Menu {
                goalSwitcherMenuContent
            } label: {
                HStack(spacing: 5) {
                    Text(goal.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Current goal: \(goal.title)")
        } else {
            Text(goal.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func expandedGoalHero(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    currentFocusLabel(goal)
                    Spacer(minLength: 12)
                    dueDateLabel(goal.deadline)
                }

                VStack(alignment: .leading, spacing: 8) {
                    currentFocusLabel(goal)
                    dueDateLabel(goal.deadline)
                }
            }

            Text(goal.title)
                .font(.title2.bold())
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(store.unlockPolicy.requiredCorrectAnswers) of \(store.unlockPolicy.questionsPerSession) to unlock")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)

            if store.isPreparingActiveGoalQuestions {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(CheckpointTheme.teal)

                    Text(store.questionGenerationStatusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    @ViewBuilder
    private func currentFocusLabel(_ goal: Goal) -> some View {
        if store.availableGoalProfiles.count > 1 {
            currentGoalMenu(goal)
        } else {
            Text("CURRENT FOCUS")
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityAddTraits(.isHeader)
        }
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
        accessibilityReduceMotion
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
        if accessibilityReduceMotion {
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
            competencies: store.visibleActiveCompetencies,
            insight: weeklyImpactInsight(for: metrics)
        ) {
            isWeeklyReviewPresented = true
        }
    }

    private func weeklyImpactInsight(for metrics: WeeklyMetricsSummary) -> WeeklyImpactInsight? {
        guard metrics.hasWeeklyReviewActivity else { return nil }

        if metrics.missedAnswers > 0, let reviewSkill = metrics.reviewSkill {
            return WeeklyImpactInsight(
                text: "Review next: \(reviewSkill).",
                systemImage: "arrow.turn.down.right",
                tint: CheckpointTheme.amber
            )
        }

        if let focusRecommendation = store.studyFocusRecommendation {
            return WeeklyImpactInsight(
                text: focusRecommendation,
                systemImage: "bookmark.fill",
                tint: CheckpointTheme.amber
            )
        }

        if let strongestSkill = metrics.strongestSkill {
            return WeeklyImpactInsight(
                text: "Strengthening: \(strongestSkill).",
                systemImage: "sparkles",
                tint: CheckpointTheme.blue
            )
        }

        if metrics.checkpointsCleared > 0 {
            let noun = metrics.checkpointsCleared == 1 ? "checkpoint" : "checkpoints"
            return WeeklyImpactInsight(
                text: "\(metrics.checkpointsCleared) \(noun) cleared this week.",
                systemImage: "shield.checkered",
                tint: CheckpointTheme.blue
            )
        }

        if metrics.questionsAnswered > 0 {
            return WeeklyImpactInsight(
                text: "Your answers are starting to shape the skill map.",
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: CheckpointTheme.teal
            )
        }

        if metrics.checkpointStreakDays > 0 {
            return WeeklyImpactInsight(
                text: "Your \(metrics.checkpointStreakText) checkpoint streak is still going.",
                systemImage: "flame.fill",
                tint: CheckpointTheme.coral
            )
        }

        return nil
    }

    private var screenTimePanel: some View {
        SectionPanel("Protected apps") {
            VStack(alignment: .leading, spacing: 12) {
                Text(screenTime.restrictedAppsSummary)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if isTemporarilyUnblocked {
                    BreakRemainingStat(
                        expiresAt: store.unlockSession?.expiresAt ?? SharedAppGroup.unlockExpiration
                    )

                    HStack(spacing: 10) {
                        HomeProtectionActionButton(title: "Choose apps", systemImage: "checklist") {
                            isRestrictedAppsPresented = true
                        }

                        HomeProtectionActionButton(title: "End break early", systemImage: "shield") {
                            workflow.endBreakEarly()
                        }
                    }
                } else if screenTime.isShieldingEnabled {
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

    @ViewBuilder
    private func currentGoalMenu(_ goal: Goal) -> some View {
        Menu {
            goalSwitcherMenuContent
        } label: {
            HStack(spacing: 6) {
                Text("Current goal")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.teal)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current goal: \(goal.title)")
    }

    @ViewBuilder
    private var goalSwitcherMenuContent: some View {
        ForEach(store.availableGoalProfiles) { profile in
            Button {
                store.switchActiveGoal(to: profile.id)
            } label: {
                Label(
                    profile.title,
                    systemImage: profile.id == store.goal?.id ? "checkmark.circle.fill" : "circle"
                )
            }
        }

        Divider()

        if !store.isMember || !store.hasReachedGoalProfileLimit {
            Button {
                store.presentGoalProfileCreator()
            } label: {
                Label("New goal", systemImage: "plus")
            }
        }
    }

    private func handleQuestionRefreshOnActivation() {
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
