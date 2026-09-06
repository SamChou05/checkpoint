import Accessibility
import StoreKit
import SwiftUI

enum MembershipPaywallLayoutElement: Hashable {
    case viewport
    case section(MembershipPaywallSection)
    case plan(String)
    case compactValueProof
    case selectedPlanSupport
    case subscriptionDisclosure
    case checkoutBar
    case secondaryAction
    case primaryAction
    case memberPlanReceipt
    case memberPlanIdentity
    case memberPlanBadge
    case memberManagementAction
    case activationReceipt
    case activationAction
    case activationVerificationViewport
    case activationVerificationContent
}

private let membershipPaywallLayoutCoordinateSpaceName = "Checkpoint.MembershipPaywall.Layout"

private struct MembershipPaywallLayoutFrameReporter: ViewModifier {
    let element: MembershipPaywallLayoutElement
    let report: (@MainActor (MembershipPaywallLayoutElement, CGRect) -> Void)?

    func body(content: Content) -> some View {
        content.background {
            if let report {
                GeometryReader { proxy in
                    let frame = proxy.frame(
                        in: .named(membershipPaywallLayoutCoordinateSpaceName)
                    )

                    Color.clear
                        .onAppear {
                            report(element, frame)
                        }
                        .onChange(of: frame) { _, updatedFrame in
                            report(element, updatedFrame)
                        }
                }
            }
        }
    }
}

private extension View {
    func reportMembershipPaywallLayoutFrame(
        _ element: MembershipPaywallLayoutElement,
        using report: (@MainActor (MembershipPaywallLayoutElement, CGRect) -> Void)?
    ) -> some View {
        modifier(MembershipPaywallLayoutFrameReporter(element: element, report: report))
    }
}

private struct MembershipSubscriptionManagementSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let scope: MembershipSubscriptionManagementScope

    @ViewBuilder
    func body(content: Content) -> some View {
        switch scope {
        case .allSubscriptions:
            content.manageSubscriptionsSheet(isPresented: $isPresented)
        case .subscriptionGroup(let groupID):
            content.manageSubscriptionsSheet(
                isPresented: $isPresented,
                subscriptionGroupID: groupID
            )
        }
    }
}

struct MembershipViewRenderConfiguration {
    let planOptions: [MembershipPlanOption]
    let selectedPlanID: String?
    let legalLinks: LegalLinks
    let reduceMotion: Bool
    let activationPresentation: MembershipActivationPresentation?
    let layoutReporter: (@MainActor (MembershipPaywallLayoutElement, CGRect) -> Void)?
    let purchaseAction: (String?) -> Void
    let reloadAction: () -> Void
    let restoreAction: () -> Void
    let checkPurchaseStatusAction: () -> Void

    init(
        planOptions: [MembershipPlanOption],
        selectedPlanID: String?,
        legalLinks: LegalLinks,
        reduceMotion: Bool = false,
        activationPresentation: MembershipActivationPresentation? = nil,
        layoutReporter: (@MainActor (MembershipPaywallLayoutElement, CGRect) -> Void)? = nil,
        purchaseAction: @escaping (String?) -> Void = { _ in },
        reloadAction: @escaping () -> Void = {},
        restoreAction: @escaping () -> Void = {},
        checkPurchaseStatusAction: @escaping () -> Void = {}
    ) {
        self.planOptions = planOptions
        self.selectedPlanID = selectedPlanID
        self.legalLinks = legalLinks
        self.reduceMotion = reduceMotion
        self.activationPresentation = activationPresentation
        self.layoutReporter = layoutReporter
        self.purchaseAction = purchaseAction
        self.reloadAction = reloadAction
        self.restoreAction = restoreAction
        self.checkPurchaseStatusAction = checkPurchaseStatusAction
    }
}

enum MembershipActivationMotionStyle: Equatable {
    case reveal
    case identity
}

struct MembershipActivationMotionPolicy {
    let reduceMotion: Bool

    var style: MembershipActivationMotionStyle {
        reduceMotion ? .identity : .reveal
    }

    var animation: Animation? {
        CheckpointMotion.animation(CheckpointMotion.reveal, reduceMotion: reduceMotion)
    }

    var hiddenOpacity: Double { reduceMotion ? 1 : 0 }
    var hiddenScale: CGFloat { reduceMotion ? 1 : 0.84 }
    var hiddenRotation: Angle { reduceMotion ? .zero : .degrees(-34) }
    var animatesSymbol: Bool { !reduceMotion }
}

enum MembershipActivePlanMotionStyle: Equatable {
    case animated
    case identity
}

struct MembershipActivePlanMotionPolicy {
    let style: MembershipActivePlanMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .animated
    }

    var animation: Animation? {
        style == .animated ? CheckpointMotion.change : nil
    }

    var animatesSymbol: Bool {
        style == .animated
    }
}

struct MembershipActivationFeedbackTaskID: Hashable {
    let presentationID: UUID?
    let isSceneActive: Bool
}

struct MembershipActivationFeedbackState: Equatable {
    private(set) var deliveredPresentationID: UUID?

    mutating func take(
        _ presentation: MembershipActivationPresentation?,
        isSceneActive: Bool
    ) -> String? {
        guard isSceneActive,
              let presentation,
              deliveredPresentationID != presentation.id else {
            return nil
        }
        deliveredPresentationID = presentation.id
        return presentation.accessibilityAnnouncement
    }
}

struct MembershipView: View {
    let context: MembershipPresentationContext
    let store: CheckpointStore
    let purchaseController: PurchaseController

    private let legalLinks: LegalLinks
    private let planOptionsOverride: [MembershipPlanOption]?
    private let performsStoreKitLoading: Bool
    private let reduceMotionOverride: Bool?
    private let renderPurchaseAction: ((String?) -> Void)?
    private let renderReloadAction: (() -> Void)?
    private let renderRestoreAction: (() -> Void)?
    private let renderCheckPurchaseStatusAction: (() -> Void)?
    private let layoutReporter: (@MainActor (MembershipPaywallLayoutElement, CGRect) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedProductID: String?
    @State private var selectionFeedbackSequence = 0
    @State private var activationPresentation: MembershipActivationPresentation?
    @State private var activationFeedback = MembershipActivationFeedbackState()
    @State private var activationFeedbackSequence = 0
    @State private var isActivationRevealed = false
    @State private var activationActionNotice: String?
    @State private var isSubscriptionManagementPresented = false

    init(
        context: MembershipPresentationContext,
        store: CheckpointStore,
        purchaseController: PurchaseController,
        renderConfiguration: MembershipViewRenderConfiguration? = nil
    ) {
        self.context = context
        self.store = store
        self.purchaseController = purchaseController
        legalLinks = renderConfiguration?.legalLinks ?? .current
        planOptionsOverride = renderConfiguration?.planOptions
        performsStoreKitLoading = renderConfiguration == nil
        reduceMotionOverride = renderConfiguration?.reduceMotion
        renderPurchaseAction = renderConfiguration?.purchaseAction
        renderReloadAction = renderConfiguration?.reloadAction
        renderRestoreAction = renderConfiguration?.restoreAction
        renderCheckPurchaseStatusAction = renderConfiguration?.checkPurchaseStatusAction
        layoutReporter = renderConfiguration?.layoutReporter
        _selectedProductID = State(initialValue: renderConfiguration?.selectedPlanID)
        let liveActivationPresentation = store.membershipActivationPresentationIfVerified(
            fallbackContext: context,
            fallbackSource: .entitlementRefresh
        )
        _activationPresentation = State(
            initialValue: renderConfiguration?.activationPresentation
                ?? liveActivationPresentation
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let activationPresentation {
                    membershipActivationContent(activationPresentation)
                } else if isAwaitingActivationPresentation {
                    membershipActivationVerificationContent
                } else {
                    paywallContent
                }
            }
            .navigationTitle(navigationTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if !isAwaitingActivationPresentation {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(activationPresentation == nil ? "Done" : "Close") {
                            close()
                        }
                        .foregroundStyle(CheckpointTheme.teal)
                        .disabled(purchaseController.isCheckoutActionInProgress)
                    }
                }
            }
            .task {
                guard performsStoreKitLoading else {
                    selectDefaultPlanIfNeeded()
                    return
                }
                purchaseController.startListeningForTransactions()
                await loadEntitlements()
                if purchaseController.isMembershipUnlocked,
                   activationPresentation == nil,
                   store.hasMembershipActivationReceipt {
                    presentActivation(source: .entitlementRefresh)
                }
                selectDefaultPlanIfNeeded()
            }
            .onChange(of: planOptions.map(\.id)) { _, _ in
                selectDefaultPlanIfNeeded()
            }
            .onChange(of: purchaseController.purchaseNotice) { _, notice in
                guard let notice else { return }
                AccessibilityNotification.Announcement(notice.message).post()
            }
            .onChange(of: store.isMember) { wasMember, isMember in
                guard !wasMember, isMember else { return }
                presentActivation(source: activationSourceForEntitlementChange)
            }
            .task(id: activationFeedbackTaskID) {
                deliverActivationFeedbackIfPossible()
            }
            .sensoryFeedback(.selection, trigger: selectionFeedbackSequence)
            .sensoryFeedback(.success, trigger: activationFeedbackSequence)
        }
        .coordinateSpace(name: membershipPaywallLayoutCoordinateSpaceName)
        .interactiveDismissDisabled(
            activationPresentation != nil
                || isAwaitingActivationPresentation
                || purchaseController.isCheckoutActionInProgress
        )
        .modifier(
            MembershipSubscriptionManagementSheetModifier(
                isPresented: $isSubscriptionManagementPresented,
                scope: subscriptionManagementScope
            )
        )
        .onChange(of: isSubscriptionManagementPresented) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
            Task {
                _ = await purchaseController.refreshEntitlements()
            }
        }
    }

    private var navigationTitle: String {
        if activationPresentation != nil {
            return "Pro active"
        }
        if isAwaitingActivationPresentation {
            return "Confirming Pro"
        }
        return store.isMember ? "Your Plan" : "Checkpoint Pro"
    }

    private var isAwaitingActivationPresentation: Bool {
        activationPresentation == nil && store.hasMembershipActivationReceipt
    }

    private var membershipActivationVerificationContent: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(CheckpointTheme.teal)
                        .accessibilityHidden(true)
                    Text("Confirming your Pro access…")
                        .font(.headline)
                        .foregroundStyle(CheckpointTheme.ink)
                    Text("Keep this screen open while Checkpoint verifies your purchase with the App Store.")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .reportMembershipPaywallLayoutFrame(
                    .activationVerificationContent,
                    using: layoutReporter
                )
            }
            .scrollIndicators(.hidden)
            .reportMembershipPaywallLayoutFrame(
                .activationVerificationViewport,
                using: layoutReporter
            )
        }
        .checkpointScreenBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Confirming your Pro access. Keep this screen open while Checkpoint verifies your purchase with the App Store."
        )
    }

    private var paywallContent: some View {
        GeometryReader { proxy in
            let presentation = paywallPresentation(availableHeight: proxy.size.height)

            ScrollView {
                VStack(alignment: .leading, spacing: presentation.contentDensity == .compact ? 13 : 16) {
                    ForEach(presentation.sectionOrder, id: \.self) { section in
                        paywallSection(section, presentation: presentation)
                            .reportMembershipPaywallLayoutFrame(
                                .section(section),
                                using: layoutReporter
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, presentation.contentDensity == .compact ? 9 : 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .checkpointScreenBackground()
            .reportMembershipPaywallLayoutFrame(.viewport, using: layoutReporter)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if presentation.checkoutPlacement == .sticky {
                    purchaseBar(presentation: presentation)
                        .reportMembershipPaywallLayoutFrame(.checkoutBar, using: layoutReporter)
                }
            }
        }
    }

    private func membershipActivationContent(
        _ presentation: MembershipActivationPresentation
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                activationHero(presentation)
                activationBenefits
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .checkpointScreenBackground()
        .reportMembershipPaywallLayoutFrame(.activationReceipt, using: layoutReporter)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            activationActionBar(presentation)
        }
        .onAppear {
            revealActivation()
        }
    }

    private func activationHero(
        _ presentation: MembershipActivationPresentation
    ) -> some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.mint,
            glowOpacity: 0.15,
            glowDiameter: 230,
            glowBlurRadius: 18,
            glowOffset: CGSize(width: 92, height: -98),
            contentPadding: dynamicTypeSize.isAccessibilitySize ? 18 : 22
        ) {
            VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 20) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        activationEyebrow(presentation)
                        Spacer(minLength: 8)
                        activationStatusBadge
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        activationEyebrow(presentation)
                        activationStatusBadge
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                MembershipActivationMark(
                    isRevealed: isActivationRevealed,
                    motionPolicy: activationMotionPolicy
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 9) {
                    Text(presentation.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(CheckpointTheme.heroText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(presentation.detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CheckpointTheme.heroMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(isActivationRevealed ? 1 : activationMotionPolicy.hiddenOpacity)
                .scaleEffect(isActivationRevealed ? 1 : 0.97)
                .animation(activationMotionPolicy.animation, value: isActivationRevealed)

                Label("Verified through the App Store", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.mint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(
                        maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                        alignment: .leading
                    )
                    .background {
                        if dynamicTypeSize.isAccessibilitySize {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(CheckpointTheme.mint.opacity(0.10))
                        } else {
                            Capsule()
                                .fill(CheckpointTheme.mint.opacity(0.10))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private func activationEyebrow(
        _ presentation: MembershipActivationPresentation
    ) -> some View {
        Label(presentation.eyebrow, systemImage: "sparkles")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.mint)
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var activationStatusBadge: some View {
        Label("PRO ACTIVE", systemImage: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.mint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(CheckpointTheme.mint.opacity(0.10), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var activationBenefits: some View {
        SectionPanel("Ready with Pro") {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    activationBenefitItems
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    activationBenefitItems
                }
            }
        }
        .opacity(isActivationRevealed ? 1 : activationMotionPolicy.hiddenOpacity)
        .offset(y: isActivationRevealed || reduceMotion ? 0 : 10)
        .animation(activationMotionPolicy.animation, value: isActivationRevealed)
    }

    @ViewBuilder
    private var activationBenefitItems: some View {
        activationBenefit(title: "Focused goals", systemImage: "square.stack.3d.up.fill")
        activationBenefit(title: "Fresh practice", systemImage: "sparkles")
        activationBenefit(title: "Next Focus", systemImage: "scope")
    }

    private func activationBenefit(title: String, systemImage: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 11) {
                    activationBenefitIcon(systemImage)
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    activationBenefitIcon(systemImage)
                    Text(title)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(CheckpointTheme.text)
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(
            CheckpointTheme.panelRaised.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func activationBenefitIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(width: 30, height: 30)
            .background(CheckpointTheme.teal.opacity(0.10), in: Circle())
            .accessibilityHidden(true)
    }

    private func activationActionBar(
        _ presentation: MembershipActivationPresentation
    ) -> some View {
        VStack(spacing: 8) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            if let activationActionNotice {
                purchaseNotice(.failure(activationActionNotice))
                    .padding(.horizontal, 20)
            }

            PrimaryActionButton(
                title: presentation.actionTitle,
                systemImage: presentation.actionSystemImage
            ) {
                performActivationAction(presentation)
            }
            .accessibilityHint(presentation.actionAccessibilityHint)
            .reportMembershipPaywallLayoutFrame(.activationAction, using: layoutReporter)
            .padding(.horizontal, 20)

            Text(activationSupportText(for: presentation))
                .font(.caption2.weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 9)
        .background(CheckpointTheme.panel)
        .shadow(color: CheckpointTheme.shadowCard, radius: 12, y: -4)
    }

    private func activationSupportText(
        for presentation: MembershipActivationPresentation
    ) -> String {
        switch presentation.continuation {
        case .createGoalProfile:
            "Opens goal setup next."
        case .activateGoal:
            "You’ll review the switch and any protection changes next."
        case .revealNextFocus:
            "Returns to Next Focus in Progress."
        case nil:
            "Your Pro benefits are ready now."
        }
    }

    private var activationMotionPolicy: MembershipActivationMotionPolicy {
        MembershipActivationMotionPolicy(reduceMotion: reduceMotion)
    }

    private var activationFeedbackTaskID: MembershipActivationFeedbackTaskID {
        MembershipActivationFeedbackTaskID(
            presentationID: activationPresentation?.id,
            isSceneActive: scenePhase == .active
        )
    }

    private var activationSourceForEntitlementChange: MembershipActivationSource {
        if purchaseController.purchasingProductID != nil {
            return .purchase
        }
        if purchaseController.isRestoringPurchases {
            return .restore
        }
        if purchaseController.isCheckingPurchaseStatus {
            return .purchase
        }
        return .entitlementRefresh
    }

    private func presentActivation(source: MembershipActivationSource) {
        guard activationPresentation == nil else { return }
        store.reconcileMembershipEntitlement(
            isUnlocked: true,
            activationSource: source
        )
        _ = store.completeMembershipCheckout(source: source)
        activationPresentation = store.membershipActivationPresentation(
            fallbackContext: context,
            fallbackSource: source
        )
    }

    private func performActivationAction(
        _ presentation: MembershipActivationPresentation
    ) {
        guard presentation.continuation != nil else {
            close()
            return
        }
        switch store.requestMembershipActivationResume() {
        case .requested:
            activationActionNotice = nil
            dismiss()
        case .actionUnavailable:
            let notice = "That next step is no longer available. Your Pro access is still active."
            activationActionNotice = notice
            activationPresentation = store.membershipActivationPresentation(
                fallbackContext: presentation.context,
                fallbackSource: presentation.source
            )
            AccessibilityNotification.Announcement(notice).post()
        case .persistenceFailed:
            let notice = "Checkpoint couldn’t save this handoff yet. Keep this screen open and try again."
            activationActionNotice = notice
            AccessibilityNotification.Announcement(notice).post()
        }
    }

    private func revealActivation() {
        guard !isActivationRevealed else { return }
        if reduceMotion {
            isActivationRevealed = true
        } else {
            withAnimation(activationMotionPolicy.animation) {
                isActivationRevealed = true
            }
        }
    }

    private func deliverActivationFeedbackIfPossible() {
        guard let announcement = activationFeedback.take(
            activationPresentation,
            isSceneActive: scenePhase == .active
        ) else { return }
        activationFeedbackSequence += 1
        AccessibilityNotification.Announcement(announcement).post()
    }

    @ViewBuilder
    private func paywallSection(
        _ section: MembershipPaywallSection,
        presentation: MembershipPaywallPresentation
    ) -> some View {
        switch section {
        case .hero:
            proHero
        case .offer:
            planSelection(presentation: presentation)
        case .memberManagement:
            memberManagement
        case .valueProof:
            proValueProof
        case .benefits:
            proBenefitsPanel
        case .notice:
            if let notice = purchaseController.purchaseNotice,
               store.isMember {
                purchaseNotice(notice)
            }
        case .restore:
            if !purchaseController.hasUnresolvedPurchase {
                restoreButton
            }
        case .legal:
            paywallLegalLinks
        }
    }

    private var proHero: some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.mint,
            glowDiameter: store.isMember ? 190 : 150,
            glowBlurRadius: store.isMember ? 14 : 11,
            glowOffset: CGSize(width: 72, height: -82),
            contentPadding: store.isMember ? 20 : 16
        ) {
            VStack(alignment: .leading, spacing: store.isMember ? 18 : 12) {
                proHeroHeader

                VStack(alignment: .leading, spacing: 7) {
                    Text(store.isMember ? "Your practice stays in motion." : context.membershipHeadline)
                        .font(
                            .system(
                                store.isMember && !dynamicTypeSize.isAccessibilitySize
                                    ? .largeTitle
                                    : .title2,
                                design: .rounded,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(proText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        store.isMember
                            ? "Fresh, adaptive checkpoints stay ready as your goals and skills evolve."
                            : context.offerDetail
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(proSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var proHeroHeader: some View {
        if !store.isMember {
            HStack(alignment: .center, spacing: 10) {
                Label(context.offerLabel, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.mint)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                Spacer(minLength: 6)

                if !dynamicTypeSize.isAccessibilitySize {
                    ProMomentumMark()
                }
            }
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                proEyebrow
                activePlanBadge
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                proEyebrow
                Spacer(minLength: 8)
                activePlanBadge
            }
        }
    }

    @ViewBuilder
    private var proBenefitGrid: some View {
        let benefits = [
            ProBenefit(
                title: "Up to \(ProductLimits.memberGoalProfileLimit) focused goals",
                systemImage: "square.stack.3d.up.fill"
            ),
            ProBenefit(title: "Fresh checkpoints", systemImage: "sparkles"),
            ProBenefit(title: "More question variety", systemImage: "rectangle.stack.badge.plus"),
            ProBenefit(title: "Adaptive Next Focus", systemImage: "scope")
        ]

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                ForEach(benefits) { benefit in
                    ProBenefitTile(benefit: benefit)
                }
            }
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(benefits) { benefit in
                    ProBenefitTile(benefit: benefit)
                }
            }
        }
    }

    private var proBenefitsPanel: some View {
        SectionPanel("Included with Pro") {
            proBenefitGrid
        }
    }

    private var proValueProof: some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.blue,
            glowOpacity: 0.07,
            glowDiameter: 125,
            glowBlurRadius: 10,
            glowOffset: CGSize(width: 64, height: -70),
            contentPadding: 12
        ) {
            MembershipValuePreview(
                presentation: MembershipValuePreviewPresentation(context: context),
                reduceMotion: reduceMotion
            )
        }
    }

    private var proEyebrow: some View {
        Text("Checkpoint Pro")
            .font(.caption.weight(.semibold))
            .foregroundStyle(proSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var activePlanBadge: some View {
        Label("Active", systemImage: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(CheckpointTheme.mint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(CheckpointTheme.mint.opacity(0.10), in: Capsule())
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func planSelection(presentation: MembershipPaywallPresentation) -> some View {
        let usesCompactDensity = presentation.contentDensity == .compact

        return VStack(alignment: .leading, spacing: usesCompactDensity ? 7 : 12) {
            if presentation.offerIntroduction == .compactWithValueProof {
                compactOfferIntro
            } else if presentation.offerIntroduction == .expanded {
                expandedOfferIntro
            }

            Text("Choose your plan")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .accessibilityAddTraits(.isHeader)

            if purchaseController.isLoadingProducts && planOptions.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(CheckpointTheme.teal)
                    Text("Loading App Store plans")
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 88)

                if presentation.checkoutPlacement == .afterPlanChoices {
                    inlinePurchaseAction
                }
            } else if planOptions.isEmpty {
                unavailablePlans

                if let notice = purchaseController.purchaseNotice,
                   notice.shouldDisplayWithoutSelectedPlan {
                    purchaseNotice(notice)
                }

                if presentation.checkoutPlacement == .afterPlanChoices {
                    inlinePurchaseAction
                }
            } else if presentation.laysOutPlansSideBySide {
                HStack(alignment: .top, spacing: usesCompactDensity ? 8 : 10) {
                    ForEach(planOptions) { option in
                        MembershipPlanRow(
                            option: option,
                            isSelected: selectedProductID == option.id,
                            style: usesCompactDensity ? .compactHeightCard : .compactCard,
                            reduceMotion: reduceMotion
                        ) {
                            selectPlan(option.id)
                        }
                        .reportMembershipPaywallLayoutFrame(
                            .plan(option.id),
                            using: layoutReporter
                        )
                    }
                }
                .disabled(isPurchaseActionInProgress)
                .opacity(isPurchaseActionInProgress ? 0.72 : 1)
                .animation(
                    CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                    value: isPurchaseActionInProgress
                )

                if let selectedOption {
                    selectedOfferSupport(selectedOption, compact: usesCompactDensity)
                        .reportMembershipPaywallLayoutFrame(
                            .selectedPlanSupport,
                            using: layoutReporter
                        )
                    subscriptionDisclosure(compact: usesCompactDensity)
                        .reportMembershipPaywallLayoutFrame(
                            .subscriptionDisclosure,
                            using: layoutReporter
                        )

                    if presentation.checkoutPlacement == .afterPlanChoices {
                        inlinePurchaseAction
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(planOptions) { option in
                            MembershipPlanRow(
                                option: option,
                                isSelected: selectedProductID == option.id,
                                style: presentation.checkoutPlacement == .afterPlanChoices
                                    && selectedProductID != option.id
                                        ? .compactAlternativeRow
                                        : .expandedRow,
                                reduceMotion: reduceMotion
                            ) {
                                selectPlan(option.id)
                            }
                            .reportMembershipPaywallLayoutFrame(
                                .plan(option.id),
                                using: layoutReporter
                            )
                        }
                    }
                    .disabled(isPurchaseActionInProgress)
                    .opacity(isPurchaseActionInProgress ? 0.72 : 1)
                    .animation(
                        CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
                        value: isPurchaseActionInProgress
                    )

                    if selectedOption != nil {
                        subscriptionDisclosure(compact: usesCompactDensity)
                            .reportMembershipPaywallLayoutFrame(
                                .subscriptionDisclosure,
                                using: layoutReporter
                            )

                        if presentation.checkoutPlacement == .afterPlanChoices {
                            inlinePurchaseAction
                        }
                    }
                }
            }
        }
        .padding(.bottom, usesCompactDensity ? 28 : 0)
    }

    private var compactOfferIntro: some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.mint,
            glowOpacity: 0.08,
            glowDiameter: 92,
            glowBlurRadius: 8,
            glowOffset: CGSize(width: 52, height: -48),
            contentPadding: 9
        ) {
            VStack(alignment: .leading, spacing: 7) {
                Text(context.membershipHeadline)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(proText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(context.offerLabel). \(context.membershipHeadline)")
                    .accessibilityAddTraits(.isHeader)

                MembershipValuePreview(
                    presentation: MembershipValuePreviewPresentation(context: context),
                    reduceMotion: reduceMotion,
                    style: .embeddedCompact
                )
                .reportMembershipPaywallLayoutFrame(
                    .compactValueProof,
                    using: layoutReporter
                )
            }
        }
    }

    private var expandedOfferIntro: some View {
        CheckpointHeroSurface(
            glowColor: CheckpointTheme.mint,
            glowOpacity: 0.07,
            glowDiameter: 110,
            glowBlurRadius: 9,
            glowOffset: CGSize(width: 55, height: -62),
            contentPadding: 14
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Label(context.offerLabel, systemImage: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.mint)
                    .fixedSize(horizontal: false, vertical: true)

                Text(context.offerDetail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(proSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selectedOfferSupport(
        _ option: MembershipPlanOption,
        compact: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .accessibilityHidden(true)

            Text(compact ? option.compactDetail : option.detail)
                .font((compact ? Font.caption : .footnote).weight(.medium))
                .foregroundStyle(CheckpointTheme.muted)
                .lineLimit(compact ? 1 : nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func subscriptionDisclosure(compact: Bool) -> some View {
        Text(
            compact
                ? MembershipPaywallPresentation.compactSubscriptionDisclosureText
                : MembershipPaywallPresentation.subscriptionDisclosureText
        )
            .font(.caption)
            .foregroundStyle(CheckpointTheme.muted)
            .lineLimit(compact ? 2 : nil)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(MembershipPaywallPresentation.subscriptionDisclosureText)
    }

    private var unavailablePlans: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plans are temporarily unavailable.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)

            Text("Reconnect to the App Store and try loading prices again.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panel.opacity(0.86),
            in: RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CheckpointTheme.cardCornerRadius, style: .continuous)
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        }
    }

    private var memberManagement: some View {
        let presentation = activePlanPresentation

        return SectionPanel("Plan & billing") {
            VStack(alignment: .leading, spacing: 12) {
                memberPlanReceipt(presentation)
                    .reportMembershipPaywallLayoutFrame(
                        .memberPlanReceipt,
                        using: layoutReporter
                    )

                memberManagementButton(presentation)
                    .reportMembershipPaywallLayoutFrame(
                        .memberManagementAction,
                        using: layoutReporter
                    )
            }
        }
    }

    private func memberPlanReceipt(
        _ presentation: MembershipActivePlanPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            memberPlanHeader(presentation)

            Divider()
                .overlay(CheckpointTheme.hairline)

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: presentation.statusSystemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(memberPlanTint(for: presentation.tone))
                    .frame(width: 30, height: 30)
                    .background(
                        memberPlanTint(for: presentation.tone).opacity(0.11),
                        in: Circle()
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(
                        .bounce,
                        options: .nonRepeating,
                        value: presentation.visualStateKey
                    )
                    .symbolEffectsRemoved(!activePlanMotionPolicy.animatesSymbol)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)
                        .contentTransition(.interpolate)

                    Text(presentation.supportText)
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.interpolate)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CheckpointTheme.hairline, lineWidth: 1)
        }
        .animation(activePlanMotionPolicy.animation, value: presentation.visualStateKey)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private func memberPlanHeader(
        _ presentation: MembershipActivePlanPresentation
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedMemberPlanHeader(presentation, keepsBadgeOnOneLine: false)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    memberPlanIdentity(presentation)
                        .fixedSize(horizontal: true, vertical: false)
                        .reportMembershipPaywallLayoutFrame(
                            .memberPlanIdentity,
                            using: layoutReporter
                        )

                    Spacer(minLength: 8)

                    memberPlanBadge(presentation)
                        .fixedSize(horizontal: true, vertical: false)
                }

                stackedMemberPlanHeader(presentation, keepsBadgeOnOneLine: true)
            }
        }
    }

    private func stackedMemberPlanHeader(
        _ presentation: MembershipActivePlanPresentation,
        keepsBadgeOnOneLine: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            memberPlanIdentity(presentation)
                .reportMembershipPaywallLayoutFrame(
                    .memberPlanIdentity,
                    using: layoutReporter
                )

            memberPlanBadge(presentation)
                .fixedSize(horizontal: keepsBadgeOnOneLine, vertical: false)
        }
    }

    private func memberPlanBadge(
        _ presentation: MembershipActivePlanPresentation
    ) -> some View {
        StatusBadge(
            text: presentation.badgeText,
            tint: memberPlanTint(for: presentation.tone)
        )
        .reportMembershipPaywallLayoutFrame(
            .memberPlanBadge,
            using: layoutReporter
        )
    }

    private func memberPlanIdentity(
        _ presentation: MembershipActivePlanPresentation
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: presentation.planSystemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 40, height: 40)
                .background(CheckpointTheme.teal.opacity(0.11), in: Circle())
                .contentTransition(.symbolEffect(.replace))
                .symbolEffectsRemoved(!activePlanMotionPolicy.animatesSymbol)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("PRO PLAN")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(CheckpointTheme.muted)
                    .lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                Text(presentation.planTitle)
                    .font(.headline)
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
            }
        }
    }

    private func memberManagementButton(
        _ presentation: MembershipActivePlanPresentation
    ) -> some View {
        Button {
            openSubscriptionManagement()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "creditcard")
                    .foregroundStyle(CheckpointTheme.teal)
                    .accessibilityHidden(true)

                Text(presentation.managementTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.interpolate)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckpointTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                CheckpointTheme.panelRaised.opacity(0.58),
                in: RoundedRectangle(
                    cornerRadius: CheckpointTheme.compactCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: CheckpointTheme.compactCornerRadius,
                    style: .continuous
                )
                .stroke(CheckpointTheme.controlStroke, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CheckpointPressButtonStyle(role: .surface))
        .accessibilityLabel(presentation.managementTitle)
        .accessibilityHint(presentation.managementAccessibilityHint)
    }

    private func purchaseBar(presentation: MembershipPaywallPresentation) -> some View {
        VStack(spacing: presentation.contentDensity == .compact ? 5 : 8) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            if let notice = purchaseController.purchaseNotice,
               checkoutPresentation.shouldShowNoticeInPurchaseBar {
                purchaseNotice(notice)
                    .padding(.horizontal, 20)
            }

            if purchaseController.hasUnresolvedPurchase {
                restoreButton
                    .padding(.horizontal, 20)
            }

            purchaseActionButton(usesCompactTitle: presentation.contentDensity == .compact)
                .padding(.horizontal, 20)
                .padding(.top, selectedOption == nil ? 2 : 0)

            if selectedOption != nil,
               !purchaseController.hasUnresolvedPurchase {
                purchaseTrustLine
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, presentation.contentDensity == .compact ? 5 : 9)
        .background(CheckpointTheme.panel)
        .shadow(color: CheckpointTheme.shadowCard, radius: 12, y: -4)
    }

    private var inlinePurchaseAction: some View {
        VStack(spacing: 10) {
            if let notice = purchaseController.purchaseNotice,
               checkoutPresentation.shouldShowNoticeInPurchaseBar {
                purchaseNotice(notice)
            }

            if purchaseController.hasUnresolvedPurchase {
                restoreButton
            }

            purchaseActionButton(usesCompactTitle: false)
        }
    }

    private func purchaseActionButton(usesCompactTitle: Bool) -> some View {
        PrimaryActionButton(
            title: purchaseButtonTitle(usesCompactTitle: usesCompactTitle),
            systemImage: purchaseButtonSystemImage,
            isLoading: checkoutPresentation.showsPrimaryProgress
        ) {
            handlePurchaseButton()
        }
        .reportMembershipPaywallLayoutFrame(.primaryAction, using: layoutReporter)
        .accessibilityLabel(checkoutPresentation.buttonAccessibilityLabel)
        .disabled(checkoutPresentation.isPrimaryActionDisabled)
    }

    private var purchaseTrustLine: some View {
        Label(MembershipPaywallPresentation.billingTrustText, systemImage: "lock.fill")
            .font(.caption2.weight(.medium))
            .foregroundStyle(CheckpointTheme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MembershipPaywallPresentation.billingTrustAccessibilityLabel)
    }

    private var restoreButton: some View {
        Button {
            handleSecondaryStoreAction()
        } label: {
            HStack(spacing: 7) {
                if checkoutPresentation.showsSecondaryProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: checkoutPresentation.secondaryButtonSystemImage)
                }

                Text(checkoutPresentation.secondaryButtonTitle)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CheckpointPressButtonStyle())
        .reportMembershipPaywallLayoutFrame(.secondaryAction, using: layoutReporter)
        .accessibilityLabel(checkoutPresentation.secondaryButtonAccessibilityLabel)
        .disabled(checkoutPresentation.isSecondaryActionDisabled)
    }

    private func purchaseNotice(_ notice: MembershipPurchaseNotice) -> some View {
        let tint: Color
        let systemImage: String

        switch notice.tone {
        case .pending:
            tint = CheckpointTheme.amber
            systemImage = "clock.fill"
        case .failure:
            tint = CheckpointTheme.coral
            systemImage = "exclamationmark.circle.fill"
        case .information:
            tint = CheckpointTheme.blue
            systemImage = "info.circle.fill"
        }

        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(notice.message)
                .font(.footnote)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var planOptions: [MembershipPlanOption] {
        planOptionsOverride ?? catalogPresentation.planOptions
    }

    private var catalogPresentation: MembershipCatalogPresentation {
        MembershipCatalogPresentation(products: purchaseController.products)
    }

    private var selectedOption: MembershipPlanOption? {
        planOptions.first { $0.id == selectedProductID }
    }

    private var selectedProduct: Product? {
        purchaseController.products.first { $0.id == selectedProductID }
    }

    private func purchaseButtonTitle(usesCompactTitle: Bool) -> String {
        checkoutPresentation.buttonTitle(
            accessibilitySize: dynamicTypeSize.isAccessibilitySize,
            compact: usesCompactTitle
        )
    }

    private var purchaseButtonSystemImage: String {
        checkoutPresentation.buttonSystemImage
    }

    private func paywallPresentation(availableHeight: CGFloat) -> MembershipPaywallPresentation {
        MembershipPaywallPresentation(
            isMember: store.isMember,
            accessibilitySize: dynamicTypeSize.isAccessibilitySize,
            usesLargeText: dynamicTypeSize >= .xLarge,
            hasCheckoutNotice: checkoutPresentation.shouldShowNoticeInPurchaseBar,
            availableHeight: availableHeight
        )
    }

    private var isPurchaseActionInProgress: Bool {
        checkoutPresentation.isActionInProgress
    }

    private var checkoutPresentation: MembershipCheckoutPresentation {
        MembershipCheckoutPresentation(
            selectedPlan: selectedOption,
            hasUnresolvedPurchase: purchaseController.hasUnresolvedPurchase,
            isLoadingPlans: purchaseController.isLoadingProducts,
            isRestoringPurchases: purchaseController.isRestoringPurchases,
            isCheckingPurchaseStatus: purchaseController.isCheckingPurchaseStatus,
            isPurchasing: purchaseController.purchasingProductID != nil,
            notice: purchaseController.purchaseNotice
        )
    }

    private var paywallLegalLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    paywallLegalLinkItems
                }

                VStack(alignment: .leading, spacing: 8) {
                    paywallLegalLinkItems
                }
            }

            if let missingMessage = legalLinks.missingConfigurationMessage {
                Text(missingMessage)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var paywallLegalLinkItems: some View {
        CompactLegalLink(title: "Privacy Policy", url: legalLinks.privacyPolicyURL)
        CompactLegalLink(title: "Support", url: legalLinks.supportURL)
        CompactLegalLink(title: "Terms of Use", url: LegalLinks.termsOfUseURL)
    }

    private func selectDefaultPlanIfNeeded() {
        guard !planOptions.isEmpty else {
            selectedProductID = nil
            return
        }

        let defaultOptionID: String?
        if planOptionsOverride != nil {
            defaultOptionID = planOptions.first(where: \.isRecommended)?.id ?? planOptions.first?.id
        } else {
            defaultOptionID = catalogPresentation.defaultPlanID
        }
        let resolvedSelection = MembershipPlanSelectionResolver.resolve(
            planOptions: planOptions,
            currentID: selectedProductID,
            pendingProductID: purchaseController.pendingPurchaseProductID,
            defaultID: defaultOptionID
        )
        guard resolvedSelection != selectedProductID else { return }
        withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
            selectedProductID = resolvedSelection
        }
    }

    private func selectPlan(_ productID: String) {
        guard selectedProductID != productID else { return }

        withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
            selectedProductID = productID
        }
        selectionFeedbackSequence += 1
    }

    private func loadEntitlements() async {
        await purchaseController.loadProducts()
        _ = await purchaseController.refreshEntitlements()
    }

    private func handlePurchaseButton() {
        if let renderPurchaseAction {
            renderPurchaseAction(selectedProductID)
            return
        }

        guard let selectedProduct else {
            reloadProducts()
            return
        }
        purchase(selectedProduct)
    }

    private func reloadProducts() {
        if let renderReloadAction {
            renderReloadAction()
            return
        }

        Task {
            await purchaseController.loadProducts()
            selectDefaultPlanIfNeeded()
        }
    }

    private func purchase(_ product: Product) {
        Task {
            guard beginMembershipStoreAction() else { return }
            let unlocked = await purchaseController.purchase(product)
            store.membershipCheckoutFinished(
                hasUnresolvedPurchase: purchaseController.hasUnresolvedPurchase
            )

            if unlocked {
                presentActivation(source: .purchase)
            }
        }
    }

    private func restorePurchases() {
        if let renderRestoreAction {
            renderRestoreAction()
            return
        }

        Task {
            guard beginMembershipStoreAction() else { return }
            let unlocked = await purchaseController.restorePurchases()
            store.membershipCheckoutFinished(
                hasUnresolvedPurchase: purchaseController.hasUnresolvedPurchase
            )
            if unlocked {
                presentActivation(source: .restore)
            }
        }
    }

    private func handleSecondaryStoreAction() {
        switch checkoutPresentation.secondaryAction {
        case .restorePurchases:
            restorePurchases()
        case .checkPurchaseStatus:
            checkPurchaseStatus()
        }
    }

    private func checkPurchaseStatus() {
        if let renderCheckPurchaseStatusAction {
            renderCheckPurchaseStatusAction()
            return
        }

        Task {
            guard beginMembershipStoreAction() else { return }
            let unlocked = await purchaseController.checkPurchaseStatus()
            store.membershipCheckoutFinished(
                hasUnresolvedPurchase: purchaseController.hasUnresolvedPurchase
            )
            if unlocked {
                presentActivation(source: .purchase)
            }
        }
    }

    private func beginMembershipStoreAction() -> Bool {
        guard store.membershipCheckoutStarted() else {
            purchaseController.purchaseNotice = .failure(
                "Checkpoint couldn’t safely save where to continue, so the App Store action hasn’t started. Free up storage and try again."
            )
            return false
        }
        return true
    }

    private func openSubscriptionManagement() {
        isSubscriptionManagementPresented = true
    }

    private func close() {
        guard store.dismissMembershipPrompt(
            hasUnresolvedPurchase: purchaseController.hasUnresolvedCheckout
        ) else {
            let notice = "Checkpoint couldn’t save this choice yet. Keep this screen open and try again."
            if activationPresentation != nil {
                activationActionNotice = notice
            } else {
                purchaseController.purchaseNotice = .failure(notice)
            }
            AccessibilityNotification.Announcement(notice).post()
            return
        }
        dismiss()
    }

    private var proText: Color { CheckpointTheme.heroText }
    private var proSecondaryText: Color { CheckpointTheme.heroMuted }
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    private var activePlanPresentation: MembershipActivePlanPresentation {
        MembershipActivePlanPresentation(snapshot: purchaseController.activePlanSnapshot)
    }

    private var activePlanMotionPolicy: MembershipActivePlanMotionPolicy {
        MembershipActivePlanMotionPolicy(reduceMotion: reduceMotion)
    }

    private var subscriptionManagementScope: MembershipSubscriptionManagementScope {
        MembershipSubscriptionManagementScope(
            activePlanSnapshot: purchaseController.activePlanSnapshot
        )
    }

    private func memberPlanTint(for tone: MembershipActivePlanTone) -> Color {
        switch tone {
        case .active:
            CheckpointTheme.teal
        case .scheduled:
            CheckpointTheme.blue
        case .attention:
            CheckpointTheme.amber
        }
    }
}

enum MembershipValuePreviewMotionStyle: Equatable {
    case stagedReveal
    case identity
}

struct MembershipValuePreviewMotionPolicy: Equatable {
    let style: MembershipValuePreviewMotionStyle

    init(reduceMotion: Bool) {
        style = reduceMotion ? .identity : .stagedReveal
    }

    var animatesReveal: Bool { style == .stagedReveal }
    var animatesSymbol: Bool { style == .stagedReveal }
    var hiddenOpacity: Double { style == .stagedReveal ? 0 : 1 }
    var hiddenScale: CGFloat { style == .stagedReveal ? 0.92 : 1 }

    func nodeAnimation(at index: Int) -> Animation? {
        guard style == .stagedReveal else { return nil }
        return .smooth(duration: 0.34).delay(Double(index) * 0.09)
    }

    func connectorAnimation(after index: Int) -> Animation? {
        guard style == .stagedReveal else { return nil }
        return .smooth(duration: 0.3).delay(0.08 + (Double(index) * 0.09))
    }
}

enum MembershipValuePreviewStyle: Equatable {
    case standardCard
    case embeddedCompact
}

struct MembershipValuePreview: View {
    let presentation: MembershipValuePreviewPresentation
    let reduceMotion: Bool
    let style: MembershipValuePreviewStyle

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isRevealed = false
    @State private var symbolRevealSequence = 0

    init(
        presentation: MembershipValuePreviewPresentation,
        reduceMotion: Bool,
        style: MembershipValuePreviewStyle = .standardCard
    ) {
        self.presentation = presentation
        self.reduceMotion = reduceMotion
        self.style = style
    }

    private var motionPolicy: MembershipValuePreviewMotionPolicy {
        MembershipValuePreviewMotionPolicy(reduceMotion: reduceMotion)
    }

    var body: some View {
        previewContent
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
            .onAppear {
                reveal()
            }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch style {
        case .standardCard:
            standardCard
        case .embeddedCompact:
            embeddedCompactWorkflow
        }
    }

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("How Pro works")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.heroMuted)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                verticalWorkflow
            } else {
                ViewThatFits(in: .horizontal) {
                    standardWorkflow
                        .fixedSize(horizontal: true, vertical: false)

                    compactWorkflow
                }
            }

            Text(presentation.outcome)
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.heroSubtleFill,
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(CheckpointTheme.heroDivider, lineWidth: 1)
        }
    }

    private var standardWorkflow: some View {
        HStack(spacing: 5) {
            ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    horizontalConnector(after: index - 1)
                }

                VStack(spacing: 6) {
                    nodeMark(node)

                    Text(node.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(nodeTextColor(node))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 74)
                }
                .opacity(isRevealed ? 1 : motionPolicy.hiddenOpacity)
                .scaleEffect(isRevealed ? 1 : motionPolicy.hiddenScale)
                .animation(motionPolicy.nodeAnimation(at: index), value: isRevealed)
            }
        }
    }

    private var compactWorkflow: some View {
        ZStack(alignment: .top) {
            compactConnector
                .padding(.horizontal, 34)
                .padding(.top, 15)

            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                    VStack(spacing: 5) {
                        nodeMark(node)

                        Text(node.compactTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(nodeTextColor(node))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(isRevealed ? 1 : motionPolicy.hiddenOpacity)
                    .scaleEffect(isRevealed ? 1 : motionPolicy.hiddenScale)
                    .animation(motionPolicy.nodeAnimation(at: index), value: isRevealed)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var embeddedCompactWorkflow: some View {
        ZStack(alignment: .top) {
            compactConnector
                .padding(.horizontal, 26)
                .padding(.top, 11)

            HStack(alignment: .top, spacing: 3) {
                ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                    VStack(spacing: 3) {
                        nodeMark(node, size: 24)

                        Text(node.compactTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(nodeTextColor(node))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(isRevealed ? 1 : motionPolicy.hiddenOpacity)
                    .scaleEffect(isRevealed ? 1 : motionPolicy.hiddenScale)
                    .animation(motionPolicy.nodeAnimation(at: index), value: isRevealed)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var compactConnector: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(CheckpointTheme.heroDivider)

            Capsule()
                .fill(CheckpointTheme.mint.opacity(0.54))
                .scaleEffect(x: isRevealed ? 1 : 0, anchor: .leading)
                .animation(motionPolicy.connectorAnimation(after: 0), value: isRevealed)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var verticalWorkflow: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    verticalConnector(after: index - 1)
                }

                HStack(spacing: 11) {
                    nodeMark(node)

                    Text(node.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(nodeTextColor(node))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(isRevealed ? 1 : motionPolicy.hiddenOpacity)
                .scaleEffect(
                    isRevealed ? 1 : motionPolicy.hiddenScale,
                    anchor: .leading
                )
                .animation(motionPolicy.nodeAnimation(at: index), value: isRevealed)
            }
        }
    }

    private func nodeMark(
        _ node: MembershipValuePreviewNode,
        size: CGFloat = 32
    ) -> some View {
        let highlighted = isHighlighted(node)
        let animated = isAnimatedDestination(node)

        return Image(systemName: node.systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(highlighted ? CheckpointTheme.mint : CheckpointTheme.heroMuted)
            .frame(width: size, height: size)
            .background(
                highlighted
                    ? CheckpointTheme.mint.opacity(0.14)
                    : CheckpointTheme.heroSubtleFill,
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        highlighted
                            ? CheckpointTheme.mint.opacity(0.5)
                            : CheckpointTheme.heroDivider,
                        lineWidth: 1
                    )
            }
            .symbolEffect(.bounce, options: .nonRepeating, value: symbolRevealSequence)
            .symbolEffectsRemoved(!motionPolicy.animatesSymbol || !animated)
            .accessibilityHidden(true)
    }

    private func horizontalConnector(after index: Int) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(CheckpointTheme.heroDivider)

            Capsule()
                .fill(CheckpointTheme.mint.opacity(0.54))
                .scaleEffect(x: isRevealed ? 1 : 0, anchor: .leading)
                .animation(motionPolicy.connectorAnimation(after: index), value: isRevealed)
        }
        .frame(width: 14, height: 2)
        .accessibilityHidden(true)
    }

    private func verticalConnector(after index: Int) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(CheckpointTheme.heroDivider)

            Capsule()
                .fill(CheckpointTheme.mint.opacity(0.54))
                .scaleEffect(y: isRevealed ? 1 : 0, anchor: .top)
                .animation(motionPolicy.connectorAnimation(after: index), value: isRevealed)
        }
        .frame(width: 2, height: 12)
        .padding(.leading, 15)
        .accessibilityHidden(true)
    }

    private func isHighlighted(_ node: MembershipValuePreviewNode) -> Bool {
        presentation.highlightedNodeID == nil || presentation.highlightedNodeID == node.id
    }

    private func isAnimatedDestination(_ node: MembershipValuePreviewNode) -> Bool {
        if let highlightedNodeID = presentation.highlightedNodeID {
            return highlightedNodeID == node.id
        }
        return node.id == presentation.nodes.last?.id
    }

    private func nodeTextColor(_ node: MembershipValuePreviewNode) -> Color {
        isHighlighted(node) ? CheckpointTheme.heroText : CheckpointTheme.heroMuted
    }

    private func reveal() {
        isRevealed = true
        guard motionPolicy.animatesSymbol else { return }
        symbolRevealSequence += 1
    }
}

private enum MembershipPlanRowStyle: Equatable {
    case compactCard
    case compactHeightCard
    case compactAlternativeRow
    case expandedRow
}

private struct MembershipPlanRow: View {
    let option: MembershipPlanOption
    let isSelected: Bool
    let style: MembershipPlanRowStyle
    let reduceMotion: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            planRowContent
                .padding(planPadding)
                .frame(
                    maxWidth: .infinity,
                    minHeight: compactCardMinimumHeight,
                    alignment: .leading
                )
                .background(
                    isSelected
                        ? CheckpointTheme.teal.opacity(0.10)
                        : CheckpointTheme.panel.opacity(0.84),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isSelected ? CheckpointTheme.teal.opacity(0.72) : CheckpointTheme.controlStroke,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
        }
        .buttonStyle(CheckpointPressButtonStyle(role: .surface))
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: isSelected
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Selects the \(option.title.lowercased()) plan")
    }

    @ViewBuilder
    private var planRowContent: some View {
        if style == .compactCard || style == .compactHeightCard {
            compactCardContent
        } else if style == .compactAlternativeRow {
            compactAlternativeContent
        } else if dynamicTypeSize.isAccessibilitySize {
            expandedContent
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    selectionIcon
                    optionDescription
                    Spacer(minLength: 8)
                    optionPrice
                }

                expandedContent
            }
        }
    }

    private var planPadding: CGFloat {
        switch style {
        case .compactCard:
            12
        case .compactHeightCard:
            10
        case .compactAlternativeRow, .expandedRow:
            15
        }
    }

    private var compactCardMinimumHeight: CGFloat? {
        switch style {
        case .compactCard:
            118
        case .compactHeightCard:
            104
        case .compactAlternativeRow, .expandedRow:
            nil
        }
    }

    private var compactAlternativeContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                selectionIcon
                optionTitleText
            }

            recommendedBadge

            Text("\(option.displayPrice) \(option.cadence)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            optionSavings
        }
    }

    private var compactCardContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 6) {
                selectionIcon
                Spacer(minLength: 4)
                recommendedBadge
            }

            optionTitleText

            compactPricePresentation

            optionSavings
        }
    }

    @ViewBuilder
    private var compactPricePresentation: some View {
        if style == .compactHeightCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    compactPriceText
                        .fixedSize(horizontal: true, vertical: false)
                    compactCadenceText
                        .fixedSize(horizontal: true, vertical: false)
                }
                .fixedSize(horizontal: true, vertical: false)

                compactPriceText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                compactPriceText
                Spacer(minLength: 2)
                compactCadenceText
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var compactPriceText: some View {
        Text(option.displayPrice)
            .font(.headline.weight(.bold))
            .foregroundStyle(CheckpointTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
    }

    private var compactCadenceText: some View {
        Text(option.cadence)
            .font(.caption2)
            .foregroundStyle(CheckpointTheme.muted)
            .lineLimit(1)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                selectionIcon
                optionTitle
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(option.displayPrice)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)

                Text(option.cadence)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)

                optionSavings
            }
            .padding(.leading, 32)

            Text(option.detail)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 32)
        }
    }

    private var selectionIcon: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(isSelected ? CheckpointTheme.teal : CheckpointTheme.muted)
            .frame(width: 22)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffectsRemoved(reduceMotion)
            .accessibilityHidden(true)
    }

    private var optionDescription: some View {
        VStack(alignment: .leading, spacing: 3) {
            optionTitle

            Text(option.detail)
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var optionPrice: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(option.displayPrice)
                .font(.headline.weight(.bold))
                .foregroundStyle(CheckpointTheme.text)

            Text(option.cadence)
                .font(.caption)
                .foregroundStyle(CheckpointTheme.muted)

            optionSavings
        }
    }

    private var optionTitle: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    optionTitleText
                    recommendedBadge
                }
            } else {
                HStack(spacing: 7) {
                    optionTitleText
                    recommendedBadge
                }
            }
        }
    }

    private var optionTitleText: some View {
        Text(option.title)
            .font(.headline)
            .foregroundStyle(CheckpointTheme.text)
    }

    @ViewBuilder
    private var recommendedBadge: some View {
        if option.isRecommended {
            Text("Best value")
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckpointTheme.selectionText)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(CheckpointTheme.actionTeal, in: Capsule())
        }
    }

    @ViewBuilder
    private var optionSavings: some View {
        if let valueBadge = option.valueBadge {
            Text(valueBadge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckpointTheme.teal)
                .padding(.top, 2)
        }
    }
}

private struct ProBenefit: Identifiable {
    let title: String
    let systemImage: String

    var id: String { title }
}

private struct ProBenefitTile: View {
    let benefit: ProBenefit

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: benefit.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 27, height: 27)
                .background(
                    CheckpointTheme.teal.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityHidden(true)

            Text(benefit.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ProMomentumMark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(CheckpointTheme.mint.opacity(0.28), lineWidth: 1)
                .frame(width: 40, height: 40)

            Circle()
                .fill(CheckpointTheme.heroSubtleFill)
                .frame(width: 32, height: 32)

            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CheckpointTheme.mint)
        }
        .accessibilityHidden(true)
    }
}

private struct MembershipActivationMark: View {
    let isRevealed: Bool
    let motionPolicy: MembershipActivationMotionPolicy

    var body: some View {
        ZStack {
            Circle()
                .fill(CheckpointTheme.mint.opacity(0.08))
                .frame(width: 104, height: 104)

            Circle()
                .stroke(CheckpointTheme.mint.opacity(0.22), lineWidth: 1)
                .frame(width: 88, height: 88)

            Circle()
                .trim(from: 0.08, to: 0.82)
                .stroke(
                    CheckpointTheme.mint,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 78, height: 78)
                .rotationEffect(isRevealed ? .degrees(-24) : motionPolicy.hiddenRotation)

            Circle()
                .fill(CheckpointTheme.mint.opacity(0.15))
                .frame(width: 64, height: 64)

            Image(systemName: "checkmark")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(CheckpointTheme.mint)
                .symbolEffect(.bounce, options: .nonRepeating, value: isRevealed)
                .symbolEffectsRemoved(!motionPolicy.animatesSymbol)

            Circle()
                .fill(CheckpointTheme.mint)
                .frame(width: 9, height: 9)
                .offset(y: -39)
                .rotationEffect(isRevealed ? .degrees(76) : .degrees(18))
        }
        .opacity(isRevealed ? 1 : motionPolicy.hiddenOpacity)
        .scaleEffect(isRevealed ? 1 : motionPolicy.hiddenScale)
        .animation(motionPolicy.animation, value: isRevealed)
        .accessibilityHidden(true)
    }
}

private struct CompactLegalLink: View {
    let title: String
    let url: URL?

    @ViewBuilder
    var body: some View {
        if let url {
            Link(destination: url) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        } else {
            Text("\(title) — not configured")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CheckpointTheme.coral)
                .frame(minHeight: 44, alignment: .leading)
        }
    }
}
