import SwiftUI

struct SettingsView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let purchaseController: PurchaseController
    let workflow: CheckpointWorkflowCoordinator
    let presentCheckpoint: (CheckpointSession) -> Bool
    private let legalLinks = LegalLinks.current

    @State private var isRestrictedAppsPresented = false
    @State private var isHistoryPresented = false
    @State private var isIssueReportsPresented = false
    @State private var isGenerationDiagnosticsPresented = false
    @State private var isPlanPresented = false
    @State private var isPracticeStandardExpanded = false
    @State private var isAppDataExpanded = false
    @State private var isDeveloperToolsExpanded = false
    @State private var advancedAction: AdvancedSettingsAction?
    @State private var previewCheckpointMessage: String?
    @State private var isPreparingPreviewCheckpoint = false
    @State private var stopBlockingMessage: String?
    @State private var isPreparingStopChallenge = false
    @State private var isStopProtectionConfirmationPresented = false
    @State private var isStopWithoutReviewConfirmationPresented = false
    @State private var pendingGoalDeletion: Goal?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionPanel("Goals") {
                        if let goal = store.goal {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(goal.title)
                                            .font(.headline)
                                            .foregroundStyle(CheckpointTheme.text)

                                        if let focusText = store.activeGoalFocusText {
                                            Text("Focus: \(focusText)")
                                                .font(.subheadline)
                                                .foregroundStyle(CheckpointTheme.muted)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }

                                    Spacer()

                                    if store.availableGoalProfiles.count > 1 || (store.isMember && store.hasReachedGoalProfileLimit) {
                                        StatusBadge(
                                            text: store.goalProfileCapacityText,
                                            tint: store.hasReachedGoalProfileLimit ? CheckpointTheme.amber : CheckpointTheme.teal
                                        )
                                    }
                                }

                                if store.availableGoalProfiles.count > 1 {
                                    Divider()

                                    VStack(spacing: 0) {
                                        ForEach(store.availableGoalProfiles) { profile in
                                            goalProfileRow(profile)

                                            if profile.id != store.availableGoalProfiles.last?.id {
                                                Divider()
                                                    .padding(.leading, 44)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            SecondaryActionButton(title: "Edit goal", systemImage: "pencil") {
                                store.presentActiveGoalEditor()
                            }

                            newGoalButton
                        }

                        if let goal = store.goal, store.availableGoalProfiles.count <= 1 {
                            deleteGoalButton(goal)
                        }
                    }

                    SectionPanel("Protected apps") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Status")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text(screenTime.userFacingProtectionStatus)
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
                            } else if screenTime.setupState != .unavailable {
                                SecondaryActionButton(title: "Choose protected apps", systemImage: "checklist") {
                                    isRestrictedAppsPresented = true
                                }
                            }

                            if canStopBlocking {
                                Divider()

                                SecondaryActionButton(title: isPreparingStopChallenge ? "Preparing review" : "Turn off protection", systemImage: "hand.raised") {
                                    isStopProtectionConfirmationPresented = true
                                }
                                .disabled(isPreparingStopChallenge)

                                if let stopBlockingMessage {
                                    Text(stopBlockingMessage)
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.amber)
                                        .fixedSize(horizontal: false, vertical: true)

                                    SecondaryActionButton(
                                        title: "Turn off without review",
                                        systemImage: "lock.open"
                                    ) {
                                        isStopWithoutReviewConfirmationPresented = true
                                    }
                                }
                            }

                            if let message = screenTime.userFacingErrorMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.coral)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    SectionPanel("Practice standard") {
                        practiceStandardContent
                    }

                    activityPanel
                    planPanel
                    privacyAndSupportPanel
                    appDataPanel

                    #if DEBUG
                    developerToolsPanel
                    #endif
                }
                .padding(20)
                .padding(.bottom, 56)
            }
            .padding(.bottom, 48)
            .checkpointScreenBackground()
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $isRestrictedAppsPresented) {
                RestrictedAppsView(screenTime: screenTime)
            }
            .sheet(isPresented: $isHistoryPresented) {
                HistoryView(store: store)
            }
            .sheet(isPresented: $isIssueReportsPresented) {
                QuestionReportsView(store: store)
            }
            .sheet(isPresented: $isGenerationDiagnosticsPresented) {
                QuestionGenerationDiagnosticsView(store: store)
            }
            .sheet(isPresented: $isPlanPresented) {
                MembershipView(feature: .freshQuestionGeneration, store: store, purchaseController: purchaseController)
            }
            .sheet(item: $advancedAction) { action in
                AdvancedConfirmationView(action: action, store: store, screenTime: screenTime)
            }
            .alert("Turn off protection?", isPresented: $isStopProtectionConfirmationPresented) {
                Button("Start 20-question review") {
                    prepareStopBlockingChallenge()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to answer 18 of 20 questions correctly before protection turns off.")
            }
            .alert("Turn off without review?", isPresented: $isStopWithoutReviewConfirmationPresented) {
                Button("Turn off protection", role: .destructive) {
                    workflow.stopProtectionWithoutReview()
                    stopBlockingMessage = nil
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The review could not be prepared. You can turn protection off now and restart it after a full checkpoint is ready.")
            }
            .alert("Delete goal?", isPresented: goalDeletionConfirmationBinding) {
                Button("Delete goal", role: .destructive) {
                    confirmGoalDeletion()
                }

                Button("Cancel", role: .cancel) {
                    pendingGoalDeletion = nil
                }
            } message: {
                Text(goalDeletionConfirmationMessage)
            }
        }
    }

    @ViewBuilder
    private var newGoalButton: some View {
        let isLimitReached = store.isMember && store.hasReachedGoalProfileLimit

        SecondaryActionButton(
            title: isLimitReached ? "Goal limit reached" : "New goal",
            systemImage: isLimitReached ? "checkmark.seal" : "plus"
        ) {
            store.presentGoalProfileCreator()
        }
        .disabled(isLimitReached)
        .opacity(isLimitReached ? 0.65 : 1)
    }

    private func goalProfileRow(_ profile: Goal) -> some View {
        let isActive = profile.id == store.goal?.id

        return HStack(spacing: 10) {
            Button {
                store.switchActiveGoal(to: profile.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isActive ? CheckpointTheme.teal : CheckpointTheme.muted)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(goalProfileDetailText(for: profile))
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if isActive {
                        StatusBadge(text: "Current", tint: CheckpointTheme.teal)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isActive)

            Button {
                pendingGoalDeletion = profile
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CheckpointTheme.coral)
                    .frame(width: 44, height: 44)
                    .background(CheckpointTheme.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(profile.title)")
        }
        .padding(.vertical, 10)
    }

    private func deleteGoalButton(_ goal: Goal) -> some View {
        Button {
            pendingGoalDeletion = goal
        } label: {
            Label("Delete goal", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.coral)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(CheckpointTheme.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func goalProfileDetailText(for profile: Goal) -> String {
        if let readinessWarning = store.questionBankReadinessWarning(for: profile) {
            return readinessWarning
        }

        return "Due \(profile.deadline.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private var canStopBlocking: Bool {
        screenTime.isShieldingEnabled || screenTime.setupState == .temporarilyUnlocked
    }

    private var shouldShowScreenTimeAuthorizationButton: Bool {
        screenTime.setupState == .notStarted || screenTime.setupState == .failed
    }

    private var planDetailText: String {
        if store.isMember {
            return "Pro is active: multiple goals, ongoing practice, and guided review."
        }

        return "Free includes one goal and app protection."
    }

    private var historyDetailText: String {
        store.activeAttempts.isEmpty ? "No practice yet" : "Review past answers"
    }

    private var issueReportsDetailText: String {
        if store.issueReportCount == 0 {
            return "Save or share an issue"
        }

        return "\(store.issueReportCount) saved"
    }

    private var practiceStandardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Passing standard")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)

                Text("\(store.unlockPolicy.requiredCorrectAnswers) of \(store.unlockPolicy.questionsPerSession) correct starts a \(store.unlockPolicy.unlockMinutes)-minute break.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
            }

            DisclosureGroup(isExpanded: $isPracticeStandardExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    PracticeStandardStepperRow(
                        title: "Questions per checkpoint",
                        value: store.unlockPolicy.questionsPerSession,
                        decrementDisabled: store.unlockPolicy.questionsPerSession <= UnlockPolicy.minimumQuestionsPerSession,
                        incrementDisabled: store.unlockPolicy.questionsPerSession >= UnlockPolicy.maximumQuestionsPerSession,
                        decrementAction: {
                            store.updateQuestionsPerSession(store.unlockPolicy.questionsPerSession - 1)
                        },
                        incrementAction: {
                            store.updateQuestionsPerSession(store.unlockPolicy.questionsPerSession + 1)
                        }
                    )

                    PracticeStandardStepperRow(
                        title: "Correct answers needed",
                        value: store.unlockPolicy.requiredCorrectAnswers,
                        decrementDisabled: store.unlockPolicy.requiredCorrectAnswers <= UnlockPolicy.minimumRequiredCorrectAnswers,
                        incrementDisabled: store.unlockPolicy.requiredCorrectAnswers >= store.unlockPolicy.questionsPerSession,
                        decrementAction: {
                            store.updateRequiredCorrectAnswers(store.unlockPolicy.requiredCorrectAnswers - 1)
                        },
                        incrementAction: {
                            store.updateRequiredCorrectAnswers(store.unlockPolicy.requiredCorrectAnswers + 1)
                        }
                    )

                    BreakDurationMenu(
                        selectedMinutes: store.unlockPolicy.unlockMinutes,
                        options: UnlockPolicy.correctAnswerUnlockMinuteOptions
                    ) { minutes in
                        store.updateUnlockMinutes(minutes)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("Customize")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
            }
            .tint(CheckpointTheme.teal)
        }
    }

    private var activityPanel: some View {
        SectionPanel("Activity & help") {
            VStack(spacing: 14) {
                SettingsNavigationRow(
                    title: "Practice history",
                    detail: historyDetailText,
                    systemImage: "clock.arrow.circlepath",
                    trailingText: "\(store.activeAttempts.count)"
                ) {
                    isHistoryPresented = true
                }

                Divider()

                SettingsNavigationRow(
                    title: "Help & feedback",
                    detail: issueReportsDetailText,
                    systemImage: "bubble.left.and.bubble.right",
                    trailingText: "\(store.issueReportCount)"
                ) {
                    isIssueReportsPresented = true
                }
            }
        }
    }

    private var planPanel: some View {
        SectionPanel("Plan") {
            SettingsNavigationRow(
                title: "Free and Pro",
                detail: planDetailText,
                systemImage: "creditcard",
                trailingText: store.membershipTier.displayName
            ) {
                isPlanPresented = true
            }
        }
    }

    private var privacyAndSupportPanel: some View {
        SectionPanel("Privacy & support") {
            VStack(spacing: 0) {
                LegalLinkRow(
                    title: "Privacy Policy",
                    detail: "How Checkpoint handles app, learning, and service data",
                    systemImage: "hand.raised",
                    url: legalLinks.privacyPolicyURL
                )

                Divider()
                    .padding(.vertical, 10)

                LegalLinkRow(
                    title: "Support",
                    detail: "Get help with Checkpoint",
                    systemImage: "questionmark.circle",
                    url: legalLinks.supportURL
                )

                Divider()
                    .padding(.vertical, 10)

                LegalLinkRow(
                    title: "Terms of Use",
                    detail: "Apple Standard End User License Agreement",
                    systemImage: "doc.text",
                    url: LegalLinks.termsOfUseURL
                )
            }
        }
    }

    private var appDataPanel: some View {
        SectionPanel("App data") {
            DisclosureGroup(isExpanded: $isAppDataExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if let persistenceMessage = store.persistenceRecoveryMessage {
                        Label(persistenceMessage, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Erase goals, progress, protected-app selections, diagnostics, and the anonymous backend install ID, then turn off app protection.")
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    SecondaryActionButton(title: "Reset Checkpoint", systemImage: "arrow.counterclockwise") {
                        advancedAction = .resetData
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("Reset options")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
            }
            .tint(CheckpointTheme.teal)
        }
    }

    #if DEBUG
    private var developerToolsPanel: some View {
        SectionPanel("Developer tools") {
            DisclosureGroup(isExpanded: $isDeveloperToolsExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(screenTime.shieldExtensionDiagnosticsText)
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    SettingsNavigationRow(
                        title: "Question diagnostics",
                        detail: store.questionGenerationDiagnosticsSummary,
                        systemImage: "text.magnifyingglass",
                        trailingText: "\(store.questionGenerationTraces.count)"
                    ) {
                        isGenerationDiagnosticsPresented = true
                    }

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
                }
                .padding(.top, 10)
            } label: {
                Text("Diagnostics and preview")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
            }
            .tint(CheckpointTheme.teal)
        }
    }
    #endif

    private func prepareCheckpointPreview() {
        guard !isPreparingPreviewCheckpoint else { return }
        isPreparingPreviewCheckpoint = true

        Task {
            if let session = await store.preparePreviewCheckpointSession() {
                previewCheckpointMessage = presentCheckpoint(session)
                    ? nil
                    : "Finish the current checkpoint before opening a preview."
            } else {
                previewCheckpointMessage = store.checkpointNotice
            }
            isPreparingPreviewCheckpoint = false
        }
    }

    private func prepareStopBlockingChallenge() {
        guard !isPreparingStopChallenge else { return }
        isPreparingStopChallenge = true

        Task {
            if let session = await store.prepareStopBlockingSession() {
                stopBlockingMessage = presentCheckpoint(session)
                    ? nil
                    : "Finish the current checkpoint before turning off protection."
            } else {
                stopBlockingMessage = store.checkpointNotice
            }
            isPreparingStopChallenge = false
        }
    }

    private var goalDeletionConfirmationBinding: Binding<Bool> {
        Binding {
            pendingGoalDeletion != nil
        } set: { isPresented in
            if !isPresented {
                pendingGoalDeletion = nil
            }
        }
    }

    private var goalDeletionConfirmationMessage: String {
        guard let pendingGoalDeletion else {
            return "This removes the goal and its saved practice data."
        }

        return "Delete “\(pendingGoalDeletion.title)” and all of its progress? This can't be undone."
    }

    private func confirmGoalDeletion() {
        guard let pendingGoalDeletion else { return }
        if store.deleteGoalProfile(pendingGoalDeletion.id) {
            if store.goal == nil {
                screenTime.clearShield()
            } else {
                screenTime.reconcileShieldState()
            }
        }
        self.pendingGoalDeletion = nil
    }
}
