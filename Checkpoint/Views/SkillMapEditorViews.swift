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

    var permitsNodeMotion: Bool {
        style == .structural
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

enum SkillMapEditorMode: Equatable {
    case review(status: SkillMapStatus)
    case repair
}

enum SkillMapEditorHeroState: Equatable {
    case draftReady
    case current
    case changesReady
    case ready
    case needsAttention
}

struct SkillMapEditorPresentation: Equatable {
    var mode: SkillMapEditorMode
    var state: SkillMapEditorHeroState
    var goalTitle: String
    var status: String
    var title: String
    var detail: String
    var actionTitle: String
    var actionEnabled: Bool
    var skillCount: Int
    var namedCount: Int

    init(
        mode: SkillMapEditorMode,
        goalTitle: String,
        skillCount: Int,
        namedCount: Int,
        isValid: Bool,
        hasChanges: Bool
    ) {
        self.mode = mode
        self.goalTitle = goalTitle
        self.skillCount = skillCount
        self.namedCount = namedCount
        actionEnabled = isValid

        if !isValid {
            state = .needsAttention
            status = "Needs attention"
            title = "Finish your skill map"
        } else {
            switch mode {
            case .review(status: .suggested):
                state = .draftReady
                status = "Suggested"
                title = "Make this plan yours"
            case .review(status: .reviewed) where hasChanges:
                state = .changesReady
                status = "Changes ready"
                title = "Shape your next practice"
            case .review(status: .reviewed):
                state = .current
                status = "Current"
                title = "Your training plan"
            case .repair:
                state = .ready
                status = "Ready"
                title = "Reconnect your skill map"
            }
        }

        switch mode {
        case .review(status: .suggested):
            detail = isValid
                ? "These skills guide each checkpoint. Rename or replace any skill before you begin."
                : "Name each skill clearly to build a focused practice plan."
            actionTitle = "Use this skill map"
        case .review(status: .reviewed):
            detail = isValid
                ? "Rename keeps progress. Replace archives the skill and starts fresh."
                : "Resolve the highlighted names. Retained skills keep their progress."
            actionTitle = hasChanges ? "Save changes" : "Done"
        case .repair:
            detail = isValid
                ? "Saved answer history stays connected while these skills shape future practice."
                : "Choose 3–6 unique names to reconnect your practice history."
            actionTitle = "Use these skills"
        }
    }

    var capacityText: String {
        namedCount == skillCount
            ? "\(skillCount) of \(SkillMapEditorAffordances.maximumSkillCount) skills"
            : "\(namedCount) named · \(skillCount) slots"
    }

    var accessibilitySummary: String {
        "Skill map for \(goalTitle). \(status). \(title). \(detail) " +
            "\(namedCount) of \(skillCount) names entered; \(skillCount) of " +
            "\(SkillMapEditorAffordances.maximumSkillCount) skill slots used."
    }
}

enum SkillNameIssue: Equatable {
    case required
    case tooLong(characterCount: Int)
    case unsupportedSeparator
    case duplicate
    case retiredName
    case duplicateSkill
    case archivedSkill

    var message: String {
        switch self {
        case .required:
            "Add a clear skill name."
        case let .tooLong(characterCount):
            "Use 48 characters or fewer (currently \(characterCount))."
        case .unsupportedSeparator:
            "Commas and semicolons aren’t supported."
        case .duplicate:
            "Give this skill a unique name."
        case .retiredName:
            "Choose a new name; this one belongs to an archived skill."
        case .duplicateSkill:
            "This skill appears more than once. Keep one copy."
        case .archivedSkill:
            "This skill is already archived. Add it again as a new skill."
        }
    }
}

struct SkillMapEditorName: Identifiable, Equatable {
    var id: UUID
    var name: String
}

struct SkillMapEditorValidation: Equatable {
    var issueByTopicID: [UUID: SkillNameIssue]
    var namedCount: Int
    var isValid: Bool

    init(
        topics: [SkillMapTopic],
        originalTopics: [SkillMapTopic],
        archivedTopics: [ArchivedSkillMapTopic]
    ) {
        let proposedIDs = Set(topics.map(\.id))
        let retiredNameKeys = Set(
            archivedTopics.map { SkillMapTopic.canonicalIdentityKey($0.topic.name) }
        ).union(
            originalTopics
                .filter { !proposedIDs.contains($0.id) }
                .map { SkillMapTopic.canonicalIdentityKey($0.name) }
        )
        self.init(
            rows: topics.map { SkillMapEditorName(id: $0.id, name: $0.name) },
            retiredNameKeys: retiredNameKeys,
            archivedTopicIDs: Set(archivedTopics.map(\.id))
        )
    }

    init(
        rows: [SkillMapEditorName],
        retiredNameKeys: Set<String> = [],
        archivedTopicIDs: Set<UUID> = []
    ) {
        let normalizedNames = rows.map { SkillMapTopic.normalizedName($0.name) }
        let identityKeys = normalizedNames.map(SkillMapTopic.canonicalIdentityKey)
        let keyCounts = identityKeys.reduce(into: [String: Int]()) { counts, key in
            counts[key, default: 0] += 1
        }
        let idCounts = rows.reduce(into: [UUID: Int]()) { counts, row in
            counts[row.id, default: 0] += 1
        }
        let unsupportedSeparators = CharacterSet(charactersIn: ",;")
        var issues = [UUID: SkillNameIssue]()

        for (index, row) in rows.enumerated() {
            let name = normalizedNames[index]
            let key = identityKeys[index]
            let issue: SkillNameIssue?
            if idCounts[row.id, default: 0] > 1 {
                issue = .duplicateSkill
            } else if archivedTopicIDs.contains(row.id) {
                issue = .archivedSkill
            } else if name.isEmpty {
                issue = .required
            } else if name.count > 48 {
                issue = .tooLong(characterCount: name.count)
            } else if name.rangeOfCharacter(from: unsupportedSeparators) != nil {
                issue = .unsupportedSeparator
            } else if keyCounts[key, default: 0] > 1 {
                issue = .duplicate
            } else if retiredNameKeys.contains(key) {
                issue = .retiredName
            } else {
                issue = nil
            }

            if let issue {
                issues[row.id] = issue
            }
        }

        issueByTopicID = issues
        namedCount = normalizedNames.filter { !$0.isEmpty }.count
        isValid = SkillMapTopic.validatedNames(rows.map(\.name)) != nil && issues.isEmpty
    }
}

enum SkillNameContinuity: Equatable {
    case suggested
    case preservesProgress
    case startsFresh
    case keepsHistory
    case newSkill

    var label: String {
        switch self {
        case .suggested:
            "Suggested skill"
        case .preservesProgress:
            "Progress kept"
        case .startsFresh:
            "Starts fresh"
        case .keepsHistory:
            "History connected"
        case .newSkill:
            "New skill"
        }
    }

    var systemImage: String {
        switch self {
        case .suggested:
            "sparkles"
        case .preservesProgress, .keepsHistory:
            "checkmark.circle.fill"
        case .startsFresh, .newSkill:
            "plus.circle.fill"
        }
    }

    static func reviewing(
        status: SkillMapStatus,
        isExistingSkill: Bool
    ) -> Self {
        guard isExistingSkill else { return .startsFresh }
        return status == .suggested ? .suggested : .preservesProgress
    }

    @MainActor
    static func repairing(
        name: String,
        historyNameKeys: Set<String>
    ) -> Self {
        let key = SkillMapReconciler.competencyTopicKey(name)
        guard !key.isEmpty, historyNameKeys.contains(key) else { return .newSkill }
        return .keepsHistory
    }
}

struct SkillNameRowPresentation: Equatable {
    var position: Int
    var fieldAccessibilityLabel: String
    var removeAccessibilityLabel: String?
    var replaceAccessibilityLabel: String?
    var continuity: SkillNameContinuity
    var issue: SkillNameIssue?

    init(
        index: Int,
        name: String,
        canRemove: Bool,
        canReplace: Bool,
        continuity: SkillNameContinuity = .suggested,
        issue: SkillNameIssue? = nil
    ) {
        position = index + 1
        fieldAccessibilityLabel = "Skill \(position) name"
        self.continuity = continuity
        self.issue = issue

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = trimmedName.isEmpty
            ? "skill \(position)"
            : "skill \(position), \(trimmedName)"
        removeAccessibilityLabel = canRemove ? "Remove \(identity)" : nil
        replaceAccessibilityLabel = canReplace ? "Replace \(identity)" : nil
    }

    var actionsAccessibilityLabel: String {
        "Actions for skill \(position)"
    }

    var statusText: String {
        issue?.message ?? continuity.label
    }

    var statusSystemImage: String {
        issue == nil ? continuity.systemImage : "exclamationmark.circle.fill"
    }

    var fieldAccessibilityHint: String {
        statusText
    }
}

private enum SkillMapDestructiveAction: Equatable {
    case replace(id: UUID, name: String)
    case remove(id: UUID, name: String)

    var title: String {
        switch self {
        case let .replace(_, name):
            "Replace \(name)?"
        case let .remove(_, name):
            "Remove \(name)?"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .replace:
            "Replace skill"
        case .remove:
            "Remove skill"
        }
    }

    var message: String {
        switch self {
        case .replace:
            "Its saved history stays in your archive. The replacement starts with fresh questions and progress."
        case .remove:
            "Its saved history stays in your archive and the skill leaves your active plan."
        }
    }
}

struct SkillMapReviewView: View {
    let store: CheckpointStore
    private let reduceMotionOverride: Bool?
    private let originalTopics: [SkillMapTopic]
    private let originalStatus: SkillMapStatus

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var topics: [SkillMapTopic]
    @State private var pendingFocusPlan: SkillMapFocusPlan?
    @State private var pendingDestructiveAction: SkillMapDestructiveAction?
    @FocusState private var focusedSkillID: UUID?

    init(
        store: CheckpointStore,
        reduceMotionOverride: Bool? = nil,
        initialTopics: [SkillMapTopic]? = nil
    ) {
        let map = store.activeDerivedSkillMap
        self.store = store
        self.reduceMotionOverride = reduceMotionOverride
        originalTopics = map?.topics ?? []
        originalStatus = map?.status ?? .suggested
        _topics = State(initialValue: initialTopics ?? map?.topics ?? [])
        _pendingFocusPlan = State(initialValue: nil)
        _pendingDestructiveAction = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SkillMapEditorHero(
                        presentation: editorPresentation,
                        motionPolicy: motionPolicy
                    )

                    SectionPanel {
                        SkillMapListHeader()

                        VStack(spacing: 14) {
                            ForEach(topics) { topic in
                                if let index = topics.firstIndex(where: { $0.id == topic.id }) {
                                    let presentation = SkillNameRowPresentation(
                                        index: index,
                                        name: topics[index].name,
                                        canRemove: affordances.canRemove,
                                        canReplace: existingSkillIDs.contains(topic.id),
                                        continuity: continuity(for: topic.id),
                                        issue: validation.issueByTopicID[topic.id]
                                    )

                                    EditableSkillNameRow(
                                        skillID: topic.id,
                                        presentation: presentation,
                                        name: nameBinding(for: topic.id),
                                        objectives: topics[index].objectives,
                                        focusedSkillID: $focusedSkillID,
                                        requestRemove: presentation.removeAccessibilityLabel == nil
                                            ? nil
                                            : { requestRemoval(of: topic.id) },
                                        requestReplace: presentation.replaceAccessibilityLabel == nil
                                            ? nil
                                            : { requestReplacement(of: topic.id) }
                                    )
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
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
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
                PrimaryActionButton(
                    title: editorPresentation.actionTitle,
                    systemImage: hasChanges ? "checkmark" : "checkmark.circle"
                ) {
                    pendingFocusPlan = nil
                    focusedSkillID = nil
                    if store.reviewActiveDerivedSkillMap(topics: topics) {
                        dismiss()
                    }
                }
                .disabled(!editorPresentation.actionEnabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .onChange(of: validationAnnouncement) { _, message in
            announceValidation(message)
        }
        .confirmationDialog(
            pendingDestructiveAction?.title ?? "Update skill",
            isPresented: destructiveConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            if let action = pendingDestructiveAction {
                Button(action.confirmationTitle, role: .destructive) {
                    perform(action)
                    pendingDestructiveAction = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDestructiveAction = nil
                }
            }
        } message: {
            if let action = pendingDestructiveAction {
                Text(action.message)
            }
        }
    }

    private var validation: SkillMapEditorValidation {
        SkillMapEditorValidation(
            topics: topics,
            originalTopics: originalTopics,
            archivedTopics: store.activeDerivedSkillMap?.archivedTopics ?? []
        )
    }

    private var editorPresentation: SkillMapEditorPresentation {
        SkillMapEditorPresentation(
            mode: .review(status: originalStatus),
            goalTitle: store.goal?.title ?? "Your goal",
            skillCount: topics.count,
            namedCount: validation.namedCount,
            isValid: validation.isValid,
            hasChanges: hasChanges
        )
    }

    private var hasChanges: Bool {
        topics != originalTopics
    }

    private var affordances: SkillMapEditorAffordances {
        SkillMapEditorAffordances(count: topics.count)
    }

    private var motionPolicy: SkillMapMutationMotionPolicy {
        SkillMapMutationMotionPolicy(
            reduceMotion: reduceMotionOverride ?? systemReduceMotion
        )
    }

    private var validationAnnouncement: String? {
        for (index, topic) in topics.enumerated() {
            if let issue = validation.issueByTopicID[topic.id] {
                return "Skill \(index + 1): \(issue.message)"
            }
        }
        return nil
    }

    private var destructiveConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDestructiveAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDestructiveAction = nil
                }
            }
        )
    }

    private func announceValidation(_ message: String?) {
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    private var existingSkillIDs: Set<SkillMapTopic.ID> {
        Set(originalTopics.map(\.id))
    }

    private func continuity(for id: SkillMapTopic.ID) -> SkillNameContinuity {
        SkillNameContinuity.reviewing(
            status: originalStatus,
            isExistingSkill: existingSkillIDs.contains(id)
        )
    }

    private func requestRemoval(of id: SkillMapTopic.ID) {
        guard let topic = topics.first(where: { $0.id == id }) else { return }
        pendingDestructiveAction = .remove(id: id, name: displayName(for: topic))
    }

    private func requestReplacement(of id: SkillMapTopic.ID) {
        guard let topic = topics.first(where: { $0.id == id }) else { return }
        pendingDestructiveAction = .replace(id: id, name: displayName(for: topic))
    }

    private func displayName(for topic: SkillMapTopic) -> String {
        let normalizedName = SkillMapTopic.normalizedName(topic.name)
        return normalizedName.isEmpty ? "this skill" : "“\(normalizedName)”"
    }

    private func perform(_ action: SkillMapDestructiveAction) {
        switch action {
        case let .remove(id, _):
            removeSkill(id: id)
        case let .replace(id, _):
            replaceSkill(id: id)
        }
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
    private let historyNameKeys: Set<String>

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var topicDrafts: [SkillNameDraft]
    @State private var pendingFocusPlan: SkillMapFocusPlan?
    @FocusState private var focusedSkillID: UUID?

    init(store: CheckpointStore, reduceMotionOverride: Bool? = nil) {
        let competencies = store.sortedCompetencies
        self.store = store
        self.reduceMotionOverride = reduceMotionOverride
        historyNameKeys = Set(
            competencies
                .map { SkillMapReconciler.competencyTopicKey($0.topic) }
                .filter { !$0.isEmpty }
        )
        var seenKeys = Set<String>()
        var initialNames = competencies.compactMap { competency -> String? in
            let name = SkillMapTopic.normalizedName(competency.topic)
            let key = SkillMapTopic.canonicalIdentityKey(name)
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
                VStack(alignment: .leading, spacing: 16) {
                    SkillMapEditorHero(
                        presentation: editorPresentation,
                        motionPolicy: motionPolicy
                    )

                    SectionPanel {
                        SkillMapListHeader()

                        VStack(spacing: 14) {
                            ForEach(topicDrafts) { draft in
                                if let index = topicDrafts.firstIndex(where: { $0.id == draft.id }) {
                                    let presentation = SkillNameRowPresentation(
                                        index: index,
                                        name: topicDrafts[index].name,
                                        canRemove: affordances.canRemove,
                                        canReplace: false,
                                        continuity: repairContinuity(for: topicDrafts[index].name),
                                        issue: validation.issueByTopicID[draft.id]
                                    )

                                    EditableSkillNameRow(
                                        skillID: draft.id,
                                        presentation: presentation,
                                        name: nameBinding(for: draft.id),
                                        objectives: [],
                                        focusedSkillID: $focusedSkillID,
                                        requestRemove: presentation.removeAccessibilityLabel == nil
                                            ? nil
                                            : { removeSkill(id: draft.id) },
                                        requestReplace: nil
                                    )
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
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
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
                PrimaryActionButton(
                    title: editorPresentation.actionTitle,
                    systemImage: "checkmark"
                ) {
                    pendingFocusPlan = nil
                    focusedSkillID = nil
                    if store.repairActiveSkillMap(topicNames: topicDrafts.map(\.name)) {
                        dismiss()
                    }
                }
                .disabled(!editorPresentation.actionEnabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .onChange(of: validationAnnouncement) { _, message in
            announceValidation(message)
        }
    }

    private var validation: SkillMapEditorValidation {
        SkillMapEditorValidation(
            rows: topicDrafts.map { SkillMapEditorName(id: $0.id, name: $0.name) }
        )
    }

    private var editorPresentation: SkillMapEditorPresentation {
        SkillMapEditorPresentation(
            mode: .repair,
            goalTitle: store.goal?.title ?? "Your goal",
            skillCount: topicDrafts.count,
            namedCount: validation.namedCount,
            isValid: validation.isValid,
            hasChanges: true
        )
    }

    private var affordances: SkillMapEditorAffordances {
        SkillMapEditorAffordances(count: topicDrafts.count)
    }

    private var motionPolicy: SkillMapMutationMotionPolicy {
        SkillMapMutationMotionPolicy(
            reduceMotion: reduceMotionOverride ?? systemReduceMotion
        )
    }

    private var validationAnnouncement: String? {
        for (index, draft) in topicDrafts.enumerated() {
            if let issue = validation.issueByTopicID[draft.id] {
                return "Skill \(index + 1): \(issue.message)"
            }
        }
        return nil
    }

    private func announceValidation(_ message: String?) {
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    private func repairContinuity(for name: String) -> SkillNameContinuity {
        SkillNameContinuity.repairing(
            name: name,
            historyNameKeys: historyNameKeys
        )
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

private struct SkillMapEditorHero: View {
    let presentation: SkillMapEditorPresentation
    let motionPolicy: SkillMapMutationMotionPolicy

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CheckpointHeroSurface(
            glowColor: accent,
            glowOpacity: presentation.state == .changesReady ? 0.14 : 0.10,
            contentPadding: dynamicTypeSize.isAccessibilitySize ? 16 : 15
        ) {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 15 : 11) {
                heroIdentity

                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.title)
                        .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .title3.bold())
                        .foregroundStyle(CheckpointTheme.heroText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(presentation.detail)
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .overlay(CheckpointTheme.heroDivider)

                capacityRow
            }
        }
        .animation(motionPolicy.animation, value: presentation.state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilitySummary)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var heroIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                identity
                statusBadge
            }
        } else if usesWideStatusLayout {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 8) {
                    identityIcon

                    Text("SKILL MAP")
                        .font(.caption2.weight(.bold))
                        .tracking(0.9)
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: true, vertical: true)

                    Spacer(minLength: 4)
                    statusBadge
                        .fixedSize(horizontal: true, vertical: true)
                }

                Text(presentation.goalTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.heroText)
                    .lineLimit(1)
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                identity
                    .layoutPriority(1)
                Spacer(minLength: 2)
                statusBadge
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 10) {
            identityIcon

            VStack(alignment: .leading, spacing: 1) {
                Text("SKILL MAP")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(accent)

                Text(presentation.goalTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.heroText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.88)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityIcon: some View {
        Image(systemName: "point.3.connected.trianglepath.dotted")
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 38, height: 38)
            .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            .symbolEffect(.bounce, options: .nonRepeating, value: presentation.state)
            .symbolEffectsRemoved(!motionPolicy.permitsNodeMotion)
            .accessibilityHidden(true)
    }

    private var usesWideStatusLayout: Bool {
        presentation.state == .needsAttention || presentation.state == .changesReady
    }

    private var statusBadge: some View {
        StatusBadge(text: presentation.status, tint: accent)
            .contentTransition(.opacity)
            .accessibilityLabel("Status: \(presentation.status)")
    }

    private var capacityRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                capacityLabel
                Spacer(minLength: 8)
                nodeRail
            }

            VStack(alignment: .leading, spacing: 9) {
                capacityLabel
                nodeRail
            }
        }
    }

    private var capacityLabel: some View {
        Text(presentation.capacityText)
            .font(.caption.weight(.bold))
            .foregroundStyle(accent)
            .contentTransition(capacityContentTransition)
            .fixedSize(horizontal: true, vertical: true)
    }

    private var nodeRail: some View {
        HStack(spacing: 0) {
            ForEach(0..<SkillMapEditorAffordances.maximumSkillCount, id: \.self) { index in
                node(at: index)

                if index < SkillMapEditorAffordances.maximumSkillCount - 1 {
                    Rectangle()
                        .fill(index < presentation.namedCount - 1 ? accent : CheckpointTheme.heroDivider)
                        .frame(width: 11, height: 2)
                }
            }
        }
        .animation(motionPolicy.animation, value: presentation.namedCount)
        .animation(motionPolicy.animation, value: presentation.skillCount)
        .accessibilityHidden(true)
    }

    private func node(at index: Int) -> some View {
        let isNamed = index < presentation.namedCount
        let isSlot = index < presentation.skillCount
        return ZStack {
            Circle()
                .fill(isNamed ? accent : Color.clear)

            Circle()
                .stroke(
                    isSlot ? accent.opacity(isNamed ? 1 : 0.82) : CheckpointTheme.heroDivider,
                    lineWidth: isSlot ? 2 : 1
                )
        }
        .frame(width: 11, height: 11)
        .scaleEffect(isNamed ? 1 : 0.84)
    }

    private var capacityContentTransition: ContentTransition {
        motionPolicy.permitsNodeMotion ? .numericText() : .identity
    }

    private var accent: Color {
        switch presentation.state {
        case .draftReady, .ready:
            CheckpointTheme.heroInfo
        case .current:
            CheckpointTheme.heroSuccess
        case .changesReady:
            CheckpointTheme.heroWarning
        case .needsAttention:
            CheckpointTheme.heroDanger
        }
    }
}

private struct SkillMapListHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    title
                    boundary
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    title
                    Spacer(minLength: 8)
                    boundary
                }
            }
        }
    }

    private var title: some View {
        Text("Your skill areas")
            .font(.headline)
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var boundary: some View {
        Text("3–6 skills")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
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
    let objectives: [SkillMapObjective]
    let focusedSkillID: FocusState<UUID?>.Binding
    let requestRemove: (() -> Void)?
    let requestReplace: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        skillNameField

                        if requestRemove != nil || requestReplace != nil {
                            actionMenu
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        skillNameField

                        if requestRemove != nil || requestReplace != nil {
                            actionMenu
                        }
                    }
                }
            }

            Label(presentation.statusText, systemImage: presentation.statusSystemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusTint)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)

            if !objectives.isEmpty {
                objectiveDisclosure
            }
        }
    }

    private var skillNameField: some View {
        TextField(
            "Skill \(presentation.position)",
            text: $name,
            axis: .vertical
        )
        .lineLimit(1...3)
        .textFieldStyle(.plain)
        .foregroundStyle(CheckpointTheme.text)
        .padding(12)
        .background(
            CheckpointTheme.panelRaised,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    presentation.issue == nil
                        ? CheckpointTheme.controlStroke
                        : CheckpointTheme.coral.opacity(0.88),
                    lineWidth: presentation.issue == nil ? 1 : 1.5
                )
        }
        .focused(focusedSkillID, equals: skillID)
        .accessibilityLabel(presentation.fieldAccessibilityLabel)
        .accessibilityHint(presentation.fieldAccessibilityHint)
    }

    private var actionMenu: some View {
        Menu {
            if let requestReplace {
                Button(action: requestReplace) {
                    Label("Replace skill", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel(presentation.replaceAccessibilityLabel ?? "Replace skill")
            }

            if let requestRemove {
                Button(role: .destructive, action: requestRemove) {
                    Label("Remove skill", systemImage: "archivebox")
                }
                .accessibilityLabel(presentation.removeAccessibilityLabel ?? "Remove skill")
            }
        } label: {
            if dynamicTypeSize.isAccessibilitySize {
                Label("Actions", systemImage: "ellipsis.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(minHeight: 44)
            } else {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.actionsAccessibilityLabel)
        .accessibilityHint(actionsAccessibilityHint)
    }

    private var actionsAccessibilityHint: String {
        switch (requestReplace != nil, requestRemove != nil) {
        case (true, true):
            "Replace or remove this skill"
        case (true, false):
            "Replace this skill"
        case (false, true):
            "Remove this skill"
        case (false, false):
            ""
        }
    }

    private var objectiveDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(objectives) { objective in
                    Label(objective.name, systemImage: "circle.fill")
                        .labelStyle(SkillObjectiveLabelStyle())
                        .font(.caption)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 6)
        } label: {
            Label(
                "\(objectives.count) practice \(objectives.count == 1 ? "focus" : "focuses")",
                systemImage: "scope"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.muted)
        }
        .tint(CheckpointTheme.teal)
    }

    private var statusTint: Color {
        if presentation.issue != nil {
            return CheckpointTheme.coral
        }
        switch presentation.continuity {
        case .suggested, .newSkill:
            return CheckpointTheme.blue
        case .preservesProgress, .keepsHistory:
            return CheckpointTheme.teal
        case .startsFresh:
            return CheckpointTheme.amber
        }
    }
}

private struct SkillObjectiveLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            configuration.icon
                .font(.system(size: 5))
                .accessibilityHidden(true)
            configuration.title
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
                .background(
                    CheckpointTheme.teal.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            CheckpointTheme.teal.opacity(0.36),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                }
        }
        .buttonStyle(CheckpointPressButtonStyle())
    }
}
