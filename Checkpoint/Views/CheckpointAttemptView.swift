import SwiftUI

struct CheckpointAttemptView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let question: CheckpointQuestion

    @Environment(\.dismiss) private var dismiss
    @State private var answer = ""
    @State private var result: AnswerResult = .correct
    @State private var isExplanationVisible = false
    @State private var didRevealAnswer = false
    @State private var reportReason: QuestionReportReason = .confusing
    @State private var reportNote = ""
    @State private var didReportQuestion = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusBadge(text: "Restricted app attempt", tint: CheckpointTheme.amber)

                        Text("Clear one checkpoint")
                            .font(.largeTitle.bold())
                            .foregroundStyle(CheckpointTheme.text)

                        Text("Answer this before the \(store.unlockPolicy.unlockMinutes)-minute unlock. Missed questions come back later.")
                            .font(.subheadline)
                            .foregroundStyle(CheckpointTheme.muted)
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
                            Text("Revealed answers keep this attempt locked.")
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

                    SectionPanel("Question quality") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Problem", selection: $reportReason) {
                                ForEach(QuestionReportReason.allCases) { reason in
                                    Text(reason.rawValue).tag(reason)
                                }
                            }

                            TextField("Optional note", text: $reportNote, axis: .vertical)
                                .lineLimit(3, reservesSpace: true)
                                .textFieldStyle(.plain)
                                .foregroundStyle(CheckpointTheme.text)
                                .padding(12)
                                .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))

                            SecondaryActionButton(
                                title: didReportQuestion ? "Reported" : "Report bad question",
                                systemImage: didReportQuestion ? "checkmark" : "exclamationmark.bubble"
                            ) {
                                store.reportQuestion(question, reason: reportReason, note: reportNote)
                                didReportQuestion = true
                            }
                            .disabled(didReportQuestion)
                        }
                    }

                    PrimaryActionButton(
                        title: submitButtonTitle,
                        systemImage: submitButtonIcon
                    ) {
                        let unlockMinutes = store.submitAnswer(question: question, answer: answer, result: submissionResult)
                        screenTime.temporarilyUnshield(minutes: unlockMinutes)
                        dismiss()
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
        .preferredColorScheme(.dark)
    }

    private var usesAutomaticEvaluation: Bool {
        question.format != .reflection
    }

    private var evaluation: AnswerEvaluation {
        AnswerGrader.evaluate(answer: answer, question: question)
    }

    private var automaticGateStatus: String {
        if didRevealAnswer {
            return "Locked"
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

    private var submitButtonTitle: String {
        if usesAutomaticEvaluation {
            return didRevealAnswer ? "Save and stay locked" : "Submit checkpoint"
        }

        switch submissionResult {
        case .correct:
            return "Save and unlock \(store.unlockPolicy.unlockMinutes) minutes"
        case .partial:
            if store.unlockPolicy.unlockOnPartial {
                return "Save and unlock \(store.unlockPolicy.partialUnlockMinutes) minutes"
            }
            return "Save and stay locked"
        case .incorrect, .unclear:
            return "Save and stay locked"
        }
    }

    private var submitButtonIcon: String {
        if usesAutomaticEvaluation {
            return didRevealAnswer ? "lock" : "checkmark.seal"
        }

        return submissionResult == .incorrect || submissionResult == .unclear ? "lock" : "lock.open"
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
                    .stroke(isSelected ? CheckpointTheme.teal.opacity(0.75) : .white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
