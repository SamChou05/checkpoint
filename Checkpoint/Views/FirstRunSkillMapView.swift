import SwiftUI

enum FirstRunSkillMapPhase: Equatable {
    case building
    case review
    case needsAttention

    init(hasSkillMap: Bool, isBuildingSkillMap: Bool, questionBatchState: QuestionBatchState) {
        if hasSkillMap {
            self = .review
        } else if isBuildingSkillMap || questionBatchState == .generating {
            self = .building
        } else {
            self = .needsAttention
        }
    }
}

struct FirstRunSkillMapApproval {
    private(set) var didApprove = false
    private(set) var errorMessage: String?

    @MainActor
    mutating func approve(
        _ context: SkillMapReviewContext,
        store: CheckpointStore,
        onApproved: () -> Void
    ) {
        guard !didApprove else { return }
        guard store.reviewDerivedSkillMap(
            topics: context.skillMap.topics,
            forGoalID: context.revision.goalID,
            expectedMap: context.skillMap
        ) else {
            errorMessage = "Your skill map could not be approved. Check the current map and try again."
            return
        }
        errorMessage = nil
        didApprove = true
        onApproved()
    }
}

struct FirstRunSkillMapView: View {
    let store: CheckpointStore
    let onApproved: () -> Void
    let onEditGoal: () -> Void
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var reviewPresentation = SkillMapReviewPresentationState()
    @State private var approval = FirstRunSkillMapApproval()
    @State private var isRetrying = false
    @State private var expandedTopicIDs: Set<UUID> = []

    private var phase: FirstRunSkillMapPhase {
        FirstRunSkillMapPhase(
            hasSkillMap: store.activeDerivedSkillMap?.topics.isEmpty == false,
            isBuildingSkillMap: store.isBuildingActiveSkillMap || isRetrying,
            questionBatchState: store.questionBatchState
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CheckpointSetupGuide(
                    step: .skillMap,
                    title: guideTitle,
                    message: guideMessage,
                    reduceMotionOverride: reduceMotionOverride
                )

                if let goal = store.goal {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR GOAL")
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(CheckpointTheme.muted)
                        Text(goal.title)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)
                }

                switch phase {
                case .building:
                    buildingState
                case .review:
                    if let map = store.activeDerivedSkillMap {
                        skillMap(map)
                    }
                case .needsAttention:
                    attentionState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .checkpointScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if phase == .review, let context = SkillMapReviewContext(goal: store.goal) {
                approvalActions(context)
            }
        }
        .sheet(item: reviewBinding, onDismiss: {
            reviewPresentation.presentationDidDismiss()
        }) { context in
            SkillMapReviewView(store: store, reviewContext: context)
                .onAppear {
                    reviewPresentation.presentationDidAppear()
                }
        }
        .onChange(of: store.goal) { _, goal in
            reviewPresentation.invalidateIfStale(for: goal)
        }
    }

    private var guideTitle: String {
        switch phase {
        case .building: "Let's map your next steps."
        case .review: "Your map is ready."
        case .needsAttention: "Let's give that another try."
        }
    }

    private var guideMessage: String {
        switch phase {
        case .building:
            "I'm finding a few skills to help you reach your goal."
        case .review:
            "Here's where we'll start. Tap a skill to see more."
        case .needsAttention:
            "Your goal is saved. Let's try building your map again."
        }
    }

    private var buildingState: some View {
        SectionPanel {
            HStack(alignment: .top, spacing: 14) {
                ProgressView()
                    .tint(CheckpointTheme.teal)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Building your skill map")
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.text)
                    Text("It'll appear here when it's ready.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func skillMap(_ map: GoalSkillMap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(map.topics.count) skills to build")
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)
                .accessibilityAddTraits(.isHeader)

            SectionPanel(contentPadding: 14) {
                VStack(spacing: 0) {
                    ForEach(Array(map.topics.enumerated()), id: \.element.id) { index, topic in
                        skillRow(topic, index: index)
                        if index < map.topics.count - 1 {
                            Divider()
                                .overlay(CheckpointTheme.hairline)
                                .padding(.leading, 42)
                        }
                    }
                }
            }

            Button("Adjust goal or materials", action: onEditGoal)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(minHeight: 44)
                .disabled(reviewPresentation.blocksUnderlyingPresentations)
        }
    }

    private func skillRow(_ topic: SkillMapTopic, index: Int) -> some View {
        let isExpanded = expandedTopicIDs.contains(topic.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                let reduceMotion = reduceMotionOverride ?? accessibilityReduceMotion
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedTopicIDs.remove(topic.id)
                    } else {
                        expandedTopicIDs.insert(topic.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                        .frame(width: 30, height: 30)
                        .background(CheckpointTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityHidden(true)
                    Text(topic.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.muted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(topic.name)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hide the practice details for this skill." : "Show the practice details for this skill.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(topic.objectives) { objective in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .accessibilityHidden(true)
                            Text(objective.name)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                    }
                }
                .padding(.leading, 42)
                .padding(.bottom, 14)
            }
        }
    }

    private var attentionState: some View {
        SectionPanel {
            Label("Your skill map isn't ready yet", systemImage: "exclamationmark.circle")
                .font(.headline)
                .foregroundStyle(CheckpointTheme.text)
                .accessibilityAddTraits(.isHeader)

            Text(store.lastQuestionGenerationFailure?.message
                 ?? "We couldn't finish creating your skill map. Try again when you have a connection, or update your goal and materials.")
                .font(.subheadline)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryActionButton(title: "Try Again", systemImage: "arrow.clockwise") {
                retryGeneration()
            }
            .disabled(isRetrying)

            SecondaryActionButton(title: "Edit Goal", systemImage: "pencil", action: onEditGoal)
                .disabled(isRetrying)
        }
    }

    private func approvalActions(_ context: SkillMapReviewContext) -> some View {
        VStack(spacing: 10) {
            if let errorMessage = approval.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryActionButton(title: "Approve Skill Map", systemImage: "checkmark.circle") {
                approval.approve(context, store: store, onApproved: onApproved)
            }
            .disabled(reviewPresentation.blocksUnderlyingPresentations || approval.didApprove)
            .accessibilityHint("Save this skill map and continue to app protection setup.")

            Button {
                reviewPresentation.request(context, currentGoal: store.goal)
            } label: {
                Label("Edit Skill Map", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(reviewPresentation.blocksUnderlyingPresentations || approval.didApprove)
            .accessibilityHint("Edit your skills, then return here to approve your map.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var reviewBinding: Binding<SkillMapReviewContext?> {
        Binding(
            get: { reviewPresentation.destination },
            set: { newValue in
                if newValue == nil {
                    reviewPresentation.presentationRequestedDismissal()
                }
            }
        )
    }

    private func retryGeneration() {
        guard !isRetrying else { return }
        isRetrying = true
        Task { @MainActor in
            await store.retryInitialQuestionGeneration()
            isRetrying = false
        }
    }
}
