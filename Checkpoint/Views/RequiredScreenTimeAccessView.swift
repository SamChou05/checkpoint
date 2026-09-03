import Accessibility
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RequiredScreenTimeAccessView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @State private var isEraseConfirmationPresented = false

    private let legalLinks = LegalLinks.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 20)

                CheckpointSetupMark(
                    stage: requiresDataEraseRecovery ? "Data recovery" : "Screen Time",
                    step: requiresDataEraseRecovery ? nil : 1,
                    isWorking: screenTime.isRequestingAuthorization
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(accessHeading)
                        .font(.largeTitle.bold())
                        .foregroundStyle(CheckpointTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(accessDetail)
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !requiresDataEraseRecovery {
                    setupSequencePanel
                }

                if let message = accessErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(
                            CheckpointTheme.coral.opacity(0.08),
                            in: RoundedRectangle(
                                cornerRadius: CheckpointTheme.compactCornerRadius,
                                style: .continuous
                            )
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                privacyFooter
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            accessActionBar
        }
        .checkpointScreenBackground()
        .preferredColorScheme(.light)
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: accessErrorMessage
        )
        .onChange(of: accessErrorMessage) { _, message in
            guard let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
        .alert("Erase all Checkpoint data?", isPresented: $isEraseConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Erase all data", role: .destructive) {
                eraseAllData()
            }
        } message: {
            Text("This removes goals, progress, protected-app selections, diagnostics, and the anonymous backend install ID.")
        }
    }

    @ViewBuilder
    private var accessActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            Group {
                if requiresDataEraseRecovery {
                    PrimaryActionButton(
                        title: dynamicTypeSize.isAccessibilitySize ? "Retry erase" : "Retry data erasure",
                        systemImage: "trash"
                    ) {
                        eraseAllData()
                    }
                } else if screenTime.setupState == .unavailable {
                    Label(
                        "Screen Time app protection requires a supported iPhone build.",
                        systemImage: "iphone.slash"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if screenTime.authorizationState == .denied {
                    PrimaryActionButton(
                        title: dynamicTypeSize.isAccessibilitySize ? "Open Settings" : "Open iPhone Settings",
                        systemImage: "gear"
                    ) {
                        openSystemSettings()
                    }
                } else {
                    PrimaryActionButton(
                        title: authorizationButtonTitle,
                        systemImage: "checkmark.shield",
                        isLoading: screenTime.isRequestingAuthorization
                    ) {
                        Task {
                            await screenTime.requestAuthorization()
                        }
                    }
                    .disabled(screenTime.isRequestingAuthorization)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var setupSequencePanel: some View {
        SectionPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("HOW IT WORKS")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(CheckpointTheme.muted)
                    .accessibilityAddTraits(.isHeader)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        sequenceStep(title: "Choose apps", systemImage: "square.grid.2x2")
                        sequenceArrow
                        sequenceStep(title: "Clear a checkpoint", systemImage: "checkmark.circle")
                        sequenceArrow
                        sequenceStep(title: "Unlock a timed break", systemImage: "timer")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        verticalSequenceStep(title: "Choose apps", systemImage: "square.grid.2x2")
                        verticalSequenceStep(title: "Clear a checkpoint", systemImage: "checkmark.circle")
                        verticalSequenceStep(title: "Unlock a timed break", systemImage: "timer")
                    }
                }
            }
        }
    }

    private func sequenceStep(title: String, systemImage: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 36, height: 36)
                .background(
                    CheckpointTheme.teal.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var sequenceArrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(CheckpointTheme.muted.opacity(0.7))
            .padding(.top, 12)
            .accessibilityHidden(true)
    }

    private func verticalSequenceStep(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.text)
            .symbolRenderingMode(.hierarchical)
            .tint(CheckpointTheme.teal)
            .frame(minHeight: 36)
    }

    private var authorizationButtonTitle: String {
        if screenTime.isRequestingAuthorization {
            return "Requesting access"
        }

        if screenTime.setupState == .failed { return "Try Screen Time access again" }

        return "Allow Screen Time"
    }

    private var requiresDataEraseRecovery: Bool {
        screenTime.requiresSharedDataEraseRecovery
            || store.requiresPersistenceEraseRecovery
    }

    private var accessHeading: String {
        requiresDataEraseRecovery
            ? "Finish erasing Checkpoint data"
            : "Practice before you scroll."
    }

    private var accessDetail: String {
        if requiresDataEraseRecovery {
            return "Checkpoint must verify that its local app and Screen Time data are removed before you can continue or create a new goal."
        }

        return "Choose apps you want to use more intentionally. Clear a short, goal-based checkpoint to take a timed break."
    }

    private var accessErrorMessage: String? {
        if requiresDataEraseRecovery {
            return store.persistenceRecoveryMessage
                ?? screenTime.sharedDataEraseErrorMessage
                ?? "Checkpoint could not finish erasing local data."
        }

        return screenTime.userFacingErrorMessage
    }

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Uses Apple Screen Time", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.text)

            Text("You choose what to protect. Checkpoint does not read or store your Screen Time activity history.")
                .font(.footnote)
                .foregroundStyle(CheckpointTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    legalLinkItems
                }

                VStack(alignment: .leading, spacing: 0) {
                    legalLinkItems
                }
            }

            if store.isMember,
               let subscriptionURL = URL(string: "https://apps.apple.com/account/subscriptions") {
                compactAccessLink(title: "Manage subscription", url: subscriptionURL)
            }

            if shouldOfferDataErase {
                Divider()

                Button(role: .destructive) {
                    isEraseConfirmationPresented = true
                } label: {
                    Label("Erase all Checkpoint data", systemImage: "trash")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var legalLinkItems: some View {
        if let privacyPolicyURL = legalLinks.privacyPolicyURL {
            compactAccessLink(title: "Privacy", url: privacyPolicyURL)
        }
        compactAccessLink(title: "Terms", url: LegalLinks.termsOfUseURL)
        if let supportURL = legalLinks.supportURL {
            compactAccessLink(title: "Support", url: supportURL)
        }
    }

    private func compactAccessLink(title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private var shouldOfferDataErase: Bool {
        !requiresDataEraseRecovery
            && (!store.hasNoPersistedAppData || screenTime.hasSelection)
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }

    private func eraseAllData() {
        screenTime.eraseAllData()
        store.eraseAllData()
    }

}
