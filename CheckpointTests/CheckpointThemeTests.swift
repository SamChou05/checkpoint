import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class CheckpointThemeTests: XCTestCase {
    func testPrimaryActionIconMotionTracksLoadingAndReduceMotion() {
        XCTAssertEqual(
            PrimaryActionIconState(systemImage: "arrow.right", isLoading: false),
            .symbol("arrow.right")
        )
        XCTAssertEqual(
            PrimaryActionIconState(systemImage: "arrow.right", isLoading: true),
            .loading
        )

        let standard = PrimaryActionIconMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .animated)
        XCTAssertNotNil(standard.animation)

        let reduced = PrimaryActionIconMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
    }

    @MainActor
    func testPrimaryActionButtonsPreserveGeometryAcrossIconStates() throws {
        let fixtures = [
            PrimaryActionRenderFixture(
                name: "primary-actions-standard-light",
                width: 393,
                height: 300,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            PrimaryActionRenderFixture(
                name: "primary-actions-accessibility5-dark",
                width: 393,
                height: 700,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5
            )
        ]

        for fixture in fixtures {
            let capture = PrimaryActionSizeCapture()
            let image = HostedViewRenderer.image(
                for: PrimaryActionRenderScene(capture: capture)
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: 0.2,
                renderScale: 1
            )

            let idleSize = try XCTUnwrap(capture.sizes[.idle], fixture.name)
            let loadingSize = try XCTUnwrap(capture.sizes[.loading], fixture.name)
            let changedSymbolSize = try XCTUnwrap(capture.sizes[.changedSymbol], fixture.name)
            XCTAssertEqual(idleSize.width, loadingSize.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(idleSize.height, loadingSize.height, accuracy: 0.5, fixture.name)
            XCTAssertEqual(idleSize.width, changedSymbolSize.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(idleSize.height, changedSymbolSize.height, accuracy: 0.5, fixture.name)

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testSemanticTextAndAccentRolesMeetContrastContract() {
        let roles: [(String, CheckpointAdaptiveColor)] = [
            ("text", CheckpointPalette.text),
            ("muted", CheckpointPalette.muted),
            ("teal", CheckpointPalette.teal),
            ("blue", CheckpointPalette.blue),
            ("amber", CheckpointPalette.amber),
            ("coral", CheckpointPalette.coral)
        ]

        for (name, role) in roles {
            assertContrast(role.light, CheckpointPalette.panel.light, minimum: 4.5, context: "light \(name)")
            assertContrast(role.dark, CheckpointPalette.panel.dark, minimum: 4.5, context: "dark \(name)")
        }
    }

    func testStatusRolesRemainReadableOnTheirTintedBackgrounds() {
        let roles: [(String, CheckpointAdaptiveColor)] = [
            ("teal", CheckpointPalette.teal),
            ("blue", CheckpointPalette.blue),
            ("amber", CheckpointPalette.amber),
            ("coral", CheckpointPalette.coral)
        ]

        for (name, role) in roles {
            for (surfaceName, surface) in [
                ("panel", CheckpointPalette.panel),
                ("raised panel", CheckpointPalette.panelRaised)
            ] {
                let lightTint = composite(role.light, over: surface.light, opacity: 0.14)
                let darkTint = composite(role.dark, over: surface.dark, opacity: 0.14)

                assertContrast(
                    role.light,
                    lightTint,
                    minimum: 4.5,
                    context: "light \(surfaceName) tinted \(name)"
                )
                assertContrast(
                    role.dark,
                    darkTint,
                    minimum: 4.5,
                    context: "dark \(surfaceName) tinted \(name)"
                )
            }
        }
    }

    func testPrimaryAndDestructiveActionsKeepReadableLabels() {
        for (appearance, leading, trailing, destructive) in [
            (
                "light",
                CheckpointPalette.actionTeal.light,
                CheckpointPalette.actionDeep.light,
                CheckpointPalette.destructiveFill.light
            ),
            (
                "dark",
                CheckpointPalette.actionTeal.dark,
                CheckpointPalette.actionDeep.dark,
                CheckpointPalette.destructiveFill.dark
            )
        ] {
            assertContrast(CheckpointPalette.paper, leading, minimum: 4.5, context: "\(appearance) action leading")
            assertContrast(CheckpointPalette.paper, trailing, minimum: 4.5, context: "\(appearance) action trailing")
            assertContrast(CheckpointPalette.paper, destructive, minimum: 4.5, context: "\(appearance) destructive")
        }

        for (endpointName, endpoint) in [
            ("leading", CheckpointPalette.actionTeal.dark),
            ("trailing", CheckpointPalette.actionDeep.dark)
        ] {
            let renderedBorder = composite(
                CheckpointPalette.actionBorder.dark,
                over: endpoint,
                opacity: CheckpointPalette.actionBorder.dark.alpha
            )
            assertContrast(
                renderedBorder,
                CheckpointPalette.panel.dark,
                minimum: 3,
                context: "dark action \(endpointName) outline"
            )
        }
    }

    func testHeroAndControlRolesKeepRequiredContrast() {
        for (name, role) in [
            ("hero text", CheckpointPalette.heroText),
            ("hero muted", CheckpointPalette.heroMuted),
            ("hero success", CheckpointPalette.mint),
            ("hero info", CheckpointPalette.heroInfo),
            ("hero warning", CheckpointPalette.heroWarning),
            ("hero danger", CheckpointPalette.heroDanger)
        ] {
            assertContrast(role, CheckpointPalette.ink, minimum: 4.5, context: name)
        }

        assertContrast(
            CheckpointPalette.controlStroke.light,
            CheckpointPalette.panel.light,
            minimum: 3,
            context: "light control outline"
        )
        assertContrast(
            CheckpointPalette.controlStroke.dark,
            CheckpointPalette.panel.dark,
            minimum: 3,
            context: "dark control outline"
        )
    }

    func testSelectedControlStateRemainsDistinctAndReadable() {
        for (appearance, fill, surface) in [
            ("light", CheckpointPalette.selectionFill.light, CheckpointPalette.panelRaised.light),
            ("dark", CheckpointPalette.selectionFill.dark, CheckpointPalette.panelRaised.dark)
        ] {
            assertContrast(fill, surface, minimum: 3, context: "\(appearance) selected control state")
            assertContrast(
                CheckpointPalette.selectionText,
                fill,
                minimum: 4.5,
                context: "\(appearance) selected control label"
            )
        }
    }

    func testAdaptiveCanvasAndContentRolesHaveDistinctAppearances() {
        for role in [
            CheckpointPalette.backgroundBase,
            CheckpointPalette.backgroundGreen,
            CheckpointPalette.backgroundWarm,
            CheckpointPalette.panel,
            CheckpointPalette.panelRaised,
            CheckpointPalette.text,
            CheckpointPalette.muted,
            CheckpointPalette.teal
        ] {
            XCTAssertNotEqual(role.light, role.dark)
        }
    }

    private func assertContrast(
        _ foreground: CheckpointColorComponents,
        _ background: CheckpointColorComponents,
        minimum: Double,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = contrastRatio(foreground, background)
        XCTAssertGreaterThanOrEqual(
            ratio,
            minimum,
            "\(context) contrast was \(String(format: "%.2f", ratio)):1",
            file: file,
            line: line
        )
    }

    private func contrastRatio(
        _ first: CheckpointColorComponents,
        _ second: CheckpointColorComponents
    ) -> Double {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: CheckpointColorComponents) -> Double {
        (0.2126 * linearized(color.red))
            + (0.7152 * linearized(color.green))
            + (0.0722 * linearized(color.blue))
    }

    private func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    private func composite(
        _ foreground: CheckpointColorComponents,
        over background: CheckpointColorComponents,
        opacity: Double
    ) -> CheckpointColorComponents {
        let amount = min(max(opacity, 0), 1)
        return CheckpointColorComponents(
            red: (foreground.red * amount) + (background.red * (1 - amount)),
            green: (foreground.green * amount) + (background.green * (1 - amount)),
            blue: (foreground.blue * amount) + (background.blue * (1 - amount)),
            alpha: 1
        )
    }
}

private struct PrimaryActionRenderFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
}

private enum PrimaryActionCaptureKey: Hashable {
    case idle
    case loading
    case changedSymbol
}

@MainActor
private final class PrimaryActionSizeCapture {
    var sizes: [PrimaryActionCaptureKey: CGSize] = [:]
}

private struct PrimaryActionRenderScene: View {
    let capture: PrimaryActionSizeCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("PRIMARY ACTIONS")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(CheckpointTheme.muted)

            measuredButton(
                key: .idle,
                title: "Continue",
                systemImage: "arrow.right",
                isLoading: false
            )
            measuredButton(
                key: .loading,
                title: "Continue",
                systemImage: "arrow.right",
                isLoading: true
            )
            measuredButton(
                key: .changedSymbol,
                title: "Continue",
                systemImage: "checkmark",
                isLoading: false
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .checkpointScreenBackground()
    }

    private func measuredButton(
        key: PrimaryActionCaptureKey,
        title: String,
        systemImage: String,
        isLoading: Bool
    ) -> some View {
        PrimaryActionButton(
            title: title,
            systemImage: systemImage,
            isLoading: isLoading
        ) {}
        .disabled(isLoading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        capture.sizes[key] = proxy.size
                    }
            }
        }
    }
}
