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
                WeeklyReviewView(store: store)
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

private struct WeeklyImpactInsight {
    var text: String
    var systemImage: String
    var tint: Color
}

private struct StudyBeaconStat: Identifiable {
    var id: String { label }
    var value: String
    var label: String
    var tint: Color
}

private struct LightStudyBeaconSection: View {
    var metrics: WeeklyMetricsSummary
    var competencies: [TopicCompetency]
    var insight: WeeklyImpactInsight?
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 14) {
            HStack {
                Text("THIS WEEK")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(CheckpointTheme.muted)

                Spacer()

                if metrics.hasWeeklyReviewActivity {
                    Button(action: action) {
                        HStack(spacing: 5) {
                            Text("Review")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens weekly review")
                }
            }

            LightStudyBeacon(
                competencies: Array(competencies.prefix(6)),
                size: dynamicTypeSize.isAccessibilitySize ? 122 : 160
            )

            primaryMetric

            if !supportingStats.isEmpty {
                impactStats
            }

            if let insight {
                Button(action: action) {
                    HStack(spacing: 11) {
                        Image(systemName: insight.systemImage)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(insight.tint)
                            .frame(width: 36, height: 36)
                            .background(insight.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("WEEKLY INSIGHT")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.65)
                                .foregroundStyle(insight.tint)

                            Text(insight.text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .multilineTextAlignment(.leading)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CheckpointTheme.muted)
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .background(
                        CheckpointTheme.panelRaised.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens weekly review")
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var primaryMetric: some View {
        if let headline {
            VStack(spacing: 1) {
                Text(headline.value)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundStyle(CheckpointTheme.text)
                    .monospacedDigit()

                Text(headline.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.85)
                    .foregroundStyle(CheckpointTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 3) {
                Text("Ready")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(CheckpointTheme.text)

                Text("YOUR FIRST CHECKPOINT LIGHTS THE BEACON")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.75)
                    .foregroundStyle(CheckpointTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var impactStats: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(supportingStats) { stat in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(stat.value)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(stat.tint)
                            .monospacedDigit()

                        Text(stat.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(CheckpointTheme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 14) {
                ForEach(Array(supportingStats.enumerated()), id: \.element.id) { index, stat in
                    if index > 0 {
                        Rectangle()
                            .fill(CheckpointTheme.hairline)
                            .frame(width: 1, height: 38)
                            .accessibilityHidden(true)
                    }

                    VStack(spacing: 2) {
                        Text(stat.value)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(stat.tint)
                            .monospacedDigit()

                        Text(stat.label.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.45)
                            .foregroundStyle(CheckpointTheme.muted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var headline: (value: String, label: String)? {
        if metrics.questionsAnswered > 0 {
            return (
                "\(metrics.questionsAnswered)",
                metrics.questionsAnswered == 1 ? "question this week" : "questions this week"
            )
        }

        if metrics.checkpointsCleared > 0 {
            return (
                "\(metrics.checkpointsCleared)",
                metrics.checkpointsCleared == 1 ? "checkpoint this week" : "checkpoints this week"
            )
        }

        if metrics.checkpointStreakDays > 0 {
            return (metrics.checkpointStreakText, "checkpoint streak")
        }

        return nil
    }

    private var supportingStats: [StudyBeaconStat] {
        var stats: [StudyBeaconStat] = []

        if metrics.questionsAnswered > 0 {
            stats.append(
                StudyBeaconStat(
                    value: metrics.questionsAnswered >= 5
                        ? metrics.accuracyText
                        : "\(metrics.correctAnswers) of \(metrics.questionsAnswered)",
                    label: "correct",
                    tint: CheckpointTheme.teal
                )
            )
        }

        if metrics.checkpointsCleared > 0 {
            stats.append(
                StudyBeaconStat(
                    value: "\(metrics.checkpointsCleared)",
                    label: metrics.checkpointsCleared == 1 ? "checkpoint" : "checkpoints",
                    tint: CheckpointTheme.blue
                )
            )
        }

        if metrics.checkpointStreakDays > 0 {
            stats.append(
                StudyBeaconStat(
                    value: "\(metrics.checkpointStreakDays)-day",
                    label: "streak",
                    tint: CheckpointTheme.coral
                )
            )
        }

        return Array(stats.prefix(3))
    }
}

private struct LightStudyBeacon: View {
    var competencies: [TopicCompetency]
    var size: CGFloat

    private let petalColors: [Color] = [
        Color(red: 0.20, green: 0.62, blue: 0.56),
        Color(red: 0.31, green: 0.49, blue: 0.73),
        Color(red: 0.88, green: 0.61, blue: 0.31),
        Color(red: 0.76, green: 0.37, blue: 0.34),
        Color(red: 0.40, green: 0.55, blue: 0.78),
        Color(red: 0.24, green: 0.66, blue: 0.60)
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CheckpointTheme.teal.opacity(0.13),
                            CheckpointTheme.blue.opacity(0.06),
                            .clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: size * 0.63
                    )
                )
                .frame(width: size * 1.18, height: size * 1.18)
                .blur(radius: 9)

            Circle()
                .stroke(CheckpointTheme.amber.opacity(0.18), lineWidth: 1)
                .frame(width: size * 0.94, height: size * 0.94)

            ForEach(0..<6, id: \.self) { index in
                beaconPetal(at: index)
            }

            Circle()
                .stroke(
                    CheckpointTheme.teal.opacity(0.14),
                    style: StrokeStyle(lineWidth: 1, dash: [1, 7])
                )
                .frame(width: size * 0.82, height: size * 0.82)

            Circle()
                .fill(CheckpointTheme.panel)
                .frame(width: size * 0.39, height: size * 0.39)
                .overlay(Circle().stroke(CheckpointTheme.teal.opacity(0.12), lineWidth: 1))
                .shadow(color: CheckpointTheme.teal.opacity(0.10), radius: 10, y: 6)

            Image(systemName: "scope")
                .font(.system(size: size * 0.16, weight: .medium))
                .foregroundStyle(CheckpointTheme.teal)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func beaconPetal(at index: Int) -> some View {
        let competency = competencies.indices.contains(index) ? competencies[index] : nil
        let opacity: Double

        if let competency {
            opacity = competency.attempts == 0
                ? 0.20
                : 0.42 + (Double(competency.masteryPercent) / 100 * 0.34)
        } else {
            opacity = 0.10
        }

        return Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        petalColors[index].opacity(opacity),
                        petalColors[index].opacity(opacity * 0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size * 0.18, height: size * 0.48)
            .offset(y: -size * 0.19)
            .rotationEffect(.degrees(Double(index) * 60))
            .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        guard !competencies.isEmpty else {
            return "Learning beacon. Skill map is being prepared."
        }

        let practiced = competencies.filter { $0.attempts > 0 }
        guard let strongest = practiced.max(by: { $0.masteryPercent < $1.masteryPercent }),
              let review = practiced.min(by: { $0.masteryPercent < $1.masteryPercent }) else {
            return "Learning beacon. \(competencies.count) skill areas ready for practice."
        }

        return "Learning beacon. \(competencies.count) skill areas. Strongest: \(strongest.topic). Review next: \(review.topic)."
    }
}

private struct HomeProtectionActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 10)
            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct BreakRemainingStat: View {
    var expiresAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.amber)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Break remaining")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)

                    Text("Protection restarts automatically when this ends.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(valueText(at: context.date))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(12)
            .background(CheckpointTheme.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func valueText(at date: Date) -> String {
        guard let expiresAt else { return "Ending" }

        let minutesRemaining = max(0, Int(ceil(expiresAt.timeIntervalSince(date) / 60)))
        guard minutesRemaining > 0 else { return "Ending" }
        return "\(minutesRemaining)m"
    }
}

private struct WeeklyReviewView: View {
    let store: CheckpointStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMetricsID = WeeklyMetricsSummary.allGoalsID

    private var metricOptions: [WeeklyMetricsSummary] {
        [store.weeklyTotalMetrics] + store.weeklyGoalMetrics
    }

    private var selectedMetrics: WeeklyMetricsSummary {
        metricOptions.first { $0.id == selectedMetricsID } ?? store.weeklyTotalMetrics
    }

    private var isAllGoalsSelected: Bool {
        selectedMetrics.id == WeeklyMetricsSummary.allGoalsID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if metricOptions.count > 2 {
                        scopeSelector
                    }
                    reviewHero
                    signalPanel
                    skillFocusPanel
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Weekly Review")
            .toolbarTitleDisplayMode(.inline)
            .onChange(of: metricOptions.map(\.id)) { _, availableIDs in
                if !availableIDs.contains(selectedMetricsID) {
                    selectedMetricsID = WeeklyMetricsSummary.allGoalsID
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly review")
                .font(.largeTitle.bold())
                .foregroundStyle(CheckpointTheme.text)

            Text("A quick look at this week's questions, breaks, and progress.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scopeSelector: some View {
        SectionPanel("Goal") {
            Menu {
                Button {
                    selectedMetricsID = WeeklyMetricsSummary.allGoalsID
                } label: {
                    Label(
                        "All goals",
                        systemImage: selectedMetricsID == WeeklyMetricsSummary.allGoalsID ? "checkmark.circle.fill" : "circle"
                    )
                }

                if !store.weeklyGoalMetrics.isEmpty {
                    Divider()
                }

                ForEach(store.weeklyGoalMetrics) { metrics in
                    Button {
                        selectedMetricsID = metrics.id
                    } label: {
                        Label(
                            metrics.title,
                            systemImage: selectedMetricsID == metrics.id ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Viewing")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)

                        Text(selectedMetrics.title)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CheckpointTheme.teal)
                }
                .padding(14)
                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewHero: some View {
        SectionPanel {
            let metrics = selectedMetrics

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    StatusBadge(text: isAllGoalsSelected ? "All goals" : "Goal", tint: CheckpointTheme.teal)

                    if metrics.checkpointStreakDays > 0 {
                        StatusBadge(text: "\(metrics.checkpointStreakText) streak", tint: CheckpointTheme.coral)
                    }
                }

                Text(heroTitle(for: metrics))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(heroDetail(for: metrics))
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var signalPanel: some View {
        SectionPanel("This week") {
            let metrics = selectedMetrics

            VStack(spacing: 10) {
                WeeklySignalRow(
                    title: "Questions answered",
                    value: "\(metrics.questionsAnswered)",
                    detail: nil,
                    systemImage: "checkmark.seal",
                    tint: CheckpointTheme.teal
                )

                WeeklySignalRow(
                    title: "Accuracy",
                    value: metrics.accuracyText,
                    detail: metrics.questionsAnswered > 0 ? "\(metrics.correctAnswers) correct, \(metrics.missedAnswers) to review" : "No answered questions yet",
                    systemImage: "target",
                    tint: CheckpointTheme.amber
                )

                WeeklySignalRow(
                    title: "Checkpoint streak",
                    value: metrics.checkpointStreakText,
                    detail: "Consecutive days with a cleared checkpoint",
                    systemImage: "flame",
                    tint: CheckpointTheme.coral
                )

                WeeklySignalRow(
                    title: "App breaks",
                    value: "\(metrics.checkpointsCleared)",
                    detail: "Breaks earned by passing a checkpoint",
                    systemImage: "shield.lefthalf.filled",
                    tint: CheckpointTheme.blue
                )
            }
        }
    }

    @ViewBuilder
    private var skillFocusPanel: some View {
        let metrics = selectedMetrics

        if metrics.strongestSkill != nil || metrics.reviewSkill != nil {
            SectionPanel("Skill focus") {
                VStack(spacing: 10) {
                    if let strongestSkill = metrics.strongestSkill {
                        WeeklySignalRow(
                            title: "Strengthening",
                            value: strongestSkill,
                            detail: "Your strongest topic this week",
                            systemImage: "star",
                            tint: CheckpointTheme.blue
                        )
                    }

                    if let reviewSkill = metrics.reviewSkill {
                        WeeklySignalRow(
                            title: "Review next",
                            value: reviewSkill,
                            detail: "The next skill worth another pass",
                            systemImage: "bookmark",
                            tint: CheckpointTheme.amber
                        )
                    }
                }
            }
        }
    }

    private func heroTitle(for metrics: WeeklyMetricsSummary) -> String {
        if metrics.questionsAnswered > 0 {
            return "\(metrics.questionsAnswered) questions answered this week."
        }

        if metrics.checkpointStreakDays > 0 {
            return "\(metrics.checkpointStreakText) checkpoint streak is still alive."
        }

        return "No weekly review yet."
    }

    private func heroDetail(for metrics: WeeklyMetricsSummary) -> String {
        if metrics.checkpointsCleared > 0 {
            let checkpointText = metrics.checkpointsCleared == 1 ? "1 app break" : "\(metrics.checkpointsCleared) app breaks"
            return "You earned \(checkpointText) by passing a checkpoint."
        }

        if metrics.questionsAnswered > 0 {
            return "Keep protection active to connect more app opens with practice."
        }

        if metrics.checkpointStreakDays > 0 {
            return "Clear a checkpoint this week to keep the streak moving."
        }

        return "Clear a checkpoint this week and your review will begin to fill in."
    }
}

private struct WeeklySignalRow: View {
    var title: String
    var value: String
    var detail: String?
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let detail {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .padding(12)
        .background(CheckpointTheme.panelRaised.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }
}
