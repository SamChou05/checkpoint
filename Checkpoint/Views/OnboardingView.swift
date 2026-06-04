import SwiftUI

struct OnboardingView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date()
    @State private var focusAreas = ""
    @State private var minimumQuestionDifficulty = UnlockPolicy.default.minimumQuestionDifficulty
    @State private var isCreating = false

    init(store: CheckpointStore) {
        self.store = store

        if let goal = store.goal, !store.isCreatingGoalProfile {
            _title = State(initialValue: goal.title)
            _deadline = State(initialValue: max(goal.deadline, Date()))
            _focusAreas = State(initialValue: goal.focusAreas)
            _minimumQuestionDifficulty = State(initialValue: goal.minimumQuestionDifficulty)
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
                    }

                    SectionPanel("Focus areas") {
                        TextField("Focus areas, separated by commas", text: $focusAreas, axis: .vertical)
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

                        HStack {
                            Text("Format")
                                .foregroundStyle(CheckpointTheme.muted)
                            Spacer()
                            StatusBadge(text: QuestionFormat.multipleChoice.rawValue, tint: CheckpointTheme.teal)
                        }
                    }

                    SectionPanel("Question level") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Begin practice at \(Goal.difficultyLabel(for: minimumQuestionDifficulty)) or higher.")
                                .font(.subheadline)
                                .foregroundStyle(CheckpointTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            Stepper(
                                "Minimum: \(Goal.difficultyLabel(for: minimumQuestionDifficulty))",
                                value: $minimumQuestionDifficulty,
                                in: 1...5
                            )
                            .foregroundStyle(CheckpointTheme.text)
                        }
                    }

                    PrimaryActionButton(
                        title: primaryButtonTitle,
                        systemImage: "book.closed"
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
                            dismiss()
                        }
                    }
                    .disabled(isCreating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if store.goal != nil {
                        Button("Done") {
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
            return "Name the goal, choose the practice areas, and set the level. Checkpoint keeps each goal's practice separate."
        }

        return "Refine this goal so future practice matches your current preparation."
    }

    private var primaryButtonTitle: String {
        if isCreating {
            return "Saving goal"
        }

        return isNewProfile ? "Create goal" : "Update goal"
    }

    private var isNewProfile: Bool {
        store.goal == nil || store.isCreatingGoalProfile
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
