import XCTest
@testable import Checkpoint

// MARK: - Unlock policy

final class UnlockPolicyTests: XCTestCase {
    func testCorrectAnswerUnlockOptionsUsePracticalShortBreaks() {
        XCTAssertEqual(UnlockPolicy.default.unlockMinutes, 30)
        XCTAssertEqual(UnlockPolicy.correctAnswerUnlockMinuteOptions, [5, 10, 15, 30])
        XCTAssertTrue(UnlockPolicy.correctAnswerUnlockMinuteOptions.contains(30))
    }

    func testLegacyTinyUnlockDurationsNormalizeToCurrentOptions() throws {
        let data = Data(
            """
            {
              "unlockMinutes": 3,
              "partialUnlockMinutes": 2,
              "unlockOnPartial": true,
              "questionsPerSession": 5,
              "requiredCorrectAnswers": 4
            }
            """.utf8
        )

        let policy = try JSONDecoder().decode(UnlockPolicy.self, from: data)

        XCTAssertEqual(policy.unlockMinutes, 5)
        XCTAssertEqual(policy.partialUnlockMinutes, 5)
    }

    func testLegacyTinyCheckpointCountsNormalizeToFiveQuestionBaseline() throws {
        let data = Data(
            """
            {
              "unlockMinutes": 30,
              "partialUnlockMinutes": 15,
              "unlockOnPartial": true,
              "questionsPerSession": 3,
              "requiredCorrectAnswers": 3
            }
            """.utf8
        )

        let policy = try JSONDecoder().decode(UnlockPolicy.self, from: data)

        XCTAssertEqual(policy.questionsPerSession, 5)
        XCTAssertEqual(policy.requiredCorrectAnswers, 4)
    }
}
