import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class FocusWinsViewRenderingTests: XCTestCase {
    @MainActor
    func testFocusWinsSurfacesRenderAcrossKeyLayouts() throws {
        let suiteName = "FocusWinsViewRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let goal = Goal(
            title: "Pass senior technical interviews",
            deadline: Date().addingTimeInterval(86_400 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays, system design, communication",
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        let now = Date()
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Explained the tradeoffs in my cache design without needing a hint.",
                loggedAt: now
            ),
            FocusWin(
                goalID: goal.id,
                note: "Finished the recursion review and caught my own base-case error.",
                loggedAt: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            )
        ]

        let fixtures = [
            RenderFixture(
                name: "focus-wins-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    FocusWinsView(store: store, goalID: goal.id, goalTitle: goal.title)
                )
            ),
            RenderFixture(
                name: "focus-wins-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    FocusWinsView(store: store, goalID: goal.id, goalTitle: goal.title)
                )
            ),
            RenderFixture(
                name: "focus-wins-compact-accessibility",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    FocusWinsView(store: store, goalID: goal.id, goalTitle: goal.title)
                )
            ),
            RenderFixture(
                name: "progress-focus-wins-entry",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(CompetencyView(store: store))
            )
        ]

        for fixture in fixtures {
            let image = render(
                fixture.content
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)
                    .preferredColorScheme(fixture.colorScheme),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme
            )

            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func render(
        _ content: some View,
        width: CGFloat,
        height: CGFloat,
        colorScheme: ColorScheme
    ) -> UIImage {
        let size = CGSize(width: width, height: height)
        let frame = CGRect(origin: .zero, size: size)
        let hostingController = UIHostingController(rootView: content)
        let window = UIWindow(frame: frame)
        let interfaceStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light

        window.overrideUserInterfaceStyle = interfaceStyle
        hostingController.overrideUserInterfaceStyle = interfaceStyle
        window.rootViewController = hostingController
        window.isHidden = false
        hostingController.view.frame = frame
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        hostingController.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            XCTAssertTrue(
                hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                ),
                "Failed to draw hosted SwiftUI hierarchy"
            )
        }

        window.isHidden = true
        return image
    }
}

private struct RenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var content: AnyView
}
