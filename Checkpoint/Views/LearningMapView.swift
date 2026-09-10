import SwiftUI

struct LearningMapView: View {
    let store: CheckpointStore
    let goalID: Goal.ID
    let initialSkillID: SkillMapTopic.ID?
    let onPractice: ((SkillMapTopic.ID) -> Void)?
    let onEdit: ((SkillMapTopic.ID?) -> Void)?
    let isCovered: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: LearningMapNodeID
    @State private var mode: PresentationMode?
    @State private var showsHistory = false
    @State private var camera = LearningMapCamera()
    @State private var viewport = CGSize.zero
    @State private var availableHeight: CGFloat = 0
    @State private var gestureCamera: LearningMapCamera?
    @State private var modal: MapModal?
    @State private var hasPendingEdit = false
    @State private var pendingEditSkillID: SkillMapTopic.ID?
    @State private var suggestionError: String?
    @State private var suggestionMap: GoalSkillMap?
    @State private var scrollToHistory = false
    @State private var motionPaused = false

    private enum PresentationMode: String, CaseIterable, Identifiable {
        case map = "Map"
        case list = "List"
        var id: Self { self }
    }

    private enum MapModal: String, Identifiable {
        case details, legend, suggestion
        var id: Self { self }
    }

    init(store: CheckpointStore, goalID: Goal.ID, initialSkillID: SkillMapTopic.ID? = nil,
         onPractice: ((SkillMapTopic.ID) -> Void)? = nil,
         onEdit: ((SkillMapTopic.ID?) -> Void)? = nil, isCovered: Bool = false) {
        self.store = store
        self.goalID = goalID
        self.initialSkillID = initialSkillID
        self.onPractice = onPractice
        self.onEdit = onEdit
        self.isCovered = isCovered
        _selected = State(initialValue: initialSkillID.map(LearningMapNodeID.skill) ?? .goal)
    }

    private var goal: Goal? {
        store.goal?.id == goalID ? store.goal : store.goalProfiles.first { $0.id == goalID }
    }

    private var map: GoalSkillMap? { goal?.derivedSkillMap }
    private var effectiveMode: PresentationMode {
        mode ?? ((voiceOverEnabled || switchControlEnabled || dynamicTypeSize >= .xxLarge) ? .list : .map)
    }
    private var motionPolicy: LearningMapMotionPolicy {
        LearningMapMotionPolicy(
            reduceMotion: reduceMotion, voiceOverEnabled: voiceOverEnabled,
            switchControlEnabled: switchControlEnabled, isSceneActive: scenePhase == .active,
            isInteracting: gestureCamera != nil, isMapVisible: effectiveMode == .map && modal == nil && !isCovered,
            isPaused: motionPaused
        )
    }
    private var motion: Animation? {
        motionPolicy.allowsSpatialMotion ? .spring(response: 0.58, dampingFraction: 0.84) : nil
    }
    private var fittedCamera: LearningMapCamera {
        guard let graph else { return LearningMapCamera() }
        return .fitted(nodes: graph.nodes, frames: nodeFrames(graph), viewport: viewport)
    }
    private var zoomPercent: Int {
        Int((camera.zoom / max(0.01, fittedCamera.zoom) * 100).rounded())
    }
    private var hasCustomCamera: Bool {
        abs(camera.zoom - fittedCamera.zoom) > 0.015
            || hypot(camera.center.x - fittedCamera.center.x, camera.center.y - fittedCamera.center.y) > 12
    }
    private var editTitle: String {
        editableSelectedSkillID == nil ? "Edit map" : selectedIsObjective ? "Edit focus" : "Edit skill"
    }
    private var compactWindow: Bool {
        (availableHeight > 0 && availableHeight < 620) || (viewport.width > 0 && viewport.width < 350)
    }
    private var compactNodes: Bool { compactWindow || viewport.height < (selected == .goal ? 420 : 480) }
    private var usesCompactBranchHeader: Bool {
        compactWindow && selected != .goal && effectiveMode == .map
            && !dynamicTypeSize.isAccessibilitySize
    }
    private var graph: LearningMapGraphLayout? {
        map.map { LearningMapGraphLayout(map: $0, selected: selected, showsHistory: showsHistory, compact: compactNodes) }
    }
    private var activeCompetencies: [TopicCompetency] {
        guard let map else { return [] }
        return SkillMapReconciler.orderedCompetencies(
            for: map, from: store.competencies.filter { $0.goalID == goalID || $0.goalID == nil }, goalID: goalID
        )
    }
    private var nextFocus: StudyFocusRecommendation? {
        store.goal?.id == goalID ? store.studyFocusRecommendation : nil
    }
    private var excludedQuestions: Set<CheckpointQuestion.ID> {
        Set(store.questionReports.filter { $0.goalID == goalID }.map(\.questionID))
    }

    var body: some View {
        Group {
            if let goal, let map, !map.topics.isEmpty {
                VStack(spacing: 0) {
                    header(goal: goal, map: map)
                    if effectiveMode == .map {
                        if showsHistory { historyNavigation(map: map) }
                        mapCanvas(map: map)
                        if compactWindow { compactSelectionPreview(map: map) }
                        else { selectionPreview(map: map) }
                    } else {
                        listContents(map: map)
                    }
                }
                .background(LearningMapPalette.background.color)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { availableHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in availableHeight = height }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label(goal == nil ? "Goal unavailable" : "Your map is taking shape", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text(goal == nil ? "Return to Progress to choose a current goal." : "Your skills will appear here once your learning map is ready.")
                } actions: {
                    Button("Back to Progress") { dismiss() }
                }
            }
        }
        .navigationTitle("Learning map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let onEdit, map != nil {
                    Button {
                        onEdit(editableSelectedSkillID)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(LearningMapPalette.accent.color.opacity(0.09), in: Capsule())
                    }
                    .accessibilityLabel(editableSelectedSkillID == nil ? "Edit learning map" : selectedIsObjective ? "Edit selected focus points" : "Edit selected skill")
                    .accessibilityIdentifier("learning-map-edit")
                }
            }
        }
        .sheet(item: $modal, onDismiss: finishModalDismissal) { destination in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch destination {
                        case .details: inspector
                        case .legend: legend
                        case .suggestion: suggestionReview
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .background(LearningMapPalette.background.color)
                .navigationTitle(destination == .legend ? "Reading your map" : destination == .suggestion ? "Suggested growth" : "Learning details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { modal = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: selected)
        .onChange(of: compactNodes) { _, _ in
            if selectedIsObjective && hasCustomCamera { focusCamera(on: selected) }
            else { fitMap() }
        }
        .onChange(of: map) { _, updated in
            guard let updated else { return }
            withAnimation(motion) {
                selected = LearningMapGraphLayout.resolvedSelection(selected, in: updated)
                fitMap()
            }
        }
        .onChange(of: goalID) { _, _ in resetSelection() }
        .onChange(of: store.goal?.id) { old, new in
            if old == goalID, new != goalID { dismiss() }
        }
        .onChange(of: initialSkillID) { _, value in
            select(value.map(LearningMapNodeID.skill) ?? .goal)
        }
        .task {
            if let map { selected = LearningMapGraphLayout.resolvedSelection(selected, in: map) }
        }
    }

    private func header(goal: Goal, map: GoalSkillMap) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if usesCompactBranchHeader {
                HStack(alignment: .center, spacing: 8) {
                    compactBranchNavigation(goal: goal)
                    Spacer(minLength: 0)
                    modePicker.frame(width: 132)
                }
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    goalButton(goal)
                    modePicker
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    goalButton(goal)
                    Spacer(minLength: 0)
                    modePicker.frame(width: 132)
                }
            }
            if selected != .goal, effectiveMode == .map, !usesCompactBranchHeader { mapBreadcrumbs }
            if let suggestion = map.pendingEvolutionSuggestion {
                Button {
                    suggestionError = nil
                    suggestionMap = map
                    modal = .suggestion
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "sparkles")
                        Text("\(suggestion.replacements.count) \(suggestion.replacements.count == 1 ? "new branch" : "new branches") to review")
                            .font(.footnote.weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                    .foregroundStyle(LearningMapPalette.accent.color)
                    .padding(12)
                    .frame(minHeight: 44)
                    .background(LearningMapPalette.accent.color.opacity(0.08), in: RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius))
                }
                .buttonStyle(.plain)
            } else if map.status == .suggested {
                Text("Suggested map · Review and make it yours with Edit")
                    .font(.caption)
                    .foregroundStyle(LearningMapPalette.secondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(LearningMapPalette.background.color)
    }

    // Keep both hierarchy actions in the same row as Map/List on short phones.
    // The selected skill/focus name remains in the canvas and preview below.
    private func compactBranchNavigation(goal: Goal) -> some View {
        HStack(spacing: 4) {
            Button { select(.goal) } label: {
                Label("All skills", systemImage: "square.grid.2x2")
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Return to goal: " + goal.title)
            .accessibilityIdentifier("learning-map-overview")
            if selectedIsObjective, let topic = selectedTopic {
                Button {
                    select(selectedIsArchived ? .history(topic.id) : .skill(topic.id))
                } label: {
                    Image(systemName: "arrow.turn.up.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Fit branch: " + topic.name)
                .accessibilityIdentifier("learning-map-branch")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(LearningMapPalette.accent.color)
        .buttonStyle(CheckpointPressButtonStyle())
    }

    private func goalButton(_ goal: Goal) -> some View {
        Button { select(.goal) } label: {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "scope").padding(.top, 2)
                Text(goal.title)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(LearningMapPalette.text.color)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(LearningMapPalette.accent.color)
            .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Return to goal: \(goal.title)")
    }

    private var modePicker: some View {
        Picker("Map presentation", selection: Binding(get: { effectiveMode }, set: { mode = $0 })) {
            ForEach(PresentationMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func historyNavigation(map: GoalSkillMap) -> some View {
        let visibleCount = graph?.nodes.filter { if case .history = $0.id { return true }; return false }.count ?? 0
        return Button {
            scrollToHistory = true
            mode = .list
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("View all \(map.archivedTopics.count) earlier skills")
                        .font(.footnote.weight(.semibold))
                    Text("\(visibleCount) shown here · Select a branch to trace further back")
                        .font(.caption)
                        .foregroundStyle(LearningMapPalette.secondary.color)
                }
                Spacer(minLength: 0)
                Image(systemName: "list.bullet").font(.subheadline)
            }
            .foregroundStyle(LearningMapPalette.accent.color)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }

    private var mapBreadcrumbs: some View {
        HStack(spacing: 7) {
            Button { select(.goal) } label: {
                Label("All skills", systemImage: "square.grid.2x2")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("learning-map-overview")
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            if let topic = selectedTopic {
                Button {
                    select(selectedIsArchived ? .history(topic.id) : .skill(topic.id))
                } label: {
                    Text(topic.name).lineLimit(1).truncationMode(.middle)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Fit branch: " + topic.name)
                .accessibilityIdentifier("learning-map-branch")
            }
            if selectedIsObjective {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                Image(systemName: "viewfinder").accessibilityLabel("Focus point")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(LearningMapPalette.accent.color)
        .frame(minHeight: 44, alignment: .leading)
        .buttonStyle(CheckpointPressButtonStyle())
    }

    private func mapCanvas(map: GoalSkillMap) -> some View {
        GeometryReader { proxy in
            let layout = LearningMapGraphLayout(map: map, selected: selected, showsHistory: showsHistory, compact: compactNodes)
            let canvasSize = CGSize(width: proxy.size.width, height: max(100, proxy.size.height - 58))
            ZStack(alignment: .bottom) {
                ZStack {
                    LivingMapBackdrop(animationsEnabled: motionPolicy.allowsAmbientMotion, isInteracting: gestureCamera != nil)
                    connections(layout: layout, viewport: canvasSize)
                    ForEach(layout.nodes) { node in
                        let point = camera.project(node.position, viewport: canvasSize)
                        mapNode(node.id, map: map)
                            .position(x: point.x, y: point.y + labelOffset(for: node.id))
                            .transition(motionPolicy.allowsSpatialMotion ? .opacity.combined(with: .scale(scale: 0.78)) : .identity)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .contentShape(Rectangle())
                .clipped()
                .gesture(explorationGesture(size: canvasSize))
                .overlay(alignment: .topTrailing) {
                    if hasCustomCamera {
                        LearningMapNavigator(layout: layout, camera: camera, viewport: canvasSize, selection: selected,
                                             onRecenter: { point in withAnimation(motion) { camera = camera.recentered(on: point) } },
                                             onFit: { withAnimation(motion) { fitMap() } })
                            .padding(10)
                            .transition(motionPolicy.allowsSpatialMotion ? .opacity : .identity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)

                canvasControls(map: map)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 7)
            }
            .onAppear { updateViewport(canvasSize) }
            .onChange(of: canvasSize) { _, size in updateViewport(size) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(showsHistory ? "Historical skill connections" : "Interactive learning map")
        }
        .animation(motion, value: map)
    }

    private func connections(layout: LearningMapGraphLayout, viewport: CGSize) -> some View {
        let positions = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.position) })
        return ZStack {
            ForEach(layout.edges) { edge in
                if let from = positions[edge.from], let to = positions[edge.to] {
                    LivingMapConnection(
                        start: camera.project(from, viewport: viewport), end: camera.project(to, viewport: viewport),
                        tint: edge.relationship == .progression ? LearningMapPalette.building.color : LearningMapPalette.accent.color,
                        highlighted: LearningMapGraphLayout.isHighlighted(edge: edge, selection: selected),
                        isHistorical: edge.relationship == .progression,
                        animationsEnabled: motionPolicy.allowsAmbientMotion
                    )
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func mapNode(_ id: LearningMapNodeID, map: GoalSkillMap) -> some View {
        let visual = nodeVisual(id, map: map)
        let isSelected = selected == id
        return Button {
            if selected == id { modal = .details } else { select(id) }
        } label: {
            VStack(spacing: id == .goal ? 10 : 7) {
                LivingMapNodeFace(
                    diameter: visual.diameter, tint: visual.tint, progress: visual.progress,
                    symbol: visual.symbol, isSelected: isSelected, isGoal: id == .goal,
                    evidenceAvailable: visual.evidenceAvailable,
                    animationsEnabled: motionPolicy.allowsAmbientMotion
                )
                .overlay(alignment: .bottomTrailing) {
                    if case let .skill(skillID) = id, selected == .goal,
                       let topic = map.topics.first(where: { $0.id == skillID }), !topic.objectives.isEmpty {
                        HStack(spacing: 2) {
                            Text("\(topic.objectives.count)")
                            Image(systemName: "chevron.down").font(.system(size: 6, weight: .heavy))
                        }
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(visual.tint)
                        .padding(.horizontal, 4).padding(.vertical, 3)
                        .background(LearningMapPalette.panel.color, in: Capsule())
                        .overlay(Capsule().stroke(visual.tint.opacity(0.25), lineWidth: 0.7))
                        .offset(x: 5, y: 3)
                        .accessibilityHidden(true)
                    }
                }
                if visual.showsTitle {
                Text(id == .goal ? "Your goal" : visual.title)
                    .font(id == .goal ? .system(.subheadline, design: .serif) : .caption.weight(.semibold))
                    .foregroundStyle(LearningMapPalette.text.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
                    .background(LearningMapPalette.background.color.opacity(0.88), in: RoundedRectangle(cornerRadius: 5))
                }
                if let subtitle = visual.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(visual.tint)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(LearningMapPalette.background.color.opacity(0.92), in: Capsule())
                }
            }
            .frame(width: visual.width, height: visual.height, alignment: .top)
            .contentShape(LearningMapNodeHitShape(geometry: LearningMapNodeGeometry(id: id, compact: compactNodes, focused: selected != .goal, isSelected: selected == id)))
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .accessibilityLabel(visual.title)
        .accessibilityValue(accessibilityValue(for: id, map: map))
        .accessibilityHint(isSelected ? "Opens details and evidence. More actions include editing." : "Zooms into this branch. Press and hold for details and editing.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("learning-map-node-\(id)")
        .contextMenu {
            Button { select(id); modal = .details } label: { Label("View details", systemImage: "info.circle") }
            Button { select(id); focusCamera(on: id) } label: { Label("Look closer", systemImage: "plus.magnifyingglass") }
            if let onEdit {
                Button {
                    let activeID = id.skillID.flatMap { target in map.topics.first(where: { $0.id == target })?.id }
                    onEdit(activeID)
                } label: {
                    Label(id == .goal || !map.topics.contains(where: { $0.id == id.skillID }) ? "Edit map" : "Edit skill & focus points", systemImage: "pencil")
                }
            }
            Button { select(.goal) } label: { Label("All skills", systemImage: "square.grid.2x2") }
        }
        .dynamicTypeSize(.small ... .large)
    }

    private func canvasControls(map: GoalSkillMap) -> some View {
        HStack(spacing: 10) {
            Menu {
                Button { modal = .legend } label: { Label("Reading your map", systemImage: "info.circle") }
                Button { motionPaused.toggle() } label: {
                    Label(motionPaused ? "Resume map motion" : "Pause map motion", systemImage: motionPaused ? "play.circle" : "pause.circle")
                }
                .disabled(reduceMotion || voiceOverEnabled || switchControlEnabled)
                if !map.archivedTopics.isEmpty {
                    Button {
                        withAnimation(motion) {
                            if !showsHistory, case let .objective(skillID, _) = selected {
                                selected = map.topics.contains { $0.id == skillID } ? .skill(skillID) : .history(skillID)
                            }
                            showsHistory.toggle()
                            fitMap()
                        }
                    } label: {
                        Label(showsHistory ? "Hide earlier branches" : "Show earlier branches", systemImage: "clock.arrow.circlepath")
                    }
                }
                Button { select(.goal) } label: { Label("Return to all skills", systemImage: "square.grid.2x2") }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    .background(LearningMapPalette.panel.color, in: Circle())
                    .overlay(Circle().stroke(LearningMapPalette.border.color.opacity(0.6), lineWidth: 1))
            }
            .accessibilityLabel("Map options")
            .accessibilityIdentifier("learning-map-options")
            Text(selected == .goal ? "Tap a skill" : "Drag or pinch")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LearningMapPalette.secondary.color)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                Button { zoom(by: 0.8) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Zoom out")
                Button { withAnimation(motion) { fitMap() } } label: {
                    VStack(spacing: 1) {
                        Text("\(zoomPercent)%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        Text("Fit map").font(.system(size: 8, weight: .medium))
                    }
                    .frame(width: 56, height: 44)
                }
                .accessibilityLabel("Fit map to view")
                .accessibilityValue("Zoom \(zoomPercent) percent")
                .accessibilityIdentifier("learning-map-fit")
                Button { zoom(by: 1.25) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Zoom in")
            }
            .background(LearningMapPalette.panel.color, in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius)
                .stroke(LearningMapPalette.border.color, lineWidth: 1))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(LearningMapPalette.accent.color)
        .buttonStyle(CheckpointPressButtonStyle())
    }

    private func compactSelectionPreview(map: GoalSkillMap) -> some View {
        let visual = nodeVisual(selected, map: map)
        return HStack(spacing: 8) {
            Button { modal = .details } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected == .goal ? "\(map.topics.count) skills, connected" : visual.title)
                        .font(.system(.subheadline, design: .serif)).lineLimit(1).foregroundStyle(LearningMapPalette.text.color)
                    Text(selected == .goal ? "Tap a skill. See what unfolds." : selectionContext(for: selected, map: map))
                        .font(.caption).lineLimit(1).foregroundStyle(LearningMapPalette.secondary.color)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityHint("Opens learning details and evidence.")
            if let skill = selectedTopic, !selectedIsArchived {
                Button { if !skill.isPaused { onPractice?(skill.id) } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: skill.isPaused ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .semibold))
                        Text(skill.isPaused ? "Paused" : "Practice").font(.system(size: 9, weight: .semibold))
                    }
                    .frame(width: 58, height: 48)
                    .foregroundStyle(LearningMapPalette.actionText.color)
                    .background(LearningMapPalette.actionFill.color, in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius))
                }
                .disabled(skill.isPaused || onPractice == nil)
                .accessibilityLabel(skill.isPaused ? "Practice paused for \(skill.name)" : "Practice \(skill.name)")
                .accessibilityIdentifier("learning-map-practice")
            }
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .foregroundStyle(LearningMapPalette.accent.color)
        .padding(12)
        .background(previewSurface)
        .padding(.horizontal, 12).padding(.bottom, 6).padding(.top, 4)
    }

    private func selectionPreview(map: GoalSkillMap) -> some View {
        let visual = nodeVisual(selected, map: map)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selected == .goal ? "YOUR LEARNING JOURNEY" : selectedIsObjective ? "FOCUS POINT" : selectedIsArchived ? "EARLIER BRANCH" : "SELECTED SKILL")
                        .font(.system(size: 10, weight: .medium)).tracking(1)
                        .foregroundStyle(LearningMapPalette.accent.color)
                    Text(selected == .goal ? (showsHistory ? "Your progress stays with you" : "\(map.topics.count) skills, connected") : visual.title)
                        .font(CheckpointTypography.sectionTitle).foregroundStyle(LearningMapPalette.text.color)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(selected == .goal ? (showsHistory ? "Explore the branches that brought you here." : "Tap a skill to unfold its focus points. Make this map your own.") : selectionContext(for: selected, map: map))
                        .font(.caption).foregroundStyle(LearningMapPalette.secondary.color)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected == .goal ? "point.3.connected.trianglepath.dotted" : visual.symbol ?? "viewfinder")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(visual.tint)
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 9) {
                if selected == .goal, !showsHistory, let first = map.topics.first {
                    let next = nextFocus?.skillID.flatMap { candidate in map.topics.first { $0.id == candidate } } ?? first
                    previewAction(nextFocus?.skillID == next.id ? "Next skill" : "Explore a skill", symbol: "arrow.up.right", prominent: true) {
                        select(.skill(next.id))
                    }
                } else if let skill = selectedTopic, !selectedIsArchived {
                    previewAction(skill.isPaused ? "Practice paused" : "Practice this skill", symbol: "play.fill", prominent: true) {
                        guard !skill.isPaused else { return }
                        onPractice?(skill.id)
                    }
                    .disabled(skill.isPaused || onPractice == nil)
                    .accessibilityIdentifier("learning-map-practice")
                    previewAction("Details", symbol: "info.circle", prominent: false) { modal = .details }
                } else {
                    previewAction("View details", symbol: "arrow.up.right", prominent: true) { modal = .details }
                }
            }
        }
        .padding(16)
        .background(previewSurface)
        .padding(.horizontal, 14).padding(.bottom, 12).padding(.top, 4)
    }

    private var previewSurface: some View {
        RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius)
            .fill(LearningMapPalette.panel.color)
            .overlay {
                RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius)
                    .strokeBorder(LearningMapPalette.border.color, lineWidth: 1)
            }
    }

    private func previewAction(_ title: String, symbol: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(prominent ? LearningMapPalette.actionText.color : LearningMapPalette.accent.color)
                .background(prominent ? LearningMapPalette.actionFill.color : LearningMapPalette.accent.color.opacity(0.07), in: RoundedRectangle(cornerRadius: CheckpointTheme.compactCornerRadius))
        }
        .buttonStyle(CheckpointPressButtonStyle())
    }

    private func listContents(map: GoalSkillMap) -> some View {
        ScrollViewReader { reader in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("\(map.topics.count) skills · \(map.topics.reduce(0) { $0 + $1.objectives.count }) focus points")
                    .font(.footnote).foregroundStyle(LearningMapPalette.secondary.color)
                ForEach(map.topics) { skill in
                    VStack(alignment: .leading, spacing: 4) {
                        listNode(.skill(skill.id), map: map)
                        ForEach(skill.objectives) { objective in
                            if dynamicTypeSize.isAccessibilitySize {
                                Divider().padding(.vertical, 6)
                                listNode(.objective(skillID: skill.id, objectiveID: objective.id), map: map)
                            } else {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "arrow.turn.down.right").foregroundStyle(LearningMapPalette.border.color).padding(.top, 16)
                                listNode(.objective(skillID: skill.id, objectiveID: objective.id), map: map)
                            }
                            .padding(.leading, 13)
                            }
                        }
                    }
                    .padding(15)
                    .background(LearningMapPalette.panel.color, in: RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius))
                }
                if !map.archivedTopics.isEmpty {
                    Text("Your earlier branches").font(.headline).foregroundStyle(LearningMapPalette.text.color)
                        .id("learning-map-history")
                    Text("Earned milestones and previous choices stay part of your story.")
                        .font(.footnote).foregroundStyle(LearningMapPalette.secondary.color)
                    ForEach(map.archivedTopics) { archived in
                        listNode(.history(archived.id), map: map)
                            .padding(15)
                            .background(LearningMapPalette.panel.color, in: RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius))
                    }
                }
            }
            .padding(20)
        }
        .accessibilityIdentifier("learning-map-list")
        .task(id: scrollToHistory) {
            guard scrollToHistory else { return }
            await Task.yield()
            reader.scrollTo("learning-map-history", anchor: .top)
            scrollToHistory = false
        }
        }
    }

    private func listNode(_ id: LearningMapNodeID, map: GoalSkillMap) -> some View {
        let visual = nodeVisual(id, map: map)
        return Button {
            select(id)
            modal = .details
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: visual.symbol ?? "circle.dotted")
                        .foregroundStyle(visual.tint)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(visual.title).font(.subheadline.weight(.semibold)).foregroundStyle(LearningMapPalette.text.color)
                    Text(accessibilityValue(for: id, map: map)).font(.caption).foregroundStyle(LearningMapPalette.secondary.color)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(LearningMapPalette.secondary.color)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details and evidence.")
    }

    @ViewBuilder
    private var inspector: some View {
        if let map {
            let visual = nodeVisual(selected, map: map)
            Text(visual.title).font(CheckpointTypography.sectionTitle).foregroundStyle(LearningMapPalette.text.color).fixedSize(horizontal: false, vertical: true)
            if selected == .goal {
                let practiced = activeCompetencies.filter { $0.attempts > 0 }.count
                Text("\(practiced) of \(map.topics.count) skills practiced · \(map.archivedTopics.filter { $0.reason == .mastered }.count) earned milestones")
                    .font(.subheadline).foregroundStyle(LearningMapPalette.accent.color)
                Text("Your goal connects to each skill. Smaller branches are the focus points that make that skill concrete. Your answers strengthen the skill's progress signal.")
                    .font(.body).foregroundStyle(LearningMapPalette.secondary.color)
                if let nextFocus {
                    Text("Next focus").font(.headline).foregroundStyle(LearningMapPalette.text.color)
                    Text(nextFocus.detail).font(.subheadline).foregroundStyle(LearningMapPalette.secondary.color)
                    if let id = nextFocus.skillID { Button(nextFocus.skillName) { select(.skill(id)) } }
                }
                if onEdit != nil { editButton(title: "Edit learning map", skillID: nil) }
            } else if let skill = selectedTopic {
                if case let .objective(_, objectiveID) = selected,
                   let objective = skill.objectives.first(where: { $0.id == objectiveID }) {
                    let evidence = objectiveEvidence(skillID: skill.id, objectiveID: objective.id)
                    Text("Part of \(skill.name)").font(.subheadline.weight(.medium)).foregroundStyle(LearningMapPalette.accent.color)
                    if !objective.detail.isEmpty { Text(objective.detail).foregroundStyle(LearningMapPalette.secondary.color) }
                    Text(evidence.summary).font(.headline).foregroundStyle(LearningMapPalette.text.color)
                    if evidence.answerCount > 0 {
                        Text("\(evidence.correctCount) correct · \(evidence.partialCount) partial · \(evidence.answerCount - evidence.correctCount - evidence.partialCount) other answers")
                            .font(.subheadline).foregroundStyle(LearningMapPalette.secondary.color)
                    }
                    Text("Focus points show answers linked directly to this idea. They do not inherit the parent skill's mastery estimate.")
                        .font(.footnote).foregroundStyle(LearningMapPalette.secondary.color)
                    if let date = evidence.lastPracticedAt {
                        Text("Last practiced \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.footnote).foregroundStyle(LearningMapPalette.secondary.color)
                    }
                    if onEdit != nil, !selectedIsArchived { editButton(title: "Edit focus points", skillID: skill.id) }
                } else if let archived = map.archivedTopics.first(where: { $0.id == skill.id }) {
                    historicalDetails(archived, map: map)
                } else {
                    if skill.isPaused {
                        Label("Paused · Kept in your map and history", systemImage: "pause.circle")
                            .font(.subheadline).foregroundStyle(LearningMapPalette.building.color)
                    }
                    let competency = competency(for: skill)
                    Text("Why it matters").font(.headline).foregroundStyle(LearningMapPalette.text.color)
                    Text(skill.detail.isEmpty ? "This skill is part of your goal, \(goal?.title ?? "your current goal")." : skill.detail)
                        .font(.subheadline).foregroundStyle(LearningMapPalette.secondary.color)
                    Text("Practice evidence").font(.headline).foregroundStyle(LearningMapPalette.text.color)
                    CompetencyRow(competency: competency, learningPlan: store.adaptiveLearningPlan(for: competency))
                    Text(competency.attempts == 0 ? "No answers are linked to this skill yet." : "This status is based on \(competency.attempts) stored answers.")
                        .font(.footnote).foregroundStyle(LearningMapPalette.secondary.color)
                    Text("Recommended next step").font(.headline).foregroundStyle(LearningMapPalette.text.color)
                    Text(nextFocus?.skillID == skill.id ? nextFocus?.detail ?? "Continue with this skill." : "Practice this skill to add evidence for its focus points.")
                        .font(.subheadline).foregroundStyle(LearningMapPalette.secondary.color)
                    if !skill.isPaused, onPractice != nil {
                        previewAction("Practice this skill", symbol: "play.fill", prominent: true) { onPractice?(skill.id) }
                            .accessibilityIdentifier("learning-map-details-practice")
                    } else if skill.isPaused {
                        Text("Practice is unavailable while this skill is paused.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(LearningMapPalette.building.color)
                    }
                    Text("Practice: \(skill.practiceEmphasis.label) · Challenge: \(skill.challenge.label)")
                        .font(.footnote).foregroundStyle(LearningMapPalette.secondary.color)
                    if !skill.objectives.isEmpty {
                        Text("Focus points").font(.headline).foregroundStyle(LearningMapPalette.text.color)
                        ForEach(skill.objectives) { objective in
                            listNode(.objective(skillID: skill.id, objectiveID: objective.id), map: map)
                        }
                    } else {
                        Text("Add focus points to describe the smaller ideas you want to practice within this skill.")
                            .font(.subheadline).foregroundStyle(LearningMapPalette.secondary.color)
                    }
                    let ancestors = LearningMapGraphLayout.ancestors(of: skill.id, in: map)
                    if !ancestors.isEmpty {
                        Text("Grew from").font(.headline).foregroundStyle(LearningMapPalette.text.color)
                        ForEach(ancestors) { listNode(.history($0.id), map: map) }
                    }
                    if onEdit != nil { editButton(title: "Edit this skill", skillID: skill.id) }
                }
            }
        }
    }

    private func historicalDetails(_ archived: ArchivedSkillMapTopic, map: GoalSkillMap) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(historyLabel(archived), systemImage: archived.reason == .mastered ? "checkmark.seal.fill" : "clock.arrow.circlepath")
                .font(.headline).foregroundStyle(LearningMapPalette.building.color)
            Text(archived.archivedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.footnote).foregroundStyle(LearningMapPalette.secondary.color)
            if let mastery = archived.mastery {
                Text("\(mastery.masteryPercent)% estimate from \(mastery.attempts) answers when this branch was archived.")
                    .font(.subheadline).foregroundStyle(LearningMapPalette.secondary.color)
            }
            Text(archived.reason == .mastered
                 ? "This earned milestone stays in your history as you work on the next challenge."
                 : "Your previous work is preserved. This branch was changed by you; it is not an earned mastery milestone.")
                .font(.subheadline).foregroundStyle(LearningMapPalette.secondary.color)
            if !archived.topic.detail.isEmpty {
                Text(archived.topic.detail).font(.subheadline).foregroundStyle(LearningMapPalette.secondary.color)
            }
            if !archived.topic.objectives.isEmpty {
                Text("Earlier focus points").font(.headline).foregroundStyle(LearningMapPalette.text.color)
                ForEach(archived.topic.objectives) { objective in
                    listNode(.objective(skillID: archived.id, objectiveID: objective.id), map: map)
                }
            }
            let successorIDs = Set(archived.successorSkillIDs + (map.topics + map.archivedTopics.map(\.topic)).filter {
                $0.predecessorIDs.contains(archived.id)
            }.map(\.id))
            ForEach(map.topics.filter { successorIDs.contains($0.id) }) { listNode(.skill($0.id), map: map) }
            ForEach(map.archivedTopics.filter { successorIDs.contains($0.id) && $0.id != archived.id }) {
                listNode(.history($0.id), map: map)
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("A map of what you're becoming").font(CheckpointTypography.sectionTitle).foregroundStyle(LearningMapPalette.text.color)
            legendRow("scope", "Goal → skills → focus points", "Solid lines show what belongs to your goal and each skill. Tap a skill to unfold its focus points.", LearningMapPalette.accent.color)
            legendRow("arrow.triangle.branch", "Earlier → later branches", "Dashed amber lines show advancement or a replacement you chose. Historical details explain which happened.", LearningMapPalette.building.color)
            ForEach([CompetencyProgressBand.notStarted, .calibrating, .needsPractice, .building, .strong], id: \.label) { band in
                legendRow(band.systemImage, band.label, bandDescription(band), band.tint)
            }
            Text("Drag to move around. Pinch or use + and − to zoom. Fit map brings the current branch back into view. The goal title returns to all skills. List offers the same details in reading order.")
                .font(.subheadline).foregroundStyle(LearningMapPalette.secondary.color)
        }
    }

    private func legendRow(_ symbol: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 25)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(LearningMapPalette.text.color)
                Text(detail).font(.subheadline).foregroundStyle(LearningMapPalette.secondary.color)
            }
        }
    }

    @ViewBuilder
    private var suggestionReview: some View {
        if let map = suggestionMap, let suggestion = map.pendingEvolutionSuggestion {
            Text("Ready for a new branch?").font(CheckpointTypography.sectionTitle).foregroundStyle(LearningMapPalette.text.color)
            Text("Review these next steps. Accepting keeps the earlier skills as earned milestones and begins progress on the new branches.")
                .foregroundStyle(LearningMapPalette.secondary.color)
            ForEach(suggestion.replacements, id: \.predecessorSkillID) { replacement in
                if let previous = map.topics.first(where: { $0.id == replacement.predecessorSkillID }),
                   let next = suggestion.topics.first(where: { $0.id == replacement.successorSkillID }) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(previous.name, systemImage: "checkmark.seal")
                        Label(next.name, systemImage: "arrow.down.right")
                            .font(.headline)
                        ForEach(next.objectives) { Text("· \($0.name)").font(.subheadline) }
                    }
                    .foregroundStyle(LearningMapPalette.accent.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(LearningMapPalette.panel.color, in: RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius))
                }
            }
            if let suggestionError { Text(suggestionError).font(.footnote).foregroundStyle(CheckpointTheme.coral) }
            let acceptanceIssue = store.learningMapSuggestionAcceptanceIssue(goalID: goalID, expectedMap: map)
            if let acceptanceIssue {
                Text(acceptanceIssue.message).font(.footnote).foregroundStyle(LearningMapPalette.secondary.color)
            }
            if store.isMember {
                PrimaryActionButton(title: "Accept new branches", systemImage: "arrow.triangle.branch") {
                    if store.acceptLearningMapSuggestion(goalID: goalID, expectedMap: map) {
                        modal = nil
                        select(.goal)
                    } else {
                        suggestionError = store.learningMapSuggestionAcceptanceIssue(goalID: goalID, expectedMap: map)?.message
                            ?? "Your changes couldn't be saved. Please try again."
                    }
                }
                .disabled(acceptanceIssue != nil)
            } else {
                Text("Accepting adaptive growth requires Checkpoint Pro. Your existing skills and history remain available.")
                    .font(.footnote).foregroundStyle(LearningMapPalette.secondary.color)
            }
            Button("Keep my current skills") {
                if store.dismissLearningMapSuggestion(goalID: goalID, expectedMap: map) { modal = nil }
                else { suggestionError = "The map changed. Close this view and try again." }
            }
            .frame(minHeight: 44)
            .tint(LearningMapPalette.accent.color)
        } else {
            ContentUnavailableView("No pending suggestions", systemImage: "checkmark.circle")
        }
    }

    private func editButton(title: String, skillID: SkillMapTopic.ID?) -> some View {
        SecondaryActionButton(title: title, systemImage: "slider.horizontal.3") {
            pendingEditSkillID = skillID
            hasPendingEdit = true
            modal = nil
        }
    }

    private func finishModalDismissal() {
        suggestionMap = nil
        guard hasPendingEdit else { return }
        hasPendingEdit = false
        let target = pendingEditSkillID
        pendingEditSkillID = nil
        onEdit?(target)
    }

    private var selectedTopic: SkillMapTopic? {
        guard let map, let id = selected.skillID else { return nil }
        return map.topics.first { $0.id == id } ?? map.archivedTopics.first { $0.id == id }?.topic
    }
    private var selectedIsObjective: Bool {
        if case .objective = selected { return true }; return false
    }
    private var selectedIsArchived: Bool {
        guard let id = selected.skillID else { return false }
        return map?.archivedTopics.contains { $0.id == id } == true
    }
    private var editableSelectedSkillID: SkillMapTopic.ID? {
        selectedIsArchived ? nil : selected.skillID
    }

    private func competency(for topic: SkillMapTopic) -> TopicCompetency {
        activeCompetencies.first { $0.skillID == topic.id }
            ?? TopicCompetency.initial(topic: topic.name, goalID: goalID, skillID: topic.id)
    }

    private func objectiveEvidence(skillID: SkillMapTopic.ID, objectiveID: SkillMapObjective.ID) -> LearningMapObjectiveEvidence {
        LearningMapObjectiveEvidence(goalID: goalID, skillID: skillID, objectiveID: objectiveID,
                                     attempts: store.attempts, excludedQuestionIDs: excludedQuestions)
    }

    private struct NodeVisual {
        var title: String
        var subtitle: String?
        var symbol: String?
        var tint: Color
        var diameter: CGFloat
        var width: CGFloat
        var height: CGFloat
        var progress: Double
        var showsTitle = true
        var evidenceAvailable = false

        var frame: CGRect {
            CGRect(x: -width / 2, y: -diameter / 2, width: width, height: height)
        }
    }

    private func nodeVisual(_ id: LearningMapNodeID, map: GoalSkillMap) -> NodeVisual {
        var visual = nodeContent(id, map: map)
        let geometry = LearningMapNodeGeometry(id: id, compact: compactNodes, focused: selected != .goal, isSelected: selected == id)
        visual.width = geometry.width
        visual.height = geometry.height
        visual.diameter = geometry.diameter
        visual.showsTitle = geometry.showsTitle
        if id == .goal { visual.subtitle = nil }
        return visual
    }

    private func nodeContent(_ id: LearningMapNodeID, map: GoalSkillMap) -> NodeVisual {
        switch id {
        case .goal:
            if compactNodes && selected != .goal {
                return NodeVisual(title: goal?.title ?? "Your goal", subtitle: nil, symbol: "scope", tint: LearningMapPalette.accent.color,
                                  diameter: 52, width: 56, height: 56, progress: 0, showsTitle: false)
            }
            if compactNodes || selected != .goal {
                return NodeVisual(title: goal?.title ?? "Your goal", subtitle: nil, symbol: "scope", tint: LearningMapPalette.accent.color,
                                  diameter: 52, width: 92, height: 92, progress: 0)
            }
            return NodeVisual(title: goal?.title ?? "Your goal", subtitle: "YOUR GOAL", symbol: "scope", tint: LearningMapPalette.accent.color,
                              diameter: 72, width: 144, height: 140, progress: 0)
        case let .skill(skillID):
            guard let skill = map.topics.first(where: { $0.id == skillID }) else { return missingNode }
            let competency = competency(for: skill)
            let band = CompetencyProgressBand.resolve(for: competency)
            return NodeVisual(title: skill.name, subtitle: skill.isPaused ? "Paused" : nextFocus?.skillID == skill.id ? "Next focus" : band.label,
                              symbol: skill.isPaused ? "pause" : band.systemImage,
                              tint: skill.isPaused ? LearningMapPalette.secondary.color : progressTint(for: band), diameter: compactNodes ? 36 : 46, width: 110, height: compactNodes ? 94 : 112,
                              progress: band == .calibrating ? Double(competency.attempts) / 10 : Double(competency.masteryPercent) / 100)
        case let .objective(skillID, objectiveID):
            let topic = map.topics.first { $0.id == skillID } ?? map.archivedTopics.first { $0.id == skillID }?.topic
            let evidence = objectiveEvidence(skillID: skillID, objectiveID: objectiveID)
            return NodeVisual(title: topic?.objectives.first { $0.id == objectiveID }?.name ?? "Focus point", subtitle: nil,
                              symbol: nil, tint: LearningMapPalette.accent.color, diameter: 18, width: compactNodes ? 88 : 108, height: 64,
                              progress: 0, evidenceAvailable: evidence.answerCount > 0)
        case let .history(skillID):
            guard let archived = map.archivedTopics.first(where: { $0.id == skillID }) else { return missingNode }
            return NodeVisual(title: archived.topic.name, subtitle: historyLabel(archived),
                              symbol: archived.reason == .mastered ? "checkmark.seal" : "clock.arrow.circlepath",
                              tint: LearningMapPalette.building.color, diameter: 38, width: 112, height: 104, progress: 0)
        }
    }

    private var missingNode: NodeVisual {
        NodeVisual(title: "Unavailable", subtitle: nil, symbol: "questionmark", tint: LearningMapPalette.secondary.color,
                   diameter: 44, width: 110, height: 112, progress: 0)
    }

    private func labelOffset(for id: LearningMapNodeID) -> CGFloat {
        guard let map else { return 0 }
        let visual = nodeVisual(id, map: map)
        return (visual.height - visual.diameter) / 2
    }

    private func progressTint(for band: CompetencyProgressBand) -> Color {
        switch band {
        case .strong: LearningMapPalette.strong.color
        case .building: LearningMapPalette.building.color
        case .notStarted, .calibrating, .needsPractice: LearningMapPalette.information.color
        }
    }

    private func selectionContext(for id: LearningMapNodeID, map: GoalSkillMap) -> String {
        guard case let .skill(skillID) = id,
              let skill = map.topics.first(where: { $0.id == skillID }) else {
            return accessibilityValue(for: id, map: map)
        }
        let evidence = competency(for: skill)
        return evidence.attempts == 0
            ? "\(skill.isPaused ? "Paused. " : "")No practice evidence yet."
            : "\(CompetencyProgressBand.resolve(for: evidence).label) from \(evidence.attempts) stored answers."
    }

    private func accessibilityValue(for id: LearningMapNodeID, map: GoalSkillMap) -> String {
        switch id {
        case .goal: return "\(map.topics.count) skills · \(map.topics.reduce(0) { $0 + $1.objectives.count }) focus points"
        case let .skill(skillID):
            if let skill = map.topics.first(where: { $0.id == skillID }) {
                let competency = competency(for: skill)
                let band = CompetencyProgressBand.resolve(for: competency)
                return "\(skill.isPaused ? "Paused · " : "")\(band.label) · \(competency.attempts) answers · \(skill.objectives.count) focus points"
            }
            return "Skill unavailable"
        case let .objective(skillID, objectiveID):
            return objectiveEvidence(skillID: skillID, objectiveID: objectiveID).summary
        case let .history(skillID):
            return map.archivedTopics.first(where: { $0.id == skillID }).map(historyLabel) ?? "Previous skill"
        }
    }

    private func historyLabel(_ archived: ArchivedSkillMapTopic) -> String {
        switch archived.reason {
        case .mastered: "Earned milestone"
        case .userRemoved: "Removed by you"
        case .userReplaced: "Replaced by you"
        }
    }

    private func bandDescription(_ band: CompetencyProgressBand) -> String {
        switch band {
        case .notStarted: "Ready for its first answer."
        case .calibrating: "The first 10 answers establish a more reliable skill estimate."
        case .needsPractice: "Enough evidence to show where another pass could help."
        case .building: "Your current skill estimate is developing."
        case .strong: "A strong current estimate. Earned advancement requires additional evidence."
        }
    }

    private func select(_ requested: LearningMapNodeID) {
        guard let map else { return }
        let resolved = LearningMapGraphLayout.resolvedSelection(requested, in: map)
        withAnimation(motion) {
            selected = resolved
            if case .history = resolved { showsHistory = true }
            else { showsHistory = false }
            if case .objective = resolved { focusCamera(on: resolved) }
            else { fitMap() }
        }
    }

    private func resetSelection() {
        selected = initialSkillID.map(LearningMapNodeID.skill) ?? .goal
        showsHistory = false
        modal = nil
        gestureCamera = nil
        fitMap()
    }

    private func updateViewport(_ size: CGSize) {
        guard size != viewport else { return }
        let shouldKeepFocus = selectedIsObjective && hasCustomCamera
        viewport = size
        if shouldKeepFocus { focusCamera(on: selected) }
        else { fitMap() }
    }

    private func nodeFrames(_ layout: LearningMapGraphLayout) -> [LearningMapNodeID: CGRect] {
        Dictionary(uniqueKeysWithValues: layout.nodes.map {
            ($0.id, LearningMapNodeGeometry(id: $0.id, compact: compactNodes, focused: selected != .goal, isSelected: selected == $0.id).hitBounds)
        })
    }

    private func fitMap() {
        guard let graph, viewport.width > 0, viewport.height > 0 else { return }
        camera = .fitted(nodes: graph.nodes, frames: nodeFrames(graph), viewport: viewport)
        gestureCamera = nil
    }

    private func focusCamera(on id: LearningMapNodeID) {
        guard let graph, let node = graph.nodes.first(where: { $0.id == id }), let frame = nodeFrames(graph)[id] else { return }
        withAnimation(motion) { camera = camera.focused(on: node, frame: frame, viewport: viewport, minimumZoom: 1.05) }
        gestureCamera = nil
    }

    private func zoom(by amount: CGFloat) {
        withAnimation(motion) {
            camera = camera.magnified(by: amount, anchor: CGPoint(x: viewport.width / 2, y: viewport.height / 2), viewport: viewport)
        }
    }

    private func explorationGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .simultaneously(with: MagnifyGesture(minimumScaleDelta: 0.015))
            .onChanged { value in
                if gestureCamera == nil { gestureCamera = camera }
                guard let baseline = gestureCamera else { return }
                var next = baseline
                if let drag = value.first { next = next.panned(by: drag.translation) }
                if let magnify = value.second {
                    next = next.magnified(by: magnify.magnification,
                        anchor: CGPoint(x: magnify.startAnchor.x * size.width, y: magnify.startAnchor.y * size.height), viewport: size)
                }
                camera = next
            }
            .onEnded { _ in gestureCamera = nil }
    }

}

private struct LearningMapNodeHitShape: Shape {
    let geometry: LearningMapNodeGeometry

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for region in geometry.hitRegions {
            path.addRect(region.offsetBy(dx: rect.midX, dy: geometry.diameter / 2))
        }
        return path
    }
}
