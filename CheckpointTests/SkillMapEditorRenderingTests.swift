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
        XCTAssertTrue(standard.permitsNodeMotion)

        let reduced = SkillMapMutationMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
        XCTAssertFalse(reduced.permitsNodeMotion)
    }

    func testEditorPresentationKeepsStatusAndActionsTruthful() {
        let suggested = SkillMapEditorPresentation(
            mode: .review(status: .suggested),
            goalTitle: "Pass the architecture interview",
            skillCount: 3,
            namedCount: 3,
            isValid: true,
            hasChanges: false
        )
        XCTAssertEqual(suggested.state, .draftReady)
        XCTAssertEqual(suggested.status, "Suggested")
        XCTAssertEqual(suggested.actionTitle, "Use this skill map")
        XCTAssertTrue(suggested.actionEnabled)

        let current = SkillMapEditorPresentation(
            mode: .review(status: .reviewed),
            goalTitle: "Pass the architecture interview",
            skillCount: 4,
            namedCount: 4,
            isValid: true,
            hasChanges: false
        )
        XCTAssertEqual(current.state, .current)
        XCTAssertEqual(current.status, "Current")
        XCTAssertEqual(current.actionTitle, "Done")

        let changed = SkillMapEditorPresentation(
            mode: .review(status: .reviewed),
            goalTitle: "Pass the architecture interview",
            skillCount: 4,
            namedCount: 4,
            isValid: true,
            hasChanges: true
        )
        XCTAssertEqual(changed.state, .changesReady)
        XCTAssertEqual(changed.status, "Changes ready")
        XCTAssertEqual(changed.actionTitle, "Save changes")

        let repair = SkillMapEditorPresentation(
            mode: .repair,
            goalTitle: "Pass the architecture interview",
            skillCount: 3,
            namedCount: 3,
            isValid: true,
            hasChanges: true
        )
        XCTAssertEqual(repair.state, .ready)
        XCTAssertEqual(repair.status, "Ready")
        XCTAssertEqual(repair.actionTitle, "Use these skills")

        for mode in [
            SkillMapEditorMode.review(status: .suggested),
            .review(status: .reviewed),
            .repair
        ] {
            let invalid = SkillMapEditorPresentation(
                mode: mode,
                goalTitle: "Pass the architecture interview",
                skillCount: 4,
                namedCount: 2,
                isValid: false,
                hasChanges: true
            )
            XCTAssertEqual(invalid.state, .needsAttention)
            XCTAssertEqual(invalid.status, "Needs attention")
            XCTAssertFalse(invalid.actionEnabled)
            XCTAssertTrue(invalid.accessibilitySummary.contains("names entered"))
            XCTAssertTrue(invalid.accessibilitySummary.contains(invalid.title))
            XCTAssertTrue(invalid.accessibilitySummary.contains(invalid.detail))
            XCTAssertFalse(invalid.accessibilitySummary.contains("names complete"))
        }
    }

    func testValidationPinsEachIssueToTheResponsibleSkill() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000321")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000322")!
        let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000323")!

        func validation(_ firstName: String) -> SkillMapEditorValidation {
            SkillMapEditorValidation(
                rows: [
                    SkillMapEditorName(id: firstID, name: firstName),
                    SkillMapEditorName(id: secondID, name: "State modeling"),
                    SkillMapEditorName(id: thirdID, name: "Testing strategy")
                ]
            )
        }

        XCTAssertEqual(validation("   ").issueByTopicID[firstID], .required)
        XCTAssertEqual(
            validation(String(repeating: "a", count: 49)).issueByTopicID[firstID],
            .tooLong(characterCount: 49)
        )
        XCTAssertEqual(
            validation("Requirements, constraints").issueByTopicID[firstID],
            .unsupportedSeparator
        )
        XCTAssertEqual(
            validation("Requirements; constraints").issueByTopicID[firstID],
            .unsupportedSeparator
        )

        let duplicate = SkillMapEditorValidation(
            rows: [
                SkillMapEditorName(id: firstID, name: "Data Flow"),
                SkillMapEditorName(id: secondID, name: "Data-Flow"),
                SkillMapEditorName(id: thirdID, name: "Testing strategy")
            ]
        )
        XCTAssertEqual(duplicate.issueByTopicID[firstID], .duplicate)
        XCTAssertEqual(duplicate.issueByTopicID[secondID], .duplicate)
        XCTAssertFalse(duplicate.isValid)
    }

    func testValidationKeepsArchivedAndRemovedSkillHistoriesDistinct() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000331")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000332")!
        let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000333")!
        let replacementID = UUID(uuidString: "00000000-0000-0000-0000-000000000334")!
        let archivedID = UUID(uuidString: "00000000-0000-0000-0000-000000000335")!
        let original = [
            SkillMapTopic(id: firstID, name: "Requirements discovery"),
            SkillMapTopic(id: secondID, name: "State modeling"),
            SkillMapTopic(id: thirdID, name: "Testing strategy")
        ]
        let archived = ArchivedSkillMapTopic(
            topic: SkillMapTopic(id: archivedID, name: "Retired systems thinking"),
            reason: .userRemoved,
            archivedAt: Date(timeIntervalSince1970: 1_735_689_600),
            successorSkillIDs: [],
            mastery: nil
        )

        let archivedReuse = SkillMapEditorValidation(
            topics: [
                SkillMapTopic(id: firstID, name: "Retired systems thinking"),
                original[1],
                original[2]
            ],
            originalTopics: original,
            archivedTopics: [archived]
        )
        XCTAssertEqual(archivedReuse.issueByTopicID[firstID], .retiredName)

        let archivedIdentityReuse = SkillMapEditorValidation(
            topics: [
                SkillMapTopic(id: archivedID, name: "New systems thinking"),
                original[1],
                original[2]
            ],
            originalTopics: original,
            archivedTopics: [archived]
        )
        XCTAssertEqual(archivedIdentityReuse.issueByTopicID[archivedID], .archivedSkill)
        XCTAssertFalse(archivedIdentityReuse.isValid)

        let removedReuse = SkillMapEditorValidation(
            topics: [
                SkillMapTopic(id: replacementID, name: "Requirements discovery"),
                original[1],
                original[2]
            ],
            originalTopics: original,
            archivedTopics: []
        )
        XCTAssertEqual(removedReuse.issueByTopicID[replacementID], .retiredName)

        let retainedRename = SkillMapEditorValidation(
            topics: [
                SkillMapTopic(id: firstID, name: "Constraint discovery"),
                original[1],
                original[2]
            ],
            originalTopics: original,
            archivedTopics: []
        )
        XCTAssertNil(retainedRename.issueByTopicID[firstID])
        XCTAssertTrue(retainedRename.isValid)

        let duplicateIdentity = SkillMapEditorValidation(
            rows: [
                SkillMapEditorName(id: firstID, name: "Constraint discovery"),
                SkillMapEditorName(id: firstID, name: "State modeling"),
                SkillMapEditorName(id: thirdID, name: "Testing strategy")
            ]
        )
        XCTAssertEqual(duplicateIdentity.issueByTopicID[firstID], .duplicateSkill)
        XCTAssertFalse(duplicateIdentity.isValid)
    }

    @MainActor
    func testRowContinuityCopyMatchesSkillIdentity() {
        XCTAssertEqual(
            SkillNameContinuity.reviewing(status: .reviewed, isExistingSkill: true),
            .preservesProgress
        )
        XCTAssertEqual(
            SkillNameContinuity.reviewing(status: .suggested, isExistingSkill: true),
            .suggested
        )
        XCTAssertEqual(
            SkillNameContinuity.reviewing(status: .reviewed, isExistingSkill: false),
            .startsFresh
        )

        let historyKey = SkillMapReconciler.competencyTopicKey("Evidence synthesis")
        XCTAssertEqual(
            SkillNameContinuity.repairing(
                name: "  EVIDENCE   SYNTHESIS ",
                historyNameKeys: [historyKey]
            ),
            .keepsHistory
        )
        XCTAssertEqual(
            SkillNameContinuity.repairing(
                name: "New skill",
                historyNameKeys: [historyKey]
            ),
            .newSkill
        )

        let retained = SkillNameRowPresentation(
            index: 0,
            name: "Constraint discovery",
            canRemove: true,
            canReplace: true,
            continuity: .preservesProgress
        )
        XCTAssertEqual(retained.statusText, "Progress kept")
        XCTAssertEqual(retained.fieldAccessibilityHint, "Progress kept")

        let replacement = SkillNameRowPresentation(
            index: 1,
            name: "Communication",
            canRemove: true,
            canReplace: false,
            continuity: .startsFresh
        )
        XCTAssertEqual(replacement.statusText, "Starts fresh")

        let invalid = SkillNameRowPresentation(
            index: 2,
            name: "Communication",
            canRemove: true,
            canReplace: false,
            continuity: .startsFresh,
            issue: .duplicate
        )
        XCTAssertEqual(invalid.statusText, "Give this skill a unique name.")
        XCTAssertEqual(invalid.statusSystemImage, "exclamationmark.circle.fill")
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
        let suggestedSuiteName = "SkillMapEditorRenderingTests.Suggested.\(UUID().uuidString)"
        let reviewedSuiteName = "SkillMapEditorRenderingTests.Reviewed.\(UUID().uuidString)"
        let invalidSuiteName = "SkillMapEditorRenderingTests.Invalid.\(UUID().uuidString)"
        let repairSuiteName = "SkillMapEditorRenderingTests.RepairEmpty.\(UUID().uuidString)"
        let suggestedDefaults = try XCTUnwrap(UserDefaults(suiteName: suggestedSuiteName))
        let reviewedDefaults = try XCTUnwrap(UserDefaults(suiteName: reviewedSuiteName))
        let invalidDefaults = try XCTUnwrap(UserDefaults(suiteName: invalidSuiteName))
        let repairDefaults = try XCTUnwrap(UserDefaults(suiteName: repairSuiteName))
        defer {
            suggestedDefaults.removePersistentDomain(forName: suggestedSuiteName)
            reviewedDefaults.removePersistentDomain(forName: reviewedSuiteName)
            invalidDefaults.removePersistentDomain(forName: invalidSuiteName)
            repairDefaults.removePersistentDomain(forName: repairSuiteName)
        }

        let threeTopics = Array(Self.reviewTopics.prefix(3))
        let sixTopics = Self.reviewTopics
        let suggestedStore = makeReviewStore(
            defaults: suggestedDefaults,
            topics: threeTopics,
            status: .suggested
        )
        let reviewedStore = makeReviewStore(
            defaults: reviewedDefaults,
            topics: sixTopics,
            status: .reviewed
        )
        let invalidStore = makeReviewStore(
            defaults: invalidDefaults,
            topics: threeTopics,
            status: .reviewed
        )
        let repairStore = makeRepairStore(defaults: repairDefaults, names: [])
        var invalidTopics = threeTopics
        invalidTopics[0].name = "Data Flow"
        invalidTopics[1] = SkillMapTopic(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000341")!,
            name: "Data-Flow"
        )

        let fixtures = [
            SkillMapEditorRenderFixture(
                name: "skill-map-suggested-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    SkillMapReviewView(store: suggestedStore, reduceMotionOverride: false)
                )
            ),
            SkillMapEditorRenderFixture(
                name: "skill-map-review-six-current-dark",
                width: 393,
                height: 1_500,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    SkillMapReviewView(store: reviewedStore, reduceMotionOverride: false)
                )
            ),
            SkillMapEditorRenderFixture(
                name: "skill-map-reviewed-invalid-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    SkillMapReviewView(
                        store: invalidStore,
                        reduceMotionOverride: false,
                        initialTopics: invalidTopics
                    )
                )
            ),
            SkillMapEditorRenderFixture(
                name: "skill-map-repair-empty-compact-light",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    SkillMapRepairView(store: repairStore, reduceMotionOverride: false)
                )
            ),
            SkillMapEditorRenderFixture(
                name: "skill-map-review-six-ax2-dark-reduced",
                width: 320,
                height: 2_500,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    SkillMapReviewView(store: reviewedStore, reduceMotionOverride: true)
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
        topics: [SkillMapTopic],
        status: SkillMapStatus,
        archivedTopics: [ArchivedSkillMapTopic] = []
    ) -> CheckpointStore {
        let map = GoalSkillMap(
            topics: topics,
            archivedTopics: archivedTopics,
            status: status,
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
