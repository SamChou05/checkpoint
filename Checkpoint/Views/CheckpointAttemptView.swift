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
    let compactTitle: String
    let scoreText: String
    let scoreComponents: [String]
    let compactScoreComponents: [String]
    let detail: String
    let systemImage: String
    let tone: CheckpointResolutionTone
    let actionTitle: String
    let actionSystemImage: String

    init(
        purpose: CheckpointSessionPurpose,
        didMeetStandard: Bool,
        correctAnswerCount: Int,
        answeredQuestionCount: Int,
        questionCount: Int,
        requiredCorrectAnswerCount: Int,
        unlockMinutes: Int,
        failureProtectionOutcome: CheckpointFailureProtectionOutcome?,
        protectionActionFailed: Bool = false,
        cooldownDurationText: String = CheckpointRetryPolicy.cooldownDurationText
    ) {
        let safeQuestionCount = max(0, questionCount)
        let safeAnsweredQuestionCount = min(max(0, answeredQuestionCount), safeQuestionCount)
        let safeCorrectAnswerCount = min(max(0, correctAnswerCount), safeAnsweredQuestionCount)
        let safeRequiredCorrectAnswerCount = min(
            max(0, requiredCorrectAnswerCount),
            safeQuestionCount
        )
        let endedBeforeFinalQuestion = safeAnsweredQuestionCount < safeQuestionCount

        if endedBeforeFinalQuestion {
            scoreComponents = [
                "\(safeCorrectAnswerCount) correct",
                "\(safeAnsweredQuestionCount) of \(safeQuestionCount) answered"
            ]
            compactScoreComponents = [
                "\(safeCorrectAnswerCount) correct",
                "\(safeAnsweredQuestionCount) / \(safeQuestionCount) done"
            ]
            scoreText = scoreComponents.joined(separator: " · ")
        } else {
            scoreText = "\(safeCorrectAnswerCount) of \(safeQuestionCount) correct"
            scoreComponents = [scoreText]
            compactScoreComponents = ["Score \(safeCorrectAnswerCount) / \(safeQuestionCount)"]
        }
        tone = didMeetStandard ? .success : .needsPractice

        if purpose == .preview {
            eyebrow = "PRACTICE RESULT"
            title = "Practice complete"
            compactTitle = "Complete"
            systemImage = didMeetStandard ? "checkmark.seal.fill" : "book.closed.fill"
            if didMeetStandard {
                detail = "You met the practice standard. App protection did not change."
            } else if endedBeforeFinalQuestion {
                detail = "The \(safeRequiredCorrectAnswerCount)-of-\(safeQuestionCount) standard was no longer reachable. App protection did not change."
            } else {
                detail = "You didn't meet the practice standard yet. App protection did not change."
            }
            actionTitle = "Finish"
            actionSystemImage = "checkmark.seal"
            return
        }

        eyebrow = "CHECKPOINT RESULT"
        if didMeetStandard {
            title = "Checkpoint cleared"
            compactTitle = "Cleared"
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
            compactTitle = "Not cleared"
            systemImage = "arrow.counterclockwise.circle.fill"
            let earlyResolutionDetail = endedBeforeFinalQuestion
                ? "The \(safeRequiredCorrectAnswerCount)-of-\(safeQuestionCount) standard was no longer reachable. "
                : ""
            switch failureProtectionOutcome {
            case .activeBreakContinues:
                detail = earlyResolutionDetail
                    + "Your break continues. Check Home when it ends to confirm protection status."
            case .protectionRemainsOn:
                detail = earlyResolutionDetail
                    + "Protection stays on. Try again in \(cooldownDurationText), and we'll revisit what you missed."
            case .protectionTurnedOffForUnavailableCheckpoint:
                detail = earlyResolutionDetail
                    + "Protection was turned off because another full checkpoint isn't ready. Prepare questions before starting it again."
            case .protectionIsOff:
                detail = earlyResolutionDetail
                    + "Protection is off. Review its status from Home before trying another checkpoint."
            case nil:
                detail = earlyResolutionDetail
                    + "The standard wasn't met. Return home to review protection before trying again."
            }
            actionTitle = "Return home"
            actionSystemImage = "house"
        }
    }
}

enum CheckpointAttemptPrimaryActionPlacement: Equatable {
    case pinned
    case inline
}

struct CheckpointAttemptChromePresentation: Equatable {
    let showsProgressHeader: Bool
    let primaryActionPlacement: CheckpointAttemptPrimaryActionPlacement

    init(isResolved: Bool, usesAccessibilityTextSize: Bool) {
        showsProgressHeader = !isResolved
        primaryActionPlacement = usesAccessibilityTextSize ? .inline : .pinned
    }
}

struct CheckpointAnswerProgression: Equatable {
    let shouldFinish: Bool
    let shouldPass: Bool

    init(
        session: CheckpointSession,
        correctAnswerCount: Int,
        answeredQuestionCount: Int
    ) {
        let answeredEveryQuestion = answeredQuestionCount >= session.questions.count
        shouldFinish = answeredEveryQuestion || !session.canStillMeetUnlockThreshold(
            correctAnswerCount: correctAnswerCount,
            answeredQuestionCount: answeredQuestionCount
        )
        shouldPass = shouldFinish
            && session.hasMetUnlockThreshold(correctAnswerCount: correctAnswerCount)
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

    var progressTransition: AnyTransition {
        reduceMotion ? .identity : .opacity
    }
}

struct CheckpointChoiceSelectionDecision: Equatable {
    let answer: String
    let reportsSelectionFeedback: Bool
}

struct CheckpointChoiceSelectionPolicy {
    let reduceMotion: Bool

    var usesLinkedSelectionPlate: Bool {
        !reduceMotion
    }

    var animation: Animation? {
        CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)
    }

    static func decision(
        currentAnswer: String,
        requestedAnswer: String,
        isLocked: Bool
    ) -> CheckpointChoiceSelectionDecision? {
        guard !isLocked, currentAnswer != requestedAnswer else { return nil }
        return CheckpointChoiceSelectionDecision(
            answer: requestedAnswer,
            reportsSelectionFeedback: true
        )
    }
}

enum CheckpointChoiceLayoutStyle: Equatable {
    case inline
    case stacked
}

struct CheckpointChoiceLayoutPolicy: Equatable {
    let usesAccessibilityTextSize: Bool

    let contentSpacing: CGFloat = 12
    let indicatorWidth: CGFloat = 22
    let minimumControlHeight: CGFloat = 52

    var style: CheckpointChoiceLayoutStyle {
        usesAccessibilityTextSize ? .stacked : .inline
    }

    var contentPadding: CGFloat {
        usesAccessibilityTextSize ? 8 : 12
    }

    var answerGroupHorizontalExpansion: CGFloat {
        usesAccessibilityTextSize ? 12 : 0
    }

    var titleFont: Font {
        usesAccessibilityTextSize
            ? .footnote.weight(.semibold)
            : .subheadline.weight(.semibold)
    }

    func availableTitleWidth(in controlWidth: CGFloat) -> CGFloat {
        let reservedWidth = contentPadding * 2
            + (style == .inline ? indicatorWidth + contentSpacing : 0)
        return max(0, controlWidth - reservedWidth)
    }
}

enum CheckpointChoiceLayoutElement: Hashable {
    case questionPanel
    case answerGroup
    case control(String)
    case indicator(String)
    case title(String)
}

struct CheckpointChoiceLayoutPreferenceKey: PreferenceKey {
    static var defaultValue: [CheckpointChoiceLayoutElement: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [CheckpointChoiceLayoutElement: Anchor<CGRect>],
        nextValue: () -> [CheckpointChoiceLayoutElement: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private extension View {
    func checkpointChoiceLayoutAnchor(
        _ element: CheckpointChoiceLayoutElement
    ) -> some View {
        transformAnchorPreference(
            key: CheckpointChoiceLayoutPreferenceKey.self,
            value: .bounds,
            transform: { value, anchor in
                value[element] = anchor
            }
        )
    }
}

enum CheckpointRunwayNodeState: Equatable {
    case upcoming
    case current
    case answered(AnswerResult)
}

enum CheckpointRunwayNodeTone: Equatable {
    case muted
    case current
    case success
    case warning
    case failure
}

struct CheckpointRunwayNodePresentation: Identifiable, Equatable {
    let questionIndex: Int
    let state: CheckpointRunwayNodeState
    let isCurrentQuestion: Bool

    var id: Int { questionIndex }
    var questionNumber: Int { questionIndex + 1 }

    var systemImage: String {
        switch state {
        case .upcoming:
            return "\(questionNumber).circle"
        case .current:
            return "\(questionNumber).circle.fill"
        case let .answered(result):
            switch result {
            case .correct:
                return "checkmark.circle.fill"
            case .partial:
                return "circle.lefthalf.filled"
            case .incorrect:
                return "xmark.circle.fill"
            case .unclear:
                return "questionmark.circle.fill"
            }
        }
    }

    var tone: CheckpointRunwayNodeTone {
        switch state {
        case .upcoming:
            return .muted
        case .current:
            return .current
        case let .answered(result):
            switch result {
            case .correct:
                return .success
            case .partial, .unclear:
                return .warning
            case .incorrect:
                return .failure
            }
        }
    }

}

enum CheckpointRunwayStatusTone: Equatable {
    case progress
    case secured
}

struct CheckpointRunwayPresentation: Equatable {
    let nodes: [CheckpointRunwayNodePresentation]
    let currentQuestionNumber: Int
    let questionCount: Int
    let answeredQuestionCount: Int
    let correctAnswerCount: Int
    let requiredCorrectAnswerCount: Int
    let statusText: String
    let statusTone: CheckpointRunwayStatusTone
    let accessibilityValue: String

    init(
        questionCount: Int,
        currentQuestionIndex: Int,
        answerResults: [AnswerResult],
        requiredCorrectAnswerCount: Int
    ) {
        let safeQuestionCount = max(0, questionCount)
        let safeCurrentQuestionIndex = min(
            max(0, currentQuestionIndex),
            max(0, safeQuestionCount - 1)
        )
        let safeAnswerResults = Array(answerResults.prefix(safeQuestionCount))
        let safeRequiredCorrectAnswerCount = min(
            max(0, requiredCorrectAnswerCount),
            safeQuestionCount
        )
        let safeCorrectAnswerCount = safeAnswerResults.reduce(into: 0) { count, result in
            if result == .correct {
                count += 1
            }
        }
        let remainingCorrectAnswers = max(
            0,
            safeRequiredCorrectAnswerCount - safeCorrectAnswerCount
        )
        let remainingQuestions = max(0, safeQuestionCount - safeAnswerResults.count)

        self.questionCount = safeQuestionCount
        currentQuestionNumber = safeQuestionCount == 0 ? 0 : safeCurrentQuestionIndex + 1
        answeredQuestionCount = safeAnswerResults.count
        correctAnswerCount = safeCorrectAnswerCount
        self.requiredCorrectAnswerCount = safeRequiredCorrectAnswerCount

        let nodePresentations = (0..<safeQuestionCount).map { questionIndex in
            let state: CheckpointRunwayNodeState
            if safeAnswerResults.indices.contains(questionIndex) {
                state = .answered(safeAnswerResults[questionIndex])
            } else if questionIndex == safeCurrentQuestionIndex {
                state = .current
            } else {
                state = .upcoming
            }
            return CheckpointRunwayNodePresentation(
                questionIndex: questionIndex,
                state: state,
                isCurrentQuestion: questionIndex == safeCurrentQuestionIndex
            )
        }
        nodes = nodePresentations

        if remainingCorrectAnswers == 0 {
            statusTone = .secured
            if remainingQuestions == 1 {
                statusText = "Standard secured · Final question"
            } else if remainingQuestions > 1 {
                statusText = "Standard secured · \(remainingQuestions) questions left"
            } else {
                statusText = "Standard secured"
            }
        } else {
            statusTone = .progress
            statusText = remainingCorrectAnswers == 1
                ? "1 more to clear"
                : "\(remainingCorrectAnswers) more to clear"
        }

        let questionProgress = safeQuestionCount == 0
            ? "No questions"
            : "Question \(safeCurrentQuestionIndex + 1) of \(safeQuestionCount)"
        let answerProgress = "\(safeAnswerResults.count) of \(safeQuestionCount) answered"
        let correctProgress = "\(safeCorrectAnswerCount) of \(safeRequiredCorrectAnswerCount) correct"
        let answerHistory = Self.answerHistoryAccessibilityText(in: nodePresentations)
        accessibilityValue = "\(questionProgress). \(answerProgress). \(correctProgress). \(statusText).\(answerHistory)"
    }

    static func recording(
        _ result: AnswerResult,
        for questionIndex: Int,
        in answerResults: [AnswerResult],
        questionCount: Int
    ) -> [AnswerResult] {
        guard questionCount > 0 else { return [] }
        let safeQuestionIndex = min(max(0, questionIndex), questionCount - 1)
        var updatedResults = Array(answerResults.prefix(safeQuestionIndex))
        updatedResults.append(result)
        return updatedResults
    }

    private static func answerHistoryAccessibilityText(
        in nodes: [CheckpointRunwayNodePresentation]
    ) -> String {
        let resultGroups: [(result: AnswerResult, label: String)] = [
            (.correct, "Correct"),
            (.partial, "Almost"),
            (.incorrect, "Incorrect"),
            (.unclear, "Needs review"),
        ]
        let descriptions = resultGroups.compactMap { group -> String? in
            let questionNumbers = nodes.compactMap { node -> Int? in
                guard node.state == .answered(group.result) else { return nil }
                return node.questionNumber
            }
            guard !questionNumbers.isEmpty else { return nil }

            let questionNoun = questionNumbers.count == 1 ? "question" : "questions"
            let numberList = questionNumbers.map(String.init).joined(separator: ", ")
            return "\(group.label): \(questionNoun) \(numberList)"
        }

        guard !descriptions.isEmpty else { return "" }
        return " Answer history. \(descriptions.joined(separator: ". "))."
    }
}

struct CheckpointRunwayLayoutMetrics: Equatable {
    static let maximumNodesPerRow = 10
    static let maximumRegularNodeCount = 6

    let questionCount: Int

    var usesCompactNodes: Bool {
        questionCount > Self.maximumRegularNodeCount
    }

    var nodeDiameter: CGFloat {
        usesCompactNodes ? 20 : 30
    }

    var nodeFrameDiameter: CGFloat {
        usesCompactNodes ? 26 : 38
    }

    var connectorMinimumWidth: CGFloat {
        usesCompactNodes ? 2 : 4
    }

    var connectorHorizontalPadding: CGFloat {
        usesCompactNodes ? 0 : 1
    }

    func minimumRowWidth(nodeCount: Int) -> CGFloat {
        let safeNodeCount = max(0, nodeCount)
        guard safeNodeCount > 0 else { return 0 }
        let connectorCount = max(0, safeNodeCount - 1)
        let connectorWidth = connectorMinimumWidth + (connectorHorizontalPadding * 2)
        return (CGFloat(safeNodeCount) * nodeFrameDiameter)
            + (CGFloat(connectorCount) * connectorWidth)
    }
}

enum CheckpointRunwayMotionStyle: Equatable {
    case linked
    case identity
}

struct CheckpointRunwayMotionPolicy {
    let reduceMotion: Bool

    var style: CheckpointRunwayMotionStyle {
        reduceMotion ? .identity : .linked
    }

    var usesLinkedCurrentMarker: Bool {
        !reduceMotion
    }

    var animation: Animation? {
        CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)
    }
}

enum CheckpointAnswerFeedbackSensoryTone: Equatable {
    case success
    case warning

    init(result: AnswerResult) {
        self = result == .correct ? .success : .warning
    }
}

struct CheckpointAnswerFeedbackSignal: Equatable {
    let sequence: Int
    let tone: CheckpointAnswerFeedbackSensoryTone
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
    case selected(questionIndex: Int, answer: String)
    case reviewed(
        questionIndex: Int,
        previousResults: [AnswerResult],
        answer: String,
        result: AnswerResult
    )
    case terminal(
        questionIndex: Int,
        correctAnswerCount: Int,
        answer: String,
        result: AnswerResult,
        didPass: Bool,
        actionErrorMessage: String? = nil
    )
}

struct CheckpointClearanceRunway: View {
    let presentation: CheckpointRunwayPresentation
    let motionPolicy: CheckpointRunwayMotionPolicy
    let currentMarkerNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: nodeRows.count > 1 ? 8 : 0) {
            ForEach(nodeRows.indices, id: \.self) { rowIndex in
                runwayRow(nodeRows[rowIndex])
            }
        }
        .frame(maxWidth: .infinity)
        .animation(motionPolicy.animation, value: presentation)
        .accessibilityHidden(true)
    }

    private var nodeRows: [[CheckpointRunwayNodePresentation]] {
        let nodes = presentation.nodes
        let maximumNodesPerRow = CheckpointRunwayLayoutMetrics.maximumNodesPerRow
        guard nodes.count > maximumNodesPerRow else { return nodes.isEmpty ? [] : [nodes] }

        let rowCount = Int(ceil(Double(nodes.count) / Double(maximumNodesPerRow)))
        let nodesPerRow = Int(ceil(Double(nodes.count) / Double(rowCount)))
        return stride(from: 0, to: nodes.count, by: nodesPerRow).map { startIndex in
            Array(nodes[startIndex..<min(startIndex + nodesPerRow, nodes.count)])
        }
    }

    private var layoutMetrics: CheckpointRunwayLayoutMetrics {
        CheckpointRunwayLayoutMetrics(questionCount: presentation.nodes.count)
    }

    private func runwayRow(_ nodes: [CheckpointRunwayNodePresentation]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { offset, node in
                runwayNode(node)

                if offset < nodes.count - 1 {
                    connector(after: node)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func runwayNode(_ node: CheckpointRunwayNodePresentation) -> some View {
        ZStack {
            if node.isCurrentQuestion {
                currentMarker(for: node)
            }

            Image(systemName: node.systemImage)
                .font(.system(size: layoutMetrics.nodeDiameter, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint(for: node.tone))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffectsRemoved(motionPolicy.reduceMotion)
        }
        .frame(width: layoutMetrics.nodeFrameDiameter, height: layoutMetrics.nodeFrameDiameter)
    }

    @ViewBuilder
    private func currentMarker(for node: CheckpointRunwayNodePresentation) -> some View {
        let marker = Circle()
            .stroke(CheckpointTheme.teal.opacity(0.48), lineWidth: 2)
            .frame(
                width: layoutMetrics.nodeDiameter + 7,
                height: layoutMetrics.nodeDiameter + 7
            )

        if motionPolicy.usesLinkedCurrentMarker {
            marker.matchedGeometryEffect(
                id: "checkpoint-runway-current-marker",
                in: currentMarkerNamespace
            )
        } else {
            marker
        }
    }

    private func connector(after node: CheckpointRunwayNodePresentation) -> some View {
        Capsule()
            .fill(connectorTint(after: node))
            .frame(minWidth: layoutMetrics.connectorMinimumWidth, maxWidth: .infinity)
            .frame(height: 2)
            .padding(.horizontal, layoutMetrics.connectorHorizontalPadding)
    }

    private func connectorTint(after node: CheckpointRunwayNodePresentation) -> Color {
        guard case .answered = node.state else { return CheckpointTheme.hairline }
        return tint(for: node.tone).opacity(0.52)
    }

    private func tint(for tone: CheckpointRunwayNodeTone) -> Color {
        switch tone {
        case .muted:
            return CheckpointTheme.muted.opacity(0.68)
        case .current, .success:
            return CheckpointTheme.teal
        case .warning:
            return CheckpointTheme.amber
        case .failure:
            return CheckpointTheme.coral
        }
    }
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
                    scoreBadges

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
    private var scoreBadges: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(displayedScoreComponents, id: \.self) { component in
                    scoreBadge(component)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(displayedScoreComponents, id: \.self) { component in
                        scoreBadge(component)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(displayedScoreComponents, id: \.self) { component in
                        scoreBadge(component)
                    }
                }
            }
        }
    }

    private func scoreBadge(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(CheckpointTheme.heroText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                CheckpointTheme.heroSubtleFill,
                in: RoundedRectangle(
                    cornerRadius: dynamicTypeSize.isAccessibilitySize
                        ? CheckpointTheme.compactCornerRadius
                        : 100,
                    style: .continuous
                )
            )
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
            Text(usesCompactResultCopy ? "RESULT" : presentation.eyebrow)
                .font(.caption2.weight(.bold))
                .tracking(0.85)
                .foregroundStyle(accent)

            Text(usesCompactResultCopy ? presentation.compactTitle : presentation.title)
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

    private var usesCompactResultCopy: Bool {
        dynamicTypeSize >= .accessibility4
    }

    private var displayedScoreComponents: [String] {
        usesCompactResultCopy
            ? presentation.compactScoreComponents
            : presentation.scoreComponents
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
    private let onEarnedBreak: @MainActor (EarnedBreakHandoffToken) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var currentQuestionIndex = 0
    @State private var correctAnswerCount = 0
    @State private var answer = ""
    @State private var result: AnswerResult = .correct
    @State private var answerResults: [AnswerResult] = []
    @State private var checkedAnswer: CheckedCheckpointAnswer?
    @State private var protectionActionErrorMessage: String?
    @State private var protectionActionErrorSequence = 0
    @State private var feedbackSequence = 0
    @State private var choiceSelectionFeedbackSequence = 0
    @State private var answerFeedbackSignal: CheckpointAnswerFeedbackSignal?
    @State private var resolutionFeedback: CheckpointResolutionFeedback?
    @State private var isExitConfirmationPresented = false
    @State private var hasFinalizedCheckpoint = false
    @State private var hasCommittedResolutionAction = false
    @State private var questionQualityFeedbackContext: QuestionQualityFeedbackContext?
    @FocusState private var isAnswerFieldFocused: Bool
    @AccessibilityFocusState private var accessibilityFocus: AttemptAccessibilityFocus?
    @Namespace private var choiceSelectionNamespace
    @Namespace private var runwayCurrentMarkerNamespace

    init(
        store: CheckpointStore,
        workflow: CheckpointWorkflowCoordinator,
        session: CheckpointSession,
        initialPresentation: CheckpointAttemptInitialPresentation = .unanswered,
        reduceMotionOverride: Bool? = nil,
        onEarnedBreak: @escaping @MainActor (EarnedBreakHandoffToken) -> Void = { _ in }
    ) {
        self.store = store
        self.workflow = workflow
        self.session = session
        self.reduceMotionOverride = reduceMotionOverride
        self.onEarnedBreak = onEarnedBreak

        switch initialPresentation {
        case .unanswered:
            return
        case let .selected(questionIndex, answer):
            _currentQuestionIndex = State(
                initialValue: Self.boundedQuestionIndex(questionIndex, in: session)
            )
            _answer = State(initialValue: answer)
        case let .reviewed(questionIndex, previousResults, answer, result):
            let boundedQuestionIndex = Self.boundedQuestionIndex(questionIndex, in: session)
            let recordedResults = CheckpointRunwayPresentation.recording(
                result,
                for: boundedQuestionIndex,
                in: previousResults,
                questionCount: session.questions.count
            )
            let reviewedCorrectAnswerCount = recordedResults.filter { $0 == .correct }.count
            let reviewedProgression = CheckpointAnswerProgression(
                session: session,
                correctAnswerCount: reviewedCorrectAnswerCount,
                answeredQuestionCount: recordedResults.count
            )
            _currentQuestionIndex = State(initialValue: boundedQuestionIndex)
            _correctAnswerCount = State(initialValue: reviewedCorrectAnswerCount)
            _answer = State(initialValue: answer)
            _result = State(initialValue: result)
            _answerResults = State(initialValue: recordedResults)
            _checkedAnswer = State(
                initialValue: CheckedCheckpointAnswer(
                    result: result,
                    shouldFinish: reviewedProgression.shouldFinish,
                    shouldPass: reviewedProgression.shouldPass,
                    failureProtectionOutcome: reviewedProgression.shouldFinish
                        && !reviewedProgression.shouldPass
                        && session.purpose != .preview
                        ? (store.hasReadyCheckpointSet
                            ? .protectionRemainsOn
                            : .protectionTurnedOffForUnavailableCheckpoint)
                        : nil
                )
            )
        case let .terminal(
            questionIndex,
            correctAnswerCount,
            answer,
            result,
            didPass,
            actionErrorMessage
        ):
            let boundedCorrectAnswerCount = min(
                max(0, correctAnswerCount),
                session.questions.count
            )
            _currentQuestionIndex = State(
                initialValue: Self.boundedQuestionIndex(questionIndex, in: session)
            )
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
    }

    private static func boundedQuestionIndex(
        _ questionIndex: Int,
        in session: CheckpointSession
    ) -> Int {
        min(max(0, questionIndex), max(0, session.questions.count - 1))
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if chromePresentation.showsProgressHeader {
                            progressHeader
                                .id(AttemptScrollAnchor.question)
                                .transition(resolutionMotionPolicy.progressTransition)
                        }

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

                            if chromePresentation.primaryActionPlacement == .inline {
                                inlinePrimaryActionButton
                            }
                        }

                        questionPanel
                            .id(question.id)
                            .transition(questionTransition)

                        if chromePresentation.primaryActionPlacement == .inline,
                           resolutionPresentation == nil {
                            inlinePrimaryActionButton
                        }
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
                if chromePresentation.primaryActionPlacement == .pinned {
                    primaryActionBar
                }
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
        .modifier(
            CheckpointAttemptSensoryFeedbackModifier(
                resolutionFeedback: resolutionFeedback,
                answerFeedbackSignal: answerFeedbackSignal,
                choiceSelectionFeedbackSequence: choiceSelectionFeedbackSequence,
                protectionActionErrorSequence: protectionActionErrorSequence
            )
        )
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 11) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    questionProgressLabel
                        .fixedSize(horizontal: true, vertical: true)

                    Spacer(minLength: 8)

                    progressStatusLabel
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    questionProgressLabel
                    stackedProgressStatusLabel
                }
            }

            CheckpointClearanceRunway(
                presentation: runwayPresentation,
                motionPolicy: runwayMotionPolicy,
                currentMarkerNamespace: runwayCurrentMarkerNamespace
            )

            Text(sessionSubtitle)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checkpoint progress")
        .accessibilityValue("\(runwayPresentation.accessibilityValue) \(sessionSubtitle)")
        .accessibilityAddTraits(.isHeader)
    }

    private var questionProgressLabel: some View {
        Text("Question \(currentQuestionIndex + 1) of \(session.questions.count)")
            .font(.headline)
            .foregroundStyle(CheckpointTheme.text)
            .contentTransition(.numericText())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var progressStatusLabel: some View {
        Text(runwayPresentation.statusText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(progressStatusTint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stackedProgressStatusLabel: some View {
        Text(runwayPresentation.statusText.replacingOccurrences(of: " · ", with: "\n"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(progressStatusTint)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
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
        .checkpointChoiceLayoutAnchor(.questionPanel)
    }

    @ViewBuilder
    private var answerControls: some View {
        if question.format == .multipleChoice, !question.choices.isEmpty {
            VStack(spacing: 10) {
                ForEach(question.choices, id: \.self) { choice in
                    ChoiceButton(
                        title: choice,
                        state: choiceState(for: choice),
                        selectionNamespace: choiceSelectionNamespace,
                        selectionID: "choice-selection-\(question.id.uuidString)",
                        selectionPolicy: choiceSelectionPolicy,
                        layoutPolicy: choiceLayoutPolicy
                    ) {
                        selectChoice(choice)
                    }
                }
            }
            .checkpointChoiceLayoutAnchor(.answerGroup)
            .padding(.horizontal, -choiceLayoutPolicy.answerGroupHorizontalExpansion)
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

            primaryActionButton
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var primaryActionButton: some View {
        PrimaryActionButton(
            title: submitButtonTitle,
            systemImage: submitButtonIcon
        ) {
            handlePrimaryAction()
        }
        .disabled(
            hasCommittedResolutionAction
                || (checkedAnswer == nil && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        )
    }

    private var inlinePrimaryActionButton: some View {
        primaryActionButton
            .padding(.top, 2)
            .padding(.bottom, 12)
    }

    private var question: CheckpointQuestion {
        session.questions[currentQuestionIndex]
    }

    private var completedQuestionCount: Int {
        currentQuestionIndex + (checkedAnswer == nil ? 0 : 1)
    }

    private var runwayPresentation: CheckpointRunwayPresentation {
        CheckpointRunwayPresentation(
            questionCount: session.questions.count,
            currentQuestionIndex: currentQuestionIndex,
            answerResults: answerResults,
            requiredCorrectAnswerCount: session.unlockThreshold
        )
    }

    private var runwayMotionPolicy: CheckpointRunwayMotionPolicy {
        CheckpointRunwayMotionPolicy(reduceMotion: reduceMotion)
    }

    private var progressStatusTint: Color {
        switch runwayPresentation.statusTone {
        case .progress:
            return CheckpointTheme.muted
        case .secured:
            return CheckpointTheme.teal
        }
    }

    private var resolutionPresentation: CheckpointResolutionPresentation? {
        guard let checkedAnswer, checkedAnswer.shouldFinish else { return nil }
        return CheckpointResolutionPresentation(
            purpose: session.purpose,
            didMeetStandard: checkedAnswer.shouldPass,
            correctAnswerCount: correctAnswerCount,
            answeredQuestionCount: completedQuestionCount,
            questionCount: session.questions.count,
            requiredCorrectAnswerCount: session.unlockThreshold,
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

    private var choiceSelectionPolicy: CheckpointChoiceSelectionPolicy {
        CheckpointChoiceSelectionPolicy(reduceMotion: reduceMotion)
    }

    private var choiceLayoutPolicy: CheckpointChoiceLayoutPolicy {
        CheckpointChoiceLayoutPolicy(
            usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var chromePresentation: CheckpointAttemptChromePresentation {
        CheckpointAttemptChromePresentation(
            isResolved: resolutionPresentation != nil,
            usesAccessibilityTextSize: dynamicTypeSize.isAccessibilitySize
        )
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
        let updatedAnswerResults = CheckpointRunwayPresentation.recording(
            result,
            for: currentQuestionIndex,
            in: answerResults,
            questionCount: session.questions.count
        )

        let answeredQuestionCount = currentQuestionIndex + 1
        let progression = CheckpointAnswerProgression(
            session: session,
            correctAnswerCount: updatedCorrectCount,
            answeredQuestionCount: answeredQuestionCount
        )
        var failureProtectionOutcome: CheckpointFailureProtectionOutcome?

        if session.purpose != .preview {
            store.submitAnswer(
                question: question,
                answer: answer,
                result: result,
                grantsUnlock: false
            )

            if progression.shouldFinish && !progression.shouldPass {
                failureProtectionOutcome = workflow.resolveFailed(session)
            }
        }

        isAnswerFieldFocused = false
        let updateAnimation = progression.shouldFinish
            ? resolutionMotionPolicy.animation
            : CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)
        let nextFeedbackSequence = feedbackSequence + 1
        withAnimation(updateAnimation) {
            correctAnswerCount = updatedCorrectCount
            answerResults = updatedAnswerResults
            checkedAnswer = CheckedCheckpointAnswer(
                result: result,
                shouldFinish: progression.shouldFinish,
                shouldPass: progression.shouldPass,
                failureProtectionOutcome: failureProtectionOutcome
            )
            feedbackSequence = nextFeedbackSequence
            if !progression.shouldFinish {
                answerFeedbackSignal = CheckpointAnswerFeedbackSignal(
                    sequence: nextFeedbackSequence,
                    tone: CheckpointAnswerFeedbackSensoryTone(result: result)
                )
            }
        }
        if progression.shouldFinish {
            resolutionFeedback = progression.shouldPass ? .passed : .failed
        }
    }

    private func continueAfterCheckedAnswer() {
        guard let checkedAnswer else { return }

        guard !checkedAnswer.shouldFinish else {
            guard !hasCommittedResolutionAction else { return }
            if checkedAnswer.shouldPass {
                switch workflow.finishPassed(session) {
                case let .failed(message):
                    withAnimation(resolutionMotionPolicy.animation) {
                        protectionActionErrorMessage = message
                        protectionActionErrorSequence += 1
                    }
                    return
                case let .completed(earnedBreak):
                    protectionActionErrorMessage = nil
                    if let earnedBreak {
                        onEarnedBreak(earnedBreak)
                    }
                }
            }
            hasCommittedResolutionAction = true
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

    private func selectChoice(_ choice: String) {
        guard let decision = CheckpointChoiceSelectionPolicy.decision(
            currentAnswer: answer,
            requestedAnswer: choice,
            isLocked: checkedAnswer != nil
        ) else { return }

        withAnimation(choiceSelectionPolicy.animation) {
            answer = decision.answer
        }
        if decision.reportsSelectionFeedback {
            choiceSelectionFeedbackSequence += 1
        }
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
                    Text("LAST ANSWER")
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
                                ? "Last answer: \(feedbackPresentation.label)"
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

private struct CheckpointAttemptSensoryFeedbackModifier: ViewModifier {
    let resolutionFeedback: CheckpointResolutionFeedback?
    let answerFeedbackSignal: CheckpointAnswerFeedbackSignal?
    let choiceSelectionFeedbackSequence: Int
    let protectionActionErrorSequence: Int

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(trigger: resolutionFeedback) { _, newValue in
                switch newValue {
                case .passed:
                    return .success
                case .failed:
                    return .warning
                case nil:
                    return nil
                }
            }
            .sensoryFeedback(trigger: answerFeedbackSignal) { _, newValue in
                switch newValue?.tone {
                case .success:
                    return .success
                case .warning:
                    return .warning
                case nil:
                    return nil
                }
            }
            .sensoryFeedback(.selection, trigger: choiceSelectionFeedbackSequence)
            .sensoryFeedback(.error, trigger: protectionActionErrorSequence)
    }
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
    var selectionNamespace: Namespace.ID
    var selectionID: String
    var selectionPolicy: CheckpointChoiceSelectionPolicy
    var layoutPolicy: CheckpointChoiceLayoutPolicy
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            choiceLabel
                .padding(layoutPolicy.contentPadding)
                .frame(
                    maxWidth: .infinity,
                    minHeight: layoutPolicy.minimumControlHeight,
                    alignment: .leading
                )
                .background { choiceBackground }
                .overlay(
                    RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: state == .idle || state == .locked ? 1 : 1.4)
                )
                .checkpointChoiceLayoutAnchor(.control(title))
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .disabled(state.isLocked)
        .opacity(state == .locked ? 0.58 : 1)
        .animation(
            selectionPolicy.animation,
            value: state
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }

    @ViewBuilder
    private var choiceLabel: some View {
        switch layoutPolicy.style {
        case .inline:
            HStack(spacing: layoutPolicy.contentSpacing) {
                choiceIndicator
                choiceTitle
            }
        case .stacked:
            VStack(alignment: .leading, spacing: layoutPolicy.contentSpacing) {
                choiceIndicator
                choiceTitle
            }
        }
    }

    private var choiceIndicator: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(iconTint)
            .frame(width: layoutPolicy.indicatorWidth)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffectsRemoved(selectionPolicy.reduceMotion)
            .checkpointChoiceLayoutAnchor(.indicator(title))
    }

    private var choiceTitle: some View {
        Text(title)
            .font(layoutPolicy.titleFont)
            .foregroundStyle(CheckpointTheme.text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .checkpointChoiceLayoutAnchor(.title(title))
    }

    @ViewBuilder
    private var choiceBackground: some View {
        let shape = RoundedRectangle(
            cornerRadius: CheckpointTheme.compactCornerRadius,
            style: .continuous
        )

        ZStack {
            shape.fill(backgroundColor)

            if state == .selected {
                if selectionPolicy.usesLinkedSelectionPlate {
                    shape
                        .fill(CheckpointTheme.teal.opacity(0.12))
                        .matchedGeometryEffect(
                            id: selectionID,
                            in: selectionNamespace
                        )
                        .transition(.opacity)
                } else {
                    shape.fill(CheckpointTheme.teal.opacity(0.12))
                }
            }
        }
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
        case .correct:
            return CheckpointTheme.teal.opacity(0.18)
        case .incorrect:
            return CheckpointTheme.coral.opacity(0.12)
        case .idle, .selected, .locked:
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
