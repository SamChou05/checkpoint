import SwiftUI

enum PracticeHistoryLayoutElement: Hashable {
    case viewport
    case header
    case summary
    case filter
    case resultStatus
    case timeline
    case firstAttempt
}

private struct PracticeHistoryLayoutFrameReporter: ViewModifier {
    let element: PracticeHistoryLayoutElement?
    let report: (@MainActor (PracticeHistoryLayoutElement, CGRect) -> Void)?

    func body(content: Content) -> some View {
        content.background {
            if let element, let report {
                GeometryReader { proxy in
                    let frame = proxy.frame(
                        in: .named(practiceHistoryLayoutCoordinateSpaceName)
                    )

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
    func reportPracticeHistoryLayoutFrame(
        _ element: PracticeHistoryLayoutElement?,
        using report: (@MainActor (PracticeHistoryLayoutElement, CGRect) -> Void)?
    ) -> some View {
        modifier(PracticeHistoryLayoutFrameReporter(element: element, report: report))
    }
}

let practiceHistoryLayoutCoordinateSpaceName = "Checkpoint.PracticeHistory.Layout"

struct HistoryView: View {
    let store: CheckpointStore
    let renderConfiguration: HistoryViewRenderConfiguration?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Namespace private var filterSelectionNamespace
    @State private var selectedFilter: PracticeHistoryFilter
    @State private var requestedScope: PracticeHistoryScope?
    @State private var scopeSelectionFeedbackSequence = 0
    @State private var resultChange: PracticeHistoryResultChange = .initial
    @State private var resultUpdateRequest: PracticeHistoryResultUpdateRequest?
    @State private var questionQualityFeedbackContext: QuestionQualityFeedbackContext?
    @AccessibilityFocusState(for: [.voiceOver, .switchControl])
    private var isResultStatusAccessibilityFocused: Bool

    init(
        store: CheckpointStore,
        renderConfiguration: HistoryViewRenderConfiguration? = nil
    ) {
        self.store = store
        self.renderConfiguration = renderConfiguration
        _selectedFilter = State(initialValue: renderConfiguration?.initialFilter ?? .all)
        _requestedScope = State(initialValue: renderConfiguration?.initialScope)
    }

    private var presentation: PracticeHistoryArchivePresentation {
        PracticeHistoryArchivePresentation(
            allAttempts: store.attempts,
            goalProfiles: store.availableGoalProfiles,
            activeGoalID: store.goal?.id,
            requestedScope: requestedScope,
            filter: selectedFilter,
            displayCalendar: calendar,
            displayLocale: locale,
            displayTimeZone: timeZone
        )
    }

    private var reduceMotion: Bool {
        renderConfiguration?.reduceMotion ?? systemReduceMotion
    }

    private var motionPolicy: PracticeHistoryMotionPolicy {
        PracticeHistoryMotionPolicy(
            reduceMotion: reduceMotion,
            assistiveNavigationEnabled: assistiveNavigationEnabled
        )
    }

    private var assistiveNavigationEnabled: Bool {
        renderConfiguration?.assistiveNavigationEnabled
            ?? (voiceOverEnabled || switchControlEnabled)
    }

    private var layoutReporter: (@MainActor (PracticeHistoryLayoutElement, CGRect) -> Void)? {
        renderConfiguration?.layoutReporter
    }

    private func dayGroups(
        for archive: PracticeHistoryArchivePresentation
    ) -> [PracticeHistoryDay] {
        Dictionary(grouping: archive.filteredAttempts) {
            calendar.startOfDay(for: $0.createdAt)
        }
        .map { PracticeHistoryDay(date: $0.key, attempts: $0.value) }
        .sorted { $0.date > $1.date }
    }

    private func accuracyProgress(
        for archive: PracticeHistoryArchivePresentation
    ) -> Double {
        guard !archive.scopedAttempts.isEmpty else { return 0 }
        return Double(archive.correctCount) / Double(archive.scopedAttempts.count)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { viewportProxy in
                let archive = presentation
                let layoutPolicy = PracticeHistoryLayoutPolicy(
                    viewportHeight: viewportProxy.size.height,
                    usesExpandedTypeLayout: usesExpandedTypeLayout
                )
                let usesMenuFilter = PracticeHistoryFilterLayoutPolicy.usesMenu(
                    viewportWidth: viewportProxy.size.width,
                    prefersExpandedTypeLayout: layoutPolicy.usesMenuFilter,
                    counts: PracticeHistoryFilter.allCases.map {
                        count(for: $0, in: archive)
                    }
                )

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(
                            alignment: .leading,
                            spacing: 0,
                            pinnedViews: layoutPolicy.pinsFilter
                                ? [.sectionHeaders]
                                : []
                        ) {
                            historyHeader(archive, layoutPolicy: layoutPolicy)
                                .padding(.bottom, layoutPolicy.sectionSpacing)
                                .reportPracticeHistoryLayoutFrame(
                                    .header,
                                    using: layoutReporter
                                )

                            if !archive.isGloballyEmpty && !archive.isScopeEmpty {
                                summaryHero(archive, density: layoutPolicy.summaryDensity)
                                    .transition(
                                        resultTransition(
                                            for: motionPolicy.style(for: .scope)
                                        )
                                    )
                                    .padding(.bottom, layoutPolicy.sectionSpacing - 2)
                                    .reportPracticeHistoryLayoutFrame(
                                        .summary,
                                        using: layoutReporter
                                    )
                            }

                            Color.clear
                                .frame(height: 0)
                                .id(PracticeHistoryScrollAnchor.results)

                            if archive.isGloballyEmpty {
                                emptyArchiveSection(
                                    archive,
                                    title: "Your answer log starts here",
                                    detail: "Complete a checkpoint and each answer will appear here, ready to revisit.",
                                    systemImage: "clock.arrow.circlepath"
                                )
                            } else if archive.isScopeEmpty {
                                emptyArchiveSection(
                                    archive,
                                    title: archive.scopeEmptyTitle,
                                    detail: archive.scopeEmptyDetail,
                                    systemImage: "scope"
                                )
                            } else {
                                Section {
                                    resultRegion(archive)
                                        .padding(.top, 8)
                                } header: {
                                    filterBar(
                                        archive,
                                        usesMenu: usesMenuFilter,
                                        stacksHeading: layoutPolicy.usesMenuFilter
                                    )
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 6)
                                    .background(CheckpointTheme.background)
                                    .padding(.horizontal, -20)
                                    .reportPracticeHistoryLayoutFrame(
                                        .filter,
                                        using: layoutReporter
                                    )
                                }
                                .transition(
                                    resultTransition(
                                        for: motionPolicy.style(for: .scope)
                                    )
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 36)
                    }
                    .reportPracticeHistoryLayoutFrame(.viewport, using: layoutReporter)
                    .onChange(of: resultUpdateRequest) { _, request in
                        resetResultsPosition(for: request, using: scrollProxy)
                    }
                }
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
            .sensoryFeedback(.selection, trigger: selectedFilter)
            .sensoryFeedback(.selection, trigger: scopeSelectionFeedbackSequence)
            .onAppear(perform: normalizeRequestedScopeIfNeeded)
            .onChange(of: store.availableGoalProfiles.map(\.id)) { _, _ in
                normalizeRequestedScopeIfNeeded()
            }
            .onDisappear {
                resultUpdateRequest = nil
                isResultStatusAccessibilityFocused = false
            }
        }
        .coordinateSpace(name: practiceHistoryLayoutCoordinateSpaceName)
    }

    private func historyHeader(
        _ archive: PracticeHistoryArchivePresentation,
        layoutPolicy: PracticeHistoryLayoutPolicy
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !usesExpandedTypeLayout {
                Text("YOUR PRACTICE")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(CheckpointTheme.muted)
            }

            Group {
                if usesExpandedTypeLayout {
                    historyHeaderStackedIdentity(archive)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 12) {
                            historyTitle
                            Spacer(minLength: 4)
                            scopeControl(archive, expands: false)
                        }

                        historyHeaderStackedIdentity(archive)
                    }
                }
            }

            if layoutPolicy.showsSupportingCopy {
                Text(archive.supportingCopy)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var historyTitle: some View {
        Text(usesExpandedTypeLayout ? "Answer log" : "Answer archive")
            .font(
                usesExpandedTypeLayout
                    ? .headline.weight(.bold)
                    : .title2.weight(.bold)
            )
            .foregroundStyle(CheckpointTheme.text)
            .lineLimit(usesExpandedTypeLayout ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func historyHeaderStackedIdentity(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            historyTitle
            scopeControl(archive, expands: true)
        }
    }

    @ViewBuilder
    private func scopeControl(
        _ archive: PracticeHistoryArchivePresentation,
        expands: Bool
    ) -> some View {
        if archive.showsScopePicker {
            Menu {
                scopeMenuButton(
                    archive,
                    scope: .all,
                    title: "All goals",
                    isCurrentGoal: false
                )

                Divider()

                ForEach(archive.goalOptions) { option in
                    scopeMenuButton(
                        archive,
                        scope: .goal(option.id),
                        title: option.title,
                        isCurrentGoal: option.isCurrent
                    )
                }
            } label: {
                scopeControlLabel(archive, showsChevron: true, expands: expands)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Practice history scope")
            .accessibilityValue(archive.scopeTitle)
            .accessibilityHint("Choose which goal's answers to view.")
        } else {
            scopeControlLabel(archive, showsChevron: false, expands: expands)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Practice history scope")
                .accessibilityValue(archive.scopeTitle)
        }
    }

    private func scopeControlLabel(
        _ archive: PracticeHistoryArchivePresentation,
        showsChevron: Bool,
        expands: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: archive.scope == .all ? "square.stack.3d.up.fill" : "scope")
                .font(.system(size: 11, weight: .bold))
                .accessibilityHidden(true)

            Text(archive.scopeTitle)
                .lineLimit(expands || usesExpandedTypeLayout ? nil : 1)
                .fixedSize(horizontal: !expands, vertical: true)

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(CheckpointTheme.teal)
        .padding(.horizontal, 11)
        .frame(maxWidth: expands ? .infinity : nil, minHeight: 44, alignment: .leading)
        .background {
            if expands || usesExpandedTypeLayout {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CheckpointTheme.teal.opacity(0.10))
            } else {
                Capsule()
                    .fill(CheckpointTheme.teal.opacity(0.10))
            }
        }
        .contentShape(Rectangle())
    }

    private func scopeMenuButton(
        _ archive: PracticeHistoryArchivePresentation,
        scope: PracticeHistoryScope,
        title: String,
        isCurrentGoal: Bool
    ) -> some View {
        Button {
            selectScope(scope, from: archive)
        } label: {
            Label {
                if isCurrentGoal {
                    Text("\(title) · current")
                } else {
                    Text(title)
                }
            } icon: {
                Image(
                    systemName: archive.scope == scope
                        ? "checkmark.circle.fill"
                        : "circle"
                )
            }
        }
    }

    private func summaryHero(
        _ archive: PracticeHistoryArchivePresentation,
        density: PracticeHistorySummaryDensity
    ) -> some View {
        Group {
            switch density {
            case .compact:
                compactSummaryHero(archive)
            case .expanded:
                if usesExpandedTypeLayout {
                    VStack(alignment: .leading, spacing: 18) {
                        summaryIdentity(archive)
                        accuracyRing(archive)
                        summaryMetrics(archive)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        summaryHeroLayout(archive, stacksIdentity: false)
                        summaryHeroLayout(archive, stacksIdentity: true)
                    }
                }
            }
        }
        .padding(
            density == .compact
                ? (usesExpandedTypeLayout ? 6 : 11)
                : 20
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CheckpointTheme.ink)
                .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(CheckpointTheme.mint.opacity(0.08))
                        .frame(width: 170, height: 170)
                        .blur(radius: 12)
                        .offset(x: 76, y: -92)
                        .allowsHitTesting(false)
                }
        )
        .shadow(
            color: CheckpointTheme.shadowElevated,
            radius: density == .compact ? 12 : 18,
            y: density == .compact ? 6 : 10
        )
        .accessibilityElement(children: .contain)
        .animation(
            motionPolicy.metricAnimation,
            value: archive.scopedAttempts.count
        )
        .animation(
            motionPolicy.metricAnimation,
            value: archive.correctCount
        )
    }

    private func compactSummaryHero(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        Group {
            if usesExpandedTypeLayout {
                expandedTypeCompactSummaryHero(archive)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 12) {
                            compactSummaryIdentity(archive, staysOnOneLine: true)
                            Spacer(minLength: 8)
                            compactAccuracy(archive)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            compactSummaryIdentity(archive, staysOnOneLine: false)
                            compactAccuracy(archive)
                        }
                    }

                    Divider()
                        .overlay(CheckpointTheme.heroDivider)

                    Text("\(archive.correctCount) correct · \(archive.reviewCount) to revisit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(summarySecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Practice record")
        .accessibilityValue(
            "\(archive.scopedAttempts.count) "
                + "\(archive.scopedAttempts.count == 1 ? "saved answer" : "saved answers"), "
                + "\(archive.accuracyPercent) percent accuracy, "
                + "\(archive.correctCount) correct, "
                + "\(archive.reviewCount) to revisit. "
                + archive.summaryContext
        )
    }

    private func expandedTypeCompactSummaryHero(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    expandedTypeAnswerCount(archive, staysOnOneLine: true)
                    Spacer(minLength: 6)
                    expandedTypeAccuracy(archive)
                }

                VStack(alignment: .leading, spacing: 3) {
                    expandedTypeAnswerCount(archive, staysOnOneLine: false)
                    expandedTypeAccuracy(archive)
                }
            }

            Divider()
                .overlay(CheckpointTheme.heroDivider)

            Text("\(archive.correctCount) correct · \(archive.reviewCount) revisit")
                .font(.caption.weight(.semibold))
                .foregroundStyle(summarySecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
        }
    }

    private func expandedTypeAnswerCount(
        _ archive: PracticeHistoryArchivePresentation,
        staysOnOneLine: Bool
    ) -> some View {
        Text(
            "\(archive.scopedAttempts.count) "
                + (archive.scopedAttempts.count == 1 ? "answer" : "answers")
        )
        .font(.headline.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(summaryText)
        .lineLimit(staysOnOneLine ? 1 : nil)
        .fixedSize(horizontal: staysOnOneLine, vertical: true)
        .contentTransition(.numericText(value: Double(archive.scopedAttempts.count)))
    }

    private func expandedTypeAccuracy(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(archive.accuracyPercent)%")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(archive.accuracyPercent)))

            Text("accuracy")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(CheckpointTheme.mint)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func compactSummaryIdentity(
        _ archive: PracticeHistoryArchivePresentation,
        staysOnOneLine: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(
                "\(archive.scopedAttempts.count) "
                    + (archive.scopedAttempts.count == 1 ? "saved answer" : "saved answers")
            )
            .font(.title3.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(summaryText)
            .lineLimit(staysOnOneLine ? 1 : nil)
            .fixedSize(horizontal: staysOnOneLine, vertical: true)
            .contentTransition(.numericText(value: Double(archive.scopedAttempts.count)))

            Text(archive.summaryContext)
                .font(.caption.weight(.medium))
                .foregroundStyle(summarySecondaryText)
        }
    }

    private func compactAccuracy(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        Text("\(archive.accuracyPercent)% accuracy")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(CheckpointTheme.mint)
            .fixedSize(horizontal: true, vertical: true)
            .contentTransition(.numericText(value: Double(archive.accuracyPercent)))
    }

    private func summaryHeroLayout(
        _ archive: PracticeHistoryArchivePresentation,
        stacksIdentity: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if stacksIdentity {
                VStack(alignment: .leading, spacing: 14) {
                    summaryIdentity(archive)
                    accuracyRing(archive)
                }
            } else {
                HStack(alignment: .center, spacing: 18) {
                    summaryIdentity(archive)
                    Spacer(minLength: 8)
                    accuracyRing(archive)
                }
            }

            Divider()
                .overlay(CheckpointTheme.heroDivider)

            summaryMetrics(archive)
        }
    }

    private func summaryIdentity(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PRACTICE RECORD")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(summarySecondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(archive.scopedAttempts.count)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(summaryText)
                    .contentTransition(.numericText(value: Double(archive.scopedAttempts.count)))

                Text(archive.scopedAttempts.count == 1 ? "answer" : "answers")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(summarySecondaryText)
            }

            Text(archive.summaryContext)
                .font(.caption.weight(.medium))
                .foregroundStyle(summarySecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func accuracyRing(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        ZStack {
            Circle()
                .stroke(CheckpointTheme.heroTrack, lineWidth: 7)

            Circle()
                .trim(from: 0, to: accuracyProgress(for: archive))
                .stroke(
                    CheckpointTheme.mint,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(archive.accuracyPercent)%")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(summaryText)
                    .contentTransition(.numericText(value: Double(archive.accuracyPercent)))

                Text("ACCURACY")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.55)
                    .foregroundStyle(summarySecondaryText)
            }
        }
        .frame(width: 84, height: 84)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(archive.accuracyPercent) percent accuracy")
        .animation(
            motionPolicy.metricAnimation,
            value: accuracyProgress(for: archive)
        )
    }

    private func summaryMetrics(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        Group {
            if usesExpandedTypeLayout {
                VStack(alignment: .leading, spacing: 14) {
                    summaryMetric(
                        value: archive.correctCount,
                        label: "CORRECT",
                        systemImage: "checkmark.circle.fill",
                        tint: CheckpointTheme.mint
                    )

                    summaryMetric(
                        value: archive.reviewCount,
                        label: "TO REVISIT",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: summaryAmber
                    )
                }
            } else {
                HStack(spacing: 24) {
                    summaryMetric(
                        value: archive.correctCount,
                        label: "CORRECT",
                        systemImage: "checkmark.circle.fill",
                        tint: CheckpointTheme.mint
                    )

                    summaryMetric(
                        value: archive.reviewCount,
                        label: "TO REVISIT",
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

    private func filterBar(
        _ archive: PracticeHistoryArchivePresentation,
        usesMenu: Bool,
        stacksHeading: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if stacksHeading {
                resultStatus(
                    archive,
                    alignment: .leading,
                    showsOrdering: false
                )
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        sectionLabel("ANSWER LOG")
                        Spacer(minLength: 8)
                        resultStatus(archive, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        sectionLabel("ANSWER LOG")
                        resultStatus(archive, alignment: .leading)
                    }
                }
            }

            Group {
                if usesMenu {
                    filterMenu(
                        archive,
                        usesCondensedLabel: stacksHeading
                    )
                } else {
                    HStack(spacing: 4) {
                        filterButtons(archive)
                    }
                }
            }
            .padding(usesMenu ? 2 : 4)
            .background(
                CheckpointTheme.panelRaised.opacity(0.78),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .animation(
                motionPolicy.metricAnimation,
                value: selectedFilter
            )
        }
    }

    private func resultRegion(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        let identity = PracticeHistoryResultIdentity(
            scope: archive.scope,
            filter: selectedFilter
        )

        return answerTimeline(archive)
            .id(identity)
            .transition(resultTransition(for: motionPolicy.style(for: resultChange)))
            .animation(motionPolicy.resultAnimation, value: identity)
            .reportPracticeHistoryLayoutFrame(.timeline, using: layoutReporter)
    }

    private func resultTransition(
        for style: PracticeHistoryResultTransitionStyle
    ) -> AnyTransition {
        switch style {
        case .identity:
            .identity
        case .opacity:
            .opacity
        case .forward:
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private func resultStatus(
        _ archive: PracticeHistoryArchivePresentation,
        alignment: HorizontalAlignment,
        showsOrdering: Bool = true
    ) -> some View {
        let status = PracticeHistoryResultStatusPresentation(
            filter: selectedFilter,
            resultCount: archive.filteredAttempts.count,
            scopeTitle: archive.scopeTitle
        )

        return VStack(alignment: alignment, spacing: 1) {
            Text(status.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(status.resultCount)))

            if showsOrdering, let orderingText = status.orderingText {
                Text(orderingText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(CheckpointTheme.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
        .accessibilityFocused($isResultStatusAccessibilityFocused)
        .animation(motionPolicy.metricAnimation, value: status.resultCount)
        .reportPracticeHistoryLayoutFrame(.resultStatus, using: layoutReporter)
    }

    private func filterMenu(
        _ archive: PracticeHistoryArchivePresentation,
        usesCondensedLabel: Bool
    ) -> some View {
        Menu {
            ForEach(PracticeHistoryFilter.allCases) { filter in
                Button {
                    selectFilter(filter)
                } label: {
                    Label(
                        "\(filter.accessibilityTitle), \(count(for: filter, in: archive))",
                        systemImage: filter == selectedFilter
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)

                Text(
                    usesCondensedLabel
                        ? selectedFilter.title
                        : "Filter: \(selectedFilter.title)"
                )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(CheckpointTheme.teal)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Answer filter")
        .accessibilityValue(
            "\(selectedFilter.accessibilityTitle), "
                + "\(archive.filteredAttempts.count) "
                + (archive.filteredAttempts.count == 1 ? "result" : "results")
        )
        .accessibilityHint("Choose which answers to review.")
    }

    @ViewBuilder
    private func filterButtons(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        ForEach(PracticeHistoryFilter.allCases) { filter in
            let isSelected = filter == selectedFilter

            Button {
                selectFilter(filter)
            } label: {
                HStack(spacing: 6) {
                    Text(filter.title)

                    Text("\(count(for: filter, in: archive))")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? CheckpointTheme.selectionText : CheckpointTheme.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            (isSelected ? CheckpointTheme.selectionCountFill : CheckpointTheme.hairline.opacity(0.45)),
                            in: Capsule()
                        )
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? CheckpointTheme.selectionText : CheckpointTheme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    filterSelectionPlate(isSelected: isSelected)
                }
            }
            .buttonStyle(CheckpointPressButtonStyle())
            .accessibilityLabel(
                "\(filter.accessibilityTitle), \(count(for: filter, in: archive))"
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    @ViewBuilder
    private func filterSelectionPlate(isSelected: Bool) -> some View {
        if isSelected {
            let plate = RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CheckpointTheme.selectionFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CheckpointTheme.actionBorder, lineWidth: 1)
                }

            if motionPolicy.usesMatchedGeometry {
                plate.matchedGeometryEffect(
                    id: "practice-history-filter-selection",
                    in: filterSelectionNamespace
                )
            } else {
                plate
            }
        }
    }

    private func answerTimeline(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        let retainedQuestionsByKey = Dictionary(
            store.questions.map {
                (
                    PracticeHistoryQuestionKey(goalID: $0.goalID, questionID: $0.id),
                    $0
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
        let questionReportsByKey = Dictionary(
            store.questionReports.map {
                (
                    PracticeHistoryQuestionKey(
                        goalID: $0.goalID,
                        questionID: $0.questionID
                    ),
                    $0
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
        let groups = dayGroups(for: archive)
        let isEmpty = groups.isEmpty

        return Group {
            if isEmpty {
                filteredEmptyState(archive)
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dayLabel(for: group.date).uppercased(with: locale))
                                .font(.caption2.weight(.bold))
                                .tracking(0.75)
                                .foregroundStyle(CheckpointTheme.muted)
                                .accessibilityAddTraits(.isHeader)

                            VStack(spacing: 0) {
                                ForEach(
                                    Array(group.attempts.enumerated()),
                                    id: \.element.id
                                ) { index, attempt in
                                    let questionKey = PracticeHistoryQuestionKey(
                                        goalID: attempt.goalID,
                                        questionID: attempt.questionID
                                    )
                                    let retainedQuestion = retainedQuestionsByKey[questionKey]
                                    let questionReport = questionReportsByKey[questionKey]

                                    AttemptRow(
                                        attempt: attempt,
                                        retainedQuestion: retainedQuestion,
                                        questionReport: questionReport,
                                        goalTitle: archive.showsGoalIdentity
                                            ? archive.goalTitle(for: attempt.goalID)
                                            : nil,
                                        timeText: archive.timeText(for: attempt),
                                        initiallyExpanded: renderConfiguration?
                                            .initiallyExpandedAttemptIDs
                                            .contains(attempt.id) == true,
                                        reduceMotionOverride: renderConfiguration?.reduceMotion
                                    ) {
                                        questionQualityFeedbackContext = QuestionQualityFeedbackContext(
                                            questionID: attempt.questionID,
                                            goalID: attempt.goalID,
                                            prompt: retainedQuestion?.prompt ?? attempt.prompt,
                                            existingReason: questionReport?.reason
                                        )
                                    }
                                    .reportPracticeHistoryLayoutFrame(
                                        attempt.id == archive.filteredAttempts.first?.id
                                            ? .firstAttempt
                                            : nil,
                                        using: layoutReporter
                                    )

                                    if index < group.attempts.count - 1 {
                                        Divider()
                                            .overlay(CheckpointTheme.hairline)
                                            .padding(.leading, 62)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(
                                    cornerRadius: CheckpointTheme.cardCornerRadius,
                                    style: .continuous
                                )
                                .fill(CheckpointTheme.panel.opacity(0.96))
                                .stroke(CheckpointTheme.hairline, lineWidth: 1)
                            )
                            .shadow(color: CheckpointTheme.shadowCard, radius: 12, y: 5)
                        }
                    }
                }
            }
        }
        .animation(
            motionPolicy.metricAnimation,
            value: isEmpty
        )
    }

    private func filteredEmptyState(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        Group {
            if usesExpandedTypeLayout {
                VStack(alignment: .leading, spacing: 12) {
                    filteredEmptyIcon
                    filteredEmptyCopy(archive)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    filteredEmptyIcon
                    filteredEmptyCopy(archive)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panel.opacity(0.88),
            in: RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
        )
        .transition(
            motionPolicy.usesRevealTransition
                ? .opacity.combined(with: .scale(scale: 0.98))
                : .identity
        )
    }

    private var filteredEmptyIcon: some View {
        Image(systemName: selectedFilter.emptySystemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 38, height: 38)
            .background(CheckpointTheme.teal.opacity(0.10), in: Circle())
            .accessibilityHidden(true)
    }

    private func filteredEmptyCopy(
        _ archive: PracticeHistoryArchivePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(archive.filteredEmptyTitle)
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)

            Text(archive.filteredEmptyDetail)
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emptyState(
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 52, height: 52)
                    .background(CheckpointTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(CheckpointTheme.text)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }

    private func emptyArchiveSection(
        _ archive: PracticeHistoryArchivePresentation,
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                sectionLabel("ANSWER LOG")
                resultStatus(archive, alignment: .leading)
            }
            .reportPracticeHistoryLayoutFrame(.filter, using: layoutReporter)

            emptyState(
                title: title,
                detail: detail,
                systemImage: systemImage
            )
        }
        .transition(resultTransition(for: motionPolicy.style(for: .scope)))
    }

    private func count(
        for filter: PracticeHistoryFilter,
        in archive: PracticeHistoryArchivePresentation
    ) -> Int {
        switch filter {
        case .all:
            return archive.scopedAttempts.count
        case .correct:
            return archive.correctCount
        case .review:
            return archive.reviewCount
        }
    }

    private func dayLabel(for date: Date) -> String {
        let referenceDate = renderConfiguration?.referenceDate ?? Date()
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return formatter.string(from: date)
    }

    private func selectScope(
        _ scope: PracticeHistoryScope,
        from archive: PracticeHistoryArchivePresentation
    ) {
        guard archive.scope != scope else { return }
        resultChange = .scope
        withAnimation(motionPolicy.resultAnimation) {
            requestedScope = scope
        }
        scopeSelectionFeedbackSequence += 1
        deliverUpdatedResultStatusAfterSelection(
            targetIdentity: PracticeHistoryResultIdentity(
                scope: scope,
                filter: selectedFilter
            ),
            change: .scope
        )
    }

    private func selectFilter(_ filter: PracticeHistoryFilter) {
        guard selectedFilter != filter else { return }
        let change = PracticeHistoryResultChange.filter(
            from: selectedFilter,
            to: filter
        )
        resultChange = change
        withAnimation(motionPolicy.resultAnimation) {
            selectedFilter = filter
        }
        deliverUpdatedResultStatusAfterSelection(
            targetIdentity: PracticeHistoryResultIdentity(
                scope: presentation.scope,
                filter: filter
            ),
            change: change
        )
    }

    private func deliverUpdatedResultStatusAfterSelection(
        targetIdentity: PracticeHistoryResultIdentity,
        change: PracticeHistoryResultChange
    ) {
        let request = PracticeHistoryResultUpdateRequest(
            target: targetIdentity,
            change: change
        )
        resultUpdateRequest = request

        let delivery = PracticeHistoryResultUpdateDeliveryPolicy.delivery(
            voiceOverEnabled: voiceOverEnabled,
            switchControlEnabled: switchControlEnabled
        )
        guard delivery != .none else { return }

        if delivery == .focusStatus {
            isResultStatusAccessibilityFocused = false
        }

        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(320))
            }
            guard resultUpdateRequest == request,
                  currentResultIdentity == request.target else { return }

            switch delivery {
            case .none:
                break
            case .focusStatus:
                isResultStatusAccessibilityFocused = true
            case .announceStatus:
                let archive = presentation
                let status = PracticeHistoryResultStatusPresentation(
                    filter: selectedFilter,
                    resultCount: archive.filteredAttempts.count,
                    scopeTitle: archive.scopeTitle
                )
                AccessibilityNotification.Announcement(
                    status.accessibilityLabel
                ).post()
            }
        }
    }

    private var currentResultIdentity: PracticeHistoryResultIdentity {
        PracticeHistoryResultIdentity(
            scope: presentation.scope,
            filter: selectedFilter
        )
    }

    private func resetResultsPosition(
        for request: PracticeHistoryResultUpdateRequest?,
        using proxy: ScrollViewProxy
    ) {
        guard let request else { return }

        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard resultUpdateRequest == request,
                  currentResultIdentity == request.target,
                  PracticeHistoryResultScrollPolicy.shouldReset(
                    after: request.change,
                    voiceOverEnabled: voiceOverEnabled,
                    switchControlEnabled: switchControlEnabled
                  ) else { return }

            withAnimation(
                motionPolicy.animatesResultReset
                    ? CheckpointMotion.change
                    : nil
            ) {
                proxy.scrollTo(PracticeHistoryScrollAnchor.results, anchor: .top)
            }
        }
    }

    private func normalizeRequestedScopeIfNeeded() {
        let resolvedScope = presentation.scope
        guard let requestedScope,
              requestedScope != resolvedScope else { return }
        self.requestedScope = resolvedScope
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.95)
            .foregroundStyle(CheckpointTheme.muted)
            .accessibilityAddTraits(.isHeader)
    }

    private var summaryText: Color {
        CheckpointTheme.heroText
    }

    private var summarySecondaryText: Color {
        CheckpointTheme.heroMuted
    }

    private var summaryAmber: Color {
        CheckpointTheme.heroWarning
    }

    private var usesExpandedTypeLayout: Bool {
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
}

struct HistoryViewRenderConfiguration {
    var initialScope: PracticeHistoryScope?
    var initialFilter: PracticeHistoryFilter = .all
    var initiallyExpandedAttemptIDs: Set<CheckpointAttempt.ID> = []
    var reduceMotion: Bool?
    var assistiveNavigationEnabled: Bool?
    var referenceDate: Date?
    var layoutReporter: (@MainActor (PracticeHistoryLayoutElement, CGRect) -> Void)?
}

enum PracticeHistoryScope: Hashable, Identifiable {
    case all
    case goal(Goal.ID)

    var id: String {
        switch self {
        case .all:
            "all"
        case .goal(let goalID):
            "goal-\(goalID.uuidString)"
        }
    }
}

struct PracticeHistoryGoalOption: Identifiable, Equatable {
    let id: Goal.ID
    let title: String
    let isCurrent: Bool
}

struct PracticeHistoryQuestionKey: Hashable {
    let goalID: Goal.ID
    let questionID: CheckpointQuestion.ID
}

enum PracticeHistorySummaryDensity: Equatable {
    case compact
    case expanded
}

struct PracticeHistoryLayoutPolicy: Equatable {
    let summaryDensity: PracticeHistorySummaryDensity
    let usesMenuFilter: Bool
    let pinsFilter: Bool
    let showsSupportingCopy: Bool
    let sectionSpacing: CGFloat

    init(viewportHeight: CGFloat, usesExpandedTypeLayout: Bool) {
        let usesCompactSummary = viewportHeight <= 700 || usesExpandedTypeLayout
        summaryDensity = usesCompactSummary ? .compact : .expanded
        usesMenuFilter = usesExpandedTypeLayout
        pinsFilter = !usesExpandedTypeLayout
        showsSupportingCopy = !usesCompactSummary
        sectionSpacing = usesCompactSummary ? 12 : 20
    }
}

enum PracticeHistoryFilterLayoutPolicy {
    static func usesMenu(
        viewportWidth: CGFloat,
        prefersExpandedTypeLayout: Bool,
        counts: [Int]
    ) -> Bool {
        if prefersExpandedTypeLayout {
            return true
        }

        let largestCountDigits = counts
            .map { String(max(0, $0)).count }
            .max() ?? 1
        return viewportWidth <= 340 || largestCountDigits >= 5
    }
}

enum PracticeHistoryResultChange: Equatable {
    case initial
    case filterForward
    case filterBackward
    case scope

    static func filter(
        from previous: PracticeHistoryFilter,
        to current: PracticeHistoryFilter
    ) -> Self {
        guard previous != current else { return .initial }
        return current.sortOrder > previous.sortOrder
            ? .filterForward
            : .filterBackward
    }
}

enum PracticeHistoryResultTransitionStyle: Equatable {
    case identity
    case opacity
    case forward
    case backward
}

struct PracticeHistoryResultIdentity: Hashable {
    let scope: PracticeHistoryScope
    let filter: PracticeHistoryFilter
}

struct PracticeHistoryResultUpdateRequest: Identifiable, Equatable {
    let id = UUID()
    let target: PracticeHistoryResultIdentity
    let change: PracticeHistoryResultChange
}

enum PracticeHistoryScrollAnchor: Hashable {
    case results
}

enum PracticeHistoryResultUpdateDelivery: Equatable {
    case none
    case focusStatus
    case announceStatus
}

enum PracticeHistoryResultUpdateDeliveryPolicy {
    static func delivery(
        voiceOverEnabled: Bool,
        switchControlEnabled: Bool
    ) -> PracticeHistoryResultUpdateDelivery {
        if voiceOverEnabled {
            return .focusStatus
        }
        if switchControlEnabled {
            return .announceStatus
        }
        return .none
    }
}

enum PracticeHistoryResultScrollPolicy {
    static func shouldReset(
        after change: PracticeHistoryResultChange,
        voiceOverEnabled: Bool,
        switchControlEnabled: Bool
    ) -> Bool {
        guard change != .initial else { return false }
        if change == .scope,
           switchControlEnabled,
           !voiceOverEnabled {
            return false
        }
        return true
    }
}

struct PracticeHistoryResultStatusPresentation: Equatable {
    let resultCount: Int
    let title: String
    let orderingText: String?
    let accessibilityLabel: String

    init(
        filter: PracticeHistoryFilter,
        resultCount: Int,
        scopeTitle: String
    ) {
        self.resultCount = max(0, resultCount)
        orderingText = self.resultCount == 0 ? nil : "Newest first"

        switch filter {
        case .all:
            title = "\(self.resultCount) "
                + (self.resultCount == 1 ? "answer" : "answers")
        case .correct:
            title = "\(self.resultCount) correct "
                + (self.resultCount == 1 ? "answer" : "answers")
        case .review:
            title = "\(self.resultCount) to revisit"
        }

        if let orderingText {
            accessibilityLabel = "Showing \(title) for \(scopeTitle). \(orderingText)."
        } else {
            accessibilityLabel = "Showing \(title) for \(scopeTitle)."
        }
    }
}

struct PracticeHistoryMotionPolicy: Equatable {
    let usesMatchedGeometry: Bool
    let usesRevealTransition: Bool
    let usesAssistiveNavigation: Bool
    let reducesMotion: Bool

    init(
        reduceMotion: Bool,
        assistiveNavigationEnabled: Bool = false
    ) {
        reducesMotion = reduceMotion
        usesAssistiveNavigation = assistiveNavigationEnabled
        usesMatchedGeometry = !reduceMotion && !assistiveNavigationEnabled
        usesRevealTransition = !reduceMotion && !assistiveNavigationEnabled
    }

    var resultAnimation: Animation? {
        reducesMotion ? nil : CheckpointMotion.change
    }

    var metricAnimation: Animation? {
        reducesMotion || usesAssistiveNavigation
            ? nil
            : CheckpointMotion.change
    }

    var animatesResultReset: Bool {
        !reducesMotion && !usesAssistiveNavigation
    }

    func style(
        for change: PracticeHistoryResultChange
    ) -> PracticeHistoryResultTransitionStyle {
        guard change != .initial else { return .identity }
        guard !reducesMotion else { return .identity }
        guard !usesAssistiveNavigation else { return .opacity }

        switch change {
        case .initial:
            return .identity
        case .filterForward:
            return .forward
        case .filterBackward:
            return .backward
        case .scope:
            return .opacity
        }
    }
}

struct PracticeHistoryArchivePresentation: Equatable {
    let scope: PracticeHistoryScope
    let goalOptions: [PracticeHistoryGoalOption]
    let scopedAttempts: [CheckpointAttempt]
    let filteredAttempts: [CheckpointAttempt]
    let correctCount: Int
    let reviewCount: Int
    let accuracyPercent: Int
    let showsScopePicker: Bool
    let showsGoalIdentity: Bool
    let scopeTitle: String
    let supportingCopy: String
    let summaryContext: String
    let isGloballyEmpty: Bool
    let isScopeEmpty: Bool
    let scopeEmptyTitle: String
    let scopeEmptyDetail: String
    let filteredEmptyTitle: String
    let filteredEmptyDetail: String

    private let goalTitlesByID: [Goal.ID: String]
    private let attemptTimesByID: [CheckpointAttempt.ID: String]

    init(
        allAttempts: [CheckpointAttempt],
        goalProfiles: [Goal],
        activeGoalID: Goal.ID?,
        requestedScope: PracticeHistoryScope?,
        filter: PracticeHistoryFilter,
        displayCalendar: Calendar = .current,
        displayLocale: Locale = .current,
        displayTimeZone: TimeZone = .current
    ) {
        let knownGoalIDs = Set(goalProfiles.map(\.id))
        let archiveGoalIDs = Set(allAttempts.map(\.goalID))
        let unavailableGoalIDs = archiveGoalIDs.subtracting(knownGoalIDs)
        let resolvedScope: PracticeHistoryScope

        switch requestedScope {
        case .all:
            resolvedScope = .all
        case .goal(let goalID) where knownGoalIDs.contains(goalID):
            resolvedScope = .goal(goalID)
        case .goal:
            resolvedScope = .all
        case nil where goalProfiles.count == 1 && unavailableGoalIDs.isEmpty:
            resolvedScope = .goal(goalProfiles[0].id)
        case nil:
            resolvedScope = .all
        }

        let titlesByID = GoalDisplayTitleResolver(
            goals: goalProfiles,
            calendar: displayCalendar,
            locale: displayLocale,
            timeZone: displayTimeZone
        ).titlesByID
        let options = goalProfiles.map { goal in
            PracticeHistoryGoalOption(
                id: goal.id,
                title: titlesByID[goal.id] ?? goal.title,
                isCurrent: goal.id == activeGoalID
            )
        }
        let sortedAttempts = allAttempts.sorted(by: Self.attemptComesBefore)
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = displayCalendar
        timeFormatter.locale = displayLocale
        timeFormatter.timeZone = displayTimeZone
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timesByID = Dictionary(
            sortedAttempts.map { ($0.id, timeFormatter.string(from: $0.createdAt)) },
            uniquingKeysWith: { first, _ in first }
        )
        let scoped: [CheckpointAttempt]

        switch resolvedScope {
        case .all:
            scoped = sortedAttempts
        case .goal(let goalID):
            scoped = sortedAttempts.filter { $0.goalID == goalID }
        }

        let correct = scoped.lazy.filter { $0.result == .correct }.count
        let review = scoped.count - correct
        let contributingGoalCount = Set(scoped.map(\.goalID)).count
        let resolvedTitle: String

        switch resolvedScope {
        case .all:
            resolvedTitle = "All goals"
        case .goal(let goalID):
            resolvedTitle = titlesByID[goalID] ?? "Unavailable goal"
        }

        scope = resolvedScope
        goalOptions = options
        scopedAttempts = scoped
        filteredAttempts = scoped.filter(filter.includes)
        correctCount = correct
        reviewCount = review
        accuracyPercent = scoped.isEmpty
            ? 0
            : Int((Double(correct) / Double(scoped.count)) * 100)
        showsScopePicker = !options.isEmpty && (options.count > 1 || !unavailableGoalIDs.isEmpty)
        showsGoalIdentity = resolvedScope == .all
            && (options.count > 1 || !unavailableGoalIDs.isEmpty)
        scopeTitle = resolvedTitle
        supportingCopy = resolvedScope == .all
            ? "Every answer across your goals, with useful misses kept easy to find."
            : "Every answer for \(resolvedTitle), with useful misses kept easy to find."
        summaryContext = resolvedScope == .all
            ? "Across \(contributingGoalCount) \(contributingGoalCount == 1 ? "goal" : "goals")"
            : "For this goal"
        isGloballyEmpty = sortedAttempts.isEmpty
        isScopeEmpty = scoped.isEmpty
        scopeEmptyTitle = "No answers for this goal yet"
        scopeEmptyDetail = "Complete a checkpoint for \(resolvedTitle) to start its history."

        switch filter {
        case .all:
            filteredEmptyTitle = "No answers yet"
            filteredEmptyDetail = resolvedScope == .all
                ? "Your next checkpoint will start this log."
                : "Complete a checkpoint for this goal to start its log."
        case .correct:
            filteredEmptyTitle = resolvedScope == .all
                ? "No correct answers yet"
                : "No correct answers for this goal yet"
            filteredEmptyDetail = "Keep practicing and your correct answers will collect here."
        case .review:
            filteredEmptyTitle = "Nothing to revisit"
            filteredEmptyDetail = resolvedScope == .all
                ? "Every recorded answer is correct."
                : "Every answer for this goal is correct."
        }

        goalTitlesByID = titlesByID
        attemptTimesByID = timesByID
    }

    func goalTitle(for goalID: Goal.ID) -> String {
        goalTitlesByID[goalID] ?? "Unavailable goal"
    }

    func timeText(for attempt: CheckpointAttempt) -> String {
        attemptTimesByID[attempt.id] ?? "Time unavailable"
    }

    private static func attemptComesBefore(
        _ lhs: CheckpointAttempt,
        _ rhs: CheckpointAttempt
    ) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString > rhs.id.uuidString
        }
        return lhs.createdAt > rhs.createdAt
    }

}

enum PracticeHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case correct
    case review

    var id: Self { self }

    var sortOrder: Int {
        switch self {
        case .all: 0
        case .correct: 1
        case .review: 2
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .correct: "Correct"
        case .review: "Revisit"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .all: "All answers"
        case .correct: "Correct answers"
        case .review: "Answers to revisit"
        }
    }

    var emptySystemImage: String {
        switch self {
        case .all: "clock.arrow.circlepath"
        case .correct: "checkmark.circle"
        case .review: "arrow.triangle.2.circlepath"
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
                  retainedQuestion.id == attempt.questionID,
                  retainedQuestion.goalID == attempt.goalID {
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
    var questionReport: QuestionQualityReport?
    var goalTitle: String?
    var timeText: String
    var reduceMotionOverride: Bool?
    var manageQuestion: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded: Bool

    init(
        attempt: CheckpointAttempt,
        retainedQuestion: CheckpointQuestion?,
        questionReport: QuestionQualityReport?,
        goalTitle: String? = nil,
        timeText: String,
        initiallyExpanded: Bool = false,
        reduceMotionOverride: Bool? = nil,
        manageQuestion: @escaping () -> Void
    ) {
        self.attempt = attempt
        self.retainedQuestion = retainedQuestion
        self.questionReport = questionReport
        self.goalTitle = goalTitle
        self.timeText = timeText
        self.reduceMotionOverride = reduceMotionOverride
        self.manageQuestion = manageQuestion
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                collapsedHeader
            }
            .buttonStyle(CheckpointPressButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(resultPresentation.label), "
                    + "\(timeText). "
                    + goalAccessibilityText
                    + removalAccessibilityText
                    + "Question: \(attempt.prompt)"
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

    @ViewBuilder
    private var collapsedHeader: some View {
        if usesFullWidthReviewLayout {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    resultIcon

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            resultLabel
                            removedBadge
                        }
                        timeLabel
                    }

                    Spacer(minLength: 4)
                    expansionChevron
                }

                promptText
                goalBadge
            }
            .padding(14)
            .contentShape(Rectangle())
        } else {
            HStack(alignment: .top, spacing: 12) {
                resultIcon

                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            resultLabel
                            removedBadge
                            timeLabel
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                resultLabel
                                removedBadge
                            }
                            timeLabel
                        }
                    }

                    promptText
                    goalBadge
                }

                Spacer(minLength: 4)
                expansionChevron
            }
            .padding(14)
            .contentShape(Rectangle())
        }
    }

    private var resultIcon: some View {
        Image(systemName: resultPresentation.systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(resultTint)
            .frame(width: 38, height: 38)
            .background(
                resultTint.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var promptText: some View {
        Text(attempt.prompt)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .multilineTextAlignment(.leading)
            .lineLimit(isExpanded || usesFullWidthReviewLayout ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var goalBadge: some View {
        if let goalTitle {
            Label {
                Text(goalTitle)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "flag.fill")
                    .accessibilityHidden(true)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CheckpointTheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                CheckpointTheme.panelRaised,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityHidden(true)
        }
    }

    private var expansionChevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.muted)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
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

            reviewDivider

            QuestionRemovalControl(report: questionReport, action: manageQuestion)
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

    @ViewBuilder
    private var removedBadge: some View {
        if questionReport != nil {
            Text(QuestionQualityFeedbackPresentation.historyBadgeTitle)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.45)
                .foregroundStyle(CheckpointTheme.teal)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
                .accessibilityHidden(true)
        }
    }

    private var removalAccessibilityText: String {
        guard let questionReport else { return "" }
        return "Removed from future practice, reason \(questionReport.reason.rawValue). "
    }

    private var goalAccessibilityText: String {
        guard let goalTitle else { return "" }
        return "Goal \(goalTitle). "
    }

    private var timeLabel: some View {
        Text(timeText)
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
