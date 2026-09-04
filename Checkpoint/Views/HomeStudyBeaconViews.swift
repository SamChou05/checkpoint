import Foundation
import SwiftUI

enum HomeGoalOverviewReadyDisclosure: Equatable {
    case visible
    case suppressedByFirstCheckpointLaunchpad
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

struct HomeGoalOverviewCard<GoalControl: View>: View {
    let presentation: HomeGoalOverviewPresentation
    let reduceMotion: Bool
    let retryQuestions: () -> Void
    let editGoal: () -> Void
    @ViewBuilder let goalControl: GoalControl

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        presentation: HomeGoalOverviewPresentation,
        reduceMotion: Bool,
        retryQuestions: @escaping () -> Void,
        editGoal: @escaping () -> Void,
        @ViewBuilder goalControl: () -> GoalControl
    ) {
        self.presentation = presentation
        self.reduceMotion = reduceMotion
        self.retryQuestions = retryQuestions
        self.editGoal = editGoal
        self.goalControl = goalControl()
    }

    var body: some View {
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
        .padding(18)
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

enum HomeStudyBeaconPresentation: Equatable {
    case firstCheckpointLaunchpad
    case weeklySignal

    var showsNextFocus: Bool {
        self == .weeklySignal
    }

    init(
        hasPracticeForActiveGoal: Bool,
        hasReadyCheckpointSet: Bool,
        isProtectionActive: Bool
    ) {
        self = !hasPracticeForActiveGoal && hasReadyCheckpointSet && isProtectionActive
            ? .firstCheckpointLaunchpad
            : .weeklySignal
    }
}

struct HomeFirstCheckpointLaunchpad: View {
    var requiredCorrectAnswers: Int
    var questionCount: Int
    var unlockMinutes: Int
    var protectedAppsSummary: String
    var reviewApps: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT STEP")
                .font(.caption2.weight(.bold))
                .tracking(0.95)
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityHidden(true)

            CheckpointHeroSurface(glowColor: CheckpointTheme.mint) {
                VStack(alignment: .leading, spacing: 18) {
                    launchIdentity

                    Text(instructionText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(instructionText)

                    Divider()
                        .overlay(CheckpointTheme.heroDivider)

                    protectionControls
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var launchIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                launchIcon
                launchTitle
            }
        } else {
            HStack(alignment: .center, spacing: 13) {
                launchIcon
                launchTitle
            }
        }
    }

    private var launchIcon: some View {
        Image(systemName: "flag.checkered")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(CheckpointTheme.ink)
            .frame(width: 46, height: 46)
            .background(CheckpointTheme.mint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var launchTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("FIRST CHECKPOINT")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(CheckpointTheme.heroSuccess)

            Text("This goal’s first checkpoint is ready")
                .font(.title3.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next step. This goal’s first checkpoint is ready")
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var protectionControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                protectionIdentity
                reviewAppsButton
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    protectionIdentity
                    Spacer(minLength: 8)
                    reviewAppsButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    protectionIdentity
                    reviewAppsButton
                }
            }
        }
    }

    private var protectionIdentity: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CheckpointTheme.heroSuccess)
                .frame(width: 30, height: 30)
                .background(CheckpointTheme.heroSubtleFill, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Protection on")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.heroText)

                Text(protectedAppsSummary)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protection on. \(protectedAppsSummary)")
    }

    private var reviewAppsButton: some View {
        Button(action: reviewApps) {
            HStack(spacing: 6) {
                Text("Review apps")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.heroSuccess)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .accessibilityHint("Opens your protected app selection")
    }

    private var instructionText: String {
        let questionNoun = questionCount == 1 ? "question" : "questions"
        return "Open any protected app. Clear \(requiredCorrectAnswers) of \(questionCount) \(questionNoun) to earn a \(unlockMinutes)-minute break."
    }
}

struct LightStudyBeaconSection: View {
    var metrics: WeeklyMetricsSummary
    var competencies: [TopicCompetency]
    var insight: WeeklySignalInsight?
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var primaryMetricSize: CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            Button(action: action) {
                VStack(alignment: .leading, spacing: 16) {
                    if metrics.hasWeeklyReviewActivity {
                        activitySummary
                    } else {
                        emptySummary
                    }

                    if let insight {
                        Divider()
                            .overlay(CheckpointTheme.heroDivider)

                        insightRow(insight)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CheckpointTheme.ink)
                        .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
                        .overlay(alignment: .topTrailing) {
                            Circle()
                                .fill(signalAccent.opacity(0.08))
                                .frame(width: 140, height: 140)
                                .blur(radius: 10)
                                .offset(x: 60, y: -78)
                                .allowsHitTesting(false)
                        }
                )
                .shadow(color: CheckpointTheme.shadowElevated, radius: 16, y: 8)
            }
            .buttonStyle(CheckpointPressButtonStyle())
            .accessibilityLabel(weeklySignalAccessibilityLabel)
            .accessibilityHint("Opens weekly impact")
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var sectionHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 5) {
                sectionHeaderLabel
                viewImpactLabel
            }
        } else {
            HStack {
                sectionHeaderLabel
                Spacer()
                viewImpactLabel
            }
        }
    }

    private var sectionHeaderLabel: some View {
        Text("WEEKLY SIGNAL")
            .font(.caption2.weight(.bold))
            .tracking(0.95)
            .foregroundStyle(CheckpointTheme.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private var viewImpactLabel: some View {
        HStack(spacing: 5) {
            Text("View impact")
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(CheckpointTheme.teal)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var activitySummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 18) {
                primaryMetric
                supportingMetrics
            }
        } else {
            HStack(alignment: .center, spacing: 18) {
                primaryMetric

                Rectangle()
                    .fill(CheckpointTheme.heroDivider)
                    .frame(width: 1, height: 70)
                    .accessibilityHidden(true)

                supportingMetrics
            }
        }
    }

    private var primaryMetric: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(metrics.questionsAnswered)")
                .font(.system(size: primaryMetricSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(signalText)
                .contentTransition(.numericText(value: Double(metrics.questionsAnswered)))
                .animation(
                    CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                    value: metrics.questionsAnswered
                )

            Text(metrics.questionsAnswered == 1 ? "QUESTION" : "QUESTIONS")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(signalSecondaryText)

            if practicedSkillCount > 0 {
                Text("\(practicedSkillCount) \(practicedSkillCount == 1 ? "skill" : "skills") tracked")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(signalSecondaryText)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var supportingMetrics: some View {
        VStack(alignment: .leading, spacing: 13) {
            compactMetric(
                value: metrics.questionsAnswered > 0 ? metrics.accuracyText : "—",
                label: "ACCURACY"
            )

            compactMetric(
                value: "\(metrics.checkpointsCleared)",
                label: metrics.checkpointsCleared == 1 ? "BREAK EARNED" : "BREAKS EARNED"
            )

            if metrics.checkpointStreakDays > 1 {
                compactMetric(
                    value: "\(metrics.checkpointStreakDays)d",
                    label: "CONSISTENCY"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMetric(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(signalAccent)

            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(0.55)
                .foregroundStyle(signalSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private func insightRow(_ insight: WeeklySignalInsight) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    insightIcon(insight)
                    insightText(insight)
                }
            } else {
                HStack(spacing: 10) {
                    insightIcon(insight)
                    insightText(insight)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(signalSecondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(insight.accessibilityLabel)
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: insight
        )
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
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
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
        HStack(spacing: 13) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(signalAccent)
                .frame(width: 40, height: 40)
                .background(CheckpointTheme.heroSubtleFill, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Signal ready")
                    .font(.headline)
                    .foregroundStyle(signalText)

                Text("Your first checkpoint will start this week's impact view.")
                    .font(.subheadline)
                    .foregroundStyle(signalSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var practicedSkillCount: Int {
        competencies.filter { $0.attempts > 0 }.count
    }

    private var weeklySignalAccessibilityLabel: String {
        guard metrics.hasWeeklyReviewActivity else {
            return "Weekly signal for \(metrics.title). No checkpoint activity yet."
        }

        let questionNoun = metrics.questionsAnswered == 1 ? "question" : "questions"
        let breakNoun = metrics.checkpointsCleared == 1 ? "break" : "breaks"
        let questionSummary = metrics.questionsAnswered > 0
            ? "\(metrics.questionsAnswered) \(questionNoun), \(metrics.accuracyText) accuracy"
            : "No questions answered this week"
        let summary = "Weekly signal for \(metrics.title). \(questionSummary), \(metrics.checkpointsCleared) \(breakNoun) earned."
        guard let insight else { return summary }
        return "\(summary) \(insight.accessibilityLabel)."
    }

    private var signalText: Color { CheckpointTheme.heroText }
    private var signalSecondaryText: Color { CheckpointTheme.heroMuted }
    private var signalAccent: Color { CheckpointTheme.heroSuccess }
}
