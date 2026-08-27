import Foundation

struct AppSnapshot: Codable, Sendable {
    var goal: Goal?
    var goalProfiles: [Goal]?
    var questions: [CheckpointQuestion]
    var attempts: [CheckpointAttempt]
    var competencies: [TopicCompetency]
    var unlockEvents: [UnlockEvent]?
    var questionReports: [QuestionQualityReport]?
    var issueReports: [UserIssueReport]?
    var questionGenerationTraces: [QuestionGenerationTrace]?
    var unlockPolicy: UnlockPolicy?
    var questionBatchState: QuestionBatchState?
    var lastAIErrorMessage: String?
    var lastQuestionGenerationFailure: QuestionGenerationFailureKind?
    var aiProviderPreference: AIProviderKind?
    var lastQuestionProvider: AIProviderKind?
    var backendEndpoint: String?
    var unlockSession: UnlockSession?
    var activeCheckpointRun: ActiveCheckpointRun?
    var checkpointRetryCooldownUntil: Date?
    var membershipTier: MembershipTier?
    var questionRefreshesUsed: Int?
    var lastAutomaticQuestionRefreshAt: Date?
    var questionBankSyncIntents: [QuestionBankSyncIntent]?
}
