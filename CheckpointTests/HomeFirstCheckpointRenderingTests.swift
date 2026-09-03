import SwiftUI
import XCTest
@testable import Checkpoint

final class HomeFirstCheckpointRenderingTests: XCTestCase {
    @MainActor
    func testFirstCheckpointLaunchpadRendersAcrossKeyLayouts() {
        let fixtures = [
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-dark",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            HomeLaunchpadRenderFixture(
                name: "first-checkpoint-accessibility",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: launchpadSurface
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme
            )

            XCTAssertEqual(image.size.width, fixture.width)
            XCTAssertEqual(image.size.height, fixture.height)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private var launchpadSurface: some View {
        ScrollView {
            HomeFirstCheckpointLaunchpad(
                requiredCorrectAnswers: 4,
                questionCount: 5,
                unlockMinutes: 30,
                protectedAppsSummary: "3 apps and 2 websites selected",
                reviewApps: {}
            )
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 36)
        }
        .checkpointScreenBackground()
    }
}

private struct HomeLaunchpadRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
}
