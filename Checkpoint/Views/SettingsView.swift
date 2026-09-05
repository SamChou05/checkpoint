import SwiftUI

struct PracticeHistorySettingsPresentation: Equatable {
    let answerCount: Int
    let goalCount: Int

    init(attempts: [CheckpointAttempt]) {
        answerCount = attempts.count
        goalCount = Set(attempts.map(\.goalID)).count
    }

    var detail: String {
        switch goalCount {
        case 0:
            "Saved answers from every goal will appear here"
        case 1:
            "All saved answers from 1 goal"
        default:
            "All saved answers across \(goalCount) goals"
        }
    }

    var trailingText: String {
        "\(answerCount)"
    }

    var voiceOverValue: String {
        guard answerCount > 0 else {
            return "No saved answers yet. Practice history includes every goal."
        }

        let answerLabel = answerCount == 1 ? "answer" : "answers"
        let goalLabel = goalCount == 1 ? "1 goal" : "\(goalCount) goals"
        let scopePreposition = goalCount == 1 ? "from" : "across"
        return "\(answerCount) saved \(answerLabel) \(scopePreposition) \(goalLabel). Opens the full practice archive."
    }
}

struct GoalDeletionConfirmationPresentation: Equatable {
    let title: String
    let message: String
    let confirmationButtonTitle: String
    let cancelButtonTitle = "Keep goal"

    init(
        confirmation: GoalProfileMutationConfirmation,
        goals: [Goal]
    ) {
        let plan = confirmation.plan
        let resolver = GoalDisplayTitleResolver(goals: goals)
        let targetTitle = resolver.title(for: plan.targetGoal)
        let resultingTitle = plan.resultingActiveGoal.map(resolver.title(for:))

        guard let resultingGoal = plan.resultingActiveGoal,
              let resultingTitle else {
            title = confirmation.activeBreakAtRequest
                ? "Delete goal and end this break?"
                : "Delete your only goal?"
            if confirmation.activeBreakAtRequest {
                message = "Delete “\(targetTitle)” and all of its progress? Because this is your only goal, app protection and your current break will end. This can't be undone."
                confirmationButtonTitle = "Delete and end break"
            } else if case .deletionAndProtection = confirmation.consent {
                message = "Delete “\(targetTitle)” and all of its progress? Because this is your only goal, app protection will turn off. This can't be undone."
                confirmationButtonTitle = "Delete and turn off"
            } else {
                message = "Delete “\(targetTitle)” and all of its progress? You'll return to goal setup. This can't be undone."
                confirmationButtonTitle = "Delete goal"
            }
            return
        }

        let deletesActiveGoal = plan.sourceGoal?.id == plan.targetGoal.id
        guard deletesActiveGoal else {
            title = "Delete goal?"
            message = "Delete “\(targetTitle)” and all of its progress? This can't be undone."
            confirmationButtonTitle = "Delete goal"
            return
        }

        switch confirmation.consent {
        case .deletion:
            title = "Delete current goal?"
            message = "Delete “\(targetTitle)” and make “\(resultingTitle)” current? All progress for the deleted goal will be removed. This can't be undone."
            confirmationButtonTitle = "Delete goal"

        case .deletionAndProtection(.turnsOffImmediately):
            let readiness = plan.resultingReadiness
                ?? .incomplete(selectableCount: 0, requiredCount: 0)
            title = "Delete goal and turn off protection?"
            message = "Deleting “\(targetTitle)” makes “\(resultingTitle)” current. It has \(readiness.selectableCount) of \(readiness.requiredCount) checkpoint questions ready, so app protection will turn off. Start it again after a full checkpoint is ready. This can't be undone."
            confirmationButtonTitle = "Delete and turn off"

        case .deletionAndProtection(.preventsRelockAfterBreak):
            let readiness = plan.resultingReadiness
                ?? .incomplete(selectableCount: 0, requiredCount: 0)
            title = "Delete goal before this break ends?"
            message = "Your current break will continue. Protection will return when it ends only if “\(resultingTitle)” has a full checkpoint ready; otherwise it will turn off and you'll need to start it again. Right now, it has \(readiness.selectableCount) of \(readiness.requiredCount) questions ready. Deleting “\(targetTitle)” can't be undone."
            confirmationButtonTitle = "Delete goal"

        case .protection:
            title = "Delete current goal?"
            message = "Delete “\(targetTitle)” and make “\(resultingGoal.title)” current? This can't be undone."
            confirmationButtonTitle = "Delete goal"
        }
    }
}

struct SettingsView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let purchaseController: PurchaseController
    let workflow: CheckpointWorkflowCoordinator
    let presentCheckpoint: (CheckpointSession) -> Bool
    private let isVisible: Bool
    private let isSceneActive: Bool
    private let isCoveredByParentModal: Bool
    private let parentModalOwnsProtectionErrors: Bool
    private let legalLinks = LegalLinks.current

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.checkpointGoalSelection) private var selectGoal

    @State private var isRestrictedAppsPresented = false
    @State private var isHistoryPresented = false
    @State private var isIssueReportsPresented = false
    @State private var isGenerationDiagnosticsPresented = false
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
    @State private var pendingGoalDeletionConfirmation: GoalProfileMutationConfirmation?
    @State private var queuedGoalDeletionConfirmation: GoalProfileMutationConfirmation?
    @State private var accessibilityAnnouncementQueue = AccessibilityAnnouncementDeliveryQueue()
    @State private var isAuthorizationRequestActionInFlight = false
    @State private var protectionAnnouncementState = SettingsProtectionAnnouncementState()
    @State private var explicitlyAnnouncedScreenTimeError: String?
    @State private var protectionStartErrorFeedback = ProtectionStartErrorFeedbackState()

    init(
        store: CheckpointStore,
        screenTime: ScreenTimeController,
        purchaseController: PurchaseController,
        workflow: CheckpointWorkflowCoordinator,
        presentCheckpoint: @escaping (CheckpointSession) -> Bool,
        isVisible: Bool = true,
        isSceneActive: Bool = true,
        isCoveredByParentModal: Bool = false,
        parentModalOwnsProtectionErrors: Bool = false
    ) {
        self.store = store
        self.screenTime = screenTime
        self.purchaseController = purchaseController
        self.workflow = workflow
        self.presentCheckpoint = presentCheckpoint
        self.isVisible = isVisible
        self.isSceneActive = isSceneActive
        self.isCoveredByParentModal = isCoveredByParentModal
        self.parentModalOwnsProtectionErrors = parentModalOwnsProtectionErrors
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    protectionPanel
                    planPanel
                    goalsPanel

                    SettingsPracticeStandardCard(
                        presentation: practiceStandardPresentation,
                        isExpanded: $isPracticeStandardExpanded
                    ) {
                        practiceStandardControls
                    }

                    activityPanel
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
            .sheet(item: $advancedAction) { action in
                AdvancedConfirmationView(
                    action: action,
                    store: store,
                    screenTime: screenTime,
                    purchaseController: purchaseController
                )
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
            .alert(
                pendingGoalDeletionPresentation?.title ?? "Delete goal?",
                isPresented: goalDeletionConfirmationBinding,
                presenting: pendingGoalDeletionConfirmation
            ) { confirmation in
                let presentation = GoalDeletionConfirmationPresentation(
                    confirmation: confirmation,
                    goals: store.availableGoalProfiles
                )
                Button(presentation.confirmationButtonTitle, role: .destructive) {
                    confirmGoalDeletion(confirmation)
                }

                Button(presentation.cancelButtonTitle, role: .cancel) {
                    queuedGoalDeletionConfirmation = nil
                    pendingGoalDeletionConfirmation = nil
                }
            } message: { confirmation in
                Text(
                    GoalDeletionConfirmationPresentation(
                        confirmation: confirmation,
                        goals: store.availableGoalProfiles
                    ).message
                )
            }
            .onChange(of: settingsProtectionPresentation.state) { oldState, newState in
                if SettingsProtectionTransitionPolicy.shouldClearActionMessage(
                    from: oldState,
                    to: newState
                ) {
                    let hadActionMessage = protectionActionMessage != nil
                    protectionActionMessage = nil
                    if hadActionMessage {
                        accessibilityAnnouncementQueue.discard()
                    }
                }
                let isActionFeedbackPending = workflow.isStartingProtection
                    || workflow.pendingProtectionStartResult != nil
                    || isAuthorizationRequestActionInFlight
                guard protectionAnnouncementState.shouldDeliverTransition(
                    to: newState,
                    isActionFeedbackPending: isActionFeedbackPending
                ) else { return }
                guard ownsAccessibilityAnnouncements else { return }
                guard SettingsProtectionTransitionPolicy.shouldAnnounce(
                    from: oldState,
                    to: newState,
                    hasConcreteError: screenTime.userFacingErrorMessage != nil
                ) else { return }
                let presentation = settingsProtectionPresentation
                announceOrQueue(
                    AccessibilityAnnouncementRequest(
                        message: "Protection status: \(presentation.statusText). \(presentation.detail)",
                        context: .settingsProtectionState(newState)
                    )
                )
            }
            .onChange(of: screenTime.userFacingErrorMessage) { _, message in
                if message == nil {
                    explicitlyAnnouncedScreenTimeError = nil
                }
                let isActionFeedbackPending = workflow.isStartingProtection
                    || workflow.pendingProtectionStartResult?.protectionErrorMessage == message
                    || isAuthorizationRequestActionInFlight
                guard protectionStartErrorFeedback.shouldDeliverPassiveError(
                    message,
                    isStartFeedbackPending: isActionFeedbackPending
                ), let message else { return }
                if explicitlyAnnouncedScreenTimeError == message {
                    explicitlyAnnouncedScreenTimeError = nil
                    return
                }
                explicitlyAnnouncedScreenTimeError = nil
                guard isVisible,
                      !parentModalOwnsProtectionErrors,
                      !isRestrictedAppsPresented,
                      !isAuthorizationRequestActionInFlight else { return }
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
            .onChange(of: stopBlockingMessage) { _, message in
                guard let message else { return }
                announceOrQueue(
                    AccessibilityAnnouncementRequest(
                        message: message,
                        context: .settingsMessage(message)
                    )
                )
            }
            .onChange(of: resetRecoveryMessage) { _, message in
                guard let message else { return }
                announceOrQueue(
                    AccessibilityAnnouncementRequest(
                        message: message,
                        context: .settingsMessage(message)
                    )
                )
            }
            .onChange(of: ownsAccessibilityAnnouncements) { _, ownsAnnouncements in
                guard ownsAnnouncements else { return }
                deliverPendingAccessibilityAnnouncement()
                deliverPendingProtectionStartResultIfPossible()
            }
        }
    }

    private var protectionPanel: some View {
        SectionPanel("Protection") {
            VStack(alignment: .leading, spacing: 14) {
                protectionStatusHeader

                if let selectionSummary = settingsProtectionPresentation.visibleRestrictedAppsSummary {
                    Text(selectionSummary)
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }

                protectionPrimaryControl

                if let protectionActionMessage {
                    Label(protectionActionMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if shouldExplainCheckpointReadiness {
                    Text("Start protection checks that a full practice set is available before applying app limits.")
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
                value: settingsProtectionPresentation.state
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

    private var protectionStatusHeader: some View {
        SettingsProtectionStatusHeader(
            presentation: settingsProtectionPresentation
        )
    }

    @ViewBuilder
    private var protectionPrimaryControl: some View {
        switch settingsProtectionPresentation.controlLayout {
        case .unavailable:
            EmptyView()
        case .requestingAuthorization:
            PrimaryActionButton(
                title: "Requesting Screen Time access",
                systemImage: "shield",
                isLoading: true,
                action: {}
            )
            .disabled(true)
        case .authorizationRequired:
            PrimaryActionButton(title: "Allow Screen Time", systemImage: "shield") {
                requestScreenTimeAuthorization()
            }
        case .chooseApps:
            PrimaryActionButton(title: "Choose protected apps", systemImage: "checklist") {
                protectionActionMessage = nil
                isRestrictedAppsPresented = true
            }
        case .startAndEditApps:
            VStack(spacing: 10) {
                PrimaryActionButton(
                    title: settingsProtectionPresentation.showsProtectionStartProgress
                        ? "Checking checkpoint"
                        : "Start protection",
                    systemImage: "checkmark.shield",
                    isLoading: settingsProtectionPresentation.showsProtectionStartProgress
                ) {
                    prepareAndStartProtection()
                }
                .disabled(settingsProtectionPresentation.disablesProtectionStart)

                editProtectedAppsButton
            }
        case .editApps:
            editProtectedAppsButton
        }
    }

    private var editProtectedAppsButton: some View {
        SecondaryActionButton(title: "Edit protected apps", systemImage: "checklist") {
            protectionActionMessage = nil
            isRestrictedAppsPresented = true
        }
    }

    private var goalsPanel: some View {
        let switchPresentation = GoalSwitchMenuPresentation(store: store)

        return SectionPanel("Goals") {
            if let goal = store.goal {
                VStack(alignment: .leading, spacing: 10) {
                    goalSummary(
                        goal,
                        presentation: goalSwitchOption(
                            for: goal,
                            in: switchPresentation
                        )
                    )

                    if store.availableGoalProfiles.count > 1 {
                        Divider()

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Other goals")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.muted)
                                .padding(.bottom, 4)

                            ForEach(otherGoalProfiles) { profile in
                                goalProfileRow(
                                    profile,
                                    presentation: goalSwitchOption(
                                        for: profile,
                                        in: switchPresentation
                                    )
                                )

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
    private func goalSummary(
        _ goal: Goal,
        presentation: GoalSwitchMenuOptionPresentation
    ) -> some View {
        let summary = VStack(alignment: .leading, spacing: 5) {
            Text(presentation.title)
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
                goalSummaryAccessories(goal, displayTitle: presentation.title)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                summary
                Spacer(minLength: 8)
                goalSummaryAccessories(goal, displayTitle: presentation.title)
            }
        }
    }

    private func goalSummaryAccessories(
        _ goal: Goal,
        displayTitle: String
    ) -> some View {
        HStack(spacing: 8) {
            goalCapacityBadge

            if store.availableGoalProfiles.count > 1 {
                Menu {
                    Button(role: .destructive) {
                        requestGoalDeletion(goal.id)
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
                .accessibilityLabel("More options for \(displayTitle)")
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
    private func goalProfileRow(
        _ profile: Goal,
        presentation: GoalSwitchMenuOptionPresentation
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                goalProfileSelectionButton(profile, presentation: presentation)
                goalProfileDeleteButton(
                    profile,
                    displayTitle: presentation.title,
                    expanded: true
                )
            }
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 10) {
                goalProfileSelectionButton(profile, presentation: presentation)
                goalProfileDeleteButton(
                    profile,
                    displayTitle: presentation.title,
                    expanded: false
                )
            }
            .padding(.vertical, 10)
        }
    }

    private func goalProfileSelectionButton(
        _ profile: Goal,
        presentation: GoalSwitchMenuOptionPresentation
    ) -> some View {
        Button {
            selectGoal(profile.id)
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            goalSelectionIcon(for: presentation)

                            Text(presentation.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(goalProfileDetailText(for: profile, presentation: presentation))
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        if presentation.isCurrent {
                            StatusBadge(text: "Current", tint: CheckpointTheme.teal)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        goalSelectionIcon(for: presentation)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(presentation.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(goalProfileDetailText(for: profile, presentation: presentation))
                                .font(.footnote)
                                .foregroundStyle(CheckpointTheme.muted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        if presentation.isCurrent {
                            StatusBadge(text: "Current", tint: CheckpointTheme.teal)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(presentation.isCurrent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(goalProfileAccessibilityValue(for: profile, presentation: presentation))
        .accessibilityHint(goalProfileAccessibilityHint(for: presentation))
        .accessibilityAddTraits(presentation.isCurrent ? .isSelected : [])
    }

    private func goalSelectionIcon(
        for presentation: GoalSwitchMenuOptionPresentation
    ) -> some View {
        Image(systemName: presentation.systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(goalSelectionTint(for: presentation.state))
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }

    private func goalProfileDeleteButton(
        _ profile: Goal,
        displayTitle: String,
        expanded: Bool
    ) -> some View {
        Button {
            requestGoalDeletion(profile.id)
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
        .accessibilityLabel("Delete \(displayTitle)")
    }

    private func deleteGoalButton(_ goal: Goal) -> some View {
        Button {
            requestGoalDeletion(goal.id)
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

    private func goalSwitchOption(
        for profile: Goal,
        in presentation: GoalSwitchMenuPresentation
    ) -> GoalSwitchMenuOptionPresentation {
        presentation.options.first(where: { $0.id == profile.id })
            ?? GoalSwitchMenuOptionPresentation(
                id: profile.id,
                title: profile.title,
                state: .unavailable
            )
    }

    private func goalProfileDetailText(
        for profile: Goal,
        presentation: GoalSwitchMenuOptionPresentation
    ) -> String {
        let dueText = goalDeadlineDetail(for: profile, presentation: presentation)

        switch presentation.state {
        case .current:
            return dueText ?? "Current goal"
        case .ready:
            return joinedGoalDetail("Checkpoint ready", dueText)
        case let .preparing(selectableCount, requiredCount):
            return joinedGoalDetail(
                "Preparing · \(selectableCount) of \(requiredCount) questions ready",
                dueText
            )
        case let .notReady(selectableCount, requiredCount):
            return joinedGoalDetail(
                "Not ready · \(selectableCount) of \(requiredCount) questions ready",
                dueText
            )
        case .locked:
            return joinedGoalDetail("Requires Pro", dueText)
        case .unavailable:
            return "Unavailable"
        }
    }

    private func goalProfileAccessibilityValue(
        for profile: Goal,
        presentation: GoalSwitchMenuOptionPresentation
    ) -> String {
        let dueText = goalDeadlineDetail(for: profile, presentation: presentation)
        return joinedGoalDetail(presentation.accessibilityValue, dueText)
    }

    private func goalProfileAccessibilityHint(
        for presentation: GoalSwitchMenuOptionPresentation
    ) -> String {
        switch presentation.state {
        case .current:
            "This goal is already active."
        case .ready:
            "Switches to this goal."
        case .preparing, .notReady:
            "Switches to this goal. If protection would turn off, you will be asked to confirm."
        case .locked:
            "Shows Pro access options for multiple goals."
        case .unavailable:
            "Checks whether this goal can be selected now."
        }
    }

    private func goalSelectionTint(
        for state: GoalSwitchMenuOptionState
    ) -> Color {
        switch state {
        case .current, .ready:
            CheckpointTheme.teal
        case .preparing, .notReady:
            CheckpointTheme.amber
        case .locked, .unavailable:
            CheckpointTheme.muted
        }
    }

    private func goalDeadlineDetail(
        for profile: Goal,
        presentation: GoalSwitchMenuOptionPresentation
    ) -> String? {
        guard presentation.title == profile.title else { return nil }

        return "Due \(profile.deadline.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private func joinedGoalDetail(_ leading: String, _ trailing: String?) -> String {
        guard let trailing else { return leading }
        return "\(leading) · \(trailing)"
    }

    private var canStopBlocking: Bool {
        settingsProtectionPresentation.canStopBlocking
    }

    private var settingsProtectionPresentation: SettingsProtectionPresentation {
        SettingsProtectionPresentation(
            setupState: screenTime.setupState,
            isShieldingEnabled: screenTime.isShieldingEnabled,
            authorizationState: screenTime.authorizationState,
            hasSelection: screenTime.hasSelection,
            hasReadyCheckpointSet: store.hasReadyCheckpointSet,
            isStartingProtection: workflow.isStartingProtection,
            isPreparingPractice: store.isPreparingActiveGoalQuestions,
            breakRelockReadiness: protectionBreakRelockReadiness,
            restrictedAppsSummary: screenTime.restrictedAppsSummary
        )
    }

    private var protectionBreakRelockReadiness: HomeActiveBreakRelockReadiness {
        HomeActiveBreakRelockReadiness.resolve(
            hasRequiredScreenTimeAuthorization: screenTime.hasRequiredScreenTimeAuthorization,
            hasSelection: screenTime.hasSelection,
            hasReadyCheckpointSet: store.hasReadyCheckpointSet,
            sharedCheckpointReady: SharedAppGroup.checkpointReady
        )
    }

    private func requestScreenTimeAuthorization() {
        guard !screenTime.isRequestingAuthorization else { return }
        protectionActionMessage = nil

        Task {
            isAuthorizationRequestActionInFlight = true
            protectionAnnouncementState.resetExplicitState()
            explicitlyAnnouncedScreenTimeError = nil
            await screenTime.requestAuthorization()

            let request: AccessibilityAnnouncementRequest
            if let message = screenTime.userFacingErrorMessage {
                explicitlyAnnouncedScreenTimeError = message
                request = AccessibilityAnnouncementRequest(
                    message: message,
                    context: .screenTimeError(message)
                )
            } else {
                let presentation = settingsProtectionPresentation
                protectionAnnouncementState.recordExplicitState(presentation.state)
                request = AccessibilityAnnouncementRequest(
                    message: "Protection status: \(presentation.statusText). \(presentation.detail)",
                    context: .settingsProtectionState(presentation.state)
                )
            }
            announceOrQueue(request)
            isAuthorizationRequestActionInFlight = false
        }
    }

    private func prepareAndStartProtection() {
        guard !settingsProtectionPresentation.disablesProtectionStart else { return }
        protectionActionMessage = nil

        Task {
            let didStart = await workflow.startProtection()
            guard !didStart else { return }

            if let message = store.checkpointNotice {
                protectionActionMessage = message
            } else if screenTime.userFacingErrorMessage == nil {
                let message = "Protection could not start. Check your setup and try again."
                protectionActionMessage = message
            }
        }
    }

    private var ownsAccessibilityAnnouncements: Bool {
        TabContentAnnouncementOwnership.isActive(
            isVisible: isVisible,
            isSceneActive: isSceneActive,
            isCoveredByParentPresentation: isCoveredByParentModal,
            isCoveredByLocalPresentation: isRestrictedAppsPresented
                || isHistoryPresented
                || isIssueReportsPresented
                || isGenerationDiagnosticsPresented
                || advancedAction != nil
                || isStopProtectionConfirmationPresented
                || isStopWithoutReviewConfirmationPresented
                || pendingGoalDeletionConfirmation != nil
        )
    }

    private func announceOrQueue(_ request: AccessibilityAnnouncementRequest) {
        guard let request = accessibilityAnnouncementQueue.submit(
            request,
            isOwner: ownsAccessibilityAnnouncements
        ) else { return }
        AccessibilityNotification.Announcement(request.message).post()
    }

    private func deliverPendingAccessibilityAnnouncement() {
        guard let request = accessibilityAnnouncementQueue.takePending(
            isOwner: ownsAccessibilityAnnouncements
        ), accessibilityAnnouncementIsCurrent(request) else { return }
        AccessibilityNotification.Announcement(request.message).post()
    }

    private func deliverPendingProtectionStartResultIfPossible() {
        guard let result = ProtectionStartResultDelivery.takeCurrent(
            from: workflow,
            isOwner: ownsAccessibilityAnnouncements,
            currentGoalID: store.goal?.id,
            isShieldingEnabled: screenTime.isShieldingEnabled,
            protectionShouldRemainActive: SharedAppGroup.desiredShieldActive,
            checkpointNotice: store.checkpointNotice,
            protectionErrorMessage: screenTime.userFacingErrorMessage
        ) else { return }

        protectionStartErrorFeedback.recordDeliveredResult(result)
        protectionAnnouncementState.recordExplicitState(
            settingsProtectionPresentation.state
        )
        AccessibilityNotification.Announcement(
            ProtectionStartResultAnnouncement.message(for: result)
        ).post()
    }

    private func accessibilityAnnouncementIsCurrent(
        _ request: AccessibilityAnnouncementRequest
    ) -> Bool {
        switch request.context {
        case let .goalReady(goalID):
            store.goal?.id == goalID && store.hasReadyCheckpointSet
        case let .screenTimeError(message):
            screenTime.userFacingErrorMessage == message
        case let .settingsProtectionState(state):
            settingsProtectionPresentation.state == state
        case let .settingsMessage(message):
            protectionActionMessage == message
                || stopBlockingMessage == message
                || resetRecoveryMessage == message
        }
    }

    private var shouldExplainCheckpointReadiness: Bool {
        settingsProtectionPresentation.state == .checkpointRequired
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

    private var practiceHistorySettingsPresentation: PracticeHistorySettingsPresentation {
        PracticeHistorySettingsPresentation(attempts: store.attempts)
    }

    private var feedbackDraftSettingsPresentation: FeedbackDraftSettingsPresentation {
        FeedbackDraftSettingsPresentation(count: store.issueReportCount)
    }

    private var practiceStandardPresentation: SettingsPracticeStandardPresentation {
        SettingsPracticeStandardPresentation(unlockPolicy: store.unlockPolicy)
    }

    private var practiceStandardControls: some View {
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
    }

    private var activityPanel: some View {
        SectionPanel("Activity & help") {
            VStack(spacing: 14) {
                SettingsNavigationRow(
                    title: "Practice history",
                    detail: practiceHistorySettingsPresentation.detail,
                    systemImage: "clock.arrow.circlepath",
                    trailingText: practiceHistorySettingsPresentation.trailingText,
                    voiceOverValue: practiceHistorySettingsPresentation.voiceOverValue
                ) {
                    isHistoryPresented = true
                }

                Divider()

                SettingsNavigationRow(
                    title: "Support & feedback",
                    detail: feedbackDraftSettingsPresentation.detail,
                    systemImage: "bubble.left.and.bubble.right",
                    trailingText: "\(store.issueReportCount)",
                    voiceOverValue: feedbackDraftSettingsPresentation.voiceOverValue
                ) {
                    isIssueReportsPresented = true
                }
            }
        }
    }

    private var planPanel: some View {
        SettingsPlanCard(
            presentation: SettingsPlanPresentation(
                membershipTier: store.membershipTier,
                purchaseNotice: purchaseController.purchaseNotice,
                hasUnresolvedPurchase: purchaseController.hasUnresolvedPurchase,
                proActivity: store.isMember ? proActivityPresentation : nil,
                activePlanSnapshot: purchaseController.activePlanSnapshot
            )
        ) {
            store.requestMembershipOverview()
        }
    }

    private var proActivityPresentation: SettingsProActivityPresentation {
        SettingsProActivityPresentation(
            hasGoal: store.goal != nil,
            hasReadyCheckpoint: store.hasReadyCheckpointSet,
            isMaintainingFreshCheckpoints: store.isMaintainingActiveGoalQuestions,
            isQuestionGenerationBlockingPractice: store.isQuestionGenerationBlockingPractice,
            questionBankTargetCount: store.questionBankTargetCount,
            studyFocusState: store.studyFocusState,
            skillMapStatus: store.activeDerivedSkillMap?.status,
            hasPracticeHistory: !store.activeAttempts.isEmpty,
            goalCount: store.availableGoalProfiles.count,
            goalLimit: store.goalProfileLimit
        )
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
            pendingGoalDeletionConfirmation != nil
        } set: { isPresented in
            if !isPresented {
                pendingGoalDeletionConfirmation = nil
                promoteQueuedGoalDeletionConfirmationAfterDismissal()
            }
        }
    }

    private var pendingGoalDeletionPresentation: GoalDeletionConfirmationPresentation? {
        pendingGoalDeletionConfirmation.map {
            GoalDeletionConfirmationPresentation(
                confirmation: $0,
                goals: store.availableGoalProfiles
            )
        }
    }

    private func requestGoalDeletion(
        _ goalID: Goal.ID,
        authorization: GoalProfileMutationAuthorization = .none
    ) {
        let request: GoalProfileMutationRequest
        if case let .confirmed(confirmation) = authorization {
            request = confirmation.plan.request
        } else {
            request = GoalProfileMutationRequest(
                operation: .delete(goalID: goalID)
            )
        }

        let outcome = workflow.requestGoalProfileMutation(
            request,
            authorization: authorization
        )
        switch outcome {
        case let .confirmationRequired(confirmation):
            if case .confirmed = authorization {
                queuedGoalDeletionConfirmation = confirmation
            } else {
                pendingGoalDeletionConfirmation = confirmation
            }
        case .committed, .alreadyCommitted:
            queuedGoalDeletionConfirmation = nil
            pendingGoalDeletionConfirmation = nil
        case .targetNotFound, .staleRequest:
            queuedGoalDeletionConfirmation = nil
            pendingGoalDeletionConfirmation = nil
            store.checkpointNotice = "That goal changed before it could be deleted. Review your goals and try again."
        case .invalidTitle, .membershipRequired, .profileLimitReached:
            queuedGoalDeletionConfirmation = nil
            pendingGoalDeletionConfirmation = nil
        case .persistenceFailed:
            queuedGoalDeletionConfirmation = nil
            pendingGoalDeletionConfirmation = nil
        }
    }

    private func confirmGoalDeletion(
        _ confirmation: GoalProfileMutationConfirmation
    ) {
        requestGoalDeletion(
            confirmation.plan.targetGoal.id,
            authorization: .confirmed(confirmation)
        )
    }

    private func promoteQueuedGoalDeletionConfirmationAfterDismissal() {
        guard let queuedConfirmation = queuedGoalDeletionConfirmation else { return }

        Task { @MainActor in
            await Task.yield()
            guard pendingGoalDeletionConfirmation == nil,
                  queuedGoalDeletionConfirmation == queuedConfirmation else {
                return
            }
            queuedGoalDeletionConfirmation = nil
            pendingGoalDeletionConfirmation = queuedConfirmation
        }
    }
}
