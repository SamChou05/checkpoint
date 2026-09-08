import CoreGraphics
import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class LearningMapInteractionTests: XCTestCase {
    func testAmbientMotionRunsOnlyWhileVisibleIdleAndActive() {
        let idle = policy()
        XCTAssertTrue(idle.allowsSpatialMotion)
        XCTAssertTrue(idle.allowsAmbientMotion)

        for restricted in [policy(isInteracting: true), policy(isMapVisible: false)] {
            XCTAssertTrue(restricted.allowsSpatialMotion, "Direct navigation retains its transition policy.")
            XCTAssertFalse(restricted.allowsAmbientMotion, "Decorative motion stops while exploring or away from the canvas.")
        }
        XCTAssertFalse(policy(isInteracting: true, isMapVisible: false).allowsAmbientMotion)
    }

    func testEveryAccessibilityPauseAndInactiveSceneDisablesSpatialAndAmbientMotion() {
        let restrictions: [(String, LearningMapMotionPolicy)] = [
            ("Reduce Motion", policy(reduceMotion: true)),
            ("VoiceOver", policy(voiceOverEnabled: true)),
            ("Switch Control", policy(switchControlEnabled: true)),
            ("Inactive scene", policy(isSceneActive: false)),
            ("Explicit pause", policy(isPaused: true)),
            ("All accessibility settings", policy(reduceMotion: true, voiceOverEnabled: true, switchControlEnabled: true))
        ]
        for (name, restriction) in restrictions {
            XCTAssertFalse(restriction.allowsSpatialMotion, name)
            XCTAssertFalse(restriction.allowsAmbientMotion, name)
        }
        XCTAssertTrue(policy().allowsAmbientMotion, "Resuming a visible active map restores its eligible motion.")
    }

    func testCameraInverseMappingSurvivesPanAndAnchoredZoom() {
        let viewport = CGSize(width: 393, height: 480)
        let start = LearningMapCamera(center: CGPoint(x: -90, y: 200), zoom: 0.45)
        let moved = start.panned(by: CGSize(width: 113, height: -72))
            .magnified(by: 2.3, anchor: CGPoint(x: 72, y: 389), viewport: viewport)
        for point in [CGPoint.zero, CGPoint(x: -850, y: 400), CGPoint(x: 250, y: -640)] {
            assertPoint(moved.unproject(moved.project(point, viewport: viewport), viewport: viewport), equals: point)
        }
    }

    func testMinimapViewportRepresentsExactCameraEdgesAcrossZoomRange() {
        let viewport = CGSize(width: 320, height: 364)
        for zoom in [LearningMapCamera.zoomRange.lowerBound, 0.35, 1, LearningMapCamera.zoomRange.upperBound] {
            let camera = LearningMapCamera(center: CGPoint(x: 880, y: -630), zoom: zoom)
            let bounds = camera.visibleWorldBounds(viewport: viewport)
            XCTAssertFalse(bounds.isNull)
            assertPoint(camera.project(bounds.origin, viewport: viewport), equals: .zero)
            assertPoint(camera.project(CGPoint(x: bounds.maxX, y: bounds.maxY), viewport: viewport),
                        equals: CGPoint(x: viewport.width, y: viewport.height))
            assertPoint(CGPoint(x: bounds.midX, y: bounds.midY), equals: camera.center)
        }
    }

    func testMinimapRecenteringPreservesZoomAndCentersTappedWorldPoint() {
        let viewport = CGSize(width: 393, height: 480)
        let start = LearningMapCamera(center: CGPoint(x: -250, y: 680), zoom: 1.65)
        let tappedPoint = CGPoint(x: 340, y: -160)
        let recentered = start.recentered(on: tappedPoint)
        XCTAssertEqual(recentered.zoom, start.zoom)
        assertPoint(recentered.project(tappedPoint, viewport: viewport),
                    equals: CGPoint(x: viewport.width / 2, y: viewport.height / 2))
        XCTAssertEqual(start.center, CGPoint(x: -250, y: 680), "Moving the camera does not mutate the previous view.")
    }

    func testFocusCentersSelectedObjectiveAndItsReadableTargetAtEveryViewport() throws {
        let skill = makeSkill()
        let map = GoalSkillMap(topics: [skill])
        let fixtures: [(CGSize, Bool)] = [
            (CGSize(width: 320, height: 260), true),
            (CGSize(width: 393, height: 480), false),
            (CGSize(width: 768, height: 700), false)
        ]
        for (viewport, compact) in fixtures {
            for objective in skill.objectives {
                let selection = LearningMapNodeID.objective(skillID: skill.id, objectiveID: objective.id)
                let graph = LearningMapGraphLayout(map: map, selected: selection, compact: compact)
                let node = try XCTUnwrap(graph.nodes.first { $0.id == selection })
                let geometry = LearningMapNodeGeometry(id: selection, compact: compact, focused: true, isSelected: true)
                let camera = LearningMapCamera(center: CGPoint(x: -800, y: 240), zoom: 0.3)
                    .focused(on: node, frame: geometry.hitBounds, viewport: viewport)
                let point = camera.project(node.position, viewport: viewport)
                let target = geometry.hitBounds.offsetBy(dx: point.x, dy: point.y)
                XCTAssertTrue(CGRect(origin: .zero, size: viewport).contains(target))
                XCTAssertGreaterThanOrEqual(target.width, 44)
                XCTAssertGreaterThanOrEqual(target.height, 44)
                assertPoint(CGPoint(x: target.midX, y: target.midY),
                            equals: CGPoint(x: viewport.width / 2, y: viewport.height / 2))
                XCTAssertGreaterThanOrEqual(camera.zoom, 1)
            }
        }
    }

    func testFocusPreservesCloserZoomAndClampsExplicitZoomPreference() {
        let node = LearningMapGraphNode(id: .objective(skillID: UUID(), objectiveID: UUID()),
                                        position: CGPoint(x: 290, y: 760))
        let geometry = LearningMapNodeGeometry(id: node.id, compact: false, focused: true, isSelected: true)
        let viewport = CGSize(width: 393, height: 480)
        let closer = LearningMapCamera(zoom: 1.8)
        XCTAssertEqual(closer.focused(on: node, frame: geometry.hitBounds, viewport: viewport).zoom, 1.8)
        XCTAssertEqual(closer.focused(on: node, frame: geometry.hitBounds, viewport: viewport, minimumZoom: 100).zoom,
                       LearningMapCamera.zoomRange.upperBound)
        let distant = LearningMapCamera(zoom: 0.4)
        XCTAssertEqual(distant.focused(on: node, frame: geometry.hitBounds, viewport: viewport).zoom, 1)
    }

    func testSelectedObjectiveGainsEmphasisWithoutChangingWorldPositionsOrOtherTargets() throws {
        let skill = makeSkill()
        let map = GoalSkillMap(topics: [skill])
        let selection = LearningMapNodeID.objective(skillID: skill.id, objectiveID: skill.objectives[3].id)
        let before = LearningMapGraphLayout(map: map, selected: .skill(skill.id))
        let selected = LearningMapGraphLayout(map: map, selected: selection)
        XCTAssertEqual(selected.nodes, before.nodes)
        XCTAssertEqual(selected.edges, before.edges)
        for node in selected.nodes {
            let regular = LearningMapNodeGeometry(id: node.id, compact: false, focused: true)
            let emphasized = LearningMapNodeGeometry(id: node.id, compact: false, focused: true, isSelected: node.id == selection)
            XCTAssertEqual(emphasized.width, regular.width)
            if node.id == selection {
                XCTAssertGreaterThan(emphasized.diameter, regular.diameter)
                XCTAssertGreaterThan(emphasized.height, regular.height)
            } else {
                XCTAssertEqual(emphasized.frame, regular.frame)
                XCTAssertEqual(emphasized.hitRegions, regular.hitRegions)
            }
        }
        let target = try XCTUnwrap(selected.nodes.first { $0.id == selection })
        let frame = LearningMapNodeGeometry(id: selection, compact: false, focused: true, isSelected: true).hitBounds
        _ = LearningMapCamera().focused(on: target, frame: frame, viewport: CGSize(width: 393, height: 480))
        XCTAssertEqual(selected.nodes, before.nodes)
    }

    func testReturningToFitAfterCloseExplorationContainsEveryGrownMapTarget() throws {
        let skills = (1...6).map { SkillMapTopic(name: "Skill \($0)") }
        let map = GoalSkillMap(topics: skills)
        let viewport = CGSize(width: 320, height: 364)
        let graph = LearningMapGraphLayout(map: map, compact: true)
        let frames = Dictionary(uniqueKeysWithValues: graph.nodes.map {
            ($0.id, LearningMapNodeGeometry(id: $0.id, compact: true, focused: false).hitBounds)
        })
        let target = try XCTUnwrap(graph.nodes.last)
        let fitted = LearningMapCamera.fitted(nodes: graph.nodes, frames: frames, viewport: viewport)
        let explored = fitted.focused(on: target, frame: try XCTUnwrap(frames[target.id]), viewport: viewport)
            .panned(by: CGSize(width: 900, height: -1200))
        XCTAssertNotEqual(explored.center, fitted.center)
        XCTAssertGreaterThan(explored.zoom, fitted.zoom)
        let reset = LearningMapCamera.fitted(nodes: graph.nodes, frames: frames, viewport: viewport)
        XCTAssertEqual(reset, fitted)
        for node in graph.nodes {
            let point = reset.project(node.position, viewport: viewport)
            XCTAssertTrue(CGRect(origin: .zero, size: viewport).contains(
                try XCTUnwrap(frames[node.id]).offsetBy(dx: point.x, dy: point.y)))
        }
    }

    func testCameraDoesNotMoveForAnUnavailableFocusViewport() {
        let camera = LearningMapCamera(center: CGPoint(x: 40, y: 80), zoom: 0.7)
        let node = LearningMapGraphNode(id: .goal, position: CGPoint(x: -200, y: 400))
        XCTAssertEqual(camera.focused(on: node, frame: CGRect(x: -22, y: -22, width: 44, height: 44), viewport: .zero), camera)
        XCTAssertTrue(camera.visibleWorldBounds(viewport: .zero).isNull)
        XCTAssertEqual(camera.recentered(on: CGPoint(x: CGFloat.infinity, y: 0)), camera)
    }

    func testSkillSelectionHighlightsItsMembershipAndFocusEdgesOnly() {
        let skill = makeSkill()
        let other = makeSkill()
        let graph = LearningMapGraphLayout(map: GoalSkillMap(topics: [skill]), selected: .skill(skill.id))
        let unrelated = LearningMapGraphLayout(map: GoalSkillMap(topics: [other]), selected: .skill(other.id))
        let edges = graph.edges + unrelated.edges
        XCTAssertEqual(edges.filter { LearningMapGraphLayout.isHighlighted(edge: $0, selection: .skill(skill.id)) }, graph.edges)
        XCTAssertEqual(edges.filter { LearningMapGraphLayout.isHighlighted(edge: $0, selection: .goal) },
                       edges.filter { $0.relationship == .membership })
    }

    func testFocusSelectionHighlightsOnlyItsAncestorPathAndNeverSiblingFocusPoints() {
        let skill = makeSkill()
        let graph = LearningMapGraphLayout(map: GoalSkillMap(topics: [skill]), selected: .skill(skill.id))
        for objective in skill.objectives {
            let selection = LearningMapNodeID.objective(skillID: skill.id, objectiveID: objective.id)
            let highlighted = graph.edges.filter { LearningMapGraphLayout.isHighlighted(edge: $0, selection: selection) }
            XCTAssertEqual(highlighted.count, 2)
            XCTAssertEqual(highlighted.first?.from, .goal)
            XCTAssertEqual(highlighted.first?.to, .skill(skill.id))
            XCTAssertEqual(highlighted.last?.from, .skill(skill.id))
            XCTAssertEqual(highlighted.last?.to, selection)
            XCTAssertFalse(highlighted.contains { $0.relationship == .focusPoint && $0.to != selection })
        }
    }

    func testHistorySelectionHighlightsImmediateLineageWithoutImplyingUnrelatedProgression() {
        let ancestor = LearningMapNodeID.history(UUID())
        let selected = LearningMapNodeID.history(UUID())
        let successor = LearningMapNodeID.skill(UUID())
        let other = LearningMapNodeID.history(UUID())
        let included = [
            LearningMapGraphEdge(from: .goal, to: selected, relationship: .membership),
            LearningMapGraphEdge(from: ancestor, to: selected, relationship: .progression),
            LearningMapGraphEdge(from: selected, to: successor, relationship: .progression)
        ]
        let excluded = [
            LearningMapGraphEdge(from: .goal, to: other, relationship: .membership),
            LearningMapGraphEdge(from: other, to: ancestor, relationship: .progression)
        ]
        XCTAssertEqual((included + excluded).filter { LearningMapGraphLayout.isHighlighted(edge: $0, selection: selected) }, included)
    }

    func testArchivedFocusPointUsesItsHistoricalParentPath() {
        let skillID = UUID()
        let selected = LearningMapNodeID.objective(skillID: skillID, objectiveID: UUID())
        let membership = LearningMapGraphEdge(from: .goal, to: .history(skillID), relationship: .membership)
        let focus = LearningMapGraphEdge(from: .history(skillID), to: selected, relationship: .focusPoint)
        XCTAssertTrue(LearningMapGraphLayout.isHighlighted(edge: membership, selection: selected))
        XCTAssertTrue(LearningMapGraphLayout.isHighlighted(edge: focus, selection: selected))
        let unrelated = LearningMapGraphEdge(from: .history(UUID()), to: selected, relationship: .focusPoint)
        XCTAssertFalse(LearningMapGraphLayout.isHighlighted(edge: unrelated, selection: selected))
    }

    /// Explicitly opted-in native window for pointer/gesture QA; never waits in ordinary test runs.
    @MainActor
    func testOptInNativeInteractionWalkthrough() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["CHECKPOINT_MAP_INTERACTION_QA"] == "1",
                          "Set CHECKPOINT_MAP_INTERACTION_QA=1 for the bounded offline native walkthrough.")
        let duration = min(600, max(10, Double(environment["CHECKPOINT_MAP_INTERACTION_QA_SECONDS"] ?? "180") ?? 180))
        let output = URL(fileURLWithPath: environment["CHECKPOINT_MAP_INTERACTION_QA_OUTPUT"]
                         ?? NSTemporaryDirectory() + "CheckpointMapInteractionQA", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output.appendingPathComponent("finish"))
        let suite = "CheckpointMapInteractionQA.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let persistence = output.appendingPathComponent("temporary-store-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: persistence)
        }
        let store = makeOfflineInteractionStore(defaults: defaults, persistence: persistence)
        let initialGoal = try XCTUnwrap(store.goal)
        let initialMap = try XCTUnwrap(initialGoal.derivedSkillMap)
        XCTAssertEqual(initialMap.topics.count, 6)
        XCTAssertTrue(initialMap.topics.allSatisfy { $0.objectives.count == 5 })

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        let appearance = environment["CHECKPOINT_MAP_INTERACTION_QA_APPEARANCE"]
        let scheme: ColorScheme? = appearance == "dark" ? .dark : appearance == "light" ? .light : nil
        let hosting = UIHostingController(rootView:
            LearningMapContainerView(store: store, destination: LearningMapDestination(goalID: initialGoal.id))
                .preferredColorScheme(scheme)
                .transformEnvironment(\.dynamicTypeSize) { value in
                    if let override = environment["CHECKPOINT_MAP_INTERACTION_QA_ACCESSIBILITY_TEXT"] {
                        value = override == "1" ? .accessibility2 : .large
                    }
                }
        )
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.frame = window.bounds
        hosting.view.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(400))
        try captureInteractionWindow(window, name: "interaction-initial", output: output)
        let ready: [String: Any] = [
            "state": "ready", "goalID": initialGoal.id.uuidString,
            "maximumDurationSeconds": duration, "network": "All question generation and bank clients are offline test doubles.",
            "finishFile": output.appendingPathComponent("finish").path,
            "skills": initialMap.topics.map { skill in
                ["id": skill.id.uuidString, "name": skill.name,
                 "focusPoints": skill.objectives.map { ["id": $0.id.uuidString, "name": $0.name] }] as [String: Any]
            }
        ]
        try JSONSerialization.data(withJSONObject: ready, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("ready.json"), options: .atomic)
        print("CHECKPOINT_MAP_INTERACTION_QA_READY \(output.path)")
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline && !FileManager.default.fileExists(atPath: output.appendingPathComponent("finish").path) {
            try await Task.sleep(for: .milliseconds(200))
        }
        try captureInteractionWindow(window, name: "interaction-final", output: output)
        let final: [String: Any] = [
            "state": "finished", "goalID": store.goal?.id.uuidString ?? "",
            "mapChanged": store.goal?.derivedSkillMap != initialMap,
            "skillCount": store.goal?.derivedSkillMap?.topics.count ?? 0,
            "network": "Offline test doubles only",
            "interactionVerdict": "Manual review required; this fixture does not assert successful pointer gestures."
        ]
        try JSONSerialization.data(withJSONObject: final, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("finished.json"), options: .atomic)
    }

    @MainActor
    private func makeOfflineInteractionStore(defaults: UserDefaults, persistence: URL) -> CheckpointStore {
        let store = CheckpointStore(
            questionEngine: HybridQuestionEngine(
                backendEngine: StaticQuestionEngine(provider: .backend, questions: []),
                appleFoundationEngine: StaticQuestionEngine(provider: .appleFoundation, questions: [])
            ),
            questionBankClient: LearningMapOfflineQABank(), defaults: defaults, persistenceDirectory: persistence
        )
        let definitions: [(String, [String])] = [
            ("Evaluating evidence", ["Source credibility", "Relevant evidence", "Cause versus correlation", "Unsupported conclusions", "Testing explanations"]),
            ("Building arguments", ["Clear premises", "Logical structure", "Counterarguments", "Hidden assumptions", "Defensible conclusions"]),
            ("Drawing inferences", ["Deduction", "Induction", "Uncertainty", "Alternative causes", "Calibrated confidence"]),
            ("Recognizing assumptions", ["Implicit premises", "Scope limits", "Necessary conditions", "Counterexamples", "Missing information"]),
            ("Comparing explanations", ["Predictive power", "Competing hypotheses", "Base rates", "Explanatory scope", "Disconfirming evidence"]),
            ("Making thoughtful decisions", ["Tradeoffs", "Opportunity cost", "Decision criteria", "Expected outcomes", "Reversible choices"])
        ]
        var topics = definitions.map { name, focuses in
            SkillMapTopic(name: name,
                          objectives: focuses.map { SkillMapObjective(name: $0, detail: "Apply this idea to a concrete situation.") },
                          detail: "Practice \(name.lowercased()) using clear everyday examples.")
        }
        topics[0].practiceEmphasis = .focus
        topics[5].isPaused = true
        let earlier = SkillMapTopic(name: "Understanding claims", objectives: [SkillMapObjective(name: "Facts and opinions")])
        topics[0].predecessorIDs = [earlier.id]
        let map = GoalSkillMap(topics: topics,
                              archivedTopics: [ArchivedSkillMapTopic(topic: earlier, reason: .mastered,
                                  archivedAt: Date().addingTimeInterval(-86400 * 7), successorSkillIDs: [topics[0].id], mastery: nil)],
                              status: .reviewed, growthMode: .manual)
        let goal = Goal(title: "Become a clearer thinker", deadline: Date().addingTimeInterval(86400 * 30),
                        category: .custom, currentLevel: "Intermediate", focusAreas: "Critical thinking",
                        derivedSkillMap: map, preferredQuestionStyle: .multipleChoice)
        store.goal = goal
        store.goalProfiles = [goal]
        store.membershipTier = .member
        store.isOnboardingPresented = false
        let attempts = [18, 12, 4, 0, 10, 0]
        let correct = [17, 7, 2, 0, 7, 0]
        store.competencies = topics.enumerated().map { index, skill in
            var competency = TopicCompetency.initial(topic: skill.name, estimatedLevel: index == 0 ? 4.5 : 2.5,
                                                      goalID: goal.id, skillID: skill.id)
            competency.attempts = attempts[index]
            competency.correct = correct[index]
            competency.incorrect = attempts[index] - correct[index]
            return competency
        }
        store.attempts = (0..<4).map { index in
            CheckpointAttempt(questionID: UUID(), goalID: goal.id, skillID: topics[0].id,
                              objectiveID: topics[0].objectives[index % 2].id,
                              prompt: "Seeded native QA evidence", answer: "Seeded answer",
                              result: index == 3 ? .partial : .correct, unlockMinutes: 0)
        }
        return store
    }

    @MainActor
    private func captureInteractionWindow(_ window: UIWindow, name: String, output: URL) throws {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent("\(name).png"), options: .atomic)
    }

    private func makeSkill() -> SkillMapTopic {
        SkillMapTopic(name: "Reasoning with evidence", objectives: (1...5).map { SkillMapObjective(name: "Focus \($0)") })
    }

    private func policy(reduceMotion: Bool = false, voiceOverEnabled: Bool = false,
                        switchControlEnabled: Bool = false, isSceneActive: Bool = true,
                        isInteracting: Bool = false, isMapVisible: Bool = true,
                        isPaused: Bool = false) -> LearningMapMotionPolicy {
        LearningMapMotionPolicy(reduceMotion: reduceMotion, voiceOverEnabled: voiceOverEnabled,
                                switchControlEnabled: switchControlEnabled, isSceneActive: isSceneActive,
                                isInteracting: isInteracting, isMapVisible: isMapVisible, isPaused: isPaused)
    }

    private func assertPoint(_ actual: CGPoint, equals expected: CGPoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001, file: file, line: line)
    }
}

/// Makes accidental question requests from editor saves harmless and entirely local.
private struct LearningMapOfflineQABank: QuestionBankSyncing {
    func ensureQuestionBank(for request: QuestionGenerationRequest, contextRevision: String,
                            desiredCount: Int, lowWatermark: Int) async throws -> QuestionBankPreparationReceipt {
        throw QuestionGenerationError.providerUnavailable
    }

    func claimQuestions(from bankID: String, claimID: String, limit: Int,
                        for request: QuestionGenerationRequest) async throws -> QuestionBankClaimReceipt {
        throw QuestionGenerationError.providerUnavailable
    }
}
