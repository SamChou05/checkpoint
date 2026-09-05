import SwiftUI
import XCTest
@testable import Checkpoint

final class MembershipViewRenderingTests: XCTestCase {
    @MainActor
    func testMembershipJourneyRendersAcrossKeyLayoutsAndStates() throws {
        let legalLinks = try makeLegalLinks()
        let planOptions = try makePlanOptions()

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
                purchaseNotice: .pendingApproval
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
            )
        ]

        try renderMembershipFixtures(fixtures, legalLinks: legalLinks)
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
                targetGoalID: targetGoalID,
                targetTitle: "Design portfolio"
            )
        )
        let overview = MembershipActivationPresentation(
            id: UUID(uuidString: "A941302A-7E60-47F4-A688-D24F721C4C21")!,
            context: .overview,
            source: .entitlementRefresh,
            continuation: nil
        )

        XCTAssertEqual(create.eyebrow, "PURCHASE COMPLETE")
        XCTAssertEqual(create.title, "Checkpoint Pro is yours.")
        XCTAssertEqual(create.actionTitle, "Create your next goal")
        XCTAssertEqual(create.actionSystemImage, "plus")
        XCTAssertTrue(create.detail.contains("next goal"))

        XCTAssertEqual(goalSwitch.eyebrow, "ACCESS RESTORED")
        XCTAssertEqual(goalSwitch.title, "Pro access restored.")
        XCTAssertEqual(goalSwitch.actionTitle, "Continue to Design portfolio")
        XCTAssertTrue(goalSwitch.detail.contains("Design portfolio"))

        XCTAssertEqual(overview.eyebrow, "ACCESS CONFIRMED")
        XCTAssertEqual(overview.actionTitle, "Continue")
        XCTAssertEqual(overview.actionSystemImage, "checkmark")
        XCTAssertTrue(overview.accessibilityAnnouncement.contains(overview.detail))
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
                        targetGoalID: UUID(uuidString: "B738CD41-D9CD-4E85-9B74-5FB9017C0ED2")!,
                        targetTitle: "Design portfolio"
                    )
                )
            ),
            MembershipRenderFixture(
                name: "membership-activated-accessibility5-reduced-motion",
                context: .overview,
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                reduceMotion: true,
                isMember: true,
                activationPresentation: MembershipActivationPresentation(
                    id: UUID(uuidString: "5A7CE487-FE62-4034-A1F7-4CB34A94B5CA")!,
                    context: .overview,
                    source: .entitlementRefresh,
                    continuation: nil
                )
            )
        ]

        try renderMembershipFixtures(fixtures, legalLinks: legalLinks)
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

        XCTAssertEqual(regular.sectionOrder, regularOrder)
        XCTAssertEqual(regular.checkoutPlacement, .sticky)
        XCTAssertTrue(regular.laysOutPlansSideBySide)

        XCTAssertEqual(accessible.sectionOrder, accessibleOrder)
        XCTAssertEqual(accessible.checkoutPlacement, .afterPlanChoices)
        XCTAssertFalse(accessible.laysOutPlansSideBySide)

        XCTAssertEqual(largeText.sectionOrder, regularOrder)
        XCTAssertEqual(largeText.checkoutPlacement, .sticky)
        XCTAssertFalse(largeText.laysOutPlansSideBySide)

        XCTAssertLessThan(
            regularOrder.firstIndex(of: .offer) ?? .max,
            regularOrder.firstIndex(of: .valueProof) ?? .max
        )
        XCTAssertLessThan(
            accessibleOrder.firstIndex(of: .offer) ?? .max,
            accessibleOrder.firstIndex(of: .valueProof) ?? .max
        )
    }

    func testMembershipPaywallPresentationHidesCheckoutForMembers() {
        let presentation = MembershipPaywallPresentation(isMember: true, accessibilitySize: true)

        XCTAssertEqual(
            presentation.sectionOrder,
            [.hero, .memberManagement, .benefits, .notice, .legal]
        )
        XCTAssertEqual(presentation.checkoutPlacement, .hidden)
        XCTAssertFalse(presentation.laysOutPlansSideBySide)
        XCTAssertFalse(presentation.sectionOrder.contains(.offer))
        XCTAssertFalse(presentation.sectionOrder.contains(.valueProof))
        XCTAssertFalse(presentation.sectionOrder.contains(.restore))
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

    func testSettingsPlanPresentationIsStateHonestAndPrioritizesProAccess() {
        let free = SettingsPlanPresentation(
            membershipTier: .starter,
            purchaseNotice: nil
        )
        let pending = SettingsPlanPresentation(
            membershipTier: .starter,
            purchaseNotice: .pendingApproval
        )
        let pro = SettingsPlanPresentation(
            membershipTier: .member,
            purchaseNotice: .pendingApproval
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

        XCTAssertEqual(pending.state, .pendingPurchase)
        XCTAssertEqual(pending.badgeText, "PENDING")
        XCTAssertEqual(pending.headline, "Your purchase is awaiting approval.")
        XCTAssertEqual(pending.detail, "Pro unlocks as soon as the App Store confirms it.")
        XCTAssertEqual(pending.actionTitle, "Check purchase status")
        XCTAssertEqual(pending.accessibilityLabel, "Checkpoint Pro purchase")
        XCTAssertEqual(pending.accessibilityHint, "Opens purchase status and plan options.")

        XCTAssertEqual(pro.state, .pro)
        XCTAssertEqual(pro.badgeText, "PRO ACTIVE")
        XCTAssertEqual(pro.headline, "Your practice stays in motion.")
        XCTAssertEqual(
            pro.detail,
            "Up to 5 focused goals, fresh checkpoints, and adaptive Next Focus are unlocked."
        )
        XCTAssertEqual(pro.actionTitle, "View plan & billing")
        XCTAssertEqual(pro.accessibilityLabel, "Checkpoint Pro")
        XCTAssertEqual(pro.accessibilityHint, "Opens plan and billing.")
    }

    func testSettingsPlanMotionPolicyRespectsReduceMotion() {
        let animated = SettingsPlanMotionPolicy(reduceMotion: false)
        let reduced = SettingsPlanMotionPolicy(reduceMotion: true)

        XCTAssertEqual(animated.style, .animated)
        XCTAssertTrue(animated.animatesSymbol)
        XCTAssertLessThan(animated.pressedScale, 1)
        XCTAssertNotNil(animated.animation)

        XCTAssertEqual(reduced.style, .identity)
        XCTAssertFalse(reduced.animatesSymbol)
        XCTAssertEqual(reduced.pressedScale, 1)
        XCTAssertNil(reduced.animation)
    }

    @MainActor
    func testSettingsPlanCardRendersAcrossKeyLayoutsAndStates() {
        let fixtures = [
            SettingsPlanRenderFixture(
                name: "settings-plan-free-light",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: nil
                ),
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pending-dark",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: .pendingApproval
                ),
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-pro-compact-dark",
                presentation: SettingsPlanPresentation(
                    membershipTier: .member,
                    purchaseNotice: nil
                ),
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large
            ),
            SettingsPlanRenderFixture(
                name: "settings-plan-free-accessibility5-reduce-motion",
                presentation: SettingsPlanPresentation(
                    membershipTier: .starter,
                    purchaseNotice: nil
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
                let view = ScrollView {
                    SettingsPlanCard(
                        presentation: fixture.presentation,
                        reduceMotionOverride: fixture.reduceMotion,
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
                let attachment = XCTAttachment(image: image)
                attachment.name = fixture.name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
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
                    context: fixture.context,
                    store: store,
                    purchaseController: purchaseController,
                    renderConfiguration: MembershipViewRenderConfiguration(
                        planOptions: fixture.planOptions,
                        selectedPlanID: fixture.selectedPlanID,
                        legalLinks: legalLinks,
                        reduceMotion: fixture.reduceMotion,
                        activationPresentation: fixture.activationPresentation
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
    var isMember = false
    var activationPresentation: MembershipActivationPresentation?
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
