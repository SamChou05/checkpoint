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
                                Text("Question level")
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("Start at Level \(store.unlockPolicy.minimumQuestionDifficulty) or higher")
                                    .font(.subheadline)
                                    .foregroundStyle(CheckpointTheme.muted)

                                Stepper("Minimum level: \(store.unlockPolicy.minimumQuestionDifficulty)", value: minimumQuestionDifficultyBinding, in: 1...5)
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
                                }

                                Spacer()

                                Button {
                                    store.useEmergencyPass()
                                } label: {
                                    Image(systemName: "cross.case")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(CheckpointTheme.paper)
                                        .frame(width: 42, height: 42)
                                        .background(CheckpointTheme.amber, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(store.emergencyPassesRemaining == 0)
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

}
