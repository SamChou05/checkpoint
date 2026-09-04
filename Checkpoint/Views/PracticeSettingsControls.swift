import SwiftUI

struct SettingsPracticeStandardPresentation: Equatable {
    let questionCount: Int
    let requiredCorrectAnswers: Int
    let unlockMinutes: Int

    init(unlockPolicy: UnlockPolicy) {
        questionCount = unlockPolicy.questionsPerSession
        requiredCorrectAnswers = unlockPolicy.requiredCorrectAnswers
        unlockMinutes = unlockPolicy.unlockMinutes
    }

    var passRate: Double {
        guard questionCount > 0 else { return 0 }
        return min(
            1,
            max(0, Double(requiredCorrectAnswers) / Double(questionCount))
        )
    }

    var passPercent: Int {
        Int((passRate * 100).rounded())
    }

    var headline: String {
        "Pass \(requiredCorrectAnswers) of \(questionCount)"
    }

    var detail: String {
        "When protection is on, passing opens protected apps for \(unlockMinutes) minutes."
    }

    var accessibilityValue: String {
        "\(questionCount) questions. \(requiredCorrectAnswers) correct answers required. "
            + "When protection is on, passing opens protected apps for \(unlockMinutes) minutes. "
            + "\(passPercent) percent pass mark. "
            + "Applies to every goal."
    }
}

struct SettingsPracticeStandardMotionPolicy: Equatable {
    let reduceMotion: Bool

    var animation: Animation? {
        CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)
    }

    var revealTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .move(edge: .top))
    }
}

struct SettingsPracticeStandardCard<Controls: View>: View {
    let presentation: SettingsPracticeStandardPresentation
    @Binding var isExpanded: Bool
    let controls: Controls

    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        presentation: SettingsPracticeStandardPresentation,
        isExpanded: Binding<Bool>,
        reduceMotionOverride: Bool? = nil,
        @ViewBuilder controls: () -> Controls
    ) {
        self.presentation = presentation
        _isExpanded = isExpanded
        self.reduceMotionOverride = reduceMotionOverride
        self.controls = controls()
    }

    var body: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 16) {
                summaryHeader

                if !dynamicTypeSize.isAccessibilitySize {
                    metricRail
                }

                Divider()

                editStandardButton

                if isExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fine-tune the rule")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CheckpointTheme.muted)
                            .textCase(.uppercase)
                            .tracking(0.7)
                            .accessibilityAddTraits(.isHeader)

                        controls
                    }
                    .transition(motionPolicy.revealTransition)
                }
            }
        }
        .animation(motionPolicy.animation, value: presentation)
    }

    @ViewBuilder
    private var summaryHeader: some View {
        let content = Group {
            if dynamicTypeSize.isAccessibilitySize {
                summaryCopy
            } else {
                HStack(alignment: .center, spacing: 16) {
                    summaryCopy
                    Spacer(minLength: 8)
                    passGauge
                }
            }
        }

        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Checkpoint standard")
            .accessibilityValue(presentation.accessibilityValue)
    }

    private var summaryCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("CHECKPOINT STANDARD", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(CheckpointTheme.teal)

            Text(presentation.headline)
                .font(.title3.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())

            Text(presentation.detail)
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())

            Text("Applies to every goal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var passGauge: some View {
        ZStack {
            Circle()
                .stroke(CheckpointTheme.teal.opacity(0.13), lineWidth: 7)

            Circle()
                .trim(from: 0, to: presentation.passRate)
                .stroke(
                    CheckpointTheme.teal,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(presentation.passPercent)%")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(CheckpointTheme.text)
                    .contentTransition(.numericText())

                Text("TO PASS")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CheckpointTheme.muted)
            }
        }
        .frame(
            width: 68,
            height: 68
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var metricRail: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                metricViews
            }
            .frame(minWidth: 285)

            stackedMetricRail
        }
        .accessibilityHidden(true)
    }

    private var stackedMetricRail: some View {
        VStack(spacing: 8) {
            metricViews
        }
    }

    @ViewBuilder
    private var metricViews: some View {
        SettingsPracticeStandardMetric(
            value: "\(presentation.questionCount)",
            label: "Questions",
            systemImage: "list.number"
        )
        SettingsPracticeStandardMetric(
            value: "\(presentation.requiredCorrectAnswers)",
            label: "To pass",
            systemImage: "checkmark"
        )
        SettingsPracticeStandardMetric(
            value: "\(presentation.unlockMinutes) min",
            label: "Break",
            systemImage: "timer"
        )
    }

    private var editStandardButton: some View {
        Button {
            withAnimation(motionPolicy.animation) {
                isExpanded.toggle()
            }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            editStandardIcon
                            Spacer(minLength: 8)
                            editStandardChevron
                        }

                        editStandardTitle
                    }
                } else {
                    HStack(spacing: 10) {
                        editStandardIcon
                        editStandardTitle
                        Spacer(minLength: 8)
                        editStandardChevron
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .accessibilityLabel(isExpanded ? "Hide checkpoint standard controls" : "Edit checkpoint standard")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hides the editing controls." : "Shows the editing controls.")
    }

    private var editStandardIcon: some View {
        Image(systemName: "slider.horizontal.3")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 34, height: 34)
            .background(
                CheckpointTheme.teal.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var editStandardTitle: some View {
        Text(isExpanded ? "Hide standard controls" : "Edit standard")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var editStandardChevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.teal)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .accessibilityHidden(true)
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var motionPolicy: SettingsPracticeStandardMotionPolicy {
        SettingsPracticeStandardMotionPolicy(reduceMotion: reduceMotion)
    }
}

private struct SettingsPracticeStandardMetric: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CheckpointTheme.teal)

                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(CheckpointTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .contentTransition(.numericText())
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.68),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(CheckpointTheme.controlStroke.opacity(0.72), lineWidth: 1)
        }
    }
}

struct PracticeStandardStepperRow: View {
    var title: String
    var value: Int
    var decrementDisabled: Bool
    var incrementDisabled: Bool
    var decrementAction: () -> Void
    var incrementAction: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedStepper
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalStepper
                        .frame(minWidth: 280)

                    stackedStepper
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.68),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var horizontalStepper: some View {
        nativeStepper {
            HStack(spacing: 10) {
                titleLabel
                Spacer(minLength: 8)
                valueLabel
            }
        }
    }

    private var stackedStepper: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 7) {
                        titleLabel
                        valueLabel
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        titleLabel
                        Spacer(minLength: 8)
                        valueLabel
                    }
                }
            }
            .accessibilityHidden(true)

            nativeStepper {
                EmptyView()
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func nativeStepper<Label: View>(
        @ViewBuilder label: () -> Label
    ) -> some View {
        Stepper(
            onIncrement: incrementDisabled ? nil : incrementAction,
            onDecrement: decrementDisabled ? nil : decrementAction,
            label: label
        )
        .tint(CheckpointTheme.teal)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityHint("Swipe up or down to adjust.")
    }

    private var titleLabel: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueLabel: some View {
        Text("\(value)")
            .font(.title3.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

struct BreakDurationMenu: View {
    var selectedMinutes: Int
    var options: [Int]
    var selectMinutes: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { minutes in
                Button {
                    selectMinutes(minutes)
                } label: {
                    Label("\(minutes) minutes", systemImage: minutes == selectedMinutes ? "checkmark" : "timer")
                }
            }
        } label: {
            menuLabel
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(CheckpointTheme.panelRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CheckpointTheme.controlStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Break after passing")
        .accessibilityValue("\(selectedMinutes) minutes")
        .accessibilityHint("Choose how long protected apps open after passing a practice set.")
    }

    @ViewBuilder
    private var menuLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    menuIcon
                    menuTitle
                }

                HStack(spacing: 8) {
                    menuValue
                    Spacer(minLength: 8)
                    menuChevron
                }
            }
        } else {
            HStack(spacing: 12) {
                menuIcon
                menuTitle
                Spacer(minLength: 8)
                menuValue
                menuChevron
            }
        }
    }

    private var menuIcon: some View {
        Image(systemName: "timer")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 30, height: 30)
            .background(CheckpointTheme.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private var menuTitle: some View {
        Text("Break after passing")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var menuValue: some View {
        Text("\(selectedMinutes) min")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private var menuChevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.muted)
            .accessibilityHidden(true)
    }
}
