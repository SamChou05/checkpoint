import SwiftUI

struct OnboardingView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date()
    @State private var category: GoalCategory = .codingInterview
    @State private var currentLevel = ""
    @State private var focusAreas = ""
    @State private var minimumQuestionDifficulty = UnlockPolicy.default.minimumQuestionDifficulty
    @State private var isCreating = false

    init(store: CheckpointStore) {
        self.store = store

        if let goal = store.goal, !store.isCreatingGoalProfile {
            _title = State(initialValue: goal.title)
            _deadline = State(initialValue: max(goal.deadline, Date()))
            _category = State(initialValue: goal.category)
            _currentLevel = State(initialValue: goal.currentLevel)
            _focusAreas = State(initialValue: goal.focusAreas)
            _minimumQuestionDifficulty = State(initialValue: goal.minimumQuestionDifficulty)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isNewProfile ? "Create a goal profile" : "Update goal profile")
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

                        Picker("Category", selection: $category) {
                            ForEach(GoalCategory.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                    }

                    SectionPanel("Study context") {
                        TextField("Current level", text: $currentLevel, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .textFieldStyle(.plain)
                            .foregroundStyle(CheckpointTheme.text)
                            .padding(12)
                            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                        TextField("Focus areas, separated by commas", text: $focusAreas, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .textFieldStyle(.plain)
                            .foregroundStyle(CheckpointTheme.text)
                            .padding(12)
                            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                        HStack {
                            Text("Format")
                                .foregroundStyle(CheckpointTheme.muted)
                            Spacer()
                            StatusBadge(text: QuestionFormat.multipleChoice.rawValue, tint: CheckpointTheme.teal)
                        }
                    }

                    SectionPanel("Question level") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start checkpoints at \(Goal.difficultyLabel(for: minimumQuestionDifficulty)) or higher.")
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
                                category: category,
                                currentLevel: currentLevel,
                                focusAreas: focusAreas,
                                preferredQuestionStyle: .multipleChoice,
                                minimumQuestionDifficulty: minimumQuestionDifficulty,
                                createsNewProfile: isNewProfile
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
            return "Set the goal, context, and level once. Checkpoint keeps its questions and skill map separate from your other profiles."
        }

        return "Adjust the active profile so future questions match your current preparation level."
    }

    private var primaryButtonTitle: String {
        if isCreating {
            return "Preparing questions"
        }

        return isNewProfile ? "Create profile" : "Update profile"
    }

    private var isNewProfile: Bool {
        store.goal == nil || store.isCreatingGoalProfile
    }
}
