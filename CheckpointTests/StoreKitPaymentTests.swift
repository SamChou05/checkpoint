import XCTest
@testable import Checkpoint

final class StoreKitPaymentTests: XCTestCase {
    // MARK: - Entitlement configuration

    @MainActor
    func testDebugMembershipEntitlementDefaultsOff() {
        let controller = PurchaseController(grantsDebugTesterEntitlement: false)

        XCTAssertFalse(controller.isMembershipUnlocked)
    }

    @MainActor
    func testDebugMembershipEntitlementCanBeExplicitlyEnabled() async {
        let controller = PurchaseController(grantsDebugTesterEntitlement: true)
        let isUnlocked = await controller.refreshEntitlements()

        XCTAssertTrue(isUnlocked)
        XCTAssertTrue(controller.isMembershipUnlocked)
        XCTAssertEqual(controller.purchasedProductIDs, [MembershipProductID.monthly])
    }

    func testDebugMembershipEnvironmentOptInIsExplicit() {
        XCTAssertFalse(DebugMembershipEntitlement.isEnabled(environment: [:]))
        XCTAssertFalse(
            DebugMembershipEntitlement.isEnabled(
                environment: [DebugMembershipEntitlement.environmentKey: "0"]
            )
        )

        #if DEBUG
        XCTAssertTrue(
            DebugMembershipEntitlement.isEnabled(
                environment: [DebugMembershipEntitlement.environmentKey: "true"]
            )
        )
        #endif
    }

    func testCompiledQAProBuildOptInIsExplicit() {
        #if DEBUG
        XCTAssertTrue(
            DebugMembershipEntitlement.isEnabled(
                environment: [:],
                compiledQABuild: true
            )
        )
        #endif
    }

    func testLegalLinksRejectMissingAndUnexpandedBuildSettings() {
        XCTAssertNil(LegalLinks.configuredURL(nil))
        XCTAssertNil(LegalLinks.configuredURL(""))
        XCTAssertNil(LegalLinks.configuredURL("$(CHECKPOINT_PRIVACY_POLICY_URL)"))
        XCTAssertNil(LegalLinks.configuredURL("not a URL"))
        XCTAssertNil(LegalLinks.configuredURL("http://checkpoint.example/privacy"))
        XCTAssertEqual(
            LegalLinks.configuredURL("https://checkpoint.example/privacy")?.absoluteString,
            "https://checkpoint.example/privacy"
        )
        XCTAssertEqual(LegalLinks.termsOfUseURL.scheme, "https")
    }

    // MARK: - StoreKit configuration

    func testLocalStoreKitConfigMatchesMembershipProductIDs() throws {
        let subscriptions = try localSubscriptions()

        XCTAssertEqual(subscriptions.map(\.productID), MembershipProductID.all)
    }

    func testLocalStoreKitConfigUsesLaunchPricingAndPeriods() throws {
        let subscriptions = try localSubscriptions()
        let monthly = try XCTUnwrap(subscriptions.first { $0.productID == MembershipProductID.monthly })
        let yearly = try XCTUnwrap(subscriptions.first { $0.productID == MembershipProductID.yearly })

        XCTAssertEqual(monthly.displayPrice, "4.99")
        XCTAssertEqual(monthly.recurringSubscriptionPeriod, "P1M")
        XCTAssertEqual(yearly.displayPrice, "29.99")
        XCTAssertEqual(yearly.recurringSubscriptionPeriod, "P1Y")
    }

    func testCatalogDerivesLocalizedAnnualValueAndRecommendsIt() throws {
        let presentation = MembershipCatalogPresentation(
            storeProducts: [
                makeStoreProduct(
                    id: MembershipProductID.monthly,
                    price: "4.99",
                    displayPrice: "$4.99",
                    billingPeriod: .month
                ),
                makeStoreProduct(
                    id: MembershipProductID.yearly,
                    price: "29.99",
                    displayPrice: "$29.99",
                    billingPeriod: .year
                )
            ]
        )

        XCTAssertEqual(presentation.planOptions.map(\.id), [
            MembershipProductID.yearly,
            MembershipProductID.monthly
        ])
        XCTAssertEqual(presentation.defaultPlanID, MembershipProductID.yearly)

        let annual = try XCTUnwrap(presentation.planOptions.first)
        XCTAssertEqual(annual.detail, "$2.50 per month when billed annually.")
        XCTAssertEqual(annual.valueBadge, "Save 50%")
        XCTAssertTrue(annual.isRecommended)
    }

    func testCatalogOmitsSavingsWhenComparisonWouldMislead() throws {
        let mismatchedCurrency = MembershipCatalogPresentation(
            storeProducts: [
                makeStoreProduct(
                    id: MembershipProductID.monthly,
                    price: "4.99",
                    displayPrice: "$4.99",
                    billingPeriod: .month
                ),
                makeStoreProduct(
                    id: MembershipProductID.yearly,
                    price: "29.99",
                    displayPrice: "€29.99",
                    currencyCode: "EUR",
                    billingPeriod: .year
                )
            ]
        )
        let noDiscount = MembershipCatalogPresentation(
            storeProducts: [
                makeStoreProduct(
                    id: MembershipProductID.monthly,
                    price: "4.99",
                    displayPrice: "$4.99",
                    billingPeriod: .month
                ),
                makeStoreProduct(
                    id: MembershipProductID.yearly,
                    price: "59.88",
                    displayPrice: "$59.88",
                    billingPeriod: .year
                )
            ]
        )

        for presentation in [mismatchedCurrency, noDiscount] {
            XCTAssertEqual(presentation.defaultPlanID, MembershipProductID.monthly)
            let annual = try XCTUnwrap(
                presentation.planOptions.first { $0.id == MembershipProductID.yearly }
            )
            XCTAssertNil(annual.valueBadge)
            XCTAssertFalse(annual.isRecommended)
            XCTAssertEqual(
                annual.detail,
                "Billed annually through Apple for uninterrupted practice."
            )
        }
    }

    func testCatalogRejectsMislabeledPeriodsAndPreservesValidSelection() {
        let presentation = MembershipCatalogPresentation(
            storeProducts: [
                makeStoreProduct(
                    id: MembershipProductID.monthly,
                    price: "4.99",
                    displayPrice: "$4.99",
                    billingPeriod: .year
                ),
                makeStoreProduct(
                    id: MembershipProductID.yearly,
                    price: "29.99",
                    displayPrice: "$29.99",
                    billingPeriod: .year
                )
            ]
        )

        XCTAssertEqual(presentation.planOptions.map(\.id), [MembershipProductID.yearly])
        XCTAssertEqual(presentation.defaultPlanID, MembershipProductID.yearly)
        XCTAssertEqual(
            presentation.resolvedSelection(currentID: MembershipProductID.yearly),
            MembershipProductID.yearly
        )
        XCTAssertEqual(
            presentation.resolvedSelection(currentID: MembershipProductID.monthly),
            MembershipProductID.yearly
        )
    }

    private func localSubscriptions() throws -> [StoreKitSubscription] {
        let url = try XCTUnwrap(
            Bundle(for: StoreKitPaymentTests.self).url(forResource: "CheckpointProducts", withExtension: "storekit")
        )
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(StoreKitConfiguration.self, from: data)

        return config.subscriptionGroups.flatMap(\.subscriptions)
    }

    private func makeStoreProduct(
        id: String,
        price: String,
        displayPrice: String,
        currencyCode: String = "USD",
        billingPeriod: MembershipBillingPeriod
    ) -> MembershipStoreProduct {
        MembershipStoreProduct(
            id: id,
            price: Decimal(string: price)!,
            displayPrice: displayPrice,
            currencyCode: currencyCode,
            locale: Locale(identifier: "en_US"),
            billingPeriod: billingPeriod
        )
    }
}

// MARK: - StoreKit decoding fixtures

private struct StoreKitConfiguration: Decodable {
    var subscriptionGroups: [StoreKitSubscriptionGroup]
}

private struct StoreKitSubscriptionGroup: Decodable {
    var subscriptions: [StoreKitSubscription]
}

private struct StoreKitSubscription: Decodable {
    var productID: String
    var displayPrice: String
    var recurringSubscriptionPeriod: String
}
