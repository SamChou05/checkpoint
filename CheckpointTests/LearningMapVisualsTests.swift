import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class LearningMapVisualsTests: XCTestCase {
    @MainActor
    func testBackdropMovesAtExplicitDatesAndIsStillWhenDisabledOrInteracting() throws {
        for scheme in [ColorScheme.light, .dark] {
            let active = LivingMapBackdrop(animationsEnabled: true, isInteracting: false)
            let first = try pixels(active, at: 2, scheme: scheme, size: CGSize(width: 260, height: 200))
            let later = try pixels(active, at: 19, scheme: scheme, size: CGSize(width: 260, height: 200))
            XCTAssertGreaterThan(first.changedPixels(comparedWith: later), 50,
                                 "The ambient light must visibly change without moving the texture or layout.")
            for backdrop in [LivingMapBackdrop(animationsEnabled: false, isInteracting: false),
                             LivingMapBackdrop(animationsEnabled: true, isInteracting: true)] {
                let still = try pixels(backdrop, at: 2, scheme: scheme, size: CGSize(width: 260, height: 200))
                let stillLater = try pixels(backdrop, at: 19, scheme: scheme, size: CGSize(width: 260, height: 200))
                assertIdentical(still, stillLater, message: "The caller's motion restriction must survive redraws and remounts.")
            }
        }
    }

    @MainActor
    func testOnlyHighlightedCurrentConnectionsCarryTravelingLight() throws {
        for scheme in [ColorScheme.light, .dark] {
            let active = connection(highlighted: true, historical: false, animated: true)
            let first = try pixels(active, at: 2, scheme: scheme)
            let later = try pixels(active, at: 5, scheme: scheme)
            XCTAssertGreaterThan(first.changedPixels(comparedWith: later), 12)
            for wire in [connection(highlighted: true, historical: false, animated: false),
                         connection(highlighted: true, historical: true, animated: true),
                         connection(highlighted: false, historical: false, animated: true)] {
                let still = try pixels(wire, at: 2, scheme: scheme)
                let stillLater = try pixels(wire, at: 5, scheme: scheme)
                assertIdentical(still, stillLater, message: "History, unrelated branches, and suppressed motion must not imply moving progress.")
            }
        }
    }

    @MainActor
    func testSelectedHaloChangesOutsideTheFixedFaceWhileSuppressedMotionStaysStill() throws {
        let size = CGSize(width: 128, height: 128)
        let center = CGRect(x: 48, y: 48, width: 32, height: 32)
        for scheme in [ColorScheme.light, .dark] {
            let face = node(selected: true, animated: true)
            let first = try pixels(face, at: 2, scheme: scheme, size: size)
            let later = try pixels(face, at: 6, scheme: scheme, size: size)
            XCTAssertGreaterThan(first.changedPixels(comparedWith: later), 12)
            assertIdentical(first, later, inside: center, message: "A breathing halo must not drift the symbol or evidence surface.")
            let still = node(selected: true, animated: false)
            assertIdentical(try pixels(still, at: 2, scheme: scheme, size: size),
                            try pixels(still, at: 6, scheme: scheme, size: size), message: "Suppressed node motion must remain still.")
        }
    }

    @MainActor
    func testFocusPointEvidenceIsOnlyADotAndSkillProgressDoesNotDependOnThatFlag() throws {
        let size = CGSize(width: 128, height: 128)
        for scheme in [ColorScheme.light, .dark] {
            let fresh = try pixels(node(diameter: 18, progress: 0, symbol: nil, evidence: false), scheme: scheme, size: size)
            let practiced = try pixels(node(diameter: 18, progress: 0, symbol: nil, evidence: true), scheme: scheme, size: size)
            let center = CGRect(x: 59, y: 59, width: 10, height: 10)
            XCTAssertGreaterThan(fresh.changedPixels(comparedWith: practiced, inside: center), 12)
            assertIdentical(fresh, practiced, excluding: center,
                            message: "Objective evidence changes the center dot, not a mastery arc or the node geometry.")
            let unsupportedProgress = try pixels(node(diameter: 18, progress: 1, symbol: nil, evidence: true), scheme: scheme, size: size)
            assertIdentical(practiced, unsupportedProgress, message: "Focus points never render a mastery ring.")

            let skill = try pixels(node(progress: 0.65, evidence: false), scheme: scheme, size: size)
            let skillWithObjectiveFlag = try pixels(node(progress: 0.65, evidence: true), scheme: scheme, size: size)
            assertIdentical(skill, skillWithObjectiveFlag, message: "The objective flag must not affect a skill face.")
            let noProgress = try pixels(node(progress: 0, evidence: false), scheme: scheme, size: size)
            XCTAssertGreaterThan(skill.changedPixels(comparedWith: noProgress), 30,
                                 "Real skill evidence must remain visible when the objective-only flag is false.")
        }
    }

    @MainActor
    func testProgressSpringMovesMonotonicallyWithoutInventingEvidence() {
        let start = Date(timeIntervalSinceReferenceDate: 100)
        for (from, to) in [(0.2, 0.85), (0.85, 0.2)] {
            let spring = LivingMapProgressTransition(from: from, to: to, startedAt: start)
            let times: [TimeInterval] = [-1, 0, 0.08, 0.16, 0.32, 0.64, 0.9, 2]
            let values = times.map { spring.value(at: start.addingTimeInterval($0)) }
            XCTAssertEqual(values.first, from)
            XCTAssertEqual(values.last, to)
            for value in values {
                XCTAssertGreaterThanOrEqual(value, min(from, to))
                XCTAssertLessThanOrEqual(value, max(from, to))
            }
            for (earlier, later) in zip(values, values.dropFirst()) {
                if from < to { XCTAssertLessThanOrEqual(earlier, later) }
                else { XCTAssertGreaterThanOrEqual(earlier, later) }
            }
            XCTAssertFalse(spring.isFinished(at: start.addingTimeInterval(0.5)))
            XCTAssertTrue(spring.isFinished(at: start.addingTimeInterval(1)))
        }
    }

    @MainActor
    func testNodeHalosHaveRoomOutsideTheFaceAndDoNotReachTheCaptureBoundary() throws {
        let size = CGSize(width: 128, height: 128)
        for scheme in [ColorScheme.light, .dark] {
            let empty = try pixels(Color.clear, scheme: scheme, size: size)
            for diameter in [CGFloat(18), 46, 72] {
                let image = try pixels(node(diameter: diameter, selected: true), scheme: scheme, size: size)
                let faceBounds = CGRect(x: 64 - diameter / 2, y: 64 - diameter / 2, width: diameter, height: diameter)
                XCTAssertGreaterThan(image.changedPixels(comparedWith: empty, excluding: faceBounds), 24,
                                     "The fixed layout frame must not clip its decorative halo.")
                assertIdentical(image, empty, excluding: CGRect(x: 8, y: 8, width: 112, height: 112),
                                message: "The documented halo margin must contain every painted pixel.")
            }
        }
    }

    @MainActor
    func testPrimaryNodeSymbolsHaveNonTextContrastInBothAppearances() {
        let colors = [CheckpointPalette.teal, CheckpointPalette.blue, CheckpointPalette.amber,
                      CheckpointPalette.coral, CheckpointPalette.muted]
        for dark in [false, true] {
            for palette in colors {
                let foreground = dark ? palette.dark : palette.light
                for panel in [CheckpointPalette.panel, CheckpointPalette.panelRaised] {
                    let background = dark ? panel.dark : panel.light
                    let values = [luminance(foreground), luminance(background)].sorted()
                    XCTAssertGreaterThanOrEqual((values[1] + 0.05) / (values[0] + 0.05), 3,
                                                "Meaningful node symbols need contrast against both ends of the face gradient.")
                }
            }
        }
    }

    @MainActor
    func testNativeVisualBoardsInLightAndDarkAppearance() {
        for scheme in [ColorScheme.light, .dark] {
            let board = ZStack {
                LivingMapBackdrop(animationsEnabled: true, isInteracting: false)
                LivingMapConnection(start: CGPoint(x: 155, y: 66), end: CGPoint(x: 82, y: 174), tint: CheckpointTheme.teal,
                                    highlighted: true, isHistorical: false, animationsEnabled: true)
                LivingMapConnection(start: CGPoint(x: 155, y: 66), end: CGPoint(x: 228, y: 174), tint: CheckpointTheme.muted,
                                    highlighted: false, isHistorical: false, animationsEnabled: true)
                LivingMapConnection(start: CGPoint(x: 82, y: 174), end: CGPoint(x: 48, y: 274), tint: CheckpointTheme.teal,
                                    highlighted: true, isHistorical: false, animationsEnabled: true)
                LivingMapConnection(start: CGPoint(x: 82, y: 174), end: CGPoint(x: 116, y: 274), tint: CheckpointTheme.teal,
                                    highlighted: true, isHistorical: false, animationsEnabled: true)
                LivingMapNodeFace(diameter: 72, tint: CheckpointTheme.teal, progress: 0, symbol: "scope",
                                  isSelected: false, isGoal: true, evidenceAvailable: false, animationsEnabled: true)
                    .position(x: 155, y: 66)
                node(selected: true, animated: true).position(x: 82, y: 174)
                LivingMapNodeFace(diameter: 46, tint: CheckpointTheme.muted, progress: 0.4, symbol: "pause",
                                  isSelected: false, isGoal: false, evidenceAvailable: false, animationsEnabled: true)
                    .position(x: 228, y: 174)
                node(diameter: 18, progress: 0, symbol: nil, evidence: true).position(x: 48, y: 274)
                node(diameter: 18, progress: 0, symbol: nil, evidence: false).position(x: 116, y: 274)
            }
            let image = snapshot(board, at: 2, scheme: scheme, size: CGSize(width: 310, height: 324))
            let attachment = XCTAttachment(image: image)
            attachment.name = "living-map-components-\(scheme == .dark ? "dark" : "light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func node(diameter: CGFloat = 46, progress: Double = 0.62, symbol: String? = "leaf.fill",
                      selected: Bool = false, evidence: Bool = false, animated: Bool = false) -> LivingMapNodeFace {
        LivingMapNodeFace(diameter: diameter, tint: CheckpointTheme.teal, progress: progress, symbol: symbol,
                          isSelected: selected, isGoal: false, evidenceAvailable: evidence, animationsEnabled: animated)
    }

    @MainActor
    private func connection(highlighted: Bool, historical: Bool, animated: Bool) -> LivingMapConnection {
        LivingMapConnection(start: CGPoint(x: 22, y: 130), end: CGPoint(x: 236, y: 28), tint: CheckpointTheme.teal,
                            highlighted: highlighted, isHistorical: historical, animationsEnabled: animated)
    }

    @MainActor
    private func snapshot<Content: View>(_ content: Content, at seconds: TimeInterval = 2, scheme: ColorScheme,
                                        size: CGSize = CGSize(width: 260, height: 160)) -> UIImage {
        // Render these isolated vector components without a UIWindow: a tiny hosted window
        // inherits the device status-bar safe area and shifts the supposedly centered nodes.
        // This also keeps screen-compositor timing out of exact same-frame comparisons.
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light).performAsCurrent {
            let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height)
                .background(CheckpointPalette.backgroundBase.color)
                .environment(\.colorScheme, scheme)
                .environment(\.livingMapRenderingDate, Date(timeIntervalSinceReferenceDate: seconds))
                .transaction { $0.disablesAnimations = true })
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(size)
            image = renderer.uiImage
        }
        guard let image else {
            XCTFail("Native rendering must produce a real image of the Canvas components.")
            return UIImage()
        }
        return image
    }

    @MainActor
    private func pixels<Content: View>(_ content: Content, at seconds: TimeInterval = 2, scheme: ColorScheme,
                                      size: CGSize = CGSize(width: 260, height: 160)) throws -> LivingMapPixels {
        try LivingMapPixels(image: snapshot(content, at: seconds, scheme: scheme, size: size))
    }

    @MainActor
    private func assertIdentical(_ first: LivingMapPixels, _ second: LivingMapPixels,
                                 inside region: CGRect? = nil, excluding excluded: CGRect? = nil,
                                 message: String, file: StaticString = #filePath, line: UInt = #line) {
        let changed = first.changedPixels(comparedWith: second, inside: region, excluding: excluded)
        if changed != 0 {
            XCTContext.runActivity(named: message) { activity in
                for (name, image) in [("First frame", first.image), ("Second frame", second.image)] {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    activity.add(attachment)
                }
                let summary = XCTAttachment(string: first.differenceSummary(comparedWith: second, inside: region, excluding: excluded))
                summary.name = "Exact channel differences and their location"
                summary.lifetime = .keepAlways
                activity.add(summary)
            }
        }
        XCTAssertEqual(changed, 0, message, file: file, line: line)
    }

    @MainActor
    private func luminance(_ color: CheckpointColorComponents) -> Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }
}

private struct LivingMapPixels {
    let image: UIImage
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(image: UIImage) throws {
        self.image = image
        let image = try XCTUnwrap(image.cgImage)
        width = image.width
        height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = pixels
    }

    func changedPixels(comparedWith other: Self, inside region: CGRect? = nil, excluding excluded: CGRect? = nil) -> Int {
        guard width == other.width, height == other.height else {
            XCTFail("Deterministic frames must have identical dimensions.")
            return 0
        }
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                guard region?.contains(point) != false, excluded?.contains(point) != true else { continue }
                let offset = (y * width + x) * 4
                if (0..<3).contains(where: { bytes[offset + $0] != other.bytes[offset + $0] }) { count += 1 }
            }
        }
        return count
    }

    func differenceSummary(comparedWith other: Self, inside region: CGRect? = nil, excluding excluded: CGRect? = nil) -> String {
        guard width == other.width, height == other.height else { return "Different image dimensions." }
        var histogram: [Int: Int] = [:]
        var bounds = CGRect.null
        for y in 0..<height {
            for x in 0..<width {
                let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                guard region?.contains(point) != false, excluded?.contains(point) != true else { continue }
                let offset = (y * width + x) * 4
                let delta = (0..<3).map { abs(Int(bytes[offset + $0]) - Int(other.bytes[offset + $0])) }.max() ?? 0
                if delta > 0 {
                    histogram[delta, default: 0] += 1
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return "Changed pixel bounds: \(bounds)\nMaximum RGB channel delta → pixel count: \(histogram.sorted { $0.key < $1.key })"
    }
}
