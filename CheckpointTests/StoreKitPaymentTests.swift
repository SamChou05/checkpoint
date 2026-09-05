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
        XCTAssertEqual(annual.valueBadge, "Save 49%")
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

    func testPendingCheckoutDisablesRepeatPurchaseAndUsesAwaitingApprovalCTA() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: .pendingApproval
        )

        XCTAssertTrue(presentation.isActionInProgress)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
        XCTAssertFalse(presentation.showsPrimaryProgress)
        XCTAssertFalse(presentation.isRestoreActionDisabled)
        XCTAssertTrue(presentation.shouldShowNoticeInPurchaseBar)
        XCTAssertEqual(presentation.buttonTitle(accessibilitySize: false), "Awaiting approval")
        XCTAssertEqual(presentation.buttonSystemImage, "clock.fill")
        XCTAssertEqual(presentation.restoreButtonTitle, "Check purchase status")
        XCTAssertEqual(
            presentation.buttonAccessibilityLabel,
            "Purchase pending App Store approval"
        )
    }

    func testAccessibleCheckoutKeepsVisibleAndVoiceOverBillingComplete() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: nil
        )

        XCTAssertEqual(
            presentation.buttonTitle(accessibilitySize: true),
            "Subscribe — $29.99 per year"
        )
        XCTAssertEqual(
            presentation.buttonTitle(accessibilitySize: false, compact: true),
            "Subscribe — $29.99"
        )
        XCTAssertEqual(
            presentation.buttonAccessibilityLabel,
            "Subscribe to Checkpoint Pro, Annual plan, $29.99 per year"
        )
        XCTAssertFalse(presentation.isPrimaryActionDisabled)
    }

    func testCatalogRecoveryCTAHasOneClearStateWithoutInlineNotice() {
        let unavailable = MembershipCheckoutPresentation(
            selectedPlan: nil,
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: .catalogUnavailable("Could not load App Store plans yet.")
        )
        let loading = MembershipCheckoutPresentation(
            selectedPlan: nil,
            isLoadingPlans: true,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: nil
        )

        XCTAssertEqual(unavailable.buttonTitle(accessibilitySize: false), "Reload App Store plans")
        XCTAssertEqual(unavailable.buttonSystemImage, "arrow.clockwise")
        XCTAssertFalse(unavailable.isPrimaryActionDisabled)
        XCTAssertFalse(unavailable.shouldShowNoticeInPurchaseBar)

        XCTAssertEqual(loading.buttonTitle(accessibilitySize: false), "Loading plans")
        XCTAssertTrue(loading.isActionInProgress)
        XCTAssertTrue(loading.isPrimaryActionDisabled)
        XCTAssertTrue(loading.showsPrimaryProgress)
        XCTAssertTrue(loading.isRestoreActionDisabled)
    }

    func testCatalogLoadingBlocksRestoreAndSelectionUntilItsNoticeResolutionFinishes() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            isLoadingPlans: true,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: nil
        )

        XCTAssertTrue(presentation.isActionInProgress)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
        XCTAssertTrue(presentation.showsPrimaryProgress)
        XCTAssertTrue(presentation.isRestoreActionDisabled)
        XCTAssertEqual(presentation.buttonTitle(accessibilitySize: false), "Refreshing prices")
        XCTAssertEqual(
            presentation.buttonAccessibilityLabel,
            "Refreshing App Store prices, in progress"
        )
    }

    @MainActor
    func testPurchaseControllerRejectsOverlappingCatalogAndRestoreOperations() async {
        let loadingController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            initialStoreOperation: .loadingProducts
        )
        let restoreStarted = await loadingController.restorePurchases()

        XCTAssertFalse(restoreStarted)
        XCTAssertTrue(loadingController.isLoadingProducts)
        XCTAssertFalse(loadingController.isRestoringPurchases)

        let restoringController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            initialStoreOperation: .restoringPurchases
        )
        await restoringController.loadProducts()

        XCTAssertTrue(restoringController.isRestoringPurchases)
        XCTAssertFalse(restoringController.isLoadingProducts)
    }

    func testPendingApprovalSurvivesCatalogReloadUntilEntitlementUnlocks() {
        let afterSuccessfulCatalogLoad = MembershipPurchaseNotice.resolvingCatalogLoad(
            current: .pendingApproval,
            catalogNotice: nil
        )
        let afterFailedCatalogLoad = MembershipPurchaseNotice.resolvingCatalogLoad(
            current: afterSuccessfulCatalogLoad,
            catalogNotice: .catalogUnavailable("Could not load App Store plans yet.")
        )
        let whileStillLocked = MembershipPurchaseNotice.resolvingEntitlementRefresh(
            current: afterFailedCatalogLoad,
            isUnlocked: false
        )
        let afterApproval = MembershipPurchaseNotice.resolvingEntitlementRefresh(
            current: whileStillLocked,
            isUnlocked: true
        )

        XCTAssertEqual(afterSuccessfulCatalogLoad, .pendingApproval)
        XCTAssertEqual(afterFailedCatalogLoad, .pendingApproval)
        XCTAssertEqual(whileStillLocked, .pendingApproval)
        XCTAssertNil(afterApproval)
    }

    func testCatalogReloadReplacesNonpendingNoticeWithCurrentCatalogState() {
        let unavailable = MembershipPurchaseNotice.resolvingCatalogLoad(
            current: .failure("A previous purchase failed."),
            catalogNotice: .catalogUnavailable("Could not load App Store plans yet.")
        )
        let recovered = MembershipPurchaseNotice.resolvingCatalogLoad(
            current: unavailable,
            catalogNotice: nil
        )

        XCTAssertEqual(
            unavailable,
            .catalogUnavailable("Could not load App Store plans yet.")
        )
        XCTAssertNil(recovered)
    }

    func testOnlyActionableNoCatalogNoticesRenderSeparately() {
        XCTAssertFalse(MembershipPurchaseNotice.pendingApproval.shouldDisplayWithoutSelectedPlan)
        XCTAssertFalse(
            MembershipPurchaseNotice.catalogUnavailable("Catalog unavailable.")
                .shouldDisplayWithoutSelectedPlan
        )
        XCTAssertTrue(
            MembershipPurchaseNotice.failure("Restore failed.")
                .shouldDisplayWithoutSelectedPlan
        )
        XCTAssertTrue(
            MembershipPurchaseNotice.information("No subscription found.")
                .shouldDisplayWithoutSelectedPlan
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

    private func makeAnnualPlanOption() -> MembershipPlanOption {
        MembershipPlanOption(
            id: MembershipProductID.yearly,
            title: "Annual",
            displayPrice: "$29.99",
            cadence: "per year",
            detail: "$2.50 per month when billed annually.",
            valueBadge: "Save 49%",
            isRecommended: true
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
