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
                colorScheme: fixture.colorScheme,
                // Preserve point geometry while keeping the full render suite's retained attachments bounded.
                renderScale: 0.5
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 1)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testEarnedBreakCardRendersAcrossKeyLayouts() {
        let fixtures = [
            HomeBreakRenderFixture(
                name: "earned-break-light",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-dark-ending-soon",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                secondsRemaining: 46
            ),
            HomeBreakRenderFixture(
                name: "earned-break-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-accessibility-2",
                width: 393,
                height: 1_100,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-accessibility-5-dark",
                width: 393,
                height: 2_200,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                secondsRemaining: 18 * 60 + 32
            ),
            HomeBreakRenderFixture(
                name: "earned-break-reduce-motion",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                secondsRemaining: 0,
                relockReadiness: .waitingForCheckpoint,
                areProtectedAppsAvailable: false,
                reduceMotion: true
            )
        ]

        for fixture in fixtures {
            let now = Date()
            let image = HostedViewRenderer.image(
                for: ScrollView {
                    HomeActiveBreakCard(
                        startedAt: now.addingTimeInterval(-12 * 60),
                        expiresAt: now.addingTimeInterval(TimeInterval(fixture.secondsRemaining)),
                        relockReadiness: fixture.relockReadiness,
                        areProtectedAppsAvailable: fixture.areProtectedAppsAvailable,
                        protectedAppsSummary: "3 apps, 1 category, 2 sites selected",
                        reduceMotionOverride: fixture.reduceMotion,
                        manageApps: {},
                        endBreakEarly: {}
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
                .checkpointScreenBackground()
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                // Preserve point geometry while keeping the full render suite's retained attachments bounded.
                renderScale: 0.5
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 1)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = XCTAttachment.Lifetime.keepAlways
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

private struct HomeBreakRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var secondsRemaining: Int
    var relockReadiness: HomeActiveBreakRelockReadiness = .ready
    var areProtectedAppsAvailable = true
    var reduceMotion = false
}
