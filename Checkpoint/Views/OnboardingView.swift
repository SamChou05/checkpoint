import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    let store: CheckpointStore

    @Environment(\.dismiss) private var dismiss
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

    init(store: CheckpointStore) {
        self.store = store

        if let goal = store.goal, !store.isCreatingGoalProfile {
            _title = State(initialValue: goal.title)
            _deadline = State(initialValue: max(goal.deadline, Date()))
            _focusAreas = State(initialValue: goal.focusAreas)
            _currentLevel = State(initialValue: goal.currentLevel)
            _sourceDocuments = State(initialValue: goal.sourceDocuments)
            _minimumQuestionDifficulty = State(initialValue: goal.minimumQuestionDifficulty)
            _isCustomizationExpanded = State(
                initialValue: !goal.focusAreas.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !goal.currentLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !goal.sourceDocuments.isEmpty
                    || goal.minimumQuestionDifficulty != UnlockPolicy.default.minimumQuestionDifficulty
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isNewProfile ? "Create a goal" : "Update goal")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text(headerSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let persistenceMessage = store.persistenceRecoveryMessage {
                        Label(persistenceMessage, systemImage: "externaldrive.badge.exclamationmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                    }

                    SectionPanel("Goal") {
                        TextField("Goal", text: $title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                            .padding(12)
                            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                        DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .foregroundStyle(CheckpointTheme.text)

                        if shouldShowGoalInterpretation,
                           let interpretation = setupGuidance.interpretation {
                            Label("We'll prepare \(interpretation.lowercased()).", systemImage: "sparkles")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.teal)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SectionPanel {
                        DisclosureGroup(isExpanded: $isCustomizationExpanded) {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Topics to focus on")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(CheckpointTheme.text)

                                    Text("Optional. Add any must-cover skills. If you leave this blank—or give only a starting point—we’ll complete an editable 3–6 skill map from your goal.")
                                        .font(.footnote)
                                        .foregroundStyle(CheckpointTheme.muted)

                                    TextField("For example: contracts, vocabulary", text: $focusAreas, axis: .vertical)
                                        .lineLimit(3, reservesSpace: true)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(CheckpointTheme.text)
                                        .padding(12)
                                        .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

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
                                    .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
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
                                Text("Customize practice")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)

                                Text("Optional topics and starting level")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                            }
                        }
                        .tint(CheckpointTheme.teal)
                    }

                    PrimaryActionButton(
                        title: primaryButtonTitle,
                        systemImage: "book.closed",
                        isLoading: isCreating
                    ) {
                        Task {
                            guard !isCreating else { return }
                            isCreating = true
                            if isNewProfile {
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
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        isCreating
                            || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if store.goal != nil {
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
        .preferredColorScheme(.light)
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
    }

    private var headerSubtitle: String {
        if isNewProfile {
            return "Tell us what you're working toward. We'll build an editable skill map and prepare practice for each area."
        }

        return "Update what you're working toward."
    }

    private var primaryButtonTitle: String {
        return isNewProfile ? "Create goal" : "Save changes"
    }

    private var isNewProfile: Bool {
        store.goal == nil || store.isCreatingGoalProfile
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

    private var studyMaterialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Study materials")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)

            Text("Optional. Add text, Markdown, or a text-based PDF when questions should follow specific material. Extracted text is saved with this goal and sent to the AI question service.")
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

            Text("Up to \(GoalContextLimits.maximumDocumentCount) files. Long material is trimmed to a shared \(GoalContextLimits.maximumTotalDocumentCharacters.formatted())-character context budget.")
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
                .background(CheckpointTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

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
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(CheckpointTheme.coral)
            .accessibilityLabel("Remove \(document.name)")
        }
        .padding(10)
        .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
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
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
    }
}
