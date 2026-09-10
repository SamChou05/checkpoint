import SwiftUI
import XCTest
@testable import Checkpoint

final class LearningMapExplorerTests: XCTestCase {
    func testOverviewAddsSkillsWithoutMovingExistingBranches() {
        let topics = (1...6).map { SkillMapTopic(name: "Skill \($0)") }
        let initial = LearningMapGraphLayout(map: GoalSkillMap(topics: Array(topics.prefix(3))))
        let expanded = LearningMapGraphLayout(map: GoalSkillMap(topics: topics))
        for node in initial.nodes {
            XCTAssertEqual(expanded.nodes.first { $0.id == node.id }?.position, node.position)
        }
        XCTAssertEqual(Set(expanded.nodes.map { "\($0.position.x):\($0.position.y)" }).count, 7)
        XCTAssertEqual(expanded.edges.count, 6)
        XCTAssertTrue(expanded.edges.allSatisfy { $0.from == .goal && $0.relationship == .membership })
    }

    func testFocusPointExpansionKeepsGoalAndParentAndExistingFocusPointsStable() throws {
        let objectives = (1...5).map { SkillMapObjective(name: "Focus \($0)") }
        let skill = SkillMapTopic(name: "Skill", objectives: Array(objectives.prefix(2)))
        var expandedSkill = skill
        expandedSkill.objectives = objectives
        let initial = LearningMapGraphLayout(map: GoalSkillMap(topics: [skill]), selected: .skill(skill.id))
        let expanded = LearningMapGraphLayout(map: GoalSkillMap(topics: [expandedSkill]), selected: .skill(skill.id))
        for node in initial.nodes {
            XCTAssertEqual(expanded.nodes.first { $0.id == node.id }?.position, node.position)
        }
        XCTAssertEqual(expanded.nodes.count, 7)
        XCTAssertEqual(expanded.edges.filter { $0.relationship == .focusPoint }.count, 5)
        for edge in expanded.edges where edge.relationship == .focusPoint {
            XCTAssertEqual(edge.from, .skill(skill.id))
        }
        let selectedObjective = LearningMapGraphLayout(
            map: GoalSkillMap(topics: [expandedSkill]), selected: .objective(skillID: skill.id, objectiveID: objectives[4].id)
        )
        XCTAssertEqual(selectedObjective.nodes, expanded.nodes, "Inspecting a focus point must not reshuffle its branch.")
    }

    func testSelectionSurvivesRenameAndFallsBackSafelyAfterRemovalOrArchiving() {
        let objective = SkillMapObjective(name: "Evidence")
        let skill = SkillMapTopic(name: "Reasoning", objectives: [objective])
        var renamed = skill
        renamed.name = "Evaluate evidence"
        let selected = LearningMapNodeID.objective(skillID: skill.id, objectiveID: objective.id)
        XCTAssertEqual(LearningMapGraphLayout.resolvedSelection(selected, in: GoalSkillMap(topics: [renamed])), selected)
        renamed.objectives = []
        XCTAssertEqual(LearningMapGraphLayout.resolvedSelection(selected, in: GoalSkillMap(topics: [renamed])), .skill(skill.id))
        let archived = ArchivedSkillMapTopic(topic: skill, reason: .userReplaced, archivedAt: Date(), successorSkillIDs: [], mastery: nil)
        XCTAssertEqual(LearningMapGraphLayout.resolvedSelection(.skill(skill.id), in: GoalSkillMap(topics: [], archivedTopics: [archived])), .history(skill.id))
        XCTAssertEqual(LearningMapGraphLayout.resolvedSelection(selected, in: GoalSkillMap(topics: [])), .goal)
    }

    func testHistoryEdgesRepresentActualProgressionAndCycleTraversalTerminates() {
        let first = SkillMapTopic(name: "Foundations")
        let second = SkillMapTopic(name: "Applied reasoning", predecessorIDs: [first.id])
        let current = SkillMapTopic(name: "Advanced reasoning", stage: 3, predecessorIDs: [second.id])
        var older = first
        older.predecessorIDs = [second.id] // Defensive handling of damaged legacy ancestry.
        let map = GoalSkillMap(topics: [current], archivedTopics: [
            ArchivedSkillMapTopic(topic: older, reason: .mastered, archivedAt: Date(), successorSkillIDs: [second.id], mastery: nil),
            ArchivedSkillMapTopic(topic: second, reason: .userReplaced, archivedAt: Date(), successorSkillIDs: [current.id], mastery: nil)
        ])
        let ancestors = LearningMapGraphLayout.ancestors(of: current.id, in: map)
        XCTAssertEqual(ancestors.map(\.id), [second.id, first.id])
        let layout = LearningMapGraphLayout(map: map, selected: .skill(current.id), showsHistory: true)
        XCTAssertEqual(Set(layout.nodes.map(\.id)).count, layout.nodes.count)
        XCTAssertTrue(layout.edges.contains { $0.from == .history(second.id) && $0.to == .skill(current.id) && $0.relationship == .progression })
        XCTAssertFalse(layout.edges.contains { $0.from == .history(first.id) && $0.to == .skill(current.id) })
        let withoutHistory = LearningMapGraphLayout(map: map, selected: .skill(current.id))
        XCTAssertFalse(withoutHistory.nodes.contains { if case .history = $0.id { return true }; return false })
    }

    func testFiftyArchivedBranchesStayBoundedAndTheirRealLineageRemainsTraversable() throws {
        let archivedSkills = (0..<50).map { SkillMapTopic(name: "Earlier reasoning skill \($0)") }
        let archives = archivedSkills.enumerated().map { index, original in
            var topic = original
            topic.predecessorIDs = index > 0 ? [archivedSkills[index - 1].id] : []
            return ArchivedSkillMapTopic(
                topic: topic, reason: index.isMultiple(of: 2) ? .mastered : .userReplaced,
                archivedAt: Date(timeIntervalSince1970: Double(index)),
                successorSkillIDs: [], mastery: nil
            )
        }
        let current = SkillMapTopic(name: "Current reasoning", objectives: [SkillMapObjective(name: "Linked evidence")],
                                    predecessorIDs: [archivedSkills[49].id])
        let map = GoalSkillMap(topics: [current], archivedTopics: archives)
        let overview = LearningMapGraphLayout(map: map, showsHistory: true)
        XCTAssertEqual(Set(overview.nodes.map(\.id)), [.goal, .history(archivedSkills[49].id), .history(archivedSkills[48].id)])
        XCTAssertEqual(overview.hiddenHistoryCount, 48)
        XCTAssertEqual(overview.edges.filter { $0.relationship == .membership }.count, 2)

        var selected = LearningMapNodeID.skill(current.id)
        for expectedPredecessor in archivedSkills.reversed() {
            let branch = LearningMapGraphLayout(map: map, selected: selected, showsHistory: true)
            XCTAssertLessThanOrEqual(branch.nodes.count, 4)
            XCTAssertFalse(branch.nodes.contains { if case .objective = $0.id { return true }; return false })
            let earlierEdge = try XCTUnwrap(branch.edges.first { $0.to == selected && $0.relationship == .progression })
            XCTAssertEqual(earlierEdge.from, .history(expectedPredecessor.id))
            XCTAssertEqual(branch.edges.filter { $0.relationship == .progression }.count, 1,
                           "An ancestry window must not invent a shortcut to an older milestone.")
            selected = earlierEdge.from
        }
        let beginning = LearningMapGraphLayout(map: map, selected: selected, showsHistory: true)
        XCTAssertEqual(Set(beginning.nodes.map(\.id)), [.goal, .history(archivedSkills[0].id)])
        XCTAssertFalse(beginning.edges.contains { $0.relationship == .progression })
        XCTAssertEqual(map.archivedTopics.count, 50, "A bounded canvas must preserve the complete archive for the list.")
    }

    func testLargeHistoryWindowFitsReadableTargetsAndLimitsMultipleDirectParents() {
        let archives = (0..<50).map { index in
            ArchivedSkillMapTopic(
                topic: SkillMapTopic(name: "A retained milestone with a long descriptive name \(index)"),
                reason: .mastered, archivedAt: Date(timeIntervalSince1970: Double(index)),
                successorSkillIDs: [], mastery: nil
            )
        }
        let current = SkillMapTopic(name: "Current branch", predecessorIDs: Array(archives.suffix(3).map(\.id)))
        let map = GoalSkillMap(topics: [current], archivedTopics: archives)
        for compact in [true, false] {
            let viewport = compact ? CGSize(width: 320, height: 364) : CGSize(width: 393, height: 470)
            for selection in [LearningMapNodeID.goal, .skill(current.id)] {
                let graph = LearningMapGraphLayout(map: map, selected: selection, showsHistory: true, compact: compact)
                XCTAssertEqual(Set(graph.nodes.compactMap { node -> UUID? in
                    if case let .history(id) = node.id { return id }
                    return nil
                }), Set(archives.suffix(2).map(\.id)))
                XCTAssertEqual(graph.hiddenHistoryCount, 48)
                let frames = Dictionary(uniqueKeysWithValues: graph.nodes.map {
                    ($0.id, LearningMapNodeGeometry(id: $0.id, compact: compact, focused: selection != .goal).hitBounds)
                })
                let camera = LearningMapCamera.fitted(nodes: graph.nodes, frames: frames, viewport: viewport)
                let projected = graph.nodes.map { node -> CGRect in
                    let point = camera.project(node.position, viewport: viewport)
                    return frames[node.id]!.offsetBy(dx: point.x, dy: point.y)
                }
                for (index, frame) in projected.enumerated() {
                    XCTAssertTrue(CGRect(origin: .zero, size: viewport).contains(frame))
                    XCTAssertGreaterThanOrEqual(frame.width, 44)
                    XCTAssertGreaterThanOrEqual(frame.height, 44)
                    for other in projected.indices where other > index {
                        XCTAssertFalse(frame.insetBy(dx: 1, dy: 1).intersects(projected[other].insetBy(dx: 1, dy: 1)),
                                       "Growing history must not collapse readable labels into overlapping targets.")
                    }
                }
            }
        }
    }

    func testZoomOutKeepsItsDirectionAfterFittingBelowFormerMinimumZoom() {
        let nodes = [LearningMapGraphNode(id: .goal, position: .zero),
                     LearningMapGraphNode(id: .history(UUID()), position: CGPoint(x: 0, y: 4_000))]
        let viewport = CGSize(width: 320, height: 364)
        let frames = Dictionary(uniqueKeysWithValues: nodes.map {
            ($0.id, LearningMapNodeGeometry(id: $0.id, compact: true, focused: false).hitBounds)
        })
        let fitted = LearningMapCamera.fitted(nodes: nodes, frames: frames, viewport: viewport)
        XCTAssertLessThan(fitted.zoom, 0.18)
        let zoomedOut = fitted.magnified(by: 0.8, anchor: CGPoint(x: 160, y: 182), viewport: viewport)
        XCTAssertLessThan(zoomedOut.zoom, fitted.zoom, "Zooming out from a fitted view must never jump inward.")
        XCTAssertGreaterThanOrEqual(zoomedOut.zoom, LearningMapCamera.zoomRange.lowerBound)
    }

    func testCameraKeepsPinchAnchorFixedAndBoundsExtremeZoom() {
        let viewport = CGSize(width: 393, height: 450)
        let start = LearningMapCamera(center: CGPoint(x: 80, y: -40), zoom: 0.7)
        let world = CGPoint(x: 200, y: 150)
        let anchor = start.project(world, viewport: viewport)
        let zoomed = start.magnified(by: 2, anchor: anchor, viewport: viewport)
        XCTAssertEqual(zoomed.project(world, viewport: viewport).x, anchor.x, accuracy: 0.001)
        XCTAssertEqual(zoomed.project(world, viewport: viewport).y, anchor.y, accuracy: 0.001)
        let panned = start.panned(by: CGSize(width: 25, height: -70))
        XCTAssertEqual(panned.project(world, viewport: viewport).x, anchor.x + 25, accuracy: 0.001)
        XCTAssertEqual(panned.project(world, viewport: viewport).y, anchor.y - 70, accuracy: 0.001)
        XCTAssertEqual(start.magnified(by: 1_000, anchor: anchor, viewport: viewport).zoom, LearningMapCamera.zoomRange.upperBound)
        XCTAssertEqual(start.magnified(by: 0.0001, anchor: anchor, viewport: viewport).zoom, LearningMapCamera.zoomRange.lowerBound)
    }

    func testFitIncludesCurrentBranchAtRepresentativeViewportSizes() {
        let skill = SkillMapTopic(name: "Skill", objectives: (1...5).map { SkillMapObjective(name: "Focus \($0)") })
        let graph = LearningMapGraphLayout(map: GoalSkillMap(topics: [skill]), selected: .skill(skill.id))
        for viewport in [CGSize(width: 320, height: 260), CGSize(width: 393, height: 480), CGSize(width: 600, height: 780)] {
            let camera = LearningMapCamera.fitted(to: graph.bounds, viewport: viewport)
            for node in graph.nodes {
                let point = camera.project(node.position, viewport: viewport)
                XCTAssertTrue(CGRect(origin: .zero, size: viewport).contains(point))
            }
        }
    }

    func testFittedMapContainsReadableNonoverlappingNodeTargets() {
        let skills = (1...6).map { SkillMapTopic(name: "Skill \($0)", objectives: (1...5).map { SkillMapObjective(name: "Focus \($0)") }) }
        let map = GoalSkillMap(topics: skills)
        let fixtures: [(CGSize, Bool, LearningMapNodeID)] = [
            (CGSize(width: 320, height: 364), true, .goal),
            (CGSize(width: 393, height: 470), false, .goal),
            (CGSize(width: 320, height: 364), true, .skill(skills[0].id)),
            (CGSize(width: 393, height: 520), false, .skill(skills[0].id))
        ]
        for (viewport, compact, selection) in fixtures {
            let graph = LearningMapGraphLayout(map: map, selected: selection, compact: compact)
            let frames = Dictionary(uniqueKeysWithValues: graph.nodes.map { node in
                (node.id, LearningMapNodeGeometry(id: node.id, compact: compact, focused: selection != .goal).hitBounds)
            })
            let camera = LearningMapCamera.fitted(nodes: graph.nodes, frames: frames, viewport: viewport)
            let projected = graph.nodes.map { node -> CGRect in
                let point = camera.project(node.position, viewport: viewport)
                return frames[node.id]!.offsetBy(dx: point.x, dy: point.y)
            }
            for (index, frame) in projected.enumerated() {
                XCTAssertTrue(CGRect(origin: .zero, size: viewport).contains(frame), "Clipped \(graph.nodes[index].id) at \(viewport)")
                XCTAssertGreaterThanOrEqual(frame.width, 44)
                XCTAssertGreaterThanOrEqual(frame.height, 44)
                for other in projected.indices where other > index {
                    let firstPoint = camera.project(graph.nodes[index].position, viewport: viewport)
                    let otherPoint = camera.project(graph.nodes[other].position, viewport: viewport)
                    let firstRegions = LearningMapNodeGeometry(id: graph.nodes[index].id, compact: compact, focused: selection != .goal).hitRegions
                    let otherRegions = LearningMapNodeGeometry(id: graph.nodes[other].id, compact: compact, focused: selection != .goal).hitRegions
                    for first in firstRegions {
                        for second in otherRegions {
                            XCTAssertFalse(first.offsetBy(dx: firstPoint.x, dy: firstPoint.y).insetBy(dx: 1, dy: 1)
                                .intersects(second.offsetBy(dx: otherPoint.x, dy: otherPoint.y).insetBy(dx: 1, dy: 1)),
                                "Overlapping \(graph.nodes[index].id) and \(graph.nodes[other].id) at \(viewport)")
                        }
                    }
                }
            }
        }
    }

    func testCompactFocusedBranchKeepsEveryLabelAndTargetSeparateAtActualCanvasHeight() throws {
        let names = [
            "Source credibility", "Relevant evidence", "Cause versus correlation",
            "Recognize unsupported conclusions", "Check explanations against new information"
        ]
        // The SE's 320×568 screen leaves about 261pt after its compact header,
        // controls and selected preview. Keep a point of margin below that size.
        let viewport = CGSize(width: 320, height: 260)
        for count in 1...names.count {
            let skill = SkillMapTopic(name: "Evaluating evidence", objectives:
                names.prefix(count).map { SkillMapObjective(name: $0) })
            let map = GoalSkillMap(topics: [skill])
            let selections: [LearningMapNodeID] = [.skill(skill.id)] + skill.objectives.map {
                .objective(skillID: skill.id, objectiveID: $0.id)
            }
            for selection in selections {
                let graph = LearningMapGraphLayout(map: map, selected: selection, compact: true)
                let geometries = Dictionary(uniqueKeysWithValues: graph.nodes.map { node in
                    (node.id, LearningMapNodeGeometry(
                        id: node.id, compact: true, focused: true, isSelected: node.id == selection
                    ))
                })
                let frames = geometries.mapValues(\.hitBounds)
                let camera = LearningMapCamera.fitted(nodes: graph.nodes, frames: frames, viewport: viewport)
                let projected = try graph.nodes.map { node in
                    let point = camera.project(node.position, viewport: viewport)
                    return try XCTUnwrap(frames[node.id]).offsetBy(dx: point.x, dy: point.y)
                }
                let projectedRegions = try graph.nodes.map { node in
                    let geometry = try XCTUnwrap(geometries[node.id])
                    let nodeTarget = try XCTUnwrap(geometry.hitRegions.first)
                    XCTAssertGreaterThanOrEqual(nodeTarget.width, 44)
                    XCTAssertGreaterThanOrEqual(nodeTarget.height, 44)
                    let point = camera.project(node.position, viewport: viewport)
                    return geometry.hitRegions.map { $0.offsetBy(dx: point.x, dy: point.y) }
                }
                for (index, frame) in projected.enumerated() {
                    XCTAssertTrue(CGRect(origin: .zero, size: viewport).contains(frame),
                                  "Clipped node with \(count) focus points: \(graph.nodes[index].id)")
                    XCTAssertGreaterThanOrEqual(frame.width, 44)
                    XCTAssertGreaterThanOrEqual(frame.height, 44)
                    for other in projected.indices where other > index {
                        for firstRegion in projectedRegions[index] {
                            for otherRegion in projectedRegions[other] {
                                XCTAssertFalse(firstRegion.intersects(otherRegion),
                                               "Overlapping readable labels/targets with \(count) focus points: "
                                                + "\(graph.nodes[index].id) and \(graph.nodes[other].id)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testObjectiveEvidenceRequiresGoalSkillAndObjectiveIdentityAndExcludesReportedQuestions() {
        let goalID = UUID(), skillID = UUID(), objectiveID = UUID()
        func attempt(goal: UUID = goalID, skill: UUID = skillID, objective: UUID? = objectiveID, result: AnswerResult = .correct) -> CheckpointAttempt {
            CheckpointAttempt(questionID: UUID(), goalID: goal, skillID: skill, objectiveID: objective,
                              prompt: "Prompt", answer: "Answer", result: result, unlockMinutes: 0)
        }
        let included = [attempt(), attempt(result: .partial)]
        let reported = attempt()
        let unrelated = [attempt(goal: UUID()), attempt(skill: UUID()), attempt(objective: UUID()), attempt(objective: nil)]
        let evidence = LearningMapObjectiveEvidence(goalID: goalID, skillID: skillID, objectiveID: objectiveID,
                                                   attempts: included + unrelated + [reported], excludedQuestionIDs: [reported.questionID])
        XCTAssertEqual(evidence.answerCount, 2)
        XCTAssertEqual(evidence.correctCount, 1)
        XCTAssertEqual(evidence.partialCount, 1)
        let empty = LearningMapObjectiveEvidence(goalID: goalID, skillID: skillID, objectiveID: UUID(), attempts: included)
        XCTAssertEqual(empty.answerCount, 0)
        XCTAssertEqual(empty.summary, "No answers linked yet")
        XCTAssertNil(empty.lastPracticedAt)
    }

    @MainActor
    func testNativeExplorerRendersOverviewBranchesAndAccessibleList() throws {
        let suite = "LearningMapExplorerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CheckpointStore(defaults: defaults)
        let names = ["Evaluating evidence", "Building arguments", "Drawing inferences", "Recognizing assumptions", "Comparing alternative explanations", "Making thoughtful decisions"]
        let skills = names.map { name in
            SkillMapTopic(name: name, objectives: [
                SkillMapObjective(name: "Source credibility"),
                SkillMapObjective(name: "Relevant evidence"),
                SkillMapObjective(name: "Cause versus correlation"),
                SkillMapObjective(name: "Recognize unsupported conclusions"),
                SkillMapObjective(name: "Check explanations against new information")
            ])
        }
        let goal = Goal(title: "Become a clearer thinker", deadline: Date().addingTimeInterval(86400 * 30), category: .custom,
                        currentLevel: "Intermediate", focusAreas: "Critical thinking",
                        derivedSkillMap: GoalSkillMap(topics: skills, status: .reviewed), preferredQuestionStyle: .multipleChoice)
        store.goal = goal
        store.goalProfiles = [goal]
        store.competencies = skills.enumerated().map { index, skill in
            var value = TopicCompetency.initial(topic: skill.name, estimatedLevel: index == 0 ? 4.5 : 2.5, goalID: goal.id, skillID: skill.id)
            value.attempts = index == 0 ? 18 : index == 1 ? 12 : index == 2 ? 4 : 0
            value.correct = index == 0 ? 17 : index == 1 ? 7 : index == 2 ? 2 : 0
            value.incorrect = value.attempts - value.correct
            return value
        }
        let fixtures: [(String, CGFloat, CGFloat, ColorScheme, DynamicTypeSize, UUID?)] = [
            ("learning-map-overview-compact-light", 320, 640, .light, .large, nil),
            ("learning-map-overview-dark", 393, 852, .dark, .large, nil),
            ("learning-map-focus-compact-light", 320, 640, .light, .large, skills[0].id),
            ("learning-map-focus-se-light", 320, 568, .light, .large, skills[0].id),
            ("learning-map-focus-se-dark", 320, 568, .dark, .large, skills[0].id),
            ("learning-map-focus-five-light", 393, 852, .light, .large, skills[0].id),
            ("learning-map-accessible-list", 320, 852, .dark, .accessibility2, nil)
        ]
        for (name, width, height, scheme, textSize, initialSkill) in fixtures {
            let image = HostedViewRenderer.image(
                for: NavigationStack {
                    LearningMapView(store: store, goalID: goal.id, initialSkillID: initialSkill, onEdit: { _ in })
                }
                .environment(\.dynamicTypeSize, textSize)
                .transaction { $0.disablesAnimations = true },
                width: width, height: height, colorScheme: scheme, settlingTime: 0.25, renderScale: 1
            )
            XCTAssertEqual(image.size.width, width)
            XCTAssertEqual(image.size.height, height)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            if let outputDirectory = ProcessInfo.processInfo.environment["CHECKPOINT_MAP_RENDER_OUTPUT"] {
                let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try image.pngData()?.write(to: directory.appendingPathComponent("\(name).png"))
            }
        }
    }
}
