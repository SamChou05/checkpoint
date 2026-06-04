import SwiftUI

struct SettingsView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController

    @State private var isRestrictedAppsPresented = false
    @State private var isHistoryPresented = false
    @State private var isQuestionReportsPresented = false
    @State private var isGenerationDiagnosticsPresented = false
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

                    SectionPanel("Membership") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(store.membershipTier.displayName)
                                        .font(.headline)
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text(membershipDetailText)
                                        .font(.subheadline)
                                        .foregroundStyle(CheckpointTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                StatusBadge(
                                    text: store.isMember ? "Active" : "First goal",
                                    tint: store.isMember ? CheckpointTheme.teal : CheckpointTheme.amber
                                )
                            }

                            if !store.isMember {
                                SecondaryActionButton(title: "Start membership", systemImage: "sparkles") {
                                    store.requestMembership(for: .freshQuestionGeneration)
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

                                        if let focusText = store.activeGoalFocusText {
                                            Text("Focus: \(focusText)")
                                                .font(.subheadline)
                                                .foregroundStyle(CheckpointTheme.muted)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
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

                            SecondaryActionButton(title: "New goal", systemImage: "plus") {
                                store.presentGoalProfileCreator()
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

                                Stepper(
                                    "Correct answers needed: \(store.unlockPolicy.requiredCorrectAnswers)",
                                    value: requiredCorrectAnswersBinding,
                                    in: UnlockPolicy.minimumRequiredCorrectAnswers...store.unlockPolicy.questionsPerSession
                                )
                                    .foregroundStyle(CheckpointTheme.text)
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

                                SettingsNavigationRow(
                                    title: "Generation diagnostics",
                                    detail: store.questionGenerationDiagnosticsSummary,
                                    systemImage: "text.magnifyingglass",
                                    trailingText: "\(store.questionGenerationTraces.count)"
                                ) {
                                    isGenerationDiagnosticsPresented = true
                                }

                                Divider()

                                Text("Stopping blocking requires a longer 20-question challenge with at least 18 correct. Home also opens this challenge from Blocking active.")
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
            .sheet(isPresented: $isQuestionReportsPresented) {
                QuestionReportsView(store: store)
            }
            .sheet(isPresented: $isGenerationDiagnosticsPresented) {
                QuestionGenerationDiagnosticsView(store: store)
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
        }
    }

    private var canStopBlocking: Bool {
        screenTime.isShieldingEnabled || screenTime.setupState == .temporarilyUnlocked
    }

    private var shouldShowScreenTimeAuthorizationButton: Bool {
        screenTime.setupState == .notStarted || screenTime.setupState == .failed
    }

    private var goalCountText: String {
        let count = store.availableGoalProfiles.count
        return count == 1 ? "1 goal" : "\(count) goals"
    }

    private var membershipDetailText: String {
        if store.isMember {
            return "Fresh checkpoints, goal profiles, larger question banks, and Study Assist are active."
        }

        return "Your first goal and starter checkpoints are included. Membership keeps new questions flowing and unlocks goal switching."
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

                        Text("Recent prompts, providers, and generated question previews.")
                            .font(.subheadline)
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
                        ShareLink(item: store.questionGenerationDiagnosticsExportText) {
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
