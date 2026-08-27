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
            return "Guided review"
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
            return "Bring weak spots back into review so progress stays steady over time."
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
