import SwiftUI

struct LearningMapDestination: Identifiable, Equatable {
    let id: UUID
    let goalID: Goal.ID
    let initialSkillID: SkillMapTopic.ID?

    init(goalID: Goal.ID, initialSkillID: SkillMapTopic.ID? = nil, id: UUID = UUID()) {
        self.id = id
        self.goalID = goalID
        self.initialSkillID = initialSkillID
    }

    @MainActor static func resolve(target: ProgressSkillEvidenceTarget, goal: Goal?) -> Self? {
        guard let goal, goal.id == target.goalID, let map = goal.derivedSkillMap else { return nil }
        if let id = target.skillID {
            guard map.topics.contains(where: { $0.id == id }) else { return nil }
            return Self(goalID: goal.id, initialSkillID: id)
        }
        let key = SkillMapReconciler.competencyTopicKey(target.skillName)
        guard !key.isEmpty,
              let topic = map.topics.first(where: {
                  SkillMapReconciler.competencyTopicKey($0.name) == key
                      || $0.aliases.contains { SkillMapReconciler.competencyTopicKey($0) == key }
              }) else { return nil }
        return Self(goalID: goal.id, initialSkillID: topic.id)
    }
}

struct LearningMapEntrySummary: Equatable {
    let skillCount: Int
    let practicedCount: Int
    let strongCount: Int
    let pausedCount: Int
    let milestoneCount: Int
    let hasSuggestion: Bool

    @MainActor init(map: GoalSkillMap, competencies: [TopicCompetency]) {
        skillCount = map.topics.count
        let matching = map.topics.compactMap { topic in
            competencies.first { $0.skillID == topic.id }
                ?? competencies.first {
                    $0.skillID == nil && SkillMapReconciler.competencyTopicKey($0.topic)
                        == SkillMapReconciler.competencyTopicKey(topic.name)
                }
        }
        practicedCount = matching.filter { $0.attempts > 0 }.count
        strongCount = matching.filter { CompetencyProgressBand.resolve(for: $0) == .strong }.count
        pausedCount = map.topics.filter(\.isPaused).count
        milestoneCount = map.archivedTopics.filter { $0.reason == .mastered }.count
        hasSuggestion = map.pendingEvolutionSuggestion != nil
    }

    var summary: String {
        var parts = ["\(practicedCount) of \(skillCount) skills practiced"]
        if strongCount > 0 { parts.append("\(strongCount) strong") }
        if pausedCount > 0 { parts.append("\(pausedCount) paused") }
        return parts.joined(separator: " · ")
    }

    var detail: String {
        if hasSuggestion { return "New next steps ready to review" }
        if milestoneCount > 0 {
            return "\(milestoneCount) earned \(milestoneCount == 1 ? "milestone" : "milestones") in your journey"
        }
        return "Explore your skills and shape what comes next"
    }
}

struct LearningMapEntryCard: View {
    let summary: LearningMapEntrySummary
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(CheckpointTheme.teal)
                        .frame(width: 50, height: 50)
                        .background(CheckpointTheme.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Learning map")
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                        Text(summary.summary)
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                let footerLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
                footerLayout {
                    Text(summary.detail)
                        .font(.caption)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Label("View map", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(18)
            .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius)
                    .strokeBorder(CheckpointTheme.hairline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius))
        }
        .buttonStyle(CheckpointPressButtonStyle(role: .surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Learning map")
        .accessibilityValue(summary.summary + ". " + summary.detail)
        .accessibilityHint("Opens your interactive map, focus points, progress, and editing controls.")
        .accessibilityIdentifier("progress-learning-map-entry")
    }
}

struct LearningMapContainerView: View {
    let store: CheckpointStore
    let destination: LearningMapDestination

    private struct EditorDestination: Identifiable {
        let id = UUID()
        let context: SkillMapReviewContext
        let initialSkillID: SkillMapTopic.ID?
    }

    @Environment(\.dismiss) private var dismiss
    @State private var editorDestination: EditorDestination?

    var body: some View {
        NavigationStack {
            LearningMapView(
                store: store,
                goalID: destination.goalID,
                initialSkillID: destination.initialSkillID,
                onEdit: { skillID in
                    guard store.goal?.id == destination.goalID,
                          let context = SkillMapReviewContext(goal: store.goal) else { return }
                    editorDestination = EditorDestination(context: context, initialSkillID: skillID)
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close learning map")
                }
            }
        }
        .tint(CheckpointTheme.teal)
        .sheet(item: $editorDestination) { editor in
            LearningMapEditorView(store: store, context: editor.context, initialSkillID: editor.initialSkillID)
        }
        .onChange(of: store.goal?.id) { _, id in
            if id != destination.goalID { dismiss() }
        }
    }
}
