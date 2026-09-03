import SwiftUI
import XCTest
@testable import Checkpoint

final class SkillMapEditorRenderingTests: XCTestCase {
    func testEditorAffordancesEnforceThreeToSixSkillBoundary() {
        let threeSkills = SkillMapEditorAffordances(count: 3)
        XCTAssertTrue(threeSkills.canAdd)
        XCTAssertFalse(threeSkills.canRemove)

        let fourSkills = SkillMapEditorAffordances(count: 4)
        XCTAssertTrue(fourSkills.canAdd)
        XCTAssertTrue(fourSkills.canRemove)

        let sixSkills = SkillMapEditorAffordances(count: 6)
        XCTAssertFalse(sixSkills.canAdd)
        XCTAssertTrue(sixSkills.canRemove)
    }

    func testEditorMutationsPreserveBoundsOrderingAndFreshReplacementIdentity() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000311")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000312")!
        let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000313")!
        let addedID = UUID(uuidString: "00000000-0000-0000-0000-000000000314")!
        let replacementID = UUID(uuidString: "00000000-0000-0000-0000-000000000315")!
        var topics = [
            SkillMapTopic(
                id: firstID,
                name: "Problem framing",
                objectives: [SkillMapObjective(name: "Clarify constraints")]
            ),
            SkillMapTopic(id: secondID, name: "State modeling"),
            SkillMapTopic(id: thirdID, name: "Testing strategy")
        ]

        XCTAssertTrue(
            SkillMapEditorMutation.add(
                SkillMapTopic(id: addedID, name: "Communication"),
                to: &topics
            )
        )
        XCTAssertEqual(topics.map(\.id), [firstID, secondID, thirdID, addedID])
        XCTAssertEqual(
            SkillMapFocusPlan.adding(addedID).resolvedTarget(availableIDs: topics.map(\.id)),
            addedID
        )
        XCTAssertFalse(
            SkillMapEditorMutation.add(
                SkillMapTopic(id: addedID, name: "Duplicate"),
                to: &topics
            )
        )

        XCTAssertTrue(SkillMapEditorMutation.remove(id: secondID, from: &topics))
        XCTAssertEqual(topics.map(\.id), [firstID, thirdID, addedID])
        XCTAssertFalse(SkillMapEditorMutation.remove(id: thirdID, from: &topics))

        let replacement = SkillMapTopic(id: replacementID, name: "")
        XCTAssertTrue(
            SkillMapEditorMutation.replace(
                id: firstID,
                with: replacement,
                in: &topics
            )
        )
        XCTAssertEqual(topics.map(\.id), [replacementID, thirdID, addedID])
        XCTAssertEqual(topics[0].name, "")
        XCTAssertTrue(topics[0].objectives.isEmpty)
        XCTAssertEqual(
            SkillMapFocusPlan.replacing(with: replacementID)
                .resolvedTarget(availableIDs: topics.map(\.id)),
            replacementID
        )
        XCTAssertFalse(
            SkillMapEditorMutation.replace(
                id: replacementID,
                with: SkillMapTopic(id: thirdID, name: "Duplicate identity"),
                in: &topics
            )
        )
        XCTAssertFalse(
            SkillMapEditorMutation.replace(
                id: replacementID,
                with: SkillMapTopic(id: replacementID, name: "Same identity"),
                in: &topics
            )
        )
    }

    @MainActor
    func testMotionPolicyRemovesStructuralAnimationWhenReduceMotionIsEnabled() {
        let standard = SkillMapMutationMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .structural)
        XCTAssertNotNil(standard.animation)

        let reduced = SkillMapMutationMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
    }

    func testFocusPlansRouteOnlyToRowsThatStillExist() {
        let originalID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let newID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!

        let addPlan = SkillMapFocusPlan.adding(newID)
        XCTAssertFalse(addPlan.clearsCurrentFocus)
        XCTAssertEqual(
            addPlan.resolvedTarget(availableIDs: [originalID, newID]),
            newID
        )
        XCTAssertNil(addPlan.resolvedTarget(availableIDs: [originalID]))

        let focusedRemoval = SkillMapFocusPlan.removing(originalID, focusedID: originalID)
        XCTAssertTrue(focusedRemoval.clearsCurrentFocus)
        XCTAssertNil(focusedRemoval.targetAfterLayout)

        let unfocusedRemoval = SkillMapFocusPlan.removing(originalID, focusedID: newID)
        XCTAssertFalse(unfocusedRemoval.clearsCurrentFocus)

        let replacementPlan = SkillMapFocusPlan.replacing(with: newID)
        XCTAssertTrue(replacementPlan.clearsCurrentFocus)
        XCTAssertEqual(replacementPlan.resolvedTarget(availableIDs: [newID]), newID)
        XCTAssertNil(replacementPlan.resolvedTarget(availableIDs: []))
    }

    func testSkillRowAccessibilityLabelsStayDistinctAndFollowRenumbering() {
        let named = SkillNameRowPresentation(
            index: 1,
            name: "Conditional logic",
            canRemove: true,
            canReplace: true
        )
        XCTAssertEqual(named.fieldAccessibilityLabel, "Skill 2 name")
        XCTAssertEqual(named.removeAccessibilityLabel, "Remove skill 2, Conditional logic")
        XCTAssertEqual(named.replaceAccessibilityLabel, "Replace skill 2, Conditional logic")

        let blank = SkillNameRowPresentation(
            index: 0,
            name: "  ",
            canRemove: true,
            canReplace: true
        )
        XCTAssertEqual(blank.removeAccessibilityLabel, "Remove skill 1")
        XCTAssertEqual(blank.replaceAccessibilityLabel, "Replace skill 1")

        let minimumRows = (0..<3).map { index in
            SkillNameRowPresentation(
                index: index,
                name: "Skill \(index + 1)",
                canRemove: SkillMapEditorAffordances(count: 3).canRemove,
                canReplace: true
            )
        }
        XCTAssertTrue(minimumRows.allSatisfy { $0.removeAccessibilityLabel == nil })

        let names = [
            "Problem framing",
            "Conditional logic",
            "State modeling",
            "Testing strategy",
            "Performance analysis",
            "Communication"
        ]
        let maximumRows = names.enumerated().map { index, name in
            SkillNameRowPresentation(
                index: index,
                name: name,
                canRemove: SkillMapEditorAffordances(count: 6).canRemove,
                canReplace: true
            )
        }
        XCTAssertEqual(Set(maximumRows.compactMap(\.removeAccessibilityLabel)).count, 6)
        XCTAssertEqual(Set(maximumRows.compactMap(\.replaceAccessibilityLabel)).count, 6)

        let renumbered = SkillNameRowPresentation(
            index: 1,
            name: names[2],
            canRemove: true,
            canReplace: true
        )
        XCTAssertEqual(renumbered.fieldAccessibilityLabel, "Skill 2 name")
        XCTAssertEqual(renumbered.removeAccessibilityLabel, "Remove skill 2, State modeling")
    }

    @MainActor
    func testSkillMapEditorsRenderAcrossBoundariesAndAccessibilityLayouts() throws {
        let threeSuiteName = "SkillMapEditorRenderingTests.Three.\(UUID().uuidString)"
        let sixSuiteName = "SkillMapEditorRenderingTests.Six.\(UUID().uuidString)"
        let repairSuiteName = "SkillMapEditorRenderingTests.Repair.\(UUID().uuidString)"
        let threeDefaults = try XCTUnwrap(UserDefaults(suiteName: threeSuiteName))
        let sixDefaults = try XCTUnwrap(UserDefaults(suiteName: sixSuiteName))
        let repairDefaults = try XCTUnwrap(UserDefaults(suiteName: repairSuiteName))
        defer {
            threeDefaults.removePersistentDomain(forName: threeSuiteName)
            sixDefaults.removePersistentDomain(forName: sixSuiteName)
            repairDefaults.removePersistentDomain(forName: repairSuiteName)
        }

        let threeTopics = Array(Self.reviewTopics.prefix(3))
        let sixTopics = Self.reviewTopics
        let threeStore = makeReviewStore(defaults: threeDefaults, topics: threeTopics)
        let sixStore = makeReviewStore(defaults: sixDefaults, topics: sixTopics)
        let repairStore = makeRepairStore(defaults: repairDefaults, names: sixTopics.map(\.name))

        let fixtures = [
            SkillMapEditorRenderFixture(
                name: "skill-map-review-three-light",
                width: 393,
                height: 1_100,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    SkillMapReviewView(store: threeStore, reduceMotionOverride: false)
                )
            ),
            SkillMapEditorRenderFixture(
                name: "skill-map-review-six-dark",
                width: 393,
                height: 1_900,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    SkillMapReviewView(store: sixStore, reduceMotionOverride: false)
                )
            ),
            SkillMapEditorRenderFixture(
                name: "skill-map-review-six-compact-accessibility-reduced",
                width: 320,
                height: 2_500,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    SkillMapReviewView(store: sixStore, reduceMotionOverride: true)
                )
            ),
            SkillMapEditorRenderFixture(
                name: "skill-map-review-three-compact-accessibility",
                width: 320,
                height: 2_200,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    SkillMapReviewView(store: threeStore, reduceMotionOverride: false)
                )
            ),
            SkillMapEditorRenderFixture(
                name: "skill-map-repair-six-light",
                width: 393,
                height: 1_300,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    SkillMapRepairView(store: repairStore, reduceMotionOverride: false)
                )
            ),
            SkillMapEditorRenderFixture(
                name: "skill-map-review-compact-viewport",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    SkillMapReviewView(store: threeStore, reduceMotionOverride: false)
                )
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: fixture.content
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func makeReviewStore(
        defaults: UserDefaults,
        topics: [SkillMapTopic]
    ) -> CheckpointStore {
        let map = GoalSkillMap(
            topics: topics,
            status: .reviewed,
            provenance: .userEdited
        )
        let goal = makeGoal(skillMap: map)
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        return store
    }

    @MainActor
    private func makeRepairStore(
        defaults: UserDefaults,
        names: [String]
    ) -> CheckpointStore {
        let goal = makeGoal(skillMap: nil)
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.competencies = names.map {
            TopicCompetency.initial(topic: $0, goalID: goal.id)
        }
        return store
    }

    private func makeGoal(skillMap: GoalSkillMap?) -> Goal {
        Goal(
            title: "Lead a production architecture review",
            deadline: Date(timeIntervalSince1970: 1_735_689_600),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "system design and technical communication",
            derivedSkillMap: skillMap,
            preferredQuestionStyle: .multipleChoice
        )
    }

    private static let reviewTopics = [
        SkillMapTopic(
            name: "Requirements and constraint discovery",
            objectives: [
                SkillMapObjective(name: "Clarify the user and business outcome"),
                SkillMapObjective(name: "Separate functional and operational constraints"),
                SkillMapObjective(name: "State assumptions before choosing an architecture")
            ]
        ),
        SkillMapTopic(
            name: "Distributed data modeling",
            objectives: [
                SkillMapObjective(name: "Choose ownership boundaries"),
                SkillMapObjective(name: "Explain consistency tradeoffs"),
                SkillMapObjective(name: "Plan schema evolution safely")
            ]
        ),
        SkillMapTopic(
            name: "Reliability and failure recovery",
            objectives: [
                SkillMapObjective(name: "Identify high-impact failure modes"),
                SkillMapObjective(name: "Design graceful degradation"),
                SkillMapObjective(name: "Connect recovery goals to mechanisms")
            ]
        ),
        SkillMapTopic(
            name: "Performance capacity planning",
            objectives: [
                SkillMapObjective(name: "Estimate peak load"),
                SkillMapObjective(name: "Locate likely bottlenecks"),
                SkillMapObjective(name: "Define meaningful service limits")
            ]
        ),
        SkillMapTopic(
            name: "Security and privacy boundaries",
            objectives: [
                SkillMapObjective(name: "Map trust boundaries"),
                SkillMapObjective(name: "Minimize sensitive data"),
                SkillMapObjective(name: "Explain authorization decisions")
            ]
        ),
        SkillMapTopic(
            name: "Technical decision communication",
            objectives: [
                SkillMapObjective(name: "Compare credible alternatives"),
                SkillMapObjective(name: "Name costs and unknowns"),
                SkillMapObjective(name: "Land a clear recommendation")
            ]
        )
    ]
}

private struct SkillMapEditorRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var content: AnyView
}
