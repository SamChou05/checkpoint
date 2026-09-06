import SwiftUI
import UIKit

/// Setup destinations are routing context, not a numbered checklist for the user.
enum CheckpointSetupStep: Int, CaseIterable {
    case goal = 1
    case skillMap
    case protection

    var title: String {
        switch self {
        case .goal: "Goal"
        case .skillMap: "Skill Map"
        case .protection: "Protection"
        }
    }

    var accessibilityLabel: String { title }

    var mascotPose: CheckpointMascotPose {
        switch self {
        case .goal: .wave
        case .skillMap: .celebrate
        case .protection: .think
        }
    }
}

enum CheckpointMascotPose: String, CaseIterable, Sendable {
    case wave
    case think
    case celebrate

    var assetName: String {
        switch self {
        case .wave: "MascotWave"
        case .think: "MascotThink"
        case .celebrate: "MascotCelebrate"
        }
    }
}

/// One entrance and one brief reaction per new line, with no idle animation.
struct CheckpointDialogueMotionPolicy: Equatable {
    let reduceMotion: Bool
    let voiceOverEnabled: Bool

    var permitsSpatialMotion: Bool { !reduceMotion && !voiceOverEnabled }
    var entranceOffset: CGFloat { permitsSpatialMotion ? -18 : 0 }
    var entranceRotation: Double { permitsSpatialMotion ? -7 : 0 }
    var entranceScale: CGFloat { permitsSpatialMotion ? 0.92 : 1 }
    var reactionLift: CGFloat { permitsSpatialMotion ? -6 : 0 }
    var reactionRotation: Double { permitsSpatialMotion ? -4 : 0 }
    var entranceAnimation: Animation? {
        permitsSpatialMotion ? .spring(duration: 0.48, bounce: 0.24) : nil
    }
}

enum CheckpointDialogueMotionPhase: Equatable {
    case entering
    case reacting
    case settled
}

/// Matching character portraits accompany generation and success states.
struct CheckpointMascotCharacter: View {
    let pose: CheckpointMascotPose
    let size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(named: pose.assetName, in: .main, compatibleWith: nil) {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                CheckpointMascotMark(size: size, cornerRadius: size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 6, style: .continuous))
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// A short, immediately readable conversation follows the user across setup.
struct CheckpointSetupGuide: View {
    let step: CheckpointSetupStep
    let title: String
    let message: String
    var reduceMotionOverride: Bool? = nil
    var pose: CheckpointMascotPose? = nil
    var dialogueID: String? = nil
    var motionObserver: ((CheckpointDialogueMotionPhase) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasAppeared = false
    @State private var isReacting = false
    @State private var motionRequestNumber = 0
    @State private var lastPresentedDialogue: DialogueIdentity? = nil

    private var resolvedPose: CheckpointMascotPose { pose ?? step.mascotPose }

    private var motionPolicy: CheckpointDialogueMotionPolicy {
        CheckpointDialogueMotionPolicy(
            reduceMotion: reduceMotionOverride ?? systemReduceMotion,
            voiceOverEnabled: voiceOverEnabled
        )
    }

    private var motionRequest: DialogueMotionRequest {
        DialogueMotionRequest(
            identity: DialogueIdentity(title: title, message: message, pose: resolvedPose, id: dialogueID),
            policy: motionPolicy
        )
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        mascot(size: 52)
                        speakerName
                    }
                    speech(showsSpeaker: false)
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    mascot(size: 96)
                    speech(showsSpeaker: true)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: motionRequest) {
            await animateDialogueBeat()
        }
        .onDisappear {
            motionRequestNumber += 1
            settleWithoutAnimation()
            hasAppeared = false
            lastPresentedDialogue = nil
        }
    }

    @ViewBuilder
    private func mascot(size: CGFloat) -> some View {
        if motionPolicy.permitsSpatialMotion {
            character(size: size)
                .offset(
                    x: hasAppeared ? 0 : motionPolicy.entranceOffset,
                    y: isReacting ? motionPolicy.reactionLift : 0
                )
                .rotationEffect(.degrees(
                    hasAppeared
                        ? (isReacting ? motionPolicy.reactionRotation : 0)
                        : motionPolicy.entranceRotation
                ))
                .scaleEffect(hasAppeared ? 1 : motionPolicy.entranceScale)
        } else {
            // Removing the transforms also stops an in-flight spring immediately.
            character(size: size)
        }
    }

    private func character(size: CGFloat) -> some View {
        CheckpointMascotCharacter(pose: resolvedPose, size: size)
            .shadow(color: CheckpointTheme.shadowCard, radius: 6, y: 5)
            .accessibilityHidden(true)
    }

    private var speakerName: some View {
        Text("CHECKPOINT")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(CheckpointTheme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(CheckpointTheme.heroSuccess, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }

    private func speech(showsSpeaker: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSpeaker {
                speakerName
            }

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.heroMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CheckpointTheme.ink)
                .strokeBorder(CheckpointTheme.heroSuccess.opacity(0.26), lineWidth: 1)
        )
        .overlay(alignment: dynamicTypeSize.isAccessibilitySize ? .topLeading : .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(CheckpointTheme.ink)
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(45))
                .offset(
                    x: dynamicTypeSize.isAccessibilitySize ? 22 : -4,
                    y: dynamicTypeSize.isAccessibilitySize ? -4 : 0
                )
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    @MainActor
    private func animateDialogueBeat() async {
        motionRequestNumber += 1
        let requestNumber = motionRequestNumber
        let isNewLine = lastPresentedDialogue != motionRequest.identity
        lastPresentedDialogue = motionRequest.identity
        guard motionPolicy.permitsSpatialMotion else {
            settleWithoutAnimation()
            return
        }
        guard !hasAppeared || isNewLine else { return }

        do {
            if !hasAppeared {
                motionObserver?(.entering)
                withAnimation(motionPolicy.entranceAnimation) {
                    hasAppeared = true
                }
                try await Task.sleep(for: .milliseconds(480))
            } else {
                motionObserver?(.reacting)
                withAnimation(.easeOut(duration: 0.12)) {
                    isReacting = true
                }
                try await Task.sleep(for: .milliseconds(120))
                guard requestNumber == motionRequestNumber else { return }
                withAnimation(.spring(duration: 0.32, bounce: 0.2)) {
                    isReacting = false
                }
                try await Task.sleep(for: .milliseconds(320))
            }
            guard !Task.isCancelled, requestNumber == motionRequestNumber else { return }
            motionObserver?(.settled)
        } catch {
            // An interrupted line or dismissed screen cannot leave a reaction running.
            if requestNumber == motionRequestNumber {
                settleWithoutAnimation()
            }
        }
    }

    @MainActor
    private func settleWithoutAnimation() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            hasAppeared = true
            isReacting = false
        }
        motionObserver?(.settled)
    }

    private struct DialogueIdentity: Equatable {
        let title: String
        let message: String
        let pose: CheckpointMascotPose
        let id: String?
    }

    private struct DialogueMotionRequest: Equatable {
        let identity: DialogueIdentity
        let policy: CheckpointDialogueMotionPolicy
    }
}
