import Foundation
import SwiftUI

enum HomeActiveBreakPhase: Equatable {
    case active
    case endingSoon
    case ending
}

enum HomeActiveBreakRelockReadiness: Equatable {
    case ready
    case waitingForCheckpoint
    case needsAttention

    static func resolve(
        hasRequiredScreenTimeAuthorization: Bool,
        hasSelection: Bool,
        hasReadyCheckpointSet: Bool,
        sharedCheckpointReady: Bool?
    ) -> Self {
        guard hasRequiredScreenTimeAuthorization, hasSelection else {
            return .needsAttention
        }
        guard hasReadyCheckpointSet, sharedCheckpointReady != false else {
            return .waitingForCheckpoint
        }
        return .ready
    }
}

struct HomeActiveBreakPresentation: Equatable {
    let phase: HomeActiveBreakPhase
    let relockReadiness: HomeActiveBreakRelockReadiness
    let areProtectedAppsAvailable: Bool
    let secondsRemaining: Int?
    let remainingFraction: Double?
    let expiresAt: Date?

    init(
        startedAt: Date?,
        expiresAt: Date?,
        relockReadiness: HomeActiveBreakRelockReadiness,
        areProtectedAppsAvailable: Bool,
        at date: Date
    ) {
        self.expiresAt = expiresAt
        self.relockReadiness = relockReadiness
        self.areProtectedAppsAvailable = areProtectedAppsAvailable

        guard let expiresAt else {
            phase = .ending
            secondsRemaining = nil
            remainingFraction = nil
            return
        }

        let remaining = max(0, Int(ceil(expiresAt.timeIntervalSince(date))))
        secondsRemaining = remaining

        if remaining == 0 {
            phase = .ending
        } else if remaining <= 60 {
            phase = .endingSoon
        } else {
            phase = .active
        }

        guard let startedAt, expiresAt > startedAt else {
            remainingFraction = nil
            return
        }

        let duration = expiresAt.timeIntervalSince(startedAt)
        let fraction = expiresAt.timeIntervalSince(date) / duration
        remainingFraction = min(1, max(0, fraction))
    }

    var countdownText: String {
        guard let secondsRemaining, secondsRemaining > 0 else { return "Ending" }
        return String(
            format: "%02d:%02d",
            secondsRemaining / 60,
            secondsRemaining % 60
        )
    }

    var accessibilityValue: String {
        guard let secondsRemaining, secondsRemaining > 0 else { return "Ending" }

        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        let minuteText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let secondText = seconds == 1 ? "1 second" : "\(seconds) seconds"

        if minutes == 0 {
            return secondText
        }
        if seconds == 0 {
            return minuteText
        }
        return "\(minuteText), \(secondText)"
    }

    var statusText: String {
        switch phase {
        case .active:
            "Active"
        case .endingSoon:
            "Ending soon"
        case .ending:
            "Ending"
        }
    }

    var title: String {
        switch phase {
        case .active:
            "Enjoy the time you earned"
        case .endingSoon:
            relockReadiness == .ready
                ? "Protection returns soon"
                : "Your break ends soon"
        case .ending:
            relockReadiness == .ready
                ? "Protection is resuming"
                : "Your break is ending"
        }
    }

    var systemImage: String {
        switch phase {
        case .active:
            "checkmark.seal.fill"
        case .endingSoon:
            "timer"
        case .ending:
            relockReadiness == .ready ? "shield.fill" : "hourglass.bottomhalf.filled"
        }
    }

    var automaticResumeText: String {
        if phase == .ending {
            switch relockReadiness {
            case .ready:
                return "Protection is resuming now."
            case .waitingForCheckpoint:
                return "Protection is staying off. Prepare another checkpoint, then restart it."
            case .needsAttention:
                return "Protection is staying off. Finish its setup, then restart it."
            }
        }

        guard let expiresAt else {
            return "This break is ending now."
        }
        let endTime = expiresAt.formatted(date: .omitted, time: .shortened)

        switch relockReadiness {
        case .ready:
            return "Protection resumes automatically at \(endTime)."
        case .waitingForCheckpoint:
            return "This break ends at \(endTime). Protection turns back on only if another checkpoint is ready."
        case .needsAttention:
            return "This break ends at \(endTime). Protection needs attention before it can turn back on."
        }
    }

    var protectedAppsTitle: String {
        phase != .ending && areProtectedAppsAvailable
            ? "Protected apps are available"
            : "App protection"
    }

    var countdownAccessibilityValue: String {
        "\(accessibilityValue). \(automaticResumeText)"
    }

    var protectedAppsSystemImage: String {
        phase != .ending && areProtectedAppsAvailable
            ? "lock.open.fill"
            : "shield.fill"
    }

    var showsEndBreakAction: Bool {
        phase != .ending
    }

    var endBreakActionHint: String {
        switch relockReadiness {
        case .ready:
            "Ends this break and turns protection back on"
        case .waitingForCheckpoint:
            "Ends this break. Protection stays off; prepare another checkpoint, then restart it"
        case .needsAttention:
            "Ends this break. Protection stays off; finish its setup, then restart it"
        }
    }
}

struct HomeActiveBreakTimelineSchedule: TimelineSchedule {
    struct Entries: Sequence, IteratorProtocol {
        private var nextDate: Date?
        private let finalDate: Date
        private let interval: TimeInterval

        init(startDate: Date, finalDate: Date, interval: TimeInterval) {
            nextDate = startDate
            self.finalDate = finalDate
            self.interval = interval
        }

        mutating func next() -> Date? {
            guard let current = nextDate else { return nil }

            if current >= finalDate {
                nextDate = nil
            } else {
                nextDate = Swift.min(current.addingTimeInterval(interval), finalDate)
            }
            return current
        }
    }

    let expiresAt: Date?

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(
            startDate: startDate,
            finalDate: Swift.max(startDate, expiresAt ?? startDate),
            interval: mode == .lowFrequency ? 60 : 1
        )
    }
}

enum HomeActiveBreakMotionStyle: Equatable {
    case animated
    case identity
}

struct HomeActiveBreakMotionPolicy: Equatable {
    let style: HomeActiveBreakMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var animation: Animation? {
        style == .animated ? CheckpointMotion.change : nil
    }

    var transition: AnyTransition {
        style == .animated
            ? .opacity.combined(with: .scale(scale: 0.985))
            : .identity
    }
}

struct HomeActiveBreakCard: View {
    var startedAt: Date?
    var expiresAt: Date?
    var relockReadiness: HomeActiveBreakRelockReadiness
    var areProtectedAppsAvailable: Bool
    var protectedAppsSummary: String
    var manageApps: () -> Void
    var endBreakEarly: () -> Void

    private let reduceMotionOverride: Bool?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var countdownMetricSize: CGFloat = 50
    @ScaledMetric(relativeTo: .title) private var progressRingSize: CGFloat = 78

    init(
        startedAt: Date?,
        expiresAt: Date?,
        relockReadiness: HomeActiveBreakRelockReadiness,
        areProtectedAppsAvailable: Bool,
        protectedAppsSummary: String,
        reduceMotionOverride: Bool? = nil,
        manageApps: @escaping () -> Void,
        endBreakEarly: @escaping () -> Void
    ) {
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.relockReadiness = relockReadiness
        self.areProtectedAppsAvailable = areProtectedAppsAvailable
        self.protectedAppsSummary = protectedAppsSummary
        self.reduceMotionOverride = reduceMotionOverride
        self.manageApps = manageApps
        self.endBreakEarly = endBreakEarly
    }

    var body: some View {
        TimelineView(HomeActiveBreakTimelineSchedule(expiresAt: expiresAt)) { context in
            let presentation = HomeActiveBreakPresentation(
                startedAt: startedAt,
                expiresAt: expiresAt,
                relockReadiness: relockReadiness,
                areProtectedAppsAvailable: areProtectedAppsAvailable,
                at: context.date
            )

            CheckpointHeroSurface(
                glowColor: accent(for: presentation.phase),
                glowOpacity: 0.13,
                glowDiameter: 190,
                glowBlurRadius: 14,
                glowOffset: CGSize(width: 78, height: -98),
                contentPadding: 20
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    breakHeader(presentation)
                    countdownSection(presentation)

                    Divider()
                        .overlay(CheckpointTheme.heroDivider)

                    protectedAppsRow(presentation)
                    actions(presentation)
                }
            }
            .transition(motionPolicy.transition)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func breakHeader(_ presentation: HomeActiveBreakPresentation) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                breakIdentity(presentation)
                breakStatusBadge(presentation)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    breakIdentity(presentation)
                    Spacer(minLength: 8)
                    breakStatusBadge(presentation)
                }

                VStack(alignment: .leading, spacing: 12) {
                    breakIdentity(presentation)
                    breakStatusBadge(presentation)
                }
            }
        }
    }

    private func breakStatusBadge(_ presentation: HomeActiveBreakPresentation) -> some View {
        StatusBadge(text: presentation.statusText, tint: accent(for: presentation.phase))
            .accessibilityLabel("Break status")
            .accessibilityValue(presentation.statusText)
    }

    private func breakIdentity(_ presentation: HomeActiveBreakPresentation) -> some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: presentation.systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(CheckpointTheme.ink)
                .frame(width: 46, height: 46)
                .background(
                    accent(for: presentation.phase),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .contentTransition(.symbolEffect(.replace))
                .symbolEffectsRemoved(reduceMotion)
                .animation(motionPolicy.animation, value: presentation.phase)
                .fixedSize()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("EARNED BREAK")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(CheckpointTheme.heroSuccess)
                    .accessibilityHidden(true)

                Text(presentation.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CheckpointTheme.heroText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    @ViewBuilder
    private func countdownSection(_ presentation: HomeActiveBreakPresentation) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 18) {
                countdownMetric(presentation)
                progressRing(presentation)
            }
        } else {
            HStack(alignment: .center, spacing: 18) {
                countdownMetric(presentation)
                Spacer(minLength: 4)
                progressRing(presentation)
            }
        }
    }

    private func countdownMetric(_ presentation: HomeActiveBreakPresentation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TIME REMAINING")
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(CheckpointTheme.heroMuted)
                .accessibilityHidden(true)

            Text(presentation.countdownText)
                .font(
                    .system(
                        size: min(countdownMetricSize, dynamicTypeSize.isAccessibilitySize ? 76 : 58),
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(accent(for: presentation.phase))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .contentTransition(
                    presentation.secondsRemaining == nil
                        ? .opacity
                        : .numericText(countsDown: true)
                )
                .animation(motionPolicy.animation, value: presentation.secondsRemaining)

            Text(presentation.automaticResumeText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(CheckpointTheme.heroMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Break remaining")
        .accessibilityValue(presentation.countdownAccessibilityValue)
    }

    private func progressRing(_ presentation: HomeActiveBreakPresentation) -> some View {
        let tint = accent(for: presentation.phase)
        let size = min(progressRingSize, dynamicTypeSize.isAccessibilitySize ? 98 : 86)

        return ZStack {
            Circle()
                .stroke(CheckpointTheme.heroTrack, lineWidth: 7)

            if let remainingFraction = presentation.remainingFraction {
                Circle()
                    .trim(from: 0, to: remainingFraction)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(motionPolicy.animation, value: remainingFraction)
            } else {
                Circle()
                    .stroke(
                        tint.opacity(0.62),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [4, 6])
                    )
            }

            Image(systemName: presentation.systemImage)
                .font(.system(size: size * 0.28, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffectsRemoved(reduceMotion)
                .animation(motionPolicy.animation, value: presentation.phase)
        }
        .frame(width: size, height: size)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func protectedAppsRow(_ presentation: HomeActiveBreakPresentation) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: presentation.protectedAppsSystemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CheckpointTheme.heroSuccess)
                .frame(width: 32, height: 32)
                .background(CheckpointTheme.heroSubtleFill, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.protectedAppsTitle)
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
        .accessibilityLabel("\(presentation.protectedAppsTitle). \(protectedAppsSummary)")
    }

    @ViewBuilder
    private func actions(_ presentation: HomeActiveBreakPresentation) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                manageAppsButton
                if presentation.showsEndBreakAction {
                    endBreakButton(presentation)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    manageAppsButton
                    if presentation.showsEndBreakAction {
                        endBreakButton(presentation)
                    }
                }

                VStack(spacing: 10) {
                    manageAppsButton
                    if presentation.showsEndBreakAction {
                        endBreakButton(presentation)
                    }
                }
            }
        }
    }

    private var manageAppsButton: some View {
        breakActionButton(
            title: "Manage apps",
            systemImage: "checklist",
            tint: CheckpointTheme.heroText,
            hint: "Opens your protected app selection",
            action: manageApps
        )
    }

    private func endBreakButton(_ presentation: HomeActiveBreakPresentation) -> some View {
        breakActionButton(
            title: "End break early",
            systemImage: "shield.fill",
            tint: CheckpointTheme.heroWarning,
            hint: presentation.endBreakActionHint,
            action: endBreakEarly
        )
    }

    private func breakActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 10)
                .background(
                    CheckpointTheme.heroSubtleFill,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckpointTheme.heroDivider, lineWidth: 1)
                }
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .accessibilityHint(hint)
    }

    private var motionPolicy: HomeActiveBreakMotionPolicy {
        HomeActiveBreakMotionPolicy(reduceMotion: reduceMotion)
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private func accent(for phase: HomeActiveBreakPhase) -> Color {
        switch phase {
        case .active:
            CheckpointTheme.heroSuccess
        case .endingSoon, .ending:
            CheckpointTheme.heroWarning
        }
    }
}

struct HomeProtectionActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 10)
            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CheckpointTheme.controlStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
