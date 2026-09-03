import Accessibility
import SwiftUI
import UniformTypeIdentifiers

private enum GoalSetupMode: Equatable {
    case firstGoal
    case newGoal
    case editGoal
}

private enum GoalSetupField: Hashable {
    case title
    case focusAreas
    case currentLevel
}

struct OnboardingView: View {
    let store: CheckpointStore
    private let mode: GoalSetupMode
    private let onFirstGoalCreated: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: GoalSetupField?
    @State private var title = ""
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date()
    @State private var focusAreas = ""
    @State private var currentLevel = ""
    @State private var sourceDocuments: [GoalSourceDocument] = []
    @State private var minimumQuestionDifficulty = UnlockPolicy.default.minimumQuestionDifficulty
    @State private var isCreating = false
    @State private var isCustomizationExpanded = false
    @State private var isSourceImporterPresented = false
    @State private var isImportingSources = false
    @State private var sourceImportMessage: String?

    init(
        store: CheckpointStore,
        onFirstGoalCreated: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onFirstGoalCreated = onFirstGoalCreated

        if store.goal == nil {
            mode = .firstGoal
        } else if store.isCreatingGoalProfile {
            mode = .newGoal
        } else {
            mode = .editGoal
        }

        if let goal = store.goal, mode == .editGoal {
            _title = State(initialValue: goal.title)
            _deadline = State(initialValue: max(goal.deadline, Date()))
            _focusAreas = State(initialValue: goal.focusAreas)
            _currentLevel = State(initialValue: goal.currentLevel)
            _sourceDocuments = State(initialValue: goal.sourceDocuments)
            _minimumQuestionDifficulty = State(initialValue: goal.minimumQuestionDifficulty)
            let hasCustomizations = !goal.focusAreas.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !goal.currentLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !goal.sourceDocuments.isEmpty
                || goal.minimumQuestionDifficulty != UnlockPolicy.default.minimumQuestionDifficulty
            _isCustomizationExpanded = State(initialValue: hasCustomizations)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    goalSetupHeader

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

                    SectionPanel {
                        Text("Learning goal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)

                        TextField(
                            "Learning goal",
                            text: $title,
                            prompt: Text("For example: Pass the California bar exam"),
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

                        DatePicker("Target date", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .foregroundStyle(CheckpointTheme.text)

                        if shouldShowGoalInterpretation,
                           let interpretation = setupGuidance.interpretation {
                            Label("We'll prepare \(interpretation.lowercased()).", systemImage: "sparkles")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.teal)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                    .animation(
                        CheckpointMotion.animation(CheckpointMotion.reveal, reduceMotion: reduceMotion),
                        value: setupGuidance.interpretation
                    )

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
                                        .lineLimit(3, reservesSpace: true)
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

                                    if !parsedFocusAreas.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(parsedFocusAreas, id: \.self) { focusArea in
                                                    FocusAreaChip(text: focusArea)
                                                }
                                            }
                                            .padding(.vertical, 2)
                                        }
                                    }
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
                                    .lineLimit(3, reservesSpace: true)
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

                                Stepper(
                                    "Starting level: \(Goal.difficultyLabel(for: minimumQuestionDifficulty))",
                                    value: $minimumQuestionDifficulty,
                                    in: 1...5
                                )
                                .foregroundStyle(CheckpointTheme.text)
                            }
                            .padding(.top, 12)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Topics, level, and study materials")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("Optional details for more tailored questions")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                            }
                        }
                        .tint(CheckpointTheme.teal)
                    }

                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .checkpointScreenBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveActionBar
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if mode != .firstGoal {
                        Button("Cancel") {
                            store.isCreatingGoalProfile = false
                            store.isOnboardingPresented = false
                            dismiss()
                        }
                        .foregroundStyle(CheckpointTheme.teal)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isSourceImporterPresented,
            allowedContentTypes: GoalSourceDocumentImporter.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleSourceImport(result)
        }
        .onDisappear {
            if !store.isOnboardingPresented {
                store.isCreatingGoalProfile = false
            }
        }
        .onChange(of: focusedField) { previousField, currentField in
            guard previousField == .title,
                  currentField != .title,
                  shouldShowGoalInterpretation,
                  let interpretation = setupGuidance.interpretation else {
                return
            }
            AccessibilityNotification.Announcement(
                "Checkpoint will prepare \(interpretation.lowercased())."
            ).post()
        }
        .onChange(of: sourceImportMessage) { _, message in
            guard let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var goalSetupHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            if mode == .firstGoal {
                CheckpointSetupMark(stage: "Your goal", step: 2, isWorking: isCreating)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(headerTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var saveActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            PrimaryActionButton(
                title: primaryButtonTitle,
                systemImage: primaryButtonSystemImage,
                isLoading: isCreating
            ) {
                focusedField = nil
                saveGoal()
            }
            .disabled(isCreating || isTitleEmpty)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var headerTitle: String {
        switch mode {
        case .firstGoal:
            "What are you working toward?"
        case .newGoal:
            "Add another goal."
        case .editGoal:
            "Refine your goal."
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .firstGoal:
            "Checkpoint will turn your goal into short practice before selected apps open."
        case .newGoal:
            "Keep this priority separate with its own topics, practice, and progress."
        case .editGoal:
            "Update the direction and level of your future checkpoints."
        }
    }

    private var primaryButtonTitle: String {
        if isCreating {
            return mode == .editGoal ? "Saving changes" : "Preparing your goal"
        }

        switch mode {
        case .firstGoal:
            return "Continue to app selection"
        case .newGoal:
            return "Create goal"
        case .editGoal:
            return "Save changes"
        }
    }

    private var primaryButtonSystemImage: String {
        switch mode {
        case .firstGoal:
            "arrow.right"
        case .newGoal:
            "plus"
        case .editGoal:
            "checkmark"
        }
    }

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var setupGuidance: GoalSetupGuidance {
        GoalSetupGuidance(title: title, focusAreas: focusAreas)
    }

    private var shouldShowGoalInterpretation: Bool {
        parsedFocusAreas.isEmpty && setupGuidance.interpretation != nil
    }

    private var parsedFocusAreas: [String] {
        focusAreas
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func saveGoal() {
        Task {
            guard !isCreating else { return }
            isCreating = true

            if mode != .editGoal {
                await store.createGoal(
                    title: title,
                    deadline: deadline,
                    currentLevel: currentLevel,
                    focusAreas: focusAreas,
                    sourceDocuments: sourceDocuments,
                    preferredQuestionStyle: .multipleChoice,
                    minimumQuestionDifficulty: minimumQuestionDifficulty,
                    createsNewProfile: true,
                    waitForQuestionGeneration: false
                )
            } else {
                await store.updateActiveGoal(
                    title: title,
                    deadline: deadline,
                    currentLevel: currentLevel,
                    focusAreas: focusAreas,
                    sourceDocuments: sourceDocuments,
                    preferredQuestionStyle: .multipleChoice,
                    minimumQuestionDifficulty: minimumQuestionDifficulty,
                    waitForQuestionGeneration: false
                )
            }

            isCreating = false
            if !store.isOnboardingPresented {
                if mode == .firstGoal, store.goal != nil {
                    onFirstGoalCreated()
                }
                dismiss()
            }
        }
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
                Label(sourceImportMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecondaryActionButton(
                title: isImportingSources ? "Reading files" : "Add study material",
                systemImage: isImportingSources ? "hourglass" : "doc.badge.plus"
            ) {
                sourceImportMessage = nil
                isSourceImporterPresented = true
            }
            .disabled(
                isImportingSources
                    || sourceDocuments.count >= GoalContextLimits.maximumDocumentCount
            )

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

            isImportingSources = true
            Task {
                let importResult = await GoalSourceDocumentImporter.importDocuments(
                    from: Array(urls.prefix(remainingSlots))
                )
                sourceDocuments = GoalSourceDocument.normalizedDocuments(
                    sourceDocuments + importResult.documents
                )
                sourceImportMessage = importResult.failureMessages.isEmpty
                    ? nil
                    : importResult.failureMessages.joined(separator: "\n")
                isImportingSources = false
            }
        }
    }
}

private struct FocusAreaChip: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
    }
}
