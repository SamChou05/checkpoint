import SwiftUI
import XCTest
@testable import Checkpoint

final class FirstRunSkillMapTests: CheckpointWorkflowTestCase {
    func testDialoguePoseReflectsMapResultRatherThanQuestionPreparation() {
        XCTAssertEqual(FirstRunSkillMapPhase.building.mascotPose, .think)
        XCTAssertEqual(FirstRunSkillMapPhase.needsAttention.mascotPose, .wave)
        let readyWhileQuestionsBuild = FirstRunSkillMapPhase(
            hasSkillMap: true, isBuildingSkillMap: false, questionBatchState: .generating
        )
        XCTAssertEqual(readyWhileQuestionsBuild.mascotPose, .celebrate)
    }

    func testGeneratedMapCanBeReviewedBeforeQuestionsAreReady() {
        for batchState in [QuestionBatchState.idle, .generating, .ready, .failed] {
            XCTAssertEqual(
                FirstRunSkillMapPhase(
                    hasSkillMap: true,
                    isBuildingSkillMap: false,
                    questionBatchState: batchState
                ),
                .review,
                "A saved map should remain reviewable when questions are \(batchState.rawValue)."
            )
        }
    }

    func testMissingMapDistinguishesBackgroundWorkFromRecovery() {
        XCTAssertEqual(
            FirstRunSkillMapPhase(hasSkillMap: false, isBuildingSkillMap: true, questionBatchState: .idle),
            .building
        )
        XCTAssertEqual(
            FirstRunSkillMapPhase(hasSkillMap: false, isBuildingSkillMap: false, questionBatchState: .generating),
            .building
        )
        for batchState in [QuestionBatchState.idle, .ready, .failed] {
            XCTAssertEqual(
                FirstRunSkillMapPhase(hasSkillMap: false, isBuildingSkillMap: false, questionBatchState: batchState),
                .needsAttention
            )
        }
    }

    @MainActor
    func testApprovalPersistsReviewedMapBeforeContinuingAndOnlyContinuesOnce() throws {
        let store = CheckpointStore(defaults: defaults)
        store.goal = firstRunGoal()
        store.questionBatchState = .generating
        let context = try XCTUnwrap(SkillMapReviewContext(goal: store.goal))
        var approval = FirstRunSkillMapApproval()
        var continueCount = 0
        let onApproved = {
            XCTAssertEqual(store.goal?.derivedSkillMap?.status, .reviewed)
            let reloadedStore = CheckpointStore(defaults: self.defaults)
            XCTAssertEqual(reloadedStore.goal?.derivedSkillMap?.status, .reviewed)
            continueCount += 1
        }

        approval.approve(context, store: store, onApproved: onApproved)
        approval.approve(context, store: store, onApproved: onApproved)

        XCTAssertTrue(approval.didApprove)
        XCTAssertNil(approval.errorMessage)
        XCTAssertEqual(continueCount, 1)
    }

    @MainActor
    func testStaleApprovalKeepsUserOnReviewUntilCurrentMapIsApproved() throws {
        let store = CheckpointStore(defaults: defaults)
        store.goal = firstRunGoal()
        let oldContext = try XCTUnwrap(SkillMapReviewContext(goal: store.goal))
        store.goal?.derivedSkillMap?.version += 1
        store.goal?.derivedSkillMap?.topics[0].name = "Refined problem framing"
        var approval = FirstRunSkillMapApproval()
        var continueCount = 0

        approval.approve(oldContext, store: store) { continueCount += 1 }

        XCTAssertFalse(approval.didApprove)
        XCTAssertNotNil(approval.errorMessage)
        XCTAssertEqual(continueCount, 0)
        XCTAssertEqual(store.goal?.derivedSkillMap?.status, .suggested)

        let currentContext = try XCTUnwrap(SkillMapReviewContext(goal: store.goal))
        approval.approve(currentContext, store: store) { continueCount += 1 }

        XCTAssertTrue(approval.didApprove)
        XCTAssertNil(approval.errorMessage)
        XCTAssertEqual(continueCount, 1)
    }

    @MainActor
    func testFailedApprovalWriteKeepsMapSuggestedAndAllowsRetry() throws {
        let persistenceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FirstRunMapPersistence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: persistenceDirectory) }
        try Data("not a directory".utf8).write(to: persistenceDirectory)
        let store = CheckpointStore(defaults: defaults, persistenceDirectory: persistenceDirectory)
        let goal = firstRunGoal()
        store.goal = goal
        store.goalProfiles = [goal]
        let context = try XCTUnwrap(SkillMapReviewContext(goal: store.goal))
        var approval = FirstRunSkillMapApproval()
        var continueCount = 0

        approval.approve(context, store: store) { continueCount += 1 }

        XCTAssertFalse(approval.didApprove)
        XCTAssertNotNil(approval.errorMessage)
        XCTAssertNotNil(store.persistenceRecoveryMessage)
        XCTAssertEqual(continueCount, 0)
        XCTAssertEqual(store.goal?.derivedSkillMap, goal.derivedSkillMap)

        try FileManager.default.removeItem(at: persistenceDirectory)
        approval.approve(context, store: store) { continueCount += 1 }

        XCTAssertTrue(approval.didApprove)
        XCTAssertNil(approval.errorMessage)
        XCTAssertEqual(continueCount, 1)
        let reloadedStore = CheckpointStore(defaults: defaults, persistenceDirectory: persistenceDirectory)
        XCTAssertEqual(reloadedStore.goal?.derivedSkillMap?.status, .reviewed)
    }

    @MainActor
    func testSavedEditorChangesStillRequireExplicitOnboardingApproval() throws {
        let store = CheckpointStore(defaults: defaults)
        store.goal = firstRunGoal()
        let editorContext = try XCTUnwrap(SkillMapReviewContext(goal: store.goal))
        var topics = editorContext.skillMap.topics
        topics[0].name = "Clarify constraints"
        var approval = FirstRunSkillMapApproval()
        var continueCount = 0

        XCTAssertTrue(store.reviewDerivedSkillMap(
            topics: topics,
            forGoalID: editorContext.revision.goalID,
            expectedMap: editorContext.skillMap
        ))
        XCTAssertEqual(store.goal?.derivedSkillMap?.status, .reviewed)
        XCTAssertFalse(approval.didApprove)

        let currentContext = try XCTUnwrap(SkillMapReviewContext(goal: store.goal))
        approval.approve(currentContext, store: store) { continueCount += 1 }

        XCTAssertTrue(approval.didApprove)
        XCTAssertEqual(continueCount, 1)
        XCTAssertEqual(store.goal?.derivedSkillMap?.topics[0].name, "Clarify constraints")
    }

    @MainActor
    func testFirstRunMapStatesRenderInLightDarkAndAccessibilitySizes() {
        let fixtures: [(String, Int, QuestionBatchState, ColorScheme, DynamicTypeSize)] = [
            ("review-light", 3, .generating, .light, .large),
            ("review-dark", 3, .failed, .dark, .large),
            ("review-six-skills", 6, .ready, .light, .large),
            ("review-large-type", 6, .ready, .light, .accessibility3),
            ("building", 0, .generating, .light, .large),
            ("retry", 0, .failed, .dark, .large)
        ]

        for (name, topicCount, batchState, scheme, typeSize) in fixtures {
            let store = CheckpointStore(defaults: defaults)
            var goal = firstRunGoal()
            if topicCount == 0 {
                goal.derivedSkillMap = nil
            } else if topicCount == 6 {
                goal.derivedSkillMap?.topics.append(contentsOf: [
                    SkillMapTopic(name: "Algorithm design", objectives: [
                        SkillMapObjective(name: "Break a complex problem into smaller steps")
                    ]),
                    SkillMapTopic(name: "Time and space complexity", objectives: [
                        SkillMapObjective(name: "Compare the costs of different approaches")
                    ]),
                    SkillMapTopic(name: "Clear communication", objectives: [
                        SkillMapObjective(name: "Walk through a solution with an example")
                    ])
                ])
            }
            store.goal = goal
            store.questionBatchState = batchState
            var continueCount = 0
            let image = HostedViewRenderer.image(
                for: NavigationStack {
                    FirstRunSkillMapView(
                        store: store,
                        onApproved: { continueCount += 1 },
                        onEditGoal: {},
                        reduceMotionOverride: true
                    )
                }
                .environment(\.dynamicTypeSize, typeSize),
                width: 390,
                height: 844,
                colorScheme: scheme,
                renderScale: 1
            )
            XCTAssertEqual(continueCount, 0, "Rendering \(name) must not advance setup.")
            let attachment = XCTAttachment(image: image)
            attachment.name = "first-run-skill-map-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func firstRunGoal() -> Goal {
        Goal(
            title: "Build the confidence to solve coding interview problems",
            deadline: Date(timeIntervalSince1970: 1_800_000_000),
            category: .custom,
            currentLevel: "Getting started",
            focusAreas: "Problem solving and clear explanations",
            derivedSkillMap: GoalSkillMap(
                topics: [
                    SkillMapTopic(name: "Problem framing", objectives: [
                        SkillMapObjective(name: "Identify the inputs, outputs, and constraints"),
                        SkillMapObjective(name: "Explain a simple approach before optimizing")
                    ]),
                    SkillMapTopic(name: "Data structures", objectives: [
                        SkillMapObjective(name: "Choose an appropriate structure for the task")
                    ]),
                    SkillMapTopic(name: "Testing and reasoning", objectives: [
                        SkillMapObjective(name: "Check edge cases and explain tradeoffs")
                    ])
                ],
                status: .suggested,
                provenance: .backendInferred
            ),
            preferredQuestionStyle: .multipleChoice
        )
    }
}
