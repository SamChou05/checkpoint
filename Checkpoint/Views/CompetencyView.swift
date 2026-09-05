import SwiftUI

enum ProgressLayoutElement: Hashable {
    case viewport
    case header
    case goalSwitcher
    case momentum
    case momentumPrimaryOutcome
    case nextFocus
}

private struct ProgressLayoutFrameReporter: ViewModifier {
    let element: ProgressLayoutElement
    let report: (@MainActor (ProgressLayoutElement, CGRect) -> Void)?

    func body(content: Content) -> some View {
        content.background {
            if let report {
                GeometryReader { proxy in
                    let frame = proxy.frame(
                        in: .named(progressLayoutCoordinateSpaceName)
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
    func reportProgressLayoutFrame(
        _ element: ProgressLayoutElement,
        using report: (@MainActor (ProgressLayoutElement, CGRect) -> Void)?
    ) -> some View {
        modifier(ProgressLayoutFrameReporter(element: element, report: report))
    }
}

let progressLayoutCoordinateSpaceName = "Checkpoint.Progress.Layout"

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

    var developingSkillCount: Int {
        max(0, practicedSkillCount - strongSkillCount)
    }

    var skillSignalSummaryText: String? {
        guard totalSkillCount > 0 else { return nil }

        var signals: [String] = []
        if strongSkillCount > 0 {
            signals.append("\(strongSkillCount) strong")
        }
        if developingSkillCount > 0 {
            signals.append("\(developingSkillCount) developing")
        }
        if unpracticedSkillCount > 0 {
            signals.append(
                unpracticedSkillCount == 1
                    ? "1 awaiting a first signal"
                    : "\(unpracticedSkillCount) awaiting first signals"
            )
        }
        return signals.joined(separator: " · ")
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
    case competency(TopicCompetency.ID)
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

struct ProgressGoalSwitchInteractionPolicy {
    static func animatesScroll(
        reduceMotion: Bool,
        assistiveNavigationEnabled: Bool
    ) -> Bool {
        !reduceMotion && !assistiveNavigationEnabled
    }
}

struct ProgressSkillEvidenceTarget: Equatable, Sendable {
    let goalID: Goal.ID
    let skillID: SkillMapTopic.ID?
    let skillName: String
}

struct ProgressSkillEvidenceRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let target: ProgressSkillEvidenceTarget

    init(
        id: UUID = UUID(),
        target: ProgressSkillEvidenceTarget
    ) {
        self.id = id
        self.target = target
    }
}

@MainActor
struct ProgressSkillEvidenceRoutingPolicy {
    static func target(
        for state: StudyFocusState,
        goalID: Goal.ID
    ) -> ProgressSkillEvidenceTarget? {
        guard case let .recommendation(recommendation) = state else { return nil }
        return ProgressSkillEvidenceTarget(
            goalID: goalID,
            skillID: recommendation.skillID,
            skillName: recommendation.skillName
        )
    }

    static func competencyID(
        for target: ProgressSkillEvidenceTarget,
        in competencies: [TopicCompetency]
    ) -> TopicCompetency.ID? {
        let scopedCompetencies = competencies.filter {
            $0.goalID == nil || $0.goalID == target.goalID
        }

        if let skillID = target.skillID,
           let exactMatch = scopedCompetencies.first(where: { $0.skillID == skillID }) {
            return exactMatch.id
        }

        let targetKey = SkillMapReconciler.competencyTopicKey(target.skillName)
        guard !targetKey.isEmpty else { return nil }
        return scopedCompetencies.first {
            SkillMapReconciler.competencyTopicKey($0.topic) == targetKey
        }?.id
    }

    static func shouldDiscard(
        target: ProgressSkillEvidenceTarget,
        currentGoalID: Goal.ID?
    ) -> Bool {
        target.goalID != currentGoalID
    }
}

struct ProgressSkillEvidenceInteractionPolicy: Equatable {
    let animatesScroll: Bool
    let highlightsTarget: Bool

    init(
        reduceMotion: Bool,
        assistiveNavigationEnabled: Bool
    ) {
        animatesScroll = !reduceMotion && !assistiveNavigationEnabled
        highlightsTarget = !reduceMotion && !assistiveNavigationEnabled
    }
}

struct ProgressSkillEvidenceNavigationAction: Sendable {
    private let action: @MainActor @Sendable (ProgressSkillEvidenceTarget) -> Void

    init(
        _ action: @escaping @MainActor @Sendable (ProgressSkillEvidenceTarget) -> Void
    ) {
        self.action = action
    }

    @MainActor
    func callAsFunction(_ target: ProgressSkillEvidenceTarget) {
        action(target)
    }
}

private struct ProgressSkillEvidenceNavigationActionKey: EnvironmentKey {
    static let defaultValue = ProgressSkillEvidenceNavigationAction { _ in }
}

extension EnvironmentValues {
    var checkpointProgressSkillEvidenceNavigation: ProgressSkillEvidenceNavigationAction {
        get { self[ProgressSkillEvidenceNavigationActionKey.self] }
        set { self[ProgressSkillEvidenceNavigationActionKey.self] = newValue }
    }
}

private struct FocusWinsDestination: Identifiable {
    let goalID: Goal.ID
    let goalTitle: String

    var id: Goal.ID { goalID }
}

private struct ProgressWeeklyImpactDestination: Identifiable {
    let goalID: Goal.ID
    let referenceDate: Date

    var id: Goal.ID { goalID }
}

private struct ProgressCompetencyAccessibilityFocusRequest: Identifiable, Equatable {
    let id = UUID()
    let competencyID: TopicCompetency.ID
}

struct CompetencyView: View {
    let store: CheckpointStore
    private let reduceMotionOverride: Bool?
    private let referenceDateOverride: Date?
    private let isVisible: Bool
    private let isSceneActive: Bool
    private let isCoveredByParentModal: Bool
    private let workflow: CheckpointWorkflowCoordinator?
    private let screenTime: ScreenTimeController?
    private let protectionErrorMessage: String?
    private let parentModalOwnsProtectionErrors: Bool
    private let skillEvidenceRequestBinding: Binding<ProgressSkillEvidenceRequest?>?
    private let layoutReporter: (@MainActor (ProgressLayoutElement, CGRect) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.checkpointGoalSelection) private var selectGoal
    @ScaledMetric(relativeTo: .largeTitle) private var heroMetricSize: CGFloat = 54
    @State private var skillMapReviewPresentation = SkillMapReviewPresentationState()
    @State private var isSkillMapRepairPresented = false
    @State private var isSkillMapModalActive = false
    @State private var isSkillHistoryExpanded = false
    @State private var retryingInitialQuestionGoalIDs: Set<Goal.ID> = []
    @State private var focusWinsDestination: FocusWinsDestination?
    @State private var weeklyImpactDestination: ProgressWeeklyImpactDestination?
    @State private var weeklyImpactFeedbackSequence = 0
    @State private var localSkillEvidenceRequest: ProgressSkillEvidenceRequest?
    @State private var expandedCompetencyID: TopicCompetency.ID?
    @State private var highlightedCompetencyID: TopicCompetency.ID?
    @State private var skillEvidenceFeedbackSequence = 0
    @State private var skillEvidenceRequestInFlightID: UUID?
    @State private var skillEvidenceRevealTask: Task<Void, Never>?
    @State private var highlightDismissTask: Task<Void, Never>?
    @State private var competencyAccessibilityFocusRequest: ProgressCompetencyAccessibilityFocusRequest?
    @State private var pendingAccessibilityFocus: ProgressAccessibilityFocus?
    @State private var pendingProtectionErrorMessage: String?
    @State private var protectionStartErrorFeedback = ProtectionStartErrorFeedbackState()
    @AccessibilityFocusState(for: .voiceOver)
    private var accessibilityFocus: ProgressAccessibilityFocus?

    init(
        store: CheckpointStore,
        reduceMotionOverride: Bool? = nil,
        referenceDateOverride: Date? = nil,
        isVisible: Bool = true,
        isSceneActive: Bool = true,
        isCoveredByParentModal: Bool = false,
        workflow: CheckpointWorkflowCoordinator? = nil,
        screenTime: ScreenTimeController? = nil,
        protectionErrorMessage: String? = nil,
        parentModalOwnsProtectionErrors: Bool = false,
        skillEvidenceRequest: Binding<ProgressSkillEvidenceRequest?>? = nil,
        layoutReporter: (@MainActor (ProgressLayoutElement, CGRect) -> Void)? = nil
    ) {
        self.store = store
        self.reduceMotionOverride = reduceMotionOverride
        self.referenceDateOverride = referenceDateOverride
        self.isVisible = isVisible
        self.isSceneActive = isSceneActive
        self.isCoveredByParentModal = isCoveredByParentModal
        self.workflow = workflow
        self.screenTime = screenTime
        self.protectionErrorMessage = protectionErrorMessage
        self.parentModalOwnsProtectionErrors = parentModalOwnsProtectionErrors
        skillEvidenceRequestBinding = skillEvidenceRequest
        self.layoutReporter = layoutReporter
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var referenceDate: Date {
        referenceDateOverride ?? Date()
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

    private var skillMapReviewBinding: Binding<SkillMapReviewContext?> {
        Binding(
            get: { skillMapReviewPresentation.destination },
            set: { destination in
                guard destination == nil else { return }
                skillMapReviewPresentation.presentationRequestedDismissal()
            }
        )
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
                            .reportProgressLayoutFrame(
                                .header,
                                using: layoutReporter
                            )
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
                .reportProgressLayoutFrame(.viewport, using: layoutReporter)
                .padding(.bottom, 48)
                .checkpointScreenBackground()
                .navigationTitle("Progress")
                .toolbarTitleDisplayMode(.inline)
                .onAppear {
                    revealPendingSkillEvidence(using: scrollProxy)
                }
                .onChange(of: pendingSkillEvidenceRequest?.id) { _, _ in
                    revealPendingSkillEvidence(using: scrollProxy)
                }
                .onChange(of: isVisible) { _, currentIsVisible in
                    if currentIsVisible {
                        revealPendingSkillEvidence(using: scrollProxy)
                    } else {
                        cancelSkillEvidenceReveal()
                    }
                }
                .onChange(of: screenSnapshot) { previous, current in
                    if ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                        from: previous.goalID,
                        to: current.goalID
                    ) {
                        isSkillHistoryExpanded = false
                        weeklyImpactDestination = nil
                        expandedCompetencyID = nil
                        competencyAccessibilityFocusRequest = nil
                        cancelSkillEvidenceReveal()
                        cancelSkillEvidenceHighlight()
                        discardStaleSkillEvidenceRequest(for: current.goalID)
                        if pendingSkillEvidenceRequest == nil {
                            resetScrollPosition(
                                afterSwitchTo: current.goalID,
                                using: scrollProxy
                            )
                        } else {
                            revealPendingSkillEvidence(using: scrollProxy)
                        }
                    }
                    respondToScreenChangeAfterLayout(from: previous, to: current)
                }
            }
        }
        .coordinateSpace(name: progressLayoutCoordinateSpaceName)
        .onChange(of: store.goal) { _, goal in
            invalidateSkillMapReviewIfStale(for: goal)
        }
        .onChange(of: isVisible) { _, currentIsVisible in
            if !currentIsVisible {
                accessibilityFocus = nil
                pendingAccessibilityFocus = nil
                competencyAccessibilityFocusRequest = nil
                pendingProtectionErrorMessage = nil
            } else {
                deliverPendingProtectionErrorIfPossible()
                deliverPendingProtectionStartResultIfPossible()
            }
        }
        .onChange(of: isCoveredByParentModal) { _, isCovered in
            if !isCovered {
                applyPendingAccessibilityFocusAfterDismiss()
                deliverPendingProtectionErrorIfPossible()
                deliverPendingProtectionStartResultIfPossible()
            }
        }
        .onChange(of: isSceneActive) { _, isActive in
            if !isActive {
                accessibilityFocus = nil
            } else {
                applyPendingAccessibilityFocusAfterDismiss()
                deliverPendingProtectionErrorIfPossible()
                deliverPendingProtectionStartResultIfPossible()
            }
        }
        .onChange(of: protectionErrorMessage) { _, message in
            if message == nil {
                pendingProtectionErrorMessage = nil
            }
            let isStartFeedbackPending = workflow?.isStartingProtection == true
                || workflow?.pendingProtectionStartResult?.protectionErrorMessage == message
            guard protectionStartErrorFeedback.shouldDeliverPassiveError(
                message,
                isStartFeedbackPending: isStartFeedbackPending
            ), let message else { return }
            guard isVisible,
                  !parentModalOwnsProtectionErrors else { return }

            if !isSceneActive || isCoveredByModalPresentation {
                pendingProtectionErrorMessage = message
            } else {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: workflow?.pendingProtectionStartResult) { _, _ in
            deliverPendingProtectionStartResultIfPossible()
        }
        .sheet(
            item: skillMapReviewBinding,
            onDismiss: finishSkillMapModalPresentation
        ) { reviewContext in
            SkillMapReviewView(store: store, reviewContext: reviewContext)
                .onAppear {
                    skillMapReviewPresentation.presentationDidAppear()
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
        .sheet(
            item: $focusWinsDestination,
            onDismiss: finishAuxiliaryModalPresentation
        ) { destination in
            FocusWinsView(
                store: store,
                goalID: destination.goalID,
                goalTitle: destination.goalTitle
            )
        }
        .sheet(
            item: $weeklyImpactDestination,
            onDismiss: finishAuxiliaryModalPresentation
        ) { destination in
            WeeklyReviewView(
                store: store,
                initialMetricsID: destination.goalID.uuidString,
                referenceDate: destination.referenceDate
            )
        }
        .sensoryFeedback(.selection, trigger: weeklyImpactFeedbackSequence)
        .sensoryFeedback(.selection, trigger: skillEvidenceFeedbackSequence)
        .onDisappear {
            cancelSkillEvidenceReveal()
            cancelSkillEvidenceHighlight()
            competencyAccessibilityFocusRequest = nil
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
        } else if let goal = store.goal,
                  let reviewContext = SkillMapReviewContext(goal: goal),
                  reviewContext.skillMap.status == .suggested {
            suggestedSkillMapCallout(reviewContext)
            progressHero
            activeGoalFocusWinsEntry
            focusAreasPanel(title: "Focus areas")
        } else if let goal = store.goal,
                  let reviewContext = SkillMapReviewContext(goal: goal),
                  reviewContext.skillMap.status == .reviewed {
            activeGoalMomentumEntry
            nextFocusPanel
                .reportProgressLayoutFrame(.nextFocus, using: layoutReporter)
            activeGoalFocusWinsEntry
            focusAreasPanel(
                title: "Learning map",
                description: "Open any skill for its answer mix and latest signal.",
                showsCoverageSummary: true
            )
            skillMapManagementPanel(
                reviewContext.skillMap,
                reviewContext: reviewContext
            )
        } else {
            progressHero
            nextFocusPanel
            activeGoalFocusWinsEntry
            focusAreasPanel(title: "Focus areas")
        }
    }

    @ViewBuilder
    private var activeGoalFocusWinsEntry: some View {
        if let goal = store.goal {
            focusWinsEntry(for: goal)
        }
    }

    @ViewBuilder
    private var activeGoalMomentumEntry: some View {
        if let goal = store.goal,
           store.activeDerivedSkillMap?.status == .reviewed {
            momentumEntry(for: goal)
        }
    }

    private func momentumEntry(for goal: Goal) -> some View {
        let asOf = referenceDate
        let calendar = Calendar.current
        let locale = Locale.current
        let timeZone = calendar.timeZone
        let resolver = GoalDisplayTitleResolver(
            goals: store.availableGoalProfiles,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        var metrics = store.weeklyActiveGoalMetrics(
            asOf: asOf,
            calendar: calendar
        ) ?? WeeklyMetricsSummary(
            id: goal.id.uuidString,
            title: goal.title,
            questionsAnswered: 0,
            correctAnswers: 0,
            missedAnswers: 0,
            checkpointStreakDays: 0,
            checkpointsCleared: 0,
            strongestSkill: nil,
            reviewSkill: nil,
            isCurrentGoal: true
        )
        metrics.title = resolver.title(for: goal)
        let details = WeeklyMetricsCalculator(
            attempts: store.attempts,
            unlockEvents: store.unlockEvents,
            asOf: asOf,
            calendar: calendar
        ).impactDetails(goalID: goal.id)
        let presentation = ProgressMomentumPresentation(
            metrics: metrics,
            details: details,
            referenceDate: asOf,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        return ProgressMomentumCard(
            presentation: presentation,
            reduceMotion: reduceMotion,
            layoutReporter: layoutReporter
        ) {
            presentWeeklyImpact(for: goal, referenceDate: asOf)
        }
        .accessibilityFocused(
            $accessibilityFocus,
            equals: .primaryState(screenSnapshot)
        )
        .reportProgressLayoutFrame(.momentum, using: layoutReporter)
    }

    private func presentWeeklyImpact(
        for goal: Goal,
        referenceDate: Date
    ) {
        guard let destinationGoalID = ProgressWeeklyImpactRoutingPolicy.destinationGoalID(
            activeGoalID: goal.id,
            hasReviewedSkillMap: store.activeDerivedSkillMap?.status == .reviewed
        ) else { return }

        weeklyImpactDestination = ProgressWeeklyImpactDestination(
            goalID: destinationGoalID,
            referenceDate: referenceDate
        )
        weeklyImpactFeedbackSequence += 1
    }

    private var pendingSkillEvidenceRequest: ProgressSkillEvidenceRequest? {
        if let skillEvidenceRequestBinding {
            return skillEvidenceRequestBinding.wrappedValue
        }
        return localSkillEvidenceRequest
    }

    private func setPendingSkillEvidenceRequest(
        _ request: ProgressSkillEvidenceRequest?
    ) {
        if let skillEvidenceRequestBinding {
            skillEvidenceRequestBinding.wrappedValue = request
        } else {
            localSkillEvidenceRequest = request
        }
    }

    private func requestSkillEvidence(_ target: ProgressSkillEvidenceTarget?) {
        guard let target else { return }
        setPendingSkillEvidenceRequest(
            ProgressSkillEvidenceRequest(target: target)
        )
    }

    private func revealPendingSkillEvidence(using proxy: ScrollViewProxy) {
        guard isVisible,
              let request = pendingSkillEvidenceRequest,
              skillEvidenceRequestInFlightID != request.id else {
            return
        }

        skillEvidenceRevealTask?.cancel()
        skillEvidenceRequestInFlightID = request.id
        skillEvidenceRevealTask = Task { @MainActor in
            await Task.yield()

            guard !Task.isCancelled,
                  isCurrentSkillEvidenceRequest(request.id) else {
                finishSkillEvidenceRequest(request.id, consumeRequest: false)
                return
            }

            guard !ProgressSkillEvidenceRoutingPolicy.shouldDiscard(
                target: request.target,
                currentGoalID: store.goal?.id
            ),
            let competencyID = ProgressSkillEvidenceRoutingPolicy.competencyID(
                for: request.target,
                in: competencies
            ) else {
                finishSkillEvidenceRequest(request.id, consumeRequest: true)
                return
            }

            let interactionPolicy = ProgressSkillEvidenceInteractionPolicy(
                reduceMotion: reduceMotion,
                assistiveNavigationEnabled: voiceOverEnabled || switchControlEnabled
            )
            withAnimation(
                interactionPolicy.animatesScroll ? CheckpointMotion.reveal : nil
            ) {
                expandedCompetencyID = competencyID
            }

            if interactionPolicy.highlightsTarget {
                highlightCompetency(competencyID)
            } else {
                cancelSkillEvidenceHighlight()
            }

            await Task.yield()
            guard !Task.isCancelled,
                  isCurrentSkillEvidenceRequest(request.id),
                  store.goal?.id == request.target.goalID,
                  ProgressSkillEvidenceRoutingPolicy.competencyID(
                    for: request.target,
                    in: competencies
                  ) == competencyID else {
                finishSkillEvidenceRequest(
                    request.id,
                    consumeRequest: pendingSkillEvidenceRequest?.id == request.id
                )
                return
            }

            withAnimation(
                interactionPolicy.animatesScroll ? CheckpointMotion.reveal : nil
            ) {
                proxy.scrollTo(
                    ProgressScrollAnchor.competency(competencyID),
                    anchor: .center
                )
            }

            competencyAccessibilityFocusRequest = voiceOverEnabled || switchControlEnabled
                ? ProgressCompetencyAccessibilityFocusRequest(
                    competencyID: competencyID
                )
                : nil

            skillEvidenceFeedbackSequence += 1
            finishSkillEvidenceRequest(request.id, consumeRequest: true)
        }
    }

    private func isCurrentSkillEvidenceRequest(_ requestID: UUID) -> Bool {
        pendingSkillEvidenceRequest?.id == requestID
            && skillEvidenceRequestInFlightID == requestID
    }

    private func finishSkillEvidenceRequest(
        _ requestID: UUID,
        consumeRequest: Bool
    ) {
        if consumeRequest,
           pendingSkillEvidenceRequest?.id == requestID {
            setPendingSkillEvidenceRequest(nil)
        }
        if skillEvidenceRequestInFlightID == requestID {
            skillEvidenceRequestInFlightID = nil
            skillEvidenceRevealTask = nil
        }
    }

    private func cancelSkillEvidenceReveal() {
        skillEvidenceRevealTask?.cancel()
        skillEvidenceRevealTask = nil
        skillEvidenceRequestInFlightID = nil
    }

    private func discardStaleSkillEvidenceRequest(for currentGoalID: Goal.ID?) {
        guard let target = pendingSkillEvidenceRequest?.target,
              ProgressSkillEvidenceRoutingPolicy.shouldDiscard(
                target: target,
                currentGoalID: currentGoalID
              ) else {
            return
        }

        cancelSkillEvidenceReveal()
        setPendingSkillEvidenceRequest(nil)
    }

    private func highlightCompetency(_ competencyID: TopicCompetency.ID) {
        highlightDismissTask?.cancel()
        highlightedCompetencyID = competencyID
        highlightDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled,
                  highlightedCompetencyID == competencyID else {
                return
            }
            withAnimation(CheckpointMotion.change) {
                highlightedCompetencyID = nil
            }
            highlightDismissTask = nil
        }
    }

    private func cancelSkillEvidenceHighlight() {
        highlightDismissTask?.cancel()
        highlightDismissTask = nil
        highlightedCompetencyID = nil
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

            let shouldAnimate = ProgressGoalSwitchInteractionPolicy.animatesScroll(
                reduceMotion: reduceMotion,
                assistiveNavigationEnabled: voiceOverEnabled || switchControlEnabled
            )
            withAnimation(shouldAnimate ? CheckpointMotion.change : nil) {
                proxy.scrollTo(ProgressScrollAnchor.top, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private var progressHeader: some View {
        if let goal = store.goal {
            VStack(alignment: .leading, spacing: 5) {
                if dynamicTypeSize.isAccessibilitySize {
                    goalEyebrow
                    goalTitle(goal)
                    goalSwitcherIfNeeded(currentGoal: goal)
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        goalEyebrow
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 6)
                        goalSwitcherIfNeeded(currentGoal: goal)
                    }

                    goalTitle(goal)
                }
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

    private var goalEyebrow: some View {
        Text("CURRENT GOAL")
            .font(.caption2.weight(.bold))
            .tracking(1)
            .foregroundStyle(CheckpointTheme.muted)
    }

    private func goalTitle(_ goal: Goal) -> some View {
        Text(goal.title)
            .font(.title2.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .lineLimit(usesStackedTypeLayout ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityFocused($accessibilityFocus, equals: .goalTitle(goal.id))
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func goalSwitcherIfNeeded(currentGoal: Goal) -> some View {
        let presentation = GoalSwitchMenuPresentation(store: store)

        if presentation.options.count > 1 {
            Menu {
                ForEach(presentation.options) { option in
                    Button {
                        selectGoal(option.id)
                    } label: {
                        Label(
                            option.menuTitle,
                            systemImage: option.systemImage
                        )
                    }
                    .disabled(option.isCurrent)
                    .accessibilityLabel(option.title)
                    .accessibilityValue(option.accessibilityValue)
                }
            } label: {
                GoalSwitcherCapsuleLabel(title: "Switch")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch goal")
            .accessibilityValue(currentGoal.title)
            .accessibilityHint("Changes the active goal throughout Checkpoint.")
            .reportProgressLayoutFrame(.goalSwitcher, using: layoutReporter)
        }
    }

    private func focusWinsEntry(for goal: Goal) -> some View {
        let calendar = Calendar.current
        let presentation = FocusWinsEntryPresentation(
            focusWins: store.focusWins(for: goal.id),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: .current,
            timeZone: calendar.timeZone
        )

        return Button {
            focusWinsDestination = FocusWinsDestination(
                goalID: goal.id,
                goalTitle: goal.title
            )
        } label: {
            SectionPanel {
                ViewThatFits(in: .horizontal) {
                    focusWinsInlineLayout(presentation: presentation)
                    focusWinsStackedLayout(presentation: presentation)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus Wins")
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint("Opens Focus Wins for \(goal.title).")
    }

    private func focusWinsInlineLayout(
        presentation: FocusWinsEntryPresentation
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            focusWinsIcon

            VStack(alignment: .leading, spacing: 4) {
                Text("Focus Wins")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)

                focusWinsDetail(presentation.detail)
            }
            .frame(minWidth: 145, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 4)

            HStack(spacing: 7) {
                focusWinsCount(presentation.trailingText)
                focusWinsChevron
            }
        }
    }

    private func focusWinsStackedLayout(
        presentation: FocusWinsEntryPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                focusWinsIcon

                Text("Focus Wins")
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
            }

            focusWinsDetail(presentation.detail)

            HStack(spacing: 7) {
                Spacer(minLength: 0)
                focusWinsCount(presentation.trailingText)
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

    private func focusWinsDetail(_ detail: String) -> some View {
        Text(detail)
            .font(.subheadline)
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func focusWinsCount(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText())
    }

    private var focusWinsChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.teal)
            .accessibilityHidden(true)
    }

    private var progressHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    coverageMetric
                    coverageLabel
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 12) {
                    coverageMetric
                    coverageLabel
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
        ViewThatFits(in: .horizontal) {
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

            VStack(alignment: .leading, spacing: 14) {
                strongHeroMetric
                calibratingHeroMetric
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
                    let target = store.goal.flatMap {
                        ProgressSkillEvidenceRoutingPolicy.target(
                            for: focusState,
                            goalID: $0.id
                        )
                    }

                    StudyFocusCard(state: focusState, style: .panel) {
                        requestSkillEvidence(target)
                    }
                    .transition(nextFocusTransition)
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

    private func focusAreasPanel(
        title: String,
        description: String = "Skills stay in your map order. Open any area for its answer mix and latest signal.",
        showsCoverageSummary: Bool = false
    ) -> some View {
        SectionPanel(title) {
            VStack(alignment: .leading, spacing: 0) {
                if showsCoverageSummary {
                    learningMapSummary

                    Divider()
                        .overlay(CheckpointTheme.hairline)
                        .padding(.vertical, 14)
                }

                Text(description)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                ForEach(competencies) { competency in
                    CompetencyRow(
                        competency: competency,
                        expandedCompetencyID: competencyExpansionBinding,
                        isHighlighted: highlightedCompetencyID == competency.id,
                        accessibilityFocusRequestID: competencyAccessibilityFocusRequest?.competencyID
                            == competency.id
                            ? competencyAccessibilityFocusRequest?.id
                            : nil
                    )
                    .id(ProgressScrollAnchor.competency(competency.id))

                    if competency.id != competencies.last?.id {
                        Divider()
                            .overlay(CheckpointTheme.hairline)
                    }
                }
            }
        }
    }

    private var learningMapSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    learningMapCoverageValue
                    learningMapCoverageLabel
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 2) {
                    learningMapCoverageValue
                    learningMapCoverageLabel
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CheckpointTheme.hairline)

                    Capsule()
                        .fill(CheckpointTheme.teal)
                        .frame(
                            width: proxy.size.width * dashboardSummary.coverageProgress
                        )
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)

            Text(learningMapSignalSummary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Learning map, \(dashboardSummary.practicedSkillCount) of "
                + "\(dashboardSummary.totalSkillCount) skills practiced. "
                + learningMapSignalSummary
        )
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: dashboardSummary
        )
    }

    private var learningMapCoverageValue: some View {
        Text("\(dashboardSummary.practicedSkillCount)/\(dashboardSummary.totalSkillCount)")
            .font(.title2.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private var learningMapCoverageLabel: some View {
        Text("skills practiced")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var learningMapSignalSummary: String {
        dashboardSummary.skillSignalSummaryText ?? dashboardNarrative.title
    }

    private var competencyExpansionBinding: Binding<TopicCompetency.ID?> {
        Binding(
            get: { expandedCompetencyID },
            set: { updatedID in
                expandedCompetencyID = updatedID
                if let highlightedCompetencyID,
                   highlightedCompetencyID != updatedID {
                    cancelSkillEvidenceHighlight()
                }
            }
        )
    }

    private func suggestedSkillMapCallout(
        _ reviewContext: SkillMapReviewContext
    ) -> some View {
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
                        reviewSuggestedMapButton(reviewContext)
                        acceptSuggestedMapButton(reviewContext)
                    }
                } else {
                    HStack(spacing: 10) {
                        reviewSuggestedMapButton(reviewContext)
                        acceptSuggestedMapButton(reviewContext)
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

    private func acceptSuggestedMapButton(
        _ reviewContext: SkillMapReviewContext
    ) -> some View {
        SecondaryActionButton(title: "Looks good", systemImage: "checkmark") {
            _ = store.reviewDerivedSkillMap(
                topics: reviewContext.skillMap.topics,
                forGoalID: reviewContext.revision.goalID,
                expectedMap: reviewContext.skillMap
            )
        }
    }

    private func reviewSuggestedMapButton(
        _ reviewContext: SkillMapReviewContext
    ) -> some View {
        PrimaryActionButton(title: "Review skills", systemImage: "slider.horizontal.3") {
            presentSkillMapReview(reviewContext)
        }
    }

    private func skillMapManagementPanel(
        _ skillMap: GoalSkillMap,
        reviewContext: SkillMapReviewContext
    ) -> some View {
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
                    presentSkillMapReview(reviewContext)
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

                if isCoveredByModalPresentation {
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
        guard !isCoveredByModalPresentation else { return }
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
        skillMapReviewPresentation.presentationDidDismiss()
        isSkillMapModalActive = false
        applyPendingAccessibilityFocusAfterDismiss()
        deliverPendingProtectionErrorIfPossible()
        deliverPendingProtectionStartResultIfPossible()
    }

    private func presentSkillMapReview(_ reviewContext: SkillMapReviewContext) {
        _ = skillMapReviewPresentation.request(
            reviewContext,
            currentGoal: store.goal
        )
    }

    private func invalidateSkillMapReviewIfStale(for goal: Goal?) {
        _ = skillMapReviewPresentation.invalidateIfStale(for: goal)
    }

    private func finishAuxiliaryModalPresentation() {
        applyPendingAccessibilityFocusAfterDismiss()
        deliverPendingProtectionErrorIfPossible()
        deliverPendingProtectionStartResultIfPossible()
    }

    private func deliverPendingProtectionErrorIfPossible() {
        guard isVisible,
              isSceneActive,
              !isCoveredByModalPresentation,
              let pendingProtectionErrorMessage else {
            return
        }
        self.pendingProtectionErrorMessage = nil
        guard pendingProtectionErrorMessage == protectionErrorMessage else {
            return
        }
        AccessibilityNotification.Announcement(pendingProtectionErrorMessage).post()
    }

    private func deliverPendingProtectionStartResultIfPossible() {
        guard let workflow,
              let screenTime,
              let result = ProtectionStartResultDelivery.takeCurrent(
                from: workflow,
                isOwner: isVisible
                    && isSceneActive
                    && !isCoveredByModalPresentation,
                currentGoalID: store.goal?.id,
                isShieldingEnabled: screenTime.isShieldingEnabled,
                protectionShouldRemainActive: SharedAppGroup.desiredShieldActive,
                checkpointNotice: store.checkpointNotice,
                protectionErrorMessage: screenTime.userFacingErrorMessage
              ) else { return }

        pendingProtectionErrorMessage = nil
        protectionStartErrorFeedback.recordDeliveredResult(result)
        AccessibilityNotification.Announcement(
            ProtectionStartResultAnnouncement.message(for: result)
        ).post()
    }

    private var isCoveredByModalPresentation: Bool {
        isCoveredByLocalModalPresentation || isCoveredByParentModal
    }

    private var isCoveredByLocalModalPresentation: Bool {
        skillMapReviewPresentation.blocksUnderlyingPresentations
            || isSkillMapRepairPresented
            || isSkillMapModalActive
            || focusWinsDestination != nil
            || weeklyImpactDestination != nil
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
