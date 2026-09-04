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

enum MembershipFeature: String, CaseIterable, Identifiable, Sendable {
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
