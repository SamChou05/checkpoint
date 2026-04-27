import SwiftUI

struct HomeView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController

    @State private var activeQuestion: CheckpointQuestion?
    @State private var isRestrictedAppsPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let goal = store.goal {
                        goalHero(goal)
                        metricsGrid
                        nextCheckpointPanel
                        screenTimePanel
                    } else {
                        emptyState
                    }
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Checkpoint")
            .toolbarTitleDisplayMode(.inline)
            .sheet(item: $activeQuestion) { question in
                CheckpointAttemptView(store: store, screenTime: screenTime, question: question)
            }
            .sheet(isPresented: $isRestrictedAppsPresented) {
                RestrictedAppsView(screenTime: screenTime)
            }
            .onAppear {
                activeQuestion = store.takePendingShieldQuestion()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Progress before distraction")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)

                Text("Clear a checkpoint before you scroll.")
                    .font(.largeTitle.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(CheckpointTheme.amber)
                .frame(width: 48, height: 48)
                .background(CheckpointTheme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.top, 8)
    }

    private func goalHero(_ goal: Goal) -> some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    StatusBadge(text: goal.category.rawValue, tint: CheckpointTheme.teal)
                    Spacer()
                    Text(goal.deadline, style: .date)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)
                }

                Text(goal.title)
                    .font(.title2.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Focus: \(goal.focusAreas.isEmpty ? "next meaningful rep" : goal.focusAreas)")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryActionButton(title: "Simulate blocked app attempt", systemImage: "lock.open") {
                    activeQuestion = store.nextQuestion()
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(
                title: "Checkpoints today",
                value: "\(store.completedTodayCount)",
                tint: CheckpointTheme.teal,
                systemImage: "checkmark.seal"
            )

            MetricTile(
                title: "Conversion rate",
                value: store.conversionRateText,
                tint: CheckpointTheme.amber,
                systemImage: "arrow.triangle.2.circlepath"
            )

            MetricTile(
                title: "Average mastery",
                value: store.averageMasteryText,
                tint: .blue,
                systemImage: "chart.line.uptrend.xyaxis"
            )

            MetricTile(
                title: "Unlock remaining",
                value: "\(store.activeUnlockMinutesRemaining)m",
                tint: CheckpointTheme.coral,
                systemImage: "timer"
            )
        }
    }

    private var nextCheckpointPanel: some View {
        SectionPanel("Next checkpoint") {
            if let question = store.nextQuestion() {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        StatusBadge(text: question.topic, tint: CheckpointTheme.amber)
                        Spacer()
                        Text("Level \(question.difficulty)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    Text(question.prompt)
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Missed and due questions are prioritized before new AI-generated questions.")
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                }
            } else {
                Text("Create a goal to generate your first question bank.")
                    .foregroundStyle(CheckpointTheme.muted)
            }
        }
    }

    private var screenTimePanel: some View {
        SectionPanel("Restricted apps") {
            VStack(alignment: .leading, spacing: 12) {
                Text(screenTime.restrictedAppsSummary)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.text)

                SecondaryActionButton(title: "Prepare Screen Time setup", systemImage: "app.badge") {
                    Task {
                        await screenTime.requestAuthorization()
                    }
                }

                HStack(spacing: 10) {
                    SecondaryActionButton(title: "Choose apps", systemImage: "checklist") {
                        isRestrictedAppsPresented = true
                    }

                    SecondaryActionButton(title: screenTime.isShieldingEnabled ? "Pause shield" : "Apply shield", systemImage: screenTime.isShieldingEnabled ? "pause" : "shield") {
                        if screenTime.isShieldingEnabled {
                            screenTime.clearShield()
                        } else {
                            screenTime.applyShield()
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Set one goal first.")
                    .font(.title2.bold())
                    .foregroundStyle(CheckpointTheme.text)

                    Text("Checkpoint will use it to generate a multiple-choice question bank, then ask the right question when a restricted app is opened.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryActionButton(title: "Create goal", systemImage: "plus") {
                    store.isOnboardingPresented = true
                }
            }
        }
    }
}
