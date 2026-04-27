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
                                Text("Correct-answer unlock")
                                    .font(.headline)
                                    .foregroundStyle(CheckpointTheme.text)

                                Picker("Unlock minutes", selection: unlockMinutesBinding) {
                                    ForEach([1, 3, 5, 10, 15], id: \.self) { minutes in
                                        Text("\(minutes)m").tag(minutes)
                                    }
                                }
                                .pickerStyle(.segmented)
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
                                        .foregroundStyle(.black)
                                        .frame(width: 42, height: 42)
                                        .background(CheckpointTheme.amber, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(store.emergencyPassesRemaining == 0)
                            }
                        }
                    }

                    SectionPanel("Question bank") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("AI provider", selection: aiProviderBinding) {
                                ForEach(AIProviderKind.allCases) { provider in
                                    Text(provider.rawValue).tag(provider)
                                }
                            }
                            .pickerStyle(.menu)

                            TextField("Backend endpoint URL", text: backendEndpointBinding)
                                .textFieldStyle(.plain)
                                .foregroundStyle(CheckpointTheme.text)
                                .padding(12)
                                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                            HStack {
                                Text("Batch state")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text(store.questionBatchState.rawValue.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            HStack {
                                Text("Last provider")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text(store.lastQuestionProvider.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            HStack {
                                Text("Quality reports")
                                    .foregroundStyle(CheckpointTheme.muted)
                                Spacer()
                                Text("\(store.reportedQuestionCount)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                            }

                            if let message = store.lastAIErrorMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            SecondaryActionButton(title: "Refresh question batch", systemImage: "sparkles") {
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

    private var aiProviderBinding: Binding<AIProviderKind> {
        Binding(
            get: { store.aiProviderPreference },
            set: { store.updateAIProviderPreference($0) }
        )
    }

    private var backendEndpointBinding: Binding<String> {
        Binding(
            get: { store.backendEndpoint },
            set: { store.updateBackendEndpoint($0) }
        )
    }
}
