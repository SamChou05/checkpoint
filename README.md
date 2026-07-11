# Checkpoint

Checkpoint is a SwiftUI iOS app for goal-gated screen time. The app turns an attempted distraction into an AI-assisted multiple-choice checkpoint question, stores the answer history, and uses missed/due questions before generating new ones.

See `DEVELOPMENT.md` for the current build status, platform constraints, product decisions, and MVP roadmap.

## Current Build

- Native SwiftUI app shell.
- Natural-language goal onboarding flow with the first goal included and membership unlocking goal switching plus fresh ongoing question generation.
- The raw typed goal is authoritative. Legacy goal category remains compatibility metadata and new goals default to `Custom` instead of being classified by subject keywords.
- Provider-based multiple-choice question generation extracts a learning target from typed goals, so phrases like `Study for the LSAT` produce LSAT questions rather than study-habit prompts.
- Goals without focus areas ask the active AI provider to infer a subject-matter Skill Map from the user's exact learning target; Checkpoint does not seed it with canned topic lists.
- Automatic question generation with provider details abstracted away from the user-facing app.
- Multi-question checkpoint sessions that ask 5 questions and require 4 correct answers by default before an unlock.
- Per-profile 1-to-5 question difficulty floor so users can skip remedial prompts for goals they already know well, with an opt-in level-up prompt after strong recent accuracy.
- Correct-answer unlock windows use 5, 10, 15, or 30 minutes, with 30 minutes as the default.
- Stored checkpoint attempts with correctness and unlock state.
- Missed questions from a failed unlock attempt become due immediately so the next checkpoint retests them first.
- XCTest coverage for the core checkpoint, scheduler, unlock, sanitizer, and provider-cost workflows.
- Recovery states for blocked-app launches when no checkpoint questions are available.
- Academic paper-inspired UI for Home, Checkpoint, Progress, and Settings, with history available from Settings.
- Settings keeps everyday controls focused on goals, app protection, checkpoint rules, history, and plan access; reset is collapsed under App data and technical diagnostics appear only in Debug builds.
- Feedback notes live in Settings and can be shared through the system share sheet instead of interrupting the checkpoint quiz.
- Home no longer offers one-tap pause or manual checkpoint entry while blocking is active; short breaks start from blocked-app attempts or emergency passes, while fully stopping blocking requires an 18-of-20 stop challenge.
- Manual checkpoint preview lives in Debug-only Developer tools and does not unlock apps.
- Checkpoint quietly prepares fresh questions when the current set can no longer fill the next checkpoint, so users do not manage a question bank.
- Users can switch goal profiles from Home; each profile keeps its own focus areas, question difficulty, practice set, history, reports, and Skill Map.
- Starter/membership product behavior: the first goal, app blocking, and checkpoint unlock loop are usable before payment; membership keeps fresh checkpoints ready, unlocks goal profiles, larger question banks, and adaptive Study Assist.
- Privacy manifests for the app and Screen Time extensions.
- Screen Time controller for Family Controls authorization, app selection, shielding, temporary unlocks, and re-lock reconciliation.
- Shield Configuration extension target for branded Screen Time shield UI.
- Shield Action extension target that records a pending checkpoint and asks iOS to open Checkpoint when the shield primary button is tapped.
- Device Activity Monitor extension target that re-applies shields when a temporary unlock expires.
- Shared App Group state for passing the current goal/prompt and pending shield attempts between app and extensions.

## AI Question Generation

The MVP uses one canonical production AI route:

- Production `Automatic` routes directly to the configured cloud backend.
- Apple Foundation Models remains code-supported only as an explicit internal experiment. It is not selected by production `Automatic` and is not a production fallback or question source because availability, OS model version, and reasoning capability vary.
- Cloud generation is batch-based; the first AWS Bedrock Lambda service lives in `backend/bedrock-question-service`.
- Checkpoint does not substitute canned or template questions when AI generation is unavailable or produces an unacceptable batch.
- Provider prompts receive the raw goal plus optional focus, current level, derived topics, and competency history through one domain-general assessment contract.
- Named subjects such as LSAT, MCAT, language learning, and beekeeping live only in evaluation fixtures; production prompts and validators do not branch by subject or contain authored question banks.
- A set is not ready until at least five questions survive the app's relevance, completeness, difficulty, and duplicate checks.
- Pending generation and retryable service, connection, or quality failures are visible in the app instead of being replaced silently.
- Release builds require an HTTPS endpoint and token through `Checkpoint/Config/Secrets.xcconfig` or the `CHECKPOINT_AI_BACKEND_ENDPOINT_OVERRIDE` and `CHECKPOINT_AI_BACKEND_TOKEN_OVERRIDE` build settings. Provider configuration is not exposed in user-facing Settings, and AWS credentials must never ship in the app.
- Backend calls include an anonymous install ID and the Bedrock service can enforce DynamoDB-backed install/IP daily quotas before model invocation.
- The Bedrock service retries malformed output against one pinned production model and fails visibly if it cannot produce a validated batch; alternate models are disabled by default.

The backend request/response shape is documented in `docs/AI_BACKEND_CONTRACT.md`. The app intentionally generates and caches question batches instead of exposing model/source choices or calling AI on every blocked-app attempt.

## App Store Readiness

See `docs/APP_STORE_READINESS.md` for entitlement steps, physical-device testing, App Review notes, and remaining launch blockers.

See `docs/MONETIZATION.md` for the starter-membership monetization direction and launch pricing notes.

See `docs/STOREKIT_LAUNCH.md` for local StoreKit testing and App Store Connect subscription setup.

See `docs/FINAL_LAUNCH_TEST_LOG.md` for the final manual validation log, and `docs/APP_STORE_COPY.md` plus `docs/PRIVACY_POLICY_DRAFT.md` for App Store submission drafts.

## Testing

Run the `Checkpoint` scheme tests in Xcode. The suite covers the 4-of-5 unlock gate, failed-session retesting, missed/due scheduling, shield-triggered session creation, no-question recovery states, AI-only provider routing and failure handling, unlock duration policy, emergency unlock session creation, empty Screen Time selection defaults, starter membership gates, member goal profile isolation, Skill Map inference, adaptive level-up, Study Assist, and provider payload sanitization.

## Open

Open `Checkpoint.xcodeproj` in Xcode and run the `Checkpoint` target on an iPhone simulator or device. Simulator XCTest verification is passing locally; real Screen Time behavior still needs device testing.

## Preview While Building

Fastest options:

1. Open `Checkpoint.xcodeproj` in Xcode.
2. Select the `Checkpoint` scheme.
3. Run on an iPhone simulator to preview the whole app.
4. In a Debug build, use Settings -> Developer tools -> `Preview checkpoint` when you need to test the checkpoint flow manually.

For real Screen Time testing:

1. Use a real iPhone when possible.
2. In Xcode, add the Family Controls capability for the app target.
3. Confirm the bundle ID is available in your Apple Developer account.
4. Tap `Set up app protection` on Home, or open Settings -> `Allow Screen Time`, and approve access.
5. Select apps/categories and tap `Start blocking` from Home.

The current code includes the FamilyControls picker, selection persistence, ManagedSettings shielding, temporary unshielding after a successful checkpoint, automatic re-shielding after the unlock timer, a Device Activity monitor extension for background re-locking, shield configuration/action extensions, and App Group state sharing.

## Real-Device Loop To Verify

1. Launch Checkpoint and create a goal.
2. Tap `Set up app protection` and approve Screen Time access.
3. Settings -> `Choose blocked apps`.
4. Home -> `Start blocking`.
5. Open a selected blocked app.
6. Confirm the Checkpoint shield appears with current goal/prompt copy.
7. Tap `Open Checkpoint` on the shield.
8. Confirm Checkpoint opens and shows the checkpoint answer sheet.
9. Answer the checkpoint set correctly.
10. Confirm the selected app is temporarily unshielded.
11. Confirm the app re-locks after the unlock expires or after Checkpoint returns active.

## Required Apple Setup

- Add Family Controls capability to the main app and Screen Time extensions.
- Add App Groups to the main app and Screen Time extensions.
- Use the same group ID: `group.com.samchou.checkpoint`.
- Configure the main app bundle ID: `com.samchou.checkpoint`.
- Configure extension bundle IDs:
  - `com.samchou.checkpoint.ShieldConfigurationExtension`
  - `com.samchou.checkpoint.ShieldActionExtension`
  - `com.samchou.checkpoint.DeviceActivityMonitorExtension`
- Family Controls distribution requires Apple approval before App Store submission.
