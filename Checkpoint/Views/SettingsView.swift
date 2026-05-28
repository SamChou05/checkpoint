import SwiftUI

struct SettingsView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController

    @State private var isRestrictedAppsPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Settings")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Keep the MVP strict, simple, and easy to test.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    SectionPanel("Goal") {
                        if let goal = store.goal {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(goal.title)
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("\(goal.category.rawValue) - \(goal.focusAreas)")
                                    .font(.subheadline)
                                    .foregroundStyle(CheckpointTheme.muted)
                            }
                        }

                        SecondaryActionButton(title: "Edit goal setup", systemImage: "pencil") {
                            store.isOnboardingPresented = true
                        }
                    }

                    SectionPanel("Screen Time") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Status")
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

                            SecondaryActionButton(title: "Request setup", systemImage: "shield") {
                                Task {
                                    await screenTime.requestAuthorization()
                                }
                            }

                            SecondaryActionButton(title: "Choose restricted apps", systemImage: "checklist") {
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

                    SectionPanel("Launch readiness") {
                        VStack(alignment: .leading, spacing: 12) {
                            readinessRow(
                                title: "Goal",
                                detail: store.goal?.title ?? "Missing",
                                isReady: store.goal != nil
                            )

                            readinessRow(
                                title: "Questions",
                                detail: "\(store.questions.count) stored",
                                isReady: store.questions.count >= store.unlockPolicy.questionsPerSession
                            )

                            readinessRow(
                                title: "Screen Time",
                                detail: screenTime.setupState.rawValue,
                                isReady: screenTime.isReadyForShielding
                            )

                            readinessRow(
                                title: "Restricted apps",
                                detail: screenTime.restrictedAppsSummary,
                                isReady: screenTime.hasSelection
                            )

                            readinessRow(
                                title: "Unlock window",
                                detail: "\(store.unlockPolicy.unlockMinutes)m default",
                                isReady: store.unlockPolicy.unlockMinutes >= 15
                            )
                        }
                    }

                    SectionPanel("Strictness") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Checkpoint threshold")
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("\(store.unlockPolicy.requiredCorrectAnswers) of \(store.unlockPolicy.questionsPerSession) correct to unlock")
                                    .font(.subheadline)
                                    .foregroundStyle(CheckpointTheme.muted)

                                Stepper("Questions in set: \(store.unlockPolicy.questionsPerSession)", value: questionsPerSessionBinding, in: 1...10)
                                    .foregroundStyle(CheckpointTheme.text)

                                Stepper("Correct needed: \(store.unlockPolicy.requiredCorrectAnswers)", value: requiredCorrectAnswersBinding, in: 1...store.unlockPolicy.questionsPerSession)
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Question difficulty")
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("Levels run 1 to 5. Start at \(difficultyLabel(for: store.unlockPolicy.minimumQuestionDifficulty)) or higher.")
                                    .font(.subheadline)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)

                                Stepper("Minimum: \(difficultyLabel(for: store.unlockPolicy.minimumQuestionDifficulty))", value: minimumQuestionDifficultyBinding, in: 1...5)
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Correct-answer unlock")
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
                                    Text("Emergency Pass")
                                        .font(.headline)
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text("\(store.emergencyPassesRemaining) remaining this week")
                                        .font(.subheadline)
                                        .foregroundStyle(CheckpointTheme.muted)

                                    if !screenTime.isShieldingEnabled {
                                        Text("Available while shields are active")
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

                    SectionPanel("Questions") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Status")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text(store.questionBatchState.rawValue.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            HStack {
                                Text("Reports")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text("\(store.reportedQuestionCount)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            SecondaryActionButton(title: "Refresh question batch", systemImage: "arrow.clockwise") {
                                Task {
                                    await store.refreshQuestionBatch()
                                }
                            }
                        }
                    }

                    SectionPanel("Developer") {
                        SecondaryActionButton(title: "Reset local prototype data", systemImage: "arrow.counterclockwise") {
                            screenTime.clearShield()
                            store.resetDemoData()
                        }
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
        }
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

    private var minimumQuestionDifficultyBinding: Binding<Int> {
        Binding(
            get: { store.unlockPolicy.minimumQuestionDifficulty },
            set: { store.updateMinimumQuestionDifficulty($0) }
        )
    }

    private func readinessRow(title: String, detail: String, isReady: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isReady ? CheckpointTheme.teal : CheckpointTheme.amber)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func difficultyLabel(for level: Int) -> String {
        switch level {
        case 1:
            return "Level 1 of 5 (Basics)"
        case 2:
            return "Level 2 of 5 (Easy)"
        case 3:
            return "Level 3 of 5 (Medium)"
        case 4:
            return "Level 4 of 5 (Hard)"
        default:
            return "Level 5 of 5 (Expert)"
        }
    }
}
