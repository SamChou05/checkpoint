import SwiftUI

struct HomeView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController

    @Environment(\.scenePhase) private var scenePhase
    @State private var isRestrictedAppsPresented = false
    @State private var isAcceptingLevelIncrease = false
    @State private var stopBlockingSession: CheckpointSession?
    @State private var stopBlockingMessage: String?
    @State private var isPreparingStopChallenge = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    checkpointNoticePanel

                    if let goal = store.goal {
                        goalHero(goal)
                        weeklyStatsPanel
                        studyAssistPanel
                        screenTimePanel
                    } else {
                        emptyState
                    }
                }
                .padding(20)
                .padding(.bottom, 56)
            }
            .padding(.bottom, 48)
            .checkpointScreenBackground()
            .navigationTitle("Checkpoint")
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $isRestrictedAppsPresented) {
                RestrictedAppsView(screenTime: screenTime)
            }
            .sheet(item: $stopBlockingSession) { session in
                CheckpointAttemptView(store: store, screenTime: screenTime, session: session)
            }
            .onAppear {
                handleQuestionRefreshOnActivation()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    handleQuestionRefreshOnActivation()
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Consistency compounds")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)

                Text("Practice toward the goal you chose.")
                    .font(.largeTitle.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(CheckpointTheme.blue)
                .frame(width: 48, height: 48)
                .background(CheckpointTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.top, 8)
    }

    private func goalHero(_ goal: Goal) -> some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    currentGoalMenu(goal)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Deadline: \(goal.deadline.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits)))")
                        Text(Goal.deadlineDistanceText(until: goal.deadline))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)
                    .lineLimit(1)
                }

                Text("Goal: \(goal.title)")
                    .font(.title2.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if let focusText = store.activeGoalFocusText {
                    Text("Focus: \(focusText)")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                StatusBadge(text: goal.difficultyLabel, tint: CheckpointTheme.amber)

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
                    .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                } else if store.questionBatchState == .failed {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CheckpointTheme.amber)

                        Text(store.questionGenerationStatusText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                }

                Text("Protected apps open after a short practice set: \(store.unlockPolicy.questionsPerSession) questions, \(store.unlockPolicy.requiredCorrectAnswers) correct to begin a break.")
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var studyAssistPanel: some View {
        let levelRecommendation = store.questionLevelRecommendation
        let focusRecommendation = store.studyFocusRecommendation

        if levelRecommendation != nil || focusRecommendation != nil {
            SectionPanel("Next step") {
                VStack(alignment: .leading, spacing: 12) {
                    if let levelRecommendation {
                        levelUpRecommendationCard(levelRecommendation)
                    }

                    if let focusRecommendation {
                        VStack(alignment: .leading, spacing: 10) {
                            StatusBadge(text: "Next focus", tint: CheckpointTheme.teal)

                            Text(focusRecommendation)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func levelUpRecommendationCard(_ recommendation: QuestionLevelRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBadge(text: "Ready for more depth", tint: CheckpointTheme.amber)

            Text("\(recommendation.accuracyPercent)% accuracy across \(recommendation.answeredCount) recent level \(recommendation.currentQuestionLevel) questions.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryActionButton(
                title: isAcceptingLevelIncrease ? "Preparing deeper questions" : "Raise question level",
                systemImage: "arrow.up.circle"
            ) {
                Task {
                    guard !isAcceptingLevelIncrease else { return }
                    isAcceptingLevelIncrease = true
                    await store.acceptQuestionLevelRecommendation()
                    isAcceptingLevelIncrease = false
                }
            }
            .disabled(isAcceptingLevelIncrease)
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

    private var weeklyStatsPanel: some View {
        SectionPanel("Weekly stats") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(
                    title: "Questions answered",
                    value: "\(store.questionsAnsweredThisWeekCount)",
                    tint: CheckpointTheme.teal,
                    systemImage: "checkmark.seal"
                )

                MetricTile(
                    title: "Question accuracy",
                    value: store.questionAccuracyThisWeekText,
                    tint: CheckpointTheme.amber,
                    systemImage: "arrow.triangle.2.circlepath"
                )

                MetricTile(
                    title: "Skill progress",
                    value: store.averageMasteryText,
                    tint: CheckpointTheme.blue,
                    systemImage: "chart.line.uptrend.xyaxis"
                )

                MetricTile(
                    title: "Break remaining",
                    value: "\(store.activeUnlockMinutesRemaining)m",
                    tint: CheckpointTheme.coral,
                    systemImage: "timer"
                )
            }
        }
    }

    private var screenTimePanel: some View {
        SectionPanel("Protected apps") {
            VStack(alignment: .leading, spacing: 12) {
                Text(screenTime.restrictedAppsSummary)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    SecondaryActionButton(title: "Choose protected apps", systemImage: "checklist") {
                        isRestrictedAppsPresented = true
                    }

                    if screenTime.isShieldingEnabled {
                        SecondaryActionButton(
                            title: isPreparingStopChallenge ? "Preparing review" : "Protection active",
                            systemImage: "shield.fill"
                        ) {
                            prepareStopBlockingChallenge()
                        }
                        .disabled(isPreparingStopChallenge)
                    } else if isTemporarilyUnblocked {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                StatusBadge(text: "Break in progress", tint: CheckpointTheme.amber)
                                Spacer()
                                Text("\(store.activeUnlockMinutesRemaining)m left")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.muted)
                            }

                            SecondaryActionButton(title: "End break early", systemImage: "shield") {
                                store.clearUnlockSession()
                                screenTime.applyShield()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        SecondaryActionButton(title: "Start protection", systemImage: "shield") {
                            screenTime.applyShield()
                        }
                    }
                }

                if let stopBlockingMessage {
                    Text(stopBlockingMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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

        if store.isMember && store.hasReachedGoalProfileLimit {
            Button {
                store.presentGoalProfileCreator()
            } label: {
                Label("\(store.goalProfileLimit) goal limit reached", systemImage: "checkmark.seal")
            }
            .disabled(true)
        } else {
            Button {
                store.presentGoalProfileCreator()
            } label: {
                Label("New goal", systemImage: "plus")
            }
        }
    }

    private func handleQuestionRefreshOnActivation() {
        Task {
            _ = await store.refreshQuestionBatchIfNeeded()
        }
    }

    private func prepareStopBlockingChallenge() {
        guard !isPreparingStopChallenge else { return }
        isPreparingStopChallenge = true

        Task {
            if let session = await store.prepareStopBlockingSession() {
                stopBlockingMessage = nil
                stopBlockingSession = session
            } else {
                stopBlockingMessage = store.checkpointNotice
            }
            isPreparingStopChallenge = false
        }
    }

    private var isTemporarilyUnblocked: Bool {
        screenTime.setupState == .temporarilyUnlocked || store.activeUnlockMinutesRemaining > 0
    }
}
