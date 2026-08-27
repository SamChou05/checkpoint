import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RequiredScreenTimeAccessView: View {
    let store: CheckpointStore
    let screenTime: ScreenTimeController
    @Environment(\.openURL) private var openURL
    @State private var isEraseConfirmationPresented = false

    private let legalLinks = LegalLinks.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 36)

                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(CheckpointTheme.teal)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    Text(accessHeading)
                        .font(.largeTitle.bold())
                        .foregroundStyle(CheckpointTheme.text)

                    Text(accessDetail)
                        .font(.subheadline)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !requiresDataEraseRecovery {
                    SectionPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            permissionBenefit(
                                title: "You choose the apps",
                                detail: "Checkpoint only protects apps, categories, and websites you select.",
                                systemImage: "checklist"
                            )

                            Divider()

                            permissionBenefit(
                                title: "Questions unlock breaks",
                                detail: "Screen Time lets Checkpoint temporarily open those apps after a successful quiz.",
                                systemImage: "checkmark.seal"
                            )

                            Divider()

                            permissionBenefit(
                                title: "Your activity stays private",
                                detail: "Checkpoint does not read or store your Screen Time activity history.",
                                systemImage: "hand.raised"
                            )
                        }
                    }
                }

                if let message = accessErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if requiresDataEraseRecovery {
                    PrimaryActionButton(
                        title: "Retry data erasure",
                        systemImage: "trash"
                    ) {
                        eraseAllData()
                    }
                } else if screenTime.setupState == .unavailable {
                    Text("Screen Time app protection requires a supported iPhone build.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                } else if screenTime.authorizationState == .denied {
                    SecondaryActionButton(
                        title: "Open iPhone Settings",
                        systemImage: "gear"
                    ) {
                        openSystemSettings()
                    }
                } else {
                    PrimaryActionButton(
                        title: authorizationButtonTitle,
                        systemImage: "shield",
                        isLoading: screenTime.isRequestingAuthorization
                    ) {
                        Task {
                            await screenTime.requestAuthorization()
                        }
                    }
                    .disabled(screenTime.isRequestingAuthorization)
                }

                privacyAndAccountPanel
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .checkpointScreenBackground()
        .preferredColorScheme(.light)
        .alert("Erase all Checkpoint data?", isPresented: $isEraseConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Erase all data", role: .destructive) {
                eraseAllData()
            }
        } message: {
            Text("This removes goals, progress, protected-app selections, diagnostics, and the anonymous backend install ID.")
        }
    }

    private var authorizationButtonTitle: String {
        if screenTime.isRequestingAuthorization {
            return "Requesting access"
        }

        return screenTime.setupState == .failed ? "Try Screen Time access again" : "Allow Screen Time"
    }

    private var requiresDataEraseRecovery: Bool {
        screenTime.requiresSharedDataEraseRecovery
            || store.requiresPersistenceEraseRecovery
    }

    private var accessHeading: String {
        requiresDataEraseRecovery
            ? "Finish erasing Checkpoint data"
            : "Screen Time access is required"
    }

    private var accessDetail: String {
        if requiresDataEraseRecovery {
            return "Checkpoint must verify that its local app and Screen Time data are removed before you can continue or create a new goal."
        }

        return "Checkpoint uses Apple's Screen Time controls to place a short question before apps you choose to protect. Access is required before you create your first goal."
    }

    private var accessErrorMessage: String? {
        if requiresDataEraseRecovery {
            return store.persistenceRecoveryMessage
                ?? screenTime.sharedDataEraseErrorMessage
                ?? "Checkpoint could not finish erasing local data."
        }

        return screenTime.userFacingErrorMessage
    }

    private var privacyAndAccountPanel: some View {
        SectionPanel("Privacy & account") {
            VStack(alignment: .leading, spacing: 14) {
                if let privacyPolicyURL = legalLinks.privacyPolicyURL {
                    accessLink(
                        title: "Privacy Policy",
                        systemImage: "hand.raised",
                        url: privacyPolicyURL
                    )
                }

                if let supportURL = legalLinks.supportURL {
                    accessLink(
                        title: "Support",
                        systemImage: "questionmark.circle",
                        url: supportURL
                    )
                }

                accessLink(
                    title: "Terms of Use",
                    systemImage: "doc.text",
                    url: LegalLinks.termsOfUseURL
                )

                if let subscriptionURL = URL(string: "https://apps.apple.com/account/subscriptions") {
                    accessLink(
                        title: "Manage subscription",
                        systemImage: "creditcard",
                        url: subscriptionURL
                    )
                }

                Divider()

                Button(role: .destructive) {
                    isEraseConfirmationPresented = true
                } label: {
                    Label("Erase all Checkpoint data", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func accessLink(title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CheckpointTheme.teal)
        }
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

    private func permissionBenefit(
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
