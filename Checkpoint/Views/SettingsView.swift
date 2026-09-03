import SwiftUI

struct SettingsView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let purchaseController: PurchaseController
    let workflow: CheckpointWorkflowCoordinator
    let presentCheckpoint: (CheckpointSession) -> Bool
    private let legalLinks = LegalLinks.current

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @State private var protectionActionMessage: String?
    @State private var isPreparingStopChallenge = false
    @State private var isStopProtectionConfirmationPresented = false
    @State private var isStopWithoutReviewConfirmationPresented = false
    @State private var pendingGoalDeletion: Goal?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    protectionPanel
                    goalsPanel

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
            .onChange(of: screenTime.userFacingProtectionStatus) { _, status in
                guard advancedAction == nil else { return }
                protectionActionMessage = nil
                AccessibilityNotification.Announcement("Protection status: \(status).").post()
            }
            .onChange(of: screenTime.userFacingErrorMessage) { _, message in
                guard advancedAction == nil,
                      let message else { return }
                AccessibilityNotification.Announcement(message).post()
            }
            .onChange(of: stopBlockingMessage) { _, message in
                guard let message else { return }
                AccessibilityNotification.Announcement(message).post()
            }
            .onChange(of: resetRecoveryMessage) { _, message in
                guard advancedAction == nil, let message else { return }
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    private var protectionPanel: some View {
        SectionPanel("Protection") {
            VStack(alignment: .leading, spacing: 14) {
                protectionStatusHeader

                Text(screenTime.restrictedAppsSummary)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)

                protectionPrimaryControl

                if let protectionActionMessage {
                    Label(protectionActionMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if shouldExplainCheckpointReadiness {
                    Text("Checkpoint will verify a full practice set before protection turns on, so you can always earn access to your apps.")
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if canStopBlocking {
                    Divider()

                    SecondaryActionButton(
                        title: isPreparingStopChallenge ? "Preparing review" : "Turn off protection",
                        systemImage: "hand.raised"
                    ) {
                        isStopProtectionConfirmationPresented = true
                    }
                    .disabled(isPreparingStopChallenge)

                    if let stopBlockingMessage {
                        Text(stopBlockingMessage)
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        SecondaryActionButton(
                            title: "Turn off without review",
                            systemImage: "lock.open"
                        ) {
                            isStopWithoutReviewConfirmationPresented = true
                        }
                    }
                }

                if let message = screenTime.userFacingErrorMessage,
                   message != protectionActionMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(
                CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                value: screenTime.userFacingProtectionStatus
            )
            .animation(
                CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                value: screenTime.userFacingErrorMessage
            )
            .animation(
                CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                value: protectionActionMessage
            )
        }
    }

    @ViewBuilder
    private var protectionStatusHeader: some View {
        let identity = HStack(spacing: 12) {
            Image(systemName: protectionSystemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(protectionTint)
                .frame(width: 42, height: 42)
                .background(protectionTint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("App protection")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)

                Text(protectionStatusDetail)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    identity
                    StatusBadge(text: screenTime.userFacingProtectionStatus, tint: protectionTint)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    identity
                    Spacer(minLength: 8)
                    StatusBadge(text: screenTime.userFacingProtectionStatus, tint: protectionTint)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("App protection")
        .accessibilityValue(
            "\(screenTime.userFacingProtectionStatus). \(protectionStatusDetail) \(screenTime.restrictedAppsSummary)."
        )
    }

    @ViewBuilder
    private var protectionPrimaryControl: some View {
        if screenTime.setupState == .unavailable {
            EmptyView()
        } else if screenTime.isRequestingAuthorization {
            PrimaryActionButton(
                title: "Requesting Screen Time access",
                systemImage: "shield",
                isLoading: true,
                action: {}
            )
            .disabled(true)
        } else if screenTime.requiresScreenTimeAuthorization {
            PrimaryActionButton(title: "Allow Screen Time", systemImage: "shield") {
                requestScreenTimeAuthorization()
            }
        } else if !screenTime.hasSelection {
            PrimaryActionButton(title: "Choose protected apps", systemImage: "checklist") {
                protectionActionMessage = nil
                isRestrictedAppsPresented = true
            }
        } else if !canStopBlocking {
            PrimaryActionButton(
                title: isProtectionStartBusy ? "Checking checkpoint" : "Start protection",
                systemImage: "checkmark.shield",
                isLoading: isProtectionStartBusy
            ) {
                prepareAndStartProtection()
            }
            .disabled(isProtectionStartBusy)
        } else {
            SecondaryActionButton(title: "Choose protected apps", systemImage: "checklist") {
                protectionActionMessage = nil
                isRestrictedAppsPresented = true
            }
        }
    }

    private var goalsPanel: some View {
        SectionPanel("Goals") {
            if let goal = store.goal {
                VStack(alignment: .leading, spacing: 10) {
                    goalSummary(goal)

                    if store.availableGoalProfiles.count > 1 {
                        Divider()

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Other goals")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.muted)
                                .padding(.bottom, 4)

                            ForEach(otherGoalProfiles) { profile in
                                goalProfileRow(profile)

                                if profile.id != otherGoalProfiles.last?.id {
                                    Divider()
                                        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 44)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Add a learning goal to personalize each checkpoint.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    editGoalButton
                    newGoalButton
                }
            } else {
                HStack(spacing: 10) {
                    editGoalButton
                    newGoalButton
                }
            }

            if let goal = store.goal, store.availableGoalProfiles.count <= 1 {
                deleteGoalButton(goal)
            }
        }
    }

    @ViewBuilder
    private func goalSummary(_ goal: Goal) -> some View {
        let summary = VStack(alignment: .leading, spacing: 5) {
            Text(goal.title)
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            if let focusText = store.activeGoalFocusText {
                Text("Focus: \(focusText)")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                summary
                goalSummaryAccessories(goal)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                summary
                Spacer(minLength: 8)
                goalSummaryAccessories(goal)
            }
        }
    }

    private func goalSummaryAccessories(_ goal: Goal) -> some View {
        HStack(spacing: 8) {
            goalCapacityBadge

            if store.availableGoalProfiles.count > 1 {
                Menu {
                    Button(role: .destructive) {
                        pendingGoalDeletion = goal
                    } label: {
                        Label("Delete current goal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CheckpointTheme.muted)
                        .frame(width: 44, height: 44)
                        .background(CheckpointTheme.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("More options for \(goal.title)")
            }
        }
    }

    @ViewBuilder
    private var goalCapacityBadge: some View {
        if store.availableGoalProfiles.count > 1 || (store.isMember && store.hasReachedGoalProfileLimit) {
            StatusBadge(
                text: store.goalProfileCapacityText,
                tint: store.hasReachedGoalProfileLimit ? CheckpointTheme.amber : CheckpointTheme.teal
            )
        }
    }

    private var otherGoalProfiles: [Goal] {
        store.availableGoalProfiles.filter { $0.id != store.goal?.id }
    }

    private var editGoalButton: some View {
        SecondaryActionButton(title: "Edit goal", systemImage: "pencil") {
            store.presentActiveGoalEditor()
        }
        .disabled(store.goal == nil)
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

    @ViewBuilder
    private func goalProfileRow(_ profile: Goal) -> some View {
        let isActive = profile.id == store.goal?.id

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                goalProfileSelectionButton(profile, isActive: isActive)
                goalProfileDeleteButton(profile, expanded: true)
            }
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 10) {
                goalProfileSelectionButton(profile, isActive: isActive)
                goalProfileDeleteButton(profile, expanded: false)
            }
            .padding(.vertical, 10)
        }
    }

    private func goalProfileSelectionButton(_ profile: Goal, isActive: Bool) -> some View {
        Button {
            store.switchActiveGoal(to: profile.id)
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            goalSelectionIcon(isActive: isActive)

                            Text(profile.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(goalProfileDetailText(for: profile))
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        if isActive {
                            StatusBadge(text: "Current", tint: CheckpointTheme.teal)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        goalSelectionIcon(isActive: isActive)

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
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.title)
        .accessibilityValue("\(isActive ? "Current goal. " : "")\(goalProfileDetailText(for: profile))")
        .accessibilityHint(isActive ? "Current goal." : "Activates this goal.")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func goalSelectionIcon(isActive: Bool) -> some View {
        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isActive ? CheckpointTheme.teal : CheckpointTheme.muted)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }

    private func goalProfileDeleteButton(_ profile: Goal, expanded: Bool) -> some View {
        Button {
            pendingGoalDeletion = profile
        } label: {
            Group {
                if expanded {
                    Label("Delete goal", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 44)
                }
            }
            .foregroundStyle(CheckpointTheme.coral)
            .background(CheckpointTheme.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete \(profile.title)")
    }

    private func deleteGoalButton(_ goal: Goal) -> some View {
        Button {
            pendingGoalDeletion = goal
        } label: {
            Label("Delete goal", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.coral)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
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

    private func requestScreenTimeAuthorization() {
        guard !screenTime.isRequestingAuthorization else { return }
        protectionActionMessage = nil

        Task {
            await screenTime.requestAuthorization()
        }
    }

    private func prepareAndStartProtection() {
        guard !isProtectionStartBusy else { return }
        protectionActionMessage = nil

        Task {
            let didStart = await workflow.startProtection()
            guard !didStart else { return }

            if let message = store.checkpointNotice {
                protectionActionMessage = message
                AccessibilityNotification.Announcement(message).post()
            } else if screenTime.userFacingErrorMessage == nil {
                let message = "Protection could not start. Check your setup and try again."
                protectionActionMessage = message
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    private var isProtectionStartBusy: Bool {
        workflow.isStartingProtection || store.isPreparingActiveGoalQuestions
    }

    private var shouldExplainCheckpointReadiness: Bool {
        screenTime.setupState == .authorized
            && screenTime.hasSelection
            && !canStopBlocking
            && !store.hasReadyCheckpointSet
    }

    private var protectionSystemImage: String {
        switch screenTime.setupState {
        case .shieldActive:
            return "checkmark.shield.fill"
        case .temporarilyUnlocked:
            return "timer"
        case .failed:
            return "exclamationmark.shield.fill"
        case .unavailable:
            return "iphone.slash"
        case .notStarted, .authorized:
            return screenTime.hasSelection ? "shield" : "shield.lefthalf.filled"
        }
    }

    private var protectionTint: Color {
        switch screenTime.setupState {
        case .shieldActive:
            return CheckpointTheme.teal
        case .temporarilyUnlocked:
            return CheckpointTheme.amber
        case .failed:
            return CheckpointTheme.coral
        case .unavailable:
            return CheckpointTheme.muted
        case .notStarted, .authorized:
            return CheckpointTheme.blue
        }
    }

    private var protectionStatusDetail: String {
        if screenTime.isRequestingAuthorization {
            return "Waiting for iPhone to confirm Screen Time access."
        }

        switch screenTime.setupState {
        case .shieldActive:
            return "Selected apps pause at a goal-based checkpoint."
        case .temporarilyUnlocked:
            return "Your timed break is active; protection restarts automatically."
        case .failed:
            return "Screen Time access needs attention before protection can start."
        case .unavailable:
            return "App protection is available on iPhone."
        case .authorized where screenTime.hasSelection && store.hasReadyCheckpointSet:
            return "Your apps and practice set are ready to protect."
        case .authorized where screenTime.hasSelection:
            return "Your apps are selected; Checkpoint will verify practice before starting."
        case .authorized:
            return "Choose the apps you want to use more intentionally."
        case .notStarted:
            return "Allow Screen Time to set up private, on-device protection."
        }
    }

    private var resetRecoveryMessage: String? {
        let messages = [
            store.persistenceRecoveryMessage,
            screenTime.sharedDataEraseErrorMessage
        ].compactMap { $0 }
        let uniqueMessages = messages.reduce(into: [String]()) { result, message in
            if !result.contains(message) {
                result.append(message)
            }
        }
        return uniqueMessages.isEmpty ? nil : uniqueMessages.joined(separator: " ")
    }

    private var planDetailText: String {
        if store.isMember {
            return "Pro is active: multiple goals, ongoing practice, and Next Focus."
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
                    .fixedSize(horizontal: false, vertical: true)
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
                HStack {
                    Text("Customize")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .tint(CheckpointTheme.teal)
            .accessibilityHint(isPracticeStandardExpanded ? "Collapses practice controls." : "Expands practice controls.")
        }
    }

    private var activityPanel: some View {
        SectionPanel("Activity & help") {
            VStack(spacing: 14) {
                SettingsNavigationRow(
                    title: "Practice history",
                    detail: historyDetailText,
                    systemImage: "clock.arrow.circlepath",
                    trailingText: "\(store.activeAttempts.count)",
                    voiceOverValue: store.activeAttempts.isEmpty
                        ? "No answers yet"
                        : "\(store.activeAttempts.count) answers. \(historyDetailText)"
                ) {
                    isHistoryPresented = true
                }

                Divider()

                SettingsNavigationRow(
                    title: "Help & feedback",
                    detail: issueReportsDetailText,
                    systemImage: "bubble.left.and.bubble.right",
                    trailingText: "\(store.issueReportCount)",
                    voiceOverValue: store.issueReportCount == 0
                        ? "No saved reports"
                        : "\(store.issueReportCount) saved reports"
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
                trailingText: store.membershipTier.displayName,
                voiceOverValue: "\(store.membershipTier.displayName) plan. \(planDetailText)"
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
            if let resetRecoveryMessage {
                Label(resetRecoveryMessage, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            DisclosureGroup(isExpanded: $isAppDataExpanded) {
                VStack(alignment: .leading, spacing: 10) {
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
                HStack {
                    Text("Reset options")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .tint(CheckpointTheme.teal)
            .accessibilityHint(isAppDataExpanded ? "Collapses reset options." : "Expands reset options.")
        }
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: resetRecoveryMessage
        )
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
                        trailingText: "\(store.questionGenerationTraces.count)",
                        voiceOverValue: "\(store.questionGenerationTraces.count) generation traces. \(store.questionGenerationDiagnosticsSummary)"
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
                HStack {
                    Text("Diagnostics and preview")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .tint(CheckpointTheme.teal)
            .accessibilityHint(isDeveloperToolsExpanded ? "Collapses developer tools." : "Expands developer tools.")
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
