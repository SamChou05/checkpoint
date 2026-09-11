import SwiftUI

struct LearningMapDraft: Equatable {
    let original: GoalSkillMap
    var topics: [SkillMapTopic]
    var growthMode: SkillMapGrowthMode

    init(map: GoalSkillMap) {
        original = map
        topics = map.topics.map { topic in
            var draft = topic
            if draft.objectives.isEmpty {
                draft.objectives = [SkillMapObjective(id: topic.id, name: topic.name)]
            }
            return draft
        }
        growthMode = map.growthMode
    }

    var hasChanges: Bool { topics != original.topics || growthMode != original.growthMode }

    @MainActor var validationError: String? {
        if let message = SkillMapReconciler.learningMapValidationError(topics: topics) {
            return message
        }
        let identityValidation = SkillMapEditorValidation(
            topics: topics,
            originalTopics: original.topics,
            archivedTopics: original.archivedTopics
        )
        return identityValidation.isValid ? nil : "Use a distinct name for every skill. Earlier skills keep their names in history."
    }

    var changeSummary: [String] {
        var changes: [String] = []
        let originalByID = Dictionary(uniqueKeysWithValues: original.topics.map { ($0.id, $0) })
        let proposedIDs = Set(topics.map(\.id))
        let additions = topics.filter { originalByID[$0.id] == nil }
        let removals = original.topics.filter { !proposedIDs.contains($0.id) }
        for addition in additions {
            if let predecessorID = addition.predecessorIDs.first, let earlier = originalByID[predecessorID] {
                changes.append("Replace “\(earlier.name)” with “\(addition.name)”. The new branch starts with fresh practice evidence; the earlier skill stays in history.")
            } else {
                changes.append("Add “\(addition.name)” with fresh practice evidence.")
            }
        }
        let replacedIDs = Set(additions.flatMap(\.predecessorIDs))
        for removal in removals where !replacedIDs.contains(removal.id) {
            changes.append("Move “\(removal.name)” to history with its existing evidence.")
        }
        for topic in topics {
            guard let earlier = originalByID[topic.id] else { continue }
            if topic.name != earlier.name {
                changes.append("Rename “\(earlier.name)” to “\(topic.name)”; keep its progress.")
            }
            if topic.objectives != earlier.objectives {
                changes.append("Update focus points for “\(topic.name)”. Future questions follow this scope; earlier answers stay in practice history.")
                let priorObjectiveIDs = Set(earlier.objectives.map(\.id))
                let newObjectives = topic.objectives.filter { !priorObjectiveIDs.contains($0.id) }
                if !newObjectives.isEmpty {
                    changes.append("New focus points in “\(topic.name)” start with fresh evidence: \(newObjectives.map(\.name).joined(separator: ", ")).")
                }
            }
            if topic.isPaused != earlier.isPaused {
                changes.append(topic.isPaused
                    ? "Pause “\(topic.name)” in upcoming practice. Its progress stays visible."
                    : "Resume “\(topic.name)” in upcoming practice.")
            }
            if topic.detail != earlier.detail {
                changes.append("Update the description of “\(topic.name)”. Future questions follow this scope.")
            }
            if topic.practiceEmphasis != earlier.practiceEmphasis {
                changes.append("Set practice emphasis for “\(topic.name)” to \(topic.practiceEmphasis.label.lowercased()). This changes how often it appears.")
            }
            if topic.challenge != earlier.challenge {
                changes.append("Set the challenge for “\(topic.name)” to \(topic.challenge.label.lowercased()). This adjusts the level of upcoming questions.")
            }
        }
        let sharedIDs = Set(originalByID.keys).intersection(proposedIDs)
        if topics.filter({ sharedIDs.contains($0.id) }).map(\.id)
            != original.topics.filter({ sharedIDs.contains($0.id) }).map(\.id) {
            changes.append("Reorder the skills in your map.")
        }
        if growthMode != original.growthMode {
            changes.append("Set map growth to \(growthMode.label.lowercased()).")
        }
        return changes
    }

    mutating func replace(_ id: UUID) -> UUID? {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return nil }
        let old = topics[index]
        let replacement = SkillMapTopic(
            name: "",
            objectives: [SkillMapObjective(name: "")],
            stage: old.stage + 1,
            predecessorIDs: [old.id]
        )
        topics[index] = replacement
        return replacement.id
    }

    mutating func moveSkill(_ id: UUID, by offset: Int) {
        guard let index = topics.firstIndex(where: { $0.id == id }),
              topics.indices.contains(index + offset) else { return }
        topics.swapAt(index, index + offset)
    }
}

struct LearningMapEditorView: View {
    let store: CheckpointStore
    let context: SkillMapReviewContext
    private let initialSkillID: UUID?

    private enum Route: Hashable {
        case skill(UUID)
        case review
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: LearningMapDraft
    @State private var path: [Route] = []
    @State private var saveError: String?
    @State private var isDiscarding = false
    @State private var hasOpenedInitialSkill = false

    init(store: CheckpointStore, context: SkillMapReviewContext, initialSkillID: UUID? = nil) {
        self.store = store
        self.context = context
        self.initialSkillID = initialSkillID
        _draft = State(initialValue: LearningMapDraft(map: context.skillMap))
    }

    private var isStale: Bool { !context.matches(store.goal) }
    private var isReviewing: Bool { path.last == .review }
    private var editImpact: LearningMapEditImpact? {
        store.learningMapEditImpact(
            goalID: context.revision.goalID,
            expectedMap: context.skillMap,
            topics: draft.topics
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            editorOverview
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .skill(id):
                        if let topic = draft.topics.first(where: { $0.id == id }) {
                            LearningMapSkillEditor(
                                topic: topicBinding(id, fallback: topic),
                                isExisting: draft.original.topics.contains { $0.id == id },
                                canRemove: draft.topics.count > SkillMapEditorAffordances.minimumSkillCount,
                                canPause: topic.isPaused
                                    || draft.topics.filter({ !$0.isPaused }).count > 1,
                                onReplace: { replaceSkill(id) },
                                onRemove: { removeSkill(id) }
                            )
                        } else {
                            ContentUnavailableView("Skill updated", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    case .review:
                        reviewChanges
                    }
                }
                .navigationTitle("Edit learning map")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if draft.hasChanges { isDiscarding = true } else { dismiss() }
                        }
                    }
                }
        }
        .tint(CheckpointTheme.accent)
        .safeAreaInset(edge: .bottom) { saveBar }
        .interactiveDismissDisabled(draft.hasChanges)
        .confirmationDialog("Discard your map changes?", isPresented: $isDiscarding, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Your saved learning map and progress will stay as they are.")
        }
        .onAppear {
            guard !hasOpenedInitialSkill else { return }
            hasOpenedInitialSkill = true
            if let initialSkillID, draft.topics.contains(where: { $0.id == initialSkillID }) {
                path = [.skill(initialSkillID)]
            }
        }
        .onChange(of: store.goal?.id) { _, id in
            if id != context.revision.goalID { dismiss() }
        }
    }

    private var editorOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(context.goalTitle)
                        .font(CheckpointTypography.goalTitle)
                        .foregroundStyle(CheckpointTheme.text)
                    Text("Shape your skills and the smaller ideas you want to practice. Review your changes before saving.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                }
                SectionPanel("Your skills", style: .editorial) {
                    VStack(spacing: 0) {
                        ForEach(Array(draft.topics.enumerated()), id: \.element.id) { index, topic in
                            let rowLayout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                                : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
                            rowLayout {
                                Button {
                                    path.append(.skill(topic.id))
                                } label: {
                                    HStack(alignment: .center, spacing: 12) {
                                        if !dynamicTypeSize.isAccessibilitySize {
                                            Image(systemName: topic.isPaused ? "pause.circle" : "circle.hexagongrid")
                                                .font(.title3)
                                                .foregroundStyle(CheckpointTheme.accent)
                                                .frame(width: 28)
                                                .accessibilityHidden(true)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(topic.name.isEmpty ? "Name your new skill" : topic.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(CheckpointTheme.text)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text("\(topic.objectives.count) focus points · \(topic.isPaused ? "Paused" : topic.practiceEmphasis.label)")
                                                .font(.caption)
                                                .foregroundStyle(CheckpointTheme.muted)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        if !dynamicTypeSize.isAccessibilitySize {
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(CheckpointTheme.muted)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .padding(.vertical, 13)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Edits this skill and its focus points.")
                                Menu {
                                    Button("Move earlier", systemImage: "arrow.up") { draft.moveSkill(topic.id, by: -1) }
                                        .disabled(index == 0)
                                    Button("Move later", systemImage: "arrow.down") { draft.moveSkill(topic.id, by: 1) }
                                        .disabled(index == draft.topics.count - 1)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.arrow.down")
                                        if dynamicTypeSize.isAccessibilitySize { Text("Reorder") }
                                    }
                                        .font(.caption)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .foregroundStyle(CheckpointTheme.muted)
                                }
                                .accessibilityLabel("Reorder \(topic.name)")
                            }
                            if index < draft.topics.count - 1 { Divider() }
                        }
                    }
                    if draft.topics.count < SkillMapEditorAffordances.maximumSkillCount {
                        SecondaryActionButton(title: "Add skill", systemImage: "plus") { addSkill() }
                    }
                    Text("Keep 3–6 planned skills and at least one ready for practice. Paused skills stay in your map.")
                        .font(.caption)
                        .foregroundStyle(CheckpointTheme.muted)
                }
                growthPanel
            }
            .padding(20)
        }
        .checkpointScreenBackground()
    }

    private var growthPanel: some View {
        SectionPanel("How your map grows", style: .editorial) {
            if store.isMember {
                ForEach(SkillMapGrowthMode.allCases, id: \.self) { mode in
                    Button {
                        draft.growthMode = mode
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: draft.growthMode == mode ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(CheckpointTheme.accent)
                                .font(.title3)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)
                                Text(growthDescription(mode))
                                    .font(.caption)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.growthMode == mode ? .isSelected : [])
                }
            } else {
                Label("Adaptive growth with Pro", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.accent)
                Text("You can edit your skills and focus points. Pro also adds harder next steps after enough strong practice evidence. Your saved growth preference is kept.")
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
            }
        }
    }

    private func growthDescription(_ mode: SkillMapGrowthMode) -> String {
        switch mode {
        case .automatic: "Advance mastered skills to harder next steps and preserve their history."
        case .reviewSuggestions: "Show proposed next steps for your approval before the map changes."
        case .manual: "Keep the map under your control. Add or replace skills when you choose."
        }
    }

    private var reviewChanges: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Ready to update your map?")
                    .font(CheckpointTypography.sectionTitle)
                    .foregroundStyle(CheckpointTheme.text)
                SectionPanel("What will change", style: .editorial) {
                    ForEach(Array(draft.changeSummary.enumerated()), id: \.offset) { _, message in
                        Label {
                            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark.circle").foregroundStyle(CheckpointTheme.success)
                        }
                        .foregroundStyle(CheckpointTheme.text)
                        .padding(.vertical, 4)
                    }
                }
                if let impact = editImpact, impact.requiresFreshQuestions || impact.retiresQuestionInventory {
                    SectionPanel("Upcoming questions", style: .editorial) {
                        if impact.retiresQuestionInventory {
                            Text("Questions that no longer match your edited skills or focus points leave upcoming practice. Their saved answers remain in your history.")
                                .font(.subheadline)
                                .foregroundStyle(CheckpointTheme.text)
                        }
                        if impact.requiresMembershipForFreshQuestions {
                            Text("You've used your starter practice. These changes need fresh questions, which require Pro. Your edited map will still be saved, and any remaining ready questions stay available.")
                                .font(.subheadline)
                                .foregroundStyle(CheckpointTheme.text)
                        } else if impact.requiresFreshQuestions {
                            Text("Checkpoint will prepare fresh questions for this plan. They may take a moment to become ready.")
                                .font(.subheadline)
                                .foregroundStyle(CheckpointTheme.text)
                        }
                    }
                }
                Text("Changes apply to upcoming practice. Saved answers and earned history stay available. A checkpoint already in progress keeps its current questions.")
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
            }
            .padding(20)
        }
        .checkpointScreenBackground()
        .navigationTitle("Review changes")
        .toolbarTitleDisplayMode(.inline)
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isStale {
                Text("Your saved map changed while you were editing. Close this draft and reopen the editor to use the latest map.")
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.coral)
                    .accessibilityIdentifier("learning-map-stale-draft")
            } else if let error = saveError ?? draft.validationError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.coral)
            }
            PrimaryActionButton(
                title: dynamicTypeSize.isAccessibilitySize
                    ? (isReviewing ? "Save map" : "Review")
                    : (isReviewing ? "Save learning map" : "Review changes"),
                systemImage: isReviewing ? "checkmark" : "arrow.right"
            ) {
                if isReviewing { save() } else { path.append(.review) }
            }
            .disabled(isStale || draft.validationError != nil || !draft.hasChanges)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func addSkill() {
        let topic = SkillMapTopic(name: "", objectives: [SkillMapObjective(name: "")])
        guard SkillMapEditorAffordances(count: draft.topics.count).canAdd else { return }
        withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
            draft.topics.append(topic)
            path.append(.skill(topic.id))
        }
    }

    private func replaceSkill(_ id: UUID) {
        guard let replacementID = draft.replace(id) else { return }
        path = [.skill(replacementID)]
    }

    private func removeSkill(_ id: UUID) {
        guard SkillMapEditorAffordances(count: draft.topics.count).canRemove else { return }
        path = []
        draft.topics.removeAll { $0.id == id }
    }

    private func save() {
        guard !isStale, draft.validationError == nil else { return }
        if store.updateLearningMap(
            goalID: context.revision.goalID,
            expectedMap: context.skillMap,
            topics: draft.topics,
            growthMode: draft.growthMode
        ) {
            dismiss()
        } else {
            saveError = "The map couldn't be saved. Check your skills and reopen the editor if the saved map has changed."
        }
    }

    private func topicBinding(_ id: UUID, fallback: SkillMapTopic) -> Binding<SkillMapTopic> {
        Binding(
            get: { draft.topics.first(where: { $0.id == id }) ?? fallback },
            set: { topic in
                guard let index = draft.topics.firstIndex(where: { $0.id == id }) else { return }
                draft.topics[index] = topic
            }
        )
    }
}

private struct LearningMapSkillEditor: View {
    @Binding var topic: SkillMapTopic
    let isExisting: Bool
    let canRemove: Bool
    let canPause: Bool
    let onReplace: () -> Void
    let onRemove: () -> Void

    @State private var destructiveAction: DestructiveAction?
    private enum DestructiveAction: String, Identifiable {
        case replace, remove
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section {
                TextField("Skill name", text: $topic.name, axis: .vertical)
                    .accessibilityLabel("Skill name")
                TextField("What do you want to learn here?", text: $topic.detail, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityLabel("Skill description")
            } header: {
                Text("Skill")
            } footer: {
                Text(isExisting
                    ? "Renaming keeps this skill's progress. Use Replace skill to learn something different."
                    : "This new skill starts with fresh practice evidence.")
            }

            Section {
                ForEach(Array(topic.objectives.enumerated()), id: \.element.id) { index, objective in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top, spacing: 8) {
                            TextField("Focus point name", text: objectiveBinding(objective.id, \.name), axis: .vertical)
                                .font(.subheadline.weight(.semibold))
                                .accessibilityLabel("Focus point \(index + 1) name")
                            Menu {
                                Button("Move earlier", systemImage: "arrow.up") { moveObjective(objective.id, by: -1) }
                                    .disabled(index == 0)
                                Button("Move later", systemImage: "arrow.down") { moveObjective(objective.id, by: 1) }
                                    .disabled(index == topic.objectives.count - 1)
                                Button("Replace focus point", systemImage: "arrow.triangle.branch") {
                                    if let currentIndex = topic.objectives.firstIndex(where: { $0.id == objective.id }) {
                                        topic.objectives[currentIndex] = SkillMapObjective(name: "")
                                    }
                                }
                                Button("Remove focus point", systemImage: "minus.circle", role: .destructive) {
                                    topic.objectives.removeAll { $0.id == objective.id }
                                }
                                .disabled(topic.objectives.count <= 1)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Options for focus point \(index + 1)")
                        }
                        TextField("Optional practice direction", text: objectiveBinding(objective.id, \.detail), axis: .vertical)
                            .font(.footnote)
                            .lineLimit(1...4)
                            .accessibilityLabel("Focus point \(index + 1) description")
                    }
                    .padding(.vertical, 5)
                }
                if topic.objectives.count < SkillMapTopic.maximumActiveObjectiveCount {
                    Button("Add focus point", systemImage: "plus") {
                        topic.objectives.append(SkillMapObjective(name: ""))
                    }
                    .frame(minHeight: 44)
                }
            } header: {
                Text("Focus points")
            } footer: {
                Text("Choose 1–5 smaller ideas for this skill. Names and descriptions guide future questions. Renaming keeps evidence; replacing a focus point starts fresh for a different idea.")
            }

            Section {
                Picker("Practice emphasis", selection: $topic.practiceEmphasis) {
                    ForEach(SkillPracticeEmphasis.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                Picker("Challenge", selection: $topic.challenge) {
                    ForEach(SkillChallenge.allCases, id: \.self) { value in
                        Text(value.label).tag(value)
                    }
                }
                Toggle("Pause this skill", isOn: $topic.isPaused)
                    .disabled(!canPause)
            } header: {
                Text("Upcoming practice")
            } footer: {
                Text("Emphasis changes how often this skill appears. Challenge adjusts the level of questions. Pausing preserves progress and leaves the skill out of upcoming sets.")
            }

            if isExisting || canRemove {
                Section {
                    if isExisting {
                        Button("Replace skill", systemImage: "arrow.triangle.branch", role: .destructive) {
                            destructiveAction = .replace
                        }
                    }
                    if canRemove {
                        Button("Remove skill", systemImage: "minus.circle", role: .destructive) {
                            destructiveAction = .remove
                        }
                    }
                } footer: {
                    Text("Earlier skills remain in history. These changes take effect when you save the map.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .checkpointScreenBackground()
        .navigationTitle("Edit skill")
        .toolbarTitleDisplayMode(.inline)
        .confirmationDialog(
            destructiveAction == .replace ? "Replace this skill?" : "Remove this skill?",
            isPresented: Binding(
                get: { destructiveAction != nil },
                set: { if !$0 { destructiveAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if destructiveAction == .replace {
                Button("Create replacement", role: .destructive) { onReplace(); destructiveAction = nil }
            } else {
                Button("Remove from draft", role: .destructive) { onRemove(); destructiveAction = nil }
            }
            Button("Keep skill", role: .cancel) { destructiveAction = nil }
        } message: {
            Text(destructiveAction == .replace
                ? "The replacement starts with fresh evidence. This skill and its progress will remain in history after you save."
                : "This skill and its progress will remain in history after you save.")
        }
    }

    private func objectiveBinding(_ id: UUID, _ keyPath: WritableKeyPath<SkillMapObjective, String>) -> Binding<String> {
        Binding(
            get: { topic.objectives.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = topic.objectives.firstIndex(where: { $0.id == id }) else { return }
                topic.objectives[index][keyPath: keyPath] = value
            }
        )
    }

    private func moveObjective(_ id: UUID, by offset: Int) {
        guard let index = topic.objectives.firstIndex(where: { $0.id == id }),
              topic.objectives.indices.contains(index + offset) else { return }
        topic.objectives.swapAt(index, index + offset)
    }
}
