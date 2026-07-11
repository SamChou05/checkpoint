import SwiftUI

struct OnboardingView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date()
    @State private var focusAreas = ""
    @State private var minimumQuestionDifficulty = UnlockPolicy.default.minimumQuestionDifficulty
    @State private var isCreating = false
    @State private var isCustomizationExpanded = false

    init(store: CheckpointStore) {
        self.store = store

        if let goal = store.goal, !store.isCreatingGoalProfile {
            _title = State(initialValue: goal.title)
            _deadline = State(initialValue: max(goal.deadline, Date()))
            _focusAreas = State(initialValue: goal.focusAreas)
            _minimumQuestionDifficulty = State(initialValue: goal.minimumQuestionDifficulty)
            _isCustomizationExpanded = State(
                initialValue: !goal.focusAreas.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || goal.minimumQuestionDifficulty != UnlockPolicy.default.minimumQuestionDifficulty
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isNewProfile ? "Create a goal" : "Update goal")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text(headerSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Goal") {
                        TextField("Goal", text: $title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                            .padding(12)
                            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                        DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .foregroundStyle(CheckpointTheme.text)

                        if shouldShowGoalInterpretation,
                           let interpretation = setupGuidance.interpretation {
                            Label("We'll prepare \(interpretation.lowercased()).", systemImage: "sparkles")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.teal)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SectionPanel {
                        DisclosureGroup(isExpanded: $isCustomizationExpanded) {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Topics to focus on")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text("Optional. Leave this blank and we'll choose from your goal.")
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.muted)

                                    TextField("For example: contracts, vocabulary", text: $focusAreas, axis: .vertical)
                                        .lineLimit(3, reservesSpace: true)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(CheckpointTheme.text)
                                        .padding(12)
                                        .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                                    if !parsedFocusAreas.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(parsedFocusAreas, id: \.self) { focusArea in
                                                    FocusAreaChip(text: focusArea)
                                                }
                                            }
                                            .padding(.vertical, 2)
                                        }
                                    }
                                }

                                Divider()

                                Stepper(
                                    "Starting level: \(Goal.difficultyLabel(for: minimumQuestionDifficulty))",
                                    value: $minimumQuestionDifficulty,
                                    in: 1...5
                                )
                                .foregroundStyle(CheckpointTheme.text)
                            }
                            .padding(.top, 12)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Customize practice")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("Optional topics and starting level")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                            }
                        }
                        .tint(CheckpointTheme.teal)
                    }

                    PrimaryActionButton(
                        title: primaryButtonTitle,
                        systemImage: "book.closed",
                        isLoading: isCreating
                    ) {
                        Task {
                            guard !isCreating else { return }
                            isCreating = true
                            await store.createGoal(
                                title: title,
                                deadline: deadline,
                                currentLevel: "",
                                focusAreas: focusAreas,
                                preferredQuestionStyle: .multipleChoice,
                                minimumQuestionDifficulty: minimumQuestionDifficulty,
                                createsNewProfile: isNewProfile,
                                waitForQuestionGeneration: false
                            )
                            isCreating = false
                            if !store.isOnboardingPresented {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        isCreating
                            || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if store.goal != nil {
                        Button("Cancel") {
                            store.isCreatingGoalProfile = false
                            store.isOnboardingPresented = false
                            dismiss()
                        }
                        .foregroundStyle(CheckpointTheme.teal)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .onDisappear {
            if !store.isOnboardingPresented {
                store.isCreatingGoalProfile = false
            }
        }
    }

    private var headerSubtitle: String {
        if isNewProfile {
            return "Tell us what you're working toward. We'll handle the practice details."
        }

        return "Update what you're working toward."
    }

    private var primaryButtonTitle: String {
        return isNewProfile ? "Create goal" : "Save changes"
    }

    private var isNewProfile: Bool {
        store.goal == nil || store.isCreatingGoalProfile
    }

    private var setupGuidance: GoalSetupGuidance {
        GoalSetupGuidance(title: title, focusAreas: focusAreas)
    }

    private var shouldShowGoalInterpretation: Bool {
        parsedFocusAreas.isEmpty && setupGuidance.interpretation != nil
    }

    private var parsedFocusAreas: [String] {
        focusAreas
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct FocusAreaChip: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
    }
}
