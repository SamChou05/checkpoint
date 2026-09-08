import SwiftUI

struct LearningMapView: View {
    let store: CheckpointStore
    let goalID: Goal.ID
    let initialSkillID: SkillMapTopic.ID?
    let onEdit: ((SkillMapTopic.ID?) -> Void)?

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
         onEdit: ((SkillMapTopic.ID?) -> Void)? = nil) {
        self.store = store
        self.goalID = goalID
        self.initialSkillID = initialSkillID
        self.onEdit = onEdit
        _selected = State(initialValue: initialSkillID.map(LearningMapNodeID.skill) ?? .goal)
    }

    private var goal: Goal? {
        store.goal?.id == goalID ? store.goal : store.goalProfiles.first { $0.id == goalID }
    }

    private var map: GoalSkillMap? { goal?.derivedSkillMap }
    private var effectiveMode: PresentationMode {
        mode ?? ((voiceOverEnabled || switchControlEnabled || dynamicTypeSize >= .xxLarge) ? .list : .map)
    }
    private var motion: Animation? {
        reduceMotion || voiceOverEnabled || switchControlEnabled ? nil : .spring(response: 0.48, dampingFraction: 0.86)
    }
    private var compactWindow: Bool {
        (availableHeight > 0 && availableHeight < 620) || (viewport.width > 0 && viewport.width < 350)
    }
    private var compactNodes: Bool { compactWindow || viewport.height < (selected == .goal ? 420 : 480) }
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
                .background(CheckpointPalette.backgroundBase.color)
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
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityLabel(selected == .goal ? "Edit learning map" : "Edit selected skill")
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
                .background(CheckpointPalette.backgroundBase.color)
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
        .onChange(of: compactNodes) { _, _ in fitMap() }
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
            if dynamicTypeSize.isAccessibilitySize {
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
                    .foregroundStyle(CheckpointTheme.teal)
                    .padding(12)
                    .frame(minHeight: 44)
                    .background(CheckpointTheme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            } else if map.status == .suggested {
                Text("Suggested map · Review and make it yours with Edit")
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(CheckpointPalette.backgroundBase.color)
    }

    private func goalButton(_ goal: Goal) -> some View {
        Button { select(.goal) } label: {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "scope").padding(.top, 2)
                Text(goal.title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
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
                        .foregroundStyle(CheckpointTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "list.bullet").font(.subheadline)
            }
            .foregroundStyle(CheckpointTheme.teal)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }

    private func mapCanvas(map: GoalSkillMap) -> some View {
        GeometryReader { proxy in
            let layout = LearningMapGraphLayout(map: map, selected: selected, showsHistory: showsHistory, compact: compactNodes)
            let canvasSize = CGSize(width: proxy.size.width, height: max(100, proxy.size.height - 58))
            ZStack(alignment: .bottom) {
                ZStack {
                    RadialGradient(colors: [CheckpointTheme.teal.opacity(0.09), .clear], center: .center,
                                   startRadius: 10, endRadius: max(canvasSize.width, canvasSize.height) * 0.6)
                    dotGrid
                    connections(layout: layout, viewport: canvasSize)
                    ForEach(layout.nodes) { node in
                        let point = camera.project(node.position, viewport: canvasSize)
                        mapNode(node.id, map: map)
                            .position(x: point.x, y: point.y + labelOffset(for: node.id))
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .contentShape(Rectangle())
                .clipped()
                .gesture(explorationGesture(size: canvasSize))
                .frame(maxHeight: .infinity, alignment: .top)

                canvasControls(map: map)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 7)
            }
            .onAppear { updateViewport(canvasSize) }
            .onChange(of: canvasSize) { _, size in updateViewport(size) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(showsHistory ? "Historical skill connections" : "Interactive learning map")
        }
        .animation(motion, value: map)
    }

    private var dotGrid: some View {
        Canvas { context, size in
            for x in stride(from: CGFloat(12), to: size.width, by: 24) {
                for y in stride(from: CGFloat(12), to: size.height, by: 24) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)),
                                 with: .color(CheckpointTheme.muted.opacity(0.15)))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func connections(layout: LearningMapGraphLayout, viewport: CGSize) -> some View {
        let positions = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.position) })
        return ZStack {
            ForEach(layout.edges) { edge in
                if let from = positions[edge.from], let to = positions[edge.to] {
                    let start = camera.project(from, viewport: viewport)
                    let end = camera.project(to, viewport: viewport)
                    let highlighted = selected == .goal || edge.to == selected || edge.to.skillID == selected.skillID
                    LearningMapConnection(start: start, end: end)
                        .stroke(edge.relationship == .progression ? CheckpointTheme.amber : CheckpointTheme.teal,
                                style: StrokeStyle(lineWidth: highlighted ? 1.7 : 1.1,
                                                   lineCap: .round, dash: edge.relationship == .progression ? [5, 6] : []))
                        .opacity(highlighted ? 0.58 : 0.24)
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
                ZStack {
                    Circle().fill(CheckpointTheme.panel)
                    Circle().fill(visual.tint.opacity(id == .goal ? 0.15 : 0.07))
                    Circle().stroke(visual.tint.opacity(isSelected ? 0.8 : 0.4), lineWidth: 1)
                    if visual.progress > 0 {
                        Circle().trim(from: 0, to: visual.progress)
                            .stroke(visual.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    if let symbol = visual.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: id == .goal ? 26 : 18, weight: .semibold))
                            .foregroundStyle(visual.tint)
                    } else {
                        Circle().fill(visual.tint.opacity(visual.evidenceAvailable ? 0.9 : 0.35)).padding(5)
                    }
                }
                .frame(width: visual.diameter, height: visual.diameter)
                .shadow(color: CheckpointTheme.shadowElevated, radius: isSelected ? 14 : 7, y: 4)
                .overlay {
                    Circle().stroke(visual.tint.opacity(isSelected ? 0.40 : 0.15), lineWidth: 1)
                        .padding(isSelected ? -8 : -5)
                }
                if visual.showsTitle {
                Text(id == .goal ? "Your goal" : visual.title)
                    .font(id == .goal ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
                    .background(CheckpointPalette.backgroundBase.color.opacity(0.88), in: RoundedRectangle(cornerRadius: 5))
                }
                if let subtitle = visual.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(visual.tint)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(CheckpointPalette.backgroundBase.color.opacity(0.92), in: Capsule())
                }
            }
            .frame(width: visual.width, height: visual.height, alignment: .top)
            .contentShape(LearningMapNodeHitShape(geometry: LearningMapNodeGeometry(id: id, compact: compactNodes, focused: selected != .goal)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(visual.title)
        .accessibilityValue(accessibilityValue(for: id, map: map))
        .accessibilityHint(isSelected ? "Opens details and evidence." : "Explores this branch. Tap again for details.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("learning-map-node-\(id)")
        .dynamicTypeSize(.small ... .large)
    }

    private func canvasControls(map: GoalSkillMap) -> some View {
        HStack(spacing: 2) {
            Button { modal = .legend } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                .accessibilityLabel("How to read this map")
            if !map.archivedTopics.isEmpty {
                Button {
                    withAnimation(motion) {
                        if !showsHistory, case let .objective(skillID, _) = selected {
                            selected = map.topics.contains(where: { $0.id == skillID }) ? .skill(skillID) : .history(skillID)
                        }
                        showsHistory.toggle()
                        fitMap()
                    }
                } label: {
                    Image(systemName: showsHistory ? "clock.fill" : "clock").frame(width: 44, height: 44)
                }
                .accessibilityLabel(showsHistory ? "Hide historical branches" : "Show historical branches")
                .accessibilityAddTraits(showsHistory ? .isSelected : [])
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button { zoom(by: 0.8) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Zoom out")
                Button { withAnimation(motion) { fitMap() } } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Fit map to view")
                Button { zoom(by: 1.25) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Zoom in")
            }
            .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(CheckpointTheme.hairline.opacity(0.6), lineWidth: 1))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(CheckpointTheme.teal)
        .buttonStyle(.plain)
    }

    private func compactSelectionPreview(map: GoalSkillMap) -> some View {
        let visual = nodeVisual(selected, map: map)
        return HStack(spacing: 12) {
            if selected != .goal {
                Button { select(.goal) } label: {
                    Image(systemName: "arrow.turn.up.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Return to all skills")
            }
            Button { modal = .details } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected == .goal ? (showsHistory ? "Earlier branches, kept for you" : "\(map.topics.count) skills · Your learning journey") : visual.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(CheckpointTheme.text)
                        Text(selected == .goal ? (showsHistory ? "Select an earlier skill to see its story" : "Tap to unfold · Drag or pinch to explore") : accessibilityValue(for: selected, map: map))
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(CheckpointTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").frame(width: 32, height: 44)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityHint("Opens learning details and evidence.")
        }
        .buttonStyle(.plain)
        .foregroundStyle(CheckpointTheme.teal)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(CheckpointTheme.panel)
        .overlay(alignment: .top) { Rectangle().fill(CheckpointTheme.hairline.opacity(0.5)).frame(height: 1) }
    }

    private func selectionPreview(map: GoalSkillMap) -> some View {
        let visual = nodeVisual(selected, map: map)
        return VStack(alignment: .leading, spacing: 9) {
            Button { modal = .details } label: {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selected == .goal ? "YOUR LEARNING JOURNEY" : selectedIsObjective ? "FOCUS POINT" : selectedIsArchived ? "HISTORY" : "SELECTED SKILL")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(CheckpointTheme.muted)
                        Text(selected == .goal ? (showsHistory ? "Earlier branches, kept for you" : "\(map.topics.count) skills. Room to grow.") : visual.title)
                            .font(.headline)
                            .foregroundStyle(CheckpointTheme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(selected == .goal ? (showsHistory ? "Select a branch to follow its story. Your full history is always available in List." : "Tap a skill to unfold its focus points. Drag or pinch to explore.") : accessibilityValue(for: selected, map: map))
                            .font(.caption)
                            .foregroundStyle(CheckpointTheme.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.teal)
                        .frame(width: 44, height: 44)
                        .background(CheckpointTheme.teal.opacity(0.08), in: Circle())
                }
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens learning details and evidence.")
            if selected == .goal, !showsHistory, let nextFocus, let skillID = nextFocus.skillID,
               map.topics.contains(where: { $0.id == skillID }) {
                Button { select(.skill(skillID)) } label: {
                    Label("Next: \(nextFocus.skillName)", systemImage: "scope")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CheckpointTheme.teal)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            } else if selected != .goal {
                Button { select(.goal) } label: {
                    Label("All skills", systemImage: "arrow.turn.up.left")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CheckpointTheme.teal)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(CheckpointTheme.panel)
        .overlay(alignment: .top) { Rectangle().fill(CheckpointTheme.hairline.opacity(0.5)).frame(height: 1) }
    }

    private func listContents(map: GoalSkillMap) -> some View {
        ScrollViewReader { reader in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("\(map.topics.count) skills · \(map.topics.reduce(0) { $0 + $1.objectives.count }) focus points")
                    .font(.footnote).foregroundStyle(CheckpointTheme.muted)
                ForEach(map.topics) { skill in
                    VStack(alignment: .leading, spacing: 4) {
                        listNode(.skill(skill.id), map: map)
                        ForEach(skill.objectives) { objective in
                            if dynamicTypeSize.isAccessibilitySize {
                                Divider().padding(.vertical, 6)
                                listNode(.objective(skillID: skill.id, objectiveID: objective.id), map: map)
                            } else {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "arrow.turn.down.right").foregroundStyle(CheckpointTheme.hairline).padding(.top, 16)
                                listNode(.objective(skillID: skill.id, objectiveID: objective.id), map: map)
                            }
                            .padding(.leading, 13)
                            }
                        }
                    }
                    .padding(15)
                    .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                }
                if !map.archivedTopics.isEmpty {
                    Text("Your earlier branches").font(.headline).foregroundStyle(CheckpointTheme.text)
                        .id("learning-map-history")
                    Text("Earned milestones and previous choices stay part of your story.")
                        .font(.footnote).foregroundStyle(CheckpointTheme.muted)
                    ForEach(map.archivedTopics) { archived in
                        listNode(.history(archived.id), map: map)
                            .padding(15)
                            .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 18))
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
                    Text(visual.title).font(.subheadline.weight(.semibold)).foregroundStyle(CheckpointTheme.text)
                    Text(accessibilityValue(for: id, map: map)).font(.caption).foregroundStyle(CheckpointTheme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(CheckpointTheme.muted)
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
            Text(visual.title).font(.title2.bold()).foregroundStyle(CheckpointTheme.text).fixedSize(horizontal: false, vertical: true)
            if selected == .goal {
                let practiced = activeCompetencies.filter { $0.attempts > 0 }.count
                Text("\(practiced) of \(map.topics.count) skills practiced · \(map.archivedTopics.filter { $0.reason == .mastered }.count) earned milestones")
                    .font(.subheadline).foregroundStyle(CheckpointTheme.teal)
                Text("Your goal connects to each skill. Smaller branches are the focus points that make that skill concrete. Your answers strengthen the skill's progress signal.")
                    .font(.body).foregroundStyle(CheckpointTheme.muted)
                if let nextFocus {
                    Text("Next focus").font(.headline).foregroundStyle(CheckpointTheme.text)
                    Text(nextFocus.detail).font(.subheadline).foregroundStyle(CheckpointTheme.muted)
                    if let id = nextFocus.skillID { Button(nextFocus.skillName) { select(.skill(id)) } }
                }
                if onEdit != nil { editButton(title: "Edit learning map", skillID: nil) }
            } else if let skill = selectedTopic {
                if case let .objective(_, objectiveID) = selected,
                   let objective = skill.objectives.first(where: { $0.id == objectiveID }) {
                    let evidence = objectiveEvidence(skillID: skill.id, objectiveID: objective.id)
                    Text("Part of \(skill.name)").font(.subheadline.weight(.medium)).foregroundStyle(CheckpointTheme.teal)
                    if !objective.detail.isEmpty { Text(objective.detail).foregroundStyle(CheckpointTheme.muted) }
                    Text(evidence.summary).font(.headline).foregroundStyle(CheckpointTheme.text)
                    if evidence.answerCount > 0 {
                        Text("\(evidence.correctCount) correct · \(evidence.partialCount) partial · \(evidence.answerCount - evidence.correctCount - evidence.partialCount) other answers")
                            .font(.subheadline).foregroundStyle(CheckpointTheme.muted)
                    }
                    Text("Focus points show answers linked directly to this idea. They do not inherit the parent skill's mastery estimate.")
                        .font(.footnote).foregroundStyle(CheckpointTheme.muted)
                    if let date = evidence.lastPracticedAt {
                        Text("Last practiced \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.footnote).foregroundStyle(CheckpointTheme.muted)
                    }
                    if onEdit != nil, !selectedIsArchived { editButton(title: "Edit focus points", skillID: skill.id) }
                } else if let archived = map.archivedTopics.first(where: { $0.id == skill.id }) {
                    historicalDetails(archived, map: map)
                } else {
                    if !skill.detail.isEmpty { Text(skill.detail).foregroundStyle(CheckpointTheme.muted) }
                    if skill.isPaused {
                        Label("Paused · Kept in your map and history", systemImage: "pause.circle")
                            .font(.subheadline).foregroundStyle(CheckpointTheme.amber)
                    }
                    let competency = competency(for: skill)
                    CompetencyRow(competency: competency, learningPlan: store.adaptiveLearningPlan(for: competency))
                    Text("Practice: \(skill.practiceEmphasis.label) · Challenge: \(skill.challenge.label)")
                        .font(.footnote).foregroundStyle(CheckpointTheme.muted)
                    if !skill.objectives.isEmpty {
                        Text("Focus points").font(.headline).foregroundStyle(CheckpointTheme.text)
                        ForEach(skill.objectives) { objective in
                            listNode(.objective(skillID: skill.id, objectiveID: objective.id), map: map)
                        }
                    } else {
                        Text("Add focus points to describe the smaller ideas you want to practice within this skill.")
                            .font(.subheadline).foregroundStyle(CheckpointTheme.muted)
                    }
                    let ancestors = LearningMapGraphLayout.ancestors(of: skill.id, in: map)
                    if !ancestors.isEmpty {
                        Text("Grew from").font(.headline).foregroundStyle(CheckpointTheme.text)
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
                .font(.headline).foregroundStyle(CheckpointTheme.amber)
            Text(archived.archivedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.footnote).foregroundStyle(CheckpointTheme.muted)
            if let mastery = archived.mastery {
                Text("\(mastery.masteryPercent)% estimate from \(mastery.attempts) answers when this branch was archived.")
                    .font(.subheadline).foregroundStyle(CheckpointTheme.muted)
            }
            Text(archived.reason == .mastered
                 ? "This earned milestone stays in your history as you work on the next challenge."
                 : "Your previous work is preserved. This branch was changed by you; it is not an earned mastery milestone.")
                .font(.subheadline).foregroundStyle(CheckpointTheme.muted)
            if !archived.topic.detail.isEmpty {
                Text(archived.topic.detail).font(.subheadline).foregroundStyle(CheckpointTheme.muted)
            }
            if !archived.topic.objectives.isEmpty {
                Text("Earlier focus points").font(.headline).foregroundStyle(CheckpointTheme.text)
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
            Text("A map of what you're becoming").font(.title2.bold()).foregroundStyle(CheckpointTheme.text)
            legendRow("scope", "Goal → skills → focus points", "Solid lines show what belongs to your goal and each skill. Tap a skill to unfold its focus points.", CheckpointTheme.teal)
            legendRow("arrow.triangle.branch", "Earlier → later branches", "Dashed amber lines show advancement or a replacement you chose. Historical details explain which happened.", CheckpointTheme.amber)
            ForEach([CompetencyProgressBand.notStarted, .calibrating, .needsPractice, .building, .strong], id: \.label) { band in
                legendRow(band.systemImage, band.label, bandDescription(band), band.tint)
            }
            Text("Drag to move around. Pinch or use + and − to zoom. Fit map brings the current branch back into view. The goal title returns to all skills. List offers the same details in reading order.")
                .font(.subheadline).foregroundStyle(CheckpointTheme.muted)
        }
    }

    private func legendRow(_ symbol: String, _ title: String, _ detail: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 25)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(CheckpointTheme.text)
                Text(detail).font(.subheadline).foregroundStyle(CheckpointTheme.muted)
            }
        }
    }

    @ViewBuilder
    private var suggestionReview: some View {
        if let map = suggestionMap, let suggestion = map.pendingEvolutionSuggestion {
            Text("Ready for a new branch?").font(.title2.bold()).foregroundStyle(CheckpointTheme.text)
            Text("Review these next steps. Accepting keeps the earlier skills as earned milestones and begins progress on the new branches.")
                .foregroundStyle(CheckpointTheme.muted)
            ForEach(suggestion.replacements, id: \.predecessorSkillID) { replacement in
                if let previous = map.topics.first(where: { $0.id == replacement.predecessorSkillID }),
                   let next = suggestion.topics.first(where: { $0.id == replacement.successorSkillID }) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(previous.name, systemImage: "checkmark.seal")
                        Label(next.name, systemImage: "arrow.down.right")
                            .font(.headline)
                        ForEach(next.objectives) { Text("· \($0.name)").font(.subheadline) }
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(CheckpointTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            if let suggestionError { Text(suggestionError).font(.footnote).foregroundStyle(CheckpointTheme.coral) }
            let acceptanceIssue = store.learningMapSuggestionAcceptanceIssue(goalID: goalID, expectedMap: map)
            if let acceptanceIssue {
                Text(acceptanceIssue.message).font(.footnote).foregroundStyle(CheckpointTheme.muted)
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
                    .font(.footnote).foregroundStyle(CheckpointTheme.muted)
            }
            Button("Keep my current skills") {
                if store.dismissLearningMapSuggestion(goalID: goalID, expectedMap: map) { modal = nil }
                else { suggestionError = "The map changed. Close this view and try again." }
            }
            .frame(minHeight: 44)
            .tint(CheckpointTheme.teal)
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
        let geometry = LearningMapNodeGeometry(id: id, compact: compactNodes, focused: selected != .goal)
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
                return NodeVisual(title: goal?.title ?? "Your goal", subtitle: nil, symbol: "scope", tint: CheckpointTheme.teal,
                                  diameter: 52, width: 56, height: 56, progress: 0, showsTitle: false)
            }
            if compactNodes || selected != .goal {
                return NodeVisual(title: goal?.title ?? "Your goal", subtitle: nil, symbol: "scope", tint: CheckpointTheme.teal,
                                  diameter: 52, width: 92, height: 92, progress: 0)
            }
            return NodeVisual(title: goal?.title ?? "Your goal", subtitle: "YOUR GOAL", symbol: "scope", tint: CheckpointTheme.teal,
                              diameter: 72, width: 144, height: 140, progress: 0)
        case let .skill(skillID):
            guard let skill = map.topics.first(where: { $0.id == skillID }) else { return missingNode }
            let competency = competency(for: skill)
            let band = CompetencyProgressBand.resolve(for: competency)
            return NodeVisual(title: skill.name, subtitle: skill.isPaused ? "Paused" : nextFocus?.skillID == skill.id ? "Next focus" : band.label,
                              symbol: skill.isPaused ? "pause" : band.systemImage,
                              tint: skill.isPaused ? CheckpointTheme.muted : band.tint, diameter: compactNodes ? 36 : 46, width: 110, height: compactNodes ? 94 : 112,
                              progress: band == .calibrating ? Double(competency.attempts) / 10 : Double(competency.masteryPercent) / 100)
        case let .objective(skillID, objectiveID):
            let topic = map.topics.first { $0.id == skillID } ?? map.archivedTopics.first { $0.id == skillID }?.topic
            let evidence = objectiveEvidence(skillID: skillID, objectiveID: objectiveID)
            return NodeVisual(title: topic?.objectives.first { $0.id == objectiveID }?.name ?? "Focus point", subtitle: nil,
                              symbol: nil, tint: CheckpointTheme.teal, diameter: 18, width: compactNodes ? 88 : 108, height: 64,
                              progress: 0, evidenceAvailable: evidence.answerCount > 0)
        case let .history(skillID):
            guard let archived = map.archivedTopics.first(where: { $0.id == skillID }) else { return missingNode }
            return NodeVisual(title: archived.topic.name, subtitle: historyLabel(archived),
                              symbol: archived.reason == .mastered ? "checkmark.seal" : "clock.arrow.circlepath",
                              tint: CheckpointTheme.amber, diameter: 38, width: 112, height: 104, progress: 0)
        }
    }

    private var missingNode: NodeVisual {
        NodeVisual(title: "Unavailable", subtitle: nil, symbol: "questionmark", tint: CheckpointTheme.muted,
                   diameter: 44, width: 110, height: 112, progress: 0)
    }

    private func labelOffset(for id: LearningMapNodeID) -> CGFloat {
        guard let map else { return 0 }
        let visual = nodeVisual(id, map: map)
        return (visual.height - visual.diameter) / 2
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
        let branchChanged = selected.skillID != resolved.skillID || selected == .goal || resolved == .goal
        let previousHistory = showsHistory
        withAnimation(motion) {
            selected = resolved
            if case .history = resolved { showsHistory = true }
            else { showsHistory = false }
            if branchChanged || previousHistory != showsHistory { fitMap() }
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
        viewport = size
        fitMap()
    }

    private func fitMap() {
        guard let graph, viewport.width > 0, viewport.height > 0 else { return }
        let frames = Dictionary(uniqueKeysWithValues: graph.nodes.map {
            ($0.id, LearningMapNodeGeometry(id: $0.id, compact: compactNodes, focused: selected != .goal).hitBounds)
        })
        camera = .fitted(nodes: graph.nodes, frames: frames, viewport: viewport)
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

private struct LearningMapConnection: Shape {
    var start: CGPoint
    var end: CGPoint

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(start.x, start.y), AnimatablePair(end.x, end.y)) }
        set {
            start = CGPoint(x: newValue.first.first, y: newValue.first.second)
            end = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        let dx = end.x - start.x
        let dy = end.y - start.y
        path.addCurve(to: end,
                      control1: CGPoint(x: start.x + dx * 0.12, y: start.y + dy * 0.55),
                      control2: CGPoint(x: end.x - dx * 0.12, y: end.y - dy * 0.4))
        return path
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
