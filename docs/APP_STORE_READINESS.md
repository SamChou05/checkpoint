# App Store Readiness

Checkpoint is not App Store-ready yet, but the repo now has the core workflow, tests, entitlements files, and privacy manifests needed to move toward TestFlight.

## Current Status

- Core checkpoint flow is implemented.
- Default unlock policy asks 5 questions and requires 4 correct answers.
- Failed checkpoint sets make missed questions due immediately so the next attempt retests them first.
- AI generation is AI-only: production `Automatic` routes directly to the configured cloud backend, with no alternate production source or canned fallback.
- A practice set is not ready until at least five questions pass validation; pending generation and retryable service, connection, or quality states are visible.
- Live-backend smoke tests exercised LSAT, MCAT, Spanish, modern history, and a raw-goal beekeeping case. Full validated sets were observed across all five domains; a partial Spanish batch was correctly rejected by the stricter gate and succeeded on retry. Endpoint and token values live only in ignored local configuration and are not recorded in version control.
- Main app and Screen Time extensions include Family Controls and App Group entitlement files.
- Main app and Screen Time extensions include privacy manifests for `UserDefaults` access.
- Successful checkpoints temporarily unshield selected apps, then schedule a Device Activity monitor extension to re-apply shields after the unlock window.
- Settings includes shield-extension diagnostics to confirm whether the custom Checkpoint shield rendered or iOS fell back to the default Restricted page.
- New installs start with no restricted apps/categories selected, and empty shield attempts surface an in-app error.
- Blocked-app launches with no available checkpoint questions surface a recovery notice.
- Simulator XCTest coverage passes for the core workflow.
- Starter-membership product behavior is implemented. The first goal and blocker/checkpoint/unlock loop are usable before payment; membership unlocks goal switching, fresh ongoing generation, larger question banks, and adaptive Study Assist.

## External Gates

These cannot be completed from the repo alone:

1. Join the Apple Developer Program under the team that will ship Checkpoint.
2. Register these bundle IDs:
   - `com.samchou.checkpoint`
   - `com.samchou.checkpoint.ShieldConfigurationExtension`
   - `com.samchou.checkpoint.ShieldActionExtension`
   - `com.samchou.checkpoint.DeviceActivityMonitorExtension`
3. Enable App Groups for all four bundle IDs with `group.com.samchou.checkpoint`.
4. Request Family Controls distribution access from Apple for the app and Screen Time extension bundle IDs.
5. Create development and distribution provisioning profiles after Apple grants the entitlement.
6. Accept the Paid Apps Agreement and configure banking/tax details before selling membership.
7. Create the auto-renewable subscription group/products in App Store Connect before submission.
8. Run the real shield loop on a physical iPhone before TestFlight.
9. Deploy the AI backend and configure an HTTPS endpoint and token for Release through `Checkpoint/Config/Secrets.xcconfig` or the `CHECKPOINT_AI_BACKEND_ENDPOINT_OVERRIDE` and `CHECKPOINT_AI_BACKEND_TOKEN_OVERRIDE` build settings. Release builds fail without the canonical cloud generation path.

## Latest Real-Device Validation Attempt

Last checked: June 3, 2026 PDT.

- Local entitlement files are present for the main app and all Screen Time extensions.
- A paired wired iPhone named `Shampoo` was visible to `xcrun devicectl`.
- Device details now report `developerModeStatus: enabled`.
- Local signing/provisioning now finds the paid team `RF8739P5MC` (`Cicada Labs LLC`) and generated development profiles.
- Physical-device Debug build now succeeds using the project signing settings.
- Checkpoint installs and launches on `Shampoo` with bundle ID `com.samchou.checkpoint`.
- Next action: complete the real shield/unshield/re-lock test plan below on the iPhone before TestFlight.

## Physical Device Test Plan

Run this before TestFlight and again before App Store submission:

1. Install a signed build on a real iPhone.
2. Launch Checkpoint and create a goal. Confirm the app shows preparation until five validated questions are ready.
3. Open Settings and request Screen Time setup.
4. Choose at least one restricted app and one category.
5. Apply the shield from Home.
6. Open a restricted app and confirm the Checkpoint shield appears.
7. If the system default Restricted page appears, open Settings > Advanced > Troubleshooting and reset and confirm whether the custom shield render count is still zero before debugging UI copy.
8. Tap the primary shield button and confirm Checkpoint opens.
9. Confirm the checkpoint sheet appears from the pending shield attempt, including when Checkpoint was last left on Settings, Progress, or History.
10. Fail at least two questions and confirm the app stays locked.
11. Try again and confirm the missed questions appear first.
12. Pass with 4 of 5 correct and confirm the app temporarily unshields.
13. Wait for the unlock window to expire and confirm the app re-locks.
14. Force quit and relaunch Checkpoint during an unlock window and after expiration to verify reconciliation.
15. Restart the phone and verify the selected app remains shielded when it should be.
16. Exercise a backend connection failure and a rejected-quality batch, and confirm each state is visible and retryable without canned questions appearing.

## App Review Notes Draft

Use this as a starting point in App Store Connect review notes:

Checkpoint helps users reduce distracting app use by combining Apple's Screen Time APIs with goal-based learning checkpoints. Users choose a learning goal and select apps or categories they want to restrict. When a restricted app is opened, the Screen Time shield prompts the user to return to Checkpoint and complete a short multiple-choice checkpoint. Passing the checkpoint temporarily unblocks the selected apps; failing keeps them restricted and prioritizes missed questions on the next attempt.

The app uses Family Controls, Managed Settings, Managed Settings UI, Device Activity, App Groups, and Screen Time extensions. The App Group is used only to pass shield context, pending checkpoint state, unlock expiration, desired shield state, and selected Screen Time state between the app and extensions.

AI question generation is batch-based and cached. Production `Automatic` routes directly to the configured cloud backend. Apple Foundation Models remains code-supported only as an explicit internal experiment and is not a production fallback or question source because availability, OS model version, and reasoning capability vary. There is no canned question fallback, and a set is not ready until at least five questions pass validation. Pending generation and service, connection, or quality failures are visible and retryable. Backend generation is internal service wiring rather than a normal user-facing setting; it is not called on every blocked-app attempt.

## Privacy Notes

- The app stores goal, question, answer-history, competency, shield-state, and unlock-window data locally.
- The app and extensions use App Group `UserDefaults` to coordinate shield state.
- Unlock windows can be 5, 10, 15, or 30 minutes. Short windows rely on the app-level re-lock task and foreground reconciliation, with Device Activity as an additional background re-lock path.
- Backend generation, when explicitly configured, sends goal context, derived learning target/topics, competency progress, existing prompts, and reported prompts to the configured endpoint.
- The app does not use tracking domains.
- The current privacy manifests declare `UserDefaults` required-reason API access:
  - `CA92.1` for app-only defaults in the main app.
  - `1C8F.1` for App Group defaults shared by the app and extensions.

## Not Ready Until

- Family Controls distribution access is approved for all shipping bundle IDs.
- A real iPhone passes the shield/unshield/re-lock test plan.
- App Store privacy labels and a hosted privacy policy are finalized.
- Screenshots, description, support URL, age rating, and review notes are created in App Store Connect. Draft copy is tracked in `docs/APP_STORE_COPY.md`.
- A hosted privacy policy is published from the draft in `docs/PRIVACY_POLICY_DRAFT.md`.
- Persistence is accepted as MVP-local storage or replaced with a production store.
- The production backend is deployed, and the Release configuration resolves a valid HTTPS endpoint and nonempty token.
- Monetization scope is finalized, the Paid Apps Agreement is active, App Store Connect subscription products are configured, and starter/member launch assumptions are reviewed against backend AI cost.
