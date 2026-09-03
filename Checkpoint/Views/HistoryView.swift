import SwiftUI

struct HistoryView: View {
    let store: CheckpointStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedFilter: PracticeHistoryFilter = .all
    @State private var hasRevealedSummary = false

    private var attempts: [CheckpointAttempt] {
        store.activeAttempts.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var filteredAttempts: [CheckpointAttempt] {
        attempts.filter(selectedFilter.includes)
    }

    private var dayGroups: [PracticeHistoryDay] {
        Dictionary(grouping: filteredAttempts) {
            Calendar.current.startOfDay(for: $0.createdAt)
        }
        .map { PracticeHistoryDay(date: $0.key, attempts: $0.value) }
        .sorted { $0.date > $1.date }
    }

    private var correctCount: Int {
        attempts.lazy.filter { $0.result == .correct }.count
    }

    private var reviewCount: Int {
        attempts.count - correctCount
    }

    private var accuracyPercent: Int {
        guard !attempts.isEmpty else { return 0 }
        return Int((Double(correctCount) / Double(attempts.count)) * 100)
    }

    private var accuracyProgress: Double {
        guard !attempts.isEmpty else { return 0 }
        return Double(correctCount) / Double(attempts.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if attempts.isEmpty {
                        emptyState
                    } else {
                        historyHeader
                        summaryHero
                        filterBar
                        answerTimeline
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .checkpointScreenBackground()
            .navigationTitle("Practice history")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
            .onAppear {
                revealSummaryIfNeeded()
            }
            .sensoryFeedback(.selection, trigger: selectedFilter)
        }
    }

    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("YOUR PRACTICE")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(CheckpointTheme.muted)

            Text(store.goal?.title ?? "Current goal")
                .font(.title2.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Every answer, with the useful misses kept easy to find.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryHero: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 18) {
                    summaryIdentity
                    accuracyRing
                    summaryMetrics
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 18) {
                        summaryIdentity
                        Spacer(minLength: 8)
                        accuracyRing
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.11))

                    summaryMetrics
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CheckpointTheme.ink)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(CheckpointTheme.mint.opacity(0.08))
                        .frame(width: 170, height: 170)
                        .blur(radius: 12)
                        .offset(x: 76, y: -92)
                        .allowsHitTesting(false)
                }
        )
        .shadow(color: CheckpointTheme.ink.opacity(0.14), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: attempts.count
        )
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: correctCount
        )
    }

    private var summaryIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PRACTICE RECORD")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(summarySecondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(attempts.count)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(summaryText)
                    .contentTransition(.numericText(value: Double(attempts.count)))

                Text(attempts.count == 1 ? "answer" : "answers")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(summarySecondaryText)
            }

            Text("Across your current goal")
                .font(.caption.weight(.medium))
                .foregroundStyle(summarySecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var accuracyRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.11), lineWidth: 7)

            Circle()
                .trim(from: 0, to: hasRevealedSummary ? accuracyProgress : 0)
                .stroke(
                    CheckpointTheme.mint,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(accuracyPercent)%")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(summaryText)
                    .contentTransition(.numericText(value: Double(accuracyPercent)))

                Text("ACCURACY")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.55)
                    .foregroundStyle(summarySecondaryText)
            }
        }
        .frame(width: 84, height: 84)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accuracyPercent) percent accuracy")
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: accuracyProgress
        )
    }

    private var summaryMetrics: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    summaryMetric(
                        value: correctCount,
                        label: "CORRECT",
                        systemImage: "checkmark.circle.fill",
                        tint: CheckpointTheme.mint
                    )

                    summaryMetric(
                        value: reviewCount,
                        label: "NON-CORRECT",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: summaryAmber
                    )
                }
            } else {
                HStack(spacing: 24) {
                    summaryMetric(
                        value: correctCount,
                        label: "CORRECT",
                        systemImage: "checkmark.circle.fill",
                        tint: CheckpointTheme.mint
                    )

                    summaryMetric(
                        value: reviewCount,
                        label: "NON-CORRECT",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: summaryAmber
                    )
                }
            }
        }
    }

    private func summaryMetric(
        value: Int,
        label: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(summaryText)
                    .contentTransition(.numericText(value: Double(value)))

                Text(label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.55)
                    .foregroundStyle(summarySecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ANSWER LOG")

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 4) {
                        filterButtons
                    }
                } else {
                    HStack(spacing: 4) {
                        filterButtons
                    }
                }
            }
            .padding(4)
            .background(
                CheckpointTheme.panelRaised.opacity(0.78),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private var filterButtons: some View {
        ForEach(PracticeHistoryFilter.allCases) { filter in
            let isSelected = filter == selectedFilter

            Button {
                withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
                    selectedFilter = filter
                }
            } label: {
                HStack(spacing: 6) {
                    Text(filter.title)

                    Text("\(count(for: filter))")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? CheckpointTheme.mint : CheckpointTheme.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            (isSelected ? Color.white.opacity(0.09) : CheckpointTheme.hairline.opacity(0.45)),
                            in: Capsule()
                        )
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? summaryText : CheckpointTheme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    isSelected ? CheckpointTheme.ink : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .buttonStyle(CheckpointPressButtonStyle())
            .accessibilityLabel("\(filter.accessibilityTitle), \(count(for: filter))")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    @ViewBuilder
    private var answerTimeline: some View {
        let retainedQuestionsByID = Dictionary(
            store.questions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        if dayGroups.isEmpty {
            filteredEmptyState
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(dayGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayLabel(for: group.date).uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.75)
                            .foregroundStyle(CheckpointTheme.muted)
                            .accessibilityAddTraits(.isHeader)

                        VStack(spacing: 0) {
                            ForEach(Array(group.attempts.enumerated()), id: \.element.id) { index, attempt in
                                AttemptRow(
                                    attempt: attempt,
                                    retainedQuestion: retainedQuestionsByID[attempt.questionID]
                                )

                                if index < group.attempts.count - 1 {
                                    Divider()
                                        .overlay(CheckpointTheme.hairline)
                                        .padding(.leading, 62)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
                                .fill(CheckpointTheme.panel.opacity(0.96))
                                .stroke(CheckpointTheme.hairline, lineWidth: 1)
                        )
                        .shadow(color: CheckpointTheme.ink.opacity(0.05), radius: 12, y: 5)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private var filteredEmptyState: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selectedFilter == .correct ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 38, height: 38)
                .background(CheckpointTheme.teal.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedFilter.emptyTitle)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)

                Text(selectedFilter.emptyDetail)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panel.opacity(0.88),
            in: RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var emptyState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 52, height: 52)
                    .background(CheckpointTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)

                Text("Your practice record starts here")
                    .font(.title2.bold())
                    .foregroundStyle(CheckpointTheme.text)

                Text("Complete a checkpoint and each answer will appear here, ready to revisit whenever you want.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }

    private func count(for filter: PracticeHistoryFilter) -> Int {
        switch filter {
        case .all:
            return attempts.count
        case .correct:
            return correctCount
        case .review:
            return reviewCount
        }
    }

    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.95)
            .foregroundStyle(CheckpointTheme.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private func revealSummaryIfNeeded() {
        guard !hasRevealedSummary else { return }

        if reduceMotion {
            hasRevealedSummary = true
        } else {
            withAnimation(CheckpointMotion.reveal) {
                hasRevealedSummary = true
            }
        }
    }

    private var summaryText: Color {
        Color(red: 0.94, green: 0.98, blue: 0.96)
    }

    private var summarySecondaryText: Color {
        Color(red: 0.66, green: 0.75, blue: 0.71)
    }

    private var summaryAmber: Color {
        Color(red: 0.91, green: 0.72, blue: 0.35)
    }
}

private enum PracticeHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case correct
    case review

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .correct: "Correct"
        case .review: "Revisit"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: "No answers yet"
        case .correct: "No correct answers yet"
        case .review: "No answers to revisit"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .all: "All answers"
        case .correct: "Correct answers"
        case .review: "Non-correct answers"
        }
    }

    var emptyDetail: String {
        switch self {
        case .all: "Your next checkpoint will start this log."
        case .correct: "Keep practicing and your correct answers will collect here."
        case .review: "Every answer in this practice record is correct."
        }
    }

    func includes(_ attempt: CheckpointAttempt) -> Bool {
        switch self {
        case .all:
            true
        case .correct:
            attempt.result == .correct
        case .review:
            attempt.result != .correct
        }
    }
}

private struct PracticeHistoryDay: Identifiable {
    var date: Date
    var attempts: [CheckpointAttempt]

    var id: Date { date }
}

struct PracticeHistoryReviewPresentation: Equatable {
    let topic: String?
    let format: QuestionFormat?
    let userAnswer: String
    let referenceLabel: String?
    let referenceAnswer: String?
    let explanation: String?

    init(
        attempt: CheckpointAttempt,
        retainedQuestion: CheckpointQuestion? = nil
    ) {
        userAnswer = Self.nonEmpty(attempt.answer) ?? "No answer recorded"

        let candidateReferenceAnswer: String?

        if let snapshot = attempt.reviewSnapshot {
            // Presence makes the persisted review authoritative, including omitted content.
            topic = Self.nonEmpty(snapshot.topic)
            format = snapshot.format
            candidateReferenceAnswer = Self.nonEmpty(snapshot.referenceAnswer)
            explanation = Self.nonEmpty(snapshot.explanation)
        } else if let retainedQuestion,
                  retainedQuestion.id == attempt.questionID {
            topic = Self.nonEmpty(retainedQuestion.topic)
            format = retainedQuestion.format
            candidateReferenceAnswer = Self.nonEmpty(
                AnswerGrader.correctAnswerText(
                    for: retainedQuestion,
                    after: attempt.result
                )
            )
            explanation = Self.nonEmpty(retainedQuestion.explanation)
        } else {
            topic = nil
            format = nil
            candidateReferenceAnswer = nil
            explanation = nil
        }

        if attempt.result != .correct,
           let format,
           let candidateReferenceAnswer {
            referenceLabel = CheckpointAnswerReviewPresentation.answerLabel(for: format)
            referenceAnswer = candidateReferenceAnswer
        } else {
            referenceLabel = nil
            referenceAnswer = nil
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

}

private struct AttemptRow: View {
    var attempt: CheckpointAttempt
    var retainedQuestion: CheckpointQuestion?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: resultPresentation.systemImage)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(resultTint)
                        .frame(width: 38, height: 38)
                        .background(
                            resultTint.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                resultLabel
                                timeLabel
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                resultLabel
                                timeLabel
                            }
                        }

                        Text(attempt.prompt)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isExpanded || usesFullWidthReviewLayout ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckpointTheme.muted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(CheckpointPressButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(resultPresentation.label), "
                    + "\(attempt.createdAt.formatted(date: .omitted, time: .shortened)). "
                    + attempt.prompt
            )
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hides the answer review" : "Shows the answer review")

            if isExpanded {
                Divider()
                    .overlay(CheckpointTheme.hairline)
                    .padding(.leading, usesFullWidthReviewLayout ? 14 : 64)

                expandedReview
                    .transition(reviewTransition)
            }
        }
    }

    private var expandedReview: some View {
        let review = PracticeHistoryReviewPresentation(
            attempt: attempt,
            retainedQuestion: retainedQuestion
        )

        return VStack(alignment: .leading, spacing: 14) {
            if let topic = review.topic {
                Label {
                    Text(topic)
                        .lineLimit(usesFullWidthReviewLayout ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "scope")
                        .accessibilityHidden(true)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    if usesFullWidthReviewLayout {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CheckpointTheme.teal.opacity(0.09))
                    } else {
                        Capsule()
                            .fill(CheckpointTheme.teal.opacity(0.09))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Skill")
                .accessibilityValue(topic)
            }

            reviewSection(
                label: "Your answer",
                text: review.userAnswer,
                font: answerFont(for: review.format, emphasized: false),
                color: CheckpointTheme.text
            )

            if let referenceLabel = review.referenceLabel,
               let referenceAnswer = review.referenceAnswer {
                reviewDivider

                reviewSection(
                    label: referenceLabel,
                    text: referenceAnswer,
                    font: answerFont(for: review.format, emphasized: true),
                    color: CheckpointTheme.text
                )
            }

            if let explanation = review.explanation {
                reviewDivider

                reviewSection(
                    label: "Explanation",
                    text: explanation,
                    font: .footnote,
                    color: CheckpointTheme.muted
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.62),
            in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius, style: .continuous)
        )
        .padding(.leading, usesFullWidthReviewLayout ? 14 : 64)
        .padding(.trailing, 14)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .accessibilityElement(children: .contain)
    }

    private func reviewSection(
        label: String,
        text: String,
        font: Font,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.55)
                .foregroundStyle(CheckpointTheme.muted)

            Text(text)
                .font(font)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(text)
    }

    private var reviewDivider: some View {
        Divider()
            .overlay(CheckpointTheme.hairline)
            .accessibilityHidden(true)
    }

    private func answerFont(
        for format: QuestionFormat?,
        emphasized: Bool
    ) -> Font {
        let font: Font = format == .codeTrace
            ? .system(.subheadline, design: .monospaced)
            : .subheadline
        return emphasized ? font.weight(.semibold) : font
    }

    private var usesFullWidthReviewLayout: Bool {
        switch dynamicTypeSize {
        case .xxLarge,
             .xxxLarge,
             .accessibility1,
             .accessibility2,
             .accessibility3,
             .accessibility4,
             .accessibility5:
            true
        default:
            false
        }
    }

    private var reviewTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
    }

    private var resultLabel: some View {
        Text(resultPresentation.label.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.55)
            .foregroundStyle(resultTint)
    }

    private var timeLabel: some View {
        Text(attempt.createdAt.formatted(date: .omitted, time: .shortened))
            .font(.caption2.weight(.medium))
            .foregroundStyle(CheckpointTheme.muted)
    }

    private var resultPresentation: CheckpointAnswerResultPresentation {
        CheckpointAnswerResultPresentation(result: attempt.result)
    }

    private var resultTint: Color {
        switch resultPresentation.tone {
        case .success:
            CheckpointTheme.teal
        case .warning:
            CheckpointTheme.amber
        case .failure:
            CheckpointTheme.coral
        }
    }
}
