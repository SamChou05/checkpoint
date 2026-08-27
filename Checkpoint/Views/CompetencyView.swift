import SwiftUI

struct CompetencyView: View {
    let store: CheckpointStore
    @State private var isSkillMapEditorPresented = false
    @State private var isSkillMapRepairPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let skillMap = store.activeDerivedSkillMap {
                        skillMapPanel(skillMap)
                    }

                    if store.isBuildingActiveSkillMap {
                        buildingSkillMapState
                    } else if store.activeSkillMapNeedsAttention {
                        skillMapAttentionState
                    }

                    if !store.isBuildingActiveSkillMap && !store.sortedCompetencies.isEmpty {
                        Text("See what's strong and what to practice next. Topics needing attention appear first.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(store.sortedCompetencies) { competency in
                            CompetencyRow(competency: competency)
                        }
                    } else if !store.isBuildingActiveSkillMap &&
                                !store.activeSkillMapNeedsAttention &&
                                store.sortedCompetencies.isEmpty {
                        emptyState
                    }
                }
                .padding(20)
                .padding(.bottom, 56)
            }
            .padding(.bottom, 48)
            .checkpointScreenBackground()
            .navigationTitle("Progress")
            .toolbarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $isSkillMapEditorPresented) {
            SkillMapReviewView(store: store)
        }
        .sheet(isPresented: $isSkillMapRepairPresented) {
            SkillMapRepairView(store: store)
        }
    }

    private func skillMapPanel(_ skillMap: GoalSkillMap) -> some View {
        SectionPanel("Skill map") {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(skillMap.status == .suggested ? "Suggested from your goal" : "Your reviewed skills")
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                        Spacer()
                        StatusBadge(
                            text: skillMap.status == .suggested ? "AI-inferred" : "Reviewed",
                            tint: skillMap.status == .suggested ? CheckpointTheme.blue : CheckpointTheme.teal
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(skillMap.status == .suggested ? "Suggested from your goal" : "Your reviewed skills")
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                        StatusBadge(
                            text: skillMap.status == .suggested ? "AI-inferred" : "Reviewed",
                            tint: skillMap.status == .suggested ? CheckpointTheme.blue : CheckpointTheme.teal
                        )
                    }
                }

                Text(
                    skillMap.status == .suggested
                        ? "Checkpoint inferred these skills from your goal and first practice set. Review the names to make future practice more precise."
                        : "These stable skill areas organize future questions and preserve your progress across refreshes."
                )
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(skillMap.topics) { topic in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(topic.name, systemImage: "circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .symbolRenderingMode(.hierarchical)

                            if !topic.objectives.isEmpty {
                                Text(topic.objectives.prefix(3).map(\.name).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, 22)
                            }
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        if skillMap.status == .suggested {
                            skillMapButton(title: "Looks good", systemImage: "checkmark") {
                                store.confirmActiveDerivedSkillMap()
                            }
                        }
                        skillMapButton(title: "Review skills", systemImage: "slider.horizontal.3") {
                            isSkillMapEditorPresented = true
                        }
                    }

                    VStack(spacing: 10) {
                        if skillMap.status == .suggested {
                            skillMapButton(title: "Looks good", systemImage: "checkmark") {
                                store.confirmActiveDerivedSkillMap()
                            }
                        }
                        skillMapButton(title: "Review skills", systemImage: "slider.horizontal.3") {
                            isSkillMapEditorPresented = true
                        }
                    }
                }
            }
        }
    }

    private func skillMapButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(CheckpointTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private var buildingSkillMapState: some View {
        SectionPanel {
            HStack(alignment: .top, spacing: 14) {
                ProgressView()
                    .tint(CheckpointTheme.teal)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Building your skill map…")
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.text)

                    Text("Checkpoint is turning your goal into concrete skills. They’ll appear here with your first practice set.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Building your skill map")
    }

    private var skillMapAttentionState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.amber)

                Text("Your skill map needs more detail")
                    .font(.title3.bold())
                    .foregroundStyle(CheckpointTheme.text)

                Text("The first suggestions were too broad to track honestly. Add a few focus areas and Checkpoint will keep future progress organized around them.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryActionButton(title: "Add focus areas", systemImage: "plus") {
                    isSkillMapRepairPresented = true
                }
            }
        }
    }

    private var emptyState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.amber)

                Text("No progress yet")
                    .font(.title3.bold())
                    .foregroundStyle(CheckpointTheme.text)

                Text("Complete a few practice questions to see what to review next.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
