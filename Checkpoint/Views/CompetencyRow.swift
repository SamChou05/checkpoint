import SwiftUI

enum CompetencyProgressBand: Equatable {
    static let minimumReliableAttemptCount = 10

    case notStarted
    case calibrating
    case needsPractice
    case building
    case strong

    static func resolve(for competency: TopicCompetency) -> Self {
        guard competency.attempts > 0 else { return .notStarted }
        guard competency.attempts >= minimumReliableAttemptCount else { return .calibrating }

        switch competency.masteryPercent {
        case 75...:
            return .strong
        case 40..<75:
            return .building
        default:
            return .needsPractice
        }
    }

    var label: String {
        switch self {
        case .notStarted:
            return "Not started"
        case .calibrating:
            return "Calibrating"
        case .needsPractice:
            return "Needs practice"
        case .building:
            return "Building"
        case .strong:
            return "Strong"
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted:
            return "circle.dashed"
        case .calibrating:
            return "scope"
        case .needsPractice:
            return "arrow.triangle.2.circlepath"
        case .building:
            return "chart.line.uptrend.xyaxis"
        case .strong:
            return "checkmark"
        }
    }

    var tint: Color {
        switch self {
        case .notStarted, .calibrating:
            return CheckpointTheme.blue
        case .needsPractice:
            return CheckpointTheme.coral
        case .building:
            return CheckpointTheme.amber
        case .strong:
            return CheckpointTheme.teal
        }
    }
}

struct CompetencyRecencyLabel {
    static func text(
        attempts: Int,
        lastPracticedAt: Date?,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let lastPracticedAt else {
            return attempts > 0 ? "Practiced previously" : "Not practiced yet"
        }
        if calendar.isDate(lastPracticedAt, inSameDayAs: now) {
            return "Practiced today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(lastPracticedAt, inSameDayAs: yesterday) {
            return "Practiced yesterday"
        }
        if calendar.component(.year, from: lastPracticedAt) == calendar.component(.year, from: now) {
            return "Practiced \(lastPracticedAt.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return "Practiced \(lastPracticedAt.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}

struct CompetencyRow: View {
    var competency: TopicCompetency
    private let expandedCompetencyID: Binding<TopicCompetency.ID?>?
    let isHighlighted: Bool
    let accessibilityFocusRequestID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState(for: [.voiceOver, .switchControl])
    private var isAccessibilityFocused: Bool
    @State private var isLocallyExpanded = false
    @State private var expansionFeedbackSequence = 0

    init(
        competency: TopicCompetency,
        expandedCompetencyID: Binding<TopicCompetency.ID?>? = nil,
        isHighlighted: Bool = false,
        accessibilityFocusRequestID: UUID? = nil
    ) {
        self.competency = competency
        self.expandedCompetencyID = expandedCompetencyID
        self.isHighlighted = isHighlighted
        self.accessibilityFocusRequestID = accessibilityFocusRequestID
    }

    private var isExpanded: Bool {
        if let expandedCompetencyID {
            return expandedCompetencyID.wrappedValue == competency.id
        }
        return isLocallyExpanded
    }

    private var usesStackedTypeLayout: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge ||
            dynamicTypeSize.isAccessibilitySize
    }

    private var progressBand: CompetencyProgressBand {
        CompetencyProgressBand.resolve(for: competency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
                    toggleExpansion()
                }
                expansionFeedbackSequence += 1
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    if usesStackedTypeLayout {
                        accessibilitySizeHeader
                    } else {
                        standardHeader
                    }

                    if competency.attempts > 0 {
                        masteryTrack
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(CheckpointPressButtonStyle(role: .surface))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(competency.topic)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isExpanded ? "Hides the answer breakdown." : "Shows the answer breakdown.")
            .accessibilityFocused($isAccessibilityFocused)

            if isExpanded {
                Divider()
                    .overlay(CheckpointTheme.hairline)

                expandedDetails
                    .padding(.vertical, 14)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .background(
            CheckpointTheme.blue.opacity(isHighlighted ? 0.08 : 0),
            in: RoundedRectangle(
                cornerRadius: CheckpointTheme.compactCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: CheckpointTheme.compactCornerRadius,
                style: .continuous
            )
            .stroke(
                CheckpointTheme.blue.opacity(isHighlighted ? 0.72 : 0),
                lineWidth: 1.5
            )
        }
        .animation(
            CheckpointMotion.animation(
                CheckpointMotion.change,
                reduceMotion: reduceMotion || voiceOverEnabled || switchControlEnabled
            ),
            value: isHighlighted
        )
        .sensoryFeedback(.selection, trigger: expansionFeedbackSequence)
        .task(id: accessibilityFocusRequestID) {
            guard accessibilityFocusRequestID != nil else {
                isAccessibilityFocused = false
                return
            }
            await Task.yield()
            guard !Task.isCancelled,
                  accessibilityFocusRequestID != nil else {
                return
            }
            isAccessibilityFocused = true
        }
    }

    private func toggleExpansion() {
        if let expandedCompetencyID {
            expandedCompetencyID.wrappedValue = isExpanded ? nil : competency.id
        } else {
            isLocallyExpanded.toggle()
        }
    }

    private var standardHeader: some View {
        ViewThatFits(in: .horizontal) {
            standardInlineHeader
                .frame(minWidth: 270)

            accessibilitySizeHeader
        }
    }

    private var standardInlineHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 5) {
                Text(competency.topic)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(metadataText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CheckpointTheme.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                if competency.attempts > 0 {
                    masteryValue
                }
                statusChip
            }

            disclosureChevron
        }
    }

    private var accessibilitySizeHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                statusIcon
                Spacer(minLength: 8)
                disclosureChevron
            }

            Text(competency.topic)
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            statusChip

            if competency.attempts > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    masteryValue

                    Text(progressBand == .calibrating ? "answers" : "mastery estimate")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)
                        .multilineTextAlignment(.leading)
                }
            }

            Text(metadataText)
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusIcon: some View {
        Image(systemName: progressBand.systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(progressBand.tint)
            .frame(width: 38, height: 38)
            .background(
                progressBand.tint.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var statusChip: some View {
        Text(progressBand.label)
            .font(.caption.weight(.bold))
            .foregroundStyle(progressBand.tint)
            .fixedSize(
                horizontal: !usesStackedTypeLayout,
                vertical: usesStackedTypeLayout
            )
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(progressBand.tint.opacity(0.12), in: Capsule())
            .accessibilityHidden(true)
    }

    private var masteryValue: some View {
        Text(
            progressBand == .calibrating
                ? "\(competency.attempts)/\(CompetencyProgressBand.minimumReliableAttemptCount)"
                : "\(competency.masteryPercent)%"
        )
            .font(.title3.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityHidden(true)
    }

    private var disclosureChevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.muted)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .frame(width: 24, height: 38)
            .accessibilityHidden(true)
    }

    private var masteryTrack: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CheckpointTheme.panelRaised)

                Capsule()
                    .fill(progressBand.tint)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: progress
        )
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if usesStackedTypeLayout {
                    VStack(spacing: 8) {
                        detailCount(title: "Correct", value: competency.correct, systemImage: "checkmark.circle", tint: CheckpointTheme.teal)
                        detailCount(title: "Almost", value: competency.partial, systemImage: "circle.lefthalf.filled", tint: CheckpointTheme.amber)
                        detailCount(title: "Needs review", value: competency.incorrect, systemImage: "xmark.circle", tint: CheckpointTheme.coral)
                    }
                } else {
                    HStack(spacing: 8) {
                        detailCount(title: "Correct", value: competency.correct, systemImage: "checkmark.circle", tint: CheckpointTheme.teal)
                        detailCount(title: "Almost", value: competency.partial, systemImage: "circle.lefthalf.filled", tint: CheckpointTheme.amber)
                        detailCount(title: "Needs review", value: competency.incorrect, systemImage: "xmark.circle", tint: CheckpointTheme.coral)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    detailLine(systemImage: "clock", text: recencyText)

                    if competency.currentStreak > 0 {
                        Spacer(minLength: 8)
                        detailLine(systemImage: "flame", text: streakText)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    detailLine(systemImage: "clock", text: recencyText)

                    if competency.currentStreak > 0 {
                        detailLine(systemImage: "flame", text: streakText)
                    }
                }
            }

            if let lastResultText {
                detailLine(systemImage: "arrow.backward.circle", text: lastResultText)
            }

            if progressBand == .calibrating {
                detailLine(
                    systemImage: "info.circle",
                    text: "Early mastery estimate: \(competency.masteryPercent)%. It becomes fully weighted after 10 answers."
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func detailCount(
        title: String,
        value: Int,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .monospacedDigit()

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.64),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func detailLine(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var progress: Double {
        guard competency.attempts > 0 else { return 0 }

        if progressBand == .calibrating {
            return min(
                1,
                Double(competency.attempts) /
                    Double(CompetencyProgressBand.minimumReliableAttemptCount)
            )
        }

        return Double(competency.masteryPercent) / 100
    }

    private var metadataText: String {
        if progressBand == .calibrating {
            return recencyText
        }
        return "\(answerCountText) · \(recencyText)"
    }

    private var answerCountText: String {
        if progressBand == .calibrating {
            return "\(competency.attempts) of \(CompetencyProgressBand.minimumReliableAttemptCount) answers to calibrate"
        }

        switch competency.attempts {
        case 0:
            return "No answers yet"
        case 1:
            return "1 answer"
        default:
            return "\(competency.attempts) answers"
        }
    }

    private var streakText: String {
        "\(competency.currentStreak) correct in a row"
    }

    private var recencyText: String {
        CompetencyRecencyLabel.text(
            attempts: competency.attempts,
            lastPracticedAt: competency.lastPracticedAt
        )
    }

    private var lastResultText: String? {
        guard let lastResult = competency.lastResult else { return nil }
        switch lastResult {
        case .correct:
            return "Last answer correct"
        case .partial:
            return "Last answer almost"
        case .incorrect, .unclear:
            return "Last answer needs review"
        }
    }

    private var accessibilityValue: String {
        let mastery = competency.attempts == 0
            ? "No mastery estimate yet"
            : progressBand == .calibrating
                ? "\(competency.masteryPercent) percent early mastery estimate"
                : "\(competency.masteryPercent) percent mastery estimate"
        let breakdown = "\(competency.correct) correct, \(competency.partial) almost, \(competency.incorrect) need review"
        let lastResult = lastResultText.map { "\($0)." } ?? ""
        let streak = competency.currentStreak > 0 ? " \(streakText)." : ""
        let calibration = progressBand == .calibrating
            ? " The estimate becomes fully weighted after 10 answers."
            : ""
        return "\(progressBand.label). \(mastery). \(answerCountText). \(recencyText). \(breakdown). \(lastResult)\(streak)\(calibration) \(isExpanded ? "Expanded" : "Collapsed")."
    }

}
