import SwiftUI

struct SettingsView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let purchaseController: PurchaseController

    @State private var isRestrictedAppsPresented = false
    @State private var isHistoryPresented = false
    @State private var isQuestionReportsPresented = false
    @State private var isAdvancedExpanded = false
    @State private var advancedAction: AdvancedSettingsAction?
    @State private var previewCheckpointSession: CheckpointSession?
    @State private var previewCheckpointMessage: String?
    @State private var isPreparingPreviewCheckpoint = false
    @State private var stopBlockingSession: CheckpointSession?
    @State private var stopBlockingMessage: String?
    @State private var isPreparingStopChallenge = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Settings")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Tune the blocker, your study goal, and the checkpoint rules.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    SectionPanel("Plan") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(store.isPro ? "Checkpoint Pro" : "Checkpoint Free")
                                        .font(.headline)
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text(planSubtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(CheckpointTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                StatusBadge(
                                    text: store.subscriptionTier.displayName,
                                    tint: store.isPro ? CheckpointTheme.amber : CheckpointTheme.teal
                                )
                            }

                            if !store.isPro {
                                SecondaryActionButton(title: "View Pro", systemImage: "sparkles") {
                                    store.requestUpgrade(for: .largerQuestionBanks)
                                }
                            }
                        }
                    }

                    SectionPanel("Goals") {
                        if let goal = store.goal {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(goal.title)
                                            .font(.headline)
                                            .foregroundStyle(CheckpointTheme.text)

                                        Text("Focus: \(goal.focusAreas.isEmpty ? "next meaningful rep" : goal.focusAreas)")
                                            .font(.subheadline)
                                            .foregroundStyle(CheckpointTheme.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer()

                                    StatusBadge(text: goalCountText, tint: CheckpointTheme.teal)
                                }

                                Text("Question level: \(goal.difficultyLabel)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(spacing: 10) {
                            SecondaryActionButton(title: "Edit goal", systemImage: "pencil") {
                                store.presentActiveGoalEditor()
                            }

                            if store.canUse(.multipleGoals) {
                                SecondaryActionButton(title: "New goal", systemImage: "plus") {
                                    store.presentGoalProfileCreator()
                                }
                            }
                        }

                        if !store.canUse(.multipleGoals) {
                            ProLockedFeatureRow(feature: .multipleGoals) {
                                store.requestUpgrade(for: .multipleGoals)
                            }
                        }
                    }

                    SectionPanel("Activity") {
                        VStack(spacing: 14) {
                            SettingsNavigationRow(
                                title: "Checkpoint history",
                                detail: historyDetailText,
                                systemImage: "clock.arrow.circlepath",
                                trailingText: "\(store.activeAttempts.count)"
                            ) {
                                isHistoryPresented = true
                            }

                            Divider()

                            SettingsNavigationRow(
                                title: "Question reports",
                                detail: questionReportsDetailText,
                                systemImage: "exclamationmark.bubble",
                                trailingText: "\(store.reportedQuestionCount)"
                            ) {
                                isQuestionReportsPresented = true
                            }
                        }
                    }

                    SectionPanel("App blocking") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Connection")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text(screenTime.setupState.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            Text(screenTime.restrictedAppsSummary)
                                .font(.footnote)
                                .foregroundStyle(CheckpointTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            if shouldShowScreenTimeAuthorizationButton {
                                SecondaryActionButton(title: "Allow Screen Time", systemImage: "shield") {
                                    Task {
                                        await screenTime.requestAuthorization()
                                    }
                                }
                            }

                            SecondaryActionButton(title: "Choose blocked apps", systemImage: "checklist") {
                                isRestrictedAppsPresented = true
                            }

                            if let message = screenTime.lastErrorMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.coral)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    SectionPanel("Checkpoint rules") {
                        VStack(alignment: .leading, spacing: 16) {
                            if !store.canUse(.advancedStrictness) {
                                ProLockedFeatureRow(feature: .advancedStrictness) {
                                    store.requestUpgrade(for: .advancedStrictness)
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Passing score")
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("\(store.unlockPolicy.requiredCorrectAnswers) of \(store.unlockPolicy.questionsPerSession) correct to unlock")
                                    .font(.subheadline)
                                    .foregroundStyle(CheckpointTheme.muted)

                                Stepper(
                                    "Questions per checkpoint: \(store.unlockPolicy.questionsPerSession)",
                                    value: questionsPerSessionBinding,
                                    in: UnlockPolicy.minimumQuestionsPerSession...UnlockPolicy.maximumQuestionsPerSession
                                )
                                    .foregroundStyle(CheckpointTheme.text)
                                    .disabled(!store.canUse(.advancedStrictness))
                                    .opacity(store.canUse(.advancedStrictness) ? 1 : 0.48)

                                Stepper(
                                    "Correct answers needed: \(store.unlockPolicy.requiredCorrectAnswers)",
                                    value: requiredCorrectAnswersBinding,
                                    in: UnlockPolicy.minimumRequiredCorrectAnswers...store.unlockPolicy.questionsPerSession
                                )
                                    .foregroundStyle(CheckpointTheme.text)
                                    .disabled(!store.canUse(.advancedStrictness))
                                    .opacity(store.canUse(.advancedStrictness) ? 1 : 0.48)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Unlock time after passing")
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Picker("Unlock minutes", selection: unlockMinutesBinding) {
                                    ForEach(UnlockPolicy.correctAnswerUnlockMinuteOptions, id: \.self) { minutes in
                                        Text("\(minutes)m").tag(minutes)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Emergency pass")
                                        .font(.headline)
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text("\(store.emergencyPassesRemaining) remaining this week")
                                        .font(.subheadline)
                                        .foregroundStyle(CheckpointTheme.muted)

                                    if !screenTime.isShieldingEnabled {
                                        Text("Available while blocking is active")
                                            .font(.footnote)
                                            .foregroundStyle(CheckpointTheme.muted)
                                    }
                                }

                                Spacer()

                                Button {
                                    let unlockMinutes = store.useEmergencyPass()
                                    screenTime.temporarilyUnshield(minutes: unlockMinutes)
                                } label: {
                                    Image(systemName: "cross.case")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(CheckpointTheme.paper)
                                        .frame(width: 42, height: 42)
                                        .background(CheckpointTheme.amber, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(store.emergencyPassesRemaining == 0 || !screenTime.isShieldingEnabled)
                            }
                        }
                    }

                    SectionPanel("Advanced") {
                        DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Blocking diagnostics")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text(screenTime.shieldExtensionDiagnosticsText)
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Text("Stopping blocking is intentionally tucked away so app-open moments still point back to a checkpoint. To turn it off, clear a 10-question challenge with at least 9 correct.")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)

                                SecondaryActionButton(title: isPreparingPreviewCheckpoint ? "Preparing preview" : "Preview checkpoint", systemImage: "play.fill") {
                                    prepareCheckpointPreview()
                                }
                                .disabled(store.goal == nil || isPreparingPreviewCheckpoint)
                                .opacity(store.goal == nil ? 0.48 : 1)

                                if let previewCheckpointMessage {
                                    Text(previewCheckpointMessage)
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                SecondaryActionButton(title: isPreparingStopChallenge ? "Preparing stop challenge" : "Stop blocking", systemImage: "hand.raised") {
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
                                .disabled(!canStopBlocking || isPreparingStopChallenge)
                                .opacity(canStopBlocking ? 1 : 0.48)

                                if let stopBlockingMessage {
                                    Text(stopBlockingMessage)
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                SecondaryActionButton(title: "Reset app data", systemImage: "arrow.counterclockwise") {
                                    advancedAction = .resetData
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Text("Troubleshooting and reset")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                        }
                        .tint(CheckpointTheme.teal)
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $isRestrictedAppsPresented) {
                RestrictedAppsView(screenTime: screenTime)
            }
            .sheet(isPresented: $isHistoryPresented) {
                HistoryView(store: store)
            }
            .sheet(isPresented: $isQuestionReportsPresented) {
                QuestionReportsView(store: store)
            }
            .sheet(item: $advancedAction) { action in
                AdvancedConfirmationView(action: action, store: store, screenTime: screenTime)
            }
            .sheet(item: $previewCheckpointSession) { session in
                CheckpointAttemptView(store: store, screenTime: screenTime, session: session)
            }
            .sheet(item: $stopBlockingSession) { session in
                CheckpointAttemptView(store: store, screenTime: screenTime, session: session)
            }
            .sheet(
                item: Binding(
                    get: { store.pendingPaywallFeature },
                    set: { feature in
                        if feature == nil {
                            store.dismissPaywall()
                        }
                    }
                )
            ) { feature in
                PaywallView(
                    feature: feature,
                    store: store,
                    purchaseController: purchaseController
                )
            }
        }
    }

    private var canStopBlocking: Bool {
        screenTime.isShieldingEnabled || screenTime.setupState == .temporarilyUnlocked
    }

    private var shouldShowScreenTimeAuthorizationButton: Bool {
        screenTime.setupState == .notStarted || screenTime.setupState == .failed
    }

    private var planSubtitle: String {
        if store.isPro {
            return "Extra question variety, adaptive guidance, and custom checkpoint rules are active."
        }

        return "Free keeps the blocker loop usable with one goal and automatic checkpoint preparation."
    }

    private var goalCountText: String {
        let count = store.availableGoalProfiles.count
        return count == 1 ? "1 goal" : "\(count) goals"
    }

    private var historyDetailText: String {
        if store.activeAttempts.isEmpty {
            return "No checkpoint answers yet"
        }

        return "\(store.questionsAnsweredThisWeekCount) answered this week"
    }

    private var questionReportsDetailText: String {
        if store.reportedQuestionCount == 0 {
            return "Flag confusing or incorrect questions"
        }

        return "\(store.reportedQuestionCount) submitted"
    }

    private var unlockMinutesBinding: Binding<Int> {
        Binding(
            get: { store.unlockPolicy.unlockMinutes },
            set: { store.updateUnlockMinutes($0) }
        )
    }

    private var questionsPerSessionBinding: Binding<Int> {
        Binding(
            get: { store.unlockPolicy.questionsPerSession },
            set: { store.updateQuestionsPerSession($0) }
        )
    }

    private var requiredCorrectAnswersBinding: Binding<Int> {
        Binding(
            get: { store.unlockPolicy.requiredCorrectAnswers },
            set: { store.updateRequiredCorrectAnswers($0) }
        )
    }

    private func prepareCheckpointPreview() {
        guard !isPreparingPreviewCheckpoint else { return }
        isPreparingPreviewCheckpoint = true

        Task {
            if let session = await store.preparePreviewCheckpointSession() {
                previewCheckpointMessage = nil
                previewCheckpointSession = session
            } else {
                previewCheckpointMessage = store.checkpointNotice
            }
            isPreparingPreviewCheckpoint = false
        }
    }
}
