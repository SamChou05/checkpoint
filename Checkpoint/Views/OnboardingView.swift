import SwiftUI

struct OnboardingView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var title = "Pass a coding interview in 8 weeks"
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date()
    @State private var category: GoalCategory = .codingInterview
    @State private var currentLevel = "Basic Python. Comfortable with loops, shaky on recursion."
    @State private var focusAreas = "arrays, recursion, Big-O, hash maps"
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Build your checkpoint loop")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Type the goal clearly. The app turns it into stored questions that can come back when you miss them.")
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

                        DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                            .foregroundStyle(CheckpointTheme.text)

                        Picker("Category", selection: $category) {
                            ForEach(GoalCategory.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                    }

                    SectionPanel("AI context") {
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
                            Text("Question style")
                                .foregroundStyle(CheckpointTheme.muted)
                            Spacer()
                            StatusBadge(text: QuestionFormat.multipleChoice.rawValue, tint: CheckpointTheme.teal)
                        }
                    }

                    PrimaryActionButton(
                        title: isCreating ? "Generating questions" : "Generate question bank",
                        systemImage: "sparkles"
                    ) {
                        Task {
                            isCreating = true
                            await store.createGoal(
                                title: title,
                                deadline: deadline,
                                category: category,
                                currentLevel: currentLevel,
                                focusAreas: focusAreas,
                                preferredQuestionStyle: .multipleChoice
                            )
                            isCreating = false
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if store.goal != nil {
                        Button("Done") {
                            store.isOnboardingPresented = false
                            dismiss()
                        }
                        .foregroundStyle(CheckpointTheme.teal)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
