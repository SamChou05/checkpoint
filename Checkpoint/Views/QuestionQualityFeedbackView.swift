import SwiftUI

struct QuestionQualityFeedbackContext: Identifiable, Equatable {
    var questionID: CheckpointQuestion.ID
    var goalID: Goal.ID
    var prompt: String
    var existingReason: QuestionReportReason?

    var id: String {
        "\(goalID.uuidString):\(questionID.uuidString)"
    }
}

struct QuestionQualityFeedbackPresentation: Equatable {
    static let successDetail = "Your saved answer and checkpoint result are unchanged."
    static let dataUseDetail = "To avoid repeats, Checkpoint may send this question’s text—not your selected reason—to its AI question service. This doesn’t create a support ticket."
    static let failureDetail = "Couldn’t save this change. Check available device storage and try again."
    static let historyBadgeTitle = "QUESTION REMOVED"

    var title: String
    var detail: String
    var actionTitle: String
    var successTitle: String

    static func supportsRemoval(in purpose: CheckpointSessionPurpose) -> Bool {
        purpose != .preview
    }

    init(existingReason: QuestionReportReason?) {
        if existingReason == nil {
            title = "Remove this question?"
            detail = "Choose what was off. It won’t appear in future practice."
            actionTitle = "Remove from practice"
            successTitle = "Removed from future practice"
        } else {
            title = "Update why it was removed"
            detail = "Choose the reason that best describes the issue."
            actionTitle = "Update reason"
            successTitle = "Reason updated"
        }
    }
}

struct QuestionReportReasonPresentation: Equatable {
    var title: String
    var detail: String
    var systemImage: String

    init(reason: QuestionReportReason) {
        title = reason.rawValue

        switch reason {
        case .wrongAnswer:
            detail = "The expected answer or explanation seems incorrect."
            systemImage = "exclamationmark.circle"
        case .confusing:
            detail = "The wording or choices are hard to understand."
            systemImage = "text.bubble"
        case .irrelevant:
            detail = "It doesn’t match this goal or skill."
            systemImage = "scope"
        case .tooEasy:
            detail = "It isn’t challenging enough."
            systemImage = "arrow.down.right"
        case .tooHard:
            detail = "It’s beyond the level I’m practicing."
            systemImage = "arrow.up.right"
        }
    }
}

struct QuestionRemovalControlPresentation: Equatable {
    var title: String
    var detail: String
    var actionTitle: String
    var systemImage: String
    var accessibilityLabel: String
    var accessibilityHint: String

    init(report: QuestionQualityReport?) {
        if let report {
            title = "Removed from future practice"
            detail = report.reason.rawValue
            actionTitle = "Edit"
            systemImage = "eye.slash.fill"
            accessibilityLabel = "Removed from future practice. Reason: \(report.reason.rawValue)."
            accessibilityHint = "Change the saved reason"
        } else {
            title = "Question issue?"
            detail = "Remove it from future practice"
            actionTitle = "Remove"
            systemImage = "exclamationmark.bubble"
            accessibilityLabel = "Question issue. Remove this question from future practice."
            accessibilityHint = "Choose why this question should not appear again"
        }
    }
}

struct QuestionQualityFeedbackView: View {
    var context: QuestionQualityFeedbackContext
    var submit: (QuestionReportReason) -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: QuestionReportReason?
    @State private var didSave = false
    @State private var feedbackSequence = 0
    @State private var errorMessage: String?
    @AccessibilityFocusState private var accessibilityFocus: QuestionQualityAccessibilityFocus?

    init(
        context: QuestionQualityFeedbackContext,
        initiallySaved: Bool = false,
        submit: @escaping (QuestionReportReason) -> Bool
    ) {
        self.context = context
        self.submit = submit
        _selectedReason = State(initialValue: context.existingReason)
        _didSave = State(initialValue: initiallySaved)
        _feedbackSequence = State(initialValue: initiallySaved ? 1 : 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if didSave {
                        successContent
                            .transition(contentTransition)
                    } else {
                        feedbackForm
                            .transition(contentTransition)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .animation(
                    CheckpointMotion.animation(CheckpointMotion.reveal, reduceMotion: reduceMotion),
                    value: didSave
                )
            }
            .checkpointScreenBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
            .navigationTitle("Question issue")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(CheckpointTheme.teal)
                }
            }
        }
        .sensoryFeedback(.success, trigger: feedbackSequence)
    }

    private var feedbackForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            feedbackHeader
            questionPreview
            dataUsePanel

            VStack(alignment: .leading, spacing: 10) {
                Text("WHAT WAS OFF?")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(CheckpointTheme.muted)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 8) {
                    ForEach(QuestionReportReason.allCases) { reason in
                        reasonButton(reason)
                    }
                }
            }

        }
    }

    private var feedbackHeader: some View {
        let presentation = QuestionQualityFeedbackPresentation(
            existingReason: context.existingReason
        )

        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: "eye.slash")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CheckpointTheme.ink)
                .frame(width: 48, height: 48)
                .background(CheckpointTheme.mint, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.detail)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var questionPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("QUESTION")
                .font(.caption2.weight(.bold))
                .tracking(0.75)
                .foregroundStyle(CheckpointTheme.heroSuccess)

            Text(context.prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckpointTheme.heroText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CheckpointTheme.ink)
                .stroke(CheckpointTheme.heroBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question")
        .accessibilityValue(context.prompt)
    }

    private func reasonButton(_ reason: QuestionReportReason) -> some View {
        let presentation = QuestionReportReasonPresentation(reason: reason)
        let isSelected = selectedReason == reason

        return Button {
            withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
                selectedReason = reason
                errorMessage = nil
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: presentation.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isSelected ? CheckpointTheme.teal : CheckpointTheme.muted)
                    .frame(width: 38, height: 38)
                    .background(
                        (isSelected ? CheckpointTheme.teal.opacity(0.13) : CheckpointTheme.panelRaised),
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckpointTheme.text)

                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? CheckpointTheme.teal : CheckpointTheme.controlStroke)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(
                isSelected ? CheckpointTheme.teal.opacity(0.08) : CheckpointTheme.panel.opacity(0.78),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(
                        isSelected ? CheckpointTheme.teal.opacity(0.42) : CheckpointTheme.hairline,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(CheckpointPressButtonStyle(role: .surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(presentation.detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dataUsePanel: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lock.shield")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CheckpointTheme.teal)
                .frame(width: 34, height: 34)
                .background(CheckpointTheme.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("What happens")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)

                Text(QuestionQualityFeedbackPresentation.successDetail)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Text(QuestionQualityFeedbackPresentation.dataUseDetail)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CheckpointTheme.panelRaised.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var successContent: some View {
        let presentation = QuestionQualityFeedbackPresentation(
            existingReason: context.existingReason
        )

        return VStack(spacing: 18) {
            Spacer(minLength: 22)

            Image(systemName: "checkmark")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(CheckpointTheme.ink)
                .frame(width: 64, height: 64)
                .background(CheckpointTheme.mint, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: CheckpointTheme.shadowCard, radius: 12, y: 6)
                .symbolEffect(.bounce, options: .nonRepeating, value: feedbackSequence)
                .symbolEffectsRemoved(reduceMotion)
                .accessibilityHidden(true)

            VStack(spacing: 7) {
                Text(presentation.successTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CheckpointTheme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(QuestionQualityFeedbackPresentation.successDetail)
                    .font(.subheadline)
                    .foregroundStyle(CheckpointTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($accessibilityFocus, equals: .success)

            if let selectedReason {
                StatusBadge(text: selectedReason.rawValue, tint: CheckpointTheme.teal)
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionBar: some View {
        let presentation = QuestionQualityFeedbackPresentation(
            existingReason: context.existingReason
        )
        let isDisabled = !didSave && selectedReason == nil
        let actionTitle = didSave
            ? "Done"
            : (selectedReason == nil ? "Choose a reason" : presentation.actionTitle)

        return VStack(spacing: 0) {
            Divider()
                .overlay(CheckpointTheme.hairline)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .accessibilityFocused($accessibilityFocus, equals: .error)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            PrimaryActionButton(
                title: actionTitle,
                systemImage: didSave
                    ? "checkmark"
                    : (selectedReason == nil ? "list.bullet" : "eye.slash")
            ) {
                if didSave {
                    dismiss()
                } else {
                    saveSelection()
                }
            }
            .disabled(isDisabled)
            .padding(.horizontal, 20)
            .padding(.top, errorMessage == nil ? 12 : 8)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
        .animation(
            CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion),
            value: errorMessage
        )
    }

    private var contentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.985))
    }

    private func saveSelection() {
        guard let selectedReason else { return }

        guard submit(selectedReason) else {
            withAnimation(CheckpointMotion.animation(CheckpointMotion.change, reduceMotion: reduceMotion)) {
                errorMessage = QuestionQualityFeedbackPresentation.failureDetail
            }
            Task { @MainActor in
                await Task.yield()
                accessibilityFocus = .error
            }
            return
        }

        errorMessage = nil
        withAnimation(CheckpointMotion.animation(CheckpointMotion.reveal, reduceMotion: reduceMotion)) {
            didSave = true
            feedbackSequence += 1
        }
        Task { @MainActor in
            await Task.yield()
            accessibilityFocus = .success
        }
    }
}

struct QuestionRemovalControl: View {
    var report: QuestionQualityReport?
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let presentation = QuestionRemovalControlPresentation(report: report)

        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        identity(presentation)
                        actionCue(presentation)
                            .padding(.leading, 48)
                    }
                } else {
                    HStack(spacing: 12) {
                        identity(presentation)
                            .layoutPriority(1)
                        Spacer(minLength: 6)
                        actionCue(presentation)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                CheckpointTheme.panelRaised.opacity(0.62),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        report == nil ? CheckpointTheme.hairline : CheckpointTheme.teal.opacity(0.20),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(CheckpointPressButtonStyle(role: .surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint(presentation.accessibilityHint)
    }

    private func identity(_ presentation: QuestionRemovalControlPresentation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(report == nil ? CheckpointTheme.muted : CheckpointTheme.teal)
                .frame(width: 38, height: 38)
                .background(
                    (report == nil ? CheckpointTheme.panel : CheckpointTheme.teal.opacity(0.11)),
                    in: RoundedRectangle(cornerRadius: 11)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckpointTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(CheckpointTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionCue(_ presentation: QuestionRemovalControlPresentation) -> some View {
        HStack(spacing: 5) {
            Text(presentation.actionTitle)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(CheckpointTheme.teal)
        .frame(minHeight: 44)
    }
}

private enum QuestionQualityAccessibilityFocus: Hashable {
    case error
    case success
}
