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

    @State private var reviewPresentation = SkillMapReviewPresentationState()
    @State private var approval = FirstRunSkillMapApproval()
    @State private var isRetrying = false

    private var phase: FirstRunSkillMapPhase {
        FirstRunSkillMapPhase(
            hasSkillMap: store.activeDerivedSkillMap?.topics.isEmpty == false,
            isBuildingSkillMap: store.isBuildingActiveSkillMap || isRetrying,
            questionBatchState: store.questionBatchState
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                            .font(.title3.weight(.semibold))
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
        .navigationTitle("Your Skill Map")
        .toolbarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
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
        case .review: "Does this feel like your path?"
        case .needsAttention: "Let's give that another try."
        }
    }

    private var guideMessage: String {
        switch phase {
        case .building:
            "I'm turning your goal and any materials you shared into a few focused skills. You'll get to review them next."
        case .review:
            "These skills will guide your practice. Look them over, make any changes, then approve your map to continue."
        case .needsAttention:
            "Your goal is saved. We need a skill map before we can continue, so try again or adjust your goal."
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
                    Text("This may take a moment. Your map will appear here as soon as it's ready.")
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

            ForEach(Array(map.topics.enumerated()), id: \.element.id) { index, topic in
                SectionPanel {
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(CheckpointTheme.teal)
                            .padding(10)
                            .background(CheckpointTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(topic.name)
                                .font(.headline)
                                .foregroundStyle(CheckpointTheme.text)
                                .accessibilityAddTraits(.isHeader)
                                .fixedSize(horizontal: false, vertical: true)

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
                        .frame(maxWidth: .infinity, alignment: .leading)
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
