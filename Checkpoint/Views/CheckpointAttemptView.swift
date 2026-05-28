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
    @State private var isExplanationVisible = false
    @State private var didRevealAnswer = false

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
                                            isSelected: answer == choice
                                        ) {
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
                            }
                        }
                    }

                    SectionPanel("Result") {
                        if usesAutomaticEvaluation {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Gate result")
                                        .foregroundStyle(CheckpointTheme.muted)
                                    Spacer()
                                    StatusBadge(text: automaticGateStatus, tint: automaticGateTint)
                                }

                                Text("Your choice is checked when you submit.")
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

                        Button {
                            if !isExplanationVisible {
                                didRevealAnswer = true
                            }
                            isExplanationVisible.toggle()
                        } label: {
                            Label(isExplanationVisible ? "Hide expected answer" : "Reveal expected answer", systemImage: "lightbulb")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CheckpointTheme.amber)
                        }
                        .buttonStyle(.plain)

                        if didRevealAnswer {
                            Text("Revealed answers do not count toward unlock.")
                                .font(.footnote)
                                .foregroundStyle(CheckpointTheme.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if isExplanationVisible {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(question.expectedAnswer)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.text)

                                Text(question.explanation)
                                    .font(.footnote)
                                    .foregroundStyle(CheckpointTheme.muted)
                            }
                            .padding(12)
                            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    PrimaryActionButton(
                        title: submitButtonTitle,
                        systemImage: submitButtonIcon
                    ) {
                        submitCurrentAnswer()
                    }
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        if didRevealAnswer {
            return "No credit"
        }

        return answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Choose" : "Ready"
    }

    private var automaticGateTint: Color {
        didRevealAnswer ? CheckpointTheme.coral : CheckpointTheme.teal
    }

    private var submissionResult: AnswerResult {
        if didRevealAnswer {
            return .unclear
        }

        return usesAutomaticEvaluation ? evaluation.result : result
    }

    private var sessionBadgeText: String {
        switch session.purpose {
        case .temporaryUnlock:
            return "Blocked app attempt"
        case .preview:
            return "Preview"
        case .stopBlocking:
            return "Stop blocking challenge"
        }
    }

    private var sessionTitle: String {
        switch session.purpose {
        case .temporaryUnlock:
            return "Clear \(session.questions.count) \(session.questions.count == 1 ? "question" : "questions")"
        case .preview:
            return "Preview checkpoint"
        case .stopBlocking:
            return "Clear the stop challenge"
        }
    }

    private var sessionSubtitle: String {
        switch session.purpose {
        case .temporaryUnlock:
            return "Get \(session.unlockThreshold) of \(session.questions.count) correct before the \(store.unlockPolicy.unlockMinutes)-minute unlock."
        case .preview:
            return "Try the checkpoint flow without changing blocking state."
        case .stopBlocking:
            return "Get \(session.unlockThreshold) of \(session.questions.count) correct to turn app blocking off."
        }
    }

    private var submitButtonTitle: String {
        if didRevealAnswer {
            return projectedSessionCanStillPass ? "Submit answer" : "Submit and stay locked"
        }

        if projectedSessionShouldFinish {
            return projectedSessionWillPass ? passingSubmitButtonTitle : "Submit and stay locked"
        }

        return "Submit answer"
    }

    private var passingSubmitButtonTitle: String {
        switch session.purpose {
        case .temporaryUnlock:
            return "Submit and unlock \(store.unlockPolicy.unlockMinutes) minutes"
        case .preview:
            return "Submit and finish"
        case .stopBlocking:
            return "Submit and stop blocking"
        }
    }

    private var submitButtonIcon: String {
        if projectedSessionShouldFinish {
            return projectedSessionWillPass ? passingSubmitButtonIcon : "lock"
        }

        return "checkmark.seal"
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

    private func submitCurrentAnswer() {
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
        if session.purpose == .preview {
            correctAnswerCount = updatedCorrectCount
            missedQuestionIDs = updatedMissedQuestionIDs

            guard !shouldFinish else {
                dismiss()
                return
            }

            advanceToNextQuestion()
            return
        }

        let unlockMinutes = store.submitAnswer(
            question: question,
            answer: answer,
            result: result,
            grantsUnlock: false,
            unlockMinutesOverride: shouldPass && session.purpose == .temporaryUnlock ? store.unlockPolicy.unlockMinutes : nil
        )
        correctAnswerCount = updatedCorrectCount
        missedQuestionIDs = updatedMissedQuestionIDs

        guard !shouldFinish else {
            if shouldPass {
                switch session.purpose {
                case .temporaryUnlock:
                    screenTime.temporarilyUnshield(minutes: unlockMinutes)
                case .preview:
                    break
                case .stopBlocking:
                    store.clearUnlockSession()
                    screenTime.clearShield()
                }
            } else {
                store.makeMissedQuestionsDueNow(updatedMissedQuestionIDs)
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
        isExplanationVisible = false
        didRevealAnswer = false
    }

    private var projectedCorrectAnswerCount: Int {
        correctAnswerCount + (submissionResult == .correct ? 1 : 0)
    }

    private var projectedAnsweredQuestionCount: Int {
        currentQuestionIndex + (answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }

    private var projectedSessionCanStillPass: Bool {
        session.canStillMeetUnlockThreshold(
            correctAnswerCount: projectedCorrectAnswerCount,
            answeredQuestionCount: projectedAnsweredQuestionCount
        )
    }

    private var projectedSessionShouldFinish: Bool {
        isFinalQuestion || !projectedSessionCanStillPass
    }

    private var projectedSessionWillPass: Bool {
        projectedSessionShouldFinish && session.hasMetUnlockThreshold(correctAnswerCount: projectedCorrectAnswerCount)
    }
}

private struct ChoiceButton: View {
    var title: String
    var isSelected: Bool
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
    }
}
