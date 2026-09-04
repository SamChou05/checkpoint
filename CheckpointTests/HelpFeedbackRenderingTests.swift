import SwiftUI
import XCTest
@testable import Checkpoint

final class HelpFeedbackRenderingTests: XCTestCase {
    @MainActor
    func testFeedbackDraftCopyKeepsLocalOnlyOutcomeRetentionAndConfirmationLanguageExact() {
        XCTAssertEqual(
            FeedbackDraftCopy.localOnlyDetail,
            "Saving stores a draft in Checkpoint’s local app data. Nothing is sent until you tap Share and choose a destination."
        )
        XCTAssertEqual(
            FeedbackDraftCopy.savedDetail,
            "Draft saved in Checkpoint. Nothing was sent."
        )
        XCTAssertEqual(
            FeedbackDraftCopy.emptyMessageDetail,
            "Describe what happened or what would help before saving."
        )
        XCTAssertEqual(
            FeedbackDraftCopy.messageTooLongDetail,
            "Use 1,000 characters or fewer."
        )
        XCTAssertEqual(
            FeedbackDraftCopy.persistenceFailureDetail,
            "This draft couldn’t be saved. Your text is still here."
        )
        XCTAssertEqual(
            FeedbackDraftCopy.retentionDetail,
            "Checkpoint keeps your 100 most recent feedback drafts."
        )
        XCTAssertEqual(FeedbackDraftCopy.discardTitle, "Discard this draft?")
        XCTAssertEqual(
            FeedbackDraftCopy.discardDetail,
            "This text hasn’t been saved or shared."
        )
        XCTAssertEqual(FeedbackDraftCopy.deleteTitle, "Delete this draft?")
        XCTAssertEqual(
            FeedbackDraftCopy.deleteDetail,
            "Removes it from Saved drafts and current app data. A recovery backup may keep the previous copy until a later successful save or Erase all data. Already shared copies are unaffected."
        )
    }

    @MainActor
    func testFeedbackDraftNoticesMapEverySaveOutcomeToClearState() {
        XCTAssertEqual(FeedbackDraftNotice(result: .saved), .saved)
        XCTAssertEqual(FeedbackDraftNotice(result: .emptyMessage), .emptyMessage)
        XCTAssertEqual(FeedbackDraftNotice(result: .messageTooLong), .messageTooLong)
        XCTAssertEqual(FeedbackDraftNotice(result: .notRetained), .persistenceFailure)
        XCTAssertEqual(FeedbackDraftNotice(result: .persistenceFailed), .persistenceFailure)

        XCTAssertEqual(FeedbackDraftNotice.saved.detail, FeedbackDraftCopy.savedDetail)
        XCTAssertEqual(FeedbackDraftNotice.saved.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(FeedbackDraftNotice.saved.tone, .success)

        XCTAssertEqual(
            FeedbackDraftNotice.emptyMessage.detail,
            FeedbackDraftCopy.emptyMessageDetail
        )
        XCTAssertEqual(FeedbackDraftNotice.emptyMessage.systemImage, "exclamationmark.circle.fill")
        XCTAssertEqual(FeedbackDraftNotice.emptyMessage.tone, .warning)

        XCTAssertEqual(
            FeedbackDraftNotice.messageTooLong.detail,
            FeedbackDraftCopy.messageTooLongDetail
        )
        XCTAssertEqual(FeedbackDraftNotice.messageTooLong.systemImage, "exclamationmark.circle.fill")
        XCTAssertEqual(FeedbackDraftNotice.messageTooLong.tone, .warning)

        XCTAssertEqual(
            FeedbackDraftNotice.persistenceFailure.detail,
            FeedbackDraftCopy.persistenceFailureDetail
        )
        XCTAssertEqual(
            FeedbackDraftNotice.persistenceFailure.systemImage,
            "externaldrive.badge.exclamationmark"
        )
        XCTAssertEqual(FeedbackDraftNotice.persistenceFailure.tone, .failure)
    }

    @MainActor
    func testUserEditingClearsAStaleFailureNoticeEvenWhenTheyDeleteAllText() {
        var state = FeedbackDraftEditingState(
            message: "Preserve this text",
            notice: .persistenceFailure
        )

        state.userEditedMessage("")

        XCTAssertEqual(state.message, "")
        XCTAssertNil(state.notice)

        state.userEditedMessage("Try again")
        state.applySaveResult(.persistenceFailed)
        XCTAssertEqual(state.message, "Try again")
        XCTAssertEqual(state.notice, .persistenceFailure)

        state.applySaveResult(.saved)
        XCTAssertEqual(state.message, "")
        XCTAssertEqual(state.notice, .saved)
    }

    @MainActor
    func testFeedbackDraftSettingsSummariesUseZeroSingularAndPluralCopy() {
        let empty = FeedbackDraftSettingsPresentation(count: 0)
        XCTAssertEqual(empty.detail, "Open support or save a local draft")
        XCTAssertEqual(
            empty.voiceOverValue,
            "No feedback drafts saved in Checkpoint. Nothing is sent automatically."
        )

        let singular = FeedbackDraftSettingsPresentation(count: 1)
        XCTAssertEqual(singular.detail, "1 local draft")
        XCTAssertEqual(
            singular.voiceOverValue,
            "1 feedback draft saved in Checkpoint. Nothing is sent automatically."
        )

        let plural = FeedbackDraftSettingsPresentation(count: 2)
        XCTAssertEqual(plural.detail, "2 local drafts")
        XCTAssertEqual(
            plural.voiceOverValue,
            "2 feedback drafts saved in Checkpoint. Nothing is sent automatically."
        )
    }

    func testPracticeHistorySettingsSummaryUsesTheFullStoredArchiveAcrossGoals() {
        let firstGoalID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let secondGoalID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let firstAttempt = CheckpointAttempt(
            questionID: UUID(uuidString: "00000000-0000-0000-0000-000000000311")!,
            goalID: firstGoalID,
            prompt: "First saved prompt",
            answer: "First saved answer",
            result: .correct,
            unlockMinutes: 0
        )
        let secondAttemptForSameGoal = CheckpointAttempt(
            questionID: UUID(uuidString: "00000000-0000-0000-0000-000000000312")!,
            goalID: firstGoalID,
            prompt: "Second saved prompt",
            answer: "Second saved answer",
            result: .partial,
            unlockMinutes: 0
        )
        let otherGoalAttempt = CheckpointAttempt(
            questionID: UUID(uuidString: "00000000-0000-0000-0000-000000000313")!,
            goalID: secondGoalID,
            prompt: "Other goal prompt",
            answer: "Other goal answer",
            result: .incorrect,
            unlockMinutes: 0
        )

        let empty = PracticeHistorySettingsPresentation(attempts: [])
        XCTAssertEqual(empty.answerCount, 0)
        XCTAssertEqual(empty.goalCount, 0)
        XCTAssertEqual(empty.trailingText, "0")
        XCTAssertEqual(empty.detail, "Saved answers from every goal will appear here")
        XCTAssertEqual(
            empty.voiceOverValue,
            "No saved answers yet. Practice history includes every goal."
        )

        let oneGoal = PracticeHistorySettingsPresentation(
            attempts: [firstAttempt, secondAttemptForSameGoal]
        )
        XCTAssertEqual(oneGoal.answerCount, 2)
        XCTAssertEqual(oneGoal.goalCount, 1)
        XCTAssertEqual(oneGoal.trailingText, "2")
        XCTAssertEqual(oneGoal.detail, "All saved answers from 1 goal")
        XCTAssertEqual(
            oneGoal.voiceOverValue,
            "2 saved answers from 1 goal. Opens the full practice archive."
        )

        let multipleGoals = PracticeHistorySettingsPresentation(
            attempts: [firstAttempt, secondAttemptForSameGoal, otherGoalAttempt]
        )
        XCTAssertEqual(multipleGoals.answerCount, 3)
        XCTAssertEqual(multipleGoals.goalCount, 2)
        XCTAssertEqual(multipleGoals.trailingText, "3")
        XCTAssertEqual(multipleGoals.detail, "All saved answers across 2 goals")
        XCTAssertEqual(
            multipleGoals.voiceOverValue,
            "3 saved answers across 2 goals. Opens the full practice archive."
        )
    }

    func testPracticeHistorySettingsSummaryUsesSingularAnswerGrammar() {
        let attempt = CheckpointAttempt(
            questionID: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!,
            goalID: UUID(uuidString: "00000000-0000-0000-0000-000000000322")!,
            prompt: "Saved prompt",
            answer: "Saved answer",
            result: .correct,
            unlockMinutes: 0
        )

        let presentation = PracticeHistorySettingsPresentation(attempts: [attempt])

        XCTAssertEqual(
            presentation.voiceOverValue,
            "1 saved answer from 1 goal. Opens the full practice archive."
        )
    }

    @MainActor
    func testFeedbackDraftComposerUsesTrimmedInputAndExactCharacterLimit() {
        let empty = FeedbackDraftComposerPresentation(message: "  \n\t  ")
        XCTAssertEqual(empty.trimmedMessage, "")
        XCTAssertEqual(empty.characterCount, 0)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.isTooLong)
        XCTAssertFalse(empty.hasUnsavedDraft)

        let maximumLengthMessage = String(
            repeating: "x",
            count: CheckpointStore.maximumIssueReportMessageLength
        )
        let atLimit = FeedbackDraftComposerPresentation(
            message: " \(maximumLengthMessage)\n"
        )
        XCTAssertEqual(atLimit.trimmedMessage, maximumLengthMessage)
        XCTAssertEqual(
            atLimit.characterCount,
            CheckpointStore.maximumIssueReportMessageLength
        )
        XCTAssertFalse(atLimit.isEmpty)
        XCTAssertFalse(atLimit.isTooLong)
        XCTAssertTrue(atLimit.hasUnsavedDraft)

        let overLimit = FeedbackDraftComposerPresentation(
            message: maximumLengthMessage + "x"
        )
        XCTAssertEqual(
            overLimit.characterCount,
            CheckpointStore.maximumIssueReportMessageLength + 1
        )
        XCTAssertTrue(overLimit.isTooLong)
        XCTAssertTrue(overLimit.hasUnsavedDraft)
    }

    @MainActor
    func testSharePayloadIncludesGoalOnlyForExplicitGoalContext() {
        let savedAt = Date(timeIntervalSince1970: 1_704_164_400)
        let goalID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let message = "The explanation did not match the selected answer."

        let unscopedPresentation = FeedbackDraftRowPresentation(
            report: makeReport(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                goalID: goalID,
                goalTitle: "A title alone is not consent",
                category: .questionIssue,
                message: message,
                createdAt: savedAt
            )
        )
        XCTAssertNil(unscopedPresentation.goalContext)
        XCTAssertEqual(
            unscopedPresentation.shareText,
            """
            Checkpoint feedback draft
            Category: Question issue
            Saved: \(unscopedPresentation.savedAt)

            \(message)
            """
        )
        XCTAssertFalse(unscopedPresentation.shareText.contains("A title alone is not consent"))
        XCTAssertFalse(unscopedPresentation.shareText.contains("Goal:"))

        let missingTitlePresentation = FeedbackDraftRowPresentation(
            report: makeReport(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                goalID: goalID,
                goalTitle: "  ",
                includesGoalContext: true,
                category: .questionIssue,
                message: message,
                createdAt: savedAt
            )
        )
        XCTAssertNil(missingTitlePresentation.goalContext)
        XCTAssertFalse(missingTitlePresentation.shareText.contains("Goal:"))

        let placeholderTitlePresentation = FeedbackDraftRowPresentation(
            report: makeReport(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                goalID: goalID,
                goalTitle: "  No goal  ",
                includesGoalContext: true,
                category: .questionIssue,
                message: message,
                createdAt: savedAt
            )
        )
        XCTAssertNil(placeholderTitlePresentation.goalContext)
        XCTAssertFalse(placeholderTitlePresentation.shareText.contains("Goal:"))

        let scopedPresentation = FeedbackDraftRowPresentation(
            report: makeReport(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                goalID: goalID,
                goalTitle: "  Pass the architecture interview  ",
                includesGoalContext: true,
                category: .questionIssue,
                message: message,
                createdAt: savedAt
            )
        )
        XCTAssertEqual(scopedPresentation.goalContext, "Goal: Pass the architecture interview")
        XCTAssertEqual(
            scopedPresentation.shareText,
            """
            Checkpoint feedback draft
            Category: Question issue
            Saved: \(scopedPresentation.savedAt)
            Goal: Pass the architecture interview

            \(message)
            """
        )
    }

    @MainActor
    func testLegacyAndExplicitlyUnscopedDraftsKeepStoredGoalContextPrivate() throws {
        let goalID = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
        let legacyTitle = "Private legacy goal"
        let encodedReport = try JSONEncoder().encode(
            makeReport(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!,
                goalID: goalID,
                goalTitle: legacyTitle,
                includesGoalContext: true,
                category: .generalFeedback,
                message: "Legacy feedback",
                createdAt: Date(timeIntervalSince1970: 1_704_164_400)
            )
        )
        var legacyJSONObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedReport) as? [String: Any]
        )
        legacyJSONObject.removeValue(forKey: "includesGoalContext")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSONObject)
        let decodedLegacyReport = try JSONDecoder().decode(UserIssueReport.self, from: legacyData)

        XCTAssertNil(decodedLegacyReport.includesGoalContext)
        let legacyPresentation = FeedbackDraftRowPresentation(report: decodedLegacyReport)
        XCTAssertNil(legacyPresentation.goalContext)
        XCTAssertFalse(legacyPresentation.shareText.contains(legacyTitle))
        XCTAssertFalse(legacyPresentation.shareText.contains("Goal:"))

        let explicitlyUnscopedPresentation = FeedbackDraftRowPresentation(
            report: makeReport(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000107")!,
                goalID: goalID,
                goalTitle: legacyTitle,
                includesGoalContext: false,
                category: .generalFeedback,
                message: "Explicitly unscoped feedback",
                createdAt: Date(timeIntervalSince1970: 1_704_164_400)
            )
        )
        XCTAssertNil(explicitlyUnscopedPresentation.goalContext)
        XCTAssertFalse(explicitlyUnscopedPresentation.shareText.contains(legacyTitle))
        XCTAssertFalse(explicitlyUnscopedPresentation.shareText.contains("Goal:"))
    }

    @MainActor
    func testSavedDraftRowsHaveDistinctShareAccessibilityLabels() {
        let first = FeedbackDraftRowPresentation(
            report: makeReport(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                goalID: nil,
                goalTitle: "",
                category: .generalFeedback,
                message: "First draft",
                createdAt: Date(timeIntervalSince1970: 1_704_164_400)
            ),
            position: 1
        )
        let second = FeedbackDraftRowPresentation(
            report: makeReport(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                goalID: nil,
                goalTitle: "",
                category: .generalFeedback,
                message: "Second draft",
                createdAt: Date(timeIntervalSince1970: 1_704_164_400)
            ),
            position: 2
        )

        XCTAssertEqual(
            first.shareAccessibilityLabel,
            "Share feedback draft 1, General feedback, saved \(first.savedAt)"
        )
        XCTAssertEqual(
            second.shareAccessibilityLabel,
            "Share feedback draft 2, General feedback, saved \(second.savedAt)"
        )
        XCTAssertNotEqual(first.shareAccessibilityLabel, second.shareAccessibilityLabel)
        XCTAssertEqual(
            first.deleteAccessibilityLabel,
            "Delete feedback draft 1, General feedback, saved \(first.savedAt)"
        )
        XCTAssertNotEqual(first.shareAccessibilityLabel, first.deleteAccessibilityLabel)
    }

    @MainActor
    func testHelpFeedbackSurfacesRenderAcrossKeyLayoutsAndStates() throws {
        let emptySuiteName = "HelpFeedbackRenderingTests.Empty.\(UUID().uuidString)"
        let savedSuiteName = "HelpFeedbackRenderingTests.Saved.\(UUID().uuidString)"
        let emptyDefaults = try XCTUnwrap(UserDefaults(suiteName: emptySuiteName))
        let savedDefaults = try XCTUnwrap(UserDefaults(suiteName: savedSuiteName))
        defer {
            emptyDefaults.removePersistentDomain(forName: emptySuiteName)
            savedDefaults.removePersistentDomain(forName: savedSuiteName)
        }

        let fixedDate = Date(timeIntervalSince1970: 1_704_164_400)
        let goal = Goal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            title: "Pass a senior architecture interview",
            deadline: fixedDate.addingTimeInterval(86_400 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "system design, communication, and tradeoff analysis",
            preferredQuestionStyle: .multipleChoice
        )

        let emptyStore = CheckpointStore(defaults: emptyDefaults)
        emptyStore.goal = goal
        emptyStore.goalProfiles = [goal]

        let savedStore = CheckpointStore(defaults: savedDefaults)
        savedStore.goal = goal
        savedStore.goalProfiles = [goal]
        savedStore.issueReports = [
            makeReport(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                goalID: goal.id,
                goalTitle: goal.title,
                includesGoalContext: true,
                category: .questionIssue,
                message: "The rationale was clear, but the marked answer contradicted the final paragraph.",
                createdAt: fixedDate.addingTimeInterval(3_600)
            ),
            makeReport(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                goalID: nil,
                goalTitle: "",
                category: .generalFeedback,
                message: "Please make the review state easier to distinguish from a new question.",
                createdAt: fixedDate
            )
        ]

        let supportURL = try XCTUnwrap(URL(string: "https://example.com/checkpoint-support"))
        let legalLinks = LegalLinks(privacyPolicyURL: nil, supportURL: supportURL)
        let overLimitMessage = String(
            String(
                repeating: "Explain what changed, what you expected, and why the current result blocks progress. ",
                count: 20
            ).prefix(CheckpointStore.maximumIssueReportMessageLength + 1)
        )
        XCTAssertEqual(
            overLimitMessage.count,
            CheckpointStore.maximumIssueReportMessageLength + 1
        )

        let fixtures = [
            HelpFeedbackRenderFixture(
                name: "help-feedback-light-empty",
                width: 393,
                height: 1_000,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    QuestionReportsView(store: emptyStore, legalLinks: legalLinks)
                )
            ),
            HelpFeedbackRenderFixture(
                name: "help-feedback-dark-saved-drafts",
                width: 393,
                height: 1_400,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    QuestionReportsView(store: savedStore, legalLinks: legalLinks)
                )
            ),
            HelpFeedbackRenderFixture(
                name: "help-feedback-compact-width",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    QuestionReportsView(store: emptyStore, legalLinks: legalLinks)
                )
            ),
            HelpFeedbackRenderFixture(
                name: "help-feedback-accessibility2",
                width: 393,
                height: 1_800,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    QuestionReportsView(store: savedStore, legalLinks: legalLinks)
                )
            ),
            HelpFeedbackRenderFixture(
                name: "help-feedback-long-over-limit",
                width: 393,
                height: 1_000,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    QuestionReportsView(
                        store: emptyStore,
                        legalLinks: legalLinks,
                        initialCategory: .appBlocking,
                        initialMessage: overLimitMessage,
                        initiallyIncludesCurrentGoal: true
                    )
                )
            ),
            HelpFeedbackRenderFixture(
                name: "help-feedback-saved-notice",
                width: 393,
                height: 1_000,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    QuestionReportsView(
                        store: savedStore,
                        legalLinks: legalLinks,
                        initialNotice: .saved
                    )
                )
            ),
            HelpFeedbackRenderFixture(
                name: "help-feedback-failure-notice",
                width: 393,
                height: 1_000,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    QuestionReportsView(
                        store: emptyStore,
                        legalLinks: legalLinks,
                        initialCategory: .goalSetup,
                        initialMessage: "My draft is still here so I can try saving it again.",
                        initialNotice: .persistenceFailure
                    )
                )
            )
        ]

        for fixture in fixtures {
            let image = HostedViewRenderer.image(
                for: fixture.content
                    .environment(\.colorScheme, fixture.colorScheme)
                    .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme
            )

            XCTAssertGreaterThan(image.size.width, 0, fixture.name)
            XCTAssertGreaterThan(image.size.height, 0, fixture.name)
            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func makeReport(
        id: UUID,
        goalID: Goal.ID?,
        goalTitle: String,
        includesGoalContext: Bool? = nil,
        category: IssueReportCategory,
        message: String,
        createdAt: Date
    ) -> UserIssueReport {
        UserIssueReport(
            id: id,
            goalID: goalID,
            goalTitle: goalTitle,
            includesGoalContext: includesGoalContext,
            category: category,
            message: message,
            contact: "",
            createdAt: createdAt
        )
    }
}

private struct HelpFeedbackRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var content: AnyView
}
