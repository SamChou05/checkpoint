import SwiftUI

private enum LivingMapRenderingDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// A supplied date freezes the schedule while retaining that frame's visual phase.
    var livingMapRenderingDate: Date? {
        get { self[LivingMapRenderingDateKey.self] }
        set { self[LivingMapRenderingDateKey.self] = newValue }
    }
}

/// Decorative map surfaces keep their geometry fixed; the parent owns navigation and accessibility.
struct LivingMapBackdrop: View {
    let animationsEnabled: Bool
    let isInteracting: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.livingMapRenderingDate) private var renderingDate

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15,
                                paused: renderingDate != nil || !animationsEnabled || isInteracting)) { timeline in
            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }
                let bounds = Path(CGRect(origin: .zero, size: size))
                let phase = animationsEnabled && !isInteracting
                    ? LivingMapDrawing.phase(at: renderingDate ?? timeline.date, period: 34) : 0
                let reach = max(size.width, size.height)
                let center = CGPoint(x: size.width * (0.46 + 0.035 * cos(phase)),
                                     y: size.height * (0.43 + 0.025 * sin(phase)))
                context.fill(bounds, with: .color(LearningMapPalette.background.color))
                context.fill(bounds, with: .radialGradient(
                    Gradient(colors: [LearningMapPalette.iris.color.opacity(colorScheme == .dark ? 0.12 : 0.075), .clear]),
                    center: center, startRadius: 0, endRadius: reach * 0.68
                ))
                context.fill(bounds, with: .radialGradient(
                    Gradient(colors: [LearningMapPalette.building.color.opacity(colorScheme == .dark ? 0.045 : 0.035), .clear]),
                    center: CGPoint(x: size.width * 0.88, y: size.height * 0.85),
                    startRadius: 0, endRadius: reach * 0.62
                ))

                var dots = Path()
                for x in stride(from: CGFloat(14), to: size.width, by: 28) {
                    for y in stride(from: CGFloat(14), to: size.height, by: 28) {
                        dots.addEllipse(in: CGRect(x: x, y: y, width: 1.25, height: 1.25))
                    }
                }
                context.fill(dots, with: .color(LearningMapPalette.secondary.color.opacity(colorScheme == .dark ? 0.15 : 0.11)))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct LivingMapConnection: View, Animatable {
    nonisolated var start: CGPoint
    nonisolated var end: CGPoint
    let tint: Color
    let highlighted: Bool
    let isHistorical: Bool
    let animationsEnabled: Bool
    @Environment(\.livingMapRenderingDate) private var renderingDate

    nonisolated var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(start.x, start.y), AnimatablePair(end.x, end.y)) }
        set {
            start = CGPoint(x: newValue.first.first, y: newValue.first.second)
            end = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    private var hasTravelingLight: Bool { animationsEnabled && highlighted && !isHistorical }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: renderingDate != nil || !hasTravelingLight)) { timeline in
            Canvas { context, _ in
                guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite,
                      hypot(end.x - start.x, end.y - start.y) > 1 else { return }
                let path = LivingMapDrawing.connection(from: start, to: end)
                let stroke = StrokeStyle(lineWidth: highlighted ? 1.65 : 1.05, lineCap: .round,
                                         dash: isHistorical ? [4, 6] : [])
                if highlighted && !isHistorical {
                    context.stroke(path, with: .color(tint.opacity(0.045)), lineWidth: 6)
                }
                context.stroke(path, with: .linearGradient(
                    Gradient(colors: [tint.opacity(highlighted ? 0.23 : 0.12),
                                      tint.opacity(highlighted ? 0.54 : 0.25),
                                      tint.opacity(highlighted ? 0.3 : 0.15)]),
                    startPoint: start, endPoint: end
                ), style: stroke)

                if hasTravelingLight {
                    let offset = atan2(end.y - start.y, end.x - start.x) / (.pi * 2)
                    let elapsed = (renderingDate ?? timeline.date).timeIntervalSinceReferenceDate / 9 + offset
                    let head = elapsed - floor(elapsed)
                    let tail = max(0, head - 0.14)
                    let fade = min(1, min(head / 0.12, (1 - head) / 0.15))
                    let gleam = path.trimmedPath(from: tail, to: head)
                    context.stroke(gleam, with: .color(tint.opacity(0.07 * fade)),
                                   style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    context.stroke(gleam, with: .color(tint.opacity(0.42 * fade)),
                                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct LivingMapNodeFace: View {
    let diameter: CGFloat
    let tint: Color
    let progress: Double
    let symbol: String?
    let isSelected: Bool
    let isGoal: Bool
    let evidenceAvailable: Bool
    let animationsEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.livingMapRenderingDate) private var renderingDate
    @State private var ringTransition: LivingMapProgressTransition?

    // Objective evidence is a practiced dot, while skill progress remains independent of that flag.
    private var ringProgress: Double {
        guard symbol != nil, !isGoal, progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

    private var faceDiameter: CGFloat { diameter.isFinite ? max(1, diameter) : 1 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24,
                                paused: renderingDate != nil || !animationsEnabled || (!isSelected && ringTransition == nil))) { timeline in
            let date = renderingDate ?? timeline.date
            let shownProgress = ringTransition?.value(at: date) ?? ringProgress
            let breath = animationsEnabled ? (sin(LivingMapDrawing.phase(at: date, period: 8)) + 1) / 2 : 0.5
            Canvas { context, size in
                drawFace(in: &context, size: size, progress: shownProgress, breath: breath)
            }
            .frame(width: faceDiameter + 36, height: faceDiameter + 36)
            .frame(width: faceDiameter, height: faceDiameter)
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: min(26, max(11, faceDiameter * (isGoal ? 0.36 : 0.37))), weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tint)
                }
            }
            .onChange(of: date) { _, date in
                if let ringTransition, ringTransition.isFinished(at: date) {
                    self.ringTransition = nil
                }
            }
        }
        .onChange(of: ringProgress) { previous, next in
            guard animationsEnabled else {
                ringTransition = nil
                return
            }
            let now = Date()
            let current = ringTransition?.value(at: now) ?? previous
            ringTransition = LivingMapProgressTransition(from: current, to: next, startedAt: now)
        }
        .onChange(of: animationsEnabled) { _, enabled in
            if !enabled { ringTransition = nil }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func drawFace(in context: inout GraphicsContext, size: CGSize, progress: Double, breath: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = faceDiameter / 2
        let circle = LivingMapDrawing.circle(center: center, radius: radius)
        let top = CGPoint(x: center.x - radius * 0.5, y: center.y - radius)
        let bottom = CGPoint(x: center.x + radius * 0.5, y: center.y + radius)
        let dark = colorScheme == .dark

        let shadowCenter = CGPoint(x: center.x, y: center.y + 4)
        context.fill(LivingMapDrawing.circle(center: shadowCenter, radius: radius + 12), with: .radialGradient(
            Gradient(stops: [.init(color: CheckpointPalette.shadowElevated.color, location: 0.46),
                             .init(color: .clear, location: 1)]),
            center: shadowCenter, startRadius: 0, endRadius: radius + 12
        ))
        if isSelected {
            context.fill(LivingMapDrawing.circle(center: center, radius: radius + 17), with: .radialGradient(
                Gradient(stops: [.init(color: tint.opacity(0.015), location: 0.45),
                                 .init(color: tint.opacity(0.065 + breath * 0.025), location: 0.69),
                                 .init(color: .clear, location: 1)]),
                center: center, startRadius: 0, endRadius: radius + 17
            ))
            context.stroke(LivingMapDrawing.circle(center: center, radius: radius + 8),
                           with: .color(tint.opacity(0.25 + breath * 0.09)), lineWidth: 1)
        }

        context.fill(circle, with: .linearGradient(
            Gradient(colors: [LearningMapPalette.panel.color, LearningMapPalette.raised.color]),
            startPoint: top, endPoint: bottom
        ))
        context.fill(circle, with: .radialGradient(
            Gradient(colors: [tint.opacity(isGoal ? 0.15 : isSelected ? 0.1 : 0.045), .clear]),
            center: CGPoint(x: center.x - radius * 0.3, y: center.y - radius * 0.5),
            startRadius: 0, endRadius: radius * 1.5
        ))
        context.stroke(circle, with: .linearGradient(
            Gradient(colors: [.white.opacity(dark ? 0.31 : 0.95), tint.opacity(0.2),
                              LearningMapPalette.text.color.opacity(dark ? 0.55 : 0.17)]),
            startPoint: top, endPoint: bottom
        ), lineWidth: 1)
        context.stroke(LivingMapDrawing.circle(center: center, radius: max(1, radius - 2)), with: .linearGradient(
            Gradient(colors: [.white.opacity(dark ? 0.07 : 0.55), .clear]), startPoint: top, endPoint: bottom
        ), lineWidth: 0.75)

        if symbol == nil {
            let dotRadius = max(2, radius * 0.4)
            context.fill(LivingMapDrawing.circle(center: center, radius: dotRadius),
                         with: .color(tint.opacity(evidenceAvailable ? 0.9 : 0.28)))
        } else if !isGoal {
            let ringRadius = radius + 3
            context.stroke(LivingMapDrawing.circle(center: center, radius: ringRadius),
                           with: .color(tint.opacity(0.12)), lineWidth: 2.3)
            if progress > 0 {
                var arc = Path()
                arc.addArc(center: center, radius: ringRadius, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * progress), clockwise: false)
                context.stroke(arc, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.72), tint]), startPoint: top, endPoint: bottom
                ), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
    }
}

private enum LivingMapDrawing {
    static func phase(at date: Date, period: Double) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * .pi * 2
    }

    static func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    static func connection(from start: CGPoint, to end: CGPoint) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end,
                      control1: CGPoint(x: start.x + dx * 0.12, y: start.y + dy * 0.55),
                      control2: CGPoint(x: end.x - dx * 0.12, y: end.y - dy * 0.4))
        return path
    }
}

/// A critically damped spring never displays more evidence than either endpoint.
struct LivingMapProgressTransition {
    let from: Double
    let to: Double
    let startedAt: Date

    func value(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        guard elapsed < 0.9 else { return to }
        let amount = 1 - (1 + 12 * elapsed) * exp(-12 * elapsed)
        return from + (to - from) * amount
    }

    func isFinished(at date: Date) -> Bool {
        date.timeIntervalSince(startedAt) >= 0.9
    }
}
