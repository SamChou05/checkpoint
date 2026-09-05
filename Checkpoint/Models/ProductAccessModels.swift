import Foundation

enum MembershipTier: String, Codable, Sendable {
    case starter
    case member

    var displayName: String {
        switch self {
        case .starter:
            return "Free"
        case .member:
            return "Pro"
        }
    }
}

enum MembershipFeature: String, CaseIterable, Codable, Identifiable, Sendable {
    case goalProfiles
    case freshQuestionGeneration
    case largerQuestionBank
    case adaptiveStudyAssist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goalProfiles:
            return "Multiple goals"
        case .freshQuestionGeneration:
            return "Ongoing practice"
        case .largerQuestionBank:
            return "More variety"
        case .adaptiveStudyAssist:
            return "Next Focus"
        }
    }

    var detail: String {
        switch self {
        case .goalProfiles:
            return "Keep separate goals organized without blending their progress, focus areas, or question levels."
        case .freshQuestionGeneration:
            return "Continue getting new goal-aligned checkpoints after your first Free set has done its job."
        case .largerQuestionBank:
            return "See a broader range of questions so practice stays useful instead of repetitive."
        case .adaptiveStudyAssist:
            return "Use your answer history and review schedule to surface one clear priority for every checkpoint."
        }
    }

    var membershipHeadline: String {
        switch self {
        case .goalProfiles:
            return "Give every goal its own lane."
        case .freshQuestionGeneration:
            return "Keep checkpoints ready."
        case .largerQuestionBank:
            return "Keep practice from feeling repetitive."
        case .adaptiveStudyAssist:
            return "Know what to practice next."
        }
    }
}

enum MembershipPresentationContext: Codable, Equatable, Identifiable, Sendable {
    case overview
    case feature(MembershipFeature)

    var id: String {
        switch self {
        case .overview:
            "overview"
        case .feature(let feature):
            "feature.\(feature.id)"
        }
    }

    var heroLabel: String {
        switch self {
        case .overview:
            "THE FULL EXPERIENCE"
        case .feature(let feature):
            "UNLOCK \(feature.title.uppercased())"
        }
    }

    var offerLabel: String {
        switch self {
        case .overview:
            "Full Pro access"
        case .feature(.goalProfiles):
            "More goals with Pro"
        case .feature(.freshQuestionGeneration):
            "Ongoing practice with Pro"
        case .feature(.largerQuestionBank):
            "More variety with Pro"
        case .feature(.adaptiveStudyAssist):
            "Next Focus with Pro"
        }
    }

    var membershipHeadline: String {
        switch self {
        case .overview:
            "Practice that keeps pace with you."
        case .feature(let feature):
            feature.membershipHeadline
        }
    }

    var detail: String {
        switch self {
        case .overview:
            "Build up to \(ProductLimits.memberGoalProfileLimit) focused goals, keep checkpoints fresh, and get a clear Next Focus from your progress."
        case .feature(let feature):
            feature.detail
        }
    }

    var offerDetail: String {
        switch self {
        case .overview:
            "Up to \(ProductLimits.memberGoalProfileLimit) focused goals, fresh checkpoints, and one clear Next Focus."
        case .feature(.goalProfiles):
            "Keep progress, focus areas, and question levels separate for every goal."
        case .feature(.freshQuestionGeneration):
            "Keep new goal-aligned checkpoints ready after your first Free set."
        case .feature(.largerQuestionBank):
            "Get broader question variety so practice stays useful."
        case .feature(.adaptiveStudyAssist):
            "Turn answer history into one clear priority for every checkpoint."
        }
    }

    var feature: MembershipFeature? {
        guard case .feature(let feature) = self else { return nil }
        return feature
    }
}

enum MembershipActivationContinuation: Codable, Equatable, Sendable {
    case createGoalProfile(sourceGoalID: Goal.ID?)
    case activateGoal(
        sourceGoalID: Goal.ID?,
        targetGoalID: Goal.ID
    )
}

enum MembershipActivationSource: Codable, Equatable, Sendable {
    case purchase
    case restore
    case entitlementRefresh
}

enum MembershipActivationResumeResult: Equatable, Sendable {
    case requested
    case actionUnavailable
    case persistenceFailed
}

struct MembershipActivationRequest: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let context: MembershipPresentationContext
    let continuation: MembershipActivationContinuation?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        context: MembershipPresentationContext,
        continuation: MembershipActivationContinuation? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.context = context
        self.continuation = continuation
    }
}

struct MembershipActivationHandoff: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Equatable, Sendable {
        case offered
        case awaitingEntitlement
        case activationReady
        case resumeRequested
    }

    let request: MembershipActivationRequest
    var phase: Phase
    var source: MembershipActivationSource?

    init(
        request: MembershipActivationRequest,
        phase: Phase = .offered,
        source: MembershipActivationSource? = nil
    ) {
        self.request = request
        self.phase = phase
        self.source = source
    }
}

enum MembershipActivationHandoffEvent: Equatable, Sendable {
    case request(MembershipActivationRequest)
    case checkoutStarted
    case checkoutFinished(hasUnresolvedPurchase: Bool)
    case entitlementVerified(source: MembershipActivationSource)
    case dismissed(hasUnresolvedPurchase: Bool)
    case resumeRequested
    case resumeFailed
    case consumed
    case entitlementRevoked
    case abandoned
}

enum MembershipActivationHandoffReducer {
    static func reduce(
        _ current: MembershipActivationHandoff?,
        event: MembershipActivationHandoffEvent
    ) -> MembershipActivationHandoff? {
        switch event {
        case .request(let request):
            guard let current else {
                return MembershipActivationHandoff(request: request)
            }
            if current.phase == .offered,
               current.request.continuation == nil {
                return MembershipActivationHandoff(request: request)
            }
            return current
        case .checkoutStarted:
            guard var current, current.phase == .offered else { return current }
            current.phase = .awaitingEntitlement
            current.source = nil
            return current
        case .checkoutFinished(let hasUnresolvedPurchase):
            guard var current, current.phase == .awaitingEntitlement else { return current }
            current.phase = hasUnresolvedPurchase ? .awaitingEntitlement : .offered
            current.source = nil
            return current
        case .entitlementVerified(let source):
            guard var current else { return nil }
            guard current.phase == .offered || current.phase == .awaitingEntitlement else {
                return current
            }
            current.phase = .activationReady
            current.source = source
            return current
        case .dismissed(let hasUnresolvedPurchase):
            guard let current else { return nil }
            switch current.phase {
            case .offered, .activationReady:
                return nil
            case .awaitingEntitlement:
                return hasUnresolvedPurchase ? current : nil
            case .resumeRequested:
                return current
            }
        case .resumeRequested:
            guard var current, current.phase == .activationReady else { return current }
            current.phase = .resumeRequested
            return current
        case .resumeFailed:
            guard var current, current.phase == .resumeRequested else { return current }
            current.phase = .activationReady
            return current
        case .consumed:
            guard current?.phase == .resumeRequested else { return current }
            return nil
        case .entitlementRevoked:
            guard let current else { return nil }
            switch current.phase {
            case .offered, .awaitingEntitlement:
                return current
            case .activationReady, .resumeRequested:
                return nil
            }
        case .abandoned:
            return nil
        }
    }
}

struct MembershipActivationPresentation: Equatable, Identifiable, Sendable {
    let id: UUID
    let context: MembershipPresentationContext
    let source: MembershipActivationSource
    let continuation: MembershipActivationContinuation?
    let destinationTitle: String?

    init(
        id: UUID = UUID(),
        context: MembershipPresentationContext,
        source: MembershipActivationSource,
        continuation: MembershipActivationContinuation?,
        destinationTitle: String? = nil
    ) {
        self.id = id
        self.context = context
        self.source = source
        self.continuation = continuation
        self.destinationTitle = destinationTitle
    }

    var eyebrow: String {
        switch source {
        case .purchase:
            "PURCHASE COMPLETE"
        case .restore:
            "ACCESS RESTORED"
        case .entitlementRefresh:
            "ACCESS CONFIRMED"
        }
    }

    var title: String {
        switch source {
        case .purchase:
            "Checkpoint Pro is active."
        case .restore:
            "Pro access restored."
        case .entitlementRefresh:
            "Checkpoint Pro is active."
        }
    }

    var detail: String {
        switch continuation {
        case .createGoalProfile:
            "Your next goal can now keep its own checkpoints, progress, and Next Focus."
        case .activateGoal:
            if let destinationTitle {
                "\(destinationTitle) is ready for review as your active goal."
            } else {
                "Your selected goal is ready for review."
            }
        case nil:
            switch context {
            case .overview:
                "Multiple goals, fresh checkpoints, and adaptive Next Focus are now unlocked."
            case .feature(.goalProfiles):
                "Each goal can now keep its own checkpoints, progress, and Next Focus."
            case .feature(.freshQuestionGeneration):
                "Fresh goal-aligned checkpoints can keep arriving as your ready set runs low."
            case .feature(.largerQuestionBank):
                "Your practice can now grow into a broader, more varied question bank."
            case .feature(.adaptiveStudyAssist):
                "Your answer history can now guide one clear Next Focus."
            }
        }
    }

    var actionTitle: String {
        switch continuation {
        case .createGoalProfile:
            "Set up new goal"
        case .activateGoal:
            "Review goal switch"
        case nil:
            "Done"
        }
    }

    var actionSystemImage: String {
        switch continuation {
        case .createGoalProfile:
            "plus"
        case .activateGoal:
            "arrow.right"
        case nil:
            "checkmark"
        }
    }

    var accessibilityAnnouncement: String {
        "\(title) \(detail)"
    }

    var actionAccessibilityHint: String {
        switch continuation {
        case .createGoalProfile:
            "Opens goal setup."
        case .activateGoal:
            "Reviews the goal switch and any protection changes."
        case nil:
            "Closes this confirmation."
        }
    }
}

enum MembershipPaywallSection: Equatable, Hashable, Sendable {
    case hero
    case offer
    case memberManagement
    case valueProof
    case benefits
    case notice
    case restore
    case legal
}

enum MembershipPaywallViewportClass: Equatable, Sendable {
    case constrained
    case compact
    case regular

    // Measured inside NavigationStack, before the checkout safe-area inset is applied.
    static let constrainedHeightUpperBound: CGFloat = 420
    static let compactHeightUpperBound: CGFloat = 640

    init(availableHeight: CGFloat) {
        if availableHeight < Self.constrainedHeightUpperBound {
            self = .constrained
        } else if availableHeight < Self.compactHeightUpperBound {
            self = .compact
        } else {
            self = .regular
        }
    }
}

struct MembershipPaywallPresentation: Equatable, Sendable {
    enum CheckoutPlacement: Equatable, Sendable {
        case sticky
        case afterPlanChoices
        case hidden
    }

    enum ContentDensity: Equatable, Sendable {
        case compact
        case regular
    }

    enum OfferIntroduction: Equatable, Sendable {
        case none
        case compact
        case expanded
    }

    let sectionOrder: [MembershipPaywallSection]
    let checkoutPlacement: CheckoutPlacement
    let laysOutPlansSideBySide: Bool
    let contentDensity: ContentDensity
    let offerIntroduction: OfferIntroduction

    init(
        isMember: Bool,
        accessibilitySize: Bool,
        usesLargeText: Bool = false,
        hasCheckoutNotice: Bool = false,
        availableHeight: CGFloat = .infinity
    ) {
        let viewportClass = MembershipPaywallViewportClass(availableHeight: availableHeight)
        let needsFlowingCheckout = accessibilitySize
            || usesLargeText
            || (viewportClass != .regular && hasCheckoutNotice)
            || viewportClass == .constrained
        let usesCompactOffer = viewportClass != .regular && !usesLargeText

        if isMember {
            sectionOrder = viewportClass == .regular
                ? [.hero, .memberManagement, .benefits, .notice, .legal]
                : [.memberManagement, .hero, .benefits, .notice, .legal]
            checkoutPlacement = .hidden
            laysOutPlansSideBySide = false
            contentDensity = .regular
            offerIntroduction = .none
        } else {
            sectionOrder = needsFlowingCheckout || usesCompactOffer
                ? [.offer, .valueProof, .benefits, .notice, .restore, .legal]
                : [.hero, .offer, .valueProof, .benefits, .notice, .restore, .legal]
            checkoutPlacement = needsFlowingCheckout ? .afterPlanChoices : .sticky
            laysOutPlansSideBySide = !accessibilitySize && !usesLargeText
            contentDensity = usesCompactOffer ? .compact : .regular
            offerIntroduction = usesCompactOffer
                ? .compact
                : (needsFlowingCheckout ? .expanded : .none)
        }
    }

    static let billingTrustText = "Apple billing · Auto-renews until canceled"
    static let billingTrustAccessibilityLabel =
        "Billing is handled by Apple. Subscription renews automatically until canceled."
    static let subscriptionDisclosureText =
        "Payment is charged by Apple. Subscriptions renew automatically until canceled in App Store account settings."
}

struct MembershipValuePreviewNode: Equatable, Identifiable, Sendable {
    enum ID: String, CaseIterable, Hashable, Sendable {
        case focusedGoals
        case freshCheckpoints
        case nextFocus
    }

    let id: ID
    let title: String
    let compactTitle: String
    let detail: String
    let systemImage: String
}

struct MembershipValuePreviewPresentation: Equatable, Sendable {
    let nodes: [MembershipValuePreviewNode]
    let highlightedNodeID: MembershipValuePreviewNode.ID?
    let outcome: String
    let accessibilityLabel: String

    init(context: MembershipPresentationContext) {
        let nodes = [
            MembershipValuePreviewNode(
                id: .focusedGoals,
                title: "Focused goals",
                compactTitle: "Goals",
                detail: "Up to \(ProductLimits.memberGoalProfileLimit) separate goals",
                systemImage: "square.stack.3d.up.fill"
            ),
            MembershipValuePreviewNode(
                id: .freshCheckpoints,
                title: "Fresh checkpoints",
                compactTitle: "Fresh sets",
                detail: "\(ProductLimits.memberQuestionBankTargetCount)-question practice target",
                systemImage: "sparkles"
            ),
            MembershipValuePreviewNode(
                id: .nextFocus,
                title: "Clear Next Focus",
                compactTitle: "Next focus",
                detail: "One priority from your progress",
                systemImage: "scope"
            )
        ]

        let highlightedNodeID: MembershipValuePreviewNode.ID?
        let outcome: String

        switch context {
        case .overview:
            highlightedNodeID = nil
            outcome = "Focused goals flow into fresh checkpoints and a clear Next Focus."
        case .feature(.goalProfiles):
            highlightedNodeID = .focusedGoals
            outcome = "Keep up to \(ProductLimits.memberGoalProfileLimit) goals separate and focused."
        case .feature(.freshQuestionGeneration):
            highlightedNodeID = .freshCheckpoints
            outcome = "Keep new checkpoints coming as your ready set runs low."
        case .feature(.largerQuestionBank):
            highlightedNodeID = .freshCheckpoints
            outcome = "Build toward an \(ProductLimits.memberQuestionBankTargetCount)-question bank for broader practice."
        case .feature(.adaptiveStudyAssist):
            highlightedNodeID = .nextFocus
            outcome = "Turn answer history into one clear next step."
        }

        self.nodes = nodes
        self.highlightedNodeID = highlightedNodeID
        self.outcome = outcome

        let workflowSummary = nodes
            .map { "\($0.title): \($0.detail)" }
            .joined(separator: ". ")
        if let highlightedNodeID,
           let highlightedNode = nodes.first(where: { $0.id == highlightedNodeID }) {
            accessibilityLabel = "Pro workflow. \(workflowSummary). \(highlightedNode.title) highlighted. \(outcome)"
        } else {
            accessibilityLabel = "Pro workflow. \(workflowSummary). \(outcome)"
        }
    }
}

enum MembershipProductID {
    static let monthly = "checkpoint.membership.monthly"
    static let yearly = "checkpoint.membership.yearly"
    static let all = [monthly, yearly]
}

enum ProductLimits {
    static let starterGoalProfileLimit = 1
    static let memberGoalProfileLimit = 5
    static let starterQuestionBankTargetCount = 40
    static let memberQuestionBankTargetCount = 80
    static let autoRefreshThreshold = 10
    static let autoRefreshCooldown: TimeInterval = 6 * 60 * 60
}

struct StudyFocusRecommendation: Equatable, Sendable {
    let questionID: CheckpointQuestion.ID
    let skillID: SkillMapTopic.ID?
    let skillName: String
    let title: String
    let detail: String
    let systemImage: String

    init?(
        question: CheckpointQuestion,
        skillID: SkillMapTopic.ID?,
        skillName: String,
        hasPracticeHistory: Bool,
        now: Date = Date()
    ) {
        let trimmedSkillName = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displaySkillName = trimmedSkillName.isEmpty ? "this skill" : trimmedSkillName

        questionID = question.id
        self.skillID = skillID
        self.skillName = displaySkillName
        title = displaySkillName

        switch question.status {
        case .due:
            detail = question.nextReviewAt.map { $0 > now } == true
                ? "A partial answer is scheduled next in your review plan."
                : "A partial answer is ready in your review plan."
            systemImage = "circle.lefthalf.filled"
        case .incorrect:
            detail = question.nextReviewAt.map { $0 > now } == true
                ? "A missed question is scheduled next in your review plan."
                : "A missed question is ready in your review plan."
            systemImage = "arrow.counterclockwise.circle.fill"
        case .new:
            if hasPracticeHistory {
                detail = "A new question will sharpen this skill's estimate."
                systemImage = "arrow.up.right"
            } else {
                detail = "A new question will establish your first signal."
                systemImage = "sparkles"
            }
        case .skipped:
            detail = "A skipped question is next in your review plan."
            systemImage = "arrow.uturn.backward.circle.fill"
        case .correct:
            detail = "A maintenance check will keep this skill current."
            systemImage = "arrow.triangle.2.circlepath"
        case .retired:
            return nil
        }
    }
}

enum StudyFocusState: Equatable, Sendable {
    case recommendation(StudyFocusRecommendation)
    case awaitingQuestion
    case caughtUp

    var title: String {
        switch self {
        case let .recommendation(recommendation):
            recommendation.title
        case .awaitingQuestion:
            "Next focus will appear here"
        case .caughtUp:
            "You're caught up"
        }
    }

    var detail: String {
        switch self {
        case let .recommendation(recommendation):
            recommendation.detail
        case .awaitingQuestion:
            "It becomes available when a practice question is ready."
        case .caughtUp:
            "No review is due right now. Your next focus will appear when it's ready."
        }
    }

    var systemImage: String {
        switch self {
        case let .recommendation(recommendation):
            recommendation.systemImage
        case .awaitingQuestion:
            "hourglass"
        case .caughtUp:
            "checkmark.circle.fill"
        }
    }

    var isRecommendation: Bool {
        if case .recommendation = self { return true }
        return false
    }
}
