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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 13) {
                    connectedMapEmblem
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
                    Text(entryDetail)
                        .font(.caption)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Label("Explore map", systemImage: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(CheckpointTheme.teal.opacity(0.08), in: Capsule())
                }
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius)
                    .fill(CheckpointTheme.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius)
                            .fill(LinearGradient(
                                colors: [CheckpointTheme.teal.opacity(0.045), .clear, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius)
                    .strokeBorder(LinearGradient(
                        colors: [CheckpointTheme.teal.opacity(0.22), CheckpointTheme.hairline],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 1)
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

    private var entryDetail: String {
        summary.hasSuggestion || summary.milestoneCount > 0
            ? summary.detail
            : "Explore • Grow • Make it yours"
    }

    private var connectedMapEmblem: some View {
        Canvas { context, size in
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: size.width * x, y: size.height * y)
            }
            let goal = point(0.25, 0.53)
            let upperSkill = point(0.58, 0.27)
            let lowerSkill = point(0.65, 0.71)
            let upperFocus = point(0.86, 0.18)
            let middleFocus = point(0.86, 0.43)
            let lowerFocus = point(0.88, 0.85)

            func connection(_ start: CGPoint, _ end: CGPoint, primary: Bool) {
                var path = Path()
                path.move(to: start)
                let bend = (end.x - start.x) * 0.55
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x + bend, y: start.y),
                    control2: CGPoint(x: end.x - bend, y: end.y)
                )
                context.stroke(
                    path,
                    with: .color(CheckpointTheme.teal.opacity(primary ? 0.6 : 0.35)),
                    style: StrokeStyle(lineWidth: primary ? 1.6 : 1.1, lineCap: .round)
                )
            }
            connection(goal, upperSkill, primary: true)
            connection(goal, lowerSkill, primary: true)
            connection(upperSkill, upperFocus, primary: false)
            connection(upperSkill, middleFocus, primary: false)
            connection(lowerSkill, lowerFocus, primary: false)

            func node(_ center: CGPoint, radius: CGFloat, color: Color, filled: Bool) {
                let bounds = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: bounds), with: .color(filled ? color : CheckpointTheme.panel))
                context.stroke(Path(ellipseIn: bounds), with: .color(color), lineWidth: 1.2)
            }
            let halo = CGRect(x: goal.x - 11, y: goal.y - 11, width: 22, height: 22)
            context.fill(Path(ellipseIn: halo), with: .color(CheckpointTheme.teal.opacity(0.08)))
            node(goal, radius: 6.2, color: CheckpointTheme.teal, filled: true)
            node(upperSkill, radius: 4.6, color: CheckpointTheme.teal, filled: false)
            node(lowerSkill, radius: 4.6, color: CheckpointTheme.blue, filled: false)
            node(upperFocus, radius: 2.3, color: CheckpointTheme.teal.opacity(0.75), filled: true)
            node(middleFocus, radius: 2.3, color: CheckpointTheme.teal.opacity(0.75), filled: true)
            node(lowerFocus, radius: 2.3, color: CheckpointTheme.blue.opacity(0.75), filled: true)
            context.fill(
                Path(ellipseIn: CGRect(x: goal.x - 1.5, y: goal.y - 1.5, width: 3, height: 3)),
                with: .color(CheckpointTheme.panel)
            )
        }
        .frame(width: 50, height: 50)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(LinearGradient(
                    colors: [CheckpointTheme.teal.opacity(0.1), CheckpointTheme.blue.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .accessibilityHidden(true)
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
                },
                isCovered: editorDestination != nil
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
