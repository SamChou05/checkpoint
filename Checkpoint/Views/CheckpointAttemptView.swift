import SwiftUI

enum CheckpointAnswerResultTone: Equatable {
    case success
    case warning
    case failure
}

struct CheckpointAnswerResultPresentation: Equatable {
    let label: String
    let systemImage: String
    let tone: CheckpointAnswerResultTone

    init(result: AnswerResult) {
        switch result {
        case .correct:
            label = "Correct"
            systemImage = "checkmark.circle.fill"
            tone = .success
        case .partial:
            label = "Almost"
            systemImage = "circle.lefthalf.filled"
            tone = .warning
        case .incorrect:
            label = "Not quite"
            systemImage = "xmark.circle.fill"
            tone = .failure
        case .unclear:
            label = "Needs review"
            systemImage = "questionmark.circle.fill"
            tone = .warning
        }
    }
}

struct CheckpointAnswerReviewPresentation: Equatable {
    let answerLabel: String
    let answerText: String

    init?(question: CheckpointQuestion, result: AnswerResult) {
        guard let answerText = AnswerGrader.correctAnswerText(
            for: question,
            after: result
        ) else {
            return nil
        }

        self.answerText = answerText
        answerLabel = Self.answerLabel(for: question.format)
    }

    static func answerLabel(for format: QuestionFormat) -> String {
        switch format {
        case .multipleChoice:
            "Correct answer"
        case .shortAnswer, .codeTrace:
            "Expected answer"
        case .reflection:
            "Example response"
        }
    }
}

struct CheckpointExitConfirmation: Equatable {
    let title = "Leave checkpoint?"
    let message: String
    let cancelButtonTitle = "Keep answering"
    let confirmButtonTitle = "Leave checkpoint"

    init(cooldownDurationText: String = CheckpointRetryPolicy.cooldownDurationText) {
        message = "Your completed answers stay saved. Leaving starts a \(cooldownDurationText) retry wait. Any active break continues; otherwise, protection stays on only if another full checkpoint is ready."
    }

    static func shouldPresent(
        for purpose: CheckpointSessionPurpose,
        hasActiveRun: Bool
    ) -> Bool {
        purpose != .preview && hasActiveRun
    }
}

enum CheckpointExitChoice: Equatable {
    case keepAnswering
    case leaveCheckpoint

    var shouldDismiss: Bool {
        self == .leaveCheckpoint
    }
}

enum CheckpointFeedbackRevealBehavior: Equatable {
    case focusOnly
    case focusAndScroll(animated: Bool)

    static func resolve(
        reduceMotion: Bool,
        assistiveNavigationEnabled: Bool
    ) -> Self {
        assistiveNavigationEnabled
            ? .focusOnly
            : .focusAndScroll(animated: !reduceMotion)
    }
}

struct CheckpointAttemptView: View {
    let store: CheckpointStore
    let workflow: CheckpointWorkflowCoordinator
    let session: CheckpointSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @State private var currentQuestionIndex = 0
    @State private var correctAnswerCount = 0
    @State private var answer = ""
    @State private var result: AnswerResult = .correct
    @State private var checkedAnswer: CheckedCheckpointAnswer?
    @State private var protectionActionErrorMessage: String?
    @State private var feedbackSequence = 0
    @State private var resolutionFeedback: CheckpointResolutionFeedback?
    @State private var isExitConfirmationPresented = false
    @State private var hasFinalizedCheckpoint = false
    @State private var questionQualityFeedbackContext: QuestionQualityFeedbackContext?
    @FocusState private var isAnswerFieldFocused: Bool
    @AccessibilityFocusState private var accessibilityFocus: AttemptAccessibilityFocus?

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        progressHeader
                            .id(AttemptScrollAnchor.question)

                        questionPanel
                            .id(question.id)
                            .transition(questionTransition)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: currentQuestionIndex) { _, _ in
                    scrollToQuestion(using: scrollProxy)
                }
                .onChange(of: feedbackSequence) { _, sequence in
                    revealFeedback(sequence: sequence, using: scrollProxy)
                }
            }
            .checkpointScreenBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                primaryActionBar
            }
            .navigationTitle("Checkpoint")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        closeCheckpoint()
                    }
                    .foregroundStyle(CheckpointTheme.muted)
                    .accessibilityHint(closeAccessibilityHint)
                }
            }
        }
        .interactiveDismissDisabled(session.purpose != .preview)
        .alert(
            exitConfirmation.title,
            isPresented: $isExitConfirmationPresented
        ) {
            Button(exitConfirmation.cancelButtonTitle, role: .cancel) {
                handleExitChoice(.keepAnswering)
            }
            Button(exitConfirmation.confirmButtonTitle, role: .destructive) {
                handleExitChoice(.leaveCheckpoint)
            }
        } message: {
            Text(exitConfirmation.message)
        }
        .sheet(item: $questionQualityFeedbackContext) { context in
            QuestionQualityFeedbackView(context: context) { reason in
                store.removeQuestionFromFuturePractice(
                    questionID: context.questionID,
                    goalID: context.goalID,
                    reason: reason
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            guard !hasFinalizedCheckpoint,
                  store.activeCheckpointRun?.sessionID == session.id else { return }
            hasFinalizedCheckpoint = workflow.abandon(session)
        }
        .sensoryFeedback(.success, trigger: resolutionFeedback) { _, newValue in
            newValue == .passed
        }
        .sensoryFeedback(.warning, trigger: resolutionFeedback) { _, newValue in
            newValue == .failed
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Question \(currentQuestionIndex + 1) of \(session.questions.count)")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .contentTransition(.numericText())

                Spacer(minLength: 8)

                Text(progressStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(progressStatusTint)
                    .multilineTextAlignment(.trailing)
            }

            ProgressView(
                value: Double(completedQuestionCount),
                total: Double(max(session.questions.count, 1))
            )
            .tint(CheckpointTheme.teal)
            .animation(
                CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                value: completedQuestionCount
            )
            .accessibilityLabel("Checkpoint progress")
            .accessibilityValue(
                "\(completedQuestionCount) of \(session.questions.count) questions completed; \(correctAnswerCount) of \(session.unlockThreshold) correct"
            )

            Text(sessionSubtitle)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var questionPanel: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 16) {
                StatusBadge(text: question.topic, tint: CheckpointTheme.teal)

                Text(question.prompt)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .question)

                answerControls

                inlineFeedback
            }
        }
    }

    @ViewBuilder
    private var answerControls: some View {
        if question.format == .multipleChoice, !question.choices.isEmpty {
            VStack(spacing: 10) {
                ForEach(question.choices, id: \.self) { choice in
                    ChoiceButton(
                        title: choice,
                        state: choiceState(for: choice)
                    ) {
                        guard checkedAnswer == nil else { return }
                        answer = choice
                    }
                }
            }
        } else {
            TextField("Type your answer", text: $answer, axis: .vertical)
                .focused($isAnswerFieldFocused)
                .lineLimit(5, reservesSpace: true)
                .textFieldStyle(.plain)
                .foregroundStyle(CheckpointTheme.text)
                .padding(14)
                .background(
                    CheckpointTheme.panelRaised.opacity(0.78),
                    in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius)
                        .stroke(CheckpointTheme.controlStroke, lineWidth: 1)
                }
                .disabled(checkedAnswer != nil)

            if !usesAutomaticEvaluation, checkedAnswer == nil {
                reflectionAssessment
            }
        }
    }

    private var primaryActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            PrimaryActionButton(
                title: submitButtonTitle,
                systemImage: submitButtonIcon
            ) {
                handlePrimaryAction()
            }
            .disabled(checkedAnswer == nil && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var question: CheckpointQuestion {
        session.questions[currentQuestionIndex]
    }

    private var isFinalQuestion: Bool {
        currentQuestionIndex >= session.questions.count - 1
    }

    private var completedQuestionCount: Int {
        currentQuestionIndex + (checkedAnswer == nil ? 0 : 1)
    }

    private var remainingCorrectAnswers: Int {
        max(0, session.unlockThreshold - correctAnswerCount)
    }

    private var progressStatusText: String {
        if let checkedAnswer, checkedAnswer.shouldFinish {
            return checkedAnswer.shouldPass ? "Ready to clear" : "Standard not met"
        }
        if remainingCorrectAnswers == 0 {
            return "Standard met"
        }
        return remainingCorrectAnswers == 1
            ? "1 more to clear"
            : "\(remainingCorrectAnswers) more to clear"
    }

    private var progressStatusTint: Color {
        guard let checkedAnswer, checkedAnswer.shouldFinish else {
            return remainingCorrectAnswers == 0 ? CheckpointTheme.teal : CheckpointTheme.muted
        }
        return checkedAnswer.shouldPass ? CheckpointTheme.teal : CheckpointTheme.coral
    }

    private var usesAutomaticEvaluation: Bool {
        question.format != .reflection
    }

    private var evaluation: AnswerEvaluation {
        AnswerGrader.evaluate(answer: answer, question: question)
    }

    private var submissionResult: AnswerResult {
        return usesAutomaticEvaluation ? evaluation.result : result
    }

    private var sessionSubtitle: String {
        switch session.purpose {
        case .temporaryUnlock:
            return "Get \(session.unlockThreshold) of \(session.questions.count) correct to start a \(store.unlockPolicy.unlockMinutes)-minute break."
        case .preview:
            return "Practice preview — app protection won't change."
        case .stopBlocking:
            return "Get \(session.unlockThreshold) of \(session.questions.count) correct to turn app protection off."
        }
    }

    private var submitButtonTitle: String {
        guard let checkedAnswer else {
            return "Check answer"
        }

        if checkedAnswer.shouldFinish {
            return checkedAnswer.shouldPass ? passingSubmitButtonTitle : "Done"
        }

        return "Next question"
    }

    private var passingSubmitButtonTitle: String {
        switch session.purpose {
        case .temporaryUnlock:
            return "Begin \(store.unlockPolicy.unlockMinutes)-minute break"
        case .preview:
            return "Finish"
        case .stopBlocking:
            return "Turn off protection"
        }
    }

    private var submitButtonIcon: String {
        guard let checkedAnswer else {
            return "checkmark.seal"
        }

        if checkedAnswer.shouldFinish {
            return checkedAnswer.shouldPass ? passingSubmitButtonIcon : "lock"
        }

        return "arrow.right"
    }

    private var passingSubmitButtonIcon: String {
        switch session.purpose {
        case .temporaryUnlock:
            return "lock.open"
        case .preview:
            return "checkmark.seal"
        case .stopBlocking:
            return "hand.raised"
        }
    }

    private func handlePrimaryAction() {
        if checkedAnswer == nil {
            checkCurrentAnswer()
        } else {
            continueAfterCheckedAnswer()
        }
    }

    private func checkCurrentAnswer() {
        let result = submissionResult
        let updatedCorrectCount = correctAnswerCount + (result == .correct ? 1 : 0)

        let answeredQuestionCount = currentQuestionIndex + 1
        let shouldFinish = isFinalQuestion || !session.canStillMeetUnlockThreshold(
            correctAnswerCount: updatedCorrectCount,
            answeredQuestionCount: answeredQuestionCount
        )
        let shouldPass = shouldFinish && session.hasMetUnlockThreshold(correctAnswerCount: updatedCorrectCount)

        if session.purpose != .preview {
            store.submitAnswer(
                question: question,
                answer: answer,
                result: result,
                grantsUnlock: false
            )

            if shouldFinish && !shouldPass {
                workflow.resolveFailed(session)
            }
        }

        isAnswerFieldFocused = false
        withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
            correctAnswerCount = updatedCorrectCount
            checkedAnswer = CheckedCheckpointAnswer(
                result: result,
                shouldFinish: shouldFinish,
                shouldPass: shouldPass
            )
            feedbackSequence += 1
        }
        if shouldFinish {
            resolutionFeedback = shouldPass ? .passed : .failed
        }
    }

    private func continueAfterCheckedAnswer() {
        guard let checkedAnswer else { return }

        guard !checkedAnswer.shouldFinish else {
            if checkedAnswer.shouldPass {
                if let errorMessage = workflow.finishPassed(session) {
                    protectionActionErrorMessage = errorMessage
                    return
                }
                protectionActionErrorMessage = nil
            }
            dismiss()
            return
        }

        advanceToNextQuestion()
    }

    private func advanceToNextQuestion() {
        withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
            currentQuestionIndex += 1
            answer = ""
            result = .correct
            checkedAnswer = nil
        }
        accessibilityFocus = .question
    }

    private func scrollToQuestion(using proxy: ScrollViewProxy) {
        withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
            proxy.scrollTo(AttemptScrollAnchor.question, anchor: .top)
        }
    }

    private func revealFeedback(
        sequence: Int,
        using proxy: ScrollViewProxy
    ) {
        Task { @MainActor in
            await Task.yield()

            guard sequence == feedbackSequence, checkedAnswer != nil else { return }

            accessibilityFocus = .feedback

            let behavior = CheckpointFeedbackRevealBehavior.resolve(
                reduceMotion: reduceMotion,
                assistiveNavigationEnabled: voiceOverEnabled || switchControlEnabled
            )
            guard case let .focusAndScroll(animated) = behavior else { return }

            withAnimation(animated ? CheckpointMotion.change : nil) {
                proxy.scrollTo(AttemptScrollAnchor.feedback, anchor: .top)
            }
        }
    }

    private func closeCheckpoint() {
        let hasActiveRun = store.activeCheckpointRun?.sessionID == session.id
        guard !CheckpointExitConfirmation.shouldPresent(
            for: session.purpose,
            hasActiveRun: hasActiveRun
        ) else {
            isExitConfirmationPresented = true
            return
        }

        dismiss()
    }

    private func handleExitChoice(_ choice: CheckpointExitChoice) {
        guard choice.shouldDismiss else { return }
        hasFinalizedCheckpoint = workflow.abandon(session)
        dismiss()
    }

    private var exitConfirmation: CheckpointExitConfirmation {
        CheckpointExitConfirmation()
    }

    private var closeAccessibilityHint: String {
        guard CheckpointExitConfirmation.shouldPresent(
            for: session.purpose,
            hasActiveRun: store.activeCheckpointRun?.sessionID == session.id
        ) else {
            return "Closes this checkpoint."
        }

        return "Shows a confirmation with the effect on protection and the \(CheckpointRetryPolicy.cooldownDurationText) retry wait."
    }

    private func resultTint(for tone: CheckpointAnswerResultTone) -> Color {
        switch tone {
        case .success:
            return CheckpointTheme.teal
        case .warning:
            return CheckpointTheme.amber
        case .failure:
            return CheckpointTheme.coral
        }
    }

    private var failedSessionFeedbackText: String {
        switch session.purpose {
        case .preview:
            return "We'll revisit what you missed."
        case .temporaryUnlock, .stopBlocking:
            if store.hasReadyCheckpointSet {
                return "Protection stays on. Try again in \(CheckpointRetryPolicy.cooldownDurationText), and we'll revisit what you missed."
            }
            return "Protection was turned off because another full checkpoint isn't ready. Prepare questions before starting it again."
        }
    }

    @ViewBuilder
    private var inlineFeedback: some View {
        if let checkedAnswer {
            let feedbackPresentation = CheckpointAnswerResultPresentation(
                result: checkedAnswer.result
            )

            Divider()
                .overlay(CheckpointTheme.hairline)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: feedbackPresentation.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(resultTint(for: feedbackPresentation.tone))
                        .symbolEffect(.bounce, options: .nonRepeating, value: feedbackSequence)
                        .symbolEffectsRemoved(reduceMotion)
                        .accessibilityHidden(true)

                    Text(feedbackPresentation.label)
                        .font(.headline)
                        .foregroundStyle(resultTint(for: feedbackPresentation.tone))
                        .accessibilityFocused($accessibilityFocus, equals: .feedback)
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if let answerReview = CheckpointAnswerReviewPresentation(
                        question: question,
                        result: checkedAnswer.result
                    ) {
                        Text(answerReview.answerLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CheckpointTheme.muted)

                        Text(answerReview.answerText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()
                            .overlay(CheckpointTheme.hairline)
                    }

                    Text("Explanation")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckpointTheme.muted)

                    Text(question.explanation)
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(13)
                .background(
                    CheckpointTheme.panelRaised.opacity(0.68),
                    in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius)
                )

                if checkedAnswer.result != .correct && checkedAnswer.shouldFinish && !checkedAnswer.shouldPass {
                    Text(failedSessionFeedbackText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let protectionActionErrorMessage {
                    Text(protectionActionErrorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if QuestionQualityFeedbackPresentation.supportsRemoval(in: session.purpose) {
                    QuestionRemovalControl(report: currentQuestionReport) {
                        presentQuestionQualityFeedback()
                    }
                }
            }
            .id(AttemptScrollAnchor.feedback)
            .transition(feedbackTransition)
        }
    }

    private var reflectionAssessment: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How did it go?")
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.muted)

            Picker("How did it go?", selection: $result) {
                ForEach(AnswerResult.allCases) { result in
                    Text(selfAssessmentLabel(for: result)).tag(result)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var questionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            )
    }

    private var feedbackTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private func choiceState(for choice: String) -> CheckpointChoiceState {
        guard checkedAnswer != nil else {
            return answer == choice ? .selected : .idle
        }

        if AnswerGrader.evaluate(answer: choice, question: question).result == .correct {
            return .correct
        }
        if answer == choice {
            return .incorrect
        }
        return .locked
    }

    private func selfAssessmentLabel(for result: AnswerResult) -> String {
        switch result {
        case .correct:
            return "Got it"
        case .partial:
            return "Almost"
        case .incorrect:
            return "Need practice"
        case .unclear:
            return "Not sure"
        }
    }

    private var currentQuestionReport: QuestionQualityReport? {
        store.questionReport(for: question.id, goalID: question.goalID)
    }

    private func presentQuestionQualityFeedback() {
        questionQualityFeedbackContext = QuestionQualityFeedbackContext(
            questionID: question.id,
            goalID: question.goalID,
            prompt: question.prompt,
            existingReason: currentQuestionReport?.reason
        )
    }
}

private struct CheckedCheckpointAnswer {
    let result: AnswerResult
    let shouldFinish: Bool
    let shouldPass: Bool
}

private enum AttemptAccessibilityFocus: Hashable {
    case question
    case feedback
}

private enum AttemptScrollAnchor: Hashable {
    case question
    case feedback
}

private enum CheckpointResolutionFeedback: Hashable {
    case passed
    case failed
}

private enum CheckpointChoiceState: Hashable {
    case idle
    case selected
    case correct
    case incorrect
    case locked

    var isLocked: Bool {
        switch self {
        case .correct, .incorrect, .locked:
            return true
        case .idle, .selected:
            return false
        }
    }
}

private struct ChoiceButton: View {
    var title: String
    var state: CheckpointChoiceState
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 22)
                    .contentTransition(.symbolEffect(.replace))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: state == .idle || state == .locked ? 1 : 1.4)
            )
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .disabled(state.isLocked)
        .opacity(state == .locked ? 0.58 : 1)
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: state
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }

    private var systemImage: String {
        switch state {
        case .selected, .correct:
            return "checkmark.circle.fill"
        case .incorrect:
            return "xmark.circle.fill"
        case .idle, .locked:
            return "circle"
        }
    }

    private var iconTint: Color {
        switch state {
        case .selected, .correct:
            return CheckpointTheme.teal
        case .incorrect:
            return CheckpointTheme.coral
        case .idle, .locked:
            return CheckpointTheme.muted
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .selected, .correct:
            return CheckpointTheme.teal.opacity(state == .correct ? 0.18 : 0.12)
        case .incorrect:
            return CheckpointTheme.coral.opacity(0.12)
        case .idle, .locked:
            return CheckpointTheme.panelRaised.opacity(0.72)
        }
    }

    private var borderColor: Color {
        switch state {
        case .selected, .correct:
            return CheckpointTheme.teal.opacity(0.72)
        case .incorrect:
            return CheckpointTheme.coral.opacity(0.72)
        case .idle, .locked:
            return CheckpointTheme.controlStroke
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .idle:
            return "Not selected"
        case .selected:
            return "Selected"
        case .correct:
            return "Correct answer"
        case .incorrect:
            return "Selected, incorrect"
        case .locked:
            return "Not selected"
        }
    }
}
