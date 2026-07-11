import SwiftUI

struct SettingsView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let purchaseController: PurchaseController

    @State private var isRestrictedAppsPresented = false
    @State private var isHistoryPresented = false
    @State private var isIssueReportsPresented = false
    @State private var isGenerationDiagnosticsPresented = false
    @State private var isPlanPresented = false
    @State private var isAdvancedExpanded = false
    @State private var advancedAction: AdvancedSettingsAction?
    @State private var previewCheckpointSession: CheckpointSession?
    @State private var previewCheckpointMessage: String?
    @State private var isPreparingPreviewCheckpoint = false
    @State private var stopBlockingSession: CheckpointSession?
    @State private var stopBlockingMessage: String?
    @State private var isPreparingStopChallenge = false
    @State private var isStopProtectionConfirmationPresented = false
    @State private var pendingGoalDeletion: Goal?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Settings")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Adjust your goal, protected apps, and practice standards.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    SectionPanel("Plan") {
                        SettingsNavigationRow(
                            title: "Choose your plan",
                            detail: planDetailText,
                            systemImage: "creditcard",
                            trailingText: store.membershipTier.displayName
                        ) {
                            isPlanPresented = true
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

                                        if let focusText = store.activeGoalFocusText {
                                            Text("Focus: \(focusText)")
                                                .font(.subheadline)
                                                .foregroundStyle(CheckpointTheme.muted)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }

                                    Spacer()

                                    StatusBadge(
                                        text: store.goalProfileCapacityText,
                                        tint: store.hasReachedGoalProfileLimit ? CheckpointTheme.amber : CheckpointTheme.teal
                                    )
                                }

                                Text("Question level: \(goal.difficultyLabel)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text("Each goal keeps its own practice sets, Skill Map, and answer history.")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)

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

                    SectionPanel("Activity") {
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
                                title: "Report an issue",
                                detail: issueReportsDetailText,
                                systemImage: "bubble.left.and.bubble.right",
                                trailingText: "\(store.issueReportCount)"
                            ) {
                                isIssueReportsPresented = true
                            }
                        }
                    }

                    SectionPanel("Protected apps") {
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

                            SecondaryActionButton(title: "Choose protected apps", systemImage: "checklist") {
                                isRestrictedAppsPresented = true
                            }

                            if canStopBlocking {
                                Divider()

                                Text("Turning off protection requires a longer 20-question review with at least 18 correct.")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)

                                SecondaryActionButton(title: isPreparingStopChallenge ? "Preparing review" : "Turn off protection", systemImage: "hand.raised") {
                                    isStopProtectionConfirmationPresented = true
                                }
                                .disabled(isPreparingStopChallenge)

                                if let stopBlockingMessage {
                                    Text(stopBlockingMessage)
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            if let message = screenTime.lastErrorMessage {
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

                    if store.isBackendQuestionGenerationConfigured {
                        SectionPanel("Cloud question generation") {
                            if store.isMember {
                                Toggle(
                                    "Use Pro cloud questions",
                                    isOn: Binding(
                                        get: { store.backendQuestionGenerationConsentGranted },
                                        set: { store.updateBackendQuestionGenerationConsent($0) }
                                    )
                                )
                                .tint(CheckpointTheme.teal)

                                Text(
                                    store.isProCloudQuestionGenerationActive
                                        ? "Cloud-first generation and the background question reserve are active. Local generation takes over automatically during an outage."
                                        : "Pro is using local generation. Enable cloud questions for more variety and questions prepared while the app is closed."
                                    )
                                .font(.footnote)
                                .foregroundStyle(CheckpointTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)

                                Text("When enabled, Checkpoint sends your goal details, focus areas, skill progress, recent question coverage, and question-report notes to its AWS service. Up to 20 prepared questions per goal may be retained for 30 days; turning this off requests deletion.")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Label("Free questions are generated on this device", systemImage: "iphone")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("Pro adds cloud-first generation and a background reserve. Free never sends question-generation data to the cloud.")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)

                                if store.backendQuestionGenerationConsentGranted {
                                    Button("Clear saved cloud permission and data") {
                                        store.updateBackendQuestionGenerationConsent(false)
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.coral)
                                }
                            }
                        }
                    }

                    SectionPanel("Help & legal") {
                        helpAndLegalContent
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

                                SettingsNavigationRow(
                                    title: "Generation diagnostics",
                                    detail: store.questionGenerationDiagnosticsSummary,
                                    systemImage: "text.magnifyingglass",
                                    trailingText: "\(store.questionGenerationTraces.count)"
                                ) {
                                    isGenerationDiagnosticsPresented = true
                                }

                                Divider()

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
            .sheet(item: $previewCheckpointSession) { session in
                CheckpointAttemptView(store: store, screenTime: screenTime, session: session)
            }
            .sheet(item: $stopBlockingSession) { session in
                CheckpointAttemptView(store: store, screenTime: screenTime, session: session)
            }
            .alert("Turn off protection?", isPresented: $isStopProtectionConfirmationPresented) {
                Button("Start 20-question review") {
                    prepareStopBlockingChallenge()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to answer 18 of 20 questions correctly before protection turns off.")
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
                    .frame(width: 36, height: 36)
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
        var parts = ["Question level: \(profile.difficultyLabel)"]

        if let readinessWarning = store.questionBankReadinessWarning(for: profile) {
            parts.append(readinessWarning)
        }

        return parts.joined(separator: " - ")
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

        return "Free includes one goal and the core protected-app flow."
    }

    private var historyDetailText: String {
        if store.activeAttempts.isEmpty {
            return "No practice answers yet"
        }

        return "\(store.questionsAnsweredThisWeekCount) answered this week"
    }

    private var issueReportsDetailText: String {
        if store.issueReportCount == 0 {
            return "Questions, app issues, or feedback"
        }

        return "\(store.issueReportCount) submitted"
    }

    private var practiceStandardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Passing standard")
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.text)

                    Text("\(store.unlockPolicy.requiredCorrectAnswers) of \(store.unlockPolicy.questionsPerSession) correct starts a break.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                }

                Spacer(minLength: 12)

                StatusBadge(
                    text: "\(store.unlockPolicy.requiredCorrectAnswers)/\(store.unlockPolicy.questionsPerSession)",
                    tint: CheckpointTheme.teal
                )
            }

            Divider()

            VStack(spacing: 10) {
                PracticeStandardStepperRow(
                    title: "Questions per practice set",
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
            }

            BreakDurationMenu(
                selectedMinutes: store.unlockPolicy.unlockMinutes,
                options: UnlockPolicy.correctAnswerUnlockMinuteOptions
            ) { minutes in
                store.updateUnlockMinutes(minutes)
            }
        }
    }

    @ViewBuilder
    private var helpAndLegalContent: some View {
        let privacyPolicyURL = AppResourceURL.configuredHTTPSValue(
            forInfoDictionaryKey: "CheckpointPrivacyPolicyURL"
        )
        let termsOfUseURL = AppResourceURL.configuredHTTPSValue(
            forInfoDictionaryKey: "CheckpointTermsOfUseURL"
        )
        let supportURL = AppResourceURL.configuredHTTPSValue(
            forInfoDictionaryKey: "CheckpointSupportURL"
        )

        VStack(alignment: .leading, spacing: 14) {
            if let privacyPolicyURL {
                legalResourceLink(
                    title: "Privacy Policy",
                    systemImage: "hand.raised",
                    destination: privacyPolicyURL
                )

                Divider()
            }

            if let termsOfUseURL {
                legalResourceLink(
                    title: "Terms of Use",
                    systemImage: "doc.text",
                    destination: termsOfUseURL
                )
            }

            if let supportURL {
                if termsOfUseURL != nil {
                    Divider()
                }

                legalResourceLink(
                    title: "Support",
                    systemImage: "questionmark.circle",
                    destination: supportURL
                )
            }

            let missingResources = [
                privacyPolicyURL == nil ? "Privacy Policy" : nil,
                termsOfUseURL == nil ? "Terms of Use" : nil,
                supportURL == nil ? "Support" : nil
            ].compactMap { $0 }

            if !missingResources.isEmpty {
                if privacyPolicyURL != nil || termsOfUseURL != nil || supportURL != nil {
                    Divider()
                }

                VStack(alignment: .leading, spacing: 5) {
                    Label("Release setup needed", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.amber)

                    Text("Configure valid HTTPS links for: \(missingResources.joined(separator: ", ")).")
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func legalResourceLink(
        title: String,
        systemImage: String,
        destination: URL
    ) -> some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 34, height: 34)
                    .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens in your browser")
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

        return "This removes \(pendingGoalDeletion.title), including its questions, Skill Map, practice history, reports, and unlock history."
    }

    private func confirmGoalDeletion() {
        guard let pendingGoalDeletion else { return }
        _ = store.deleteGoalProfile(pendingGoalDeletion.id)
        self.pendingGoalDeletion = nil
    }
}

private struct PracticeStandardStepperRow: View {
    var title: String
    var value: Int
    var decrementDisabled: Bool
    var incrementDisabled: Bool
    var decrementAction: () -> Void
    var incrementAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 8)

            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)

            HStack(spacing: 1) {
                adjustmentButton(
                    systemImage: "minus",
                    accessibilityLabel: "Decrease \(title)",
                    isDisabled: decrementDisabled,
                    action: decrementAction
                )

                adjustmentButton(
                    systemImage: "plus",
                    accessibilityLabel: "Increase \(title)",
                    isDisabled: incrementDisabled,
                    action: incrementAction
                )
            }
            .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CheckpointTheme.hairline, lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CheckpointTheme.panelRaised.opacity(0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func adjustmentButton(
        systemImage: String,
        accessibilityLabel: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isDisabled ? CheckpointTheme.muted.opacity(0.45) : CheckpointTheme.teal)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct BreakDurationMenu: View {
    var selectedMinutes: Int
    var options: [Int]
    var selectMinutes: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { minutes in
                Button {
                    selectMinutes(minutes)
                } label: {
                    Label("\(minutes) minutes", systemImage: minutes == selectedMinutes ? "checkmark" : "timer")
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 30, height: 30)
                    .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("Break after passing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)

                Text("\(selectedMinutes) min")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .monospacedDigit()
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CheckpointTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose how long protected apps open after passing a practice set.")
    }
}

private struct QuestionGenerationDiagnosticsView: View {
    let store: CheckpointStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Generation Diagnostics")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Recent prompts, providers, generated question previews, and background preparation status.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Background preparation") {
                        Text(QuestionBankBackgroundScheduler.diagnosticsSummary)
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        ShareLink(item: QuestionBankBackgroundScheduler.diagnosticsSupportText) {
                            Label("Share background details", systemImage: "square.and.arrow.up")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.teal)
                        }
                    }

                    SectionPanel("Saved data") {
                        Text(store.persistenceDiagnosticsSummary)
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Recent runs") {
                        if store.questionGenerationTraces.isEmpty {
                            EmptyGenerationDiagnosticsState()
                        } else {
                            VStack(spacing: 12) {
                                ForEach(store.questionGenerationTraces) { trace in
                                    GenerationTraceRow(trace: trace)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 32)
            }
            .checkpointScreenBackground()
            .navigationTitle("Generation")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }

                if !store.questionGenerationTraces.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        ShareLink(item: store.questionGenerationDiagnosticsSupportText) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(CheckpointTheme.teal)

                        Button("Clear", role: .destructive) {
                            store.clearQuestionGenerationDiagnostics()
                        }
                    }
                }
            }
        }
    }
}

private struct GenerationTraceRow: View {
    var trace: QuestionGenerationTrace
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                DiagnosticsKeyValueGrid(rows: [
                    ("Goal", trace.goalTitle),
                    ("Preference", trace.providerPreference.rawValue),
                    ("Provider", trace.resolvedProvider.rawValue),
                    ("Target", "\(trace.targetCount)"),
                    ("Existing", "\(trace.existingQuestionCount)"),
                    ("Generated", "\(trace.generatedQuestionCount)"),
                    ("Added", "\(trace.addedQuestionCount)"),
                    ("Retired", "\(trace.retiredQuestionCount)"),
                    ("Minimum level", "\(trace.minimumDifficulty)"),
                    ("Duration", formattedDuration(trace.duration))
                ])

                if let errorMessage = trace.errorMessage {
                    DiagnosticsTextBlock(title: "Message", text: errorMessage)
                }

                DiagnosticsTextBlock(title: "Prompt", text: trace.sourcePrompt)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Questions")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckpointTheme.muted)

                    if trace.questions.isEmpty {
                        Text("No question previews recorded.")
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                    } else {
                        ForEach(Array(trace.questions.enumerated()), id: \.element.id) { index, question in
                            GenerationQuestionPreviewRow(index: index + 1, question: question)
                        }
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trace.phase)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)

                        Text(trace.createdAt, style: .time)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    Spacer()

                    StatusBadge(
                        text: trace.usedFallback ? "Fallback" : trace.resolvedProvider.rawValue,
                        tint: trace.usedFallback ? CheckpointTheme.amber : CheckpointTheme.teal
                    )
                }

                HStack(spacing: 12) {
                    Label("\(trace.generatedQuestionCount) generated", systemImage: "sparkles")
                    Label("\(trace.addedQuestionCount) added", systemImage: "plus.circle")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
            }
        }
        .tint(CheckpointTheme.teal)
        .padding(12)
        .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "under 1s"
        }

        return "\(Int(duration.rounded()))s"
    }
}

private struct DiagnosticsKeyValueGrid: View {
    var rows: [(String, String)]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)

                    Spacer(minLength: 12)

                    Text(row.1)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct DiagnosticsTextBlock: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.muted)

            Text(text)
                .font(.caption)
                .foregroundStyle(CheckpointTheme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct GenerationQuestionPreviewRow: View {
    var index: Int
    var question: QuestionGenerationQuestionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(text: question.topic, tint: CheckpointTheme.teal)

                Spacer()

                Text("Level \(question.difficulty)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)
            }

            Text("\(index). \(question.prompt)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Choices: \(question.choices.joined(separator: " | "))")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Answer: \(question.expectedAnswer)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(question.explanation)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptyGenerationDiagnosticsState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(CheckpointTheme.amber)

            Text("No generation runs yet")
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)

            Text("Create or refresh a goal to record the next prompt and question batch.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
