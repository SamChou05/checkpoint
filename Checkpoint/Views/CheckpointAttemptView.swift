import SwiftUI

struct CheckpointAttemptView: View {
    let store: CheckpointStore
    let workflow: CheckpointWorkflowCoordinator
    let session: CheckpointSession

    @Environment(\.dismiss) private var dismiss
    @State private var currentQuestionIndex = 0
    @State private var correctAnswerCount = 0
    @State private var answer = ""
    @State private var result: AnswerResult = .correct
    @State private var checkedAnswer: CheckedCheckpointAnswer?
    @State private var protectionActionErrorMessage: String?
    @AccessibilityFocusState private var accessibilityFocus: AttemptAccessibilityFocus?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sessionSubtitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Question \(currentQuestionIndex + 1) of \(session.questions.count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(CheckpointTheme.text)

                                Spacer()

                                Text("\(correctAnswerCount)/\(session.unlockThreshold) correct")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.muted)
                            }

                            ProgressView(
                                value: Double(completedQuestionCount),
                                total: Double(max(session.questions.count, 1))
                            )
                            .tint(CheckpointTheme.teal)
                            .accessibilityLabel("Checkpoint progress")
                            .accessibilityValue(
                                "\(completedQuestionCount) of \(session.questions.count) questions completed; \(correctAnswerCount) of \(session.unlockThreshold) correct"
                            )
                        }
                        .padding(.top, 6)
                    }

                    SectionPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                StatusBadge(text: question.topic, tint: CheckpointTheme.teal)
                            }

                            Text(question.prompt)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityFocused($accessibilityFocus, equals: .question)

                            if question.format == .multipleChoice, !question.choices.isEmpty {
                                VStack(spacing: 10) {
                                    ForEach(question.choices, id: \.self) { choice in
                                        ChoiceButton(
                                            title: choice,
                                            isSelected: answer == choice,
                                            isLocked: checkedAnswer != nil
                                        ) {
                                            guard checkedAnswer == nil else { return }
                                            answer = choice
                                        }
                                    }
                                }
                            } else {
                                TextField("Type your answer", text: $answer, axis: .vertical)
                                    .lineLimit(5, reservesSpace: true)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(CheckpointTheme.text)
                                    .padding(12)
                                    .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                                    .disabled(checkedAnswer != nil)
                            }
                        }
                    }

                    resultPanel

                    PrimaryActionButton(
                        title: submitButtonTitle,
                        systemImage: submitButtonIcon
                    ) {
                        handlePrimaryAction()
                    }
                    .disabled(checkedAnswer == nil && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .navigationTitle("Checkpoint")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        closeCheckpoint()
                    }
                    .foregroundStyle(CheckpointTheme.muted)
                }
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(session.purpose != .preview)
        .onDisappear {
            workflow.abandon(session)
        }
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

        correctAnswerCount = updatedCorrectCount
        checkedAnswer = CheckedCheckpointAnswer(
            result: result,
            shouldFinish: shouldFinish,
            shouldPass: shouldPass
        )
        accessibilityFocus = .feedback
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
        currentQuestionIndex += 1
        answer = ""
        result = .correct
        checkedAnswer = nil
        accessibilityFocus = .question
    }

    private func closeCheckpoint() {
        dismiss()
    }

    private func resultTint(for result: AnswerResult) -> Color {
        result == .correct ? CheckpointTheme.teal : CheckpointTheme.coral
    }

    private var failedSessionFeedbackText: String {
        switch session.purpose {
        case .preview:
            return "We'll revisit what you missed."
        case .temporaryUnlock, .stopBlocking:
            if store.hasReadyCheckpointSet {
                return "Protection stays on. Try again in 5 minutes, and we'll revisit what you missed."
            }
            return "Protection was turned off because another full checkpoint isn't ready. Prepare questions before starting it again."
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let checkedAnswer {
            SectionPanel("Feedback") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(checkedAnswer.result == .correct ? "Correct" : "Not quite")
                        .font(.headline)
                        .foregroundStyle(resultTint(for: checkedAnswer.result))
                        .accessibilityFocused($accessibilityFocus, equals: .feedback)

                    VStack(alignment: .leading, spacing: 8) {
                        if checkedAnswer.result != .correct {
                            Text("Correct answer")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(CheckpointTheme.muted)

                            Text(question.expectedAnswer)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(question.explanation)
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

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
                }
            }
        } else if !usesAutomaticEvaluation {
            SectionPanel("How did it go?") {
                Picker("How did it go?", selection: $result) {
                    ForEach(AnswerResult.allCases) { result in
                        Text(selfAssessmentLabel(for: result)).tag(result)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
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

private struct ChoiceButton: View {
    var title: String
    var isSelected: Bool
    var isLocked: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? CheckpointTheme.teal : CheckpointTheme.muted)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? CheckpointTheme.teal.opacity(0.16) : CheckpointTheme.panelRaised,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? CheckpointTheme.teal.opacity(0.75) : CheckpointTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .opacity(isLocked && !isSelected ? 0.62 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
