import SwiftUI
import XCTest
@testable import Checkpoint

final class MembershipViewRenderingTests: XCTestCase {
    @MainActor
    func testMembershipJourneyRendersAcrossKeyLayoutsAndStates() throws {
        let legalLinks = try makeLegalLinks()
        let planOptions = try makePlanOptions()
        let futurePlanDate = Date(timeIntervalSince1970: 2_000_000_000)
        let pendingInitiatedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let fixtures = [
            MembershipRenderFixture(
                name: "membership-annual-light",
                context: .feature(.adaptiveStudyAssist),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly
            ),
            MembershipRenderFixture(
                name: "membership-monthly-compact-dark",
                context: .feature(.goalProfiles),
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.monthly
            ),
            MembershipRenderFixture(
                name: "membership-annual-compact-light",
                context: .overview,
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly
            ),
            MembershipRenderFixture(
                name: "membership-large-text-dark",
                context: .overview,
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .xxxLarge,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly
            ),
            MembershipRenderFixture(
                name: "membership-annual-accessibility",
                context: .feature(.largerQuestionBank),
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
                context: .feature(.goalProfiles),
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
                context: .feature(.freshQuestionGeneration),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                isLoading: true
            ),
            MembershipRenderFixture(
                name: "membership-unavailable",
                context: .feature(.freshQuestionGeneration),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                purchaseNotice: .catalogUnavailable("Could not load App Store plans yet.")
            ),
            MembershipRenderFixture(
                name: "membership-pending-dark",
                context: .feature(.adaptiveStudyAssist),
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly,
                pendingPurchaseRecord: MembershipPendingPurchaseRecord(
                    productID: MembershipProductID.monthly,
                    initiatedAt: pendingInitiatedAt
                ),
                currentDate: pendingInitiatedAt.addingTimeInterval(60)
            ),
            MembershipRenderFixture(
                name: "membership-pending-accessibility5-light",
                context: .feature(.adaptiveStudyAssist),
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly,
                pendingPurchaseRecord: MembershipPendingPurchaseRecord(
                    productID: MembershipProductID.monthly,
                    initiatedAt: pendingInitiatedAt
                ),
                currentDate: pendingInitiatedAt.addingTimeInterval(60)
            ),
            MembershipRenderFixture(
                name: "membership-unconfirmed-retry-compact-dark",
                context: .feature(.adaptiveStudyAssist),
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.monthly,
                pendingPurchaseRecord: MembershipPendingPurchaseRecord(
                    productID: MembershipProductID.monthly,
                    initiatedAt: pendingInitiatedAt
                ),
                currentDate: pendingInitiatedAt.addingTimeInterval(
                    MembershipPendingPurchasePersistence.defaultLongRunningInterval
                )
            ),
            MembershipRenderFixture(
                name: "membership-unconfirmed-retry-accessibility5-light",
                context: .feature(.adaptiveStudyAssist),
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly,
                pendingPurchaseRecord: MembershipPendingPurchaseRecord(
                    productID: MembershipProductID.monthly,
                    initiatedAt: pendingInitiatedAt
                ),
                currentDate: pendingInitiatedAt.addingTimeInterval(
                    MembershipPendingPurchasePersistence.defaultLongRunningInterval
                )
            ),
            MembershipRenderFixture(
                name: "membership-pending-no-catalog-light",
                context: .overview,
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                pendingPurchaseRecord: MembershipPendingPurchaseRecord(
                    productID: MembershipProductID.monthly,
                    initiatedAt: pendingInitiatedAt
                ),
                currentDate: pendingInitiatedAt.addingTimeInterval(60)
            ),
            MembershipRenderFixture(
                name: "membership-purchase-failure",
                context: .feature(.goalProfiles),
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
                context: .feature(.freshQuestionGeneration),
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
                context: .feature(.freshQuestionGeneration),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                reduceMotion: true,
                isMember: true
            ),
            MembershipRenderFixture(
                name: "membership-active-annual-renews-light",
                context: .overview,
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                isMember: true,
                activePlanSnapshot: makeActivePlanSnapshot(
                    planKind: .annual,
                    currentPeriodEnd: futurePlanDate,
                    renewalDisposition: .renews
                )
            ),
            MembershipRenderFixture(
                name: "membership-active-monthly-ending-compact-dark",
                context: .overview,
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                isMember: true,
                activePlanSnapshot: makeActivePlanSnapshot(
                    planKind: .monthly,
                    currentPeriodEnd: futurePlanDate,
                    renewalDisposition: .ends
                )
            ),
            MembershipRenderFixture(
                name: "membership-active-grace-dark",
                context: .overview,
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                isMember: true,
                activePlanSnapshot: makeActivePlanSnapshot(
                    planKind: .annual,
                    renewalDisposition: .gracePeriod(until: futurePlanDate)
                )
            ),
            MembershipRenderFixture(
                name: "membership-active-family-accessibility5",
                context: .overview,
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                isMember: true,
                activePlanSnapshot: makeActivePlanSnapshot(
                    planKind: .annual,
                    renewalDisposition: .renews,
                    ownership: .familyShared
                )
            )
        ]

        try renderMembershipFixtures(fixtures, legalLinks: legalLinks)
    }

    @MainActor
    func testCompactPaywallKeepsTheCompleteSelectedOfferAboveStickyCheckout() throws {
        let legalLinks = try makeLegalLinks()
        let planOptions = try makePlanOptions()
        let fixtures = [
            MembershipCompactFirstFoldFixture(
                name: "annual",
                context: .overview,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly
            ),
            MembershipCompactFirstFoldFixture(
                name: "monthly-long-headline",
                context: .feature(.largerQuestionBank),
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.monthly
            ),
            MembershipCompactFirstFoldFixture(
                name: "long-localized-price",
                context: .overview,
                planOptions: try makeLongLocalizedPlanOptions(),
                selectedPlanID: MembershipProductID.yearly
            ),
        ]

        for fixture in fixtures {
            let suiteName = "MembershipCompactFirstFold.\(fixture.name).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let capture = MembershipPaywallLayoutCapture()
            let store = CheckpointStore(defaults: defaults)
            let purchaseController = PurchaseController(
                grantsDebugTesterEntitlement: false,
                pendingPurchaseDefaults: nil
            )
            let view = MembershipView(
                context: fixture.context,
                store: store,
                purchaseController: purchaseController,
                renderConfiguration: MembershipViewRenderConfiguration(
                    planOptions: fixture.planOptions,
                    selectedPlanID: fixture.selectedPlanID,
                    legalLinks: legalLinks,
                    reduceMotion: true,
                    layoutReporter: { element, frame in
                        capture.frames[element] = frame
                    }
                )
            )
            .environment(\.colorScheme, ColorScheme.light)
            .environment(\.dynamicTypeSize, DynamicTypeSize.large)

            let image = HostedViewRenderer.image(
                for: view,
                width: 320,
                height: 568,
                colorScheme: .light,
                settlingTime: 0.15,
                renderScale: 0.5
            )

            XCTAssertEqual(image.size.width, 320, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, 568, accuracy: 0.5, fixture.name)
            XCTAssertNil(capture.frames[.section(.hero)], fixture.name)

            let viewport = try XCTUnwrap(capture.frames[.viewport], fixture.name)
            let offer = try XCTUnwrap(capture.frames[.section(.offer)], fixture.name)
            let yearly = try XCTUnwrap(
                capture.frames[.plan(MembershipProductID.yearly)],
                fixture.name
            )
            let monthly = try XCTUnwrap(
                capture.frames[.plan(MembershipProductID.monthly)],
                fixture.name
            )
            let selectedSupport = try XCTUnwrap(
                capture.frames[.selectedPlanSupport],
                fixture.name
            )
            let disclosure = try XCTUnwrap(
                capture.frames[.subscriptionDisclosure],
                fixture.name
            )
            let checkoutBar = try XCTUnwrap(capture.frames[.checkoutBar], fixture.name)
            let primaryAction = try XCTUnwrap(capture.frames[.primaryAction], fixture.name)
            let visibleOfferFrames = [offer, yearly, monthly, selectedSupport, disclosure]

            for frame in visibleOfferFrames + [viewport, checkoutBar, primaryAction] {
                XCTAssertFalse(frame.isNull, fixture.name)
                XCTAssertFalse(frame.isInfinite, fixture.name)
                XCTAssertGreaterThan(frame.width, 0, fixture.name)
                XCTAssertGreaterThan(frame.height, 0, fixture.name)
            }

            XCTAssertEqual(yearly.width, monthly.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(yearly.width, 136, accuracy: 1, fixture.name)
            for planFrame in [yearly, monthly] {
                XCTAssertGreaterThanOrEqual(planFrame.height, 104, fixture.name)
                XCTAssertLessThanOrEqual(planFrame.height, 122, fixture.name)
                XCTAssertGreaterThanOrEqual(planFrame.minY, viewport.minY - 0.5, fixture.name)
                XCTAssertLessThanOrEqual(
                    planFrame.maxY,
                    checkoutBar.minY - 6,
                    "\(fixture.name) let a plan card run under the checkout bar"
                )
                XCTAssertTrue(
                    planFrame.intersection(checkoutBar).isNull,
                    "\(fixture.name) overlapped a plan card with checkout"
                )
            }

            XCTAssertLessThanOrEqual(
                selectedSupport.maxY,
                checkoutBar.minY - 6,
                "\(fixture.name) hid selected-plan context below checkout"
            )
            XCTAssertLessThanOrEqual(
                disclosure.maxY,
                checkoutBar.minY - 6,
                "\(fixture.name) hid renewal disclosure below checkout"
            )
            XCTAssertTrue(offer.insetBy(dx: -0.5, dy: -0.5).contains(disclosure), fixture.name)
            XCTAssertGreaterThanOrEqual(primaryAction.height, 50, fixture.name)
            XCTAssertLessThanOrEqual(checkoutBar.height, 92, fixture.name)
            XCTAssertTrue(
                checkoutBar.insetBy(dx: -0.5, dy: -0.5).contains(primaryAction),
                fixture.name
            )

            let attachment = XCTAttachment(image: image)
            attachment.name = "membership-compact-first-fold-\(fixture.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testPaywallFlowsCheckoutInlineForConstrainedLayoutsLargeTextNoticesAndAccessibility() throws {
        let legalLinks = try makeLegalLinks()
        let planOptions = try makePlanOptions()
        let pendingInitiatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let fixtures: [MembershipInlineCheckoutFixture] = [
            MembershipInlineCheckoutFixture(
                name: "compact-xxx-large",
                dynamicTypeSize: .xxxLarge
            ),
            MembershipInlineCheckoutFixture(
                name: "regular-xxx-large",
                dynamicTypeSize: .xxxLarge,
                width: 393,
                height: 852
            ),
            MembershipInlineCheckoutFixture(
                name: "compact-pending",
                dynamicTypeSize: .large,
                pendingPurchaseRecord: MembershipPendingPurchaseRecord(
                    productID: MembershipProductID.monthly,
                    initiatedAt: pendingInitiatedAt
                ),
                currentDate: pendingInitiatedAt.addingTimeInterval(60)
            ),
            MembershipInlineCheckoutFixture(
                name: "compact-unconfirmed-purchase",
                dynamicTypeSize: .large,
                pendingPurchaseRecord: MembershipPendingPurchaseRecord(
                    productID: MembershipProductID.monthly,
                    initiatedAt: pendingInitiatedAt
                ),
                currentDate: pendingInitiatedAt.addingTimeInterval(
                    MembershipPendingPurchasePersistence.defaultLongRunningInterval
                )
            ),
            MembershipInlineCheckoutFixture(
                name: "compact-pending-accessibility5",
                dynamicTypeSize: .accessibility5,
                pendingPurchaseRecord: MembershipPendingPurchaseRecord(
                    productID: MembershipProductID.monthly,
                    initiatedAt: pendingInitiatedAt
                ),
                currentDate: pendingInitiatedAt.addingTimeInterval(60),
                height: 1_600
            ),
            MembershipInlineCheckoutFixture(
                name: "compact-unconfirmed-accessibility5",
                dynamicTypeSize: .accessibility5,
                pendingPurchaseRecord: MembershipPendingPurchaseRecord(
                    productID: MembershipProductID.monthly,
                    initiatedAt: pendingInitiatedAt
                ),
                currentDate: pendingInitiatedAt.addingTimeInterval(
                    MembershipPendingPurchasePersistence.defaultLongRunningInterval
                ),
                height: 1_600
            ),
            MembershipInlineCheckoutFixture(
                name: "compact-accessibility5",
                dynamicTypeSize: .accessibility5
            ),
            MembershipInlineCheckoutFixture(
                name: "landscape",
                dynamicTypeSize: .large,
                width: 852,
                height: 393
            ),
        ]

        for fixture in fixtures {
            let suiteName = "MembershipInlineCheckout.\(fixture.name).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let capture = MembershipPaywallLayoutCapture()
            let store = CheckpointStore(defaults: defaults)
            if let pendingPurchaseRecord = fixture.pendingPurchaseRecord {
                MembershipPendingPurchasePersistence(defaults: defaults).save(
                    pendingPurchaseRecord
                )
            }
            let purchaseController = PurchaseController(
                grantsDebugTesterEntitlement: false,
                pendingPurchaseDefaults: defaults,
                currentDate: { fixture.currentDate }
            )
            if let purchaseNotice = fixture.purchaseNotice {
                purchaseController.purchaseNotice = purchaseNotice
            }
            let view = MembershipView(
                context: .feature(.goalProfiles),
                store: store,
                purchaseController: purchaseController,
                renderConfiguration: MembershipViewRenderConfiguration(
                    planOptions: planOptions,
                    selectedPlanID: MembershipProductID.yearly,
                    legalLinks: legalLinks,
                    reduceMotion: true,
                    layoutReporter: { element, frame in
                        capture.frames[element] = frame
                    }
                )
            )
            .environment(\.colorScheme, ColorScheme.dark)
            .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)

            let image = HostedViewRenderer.image(
                for: view,
                width: fixture.width,
                height: fixture.height,
                colorScheme: .dark,
                settlingTime: 0.15,
                renderScale: 0.5
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 1.1, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 1.1, fixture.name)
            XCTAssertNil(capture.frames[.section(.hero)], fixture.name)
            XCTAssertNil(capture.frames[.checkoutBar], fixture.name)

            let offer = try XCTUnwrap(capture.frames[.section(.offer)], fixture.name)
            let yearly = try XCTUnwrap(
                capture.frames[.plan(MembershipProductID.yearly)],
                fixture.name
            )
            let monthly = try XCTUnwrap(
                capture.frames[.plan(MembershipProductID.monthly)],
                fixture.name
            )
            let disclosure = try XCTUnwrap(
                capture.frames[.subscriptionDisclosure],
                fixture.name
            )
            let primaryAction = try XCTUnwrap(capture.frames[.primaryAction], fixture.name)
            let valueProof = try XCTUnwrap(
                capture.frames[.section(.valueProof)],
                fixture.name
            )

            for planFrame in [yearly, monthly] {
                XCTAssertGreaterThanOrEqual(planFrame.height, 44, fixture.name)
                XCTAssertTrue(
                    offer.insetBy(dx: -0.5, dy: -0.5).contains(planFrame),
                    fixture.name
                )
            }
            XCTAssertTrue(yearly.intersection(monthly).isNull, fixture.name)
            XCTAssertGreaterThanOrEqual(primaryAction.height, 50, fixture.name)
            XCTAssertGreaterThanOrEqual(primaryAction.minY, disclosure.maxY - 0.5, fixture.name)
            XCTAssertGreaterThanOrEqual(valueProof.minY, primaryAction.maxY - 0.5, fixture.name)
            XCTAssertTrue(
                offer.insetBy(dx: -0.5, dy: -0.5).contains(primaryAction),
                fixture.name
            )

            if fixture.pendingPurchaseRecord != nil {
                let secondaryAction = try XCTUnwrap(
                    capture.frames[.secondaryAction],
                    fixture.name
                )
                XCTAssertGreaterThanOrEqual(secondaryAction.height, 44, fixture.name)
                XCTAssertGreaterThanOrEqual(
                    secondaryAction.minY,
                    disclosure.maxY - 0.5,
                    "\(fixture.name) placed purchase-status recovery above billing disclosure"
                )
                XCTAssertGreaterThanOrEqual(
                    primaryAction.minY,
                    secondaryAction.maxY - 0.5,
                    "\(fixture.name) overlapped purchase-status recovery and the primary action"
                )
                XCTAssertTrue(
                    offer.insetBy(dx: -0.5, dy: -0.5).contains(secondaryAction),
                    "\(fixture.name) let purchase-status recovery escape the offer"
                )
            }

            let attachment = XCTAttachment(image: image)
            attachment.name = "membership-\(fixture.name)-inline-checkout"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testActiveMemberReceiptContainsItsSummaryAndAppleManagementAction() throws {
        let legalLinks = try makeLegalLinks()
        let futurePlanDate = Date(timeIntervalSince1970: 2_000_000_000)
        let fixtures = [
            MembershipActiveReceiptLayoutFixture(
                name: "regular-annual",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                snapshot: makeActivePlanSnapshot(
                    planKind: .annual,
                    currentPeriodEnd: futurePlanDate,
                    renewalDisposition: .renews
                )
            ),
            MembershipActiveReceiptLayoutFixture(
                name: "compact-grace",
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                snapshot: makeActivePlanSnapshot(
                    planKind: .monthly,
                    renewalDisposition: .gracePeriod(until: futurePlanDate)
                )
            ),
            MembershipActiveReceiptLayoutFixture(
                name: "accessibility5-family",
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                snapshot: makeActivePlanSnapshot(
                    planKind: .annual,
                    renewalDisposition: .renews,
                    ownership: .familyShared
                )
            ),
        ]

        for fixture in fixtures {
            let suiteName = "MembershipActiveReceipt.\(fixture.name).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let capture = MembershipPaywallLayoutCapture()
            let store = CheckpointStore(defaults: defaults)
            store.updateMembershipTier(.member)
            let purchaseController = PurchaseController(
                grantsDebugTesterEntitlement: false,
                initialActivePlanSnapshot: fixture.snapshot,
                pendingPurchaseDefaults: nil
            )
            let view = MembershipView(
                context: .overview,
                store: store,
                purchaseController: purchaseController,
                renderConfiguration: MembershipViewRenderConfiguration(
                    planOptions: [],
                    selectedPlanID: nil,
                    legalLinks: legalLinks,
                    reduceMotion: true,
                    layoutReporter: { element, frame in
                        capture.frames[element] = frame
                    }
                )
            )
            .environment(\.colorScheme, fixture.colorScheme)
            .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)

            let image = HostedViewRenderer.image(
                for: view,
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: 0.15,
                renderScale: 0.5
            )

            let section = try XCTUnwrap(
                capture.frames[.section(.memberManagement)],
                fixture.name
            )
            let receipt = try XCTUnwrap(capture.frames[.memberPlanReceipt], fixture.name)
            let identity = try XCTUnwrap(capture.frames[.memberPlanIdentity], fixture.name)
            let badge = try XCTUnwrap(capture.frames[.memberPlanBadge], fixture.name)
            let action = try XCTUnwrap(capture.frames[.memberManagementAction], fixture.name)

            for frame in [section, receipt, identity, badge, action] {
                XCTAssertFalse(frame.isNull, fixture.name)
                XCTAssertFalse(frame.isInfinite, fixture.name)
                XCTAssertGreaterThan(frame.width, 0, fixture.name)
                XCTAssertGreaterThan(frame.height, 0, fixture.name)
            }
            XCTAssertTrue(
                section.insetBy(dx: -0.5, dy: -0.5).contains(receipt),
                fixture.name
            )
            XCTAssertTrue(
                section.insetBy(dx: -0.5, dy: -0.5).contains(action),
                fixture.name
            )
            XCTAssertGreaterThanOrEqual(action.height, 44, fixture.name)
            XCTAssertGreaterThanOrEqual(action.minY, receipt.maxY - 0.5, fixture.name)
            XCTAssertTrue(receipt.intersection(action).isNull, fixture.name)

            if fixture.name == "compact-grace" {
                XCTAssertGreaterThanOrEqual(
                    badge.minY,
                    identity.maxY - 0.5,
                    "Compact attention state should stack instead of compressing plan identity"
                )
                XCTAssertGreaterThanOrEqual(
                    badge.width,
                    118,
                    "Attention badge should retain enough intrinsic width to show its full label"
                )
            }

            let attachment = XCTAttachment(image: image)
            attachment.name = "membership-active-receipt-\(fixture.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testMembershipOverviewRendersAcrossKeyLayouts() throws {
        let legalLinks = try makeLegalLinks()
        let planOptions = try makePlanOptions()
        let fixtures = [
            MembershipRenderFixture(
                name: "membership-overview-light",
                context: .overview,
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly
            ),
            MembershipRenderFixture(
                name: "membership-overview-accessibility5-dark",
                context: .overview,
                width: 393,
                height: 2_200,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                planOptions: planOptions,
                selectedPlanID: MembershipProductID.yearly
            )
        ]

        try renderMembershipFixtures(fixtures, legalLinks: legalLinks)
    }

    func testMembershipPresentationContextKeepsOverviewAndFeatureCopyDistinct() {
        let overview = MembershipPresentationContext.overview
        let feature = MembershipPresentationContext.feature(.adaptiveStudyAssist)

        XCTAssertEqual(overview.id, "overview")
        XCTAssertEqual(overview.heroLabel, "THE FULL EXPERIENCE")
        XCTAssertEqual(overview.offerLabel, "Full Pro access")
        XCTAssertEqual(overview.membershipHeadline, "Practice that keeps pace with you.")
        XCTAssertEqual(
            overview.detail,
            "Build up to 5 focused goals, keep checkpoints fresh, and get a clear Next Focus from your progress."
        )
        XCTAssertEqual(
            overview.offerDetail,
            "Up to 5 focused goals, fresh checkpoints, and one clear Next Focus."
        )
        XCTAssertNil(overview.feature)

        XCTAssertEqual(feature.id, "feature.adaptiveStudyAssist")
        XCTAssertEqual(feature.heroLabel, "UNLOCK NEXT FOCUS")
        XCTAssertEqual(feature.offerLabel, "Next Focus with Pro")
        XCTAssertEqual(feature.membershipHeadline, MembershipFeature.adaptiveStudyAssist.membershipHeadline)
        XCTAssertEqual(feature.detail, MembershipFeature.adaptiveStudyAssist.detail)
        XCTAssertEqual(
            feature.offerDetail,
            "Turn answer history into one clear priority for every checkpoint."
        )
        XCTAssertEqual(feature.feature, .adaptiveStudyAssist)
        XCTAssertEqual(
            MembershipPresentationContext.feature(.goalProfiles).offerLabel,
            "More goals with Pro"
        )
    }

    func testMembershipActivationPresentationCarriesThePaidActionForward() {
        let sourceGoalID = UUID()
        let targetGoalID = UUID()
        let create = MembershipActivationPresentation(
            id: UUID(uuidString: "A8A95063-A36F-4776-9485-6F8E0242896D")!,
            context: .feature(.goalProfiles),
            source: .purchase,
            continuation: .createGoalProfile(sourceGoalID: sourceGoalID)
        )
        let goalSwitch = MembershipActivationPresentation(
            id: UUID(uuidString: "EF0444D9-0F65-4D00-B9CB-D99C3F2BC4EF")!,
            context: .feature(.goalProfiles),
            source: .restore,
            continuation: .activateGoal(
                sourceGoalID: sourceGoalID,
                targetGoalID: targetGoalID
            ),
            destinationTitle: "Design portfolio"
        )
        let nextFocus = MembershipActivationPresentation(
            id: UUID(uuidString: "DD9007C4-A1A1-4F3E-9EB2-A713BE5437CF")!,
            context: .feature(.adaptiveStudyAssist),
            source: .purchase,
            continuation: .revealNextFocus(sourceGoalID: sourceGoalID),
            destinationTitle: "Reliability and failure recovery"
        )
        let overview = MembershipActivationPresentation(
            id: UUID(uuidString: "A941302A-7E60-47F4-A688-D24F721C4C21")!,
            context: .overview,
            source: .entitlementRefresh,
            continuation: nil
        )

        XCTAssertEqual(create.eyebrow, "PURCHASE COMPLETE")
        XCTAssertEqual(create.title, "Checkpoint Pro is active.")
        XCTAssertEqual(create.actionTitle, "Set up new goal")
        XCTAssertEqual(create.actionSystemImage, "plus")
        XCTAssertEqual(create.actionAccessibilityHint, "Opens goal setup.")
        XCTAssertTrue(create.detail.contains("next goal"))

        XCTAssertEqual(goalSwitch.eyebrow, "ACCESS RESTORED")
        XCTAssertEqual(goalSwitch.title, "Pro access restored.")
        XCTAssertEqual(goalSwitch.actionTitle, "Review goal switch")
        XCTAssertTrue(goalSwitch.actionAccessibilityHint.contains("protection"))
        XCTAssertTrue(goalSwitch.detail.contains("Design portfolio"))

        XCTAssertEqual(nextFocus.actionTitle, "Open Next Focus")
        XCTAssertEqual(nextFocus.actionSystemImage, "scope")
        XCTAssertEqual(
            nextFocus.detail,
            "Next Focus is now available for this goal in Progress."
        )
        XCTAssertEqual(
            nextFocus.actionAccessibilityHint,
            "Closes this confirmation and opens Next Focus in Progress."
        )

        XCTAssertEqual(overview.eyebrow, "ACCESS CONFIRMED")
        XCTAssertEqual(overview.actionTitle, "Done")
        XCTAssertEqual(overview.actionSystemImage, "checkmark")
        XCTAssertTrue(overview.accessibilityAnnouncement.contains(overview.detail))
    }

    func testMembershipActivationHandoffReducerKeepsTheFirstPaidAction() {
        let firstRequest = MembershipActivationRequest(
            id: UUID(uuidString: "6EC28BF2-3798-4E65-937D-2137262C4C64")!,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            context: .feature(.goalProfiles),
            continuation: .createGoalProfile(sourceGoalID: UUID())
        )
        let secondRequest = MembershipActivationRequest(
            id: UUID(uuidString: "29346431-7618-4089-82D6-D0DCC75A34E4")!,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100),
            context: .feature(.freshQuestionGeneration),
            continuation: .createGoalProfile(sourceGoalID: UUID())
        )

        let offered = MembershipActivationHandoffReducer.reduce(
            nil,
            event: .request(firstRequest)
        )
        let duplicateRequest = MembershipActivationHandoffReducer.reduce(
            offered,
            event: .request(secondRequest)
        )

        XCTAssertEqual(offered?.phase, .offered)
        XCTAssertEqual(duplicateRequest?.request, firstRequest)
    }

    func testMembershipActivationHandoffReducerLetsAContextualActionReplaceAnUnstartedOverview() {
        let overviewRequest = MembershipActivationRequest(
            context: .overview
        )
        let contextualRequest = MembershipActivationRequest(
            context: .feature(.goalProfiles),
            continuation: .createGoalProfile(sourceGoalID: UUID())
        )
        let offeredOverview = MembershipActivationHandoff(request: overviewRequest)

        let contextualHandoff = MembershipActivationHandoffReducer.reduce(
            offeredOverview,
            event: .request(contextualRequest)
        )

        XCTAssertEqual(contextualHandoff?.request, contextualRequest)
        XCTAssertEqual(contextualHandoff?.phase, .offered)
    }

    func testMembershipActivationHandoffReducerPreservesOnlyUnresolvedCheckoutDismissals() {
        let request = MembershipActivationRequest(
            context: .feature(.goalProfiles),
            continuation: .createGoalProfile(sourceGoalID: UUID())
        )
        let offered = MembershipActivationHandoff(request: request)
        let awaiting = MembershipActivationHandoffReducer.reduce(
            offered,
            event: .checkoutStarted
        )

        XCTAssertEqual(awaiting?.phase, .awaitingEntitlement)
        XCTAssertNil(
            MembershipActivationHandoffReducer.reduce(
                awaiting,
                event: .dismissed(hasUnresolvedPurchase: false)
            )
        )
        XCTAssertEqual(
            MembershipActivationHandoffReducer.reduce(
                awaiting,
                event: .dismissed(hasUnresolvedPurchase: true)
            ),
            awaiting
        )
        XCTAssertEqual(
            MembershipActivationHandoffReducer.reduce(
                awaiting,
                event: .checkoutFinished(hasUnresolvedPurchase: false)
            )?.phase,
            .offered
        )
    }

    func testMembershipActivationHandoffReducerResumesOnlyAfterExplicitAcknowledgment() {
        let request = MembershipActivationRequest(
            context: .feature(.goalProfiles),
            continuation: .createGoalProfile(sourceGoalID: UUID())
        )
        let offered = MembershipActivationHandoff(request: request)
        let ready = MembershipActivationHandoffReducer.reduce(
            offered,
            event: .entitlementVerified(source: .purchase)
        )
        let duplicateVerification = MembershipActivationHandoffReducer.reduce(
            ready,
            event: .entitlementVerified(source: .restore)
        )
        let resumeRequested = MembershipActivationHandoffReducer.reduce(
            ready,
            event: .resumeRequested
        )

        XCTAssertEqual(ready?.phase, .activationReady)
        XCTAssertEqual(ready?.source, .purchase)
        XCTAssertEqual(duplicateVerification, ready)
        XCTAssertNil(
            MembershipActivationHandoffReducer.reduce(
                ready,
                event: .dismissed(hasUnresolvedPurchase: false)
            )
        )
        XCTAssertEqual(resumeRequested?.phase, .resumeRequested)
        XCTAssertEqual(
            MembershipActivationHandoffReducer.reduce(
                resumeRequested,
                event: .resumeFailed
            ),
            ready
        )
        XCTAssertEqual(
            MembershipActivationHandoffReducer.reduce(
                resumeRequested,
                event: .dismissed(hasUnresolvedPurchase: false)
            ),
            resumeRequested
        )
        XCTAssertNil(
            MembershipActivationHandoffReducer.reduce(
                resumeRequested,
                event: .consumed
            )
        )
    }

    func testMembershipActivationFeedbackWaitsForAnActiveSceneAndDeliversEachReceiptOnce() {
        let first = MembershipActivationPresentation(
            id: UUID(uuidString: "D66F9C72-E354-4C8A-84D6-FF83726A38D7")!,
            context: .feature(.goalProfiles),
            source: .purchase,
            continuation: .createGoalProfile(sourceGoalID: UUID())
        )
        let second = MembershipActivationPresentation(
            id: UUID(uuidString: "54E4D1B1-06F2-4A7D-B68D-B7C5499EA590")!,
            context: .overview,
            source: .restore,
            continuation: nil
        )
        var feedback = MembershipActivationFeedbackState()

        XCTAssertNil(feedback.take(first, isSceneActive: false))
        XCTAssertEqual(
            feedback.take(first, isSceneActive: true),
            first.accessibilityAnnouncement
        )
        XCTAssertNil(feedback.take(first, isSceneActive: true))
        XCTAssertEqual(
            feedback.take(second, isSceneActive: true),
            second.accessibilityAnnouncement
        )
        XCTAssertNil(feedback.take(second, isSceneActive: true))
    }

    func testMembershipActivationMotionHonorsReduceMotion() {
        let animated = MembershipActivationMotionPolicy(reduceMotion: false)
        let reduced = MembershipActivationMotionPolicy(reduceMotion: true)

        XCTAssertEqual(animated.style, .reveal)
        XCTAssertNotNil(animated.animation)
        XCTAssertEqual(animated.hiddenOpacity, 0)
        XCTAssertLessThan(animated.hiddenScale, 1)
        XCTAssertNotEqual(animated.hiddenRotation, .zero)
        XCTAssertTrue(animated.animatesSymbol)

        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
        XCTAssertEqual(reduced.hiddenOpacity, 1)
        XCTAssertEqual(reduced.hiddenScale, 1)
        XCTAssertEqual(reduced.hiddenRotation, .zero)
        XCTAssertFalse(reduced.animatesSymbol)
    }

    @MainActor
    func testMembershipActivationRendersAcrossDestinationAndAccessibilityStates() throws {
        let legalLinks = try makeLegalLinks()
        let sourceGoalID = UUID(uuidString: "A732D6DF-867D-40C7-B858-0E5C90033BD6")!
        let fixtures = [
            MembershipRenderFixture(
                name: "membership-activated-create-light",
                context: .feature(.goalProfiles),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large,
                isMember: true,
                activationPresentation: MembershipActivationPresentation(
                    id: UUID(uuidString: "D4EAF994-7E37-4507-966E-C7326E4BD6A0")!,
                    context: .feature(.goalProfiles),
                    source: .purchase,
                    continuation: .createGoalProfile(sourceGoalID: sourceGoalID)
                )
            ),
            MembershipRenderFixture(
                name: "membership-activated-switch-compact-dark",
                context: .feature(.goalProfiles),
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                isMember: true,
                activationPresentation: MembershipActivationPresentation(
                    id: UUID(uuidString: "0786C716-C72C-4C81-A74D-4936B05DECB9")!,
                    context: .feature(.goalProfiles),
                    source: .restore,
                    continuation: .activateGoal(
                        sourceGoalID: sourceGoalID,
                        targetGoalID: UUID(uuidString: "B738CD41-D9CD-4E85-9B74-5FB9017C0ED2")!
                    ),
                    destinationTitle: "Design portfolio"
                )
            ),
            MembershipRenderFixture(
                name: "membership-activated-next-focus-compact-dark",
                context: .feature(.adaptiveStudyAssist),
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                isMember: true,
                activationPresentation: MembershipActivationPresentation(
                    id: UUID(uuidString: "06D34D49-09AD-46E8-A7EC-8684933677CD")!,
                    context: .feature(.adaptiveStudyAssist),
                    source: .purchase,
                    continuation: .revealNextFocus(sourceGoalID: sourceGoalID)
                )
            ),
            MembershipRenderFixture(
                name: "membership-activated-accessibility5-reduced-motion",
                context: .feature(.goalProfiles),
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                isMember: true,
                activationPresentation: MembershipActivationPresentation(
                    id: UUID(uuidString: "5A7CE487-FE62-4034-A1F7-4CB34A94B5CA")!,
                    context: .feature(.goalProfiles),
                    source: .entitlementRefresh,
                    continuation: .createGoalProfile(sourceGoalID: sourceGoalID)
                )
            ),
            MembershipRenderFixture(
                name: "membership-activated-next-focus-accessibility5-reduced",
                context: .feature(.adaptiveStudyAssist),
                width: 393,
                height: 1_700,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                isMember: true,
                activationPresentation: MembershipActivationPresentation(
                    id: UUID(uuidString: "8070E977-CC0D-4D8E-963A-D0E19322CC0F")!,
                    context: .feature(.adaptiveStudyAssist),
                    source: .restore,
                    continuation: .revealNextFocus(sourceGoalID: sourceGoalID)
                )
            )
        ]

        try renderMembershipFixtures(fixtures, legalLinks: legalLinks)
    }

    @MainActor
    func testLiveVerifiedReceiptOwnsTheMembershipSheetsFirstFrame() throws {
        let suiteName = "MembershipViewRenderingTests.live-receipt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.presentGoalProfileCreator()
        store.reconcileMembershipEntitlement(
            isUnlocked: true,
            activationSource: .purchase
        )
        let capture = MembershipPaywallLayoutCapture()
        let view = MembershipView(
            context: .feature(.goalProfiles),
            store: store,
            purchaseController: PurchaseController(
                grantsDebugTesterEntitlement: false,
                pendingPurchaseDefaults: nil
            ),
            renderConfiguration: MembershipViewRenderConfiguration(
                planOptions: [],
                selectedPlanID: nil,
                legalLinks: try makeLegalLinks(),
                reduceMotion: true,
                layoutReporter: { element, frame in
                    capture.frames[element] = frame
                }
            )
        )

        _ = HostedViewRenderer.image(
            for: view,
            width: 393,
            height: 852,
            colorScheme: .light,
            settlingTime: 0.05,
            renderScale: 0.5
        )

        XCTAssertNotNil(capture.frames[.activationReceipt])
        XCTAssertNotNil(capture.frames[.activationAction])
        XCTAssertNil(capture.frames[.section(.hero)])
    }

    @MainActor
    func testPersistedReceiptVerificationScrollsAtCompactAccessibilitySize() throws {
        let suiteName = "MembershipViewRenderingTests.pending-receipt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let goal = makeGoal()
        let initialStore = CheckpointStore(defaults: defaults)
        initialStore.goal = goal
        initialStore.goalProfiles = [goal]
        initialStore.presentGoalProfileCreator()
        initialStore.reconcileMembershipEntitlement(
            isUnlocked: true,
            activationSource: .purchase
        )

        let restoredStore = CheckpointStore(defaults: defaults)
        XCTAssertTrue(restoredStore.hasMembershipActivationReceipt)
        XCTAssertNil(
            restoredStore.membershipActivationPresentationIfVerified(
                fallbackContext: .feature(.goalProfiles),
                fallbackSource: .entitlementRefresh
            )
        )

        let capture = MembershipPaywallLayoutCapture()
        let view = MembershipView(
            context: .feature(.goalProfiles),
            store: restoredStore,
            purchaseController: PurchaseController(
                grantsDebugTesterEntitlement: false,
                pendingPurchaseDefaults: nil
            ),
            renderConfiguration: MembershipViewRenderConfiguration(
                planOptions: [],
                selectedPlanID: nil,
                legalLinks: try makeLegalLinks(),
                reduceMotion: true,
                layoutReporter: { element, frame in
                    capture.frames[element] = frame
                }
            )
        )
        .environment(\.dynamicTypeSize, DynamicTypeSize.accessibility5)

        let image = HostedViewRenderer.image(
            for: view,
            width: 568,
            height: 320,
            colorScheme: .light,
            settlingTime: 0.05,
            renderScale: 0.5
        )

        let viewport = try XCTUnwrap(capture.frames[.activationVerificationViewport])
        let content = try XCTUnwrap(capture.frames[.activationVerificationContent])
        XCTAssertGreaterThan(viewport.width, 0)
        XCTAssertGreaterThan(viewport.height, 0)
        XCTAssertGreaterThan(
            content.height,
            viewport.height,
            "Accessibility content should overflow into the scrollable region"
        )
        XCTAssertGreaterThanOrEqual(viewport.minX, -0.5)
        XCTAssertLessThanOrEqual(viewport.maxX, 568.5)
        XCTAssertGreaterThanOrEqual(viewport.minY, -0.5)
        XCTAssertLessThanOrEqual(viewport.maxY, 320.5)
        XCTAssertNil(capture.frames[.section(.hero)])
        XCTAssertNil(capture.frames[.activationReceipt])

        let attachment = XCTAttachment(image: image)
        attachment.name = "membership-pending-receipt-landscape-accessibility5"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMembershipPaywallPresentationKeepsCheckoutAheadOfExtendedProof() {
        let regularOrder: [MembershipPaywallSection] = [
            .hero,
            .offer,
            .valueProof,
            .benefits,
            .notice,
            .restore,
            .legal
        ]
        let accessibleOrder: [MembershipPaywallSection] = [
            .offer,
            .valueProof,
            .benefits,
            .notice,
            .restore,
            .legal
        ]
        let regular = MembershipPaywallPresentation(isMember: false, accessibilitySize: false)
        let accessible = MembershipPaywallPresentation(isMember: false, accessibilitySize: true)
        let largeText = MembershipPaywallPresentation(
            isMember: false,
            accessibilitySize: false,
            usesLargeText: true
        )
        let compact = MembershipPaywallPresentation(
            isMember: false,
            accessibilitySize: false,
            availableHeight: 639.5
        )
        let compactLargeText = MembershipPaywallPresentation(
            isMember: false,
            accessibilitySize: false,
            usesLargeText: true,
            availableHeight: 639.5
        )
        let compactNotice = MembershipPaywallPresentation(
            isMember: false,
            accessibilitySize: false,
            hasCheckoutNotice: true,
            availableHeight: 639.5
        )
        let constrained = MembershipPaywallPresentation(
            isMember: false,
            accessibilitySize: false,
            availableHeight: 419.5
        )

        XCTAssertEqual(regular.sectionOrder, regularOrder)
        XCTAssertEqual(regular.checkoutPlacement, .sticky)
        XCTAssertTrue(regular.laysOutPlansSideBySide)
        XCTAssertEqual(regular.contentDensity, .regular)
        XCTAssertEqual(regular.offerIntroduction, .none)

        XCTAssertEqual(accessible.sectionOrder, accessibleOrder)
        XCTAssertEqual(accessible.checkoutPlacement, .afterPlanChoices)
        XCTAssertFalse(accessible.laysOutPlansSideBySide)
        XCTAssertEqual(accessible.contentDensity, .regular)
        XCTAssertEqual(accessible.offerIntroduction, .expanded)

        XCTAssertEqual(largeText.sectionOrder, accessibleOrder)
        XCTAssertEqual(largeText.checkoutPlacement, .afterPlanChoices)
        XCTAssertFalse(largeText.laysOutPlansSideBySide)
        XCTAssertEqual(largeText.contentDensity, .regular)
        XCTAssertEqual(largeText.offerIntroduction, .expanded)

        XCTAssertEqual(compact.sectionOrder, accessibleOrder)
        XCTAssertEqual(compact.checkoutPlacement, .sticky)
        XCTAssertTrue(compact.laysOutPlansSideBySide)
        XCTAssertEqual(compact.contentDensity, .compact)
        XCTAssertEqual(compact.offerIntroduction, .compact)

        XCTAssertEqual(compactLargeText.sectionOrder, accessibleOrder)
        XCTAssertEqual(compactLargeText.checkoutPlacement, .afterPlanChoices)
        XCTAssertFalse(compactLargeText.laysOutPlansSideBySide)
        XCTAssertEqual(compactLargeText.contentDensity, .regular)
        XCTAssertEqual(compactLargeText.offerIntroduction, .expanded)

        XCTAssertEqual(compactNotice.sectionOrder, accessibleOrder)
        XCTAssertEqual(compactNotice.checkoutPlacement, .afterPlanChoices)
        XCTAssertTrue(compactNotice.laysOutPlansSideBySide)
        XCTAssertEqual(compactNotice.contentDensity, .compact)
        XCTAssertEqual(compactNotice.offerIntroduction, .compact)

        XCTAssertEqual(constrained.sectionOrder, accessibleOrder)
        XCTAssertEqual(constrained.checkoutPlacement, .afterPlanChoices)
        XCTAssertTrue(constrained.laysOutPlansSideBySide)
        XCTAssertEqual(constrained.contentDensity, .compact)
        XCTAssertEqual(constrained.offerIntroduction, .compact)

        XCTAssertLessThan(
            regularOrder.firstIndex(of: .offer) ?? .max,
            regularOrder.firstIndex(of: .valueProof) ?? .max
        )
        XCTAssertLessThan(
            accessibleOrder.firstIndex(of: .offer) ?? .max,
            accessibleOrder.firstIndex(of: .valueProof) ?? .max
        )
    }

    func testMembershipPaywallViewportClassUsesBoundedContainerHeight() {
        XCTAssertEqual(
            MembershipPaywallViewportClass(availableHeight: 419.5),
            .constrained
        )
        XCTAssertEqual(
            MembershipPaywallViewportClass(availableHeight: 420),
            .compact
        )
        XCTAssertEqual(
            MembershipPaywallViewportClass(availableHeight: 639.5),
            .compact
        )
        XCTAssertEqual(
            MembershipPaywallViewportClass(availableHeight: 640),
            .regular
        )
        XCTAssertEqual(
            MembershipPaywallViewportClass(availableHeight: .infinity),
            .regular
        )
    }

    func testMembershipPaywallPresentationHidesCheckoutForMembers() {
        let presentation = MembershipPaywallPresentation(isMember: true, accessibilitySize: true)
        let compact = MembershipPaywallPresentation(
            isMember: true,
            accessibilitySize: false,
            availableHeight: 568
        )

        XCTAssertEqual(
            presentation.sectionOrder,
            [.hero, .memberManagement, .benefits, .notice, .legal]
        )
        XCTAssertEqual(presentation.checkoutPlacement, .hidden)
        XCTAssertFalse(presentation.laysOutPlansSideBySide)
        XCTAssertEqual(presentation.contentDensity, .regular)
        XCTAssertEqual(presentation.offerIntroduction, .none)
        XCTAssertFalse(presentation.sectionOrder.contains(.offer))
        XCTAssertFalse(presentation.sectionOrder.contains(.valueProof))
        XCTAssertFalse(presentation.sectionOrder.contains(.restore))
        XCTAssertEqual(
            compact.sectionOrder,
            [.memberManagement, .hero, .benefits, .notice, .legal]
        )
        XCTAssertEqual(compact.checkoutPlacement, .hidden)
    }

    func testMembershipOfferTrustCopyNamesAppleRenewalAndCancellation() {
        XCTAssertEqual(
            MembershipPaywallPresentation.billingTrustText,
            "Apple billing · Auto-renews until canceled"
        )
        XCTAssertEqual(
            MembershipPaywallPresentation.subscriptionDisclosureText,
            "Payment is charged by Apple. Subscriptions renew automatically until canceled in App Store account settings."
        )
    }

    func testActivePlanPresentationUsesVerifiedRenewalAndEndCopy() throws {
        let context = try makeActivePlanDateContext()
        let periodEnd = try XCTUnwrap(
            context.calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 18)
            )
        )
        let annual = MembershipActivePlanPresentation(
            snapshot: makeActivePlanSnapshot(
                planKind: .annual,
                currentPeriodEnd: periodEnd,
                renewalDisposition: .renews
            ),
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )
        let monthly = MembershipActivePlanPresentation(
            snapshot: makeActivePlanSnapshot(
                planKind: .monthly,
                currentPeriodEnd: periodEnd,
                renewalDisposition: .ends
            ),
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )

        XCTAssertEqual(annual.planTitle, "Annual plan")
        XCTAssertEqual(annual.badgeText, "ACTIVE")
        XCTAssertEqual(annual.tone, .active)
        XCTAssertEqual(annual.statusText, "Renews Sep 18, 2026")
        XCTAssertEqual(annual.managementTitle, "Manage with Apple")
        XCTAssertTrue(annual.accessibilityLabel.contains("Renews Sep 18, 2026"))

        XCTAssertEqual(monthly.planTitle, "Monthly plan")
        XCTAssertEqual(monthly.statusText, "Access through Sep 18, 2026")
        XCTAssertEqual(
            monthly.supportText,
            "Your Pro benefits stay active through the current billing period."
        )
    }

    func testActivePlanPresentationDistinguishesScheduledChangeAndGrace() throws {
        let context = try makeActivePlanDateContext()
        let periodEnd = try XCTUnwrap(
            context.calendar.date(
                from: DateComponents(year: 2026, month: 10, day: 2)
            )
        )
        let scheduled = MembershipActivePlanPresentation(
            snapshot: makeActivePlanSnapshot(
                planKind: .annual,
                currentPeriodEnd: periodEnd,
                renewalDisposition: .changesTo(.monthly)
            ),
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )
        let grace = MembershipActivePlanPresentation(
            snapshot: makeActivePlanSnapshot(
                planKind: .monthly,
                renewalDisposition: .gracePeriod(until: periodEnd)
            ),
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )

        XCTAssertEqual(scheduled.badgeText, "SCHEDULED")
        XCTAssertEqual(scheduled.tone, .scheduled)
        XCTAssertEqual(scheduled.statusText, "Changes to Monthly on Oct 2, 2026")
        XCTAssertEqual(
            scheduled.supportText,
            "Your current plan stays active until the switch."
        )

        XCTAssertEqual(grace.badgeText, "NEEDS ATTENTION")
        XCTAssertEqual(grace.tone, .attention)
        XCTAssertEqual(
            grace.statusText,
            "Billing issue · Pro remains active through Oct 2, 2026"
        )
        XCTAssertEqual(
            grace.supportText,
            "Update payment details with Apple to keep Pro active."
        )
    }

    func testActivePlanPresentationAvoidsStaleDatesAndUnsupportedBillingClaims() throws {
        let context = try makeActivePlanDateContext()
        let pastDate = try XCTUnwrap(
            context.calendar.date(
                from: DateComponents(year: 2026, month: 8, day: 1)
            )
        )
        let noRenewalMetadata = MembershipActivePlanPresentation(
            snapshot: makeActivePlanSnapshot(
                planKind: .annual,
                currentPeriodEnd: pastDate,
                renewalDisposition: .active
            ),
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )
        let staleGrace = MembershipActivePlanPresentation(
            snapshot: makeActivePlanSnapshot(
                planKind: .monthly,
                renewalDisposition: .gracePeriod(until: pastDate)
            ),
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )

        XCTAssertEqual(noRenewalMetadata.statusText, "Active access verified by Apple")
        XCTAssertFalse(noRenewalMetadata.statusText.contains("Renews"))
        XCTAssertFalse(noRenewalMetadata.statusText.contains("Aug"))
        XCTAssertEqual(staleGrace.statusText, "Billing issue · Pro remains active")
        XCTAssertFalse(staleGrace.statusText.contains("Aug"))
    }

    func testActivePlanPresentationHandlesFamilySharingAndSnapshotFallback() {
        let family = MembershipActivePlanPresentation(
            snapshot: makeActivePlanSnapshot(
                planKind: .annual,
                renewalDisposition: .renews,
                ownership: .familyShared
            )
        )
        let fallback = MembershipActivePlanPresentation(snapshot: nil)

        XCTAssertEqual(family.statusText, "Shared through Family Sharing")
        XCTAssertEqual(family.supportText, "The purchaser manages billing with Apple.")
        XCTAssertEqual(family.managementTitle, "View Apple subscriptions")
        XCTAssertEqual(
            family.managementAccessibilityHint,
            "Shows subscriptions for this Apple Account. The purchaser manages the shared plan."
        )
        XCTAssertFalse(family.statusText.contains("Renews"))

        XCTAssertEqual(fallback.planTitle, "Checkpoint Pro")
        XCTAssertEqual(fallback.statusText, "Pro access is active")
        XCTAssertEqual(
            fallback.supportText,
            "Open Apple subscriptions for plan and billing details."
        )
        XCTAssertFalse(fallback.statusText.contains("verified"))
    }

    func testSubscriptionManagementScopeUsesVerifiedGroupWhenAvailable() {
        XCTAssertEqual(
            MembershipSubscriptionManagementScope(subscriptionGroupID: " checkpoint.pro "),
            .subscriptionGroup("checkpoint.pro")
        )
        XCTAssertEqual(
            MembershipSubscriptionManagementScope(subscriptionGroupID: nil),
            .allSubscriptions
        )
        XCTAssertEqual(
            MembershipSubscriptionManagementScope(subscriptionGroupID: "  "),
            .allSubscriptions
        )
        XCTAssertEqual(
            MembershipSubscriptionManagementScope(
                activePlanSnapshot: makeActivePlanSnapshot(
                    planKind: .annual,
                    renewalDisposition: .renews,
                    ownership: .familyShared
                )
            ),
            .allSubscriptions
        )
    }

    func testActivePlanMotionPolicyRespectsReduceMotion() {
        let animated = MembershipActivePlanMotionPolicy(reduceMotion: false)
        let reduced = MembershipActivePlanMotionPolicy(reduceMotion: true)

        XCTAssertEqual(animated.style, .animated)
        XCTAssertNotNil(animated.animation)
        XCTAssertTrue(animated.animatesSymbol)

        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
        XCTAssertFalse(reduced.animatesSymbol)
    }

    func testMembershipPlanAccessibilityLabelKeepsOfferDetailsInReadingOrder() {
        let option = MembershipPlanOption(
            id: MembershipProductID.yearly,
            title: "Annual",
            displayPrice: "$29.99",
            cadence: "per year",
            detail: "$2.50 per month when billed annually.",
            valueBadge: "Save 49%",
            isRecommended: true
        )

        XCTAssertEqual(
            option.accessibilityLabel,
            "Annual plan. $29.99 per year. $2.50 per month when billed annually. Save 49%. Best value."
        )
    }

    func testMembershipValuePreviewOverviewShowsTheCompleteWorkflowWithoutASpotlight() {
        let presentation = MembershipValuePreviewPresentation(context: .overview)

        XCTAssertEqual(presentation.nodes.map(\.id), [.focusedGoals, .freshCheckpoints, .nextFocus])
        XCTAssertEqual(presentation.nodes.map(\.title), ["Focused goals", "Fresh checkpoints", "Clear Next Focus"])
        XCTAssertEqual(presentation.nodes.map(\.compactTitle), ["Goals", "Fresh sets", "Next focus"])
        XCTAssertEqual(
            presentation.nodes.map(\.systemImage),
            ["square.stack.3d.up.fill", "sparkles", "scope"]
        )
        XCTAssertNil(presentation.highlightedNodeID)
        XCTAssertEqual(
            presentation.outcome,
            "Focused goals flow into fresh checkpoints and a clear Next Focus."
        )
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Pro workflow. Focused goals: Up to \(ProductLimits.memberGoalProfileLimit) separate goals. Fresh checkpoints: \(ProductLimits.memberQuestionBankTargetCount)-question practice target. Clear Next Focus: One priority from your progress. Focused goals flow into fresh checkpoints and a clear Next Focus."
        )
    }

    func testMembershipValuePreviewSpotlightsTheFeatureWorkflowNode() {
        let expectations: [(MembershipFeature, MembershipValuePreviewNode.ID, String)] = [
            (
                .goalProfiles,
                .focusedGoals,
                "Keep up to \(ProductLimits.memberGoalProfileLimit) goals separate and focused."
            ),
            (
                .freshQuestionGeneration,
                .freshCheckpoints,
                "Keep new checkpoints coming as your ready set runs low."
            ),
            (
                .largerQuestionBank,
                .freshCheckpoints,
                "Build toward an \(ProductLimits.memberQuestionBankTargetCount)-question bank for broader practice."
            ),
            (
                .adaptiveStudyAssist,
                .nextFocus,
                "Turn answer history into one clear next step."
            )
        ]

        for (feature, expectedNodeID, expectedOutcome) in expectations {
            let presentation = MembershipValuePreviewPresentation(context: .feature(feature))

            XCTAssertEqual(presentation.highlightedNodeID, expectedNodeID, feature.id)
            XCTAssertEqual(presentation.outcome, expectedOutcome, feature.id)
            let highlightedTitle = presentation.nodes.first(where: { $0.id == expectedNodeID })?.title ?? ""
            XCTAssertEqual(
                presentation.accessibilityLabel,
                "Pro workflow. Focused goals: Up to \(ProductLimits.memberGoalProfileLimit) separate goals. Fresh checkpoints: \(ProductLimits.memberQuestionBankTargetCount)-question practice target. Clear Next Focus: One priority from your progress. \(highlightedTitle) highlighted. \(expectedOutcome)",
                feature.id
            )
        }
    }

    func testMembershipValuePreviewCopyUsesProductLimits() throws {
        let overview = MembershipValuePreviewPresentation(context: .overview)
        let goalNode = try XCTUnwrap(overview.nodes.first(where: { $0.id == .focusedGoals }))
        let checkpointNode = try XCTUnwrap(overview.nodes.first(where: { $0.id == .freshCheckpoints }))

        XCTAssertEqual(goalNode.detail, "Up to \(ProductLimits.memberGoalProfileLimit) separate goals")
        XCTAssertEqual(
            checkpointNode.detail,
            "\(ProductLimits.memberQuestionBankTargetCount)-question practice target"
        )
        XCTAssertTrue(overview.accessibilityLabel.contains(goalNode.detail))
        XCTAssertTrue(overview.accessibilityLabel.contains(checkpointNode.detail))
    }

    func testMembershipValuePreviewMotionPolicyHonorsReduceMotion() {
        let animated = MembershipValuePreviewMotionPolicy(reduceMotion: false)
        XCTAssertEqual(animated.style, .stagedReveal)
        XCTAssertTrue(animated.animatesReveal)
        XCTAssertTrue(animated.animatesSymbol)
        XCTAssertEqual(animated.hiddenOpacity, 0)
        XCTAssertLessThan(animated.hiddenScale, 1)
        XCTAssertNotNil(animated.nodeAnimation(at: 0))
        XCTAssertNotNil(animated.connectorAnimation(after: 0))

        let reduced = MembershipValuePreviewMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertFalse(reduced.animatesReveal)
        XCTAssertFalse(reduced.animatesSymbol)
        XCTAssertEqual(reduced.hiddenOpacity, 1)
        XCTAssertEqual(reduced.hiddenScale, 1)
        XCTAssertNil(reduced.nodeAnimation(at: 0))
        XCTAssertNil(reduced.connectorAnimation(after: 0))
    }

    @MainActor
    func testMembershipValuePreviewRendersAcrossKeyLayouts() {
        let fixtures = [
            MembershipValuePreviewRenderFixture(
                name: "membership-value-preview-overview-light",
                context: .overview,
                width: 353,
                height: 300,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            MembershipValuePreviewRenderFixture(
                name: "membership-value-preview-feature-compact-dark",
                context: .feature(.largerQuestionBank),
                width: 280,
                height: 300,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            MembershipValuePreviewRenderFixture(
                name: "membership-value-preview-accessibility5-reduced-motion",
                context: .feature(.adaptiveStudyAssist),
                width: 353,
                height: 900,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true
            )
        ]

        for fixture in fixtures {
            autoreleasepool {
                let view = MembershipValuePreview(
                    presentation: MembershipValuePreviewPresentation(context: fixture.context),
                    reduceMotion: fixture.reduceMotion
                )
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CheckpointTheme.ink)
                .ignoresSafeArea()
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)

                let image = HostedViewRenderer.image(
                    for: view,
                    width: fixture.width,
                    height: fixture.height,
                    colorScheme: fixture.colorScheme,
                    settlingTime: fixture.reduceMotion ? 0.05 : 0.55,
                    renderScale: 1
                )

                XCTAssertEqual(image.size.width, fixture.width, accuracy: 1, fixture.name)
                XCTAssertEqual(image.size.height, fixture.height, accuracy: 1, fixture.name)
                let attachment = XCTAttachment(image: image)
                attachment.name = fixture.name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testStoreRoutesSettingsOverviewWithoutMasqueradingAsAFeatureGate() throws {
        let suiteName = "MembershipViewRenderingTests.route.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = CheckpointStore(defaults: defaults)

        store.requestMembershipOverview()
        XCTAssertEqual(store.pendingMembershipPresentation, .overview)
        XCTAssertNil(store.pendingMembershipFeature)

        store.requestMembership(for: .goalProfiles)
        XCTAssertEqual(store.pendingMembershipPresentation, .feature(.goalProfiles))
        XCTAssertEqual(store.pendingMembershipFeature, .goalProfiles)

        store.dismissMembershipPrompt()
        XCTAssertNil(store.pendingMembershipPresentation)
        XCTAssertNil(store.pendingMembershipFeature)
    }

    func testSettingsPlanPresentationIsStateHonestAndPrioritizesProAccess() throws {
        let annualOption = try XCTUnwrap(
            try makePlanOptions().first { $0.id == MembershipProductID.yearly }
        )
        let proActivity = SettingsProActivityPresentation(
            hasGoal: true,
            hasReadyCheckpoint: true,
            isMaintainingFreshCheckpoints: false,
            isQuestionGenerationBlockingPractice: false,
            questionBankTargetCount: 80,
            studyFocusState: .caughtUp,
            skillMapStatus: .reviewed,
            hasPracticeHistory: true,
            goalCount: 2,
            goalLimit: 5
        )
        let free = SettingsPlanPresentation(
            membershipTier: .starter,
            purchaseNotice: nil,
            proActivity: proActivity,
            upgradePlanOption: annualOption
        )
        let freeWithoutCatalog = SettingsPlanPresentation(
            membershipTier: .starter,
            purchaseNotice: nil
        )
        let freeWithUnavailableCatalog = SettingsPlanPresentation(
            membershipTier: .starter,
            purchaseNotice: .catalogUnavailable("Could not load App Store plans yet."),
            upgradePlanOption: annualOption
        )
        let pending = SettingsPlanPresentation(
            membershipTier: .starter,
            purchaseNotice: .pendingApproval,
            hasUnresolvedPurchase: true,
            proActivity: proActivity,
            upgradePlanOption: annualOption
        )
        let unconfirmed = SettingsPlanPresentation(
            membershipTier: .starter,
            purchaseNotice: .previousPurchaseUnconfirmed,
            hasUnresolvedPurchase: true,
            proActivity: proActivity,
            upgradePlanOption: annualOption
        )
        let pro = SettingsPlanPresentation(
            membershipTier: .member,
            purchaseNotice: .pendingApproval,
            hasUnresolvedPurchase: true,
            proActivity: proActivity,
            upgradePlanOption: annualOption
        )

        XCTAssertEqual(free.state, .free)
        XCTAssertEqual(free.planName, "Checkpoint Free")
        XCTAssertEqual(free.badgeText, "FREE")
        XCTAssertEqual(free.headline, "Protection for one focused goal.")
        XCTAssertEqual(
            free.detail,
            "Explore Pro for up to 5 goals, fresh checkpoints, and adaptive Next Focus."
        )
        XCTAssertEqual(free.actionTitle, "Explore Checkpoint Pro")
        XCTAssertEqual(free.accessibilityLabel, "Checkpoint Free")
        XCTAssertEqual(free.accessibilityHint, "Opens Checkpoint Pro plans.")
        XCTAssertNil(free.proActivity)
        XCTAssertEqual(free.upgradePlanOption, annualOption)
        XCTAssertTrue(free.accessibilityValue.contains("App Store price"))
        XCTAssertTrue(free.accessibilityValue.contains(annualOption.accessibilityLabel))
        XCTAssertNil(freeWithoutCatalog.upgradePlanOption)
        XCTAssertFalse(freeWithoutCatalog.accessibilityValue.contains("App Store price"))
        XCTAssertEqual(freeWithUnavailableCatalog.state, .free)
        XCTAssertNil(freeWithUnavailableCatalog.upgradePlanOption)
        XCTAssertFalse(
            freeWithUnavailableCatalog.accessibilityValue.contains(annualOption.displayPrice)
        )

        XCTAssertEqual(pending.state, .pendingPurchase)
        XCTAssertEqual(pending.badgeText, "PENDING")
        XCTAssertEqual(pending.headline, "The App Store is completing your purchase.")
        XCTAssertEqual(
            pending.detail,
            "Pro unlocks automatically when it finishes. You may need to take action in the App Store."
        )
        XCTAssertEqual(pending.actionTitle, "Check purchase status")
        XCTAssertEqual(pending.accessibilityLabel, "Checkpoint Pro purchase")
        XCTAssertEqual(
            pending.accessibilityValue,
            "Waiting for the App Store to complete this purchase. Pro unlocks automatically when it finishes. You may need to take action in the App Store."
        )
        XCTAssertEqual(pending.accessibilityHint, "Opens purchase status and plan options.")
        XCTAssertNil(pending.proActivity)
        XCTAssertNil(pending.upgradePlanOption)
        XCTAssertFalse(pending.accessibilityValue.contains(annualOption.displayPrice))

        XCTAssertEqual(unconfirmed.state, .unconfirmedPurchase)
        XCTAssertEqual(unconfirmed.badgeText, "UNCONFIRMED")
        XCTAssertEqual(unconfirmed.headline, "The App Store hasn’t completed this purchase.")
        XCTAssertEqual(
            unconfirmed.detail,
            "It may still complete. Check its status before starting another purchase."
        )
        XCTAssertEqual(unconfirmed.actionTitle, "Check purchase status")
        XCTAssertEqual(
            unconfirmed.accessibilityValue,
            "Unconfirmed App Store purchase. It may still complete."
        )
        XCTAssertNil(unconfirmed.proActivity)
        XCTAssertNil(unconfirmed.upgradePlanOption)
        XCTAssertFalse(unconfirmed.accessibilityValue.contains(annualOption.displayPrice))

        XCTAssertEqual(pro.state, .pro)
        XCTAssertEqual(pro.badgeText, "ACTIVE")
        XCTAssertEqual(pro.headline, "Pro is working in the background.")
        XCTAssertEqual(
            pro.detail,
            "Fresh checkpoints, adaptive guidance, and separate goal lanes stay ready as you practice."
        )
        XCTAssertEqual(pro.actionTitle, "View plan & billing")
        XCTAssertEqual(pro.accessibilityLabel, "Checkpoint Pro")
        XCTAssertEqual(pro.accessibilityHint, "Opens plan and billing.")
        XCTAssertEqual(pro.proActivity, proActivity)
        XCTAssertEqual(pro.activePlanPresentation?.statusText, "Pro access is active")
        XCTAssertTrue(pro.accessibilityValue.contains("Open Apple subscriptions"))
        XCTAssertNil(pro.upgradePlanOption)
        XCTAssertFalse(pro.accessibilityValue.contains(annualOption.displayPrice))
        XCTAssertTrue(pro.accessibilityValue.contains("Next Focus: Caught up for now"))
        XCTAssertTrue(pro.accessibilityValue.contains("Goal Lanes: 2 of 5 in use"))
    }

    func testSettingsPlanPresentationCarriesVerifiedPlanHealthWithoutAffectingOtherStates() throws {
        let context = try makeActivePlanDateContext()
        let periodEnd = try XCTUnwrap(
            context.calendar.date(
                from: DateComponents(year: 2026, month: 10, day: 2)
            )
        )
        let annualSnapshot = makeActivePlanSnapshot(
            planKind: .annual,
            currentPeriodEnd: periodEnd,
            renewalDisposition: .renews
        )
        let annual = SettingsPlanPresentation(
            membershipTier: .member,
            purchaseNotice: nil,
            activePlanSnapshot: annualSnapshot,
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )
        let ignoredWhileFree = SettingsPlanPresentation(
            membershipTier: .starter,
            purchaseNotice: nil,
            activePlanSnapshot: annualSnapshot
        )
        let ending = SettingsPlanPresentation(
            membershipTier: .member,
            purchaseNotice: nil,
            activePlanSnapshot: makeActivePlanSnapshot(
                planKind: .monthly,
                currentPeriodEnd: periodEnd,
                renewalDisposition: .ends
            ),
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )
        let scheduled = SettingsPlanPresentation(
            membershipTier: .member,
            purchaseNotice: nil,
            activePlanSnapshot: makeActivePlanSnapshot(
                planKind: .annual,
                currentPeriodEnd: periodEnd,
                renewalDisposition: .changesTo(.monthly)
            ),
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )
        let grace = SettingsPlanPresentation(
            membershipTier: .member,
            purchaseNotice: nil,
            activePlanSnapshot: makeActivePlanSnapshot(
                planKind: .monthly,
                renewalDisposition: .gracePeriod(until: periodEnd)
            ),
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )
        let family = SettingsPlanPresentation(
            membershipTier: .member,
            purchaseNotice: nil,
            activePlanSnapshot: makeActivePlanSnapshot(
                planKind: .annual,
                renewalDisposition: .renews,
                ownership: .familyShared
            ),
            now: context.now,
            locale: context.locale,
            calendar: context.calendar,
            timeZone: context.timeZone
        )

        XCTAssertEqual(annual.planName, "Checkpoint Pro · Annual")
        XCTAssertEqual(annual.accessibilityLabel, "Checkpoint Pro · Annual")
        XCTAssertEqual(annual.badgeText, "ACTIVE")
        XCTAssertEqual(annual.activePlanPresentation?.tone, .active)
        XCTAssertEqual(annual.activePlanPresentation?.statusText, "Renews Oct 2, 2026")
        XCTAssertTrue(annual.accessibilityValue.contains("Annual plan"))
        XCTAssertTrue(annual.accessibilityValue.contains("Renews Oct 2, 2026"))
        XCTAssertEqual(annual.visualStateKey.activePlanKind, .annual)
        XCTAssertEqual(
            annual.visualStateKey.activePlan,
            annual.activePlanPresentation?.visualStateKey
        )

        XCTAssertEqual(ending.activePlanPresentation?.statusText, "Access through Oct 2, 2026")
        XCTAssertTrue(ending.accessibilityValue.contains("current billing period"))

        XCTAssertEqual(scheduled.badgeText, "SCHEDULED")
        XCTAssertEqual(scheduled.activePlanPresentation?.tone, .scheduled)
        XCTAssertEqual(
            scheduled.activePlanPresentation?.statusText,
            "Changes to Monthly on Oct 2, 2026"
        )

        XCTAssertEqual(grace.badgeText, "NEEDS ATTENTION")
        XCTAssertEqual(grace.activePlanPresentation?.tone, .attention)
        XCTAssertTrue(grace.accessibilityValue.contains("Update payment details with Apple"))

        XCTAssertEqual(family.activePlanPresentation?.statusText, "Shared through Family Sharing")
        XCTAssertTrue(family.accessibilityValue.contains("purchaser manages billing"))
        XCTAssertEqual(family.actionTitle, "View plan & billing")

        XCTAssertEqual(ignoredWhileFree.planName, "Checkpoint Free")
        XCTAssertNil(ignoredWhileFree.activePlanKind)
        XCTAssertNil(ignoredWhileFree.activePlanPresentation)
        XCTAssertNil(ignoredWhileFree.visualStateKey.activePlan)
    }

    func testSettingsProActivityPresentationUsesTruthfulLiveStates() throws {
        let goal = makeLSATGoal()
        let longSkillName = "Reliability and failure recovery under distributed load"
        let recommendation = try XCTUnwrap(
            StudyFocusRecommendation(
                question: makeQuestion(
                    goal: goal,
                    index: 1,
                    topic: longSkillName
                ),
                skillID: nil,
                skillName: longSkillName,
                hasPracticeHistory: true
            )
        )
        let ready = SettingsProActivityPresentation(
            hasGoal: true,
            hasReadyCheckpoint: true,
            isMaintainingFreshCheckpoints: false,
            isQuestionGenerationBlockingPractice: false,
            questionBankTargetCount: 80,
            studyFocusState: .recommendation(recommendation),
            skillMapStatus: .reviewed,
            hasPracticeHistory: true,
            goalCount: 2,
            goalLimit: 5
        )

        XCTAssertEqual(
            ready.items.map(\.id),
            [.freshCheckpoints, .nextFocus, .goalLanes]
        )
        XCTAssertEqual(ready.freshCheckpoints.value, "Next checkpoint ready")
        XCTAssertEqual(ready.freshCheckpoints.detail, "80-question practice target")
        XCTAssertEqual(ready.freshCheckpoints.tone, .positive)
        XCTAssertEqual(ready.nextFocus.value, longSkillName)
        XCTAssertEqual(ready.nextFocus.detail, "Adaptive recommendation")
        XCTAssertEqual(ready.goalLanes.value, "2 of 5 in use")
        XCTAssertTrue(ready.accessibilityValue.contains(longSkillName))

        let refreshing = makeSettingsProActivity(
            hasReadyCheckpoint: true,
            isMaintaining: true
        )
        XCTAssertEqual(refreshing.freshCheckpoints.value, "Refreshing practice")
        XCTAssertEqual(refreshing.freshCheckpoints.tone, .informative)

        let preparing = makeSettingsProActivity(
            hasReadyCheckpoint: false,
            isMaintaining: true
        )
        XCTAssertEqual(preparing.freshCheckpoints.value, "Preparing checkpoint")

        let failure = makeSettingsProActivity(
            hasReadyCheckpoint: false,
            isMaintaining: true,
            isBlocking: true
        )
        XCTAssertEqual(failure.freshCheckpoints.value, "Needs attention")
        XCTAssertEqual(failure.freshCheckpoints.tone, .attention)
        XCTAssertEqual(failure.freshCheckpoints.detail, "Review Home to retry checkpoint setup")
        XCTAssertEqual(failure.headline, "Practice needs a little attention.")

        let caughtUp = makeSettingsProActivity(studyFocusState: .caughtUp)
        XCTAssertEqual(caughtUp.nextFocus.value, "Caught up for now")
        XCTAssertEqual(caughtUp.nextFocus.detail, "No review is due")

        let awaiting = makeSettingsProActivity(studyFocusState: .awaitingQuestion)
        XCTAssertEqual(awaiting.nextFocus.value, "Waiting for practice")

        let calibrating = makeSettingsProActivity(
            studyFocusState: nil,
            skillMapStatus: nil,
            hasPracticeHistory: true
        )
        XCTAssertEqual(calibrating.nextFocus.value, "Calibrating from your answers")
        XCTAssertEqual(calibrating.nextFocus.detail, "Next Focus is not ready yet")

        let suggested = makeSettingsProActivity(
            studyFocusState: nil,
            skillMapStatus: .suggested,
            hasPracticeHistory: true
        )
        XCTAssertEqual(suggested.nextFocus.value, "Skill map ready to review")
        XCTAssertEqual(suggested.nextFocus.detail, "Review it in Progress to unlock guidance")

        let suggestedBeforeFirstCheckpoint = makeSettingsProActivity(
            studyFocusState: nil,
            skillMapStatus: .suggested,
            hasPracticeHistory: false
        )
        XCTAssertEqual(suggestedBeforeFirstCheckpoint.nextFocus.value, "Skill map ready to review")

        let firstCheckpoint = makeSettingsProActivity(
            studyFocusState: nil,
            skillMapStatus: nil,
            hasPracticeHistory: false
        )
        XCTAssertEqual(firstCheckpoint.nextFocus.value, "Starts after your first checkpoint")

        let noGoal = makeSettingsProActivity(
            hasGoal: false,
            hasReadyCheckpoint: false,
            studyFocusState: nil,
            skillMapStatus: nil,
            hasPracticeHistory: false,
            goalCount: 0
        )
        XCTAssertEqual(noGoal.freshCheckpoints.value, "Ready for your first goal")
        XCTAssertEqual(noGoal.nextFocus.value, "Starts with your first goal")
        XCTAssertEqual(noGoal.goalLanes.value, "Ready for your first goal")
        XCTAssertEqual(noGoal.goalLanes.detail, "5 Pro goal lanes available")
        XCTAssertEqual(noGoal.headline, "Your Pro workspace is ready.")
    }

    @MainActor
    func testStoreExposesReadyProBackgroundMaintenanceWithoutBlockingPractice() throws {
        let suiteName = "SettingsProActivityStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let goal = makeLSATGoal()
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = .member
        store.goal = goal
        store.goalProfiles = [goal]
        store.questions = (1...store.unlockPolicy.questionsPerSession).map {
            makeQuestion(goal: goal, index: $0)
        }
        store.questionBatchState = .ready
        store.isQuestionBankTopOffInProgress = true

        XCTAssertTrue(store.hasReadyCheckpointSet)
        XCTAssertFalse(store.isPreparingActiveGoalQuestions)
        XCTAssertTrue(store.isMaintainingActiveGoalQuestions)

        store.membershipTier = .starter
        XCTAssertFalse(store.isMaintainingActiveGoalQuestions)
    }

    func testSettingsPlanMotionPolicyRespectsReduceMotion() {
        let animated = SettingsPlanMotionPolicy(reduceMotion: false)
        let reduced = SettingsPlanMotionPolicy(reduceMotion: true)

        XCTAssertEqual(animated.style, .animated)
        XCTAssertTrue(animated.animatesSymbol)
        XCTAssertNotNil(animated.animation)

        XCTAssertEqual(reduced.style, .identity)
        XCTAssertFalse(reduced.animatesSymbol)
        XCTAssertNil(reduced.animation)
    }

    @MainActor
    func testSettingsPlanCardRendersAcrossKeyLayoutsAndStates() throws {
        let planDateContext = try makeActivePlanDateContext()
        let futurePlanDate = try XCTUnwrap(
            planDateContext.calendar.date(
                from: DateComponents(year: 2026, month: 10, day: 2)
            )
        )
        let annualOption = try XCTUnwrap(
            try makePlanOptions().first { $0.id == MembershipProductID.yearly }
        )
        let longAnnualOption = try XCTUnwrap(
            try makeLongLocalizedPlanOptions().first {
                $0.id == MembershipProductID.yearly
            }
        )
        let fixtures = [
            SettingsPlanRenderFixture(
                name: "settings-plan-free-light",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: nil,
                    upgradePlanOption: annualOption
                ),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-free-long-localized-compact-dark",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: nil,
                    upgradePlanOption: longAnnualOption
                ),
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-free-long-localized-compact-accessibility3",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: nil,
                    upgradePlanOption: longAnnualOption
                ),
                width: 320,
                height: 1_800,
                colorScheme: .light,
                dynamicTypeSize: .accessibility3,
                reduceMotion: true
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pending-dark",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: .pendingApproval,
                    hasUnresolvedPurchase: true
                ),
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-unconfirmed-light",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: .previousPurchaseUnconfirmed,
                    hasUnresolvedPurchase: true
                ),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pending-accessibility5-dark",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: .pendingApproval,
                    hasUnresolvedPurchase: true
                ),
                width: 393,
                height: 1_200,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-unconfirmed-accessibility5-light",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: .previousPurchaseUnconfirmed,
                    hasUnresolvedPurchase: true
                ),
                width: 393,
                height: 1_200,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pro-ready-light",
                presentation: SettingsPlanPresentation(
                    membershipTier: .member,
                    purchaseNotice: nil,
                    proActivity: makeSettingsProActivity(
                        studyFocusState: .caughtUp,
                        goalCount: 2
                    ),
                    activePlanSnapshot: makeActivePlanSnapshot(
                        planKind: .annual,
                        currentPeriodEnd: futurePlanDate,
                        renewalDisposition: .renews
                    ),
                    now: planDateContext.now,
                    locale: planDateContext.locale,
                    calendar: planDateContext.calendar,
                    timeZone: planDateContext.timeZone
                ),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pro-refreshing-compact-dark",
                presentation: SettingsPlanPresentation(
                    membershipTier: .member,
                    purchaseNotice: nil,
                    proActivity: makeSettingsProActivity(
                        isMaintaining: true,
                        nextFocusValue: "Multi-stage causal inference with counterfactual calibration",
                        goalCount: 4
                    ),
                    activePlanSnapshot: makeActivePlanSnapshot(
                        planKind: .monthly,
                        currentPeriodEnd: futurePlanDate,
                        renewalDisposition: .renews
                    ),
                    now: planDateContext.now,
                    locale: planDateContext.locale,
                    calendar: planDateContext.calendar,
                    timeZone: planDateContext.timeZone
                ),
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pro-ending-compact-dark",
                presentation: SettingsPlanPresentation(
                    membershipTier: .member,
                    purchaseNotice: nil,
                    proActivity: makeSettingsProActivity(goalCount: 3),
                    activePlanSnapshot: makeActivePlanSnapshot(
                        planKind: .monthly,
                        currentPeriodEnd: futurePlanDate,
                        renewalDisposition: .ends
                    ),
                    now: planDateContext.now,
                    locale: planDateContext.locale,
                    calendar: planDateContext.calendar,
                    timeZone: planDateContext.timeZone
                ),
                width: 320,
                height: 760,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pro-change-scheduled-light",
                presentation: SettingsPlanPresentation(
                    membershipTier: .member,
                    purchaseNotice: nil,
                    proActivity: makeSettingsProActivity(goalCount: 3),
                    activePlanSnapshot: makeActivePlanSnapshot(
                        planKind: .annual,
                        currentPeriodEnd: futurePlanDate,
                        renewalDisposition: .changesTo(.monthly)
                    ),
                    now: planDateContext.now,
                    locale: planDateContext.locale,
                    calendar: planDateContext.calendar,
                    timeZone: planDateContext.timeZone
                ),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pro-grace-dark",
                presentation: SettingsPlanPresentation(
                    membershipTier: .member,
                    purchaseNotice: nil,
                    proActivity: makeSettingsProActivity(goalCount: 3),
                    activePlanSnapshot: makeActivePlanSnapshot(
                        planKind: .monthly,
                        renewalDisposition: .gracePeriod(until: futurePlanDate)
                    ),
                    now: planDateContext.now,
                    locale: planDateContext.locale,
                    calendar: planDateContext.calendar,
                    timeZone: planDateContext.timeZone
                ),
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pro-family-accessibility5",
                presentation: SettingsPlanPresentation(
                    membershipTier: .member,
                    purchaseNotice: nil,
                    proActivity: makeSettingsProActivity(goalCount: 3),
                    activePlanSnapshot: makeActivePlanSnapshot(
                        planKind: .annual,
                        renewalDisposition: .renews,
                        ownership: .familyShared
                    ),
                    now: planDateContext.now,
                    locale: planDateContext.locale,
                    calendar: planDateContext.calendar,
                    timeZone: planDateContext.timeZone
                ),
                width: 393,
                height: 1_800,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pro-accessibility5-reduce-motion",
                presentation: SettingsPlanPresentation(
                    membershipTier: .member,
                    purchaseNotice: nil,
                    proActivity: makeSettingsProActivity(
                        isMaintaining: true,
                        nextFocusValue: "Multi-stage causal inference with counterfactual calibration",
                        goalCount: 4
                    )
                ),
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-free-accessibility5-reduce-motion",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: nil,
                    upgradePlanOption: annualOption
                ),
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true
            )
        ]

        for fixture in fixtures {
            autoreleasepool {
                let layoutCapture = SettingsPlanLayoutCapture()
                let view = ScrollView {
                    SettingsPlanCard(
                        presentation: fixture.presentation,
                        reduceMotionOverride: fixture.reduceMotion,
                        layoutReporter: { element, frame in
                            layoutCapture.frames[element] = frame
                        },
                        action: {}
                    )
                    .padding(20)
                }
                .checkpointScreenBackground()
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)

                let image = HostedViewRenderer.image(
                    for: view,
                    width: fixture.width,
                    height: fixture.height,
                    colorScheme: fixture.colorScheme,
                    settlingTime: fixture.reduceMotion ? 0.05 : 0.55,
                    renderScale: 0.5
                )

                XCTAssertEqual(image.size.width, fixture.width, accuracy: 1)
                XCTAssertEqual(image.size.height, fixture.height, accuracy: 1)

                let card = try? XCTUnwrap(layoutCapture.frames[.card], fixture.name)
                let action = try? XCTUnwrap(layoutCapture.frames[.action], fixture.name)
                if let card, let action {
                    XCTAssertTrue(
                        card.insetBy(dx: -0.5, dy: -0.5).contains(action),
                        "\(fixture.name) action escaped the plan card"
                    )
                    XCTAssertGreaterThanOrEqual(
                        action.height,
                        43.5,
                        "\(fixture.name) plan action is below the 44-point affordance"
                    )
                }

                if fixture.presentation.activePlanPresentation != nil {
                    let subscriptionStatus = try? XCTUnwrap(
                        layoutCapture.frames[.subscriptionStatus],
                        fixture.name
                    )
                    if let card, let action, let subscriptionStatus {
                        XCTAssertGreaterThan(subscriptionStatus.width, 0, fixture.name)
                        XCTAssertGreaterThan(subscriptionStatus.height, 0, fixture.name)
                        XCTAssertTrue(
                            card.insetBy(dx: -0.5, dy: -0.5).contains(subscriptionStatus),
                            "\(fixture.name) subscription status escaped the plan card"
                        )
                        XCTAssertLessThanOrEqual(
                            subscriptionStatus.maxY,
                            action.minY + 0.5,
                            "\(fixture.name) subscription status overlaps the plan action"
                        )
                    }
                } else {
                    XCTAssertNil(
                        layoutCapture.frames[.subscriptionStatus],
                        "\(fixture.name) exposed subscription health outside the Pro state"
                    )
                }

                if fixture.presentation.upgradePlanOption != nil {
                    let upgradeOffer = try? XCTUnwrap(
                        layoutCapture.frames[.upgradeOffer],
                        fixture.name
                    )
                    if let card, let action, let upgradeOffer {
                        XCTAssertGreaterThan(upgradeOffer.width, 0, fixture.name)
                        XCTAssertGreaterThan(upgradeOffer.height, 0, fixture.name)
                        XCTAssertTrue(
                            card.insetBy(dx: -0.5, dy: -0.5).contains(upgradeOffer),
                            "\(fixture.name) price preview escaped the plan card"
                        )
                        XCTAssertLessThanOrEqual(
                            upgradeOffer.maxY,
                            action.minY + 0.5,
                            "\(fixture.name) price preview overlaps the plan action"
                        )
                    }
                } else {
                    XCTAssertNil(
                        layoutCapture.frames[.upgradeOffer],
                        "\(fixture.name) exposed a price preview outside the Free state"
                    )
                }

                if fixture.presentation.proActivity != nil,
                   let activity = try? XCTUnwrap(
                       layoutCapture.frames[.proActivity],
                       fixture.name
                   ) {
                    let rows = SettingsProActivityID.allCases.compactMap {
                        layoutCapture.frames[.proActivityRow($0)]
                    }
                    XCTAssertEqual(rows.count, SettingsProActivityID.allCases.count)
                    for row in rows {
                        XCTAssertTrue(
                            activity.insetBy(dx: -0.5, dy: -0.5).contains(row),
                            "\(fixture.name) activity row escaped its status surface"
                        )
                        XCTAssertGreaterThan(row.height, 0, fixture.name)
                    }
                    for (first, second) in zip(rows, rows.dropFirst()) {
                        XCTAssertLessThanOrEqual(
                            first.maxY,
                            second.minY + 0.5,
                            "\(fixture.name) activity rows overlap"
                        )
                    }

                    if let subscriptionStatus = layoutCapture.frames[.subscriptionStatus] {
                        XCTAssertLessThanOrEqual(
                            subscriptionStatus.maxY,
                            activity.minY + 0.5,
                            "\(fixture.name) subscription status overlaps Pro activity"
                        )
                    }
                }

                let attachment = XCTAttachment(image: image)
                attachment.name = fixture.name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func makeSettingsProActivity(
        hasGoal: Bool = true,
        hasReadyCheckpoint: Bool = true,
        isMaintaining: Bool = false,
        isBlocking: Bool = false,
        studyFocusState: StudyFocusState? = .caughtUp,
        nextFocusValue: String? = nil,
        skillMapStatus: SkillMapStatus? = .reviewed,
        hasPracticeHistory: Bool = true,
        goalCount: Int = 2
    ) -> SettingsProActivityPresentation {
        let resolvedStudyFocusState: StudyFocusState?
        if let nextFocusValue {
            let goal = makeLSATGoal()
            resolvedStudyFocusState = StudyFocusRecommendation(
                question: makeQuestion(goal: goal, index: 99, topic: nextFocusValue),
                skillID: nil,
                skillName: nextFocusValue,
                hasPracticeHistory: true
            ).map(StudyFocusState.recommendation)
        } else {
            resolvedStudyFocusState = studyFocusState
        }

        return SettingsProActivityPresentation(
            hasGoal: hasGoal,
            hasReadyCheckpoint: hasReadyCheckpoint,
            isMaintainingFreshCheckpoints: isMaintaining,
            isQuestionGenerationBlockingPractice: isBlocking,
            questionBankTargetCount: 80,
            studyFocusState: resolvedStudyFocusState,
            skillMapStatus: skillMapStatus,
            hasPracticeHistory: hasPracticeHistory,
            goalCount: goalCount,
            goalLimit: 5
        )
    }

    private func makeLegalLinks() throws -> LegalLinks {
        LegalLinks(
            privacyPolicyURL: try XCTUnwrap(URL(string: "https://example.com/privacy")),
            supportURL: try XCTUnwrap(URL(string: "https://example.com/support"))
        )
    }

    private func makePlanOptions() throws -> [MembershipPlanOption] {
        MembershipCatalogPresentation(
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
    }

    private func makeLongLocalizedPlanOptions() throws -> [MembershipPlanOption] {
        MembershipCatalogPresentation(
            storeProducts: [
                MembershipStoreProduct(
                    id: MembershipProductID.monthly,
                    price: try XCTUnwrap(Decimal(string: "1234.56")),
                    displayPrice: "US$1,234.56",
                    currencyCode: "USD",
                    locale: Locale(identifier: "en_US"),
                    billingPeriod: .month
                ),
                MembershipStoreProduct(
                    id: MembershipProductID.yearly,
                    price: try XCTUnwrap(Decimal(string: "12345.67")),
                    displayPrice: "US$12,345.67",
                    currencyCode: "USD",
                    locale: Locale(identifier: "en_US"),
                    billingPeriod: .year
                ),
            ]
        ).planOptions
    }

    private func makeActivePlanSnapshot(
        planKind: MembershipPlanKind,
        currentPeriodEnd: Date? = nil,
        renewalDisposition: MembershipRenewalDisposition,
        ownership: MembershipPlanOwnership = .purchased,
        subscriptionGroupID: String? = "checkpoint.pro"
    ) -> MembershipActivePlanSnapshot {
        let productID: String
        switch planKind {
        case .monthly:
            productID = MembershipProductID.monthly
        case .annual:
            productID = MembershipProductID.yearly
        }

        return MembershipActivePlanSnapshot(
            transactionID: planKind == .annual ? 100 : 101,
            productID: productID,
            planKind: planKind,
            subscriptionGroupID: subscriptionGroupID,
            purchaseDate: Date(timeIntervalSince1970: 1_780_000_000),
            currentPeriodEnd: currentPeriodEnd,
            renewalDisposition: renewalDisposition,
            ownership: ownership
        )
    }

    private func makeActivePlanDateContext() throws -> ActivePlanDateContext {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))
        )
        return ActivePlanDateContext(
            now: now,
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            timeZone: timeZone
        )
    }

    @MainActor
    private func renderMembershipFixtures(
        _ fixtures: [MembershipRenderFixture],
        legalLinks: LegalLinks
    ) throws {
        var defaultsSuites: [String] = []
        defer {
            for suiteName in defaultsSuites {
                UserDefaults.standard.removePersistentDomain(forName: suiteName)
            }
        }

        for fixture in fixtures {
            let suiteName = "MembershipViewRenderingTests.\(fixture.name).\(UUID().uuidString)"
            defaultsSuites.append(suiteName)

            try autoreleasepool {
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
                let store = CheckpointStore(defaults: defaults)
                let layoutCapture = MembershipPaywallLayoutCapture()
                if fixture.isMember {
                    store.updateMembershipTier(.member)
                }

                let initialStoreOperation: MembershipStoreOperation? = fixture.isLoading
                    ? .loadingProducts
                    : nil
                if let pendingPurchaseRecord = fixture.pendingPurchaseRecord {
                    MembershipPendingPurchasePersistence(defaults: defaults).save(
                        pendingPurchaseRecord
                    )
                }
                let purchaseController = PurchaseController(
                    grantsDebugTesterEntitlement: false,
                    initialStoreOperation: initialStoreOperation,
                    initialActivePlanSnapshot: fixture.activePlanSnapshot,
                    pendingPurchaseDefaults: defaults,
                    currentDate: { fixture.currentDate }
                )
                if let purchaseNotice = fixture.purchaseNotice {
                    purchaseController.purchaseNotice = purchaseNotice
                }

                let view = MembershipView(
                    context: fixture.context,
                    store: store,
                    purchaseController: purchaseController,
                    renderConfiguration: MembershipViewRenderConfiguration(
                        planOptions: fixture.planOptions,
                        selectedPlanID: fixture.selectedPlanID,
                        legalLinks: legalLinks,
                        reduceMotion: fixture.reduceMotion,
                        activationPresentation: fixture.activationPresentation,
                        layoutReporter: { element, frame in
                            layoutCapture.frames[element] = frame
                        }
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
                if fixture.activationPresentation != nil,
                   let action = try? XCTUnwrap(
                       layoutCapture.frames[.activationAction],
                       fixture.name
                   ) {
                    XCTAssertGreaterThanOrEqual(
                        action.height,
                        43.5,
                        "\(fixture.name) activation action is below the 44-point affordance"
                    )
                    XCTAssertGreaterThanOrEqual(action.minX, -0.5, fixture.name)
                    XCTAssertLessThanOrEqual(action.maxX, fixture.width + 0.5, fixture.name)
                    XCTAssertGreaterThanOrEqual(action.minY, -0.5, fixture.name)
                    XCTAssertLessThanOrEqual(action.maxY, fixture.height + 0.5, fixture.name)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = fixture.name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}

private struct ActivePlanDateContext {
    let now: Date
    let locale: Locale
    let calendar: Calendar
    let timeZone: TimeZone
}

@MainActor
private final class MembershipPaywallLayoutCapture {
    var frames: [MembershipPaywallLayoutElement: CGRect] = [:]
}

private struct MembershipCompactFirstFoldFixture {
    let name: String
    let context: MembershipPresentationContext
    let planOptions: [MembershipPlanOption]
    let selectedPlanID: String
}

private struct MembershipInlineCheckoutFixture {
    let name: String
    let dynamicTypeSize: DynamicTypeSize
    var purchaseNotice: MembershipPurchaseNotice?
    var pendingPurchaseRecord: MembershipPendingPurchaseRecord?
    var currentDate: Date
    var width: CGFloat
    var height: CGFloat

    init(
        name: String,
        dynamicTypeSize: DynamicTypeSize,
        purchaseNotice: MembershipPurchaseNotice? = nil,
        pendingPurchaseRecord: MembershipPendingPurchaseRecord? = nil,
        currentDate: Date = Date(timeIntervalSince1970: 1_800_000_000),
        width: CGFloat = 320,
        height: CGFloat = 568
    ) {
        self.name = name
        self.dynamicTypeSize = dynamicTypeSize
        self.purchaseNotice = purchaseNotice
        self.pendingPurchaseRecord = pendingPurchaseRecord
        self.currentDate = currentDate
        self.width = width
        self.height = height
    }
}

private struct MembershipActiveReceiptLayoutFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let snapshot: MembershipActivePlanSnapshot
}

private struct MembershipRenderFixture {
    let name: String
    let context: MembershipPresentationContext
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    var reduceMotion = false
    var planOptions: [MembershipPlanOption] = []
    var selectedPlanID: String?
    var isLoading = false
    var purchaseNotice: MembershipPurchaseNotice?
    var pendingPurchaseRecord: MembershipPendingPurchaseRecord?
    var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
    var isMember = false
    var activationPresentation: MembershipActivationPresentation?
    var activePlanSnapshot: MembershipActivePlanSnapshot?
}

private struct MembershipValuePreviewRenderFixture {
    let name: String
    let context: MembershipPresentationContext
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    var reduceMotion = false
}

private struct SettingsPlanRenderFixture {
    let name: String
    let presentation: SettingsPlanPresentation
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    var reduceMotion = false
}

@MainActor
private final class SettingsPlanLayoutCapture {
    var frames: [SettingsPlanLayoutElement: CGRect] = [:]
}
