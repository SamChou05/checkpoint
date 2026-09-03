import XCTest
@testable import Checkpoint

final class BackendQuestionEngineContractTests: XCTestCase {
    // MARK: - Persistence and request contracts

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
        XCTAssertEqual(skillMap.topics.first?.stage, 1)
        XCTAssertEqual(skillMap.topics.first?.predecessorIDs, [])
        XCTAssertEqual(skillMap.archivedTopics, [])
        XCTAssertTrue(skillMap.evolutionEnabled)
        XCTAssertNil(skillMap.lastEvolvedAt)

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

    func testSkillMapNamesUseBackendCanonicalUniqueness() {
        XCTAssertNil(
            SkillMapTopic.validatedNames([
                "Data Flow",
                "Data-Flow",
                "Control flow"
            ])
        )
        XCTAssertNotNil(
            SkillMapTopic.validatedNames([
                "Data Flow",
                "Control flow",
                "State management"
            ])
        )
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
        XCTAssertNil(payload["requiresFullObjectiveCoverage"])
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
        let blockedStemFingerprints = try XCTUnwrap(
            payload["blockedStemFingerprints"] as? [String]
        )
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
        XCTAssertEqual(blockedStemFingerprints.count, 90)
        XCTAssertEqual(blockedStemFingerprints, blockedStemFingerprints.sorted())
        let oldestExistingFingerprint = try XCTUnwrap(
            QuestionBatchSanitizer.questionStemFingerprint("Existing prompt 0")
        )
        let olderReportedFingerprint = try XCTUnwrap(
            QuestionBatchSanitizer.questionStemFingerprint("Reported prompt 44")
        )
        XCTAssertTrue(blockedStemFingerprints.contains(oldestExistingFingerprint))
        XCTAssertTrue(blockedStemFingerprints.contains(olderReportedFingerprint))
        XCTAssertEqual(competencies.count, 20)
        XCTAssertEqual(competencies.first?["topic"] as? String, "Competency 0")
        XCTAssertEqual(competencies.last?["topic"] as? String, "Competency 19")
    }

    func testBlockedStemFingerprintHistoryIsDeterministicallyCapped() {
        let goal = makeGoal()
        var request = makeRequest(goal: goal)
        request.existingQuestions = (0..<800).map { index in
            CheckpointQuestion(
                goalID: goal.id,
                prompt: "Complete historical question \(index)",
                expectedAnswer: "Answer \(index)",
                choices: ["Answer \(index)", "Wrong A", "Wrong B", "Wrong C"],
                explanation: "Explanation \(index)",
                topic: "History",
                difficulty: 2,
                format: .multipleChoice,
                sourcePrompt: "contract history"
            )
        }

        let fingerprints = BackendQuestionHistory.blockedStemFingerprints(for: request)

        XCTAssertEqual(
            fingerprints.count,
            BackendQuestionHistory.maximumBlockedStemFingerprintCount
        )
        XCTAssertEqual(fingerprints, fingerprints.sorted())
        XCTAssertEqual(Set(fingerprints).count, fingerprints.count)
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

    func testSkillMapEvolutionRequestCarriesBoundedEvidenceAndHistory() throws {
        let skills = makeSkills()
        let archived = (0..<50).map { index in
            let topic = SkillMapTopic(
                name: "Archived skill \(index)",
                objectives: [SkillMapObjective(name: "Archived objective \(index)")]
            )
            return ArchivedSkillMapTopic(
                topic: topic,
                reason: .mastered,
                archivedAt: Date(timeIntervalSince1970: Double(index)),
                successorSkillIDs: [],
                mastery: nil
            )
        }
        let skillMap = GoalSkillMap(
            topics: skills,
            archivedTopics: archived,
            status: .reviewed,
            version: 7,
            provenance: .adaptiveEvolution
        )
        let goal = makeGoal(skillMap: skillMap)
        var competency = TopicCompetency.initial(
            topic: skills[0].name,
            estimatedLevel: 5,
            goalID: goal.id,
            skillID: skills[0].id
        )
        competency.attempts = 10
        competency.correct = 9
        competency.partial = 1
        competency.currentStreak = 4
        let attemptDate = Date(timeIntervalSince1970: 1_700_000_000)
        let attempts = (0..<35).map { index in
            CheckpointAttempt(
                questionID: UUID(),
                goalID: goal.id,
                skillID: skills[0].id,
                objectiveID: skills[0].objectives[0].id,
                questionDifficulty: index == 0 ? 4 : 3,
                prompt: "Evidence \(index)",
                answer: "Answer",
                result: index == 0 ? .partial : .correct,
                unlockMinutes: 0,
                createdAt: attemptDate.addingTimeInterval(Double(index))
            )
        }
        let request = SkillMapEvolutionRequest(
            goal: goal,
            baseMapFingerprint: "0123456789abcdef",
            masteredSkillIDs: [skills[0].id],
            competencies: [competency],
            recentAttempts: attempts,
            backendEndpoint: URL(string: "https://api.example.com/prod/v1/questions"),
            backendAuthorizationToken: "token"
        )

        let data = try JSONEncoder().encode(BackendSkillMapEvolutionRequest(request: request))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let goalPayload = try XCTUnwrap(payload["goal"] as? [String: Any])
        let currentSkillMap = try XCTUnwrap(payload["currentSkillMap"] as? [String: Any])
        let encodedAttempts = try XCTUnwrap(payload["recentAttempts"] as? [[String: Any]])
        let archivedSkills = try XCTUnwrap(payload["archivedSkills"] as? [[String: Any]])
        let archivedNameFingerprints = try XCTUnwrap(
            payload["archivedSkillNameFingerprints"] as? [String]
        )

        XCTAssertEqual(goalPayload["id"] as? String, goal.id.uuidString)
        XCTAssertEqual(payload["baseMapFingerprint"] as? String, "0123456789abcdef")
        XCTAssertEqual(currentSkillMap["version"] as? Int, 7)
        XCTAssertEqual((currentSkillMap["skills"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual(payload["masteredSkillIDs"] as? [String], [skills[0].id.uuidString])
        XCTAssertEqual((payload["competencies"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(encodedAttempts.count, 30)
        XCTAssertEqual(encodedAttempts[0]["result"] as? String, "partial")
        XCTAssertEqual(encodedAttempts[0]["difficulty"] as? Int, 4)
        XCTAssertNotNil(encodedAttempts[0]["occurredAt"] as? String)
        XCTAssertEqual(archivedSkills.count, 48)
        XCTAssertEqual(archivedSkills.first?["id"] as? String, archived[2].id.uuidString)
        XCTAssertEqual(archivedSkills.last?["id"] as? String, archived[49].id.uuidString)
        XCTAssertEqual(archivedNameFingerprints.count, 50)
        XCTAssertEqual(Set(archivedNameFingerprints).count, 50)
        XCTAssertTrue(
            archivedNameFingerprints.contains(
                try XCTUnwrap(
                    BackendSkillMapEvolutionHistory.skillNameFingerprint("Archived skill 0")
                )
            )
        )
    }

    func testArchivedSkillNameFingerprintParityAndBound() throws {
        XCTAssertEqual(
            BackendSkillMapEvolutionHistory.skillNameFingerprint("Formal-Logic Basics"),
            "c229f5dbe43478b7"
        )

        let archived = (0..<(BackendSkillMapEvolutionHistory
            .maximumArchivedSkillNameFingerprintCount + 10)).map { index in
            ArchivedSkillMapTopic(
                topic: SkillMapTopic(name: "Historical skill \(index)"),
                reason: .mastered,
                archivedAt: Date(timeIntervalSince1970: Double(index)),
                successorSkillIDs: [],
                mastery: nil
            )
        }
        let fingerprints = BackendSkillMapEvolutionHistory.archivedSkillNameFingerprints(
            for: GoalSkillMap(topics: makeSkills(), archivedTopics: archived)
        )

        XCTAssertEqual(
            fingerprints.count,
            BackendSkillMapEvolutionHistory.maximumArchivedSkillNameFingerprintCount
        )
        XCTAssertEqual(fingerprints, fingerprints.sorted())
        XCTAssertEqual(Set(fingerprints).count, fingerprints.count)
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

    // MARK: - Response decoding

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

    func testLegacySkillMapObjectivesMigrateToBackendLimitInOriginalOrder() throws {
        let legacyObjectives = (0..<8).map { index in
            SkillMapObjective(name: "Legacy objective \(index)")
        }
        var legacyMap = GoalSkillMap(
            topics: [
                SkillMapTopic(name: "Legacy skill", objectives: [legacyObjectives[0]]),
                SkillMapTopic(
                    name: "Current skill two",
                    objectives: [SkillMapObjective(name: "Current objective two")]
                ),
                SkillMapTopic(
                    name: "Current skill three",
                    objectives: [SkillMapObjective(name: "Current objective three")]
                )
            ],
            status: .reviewed,
            provenance: .userEdited
        )
        // Simulate a snapshot written by the former eight-objective client.
        legacyMap.topics[0].objectives = legacyObjectives

        let persistedData = try JSONEncoder().encode(legacyMap)
        let migratedMap = try JSONDecoder().decode(GoalSkillMap.self, from: persistedData)

        XCTAssertEqual(
            migratedMap.topics[0].objectives.map(\.id),
            Array(legacyObjectives.prefix(SkillMapTopic.maximumActiveObjectiveCount)).map(\.id)
        )

        var defensivelyMutatedMap = migratedMap
        defensivelyMutatedMap.topics[0].objectives = legacyObjectives
        let backendPayload = BackendSkillMapPayload(skillMap: defensivelyMutatedMap)
        XCTAssertEqual(
            backendPayload.skills[0].objectives.count,
            SkillMapTopic.maximumActiveObjectiveCount
        )
        XCTAssertNoThrow(
            try backendPayload.makeSkillMap(
                provenance: .userEdited,
                expectedVersion: migratedMap.version
            )
        )
    }

    func testEvolutionResponseBuildsVersionedReplacementProposal() throws {
        let skills = makeSkills()
        let successor = SkillMapTopic(
            name: "Advanced algebra",
            objectives: [
                SkillMapObjective(name: "Model nonlinear systems"),
                SkillMapObjective(name: "Compare nonlinear solution methods")
            ]
        )
        let responseData = try JSONEncoder().encode(
            TestEvolutionEnvelope(
                baseMapFingerprint: "0123456789abcdef",
                baseVersion: 7,
                skillMap: BackendSkillMapPayload(
                    skillMap: GoalSkillMap(
                        topics: [successor, skills[1], skills[2]],
                        version: 8,
                        provenance: .adaptiveEvolution
                    )
                ),
                replacements: [
                    TestEvolutionReplacementEnvelope(
                        predecessorSkillID: skills[0].id,
                        successorSkillID: successor.id
                    )
                ]
            )
        )

        let response = try JSONDecoder().decode(BackendSkillMapEvolutionResponse.self, from: responseData)
        let proposal = try response.makeProposal()

        XCTAssertEqual(proposal.baseMapFingerprint, "0123456789abcdef")
        XCTAssertEqual(proposal.baseVersion, 7)
        XCTAssertEqual(proposal.topics.map(\.id), [successor.id, skills[1].id, skills[2].id])
        XCTAssertEqual(
            proposal.replacements,
            [
                SkillMapEvolutionReplacement(
                    predecessorSkillID: skills[0].id,
                    successorSkillID: successor.id
                )
            ]
        )
    }

    func testEvolutionResponseRejectsSuccessorWithTooFewObjectives() throws {
        let skills = makeSkills()
        let successor = SkillMapTopic(
            name: "Advanced algebra",
            objectives: [SkillMapObjective(name: "Model nonlinear systems")]
        )
        let responseData = try JSONEncoder().encode(
            TestEvolutionEnvelope(
                baseMapFingerprint: "0123456789abcdef",
                baseVersion: 7,
                skillMap: BackendSkillMapPayload(
                    skillMap: GoalSkillMap(
                        topics: [successor, skills[1], skills[2]],
                        version: 8,
                        provenance: .adaptiveEvolution
                    )
                ),
                replacements: [
                    TestEvolutionReplacementEnvelope(
                        predecessorSkillID: skills[0].id,
                        successorSkillID: successor.id
                    )
                ]
            )
        )

        let response = try JSONDecoder().decode(BackendSkillMapEvolutionResponse.self, from: responseData)
        XCTAssertThrowsError(try response.makeProposal()) { error in
            XCTAssertEqual(error as? QuestionGenerationError, .badResponse)
        }
    }

    @MainActor
    func testSkillMapFingerprintMatchesBackendCanonicalVector() throws {
        let skills = [
            SkillMapTopic(
                id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
                name: "Geometry",
                objectives: [
                    SkillMapObjective(
                        id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000020")),
                        name: "Angles"
                    )
                ],
                stage: 4,
                predecessorIDs: [UUID()]
            ),
            SkillMapTopic(
                id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
                name: "Algebra",
                objectives: [
                    SkillMapObjective(
                        id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011")),
                        name: "Quadratics"
                    ),
                    SkillMapObjective(
                        id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010")),
                        name: "Equations"
                    )
                ]
            )
        ]

        XCTAssertEqual(
            SkillMapReconciler.skillMapFingerprint(topics: skills),
            "c9b546abf8a1bf1f"
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

    // MARK: - Provider routing

    func testSkillMapInferenceEndpointIsSiblingOfQuestionEndpoint() throws {
        let endpoint = try XCTUnwrap(URL(string: "https://api.example.com/prod/v1/questions"))

        XCTAssertEqual(
            BackendQuestionEngine.skillMapEndpoint(generationEndpoint: endpoint).absoluteString,
            "https://api.example.com/prod/v1/skill-maps/infer"
        )
    }

    func testSkillMapEvolutionEndpointIsSiblingOfQuestionEndpoint() throws {
        let endpoint = try XCTUnwrap(URL(string: "https://api.example.com/prod/v1/questions"))

        XCTAssertEqual(
            BackendQuestionEngine.skillMapEvolutionEndpoint(generationEndpoint: endpoint).absoluteString,
            "https://api.example.com/prod/v1/skill-maps/evolve"
        )
    }

    func testProviderFailureResponseIsDistinctFromTransientServerFailure() {
        XCTAssertEqual(
            BackendQuestionEngine.generationError(
                for: 502,
                responseBody: Data(#"{"code":"provider_failure"}"#.utf8)
            ),
            .providerFailure
        )
        XCTAssertEqual(
            BackendQuestionEngine.generationError(
                for: 502,
                responseBody: Data(#"{"code":"system_failure"}"#.utf8)
            ),
            .serviceUnavailable
        )
        XCTAssertEqual(
            BackendQuestionEngine.generationError(
                for: 502,
                responseBody: Data(#"{"code":"provider_invalid_response"}"#.utf8)
            ),
            .badResponse
        )
    }

    func testEvolutionInvalidRequestUsesBoundedInvalidResponsePathOnlyForEvolution() {
        let responseBody = Data(#"{"code":"invalid_request"}"#.utf8)

        XCTAssertEqual(
            BackendQuestionEngine.skillMapEvolutionError(
                for: 400,
                responseBody: responseBody
            ),
            .badResponse
        )
        XCTAssertEqual(
            BackendQuestionEngine.generationError(
                for: 400,
                responseBody: responseBody
            ),
            .serviceUnavailable
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

// MARK: - Test support

private struct TestInferenceEnvelope: Encodable {
    var skillMap: BackendSkillMapPayload
}

private struct TestEvolutionEnvelope: Encodable {
    var baseMapFingerprint: String
    var baseVersion: Int
    var skillMap: BackendSkillMapPayload
    var replacements: [TestEvolutionReplacementEnvelope]
}

private struct TestEvolutionReplacementEnvelope: Encodable {
    var predecessorSkillID: SkillMapTopic.ID
    var successorSkillID: SkillMapTopic.ID
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
