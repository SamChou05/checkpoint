import SwiftUI

struct SkillMapEditorAffordances: Equatable {
    static let minimumSkillCount = 3
    static let maximumSkillCount = 6

    var canAdd: Bool
    var canRemove: Bool

    init(count: Int) {
        canAdd = count < Self.maximumSkillCount
        canRemove = count > Self.minimumSkillCount
    }
}

enum SkillMapEditorMutation {
    @discardableResult
    static func add<Item: Identifiable>(
        _ item: Item,
        to items: inout [Item]
    ) -> Bool where Item.ID == UUID {
        guard SkillMapEditorAffordances(count: items.count).canAdd,
              !items.contains(where: { $0.id == item.id }) else {
            return false
        }
        items.append(item)
        return true
    }

    @discardableResult
    static func remove<Item: Identifiable>(
        id: Item.ID,
        from items: inout [Item]
    ) -> Bool where Item.ID == UUID {
        guard SkillMapEditorAffordances(count: items.count).canRemove,
              items.contains(where: { $0.id == id }) else {
            return false
        }
        items.removeAll { $0.id == id }
        return true
    }

    @discardableResult
    static func replace<Item: Identifiable>(
        id: Item.ID,
        with replacement: Item,
        in items: inout [Item]
    ) -> Bool where Item.ID == UUID {
        guard replacement.id != id,
              !items.contains(where: { $0.id == replacement.id }),
              let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        items[index] = replacement
        return true
    }
}

enum SkillMapMutationMotionStyle: Equatable {
    case structural
    case identity
}

struct SkillMapMutationMotionPolicy {
    var style: SkillMapMutationMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .structural
    }

    var animation: Animation? {
        style == .identity ? nil : CheckpointMotion.change
    }

    var rowTransition: AnyTransition {
        switch style {
        case .structural:
            .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            )
        case .identity:
            .identity
        }
    }

    var controlTransition: AnyTransition {
        style == .identity ? .identity : .opacity
    }
}

struct SkillMapFocusPlan: Equatable {
    var clearsCurrentFocus: Bool
    var targetAfterLayout: UUID?

    static func adding(_ newID: UUID) -> Self {
        Self(clearsCurrentFocus: false, targetAfterLayout: newID)
    }

    static func removing(_ removedID: UUID, focusedID: UUID?) -> Self {
        Self(clearsCurrentFocus: focusedID == removedID, targetAfterLayout: nil)
    }

    static func replacing(with newID: UUID) -> Self {
        Self(clearsCurrentFocus: true, targetAfterLayout: newID)
    }

    func resolvedTarget(availableIDs: some Collection<UUID>) -> UUID? {
        guard let targetAfterLayout,
              availableIDs.contains(targetAfterLayout) else {
            return nil
        }
        return targetAfterLayout
    }
}

struct SkillNameRowPresentation: Equatable {
    var position: Int
    var fieldAccessibilityLabel: String
    var removeAccessibilityLabel: String?
    var replaceAccessibilityLabel: String?

    init(index: Int, name: String, canRemove: Bool, canReplace: Bool) {
        position = index + 1
        fieldAccessibilityLabel = "Skill \(position) name"

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = trimmedName.isEmpty
            ? "skill \(position)"
            : "skill \(position), \(trimmedName)"
        removeAccessibilityLabel = canRemove ? "Remove \(identity)" : nil
        replaceAccessibilityLabel = canReplace ? "Replace \(identity)" : nil
    }
}

struct SkillMapReviewView: View {
    let store: CheckpointStore
    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var topics: [SkillMapTopic]
    @State private var pendingFocusPlan: SkillMapFocusPlan?
    @FocusState private var focusedSkillID: UUID?

    init(store: CheckpointStore, reduceMotionOverride: Bool? = nil) {
        self.store = store
        self.reduceMotionOverride = reduceMotionOverride
        _topics = State(initialValue: store.activeDerivedSkillMap?.topics ?? [])
        _pendingFocusPlan = State(initialValue: nil)
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
                            ForEach(topics) { topic in
                                if let index = topics.firstIndex(where: { $0.id == topic.id }) {
                                    let presentation = SkillNameRowPresentation(
                                        index: index,
                                        name: topics[index].name,
                                        canRemove: affordances.canRemove,
                                        canReplace: existingSkillIDs.contains(topic.id)
                                    )

                                    VStack(alignment: .leading, spacing: 7) {
                                        EditableSkillNameRow(
                                            skillID: topic.id,
                                            presentation: presentation,
                                            name: nameBinding(for: topic.id),
                                            focusedSkillID: $focusedSkillID
                                        ) {
                                            removeSkill(id: topic.id)
                                        }

                                        if !topics[index].objectives.isEmpty {
                                            Text(topics[index].objectives.prefix(3).map(\.name).joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(CheckpointTheme.muted)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }

                                        if let replaceAccessibilityLabel = presentation.replaceAccessibilityLabel {
                                            Button {
                                                replaceSkill(id: topic.id)
                                            } label: {
                                                Label("Replace this skill", systemImage: "arrow.triangle.2.circlepath")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(CheckpointTheme.amber)
                                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(replaceAccessibilityLabel)
                                            .accessibilityHint("Retires this skill's questions and starts new progress")
                                        }
                                    }
                                    .id(topic.id)
                                    .transition(motionPolicy.rowTransition)
                                    .onAppear {
                                        applyPendingFocus(to: topic.id)
                                    }
                                }
                            }

                            if affordances.canAdd {
                                AddSkillNameButton(action: addSkill)
                                    .transition(motionPolicy.controlTransition)
                            }
                        }

                        if let validationMessage {
                            SkillNameValidationMessage(message: validationMessage)
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
                        pendingFocusPlan = nil
                        focusedSkillID = nil
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        pendingFocusPlan = nil
                        focusedSkillID = nil
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Use this skill map", systemImage: "checkmark") {
                    pendingFocusPlan = nil
                    focusedSkillID = nil
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
        .onChange(of: validationMessage) { _, message in
            announceValidation(message)
        }
    }

    private var isValid: Bool {
        SkillMapTopic.validatedNames(topics.map(\.name)) != nil && !reusesRetiredSkill
    }

    private var affordances: SkillMapEditorAffordances {
        SkillMapEditorAffordances(count: topics.count)
    }

    private var motionPolicy: SkillMapMutationMotionPolicy {
        SkillMapMutationMotionPolicy(
            reduceMotion: reduceMotionOverride ?? systemReduceMotion
        )
    }

    private var reusesRetiredSkill: Bool {
        let map = store.activeDerivedSkillMap
        return SkillMapReconciler.hasArchivedSkillCollision(
            topics: topics,
            archivedTopics: map?.archivedTopics ?? []
        ) || SkillMapReconciler.hasRemovedSkillNameCollision(
            topics: topics,
            existingTopics: map?.topics ?? []
        )
    }

    private var validationMessage: String? {
        if reusesRetiredSkill {
            return "A retired skill name can’t be reused. Choose a new name so its saved history stays distinct."
        }
        if !isValid {
            return SkillNameValidationMessage.defaultMessage
        }
        return nil
    }

    private func announceValidation(_ message: String?) {
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    private var existingSkillIDs: Set<SkillMapTopic.ID> {
        Set(store.activeDerivedSkillMap?.topics.map(\.id) ?? [])
    }

    private func addSkill() {
        guard affordances.canAdd else { return }
        let topic = SkillMapTopic(name: "")
        let focusPlan = SkillMapFocusPlan.adding(topic.id)
        pendingFocusPlan = focusPlan

        withAnimation(motionPolicy.animation) {
            if !SkillMapEditorMutation.add(topic, to: &topics) {
                pendingFocusPlan = nil
            }
        }
    }

    private func nameBinding(for id: SkillMapTopic.ID) -> Binding<String> {
        Binding(
            get: {
                topics.first(where: { $0.id == id })?.name ?? ""
            },
            set: { newName in
                guard let index = topics.firstIndex(where: { $0.id == id }) else { return }
                topics[index].name = newName
            }
        )
    }

    private func removeSkill(id: SkillMapTopic.ID) {
        guard affordances.canRemove,
              topics.contains(where: { $0.id == id }) else {
            return
        }
        let focusPlan = SkillMapFocusPlan.removing(id, focusedID: focusedSkillID)
        if pendingFocusPlan?.targetAfterLayout == id {
            pendingFocusPlan = nil
        }
        if focusPlan.clearsCurrentFocus {
            focusedSkillID = nil
        }

        withAnimation(motionPolicy.animation) {
            _ = SkillMapEditorMutation.remove(id: id, from: &topics)
        }
    }

    private func replaceSkill(id: SkillMapTopic.ID) {
        guard topics.contains(where: { $0.id == id }) else { return }
        let replacement = SkillMapTopic(name: "")
        let focusPlan = SkillMapFocusPlan.replacing(with: replacement.id)
        pendingFocusPlan = focusPlan
        if focusPlan.clearsCurrentFocus {
            focusedSkillID = nil
        }

        withAnimation(motionPolicy.animation) {
            if !SkillMapEditorMutation.replace(id: id, with: replacement, in: &topics) {
                pendingFocusPlan = nil
            }
        }
    }

    private func applyPendingFocus(to appearedID: UUID) {
        guard let plan = pendingFocusPlan,
              plan.targetAfterLayout == appearedID else {
            return
        }
        pendingFocusPlan = nil
        focusedSkillID = plan.resolvedTarget(availableIDs: topics.map(\.id))
    }
}

struct SkillMapRepairView: View {
    let store: CheckpointStore
    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var topicDrafts: [SkillNameDraft]
    @State private var pendingFocusPlan: SkillMapFocusPlan?
    @FocusState private var focusedSkillID: UUID?

    init(store: CheckpointStore, reduceMotionOverride: Bool? = nil) {
        self.store = store
        self.reduceMotionOverride = reduceMotionOverride
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
        _topicDrafts = State(initialValue: initialNames.map(SkillNameDraft.init(name:)))
        _pendingFocusPlan = State(initialValue: nil)
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
                            ForEach(topicDrafts) { draft in
                                if let index = topicDrafts.firstIndex(where: { $0.id == draft.id }) {
                                    let presentation = SkillNameRowPresentation(
                                        index: index,
                                        name: topicDrafts[index].name,
                                        canRemove: affordances.canRemove,
                                        canReplace: false
                                    )

                                    EditableSkillNameRow(
                                        skillID: draft.id,
                                        presentation: presentation,
                                        name: nameBinding(for: draft.id),
                                        focusedSkillID: $focusedSkillID
                                    ) {
                                        removeSkill(id: draft.id)
                                    }
                                    .id(draft.id)
                                    .transition(motionPolicy.rowTransition)
                                    .onAppear {
                                        applyPendingFocus(to: draft.id)
                                    }
                                }
                            }
                        }

                        if affordances.canAdd {
                            AddSkillNameButton(action: addSkill)
                                .transition(motionPolicy.controlTransition)
                        }

                        if let validationMessage {
                            SkillNameValidationMessage(message: validationMessage)
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
                        pendingFocusPlan = nil
                        focusedSkillID = nil
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        pendingFocusPlan = nil
                        focusedSkillID = nil
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Use these skills", systemImage: "checkmark") {
                    pendingFocusPlan = nil
                    focusedSkillID = nil
                    if store.repairActiveSkillMap(topicNames: topicDrafts.map(\.name)) {
                        dismiss()
                    }
                }
                .disabled(!isValid)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .onChange(of: validationMessage) { _, message in
            announceValidation(message)
        }
    }

    private var isValid: Bool {
        SkillMapTopic.validatedNames(topicDrafts.map(\.name)) != nil
    }

    private var affordances: SkillMapEditorAffordances {
        SkillMapEditorAffordances(count: topicDrafts.count)
    }

    private var motionPolicy: SkillMapMutationMotionPolicy {
        SkillMapMutationMotionPolicy(
            reduceMotion: reduceMotionOverride ?? systemReduceMotion
        )
    }

    private var validationMessage: String? {
        isValid ? nil : SkillNameValidationMessage.defaultMessage
    }

    private func announceValidation(_ message: String?) {
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    private func addSkill() {
        guard affordances.canAdd else { return }
        let draft = SkillNameDraft(name: "")
        let focusPlan = SkillMapFocusPlan.adding(draft.id)
        pendingFocusPlan = focusPlan

        withAnimation(motionPolicy.animation) {
            if !SkillMapEditorMutation.add(draft, to: &topicDrafts) {
                pendingFocusPlan = nil
            }
        }
    }

    private func nameBinding(for id: SkillNameDraft.ID) -> Binding<String> {
        Binding(
            get: {
                topicDrafts.first(where: { $0.id == id })?.name ?? ""
            },
            set: { newName in
                guard let index = topicDrafts.firstIndex(where: { $0.id == id }) else { return }
                topicDrafts[index].name = newName
            }
        )
    }

    private func removeSkill(id: SkillNameDraft.ID) {
        guard affordances.canRemove,
              topicDrafts.contains(where: { $0.id == id }) else {
            return
        }
        let focusPlan = SkillMapFocusPlan.removing(id, focusedID: focusedSkillID)
        if pendingFocusPlan?.targetAfterLayout == id {
            pendingFocusPlan = nil
        }
        if focusPlan.clearsCurrentFocus {
            focusedSkillID = nil
        }

        withAnimation(motionPolicy.animation) {
            _ = SkillMapEditorMutation.remove(id: id, from: &topicDrafts)
        }
    }

    private func applyPendingFocus(to appearedID: UUID) {
        guard let plan = pendingFocusPlan,
              plan.targetAfterLayout == appearedID else {
            return
        }
        pendingFocusPlan = nil
        focusedSkillID = plan.resolvedTarget(availableIDs: topicDrafts.map(\.id))
    }
}

private struct SkillNameDraft: Identifiable {
    let id = UUID()
    var name: String
}

private struct EditableSkillNameRow: View {
    let skillID: UUID
    let presentation: SkillNameRowPresentation
    @Binding var name: String
    let focusedSkillID: FocusState<UUID?>.Binding
    let remove: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    skillNameField

                    if let removeAccessibilityLabel = presentation.removeAccessibilityLabel {
                        removeButton(
                            accessibilityLabel: removeAccessibilityLabel,
                            showsTitle: true
                        )
                    }
                }
            } else {
                HStack(spacing: 10) {
                    skillNameField

                    if let removeAccessibilityLabel = presentation.removeAccessibilityLabel {
                        removeButton(
                            accessibilityLabel: removeAccessibilityLabel,
                            showsTitle: false
                        )
                    }
                }
            }
        }
    }

    private var skillNameField: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                TextField(
                    "Skill \(presentation.position)",
                    text: $name,
                    axis: .vertical
                )
                .lineLimit(1...3)
            } else {
                TextField("Skill \(presentation.position)", text: $name)
            }
        }
        .textFieldStyle(.plain)
        .foregroundStyle(CheckpointTheme.text)
        .padding(12)
        .background(
            CheckpointTheme.panelRaised,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .focused(focusedSkillID, equals: skillID)
        .accessibilityLabel(presentation.fieldAccessibilityLabel)
    }

    @ViewBuilder
    private func removeButton(
        accessibilityLabel: String,
        showsTitle: Bool
    ) -> some View {
        Button(action: remove) {
            if showsTitle {
                Label("Remove", systemImage: "minus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.coral)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(CheckpointTheme.coral)
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct AddSkillNameButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add another skill", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

private struct SkillNameValidationMessage: View {
    static let defaultMessage = "Use a unique name up to 48 characters for every skill. Commas and semicolons aren’t supported in skill names."

    var message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(CheckpointTheme.coral)
            .fixedSize(horizontal: false, vertical: true)
    }
}
