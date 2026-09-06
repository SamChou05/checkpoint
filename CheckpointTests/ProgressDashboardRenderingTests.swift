import SwiftUI
import UIKit
import XCTest
@testable import Checkpoint

final class ProgressDashboardRenderingTests: XCTestCase {
    @MainActor
    func testProgressStateMotionPolicyHonorsReduceMotion() {
        let standard = ProgressStateMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .choreographed)
        XCTAssertNotNil(standard.animation)

        let reduced = ProgressStateMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.animation)
    }

    @MainActor
    func testGoalChangePolicyResetsOnlyGoalScopedPresentation() {
        let firstGoalID = Goal.ID()
        let secondGoalID = Goal.ID()
        XCTAssertFalse(
            ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                from: firstGoalID,
                to: firstGoalID
            )
        )
        XCTAssertFalse(
            ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                from: nil,
                to: nil
            )
        )
        XCTAssertTrue(
            ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                from: firstGoalID,
                to: secondGoalID
            )
        )
        XCTAssertTrue(
            ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                from: nil,
                to: firstGoalID
            )
        )
        XCTAssertTrue(
            ProgressScreenChangePolicy.resetsGoalScopedPresentation(
                from: firstGoalID,
                to: nil
            )
        )
        XCTAssertTrue(
            ProgressScreenChangePolicy.suppressesGeneralAccessibilityResponse(
                hasPendingSkillEvidenceRequest: true
            )
        )
        XCTAssertFalse(
            ProgressScreenChangePolicy.suppressesGeneralAccessibilityResponse(
                hasPendingSkillEvidenceRequest: false
            )
        )

        XCTAssertTrue(
            ProgressGoalSwitchInteractionPolicy.animatesScroll(
                reduceMotion: false,
                assistiveNavigationEnabled: false
            )
        )
        XCTAssertFalse(
            ProgressGoalSwitchInteractionPolicy.animatesScroll(
                reduceMotion: true,
                assistiveNavigationEnabled: false
            )
        )
        XCTAssertFalse(
            ProgressGoalSwitchInteractionPolicy.animatesScroll(
                reduceMotion: false,
                assistiveNavigationEnabled: true
            )
        )
    }

    @MainActor
    func testSkillEvidenceTargetIsCreatedOnlyForRecommendations() throws {
        let goalID = Goal.ID()
        let skillID = SkillMapTopic.ID()
        let recommendationState = try makeRecommendationState(
            goalID: goalID,
            skillID: skillID,
            skillName: "Reliability and failure recovery"
        )

        let target = try XCTUnwrap(
            ProgressSkillEvidenceRoutingPolicy.target(
                for: recommendationState,
                goalID: goalID
            )
        )

        XCTAssertEqual(target.goalID, goalID)
        XCTAssertEqual(target.skillID, skillID)
        XCTAssertEqual(target.skillName, "Reliability and failure recovery")
        XCTAssertNil(
            ProgressSkillEvidenceRoutingPolicy.target(
                for: .awaitingQuestion,
                goalID: goalID
            )
        )
        XCTAssertNil(
            ProgressSkillEvidenceRoutingPolicy.target(
                for: .caughtUp,
                goalID: goalID
            )
        )
    }

    @MainActor
    func testSkillEvidenceRoutingPrefersIDThenFallsBackToCanonicalName() {
        let goalID = Goal.ID()
        let exactSkillID = SkillMapTopic.ID()
        let canonicalNameSkillID = SkillMapTopic.ID()
        let exactMatch = TopicCompetency.initial(
            topic: "A different display name",
            goalID: goalID,
            skillID: exactSkillID
        )
        let canonicalNameMatch = TopicCompetency.initial(
            topic: "Evidence evaluation",
            goalID: goalID,
            skillID: canonicalNameSkillID
        )
        let foreignExactMatch = TopicCompetency.initial(
            topic: "Foreign goal evidence",
            goalID: Goal.ID(),
            skillID: exactSkillID
        )
        let competencies = [foreignExactMatch, exactMatch, canonicalNameMatch]

        XCTAssertEqual(
            ProgressSkillEvidenceRoutingPolicy.competencyID(
                for: ProgressSkillEvidenceTarget(
                    goalID: goalID,
                    skillID: exactSkillID,
                    skillName: canonicalNameMatch.topic
                ),
                in: competencies
            ),
            exactMatch.id,
            "A stable skill ID must win even when the fallback name matches another row."
        )
        XCTAssertEqual(
            ProgressSkillEvidenceRoutingPolicy.competencyID(
                for: ProgressSkillEvidenceTarget(
                    goalID: goalID,
                    skillID: SkillMapTopic.ID(),
                    skillName: "  EVIDENCE\n EVALUATION: "
                ),
                in: competencies
            ),
            canonicalNameMatch.id,
            "A missing ID should fall back through the same canonical topic key used by reconciliation."
        )
        XCTAssertNil(
            ProgressSkillEvidenceRoutingPolicy.competencyID(
                for: ProgressSkillEvidenceTarget(
                    goalID: goalID,
                    skillID: nil,
                    skillName: "Unrepresented skill"
                ),
                in: competencies
            )
        )
        XCTAssertNil(
            ProgressSkillEvidenceRoutingPolicy.competencyID(
                for: ProgressSkillEvidenceTarget(
                    goalID: goalID,
                    skillID: nil,
                    skillName: "   "
                ),
                in: competencies
            )
        )
    }

    @MainActor
    func testSkillEvidenceRoutingDiscardsRequestsForAnotherGoal() {
        let requestedGoalID = Goal.ID()
        let target = ProgressSkillEvidenceTarget(
            goalID: requestedGoalID,
            skillID: SkillMapTopic.ID(),
            skillName: "Reliability and failure recovery"
        )

        XCTAssertFalse(
            ProgressSkillEvidenceRoutingPolicy.shouldDiscard(
                target: target,
                currentGoalID: requestedGoalID
            )
        )
        XCTAssertTrue(
            ProgressSkillEvidenceRoutingPolicy.shouldDiscard(
                target: target,
                currentGoalID: Goal.ID()
            )
        )
        XCTAssertTrue(
            ProgressSkillEvidenceRoutingPolicy.shouldDiscard(
                target: target,
                currentGoalID: nil
            )
        )
    }

    @MainActor
    func testSkillEvidenceInteractionPolicyHonorsMotionAndAssistiveNavigation() {
        let standard = ProgressSkillEvidenceInteractionPolicy(
            reduceMotion: false,
            voiceOverEnabled: false,
            switchControlEnabled: false
        )
        XCTAssertFalse(standard.suppressesTransientHighlight)
        XCTAssertTrue(standard.highlightsTarget)
        XCTAssertTrue(standard.animatesNavigation)

        for scenario in suppressiveSkillEvidencePolicies() {
            XCTAssertTrue(
                scenario.policy.suppressesTransientHighlight,
                scenario.name
            )
            XCTAssertFalse(scenario.policy.highlightsTarget, scenario.name)
            XCTAssertFalse(scenario.policy.animatesNavigation, scenario.name)
        }

        XCTAssertTrue(
            ProgressSkillEvidenceDeliveryPolicy.canDeliver(
                isVisible: true,
                isSceneActive: true,
                isCoveredByModalPresentation: false
            )
        )
        XCTAssertFalse(
            ProgressSkillEvidenceDeliveryPolicy.canDeliver(
                isVisible: false,
                isSceneActive: true,
                isCoveredByModalPresentation: false
            )
        )
        XCTAssertFalse(
            ProgressSkillEvidenceDeliveryPolicy.canDeliver(
                isVisible: true,
                isSceneActive: false,
                isCoveredByModalPresentation: false
            )
        )
        XCTAssertFalse(
            ProgressSkillEvidenceDeliveryPolicy.canDeliver(
                isVisible: true,
                isSceneActive: true,
                isCoveredByModalPresentation: true
            )
        )
    }

    func testNextFocusUpgradePresentationMakesThePlanBoundaryExplicit() {
        let presentation = ProgressNextFocusUpgradePresentation.standard

        XCTAssertEqual(presentation.eyebrow, "NEXT FOCUS")
        XCTAssertEqual(presentation.planBadge, "PRO")
        XCTAssertEqual(presentation.headline, "Know what to practice next")
        XCTAssertEqual(presentation.accessory, "See plans")
        XCTAssertEqual(presentation.accessibilityLabel, "Next Focus")
        XCTAssertTrue(presentation.accessibilityValue.hasPrefix("Requires Checkpoint Pro."))
        XCTAssertEqual(presentation.accessibilityHint, "Opens Checkpoint Pro plans.")
    }

    @MainActor
    func testSkillEvidenceInteractionPolicySnapsOnlyOnNewSuppression() {
        let standard = ProgressSkillEvidenceInteractionPolicy(
            reduceMotion: false,
            voiceOverEnabled: false,
            switchControlEnabled: false
        )
        for scenario in suppressiveSkillEvidencePolicies() {
            XCTAssertTrue(
                ProgressSkillEvidenceInteractionPolicy.shouldSnapActiveHighlight(
                    from: standard,
                    to: scenario.policy,
                    hasActiveHighlight: true
                ),
                scenario.name
            )
            XCTAssertFalse(
                ProgressSkillEvidenceInteractionPolicy.shouldSnapActiveHighlight(
                    from: standard,
                    to: scenario.policy,
                    hasActiveHighlight: false
                ),
                scenario.name
            )
            XCTAssertFalse(
                ProgressSkillEvidenceInteractionPolicy.shouldSnapActiveHighlight(
                    from: scenario.policy,
                    to: standard,
                    hasActiveHighlight: true
                ),
                scenario.name
            )
            XCTAssertFalse(
                ProgressSkillEvidenceInteractionPolicy.shouldSnapActiveHighlight(
                    from: scenario.policy,
                    to: scenario.policy,
                    hasActiveHighlight: true
                ),
                scenario.name
            )
        }
    }

    private func suppressiveSkillEvidencePolicies() -> [(
        name: String,
        policy: ProgressSkillEvidenceInteractionPolicy
    )] {
        [
            (
                "Reduce Motion",
                ProgressSkillEvidenceInteractionPolicy(
                    reduceMotion: true,
                    voiceOverEnabled: false,
                    switchControlEnabled: false
                )
            ),
            (
                "VoiceOver",
                ProgressSkillEvidenceInteractionPolicy(
                    reduceMotion: false,
                    voiceOverEnabled: true,
                    switchControlEnabled: false
                )
            ),
            (
                "Switch Control",
                ProgressSkillEvidenceInteractionPolicy(
                    reduceMotion: false,
                    voiceOverEnabled: false,
                    switchControlEnabled: true
                )
            ),
            (
                "combined assistive settings",
                ProgressSkillEvidenceInteractionPolicy(
                    reduceMotion: true,
                    voiceOverEnabled: true,
                    switchControlEnabled: true
                )
            )
        ]
    }

    @MainActor
    func testSkillEvidenceHighlightSnapsWhenMotionBecomesSuppressedWhileMounted() throws {
        let suiteName = "ProgressDashboardRenderingTests.DynamicEvidenceMotion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let store = makeReviewedStore(defaults: defaults, referenceDate: referenceDate)
        let target = try XCTUnwrap(
            ProgressSkillEvidenceRoutingPolicy.target(
                for: try XCTUnwrap(store.studyFocusState),
                goalID: try XCTUnwrap(store.goal?.id)
            )
        )
        let frame = CGRect(x: 0, y: 0, width: 393, height: 1_000)

        let driver = ProgressSkillEvidenceMotionDriver(reduceMotion: false)
        let hostingController = UIHostingController(
            rootView: ProgressSkillEvidenceMotionHarness(
                driver: driver,
                store: store,
                referenceDate: referenceDate,
                request: ProgressSkillEvidenceRequest(target: target)
            )
            .preferredColorScheme(.dark)
        )
        let window = UIWindow(frame: frame)
        defer { window.isHidden = true }
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = hostingController
        window.isHidden = false
        hostingController.view.frame = frame
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        let highlightedImage = mountedViewImage(
            of: hostingController.view,
            size: frame.size
        )
        driver.reduceMotion = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))

        let snappedImage = mountedViewImage(
            of: hostingController.view,
            size: frame.size
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.1))
        let settledImage = mountedViewImage(
            of: hostingController.view,
            size: frame.size
        )
        let highlightBorderRegion = CGRect(x: 353, y: 0, width: 7, height: frame.height)
        let activeBorderDifference = meanPixelDifference(
            highlightedImage,
            settledImage,
            region: highlightBorderRegion
        )
        let snappedBorderDifference = meanPixelDifference(
            snappedImage,
            settledImage,
            region: highlightBorderRegion
        )
        XCTAssertGreaterThan(
            activeBorderDifference,
            0.012,
            "The mounted test must intercept the active evidence highlight."
        )
        XCTAssertLessThan(
            snappedBorderDifference,
            activeBorderDifference * 0.55,
            "Enabling suppression must snap to the stable no-highlight rendering."
        )
    }

    @MainActor
    func testMembershipNextFocusHandoffClearsOnlyAfterTheMountedDestinationReveals() throws {
        let suiteName = "ProgressDashboardRenderingTests.NextFocusDelivery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let store = makeReviewedStore(defaults: defaults, referenceDate: referenceDate)
        let goalID = try XCTUnwrap(store.goal?.id)
        let continuation = MembershipActivationContinuation.revealNextFocus(
            sourceGoalID: goalID
        )
        store.membershipTier = .starter
        store.requestMembership(
            for: .adaptiveStudyAssist,
            continuation: continuation
        )
        store.reconcileMembershipEntitlement(
            isUnlocked: true,
            activationSource: .purchase
        )
        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        XCTAssertEqual(
            store.claimMembershipActivationContinuationForResume(),
            continuation
        )
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .resumeRequested)

        let recorder = ProgressSkillEvidenceResolutionRecorder()
        let frame = CGRect(x: 0, y: 0, width: 393, height: 1_000)
        let hostingController = UIHostingController(
            rootView: ProgressSkillEvidenceMotionHarness(
                driver: ProgressSkillEvidenceMotionDriver(reduceMotion: false),
                store: store,
                referenceDate: referenceDate,
                request: ProgressSkillEvidenceRequest(currentNextFocusFor: goalID),
                resolution: { request, resolution in
                    recorder.record(resolution)
                    guard resolution == .revealed else { return }
                    _ = store.completeResumedMembershipNextFocusReveal(
                        for: request.goalID
                    )
                }
            )
            .preferredColorScheme(.dark)
        )
        let window = UIWindow(frame: frame)
        defer { window.isHidden = true }
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = hostingController
        window.isHidden = false
        hostingController.view.frame = frame
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        XCTAssertEqual(recorder.events, [.revealed])
        XCTAssertNil(store.membershipActivationHandoff)

        let image = mountedViewImage(of: hostingController.view, size: frame.size)
        let attachment = XCTAttachment(image: image)
        attachment.name = "membership-next-focus-delivery-highlighted"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testMembershipNextFocusHandoffWaitsUntilParentPresentationClears() throws {
        let suiteName = "ProgressDashboardRenderingTests.NextFocusCovered.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let store = makeReviewedStore(defaults: defaults, referenceDate: referenceDate)
        let goalID = try XCTUnwrap(store.goal?.id)
        let continuation = MembershipActivationContinuation.revealNextFocus(
            sourceGoalID: goalID
        )
        store.membershipTier = .starter
        store.requestMembership(
            for: .adaptiveStudyAssist,
            continuation: continuation
        )
        store.reconcileMembershipEntitlement(isUnlocked: true)
        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        XCTAssertEqual(
            store.claimMembershipActivationContinuationForResume(),
            continuation
        )

        let recorder = ProgressSkillEvidenceResolutionRecorder()
        let driver = ProgressSkillEvidenceMotionDriver(
            reduceMotion: true,
            isCoveredByParentModal: true
        )
        let frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let hostingController = UIHostingController(
            rootView: ProgressSkillEvidenceMotionHarness(
                driver: driver,
                store: store,
                referenceDate: referenceDate,
                request: ProgressSkillEvidenceRequest(currentNextFocusFor: goalID),
                resolution: { request, resolution in
                    recorder.record(resolution)
                    guard resolution == .revealed else { return }
                    _ = store.completeResumedMembershipNextFocusReveal(
                        for: request.goalID
                    )
                }
            )
        )
        let window = UIWindow(frame: frame)
        defer { window.isHidden = true }
        window.rootViewController = hostingController
        window.isHidden = false
        hostingController.view.frame = frame
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .resumeRequested)

        driver.isCoveredByParentModal = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))

        XCTAssertEqual(recorder.events, [.revealed])
        XCTAssertNil(store.membershipActivationHandoff)
    }

    @MainActor
    func testMembershipNextFocusHandoffReturnsToTheReceiptWhenItsGoalChanges() throws {
        let suiteName = "ProgressDashboardRenderingTests.NextFocusStale.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let store = makeReviewedStore(defaults: defaults, referenceDate: referenceDate)
        let sourceGoalID = try XCTUnwrap(store.goal?.id)
        let continuation = MembershipActivationContinuation.revealNextFocus(
            sourceGoalID: sourceGoalID
        )
        store.membershipTier = .starter
        store.requestMembership(
            for: .adaptiveStudyAssist,
            continuation: continuation
        )
        store.reconcileMembershipEntitlement(isUnlocked: true)
        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        XCTAssertEqual(
            store.claimMembershipActivationContinuationForResume(),
            continuation
        )

        let replacementSkill = SkillMapTopic(name: "Conversational listening")
        var replacementGoal = makeInterviewGoal(title: "Reach conversational Spanish")
        replacementGoal.derivedSkillMap = GoalSkillMap(
            topics: [replacementSkill],
            status: .reviewed,
            provenance: .userEdited
        )
        store.goal = replacementGoal
        store.goalProfiles.append(replacementGoal)

        let recorder = ProgressSkillEvidenceResolutionRecorder()
        let frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let hostingController = UIHostingController(
            rootView: ProgressSkillEvidenceMotionHarness(
                driver: ProgressSkillEvidenceMotionDriver(reduceMotion: true),
                store: store,
                referenceDate: referenceDate,
                request: ProgressSkillEvidenceRequest(
                    currentNextFocusFor: sourceGoalID
                ),
                resolution: { _, resolution in
                    recorder.record(resolution)
                    guard resolution == .unavailable else { return }
                    _ = store.returnMembershipActivationResumeToReceipt()
                }
            )
        )
        let window = UIWindow(frame: frame)
        defer { window.isHidden = true }
        window.rootViewController = hostingController
        window.isHidden = false
        hostingController.view.frame = frame
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))

        XCTAssertEqual(recorder.events, [.unavailable])
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .activationReady)
        XCTAssertTrue(store.hasDeferredMembershipActivationPresentation)
        let fallbackPresentation = try XCTUnwrap(
            store.membershipActivationPresentationIfVerified(
                fallbackContext: .overview,
                fallbackSource: .entitlementRefresh
            )
        )
        XCTAssertNil(fallbackPresentation.continuation)
        XCTAssertEqual(fallbackPresentation.actionTitle, "Done")
        XCTAssertEqual(
            fallbackPresentation.detail,
            "Your answer history can now guide one clear Next Focus."
        )
    }

    @MainActor
    func testMembershipNextFocusHandoffRevealsAwaitingAndCaughtUpStates() throws {
        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )

        for isCaughtUp in [false, true] {
            let scenarioName = isCaughtUp ? "caught-up" : "awaiting"
            let suiteName =
                "ProgressDashboardRenderingTests.NextFocus.\(scenarioName).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = makeReviewedStore(
                defaults: defaults,
                referenceDate: referenceDate
            )
            let goal = try XCTUnwrap(store.goal)
            let skill = try XCTUnwrap(goal.derivedSkillMap?.topics.first)
            store.questions = isCaughtUp
                ? [
                    makeQuestion(
                        goal: goal,
                        index: 1,
                        topic: skill.name,
                        skillID: skill.id,
                        status: .correct,
                        timesAsked: 1,
                        timesCorrect: 1,
                        nextReviewAt: .distantFuture
                    )
                ]
                : []
            let continuation = MembershipActivationContinuation.revealNextFocus(
                sourceGoalID: goal.id
            )
            store.requestMembership(
                for: .adaptiveStudyAssist,
                continuation: continuation
            )
            store.reconcileMembershipEntitlement(isUnlocked: true)
            XCTAssertEqual(
                store.studyFocusState,
                isCaughtUp ? .caughtUp : .awaitingQuestion,
                scenarioName
            )
            XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
            XCTAssertEqual(
                store.claimMembershipActivationContinuationForResume(),
                continuation,
                scenarioName
            )

            let recorder = ProgressSkillEvidenceResolutionRecorder()
            let frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let hostingController = UIHostingController(
                rootView: ProgressSkillEvidenceMotionHarness(
                    driver: ProgressSkillEvidenceMotionDriver(reduceMotion: true),
                    store: store,
                    referenceDate: referenceDate,
                    request: ProgressSkillEvidenceRequest(
                        currentNextFocusFor: goal.id
                    ),
                    resolution: { request, resolution in
                        recorder.record(resolution)
                        guard resolution == .revealed else { return }
                        _ = store.completeResumedMembershipNextFocusReveal(
                            for: request.goalID
                        )
                    }
                )
            )
            let window = UIWindow(frame: frame)
            window.rootViewController = hostingController
            window.isHidden = false
            hostingController.view.frame = frame
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))

            XCTAssertEqual(recorder.events, [.revealed], scenarioName)
            XCTAssertNil(store.membershipActivationHandoff, scenarioName)
            window.isHidden = true
        }
    }

    @MainActor
    func testMembershipNextFocusHandoffRetriesAfterSameGoalPreparationFinishes() throws {
        let suiteName = "ProgressDashboardRenderingTests.NextFocusPreparation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let store = makeReviewedStore(defaults: defaults, referenceDate: referenceDate)
        let goal = try XCTUnwrap(store.goal)
        let skill = try XCTUnwrap(goal.derivedSkillMap?.topics.first)
        let continuation = MembershipActivationContinuation.revealNextFocus(
            sourceGoalID: goal.id
        )
        store.membershipTier = .starter
        store.requestMembership(
            for: .adaptiveStudyAssist,
            continuation: continuation
        )
        store.reconcileMembershipEntitlement(isUnlocked: true)
        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        XCTAssertEqual(
            store.claimMembershipActivationContinuationForResume(),
            continuation
        )
        store.questions = []
        store.questionBatchState = .generating
        XCTAssertNil(store.studyFocusState)

        let recorder = ProgressSkillEvidenceResolutionRecorder()
        let frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let hostingController = UIHostingController(
            rootView: ProgressSkillEvidenceMotionHarness(
                driver: ProgressSkillEvidenceMotionDriver(reduceMotion: true),
                store: store,
                referenceDate: referenceDate,
                request: ProgressSkillEvidenceRequest(currentNextFocusFor: goal.id),
                resolution: { request, resolution in
                    recorder.record(resolution)
                    guard resolution == .revealed else { return }
                    _ = store.completeResumedMembershipNextFocusReveal(
                        for: request.goalID
                    )
                }
            )
        )
        let window = UIWindow(frame: frame)
        defer { window.isHidden = true }
        window.rootViewController = hostingController
        window.isHidden = false
        hostingController.view.frame = frame
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .resumeRequested)

        store.questions = [
            makeQuestion(
                goal: goal,
                index: 99,
                topic: skill.name,
                skillID: skill.id,
                status: .incorrect
            )
        ]
        store.questionBatchState = .ready
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))

        XCTAssertEqual(recorder.events, [.revealed])
        XCTAssertNil(store.membershipActivationHandoff)
    }

    @MainActor
    func testMembershipNextFocusHandoffReturnsToReceiptForPermanentFailure() throws {
        let suiteName = "ProgressDashboardRenderingTests.NextFocusFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let store = makeReviewedStore(defaults: defaults, referenceDate: referenceDate)
        let goalID = try XCTUnwrap(store.goal?.id)
        let continuation = MembershipActivationContinuation.revealNextFocus(
            sourceGoalID: goalID
        )
        store.membershipTier = .starter
        store.requestMembership(
            for: .adaptiveStudyAssist,
            continuation: continuation
        )
        store.reconcileMembershipEntitlement(isUnlocked: true)
        XCTAssertEqual(store.requestMembershipActivationResume(), .requested)
        XCTAssertEqual(
            store.claimMembershipActivationContinuationForResume(),
            continuation
        )
        store.questions = []
        store.questionBatchState = .generating
        XCTAssertNil(store.studyFocusState)

        let recorder = ProgressSkillEvidenceResolutionRecorder()
        let frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let hostingController = UIHostingController(
            rootView: ProgressSkillEvidenceMotionHarness(
                driver: ProgressSkillEvidenceMotionDriver(reduceMotion: true),
                store: store,
                referenceDate: referenceDate,
                request: ProgressSkillEvidenceRequest(currentNextFocusFor: goalID),
                resolution: { _, resolution in
                    recorder.record(resolution)
                    guard resolution == .unavailable else { return }
                    _ = store.returnMembershipActivationResumeToReceipt()
                }
            )
        )
        let window = UIWindow(frame: frame)
        defer { window.isHidden = true }
        window.rootViewController = hostingController
        window.isHidden = false
        hostingController.view.frame = frame
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .resumeRequested)

        store.questionBatchState = .failed
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

        XCTAssertEqual(recorder.events, [.unavailable])
        XCTAssertEqual(store.membershipActivationHandoff?.phase, .activationReady)
        XCTAssertTrue(store.hasDeferredMembershipActivationPresentation)
        let fallbackPresentation = try XCTUnwrap(
            store.membershipActivationPresentationIfVerified(
                fallbackContext: .overview,
                fallbackSource: .entitlementRefresh
            )
        )
        XCTAssertNil(fallbackPresentation.continuation)
        XCTAssertEqual(fallbackPresentation.actionTitle, "Done")
        XCTAssertEqual(
            fallbackPresentation.detail,
            "Your answer history can now guide one clear Next Focus."
        )
    }

    @MainActor
    func testMeanPixelDifferenceReadsOnlyRequestedRegion() {
        let size = CGSize(width: 20, height: 20)
        let bounds = CGRect(origin: .zero, size: size)
        let targetRegion = CGRect(x: 15, y: 0, width: 5, height: 20)
        let rendererFormat = UIGraphicsImageRendererFormat.preferred()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)

        func image(changedRegion: CGRect? = nil) -> UIImage {
            renderer.image { context in
                context.cgContext.setFillColor(UIColor.black.cgColor)
                context.cgContext.fill(bounds)
                if let changedRegion {
                    context.cgContext.setFillColor(UIColor.red.cgColor)
                    context.cgContext.fill(changedRegion)
                }
            }
        }

        let baseline = image()
        let changedOutsideTarget = image(
            changedRegion: CGRect(x: 0, y: 0, width: 5, height: 20)
        )
        let changedInsideTarget = image(changedRegion: targetRegion)

        XCTAssertGreaterThan(
            meanPixelDifference(baseline, changedOutsideTarget),
            0.05,
            "The fixture must contain a material full-frame difference."
        )
        XCTAssertEqual(
            meanPixelDifference(baseline, changedOutsideTarget, region: targetRegion),
            0,
            accuracy: 0.000_001,
            "Changes outside the requested region must not affect its comparison."
        )
        XCTAssertGreaterThan(
            meanPixelDifference(baseline, changedInsideTarget, region: targetRegion),
            0.2,
            "Changes inside the requested region must remain visible."
        )
    }

    @MainActor
    func testMomentumPresentationUsesLearningFirstHierarchyAndExcludesFutureDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: referenceDate))
        let days = try (0..<7).map { offset -> WeeklyPracticeDay in
            let date = try XCTUnwrap(
                calendar.date(byAdding: .day, value: offset, to: week.start)
            )
            switch offset {
            case 0:
                return WeeklyPracticeDay(
                    date: date,
                    questionsAnswered: 4,
                    correctAnswers: 3,
                    checkpointsCleared: 1,
                    earnedBreakMinutes: 30
                )
            case 2:
                return WeeklyPracticeDay(
                    date: date,
                    questionsAnswered: 5,
                    correctAnswers: 3,
                    checkpointsCleared: 1,
                    earnedBreakMinutes: 20
                )
            case 4:
                return WeeklyPracticeDay(
                    date: date,
                    questionsAnswered: 99,
                    correctAnswers: 99
                )
            default:
                return WeeklyPracticeDay(date: date, questionsAnswered: 0)
            }
        }
        let metrics = WeeklyMetricsSummary(
            id: Goal.ID().uuidString,
            title: "Lead a production architecture review",
            questionsAnswered: 9,
            correctAnswers: 6,
            missedAnswers: 3,
            checkpointStreakDays: 2,
            checkpointsCleared: 2,
            strongestSkill: nil,
            reviewSkill: nil,
            isCurrentGoal: true
        )
        let details = WeeklyImpactDetails(
            practiceDays: days,
            earnedBreakMinutes: 50,
            recoveredQuestions: 1,
            activePracticeDays: 2,
            previousWeekQuestions: 4
        )

        let presentation = ProgressMomentumPresentation(
            metrics: metrics,
            details: details,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertEqual(presentation.state, .learning)
        XCTAssertTrue(presentation.hasActivity)
        XCTAssertEqual(presentation.primaryMetric?.kind, .questionsAnswered)
        XCTAssertEqual(presentation.primaryMetric?.valueText, "9")
        XCTAssertEqual(presentation.primaryMetric?.labelText, "QUESTIONS ANSWERED")
        XCTAssertEqual(
            presentation.supportingMetrics.map(\.kind),
            [.accuracy, .recoveredMisses, .checkpointsCleared]
        )
        XCTAssertEqual(
            presentation.supportingMetrics.map(\.valueText),
            ["66%", "1", "2"]
        )
        XCTAssertEqual(presentation.streakBadgeText, "2d current streak")
        XCTAssertEqual(
            presentation.trendText,
            "5 more questions than this point last week"
        )
        XCTAssertEqual(
            presentation.summaryText,
            "9 questions answered · 2 checkpoints cleared"
        )
        XCTAssertEqual(
            presentation.footerText,
            "Break access · 50m granted · 5 more questions than this point last week"
        )
        XCTAssertEqual(presentation.breakAccessText, "Break access · 50m granted")
        XCTAssertEqual(
            presentation.accessibilityValue,
            "9 questions answered this week. "
                + "66 percent accuracy, 6 of 9 correct. "
                + "1 previously missed question currently correct. "
                + "2 checkpoints cleared this week. "
                + "50 minutes of break access granted this week. "
                + "2-day checkpoint streak. "
                + "5 more questions than this point last week. "
                + "Activity by day: Monday, 4 questions, "
                + "1 checkpoint cleared, 30 minutes of break access granted; "
                + "Wednesday, 5 questions, 1 checkpoint cleared, "
                + "20 minutes of break access granted."
        )
        XCTAssertEqual(
            presentation.days.map(\.state),
            [.active, .inactive, .active, .inactive, .future, .future, .future]
        )
        XCTAssertEqual(presentation.days[0].activityLevel, 1, accuracy: 0.001)
        XCTAssertEqual(presentation.days[2].activityLevel, 1, accuracy: 0.001)
        XCTAssertEqual(presentation.days[4].activityLevel, 0, accuracy: 0.001)
    }

    @MainActor
    func testMomentumEmptyBreakOnlyRoutingAndMotionPoliciesStayTruthful() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: referenceDate))
        let days = try (0..<7).map { offset in
            WeeklyPracticeDay(
                date: try XCTUnwrap(
                    calendar.date(byAdding: .day, value: offset, to: week.start)
                ),
                questionsAnswered: 0
            )
        }
        let goalID = Goal.ID()
        let metrics = WeeklyMetricsSummary(
            id: goalID.uuidString,
            title: "Reach conversational Spanish",
            questionsAnswered: 0,
            correctAnswers: 0,
            missedAnswers: 0,
            checkpointStreakDays: 0,
            checkpointsCleared: 0,
            strongestSkill: nil,
            reviewSkill: nil,
            isCurrentGoal: true
        )
        let presentation = ProgressMomentumPresentation(
            metrics: metrics,
            details: WeeklyImpactDetails(
                practiceDays: days,
                earnedBreakMinutes: 0,
                recoveredQuestions: 0,
                activePracticeDays: 0,
                previousWeekQuestions: 5
            ),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertFalse(presentation.hasActivity)
        XCTAssertEqual(presentation.state, .empty)
        XCTAssertNil(presentation.primaryMetric)
        XCTAssertTrue(presentation.supportingMetrics.isEmpty)
        XCTAssertNil(presentation.streakBadgeText)
        XCTAssertNil(presentation.trendText)
        XCTAssertEqual(
            presentation.summaryText,
            "Your next checkpoint starts this week’s momentum."
        )
        XCTAssertEqual(
            presentation.accessibilityValue,
            "No checkpoint activity this week. Your next checkpoint starts this week’s momentum."
        )

        var orphanedBreakDays = days
        orphanedBreakDays[0].earnedBreakMinutes = 15
        let orphanedBreakPresentation = ProgressMomentumPresentation(
            metrics: metrics,
            details: WeeklyImpactDetails(
                practiceDays: orphanedBreakDays,
                earnedBreakMinutes: 15,
                recoveredQuestions: 0,
                activePracticeDays: 0,
                previousWeekQuestions: 0
            ),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )
        XCTAssertEqual(orphanedBreakPresentation.state, .empty)
        XCTAssertFalse(orphanedBreakPresentation.hasActivity)
        XCTAssertNil(orphanedBreakPresentation.primaryMetric)
        XCTAssertNil(orphanedBreakPresentation.streakBadgeText)
        XCTAssertEqual(orphanedBreakPresentation.days[0].state, .inactive)
        XCTAssertEqual(
            orphanedBreakPresentation.accessibilityValue,
            "No checkpoint activity this week. Your next checkpoint starts this week’s momentum."
        )

        var breakOnlyDays = days
        breakOnlyDays[0].checkpointsCleared = 1
        breakOnlyDays[0].earnedBreakMinutes = 15
        var breakOnlyMetrics = metrics
        breakOnlyMetrics.checkpointStreakDays = 1
        breakOnlyMetrics.checkpointsCleared = 1
        let breakOnlyPresentation = ProgressMomentumPresentation(
            metrics: breakOnlyMetrics,
            details: WeeklyImpactDetails(
                practiceDays: breakOnlyDays,
                earnedBreakMinutes: 15,
                recoveredQuestions: 0,
                activePracticeDays: 0,
                previousWeekQuestions: 0
            ),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )
        XCTAssertEqual(breakOnlyPresentation.state, .checkpointOnly)
        XCTAssertTrue(breakOnlyPresentation.hasActivity)
        XCTAssertEqual(breakOnlyPresentation.primaryMetric?.kind, .checkpointsCleared)
        XCTAssertEqual(breakOnlyPresentation.primaryMetric?.valueText, "1")
        XCTAssertTrue(breakOnlyPresentation.supportingMetrics.isEmpty)
        XCTAssertNil(
            breakOnlyPresentation.streakBadgeText,
            "A one-day value should not be promoted as a current streak"
        )
        XCTAssertEqual(breakOnlyPresentation.summaryText, "1 checkpoint cleared this week")
        XCTAssertEqual(breakOnlyPresentation.footerText, "Break access · 15m granted")
        XCTAssertEqual(
            breakOnlyPresentation.accessibilityValue,
            "1 checkpoint cleared this week. "
                + "15 minutes of break access granted this week. "
                + "Activity by day: Monday, 1 checkpoint cleared, "
                + "15 minutes of break access granted."
        )
        XCTAssertEqual(
            breakOnlyPresentation.days[0].activityLevel,
            1,
            accuracy: 0.001
        )

        let standard = ProgressMomentumMotionPolicy(reduceMotion: false)
        XCTAssertEqual(standard.style, .animated)
        XCTAssertNotNil(standard.updateAnimation)
        XCTAssertNotNil(standard.revealAnimation(dayIndex: 0))
        XCTAssertNotNil(standard.revealAnimation(dayIndex: 99))
        XCTAssertEqual(standard.revealDelay(dayIndex: -1), 0, accuracy: 0.001)
        XCTAssertEqual(standard.revealDelay(dayIndex: 2), 0.09, accuracy: 0.001)
        XCTAssertEqual(standard.revealDelay(dayIndex: 99), 0.27, accuracy: 0.001)
        let reduced = ProgressMomentumMotionPolicy(reduceMotion: true)
        XCTAssertEqual(reduced.style, .identity)
        XCTAssertNil(reduced.updateAnimation)
        XCTAssertNil(reduced.revealAnimation(dayIndex: 0))

        XCTAssertEqual(
            ProgressWeeklyImpactRoutingPolicy.destinationGoalID(
                activeGoalID: goalID,
                hasReviewedSkillMap: true
            ),
            goalID
        )
        XCTAssertNil(
            ProgressWeeklyImpactRoutingPolicy.destinationGoalID(
                activeGoalID: goalID,
                hasReviewedSkillMap: false
            )
        )
        XCTAssertNil(
            ProgressWeeklyImpactRoutingPolicy.destinationGoalID(
                activeGoalID: nil,
                hasReviewedSkillMap: true
            )
        )
    }

    @MainActor
    func testMomentumPresentationTreatsCarriedStreakAsEmptyAtMondayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let sunday = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2027, month: 1, day: 3, hour: 12)
            )
        )
        let mondayMorning = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2027, month: 1, day: 4, hour: 9)
            )
        )
        let mondayNoon = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2027, month: 1, day: 4, hour: 12)
            )
        )
        let goal = Goal(
            title: "Monday study plan",
            deadline: try XCTUnwrap(
                calendar.date(from: DateComponents(year: 2027, month: 2, day: 1))
            ),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "weekly boundaries",
            preferredQuestionStyle: .multipleChoice
        )
        let sundayClear = UnlockEvent(
            goalID: goal.id,
            minutes: 10,
            createdAt: sunday
        )
        let carriedCalculator = WeeklyMetricsCalculator(
            attempts: [],
            unlockEvents: [sundayClear],
            asOf: mondayNoon,
            calendar: calendar
        )
        let carriedSummary = carriedCalculator.summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true,
            skillCompetencies: []
        )
        let carriedPresentation = ProgressMomentumPresentation(
            metrics: carriedSummary,
            details: carriedCalculator.impactDetails(goalID: goal.id),
            referenceDate: mondayNoon,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertEqual(calendar.component(.weekday, from: mondayNoon), 2)
        XCTAssertEqual(carriedSummary.questionsAnswered, 0)
        XCTAssertEqual(carriedSummary.checkpointsCleared, 0)
        XCTAssertEqual(carriedSummary.checkpointStreakDays, 1)
        XCTAssertTrue(carriedSummary.hasWeeklyReviewActivity)
        XCTAssertEqual(carriedPresentation.state, .empty)
        XCTAssertFalse(carriedPresentation.hasActivity)
        XCTAssertNil(carriedPresentation.primaryMetric)
        XCTAssertNil(carriedPresentation.streakBadgeText)
        XCTAssertEqual(
            carriedPresentation.days.map(\.state),
            [.inactive, .future, .future, .future, .future, .future, .future]
        )
        XCTAssertEqual(
            carriedPresentation.accessibilityValue,
            "No checkpoint activity this week. Your next checkpoint starts this week’s momentum."
        )

        let mondayClear = UnlockEvent(
            goalID: goal.id,
            minutes: 15,
            createdAt: mondayMorning
        )
        let activeCalculator = WeeklyMetricsCalculator(
            attempts: [],
            unlockEvents: [sundayClear, mondayClear],
            asOf: mondayNoon,
            calendar: calendar
        )
        let activeSummary = activeCalculator.summary(
            id: goal.id.uuidString,
            title: goal.title,
            goalID: goal.id,
            isCurrentGoal: true,
            skillCompetencies: []
        )
        let activePresentation = ProgressMomentumPresentation(
            metrics: activeSummary,
            details: activeCalculator.impactDetails(goalID: goal.id),
            referenceDate: mondayNoon,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertEqual(activeSummary.checkpointsCleared, 1)
        XCTAssertEqual(activeSummary.checkpointStreakDays, 2)
        XCTAssertEqual(activePresentation.state, .checkpointOnly)
        XCTAssertEqual(activePresentation.primaryMetric?.kind, .checkpointsCleared)
        XCTAssertEqual(activePresentation.primaryMetric?.valueText, "1")
        XCTAssertEqual(activePresentation.footerText, "Break access · 15m granted")
        XCTAssertEqual(activePresentation.streakBadgeText, "2d current streak")
        XCTAssertEqual(
            activePresentation.accessibilityValue,
            "1 checkpoint cleared this week. "
                + "15 minutes of break access granted this week. "
                + "2-day checkpoint streak. "
                + "Activity by day: Monday, 1 checkpoint cleared, "
                + "15 minutes of break access granted."
        )
    }

    @MainActor
    func testMomentumRailCancelsRevealWhenReduceMotionChangesWhileMounted() {
        let startDate = Date(timeIntervalSince1970: 1_788_124_800)
        let days = (0..<7).map { offset in
            ProgressWeeklyImpactDayPresentation(
                id: startDate.addingTimeInterval(Double(offset) * 86_400),
                label: "D\(offset + 1)",
                state: .active,
                activityLevel: 1
            )
        }
        let driver = ProgressMomentumRailMotionDriver(
            revealID: ProgressMomentumRevealID(
                goalID: "goal-one",
                weekStart: startDate
            )
        )
        var reportedStyles: [ProgressMomentumMotionStyle] = []
        let hostingController = UIHostingController(
            rootView: ProgressMomentumRailMotionHarness(
                driver: driver,
                days: days,
                report: { reportedStyles.append($0) }
            )
            .preferredColorScheme(.dark)
        )
        let frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        let window = UIWindow(frame: frame)
        defer { window.isHidden = true }
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = hostingController
        window.isHidden = false
        hostingController.view.frame = frame
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))

        XCTAssertEqual(reportedStyles.last, .animated)
        let initialAppearanceCount = reportedStyles.count
        let inFlightImage = mountedViewImage(
            of: hostingController.view,
            size: frame.size
        )
        let reducedBaselineDriver = ProgressMomentumRailMotionDriver(
            reduceMotion: true,
            revealID: driver.revealID
        )
        let reducedBaselineImage = HostedViewRenderer.image(
            for: ProgressMomentumRailMotionHarness(
                driver: reducedBaselineDriver,
                days: days,
                report: { _ in }
            ),
            width: frame.width,
            height: frame.height,
            colorScheme: .dark,
            settlingTime: 0.05,
            renderScale: 1
        )
        XCTAssertGreaterThan(
            meanPixelDifference(inFlightImage, reducedBaselineImage),
            0.002,
            "The test must intercept a visibly incomplete reveal."
        )

        driver.reduceMotion = true
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))

        XCTAssertEqual(reportedStyles.last, .identity)
        XCTAssertGreaterThan(reportedStyles.count, initialAppearanceCount)
        let suppressedAppearanceCount = reportedStyles.count
        let snappedImage = mountedViewImage(
            of: hostingController.view,
            size: frame.size
        )
        XCTAssertLessThan(
            meanPixelDifference(snappedImage, reducedBaselineImage),
            0.002,
            "Enabling Reduce Motion must snap every bar to its final height."
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.7))
        let settledImage = mountedViewImage(
            of: hostingController.view,
            size: frame.size
        )
        XCTAssertLessThan(
            meanPixelDifference(settledImage, reducedBaselineImage),
            0.002,
            "No delayed reveal animator may survive motion suppression."
        )

        driver.reduceMotion = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))

        XCTAssertEqual(
            reportedStyles.count,
            suppressedAppearanceCount,
            "Disabling Reduce Motion must not replay the reveal in the same scope."
        )
        let restoredPreferenceImage = mountedViewImage(
            of: hostingController.view,
            size: frame.size
        )
        XCTAssertLessThan(
            meanPixelDifference(restoredPreferenceImage, reducedBaselineImage),
            0.002,
            "Disabling Reduce Motion must leave the completed rail in place."
        )

        driver.revealID = ProgressMomentumRevealID(
            goalID: "goal-two",
            weekStart: startDate
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))

        XCTAssertEqual(reportedStyles.last, .animated)
        XCTAssertGreaterThan(reportedStyles.count, suppressedAppearanceCount)
        let newScopeImage = mountedViewImage(
            of: hostingController.view,
            size: frame.size
        )
        XCTAssertGreaterThan(
            meanPixelDifference(newScopeImage, reducedBaselineImage),
            0.002,
            "A new goal or week may reveal once when Reduce Motion is off."
        )
    }

    @MainActor
    private func mountedViewImage(of view: UIView, size: CGSize) -> UIImage {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            XCTAssertTrue(
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true),
                "Failed to render the mounted view."
            )
        }
    }

    private func meanPixelDifference(
        _ first: UIImage,
        _ second: UIImage,
        region: CGRect? = nil
    ) -> Double {
        guard let firstImage = first.cgImage,
              let secondImage = second.cgImage else {
            XCTFail("Mounted snapshots must expose CGImages.")
            return 1
        }

        guard let firstData = packedPixelData(from: firstImage, region: region),
              let secondData = packedPixelData(from: secondImage, region: region),
              firstData.count == secondData.count,
              !firstData.isEmpty else {
            XCTFail("Mounted snapshots must have matching pixel buffers.")
            return 1
        }

        let totalDifference = zip(firstData, secondData).reduce(0.0) { result, pair in
            result + abs(Double(pair.0) - Double(pair.1))
        }
        return totalDifference / Double(firstData.count) / 255
    }

    private func packedPixelData(from image: CGImage, region: CGRect?) -> Data? {
        let requestedBounds = (region ?? CGRect(x: 0, y: 0, width: image.width, height: image.height))
            .standardized
        let minX = max(0, Int(floor(requestedBounds.minX)))
        let minY = max(0, Int(floor(requestedBounds.minY)))
        let maxX = min(image.width, Int(ceil(requestedBounds.maxX)))
        let maxY = min(image.height, Int(ceil(requestedBounds.maxY)))
        let width = maxX - minX
        let height = maxY - minY
        guard width > 0,
              height > 0,
              let croppedImage = image.cropping(
                  to: CGRect(x: minX, y: minY, width: width, height: height)
              ) else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var comparisonData = Data(count: bytesPerRow * height)
        let rendered = comparisonData.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                          | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else {
                return false
            }

            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? comparisonData : nil
    }

    @MainActor
    func testMomentumPresentationTreatsCarriedStreakAsEmptyAndPreservesWeeklyStates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: referenceDate))
        var days = try (0..<7).map { offset in
            WeeklyPracticeDay(
                date: try XCTUnwrap(
                    calendar.date(byAdding: .day, value: offset, to: week.start)
                ),
                questionsAnswered: 0
            )
        }
        days[0].questionsAnswered = 2
        days[0].correctAnswers = 1
        days[1].questionsAnswered = 1

        let goalID = Goal.ID()
        let practiceMetrics = WeeklyMetricsSummary(
            id: goalID.uuidString,
            title: "Reach conversational Spanish",
            questionsAnswered: 3,
            correctAnswers: 1,
            missedAnswers: 2,
            checkpointStreakDays: 0,
            checkpointsCleared: 0,
            strongestSkill: nil,
            reviewSkill: nil,
            isCurrentGoal: true
        )
        let practiceDetails = WeeklyImpactDetails(
            practiceDays: days,
            earnedBreakMinutes: 0,
            recoveredQuestions: 1,
            activePracticeDays: 2,
            previousWeekQuestions: 3
        )
        let practicePresentation = ProgressMomentumPresentation(
            metrics: practiceMetrics,
            details: practiceDetails,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertEqual(practicePresentation.state, .learning)
        XCTAssertEqual(practicePresentation.primaryMetric?.kind, .questionsAnswered)
        XCTAssertEqual(practicePresentation.primaryMetric?.valueText, "3")
        XCTAssertEqual(
            practicePresentation.supportingMetrics.map(\.kind),
            [.accuracy, .recoveredMisses, .practiceDays]
        )
        XCTAssertEqual(
            practicePresentation.supportingMetrics.map(\.valueText),
            ["33%", "1", "2"]
        )
        XCTAssertEqual(
            practicePresentation.trendText,
            "Level with this point last week"
        )
        XCTAssertNil(practicePresentation.breakAccessText)
        XCTAssertEqual(
            practicePresentation.summaryText,
            "3 questions answered this week"
        )
        XCTAssertEqual(practicePresentation.footerText, "Level with this point last week")
        XCTAssertEqual(
            practicePresentation.accessibilityValue,
            "3 questions answered this week. "
                + "33 percent accuracy, 1 of 3 correct. "
                + "1 previously missed question currently correct. "
                + "2 practice days this week. "
                + "Level with this point last week. "
                + "Activity by day: Monday, 2 questions; Tuesday, 1 question."
        )

        var streakMetrics = practiceMetrics
        streakMetrics.questionsAnswered = 0
        streakMetrics.correctAnswers = 0
        streakMetrics.missedAnswers = 0
        streakMetrics.checkpointStreakDays = 4
        let quietDays = days.map {
            WeeklyPracticeDay(date: $0.date, questionsAnswered: 0)
        }
        let carriedStreakPresentation = ProgressMomentumPresentation(
            metrics: streakMetrics,
            details: WeeklyImpactDetails(
                practiceDays: quietDays,
                earnedBreakMinutes: 0,
                recoveredQuestions: 0,
                activePracticeDays: 0,
                previousWeekQuestions: 5
            ),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertEqual(carriedStreakPresentation.state, .empty)
        XCTAssertFalse(carriedStreakPresentation.hasActivity)
        XCTAssertNil(carriedStreakPresentation.primaryMetric)
        XCTAssertTrue(carriedStreakPresentation.supportingMetrics.isEmpty)
        XCTAssertNil(carriedStreakPresentation.streakBadgeText)
        XCTAssertNil(carriedStreakPresentation.trendText)
        XCTAssertEqual(
            carriedStreakPresentation.summaryText,
            "Your next checkpoint starts this week’s momentum."
        )
        XCTAssertEqual(
            carriedStreakPresentation.accessibilityValue,
            "No checkpoint activity this week. Your next checkpoint starts this week’s momentum."
        )

        var legacyClearMetrics = streakMetrics
        legacyClearMetrics.checkpointStreakDays = 0
        legacyClearMetrics.checkpointsCleared = 1
        var legacyClearDays = quietDays
        legacyClearDays[0].checkpointsCleared = 1
        let legacyClearPresentation = ProgressMomentumPresentation(
            metrics: legacyClearMetrics,
            details: WeeklyImpactDetails(
                practiceDays: legacyClearDays,
                earnedBreakMinutes: 0,
                recoveredQuestions: 0,
                activePracticeDays: 0,
                previousWeekQuestions: 0
            ),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )

        XCTAssertEqual(legacyClearPresentation.state, .checkpointOnly)
        XCTAssertEqual(
            legacyClearPresentation.primaryMetric?.kind,
            .checkpointsCleared
        )
        XCTAssertEqual(legacyClearPresentation.primaryMetric?.valueText, "1")
        XCTAssertTrue(legacyClearPresentation.supportingMetrics.isEmpty)
        XCTAssertNil(legacyClearPresentation.breakAccessText)
        XCTAssertEqual(
            legacyClearPresentation.footerText,
            "1 checkpoint cleared this week"
        )
        XCTAssertEqual(
            legacyClearPresentation.accessibilityValue,
            "1 checkpoint cleared this week. "
                + "Activity by day: Monday, 1 checkpoint cleared."
        )

        var updatedMetrics = practiceMetrics
        updatedMetrics.questionsAnswered = 4
        let sameWeekUpdate = ProgressMomentumPresentation(
            metrics: updatedMetrics,
            details: practiceDetails,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )
        XCTAssertEqual(sameWeekUpdate.revealID, practicePresentation.revealID)

        updatedMetrics.id = Goal.ID().uuidString
        let otherGoal = ProgressMomentumPresentation(
            metrics: updatedMetrics,
            details: practiceDetails,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )
        XCTAssertNotEqual(otherGoal.revealID, practicePresentation.revealID)

        let nextWeekReferenceDate = try XCTUnwrap(
            calendar.date(byAdding: .weekOfYear, value: 1, to: referenceDate)
        )
        var nextWeekDetails = practiceDetails
        nextWeekDetails.practiceDays = try practiceDetails.practiceDays.map { day in
            var shiftedDay = day
            shiftedDay.date = try XCTUnwrap(
                calendar.date(byAdding: .weekOfYear, value: 1, to: day.date)
            )
            return shiftedDay
        }
        let nextWeek = ProgressMomentumPresentation(
            metrics: practiceMetrics,
            details: nextWeekDetails,
            referenceDate: nextWeekReferenceDate,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: calendar.timeZone
        )
        XCTAssertNotEqual(nextWeek.revealID, practicePresentation.revealID)
    }

    @MainActor
    func testMomentumCardRendersLearningCheckpointOnlyAndEmptyStates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let referenceDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let week = try XCTUnwrap(
            calendar.dateInterval(of: .weekOfYear, for: referenceDate)
        )

        func presentation(
            questions: Int,
            correct: Int,
            clears: Int,
            minutes: Int,
            recovered: Int = 0,
            previousWeekQuestions: Int = 0
        ) throws -> ProgressMomentumPresentation {
            let practiceDays = try (0..<7).map { offset -> WeeklyPracticeDay in
                let date = try XCTUnwrap(
                    calendar.date(byAdding: .day, value: offset, to: week.start)
                )
                guard offset == 0 else {
                    return WeeklyPracticeDay(date: date, questionsAnswered: 0)
                }
                return WeeklyPracticeDay(
                    date: date,
                    questionsAnswered: questions,
                    correctAnswers: correct,
                    checkpointsCleared: clears,
                    earnedBreakMinutes: minutes
                )
            }
            return ProgressMomentumPresentation(
                metrics: WeeklyMetricsSummary(
                    id: Goal.ID().uuidString,
                    title: "Lead a production architecture review",
                    questionsAnswered: questions,
                    correctAnswers: correct,
                    missedAnswers: max(0, questions - correct),
                    checkpointStreakDays: clears > 0 ? 1 : 0,
                    checkpointsCleared: clears,
                    strongestSkill: nil,
                    reviewSkill: nil,
                    isCurrentGoal: true
                ),
                details: WeeklyImpactDetails(
                    practiceDays: practiceDays,
                    earnedBreakMinutes: minutes,
                    recoveredQuestions: recovered,
                    activePracticeDays: questions > 0 ? 1 : 0,
                    previousWeekQuestions: previousWeekQuestions
                ),
                referenceDate: referenceDate,
                calendar: calendar,
                locale: Locale(identifier: "en_US"),
                timeZone: calendar.timeZone
            )
        }

        let fixtures = [
            ProgressDashboardRenderFixture(
                name: "progress-momentum-learning-with-access-light",
                width: 393,
                height: 390,
                colorScheme: .light,
                dynamicTypeSize: .large,
                settlingTime: 0.35,
                content: AnyView(
                    ProgressMomentumCardAuditView(
                        presentation: try presentation(
                            questions: 9,
                            correct: 7,
                            clears: 2,
                            minutes: 50,
                            recovered: 1,
                            previousWeekQuestions: 4
                        )
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-momentum-learning-only-compact-dark",
                width: 320,
                height: 390,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    ProgressMomentumCardAuditView(
                        presentation: try presentation(
                            questions: 6,
                            correct: 5,
                            clears: 0,
                            minutes: 0,
                            recovered: 1,
                            previousWeekQuestions: 3
                        )
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-momentum-checkpoint-only-accessibility",
                width: 393,
                height: 540,
                colorScheme: .light,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    ProgressMomentumCardAuditView(
                        presentation: try presentation(
                            questions: 0,
                            correct: 0,
                            clears: 1,
                            minutes: 15
                        )
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-momentum-empty-accessibility5-dark",
                width: 320,
                height: 1_100,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    ProgressMomentumCardAuditView(
                        presentation: try presentation(
                            questions: 0,
                            correct: 0,
                            clears: 0,
                            minutes: 0
                        )
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
                colorScheme: fixture.colorScheme,
                settlingTime: fixture.settlingTime
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testReviewedDashboardKeepsMomentumInTheFirstFold() throws {
        let fixtures = [
            ProgressFirstFoldFixture(
                name: "progress-first-fold-compact",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                requiresFullyVisibleMomentum: true
            ),
            ProgressFirstFoldFixture(
                name: "progress-first-fold-accessibility5",
                width: 393,
                height: 852,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                requiresFullyVisibleMomentum: false
            ),
        ]
        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )

        for fixture in fixtures {
            let suiteName = "ProgressFirstFold.\(fixture.name).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = makeReviewedStore(
                defaults: defaults,
                referenceDate: referenceDate
            )
            let capture = ProgressLayoutCapture()
            let image = HostedViewRenderer.image(
                for: CompetencyView(
                    store: store,
                    reduceMotionOverride: true,
                    referenceDateOverride: referenceDate,
                    layoutReporter: { element, frame in
                        capture.frames[element] = frame
                    }
                )
                .environment(\.colorScheme, fixture.colorScheme)
                .environment(\.dynamicTypeSize, fixture.dynamicTypeSize),
                width: fixture.width,
                height: fixture.height,
                colorScheme: fixture.colorScheme,
                settlingTime: 0.15,
                renderScale: 1
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)

            let viewport = try XCTUnwrap(capture.frames[.viewport], fixture.name)
            let header = try XCTUnwrap(capture.frames[.header], fixture.name)
            let switcher = try XCTUnwrap(capture.frames[.goalSwitcher], fixture.name)
            let momentum = try XCTUnwrap(capture.frames[.momentum], fixture.name)
            let primaryOutcome = try XCTUnwrap(
                capture.frames[.momentumPrimaryOutcome],
                fixture.name
            )
            let nextFocus = try XCTUnwrap(capture.frames[.nextFocus], fixture.name)
            let semanticFrames = [
                header,
                switcher,
                momentum,
                primaryOutcome,
                nextFocus,
            ]

            XCTAssertGreaterThan(viewport.width, 0, fixture.name)
            XCTAssertGreaterThan(viewport.height, 0, fixture.name)
            for frame in semanticFrames {
                XCTAssertGreaterThan(frame.width, 0, fixture.name)
                XCTAssertGreaterThan(frame.height, 0, fixture.name)
                XCTAssertGreaterThanOrEqual(
                    frame.minX,
                    viewport.minX - 0.5,
                    fixture.name
                )
                XCTAssertLessThanOrEqual(
                    frame.maxX,
                    viewport.maxX + 0.5,
                    fixture.name
                )
            }

            XCTAssertGreaterThanOrEqual(switcher.height, 43.5, fixture.name)
            XCTAssertTrue(
                header.insetBy(dx: -0.5, dy: -0.5).contains(switcher),
                "\(fixture.name) switcher escaped the goal header"
            )
            XCTAssertLessThanOrEqual(header.maxY, momentum.minY + 0.5, fixture.name)
            XCTAssertLessThanOrEqual(momentum.maxY, nextFocus.minY + 0.5, fixture.name)
            XCTAssertTrue(
                momentum.insetBy(dx: -0.5, dy: -0.5).contains(primaryOutcome),
                "\(fixture.name) primary outcome escaped the Momentum card"
            )
            XCTAssertTrue(
                viewport.insetBy(dx: -0.5, dy: -0.5).contains(primaryOutcome),
                "\(fixture.name) hid the weekly value or its meaning below the first fold"
            )

            if fixture.requiresFullyVisibleMomentum {
                XCTAssertGreaterThanOrEqual(
                    momentum.minY,
                    viewport.minY - 0.5,
                    fixture.name
                )
                XCTAssertLessThanOrEqual(
                    momentum.maxY,
                    viewport.maxY + 0.5,
                    "\(fixture.name) pushed the weekly payoff below the first fold"
                )
            } else {
                let visibleMomentum = momentum.intersection(viewport)
                XCTAssertFalse(visibleMomentum.isNull, fixture.name)
                XCTAssertGreaterThanOrEqual(
                    visibleMomentum.height,
                    44,
                    "\(fixture.name) hid the primary weekly outcome at large text sizes"
                )
            }

            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testProgressDashboardRendersPrimaryStatesAcrossKeyLayouts() throws {
        let reviewedSuiteName = "ProgressDashboardRenderingTests.Reviewed.\(UUID().uuidString)"
        let reviewedEmptySuiteName = "ProgressDashboardRenderingTests.ReviewedEmpty.\(UUID().uuidString)"
        let repairSuiteName = "ProgressDashboardRenderingTests.Repair.\(UUID().uuidString)"
        let buildingSuiteName = "ProgressDashboardRenderingTests.Building.\(UUID().uuidString)"
        let suggestedSuiteName = "ProgressDashboardRenderingTests.Suggested.\(UUID().uuidString)"
        let failureSuiteName = "ProgressDashboardRenderingTests.Failure.\(UUID().uuidString)"
        let reviewedDefaults = try XCTUnwrap(UserDefaults(suiteName: reviewedSuiteName))
        let reviewedEmptyDefaults = try XCTUnwrap(UserDefaults(suiteName: reviewedEmptySuiteName))
        let repairDefaults = try XCTUnwrap(UserDefaults(suiteName: repairSuiteName))
        let buildingDefaults = try XCTUnwrap(UserDefaults(suiteName: buildingSuiteName))
        let suggestedDefaults = try XCTUnwrap(UserDefaults(suiteName: suggestedSuiteName))
        let failureDefaults = try XCTUnwrap(UserDefaults(suiteName: failureSuiteName))
        defer {
            reviewedDefaults.removePersistentDomain(forName: reviewedSuiteName)
            reviewedEmptyDefaults.removePersistentDomain(forName: reviewedEmptySuiteName)
            repairDefaults.removePersistentDomain(forName: repairSuiteName)
            buildingDefaults.removePersistentDomain(forName: buildingSuiteName)
            suggestedDefaults.removePersistentDomain(forName: suggestedSuiteName)
            failureDefaults.removePersistentDomain(forName: failureSuiteName)
        }

        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let reviewedStore = makeReviewedStore(
            defaults: reviewedDefaults,
            referenceDate: referenceDate
        )
        let reviewedEmptyStore = makeReviewedStore(
            defaults: reviewedEmptyDefaults,
            referenceDate: referenceDate,
            includesWeeklyActivity: false
        )
        let repairStore = makeRepairStore(defaults: repairDefaults)
        let buildingStore = makeBuildingStore(defaults: buildingDefaults)
        let suggestedStore = makeSuggestedStore(defaults: suggestedDefaults)
        let failureStore = makeFailureStore(defaults: failureDefaults)
        try assertReviewedFixtureContract(reviewedStore)
        let reviewedMetrics = try XCTUnwrap(
            reviewedStore.weeklyActiveGoalMetrics(
                asOf: referenceDate,
                calendar: .current
            )
        )
        let reviewedEmptyMetrics = try XCTUnwrap(
            reviewedEmptyStore.weeklyActiveGoalMetrics(
                asOf: referenceDate,
                calendar: .current
            )
        )
        XCTAssertEqual(reviewedMetrics.questionsAnswered, 6)
        XCTAssertEqual(reviewedMetrics.checkpointsCleared, 2)
        XCTAssertFalse(reviewedEmptyMetrics.hasWeeklyReviewActivity)
        XCTAssertTrue(repairStore.activeSkillMapNeedsAttention)
        XCTAssertEqual(repairStore.activeProgressCompetencies.count, 1)
        XCTAssertGreaterThan(
            repairStore.activeProgressCompetencies[0].attempts,
            0
        )
        XCTAssertNotNil(repairStore.activeProgressCompetencies[0].lastPracticedAt)
        XCTAssertEqual(repairStore.activeFocusWins.count, 1)
        XCTAssertTrue(buildingStore.isPreparingActiveGoalQuestions)
        XCTAssertEqual(buildingStore.activeFocusWins.count, 1)
        XCTAssertEqual(suggestedStore.activeDerivedSkillMap?.status, .suggested)
        XCTAssertTrue(suggestedStore.hasReadyCheckpointSet)
        XCTAssertTrue(failureStore.isQuestionGenerationBlockingPractice)
        XCTAssertEqual(failureStore.lastQuestionGenerationFailure, .qualityRejected)

        let fixtures = [
            ProgressDashboardRenderFixture(
                name: "progress-reviewed-mixed-light",
                width: 393,
                height: 2_000,
                colorScheme: .light,
                dynamicTypeSize: .large,
                settlingTime: 0.8,
                content: AnyView(
                    CompetencyView(
                        store: reviewedStore,
                        reduceMotionOverride: false,
                        referenceDateOverride: referenceDate
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-reviewed-mixed-dark",
                width: 393,
                height: 2_000,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                settlingTime: 0.8,
                content: AnyView(
                    CompetencyView(
                        store: reviewedStore,
                        reduceMotionOverride: false,
                        referenceDateOverride: referenceDate
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-reviewed-compact-viewport",
                width: 320,
                height: 568,
                colorScheme: .light,
                dynamicTypeSize: .large,
                settlingTime: 0.8,
                content: AnyView(
                    CompetencyView(
                        store: reviewedStore,
                        reduceMotionOverride: false,
                        referenceDateOverride: referenceDate
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-reviewed-accessibility-priority-reduced",
                width: 393,
                height: 2_500,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    CompetencyView(
                        store: reviewedStore,
                        reduceMotionOverride: true,
                        referenceDateOverride: referenceDate
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-reviewed-empty-week-light",
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(
                        store: reviewedEmptyStore,
                        reduceMotionOverride: false,
                        referenceDateOverride: referenceDate
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-skill-rows-accessibility2",
                width: 393,
                height: 2_500,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility2,
                content: AnyView(
                    ProgressSkillRowsAuditView(
                        competencies: reviewedStore.activeProgressCompetencies
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-repair-primary-order",
                width: 320,
                height: 1_100,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(store: repairStore, reduceMotionOverride: false)
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-building-primary-order",
                width: 393,
                height: 900,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(store: buildingStore, reduceMotionOverride: false)
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-suggested-map-priority",
                width: 393,
                height: 1_600,
                colorScheme: .light,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(store: suggestedStore, reduceMotionOverride: false)
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-generation-failure-priority-dark",
                width: 393,
                height: 1_100,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    CompetencyView(store: failureStore, reduceMotionOverride: false)
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
                colorScheme: fixture.colorScheme,
                settlingTime: fixture.settlingTime
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testNextFocusEvidenceHandoffRendersAcrossKeyLayouts() throws {
        let suiteName = "ProgressDashboardRenderingTests.NextFocusEvidence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let referenceDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 9, day: 3, hour: 12)
            )
        )
        let store = makeReviewedStore(defaults: defaults, referenceDate: referenceDate)
        let recommendationState = try XCTUnwrap(store.studyFocusState)
        let target = try XCTUnwrap(
            ProgressSkillEvidenceRoutingPolicy.target(
                for: recommendationState,
                goalID: try XCTUnwrap(store.goal?.id)
            )
        )
        let request = ProgressSkillEvidenceRequest(target: target)

        let fixtures = [
            ProgressDashboardRenderFixture(
                name: "progress-next-focus-gate-compact-dark",
                width: 320,
                height: 568,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    ProgressNextFocusUpgradeCardAuditView()
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-next-focus-gate-accessibility5-reduced",
                width: 393,
                height: 852,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    ProgressNextFocusUpgradeCardAuditView()
                )
            ),
            ProgressDashboardRenderFixture(
                name: "next-focus-cards-compact-dark",
                width: 320,
                height: 1_050,
                colorScheme: .dark,
                dynamicTypeSize: .large,
                content: AnyView(
                    ProgressNextFocusCardsAuditView(
                        recommendationState: recommendationState,
                        style: .compact
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "next-focus-cards-panel-accessibility5",
                width: 393,
                height: 2_500,
                colorScheme: .light,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    ProgressNextFocusCardsAuditView(
                        recommendationState: recommendationState,
                        style: .panel
                    )
                )
            ),
            ProgressDashboardRenderFixture(
                name: "progress-next-focus-request-expanded-accessibility5-reduced",
                width: 393,
                height: 2_500,
                colorScheme: .dark,
                dynamicTypeSize: .accessibility5,
                content: AnyView(
                    CompetencyView(
                        store: store,
                        reduceMotionOverride: true,
                        referenceDateOverride: referenceDate,
                        skillEvidenceRequest: Binding.constant(Optional(request))
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
                colorScheme: fixture.colorScheme,
                settlingTime: 0.15
            )

            XCTAssertEqual(image.size.width, fixture.width, accuracy: 0.5, fixture.name)
            XCTAssertEqual(image.size.height, fixture.height, accuracy: 0.5, fixture.name)
            let attachment = XCTAttachment(image: image)
            attachment.name = fixture.name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func makeRecommendationState(
        goalID: Goal.ID,
        skillID: SkillMapTopic.ID?,
        skillName: String
    ) throws -> StudyFocusState {
        let question = CheckpointQuestion(
            goalID: goalID,
            prompt: "Explain a recovery decision.",
            expectedAnswer: "Name the tradeoff and the recovery path.",
            explanation: "Use the latest failure signal as evidence.",
            topic: skillName,
            skillID: skillID,
            difficulty: 3,
            format: .shortAnswer,
            status: .incorrect,
            sourcePrompt: skillName
        )
        let recommendation = try XCTUnwrap(
            StudyFocusRecommendation(
                question: question,
                skillID: skillID,
                skillName: skillName,
                hasPracticeHistory: true
            )
        )
        return .recommendation(recommendation)
    }

    @MainActor
    private func assertReviewedFixtureContract(_ store: CheckpointStore) throws {
        XCTAssertEqual(store.activeDerivedSkillMap?.status, .reviewed)
        XCTAssertEqual(store.availableGoalProfiles.count, 2)
        XCTAssertEqual(
            store.activeProgressCompetencies.map { CompetencyProgressBand.resolve(for: $0) },
            [.notStarted, .calibrating, .needsPractice, .building, .strong]
        )

        guard case let .recommendation(recommendation)? = store.studyFocusState else {
            return XCTFail("The reviewed fixture must expose a real Next Focus recommendation.")
        }
        XCTAssertEqual(recommendation.title, "Reliability and failure recovery")
    }

    @MainActor
    private func makeReviewedStore(
        defaults: UserDefaults,
        referenceDate: Date,
        includesWeeklyActivity: Bool = true
    ) -> CheckpointStore {
        let now = referenceDate
        let topics = [
            SkillMapTopic(name: "Requirements and constraint discovery"),
            SkillMapTopic(name: "Distributed data modeling"),
            SkillMapTopic(name: "Reliability and failure recovery"),
            SkillMapTopic(name: "Performance capacity planning"),
            SkillMapTopic(name: "Technical decision communication")
        ]
        let map = GoalSkillMap(
            topics: topics,
            status: .reviewed,
            provenance: .userEdited,
            updatedAt: now.addingTimeInterval(-86_400)
        )
        let goal = Goal(
            title: "Lead a production architecture review",
            deadline: now.addingTimeInterval(86_400 * 45),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "system design and technical communication",
            derivedSkillMap: map,
            preferredQuestionStyle: .multipleChoice
        )
        let otherGoal = Goal(
            title: "Reach conversational Spanish",
            deadline: now.addingTimeInterval(86_400 * 90),
            category: .languageLearning,
            currentLevel: "Beginner",
            focusAreas: "speaking and listening",
            preferredQuestionStyle: .shortAnswer
        )
        let store = CheckpointStore(defaults: defaults)
        store.membershipTier = .member
        store.goal = goal
        store.goalProfiles = [goal, otherGoal]
        store.questionBatchState = .ready
        store.competencies = makeMixedCompetencies(
            goalID: goal.id,
            topics: topics,
            practicedAt: now
        )
        store.questions = topics.enumerated().map { index, topic in
            CheckpointQuestion(
                goalID: goal.id,
                prompt: "Explain a practical decision in \(topic.name.lowercased()).",
                expectedAnswer: "A clear decision with a stated tradeoff.",
                explanation: "Connect the decision to the system constraint.",
                verificationVersion: 1,
                topic: topic.name,
                skillID: topic.id,
                difficulty: 3,
                format: .shortAnswer,
                status: index == 2 ? .incorrect : .new,
                nextReviewAt: index == 2 ? now.addingTimeInterval(-300) : nil,
                sourcePrompt: topic.name
            )
        }
        if includesWeeklyActivity,
           let week = Calendar.current.dateInterval(of: .weekOfYear, for: referenceDate) {
            let availablePracticeDates = (0..<7).compactMap { offset -> Date? in
                guard let day = Calendar.current.date(
                    byAdding: .day,
                    value: offset,
                    to: week.start
                ),
                let practiceDate = Calendar.current.date(
                    byAdding: .hour,
                    value: 9,
                    to: day
                ),
                practiceDate <= referenceDate else { return nil }
                return practiceDate
            }
            let firstDate = availablePracticeDates.first ?? referenceDate
            let secondDate = availablePracticeDates.dropFirst().first
                ?? firstDate.addingTimeInterval(300)
            let thirdDate = availablePracticeDates.dropFirst(2).first
                ?? secondDate.addingTimeInterval(300)
            store.attempts = [
                makeAttempt(goal: goal, result: .correct, createdAt: firstDate),
                makeAttempt(
                    goal: goal,
                    result: .incorrect,
                    createdAt: firstDate.addingTimeInterval(60)
                ),
                makeAttempt(goal: goal, result: .correct, createdAt: secondDate),
                makeAttempt(
                    goal: goal,
                    result: .partial,
                    createdAt: secondDate.addingTimeInterval(60)
                ),
                makeAttempt(goal: goal, result: .correct, createdAt: thirdDate),
                makeAttempt(
                    goal: goal,
                    result: .correct,
                    createdAt: thirdDate.addingTimeInterval(60)
                )
            ]
            store.unlockEvents = [
                UnlockEvent(goalID: goal.id, minutes: 30, createdAt: firstDate),
                UnlockEvent(goalID: goal.id, minutes: 20, createdAt: thirdDate)
            ]
        }
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Explained a consistency tradeoff without losing the room.",
                loggedAt: now
            ),
            FocusWin(
                goalID: goal.id,
                note: "Found the highest-risk failure mode before proposing infrastructure.",
                loggedAt: now.addingTimeInterval(-86_400)
            )
        ]
        return store
    }

    private func makeMixedCompetencies(
        goalID: Goal.ID,
        topics: [SkillMapTopic],
        practicedAt: Date
    ) -> [TopicCompetency] {
        let untouched = TopicCompetency.initial(
            topic: topics[0].name,
            goalID: goalID,
            skillID: topics[0].id
        )

        var calibrating = TopicCompetency.initial(
            topic: topics[1].name,
            estimatedLevel: 2,
            goalID: goalID,
            skillID: topics[1].id
        )
        calibrating.attempts = 4
        calibrating.correct = 3
        calibrating.incorrect = 1
        calibrating.currentStreak = 2
        calibrating.lastResult = .correct
        calibrating.lastPracticedAt = practicedAt

        var needsPractice = TopicCompetency.initial(
            topic: topics[2].name,
            estimatedLevel: 1,
            goalID: goalID,
            skillID: topics[2].id
        )
        needsPractice.attempts = 10
        needsPractice.correct = 2
        needsPractice.partial = 1
        needsPractice.incorrect = 7
        needsPractice.lastResult = .incorrect
        needsPractice.lastPracticedAt = practicedAt.addingTimeInterval(-3_600)

        var building = TopicCompetency.initial(
            topic: topics[3].name,
            estimatedLevel: 2,
            goalID: goalID,
            skillID: topics[3].id
        )
        building.attempts = 10
        building.correct = 6
        building.partial = 1
        building.incorrect = 3
        building.currentStreak = 1
        building.lastResult = .correct
        building.lastPracticedAt = practicedAt.addingTimeInterval(-7_200)

        var strong = TopicCompetency.initial(
            topic: topics[4].name,
            estimatedLevel: 5,
            goalID: goalID,
            skillID: topics[4].id
        )
        strong.attempts = 10
        strong.correct = 10
        strong.currentStreak = 6
        strong.lastResult = .correct
        strong.lastPracticedAt = practicedAt.addingTimeInterval(-10_800)

        return [untouched, calibrating, needsPractice, building, strong]
    }

    @MainActor
    private func makeRepairStore(defaults: UserDefaults) -> CheckpointStore {
        let now = Date()
        let goal = Goal(
            title: "Pass senior technical interviews",
            deadline: now.addingTimeInterval(86_400 * 30),
            category: .codingInterview,
            currentLevel: "Intermediate",
            focusAreas: "arrays, system design, communication",
            preferredQuestionStyle: .multipleChoice
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        var recentCompetency = TopicCompetency.initial(
            topic: "Array problem solving",
            estimatedLevel: 2,
            goalID: goal.id
        )
        recentCompetency.attempts = 4
        recentCompetency.correct = 3
        recentCompetency.incorrect = 1
        recentCompetency.currentStreak = 2
        recentCompetency.lastResult = .correct
        recentCompetency.lastPracticedAt = now.addingTimeInterval(-1_800)
        store.competencies = [recentCompetency]
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Spotted the missing base case before running the code.",
                loggedAt: now
            )
        ]
        return store
    }

    @MainActor
    private func makeSuggestedStore(defaults: UserDefaults) -> CheckpointStore {
        let now = Date()
        let topics = [
            SkillMapTopic(name: "Argument structure"),
            SkillMapTopic(name: "Evidence evaluation"),
            SkillMapTopic(name: "Timed synthesis")
        ]
        let map = GoalSkillMap(
            topics: topics,
            status: .suggested,
            provenance: .backendInferred
        )
        let goal = Goal(
            title: "Raise my analytical writing score",
            deadline: now.addingTimeInterval(86_400 * 60),
            category: .examPrep,
            currentLevel: "Intermediate",
            focusAreas: "argument analysis and timed writing",
            derivedSkillMap: map,
            preferredQuestionStyle: .shortAnswer
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questionBatchState = .ready
        store.competencies = topics.map {
            TopicCompetency.initial(
                topic: $0.name,
                goalID: goal.id,
                skillID: $0.id
            )
        }
        store.questions = (0..<5).map { index in
            let topic = topics[index % topics.count]
            return CheckpointQuestion(
                goalID: goal.id,
                prompt: "Practice \(topic.name.lowercased()) with example \(index + 1).",
                expectedAnswer: "A focused response that makes the reasoning explicit.",
                explanation: "Connect the claim, evidence, and time constraint.",
                topic: topic.name,
                skillID: topic.id,
                difficulty: 3,
                format: .shortAnswer,
                sourcePrompt: topic.name
            )
        }
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Finished a timed outline without over-editing the introduction.",
                loggedAt: now
            )
        ]
        return store
    }

    @MainActor
    private func makeBuildingStore(defaults: UserDefaults) -> CheckpointStore {
        let now = Date()
        let goal = Goal(
            title: "Build confidence with financial modeling",
            deadline: now.addingTimeInterval(86_400 * 50),
            category: .custom,
            currentLevel: "Beginner",
            focusAreas: "forecasting, scenario analysis, and communication",
            preferredQuestionStyle: .shortAnswer
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questionBatchState = .generating
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Explained the main revenue driver without reaching for jargon.",
                loggedAt: now
            )
        ]
        return store
    }

    @MainActor
    private func makeFailureStore(defaults: UserDefaults) -> CheckpointStore {
        let now = Date()
        let goal = Goal(
            title: "Prepare a confident product strategy interview",
            deadline: now.addingTimeInterval(86_400 * 21),
            category: .custom,
            currentLevel: "Intermediate",
            focusAreas: "product sense and prioritization",
            preferredQuestionStyle: .reflection
        )
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.goalProfiles = [goal]
        store.questionBatchState = .failed
        store.lastQuestionGenerationFailure = .qualityRejected
        store.focusWins = [
            FocusWin(
                goalID: goal.id,
                note: "Made the tradeoff explicit before choosing a roadmap direction.",
                loggedAt: now
            )
        ]
        return store
    }
}

private struct ProgressFirstFoldFixture {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    let requiresFullyVisibleMomentum: Bool
}

@MainActor
private final class ProgressLayoutCapture {
    var frames: [ProgressLayoutElement: CGRect] = [:]
}

private struct ProgressDashboardRenderFixture {
    var name: String
    var width: CGFloat
    var height: CGFloat
    var colorScheme: ColorScheme
    var dynamicTypeSize: DynamicTypeSize
    var settlingTime: TimeInterval = 0.05
    var content: AnyView
}

private struct ProgressMomentumCardAuditView: View {
    let presentation: ProgressMomentumPresentation

    var body: some View {
        VStack {
            ProgressMomentumCard(
                presentation: presentation,
                reduceMotion: true
            ) {}

            Spacer(minLength: 0)
        }
        .padding(20)
        .checkpointScreenBackground()
    }
}

@MainActor
private final class ProgressMomentumRailMotionDriver: ObservableObject {
    @Published var reduceMotion: Bool
    @Published var revealID: ProgressMomentumRevealID

    init(
        reduceMotion: Bool = false,
        revealID: ProgressMomentumRevealID
    ) {
        self.reduceMotion = reduceMotion
        self.revealID = revealID
    }
}

private struct ProgressMomentumRailMotionHarness: View {
    @ObservedObject var driver: ProgressMomentumRailMotionDriver
    let days: [ProgressWeeklyImpactDayPresentation]
    let report: @MainActor (ProgressMomentumMotionStyle) -> Void

    var body: some View {
        ProgressMomentumActivityRail(
            days: days,
            replayID: driver.revealID,
            reduceMotion: driver.reduceMotion,
            renderStyleReporter: report
        )
        .padding(10)
        .frame(width: 320, height: 100)
        .background(CheckpointTheme.ink)
    }
}

@MainActor
private final class ProgressSkillEvidenceMotionDriver: ObservableObject {
    @Published var reduceMotion: Bool
    @Published var isSceneActive: Bool
    @Published var isCoveredByParentModal: Bool

    init(
        reduceMotion: Bool,
        isSceneActive: Bool = true,
        isCoveredByParentModal: Bool = false
    ) {
        self.reduceMotion = reduceMotion
        self.isSceneActive = isSceneActive
        self.isCoveredByParentModal = isCoveredByParentModal
    }
}

private struct ProgressSkillEvidenceMotionHarness: View {
    @ObservedObject var driver: ProgressSkillEvidenceMotionDriver
    let store: CheckpointStore
    let referenceDate: Date
    let resolution: @MainActor (
        ProgressSkillEvidenceRequest,
        ProgressSkillEvidenceResolution
    ) -> Void
    @State private var request: ProgressSkillEvidenceRequest?

    init(
        driver: ProgressSkillEvidenceMotionDriver,
        store: CheckpointStore,
        referenceDate: Date,
        request: ProgressSkillEvidenceRequest,
        resolution: @escaping @MainActor (
            ProgressSkillEvidenceRequest,
            ProgressSkillEvidenceResolution
        ) -> Void = { _, _ in }
    ) {
        self.driver = driver
        self.store = store
        self.referenceDate = referenceDate
        self.resolution = resolution
        _request = State(initialValue: request)
    }

    var body: some View {
        CompetencyView(
            store: store,
            reduceMotionOverride: driver.reduceMotion,
            referenceDateOverride: referenceDate,
            isSceneActive: driver.isSceneActive,
            isCoveredByParentModal: driver.isCoveredByParentModal,
            skillEvidenceRequest: $request,
            skillEvidenceResolution: resolution
        )
    }
}

@MainActor
private final class ProgressSkillEvidenceResolutionRecorder {
    private(set) var events: [ProgressSkillEvidenceResolution] = []

    func record(_ resolution: ProgressSkillEvidenceResolution) {
        events.append(resolution)
    }
}

private struct ProgressSkillRowsAuditView: View {
    var competencies: [TopicCompetency]

    var body: some View {
        ScrollView {
            SectionPanel("Focus areas") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Each proficiency state remains legible at large text sizes.")
                        .font(.footnote)
                        .foregroundStyle(CheckpointTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)

                    ForEach(Array(competencies.enumerated()), id: \.element.id) { index, competency in
                        CompetencyRow(competency: competency)

                        if index < competencies.count - 1 {
                            Divider()
                                .overlay(CheckpointTheme.hairline)
                        }
                    }
                }
            }
            .padding(20)
        }
        .checkpointScreenBackground()
    }
}

private struct ProgressNextFocusUpgradeCardAuditView: View {
    var body: some View {
        ScrollView {
            ProgressNextFocusUpgradeCard {}
                .padding(20)
        }
        .checkpointScreenBackground()
    }
}

private struct ProgressNextFocusCardsAuditView: View {
    let recommendationState: StudyFocusState
    let style: StudyFocusCardStyle

    private let informationalStates: [(label: String, state: StudyFocusState)] = [
        ("Awaiting a question", .awaitingQuestion),
        ("Caught up", .caughtUp)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                auditedCard(label: "Recommendation", state: recommendationState)

                ForEach(informationalStates, id: \.label) { item in
                    auditedCard(label: item.label, state: item.state)
                }
            }
            .padding(20)
        }
        .checkpointScreenBackground()
    }

    private func auditedCard(
        label: String,
        state: StudyFocusState
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(CheckpointTheme.muted)
                .accessibilityAddTraits(.isHeader)

            StudyFocusCard(state: state, style: style) {}
        }
    }
}
