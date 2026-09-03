import SwiftUI

struct ProgressDashboardSummary: Equatable {
    var totalSkillCount: Int
    var practicedSkillCount: Int
    var strongSkillCount: Int
    var calibratingSkillCount: Int
    var lastPracticedAt: Date?
    var allSkillsAreStrong: Bool

    init(competencies: [TopicCompetency], attemptDates: [Date] = []) {
        totalSkillCount = competencies.count
        practicedSkillCount = competencies.filter { $0.attempts > 0 }.count
        strongSkillCount = competencies.filter {
            CompetencyProgressBand.resolve(for: $0) == .strong
        }.count
        calibratingSkillCount = competencies.filter {
            CompetencyProgressBand.resolve(for: $0) == .calibrating
        }.count
        lastPracticedAt = (
            attemptDates + competencies.compactMap(\.lastPracticedAt)
        ).max()
        allSkillsAreStrong = totalSkillCount > 0 && strongSkillCount == totalSkillCount
    }

    var coverageProgress: Double {
        guard totalSkillCount > 0 else { return 0 }
        return Double(practicedSkillCount) / Double(totalSkillCount)
    }

    var unpracticedSkillCount: Int {
        max(0, totalSkillCount - practicedSkillCount)
    }

    func lastPracticedValue(
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let lastPracticedAt else {
            return practicedSkillCount > 0 ? "Earlier" : "Not yet"
        }
        if calendar.isDate(lastPracticedAt, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(lastPracticedAt, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if calendar.component(.year, from: lastPracticedAt) == calendar.component(.year, from: now) {
            return lastPracticedAt.formatted(.dateTime.month(.abbreviated).day())
        }
        return lastPracticedAt.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

struct ProgressDashboardNarrative: Equatable {
    var title: String
    var detail: String

    init(summary: ProgressDashboardSummary) {
        if summary.allSkillsAreStrong {
            title = "All \(summary.totalSkillCount) active skills look strong"
            detail = "Keep practicing to keep these estimates current."
        } else if summary.practicedSkillCount == 0 {
            title = "Your map is ready for its first signals"
            detail = "Your first answers will begin calibrating each skill."
        } else if summary.unpracticedSkillCount > 0 {
            let count = summary.unpracticedSkillCount
            title = count == 1
                ? "1 skill still needs a first signal"
                : "\(count) skills still need first signals"
            detail = count == 1
                ? "Practice it once to complete your skill coverage."
                : "Practice each one once to complete your skill coverage."
        } else if summary.calibratingSkillCount > 0 {
            let count = summary.calibratingSkillCount
            title = "\(count) \(count == 1 ? "skill is" : "skills are") still calibrating"
            detail = "Each estimate becomes fully weighted after 10 answers in that skill."
        } else {
            title = "Your active skill signals are established"
            detail = "Regular practice will show what is strengthening and what needs another pass."
        }
    }
}

private struct ProgressScreenSnapshot: Hashable {
    enum Stage: Hashable {
        case noGoal
        case building
        case generationFailure
        case repair
        case suggested
        case reviewed
        case empty
    }

    var goalID: Goal.ID?
    var stage: Stage
}

private enum ProgressScrollAnchor: Hashable {
    case top
}

private enum ProgressAccessibilityFocus: Hashable {
    case goalTitle(Goal.ID)
    case primaryState(ProgressScreenSnapshot)
}

enum ProgressStateMotionStyle: Equatable {
    case choreographed
    case identity
}

struct ProgressStateMotionPolicy {
    var style: ProgressStateMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .choreographed
    }

    var animation: Animation? {
        style == .identity ? nil : CheckpointMotion.reveal
    }

    var transition: AnyTransition {
        switch style {
        case .choreographed:
            .asymmetric(
                insertion: .opacity.combined(
                    with: .scale(scale: 0.99, anchor: .top)
                ),
                removal: .opacity
            )
        case .identity:
            .identity
        }
    }
}

struct ProgressScreenChangePolicy {
    static func resetsGoalScopedPresentation(
        from previousGoalID: Goal.ID?,
        to currentGoalID: Goal.ID?
    ) -> Bool {
        previousGoalID != currentGoalID
    }
}

private struct FocusWinsDestination: Identifiable {
    let goalID: Goal.ID
    let goalTitle: String

    var id: Goal.ID { goalID }
}

struct CompetencyView: View {
    let store: CheckpointStore
    private let reduceMotionOverride: Bool?
    private let isVisible: Bool
    private let isCoveredByParentModal: Bool

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroMetricSize: CGFloat = 54
    @State private var isSkillMapEditorPresented = false
    @State private var isSkillMapRepairPresented = false
    @State private var isSkillMapModalActive = false
    @State private var isSkillHistoryExpanded = false
    @State private var retryingInitialQuestionGoalIDs: Set<Goal.ID> = []
    @State private var focusWinsDestination: FocusWinsDestination?
    @State private var pendingAccessibilityFocus: ProgressAccessibilityFocus?
    @AccessibilityFocusState(for: .voiceOver)
    private var accessibilityFocus: ProgressAccessibilityFocus?

    init(
        store: CheckpointStore,
        reduceMotionOverride: Bool? = nil,
        isVisible: Bool = true,
        isCoveredByParentModal: Bool = false
    ) {
        self.store = store
        self.reduceMotionOverride = reduceMotionOverride
        self.isVisible = isVisible
        self.isCoveredByParentModal = isCoveredByParentModal
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var usesStackedTypeLayout: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge ||
            dynamicTypeSize.isAccessibilitySize
    }

    private var competencies: [TopicCompetency] {
        store.activeProgressCompetencies
    }

    private var dashboardSummary: ProgressDashboardSummary {
        ProgressDashboardSummary(
            competencies: competencies,
            attemptDates: store.activeAttempts.map(\.createdAt)
        )
    }

    private var dashboardNarrative: ProgressDashboardNarrative {
        ProgressDashboardNarrative(summary: dashboardSummary)
    }

    private var focusState: StudyFocusState? {
        store.studyFocusState
    }

    private var screenSnapshot: ProgressScreenSnapshot {
        let stage: ProgressScreenSnapshot.Stage
        if store.goal == nil {
            stage = .noGoal
        } else if store.isPreparingActiveGoalQuestions {
            stage = .building
        } else if shouldShowQuestionGenerationFailure {
            stage = .generationFailure
        } else if store.activeSkillMapNeedsAttention {
            stage = .repair
        } else if store.activeDerivedSkillMap?.status == .suggested {
            stage = .suggested
        } else if store.activeDerivedSkillMap?.status == .reviewed {
            stage = .reviewed
        } else {
            stage = .empty
        }
        return ProgressScreenSnapshot(goalID: store.goal?.id, stage: stage)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        progressHeader
                            .id(ProgressScrollAnchor.top)
                            .padding(.bottom, 20)

                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 20) {
                                progressStateContent
                            }
                            .id(screenSnapshot)
                            .transition(progressStateMotionPolicy.transition)
                        }
                        .animation(
                            progressStateMotionPolicy.animation,
                            value: screenSnapshot
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 56)
                }
                .padding(.bottom, 48)
                .checkpointScreenBackground()
                .navigationTitle("Progress")
                .toolbarTitleDisplayMode(.inline)
                .onChange(of: screenSnapshot) { previous, current in
                    if ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                        from: previous.goalID,
                        to: current.goalID
                    ) {
                        isSkillHistoryExpanded = false
                        resetScrollPosition(
                            afterSwitchTo: current.goalID,
                            using: scrollProxy
                        )
                    }
                    respondToScreenChangeAfterLayout(from: previous, to: current)
                }
                .sensoryFeedback(.selection, trigger: store.goal?.id)
            }
        }
        .onChange(of: isVisible) { _, currentIsVisible in
            if !currentIsVisible {
                accessibilityFocus = nil
                pendingAccessibilityFocus = nil
            }
        }
        .onChange(of: isCoveredByParentModal) { _, isCovered in
            if !isCovered {
                applyPendingAccessibilityFocusAfterDismiss()
            }
        }
        .sheet(
            isPresented: $isSkillMapEditorPresented,
            onDismiss: finishSkillMapModalPresentation
        ) {
            SkillMapReviewView(store: store)
                .onAppear {
                    isSkillMapModalActive = true
                }
        }
        .sheet(
            isPresented: $isSkillMapRepairPresented,
            onDismiss: finishSkillMapModalPresentation
        ) {
            SkillMapRepairView(store: store)
                .onAppear {
                    isSkillMapModalActive = true
                }
        }
        .sheet(item: $focusWinsDestination) { destination in
            FocusWinsView(
                store: store,
                goalID: destination.goalID,
                goalTitle: destination.goalTitle
            )
        }
    }

    @ViewBuilder
    private var progressStateContent: some View {
        if store.goal == nil {
            emptyState
        } else if store.isPreparingActiveGoalQuestions {
            buildingSkillMapState
            activeGoalFocusWinsEntry
        } else if shouldShowQuestionGenerationFailure {
            questionGenerationFailureState
            activeGoalFocusWinsEntry
        } else if store.activeSkillMapNeedsAttention {
            skillMapAttentionState

            if !competencies.isEmpty {
                focusAreasPanel(
                    title: "Recent signals",
                    description: "Your existing practice history stays visible while you set up the new map."
                )
            }

            activeGoalFocusWinsEntry
        } else if dashboardSummary.totalSkillCount == 0 {
            emptyState
            activeGoalFocusWinsEntry
        } else {
            if store.activeDerivedSkillMap?.status == .suggested {
                suggestedSkillMapCallout
            }

            progressHero
            nextFocusPanel
            activeGoalFocusWinsEntry
            focusAreasPanel(title: "Focus areas")

            if let skillMap = store.activeDerivedSkillMap,
               skillMap.status == .reviewed {
                skillMapManagementPanel(skillMap)
            }
        }
    }

    @ViewBuilder
    private var activeGoalFocusWinsEntry: some View {
        if let goal = store.goal {
            focusWinsEntry(for: goal)
        }
    }

    private var progressStateMotionPolicy: ProgressStateMotionPolicy {
        ProgressStateMotionPolicy(reduceMotion: reduceMotion)
    }

    private var isRetryingInitialQuestions: Bool {
        guard let goalID = store.goal?.id else { return false }
        return retryingInitialQuestionGoalIDs.contains(goalID)
    }

    private func resetScrollPosition(
        afterSwitchTo goalID: Goal.ID?,
        using proxy: ScrollViewProxy
    ) {
        Task { @MainActor in
            await Task.yield()
            guard screenSnapshot.goalID == goalID else { return }

            if reduceMotion {
                proxy.scrollTo(ProgressScrollAnchor.top, anchor: .top)
            } else {
                withAnimation(CheckpointMotion.change) {
                    proxy.scrollTo(ProgressScrollAnchor.top, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private var progressHeader: some View {
        if let goal = store.goal {
            VStack(alignment: .leading, spacing: 10) {
                if usesStackedTypeLayout {
                    VStack(alignment: .leading, spacing: 12) {
                        goalIdentity(goal)
                        goalSwitcherIfNeeded(currentGoal: goal)
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        goalEyebrow
                        Spacer(minLength: 8)
                        goalSwitcherIfNeeded(currentGoal: goal)
                    }

                    goalTitle(goal)
                }

                Text("A live view of what is taking hold and where the next checkpoint can help most.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR LEARNING MAP")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(CheckpointTheme.muted)

                Text("Progress starts with a clear goal")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
            }
        }
    }

    private func goalIdentity(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            goalEyebrow
            goalTitle(goal)
        }
    }

    private var goalEyebrow: some View {
        Text("YOUR LEARNING MAP")
            .font(.caption2.weight(.bold))
            .tracking(1)
            .foregroundStyle(CheckpointTheme.muted)
    }

    private func goalTitle(_ goal: Goal) -> some View {
        Text(goal.title)
            .font(.title2.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .lineLimit(usesStackedTypeLayout ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityFocused($accessibilityFocus, equals: .goalTitle(goal.id))
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func goalSwitcherIfNeeded(currentGoal: Goal) -> some View {
        if store.availableGoalProfiles.count > 1 {
            Menu {
                ForEach(store.availableGoalProfiles) { profile in
                    Button {
                        store.switchActiveGoal(to: profile.id)
                    } label: {
                        Label(
                            goalMenuTitle(profile),
                            systemImage: goalMenuSystemImage(profile, currentGoal: currentGoal)
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Current goal")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckpointTheme.teal)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
                .background(CheckpointTheme.teal.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Current goal: \(currentGoal.title)")
            .accessibilityHint("Changes the active goal throughout Checkpoint.")
        }
    }

    private func goalMenuTitle(_ profile: Goal) -> String {
        let duplicateTitleCount = store.availableGoalProfiles.filter {
            $0.title.compare(profile.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }.count
        guard duplicateTitleCount > 1 else { return profile.title }
        let dueDate = profile.deadline.formatted(.dateTime.month(.abbreviated).day())
        return "\(profile.title) · due \(dueDate)"
    }

    private func goalMenuSystemImage(_ profile: Goal, currentGoal: Goal) -> String {
        if profile.id == currentGoal.id {
            return "checkmark.circle.fill"
        }
        return store.isMember ? "circle" : "lock.fill"
    }

    private func focusWinsEntry(for goal: Goal) -> some View {
        let count = store.focusWins(for: goal.id).count

        return Button {
            focusWinsDestination = FocusWinsDestination(
                goalID: goal.id,
                goalTitle: goal.title
            )
        } label: {
            SectionPanel {
                ViewThatFits(in: .horizontal) {
                    focusWinsInlineLayout(count: count)
                    focusWinsStackedLayout(count: count)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus Wins")
        .accessibilityValue(focusWinsAccessibilityValue(count))
        .accessibilityHint("Opens Focus Wins for \(goal.title).")
    }

    private func focusWinsInlineLayout(count: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            focusWinsIcon

            VStack(alignment: .leading, spacing: 4) {
                Text("Focus Wins")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)

                focusWinsDetail
            }
            .frame(minWidth: 145, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 4)

            HStack(spacing: 7) {
                focusWinsCount(count)
                focusWinsChevron
            }
        }
    }

    private func focusWinsStackedLayout(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                focusWinsIcon

                Text("Focus Wins")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
            }

            focusWinsDetail

            HStack(spacing: 7) {
                Spacer(minLength: 0)
                focusWinsCount(count)
                focusWinsChevron
            }
        }
    }

    private var focusWinsIcon: some View {
        Image(systemName: "note.text")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 44, height: 44)
            .background(
                CheckpointTheme.teal.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var focusWinsDetail: some View {
        Text("Keep a private note of progress you noticed toward this goal.")
            .font(.subheadline)
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func focusWinsCount(_ count: Int) -> some View {
        Text(focusWinsCountLabel(count))
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var focusWinsChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.teal)
            .accessibilityHidden(true)
    }

    private func focusWinsCountLabel(_ count: Int) -> String {
        switch count {
        case 0: "No notes"
        case 1: "1 note"
        default: "\(count) notes"
        }
    }

    private func focusWinsAccessibilityValue(_ count: Int) -> String {
        count == 0
            ? "No entries logged by you"
            : "\(count) \(count == 1 ? "entry" : "entries") logged by you"
    }

    private var progressHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            if usesStackedTypeLayout {
                VStack(alignment: .leading, spacing: 12) {
                    coverageMetric
                    coverageLabel
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    coverageMetric
                    coverageLabel
                    Spacer(minLength: 0)
                }
            }

            coverageTrack

            Divider()
                .overlay(CheckpointTheme.heroDivider)

            heroSupportingMetrics

            Divider()
                .overlay(CheckpointTheme.heroDivider)

            progressNarrative
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CheckpointTheme.ink)
                .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(heroAccent.opacity(0.08))
                        .frame(width: 180, height: 180)
                        .blur(radius: 12)
                        .offset(x: 82, y: -100)
                        .allowsHitTesting(false)
                }
        )
        .shadow(color: CheckpointTheme.shadowElevated, radius: 18, y: 10)
        .accessibilityElement(children: .contain)
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: dashboardSummary
        )
    }

    @ViewBuilder
    private var coverageMetric: some View {
        if screenSnapshot.stage == .reviewed {
            coverageMetricContent
                .accessibilityFocused(
                    $accessibilityFocus,
                    equals: .primaryState(screenSnapshot)
                )
        } else {
            coverageMetricContent
        }
    }

    private var coverageMetricContent: some View {
        Text("\(dashboardSummary.practicedSkillCount)/\(dashboardSummary.totalSkillCount)")
            .font(.system(size: heroMetricSize, weight: .bold, design: .rounded))
            .foregroundStyle(heroText)
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityLabel(coverageAccessibilityLabel)
    }

    private var coverageLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(
                store.activeDerivedSkillMap?.status == .suggested
                    ? "DRAFT SKILL COVERAGE"
                    : "ACTIVE SKILL COVERAGE"
            )
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(heroSecondaryText)

            Text("practiced at least once")
                .font(.caption.weight(.semibold))
                .foregroundStyle(heroSecondaryText)
        }
        .accessibilityHidden(true)
    }

    private var coverageAccessibilityLabel: String {
        let mapState = store.activeDerivedSkillMap?.status == .suggested
            ? "Draft learning map"
            : "Active learning map"
        return "\(mapState), \(dashboardSummary.practicedSkillCount) of \(dashboardSummary.totalSkillCount) skills practiced"
    }

    private var coverageTrack: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CheckpointTheme.heroTrack)

                Capsule()
                    .fill(heroAccent)
                    .frame(width: proxy.size.width * dashboardSummary.coverageProgress)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: dashboardSummary.coverageProgress
        )
    }

    @ViewBuilder
    private var heroSupportingMetrics: some View {
        if usesStackedTypeLayout {
            VStack(alignment: .leading, spacing: 14) {
                strongHeroMetric
                calibratingHeroMetric
                lastPracticedHeroMetric
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                if dashboardSummary.strongSkillCount > 0 {
                    strongHeroMetric
                    Spacer(minLength: 4)
                }
                if dashboardSummary.calibratingSkillCount > 0 {
                    calibratingHeroMetric
                    Spacer(minLength: 4)
                }
                lastPracticedHeroMetric
            }
        }
    }

    @ViewBuilder
    private var strongHeroMetric: some View {
        if dashboardSummary.strongSkillCount > 0 {
            heroMetric(
                value: dashboardSummary.strongSkillCount,
                label: "STRONG",
                systemImage: "checkmark.seal.fill"
            )
        }
    }

    @ViewBuilder
    private var calibratingHeroMetric: some View {
        if dashboardSummary.calibratingSkillCount > 0 {
            heroMetric(
                value: dashboardSummary.calibratingSkillCount,
                label: "CALIBRATING",
                systemImage: "scope"
            )
        }
    }

    private var lastPracticedHeroMetric: some View {
        heroTextMetric(
            value: lastPracticedValue,
            label: "LAST PRACTICED",
            systemImage: "clock.fill"
        )
    }

    private func heroMetric(value: Int, label: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(heroAccent)
                    .accessibilityHidden(true)

                Text("\(value)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(heroText)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
            }

            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(heroSecondaryText)
                .fixedSize(horizontal: true, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func heroTextMetric(value: String, label: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(heroAccent)
                    .accessibilityHidden(true)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(heroText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(heroSecondaryText)
                .fixedSize(horizontal: true, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var progressNarrative: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dashboardNarrative.title)
                .font(.headline)
                .foregroundStyle(heroText)
                .fixedSize(horizontal: false, vertical: true)

            Text(dashboardNarrative.detail)
                .font(.footnote.weight(.medium))
                .foregroundStyle(heroSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var lastPracticedValue: String {
        dashboardSummary.lastPracticedValue()
    }

    private var nextFocusPanel: some View {
        Group {
            if store.activeDerivedSkillMap?.status == .reviewed {
                if !store.canUse(.adaptiveStudyAssist) {
                    guidedReviewUpgradePanel
                        .transition(nextFocusTransition)
                } else if let focusState {
                    switch focusState {
                    case let .recommendation(recommendation):
                        guidedReviewPanel(recommendation)
                            .transition(nextFocusTransition)
                    case .awaitingQuestion, .caughtUp:
                        guidedReviewStatusPanel(focusState)
                            .transition(nextFocusTransition)
                    }
                }
            }
        }
        .animation(
            CheckpointMotion.animation(CheckpointMotion.reveal, reduceMotion: reduceMotion),
            value: focusState
        )
    }

    private var nextFocusTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.985))
    }

    private func guidedReviewPanel(_ recommendation: StudyFocusRecommendation) -> some View {
        SectionPanel {
            Group {
                if usesStackedTypeLayout {
                    VStack(alignment: .leading, spacing: 14) {
                        guidedReviewIcon(recommendation)
                        guidedReviewCopy(recommendation)
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        guidedReviewIcon(recommendation)
                        guidedReviewCopy(recommendation)
                    }
                }
            }
        }
    }

    private var guidedReviewUpgradePanel: some View {
        Button {
            store.requestMembership(for: .adaptiveStudyAssist)
        } label: {
            SectionPanel {
                Group {
                    if usesStackedTypeLayout {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                guidedReviewUpgradeIcon
                                Spacer(minLength: 8)
                                guidedReviewUpgradeChevron
                            }
                            guidedReviewUpgradeCopy
                        }
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            guidedReviewUpgradeIcon
                            guidedReviewUpgradeCopy
                            Spacer(minLength: 4)
                            guidedReviewUpgradeChevron
                        }
                    }
                }
            }
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .accessibilityLabel("Next Focus, Pro. Know what to practice next.")
        .accessibilityHint("Opens Checkpoint Pro")
    }

    private var guidedReviewUpgradeIcon: some View {
        Image(systemName: "scope")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(CheckpointTheme.blue)
            .frame(width: 44, height: 44)
            .background(
                CheckpointTheme.blue.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var guidedReviewUpgradeCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text("NEXT FOCUS")
                    .font(.caption2.weight(.bold))
                    .tracking(0.85)

                Text("PRO")
                    .font(.caption2.weight(.bold))
                    .tracking(0.55)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(CheckpointTheme.blue.opacity(0.11), in: Capsule())
            }
            .foregroundStyle(CheckpointTheme.blue)

            Text("Know what to practice next")
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("Pro uses your answer history and review schedule to surface one clear priority.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var guidedReviewUpgradeChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.blue)
            .accessibilityHidden(true)
    }

    private func guidedReviewStatusPanel(_ state: StudyFocusState) -> some View {
        SectionPanel {
            Group {
                if usesStackedTypeLayout {
                    VStack(alignment: .leading, spacing: 14) {
                        guidedReviewStatusIcon(state.systemImage)
                        guidedReviewStatusCopy(state)
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        guidedReviewStatusIcon(state.systemImage)
                        guidedReviewStatusCopy(state)
                    }
                }
            }
        }
    }

    private func guidedReviewStatusIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 44, height: 44)
            .background(
                CheckpointTheme.teal.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private func guidedReviewStatusCopy(_ state: StudyFocusState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NEXT FOCUS")
                .font(.caption2.weight(.bold))
                .tracking(0.85)
                .foregroundStyle(CheckpointTheme.teal)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(state.detail)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func guidedReviewIcon(_ recommendation: StudyFocusRecommendation) -> some View {
        Image(systemName: recommendation.systemImage)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(CheckpointTheme.blue)
            .frame(width: 44, height: 44)
            .background(
                CheckpointTheme.blue.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private func guidedReviewCopy(_ recommendation: StudyFocusRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NEXT FOCUS")
                .font(.caption2.weight(.bold))
                .tracking(0.85)
                .foregroundStyle(CheckpointTheme.blue)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recommendation.detail)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func focusAreasPanel(
        title: String,
        description: String = "Skills stay in your map order. Open any area for its answer mix and latest signal."
    ) -> some View {
        SectionPanel(title) {
            VStack(alignment: .leading, spacing: 0) {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                ForEach(competencies) { competency in
                    CompetencyRow(competency: competency)

                    if competency.id != competencies.last?.id {
                        Divider()
                            .overlay(CheckpointTheme.hairline)
                    }
                }
            }
        }
    }

    private var suggestedSkillMapCallout: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 14) {
                if usesStackedTypeLayout {
                    VStack(alignment: .leading, spacing: 10) {
                        suggestedMapIdentity
                        suggestedMapBadge
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        suggestedMapIdentity
                        Spacer(minLength: 8)
                        suggestedMapBadge
                    }
                }

                Text("Confirm or edit these skills so future questions and progress signals stay aligned.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if usesStackedTypeLayout {
                    VStack(spacing: 10) {
                        reviewSuggestedMapButton
                        acceptSuggestedMapButton
                    }
                } else {
                    HStack(spacing: 10) {
                        reviewSuggestedMapButton
                        acceptSuggestedMapButton
                    }
                }
            }
        }
    }

    private var suggestedMapIdentity: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(CheckpointTheme.blue)
                .frame(width: 42, height: 42)
                .background(
                    CheckpointTheme.blue.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Draft learning map")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .primaryState(screenSnapshot)
                    )

                Text("A quick review keeps every signal meaningful.")
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var suggestedMapBadge: some View {
        Text("DRAFT")
            .font(.caption2.weight(.bold))
            .tracking(0.65)
            .foregroundStyle(CheckpointTheme.blue)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(CheckpointTheme.blue.opacity(0.11), in: Capsule())
    }

    private var acceptSuggestedMapButton: some View {
        SecondaryActionButton(title: "Looks good", systemImage: "checkmark") {
            store.confirmActiveDerivedSkillMap()
        }
    }

    private var reviewSuggestedMapButton: some View {
        PrimaryActionButton(title: "Review skills", systemImage: "slider.horizontal.3") {
            isSkillMapEditorPresented = true
        }
    }

    private func skillMapManagementPanel(_ skillMap: GoalSkillMap) -> some View {
        SectionPanel("Skill map") {
            VStack(alignment: .leading, spacing: 14) {
                if usesStackedTypeLayout {
                    VStack(alignment: .leading, spacing: 10) {
                        reviewedMapIdentity(skillMap)
                        reviewedMapBadge
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        reviewedMapIdentity(skillMap)
                        Spacer(minLength: 8)
                        reviewedMapBadge
                    }
                }

                SecondaryActionButton(title: "Edit skill map", systemImage: "slider.horizontal.3") {
                    isSkillMapEditorPresented = true
                }

                Divider()

                evolutionControl(skillMap)

                if !skillMap.archivedTopics.isEmpty {
                    Divider()
                    skillHistory(skillMap)
                }
            }
        }
    }

    private func reviewedMapIdentity(_ skillMap: GoalSkillMap) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 42, height: 42)
                .background(
                    CheckpointTheme.teal.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Active learning map")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .accessibilityAddTraits(.isHeader)

                Text("\(skillMap.topics.count) active skills · updated \(skillMap.updatedAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reviewedMapBadge: some View {
        Text("ACTIVE")
            .font(.caption2.weight(.bold))
            .tracking(0.65)
            .foregroundStyle(CheckpointTheme.teal)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(CheckpointTheme.teal.opacity(0.11), in: Capsule())
    }

    @ViewBuilder
    private func evolutionControl(_ skillMap: GoalSkillMap) -> some View {
        if store.isMember {
            Toggle(
                isOn: Binding(
                    get: { skillMap.evolutionEnabled },
                    set: { store.updateActiveSkillMapEvolutionEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Advance mastered skills")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)

                    Text("When a skill has enough strong, recent evidence, replace it with a harder next step and keep its history.")
                        .font(.caption)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 44)
            .tint(CheckpointTheme.teal)
            .accessibilityHint("Controls automatic progression after a skill is mastered.")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("Adaptive progression with Pro")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                Text("Pro can replace a skill after enough strong, recent evidence while keeping its history.")
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func skillHistory(_ skillMap: GoalSkillMap) -> some View {
        DisclosureGroup(isExpanded: $isSkillHistoryExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.archivedActiveSkillTopics) { archived in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(archived.topic.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckpointTheme.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(archivedSkillSummary(archived, in: skillMap))
                            .font(.caption)
                            .foregroundStyle(CheckpointTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                    if archived.id != store.archivedActiveSkillTopics.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Group {
                if usesStackedTypeLayout {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Skill history")
                            .font(.subheadline.weight(.semibold))
                        Text("\(skillMap.archivedTopics.count) archived skills")
                            .font(.footnote)
                            .foregroundStyle(CheckpointTheme.muted)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Skill history (\(skillMap.archivedTopics.count))")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(CheckpointTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .tint(CheckpointTheme.teal)
        .accessibilityHint(isSkillHistoryExpanded ? "Collapses skill history." : "Expands skill history.")
    }

    private func archivedSkillSummary(
        _ archived: ArchivedSkillMapTopic,
        in skillMap: GoalSkillMap
    ) -> String {
        let date = archived.archivedAt.formatted(date: .abbreviated, time: .omitted)
        let estimate = archived.mastery.map { "\($0.masteryPercent)% estimate" }

        switch archived.reason {
        case .mastered:
            if let successorName = archived.successorSkillIDs.compactMap({ successorID in
                skillMap.topics.first(where: { $0.id == successorID })?.name ??
                    skillMap.archivedTopics.first(where: { $0.id == successorID })?.topic.name
            }).first {
                return [estimate.map { "Mastered at \($0)" } ?? "Mastered", "Advanced to \(successorName)", date]
                    .joined(separator: " · ")
            }
            return [estimate.map { "Mastered at \($0)" } ?? "Mastered", date]
                .joined(separator: " · ")
        case .userRemoved:
            return [
                "Removed during review",
                estimate.map { "\($0) at removal" },
                date
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        }
    }

    private var buildingSkillMapState: some View {
        SectionPanel {
            HStack(alignment: .top, spacing: 14) {
                ProgressView()
                    .tint(CheckpointTheme.teal)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        store.activeDerivedSkillMap == nil
                            ? "Building your skill map"
                            : "Preparing your first checkpoint"
                    )
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.text)

                    Text(
                        store.activeDerivedSkillMap == nil
                            ? "Turning this goal into focused skills. Progress will appear when the first practice set is ready."
                            : "Your skills are ready. Progress will appear when the first practice set is prepared."
                    )
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            store.activeDerivedSkillMap == nil
                ? "Building your skill map. Progress will appear when the first practice set is ready."
                : "Preparing your first checkpoint. Progress will appear when the first practice set is prepared."
        )
        .accessibilityFocused($accessibilityFocus, equals: .primaryState(screenSnapshot))
    }

    private var questionGenerationFailureState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.coral)
                    .frame(width: 48, height: 48)
                    .background(
                        CheckpointTheme.coral.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .accessibilityHidden(true)

                Text(store.lastQuestionGenerationFailure?.title ?? "Practice isn't ready yet")
                    .font(.title3.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .primaryState(screenSnapshot)
                    )

                Text(
                    store.lastQuestionGenerationFailure?.message
                        ?? "Your goal is saved. Try preparing your checkpoint again in a little while."
                )
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    if store.lastQuestionGenerationFailure?.allowsRetryWithoutChanges != false {
                        PrimaryActionButton(
                            title: isRetryingInitialQuestions ? "Trying again" : "Try again",
                            systemImage: "arrow.clockwise"
                        ) {
                            retryInitialQuestionGeneration()
                        }
                        .disabled(isRetryingInitialQuestions)
                    }

                    if store.lastQuestionGenerationFailure?.allowsEditingTopics == true {
                        SecondaryActionButton(title: "Edit topics", systemImage: "pencil") {
                            store.presentActiveGoalEditor()
                        }
                    }
                }
            }
        }
    }

    private var skillMapAttentionState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.amber)
                    .frame(width: 48, height: 48)
                    .background(
                        CheckpointTheme.amber.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .accessibilityHidden(true)

                Text("Set up your skill map")
                    .font(.title3.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .primaryState(screenSnapshot)
                    )

                Text("Add 3–6 focused skills so Checkpoint can track progress meaningfully and preserve your existing answer history.")
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryActionButton(title: "Add focus areas", systemImage: "plus") {
                    isSkillMapRepairPresented = true
                }
            }
        }
    }

    private var emptyState: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "scope")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(width: 48, height: 48)
                    .background(
                        CheckpointTheme.teal.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .accessibilityHidden(true)

                Text(store.goal == nil ? "Create your first goal" : "No progress signals yet")
                    .font(.title3.bold())
                    .foregroundStyle(CheckpointTheme.text)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(
                        $accessibilityFocus,
                        equals: .primaryState(screenSnapshot)
                    )

                Text(
                    store.goal == nil
                        ? "Checkpoint will turn one clear goal into focus areas you can actually measure."
                        : "Complete a few practice questions to see what is strong and what to revisit next."
                )
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

                if store.goal == nil {
                    PrimaryActionButton(title: "Create goal", systemImage: "plus") {
                        store.presentGoalProfileCreator()
                    }
                }
            }
        }
    }

    private var shouldShowQuestionGenerationFailure: Bool {
        store.isQuestionGenerationBlockingPractice
    }

    private func retryInitialQuestionGeneration() {
        Task {
            guard let goalID = store.goal?.id,
                  !retryingInitialQuestionGoalIDs.contains(goalID) else {
                return
            }
            retryingInitialQuestionGoalIDs.insert(goalID)
            await store.retryInitialQuestionGeneration()
            retryingInitialQuestionGoalIDs.remove(goalID)
        }
    }

    private func respondToScreenChangeAfterLayout(
        from previous: ProgressScreenSnapshot,
        to current: ProgressScreenSnapshot
    ) {
        Task { @MainActor in
            await Task.yield()
            guard screenSnapshot == current else { return }
            guard isVisible else { return }

            if voiceOverEnabled {
                let nextFocus: ProgressAccessibilityFocus
                if previous.goalID != current.goalID,
                   let currentGoalID = current.goalID {
                    nextFocus = .goalTitle(currentGoalID)
                } else {
                    nextFocus = .primaryState(current)
                }

                if isSkillMapModalActive || isCoveredByParentModal {
                    pendingAccessibilityFocus = nextFocus
                    return
                }

                accessibilityFocus = nextFocus
                return
            }

            announceScreenChange(from: previous, to: current)
        }
    }

    private func applyPendingAccessibilityFocusAfterDismiss() {
        guard !isSkillMapModalActive, !isCoveredByParentModal else { return }
        guard voiceOverEnabled,
              isVisible,
              let pendingFocus = pendingAccessibilityFocus else {
            pendingAccessibilityFocus = nil
            return
        }

        pendingAccessibilityFocus = nil
        Task { @MainActor in
            await Task.yield()
            guard isVisible,
                  accessibilityFocusMatchesCurrentScreen(pendingFocus) else {
                return
            }
            accessibilityFocus = pendingFocus
        }
    }

    private func accessibilityFocusMatchesCurrentScreen(
        _ focus: ProgressAccessibilityFocus
    ) -> Bool {
        switch focus {
        case let .goalTitle(goalID):
            screenSnapshot.goalID == goalID
        case let .primaryState(snapshot):
            screenSnapshot == snapshot
        }
    }

    private func finishSkillMapModalPresentation() {
        isSkillMapModalActive = false
        applyPendingAccessibilityFocusAfterDismiss()
    }

    private func announceScreenChange(
        from previous: ProgressScreenSnapshot,
        to current: ProgressScreenSnapshot
    ) {
        if previous.goalID != current.goalID,
           let goalTitle = store.goal?.title {
            AccessibilityNotification.Announcement(
                "Current goal changed to \(goalTitle)."
            ).post()
            return
        }

        guard previous.stage != current.stage else { return }
        let message: String?
        switch current.stage {
        case .suggested:
            message = "Your suggested skill map is ready to review."
        case .reviewed:
            message = "Your skill map is ready."
        case .generationFailure:
            message = store.lastQuestionGenerationFailure?.title
        case .repair:
            message = "Your skill map needs setup."
        case .building:
            message = store.activeDerivedSkillMap == nil
                ? "Building your skill map."
                : "Preparing your first checkpoint."
        case .noGoal, .empty:
            message = nil
        }

        if let message {
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var heroText: Color {
        CheckpointTheme.heroText
    }

    private var heroSecondaryText: Color {
        CheckpointTheme.heroMuted
    }

    private var heroAccent: Color {
        CheckpointTheme.heroSuccess
    }

}
