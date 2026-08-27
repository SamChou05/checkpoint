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

struct SkillMapReviewView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var topics: [SkillMapTopic]

    init(store: CheckpointStore) {
        self.store = store
        _topics = State(initialValue: store.activeDerivedSkillMap?.topics ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Review your skill map")
                            .font(.title2.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Edit a name to rename a skill and preserve its progress. Use Replace when the subject itself changes; that starts fresh questions and mastery.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Skill names") {
                        VStack(spacing: 12) {
                            ForEach(Array(topics.indices), id: \.self) { index in
                                HStack(spacing: 10) {
                                    TextField("Skill \(index + 1)", text: $topics[index].name)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(CheckpointTheme.text)
                                        .padding(12)
                                        .background(
                                            CheckpointTheme.panelRaised,
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                        .accessibilityLabel("Skill \(index + 1) name")

                                    if topics.count > 3 {
                                        Button {
                                            topics.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(CheckpointTheme.coral)
                                                .frame(width: 44, height: 44)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove skill \(index + 1)")
                                    }
                                }

                                if !topics[index].objectives.isEmpty {
                                    Text(topics[index].objectives.prefix(3).map(\.name).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(CheckpointTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if existingSkillIDs.contains(topics[index].id) {
                                    Button {
                                        topics[index] = SkillMapTopic(name: "")
                                    } label: {
                                        Label("Replace this skill", systemImage: "arrow.triangle.2.circlepath")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(CheckpointTheme.amber)
                                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Retires this skill's questions and starts new progress")
                                }
                            }

                            if topics.count < 6 {
                                Button {
                                    topics.append(SkillMapTopic(name: ""))
                                } label: {
                                    Label("Add another skill", systemImage: "plus")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(CheckpointTheme.teal)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !isValid {
                            Text("Use a unique name up to 48 characters for every skill. Commas and semicolons aren’t supported in skill names.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.coral)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 96)
            }
            .checkpointScreenBackground()
            .navigationTitle("Skill Map")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Use this skill map", systemImage: "checkmark") {
                    if store.reviewActiveDerivedSkillMap(topics: topics) {
                        dismiss()
                    }
                }
                .disabled(!isValid)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.light)
    }

    private var isValid: Bool {
        SkillMapTopic.validatedNames(topics.map(\.name)) != nil
    }

    private var existingSkillIDs: Set<SkillMapTopic.ID> {
        Set(store.activeDerivedSkillMap?.topics.map(\.id) ?? [])
    }
}

private struct SkillMapRepairView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var topicNames: [String]

    init(store: CheckpointStore) {
        self.store = store
        var seenKeys = Set<String>()
        var initialNames = store.sortedCompetencies.compactMap { competency -> String? in
            let name = SkillMapTopic.normalizedName(competency.topic)
            let key = name.lowercased()
            guard (1...48).contains(name.count),
                  name.rangeOfCharacter(from: CharacterSet(charactersIn: ",;\n")) == nil,
                  !seenKeys.contains(key) else {
                return nil
            }
            seenKeys.insert(key)
            return name
        }
        initialNames = Array(initialNames.prefix(6))
        while initialNames.count < 4 {
            initialNames.append("")
        }
        _topicNames = State(initialValue: initialNames)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add your skill areas")
                            .font(.title2.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Choose 3–6 concrete skills. Checkpoint will keep your existing answer history and prepare a focused practice set around these names.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionPanel("Skill names") {
                        VStack(spacing: 12) {
                            ForEach(Array(topicNames.indices), id: \.self) { index in
                                HStack(spacing: 10) {
                                    TextField("Skill \(index + 1)", text: $topicNames[index])
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(CheckpointTheme.text)
                                        .padding(12)
                                        .background(
                                            CheckpointTheme.panelRaised,
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                        .accessibilityLabel("Skill \(index + 1) name")

                                    if topicNames.count > 3 {
                                        Button {
                                            topicNames.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(CheckpointTheme.coral)
                                                .frame(width: 44, height: 44)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove skill \(index + 1)")
                                    }
                                }
                            }
                        }

                        if topicNames.count < 6 {
                            Button {
                                topicNames.append("")
                            } label: {
                                Label("Add another skill", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.teal)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }

                        if !isValid {
                            Text("Use a unique name up to 48 characters for every skill. Commas and semicolons aren’t supported in skill names.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.coral)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 96)
            }
            .checkpointScreenBackground()
            .navigationTitle("Skill Map")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Use these skills", systemImage: "checkmark") {
                    if store.repairActiveSkillMap(topicNames: topicNames) {
                        dismiss()
                    }
                }
                .disabled(!isValid)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.light)
    }

    private var isValid: Bool {
        SkillMapTopic.validatedNames(topicNames) != nil
    }
}

private struct CompetencyRow: View {
    var competency: TopicCompetency
    @State private var isExpanded = false

    var body: some View {
        let progress = progressPresentation

        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(competency.topic)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)

                        Text(questionCountText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
                    }

                    Spacer()

                    StatusBadge(text: progress.label, tint: progress.tint)
                }

                ProgressView(value: Double(competency.masteryPercent), total: 100)
                    .tint(progress.tint)
                    .accessibilityLabel("Progress")
                    .accessibilityValue(progress.label)

                DisclosureGroup(isExpanded: $isExpanded) {
                    HStack {
                        detailCount(title: "Correct", value: competency.correct, systemImage: "checkmark.circle")
                        Spacer()
                        detailCount(title: "Almost", value: competency.partial, systemImage: "circle.lefthalf.filled")
                        Spacer()
                        detailCount(title: "Missed", value: competency.incorrect, systemImage: "xmark.circle")
                    }
                    .padding(.top, 10)
                } label: {
                    Text("Details for \(competency.topic)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                }
                .tint(CheckpointTheme.teal)
            }
        }
    }

    private var questionCountText: String {
        "\(competency.attempts) \(competency.attempts == 1 ? "question" : "questions") answered"
    }

    private var progressPresentation: (label: String, tint: Color) {
        if competency.attempts == 0 {
            return ("Not started", CheckpointTheme.blue)
        }

        switch competency.masteryPercent {
        case 75...:
            return ("Strong", CheckpointTheme.teal)
        case 40..<75:
            return ("Building", CheckpointTheme.amber)
        default:
            return ("Needs practice", CheckpointTheme.coral)
        }
    }

    private func detailCount(title: String, value: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("\(value)", systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}
