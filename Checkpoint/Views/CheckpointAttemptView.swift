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

enum CheckpointResolutionTone: Equatable {
    case success
    case needsPractice
}

struct CheckpointResolutionPresentation: Equatable {
    let eyebrow: String
    let title: String
    let scoreText: String
    let detail: String
    let systemImage: String
    let tone: CheckpointResolutionTone
    let actionTitle: String
    let actionSystemImage: String

    init(
        purpose: CheckpointSessionPurpose,
        didMeetStandard: Bool,
        correctAnswerCount: Int,
        questionCount: Int,
        unlockMinutes: Int,
        failureProtectionOutcome: CheckpointFailureProtectionOutcome?,
        protectionActionFailed: Bool = false,
        cooldownDurationText: String = CheckpointRetryPolicy.cooldownDurationText
    ) {
        let safeQuestionCount = max(0, questionCount)
        let safeCorrectAnswerCount = min(max(0, correctAnswerCount), safeQuestionCount)

        scoreText = "\(safeCorrectAnswerCount) of \(safeQuestionCount) correct"
        tone = didMeetStandard ? .success : .needsPractice

        if purpose == .preview {
            eyebrow = "PRACTICE RESULT"
            title = "Practice complete"
            systemImage = didMeetStandard ? "checkmark.seal.fill" : "book.closed.fill"
            detail = didMeetStandard
                ? "You met the practice standard. App protection did not change."
                : "You didn't meet the practice standard yet. App protection did not change."
            actionTitle = "Finish"
            actionSystemImage = "checkmark.seal"
            return
        }

        eyebrow = "CHECKPOINT RESULT"
        if didMeetStandard {
            title = "Checkpoint cleared"
            systemImage = "checkmark.seal.fill"

            switch purpose {
            case .temporaryUnlock:
                detail = protectionActionFailed
                    ? "You met the standard, but the break didn't start."
                    : "Your \(unlockMinutes)-minute break is ready to begin."
                actionTitle = "Begin \(unlockMinutes)-minute break"
                actionSystemImage = "lock.open"
            case .stopBlocking:
                detail = protectionActionFailed
                    ? "You met the standard, but app protection didn't change."
                    : "App protection is ready to turn off."
                actionTitle = "Turn off protection"
                actionSystemImage = "hand.raised"
            case .preview:
                preconditionFailure("Preview resolution is handled above")
            }
        } else {
            title = "Checkpoint not cleared"
            systemImage = "arrow.counterclockwise.circle.fill"
            switch failureProtectionOutcome {
            case .activeBreakContinues:
                detail = "Your break continues. Check Home when it ends to confirm protection status."
            case .protectionRemainsOn:
                detail = "Protection stays on. Try again in \(cooldownDurationText), and we'll revisit what you missed."
            case .protectionTurnedOffForUnavailableCheckpoint:
                detail = "Protection was turned off because another full checkpoint isn't ready. Prepare questions before starting it again."
            case .protectionIsOff:
                detail = "Protection is off. Review its status from Home before trying another checkpoint."
            case nil:
                detail = "The standard wasn't met. Return home to review protection before trying again."
            }
            actionTitle = "Return home"
            actionSystemImage = "house"
        }
    }
}

struct CheckpointProtectionActionFailurePresentation: Equatable {
    let title: String
    let detail: String
    let systemImage = "exclamationmark.triangle.fill"

    init(purpose: CheckpointSessionPurpose, detail: String) {
        switch purpose {
        case .temporaryUnlock:
            title = "Break didn't start"
        case .stopBlocking:
            title = "Protection didn't change"
        case .preview:
            title = "Action didn't finish"
        }
        self.detail = detail
    }
}

enum CheckpointResolutionMotionStyle: Equatable {
    case choreographed
    case identity
}

struct CheckpointResolutionMotionPolicy {
    let reduceMotion: Bool

    var style: CheckpointResolutionMotionStyle {
        reduceMotion ? .identity : .choreographed
    }

    var animation: Animation? {
        CheckpointMotion.animation(CheckpointMotion.reveal, reduceMotion: reduceMotion)
    }

    var transition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.975, anchor: .top)),
            removal: .opacity
        )
    }
}

enum CheckpointFeedbackDestination: Hashable {
    case answerFeedback
    case protectionActionFailure
    case resolution

    static func resolve(shouldFinish: Bool) -> Self {
        shouldFinish ? .resolution : .answerFeedback
    }
}

enum CheckpointAttemptInitialPresentation: Equatable {
    case unanswered
    case terminal(
        questionIndex: Int,
        correctAnswerCount: Int,
        answer: String,
        result: AnswerResult,
        didPass: Bool,
        actionErrorMessage: String? = nil
    )
}

private struct CheckpointResolutionCard: View {
    let presentation: CheckpointResolutionPresentation
    let feedbackSequence: Int
    let reduceMotion: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CheckpointHeroSurface(
            glowColor: accent,
            glowOpacity: 0.11,
            glowOffset: CGSize(width: 62, height: -78)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                resolutionIdentity

                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.scoreText)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(CheckpointTheme.heroText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            CheckpointTheme.heroSubtleFill,
                            in: Capsule()
                        )

                    Text(presentation.detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(presentation.title). \(presentation.scoreText). \(presentation.detail)"
        )
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var resolutionIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                resultIcon
                identityCopy
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 13) {
                    resultIcon
                    identityCopy
                }

                VStack(alignment: .leading, spacing: 12) {
                    resultIcon
                    identityCopy
                }
            }
        }
    }

    private var resultIcon: some View {
        Image(systemName: presentation.systemImage)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(CheckpointTheme.ink)
            .frame(width: 50, height: 50)
            .background(accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .symbolEffect(.bounce, options: .nonRepeating, value: feedbackSequence)
            .symbolEffectsRemoved(reduceMotion)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var identityCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(0.85)
                .foregroundStyle(accent)

            Text(presentation.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accent: Color {
        switch presentation.tone {
        case .success:
            CheckpointTheme.heroSuccess
        case .needsPractice:
            CheckpointTheme.heroWarning
        }
    }
}

private struct CheckpointProtectionActionFailureCard: View {
    let presentation: CheckpointProtectionActionFailurePresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CheckpointTheme.coral)
                .frame(width: 34, height: 34)
                .background(
                    CheckpointTheme.coral.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.coral)

                Text(presentation.detail)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.coral.opacity(0.08),
            in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                .stroke(CheckpointTheme.coral.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.title). \(presentation.detail)")
        .accessibilityAddTraits(.isHeader)
    }
}

struct CheckpointAttemptView: View {
    let store: CheckpointStore
    let workflow: CheckpointWorkflowCoordinator
    let session: CheckpointSession
    private let reduceMotionOverride: Bool?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @State private var currentQuestionIndex = 0
    @State private var correctAnswerCount = 0
    @State private var answer = ""
    @State private var result: AnswerResult = .correct
    @State private var checkedAnswer: CheckedCheckpointAnswer?
    @State private var protectionActionErrorMessage: String?
    @State private var protectionActionErrorSequence = 0
    @State private var feedbackSequence = 0
    @State private var resolutionFeedback: CheckpointResolutionFeedback?
    @State private var isExitConfirmationPresented = false
    @State private var hasFinalizedCheckpoint = false
    @State private var questionQualityFeedbackContext: QuestionQualityFeedbackContext?
    @FocusState private var isAnswerFieldFocused: Bool
    @AccessibilityFocusState private var accessibilityFocus: AttemptAccessibilityFocus?

    init(
        store: CheckpointStore,
        workflow: CheckpointWorkflowCoordinator,
        session: CheckpointSession,
        initialPresentation: CheckpointAttemptInitialPresentation = .unanswered,
        reduceMotionOverride: Bool? = nil
    ) {
        self.store = store
        self.workflow = workflow
        self.session = session
        self.reduceMotionOverride = reduceMotionOverride

        guard case let .terminal(
            questionIndex,
            correctAnswerCount,
            answer,
            result,
            didPass,
            actionErrorMessage
        ) = initialPresentation else { return }

        let boundedQuestionIndex = min(
            max(0, questionIndex),
            max(0, session.questions.count - 1)
        )
        let boundedCorrectAnswerCount = min(
            max(0, correctAnswerCount),
            session.questions.count
        )
        _currentQuestionIndex = State(initialValue: boundedQuestionIndex)
        _correctAnswerCount = State(initialValue: boundedCorrectAnswerCount)
        _answer = State(initialValue: answer)
        _result = State(initialValue: result)
        _checkedAnswer = State(
            initialValue: CheckedCheckpointAnswer(
                result: result,
                shouldFinish: true,
                shouldPass: didPass,
                failureProtectionOutcome: !didPass && session.purpose != .preview
                    ? (store.hasReadyCheckpointSet
                        ? .protectionRemainsOn
                        : .protectionTurnedOffForUnavailableCheckpoint)
                    : nil
            )
        )
        _protectionActionErrorMessage = State(initialValue: actionErrorMessage)
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        progressHeader
                            .id(AttemptScrollAnchor.question)

                        if let resolutionPresentation {
                            CheckpointResolutionCard(
                                presentation: resolutionPresentation,
                                feedbackSequence: feedbackSequence,
                                reduceMotion: reduceMotion
                            )
                            .id(CheckpointFeedbackDestination.resolution)
                            .accessibilityFocused($accessibilityFocus, equals: .resolution)
                            .transition(resolutionMotionPolicy.transition)

                            if let protectionActionFailurePresentation {
                                CheckpointProtectionActionFailureCard(
                                    presentation: protectionActionFailurePresentation
                                )
                                .id(CheckpointFeedbackDestination.protectionActionFailure)
                                .accessibilityFocused(
                                    $accessibilityFocus,
                                    equals: .protectionActionFailure
                                )
                                .transition(resolutionMotionPolicy.transition)
                            }
                        }

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
                .onChange(of: protectionActionErrorSequence) { _, sequence in
                    revealProtectionActionFailure(sequence: sequence, using: scrollProxy)
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
        .sensoryFeedback(.error, trigger: protectionActionErrorSequence)
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
            return checkedAnswer.shouldPass ? "Standard met" : "Standard not met"
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

    private var resolutionPresentation: CheckpointResolutionPresentation? {
        guard let checkedAnswer, checkedAnswer.shouldFinish else { return nil }
        return CheckpointResolutionPresentation(
            purpose: session.purpose,
            didMeetStandard: checkedAnswer.shouldPass,
            correctAnswerCount: correctAnswerCount,
            questionCount: session.questions.count,
            unlockMinutes: store.unlockPolicy.unlockMinutes,
            failureProtectionOutcome: checkedAnswer.failureProtectionOutcome,
            protectionActionFailed: protectionActionErrorMessage != nil
        )
    }

    private var protectionActionFailurePresentation: CheckpointProtectionActionFailurePresentation? {
        guard let protectionActionErrorMessage else { return nil }
        return CheckpointProtectionActionFailurePresentation(
            purpose: session.purpose,
            detail: protectionActionErrorMessage
        )
    }

    private var resolutionMotionPolicy: CheckpointResolutionMotionPolicy {
        CheckpointResolutionMotionPolicy(reduceMotion: reduceMotion)
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

        if checkedAnswer.shouldFinish, let resolutionPresentation {
            return resolutionPresentation.actionTitle
        }

        return "Next question"
    }

    private var submitButtonIcon: String {
        guard let checkedAnswer else {
            return "checkmark.seal"
        }

        if checkedAnswer.shouldFinish, let resolutionPresentation {
            return resolutionPresentation.actionSystemImage
        }

        return "arrow.right"
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
        var failureProtectionOutcome: CheckpointFailureProtectionOutcome?

        if session.purpose != .preview {
            store.submitAnswer(
                question: question,
                answer: answer,
                result: result,
                grantsUnlock: false
            )

            if shouldFinish && !shouldPass {
                failureProtectionOutcome = workflow.resolveFailed(session)
            }
        }

        isAnswerFieldFocused = false
        let updateAnimation = shouldFinish
            ? resolutionMotionPolicy.animation
            : CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)
        withAnimation(updateAnimation) {
            correctAnswerCount = updatedCorrectCount
            checkedAnswer = CheckedCheckpointAnswer(
                result: result,
                shouldFinish: shouldFinish,
                shouldPass: shouldPass,
                failureProtectionOutcome: failureProtectionOutcome
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
                    withAnimation(resolutionMotionPolicy.animation) {
                        protectionActionErrorMessage = errorMessage
                        protectionActionErrorSequence += 1
                    }
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

            guard sequence == feedbackSequence, let checkedAnswer else { return }

            let destination = CheckpointFeedbackDestination.resolve(
                shouldFinish: checkedAnswer.shouldFinish
            )
            switch destination {
            case .answerFeedback:
                accessibilityFocus = .answerFeedback
            case .protectionActionFailure:
                accessibilityFocus = .protectionActionFailure
            case .resolution:
                accessibilityFocus = .resolution
            }

            let behavior = CheckpointFeedbackRevealBehavior.resolve(
                reduceMotion: reduceMotion,
                assistiveNavigationEnabled: voiceOverEnabled || switchControlEnabled
            )
            guard case let .focusAndScroll(animated) = behavior else { return }

            withAnimation(animated ? CheckpointMotion.change : nil) {
                proxy.scrollTo(destination, anchor: .top)
            }
        }
    }

    private func revealProtectionActionFailure(
        sequence: Int,
        using proxy: ScrollViewProxy
    ) {
        Task { @MainActor in
            await Task.yield()

            guard sequence == protectionActionErrorSequence,
                  protectionActionErrorMessage != nil else { return }

            accessibilityFocus = .protectionActionFailure

            let behavior = CheckpointFeedbackRevealBehavior.resolve(
                reduceMotion: reduceMotion,
                assistiveNavigationEnabled: voiceOverEnabled || switchControlEnabled
            )
            guard case let .focusAndScroll(animated) = behavior else { return }

            withAnimation(animated ? CheckpointMotion.change : nil) {
                proxy.scrollTo(
                    CheckpointFeedbackDestination.protectionActionFailure,
                    anchor: .center
                )
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

    @ViewBuilder
    private var inlineFeedback: some View {
        if let checkedAnswer {
            let feedbackPresentation = CheckpointAnswerResultPresentation(
                result: checkedAnswer.result
            )

            Divider()
                .overlay(CheckpointTheme.hairline)

            VStack(alignment: .leading, spacing: 12) {
                if checkedAnswer.shouldFinish {
                    Text("FINAL ANSWER")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(CheckpointTheme.muted)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 10) {
                    Image(systemName: feedbackPresentation.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(resultTint(for: feedbackPresentation.tone))
                        .symbolEffect(.bounce, options: .nonRepeating, value: feedbackSequence)
                        .symbolEffectsRemoved(reduceMotion || checkedAnswer.shouldFinish)
                        .accessibilityHidden(true)

                    Text(feedbackPresentation.label)
                        .font(.headline)
                        .foregroundStyle(resultTint(for: feedbackPresentation.tone))
                        .accessibilityLabel(
                            checkedAnswer.shouldFinish
                                ? "Final answer: \(feedbackPresentation.label)"
                                : feedbackPresentation.label
                        )
                        .accessibilityFocused($accessibilityFocus, equals: .answerFeedback)
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

                if QuestionQualityFeedbackPresentation.supportsRemoval(in: session.purpose) {
                    QuestionRemovalControl(report: currentQuestionReport) {
                        presentQuestionQualityFeedback()
                    }
                }
            }
            .id(CheckpointFeedbackDestination.answerFeedback)
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
    let failureProtectionOutcome: CheckpointFailureProtectionOutcome?
}

private enum AttemptAccessibilityFocus: Hashable {
    case question
    case answerFeedback
    case protectionActionFailure
    case resolution
}

private enum AttemptScrollAnchor: Hashable {
    case question
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
