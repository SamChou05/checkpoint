@testable import Checkpoint

// MARK: - Question bank doubles

final class ScriptedQuestionBankClient: QuestionBankSyncing, @unchecked Sendable {
    struct EnsureRequest {
        var goalID: Goal.ID
        var contextRevision: String
        var desiredCount: Int
        var lowWatermark: Int
    }

    private let preparation: QuestionBankPreparationReceipt
    private let defaultClaim: QuestionBankClaimReceipt
    private let ensureError: (any Error)?
    private(set) var ensureRequests: [EnsureRequest] = []
    private(set) var claimIDs: [String] = []

    init(
        preparation: QuestionBankPreparationReceipt,
        defaultClaim: QuestionBankClaimReceipt? = nil,
        ensureError: (any Error)? = nil
    ) {
        self.preparation = preparation
        self.ensureError = ensureError
        self.defaultClaim = defaultClaim ?? QuestionBankClaimReceipt(
            questions: [],
            status: .empty,
            readyCount: 0,
            targetCount: preparation.targetCount
        )
    }

    func ensureQuestionBank(
        for request: QuestionGenerationRequest,
        contextRevision: String,
        desiredCount: Int,
        lowWatermark: Int
    ) async throws -> QuestionBankPreparationReceipt {
        ensureRequests.append(
            EnsureRequest(
                goalID: request.goal.id,
                contextRevision: contextRevision,
                desiredCount: desiredCount,
                lowWatermark: lowWatermark
            )
        )
        if let ensureError {
            throw ensureError
        }
        return preparation
    }

    func claimQuestions(
        from bankID: String,
        claimID: String,
        limit: Int,
        for request: QuestionGenerationRequest
    ) async throws -> QuestionBankClaimReceipt {
        claimIDs.append(claimID)
        return defaultClaim
    }
}
