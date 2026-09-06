import Foundation
import XCTest
@testable import Checkpoint

final class StoreKitPaymentTests: XCTestCase {
    // MARK: - Entitlement configuration

    @MainActor
    func testDebugMembershipEntitlementDefaultsOff() {
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: nil
        )

        XCTAssertFalse(controller.isMembershipUnlocked)
    }

    @MainActor
    func testDebugMembershipEntitlementCanBeExplicitlyEnabled() async {
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: true,
            pendingPurchaseDefaults: nil
        )
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
        XCTAssertEqual(presentation.defaultPlanOption, annual)
        XCTAssertEqual(annual.chargeSummary, "Annual · $29.99 per year")
        XCTAssertEqual(annual.detail, "$2.50 per month when billed annually.")
        XCTAssertEqual(annual.compactDetail, "$2.50/mo · billed annually")
        XCTAssertEqual(annual.valueBadge, "Save 49%")
        XCTAssertTrue(annual.isRecommended)

        let monthly = try XCTUnwrap(
            presentation.planOptions.first { $0.id == MembershipProductID.monthly }
        )
        XCTAssertEqual(monthly.compactDetail, "Billed monthly through Apple")
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
            let monthly = try XCTUnwrap(
                presentation.planOptions.first { $0.id == MembershipProductID.monthly }
            )
            XCTAssertEqual(presentation.defaultPlanOption, monthly)
            let annual = try XCTUnwrap(
                presentation.planOptions.first { $0.id == MembershipProductID.yearly }
            )
            XCTAssertNil(annual.valueBadge)
            XCTAssertFalse(annual.isRecommended)
            XCTAssertEqual(
                annual.detail,
                "Billed annually through Apple for uninterrupted practice."
            )
            XCTAssertEqual(annual.compactDetail, "Billed annually through Apple")
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

        let emptyPresentation = MembershipCatalogPresentation(storeProducts: [])
        XCTAssertNil(emptyPresentation.defaultPlanID)
        XCTAssertNil(emptyPresentation.defaultPlanOption)
    }

    func testPendingPurchasePlanWinsSelectionAndMissingPlanFallsBackSafely() throws {
        let planOptions = [
            makeAnnualPlanOption(),
            MembershipPlanOption(
                id: MembershipProductID.monthly,
                title: "Monthly",
                displayPrice: "$4.99",
                cadence: "per month",
                detail: "Flexible access, billed monthly through Apple."
            ),
        ]

        XCTAssertEqual(
            MembershipPlanSelectionResolver.resolve(
                planOptions: planOptions,
                currentID: MembershipProductID.yearly,
                pendingProductID: MembershipProductID.monthly,
                defaultID: MembershipProductID.yearly
            ),
            MembershipProductID.monthly
        )
        XCTAssertEqual(
            MembershipPlanSelectionResolver.resolve(
                planOptions: planOptions,
                currentID: nil,
                pendingProductID: "checkpoint.membership.missing",
                defaultID: MembershipProductID.yearly
            ),
            MembershipProductID.yearly
        )
        XCTAssertNil(
            MembershipPlanSelectionResolver.resolve(
                planOptions: [],
                currentID: MembershipProductID.yearly,
                pendingProductID: MembershipProductID.monthly,
                defaultID: MembershipProductID.yearly
            )
        )
    }

    func testPendingCheckoutDisablesRepeatPurchaseAndUsesAppStoreCompletionCTA() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            hasUnresolvedPurchase: true,
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: .pendingApproval
        )

        XCTAssertTrue(presentation.isActionInProgress)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
        XCTAssertFalse(presentation.showsPrimaryProgress)
        XCTAssertFalse(presentation.isSecondaryActionDisabled)
        XCTAssertTrue(presentation.shouldShowNoticeInPurchaseBar)
        XCTAssertEqual(presentation.buttonTitle(accessibilitySize: false), "Waiting for App Store")
        XCTAssertEqual(presentation.buttonSystemImage, "clock.fill")
        XCTAssertEqual(presentation.secondaryAction, .checkPurchaseStatus)
        XCTAssertEqual(presentation.secondaryButtonTitle, "Check purchase status")
        XCTAssertEqual(presentation.secondaryButtonSystemImage, "clock.arrow.circlepath")
        XCTAssertEqual(
            presentation.secondaryButtonAccessibilityLabel,
            "Check App Store purchase status"
        )
        XCTAssertEqual(
            presentation.buttonAccessibilityLabel,
            "Purchase waiting for the App Store to complete"
        )
        XCTAssertEqual(
            MembershipPurchaseNotice.pendingApproval.message,
            "Waiting for the App Store to complete this purchase."
        )
        XCTAssertEqual(
            MembershipPurchaseNotice.pendingApprovalChecked.message,
            "The App Store is still completing this purchase. Pro unlocks automatically when it finishes."
        )
    }

    func testAccessibleCheckoutKeepsVisibleAndVoiceOverBillingComplete() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            hasUnresolvedPurchase: false,
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
            hasUnresolvedPurchase: false,
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: .catalogUnavailable("Could not load App Store plans yet.")
        )
        let loading = MembershipCheckoutPresentation(
            selectedPlan: nil,
            hasUnresolvedPurchase: false,
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
        XCTAssertTrue(loading.isSecondaryActionDisabled)
    }

    func testCatalogLoadingBlocksRestoreAndSelectionUntilItsNoticeResolutionFinishes() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            hasUnresolvedPurchase: false,
            isLoadingPlans: true,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: nil
        )

        XCTAssertTrue(presentation.isActionInProgress)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
        XCTAssertTrue(presentation.showsPrimaryProgress)
        XCTAssertTrue(presentation.isSecondaryActionDisabled)
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
            initialStoreOperation: .loadingProducts,
            pendingPurchaseDefaults: nil
        )
        let restoreStarted = await loadingController.restorePurchases()

        XCTAssertFalse(restoreStarted)
        XCTAssertTrue(loadingController.isLoadingProducts)
        XCTAssertFalse(loadingController.isRestoringPurchases)

        let restoringController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            initialStoreOperation: .restoringPurchases,
            pendingPurchaseDefaults: nil
        )
        await restoringController.loadProducts()

        XCTAssertTrue(restoringController.isRestoringPurchases)
        XCTAssertFalse(restoringController.isLoadingProducts)

        let checkingController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            initialStoreOperation: .checkingPurchaseStatus,
            pendingPurchaseDefaults: nil
        )
        let overlappingRestoreStarted = await checkingController.restorePurchases()

        XCTAssertFalse(overlappingRestoreStarted)
        XCTAssertTrue(checkingController.isCheckingPurchaseStatus)
        XCTAssertFalse(checkingController.isRestoringPurchases)
    }

    @MainActor
    func testCheckoutActivityIsUnresolvedBeforeStoreKitCreatesAPendingRecord() {
        let checkoutOperations: [MembershipStoreOperation] = [
            .purchasing(productID: MembershipProductID.monthly),
            .restoringPurchases,
            .checkingPurchaseStatus,
        ]

        for operation in checkoutOperations {
            let controller = PurchaseController(
                grantsDebugTesterEntitlement: false,
                initialStoreOperation: operation,
                pendingPurchaseDefaults: nil
            )

            XCTAssertTrue(controller.isCheckoutActionInProgress)
            XCTAssertTrue(controller.hasUnresolvedCheckout)
            XCTAssertFalse(controller.hasUnresolvedPurchase)
        }

        let catalogController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            initialStoreOperation: .loadingProducts,
            pendingPurchaseDefaults: nil
        )
        XCTAssertFalse(catalogController.isCheckoutActionInProgress)
        XCTAssertFalse(catalogController.hasUnresolvedCheckout)
    }

    func testCheckingPurchaseStatusPresentationOwnsSecondaryProgress() {
        let presentation = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            hasUnresolvedPurchase: true,
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isCheckingPurchaseStatus: true,
            isPurchasing: false,
            notice: .pendingApproval
        )

        XCTAssertEqual(presentation.secondaryAction, .checkPurchaseStatus)
        XCTAssertEqual(presentation.secondaryButtonTitle, "Checking purchase status")
        XCTAssertEqual(
            presentation.secondaryButtonAccessibilityLabel,
            "Checking App Store purchase status, in progress"
        )
        XCTAssertTrue(presentation.showsSecondaryProgress)
        XCTAssertTrue(presentation.isSecondaryActionDisabled)
    }

    func testActivePlanResolverIgnoresUnsupportedAndUpgradedEntitlements() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activeAnnual = makeEntitlement(
            transactionID: 10,
            productID: MembershipProductID.yearly,
            purchaseDate: now
        )
        let snapshot = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [
                    makeEntitlement(
                        transactionID: 12,
                        productID: "checkpoint.membership.unsupported",
                        purchaseDate: now.addingTimeInterval(200)
                    ),
                    makeEntitlement(
                        transactionID: 11,
                        productID: MembershipProductID.monthly,
                        purchaseDate: now.addingTimeInterval(100),
                        isUpgraded: true
                    ),
                    activeAnnual,
                ]
            )
        )

        XCTAssertEqual(snapshot.transactionID, 10)
        XCTAssertEqual(snapshot.planKind, .annual)
        XCTAssertEqual(snapshot.renewalDisposition, .active)
    }

    func testActivePlanResolverUsesNewestPurchaseDateThenStablePlanOrder() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let newest = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [
                    makeEntitlement(
                        transactionID: 1,
                        productID: MembershipProductID.monthly,
                        purchaseDate: now
                    ),
                    makeEntitlement(
                        transactionID: 2,
                        productID: MembershipProductID.yearly,
                        purchaseDate: now.addingTimeInterval(1)
                    ),
                ]
            )
        )
        let stableTie = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [
                    makeEntitlement(
                        transactionID: 3,
                        productID: MembershipProductID.yearly,
                        purchaseDate: now
                    ),
                    makeEntitlement(
                        transactionID: 4,
                        productID: MembershipProductID.monthly,
                        purchaseDate: now
                    ),
                ]
            )
        )

        XCTAssertEqual(newest.planKind, .annual)
        XCTAssertEqual(stableTie.planKind, .monthly)
    }

    func testActivePlanResolverUsesOnlyMatchingVerifiedRenewalMetadata() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entitlement = makeEntitlement(
            transactionID: 42,
            productID: MembershipProductID.yearly,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(86_400)
        )
        let matchingRenewal = MembershipRenewalRecord(
            currentProductID: MembershipProductID.yearly,
            willAutoRenew: true,
            autoRenewPreference: MembershipProductID.monthly,
            gracePeriodExpirationDate: nil
        )
        let scheduledChange = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [entitlement],
                statuses: [
                    MembershipSubscriptionStatusRecord(
                        transactionID: 42,
                        productID: MembershipProductID.yearly,
                        state: .subscribed,
                        renewal: matchingRenewal
                    )
                ]
            )
        )
        let stalePreference = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [entitlement],
                statuses: [
                    MembershipSubscriptionStatusRecord(
                        transactionID: 42,
                        productID: MembershipProductID.yearly,
                        state: .subscribed,
                        renewal: MembershipRenewalRecord(
                            currentProductID: MembershipProductID.yearly,
                            willAutoRenew: false,
                            autoRenewPreference: MembershipProductID.monthly,
                            gracePeriodExpirationDate: nil
                        )
                    )
                ]
            )
        )
        let mismatchedRenewal = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [entitlement],
                statuses: [
                    MembershipSubscriptionStatusRecord(
                        transactionID: 42,
                        productID: MembershipProductID.yearly,
                        state: .subscribed,
                        renewal: MembershipRenewalRecord(
                            currentProductID: MembershipProductID.monthly,
                            willAutoRenew: true,
                            autoRenewPreference: nil,
                            gracePeriodExpirationDate: nil
                        )
                    )
                ]
            )
        )

        XCTAssertEqual(scheduledChange.renewalDisposition, .changesTo(.monthly))
        XCTAssertEqual(stalePreference.renewalDisposition, .ends)
        XCTAssertEqual(mismatchedRenewal.renewalDisposition, .active)
    }

    func testActivePlanResolverCarriesGraceAndFamilySharingTruth() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let graceEnd = now.addingTimeInterval(86_400)
        let entitlement = makeEntitlement(
            transactionID: 48,
            productID: MembershipProductID.monthly,
            purchaseDate: now,
            expirationDate: now.addingTimeInterval(-60),
            ownership: .familyShared
        )
        let snapshot = try XCTUnwrap(
            MembershipActivePlanResolver.resolve(
                entitlements: [entitlement],
                statuses: [
                    MembershipSubscriptionStatusRecord(
                        transactionID: 48,
                        productID: MembershipProductID.monthly,
                        state: .inGracePeriod,
                        renewal: MembershipRenewalRecord(
                            currentProductID: MembershipProductID.monthly,
                            willAutoRenew: true,
                            autoRenewPreference: nil,
                            gracePeriodExpirationDate: graceEnd
                        )
                    )
                ]
            )
        )

        XCTAssertEqual(snapshot.renewalDisposition, .gracePeriod(until: graceEnd))
        XCTAssertEqual(snapshot.ownership, .familyShared)
    }

    func testInactiveSubscriptionStatusCannotRevokeVerifiedCurrentEntitlement() throws {
        let entitlement = makeEntitlement(
            transactionID: 49,
            productID: MembershipProductID.monthly,
            purchaseDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        for state in [
            MembershipSubscriptionState.expired,
            .inBillingRetryPeriod,
            .revoked,
            .unknown,
        ] {
            let snapshot = try XCTUnwrap(
                MembershipActivePlanResolver.resolve(
                    entitlements: [entitlement],
                    statuses: [
                        MembershipSubscriptionStatusRecord(
                            transactionID: entitlement.transactionID,
                            productID: entitlement.productID,
                            state: state,
                            renewal: nil
                        )
                    ]
                )
            )

            XCTAssertEqual(snapshot.renewalDisposition, .active)
        }
    }

    @MainActor
    func testInitialPlanSnapshotIsPresentationOnlyAndDoesNotGrantAccess() {
        let snapshot = MembershipActivePlanSnapshot(
            transactionID: 1,
            productID: MembershipProductID.yearly,
            planKind: .annual,
            subscriptionGroupID: "checkpoint.pro",
            purchaseDate: Date(timeIntervalSince1970: 1_800_000_000),
            currentPeriodEnd: nil,
            renewalDisposition: .active,
            ownership: .purchased
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            initialActivePlanSnapshot: snapshot,
            pendingPurchaseDefaults: nil
        )

        XCTAssertFalse(controller.isMembershipUnlocked)
        XCTAssertTrue(controller.purchasedProductIDs.isEmpty)
        XCTAssertEqual(controller.activePlanSnapshot, snapshot)
    }

    @MainActor
    func testPendingStatusCheckReadsEntitlementsWithoutSynchronizingAndKeepsPendingNotice() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let client = MembershipStoreClientSpy(entitlementResponses: [[]])
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil,
            currentDate: { now }
        )
        controller.recordPendingPurchase(
            productID: MembershipProductID.monthly,
            initiatedAt: now
        )
        controller.purchaseNotice = .pendingApproval

        let unlocked = await controller.checkPurchaseStatus()
        let events = await client.recordedEvents()

        XCTAssertFalse(unlocked)
        XCTAssertEqual(controller.purchaseNotice, .pendingApprovalChecked)
        XCTAssertFalse(controller.isCheckingPurchaseStatus)
        XCTAssertEqual(events, [.readEntitlements])
    }

    @MainActor
    func testPendingPurchaseMarkerRestoresExactPlanAcrossRelaunch() throws {
        let suiteName = "StoreKitPaymentTests.pending-relaunch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let initiatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let persistence = MembershipPendingPurchasePersistence(defaults: defaults)
        persistence.save(
            MembershipPendingPurchaseRecord(
                productID: MembershipProductID.monthly,
                initiatedAt: initiatedAt
            )
        )

        let relaunched = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: defaults,
            currentDate: { initiatedAt.addingTimeInterval(60) }
        )

        XCTAssertEqual(relaunched.pendingPurchaseProductID, MembershipProductID.monthly)
        XCTAssertEqual(relaunched.purchaseNotice, .pendingApproval)
    }

    @MainActor
    func testLongRunningPendingPurchaseRetainsRecoveryEvidenceAcrossRelaunches() throws {
        let suiteName = "StoreKitPaymentTests.pending-long-running.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let initiatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let persistence = MembershipPendingPurchasePersistence(defaults: defaults)
        let record = MembershipPendingPurchaseRecord(
            productID: MembershipProductID.yearly,
            initiatedAt: initiatedAt
        )
        persistence.save(record)

        let stillPending = persistence.load(
            at: initiatedAt.addingTimeInterval(
                MembershipPendingPurchasePersistence.defaultLongRunningInterval - 1
            )
        )
        XCTAssertEqual(stillPending, .recent(record))

        let longRunningDate = initiatedAt.addingTimeInterval(
            MembershipPendingPurchasePersistence.defaultLongRunningInterval
        )
        XCTAssertEqual(
            persistence.load(at: longRunningDate),
            .longRunning(record)
        )

        let relaunched = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: defaults,
            currentDate: { longRunningDate }
        )
        let checkout = MembershipCheckoutPresentation(
            selectedPlan: makeAnnualPlanOption(),
            hasUnresolvedPurchase: relaunched.hasUnresolvedPurchase,
            isLoadingPlans: false,
            isRestoringPurchases: false,
            isPurchasing: false,
            notice: relaunched.purchaseNotice
        )

        let relaunchedAgain = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: defaults,
            currentDate: { longRunningDate.addingTimeInterval(60) }
        )

        XCTAssertEqual(relaunched.pendingPurchaseProductID, MembershipProductID.yearly)
        XCTAssertTrue(relaunched.hasUnresolvedPurchase)
        XCTAssertEqual(relaunched.purchaseNotice, .previousPurchaseUnconfirmed)
        XCTAssertNotNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))
        XCTAssertFalse(checkout.isPrimaryActionDisabled)
        XCTAssertEqual(
            checkout.buttonTitle(accessibilitySize: false),
            "Start another purchase — $29.99 per year"
        )
        XCTAssertEqual(checkout.secondaryAction, .checkPurchaseStatus)
        XCTAssertEqual(
            relaunched.purchaseNotice?.message,
            "The App Store still hasn’t completed the earlier purchase, and it may finish later. Check its status before starting another purchase."
        )
        XCTAssertFalse(relaunched.purchaseNotice?.message.contains("declined") == true)
        XCTAssertEqual(relaunchedAgain.pendingPurchaseProductID, MembershipProductID.yearly)
        XCTAssertEqual(relaunchedAgain.purchaseNotice, .previousPurchaseUnconfirmed)
    }

    @MainActor
    func testExplicitLongRunningRetryPreservesRecoveryMarkerUntilStoreKitResolves() throws {
        let suiteName = "StoreKitPaymentTests.pending-explicit-retry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let initiatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var now = initiatedAt.addingTimeInterval(60)
        let recentController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: defaults,
            currentDate: { now }
        )
        recentController.recordPendingPurchase(
            productID: MembershipProductID.monthly,
            initiatedAt: initiatedAt
        )

        XCTAssertFalse(recentController.prepareForPurchaseAttempt())
        XCTAssertEqual(recentController.pendingPurchaseProductID, MembershipProductID.monthly)
        XCTAssertNotNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))

        now = initiatedAt.addingTimeInterval(
            MembershipPendingPurchasePersistence.defaultLongRunningInterval
        )
        let longRunningController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: defaults,
            currentDate: { now }
        )

        XCTAssertEqual(longRunningController.purchaseNotice, .previousPurchaseUnconfirmed)
        XCTAssertTrue(longRunningController.prepareForPurchaseAttempt())
        XCTAssertEqual(
            longRunningController.pendingPurchaseProductID,
            MembershipProductID.monthly
        )
        XCTAssertEqual(
            longRunningController.purchaseNotice,
            .previousPurchaseUnconfirmed
        )
        XCTAssertNotNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))

        longRunningController.purchaseNotice = nil
        longRunningController.resolveUnsuccessfulPurchaseAttempt(notice: nil)
        XCTAssertEqual(
            longRunningController.purchaseNotice,
            .previousPurchaseUnconfirmed,
            "Canceling a replacement attempt must restore the earlier recovery state."
        )

        longRunningController.purchaseNotice = nil
        longRunningController.resolveUnsuccessfulPurchaseAttempt(
            notice: .failure("Replacement attempt failed.")
        )
        XCTAssertEqual(
            longRunningController.purchaseNotice,
            .previousPurchaseUnconfirmed,
            "A replacement failure cannot disprove the earlier StoreKit request."
        )
        XCTAssertEqual(
            longRunningController.pendingPurchaseProductID,
            MembershipProductID.monthly
        )
        XCTAssertNotNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))
    }

    @MainActor
    func testLateApprovalStillUnlocksAndClearsLongRunningMarker() async throws {
        let suiteName = "StoreKitPaymentTests.pending-late-approval.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let initiatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        MembershipPendingPurchasePersistence(defaults: defaults).save(
            MembershipPendingPurchaseRecord(
                productID: MembershipProductID.yearly,
                initiatedAt: initiatedAt
            )
        )
        let entitlement = makeEntitlement(
            transactionID: 80,
            productID: MembershipProductID.yearly,
            purchaseDate: initiatedAt.addingTimeInterval(30)
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: MembershipStoreClientSpy(entitlementResponses: [[entitlement]]),
            pendingPurchaseDefaults: defaults,
            currentDate: {
                initiatedAt.addingTimeInterval(
                    MembershipPendingPurchasePersistence.defaultLongRunningInterval + 60
                )
            }
        )

        let unlocked = await controller.refreshEntitlements()

        XCTAssertTrue(unlocked)
        XCTAssertTrue(controller.isMembershipUnlocked)
        XCTAssertNil(controller.pendingPurchaseProductID)
        XCTAssertNil(controller.purchaseNotice)
        XCTAssertNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))
    }

    @MainActor
    func testInvalidPendingPurchaseMarkersArePrunedWithoutBlockingCheckout() throws {
        let suiteName = "StoreKitPaymentTests.pending-invalid.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistence = MembershipPendingPurchasePersistence(defaults: defaults)

        defaults.set(Data([0x00, 0x01]), forKey: MembershipPendingPurchasePersistence.storageKey)
        XCTAssertEqual(persistence.load(at: now), .none)
        XCTAssertNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))

        let unsupported = MembershipPendingPurchaseRecord(
            productID: "checkpoint.membership.unsupported",
            initiatedAt: now
        )
        defaults.set(
            try JSONEncoder().encode(unsupported),
            forKey: MembershipPendingPurchasePersistence.storageKey
        )
        XCTAssertEqual(persistence.load(at: now), .none)
        XCTAssertNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))

        let future = MembershipPendingPurchaseRecord(
            productID: MembershipProductID.monthly,
            initiatedAt: now.addingTimeInterval(1)
        )
        defaults.set(
            try JSONEncoder().encode(future),
            forKey: MembershipPendingPurchasePersistence.storageKey
        )
        XCTAssertEqual(persistence.load(at: now), .none)
        XCTAssertNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))
    }

    @MainActor
    func testPendingStatusCheckKeepsPersistedMarkerButCheckedCopyIsSessionOnly() async throws {
        let suiteName = "StoreKitPaymentTests.pending-check.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let initiatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let persistence = MembershipPendingPurchasePersistence(defaults: defaults)
        persistence.save(
            MembershipPendingPurchaseRecord(
                productID: MembershipProductID.monthly,
                initiatedAt: initiatedAt
            )
        )
        let client = MembershipStoreClientSpy(entitlementResponses: [[]])
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: defaults,
            currentDate: { initiatedAt.addingTimeInterval(60) }
        )

        let unlocked = await controller.checkPurchaseStatus()
        let events = await client.recordedEvents()
        let relaunched = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: defaults,
            currentDate: { initiatedAt.addingTimeInterval(120) }
        )

        XCTAssertFalse(unlocked)
        XCTAssertEqual(controller.purchaseNotice, .pendingApprovalChecked)
        XCTAssertEqual(controller.pendingPurchaseProductID, MembershipProductID.monthly)
        XCTAssertEqual(events, [.readEntitlements])
        XCTAssertEqual(relaunched.purchaseNotice, .pendingApproval)
        XCTAssertEqual(relaunched.pendingPurchaseProductID, MembershipProductID.monthly)
    }

    @MainActor
    func testVerifiedEntitlementClearsPersistedPendingPurchaseMarker() async throws {
        let suiteName = "StoreKitPaymentTests.pending-approved.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let initiatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        MembershipPendingPurchasePersistence(defaults: defaults).save(
            MembershipPendingPurchaseRecord(
                productID: MembershipProductID.monthly,
                initiatedAt: initiatedAt
            )
        )
        let entitlement = makeEntitlement(
            transactionID: 76,
            productID: MembershipProductID.monthly,
            purchaseDate: initiatedAt.addingTimeInterval(30)
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: MembershipStoreClientSpy(entitlementResponses: [[entitlement]]),
            pendingPurchaseDefaults: defaults,
            currentDate: { initiatedAt.addingTimeInterval(60) }
        )

        let unlocked = await controller.refreshEntitlements()

        XCTAssertTrue(unlocked)
        XCTAssertNil(controller.pendingPurchaseProductID)
        XCTAssertNil(controller.purchaseNotice)
        XCTAssertNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))
    }

    @MainActor
    func testForegroundEntitlementRefreshAgesPendingPresentationWithoutDiscardingMarker() async {
        let initiatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var now = initiatedAt
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: MembershipStoreClientSpy(entitlementResponses: [[]]),
            pendingPurchaseDefaults: nil,
            currentDate: { now }
        )
        controller.recordPendingPurchase(
            productID: MembershipProductID.yearly,
            initiatedAt: initiatedAt
        )
        now = initiatedAt.addingTimeInterval(
            MembershipPendingPurchasePersistence.defaultLongRunningInterval
        )

        let unlocked = await controller.refreshEntitlements()

        XCTAssertFalse(unlocked)
        XCTAssertEqual(controller.pendingPurchaseProductID, MembershipProductID.yearly)
        XCTAssertEqual(controller.purchaseNotice, .previousPurchaseUnconfirmed)
    }

    @MainActor
    func testDebugEntitlementClearsPersistedPendingPurchaseMarker() async throws {
        let suiteName = "StoreKitPaymentTests.pending-debug.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        MembershipPendingPurchasePersistence(defaults: defaults).save(
            MembershipPendingPurchaseRecord(
                productID: MembershipProductID.yearly,
                initiatedAt: now
            )
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: true,
            pendingPurchaseDefaults: defaults,
            currentDate: { now }
        )

        let unlocked = await controller.refreshEntitlements()

        XCTAssertTrue(unlocked)
        XCTAssertNil(controller.pendingPurchaseProductID)
        XCTAssertNil(controller.purchaseNotice)
        XCTAssertNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))
    }

    @MainActor
    func testExplicitDataEraseClearsPendingPurchaseStateAndPersistence() throws {
        let suiteName = "StoreKitPaymentTests.pending-erase.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: defaults,
            currentDate: { now }
        )
        controller.recordPendingPurchase(
            productID: MembershipProductID.monthly,
            initiatedAt: now
        )

        controller.clearPendingPurchaseState()
        let relaunched = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: defaults,
            currentDate: { now }
        )

        XCTAssertNil(controller.pendingPurchaseProductID)
        XCTAssertNil(controller.purchaseNotice)
        XCTAssertNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))
        XCTAssertNil(relaunched.pendingPurchaseProductID)
        XCTAssertNil(relaunched.purchaseNotice)
    }

    @MainActor
    func testSupersededEntitlementRefreshCannotClearNewPersistedPendingPurchaseMarker() async throws {
        let suiteName = "StoreKitPaymentTests.pending-refresh-race.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activeAnnual = makeEntitlement(
            transactionID: 75,
            productID: MembershipProductID.yearly,
            purchaseDate: now
        )
        let client = GatedMembershipStoreClient()
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: defaults,
            currentDate: { now }
        )

        let olderRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        await client.waitForRequestCount(1)
        controller.recordPendingPurchase(
            productID: MembershipProductID.monthly,
            initiatedAt: now
        )
        let newerRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        await client.waitForRequestCount(2)

        await client.resumeRequest(1, with: [])
        _ = await newerRefresh.value
        await client.resumeRequest(0, with: [activeAnnual])
        _ = await olderRefresh.value
        let relaunched = PurchaseController(
            grantsDebugTesterEntitlement: false,
            pendingPurchaseDefaults: defaults,
            currentDate: { now.addingTimeInterval(60) }
        )

        XCTAssertEqual(controller.pendingPurchaseProductID, MembershipProductID.monthly)
        XCTAssertEqual(controller.purchaseNotice, .pendingApproval)
        XCTAssertFalse(controller.isMembershipUnlocked)
        XCTAssertNotNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))
        XCTAssertEqual(relaunched.pendingPurchaseProductID, MembershipProductID.monthly)
        XCTAssertEqual(relaunched.purchaseNotice, .pendingApproval)
    }

    @MainActor
    func testSupersededPendingStatusCheckCannotOverwriteNewerVerifiedEntitlement() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activeAnnual = makeEntitlement(
            transactionID: 82,
            productID: MembershipProductID.yearly,
            purchaseDate: now
        )
        let client = GatedMembershipStoreClient()
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil,
            currentDate: { now }
        )
        controller.recordPendingPurchase(
            productID: MembershipProductID.monthly,
            initiatedAt: now
        )

        let olderCheck = Task { @MainActor in
            await controller.checkPurchaseStatus()
        }
        await client.waitForRequestCount(1)
        let newerRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        await client.waitForRequestCount(2)

        await client.resumeRequest(1, with: [activeAnnual])
        let refreshed = await newerRefresh.value
        await client.resumeRequest(0, with: [])
        let checked = await olderCheck.value

        XCTAssertTrue(refreshed)
        XCTAssertFalse(checked)
        XCTAssertTrue(controller.isMembershipUnlocked)
        XCTAssertEqual(controller.activePlanSnapshot?.transactionID, activeAnnual.transactionID)
        XCTAssertNil(controller.pendingPurchaseProductID)
        XCTAssertNil(controller.purchaseNotice)
        XCTAssertFalse(controller.isCheckingPurchaseStatus)
    }

    @MainActor
    func testPendingStatusCheckClearsPendingAndPublishesActiveAnnualSnapshot() async throws {
        let entitlement = makeEntitlement(
            transactionID: 77,
            productID: MembershipProductID.yearly,
            purchaseDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let client = MembershipStoreClientSpy(entitlementResponses: [[entitlement]])
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil
        )
        controller.purchaseNotice = .pendingApproval
        var publishedEntitlement = false
        controller.onMembershipEntitlementChange = { publishedEntitlement = $0 }

        let unlocked = await controller.checkPurchaseStatus()
        let events = await client.recordedEvents()

        XCTAssertTrue(unlocked)
        XCTAssertTrue(publishedEntitlement)
        XCTAssertNil(controller.purchaseNotice)
        XCTAssertEqual(controller.activePlanSnapshot?.planKind, .annual)
        XCTAssertEqual(events, [.readEntitlements])
    }

    @MainActor
    func testEntitlementRefreshEnrichesSnapshotWithoutChangingAccessAuthority() async {
        let groupID = "checkpoint.pro"
        let entitlement = makeEntitlement(
            transactionID: 78,
            productID: MembershipProductID.yearly,
            purchaseDate: Date(timeIntervalSince1970: 1_800_000_000),
            expirationDate: Date(timeIntervalSince1970: 1_900_000_000),
            subscriptionGroupID: groupID
        )
        let client = MembershipStoreClientSpy(
            entitlementResponses: [[entitlement]],
            statuses: [
                MembershipSubscriptionStatusRecord(
                    transactionID: entitlement.transactionID,
                    productID: entitlement.productID,
                    state: .subscribed,
                    renewal: MembershipRenewalRecord(
                        currentProductID: entitlement.productID,
                        willAutoRenew: true,
                        autoRenewPreference: nil,
                        gracePeriodExpirationDate: nil
                    )
                )
            ]
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil
        )

        let unlocked = await controller.refreshEntitlements()
        let events = await client.recordedEvents()

        XCTAssertTrue(unlocked)
        XCTAssertEqual(controller.activePlanSnapshot?.renewalDisposition, .renews)
        XCTAssertEqual(events, [.readEntitlements, .readStatuses(groupID)])
    }

    @MainActor
    func testStatusLookupFailurePreservesVerifiedBaseSnapshot() async {
        let groupID = "checkpoint.pro"
        let entitlement = makeEntitlement(
            transactionID: 79,
            productID: MembershipProductID.monthly,
            purchaseDate: Date(timeIntervalSince1970: 1_800_000_000),
            subscriptionGroupID: groupID
        )
        let client = MembershipStoreClientSpy(
            entitlementResponses: [[entitlement]],
            statusLookupFails: true
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil
        )

        let unlocked = await controller.refreshEntitlements()

        XCTAssertTrue(unlocked)
        XCTAssertEqual(controller.activePlanSnapshot?.transactionID, entitlement.transactionID)
        XCTAssertEqual(controller.activePlanSnapshot?.renewalDisposition, .active)
    }

    @MainActor
    func testRestoreSynchronizesBeforeReadingAndReportsNoSubscription() async {
        let client = MembershipStoreClientSpy(entitlementResponses: [[]])
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil
        )

        let unlocked = await controller.restorePurchases()
        let events = await client.recordedEvents()

        XCTAssertFalse(unlocked)
        XCTAssertEqual(
            controller.purchaseNotice,
            .information("No active Checkpoint Pro subscription was found.")
        )
        XCTAssertEqual(events, [.synchronize, .readEntitlements])
    }

    @MainActor
    func testEmptyRestoreCannotOverwritePendingPurchaseMarker() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let client = MembershipStoreClientSpy(entitlementResponses: [[]])
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil,
            currentDate: { now }
        )
        controller.recordPendingPurchase(
            productID: MembershipProductID.monthly,
            initiatedAt: now
        )

        let unlocked = await controller.restorePurchases()
        let events = await client.recordedEvents()

        XCTAssertFalse(unlocked)
        XCTAssertEqual(controller.pendingPurchaseProductID, MembershipProductID.monthly)
        XCTAssertEqual(controller.purchaseNotice, .pendingApproval)
        XCTAssertEqual(events, [.synchronize, .readEntitlements])
    }

    @MainActor
    func testSynchronizationFailurePreservesRecentAndLongRunningPurchaseRecovery() async throws {
        let suiteName = "StoreKitPaymentTests.pending-sync-failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let initiatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let recentClient = MembershipStoreClientSpy(
            entitlementResponses: [[]],
            synchronizationFails: true
        )
        let recentController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: recentClient,
            pendingPurchaseDefaults: defaults,
            currentDate: { initiatedAt.addingTimeInterval(60) }
        )
        recentController.recordPendingPurchase(
            productID: MembershipProductID.monthly,
            initiatedAt: initiatedAt
        )

        let recentUnlocked = await recentController.restorePurchases()
        let recentEvents = await recentClient.recordedEvents()

        XCTAssertFalse(recentUnlocked)
        XCTAssertEqual(recentController.purchaseNotice, .pendingApproval)
        XCTAssertEqual(recentController.pendingPurchaseProductID, MembershipProductID.monthly)
        XCTAssertNotNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))
        XCTAssertEqual(recentEvents, [.synchronize])

        let longRunningClient = MembershipStoreClientSpy(
            entitlementResponses: [[]],
            synchronizationFails: true
        )
        let longRunningController = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: longRunningClient,
            pendingPurchaseDefaults: defaults,
            currentDate: {
                initiatedAt.addingTimeInterval(
                    MembershipPendingPurchasePersistence.defaultLongRunningInterval
                )
            }
        )

        let longRunningUnlocked = await longRunningController.restorePurchases()
        let longRunningEvents = await longRunningClient.recordedEvents()

        XCTAssertFalse(longRunningUnlocked)
        XCTAssertEqual(
            longRunningController.purchaseNotice,
            .previousPurchaseUnconfirmed
        )
        XCTAssertEqual(
            longRunningController.pendingPurchaseProductID,
            MembershipProductID.monthly
        )
        XCTAssertNotNil(defaults.data(forKey: MembershipPendingPurchasePersistence.storageKey))
        XCTAssertEqual(longRunningEvents, [.synchronize])
    }

    @MainActor
    func testRestoreDoesNotReadEntitlementsWhenSynchronizationFails() async {
        let client = MembershipStoreClientSpy(
            entitlementResponses: [[]],
            synchronizationFails: true
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil
        )

        let unlocked = await controller.restorePurchases()
        let events = await client.recordedEvents()

        XCTAssertFalse(unlocked)
        XCTAssertEqual(controller.purchaseNotice, .failure("Could not restore purchases yet."))
        XCTAssertEqual(events, [.synchronize])
    }

    @MainActor
    func testSuccessfulRestoreReadsEntitlementsAfterConcurrentPreSyncRefresh() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let annual = makeEntitlement(
            transactionID: 82,
            productID: MembershipProductID.yearly,
            purchaseDate: now
        )
        let client = GatedSynchronizationMembershipStoreClient(entitlements: [])
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil,
            currentDate: { now }
        )

        let restore = Task { @MainActor in
            await controller.restorePurchases()
        }
        await client.waitForSynchronizationRequest()

        let preSyncRefresh = await controller.refreshEntitlements()
        await client.replaceEntitlements(with: [annual])
        await client.succeedSynchronization()
        let restored = await restore.value
        let entitlementRequestCount = await client.entitlementRequestCount()

        XCTAssertFalse(preSyncRefresh)
        XCTAssertTrue(restored)
        XCTAssertTrue(controller.isMembershipUnlocked)
        XCTAssertEqual(controller.activePlanSnapshot?.transactionID, annual.transactionID)
        XCTAssertEqual(entitlementRequestCount, 2)
        XCTAssertFalse(controller.isRestoringPurchases)
    }

    @MainActor
    func testLateRestoreFailureCannotOverwriteNewerVerifiedEntitlement() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let annual = makeEntitlement(
            transactionID: 81,
            productID: MembershipProductID.yearly,
            purchaseDate: now
        )
        let client = GatedSynchronizationMembershipStoreClient(entitlements: [annual])
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil,
            currentDate: { now }
        )
        controller.recordPendingPurchase(
            productID: MembershipProductID.monthly,
            initiatedAt: now
        )

        let restore = Task { @MainActor in
            await controller.restorePurchases()
        }
        await client.waitForSynchronizationRequest()

        let refreshed = await controller.refreshEntitlements()
        await client.failSynchronization()
        let restored = await restore.value

        XCTAssertTrue(refreshed)
        XCTAssertFalse(restored)
        XCTAssertTrue(controller.isMembershipUnlocked)
        XCTAssertEqual(controller.activePlanSnapshot?.transactionID, annual.transactionID)
        XCTAssertNil(controller.pendingPurchaseProductID)
        XCTAssertNil(controller.purchaseNotice)
        XCTAssertFalse(controller.isRestoringPurchases)
    }

    @MainActor
    func testOlderEntitlementRefreshCannotOverwriteNewerSnapshot() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let annual = makeEntitlement(
            transactionID: 2,
            productID: MembershipProductID.yearly,
            purchaseDate: now
        )
        let client = GatedMembershipStoreClient()
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil,
            currentDate: { now }
        )
        controller.recordPendingPurchase(
            productID: MembershipProductID.monthly,
            initiatedAt: now
        )

        let olderRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        await client.waitForRequestCount(1)
        let newerRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        await client.waitForRequestCount(2)

        await client.resumeRequest(1, with: [annual])
        _ = await newerRefresh.value
        await client.resumeRequest(0, with: [])
        _ = await olderRefresh.value

        XCTAssertTrue(controller.isMembershipUnlocked)
        XCTAssertEqual(controller.activePlanSnapshot?.transactionID, annual.transactionID)
        XCTAssertEqual(controller.purchasedProductIDs, [MembershipProductID.yearly])
        XCTAssertNil(controller.pendingPurchaseProductID)
        XCTAssertNil(controller.purchaseNotice)
    }

    @MainActor
    func testOlderStatusLookupCannotOverwriteNewerSnapshot() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let annual = makeEntitlement(
            transactionID: 3,
            productID: MembershipProductID.yearly,
            purchaseDate: now,
            subscriptionGroupID: "checkpoint.pro"
        )
        let monthly = makeEntitlement(
            transactionID: 4,
            productID: MembershipProductID.monthly,
            purchaseDate: now.addingTimeInterval(60)
        )
        let client = GatedStatusMembershipStoreClient(
            entitlementResponses: [[annual], [monthly]]
        )
        let controller = PurchaseController(
            grantsDebugTesterEntitlement: false,
            storeClient: client,
            pendingPurchaseDefaults: nil
        )

        let olderRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        await client.waitForStatusRequest()
        let newerRefresh = Task { @MainActor in
            await controller.refreshEntitlements()
        }
        _ = await newerRefresh.value

        await client.resumeStatusRequest(
            with: [
                MembershipSubscriptionStatusRecord(
                    transactionID: annual.transactionID,
                    productID: annual.productID,
                    state: .subscribed,
                    renewal: MembershipRenewalRecord(
                        currentProductID: annual.productID,
                        willAutoRenew: true,
                        autoRenewPreference: nil,
                        gracePeriodExpirationDate: nil
                    )
                )
            ]
        )
        _ = await olderRefresh.value

        XCTAssertEqual(controller.activePlanSnapshot?.transactionID, monthly.transactionID)
        XCTAssertEqual(controller.activePlanSnapshot?.planKind, .monthly)
        XCTAssertEqual(controller.activePlanSnapshot?.renewalDisposition, .active)
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

    func testUnconfirmedPurchaseRecoveryNoticeSurvivesCatalogReload() {
        let recoveredCatalog = MembershipPurchaseNotice.resolvingCatalogLoad(
            current: .previousPurchaseUnconfirmed,
            catalogNotice: nil
        )
        let unavailableCatalog = MembershipPurchaseNotice.resolvingCatalogLoad(
            current: .previousPurchaseUnconfirmed,
            catalogNotice: .catalogUnavailable("Could not load App Store plans yet.")
        )

        XCTAssertEqual(recoveredCatalog, .previousPurchaseUnconfirmed)
        XCTAssertEqual(unavailableCatalog, .previousPurchaseUnconfirmed)
        XCTAssertTrue(MembershipPurchaseNotice.previousPurchaseUnconfirmed.shouldDisplayWithoutSelectedPlan)
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
        XCTAssertTrue(MembershipPurchaseNotice.pendingApproval.shouldDisplayWithoutSelectedPlan)
        XCTAssertTrue(
            MembershipPurchaseNotice.pendingApprovalChecked.shouldDisplayWithoutSelectedPlan
        )
        XCTAssertFalse(
            MembershipPurchaseNotice.catalogUnavailable("Catalog unavailable.")
                .shouldDisplayWithoutSelectedPlan
        )
        XCTAssertTrue(
            MembershipPurchaseNotice.previousPurchaseUnconfirmed
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

    private func makeEntitlement(
        transactionID: UInt64,
        productID: String,
        purchaseDate: Date,
        expirationDate: Date? = nil,
        subscriptionGroupID: String? = nil,
        isUpgraded: Bool = false,
        ownership: MembershipPlanOwnership = .purchased
    ) -> MembershipEntitlementRecord {
        MembershipEntitlementRecord(
            transactionID: transactionID,
            productID: productID,
            purchaseDate: purchaseDate,
            expirationDate: expirationDate,
            subscriptionGroupID: subscriptionGroupID,
            isUpgraded: isUpgraded,
            ownership: ownership
        )
    }
}

private actor MembershipStoreClientSpy: MembershipStoreClient {
    enum Event: Equatable, Sendable {
        case synchronize
        case readEntitlements
        case readStatuses(String)
    }

    enum Failure: Error {
        case synchronization
        case status
    }

    private var entitlementResponses: [[MembershipEntitlementRecord]]
    private let statuses: [MembershipSubscriptionStatusRecord]
    private let synchronizationFails: Bool
    private let statusLookupFails: Bool
    private var events: [Event] = []

    init(
        entitlementResponses: [[MembershipEntitlementRecord]],
        statuses: [MembershipSubscriptionStatusRecord] = [],
        synchronizationFails: Bool = false,
        statusLookupFails: Bool = false
    ) {
        self.entitlementResponses = entitlementResponses
        self.statuses = statuses
        self.synchronizationFails = synchronizationFails
        self.statusLookupFails = statusLookupFails
    }

    func currentMembershipEntitlements() async -> [MembershipEntitlementRecord] {
        events.append(.readEntitlements)
        guard !entitlementResponses.isEmpty else { return [] }
        return entitlementResponses.removeFirst()
    }

    func subscriptionStatuses(
        for subscriptionGroupID: String
    ) async throws -> [MembershipSubscriptionStatusRecord] {
        events.append(.readStatuses(subscriptionGroupID))
        if statusLookupFails {
            throw Failure.status
        }
        return statuses
    }

    func synchronize() async throws {
        events.append(.synchronize)
        if synchronizationFails {
            throw Failure.synchronization
        }
    }

    func recordedEvents() -> [Event] {
        events
    }
}

private actor GatedSynchronizationMembershipStoreClient: MembershipStoreClient {
    enum Failure: Error {
        case synchronization
    }

    private var entitlements: [MembershipEntitlementRecord]
    private var entitlementRequests = 0
    private var synchronizationRequested = false
    private var synchronizationContinuation: CheckedContinuation<Void, Error>?

    init(entitlements: [MembershipEntitlementRecord]) {
        self.entitlements = entitlements
    }

    func currentMembershipEntitlements() async -> [MembershipEntitlementRecord] {
        entitlementRequests += 1
        return entitlements
    }

    func subscriptionStatuses(
        for _: String
    ) async throws -> [MembershipSubscriptionStatusRecord] {
        []
    }

    func synchronize() async throws {
        synchronizationRequested = true
        try await withCheckedThrowingContinuation { continuation in
            synchronizationContinuation = continuation
        }
    }

    func waitForSynchronizationRequest() async {
        while !synchronizationRequested {
            await Task.yield()
        }
    }

    func failSynchronization() {
        synchronizationContinuation?.resume(throwing: Failure.synchronization)
        synchronizationContinuation = nil
    }

    func succeedSynchronization() {
        synchronizationContinuation?.resume(returning: ())
        synchronizationContinuation = nil
    }

    func replaceEntitlements(with entitlements: [MembershipEntitlementRecord]) {
        self.entitlements = entitlements
    }

    func entitlementRequestCount() -> Int {
        entitlementRequests
    }
}

private actor GatedMembershipStoreClient: MembershipStoreClient {
    private var issuedRequestCount = 0
    private var continuations: [Int: CheckedContinuation<[MembershipEntitlementRecord], Never>] = [:]

    func currentMembershipEntitlements() async -> [MembershipEntitlementRecord] {
        let requestIndex = issuedRequestCount
        issuedRequestCount += 1
        return await withCheckedContinuation { continuation in
            continuations[requestIndex] = continuation
        }
    }

    func subscriptionStatuses(
        for _: String
    ) async throws -> [MembershipSubscriptionStatusRecord] {
        []
    }

    func synchronize() async throws {}

    func waitForRequestCount(_ count: Int) async {
        while issuedRequestCount < count {
            await Task.yield()
        }
    }

    func resumeRequest(
        _ index: Int,
        with entitlements: [MembershipEntitlementRecord]
    ) {
        continuations.removeValue(forKey: index)?.resume(returning: entitlements)
    }
}

private actor GatedStatusMembershipStoreClient: MembershipStoreClient {
    private var entitlementResponses: [[MembershipEntitlementRecord]]
    private var statusRequestWasIssued = false
    private var statusContinuation: CheckedContinuation<
        [MembershipSubscriptionStatusRecord],
        Never
    >?

    init(entitlementResponses: [[MembershipEntitlementRecord]]) {
        self.entitlementResponses = entitlementResponses
    }

    func currentMembershipEntitlements() async -> [MembershipEntitlementRecord] {
        guard !entitlementResponses.isEmpty else { return [] }
        return entitlementResponses.removeFirst()
    }

    func subscriptionStatuses(
        for _: String
    ) async throws -> [MembershipSubscriptionStatusRecord] {
        statusRequestWasIssued = true
        return await withCheckedContinuation { continuation in
            statusContinuation = continuation
        }
    }

    func synchronize() async throws {}

    func waitForStatusRequest() async {
        while !statusRequestWasIssued {
            await Task.yield()
        }
    }

    func resumeStatusRequest(with statuses: [MembershipSubscriptionStatusRecord]) {
        statusContinuation?.resume(returning: statuses)
        statusContinuation = nil
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
