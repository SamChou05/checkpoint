import Accessibility
import SwiftUI
import UniformTypeIdentifiers

enum GoalSetupMode: Equatable {
    case firstGoal
    case newGoal
    case editGoal

    func preferredQuestionStyle(from existingGoal: Goal?) -> QuestionFormat {
        guard self == .editGoal else { return .multipleChoice }
        return existingGoal?.preferredQuestionStyle ?? .multipleChoice
    }
}

struct GoalSetupProtectionConfirmationPresentation: Equatable {
    let title: String
    let message: String
    let confirmationButtonTitle: String
    let cancelButtonTitle = "Keep editing"

    init(confirmation: GoalProfileMutationConfirmation) {
        let readiness = confirmation.plan.resultingReadiness
            ?? .incomplete(selectableCount: 0, requiredCount: 0)
        let selectableCount = readiness.selectableCount
        let requiredCount = readiness.requiredCount
        let readinessText = "\(selectableCount) of \(requiredCount) checkpoint questions ready"
        let impact: GoalSwitchProtectionImpact?
        switch confirmation.consent {
        case let .protection(value), let .deletionAndProtection(value):
            impact = value
        case .deletion:
            impact = nil
        }

        switch (confirmation.plan.request.operation, impact) {
        case (.create, .turnsOffImmediately):
            title = "Create goal and turn off protection?"
            message = "The new goal has \(readinessText). Creating it now makes it current and turns off app protection. Start protection again after a full checkpoint is ready."
            confirmationButtonTitle = "Create and turn off"
        case (.create, .preventsRelockAfterBreak):
            title = "Create goal before this break ends?"
            message = "Your current break will continue. Protection will return when it ends only if the new goal has a full checkpoint ready; otherwise it will turn off and you'll need to start it again. Right now, it has \(readinessText)."
            confirmationButtonTitle = "Create goal"
        case (.edit, .turnsOffImmediately):
            title = "Save changes and turn off protection?"
            message = "These changes leave \(readinessText). Saving now turns off app protection. Start protection again after a full checkpoint is ready."
            confirmationButtonTitle = "Save and turn off"
        case (.edit, .preventsRelockAfterBreak):
            title = "Save changes before this break ends?"
            message = "Your current break will continue. Protection will return when it ends only if this goal has a full checkpoint ready; otherwise it will turn off and you'll need to start it again. These changes leave \(readinessText)."
            confirmationButtonTitle = "Save changes"
        case (.delete, _):
            title = "Delete goal?"
            message = "Delete this goal and all of its progress? This can't be undone."
            confirmationButtonTitle = "Delete goal"
        case (.create, nil):
            title = "Create goal?"
            message = "Create this goal and prepare its first checkpoint."
            confirmationButtonTitle = "Create goal"
        case (.edit, nil):
            title = "Save changes?"
            message = "Save these changes to the current goal."
            confirmationButtonTitle = "Save changes"
        }
    }
}

enum GoalSetupHeroState: Equatable {
    case awaitingGoal
    case ready
    case upToDate
    case unsavedChanges
    case working
}

enum GoalSetupEditImpact: Equatable {
    case none
    case deadlineOnly
    case practiceSetup

    init(
        baseline: GoalSetupEditBaseline?,
        title: String,
        deadline: Date,
        currentLevel: String,
        focusAreas: String,
        sourceDocuments: [GoalSourceDocument],
        preferredQuestionStyle: QuestionFormat,
        minimumQuestionDifficulty: Int,
        calendar: Calendar = .current
    ) {
        guard let baseline else {
            self = .none
            return
        }

        let practiceSetupChanged =
            title.trimmingCharacters(in: .whitespacesAndNewlines) != baseline.title ||
            currentLevel.trimmingCharacters(in: .whitespacesAndNewlines) != baseline.currentLevel ||
            focusAreas.trimmingCharacters(in: .whitespacesAndNewlines) != baseline.focusAreas ||
            GoalSourceDocument.normalizedDocuments(sourceDocuments) != baseline.sourceDocuments ||
            preferredQuestionStyle != baseline.preferredQuestionStyle ||
            UnlockPolicy.normalizedQuestionDifficulty(minimumQuestionDifficulty) != baseline.minimumQuestionDifficulty

        if practiceSetupChanged {
            self = .practiceSetup
        } else if !calendar.isDate(deadline, inSameDayAs: baseline.deadline) {
            self = .deadlineOnly
        } else {
            self = .none
        }
    }
}

struct GoalSetupEditBaseline: Equatable {
    let goalID: Goal.ID
    let title: String
    let deadline: Date
    let category: GoalCategory
    let currentLevel: String
    let focusAreas: String
    let sourceDocuments: [GoalSourceDocument]
    let preferredQuestionStyle: QuestionFormat
    let minimumQuestionDifficulty: Int

    init(goal: Goal) {
        goalID = goal.id
        title = goal.title.trimmingCharacters(in: .whitespacesAndNewlines)
        deadline = goal.deadline
        category = goal.category
        currentLevel = goal.currentLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        focusAreas = goal.focusAreas.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceDocuments = GoalSourceDocument.normalizedDocuments(goal.sourceDocuments)
        preferredQuestionStyle = goal.preferredQuestionStyle
        minimumQuestionDifficulty = UnlockPolicy.normalizedQuestionDifficulty(
            goal.minimumQuestionDifficulty
        )
    }
}

struct GoalSetupHeroPresentation: Equatable {
    let state: GoalSetupHeroState
    let eyebrow: String
    let title: String
    let subtitle: String
    let status: String
    let systemImage: String
    let guidanceSystemImage: String
    let guidance: String
    let accessibilityContext: String

    init(
        mode: GoalSetupMode,
        hasGoalTitle: Bool,
        editImpact: GoalSetupEditImpact = .none,
        isWorking: Bool
    ) {
        if isWorking {
            state = .working
        } else if !hasGoalTitle {
            state = .awaitingGoal
        } else if mode != .editGoal {
            state = .ready
        } else {
            state = editImpact == .none ? .upToDate : .unsavedChanges
        }

        switch mode {
        case .firstGoal:
            eyebrow = "SETUP · STEP 2 OF 3"
            accessibilityContext = "Checkpoint setup, step 2 of 3"
            title = "Set your outcome."
            subtitle = "Checkpoint turns it into short practice before selected apps and sites open."
        case .newGoal:
            eyebrow = "NEW GOAL"
            accessibilityContext = "New goal"
            title = "Add another outcome."
            subtitle = "Build a separate practice path with its own checkpoints and progress."
        case .editGoal:
            eyebrow = "EDIT GOAL"
            accessibilityContext = "Edit goal"
            title = "Refine this outcome."
            subtitle = "Your changes will shape future checkpoints for this goal."
        }

        switch state {
        case .awaitingGoal:
            status = "Goal needed"
            systemImage = "scope"
        case .ready:
            status = "Ready"
            systemImage = "sparkles"
        case .upToDate:
            status = "Up to date"
            systemImage = "checkmark.circle.fill"
        case .unsavedChanges:
            status = "Unsaved changes"
            systemImage = "pencil.line"
        case .working:
            status = mode == .editGoal ? "Saving…" : "Preparing…"
            systemImage = "hourglass"
        }

        if state == .awaitingGoal {
            guidanceSystemImage = "arrow.down"
            guidance = mode == .editGoal
                ? "Enter a goal before saving."
                : "Enter one outcome to continue."
        } else {
            switch mode {
            case .firstGoal:
                guidanceSystemImage = "arrow.right"
                guidance = "Next: choose the apps this goal protects."
            case .newGoal:
                guidanceSystemImage = "checkmark.circle"
                guidance = "This goal becomes active. Your other goals stay available."
            case .editGoal:
                switch editImpact {
                case .none:
                    guidanceSystemImage = "checkmark.circle"
                    guidance = "Your current goal is saved."
                case .deadlineOnly:
                    guidanceSystemImage = "calendar"
                    guidance = "Only the target date will change."
                case .practiceSetup:
                    guidanceSystemImage = "arrow.triangle.2.circlepath"
                    guidance = "Future questions will use the updated practice setup."
                }
            }
        }
    }
}

struct GoalSetupDirectionPresentation: Equatable {
    let title: String
    let detail: String
    let topics: [String]
    let systemImage: String
    let accessibilityAnnouncement: String

    init?(goalTitle: String, focusAreas: String) {
        let target = GoalQuestionContext.learningTarget(fromTitle: goalTitle)
        guard !target.isEmpty else { return nil }

        let meaningfulTopics = GoalQuestionContext.meaningfulFocusTopics(from: focusAreas)
        if meaningfulTopics.isEmpty {
            guard let interpretation = GoalSetupGuidance(
                title: goalTitle,
                focusAreas: focusAreas
            ).interpretation else {
                return nil
            }
            title = "Starting with “\(target)”"
            detail = "Checkpoint will use this as the starting direction for an editable skill map."
            topics = []
            systemImage = "sparkles"
            accessibilityAnnouncement = "Checkpoint will prepare \(interpretation)."
        } else {
            let count = meaningfulTopics.count
            title = "Using \(count) \(count == 1 ? "topic" : "topics") you chose"
            detail = "These topics will seed an editable skill map for future questions."
            topics = meaningfulTopics
            systemImage = "list.bullet.rectangle"
            accessibilityAnnouncement = "Practice direction updated: \(meaningfulTopics.joined(separator: ", "))."
        }
    }
}

struct GoalSetupDirectionPreviewState: Equatable {
    private(set) var presentation: GoalSetupDirectionPresentation?
    private(set) var lastAnnouncement: String?

    init(
        initialPresentation: GoalSetupDirectionPresentation? = nil,
        initialPresentationIsCommitted: Bool = false
    ) {
        presentation = initialPresentation
        lastAnnouncement = initialPresentationIsCommitted
            ? initialPresentation?.accessibilityAnnouncement
            : nil
    }

    mutating func preview(goalTitle: String, focusAreas: String) {
        presentation = GoalSetupDirectionPresentation(
            goalTitle: goalTitle,
            focusAreas: focusAreas
        )
        if presentation == nil {
            lastAnnouncement = nil
        }
    }

    mutating func commit(goalTitle: String, focusAreas: String) -> String? {
        preview(goalTitle: goalTitle, focusAreas: focusAreas)

        guard let announcement = presentation?.accessibilityAnnouncement else {
            return nil
        }
        guard announcement != lastAnnouncement else { return nil }

        lastAnnouncement = announcement
        return announcement
    }
}

struct GoalSetupCustomizationSummary: Equatable {
    let text: String

    init(
        focusAreas: String,
        hasCurrentLevel: Bool,
        sourceDocumentCount: Int,
        minimumQuestionDifficulty: Int
    ) {
        var parts: [String] = []
        let focusAreaCount = GoalQuestionContext.meaningfulFocusTopics(from: focusAreas).count
        if focusAreaCount > 0 {
            parts.append("\(focusAreaCount) \(focusAreaCount == 1 ? "topic" : "topics")")
        }
        if hasCurrentLevel {
            parts.append("Experience noted")
        }
        if sourceDocumentCount > 0 {
            parts.append(
                "\(sourceDocumentCount) \(sourceDocumentCount == 1 ? "source" : "sources")"
            )
        }
        if minimumQuestionDifficulty != UnlockPolicy.default.minimumQuestionDifficulty {
            parts.append("Level \(UnlockPolicy.normalizedQuestionDifficulty(minimumQuestionDifficulty))")
        }

        text = parts.isEmpty ? "Automatic" : parts.joined(separator: " · ")
    }
}

enum GoalSetupMotionStyle: Equatable {
    case animated
    case identity
}

struct GoalSetupMotionPolicy {
    let style: GoalSetupMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var animation: Animation? {
        style == .animated ? CheckpointMotion.change : nil
    }

    var revealAnimation: Animation? {
        style == .animated ? CheckpointMotion.reveal : nil
    }

    var transition: AnyTransition {
        style == .animated
            ? .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            )
            : .identity
    }

    func previewAnimation(wasVisible: Bool, isVisible: Bool) -> Animation? {
        guard style == .animated else { return nil }
        return !wasVisible && isVisible ? CheckpointMotion.reveal : CheckpointMotion.change
    }
}

struct GoalSetupPersistenceAnnouncementPolicy {
    enum Event {
        case recoveryMessageChanged
        case saveFailed
    }

    static let fallbackMessage =
        "Checkpoint couldn't save this goal. Keep the app open, free device storage, and try again."

    static func message(
        for event: Event,
        recoveryMessage: String?,
        previouslyAnnouncedMessage: String?
    ) -> String? {
        let message = recoveryMessage ?? fallbackMessage
        switch event {
        case .recoveryMessageChanged:
            guard recoveryMessage != nil,
                  message != previouslyAnnouncedMessage else { return nil }
            return message
        case .saveFailed:
            return message
        }
    }
}

struct GoalSetupDraftSnapshot: Equatable {
    let title: String
    let deadline: Date
    let currentLevel: String
    let focusAreas: String
    let sourceDocuments: [GoalSourceDocument]
    let preferredQuestionStyle: QuestionFormat
    let minimumQuestionDifficulty: Int

    init(
        title: String,
        deadline: Date,
        currentLevel: String,
        focusAreas: String,
        sourceDocuments: [GoalSourceDocument],
        preferredQuestionStyle: QuestionFormat,
        minimumQuestionDifficulty: Int
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deadline = deadline
        self.currentLevel = currentLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.focusAreas = focusAreas.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceDocuments = GoalSourceDocument.normalizedDocuments(sourceDocuments)
        self.preferredQuestionStyle = preferredQuestionStyle
        self.minimumQuestionDifficulty = UnlockPolicy.normalizedQuestionDifficulty(
            minimumQuestionDifficulty
        )
    }

    func hasMeaningfulChanges(
        from baseline: GoalSetupDraftSnapshot,
        calendar: Calendar = .current
    ) -> Bool {
        title != baseline.title ||
            !calendar.isDate(deadline, inSameDayAs: baseline.deadline) ||
            currentLevel != baseline.currentLevel ||
            focusAreas != baseline.focusAreas ||
            sourceDocuments != baseline.sourceDocuments ||
            preferredQuestionStyle != baseline.preferredQuestionStyle ||
            minimumQuestionDifficulty != baseline.minimumQuestionDifficulty
    }
}

struct GoalSetupDismissalPolicy: Equatable {
    let requiresDiscardConfirmation: Bool
    let preventsInteractiveDismissal: Bool

    init(
        mode: GoalSetupMode,
        hasUnsavedDraft: Bool,
        hasPendingImport: Bool = false
    ) {
        let hasPendingWork = hasUnsavedDraft || hasPendingImport
        requiresDiscardConfirmation = mode != .firstGoal && hasPendingWork
        preventsInteractiveDismissal = mode == .firstGoal || hasPendingWork
    }
}

enum GoalSetupPrimaryActionIntent: Equatable {
    case dismiss
    case save
}

struct GoalSetupPrimaryActionPresentation: Equatable {
    let mode: GoalSetupMode
    let title: String
    let systemImage: String
    let intent: GoalSetupPrimaryActionIntent

    init(mode: GoalSetupMode, editImpact: GoalSetupEditImpact, isWorking: Bool) {
        self.mode = mode
        if isWorking {
            title = mode == .editGoal ? "Saving changes" : "Preparing your goal"
            systemImage = mode == .newGoal ? "plus" : "checkmark"
            intent = .save
            return
        }

        switch mode {
        case .firstGoal:
            title = "Continue to app selection"
            systemImage = "arrow.right"
            intent = .save
        case .newGoal:
            title = "Create goal"
            systemImage = "plus"
            intent = .save
        case .editGoal where editImpact == .none:
            title = "Done"
            systemImage = "checkmark"
            intent = .dismiss
        case .editGoal:
            title = "Save changes"
            systemImage = "checkmark"
            intent = .save
        }
    }

    func displayTitle(
        isAccessibilitySize: Bool,
        isImportingSources: Bool = false
    ) -> String {
        if isImportingSources {
            return isAccessibilitySize ? "Reading files" : "Reading study materials"
        }
        if isAccessibilitySize, mode == .firstGoal {
            return "Choose apps"
        }
        return title
    }
}

struct GoalSetupDirectionInput: Hashable {
    let goalTitle: String
    let focusAreas: String

    init(goalTitle: String, focusAreas: String) {
        self.goalTitle = goalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.focusAreas = focusAreas.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GoalSetupDirectionPreviewTaskID: Hashable {
    let input: GoalSetupDirectionInput
    let reduceMotion: Bool
}

enum GoalSetupLayoutElement: Hashable {
    case viewport
    case hero
    case goalPanel
    case titleLabel
    case titleField
    case actionBar
}

private struct GoalSetupLayoutFrameReporter: ViewModifier {
    let element: GoalSetupLayoutElement
    let report: (@MainActor (GoalSetupLayoutElement, CGRect) -> Void)?

    func body(content: Content) -> some View {
        content.background {
            if let report {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(goalSetupLayoutCoordinateSpaceName))

                    Color.clear
                        .onAppear {
                            report(element, frame)
                        }
                        .onChange(of: frame) { _, updatedFrame in
                            report(element, updatedFrame)
                        }
                }
            }
        }
    }
}

private extension View {
    func reportGoalSetupLayoutFrame(
        _ element: GoalSetupLayoutElement,
        using report: (@MainActor (GoalSetupLayoutElement, CGRect) -> Void)?
    ) -> some View {
        modifier(GoalSetupLayoutFrameReporter(element: element, report: report))
    }
}

let goalSetupLayoutCoordinateSpaceName = "Checkpoint.GoalSetup.Layout"

private enum GoalSetupField: Hashable {
    case title
    case focusAreas
    case currentLevel
}

struct OnboardingView: View {
    let store: CheckpointStore
    private let workflow: CheckpointWorkflowCoordinator
    private let mode: GoalSetupMode
    private let editBaseline: GoalSetupEditBaseline?
    private let initialDraft: GoalSetupDraftSnapshot
    private let preferredQuestionStyle: QuestionFormat
    private let reduceMotionOverride: Bool?
    private let workingStateOverride: Bool?
    private let layoutReporter: (@MainActor (GoalSetupLayoutElement, CGRect) -> Void)?
    private let onFirstGoalCreated: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: GoalSetupField?
    @State private var title = ""
    @State private var deadline: Date
    @State private var focusAreas = ""
    @State private var currentLevel = ""
    @State private var sourceDocuments: [GoalSourceDocument] = []
    @State private var minimumQuestionDifficulty = UnlockPolicy.default.minimumQuestionDifficulty
    @State private var isCreating = false
    @State private var isCustomizationExpanded = false
    @State private var isSourceImporterPresented = false
    @State private var isImportingSources = false
    @State private var sourceImportMessage: String?
    @State private var isDiscardConfirmationPresented = false
    @State private var suppressNextDirectionAnnouncement = false
    @State private var announcedPersistenceRecoveryMessage: String?
    @State private var directionPreviewState = GoalSetupDirectionPreviewState()
    @State private var pendingProtectionConfirmation: GoalProfileMutationConfirmation?
    @State private var queuedProtectionConfirmation: GoalProfileMutationConfirmation?
    @State private var mutationRequestID: UUID
    @State private var mutationCreatedAt: Date
    @State private var sourceImportTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?

    init(
        store: CheckpointStore,
        workflow: CheckpointWorkflowCoordinator,
        reduceMotionOverride: Bool? = nil,
        workingStateOverride: Bool? = nil,
        layoutReporter: (@MainActor (GoalSetupLayoutElement, CGRect) -> Void)? = nil,
        onFirstGoalCreated: @escaping () -> Void = {}
    ) {
        self.store = store
        self.workflow = workflow
        self.reduceMotionOverride = reduceMotionOverride
        self.workingStateOverride = workingStateOverride
        self.layoutReporter = layoutReporter
        self.onFirstGoalCreated = onFirstGoalCreated
        _mutationRequestID = State(initialValue: UUID())
        _mutationCreatedAt = State(initialValue: Date())

        let resolvedMode: GoalSetupMode
        if store.goal == nil {
            resolvedMode = .firstGoal
        } else if store.isCreatingGoalProfile {
            resolvedMode = .newGoal
        } else {
            resolvedMode = .editGoal
        }
        mode = resolvedMode
        preferredQuestionStyle = resolvedMode.preferredQuestionStyle(from: store.goal)

        if let goal = store.goal, resolvedMode == .editGoal {
            let presentedDeadline = max(goal.deadline, Date())
            editBaseline = GoalSetupEditBaseline(goal: goal)
            _title = State(initialValue: goal.title)
            _deadline = State(initialValue: presentedDeadline)
            _focusAreas = State(initialValue: goal.focusAreas)
            _currentLevel = State(initialValue: goal.currentLevel)
            _sourceDocuments = State(initialValue: goal.sourceDocuments)
            _minimumQuestionDifficulty = State(initialValue: goal.minimumQuestionDifficulty)
            initialDraft = GoalSetupDraftSnapshot(
                title: goal.title,
                deadline: goal.deadline,
                currentLevel: goal.currentLevel,
                focusAreas: goal.focusAreas,
                sourceDocuments: goal.sourceDocuments,
                preferredQuestionStyle: preferredQuestionStyle,
                minimumQuestionDifficulty: goal.minimumQuestionDifficulty
            )
            _directionPreviewState = State(
                initialValue: GoalSetupDirectionPreviewState(
                    initialPresentation: GoalSetupDirectionPresentation(
                        goalTitle: goal.title,
                        focusAreas: goal.focusAreas
                    ),
                    initialPresentationIsCommitted: true
                )
            )
            let hasCustomizations = !GoalQuestionContext.meaningfulFocusTopics(
                from: goal.focusAreas
            ).isEmpty
                || !goal.currentLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !goal.sourceDocuments.isEmpty
                || goal.minimumQuestionDifficulty != UnlockPolicy.default.minimumQuestionDifficulty
            _isCustomizationExpanded = State(initialValue: hasCustomizations)
        } else {
            let presentedDeadline = Calendar.current.date(
                byAdding: .month,
                value: 2,
                to: Date()
            ) ?? Date()
            editBaseline = nil
            _deadline = State(initialValue: presentedDeadline)
            initialDraft = GoalSetupDraftSnapshot(
                title: "",
                deadline: presentedDeadline,
                currentLevel: "",
                focusAreas: "",
                sourceDocuments: [],
                preferredQuestionStyle: preferredQuestionStyle,
                minimumQuestionDifficulty: UnlockPolicy.default.minimumQuestionDifficulty
            )
        }
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var isGoalSaveWorking: Bool {
        workingStateOverride ?? isCreating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: dynamicTypeSize.isAccessibilitySize ? 14 : 16
                ) {
                    goalSetupHeader
                        .reportGoalSetupLayoutFrame(.hero, using: layoutReporter)

                    SectionPanel(goalTimingSectionTitle) {
                        Text("Learning goal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)
                            .reportGoalSetupLayoutFrame(.titleLabel, using: layoutReporter)

                        TextField(
                            "Learning goal",
                            text: $title,
                            prompt: Text(goalTitlePrompt),
                            axis: .vertical
                        )
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                            .padding(12)
                            .background(
                                CheckpointTheme.panelRaised,
                                in: RoundedRectangle(
                                    cornerRadius: CheckpointTheme.compactCornerRadius,
                                    style: .continuous
                                )
                            )
                            .focused($focusedField, equals: .title)
                            .submitLabel(.done)
                            .onSubmit {
                                focusedField = nil
                            }
                            .reportGoalSetupLayoutFrame(.titleField, using: layoutReporter)

                        targetDatePicker
                    }
                    .reportGoalSetupLayoutFrame(.goalPanel, using: layoutReporter)

                    if dynamicTypeSize.isAccessibilitySize {
                        accessibilitySetupContext
                    }

                    if let persistenceMessage = store.persistenceRecoveryMessage {
                        Label(persistenceMessage, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .background(
                                CheckpointTheme.panel,
                                in: RoundedRectangle(
                                    cornerRadius: CheckpointTheme.compactCornerRadius,
                                    style: .continuous
                                )
                            )
                    }

                    if let direction = directionPreviewState.presentation {
                        GoalSetupDirectionCard(
                            presentation: direction,
                            reduceMotionOverride: reduceMotion
                        )
                            .transition(goalSetupMotionPolicy.transition)
                    }

                    SectionPanel {
                        DisclosureGroup(isExpanded: $isCustomizationExpanded) {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Topics to focus on")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text("Add anything Checkpoint must cover. Leave this blank and we’ll suggest an editable topic map from your goal.")
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)

                                    TextField("For example: contracts, vocabulary", text: $focusAreas, axis: .vertical)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(CheckpointTheme.text)
                                        .padding(12)
                                        .background(
                                            CheckpointTheme.panelRaised,
                                            in: RoundedRectangle(
                                                cornerRadius: CheckpointTheme.compactCornerRadius,
                                                style: .continuous
                                            )
                                        )
                                        .focused($focusedField, equals: .focusAreas)
                                        .submitLabel(.done)
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("What you already know")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text("Optional. A short note helps us avoid questions that are far too easy or hard. Leave it blank and we'll learn from your answers.")
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)

                                    TextField(
                                        "For example: new to this; strong on algebra, weak on proofs",
                                        text: $currentLevel,
                                        axis: .vertical
                                    )
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(CheckpointTheme.text)
                                    .padding(12)
                                    .background(
                                        CheckpointTheme.panelRaised,
                                        in: RoundedRectangle(
                                            cornerRadius: CheckpointTheme.compactCornerRadius,
                                            style: .continuous
                                        )
                                    )
                                    .focused($focusedField, equals: .currentLevel)
                                    .submitLabel(.done)
                                }

                                Divider()

                                studyMaterialsSection

                                Divider()

                                startingLevelControl
                            }
                            .padding(.top, 12)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Fine-tune practice")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)

                                Text(customizationSummary.text)
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 24 : 0)
                        }
                        .tint(CheckpointTheme.teal)
                        .sensoryFeedback(.selection, trigger: isCustomizationExpanded)
                    }

                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .reportGoalSetupLayoutFrame(.viewport, using: layoutReporter)
            .disabled(isGoalSaveWorking)
            .scrollDismissesKeyboard(.interactively)
            .checkpointScreenBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveActionBar
                    .reportGoalSetupLayoutFrame(.actionBar, using: layoutReporter)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if mode != .firstGoal {
                        Button("Cancel") {
                            requestGoalSetupDismissal()
                        }
                        .foregroundStyle(CheckpointTheme.teal)
                        .disabled(isGoalSaveWorking)
                    }
                }
            }
        }
        .coordinateSpace(name: goalSetupLayoutCoordinateSpaceName)
        .interactiveDismissDisabled(
            dismissalPolicy.preventsInteractiveDismissal
                || store.hasResumedMembershipGoalCreation
        )
        .fileImporter(
            isPresented: $isSourceImporterPresented,
            allowedContentTypes: GoalSourceDocumentImporter.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleSourceImport(result)
        }
        .alert(
            pendingProtectionConfirmationPresentation?.title ?? "Save goal?",
            isPresented: protectionConfirmationIsPresented,
            presenting: pendingProtectionConfirmation
        ) { confirmation in
            let presentation = GoalSetupProtectionConfirmationPresentation(
                confirmation: confirmation
            )
            Button(presentation.confirmationButtonTitle, role: .destructive) {
                confirmProtectedGoalSave(confirmation)
            }
            Button(presentation.cancelButtonTitle, role: .cancel) {
                queuedProtectionConfirmation = nil
                pendingProtectionConfirmation = nil
            }
        } message: { confirmation in
            Text(
                GoalSetupProtectionConfirmationPresentation(
                    confirmation: confirmation
                ).message
            )
        }
        .alert("Discard changes?", isPresented: $isDiscardConfirmationPresented) {
            Button("Discard changes", role: .destructive) {
                dismissGoalSetup()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(discardConfirmationMessage)
        }
        .onDisappear {
            cancelPendingOperations()
            if !store.isOnboardingPresented {
                store.isCreatingGoalProfile = false
            }
        }
        .onAppear {
            announcePersistenceRecoveryIfNeeded(store.persistenceRecoveryMessage)
        }
        .onChange(of: focusedField) { previousField, currentField in
            guard previousField != currentField,
                  isDirectionPreviewField(previousField),
                  !isDirectionPreviewField(currentField) else { return }
            if suppressNextDirectionAnnouncement {
                suppressNextDirectionAnnouncement = false
                return
            }
            commitDirectionPreview()
        }
        .onChange(of: sourceImportMessage) { _, message in
            guard let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
        .onChange(of: store.persistenceRecoveryMessage) { _, message in
            announcePersistenceRecoveryIfNeeded(message)
        }
        .task(id: directionPreviewTaskID) {
            let taskID = directionPreviewTaskID
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            previewDirection(taskID.input, reduceMotion: taskID.reduceMotion)
        }
    }

    private var goalSetupHeader: some View {
        GoalSetupHero(
            presentation: heroPresentation,
            reduceMotion: reduceMotion
        )
    }

    private var accessibilitySetupContext: some View {
        Label {
            Text(heroPresentation.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(CheckpointTheme.teal)
                .accessibilityHidden(true)
        }
        .font(.footnote)
        .foregroundStyle(CheckpointTheme.muted)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panel,
            in: RoundedRectangle(
                cornerRadius: CheckpointTheme.compactCornerRadius,
                style: .continuous
            )
        )
    }

    private var saveActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            PrimaryActionButton(
                title: primaryButtonDisplayTitle,
                systemImage: primaryActionPresentation.systemImage,
                isLoading: isGoalSaveWorking || isImportingSources
            ) {
                clearFocusForTransition()
                switch primaryActionPresentation.intent {
                case .dismiss:
                    dismissGoalSetup()
                case .save:
                    requestGoalSave()
                }
            }
            .disabled(isGoalSaveWorking || isImportingSources || isTitleEmpty)
            .accessibilityLabel(primaryActionAccessibilityLabel)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var primaryActionPresentation: GoalSetupPrimaryActionPresentation {
        GoalSetupPrimaryActionPresentation(
            mode: mode,
            editImpact: editImpact,
            isWorking: isGoalSaveWorking
        )
    }

    private var primaryButtonDisplayTitle: String {
        primaryActionPresentation.displayTitle(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            isImportingSources: isImportingSources
        )
    }

    private var primaryActionAccessibilityLabel: String {
        if isImportingSources {
            return "Reading study materials, in progress"
        }
        return isGoalSaveWorking
            ? "\(primaryActionPresentation.title), in progress"
            : primaryActionPresentation.title
    }

    private var goalTimingSectionTitle: String? {
        dynamicTypeSize.isAccessibilitySize ? nil : "Goal and timing"
    }

    private var goalTitlePrompt: String {
        dynamicTypeSize.isAccessibilitySize ? "Your goal" : "e.g. Pass the bar exam"
    }

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var heroPresentation: GoalSetupHeroPresentation {
        GoalSetupHeroPresentation(
            mode: mode,
            hasGoalTitle: !isTitleEmpty,
            editImpact: editImpact,
            isWorking: isGoalSaveWorking
        )
    }

    private var customizationSummary: GoalSetupCustomizationSummary {
        GoalSetupCustomizationSummary(
            focusAreas: focusAreas,
            hasCurrentLevel: !currentLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            sourceDocumentCount: sourceDocuments.count,
            minimumQuestionDifficulty: minimumQuestionDifficulty
        )
    }

    private var editImpact: GoalSetupEditImpact {
        GoalSetupEditImpact(
            baseline: editBaseline,
            title: title,
            deadline: deadline,
            currentLevel: currentLevel,
            focusAreas: focusAreas,
            sourceDocuments: sourceDocuments,
            preferredQuestionStyle: preferredQuestionStyle,
            minimumQuestionDifficulty: minimumQuestionDifficulty
        )
    }

    private var currentDraft: GoalSetupDraftSnapshot {
        GoalSetupDraftSnapshot(
            title: title,
            deadline: deadline,
            currentLevel: currentLevel,
            focusAreas: focusAreas,
            sourceDocuments: sourceDocuments,
            preferredQuestionStyle: preferredQuestionStyle,
            minimumQuestionDifficulty: minimumQuestionDifficulty
        )
    }

    private var hasUnsavedDraft: Bool {
        currentDraft.hasMeaningfulChanges(from: initialDraft)
    }

    private var dismissalPolicy: GoalSetupDismissalPolicy {
        GoalSetupDismissalPolicy(
            mode: mode,
            hasUnsavedDraft: hasUnsavedDraft,
            hasPendingImport: isImportingSources
        )
    }

    private var discardConfirmationMessage: String {
        if isImportingSources {
            return mode == .newGoal
                ? "This goal draft and any study materials still being read won't be saved."
                : "Your edits and any study materials still being read won't be saved."
        }
        return mode == .newGoal
            ? "This goal draft and its practice details won't be saved."
            : "Your edits to this goal won't be saved."
    }

    private var directionInput: GoalSetupDirectionInput {
        GoalSetupDirectionInput(goalTitle: title, focusAreas: focusAreas)
    }

    private var directionPreviewTaskID: GoalSetupDirectionPreviewTaskID {
        GoalSetupDirectionPreviewTaskID(
            input: directionInput,
            reduceMotion: reduceMotion
        )
    }

    private var goalSetupMotionPolicy: GoalSetupMotionPolicy {
        GoalSetupMotionPolicy(reduceMotion: reduceMotion)
    }

    private func commitDirectionPreview() {
        var updatedState = directionPreviewState
        let announcement = updatedState.commit(
            goalTitle: title,
            focusAreas: focusAreas
        )
        withAnimation(goalSetupMotionPolicy.revealAnimation) {
            directionPreviewState = updatedState
        }
        if let announcement {
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    private func isDirectionPreviewField(_ field: GoalSetupField?) -> Bool {
        field == .title || field == .focusAreas
    }

    private func previewDirection(
        _ input: GoalSetupDirectionInput,
        reduceMotion: Bool
    ) {
        var updatedState = directionPreviewState
        let wasVisible = updatedState.presentation != nil
        updatedState.preview(
            goalTitle: input.goalTitle,
            focusAreas: input.focusAreas
        )
        guard updatedState != directionPreviewState else { return }

        withAnimation(
            GoalSetupMotionPolicy(reduceMotion: reduceMotion).previewAnimation(
                wasVisible: wasVisible,
                isVisible: updatedState.presentation != nil
            )
        ) {
            directionPreviewState = updatedState
        }
    }

    private func requestGoalSetupDismissal() {
        clearFocusForTransition()
        if dismissalPolicy.requiresDiscardConfirmation {
            isDiscardConfirmationPresented = true
        } else {
            dismissGoalSetup()
        }
    }

    private func clearFocusForTransition() {
        if isDirectionPreviewField(focusedField) {
            suppressNextDirectionAnnouncement = true
        }
        focusedField = nil
    }

    private func announcePersistenceRecoveryIfNeeded(_ message: String?) {
        postPersistenceAnnouncement(
            GoalSetupPersistenceAnnouncementPolicy.message(
                for: .recoveryMessageChanged,
                recoveryMessage: message,
                previouslyAnnouncedMessage: announcedPersistenceRecoveryMessage
            )
        )
    }

    private func announcePersistenceFailure() {
        postPersistenceAnnouncement(
            GoalSetupPersistenceAnnouncementPolicy.message(
                for: .saveFailed,
                recoveryMessage: store.persistenceRecoveryMessage,
                previouslyAnnouncedMessage: announcedPersistenceRecoveryMessage
            )
        )
    }

    private func postPersistenceAnnouncement(_ message: String?) {
        guard let message else { return }
        announcedPersistenceRecoveryMessage = message
        AccessibilityNotification.Announcement(message).post()
    }

    private func dismissGoalSetup() {
        cancelPendingOperations()
        guard store.cancelResumedMembershipGoalCreation() else {
            announcePersistenceFailure()
            return
        }
        store.isCreatingGoalProfile = false
        store.isOnboardingPresented = false
        dismiss()
    }

    @ViewBuilder
    private var targetDatePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text("Target date")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .accessibilityHidden(true)

                DatePicker(
                    "Target date",
                    selection: $deadline,
                    in: Date()...,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .accessibilityLabel("Target date")
            }
        } else {
            DatePicker(
                "Target date",
                selection: $deadline,
                in: Date()...,
                displayedComponents: .date
            )
            .foregroundStyle(CheckpointTheme.text)
        }
    }

    @ViewBuilder
    private var startingLevelControl: some View {
        let label = "Starting level: \(Goal.difficultyLabel(for: minimumQuestionDifficulty))"
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)

                Stepper(value: $minimumQuestionDifficulty, in: 1...5) {
                    EmptyView()
                }
                .labelsHidden()
                .accessibilityLabel(label)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            Stepper(label, value: $minimumQuestionDifficulty, in: 1...5)
                .foregroundStyle(CheckpointTheme.text)
        }
    }

    private func requestGoalSave(
        authorization: GoalProfileMutationAuthorization = .none
    ) {
        guard !isCreating, currentGoalMutationRequest != nil else { return }
        isCreating = true

        saveTask?.cancel()
        saveTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, isCreating else { return }
            guard let request = currentGoalMutationRequest else {
                isCreating = false
                saveTask = nil
                return
            }
            performGoalSave(request, authorization: authorization)
            if !Task.isCancelled {
                saveTask = nil
            }
        }
    }

    private func cancelPendingOperations() {
        cancelSourceImport(announce: false)
        saveTask?.cancel()
        saveTask = nil
        isCreating = false
    }

    private func cancelSourceImport(announce: Bool) {
        let hadPendingImport = isImportingSources || sourceImportTask != nil
        sourceImportTask?.cancel()
        sourceImportTask = nil
        isImportingSources = false

        if announce, hadPendingImport {
            sourceImportMessage = "Stopped reading study materials."
        }
    }

    private func performGoalSave(
        _ request: GoalProfileMutationRequest,
        authorization: GoalProfileMutationAuthorization
    ) {
        let outcome = workflow.requestGoalProfileMutation(
            request,
            authorization: authorization
        )
        isCreating = false

        switch outcome {
        case .committed:
            finishGoalSave()
        case .alreadyCommitted:
            store.isCreatingGoalProfile = false
            store.isOnboardingPresented = false
            finishGoalSave()
        case let .confirmationRequired(confirmation):
            if case .confirmed = authorization {
                queuedProtectionConfirmation = confirmation
                promoteQueuedProtectionConfirmationWhenAvailable()
            } else {
                pendingProtectionConfirmation = confirmation
            }
        case .invalidTitle:
            queuedProtectionConfirmation = nil
            store.checkpointNotice = "Enter a goal before saving."
        case .membershipRequired, .profileLimitReached:
            queuedProtectionConfirmation = nil
            break
        case .targetNotFound, .staleRequest:
            queuedProtectionConfirmation = nil
            store.checkpointNotice = "This goal changed while the editor was open. Close it and try again."
        case .persistenceFailed:
            queuedProtectionConfirmation = nil
            announcePersistenceFailure()
        }
    }

    private func confirmProtectedGoalSave(
        _ confirmation: GoalProfileMutationConfirmation
    ) {
        requestGoalSave(authorization: .confirmed(confirmation))
    }

    private func finishGoalSave() {
        guard !store.isOnboardingPresented else { return }
        if mode == .firstGoal, store.goal != nil {
            onFirstGoalCreated()
        }
        dismiss()
    }

    private var protectionConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingProtectionConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingProtectionConfirmation = nil
                    promoteQueuedProtectionConfirmationWhenAvailable()
                }
            }
        )
    }

    private func promoteQueuedProtectionConfirmationWhenAvailable() {
        guard let queuedConfirmation = queuedProtectionConfirmation else { return }

        Task { @MainActor in
            await Task.yield()
            guard pendingProtectionConfirmation == nil,
                  queuedProtectionConfirmation == queuedConfirmation else {
                return
            }
            queuedProtectionConfirmation = nil
            pendingProtectionConfirmation = queuedConfirmation
        }
    }

    private var pendingProtectionConfirmationPresentation: GoalSetupProtectionConfirmationPresentation? {
        pendingProtectionConfirmation.map {
            GoalSetupProtectionConfirmationPresentation(confirmation: $0)
        }
    }

    private var currentGoalMutationRequest: GoalProfileMutationRequest? {
        let category: GoalCategory
        if mode == .editGoal {
            guard let editBaseline else { return nil }
            category = editBaseline.category
        } else {
            category = .custom
        }

        let draft = GoalProfileDraft(
            title: title,
            deadline: deadline,
            category: category,
            currentLevel: currentLevel,
            focusAreas: focusAreas,
            sourceDocuments: sourceDocuments,
            preferredQuestionStyle: preferredQuestionStyle,
            minimumQuestionDifficulty: minimumQuestionDifficulty
        )
        let operation: GoalProfileMutationRequest.Operation
        if mode == .editGoal {
            guard let editBaseline else { return nil }
            operation = .edit(expectedGoalID: editBaseline.goalID, draft: draft)
        } else {
            operation = .create(draft)
        }

        return GoalProfileMutationRequest(
            id: mutationRequestID,
            createdAt: mutationCreatedAt,
            operation: operation
        )
    }

    private var studyMaterialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Study materials")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)

            Text("Add text, Markdown, or a text-based PDF when practice should follow specific material. Checkpoint extracts readable text for the question service; the original file is not uploaded.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !sourceDocuments.isEmpty {
                VStack(spacing: 8) {
                    ForEach(sourceDocuments) { document in
                        sourceDocumentRow(document)
                    }
                }
            }

            if let sourceImportMessage {
                let importWasStopped = sourceImportMessage == "Stopped reading study materials."
                Label(
                    sourceImportMessage,
                    systemImage: importWasStopped
                        ? "stop.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(
                        importWasStopped ? CheckpointTheme.teal : CheckpointTheme.amber
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isImportingSources {
                SecondaryActionButton(
                    title: "Stop reading",
                    systemImage: "xmark.circle"
                ) {
                    cancelSourceImport(announce: true)
                }
            } else {
                SecondaryActionButton(
                    title: "Add study material",
                    systemImage: "doc.badge.plus"
                ) {
                    sourceImportMessage = nil
                    isSourceImporterPresented = true
                }
                .disabled(
                    sourceDocuments.count >= GoalContextLimits.maximumDocumentCount
                )
            }

            Text("Up to \(GoalContextLimits.maximumDocumentCount) files. Longer text may be trimmed to keep practice focused.")
                .font(.caption)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sourceDocumentRow(_ document: GoalSourceDocument) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 28, height: 28)
                .background(
                    CheckpointTheme.teal.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: CheckpointTheme.compactCornerRadius,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .lineLimit(1)

                Text("\(document.characterCount.formatted()) characters")
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
            }

            Spacer(minLength: 4)

            Button(role: .destructive) {
                sourceDocuments.removeAll { $0.id == document.id }
                sourceImportMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(CheckpointTheme.coral)
            .accessibilityLabel("Remove \(document.name)")
        }
        .padding(10)
        .background(
            CheckpointTheme.panelRaised,
            in: RoundedRectangle(
                cornerRadius: CheckpointTheme.compactCornerRadius,
                style: .continuous
            )
        )
    }

    private func handleSourceImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            sourceImportMessage = error.localizedDescription
        case .success(let urls):
            let remainingSlots = max(
                0,
                GoalContextLimits.maximumDocumentCount - sourceDocuments.count
            )
            guard remainingSlots > 0 else {
                sourceImportMessage = "Remove a study material before adding another."
                return
            }

            cancelSourceImport(announce: false)
            isImportingSources = true
            let selectedURLs = Array(urls.prefix(remainingSlots))
            sourceImportTask = Task { @MainActor in
                let importResult = await GoalSourceDocumentImporter.importDocuments(
                    from: selectedURLs
                )
                guard !Task.isCancelled else { return }
                sourceDocuments = GoalSourceDocument.normalizedDocuments(
                    sourceDocuments + importResult.documents
                )
                sourceImportMessage = importResult.failureMessages.isEmpty
                    ? nil
                    : importResult.failureMessages.joined(separator: "\n")
                isImportingSources = false
                sourceImportTask = nil
            }
        }
    }
}

struct GoalSetupDirectionCard: View {
    let presentation: GoalSetupDirectionPresentation
    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        presentation: GoalSetupDirectionPresentation,
        reduceMotionOverride: Bool? = nil
    ) {
        self.presentation = presentation
        self.reduceMotionOverride = reduceMotionOverride
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        SectionPanel {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    directionIcon
                    directionCopy
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    directionIcon
                    directionCopy
                }
            }

            if !presentation.topics.isEmpty {
                GoalSetupTopicList(topics: presentation.topics)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var directionIcon: some View {
        Image(systemName: presentation.systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 38, height: 38)
            .background(
                CheckpointTheme.teal.opacity(0.11),
                in: RoundedRectangle(
                    cornerRadius: CheckpointTheme.compactCornerRadius,
                    style: .continuous
                )
            )
            .contentTransition(.symbolEffect(.replace))
            .symbolEffectsRemoved(reduceMotion)
            .accessibilityHidden(true)
    }

    private var directionCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PRACTICE DIRECTION")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(CheckpointTheme.teal)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text(presentation.title)
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            Text(presentation.detail)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
    }
}

private struct GoalSetupTopicList: View {
    let topics: [String]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(topics, id: \.self) { topic in
                    FocusAreaTopicRow(text: topic)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 104),
                        spacing: 8,
                        alignment: .leading
                    )
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(topics, id: \.self) { topic in
                    FocusAreaChip(text: topic)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct GoalSetupHero: View {
    let presentation: GoalSetupHeroPresentation
    let reduceMotion: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CheckpointHeroSurface(
            glowColor: accent,
            glowOpacity: presentation.state == .working ? 0.14 : 0.10,
            glowDiameter: 132,
            contentPadding: dynamicTypeSize.isAccessibilitySize ? 14 : 16
        ) {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 11) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        compactIdentity
                        Spacer(minLength: 6)
                        statusBadge
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        compactIdentity
                        statusBadge
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.title)
                        .font(dynamicTypeSize.isAccessibilitySize ? .headline.bold() : .title2.bold())
                        .foregroundStyle(CheckpointTheme.heroText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(presentation.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.heroMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                guidanceRow
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .animation(motionAnimation, value: presentation.state)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var guidanceRow: some View {
        HStack(alignment: .top, spacing: 8) {
            guidanceIcon
            guidanceText
        }
    }

    private var guidanceIcon: some View {
        Image(systemName: presentation.guidanceSystemImage)
            .frame(width: 18)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffectsRemoved(reduceMotion)
            .accessibilityHidden(true)
    }

    private var guidanceText: some View {
        Text(presentation.guidance)
            .contentTransition(.opacity)
    }

    private var compactIdentity: some View {
        HStack(spacing: 9) {
            identityIcon

            VStack(alignment: .leading, spacing: 2) {
                Text("CHECKPOINT")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(CheckpointTheme.heroText)

                Text(compactEyebrow)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.3)
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .lineLimit(1)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .fixedSize(horizontal: true, vertical: true)
        }
        .animation(motionPolicy.animation, value: presentation.state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityContext)
    }

    private var compactEyebrow: String {
        presentation.eyebrow == "SETUP · STEP 2 OF 3"
            ? "STEP 2 OF 3"
            : presentation.eyebrow
    }

    private var identityIcon: some View {
        Image(systemName: presentation.systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 42, height: 42)
            .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, options: .nonRepeating, value: presentation.state)
            .symbolEffect(
                .pulse,
                options: .repeating,
                isActive: presentation.state == .working && !reduceMotion
            )
            .symbolEffectsRemoved(reduceMotion)
            .accessibilityHidden(true)
    }

    private var statusBadge: some View {
        StatusBadge(text: presentation.status, tint: accent)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .contentTransition(.opacity)
            .animation(motionAnimation, value: presentation.state)
            .accessibilityLabel("Status: \(presentation.status)")
    }

    private var accent: Color {
        switch presentation.state {
        case .awaitingGoal:
            CheckpointTheme.heroInfo
        case .ready:
            CheckpointTheme.heroSuccess
        case .upToDate:
            CheckpointTheme.heroSuccess
        case .unsavedChanges:
            CheckpointTheme.amber
        case .working:
            CheckpointTheme.heroInfo
        }
    }

    private var motionAnimation: Animation? {
        motionPolicy.animation
    }

    private var motionPolicy: GoalSetupMotionPolicy {
        GoalSetupMotionPolicy(reduceMotion: reduceMotion)
    }
}

private struct FocusAreaChip: View {
    var text: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
    }
}

private struct FocusAreaTopicRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(CheckpointTheme.teal)
                .accessibilityHidden(true)

            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.teal.opacity(0.10),
            in: RoundedRectangle(
                cornerRadius: CheckpointTheme.compactCornerRadius,
                style: .continuous
            )
        )
    }
}
