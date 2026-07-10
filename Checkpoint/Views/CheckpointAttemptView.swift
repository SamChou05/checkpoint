import SwiftUI

struct CheckpointAttemptView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    let session: CheckpointSession

    @Environment(\.dismiss) private var dismiss
    @State private var sessionQuestions: [CheckpointQuestion]
    @State private var currentQuestionIndex = 0
    @State private var correctAnswerCount = 0
    @State private var missedQuestionIDs: Set<CheckpointQuestion.ID> = []
    @State private var voidedQuestionIDs: Set<CheckpointQuestion.ID> = []
    @State private var answer = ""
    @State private var result: AnswerResult = .correct
    @State private var checkedAnswer: CheckedCheckpointAnswer?
    @State private var isReportingQuestion = false
    @State private var reportReason: QuestionReportReason = .confusing
    @State private var reportNote = ""
    @State private var reportReplacementUnavailable = false

    init(store: CheckpointStore, screenTime: ScreenTimeController, session: CheckpointSession) {
        self.store = store
        self.screenTime = screenTime
        self.session = session
        _sessionQuestions = State(initialValue: session.questions)
    }

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
                                Text("Question \(displayedUsefulQuestionNumber) of \(effectiveQuestionCount)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(CheckpointTheme.text)

                                Spacer()

                                Text("\(correctAnswerCount)/\(effectiveUnlockThreshold) correct")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.muted)

                            }

                            if !voidedQuestionIDs.isEmpty {
                                Text("\(voidedQuestionIDs.count) question\(voidedQuestionIDs.count == 1 ? "" : "s") replaced and not scored")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CheckpointTheme.blue)
                            }

                            ProgressView(
                                value: Double(completedUsefulQuestionCount),
                                total: Double(max(effectiveQuestionCount, 1))
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
                                    Text(
                                        checkedAnswer.isVoided
                                            ? "Not scored"
                                            : (checkedAnswer.result == .correct ? "Correct" : "Not quite")
                                    )
                                        .font(.headline)
                                        .foregroundStyle(CheckpointTheme.text)
                                    Spacer()
                                    StatusBadge(
                                        text: checkedAnswer.isVoided ? "Replaced" : checkedAnswer.result.rawValue,
                                        tint: checkedAnswer.isVoided ? CheckpointTheme.blue : resultTint(for: checkedAnswer.result)
                                    )
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(
                                        isExpectedAnswerDisputed
                                            ? "Reported answer (may be incorrect)"
                                            : "Answer"
                                    )
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

                                reportQuestionControls

                                if !checkedAnswer.isVoided
                                    && checkedAnswer.result != .correct
                                    && checkedAnswer.shouldFinish
                                    && !checkedAnswer.shouldPass {
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

                    if let checkedAnswer, checkedAnswer.shouldFinish, session.purpose != .preview {
                        growthReceiptPanel(for: checkedAnswer)
                    }

                }
                .padding(20)
            }
            .checkpointScreenBackground()
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(
                    title: submitButtonTitle,
                    systemImage: submitButtonIcon
                ) {
                    handlePrimaryAction()
                }
                .disabled(checkedAnswer == nil && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
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
        sessionQuestions[currentQuestionIndex]
    }

    private var isFinalQuestion: Bool {
        currentQuestionIndex >= sessionQuestions.count - 1
    }

    private var effectiveQuestionCount: Int {
        max(0, sessionQuestions.count - voidedQuestionIDs.count)
    }

    private var displayedUsefulQuestionNumber: Int {
        let usefulQuestionsBeforeCurrent = sessionQuestions
            .prefix(min(currentQuestionIndex, sessionQuestions.count))
            .filter { !voidedQuestionIDs.contains($0.id) }
            .count
        return min(max(1, effectiveQuestionCount), usefulQuestionsBeforeCurrent + 1)
    }

    private var completedUsefulQuestionCount: Int {
        let usefulQuestionsBeforeCurrent = sessionQuestions
            .prefix(min(currentQuestionIndex, sessionQuestions.count))
            .filter { !voidedQuestionIDs.contains($0.id) }
            .count
        let currentQuestionCounts = checkedAnswer != nil && !voidedQuestionIDs.contains(question.id)
        return usefulQuestionsBeforeCurrent + (currentQuestionCounts ? 1 : 0)
    }

    private var effectiveUnlockThreshold: Int {
        CheckpointSessionOutcome.evaluate(
            requiredCorrectAnswers: session.requiredCorrectAnswers,
            effectiveQuestionCount: effectiveQuestionCount,
            answeredQuestionCount: answeredUsefulQuestionCount,
            correctAnswerCount: correctAnswerCount
        ).unlockThreshold
    }

    private var answeredUsefulQuestionCount: Int {
        sessionQuestions
            .prefix(min(currentQuestionIndex + 1, sessionQuestions.count))
            .filter { !voidedQuestionIDs.contains($0.id) }
            .count
    }

    private var usesAutomaticEvaluation: Bool {
        question.format != .reflection
    }

    private var evaluation: AnswerEvaluation {
        AnswerGrader.evaluate(answer: answer, question: question)
    }

    private var isExpectedAnswerDisputed: Bool {
        store.questionReport(for: question)?.reason == .wrongAnswer
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

        let answeredQuestionCount = answeredUsefulQuestionCount
        let outcome = CheckpointSessionOutcome.evaluate(
            requiredCorrectAnswers: session.requiredCorrectAnswers,
            effectiveQuestionCount: effectiveQuestionCount,
            answeredQuestionCount: answeredQuestionCount,
            correctAnswerCount: updatedCorrectCount
        )
        let shouldFinish = isFinalQuestion || outcome.shouldFinish
        let shouldPass = shouldFinish && updatedCorrectCount >= outcome.unlockThreshold

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
            missedQuestionIDs: updatedMissedQuestionIDs,
            isVoided: false
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
        isReportingQuestion = false
        reportReason = .confusing
        reportNote = ""
        reportReplacementUnavailable = false
    }

    @ViewBuilder
    private var reportQuestionControls: some View {
        if store.hasReportedQuestion(question) {
            let savedReport = store.questionReport(for: question)
            VStack(alignment: .leading, spacing: 5) {
                Label(
                    savedReport?.reason.invalidatesLearningEvidence == false
                        ? "Difficulty feedback saved"
                        : "Question reported",
                    systemImage: "checkmark.circle.fill"
                )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)

                Text(
                    reportReplacementUnavailable
                        ? (savedReport?.replacementState == .pending
                            ? "No ready replacement was available, so this checkpoint result is unchanged. A fresh question is being prepared for next time."
                            : "No ready replacement was available, so this checkpoint result is unchanged. Future checkpoints will still avoid this item.")
                        : savedReport?.reason.invalidatesLearningEvidence == false
                        ? "Your answer still counts, and future questions will be calibrated around this signal."
                        : "It won't return in future checkpoints or count toward your learning progress."
                )
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        } else if isReportingQuestion {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                    .overlay(CheckpointTheme.hairline)

                Picker("What's wrong?", selection: $reportReason) {
                    ForEach(QuestionReportReason.allCases) { reason in
                        Text(reason.rawValue).tag(reason)
                    }
                }
                .pickerStyle(.menu)

                TextField("Optional note", text: $reportNote, axis: .vertical)
                    .lineLimit(3, reservesSpace: false)
                    .textFieldStyle(.plain)
                    .foregroundStyle(CheckpointTheme.text)
                    .padding(10)
                    .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: reportNote) { _, updatedNote in
                        if updatedNote.count > 280 {
                            reportNote = String(updatedNote.prefix(280))
                        }
                    }

                HStack(spacing: 16) {
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isReportingQuestion = false
                        }
                    }
                    .foregroundStyle(CheckpointTheme.muted)
                    .frame(minHeight: 44)

                    Spacer()

                    Button("Send report") {
                        submitQuestionReport()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(minHeight: 44)
                }
                .font(.footnote)
            }
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isReportingQuestion = true
                }
            } label: {
                Label("Report question", systemImage: "flag")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .padding(.top, 2)
        }
    }

    private func submitQuestionReport() {
        let submittedReason = reportReason
        let submittedQuestion = question
        let didSubmit = store.reportQuestion(submittedQuestion, reason: submittedReason, note: reportNote)
        isReportingQuestion = false
        reportReason = .confusing
        reportNote = ""

        guard didSubmit, submittedReason.invalidatesLearningEvidence else { return }
        reportReplacementUnavailable = !voidCurrentQuestion(submittedQuestion)
    }

    @discardableResult
    private func voidCurrentQuestion(_ submittedQuestion: CheckpointQuestion) -> Bool {
        guard let previousResult = checkedAnswer else { return false }

        let excludedIDs = Set(sessionQuestions.map(\.id))
        guard let replacement = store.replacementQuestion(
            excluding: excludedIDs,
            alongside: sessionQuestions.filter { !voidedQuestionIDs.contains($0.id) }
        ) else {
            return false
        }
        sessionQuestions.append(replacement)

        voidedQuestionIDs.insert(submittedQuestion.id)
        if previousResult.result == .correct {
            correctAnswerCount = max(0, correctAnswerCount - 1)
        }
        missedQuestionIDs.remove(submittedQuestion.id)

        let answeredQuestionCount = answeredUsefulQuestionCount
        let outcome = CheckpointSessionOutcome.evaluate(
            requiredCorrectAnswers: session.requiredCorrectAnswers,
            effectiveQuestionCount: effectiveQuestionCount,
            answeredQuestionCount: answeredQuestionCount,
            correctAnswerCount: correctAnswerCount
        )
        let shouldFinish = outcome.shouldFinish
        let shouldPass = outcome.shouldPass

        if session.purpose != .preview,
           previousResult.shouldFinish,
           !previousResult.shouldPass {
            store.clearCheckpointRetryCooldown()
        }
        if session.purpose != .preview, shouldFinish, !shouldPass {
            store.makeMissedQuestionsDueNow(missedQuestionIDs)
            store.startCheckpointRetryCooldown()
        }

        checkedAnswer = CheckedCheckpointAnswer(
            result: previousResult.result,
            shouldFinish: shouldFinish,
            shouldPass: shouldPass,
            unlockMinutes: shouldPass && session.purpose == .temporaryUnlock ? store.unlockPolicy.unlockMinutes : 0,
            missedQuestionIDs: missedQuestionIDs,
            isVoided: true
        )
        return true
    }

    private func growthReceiptPanel(for checkedAnswer: CheckedCheckpointAnswer) -> some View {
        var currentSession = session
        currentSession.questions = sessionQuestions
        let summary = store.growthSummary(
            for: currentSession,
            answeredQuestionCount: currentQuestionIndex + 1,
            missedQuestionIDs: checkedAnswer.missedQuestionIDs
        )

        return SectionPanel("Session recap") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(summary.scoreText, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)

                    if let deadlineText = summary.deadlineText {
                        Text(deadlineText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.muted)
                    }
                }

                if let strengthenedTopic = summary.strengthenedTopic {
                    GrowthSignalRow(
                        title: "Answered well",
                        detail: strengthenedTopic,
                        systemImage: "arrow.up.right",
                        tint: CheckpointTheme.teal
                    )
                }

                if let reviewTopic = summary.reviewTopic {
                    GrowthSignalRow(
                        title: "Review next",
                        detail: reviewTopic,
                        systemImage: "scope",
                        tint: CheckpointTheme.amber
                    )
                }

                if let nextCheckpointText = summary.nextCheckpointText {
                    GrowthSignalRow(
                        title: "Next checkpoint",
                        detail: nextCheckpointText,
                        systemImage: "arrow.right.circle",
                        tint: CheckpointTheme.blue
                    )
                }
            }
        }
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

private struct GrowthSignalRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                signalLabel
                Spacer(minLength: 12)
                signalDetail
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 6) {
                signalLabel
                signalDetail
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(10)
        .background(CheckpointTheme.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }

    private var signalLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
        }
    }

    private var signalDetail: some View {
        Text(detail)
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CheckedCheckpointAnswer {
    let result: AnswerResult
    let shouldFinish: Bool
    let shouldPass: Bool
    let unlockMinutes: Int
    let missedQuestionIDs: Set<CheckpointQuestion.ID>
    let isVoided: Bool
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
