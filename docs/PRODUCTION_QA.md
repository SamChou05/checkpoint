# Production QA

Use this checklist before TestFlight and again before App Store submission. Mark items with the date, device/build, result, and any follow-up commit. The dated final validation log lives in `docs/FINAL_LAUNCH_TEST_LOG.md`.

## Current QA Run

Started: June 4, 2026 PDT.

- [x] Debug simulator tests passed: 192 passed, 0 failed on July 12 after required Screen Time authorization, approved-relaunch, failed-erasure gating, crash-safe snapshot-erasure recovery, and question-session diversity coverage was added.
- [x] Bedrock question service unit tests passed: 88 passed, 0 failed on July 12.
- [x] Release simulator build succeeded.
- [x] `Checkpoint/Config/Secrets.xcconfig` is ignored and not tracked.
- [x] Backend endpoint is configured locally and returned authenticated, validated question sets across exam, language, history, and uncommon raw-goal fixtures.
- [x] Backend endpoint returned 401 for the same request without the bearer token.
- [x] Release physical-device build succeeded on connected iPhone.
- [x] Debug physical-device build, install, and launch succeeded on connected iPhone after StoreKit membership flow changes.
- [x] Debug physical-device build and reinstall succeeded after launch-readiness changes.
- [ ] Latest physical-device launch after reinstall is retested while the iPhone is unlocked.
- [x] StoreKit local config contract tests verify product IDs, launch prices, and renewal periods.
- [ ] Real shield loop retested on physical iPhone.
- [ ] Local StoreKit purchase/expiration tested from the shared Xcode scheme.
- [ ] StoreKit sandbox/TestFlight purchase checked.

Findings:

- Release entitlement refresh now runs when the app returns to foreground, so expired or canceled Pro access can return to Free without requiring a full app restart.
- The backend now fails closed when no bearer token is configured unless `ALLOW_UNAUTHENTICATED_BACKEND=true` is explicitly set. Keep rate limits enabled and rotate the token for controlled TestFlight testing. Before public release, replace the embedded shared bearer and caller-supplied install UUID with App Attest challenges/assertions, replay protection, and server-held key state.

## Automated Baseline

- [ ] `xcodebuild` Debug simulator tests pass.
- [ ] Release simulator build succeeds.
- [ ] Release physical-device build succeeds with distribution-ready signing settings.
- [ ] Bedrock question service unit tests pass.
- [ ] `sam validate --lint --template-file template.yaml` passes for the deployed question-bank infrastructure.
- [ ] No tracked secrets are present in the repo.
- [ ] Privacy manifests and entitlements are present for the app and Screen Time extensions.

## Payments And Plan Access

- [ ] App Store Connect has an auto-renewable subscription group.
- [ ] Monthly product ID exists: `checkpoint.membership.monthly`.
- [ ] Annual product ID exists: `checkpoint.membership.yearly`.
- [ ] Local StoreKit monthly and annual purchases switch the app to Pro in Debug.
- [ ] Local StoreKit cleared or expired subscriptions return the app to Free.
- [ ] Release builds start on Free when no current entitlement is present.
- [ ] StoreKit sandbox/TestFlight purchase switches the app to Pro.
- [ ] Restore purchases switches the app to Pro when an active entitlement exists.
- [ ] Cancellation or expired entitlement returns the app to Free on next entitlement refresh.
- [ ] Free users can complete the first-goal protected-app flow.
- [ ] Free users are gated when creating or switching beyond the first goal.
- [ ] Free users are gated when the first included practice set is exhausted.
- [ ] Pro users can create and switch up to 5 goals.

## AI Backend

- [ ] App build has the intended API Gateway `/v1/questions` endpoint; production Automatic has no Apple/local or canned fallback.
- [ ] The same API stage exposes authenticated `POST /v1/question-banks/ensure` and `POST /v1/question-banks/claim`; no unintended public routes or Lambda Function URL exist.
- [ ] Backend endpoint returns the documented JSON response, not placeholder Lambda text.
- [ ] Internal/TestFlight backend enforces its rotated bearer on synchronous generation, ensure, and claim; public production enforces App Attest assertions and replay protection instead of trusting the embedded bearer or install UUID.
- [ ] `ALLOW_UNAUTHENTICATED_BACKEND` is not enabled on any exposed API Gateway stage.
- [ ] Backend verifies current StoreKit entitlement before accepting paid bank targets/watermarks, assigning paid quotas, or enabling Pro-only access.
- [ ] Synchronous generation atomically rate limits by install ID and source IP; every asynchronous worker pass charges its pseudonymous install quota before Bedrock, and API Gateway throttles ensure/claim.
- [ ] Backend caps requested batch size.
- [ ] Backend rejects malformed, duplicate, off-target, and below-difficulty questions.
- [ ] App surfaces calm, actionable states when backend returns 401, 404, 409, 410, 422, 429, 502, 503, or malformed data.
- [ ] Goal title, focus areas, derived learning target, difficulty, and weak topics are present in backend requests.
- [ ] `ensure` returns `202` promptly without waiting for Bedrock and repeated identical ensures reuse the same bank without duplicate in-flight jobs.
- [ ] A Free-style bank with `lowWatermark=0` never exceeds `desiredCount` cumulative generated questions across claims, relaunches, and repeated ensure polling.
- [ ] A server-entitled bank with a positive watermark schedules refill after a claim reaches the watermark and returns toward `desiredCount`; an unverified caller cannot opt itself into that tier.
- [ ] Editing goal, source-document, or difficulty context produces a new context revision and never claims stale questions into the edited goal.
- [ ] The SQS worker continues preparing inventory after the app is force-quit, processes one message per invocation, and refills toward the configured target in chunks no larger than 20.
- [ ] Worker timeout is 120 seconds and source-queue visibility is at least 720 seconds; a failed job retries and reaches the dead-letter queue after five receives.
- [ ] Reusing the same persisted `claimID` returns the exact same questions after a simulated lost HTTP response; a new claim ID does not redeliver already-claimed remote IDs.
- [ ] Claiming an empty/processing bank returns quickly without making a synchronous Bedrock call, and client polling uses bounded backoff.
- [ ] The DynamoDB question-bank table uses `pk`/`sk`, encryption at rest, and enabled `expiresAt` TTL; the source queue and dead-letter queue both use server-side encryption.
- [ ] CloudWatch alarms are connected and exercised for repeated structured backend errors (including partial-batch worker failures), a source job older than 15 minutes, and any visible dead-letter message.
- [ ] Nominal question-bank TTL, queue retention, dead-letter retention, and Lambda log retention match the published privacy policy and App Store privacy labels.
- [ ] An authenticated, ownership-checked remote deletion API and offline retry flow ship before **Erase all data** claims immediate server erasure; until then, product/support copy accurately discloses TTL-based removal.

## Real Shield Loop

- [ ] On a fresh install, confirm the required Screen Time explanation appears before goal onboarding and the system authorization flow starts only after tapping Allow Screen Time.
- [ ] Cancel or deny once and confirm Checkpoint remains on a calm retry screen rather than revealing the tabs.
- [ ] Retry, approve, and confirm goal onboarding appears without relaunching.
- [ ] Force-quit and relaunch an approved install; confirm authorization resolves without another biometric sheet and the saved protected-app selection remains intact.
- [ ] Revoke access in iPhone Screen Time settings, return to Checkpoint, and confirm the required access screen replaces the app until permission is restored.
- [ ] Select protected apps/categories/websites.
- [ ] Start protection and verify the selected targets are blocked.
- [ ] While protection is on, remove one selected app and verify it opens immediately while the remaining selections stay blocked.
- [ ] Select a category, remove one app from its expanded selection, and verify the category does not silently re-protect that app.
- [ ] Install a new app from a previously selected category and confirm the documented snapshot behavior: it stays unprotected until the picker selection is refreshed.
- [ ] Select more than 50 websites and verify protection stays off with a clear limit message instead of applying a partial list.
- [ ] Select more than 50 apps and verify protection stays off with a clear limit message instead of applying a partial list.
- [ ] Remove the final protected app and verify protection turns off, the break timer is canceled, and no stale checkpoint opens.
- [ ] Turn protection off, force-quit and relaunch Checkpoint, and verify no previously selected app remains blocked.
- [ ] Open a protected app and confirm the custom Checkpoint shield appears.
- [ ] Confirm the shield shows the current goal after switching goals.
- [ ] Tap the shield action and confirm Checkpoint opens.
- [ ] Confirm a protected-app checkpoint appears without needing to manually start anything.
- [ ] Fail a checkpoint and confirm protected apps remain locked.
- [ ] Retake after failure and confirm missed questions are prioritized.
- [ ] Pass a checkpoint and confirm selected apps unblock for the configured break.
- [ ] Change the protected-app selection during a break and verify the newest list is the one re-locked at expiration.
- [ ] Repeat 5-, 10-, 15-, and 30-minute breaks, force-quit Checkpoint immediately, and verify background re-lock at each expiration.
- [ ] Confirm apps re-lock when the break expires.
- [ ] Force quit and relaunch during a break and after a break to confirm reconciliation.
- [ ] Restart the phone and confirm protection state is recovered correctly.

## Core UX

- [ ] Onboarding creates the first goal and starts background practice preparation.
- [ ] Onboarding can leave the app or force-quit while preparation is queued; relaunch resumes ensure/poll/claim from the persisted sync intent.
- [ ] A ready checkpoint is served entirely from claimed local inventory under normal, offline, and backend-outage conditions.
- [ ] Goal editing updates questions, Skill Map, and shield goal copy.
- [ ] Goal switching uses the selected goal's stored questions without unnecessary regeneration.
- [ ] Settings plan page clearly shows Free vs Pro and how to switch.
- [ ] Protected-app settings are understandable on small screens.
- [ ] Practice standard settings fit on small screens.
- [ ] Question explanations match the selected correct answer.
- [ ] Duplicate answer choices are rejected before storage.
- [ ] Correctly answered questions are not immediately repeated.
- [ ] Offline or failed generation states show calm recovery copy.

## App Store Assets

- [ ] Family Controls distribution access is approved for shipping bundle IDs.
- [ ] App privacy labels match local storage, Screen Time usage, and backend generation.
- [ ] Hosted privacy policy is live.
- [ ] Support URL is live.
- [ ] App Store screenshots are captured on current UI.
- [ ] App description and subtitle explain the consistency/checkpoint habit clearly.
- [ ] Review notes explain Family Controls, Managed Settings, Device Activity, App Groups, and unlock/re-lock behavior.
