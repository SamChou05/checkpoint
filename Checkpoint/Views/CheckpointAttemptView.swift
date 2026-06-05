import SwiftUI

struct CheckpointAttemptView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let session: CheckpointSession

    @Environment(\.dismiss) private var dismiss
    @State private var currentQuestionIndex = 0
    @State private var correctAnswerCount = 0
    @State private var missedQuestionIDs: Set<CheckpointQuestion.ID> = []
    @State private var answer = ""
    @State private var result: AnswerResult = .correct
    @State private var checkedAnswer: CheckedCheckpointAnswer?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusBadge(text: sessionBadgeText, tint: CheckpointTheme.amber)

                        Text(sessionTitle)
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text(sessionSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)

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
                                value: Double(currentQuestionIndex),
                                total: Double(max(session.questions.count, 1))
                            )
                            .tint(CheckpointTheme.teal)
                        }
                        .padding(.top, 6)
                    }

                    SectionPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                StatusBadge(text: question.topic, tint: CheckpointTheme.teal)
                                Spacer()
                                Text(question.format.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.muted)
                            }

                            Text(question.prompt)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.text)
                                .fixedSize(horizontal: false, vertical: true)

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

                    SectionPanel("Result") {
                        if let checkedAnswer {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(checkedAnswer.result == .correct ? "Correct" : "Not quite")
                                        .font(.headline)
                                        .foregroundStyle(CheckpointTheme.text)
                                    Spacer()
                                    StatusBadge(text: checkedAnswer.result.rawValue, tint: resultTint(for: checkedAnswer.result))
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Answer")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(CheckpointTheme.muted)

                                    Text(question.expectedAnswer)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(CheckpointTheme.text)
                                        .fixedSize(horizontal: false, vertical: true)

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
                            }
                        } else if usesAutomaticEvaluation {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Checkpoint result")
                                        .foregroundStyle(CheckpointTheme.muted)
                                    Spacer()
                                    StatusBadge(text: automaticGateStatus, tint: automaticGateTint)
                                }

                                Text("Choose an answer to see feedback.")
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Picker("How did you do?", selection: $result) {
                                ForEach(AnswerResult.allCases) { result in
                                    Text(result.rawValue).tag(result)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

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
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.muted)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var question: CheckpointQuestion {
        session.questions[currentQuestionIndex]
    }

    private var isFinalQuestion: Bool {
        currentQuestionIndex >= session.questions.count - 1
    }

    private var usesAutomaticEvaluation: Bool {
        question.format != .reflection
    }

    private var evaluation: AnswerEvaluation {
        AnswerGrader.evaluate(answer: answer, question: question)
    }

    private var automaticGateStatus: String {
        return answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Choose" : "Ready"
    }

    private var automaticGateTint: Color {
        CheckpointTheme.teal
    }

    private var submissionResult: AnswerResult {
        return usesAutomaticEvaluation ? evaluation.result : result
    }

    private var sessionBadgeText: String {
        switch session.purpose {
        case .temporaryUnlock:
            return "Protected app"
        case .preview:
            return "Preview"
        case .stopBlocking:
            return "Protection review"
        }
    }

    private var sessionTitle: String {
        switch session.purpose {
        case .temporaryUnlock:
            return "Complete \(session.questions.count) \(session.questions.count == 1 ? "question" : "questions")"
        case .preview:
            return "Preview practice set"
        case .stopBlocking:
            return "Complete protection review"
        }
    }

    private var sessionSubtitle: String {
        switch session.purpose {
        case .temporaryUnlock:
            return "Answer \(session.unlockThreshold) of \(session.questions.count) correctly to begin a \(store.unlockPolicy.unlockMinutes)-minute break."
        case .preview:
            return "Preview the practice flow without changing protection."
        case .stopBlocking:
            return "Answer \(session.unlockThreshold) of \(session.questions.count) correctly to turn app protection off."
        }
    }

    private var submitButtonTitle: String {
        guard let checkedAnswer else {
            return "Check answer"
        }

        if checkedAnswer.shouldFinish {
            return checkedAnswer.shouldPass ? passingSubmitButtonTitle : "Stay protected"
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
        var updatedMissedQuestionIDs = missedQuestionIDs
        if result != .correct {
            updatedMissedQuestionIDs.insert(question.id)
        }

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
                store.makeMissedQuestionsDueNow(updatedMissedQuestionIDs)
                store.startCheckpointRetryCooldown()
            }
        }

        correctAnswerCount = updatedCorrectCount
        missedQuestionIDs = updatedMissedQuestionIDs
        checkedAnswer = CheckedCheckpointAnswer(
            result: result,
            shouldFinish: shouldFinish,
            shouldPass: shouldPass,
            unlockMinutes: shouldPass && session.purpose == .temporaryUnlock ? store.unlockPolicy.unlockMinutes : 0,
            missedQuestionIDs: updatedMissedQuestionIDs
        )
    }

    private func continueAfterCheckedAnswer() {
        guard let checkedAnswer else { return }

        guard !checkedAnswer.shouldFinish else {
            if checkedAnswer.shouldPass {
                switch session.purpose {
                case .temporaryUnlock:
                    store.startUnlockSession(minutes: checkedAnswer.unlockMinutes)
                    screenTime.temporarilyUnshield(minutes: checkedAnswer.unlockMinutes)
                case .preview:
                    break
                case .stopBlocking:
                    store.clearUnlockSession()
                    screenTime.clearShield()
                }
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
    }

    private func resultTint(for result: AnswerResult) -> Color {
        result == .correct ? CheckpointTheme.teal : CheckpointTheme.coral
    }

    private var failedSessionFeedbackText: String {
        switch session.purpose {
        case .preview:
            return "Missed questions return early so practice stays focused."
        case .temporaryUnlock, .stopBlocking:
            return "Missed questions return early, and the next checkpoint opens after a 5-minute reset."
        }
    }
}

private struct CheckedCheckpointAnswer {
    let result: AnswerResult
    let shouldFinish: Bool
    let shouldPass: Bool
    let unlockMinutes: Int
    let missedQuestionIDs: Set<CheckpointQuestion.ID>
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
    }
}
