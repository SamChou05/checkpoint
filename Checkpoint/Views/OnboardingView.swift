import SwiftUI

struct OnboardingView: View {
    let store: CheckpointStore
    private let originalCurrentLevel: String?
    private let originalStartingFamiliarity: StartingFamiliarity

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date()
    @State private var focusAreas = ""
    @State private var startingFamiliarity = StartingFamiliarity.intermediate
    @State private var usesCalibrationStart = false
    @State private var showsQuestionLevelOverride = false
    @State private var minimumQuestionDifficulty = UnlockPolicy.default.minimumQuestionDifficulty
    @State private var isCreating = false

    init(store: CheckpointStore) {
        self.store = store

        if let goal = store.goal, !store.isCreatingGoalProfile {
            let familiarity = StartingFamiliarity.inferred(from: goal.currentLevel)
            let isCalibrationRequested = goal.currentLevel
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("Calibration requested") == .orderedSame
            originalCurrentLevel = goal.currentLevel
            originalStartingFamiliarity = familiarity
            _title = State(initialValue: goal.title)
            _deadline = State(initialValue: max(goal.deadline, Date()))
            _focusAreas = State(initialValue: goal.focusAreas)
            _startingFamiliarity = State(initialValue: familiarity)
            _usesCalibrationStart = State(initialValue: isCalibrationRequested)
            _minimumQuestionDifficulty = State(initialValue: goal.minimumQuestionDifficulty)
        } else {
            originalCurrentLevel = nil
            originalStartingFamiliarity = .intermediate
            _minimumQuestionDifficulty = State(
                initialValue: StartingFamiliarity.intermediate.recommendedMinimumDifficulty
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

                    SectionPanel("Goal") {
                        TextField("Goal", text: $title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                            .padding(12)
                            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                        DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .foregroundStyle(CheckpointTheme.text)
                    }

                    SectionPanel("Focus areas") {
                        TextField("Focus areas, separated by commas", text: $focusAreas, axis: .vertical)
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

                        HStack {
                            Text("Format")
                                .foregroundStyle(CheckpointTheme.muted)
                            Spacer()
                            StatusBadge(text: QuestionFormat.multipleChoice.rawValue, tint: CheckpointTheme.teal)
                        }
                    }

                    SectionPanel("Starting point") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How familiar are you with this goal today?")
                                .font(.subheadline)
                                .foregroundStyle(CheckpointTheme.muted)

                            Picker("Current familiarity", selection: $startingFamiliarity) {
                                ForEach(StartingFamiliarity.allCases) { familiarity in
                                    Text(familiarity.label).tag(familiarity)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(usesCalibrationStart)
                            .opacity(usesCalibrationStart ? 0.55 : 1)

                            Toggle("Not sure — calibrate me", isOn: $usesCalibrationStart)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)

                            Text(
                                usesCalibrationStart
                                    ? "Start in the middle, sample different skills, and let your answers tune future checkpoints."
                                    : startingFamiliarity.guidance
                            )
                                .font(.caption)
                                .foregroundStyle(CheckpointTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SectionPanel("Question level") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recommended start: \(Goal.difficultyLabel(for: minimumQuestionDifficulty)). Checkpoint adjusts as it learns from your answers.")
                                .font(.subheadline)
                                .foregroundStyle(CheckpointTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            DisclosureGroup("Advanced: adjust starting level", isExpanded: $showsQuestionLevelOverride) {
                                Stepper(
                                    "Minimum: \(Goal.difficultyLabel(for: minimumQuestionDifficulty))",
                                    value: $minimumQuestionDifficulty,
                                    in: 1...5
                                )
                                .foregroundStyle(CheckpointTheme.text)
                                .padding(.top, 8)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)
                            .disabled(usesCalibrationStart)
                            .opacity(usesCalibrationStart ? 0.55 : 1)
                        }
                    }

                    PrimaryActionButton(
                        title: primaryButtonTitle,
                        systemImage: "book.closed"
                    ) {
                        Task {
                            guard !isCreating else { return }
                            isCreating = true
                            if isNewProfile {
                                await store.createGoal(
                                    title: title,
                                    deadline: deadline,
                                    currentLevel: currentLevelForSave,
                                    focusAreas: focusAreas,
                                    preferredQuestionStyle: .multipleChoice,
                                    minimumQuestionDifficulty: minimumQuestionDifficulty,
                                    createsNewProfile: true,
                                    waitForQuestionGeneration: false
                                )
                            } else {
                                await store.updateGoal(
                                    title: title,
                                    deadline: deadline,
                                    currentLevel: currentLevelForSave,
                                    focusAreas: focusAreas,
                                    preferredQuestionStyle: .multipleChoice,
                                    minimumQuestionDifficulty: minimumQuestionDifficulty,
                                    waitForQuestionGeneration: false
                                )
                            }
                            isCreating = false
                            dismiss()
                        }
                    }
                    .disabled(isCreating || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if store.goal != nil {
                        Button("Done") {
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
        .onChange(of: startingFamiliarity) { previousValue, newValue in
            if minimumQuestionDifficulty == previousValue.recommendedMinimumDifficulty {
                minimumQuestionDifficulty = newValue.recommendedMinimumDifficulty
            }
        }
        .onChange(of: usesCalibrationStart) { _, usesCalibrationStart in
            if usesCalibrationStart {
                minimumQuestionDifficulty = StartingFamiliarity.intermediate.recommendedMinimumDifficulty
            } else {
                minimumQuestionDifficulty = startingFamiliarity.recommendedMinimumDifficulty
            }
        }
        .onDisappear {
            if !store.isOnboardingPresented {
                store.isCreatingGoalProfile = false
            }
        }
    }

    private var headerSubtitle: String {
        if isNewProfile {
            return "Name the goal, choose the practice areas, and set the level. Checkpoint keeps each goal's practice separate."
        }

        return "Refine this goal so future practice matches your current preparation."
    }

    private var primaryButtonTitle: String {
        if isCreating {
            return "Saving goal"
        }

        return isNewProfile ? "Create goal" : "Update goal"
    }

    private var isNewProfile: Bool {
        store.goal == nil || store.isCreatingGoalProfile
    }

    private var parsedFocusAreas: [String] {
        focusAreas
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var currentLevelForSave: String {
        if usesCalibrationStart {
            return "Calibration requested"
        }

        if !isNewProfile,
           startingFamiliarity == originalStartingFamiliarity,
           let originalCurrentLevel,
           originalCurrentLevel.caseInsensitiveCompare("Calibration requested") != .orderedSame,
           !originalCurrentLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return originalCurrentLevel
        }
        return startingFamiliarity.currentLevel
    }
}

enum StartingFamiliarity: String, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: Self { self }

    var label: String {
        switch self {
        case .beginner:
            return "New"
        case .intermediate:
            return "Familiar"
        case .advanced:
            return "Confident"
        }
    }

    var currentLevel: String {
        switch self {
        case .beginner:
            return "Beginner"
        case .intermediate:
            return "Intermediate"
        case .advanced:
            return "Advanced"
        }
    }

    var recommendedMinimumDifficulty: Int {
        switch self {
        case .beginner:
            return 1
        case .intermediate:
            return 2
        case .advanced:
            return 3
        }
    }

    var guidance: String {
        switch self {
        case .beginner:
            return "Start with the fundamentals and build from there."
        case .intermediate:
            return "Build on the basics and find the areas that need work."
        case .advanced:
            return "Start with deeper application and more challenging questions."
        }
    }

    static func inferred(from currentLevel: String) -> Self {
        let normalized = currentLevel.lowercased()

        if normalized.contains("advanced")
            || normalized.contains("expert")
            || normalized.contains("strong")
            || normalized.contains("very comfortable")
            || normalized.contains("confident") {
            return .advanced
        }

        if normalized.contains("intermediate")
            || normalized.contains("familiar")
            || normalized.contains("comfortable")
            || normalized.contains("decent") {
            return .intermediate
        }

        if normalized.contains("beginner")
            || normalized.contains("basic")
            || normalized.contains("new")
            || normalized.contains("starting")
            || normalized.contains("weak") {
            return .beginner
        }

        return .intermediate
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
