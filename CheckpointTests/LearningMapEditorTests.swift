import SwiftUI
import XCTest
@testable import Checkpoint

final class LearningMapEditorTests: CheckpointWorkflowTestCase {
    @MainActor
    func testDraftKeepsSavedMapUntouchedAndPreservesFocusIdentities() {
        let map = makeMap()
        var draft = LearningMapDraft(map: map)
        XCTAssertFalse(draft.hasChanges)
        draft.topics[0].name = "Reasoning with evidence"
        draft.topics[0].objectives[0].detail = "Prefer examples from everyday claims."
        draft.topics[1].practiceEmphasis = .focus
        draft.growthMode = .reviewSuggestions
        XCTAssertEqual(map.topics[0].name, "Evaluating evidence")
        XCTAssertEqual(draft.topics[0].id, map.topics[0].id)
        XCTAssertEqual(draft.topics[0].objectives[0].id, map.topics[0].objectives[0].id)
        XCTAssertTrue(draft.hasChanges)
        XCTAssertNil(draft.validationError)
        XCTAssertTrue(draft.changeSummary.contains { $0.contains("keep its progress") })
        XCTAssertTrue(draft.changeSummary.contains { $0.contains("Future questions") })
    }

    @MainActor
    func testLegacyDraftSeedsStableFocusPointIdentity() {
        let map = GoalSkillMap(topics: ["Evidence", "Arguments", "Inferences"].map { SkillMapTopic(name: $0) })
        let first = LearningMapDraft(map: map)
        let reopened = LearningMapDraft(map: map)
        XCTAssertEqual(first.topics, reopened.topics)
        XCTAssertEqual(first.topics[0].objectives.first?.id, map.topics[0].id)
        XCTAssertNil(first.validationError)
    }

    @MainActor
    func testReplacingCreatesFreshBranchWithExplicitLineage() throws {
        let map = makeMap()
        var draft = LearningMapDraft(map: map)
        let old = map.topics[0]
        let newID = try XCTUnwrap(draft.replace(old.id))
        XCTAssertNotEqual(newID, old.id)
        XCTAssertEqual(draft.topics[0].predecessorIDs, [old.id])
        XCTAssertEqual(draft.topics[0].stage, old.stage + 1)
        XCTAssertNotEqual(draft.topics[0].objectives[0].id, old.objectives[0].id)
        XCTAssertNotNil(draft.validationError, "A replacement needs a skill name and a focus point before it can be saved.")
        draft.topics[0].name = "Experimental reasoning"
        draft.topics[0].objectives[0].name = "Control variables"
        XCTAssertNil(draft.validationError)
        XCTAssertTrue(draft.changeSummary.contains { $0.contains("fresh practice evidence") })
        XCTAssertTrue(draft.changeSummary.contains { $0.contains("history") })
    }

    @MainActor
    func testDraftReorderPreservesNodeIdentitiesAndValidatesPause() {
        let map = makeMap()
        var draft = LearningMapDraft(map: map)
        draft.moveSkill(map.topics[0].id, by: 1)
        XCTAssertEqual(draft.topics.map(\.id), [map.topics[1].id, map.topics[0].id, map.topics[2].id])
        XCTAssertTrue(draft.changeSummary.contains { $0.contains("Reorder") })
        for index in draft.topics.indices { draft.topics[index].isPaused = true }
        XCTAssertNotNil(draft.validationError)
        draft.topics[1].isPaused = false
        XCTAssertNil(draft.validationError)
    }

    @MainActor
    func testMapDestinationResolvesStableIDAndAliasAndRejectsOtherGoal() throws {
        var goal = makeGoal()
        var map = makeMap()
        map.topics[0].aliases = ["Old evidence name"]
        goal.derivedSkillMap = map
        let direct = LearningMapDestination.resolve(
            target: ProgressSkillEvidenceTarget(goalID: goal.id, skillID: map.topics[0].id, skillName: map.topics[1].name),
            goal: goal
        )
        XCTAssertEqual(direct?.initialSkillID, map.topics[0].id)
        let alias = LearningMapDestination.resolve(
            target: ProgressSkillEvidenceTarget(goalID: goal.id, skillID: nil, skillName: "old evidence name"),
            goal: goal
        )
        XCTAssertEqual(alias?.initialSkillID, map.topics[0].id)
        XCTAssertNil(LearningMapDestination.resolve(
            target: ProgressSkillEvidenceTarget(goalID: goal.id, skillID: UUID(), skillName: map.topics[0].name),
            goal: goal
        ), "An explicit stale ID must never open a different branch with a matching name.")
        XCTAssertNil(LearningMapDestination.resolve(
            target: ProgressSkillEvidenceTarget(goalID: UUID(), skillID: map.topics[0].id, skillName: map.topics[0].name),
            goal: goal
        ))
        XCTAssertNil(LearningMapDestination.resolve(
            target: ProgressSkillEvidenceTarget(goalID: goal.id, skillID: UUID(), skillName: "Missing skill"),
            goal: goal
        ))
    }

    @MainActor
    func testEntrySummaryCountsEarnedHistorySeparatelyFromReplacedSkills() {
        var map = makeMap()
        map.topics[1].isPaused = true
        map.archivedTopics = [
            ArchivedSkillMapTopic(topic: SkillMapTopic(name: "Earlier milestone"), reason: .mastered, archivedAt: Date(), successorSkillIDs: [], mastery: nil),
            ArchivedSkillMapTopic(topic: SkillMapTopic(name: "Replaced interest"), reason: .userReplaced, archivedAt: Date(), successorSkillIDs: [], mastery: nil)
        ]
        var competency = TopicCompetency.initial(topic: map.topics[0].name, skillID: map.topics[0].id)
        competency.attempts = 4
        competency.correct = 4
        let summary = LearningMapEntrySummary(map: map, competencies: [competency])
        XCTAssertEqual(summary.milestoneCount, 1)
        XCTAssertEqual(summary.pausedCount, 1)
        XCTAssertEqual(summary.practicedCount, 1)
        XCTAssertEqual(summary.strongCount, 0, "Four correct answers are still calibrating.")
    }

    @MainActor
    func testNativeEditorAndEntryRenderAtPhoneAndAccessibilitySizes() throws {
        var goal = makeGoal()
        goal.title = "Become a clearer critical thinker"
        goal.derivedSkillMap = makeMap()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        let context = try XCTUnwrap(SkillMapReviewContext(goal: goal))
        let cases: [(String, CGFloat, CGFloat, ColorScheme, DynamicTypeSize, UUID?)] = [
            ("map-editor-overview-light", 393, 852, .light, .large, nil),
            ("map-editor-skill-dark", 393, 852, .dark, .large, context.skillMap.topics[0].id),
            ("map-editor-small-accessibility", 320, 740, .light, .accessibility2, nil),
            ("map-editor-skill-accessibility", 320, 740, .dark, .accessibility2, context.skillMap.topics[0].id)
        ]
        for (name, width, height, scheme, type, skillID) in cases {
            let view = LearningMapEditorView(store: store, context: context, initialSkillID: skillID)
                .environment(\.dynamicTypeSize, type)
                .transaction { $0.disablesAnimations = true }
            let image = HostedViewRenderer.image(for: view, width: width, height: height, colorScheme: scheme, settlingTime: 0.2)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let card = LearningMapEntryCard(summary: LearningMapEntrySummary(map: context.skillMap, competencies: [])) {}
            .padding(20)
            .checkpointScreenBackground()
        let image = HostedViewRenderer.image(for: card, width: 320, height: 280, colorScheme: .light)
        let attachment = XCTAttachment(image: image)
        attachment.name = "map-compact-entry"
        attachment.lifetime = .keepAlways
        add(attachment)
        let largeCard = HostedViewRenderer.image(
            for: card.environment(\.dynamicTypeSize, .accessibility2),
            width: 320, height: 650, colorScheme: .dark
        )
        let largeAttachment = XCTAttachment(image: largeCard)
        largeAttachment.name = "map-entry-accessibility"
        largeAttachment.lifetime = .keepAlways
        add(largeAttachment)
    }

    private func makeMap() -> GoalSkillMap {
        GoalSkillMap(topics: [
            SkillMapTopic(name: "Evaluating evidence", objectives: [SkillMapObjective(name: "Source credibility"), SkillMapObjective(name: "Relevant evidence")]),
            SkillMapTopic(name: "Building arguments", objectives: [SkillMapObjective(name: "Premises")]),
            SkillMapTopic(name: "Drawing inferences", objectives: [SkillMapObjective(name: "Deduction")])
        ], status: .reviewed, growthMode: .manual)
    }
}
