import CryptoKit
import Foundation
import XCTest
@testable import Checkpoint

/// Offline exact-return check. Register this file only in a temporary copy of the
/// existing Checkpoint test project. Set CHECKPOINT_DELIVERY_FIXTURE_PATH in that
/// temporary scheme's test environment, or place the helper output
/// at backend/bedrock-question-service/tests/fixtures/question_delivery_capture.json.
/// The JSON attachment retains every operation's runtime/claim/client denominator
/// and the actual composed feedback for every retained choice, even after failures.
final class QuestionDeliveryCaptureTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    func testCapturedOperationsThroughRealClientDelivery() throws {
        let override = ProcessInfo.processInfo.environment["CHECKPOINT_DELIVERY_FIXTURE_PATH"]
        let url = override.map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent(
            "backend/bedrock-question-service/tests/fixtures/question_delivery_capture.json"
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("No runtime capture supplied; synthetic delivery controls are separate.")
        }
        let raw = try Data(contentsOf: url)
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let sourceHashes = try XCTUnwrap(fixture["source_sha256"] as? [String: String])
        for (path, expected) in sourceHashes where path.hasSuffix(".swift") {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                           expected, "Source changed after delivery capture: \(path)")
        }
        let operations = try XCTUnwrap(fixture["operations"] as? [[String: Any]])
        XCTAssertFalse(operations.isEmpty)
        var results: [[String: Any]] = []
        for operation in operations {
            do {
                results.append(try inspect(operation))
            } catch {
                results.append([
                    "operation_index": operation["operation_index"] ?? -1,
                    "runtime_returned_count": operation["runtime_returned_count"] ?? 0,
                    "bank_claimable_count": operation["bank_claimable_count"] ?? 0,
                    "client_retained_count": 0,
                    "error": String(describing: error)
                ])
                XCTFail("Delivery operation failed: \(error)")
            }
        }
        let report: [String: Any] = [
            "delivery_fixture_sha256": SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined(),
            "source_sha256": sourceHashes,
            "scope": "Whole original-operation batches; exact original goal/source context; fresh empty local history; real decode, sanitizer, Codable and feedbackExplanation. No UI layout or semantic approval.",
            "operations": results,
            "runtime_returned_count": results.reduce(0) { $0 + ($1["runtime_returned_count"] as? Int ?? 0) },
            "bank_claimable_count": results.reduce(0) { $0 + ($1["bank_claimable_count"] as? Int ?? 0) },
            "client_retained_count": results.reduce(0) { $0 + ($1["client_retained_count"] as? Int ?? 0) }
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "question-delivery-client-observation.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSyntheticDeliveryControlExercisesFeedbackAndMainOnly() throws {
        let goal = makeGoal()
        var question = makeQuestion(goal: goal, index: 501, difficulty: 3)
        question.explanation = "\r\nThe main solution preserves decomposed e\u{301} and spaces.\t\r\n"
        question.choiceExplanations = [
            question.choices[0]: "\tThis exact choice feedback preserves '  e\u{301}  '.\r\n",
            question.choices[1]: question.explanation
        ]
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(question)) as? [String: Any])
        let observation = try inspect([
            "operation_index": 0,
            "runtime_returned_count": 1,
            "bank_claimable_count": 1,
            "request": ["goal": ["title": goal.title, "currentLevel": goal.currentLevel,
                                   "focusAreas": goal.focusAreas, "category": goal.category.rawValue],
                        "targetCount": 5, "minimumDifficulty": 3],
            "claim_response": ["questions": [wire]]
        ])
        XCTAssertEqual(observation["client_retained_count"] as? Int, 1)
    }

    private struct Claim: Decodable { var questions: [GeneratedQuestionPayload] }
    private struct Request: Decodable {
        struct GoalInput: Decodable {
            var title: String
            var category: String?
            var currentLevel: String?
            var focusAreas: String?
        }
        struct Source: Decodable {
            var name: String
            var text: String
            var truncated: Bool?
        }
        var goal: GoalInput
        var sourceDocuments: [Source]?
        var targetCount: Int
        var minimumDifficulty: Int
    }

    private func inspect(_ operation: [String: Any]) throws -> [String: Any] {
        let requestData = try JSONSerialization.data(withJSONObject: XCTUnwrap(operation["request"]))
        let input = try JSONDecoder().decode(Request.self, from: requestData)
        let sources = (input.sourceDocuments ?? []).map {
            GoalSourceDocument(name: $0.name, text: $0.text, truncated: $0.truncated)
        }
        let goal = Goal(title: input.goal.title, deadline: Date(timeIntervalSince1970: 0),
                        category: GoalCategory(rawValue: input.goal.category ?? "") ?? .custom,
                        currentLevel: input.goal.currentLevel ?? "",
                        focusAreas: input.goal.focusAreas ?? "",
                        sourceDocuments: sources, preferredQuestionStyle: .multipleChoice)
        var request = makeRequest(goal: goal, targetCount: input.targetCount,
                                  minimumDifficulty: input.minimumDifficulty)
        request.requiresVerifiedQuestions = true
        let claimData = try JSONSerialization.data(withJSONObject: XCTUnwrap(operation["claim_response"]))
        let payloads = try QuestionContentJSONDecoder.decode(Claim.self, from: claimData).questions
        let received = payloads.map { $0.makeQuestion(goalID: goal.id, sourcePrompt: "captured delivery") }
        // Exactly one batch admission; never sanitize items separately to evade coverage/deduplication.
        let admitted = QuestionBatchSanitizer.sanitize(received, for: request)
        let persisted = try JSONEncoder().encode(admitted)
        let restored = try QuestionContentJSONDecoder.decode([CheckpointQuestion].self, from: persisted)
        XCTAssertEqual(admitted.count, payloads.count, "Client admission loss in operation \(operation["operation_index"] ?? -1)")
        XCTAssertEqual(restored.count, admitted.count)
        var retained: [[String: Any]] = []
        for question in restored {
            let payload = try XCTUnwrap(payloads.first { $0.remoteID == question.remoteID })
            exact(question.prompt, payload.prompt)
            exact(question.expectedAnswer, payload.expectedAnswer)
            exact(question.explanation, payload.explanation)
            exact(question.topic, payload.topic)
            XCTAssertEqual(question.verificationVersion, payload.verificationVersion)
            XCTAssertEqual(question.verificationPolicyRevision, payload.verificationPolicyRevision)
            XCTAssertEqual(question.difficulty, payload.difficulty)
            XCTAssertEqual(Set(question.choices.map { Data($0.utf8) }), Set(payload.choices.map { Data($0.utf8) }))
            XCTAssertEqual(question.choices.count, payload.choices.count)
            XCTAssertEqual(Set(question.choiceExplanations.keys.map { Data($0.utf8) }),
                           Set(payload.choiceExplanations.keys.map { Data($0.utf8) }))
            var displays: [[String: Any]] = []
            for choice in question.choices {
                let originalFeedback = payload.choiceExplanations.first { Data($0.key.utf8) == Data(choice.utf8) }?.value
                let persistedFeedback = question.choiceExplanations.first { Data($0.key.utf8) == Data(choice.utf8) }?.value
                XCTAssertEqual(persistedFeedback.map { Data($0.utf8) }, originalFeedback.map { Data($0.utf8) })
                let expectedDisplay: String
                if let feedback = originalFeedback,
                   !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   feedback != payload.explanation {
                    expectedDisplay = feedback + "\n\n" + payload.explanation
                } else {
                    expectedDisplay = payload.explanation
                }
                let display = question.feedbackExplanation(for: choice)
                exact(display, expectedDisplay)
                displays.append(["choice": choice, "display": display,
                                 "choice_feedback": originalFeedback.map { $0 as Any } ?? NSNull()])
            }
            retained.append(["remoteID": question.remoteID ?? "", "prompt": question.prompt,
                             "expectedAnswer": question.expectedAnswer, "main": question.explanation,
                             "displayed_choices": question.choices, "feedback_displays": displays])
        }
        return ["operation_index": operation["operation_index"] ?? -1,
                "runtime_returned_count": operation["runtime_returned_count"] ?? payloads.count,
                "bank_claimable_count": payloads.count, "client_retained_count": restored.count,
                "client_dropped_remote_ids": payloads.compactMap { payload in
                    restored.contains { $0.remoteID == payload.remoteID } ? nil : payload.remoteID
                }, "retained_questions": retained]
    }

    private func exact(_ actual: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Data(actual.utf8), Data(expected.utf8), file: file, line: line)
    }
}
