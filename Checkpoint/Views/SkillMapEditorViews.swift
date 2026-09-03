import SwiftUI

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
                            ForEach(topics) { topic in
                                if let index = topics.firstIndex(where: { $0.id == topic.id }) {
                                    EditableSkillNameRow(
                                        index: index,
                                        name: $topics[index].name,
                                        canRemove: topics.count > 3
                                    ) {
                                        topics.removeAll { $0.id == topic.id }
                                    }

                                    if !topics[index].objectives.isEmpty {
                                        Text(topics[index].objectives.prefix(3).map(\.name).joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(CheckpointTheme.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    if existingSkillIDs.contains(topic.id) {
                                        Button {
                                            guard let replacementIndex = topics.firstIndex(where: { $0.id == topic.id }) else { return }
                                            topics[replacementIndex] = SkillMapTopic(name: "")
                                        } label: {
                                            Label("Replace this skill", systemImage: "arrow.triangle.2.circlepath")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(CheckpointTheme.amber)
                                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Retires this skill's questions and starts new progress")
                                    }
                                }
                            }

                            if topics.count < 6 {
                                AddSkillNameButton {
                                    topics.append(SkillMapTopic(name: ""))
                                }
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
        .onChange(of: validationMessage) { _, message in
            announceValidation(message)
        }
    }

    private var isValid: Bool {
        SkillMapTopic.validatedNames(topics.map(\.name)) != nil && !reusesRetiredSkill
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
}

struct SkillMapRepairView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
    @State private var topicDrafts: [SkillNameDraft]

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
        _topicDrafts = State(initialValue: initialNames.map(SkillNameDraft.init(name:)))
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
                                    EditableSkillNameRow(
                                        index: index,
                                        name: $topicDrafts[index].name,
                                        canRemove: topicDrafts.count > 3
                                    ) {
                                        topicDrafts.removeAll { $0.id == draft.id }
                                    }
                                }
                            }
                        }

                        if topicDrafts.count < 6 {
                            AddSkillNameButton {
                                topicDrafts.append(SkillNameDraft(name: ""))
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
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Use these skills", systemImage: "checkmark") {
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
        .preferredColorScheme(.light)
        .onChange(of: validationMessage) { _, message in
            announceValidation(message)
        }
    }

    private var isValid: Bool {
        SkillMapTopic.validatedNames(topicDrafts.map(\.name)) != nil
    }

    private var validationMessage: String? {
        isValid ? nil : SkillNameValidationMessage.defaultMessage
    }

    private func announceValidation(_ message: String?) {
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
    }
}

private struct SkillNameDraft: Identifiable {
    let id = UUID()
    var name: String
}

private struct EditableSkillNameRow: View {
    let index: Int
    @Binding var name: String
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Skill \(index + 1)", text: $name)
                .textFieldStyle(.plain)
                .foregroundStyle(CheckpointTheme.text)
                .padding(12)
                .background(
                    CheckpointTheme.panelRaised,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityLabel("Skill \(index + 1) name")

            if canRemove {
                Button(action: remove) {
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
