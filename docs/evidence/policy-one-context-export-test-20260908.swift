    @MainActor
    func testExportActualPolicyOneContextFixture() async throws {
        XCTAssertEqual(QuestionVerificationPolicy.currentRevision, 1)
        let suiteName = "PolicyOneContextCapture.20260908"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixedDate = Date(timeIntervalSince1970: 1_788_825_600)
        let objective = SkillMapObjective(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            name: "Trace array traversal", detail: "Track values as an array is traversed."
        )
        let skill = SkillMapTopic(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            name: "arrays", objectives: [objective]
        )
        let goal = Goal(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            title: "Understand array traversal", deadline: fixedDate.addingTimeInterval(30 * 86400),
            category: .codingInterview, currentLevel: "Intermediate", focusAreas: "arrays",
            derivedSkillMap: GoalSkillMap(topics: [skill], status: .reviewed,
                provenance: .userEdited, createdAt: fixedDate, updatedAt: fixedDate,
                growthMode: .manual),
            preferredQuestionStyle: .multipleChoice, minimumQuestionDifficulty: 3,
            createdAt: fixedDate
        )
        var question = makeQuestion(
            goal: goal, index: 1, topic: skill.name,
            prompt: "For the array [2, 5, 8], what is the sum of its first and last values?",
            expectedAnswer: "10", choices: ["10", "7", "13", "15"],
            explanation: "The first value is 2 and the last value is 8, giving 2 + 8 = 10.",
            verificationPolicyRevision: 1, skillID: skill.id, objectiveID: objective.id,
            objective: objective.name, status: .correct, timesAsked: 1, timesCorrect: 1,
            lastAskedAt: fixedDate, nextReviewAt: fixedDate.addingTimeInterval(365 * 86400),
            difficulty: 2
        )
        question.id = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        var attempt = CheckpointAttempt(
            questionID: question.id, goalID: goal.id, skillID: skill.id,
            objectiveID: objective.id, questionDifficulty: question.difficulty,
            questionVerificationVersion: 1, prompt: question.prompt,
            answer: question.expectedAnswer, result: .correct, unlockMinutes: 0
        )
        attempt.id = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        attempt.createdAt = fixedDate
        try AppSnapshotPersistence(defaults: defaults).save(AppSnapshot(
            goal: goal, goalProfiles: [goal], questions: [question], attempts: [attempt],
            competencies: [], aiProviderPreference: .backend,
            backendEndpoint: "https://api.example.com/prod/v1/questions",
            membershipTier: .member
        ))
        let client = ScriptedQuestionBankClient(preparation: QuestionBankPreparationReceipt(
            bankID: "policy-one-bank", status: .queued, readyCount: 0,
            targetCount: ProductLimits.memberQuestionBankTargetCount
        ))
        let store = CheckpointStore(questionBankClient: client, defaults: defaults,
            questionBankPollingDelaysNanoseconds: [60_000_000_000])
        for _ in 0..<500 where store.questionBankSyncIntents.first?.bankID != "policy-one-bank" {
            await Task.yield()
        }
        let intent = try XCTUnwrap(store.questionBankSyncIntents.first)
        XCTAssertEqual(intent.bankID, "policy-one-bank")
        XCTAssertEqual(client.ensureRequests.count, 1)
        XCTAssertEqual(client.ensureRequests.first?.requiresVerifiedQuestions, true)
        let data = try XCTUnwrap(defaults.data(forKey: AppSnapshotPersistence.primaryDefaultsKey))
        let snapshot = try JSONDecoder().decode(AppSnapshotEnvelope.self, from: data).snapshot
        XCTAssertEqual(snapshot.questions.first?.verificationPolicyRevision, 1)
        XCTAssertEqual(snapshot.attempts.first?.id, attempt.id)
        XCTAssertEqual(snapshot.questionBankSyncIntents?.first, intent)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("checkpoint-policy1-context-snapshot-20260908.json")
        try encoder.encode(snapshot).write(to: output, options: .atomic)
        print("POLICY_ONE_FIXTURE_PATH=\(output.path)")
        print("POLICY_ONE_CONTEXT=\(intent.contextRevision)")
        print("POLICY_ONE_BANK_CONTEXT=\(intent.bankContextRevision ?? "nil")")
    }

