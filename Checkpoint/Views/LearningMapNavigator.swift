import SwiftUI

/// A small, truthful overview of the current branch anchors exploration at closer zoom levels.
struct LearningMapNavigator: View {
    let layout: LearningMapGraphLayout
    let camera: LearningMapCamera
    let viewport: CGSize
    let selection: LearningMapNodeID
    let onRecenter: (CGPoint) -> Void
    let onFit: () -> Void

    private let size = CGSize(width: 88, height: 64)
    private var overview: LearningMapCamera {
        let bounds = layout.bounds.insetBy(dx: -70, dy: -70)
        return LearningMapCamera(center: CGPoint(x: bounds.midX, y: bounds.midY),
                                 zoom: min((size.width - 16) / max(1, bounds.width), (size.height - 16) / max(1, bounds.height)))
    }

    var body: some View {
        Canvas { context, _ in
            let positions = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, overview.project($0.position, viewport: size)) })
            for edge in layout.edges {
                guard let start = positions[edge.from], let end = positions[edge.to] else { continue }
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(LearningMapPalette.iris.color.opacity(0.3)), lineWidth: 0.7)
            }
            let bounds = camera.visibleWorldBounds(viewport: viewport)
            if !bounds.isNull {
                let origin = overview.project(bounds.origin, viewport: size)
                let frame = CGRect(origin: origin, size: CGSize(width: bounds.width * overview.zoom, height: bounds.height * overview.zoom))
                let path = Path(roundedRect: frame, cornerRadius: 3)
                context.fill(path, with: .color(LearningMapPalette.iris.color.opacity(0.09)))
                context.stroke(path, with: .color(LearningMapPalette.iris.color.opacity(0.7)), lineWidth: 1)
            }
            for node in layout.nodes {
                guard let point = positions[node.id] else { continue }
                let radius: CGFloat = node.id == selection ? 3.2 : node.id == .goal ? 2.5 : 1.8
                let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.fill(circle, with: .color(LearningMapPalette.iris.color.opacity(node.id == selection ? 1 : 0.55)))
            }
        }
        .frame(width: size.width, height: size.height)
        .background(LearningMapPalette.panel.color.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(LearningMapPalette.border.color.opacity(0.7), lineWidth: 1))
        .shadow(color: CheckpointTheme.shadowElevated, radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { point in onRecenter(overview.unproject(point, viewport: size)) }
        .accessibilityElement()
        .accessibilityLabel("Map navigator")
        .accessibilityHint("Shows your position in this branch. Activate to fit the whole branch.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onFit() }
        .accessibilityIdentifier("learning-map-navigator")
    }
}
