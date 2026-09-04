import SwiftUI
import XCTest
@testable import Checkpoint

final class MembershipViewRenderingTests: XCTestCase {
    @MainActor
    func testMembershipJourneyRendersAcrossKeyLayoutsAndStates() throws {
        let legalLinks = LegalLinks(
            privacyPolicyURL: try XCTUnwrap(URL(string: "https://example.com/privacy")),
            supportURL: try XCTUnwrap(URL(string: "https://example.com/support"))
        )
        let planOptions = MembershipCatalogPresentation(
            storeProducts: [
                MembershipStoreProduct(
                    id: MembershipProductID.monthly,
                    price: try XCTUnwrap(Decimal(string: "4.99")),
                    displayPrice: "$4.99",
                    currencyCode: "USD",
                    locale: Locale(identifier: "en_US"),
                    billingPeriod: .month
                ),
                MembershipStoreProduct(
                    id: MembershipProductID.yearly,
                    price: try XCTUnwrap(Decimal(string: "29.99")),
                    displayPrice: "$29.99",
                    currencyCode: "USD",
                    locale: Locale(identifier: "en_US"),
                    billingPeriod: .year
                )
            ]
        ).planOptions

        let fixtures = [
            MembershipRenderFixture(
                name: "membership-annual-light",
                feature: .adaptiveStudyAssist,
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly
            ),
            MembershipRenderFixture(
                name: "membership-monthly-compact-dark",
                feature: .goalProfiles,
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.monthly
            ),
            MembershipRenderFixture(
                name: "membership-annual-accessibility",
                feature: .largerQuestionBank,
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                reduceMotion: true,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly
            ),
            MembershipRenderFixture(
                name: "membership-compact-accessibility5",
                feature: .goalProfiles,
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly
            ),
            MembershipRenderFixture(
                name: "membership-loading",
                feature: .freshQuestionGeneration,
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                isLoading: true
            ),
            MembershipRenderFixture(
                name: "membership-unavailable",
                feature: .freshQuestionGeneration,
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                purchaseNotice: .catalogUnavailable("Could not load App Store plans yet.")
            ),
            MembershipRenderFixture(
                name: "membership-pending-dark",
                feature: .adaptiveStudyAssist,
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly,
                purchaseNotice: .pendingApproval
            ),
            MembershipRenderFixture(
                name: "membership-purchase-failure",
                feature: .goalProfiles,
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.monthly,
                purchaseNotice: .failure("Purchase failed. Try again from the App Store sheet.")
            ),
            MembershipRenderFixture(
                name: "membership-restore-information",
                feature: .freshQuestionGeneration,
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly,
                purchaseNotice: .information("No active Checkpoint Pro subscription was found.")
            ),
            MembershipRenderFixture(
                name: "membership-active-accessibility",
                feature: .freshQuestionGeneration,
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                reduceMotion: true,
                isMember: true
            )
        ]

        var defaultsSuites: [String] = []
        defer {
            for suiteName in defaultsSuites {
                UserDefaults.standard.removePersistentDomain(forName: suiteName)
            }
        }

        for fixture in fixtures {
            let suiteName = "MembershipViewRenderingTests.\(fixture.name).\(UUID().uuidString)"
            defaultsSuites.append(suiteName)
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            let store = CheckpointStore(defaults: defaults)
            if fixture.isMember {
                store.updateMembershipTier(.member)
            }

            let initialStoreOperation: MembershipStoreOperation? = fixture.isLoading
                ? .loadingProducts
                : nil
            let purchaseController = PurchaseController(
                grantsDebugTesterEntitlement: false,
                initialStoreOperation: initialStoreOperation
            )
            purchaseController.purchaseNotice = fixture.purchaseNotice

            let view = MembershipView(
                feature: fixture.feature,
                store: store,
                purchaseController: purchaseController,
                renderConfiguration: MembershipViewRenderConfiguration(
                    planOptions: fixture.planOptions,
                    selectedPlanID: fixture.selectedPlanID,
                    legalLinks: legalLinks,
                    reduceMotion: fixture.reduceMotion
                )
            )
            .environment(\.colorScheme, fixture.colorScheme)
            .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)

            let image = HostedViewRenderer.image(
                for: view,
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: fixture.reduceMotion ? 0.05 : 0.55,
                // Preserve device point geometry while keeping the full render suite's memory bounded.
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
}

private struct MembershipRenderFixture {
    let name: String
    let feature: MembershipFeature
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    var reduceMotion = false
    var planOptions: [MembershipPlanOption] = []
    var selectedPlanID: String?
    var isLoading = false
    var purchaseNotice: MembershipPurchaseNotice?
    var isMember = false
}
