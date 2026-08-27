import XCTest
@testable import Checkpoint

final class BackendQuestionEngineContractTests: XCTestCase {
    func testLegacySkillMapAndQuestionDecodeWithMigrationDefaults() throws {
        let goalID = UUID()
        let skillID = UUID()
        let legacyMapData = Data(
            """
            {"topics":[{"id":"\(skillID.uuidString)","name":"Algebra","aliases":[]}],"status":"suggested"}
            """.utf8
        )

        let skillMap = try JSONDecoder().decode(GoalSkillMap.self, from: legacyMapData)

        XCTAssertEqual(skillMap.version, 1)
        XCTAssertEqual(skillMap.provenance, .questionTopics)
        XCTAssertEqual(skillMap.topics.first?.id, skillID)
        XCTAssertEqual(skillMap.topics.first?.objectives, [])

        let legacyQuestionData = Data(
            """
            {
              "goalID":"\(goalID.uuidString)",
              "prompt":"What is x?",
              "expectedAnswer":"2",
              "choices":["2","3","4","5"],
              "explanation":"Solve for x.",
              "topic":"Algebra",
              "difficulty":2,
              "format":"Multiple Choice"
            }
            """.utf8
        )

        let question = try JSONDecoder().decode(CheckpointQuestion.self, from: legacyQuestionData)
        XCTAssertNil(question.skillID)
        XCTAssertNil(question.objectiveID)
        XCTAssertNil(question.objective)
    }

    func testBackendQuestionRequestEncodesSkillMapAndAllocationAsArray() throws {
        let skills = makeSkills()
        let goal = makeGoal(
            focusAreas: "legacy focus that should not override the map",
            skillMap: GoalSkillMap(
                topics: skills,
                status: .reviewed,
                provenance: .userEdited
            )
        )
        var request = makeRequest(goal: goal)
        request.desiredSkillAllocation = [
            skills[0].id: 4,
            skills[1].id: 2,
            skills[2].id: 0
        ]

        let data = try JSONEncoder().encode(BackendQuestionRequest(request: request))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let skillMap = try XCTUnwrap(payload["skillMap"] as? [String: Any])
        let encodedSkills = try XCTUnwrap(skillMap["skills"] as? [[String: Any]])
        let allocation = try XCTUnwrap(payload["desiredSkillAllocation"] as? [[String: Any]])

        XCTAssertEqual(skillMap["version"] as? Int, 1)
        XCTAssertEqual(encodedSkills.count, 3)
        XCTAssertEqual(encodedSkills.first?["id"] as? String, skills[0].id.uuidString)
        XCTAssertEqual(
            (encodedSkills.first?["objectives"] as? [[String: Any]])?.first?["id"] as? String,
            skills[0].objectives[0].id.uuidString
        )
        XCTAssertEqual(allocation.count, 3)
        XCTAssertEqual(Set(allocation.compactMap { $0["skillID"] as? String }), Set(skills.map { $0.id.uuidString }))
        XCTAssertEqual(
            allocation.first { ($0["skillID"] as? String) == skills[2].id.uuidString }?["count"] as? Int,
            0
        )
        let sourcePrompt = request.sourcePrompt(provider: .backend)
        XCTAssertTrue(sourcePrompt.contains(skills[0].id.uuidString))
        XCTAssertTrue(sourcePrompt.contains(skills[0].objectives[0].id.uuidString))
    }

    func testBackendQuestionRequestBoundsMatureHistoryToRecentContractWindow() throws {
        let goal = makeGoal()
        var request = makeRequest(goal: goal)
        request.existingQuestions = (0..<45).map { index in
            CheckpointQuestion(
                goalID: goal.id,
                prompt: "Existing prompt \(index)",
                expectedAnswer: "Correct \(index)",
                choices: ["Correct \(index)", "Wrong A", "Wrong B", "Wrong C"],
                explanation: "Explanation \(index)",
                topic: "Topic \(index)",
                difficulty: 2,
                format: .multipleChoice,
                sourcePrompt: "contract history"
            )
        }
        request.reportedQuestions = (0..<45).map { index in
            QuestionQualityReport(
                questionID: UUID(),
                goalID: goal.id,
                prompt: "Reported prompt \(index)",
                reason: .irrelevant,
                note: ""
            )
        }
        request.competencies = (0..<25).map { index in
            .initial(topic: "Competency \(index)", goalID: goal.id)
        }

        let data = try JSONEncoder().encode(BackendQuestionRequest(request: request))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let existingPrompts = try XCTUnwrap(payload["existingPrompts"] as? [String])
        let coverage = try XCTUnwrap(payload["existingQuestionCoverage"] as? [[String: Any]])
        let reportedPrompts = try XCTUnwrap(payload["reportedPrompts"] as? [String])
        let competencies = try XCTUnwrap(payload["competencies"] as? [[String: Any]])

        XCTAssertEqual(existingPrompts.count, 30)
        XCTAssertEqual(existingPrompts.first, "Existing prompt 15")
        XCTAssertEqual(existingPrompts.last, "Existing prompt 44")
        XCTAssertEqual(coverage.count, 30)
        XCTAssertEqual(coverage.first?["prompt"] as? String, "Existing prompt 15")
        XCTAssertEqual(coverage.last?["prompt"] as? String, "Existing prompt 44")
        XCTAssertEqual(reportedPrompts.count, 30)
        XCTAssertEqual(reportedPrompts.first, "Reported prompt 0")
        XCTAssertEqual(reportedPrompts.last, "Reported prompt 29")
        XCTAssertEqual(competencies.count, 20)
        XCTAssertEqual(competencies.first?["topic"] as? String, "Competency 0")
        XCTAssertEqual(competencies.last?["topic"] as? String, "Competency 19")
    }

    func testSkillMapInferenceRequestCarriesSuggestedSkills() throws {
        let request = makeRequest(
            goal: makeGoal(focusAreas: "Algebra, Geometry, Probability")
        )

        let data = try JSONEncoder().encode(BackendSkillMapInferenceRequest(request: request))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(
            payload["suggestedSkills"] as? [String],
            ["Algebra", "Geometry", "Probability"]
        )
        XCTAssertNotNil(payload["goal"] as? [String: Any])
        XCTAssertNotNil(payload["competencies"] as? [[String: Any]])
        XCTAssertNotNil(payload["sourceDocuments"] as? [[String: Any]])
    }

    func testPartialFocusAreasRequestSkillMapCompletionForFallbackGeneration() throws {
        let request = makeRequest(goal: makeGoal(focusAreas: "Algebra, Geometry"))
        let context = request.questionContext

        XCTAssertTrue(context.hasUserFocusAreas)
        XCTAssertFalse(context.hasDerivedSkillMap)
        XCTAssertTrue(context.needsGeneratedSkillMap)

        let data = try JSONEncoder().encode(BackendQuestionRequest(request: request))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedGoal = try XCTUnwrap(payload["goal"] as? [String: Any])

        XCTAssertEqual(encodedGoal["needsSkillMap"] as? Bool, true)
        XCTAssertTrue(
            request.sourcePrompt(provider: .backend)
                .contains("Preserve and complete any supplied starting skills")
        )
    }

    func testGoalContextPrefersPersistedSkillMapOverLegacyFocusText() {
        let skills = makeSkills()
        let goal = makeGoal(
            focusAreas: "Old focus A, Old focus B, Old focus C",
            skillMap: GoalSkillMap(topics: skills, provenance: .backendInferred)
        )

        let context = GoalQuestionContext(goal: goal)

        XCTAssertEqual(context.contentTopics, skills.map(\.name))
        XCTAssertTrue(context.hasDerivedSkillMap)
        XCTAssertFalse(context.hasUserFocusAreas)
        XCTAssertFalse(context.needsGeneratedSkillMap)
    }

    func testInferenceResponseBuildsStableSkillAndObjectiveModels() throws {
        let skills = makeSkills()
        let responseData = try JSONEncoder().encode(
            TestInferenceEnvelope(
                skillMap: BackendSkillMapPayload(
                    skillMap: GoalSkillMap(topics: skills, provenance: .backendInferred)
                )
            )
        )

        let response = try JSONDecoder().decode(BackendSkillMapInferenceResponse.self, from: responseData)
        let skillMap = try response.skillMap.makeSkillMap(provenance: .backendInferred)

        XCTAssertEqual(skillMap.version, 1)
        XCTAssertEqual(skillMap.provenance, .backendInferred)
        XCTAssertEqual(skillMap.topics.map(\.id), skills.map(\.id))
        XCTAssertEqual(
            skillMap.topics.flatMap(\.objectives).map(\.id),
            skills.flatMap(\.objectives).map(\.id)
        )
    }

    func testInferenceResponseAcceptsShortDomainSkillAndObjectiveNames() throws {
        let skillIDs = (0..<3).map { _ in UUID() }
        let objectiveIDs = (0..<3).map { _ in UUID() }
        let responseData = Data(
            """
            {"skillMap":{"version":1,"skills":[
              {"id":"\(skillIDs[0].uuidString)","name":"AI","objectives":[{"id":"\(objectiveIDs[0].uuidString)","name":"ML"}]},
              {"id":"\(skillIDs[1].uuidString)","name":"R","objectives":[{"id":"\(objectiveIDs[1].uuidString)","name":"IO"}]},
              {"id":"\(skillIDs[2].uuidString)","name":"C","objectives":[{"id":"\(objectiveIDs[2].uuidString)","name":"C"}]}
            ]}}
            """.utf8
        )

        let response = try JSONDecoder().decode(BackendSkillMapInferenceResponse.self, from: responseData)
        let skillMap = try response.skillMap.makeSkillMap(provenance: .backendInferred)

        XCTAssertEqual(skillMap.topicNames, ["AI", "R", "C"])
        XCTAssertEqual(
            skillMap.topics.flatMap(\.objectives).map(\.name),
            ["ML", "IO", "C"]
        )
    }

    func testGeneratedQuestionDecodesStableSkillObjectiveTags() throws {
        let skill = makeSkills()[0]
        let objective = try XCTUnwrap(skill.objectives.first)
        let remoteID = UUID()
        let data = Data(
            """
            {"questions":[{"remoteID":"\(remoteID.uuidString)","prompt":"Which statement is correct?","expectedAnswer":"Correct","choices":["Correct","Wrong 1","Wrong 2","Wrong 3"],"explanation":"Because it is correct.","topic":"\(skill.name)","skillID":"\(skill.id.uuidString)","objectiveID":"\(objective.id.uuidString)","objective":"\(objective.name)","difficulty":3,"format":"Multiple Choice"}]}
            """.utf8
        )

        let response = try JSONDecoder().decode(BackendQuestionResponse.self, from: data)
        let question = try XCTUnwrap(
            response.questions.first?.makeQuestion(goalID: UUID(), sourcePrompt: "contract test")
        )

        XCTAssertEqual(question.id, remoteID)
        XCTAssertEqual(question.skillID, skill.id)
        XCTAssertEqual(question.objectiveID, objective.id)
        XCTAssertEqual(question.objective, objective.name)
    }

    func testInvalidOptionalTagsDoNotPoisonOtherwiseUsableQuestion() throws {
        let data = Data(
            """
            {"questions":[{"prompt":"Which statement is correct?","expectedAnswer":"Correct","choices":["Correct","Wrong 1","Wrong 2","Wrong 3"],"explanation":"Because it is correct.","topic":"Algebra","skillID":"optional UUID","objectiveID":"not-a-uuid","objective":"Solve equations","difficulty":3,"format":"Multiple Choice"}]}
            """.utf8
        )

        let response = try JSONDecoder().decode(BackendQuestionResponse.self, from: data)
        let question = try XCTUnwrap(
            response.questions.first?.makeQuestion(goalID: UUID(), sourcePrompt: "contract test")
        )

        XCTAssertNil(question.skillID)
        XCTAssertNil(question.objectiveID)
        XCTAssertEqual(question.objective, "Solve equations")
    }

    func testSkillMapInferenceEndpointIsSiblingOfQuestionEndpoint() throws {
        let endpoint = try XCTUnwrap(URL(string: "https://api.example.com/prod/v1/questions"))

        XCTAssertEqual(
            BackendQuestionEngine.skillMapEndpoint(generationEndpoint: endpoint).absoluteString,
            "https://api.example.com/prod/v1/skill-maps/infer"
        )
    }

    func testHybridInferenceUsesInjectedContract() async throws {
        let expected = GoalSkillMap(
            topics: makeSkills(),
            provenance: .backendInferred
        )
        let engine = HybridQuestionEngine(
            backendEngine: StubSkillMapEngine(result: .success(expected)),
            appleFoundationEngine: StubQuestionEngine()
        )

        let actual = try await engine.inferSkillMap(for: makeRequest(goal: makeGoal()))

        XCTAssertEqual(actual, expected)
    }

    func testHybridInferenceFallsBackToThreeExplicitFocusAreas() async throws {
        let engine = HybridQuestionEngine(
            backendEngine: StubSkillMapEngine(result: .failure(.serviceUnavailable)),
            appleFoundationEngine: StubQuestionEngine()
        )

        let skillMap = try await engine.inferSkillMap(
            for: makeRequest(goal: makeGoal(focusAreas: "Algebra, Geometry, Probability"))
        )

        XCTAssertEqual(skillMap.provenance, .explicitFocusAreas)
        XCTAssertEqual(skillMap.status, .reviewed)
        XCTAssertEqual(skillMap.topicNames, ["Algebra", "Geometry", "Probability"])
        XCTAssertEqual(skillMap.topics.map { $0.objectives.map(\.name) }, [["Algebra"], ["Geometry"], ["Probability"]])
    }

    func testHybridInferenceDoesNotCreateInvalidTwoSkillFallback() async {
        let engine = HybridQuestionEngine(
            backendEngine: StubSkillMapEngine(result: .failure(.serviceUnavailable)),
            appleFoundationEngine: StubQuestionEngine()
        )

        do {
            _ = try await engine.inferSkillMap(
                for: makeRequest(goal: makeGoal(focusAreas: "Algebra, Geometry"))
            )
            XCTFail("Expected the backend error to be preserved")
        } catch {
            XCTAssertEqual(error as? QuestionGenerationError, .serviceUnavailable)
        }
    }

    private func makeSkills() -> [SkillMapTopic] {
        [
            SkillMapTopic(name: "Algebra", objectives: [SkillMapObjective(name: "Solve equations")]),
            SkillMapTopic(name: "Geometry", objectives: [SkillMapObjective(name: "Compare angles")]),
            SkillMapTopic(name: "Probability", objectives: [SkillMapObjective(name: "Compute outcomes")])
        ]
    }

    private func makeGoal(
        focusAreas: String = "",
        skillMap: GoalSkillMap? = nil
    ) -> Goal {
        Goal(
            title: "Learn mathematics",
            deadline: Date().addingTimeInterval(86_400),
            category: .examPrep,
            currentLevel: "Beginner",
            focusAreas: focusAreas,
            derivedSkillMap: skillMap,
            preferredQuestionStyle: .multipleChoice
        )
    }

    private func makeRequest(goal: Goal) -> QuestionGenerationRequest {
        QuestionGenerationRequest(
            goal: goal,
            existingQuestions: [],
            competencies: [],
            reportedQuestions: [],
            targetCount: 5,
            minimumDifficulty: 2,
            backendEndpoint: URL(string: "https://api.example.com/prod/v1/questions")
        )
    }
}

private struct TestInferenceEnvelope: Encodable {
    var skillMap: BackendSkillMapPayload
}

private final class StubSkillMapEngine: QuestionGenerating, SkillMapInferring, @unchecked Sendable {
    let provider: AIProviderKind = .backend
    private let result: Result<GoalSkillMap, QuestionGenerationError>

    init(result: Result<GoalSkillMap, QuestionGenerationError>) {
        self.result = result
    }

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        []
    }

    func inferSkillMap(for request: QuestionGenerationRequest) async throws -> GoalSkillMap {
        try result.get()
    }
}

private struct StubQuestionEngine: QuestionGenerating {
    let provider: AIProviderKind = .appleFoundation

    func generateQuestions(for request: QuestionGenerationRequest) async throws -> [CheckpointQuestion] {
        []
    }
}
