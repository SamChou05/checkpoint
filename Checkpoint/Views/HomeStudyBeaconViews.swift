import Foundation
import SwiftUI

enum HomeGoalOverviewReadyDisclosure: Equatable {
    case visible
    case suppressedByFirstWinJourney
}

enum HomeGoalOverviewDeadlineState: Equatable {
    case upcoming(daysRemaining: Int)
    case dueToday
    case overdue(days: Int)
}

struct HomeGoalOverviewDeadlinePresentation: Equatable {
    let state: HomeGoalOverviewDeadlineState
    let text: String
    let accessibilityLabel: String
}

enum HomeGoalOverviewRecoveryAction: Equatable, Identifiable {
    case retry(isInProgress: Bool)
    case editGoal

    var id: String {
        switch self {
        case .retry:
            "retry"
        case .editGoal:
            "edit-goal"
        }
    }

    var title: String {
        switch self {
        case let .retry(isInProgress):
            isInProgress ? "Trying again" : "Try again"
        case .editGoal:
            "Edit goal"
        }
    }

    var systemImage: String {
        switch self {
        case .retry:
            "arrow.clockwise"
        case .editGoal:
            "pencil"
        }
    }

    var isEnabled: Bool {
        switch self {
        case let .retry(isInProgress):
            !isInProgress
        case .editGoal:
            true
        }
    }
}

struct HomeGoalOverviewActionDispatcher {
    let retryQuestions: () -> Void
    let editGoal: () -> Void

    func perform(_ action: HomeGoalOverviewRecoveryAction) {
        guard action.isEnabled else { return }

        switch action {
        case .retry:
            retryQuestions()
        case .editGoal:
            editGoal()
        }
    }
}

enum HomeGoalOverviewCheckpointPhase: Hashable {
    case ready
    case preparing
    case recovery
    case incomplete
}

enum HomeGoalOverviewCheckpointState: Equatable {
    case ready(
        requiredCount: Int,
        disclosure: HomeGoalOverviewReadyDisclosure,
        isNewlyPrepared: Bool
    )
    case preparing(selectableCount: Int, requiredCount: Int, detail: String)
    case recovery(
        title: String,
        message: String,
        actions: [HomeGoalOverviewRecoveryAction]
    )
    case incomplete(selectableCount: Int, requiredCount: Int)

    var phase: HomeGoalOverviewCheckpointPhase {
        switch self {
        case .ready:
            .ready
        case .preparing:
            .preparing
        case .recovery:
            .recovery
        case .incomplete:
            .incomplete
        }
    }
}

enum HomeGoalOverviewGoalAction: Equatable {
    case none
    case editGoal
    case switchGoal
}

struct HomeGoalOverviewPresentation: Equatable {
    let goalTitle: String
    let deadline: HomeGoalOverviewDeadlinePresentation
    let passTargetText: String
    let passTargetAccessibilityLabel: String
    let checkpointState: HomeGoalOverviewCheckpointState
    let goalAction: HomeGoalOverviewGoalAction

    init(
        goal: Goal,
        readiness: GoalCheckpointReadiness,
        isGenerationBlockingPractice: Bool,
        generationFailure: QuestionGenerationFailureKind?,
        isRetryingGeneration: Bool,
        readyDisclosure: HomeGoalOverviewReadyDisclosure,
        isNewlyPrepared: Bool,
        unlockPolicy: UnlockPolicy,
        availableGoalCount: Int,
        generationStatusText: String,
        referenceDate: Date,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        goalTitle = goal.title
        deadline = Self.deadlinePresentation(
            deadline: goal.deadline,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        let requiredCorrectAnswers = unlockPolicy.requiredCorrectAnswers
        let questionCount = unlockPolicy.questionsPerSession
        passTargetText = "\(requiredCorrectAnswers) of \(questionCount) correct"
        passTargetAccessibilityLabel = "Pass target, \(requiredCorrectAnswers) correct answers out of \(questionCount) questions."

        if readiness.hasFullCheckpoint {
            checkpointState = .ready(
                requiredCount: readiness.requiredCount,
                disclosure: readyDisclosure,
                isNewlyPrepared: isNewlyPrepared
            )
        } else if case let .preparing(selectableCount, requiredCount) = readiness {
            checkpointState = .preparing(
                selectableCount: selectableCount,
                requiredCount: requiredCount,
                detail: generationStatusText
            )
        } else if isGenerationBlockingPractice {
            checkpointState = Self.recoveryState(
                failure: generationFailure,
                isRetryingGeneration: isRetryingGeneration,
                fallbackMessage: generationStatusText
            )
        } else {
            checkpointState = .incomplete(
                selectableCount: readiness.selectableCount,
                requiredCount: readiness.requiredCount
            )
        }

        switch availableGoalCount {
        case ...0:
            goalAction = .none
        case 1:
            goalAction = .editGoal
        default:
            goalAction = .switchGoal
        }
    }

    private static func recoveryState(
        failure: QuestionGenerationFailureKind?,
        isRetryingGeneration: Bool,
        fallbackMessage: String
    ) -> HomeGoalOverviewCheckpointState {
        var actions: [HomeGoalOverviewRecoveryAction] = []
        if failure?.allowsRetryWithoutChanges != false {
            actions.append(.retry(isInProgress: isRetryingGeneration))
        }
        if failure?.allowsEditingTopics == true {
            actions.append(.editGoal)
        }

        let fallback = fallbackMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return .recovery(
            title: failure?.title ?? "Questions aren't ready",
            message: failure?.message ?? (
                fallback.isEmpty
                    ? "Your checkpoint isn't ready yet. Try again in a little while."
                    : fallback
            ),
            actions: actions
        )
    }

    private static func deadlinePresentation(
        deadline: Date,
        referenceDate: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> HomeGoalOverviewDeadlinePresentation {
        var calendar = calendar
        calendar.locale = locale
        calendar.timeZone = timeZone

        let referenceDay = calendar.startOfDay(for: referenceDate)
        let deadlineDay = calendar.startOfDay(for: deadline)
        let dayDelta = calendar.dateComponents(
            [.day],
            from: referenceDay,
            to: deadlineDay
        ).day ?? 0
        let includesYear = calendar.component(.year, from: deadlineDay)
            != calendar.component(.year, from: referenceDay)
        let compactDate = formattedDate(
            deadlineDay,
            template: includesYear ? "MMMdy" : "MMMd",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let fullDate = formattedDate(
            deadlineDay,
            template: "MMMMdy",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        if dayDelta == 0 {
            return HomeGoalOverviewDeadlinePresentation(
                state: .dueToday,
                text: "Due today",
                accessibilityLabel: "Due today, \(fullDate)."
            )
        }

        if dayDelta < 0 {
            let daysOverdue = abs(dayDelta)
            let dayNoun = daysOverdue == 1 ? "day" : "days"
            return HomeGoalOverviewDeadlinePresentation(
                state: .overdue(days: daysOverdue),
                text: "Overdue · \(compactDate)",
                accessibilityLabel: "Overdue by \(daysOverdue) \(dayNoun). Due \(fullDate)."
            )
        }

        let dayNoun = dayDelta == 1 ? "day" : "days"
        return HomeGoalOverviewDeadlinePresentation(
            state: .upcoming(daysRemaining: dayDelta),
            text: "Due \(compactDate)",
            accessibilityLabel: "Due in \(dayDelta) \(dayNoun). Due \(fullDate)."
        )
    }

    private static func formattedDate(
        _ date: Date,
        template: String,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

enum HomeGoalOverviewMotionStyle: Equatable {
    case animated
    case identity
}

struct HomeGoalOverviewMotionPolicy: Equatable {
    let style: HomeGoalOverviewMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var animation: Animation? {
        style == .animated ? CheckpointMotion.change : nil
    }

    var transition: AnyTransition {
        switch style {
        case .animated:
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                removal: .opacity
            )
        case .identity:
            .identity
        }
    }
}

enum HomeGoalOverviewLayout: Equatable {
    case standard
    case firstWinCompact
}

struct HomeGoalOverviewCard<GoalControl: View>: View {
    let presentation: HomeGoalOverviewPresentation
    let reduceMotion: Bool
    let layout: HomeGoalOverviewLayout
    let retryQuestions: () -> Void
    let editGoal: () -> Void
    @ViewBuilder let goalControl: GoalControl

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        presentation: HomeGoalOverviewPresentation,
        reduceMotion: Bool,
        layout: HomeGoalOverviewLayout = .standard,
        retryQuestions: @escaping () -> Void,
        editGoal: @escaping () -> Void,
        @ViewBuilder goalControl: () -> GoalControl
    ) {
        self.presentation = presentation
        self.reduceMotion = reduceMotion
        self.layout = layout
        self.retryQuestions = retryQuestions
        self.editGoal = editGoal
        self.goalControl = goalControl()
    }

    var body: some View {
        cardContent
            .padding(layout == .firstWinCompact ? 12 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                CheckpointTheme.panel,
                                CheckpointTheme.panelRaised.opacity(0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CheckpointTheme.hairline, lineWidth: 1)
            }
            .shadow(color: CheckpointTheme.shadowCard, radius: 14, x: 0, y: 6)
            .animation(motionPolicy.animation, value: presentation.checkpointState)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch layout {
        case .standard:
            standardContent
        case .firstWinCompact:
            firstWinCompactContent
        }
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Text(presentation.goalTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            metadata

            checkpointStatus
                .id(presentation.checkpointState.phase)
                .transition(motionPolicy.transition)
        }
    }

    @ViewBuilder
    private var firstWinCompactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            compactHeader

            Text(presentation.goalTitle)
                .font(.headline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            compactMetadata

            if presentation.checkpointState.phase == .recovery {
                checkpointStatus
                    .id(presentation.checkpointState.phase)
                    .transition(motionPolicy.transition)
            }
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "scope")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 25, height: 25)
                    .background(
                        CheckpointTheme.teal.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .accessibilityHidden(true)

                Text("CURRENT FOCUS")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(CheckpointTheme.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current focus")

            Spacer(minLength: 4)
            goalControl
        }
    }

    private var compactMetadata: some View {
        HStack(spacing: 8) {
            compactMetadataItem(
                value: presentation.deadline.text,
                systemImage: deadlineSystemImage,
                tint: deadlineTint,
                accessibilityLabel: presentation.deadline.accessibilityLabel
            )

            compactMetadataItem(
                value: presentation.passTargetText,
                systemImage: "checkmark.circle",
                tint: CheckpointTheme.blue,
                accessibilityLabel: presentation.passTargetAccessibilityLabel
            )
        }
    }

    private func compactMetadataItem(
        value: String,
        systemImage: String,
        tint: Color,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.70),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(CheckpointTheme.controlStroke.opacity(0.64), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                scopeIdentity
                goalControl
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    scopeIdentity
                    Spacer(minLength: 8)
                    goalControl
                }

                VStack(alignment: .leading, spacing: 10) {
                    scopeIdentity
                    goalControl
                }
            }
        }
    }

    private var scopeIdentity: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                scopeLabel
            } else {
                HStack(spacing: 10) {
                    scopeIcon
                    scopeLabel
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current focus")
    }

    private var scopeIcon: some View {
        Image(systemName: "scope")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 38, height: 38)
            .background(
                CheckpointTheme.teal.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var scopeLabel: some View {
        Text("CURRENT FOCUS")
            .font(.caption2.weight(.bold))
            .tracking(0.95)
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var metadata: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityMetadata
        } else if usesStackedMetadataLayout {
            VStack(spacing: 10) {
                deadlineMetadata
                passTargetMetadata
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    deadlineMetadata
                        .frame(height: 86)
                    passTargetMetadata
                        .frame(height: 86)
                }
                .frame(width: 280)
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 10) {
                    deadlineMetadata
                    passTargetMetadata
                }
            }
        }
    }

    private var accessibilityMetadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            accessibilityMetadataRow(
                label: "Deadline",
                value: presentation.deadline.text,
                accessibilityLabel: presentation.deadline.accessibilityLabel
            )

            Divider()
                .overlay(CheckpointTheme.hairline)
                .accessibilityHidden(true)

            accessibilityMetadataRow(
                label: "Pass target",
                value: presentation.passTargetText,
                accessibilityLabel: presentation.passTargetAccessibilityLabel
            )
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(CheckpointTheme.controlStroke.opacity(0.72), lineWidth: 1)
        }
    }

    private func accessibilityMetadataRow(
        label: String,
        value: String,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var deadlineMetadata: some View {
        metadataItem(
            label: "DEADLINE",
            value: presentation.deadline.text,
            systemImage: deadlineSystemImage,
            tint: deadlineTint,
            accessibilityLabel: presentation.deadline.accessibilityLabel
        )
    }

    private var passTargetMetadata: some View {
        metadataItem(
            label: "PASS TARGET",
            value: presentation.passTargetText,
            systemImage: "checkmark.circle",
            tint: CheckpointTheme.blue,
            accessibilityLabel: presentation.passTargetAccessibilityLabel
        )
    }

    private func metadataItem(
        label: String,
        value: String,
        systemImage: String,
        tint: Color,
        accessibilityLabel: String
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.25)
                    .foregroundStyle(CheckpointTheme.muted)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CheckpointTheme.controlStroke.opacity(0.72), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var checkpointStatus: some View {
        switch presentation.checkpointState {
        case let .ready(requiredCount, disclosure, isNewlyPrepared):
            if disclosure == .visible {
                readyStatus(requiredCount: requiredCount, isNewlyPrepared: isNewlyPrepared)
            }
        case let .preparing(selectableCount, requiredCount, detail):
            preparingStatus(
                selectableCount: selectableCount,
                requiredCount: requiredCount,
                detail: detail
            )
        case let .recovery(title, message, actions):
            recoveryStatus(title: title, message: message, actions: actions)
        case let .incomplete(selectableCount, requiredCount):
            incompleteStatus(selectableCount: selectableCount, requiredCount: requiredCount)
        }
    }

    private func readyStatus(requiredCount: Int, isNewlyPrepared: Bool) -> some View {
        let icon = Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .symbolEffect(.bounce, options: .nonRepeating, value: isNewlyPrepared)
            .symbolEffectsRemoved(reduceMotion || !isNewlyPrepared)
            .accessibilityHidden(true)
        let copy = VStack(alignment: .leading, spacing: 2) {
            Text(isNewlyPrepared ? "Questions ready" : "Checkpoint ready")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)

            Text("Your next \(requiredCount)-question checkpoint is ready.")
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                copy
            } else {
                HStack(alignment: .center, spacing: 11) {
                    icon
                    copy
                    Spacer(minLength: 0)
                }
            }
        }
        .statusSurface(tint: CheckpointTheme.teal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(isNewlyPrepared ? "Questions ready" : "Checkpoint ready"). Your next \(requiredCount)-question checkpoint is ready."
        )
    }

    private func preparingStatus(
        selectableCount: Int,
        requiredCount: Int,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    preparingCopy(detail: detail)
                } else {
                    HStack(alignment: .top, spacing: 11) {
                        ProgressView()
                            .tint(CheckpointTheme.teal)
                            .accessibilityHidden(true)
                        preparingCopy(detail: detail)
                    }
                }
            }

            ProgressView(
                value: Double(selectableCount),
                total: Double(max(1, requiredCount))
            )
            .tint(CheckpointTheme.teal)
            .accessibilityHidden(true)

            Text("\(selectableCount) of \(requiredCount) checkpoint questions ready")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
                .contentTransition(.numericText())
        }
        .statusSurface(tint: CheckpointTheme.teal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Preparing checkpoint. \(detail) \(selectableCount) of \(requiredCount) checkpoint questions ready."
        )
    }

    private func preparingCopy(detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Preparing checkpoint")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)

            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func recoveryStatus(
        title: String,
        message: String,
        actions: [HomeGoalOverviewRecoveryAction]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    recoveryCopy(title: title, message: message)
                } else {
                    HStack(alignment: .top, spacing: 11) {
                        recoveryIcon
                        recoveryCopy(title: title, message: message)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title). \(message)")

            recoveryControls(actions)
        }
        .statusSurface(tint: CheckpointTheme.amber)
    }

    private var recoveryIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(CheckpointTheme.amber)
            .accessibilityHidden(true)
    }

    private func recoveryCopy(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)

            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func recoveryControls(_ actions: [HomeGoalOverviewRecoveryAction]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                recoveryButtons(actions)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    recoveryButtons(actions)
                }

                VStack(spacing: 10) {
                    recoveryButtons(actions)
                }
            }
        }
    }

    private func recoveryButtons(_ actions: [HomeGoalOverviewRecoveryAction]) -> some View {
        ForEach(actions) { action in
            SecondaryActionButton(
                title: action.title,
                systemImage: action.systemImage
            ) {
                actionDispatcher.perform(action)
            }
            .disabled(!action.isEnabled)
        }
    }

    private func incompleteStatus(selectableCount: Int, requiredCount: Int) -> some View {
        let icon = Image(systemName: "circle.dotted")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(CheckpointTheme.blue)
            .accessibilityHidden(true)
        let copy = VStack(alignment: .leading, spacing: 3) {
            Text("Checkpoint not ready")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)

            Text("\(selectableCount) of \(requiredCount) checkpoint questions ready")
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
        }

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                copy
            } else {
                HStack(alignment: .top, spacing: 11) {
                    icon
                    copy
                    Spacer(minLength: 0)
                }
            }
        }
        .statusSurface(tint: CheckpointTheme.blue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Checkpoint not ready. \(selectableCount) of \(requiredCount) checkpoint questions ready."
        )
    }

    private var deadlineSystemImage: String {
        switch presentation.deadline.state {
        case .upcoming:
            "calendar"
        case .dueToday:
            "calendar.badge.clock"
        case .overdue:
            "calendar.badge.exclamationmark"
        }
    }

    private var deadlineTint: Color {
        switch presentation.deadline.state {
        case .upcoming:
            CheckpointTheme.teal
        case .dueToday:
            CheckpointTheme.amber
        case .overdue:
            CheckpointTheme.coral
        }
    }

    private var motionPolicy: HomeGoalOverviewMotionPolicy {
        HomeGoalOverviewMotionPolicy(reduceMotion: reduceMotion)
    }

    private var usesStackedMetadataLayout: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge
    }

    private var actionDispatcher: HomeGoalOverviewActionDispatcher {
        HomeGoalOverviewActionDispatcher(
            retryQuestions: retryQuestions,
            editGoal: editGoal
        )
    }
}

private extension View {
    func statusSurface(tint: Color) -> some View {
        padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                tint.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(tint.opacity(0.14), lineWidth: 1)
            }
    }
}

enum HomeStudyBeaconKind: Equatable {
    case firstWinJourney
    case weeklySignal
}

enum HomeStudyBeaconPresentation: Equatable {
    case firstWinJourney(HomeFirstWinJourneyPresentation)
    case weeklySignal

    var kind: HomeStudyBeaconKind {
        switch self {
        case .firstWinJourney:
            .firstWinJourney
        case .weeklySignal:
            .weeklySignal
        }
    }

    var showsNextFocus: Bool {
        kind == .weeklySignal
    }

    var suppressesReadyGoalDisclosure: Bool {
        kind == .firstWinJourney
    }

    init(
        hasPracticeForActiveGoal: Bool,
        firstWinJourney: HomeFirstWinJourneyPresentation
    ) {
        self = hasPracticeForActiveGoal
            ? .weeklySignal
            : .firstWinJourney(firstWinJourney)
    }
}

enum HomeFirstWinJourneyNodeID: String, CaseIterable, Equatable {
    case checkpoint
    case protectedApps
    case protection

    var title: String {
        switch self {
        case .checkpoint:
            "Checkpoint"
        case .protectedApps:
            "Apps & websites"
        case .protection:
            "Protection"
        }
    }

    var systemImage: String {
        switch self {
        case .checkpoint:
            "checkmark.circle"
        case .protectedApps:
            "checklist"
        case .protection:
            "shield.checkered"
        }
    }

    var compactTitle: String {
        switch self {
        case .checkpoint:
            "Checkpoint"
        case .protectedApps:
            "Apps & sites"
        case .protection:
            "Protection"
        }
    }
}

enum HomeFirstWinJourneyNodeState: Equatable {
    case complete
    case ready
    case working
    case attention
    case blocked
}

enum HomeFirstWinJourneyConnectorAxis: Equatable {
    case horizontal
    case vertical
}

enum HomeFirstWinJourneyMotionStyle: Equatable {
    case animated
    case identity
}

struct HomeFirstWinJourneyMotionPolicy: Equatable {
    let style: HomeFirstWinJourneyMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var connectorAnimation: Animation? {
        style == .animated ? CheckpointMotion.reveal : nil
    }
}

struct HomeFirstWinJourneyNode: Identifiable, Equatable {
    let id: HomeFirstWinJourneyNodeID
    let state: HomeFirstWinJourneyNodeState
    let status: String
    let isCurrent: Bool
}

struct HomeFirstWinJourneyConnectorProgress: Equatable {
    private(set) var filledConnectorIDs: Set<HomeFirstWinJourneyNodeID>

    init(nodes: [HomeFirstWinJourneyNode]) {
        filledConnectorIDs = Set(
            nodes.dropLast().compactMap { node in
                node.state == .complete ? node.id : nil
            }
        )
    }

    func isFilled(after node: HomeFirstWinJourneyNode) -> Bool {
        filledConnectorIDs.contains(node.id)
    }
}

enum HomeFirstWinJourneyAction: Equatable {
    case chooseApps
    case reviewProtection
    case prepareAndProtect
    case startProtection(isLoading: Bool)
    case reviewSelection

    var title: String {
        switch self {
        case .chooseApps:
            "Choose apps & sites"
        case .reviewProtection:
            "Review protection"
        case .prepareAndProtect:
            "Prepare & turn on protection"
        case let .startProtection(isLoading):
            isLoading ? "Turning on protection" : "Turn on protection"
        case .reviewSelection:
            "Review selection"
        }
    }

    var systemImage: String {
        switch self {
        case .chooseApps:
            "checklist"
        case .reviewProtection, .reviewSelection:
            "slider.horizontal.3"
        case .prepareAndProtect:
            "wand.and.sparkles"
        case .startProtection:
            "shield"
        }
    }

    var isLoading: Bool {
        if case let .startProtection(isLoading) = self {
            return isLoading
        }
        return false
    }

    var isProminent: Bool {
        self != .reviewSelection
    }

    var accessibilityHint: String {
        switch self {
        case .chooseApps:
            "Opens the app and website picker"
        case .reviewProtection:
            "Opens protection settings"
        case .prepareAndProtect:
            "Builds the remaining questions, then turns on protection"
        case .startProtection:
            "Places your checkpoint before the apps and websites you select"
        case .reviewSelection:
            "Opens your protected app and website selection"
        }
    }
}

enum HomeFirstWinJourneyPhase: Hashable {
    case screenTimeUnavailable
    case screenTimeAuthorizationRequired
    case requestingScreenTime
    case screenTimePermissionRequired
    case chooseApps
    case protectionNeedsAttention
    case preparingCheckpoint
    case checkpointNeedsAttention
    case checkpointNotReady
    case readyToProtect
    case startingProtection
    case firstCheckpointReady
}

struct HomeFirstWinJourneyPresentation: Equatable {
    let phase: HomeFirstWinJourneyPhase
    let nodes: [HomeFirstWinJourneyNode]
    let headline: String
    let title: String
    let detail: String
    let action: HomeFirstWinJourneyAction?
    let completedStepCount: Int

    init(
        hasReadyCheckpointSet: Bool,
        isPreparingCheckpoint: Bool,
        isCheckpointBlockedByGeneration: Bool,
        selectableQuestionCount: Int,
        requiredQuestionCount: Int,
        authorizationState: ScreenTimeController.AuthorizationState,
        setupState: ScreenTimeController.SetupState,
        hasSelection: Bool,
        isProtectionActive: Bool,
        isStartingProtection: Bool,
        protectionErrorMessage: String?,
        protectedAppsSummary: String,
        requiredCorrectAnswers: Int,
        questionCount: Int,
        unlockMinutes: Int
    ) {
        let hasAuthorizedSelection = isProtectionActive || (
            (authorizationState == .approved || authorizationState == .approvedWithDataAccess)
                && hasSelection
        )
        let normalizedError = protectionErrorMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasProtectionError = normalizedError?.isEmpty == false

        if setupState == .unavailable || authorizationState == .unavailable {
            phase = .screenTimeUnavailable
        } else if authorizationState == .requesting {
            phase = .requestingScreenTime
        } else if authorizationState == .unresolved || authorizationState == .notDetermined {
            phase = .screenTimeAuthorizationRequired
        } else if authorizationState == .denied || authorizationState == .failed {
            phase = .screenTimePermissionRequired
        } else if !hasAuthorizedSelection {
            phase = .chooseApps
        } else if setupState == .failed || hasProtectionError {
            phase = .protectionNeedsAttention
        } else if !hasReadyCheckpointSet {
            if isCheckpointBlockedByGeneration {
                phase = .checkpointNeedsAttention
            } else if isPreparingCheckpoint {
                phase = .preparingCheckpoint
            } else {
                phase = .checkpointNotReady
            }
        } else if isProtectionActive {
            phase = .firstCheckpointReady
        } else if isStartingProtection {
            phase = .startingProtection
        } else {
            phase = .readyToProtect
        }

        let currentNodeID: HomeFirstWinJourneyNodeID? = switch phase {
        case .screenTimeUnavailable,
             .screenTimeAuthorizationRequired,
             .requestingScreenTime,
             .screenTimePermissionRequired,
             .chooseApps:
            .protectedApps
        case .protectionNeedsAttention, .readyToProtect, .startingProtection:
            .protection
        case .preparingCheckpoint, .checkpointNeedsAttention, .checkpointNotReady:
            .checkpoint
        case .firstCheckpointReady:
            nil
        }

        let checkpointState: HomeFirstWinJourneyNodeState
        let checkpointStatus: String
        if hasReadyCheckpointSet {
            checkpointState = .complete
            checkpointStatus = "\(requiredQuestionCount) questions ready"
        } else if isCheckpointBlockedByGeneration {
            checkpointState = .attention
            checkpointStatus = "Needs attention"
        } else if isPreparingCheckpoint {
            checkpointState = .working
            checkpointStatus = "\(selectableQuestionCount) of \(requiredQuestionCount) ready"
        } else {
            checkpointState = .attention
            checkpointStatus = "Needs questions"
        }

        let appsState: HomeFirstWinJourneyNodeState
        let appsStatus: String
        switch phase {
        case .screenTimeUnavailable:
            appsState = .attention
            appsStatus = "iPhone required"
        case .requestingScreenTime:
            appsState = .working
            appsStatus = "Requesting access"
        case .screenTimeAuthorizationRequired, .screenTimePermissionRequired:
            appsState = .attention
            appsStatus = "Allow Screen Time"
        case .chooseApps:
            appsState = .ready
            appsStatus = "Choose apps or sites"
        default:
            if hasAuthorizedSelection {
                appsState = .complete
                appsStatus = protectedAppsSummary
            } else {
                appsState = .blocked
                appsStatus = "Waiting"
            }
        }

        let protectionState: HomeFirstWinJourneyNodeState
        let protectionStatus: String
        if isProtectionActive && phase == .firstCheckpointReady {
            protectionState = .complete
            protectionStatus = "On"
        } else {
            switch phase {
            case .protectionNeedsAttention:
                protectionState = .attention
                protectionStatus = "Needs attention"
            case .startingProtection:
                protectionState = .working
                protectionStatus = "Turning on"
            case .readyToProtect:
                protectionState = .ready
                protectionStatus = "Ready to start"
            default:
                protectionState = .blocked
                protectionStatus = "Waiting"
            }
        }

        nodes = [
            HomeFirstWinJourneyNode(
                id: .checkpoint,
                state: checkpointState,
                status: checkpointStatus,
                isCurrent: currentNodeID == .checkpoint
            ),
            HomeFirstWinJourneyNode(
                id: .protectedApps,
                state: appsState,
                status: appsStatus,
                isCurrent: currentNodeID == .protectedApps
            ),
            HomeFirstWinJourneyNode(
                id: .protection,
                state: protectionState,
                status: protectionStatus,
                isCurrent: currentNodeID == .protection
            )
        ]
        completedStepCount = nodes.filter { $0.state == .complete }.count
        headline = phase == .firstCheckpointReady
            ? "Your first win is ready"
            : "Set up your first win"

        switch phase {
        case .screenTimeUnavailable:
            title = "Continue on iPhone"
            detail = "Protection uses Screen Time and is available in the iPhone app."
            action = nil
        case .screenTimeAuthorizationRequired:
            title = "Connect Screen Time"
            detail = "Allow Screen Time access to protect only what you choose."
            action = nil
        case .requestingScreenTime:
            title = "Connecting Screen Time"
            detail = "Finish the permission request, then choose what you want to protect."
            action = nil
        case .screenTimePermissionRequired:
            title = "Screen Time needs attention"
            detail = normalizedError ?? "Allow Screen Time access before setting up protection."
            action = nil
        case .chooseApps:
            title = "Choose what to protect"
            detail = "Choose the apps and websites you want behind practice."
            action = .chooseApps
        case .protectionNeedsAttention:
            title = "Protection needs attention"
            detail = normalizedError ?? "Review your protected selection before continuing."
            action = .reviewProtection
        case .preparingCheckpoint:
            title = "Preparing your checkpoint"
            detail = "\(selectableQuestionCount) of \(requiredQuestionCount) questions are ready. We’ll move you forward when the set is complete."
            action = nil
        case .checkpointNeedsAttention:
            title = "Finish your checkpoint setup"
            detail = "Use the checkpoint options above, then your first-win setup will continue here."
            action = nil
        case .checkpointNotReady:
            title = "Your checkpoint needs more questions"
            detail = "Prepare the rest of the set, then Checkpoint will turn protection on."
            action = .prepareAndProtect
        case .readyToProtect:
            title = "Turn on protection"
            detail = "Your checkpoint and protected selection are ready."
            action = .startProtection(isLoading: false)
        case .startingProtection:
            title = "Turning on protection"
            detail = "Checkpoint is verifying your question set and protected selection."
            action = .startProtection(isLoading: true)
        case .firstCheckpointReady:
            let questionNoun = questionCount == 1 ? "question" : "questions"
            title = "Open a protected app or website"
            detail = "Clear \(requiredCorrectAnswers) of \(questionCount) \(questionNoun) to earn a \(unlockMinutes)-minute break."
            action = .reviewSelection
        }
    }

    var progressText: String {
        completedStepCount == nodes.count
            ? "SETUP COMPLETE"
            : "\(completedStepCount) OF \(nodes.count) READY"
    }
}

struct HomeFirstWinJourneyCard: View {
    let presentation: HomeFirstWinJourneyPresentation
    let reduceMotion: Bool
    let manageApps: () -> Void
    let startProtection: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var connectorProgress: HomeFirstWinJourneyConnectorProgress

    init(
        presentation: HomeFirstWinJourneyPresentation,
        reduceMotion: Bool,
        manageApps: @escaping () -> Void,
        startProtection: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.reduceMotion = reduceMotion
        self.manageApps = manageApps
        self.startProtection = startProtection
        _connectorProgress = State(
            initialValue: HomeFirstWinJourneyConnectorProgress(nodes: presentation.nodes)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactJourneyLayout ? 6 : 12) {
            sectionHeader

            CheckpointHeroSurface(
                glowColor: glowColor,
                contentPadding: usesCompactJourneyLayout ? 12 : 18
            ) {
                journeyContent
                .animation(
                    CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                    value: presentation.phase
                )
            }
        }
        .padding(.horizontal, 4)
        .onChange(of: presentation.nodes) { _, nodes in
            updateConnectorProgress(for: nodes)
        }
    }

    @ViewBuilder
    private var journeyContent: some View {
        if usesCompactJourneyLayout {
            VStack(alignment: .leading, spacing: 9) {
                compactIdentity
                compactJourneyRail
                currentStep
                    .id(presentation.phase)
                    .transition(currentStepTransition)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                identity
                journeyRail

                Divider()
                    .overlay(CheckpointTheme.heroDivider)
                    .accessibilityHidden(true)

                currentStep
                    .id(presentation.phase)
                    .transition(currentStepTransition)
            }
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("FIRST WIN")
                .font(.caption2.weight(.bold))
                .tracking(0.95)
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 4)

            Text(presentation.progressText)
                .font(.caption2.weight(.bold))
                .tracking(0.55)
                .foregroundStyle(CheckpointTheme.teal)
                .contentTransition(.numericText())
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private var identity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                identityIcon
                identityCopy
            }
        } else {
            HStack(alignment: .center, spacing: 13) {
                identityIcon
                identityCopy
            }
        }
    }

    private var identityIcon: some View {
        Image(systemName: "flag.checkered")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(CheckpointTheme.ink)
            .frame(width: 46, height: 46)
            .background(CheckpointTheme.mint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .symbolEffect(.bounce, options: .nonRepeating, value: presentation.phase)
            .symbolEffectsRemoved(reduceMotion)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var compactIdentity: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CheckpointTheme.ink)
                .frame(width: 28, height: 28)
                .background(
                    CheckpointTheme.mint,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .symbolEffect(.bounce, options: .nonRepeating, value: presentation.phase)
                .symbolEffectsRemoved(reduceMotion)
                .accessibilityHidden(true)

            Text(presentation.headline)
                .font(.headline.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
    }

    private var identityCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("YOUR PATH")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(CheckpointTheme.heroSuccess)

            Text(presentation.headline)
                .font(.title3.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.headline)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var journeyRail: some View {
        if usesVerticalJourneyRail {
            verticalJourneyRail
        } else {
            horizontalJourneyRail
        }
    }

    private var horizontalJourneyRail: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    connector(
                        after: presentation.nodes[index - 1],
                        axis: .horizontal
                    )
                        .frame(width: 16, height: 2)
                        .padding(.top, 15)
                }

                horizontalNode(node, index: index)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var compactJourneyRail: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    connector(
                        after: presentation.nodes[index - 1],
                        axis: .horizontal
                    )
                        .frame(width: 12, height: 2)
                        .padding(.top, 11)
                }

                VStack(spacing: 3) {
                    nodeBadge(node, size: 24)

                    Text(node.id.compactTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(
                            node.isCurrent
                                ? CheckpointTheme.heroText
                                : CheckpointTheme.heroMuted
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nodeAccessibilityLabel(node, index: index))
            }
        }
    }

    private var verticalJourneyRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                verticalNode(node, index: index)

                if index < presentation.nodes.count - 1 {
                    connector(after: node, axis: .vertical)
                        .frame(width: 2, height: 16)
                        .padding(.leading, 15)
                        .padding(.vertical, 4)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func horizontalNode(
        _ node: HomeFirstWinJourneyNode,
        index: Int
    ) -> some View {
        VStack(spacing: 7) {
            nodeBadge(node)

            VStack(spacing: 2) {
                Text(node.id.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(node.isCurrent ? CheckpointTheme.heroText : CheckpointTheme.heroMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(node.status)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(nodeTint(node))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nodeAccessibilityLabel(node, index: index))
    }

    private func verticalNode(
        _ node: HomeFirstWinJourneyNode,
        index: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            nodeBadge(node)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.id.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(node.isCurrent ? CheckpointTheme.heroText : CheckpointTheme.heroMuted)

                Text(node.status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(nodeTint(node))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nodeAccessibilityLabel(node, index: index))
    }

    private func nodeBadge(
        _ node: HomeFirstWinJourneyNode,
        size: CGFloat = 32
    ) -> some View {
        ZStack {
            Circle()
                .fill(nodeTint(node).opacity(node.isCurrent ? 0.20 : 0.11))

            Circle()
                .stroke(
                    node.isCurrent ? nodeTint(node) : CheckpointTheme.heroDivider,
                    lineWidth: node.isCurrent ? 1.5 : 1
                )

            if node.state == .working {
                ProgressView()
                    .controlSize(.small)
                    .tint(nodeTint(node))
            } else {
                Image(systemName: nodeSystemImage(node))
                    .font(.system(size: size == 32 ? 12 : 10, weight: .bold))
                    .foregroundStyle(nodeTint(node))
                    .symbolEffect(.bounce, options: .nonRepeating, value: presentation.phase)
                    .symbolEffectsRemoved(reduceMotion || !node.isCurrent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func connector(
        after node: HomeFirstWinJourneyNode,
        axis: HomeFirstWinJourneyConnectorAxis
    ) -> some View {
        let isFilled = connectorProgress.isFilled(after: node)

        ZStack {
            Rectangle()
                .fill(CheckpointTheme.heroDivider)

            switch axis {
            case .horizontal:
                Rectangle()
                    .fill(CheckpointTheme.heroSuccess.opacity(0.68))
                    .scaleEffect(x: isFilled ? 1 : 0, y: 1, anchor: .leading)
            case .vertical:
                Rectangle()
                    .fill(CheckpointTheme.heroSuccess.opacity(0.68))
                    .scaleEffect(x: 1, y: isFilled ? 1 : 0, anchor: .top)
            }
        }
        .animation(motionPolicy.connectorAnimation, value: isFilled)
        .accessibilityHidden(true)
    }

    private func updateConnectorProgress(for nodes: [HomeFirstWinJourneyNode]) {
        connectorProgress = HomeFirstWinJourneyConnectorProgress(nodes: nodes)
    }

    private var currentStep: some View {
        VStack(alignment: .leading, spacing: usesCompactJourneyLayout ? 9 : 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP")
                    .font(.caption2.weight(.bold))
                    .tracking(0.75)
                    .foregroundStyle(currentTint)

                Text(presentation.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.heroText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if let action = presentation.action {
                journeyAction(action)
            }
        }
        .padding(usesCompactJourneyLayout ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            currentTint.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(currentTint.opacity(0.20), lineWidth: 1)
        }
    }

    private func journeyAction(_ action: HomeFirstWinJourneyAction) -> some View {
        Button {
            switch action {
            case .chooseApps, .reviewProtection, .reviewSelection:
                manageApps()
            case .prepareAndProtect, .startProtection:
                startProtection()
            }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 9) {
                        actionIcon(action)
                        Text(action.title)
                    }
                } else {
                    HStack(spacing: 8) {
                        actionIcon(action)
                        Text(action.title)
                        Spacer(minLength: 0)
                        if !action.isLoading {
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(action.isProminent ? CheckpointTheme.ink : CheckpointTheme.heroText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(
                .vertical,
                dynamicTypeSize.isAccessibilitySize
                    ? 16
                    : (usesCompactJourneyLayout ? 10 : 13)
            )
            .frame(minHeight: 44)
            .background(
                action.isProminent ? CheckpointTheme.heroSuccess : CheckpointTheme.heroSubtleFill,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(action.isProminent ? Color.clear : CheckpointTheme.heroDivider, lineWidth: 1)
            }
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .disabled(action.isLoading)
        .accessibilityHint(action.accessibilityHint)
    }

    @ViewBuilder
    private func actionIcon(_ action: HomeFirstWinJourneyAction) -> some View {
        if action.isLoading {
            ProgressView()
                .tint(CheckpointTheme.ink)
                .accessibilityHidden(true)
        } else {
            Image(systemName: action.systemImage)
                .font(.system(size: 15, weight: .bold))
                .accessibilityHidden(true)
        }
    }

    private func nodeSystemImage(_ node: HomeFirstWinJourneyNode) -> String {
        switch node.state {
        case .complete:
            "checkmark"
        case .attention:
            "exclamationmark"
        case .ready, .working, .blocked:
            node.id.systemImage
        }
    }

    private func nodeTint(_ node: HomeFirstWinJourneyNode) -> Color {
        switch node.state {
        case .complete:
            CheckpointTheme.heroSuccess
        case .ready:
            node.isCurrent ? CheckpointTheme.heroSuccess : CheckpointTheme.heroInfo
        case .working:
            CheckpointTheme.heroInfo
        case .attention:
            CheckpointTheme.heroWarning
        case .blocked:
            CheckpointTheme.heroMuted
        }
    }

    private func nodeAccessibilityLabel(
        _ node: HomeFirstWinJourneyNode,
        index: Int
    ) -> String {
        let current = node.isCurrent ? " Current step." : ""
        return "Step \(index + 1) of \(presentation.nodes.count), \(node.id.title), \(node.status).\(current)"
    }

    private var currentTint: Color {
        switch presentation.phase {
        case .screenTimeUnavailable:
            CheckpointTheme.heroMuted
        case .screenTimePermissionRequired,
             .protectionNeedsAttention,
             .checkpointNeedsAttention,
             .checkpointNotReady:
            CheckpointTheme.heroWarning
        case .requestingScreenTime, .preparingCheckpoint, .startingProtection:
            CheckpointTheme.heroInfo
        case .screenTimeAuthorizationRequired, .chooseApps, .readyToProtect, .firstCheckpointReady:
            CheckpointTheme.heroSuccess
        }
    }

    private var glowColor: Color {
        switch presentation.phase {
        case .screenTimePermissionRequired,
             .protectionNeedsAttention,
             .checkpointNeedsAttention,
             .checkpointNotReady:
            CheckpointTheme.heroWarning
        case .requestingScreenTime, .preparingCheckpoint, .startingProtection:
            CheckpointTheme.heroInfo
        case .screenTimeUnavailable:
            CheckpointTheme.heroTrack
        case .screenTimeAuthorizationRequired, .chooseApps, .readyToProtect, .firstCheckpointReady:
            CheckpointTheme.mint
        }
    }

    private var currentStepTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
    }

    private var motionPolicy: HomeFirstWinJourneyMotionPolicy {
        HomeFirstWinJourneyMotionPolicy(reduceMotion: reduceMotion)
    }

    private var usesVerticalJourneyRail: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge ||
            dynamicTypeSize.isAccessibilitySize
    }

    private var usesCompactJourneyLayout: Bool {
        dynamicTypeSize == .xSmall ||
            dynamicTypeSize == .small ||
            dynamicTypeSize == .medium ||
            dynamicTypeSize == .large
    }
}

enum HomeWeeklySignalLayout: Equatable {
    case regular
    case stacked
}

struct HomeWeeklySignalLayoutPolicy: Equatable {
    static let compactViewportMaximum: CGFloat = 320

    let viewportWidth: CGFloat
    let dynamicTypeSize: DynamicTypeSize

    var layout: HomeWeeklySignalLayout {
        if Self.usesCompactHomeMargins(viewportWidth: viewportWidth) {
            return .stacked
        }

        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            return .regular
        default:
            return .stacked
        }
    }

    var contentPadding: CGFloat {
        Self.usesCompactHomeMargins(viewportWidth: viewportWidth) ? 16 : 18
    }

    var stacksSupportingMetricLabels: Bool {
        switch dynamicTypeSize {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4,
             .accessibility5:
            true
        default:
            false
        }
    }

    static func usesCompactHomeMargins(viewportWidth: CGFloat) -> Bool {
        viewportWidth <= compactViewportMaximum
    }
}

enum HomeWeeklySignalMotionStyle: Equatable {
    case animated
    case identity
}

struct HomeWeeklySignalMotionPolicy {
    let style: HomeWeeklySignalMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var animation: Animation? {
        style == .animated ? CheckpointMotion.change : nil
    }

    var conditionalTransition: AnyTransition {
        style == .animated ? .opacity : .identity
    }

    var permitsSignalEffect: Bool {
        style == .animated
    }
}

struct HomeWeeklySignalMetricPresentation: Equatable, Identifiable {
    enum ID: Equatable, Hashable {
        case questions
        case accuracy
        case checkpointsCleared
        case practicedSkills
        case currentStreak
    }

    let id: ID
    let value: String
    let label: String
    let numericValue: Double
    let accessibilityValue: String
}

struct HomeWeeklySignalHeroPresentation: Equatable {
    static let actionLabel = "View weekly impact"
    static let emptyAccessibilityValue =
        "No checkpoint activity this week. Your next checkpoint will start this week's impact view."

    let hasActivity: Bool
    let title: String
    let questions: HomeWeeklySignalMetricPresentation
    let accuracy: HomeWeeklySignalMetricPresentation?
    let checkpointsCleared: HomeWeeklySignalMetricPresentation
    let practicedSkills: HomeWeeklySignalMetricPresentation?
    let currentStreak: HomeWeeklySignalMetricPresentation?
    let insight: WeeklySignalInsight?

    init(
        metrics: WeeklyMetricsSummary,
        practicedSkillCount: Int,
        insight: WeeklySignalInsight?
    ) {
        hasActivity = metrics.questionsAnswered > 0 || metrics.checkpointsCleared > 0
        title = metrics.title
        let questionNoun = metrics.questionsAnswered == 1 ? "question" : "questions"
        let checkpointNoun = metrics.checkpointsCleared == 1 ? "checkpoint" : "checkpoints"
        questions = HomeWeeklySignalMetricPresentation(
            id: .questions,
            value: "\(metrics.questionsAnswered)",
            label: metrics.questionsAnswered == 1
                ? "QUESTION ANSWERED"
                : "QUESTIONS ANSWERED",
            numericValue: Double(metrics.questionsAnswered),
            accessibilityValue: "\(metrics.questionsAnswered) \(questionNoun) answered this week"
        )

        if metrics.questionsAnswered > 0 {
            let accuracyPercent = Int(
                (Double(metrics.correctAnswers) / Double(metrics.questionsAnswered)) * 100
            )
            accuracy = HomeWeeklySignalMetricPresentation(
                id: .accuracy,
                value: "\(accuracyPercent)%",
                label: "ACCURACY",
                numericValue: Double(accuracyPercent),
                accessibilityValue:
                    "\(accuracyPercent) percent accuracy, " +
                    "\(metrics.correctAnswers) of \(metrics.questionsAnswered) correct"
            )
        } else {
            accuracy = nil
        }

        checkpointsCleared = HomeWeeklySignalMetricPresentation(
            id: .checkpointsCleared,
            value: "\(metrics.checkpointsCleared)",
            label: metrics.checkpointsCleared == 1
                ? "CHECKPOINT CLEARED"
                : "CHECKPOINTS CLEARED",
            numericValue: Double(metrics.checkpointsCleared),
            accessibilityValue:
                "\(metrics.checkpointsCleared) \(checkpointNoun) cleared this week"
        )

        if practicedSkillCount > 0 {
            let skillNoun = practicedSkillCount == 1 ? "skill" : "skills"
            practicedSkills = HomeWeeklySignalMetricPresentation(
                id: .practicedSkills,
                value: "\(practicedSkillCount)",
                label: practicedSkillCount == 1 ? "SKILL PRACTICED" : "SKILLS PRACTICED",
                numericValue: Double(practicedSkillCount),
                accessibilityValue: "\(practicedSkillCount) practiced \(skillNoun) this week"
            )
        } else {
            practicedSkills = nil
        }

        if metrics.checkpointStreakDays > 1 {
            currentStreak = HomeWeeklySignalMetricPresentation(
                id: .currentStreak,
                value: "\(metrics.checkpointStreakDays)d",
                label: "CURRENT STREAK",
                numericValue: Double(metrics.checkpointStreakDays),
                accessibilityValue: "\(metrics.checkpointStreakDays)-day checkpoint streak"
            )
        } else {
            currentStreak = nil
        }

        if hasActivity, insight?.role != .checkpointsCleared {
            self.insight = insight
        } else {
            self.insight = nil
        }
    }

    var primaryMetric: HomeWeeklySignalMetricPresentation? {
        guard hasActivity else { return nil }
        return questions.numericValue > 0 ? questions : checkpointsCleared
    }

    var supportingMetrics: [HomeWeeklySignalMetricPresentation] {
        guard hasActivity else { return [] }

        return [
            accuracy,
            checkpointsCleared.numericValue > 0 && primaryMetric?.id != .checkpointsCleared
                ? checkpointsCleared
                : nil,
            currentStreak
        ].compactMap { $0 }
    }

    var visibleMetrics: [HomeWeeklySignalMetricPresentation] {
        guard hasActivity else { return [] }

        return [primaryMetric, practicedSkills].compactMap { $0 } + supportingMetrics
    }

    var accessibilityValue: String {
        guard hasActivity else { return "For \(title). \(Self.emptyAccessibilityValue)" }

        var parts = ["For \(title)"] + visibleMetrics.map(\.accessibilityValue)
        if let insight {
            parts.append("Insight: \(insight.accessibilityLabel)")
        }
        return parts.joined(separator: ". ") + "."
    }
}

enum HomeWeeklySignalSkillPolicy {
    static func practicedSkillCount(
        competencies: [TopicCompetency],
        asOf referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
            return 0
        }

        return competencies.filter { competency in
            guard let lastPracticedAt = competency.lastPracticedAt else { return false }
            return competency.attempts > 0
                && lastPracticedAt <= referenceDate
                && week.contains(lastPracticedAt)
        }.count
    }
}

enum HomeWeeklySignalLayoutElement: Hashable {
    case section
    case actionButton
    case actionAffordance
    case primaryMetric
    case supportingMetrics
}

private struct HomeWeeklySignalViewportWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 393
}

extension EnvironmentValues {
    var homeWeeklySignalViewportWidth: CGFloat {
        get { self[HomeWeeklySignalViewportWidthKey.self] }
        set { self[HomeWeeklySignalViewportWidthKey.self] = newValue }
    }
}

private let homeWeeklySignalLayoutCoordinateSpaceName = "Checkpoint.Home.WeeklySignal.Layout"

private struct HomeWeeklySignalLayoutFrameReporter: ViewModifier {
    let element: HomeWeeklySignalLayoutElement
    let report: (@MainActor (HomeWeeklySignalLayoutElement, CGRect) -> Void)?

    func body(content: Content) -> some View {
        content.background {
            if let report {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(homeWeeklySignalLayoutCoordinateSpaceName))

                    Color.clear
                        .onAppear {
                            report(element, frame)
                        }
                        .onChange(of: frame) { _, updatedFrame in
                            report(element, updatedFrame)
                        }
                }
            }
        }
    }
}

private extension View {
    func reportHomeWeeklySignalLayoutFrame(
        _ element: HomeWeeklySignalLayoutElement,
        using report: (@MainActor (HomeWeeklySignalLayoutElement, CGRect) -> Void)?
    ) -> some View {
        modifier(HomeWeeklySignalLayoutFrameReporter(element: element, report: report))
    }
}

struct LightStudyBeaconSection: View {
    var metrics: WeeklyMetricsSummary
    var competencies: [TopicCompetency]
    var insight: WeeklySignalInsight?
    var action: () -> Void

    private let reduceMotionOverride: Bool?
    private let layoutReporter: (@MainActor (HomeWeeklySignalLayoutElement, CGRect) -> Void)?
    private let referenceDate: Date
    private let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.homeWeeklySignalViewportWidth) private var viewportWidth
    @ScaledMetric(relativeTo: .largeTitle) private var primaryMetricSize: CGFloat = 50

    init(
        metrics: WeeklyMetricsSummary,
        competencies: [TopicCompetency],
        insight: WeeklySignalInsight?,
        reduceMotionOverride: Bool? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        layoutReporter: (@MainActor (HomeWeeklySignalLayoutElement, CGRect) -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.metrics = metrics
        self.competencies = competencies
        self.insight = insight
        self.reduceMotionOverride = reduceMotionOverride
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.layoutReporter = layoutReporter
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderLabel

            Button(action: action) {
                CheckpointHeroSurface(
                    glowColor: signalAccent,
                    glowOpacity: heroPresentation.hasActivity ? 0.12 : 0.07,
                    glowDiameter: 142,
                    contentPadding: layoutPolicy.contentPadding
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        signalHeader

                        if heroPresentation.hasActivity {
                            activitySummary
                        } else {
                            emptySummary
                        }

                        if let insight = heroPresentation.insight {
                            Divider()
                                .overlay(CheckpointTheme.heroDivider)

                            insightRow(insight)
                                .transition(motionPolicy.conditionalTransition)
                        }
                    }
                    .animation(motionPolicy.animation, value: heroPresentation.insight)
                }
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(CheckpointPressButtonStyle(role: .surface))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HomeWeeklySignalHeroPresentation.actionLabel)
            .accessibilityValue(weeklySignalAccessibilityValue)
            .accessibilityHint("Opens weekly impact")
            .accessibilityIdentifier("home-weekly-signal-action")
            .reportHomeWeeklySignalLayoutFrame(.actionButton, using: layoutReporter)
        }
        .reportHomeWeeklySignalLayoutFrame(.section, using: layoutReporter)
        .coordinateSpace(name: homeWeeklySignalLayoutCoordinateSpaceName)
    }

    private var sectionHeaderLabel: some View {
        Text("WEEKLY SIGNAL")
            .font(.caption2.weight(.bold))
            .tracking(0.95)
            .foregroundStyle(CheckpointTheme.muted)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var signalHeader: some View {
        if layoutPolicy.layout == .stacked {
            VStack(alignment: .leading, spacing: 8) {
                signalIdentity
                viewImpactLabel
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                signalIdentity
                Spacer(minLength: 8)
                viewImpactLabel
            }
        }
    }

    private var signalIdentity: some View {
        HStack(spacing: 9) {
            Image(systemName: heroPresentation.hasActivity ? "waveform.path.ecg" : "circle.dotted")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(signalAccent)
                .frame(width: 32, height: 32)
                .background(CheckpointTheme.heroSubtleFill, in: RoundedRectangle(cornerRadius: 10))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(
                    .bounce,
                    options: .nonRepeating,
                    value: signalChangeToken
                )
                .symbolEffectsRemoved(!motionPolicy.permitsSignalEffect)
                .accessibilityHidden(true)

            Text("THIS WEEK")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(signalSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var viewImpactLabel: some View {
        HStack(spacing: 6) {
            Text("View impact")
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(CheckpointTheme.heroSuccess)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(CheckpointTheme.heroSubtleFill, in: Capsule())
        .accessibilityHidden(true)
        .reportHomeWeeklySignalLayoutFrame(.actionAffordance, using: layoutReporter)
    }

    @ViewBuilder
    private var activitySummary: some View {
        if let primaryMetric = heroPresentation.primaryMetric {
            if heroPresentation.supportingMetrics.isEmpty {
                primaryMetricView(primaryMetric)
            } else if layoutPolicy.layout == .stacked {
                VStack(alignment: .leading, spacing: 16) {
                    primaryMetricView(primaryMetric)

                    Rectangle()
                        .fill(CheckpointTheme.heroDivider)
                        .frame(height: 1)
                        .accessibilityHidden(true)

                    supportingMetrics
                }
            } else {
                HStack(alignment: .center, spacing: 18) {
                    primaryMetricView(primaryMetric)

                    Rectangle()
                        .fill(CheckpointTheme.heroDivider)
                        .frame(width: 1, height: 76)
                        .accessibilityHidden(true)

                    supportingMetrics
                }
            }
        }
    }

    private func primaryMetricView(
        _ primaryMetric: HomeWeeklySignalMetricPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(primaryMetric.value)
                .font(.system(size: primaryMetricSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(signalText)
                .contentTransition(.numericText(value: primaryMetric.numericValue))
                .animation(motionPolicy.animation, value: primaryMetric.numericValue)

            Text(primaryMetric.label)
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(signalSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let practicedSkills = heroPresentation.practicedSkills {
                Text("\(practicedSkills.value) \(practicedSkills.label.lowercased())")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(signalSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .contentTransition(.numericText(value: practicedSkills.numericValue))
                    .animation(motionPolicy.animation, value: practicedSkills.numericValue)
            }
        }
        .frame(maxWidth: layoutPolicy.layout == .stacked ? .infinity : nil, alignment: .leading)
        .accessibilityElement(children: .combine)
        .reportHomeWeeklySignalLayoutFrame(.primaryMetric, using: layoutReporter)
    }

    private var supportingMetrics: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(heroPresentation.supportingMetrics) { metric in
                compactMetric(metric)
                .transition(motionPolicy.conditionalTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(motionPolicy.animation, value: heroPresentation.supportingMetrics.map(\.id))
        .reportHomeWeeklySignalLayoutFrame(.supportingMetrics, using: layoutReporter)
    }

    @ViewBuilder
    private func compactMetric(_ metric: HomeWeeklySignalMetricPresentation) -> some View {
        Group {
            if layoutPolicy.stacksSupportingMetricLabels {
                VStack(alignment: .leading, spacing: 2) {
                    compactMetricValue(metric)
                    compactMetricLabel(metric)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    compactMetricValue(metric)
                    compactMetricLabel(metric)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func compactMetricValue(_ metric: HomeWeeklySignalMetricPresentation) -> some View {
        Text(metric.value)
            .font(.headline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(signalAccent)
            .contentTransition(.numericText(value: metric.numericValue))
            .animation(motionPolicy.animation, value: metric.numericValue)
    }

    private func compactMetricLabel(_ metric: HomeWeeklySignalMetricPresentation) -> some View {
        Text(metric.label)
            .font(.caption2.weight(.bold))
            .tracking(0.55)
            .foregroundStyle(signalSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func insightRow(_ insight: WeeklySignalInsight) -> some View {
        Group {
            if layoutPolicy.layout == .stacked {
                VStack(alignment: .leading, spacing: 10) {
                    insightIcon(insight)
                    insightText(insight)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    insightIcon(insight)
                    insightText(insight)

                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(insight.accessibilityLabel)
    }

    private func insightIcon(_ insight: WeeklySignalInsight) -> some View {
        Image(systemName: insightSystemImage(for: insight))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(insightTint(for: insight))
            .frame(width: 30, height: 30)
            .background(
                insightTint(for: insight).opacity(0.14),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .accessibilityHidden(true)
    }

    private func insightText(_ insight: WeeklySignalInsight) -> some View {
        Text(insight.text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(signalText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
    }

    private func insightSystemImage(for insight: WeeklySignalInsight) -> String {
        switch insight.role {
        case .lowestCurrentEstimate:
            "chart.bar.fill"
        case .highestCurrentEstimate:
            "waveform.path.ecg"
        case .checkpointsCleared:
            "shield.checkered"
        case .answersLogged:
            "point.3.connected.trianglepath.dotted"
        case .checkpointStreak:
            "bolt.fill"
        }
    }

    private func insightTint(for insight: WeeklySignalInsight) -> Color {
        switch insight.role {
        case .lowestCurrentEstimate:
            CheckpointTheme.heroWarning
        case .highestCurrentEstimate:
            CheckpointTheme.heroInfo
        case .checkpointsCleared, .answersLogged, .checkpointStreak:
            CheckpointTheme.heroSuccess
        }
    }

    private var emptySummary: some View {
        Group {
            if layoutPolicy.layout == .stacked {
                VStack(alignment: .leading, spacing: 8) {
                    emptySignalIcon
                    emptySummaryCopy
                }
            } else {
                HStack(alignment: .top, spacing: 13) {
                    emptySignalIcon
                    emptySummaryCopy
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emptySignalIcon: some View {
        Image(systemName: "point.3.connected.trianglepath.dotted")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(signalAccent)
            .frame(width: 40, height: 40)
            .background(CheckpointTheme.heroSubtleFill, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private var emptySummaryCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("No checkpoint activity this week")
                .font(.headline)
                .foregroundStyle(signalText)

            Text("Your next checkpoint will start this week's impact view.")
                .font(.subheadline)
                .foregroundStyle(signalSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var practicedSkillCount: Int {
        HomeWeeklySignalSkillPolicy.practicedSkillCount(
            competencies: competencies,
            asOf: referenceDate,
            calendar: calendar
        )
    }

    private var weeklySignalAccessibilityValue: String {
        heroPresentation.accessibilityValue
    }

    private var heroPresentation: HomeWeeklySignalHeroPresentation {
        HomeWeeklySignalHeroPresentation(
            metrics: metrics,
            practicedSkillCount: practicedSkillCount,
            insight: insight
        )
    }

    private var layoutPolicy: HomeWeeklySignalLayoutPolicy {
        HomeWeeklySignalLayoutPolicy(
            viewportWidth: viewportWidth,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var motionPolicy: HomeWeeklySignalMotionPolicy {
        HomeWeeklySignalMotionPolicy(reduceMotion: reduceMotion)
    }

    private var signalChangeToken: String {
        [
            String(metrics.questionsAnswered),
            String(metrics.correctAnswers),
            String(metrics.checkpointsCleared),
            String(metrics.checkpointStreakDays),
            String(practicedSkillCount),
            heroPresentation.insight?.text ?? "none"
        ].joined(separator: ":")
    }

    private var signalText: Color { CheckpointTheme.heroText }
    private var signalSecondaryText: Color { CheckpointTheme.heroMuted }
    private var signalAccent: Color { CheckpointTheme.heroSuccess }
}
