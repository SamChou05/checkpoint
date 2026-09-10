import Foundation
import CoreGraphics

/// Stable identities let a branch unfold without replacing the nodes the learner knows.
enum LearningMapNodeID: Hashable, Identifiable {
    case goal
    case skill(SkillMapTopic.ID)
    case objective(skillID: SkillMapTopic.ID, objectiveID: SkillMapObjective.ID)
    case history(SkillMapTopic.ID)

    var id: Self { self }

    var skillID: SkillMapTopic.ID? {
        switch self {
        case .goal: nil
        case let .skill(id), let .history(id): id
        case let .objective(skillID, _): skillID
        }
    }
}

struct LearningMapGraphNode: Identifiable, Equatable {
    let id: LearningMapNodeID
    let position: CGPoint
}

struct LearningMapGraphEdge: Identifiable, Equatable {
    enum Relationship: String {
        case membership
        case focusPoint
        case progression
    }

    let from: LearningMapNodeID
    let to: LearningMapNodeID
    let relationship: Relationship
    var id: String { "\(from)-\(to)-\(relationship.rawValue)" }
}

struct LearningMapMotionPolicy: Equatable, Sendable {
    let reduceMotion: Bool
    let voiceOverEnabled: Bool
    let switchControlEnabled: Bool
    let isSceneActive: Bool
    let isInteracting: Bool
    let isMapVisible: Bool
    let isPaused: Bool

    var allowsSpatialMotion: Bool {
        !reduceMotion && !voiceOverEnabled && !switchControlEnabled && isSceneActive && !isPaused
    }

    var allowsAmbientMotion: Bool {
        allowsSpatialMotion && !isInteracting && isMapVisible
    }
}

struct LearningMapGraphLayout {
    let nodes: [LearningMapGraphNode]
    let edges: [LearningMapGraphEdge]
    let hiddenHistoryCount: Int

    init(map: GoalSkillMap, selected: LearningMapNodeID = .goal, showsHistory: Bool = false, compact: Bool = false) {
        let resolved = Self.resolvedSelection(selected, in: map)
        if showsHistory {
            // A bounded window keeps historical labels and targets readable as the
            // map grows. Selecting an earlier skill walks back through its lineage;
            // the complete archive remains available in the list presentation.
            let progression = Self.progressionEdges(in: map)
            let mostRecent = map.archivedTopics.sorted {
                if $0.archivedAt != $1.archivedAt { return $0.archivedAt > $1.archivedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            var nodes: [LearningMapGraphNode]
            var edges: [LearningMapGraphEdge]
            let earlierSkills: [ArchivedSkillMapTopic]
            if let skillID = resolved.skillID {
                let skillNode: LearningMapNodeID = map.topics.contains { $0.id == skillID }
                    ? .skill(skillID) : .history(skillID)
                let predecessorIDs = Set(progression.filter { $0.to == skillNode }.compactMap { $0.from.skillID })
                earlierSkills = Array(mostRecent.filter { predecessorIDs.contains($0.id) }.prefix(2))
                nodes = [
                    LearningMapGraphNode(id: .goal, position: CGPoint(x: 0, y: -230)),
                    LearningMapGraphNode(id: skillNode, position: .zero)
                ]
                edges = [LearningMapGraphEdge(from: .goal, to: skillNode, relationship: .membership)]
            } else {
                earlierSkills = Array(mostRecent.prefix(2))
                nodes = [LearningMapGraphNode(id: .goal, position: .zero)]
                edges = earlierSkills.map {
                    LearningMapGraphEdge(from: .goal, to: .history($0.id), relationship: .membership)
                }
            }
            for (index, archived) in earlierSkills.enumerated() {
                nodes.append(LearningMapGraphNode(
                    id: .history(archived.id),
                    position: CGPoint(x: earlierSkills.count == 1 ? 0 : (index == 0 ? -145 : 145), y: 280)
                ))
            }
            let visibleIDs = Set(nodes.map(\.id))
            edges += progression.filter { visibleIDs.contains($0.from) && visibleIDs.contains($0.to) }
            self.nodes = nodes
            self.edges = edges
            self.hiddenHistoryCount = map.archivedTopics.count - nodes.filter {
                if case .history = $0.id { return true }
                return false
            }.count
            return
        }
        self.hiddenHistoryCount = map.archivedTopics.count
        if let skillID = resolved.skillID,
           let skill = map.topics.first(where: { $0.id == skillID })
                ?? map.archivedTopics.first(where: { $0.id == skillID })?.topic {
            let isArchived = !map.topics.contains { $0.id == skillID }
            let skillNode: LearningMapNodeID = isArchived ? .history(skillID) : .skill(skillID)
            var nodes = [
                LearningMapGraphNode(id: .goal, position: compact
                    ? CGPoint(x: -120, y: 0) : CGPoint(x: 0, y: -250)),
                LearningMapGraphNode(id: skillNode, position: .zero)
            ]
            var edges = [LearningMapGraphEdge(from: .goal, to: skillNode, relationship: .membership)]
            for (index, objective) in skill.objectives.enumerated() {
                let x: CGFloat
                let point: CGPoint
                if compact {
                    // Labels keep their screen size when fitted. Flank the skill's
                    // title/status before using a lower row, so a short canvas does
                    // not compress three columns into that text or into each other.
                    if skill.objectives.count == 1 {
                        point = CGPoint(x: 0, y: 140)
                    } else if index < 2 {
                        point = CGPoint(x: index == 0 ? -110 : 110, y: 76)
                    } else {
                        let rowIndex = index - 2
                        let rowCount = min(3, skill.objectives.count - 2 - (rowIndex / 3) * 3)
                        x = rowCount == 1 ? 0 : rowCount == 2
                            ? (rowIndex.isMultiple(of: 3) ? -110 : 110)
                            : CGFloat(rowIndex % 3 - 1) * 110
                        point = CGPoint(x: x, y: 170 + CGFloat(rowIndex / 3) * 90)
                    }
                } else {
                    x = skill.objectives.count == 1 ? 0 : (index.isMultiple(of: 2) ? -145 : 145)
                    point = CGPoint(x: x, y: 290 + CGFloat(index / 2) * 200)
                }
                let id = LearningMapNodeID.objective(skillID: skillID, objectiveID: objective.id)
                nodes.append(LearningMapGraphNode(id: id, position: point))
                edges.append(LearningMapGraphEdge(from: skillNode, to: id, relationship: .focusPoint))
            }
            self.nodes = nodes
            self.edges = edges
        } else {
            var nodes = [LearningMapGraphNode(id: .goal, position: .zero)]
            var edges: [LearningMapGraphEdge] = []
            // Six fixed slots retain every existing skill's position when a new one is added.
            let angles: [Double] = [-150, -30, 90, -90, 30, 150]
            for (index, topic) in map.topics.enumerated() {
                let angle = angles[index % angles.count] * .pi / 180
                let radius = CGFloat(300 + (index / angles.count) * 250)
                let id = LearningMapNodeID.skill(topic.id)
                nodes.append(LearningMapGraphNode(
                    id: id,
                    position: CGPoint(x: CGFloat(cos(angle)) * radius, y: CGFloat(sin(angle)) * radius * (compact ? 1.1 : 1))
                ))
                edges.append(LearningMapGraphEdge(from: .goal, to: id, relationship: .membership))
            }
            self.nodes = nodes
            self.edges = edges
        }
    }

    var bounds: CGRect {
        nodes.reduce(CGRect.null) { bounds, node in
            bounds.union(CGRect(x: node.position.x - 92, y: node.position.y - 70, width: 184, height: 175))
        }
    }

    static func resolvedSelection(_ selected: LearningMapNodeID, in map: GoalSkillMap) -> LearningMapNodeID {
        guard let skillID = selected.skillID else { return .goal }
        let active = map.topics.first { $0.id == skillID }
        let archived = map.archivedTopics.first { $0.id == skillID }
        guard let topic = active ?? archived?.topic else { return .goal }
        let parent: LearningMapNodeID = active == nil ? .history(skillID) : .skill(skillID)
        if case let .objective(_, objectiveID) = selected,
           topic.objectives.contains(where: { $0.id == objectiveID }) {
            return selected
        }
        return parent
    }

    static func isHighlighted(edge: LearningMapGraphEdge, selection: LearningMapNodeID) -> Bool {
        switch selection {
        case .goal:
            return edge.relationship == .membership
        case .skill:
            return (edge.relationship == .membership && edge.to == selection)
                || (edge.relationship == .focusPoint && edge.from == selection)
        case let .objective(skillID, _):
            let parent: Bool = edge.to == .skill(skillID) || edge.to == .history(skillID)
            return (edge.relationship == .membership && parent)
                || (edge.relationship == .focusPoint && edge.to == selection && edge.from.skillID == skillID)
        case .history:
            return (edge.relationship == .membership && edge.to == selection)
                || (edge.relationship == .progression && (edge.from == selection || edge.to == selection))
        }
    }

    static func ancestors(of skillID: SkillMapTopic.ID, in map: GoalSkillMap) -> [ArchivedSkillMapTopic] {
        var seen = Set<SkillMapTopic.ID>([skillID])
        var pending = [skillID]
        var result: [ArchivedSkillMapTopic] = []
        while !pending.isEmpty {
            let child = pending.removeFirst()
            let predecessorIDs = (map.topics.first { $0.id == child }
                ?? map.archivedTopics.first { $0.id == child }?.topic)?.predecessorIDs ?? []
            for archived in map.archivedTopics where predecessorIDs.contains(archived.id)
                || archived.successorSkillIDs.contains(child) {
                if seen.insert(archived.id).inserted {
                    result.append(archived)
                    pending.append(archived.id)
                }
            }
        }
        return result
    }

    static func progressionEdges(in map: GoalSkillMap) -> [LearningMapGraphEdge] {
        var result: [LearningMapGraphEdge] = []
        let archivedIDs = Set(map.archivedTopics.map(\.id))
        let topics = map.topics + map.archivedTopics.map(\.topic)
        for topic in topics {
            let predecessors = Set(topic.predecessorIDs + map.archivedTopics.filter {
                $0.successorSkillIDs.contains(topic.id)
            }.map(\.id))
            for predecessor in predecessors.sorted(by: { $0.uuidString < $1.uuidString })
                where predecessor != topic.id && archivedIDs.contains(predecessor) {
                result.append(LearningMapGraphEdge(
                    from: .history(predecessor),
                    to: archivedIDs.contains(topic.id) ? .history(topic.id) : .skill(topic.id),
                    relationship: .progression
                ))
            }
        }
        return result
    }
}

struct LearningMapNodeGeometry {
    let width: CGFloat
    let height: CGFloat
    let diameter: CGFloat
    let showsTitle: Bool

    init(id: LearningMapNodeID, compact: Bool, focused: Bool, isSelected: Bool = false) {
        switch id {
        case .goal where compact && focused:
            (width, height, diameter, showsTitle) = (56, 56, 52, false)
        case .goal where compact || focused:
            (width, height, diameter, showsTitle) = (92, 92, 52, true)
        case .goal:
            (width, height, diameter, showsTitle) = (96, 112, 72, true)
        case .skill:
            (width, height, diameter, showsTitle) = (110, compact ? 100 : 112, compact ? 36 : 46, true)
        case .objective where isSelected:
            (width, height, diameter, showsTitle) = (compact ? 88 : 108, 76, 30, true)
        case .objective:
            (width, height, diameter, showsTitle) = (compact ? 88 : 108, 64, 18, true)
        case .history:
            (width, height, diameter, showsTitle) = (112, 104, 38, true)
        }
    }

    var frame: CGRect { CGRect(x: -width / 2, y: -diameter / 2, width: width, height: height) }

    var hitRegions: [CGRect] {
        let target = max(44, diameter)
        var regions = [CGRect(x: -target / 2, y: -target / 2, width: target, height: target)]
        if showsTitle {
            let gap: CGFloat = diameter >= 52 ? 10 : 7
            regions.append(CGRect(x: -width / 2, y: diameter / 2 + gap,
                                  width: width, height: max(20, height - diameter - gap)))
        }
        return regions
    }

    var hitBounds: CGRect { hitRegions.reduce(.null) { $0.union($1) } }
}

struct LearningMapCamera: Equatable {
    var center: CGPoint = .zero
    var zoom: CGFloat = 1

    static let zoomRange: ClosedRange<CGFloat> = 0.01...2.5

    static func fitted(to bounds: CGRect, viewport: CGSize) -> Self {
        guard !bounds.isNull, viewport.width > 0, viewport.height > 0 else { return Self() }
        let scale = min((viewport.width - 30) / bounds.width, (viewport.height - 30) / bounds.height)
        return Self(center: CGPoint(x: bounds.midX, y: bounds.midY), zoom: max(zoomRange.lowerBound, min(1, scale)))
    }

    static func fitted(nodes: [LearningMapGraphNode], frames: [LearningMapNodeID: CGRect], viewport: CGSize) -> Self {
        guard !nodes.isEmpty, viewport.width > 24, viewport.height > 24 else { return Self() }
        func projectedBounds(at zoom: CGFloat) -> CGRect {
            nodes.reduce(CGRect.null) { bounds, node in
                guard let frame = frames[node.id] else { return bounds }
                return bounds.union(frame.offsetBy(dx: node.position.x * zoom, dy: node.position.y * zoom))
            }
        }
        // Labels and targets retain their readable size while the camera moves.
        // Fit their actual screen bounds, not a scaled approximation of the text.
        var lower = zoomRange.lowerBound
        var upper: CGFloat = 1
        for _ in 0..<40 {
            let candidate = (lower + upper) / 2
            let bounds = projectedBounds(at: candidate)
            if bounds.width <= viewport.width - 24 && bounds.height <= viewport.height - 24 {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        let bounds = projectedBounds(at: lower)
        return Self(center: CGPoint(x: bounds.midX / lower, y: bounds.midY / lower), zoom: lower)
    }

    func project(_ point: CGPoint, viewport: CGSize) -> CGPoint {
        CGPoint(x: (point.x - center.x) * zoom + viewport.width / 2,
                y: (point.y - center.y) * zoom + viewport.height / 2)
    }

    func unproject(_ point: CGPoint, viewport: CGSize) -> CGPoint {
        guard zoom.isFinite, zoom > 0 else { return center }
        return CGPoint(x: center.x + (point.x - viewport.width / 2) / zoom,
                       y: center.y + (point.y - viewport.height / 2) / zoom)
    }

    func visibleWorldBounds(viewport: CGSize) -> CGRect {
        guard zoom.isFinite, zoom > 0,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0 else { return .null }
        return CGRect(origin: unproject(.zero, viewport: viewport),
                      size: CGSize(width: viewport.width / zoom, height: viewport.height / zoom))
    }

    /// The node's screen-sized label remains readable; only camera spacing changes.
    func focused(on node: LearningMapGraphNode, frame: CGRect, viewport: CGSize,
                 minimumZoom: CGFloat = 1) -> Self {
        guard viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0,
              node.position.x.isFinite, node.position.y.isFinite,
              !frame.isNull, !frame.isInfinite else { return self }
        let preferredZoom = max(zoom.isFinite ? zoom : 1, minimumZoom.isFinite ? minimumZoom : 1)
        let nextZoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, preferredZoom))
        // Account for the asymmetric label below the node when centering its target.
        return Self(center: CGPoint(x: node.position.x + frame.midX / nextZoom,
                                    y: node.position.y + frame.midY / nextZoom), zoom: nextZoom)
    }

    func recentered(on point: CGPoint) -> Self {
        guard point.x.isFinite, point.y.isFinite else { return self }
        return Self(center: point, zoom: zoom)
    }

    func panned(by translation: CGSize) -> Self {
        Self(center: CGPoint(x: center.x - translation.width / zoom, y: center.y - translation.height / zoom), zoom: zoom)
    }

    func magnified(by amount: CGFloat, anchor: CGPoint, viewport: CGSize) -> Self {
        let nextZoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom * amount))
        // Preserve the world point under the fingers while pinching.
        let dx = anchor.x - viewport.width / 2
        let dy = anchor.y - viewport.height / 2
        return Self(center: CGPoint(x: center.x + dx / zoom - dx / nextZoom,
                                    y: center.y + dy / zoom - dy / nextZoom), zoom: nextZoom)
    }
}

/// Objective evidence is deliberately independent of its parent's mastery estimate.
struct LearningMapObjectiveEvidence: Equatable {
    let answerCount: Int
    let correctCount: Int
    let partialCount: Int
    let lastPracticedAt: Date?

    init(goalID: Goal.ID, skillID: SkillMapTopic.ID, objectiveID: SkillMapObjective.ID,
         attempts: [CheckpointAttempt], excludedQuestionIDs: Set<CheckpointQuestion.ID> = []) {
        let scoped = attempts.filter {
            $0.goalID == goalID && $0.skillID == skillID && $0.objectiveID == objectiveID
                && !excludedQuestionIDs.contains($0.questionID)
        }
        answerCount = scoped.count
        correctCount = scoped.filter { $0.result == .correct }.count
        partialCount = scoped.filter { $0.result == .partial }.count
        lastPracticedAt = scoped.map(\.createdAt).max()
    }

    var summary: String {
        answerCount == 0 ? "No answers linked yet" : "\(answerCount) linked \(answerCount == 1 ? "answer" : "answers")"
    }
}
