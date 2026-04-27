# Checkpoint

Checkpoint is a SwiftUI iOS prototype for goal-gated screen time. The app turns an attempted distraction into an AI-assisted multiple-choice checkpoint question, stores the answer history, and uses missed/due questions before generating new ones.

See `DEVELOPMENT.md` for the current build status, platform constraints, product decisions, and MVP roadmap.

## Current Build

- Native SwiftUI app shell.
- One active goal onboarding flow.
- Provider-based multiple-choice question generation seeded from typed goal context.
- AI provider settings for Automatic, Apple Foundation Models, Backend, and Local Templates.
- Stored checkpoint attempts with correctness and unlock state.
- Modern dark UI for Home, Checkpoint, History, and Settings.
- Screen Time service placeholder ready for the FamilyControls technical spike.
- Shield Configuration extension target for branded Screen Time shield UI.
- Shield Action extension target that records a pending checkpoint when the shield primary button is tapped.
- Shared App Group state for passing the current goal/prompt and pending shield attempts between app and extensions.

## AI Question Generation

The MVP uses a hybrid provider approach:

- Automatic tries Apple Foundation Models when available, then a configured backend endpoint, then local templates.
- Apple Foundation Models can provide on-device generation on Apple Intelligence-compatible devices.
- Backend generation is batch-based and configured in Settings with an endpoint URL.
- Local Templates keep the app usable without network, backend, or supported on-device models.

The backend request/response shape is documented in `docs/AI_BACKEND_CONTRACT.md`. The app intentionally generates and caches question batches instead of calling AI on every blocked-app attempt.

## Open

Open `Checkpoint.xcodeproj` in Xcode and run the `Checkpoint` target on an iPhone simulator or device. Full `xcodebuild` verification was not run in this environment because the active developer directory is Command Line Tools, not Xcode.

## Preview While Building

Fastest options:

1. Open `Checkpoint.xcodeproj` in Xcode.
2. Select the `Checkpoint` scheme.
3. Run on an iPhone simulator to preview the whole app.
4. Use Home -> `Simulate blocked app attempt` to preview the checkpoint flow before real app shielding is fully wired.

For real Screen Time testing:

1. Use a real iPhone when possible.
2. In Xcode, add the Family Controls capability for the app target.
3. Confirm the bundle ID is available in your Apple Developer account.
4. Run the app, open Settings -> `Request setup`, then `Choose restricted apps`.
5. Select apps/categories and tap `Apply shield` from Home.

The current code includes the FamilyControls picker, selection persistence, ManagedSettings shielding, temporary unshielding after a successful checkpoint, automatic re-shielding after the unlock timer, shield configuration/action extensions, and App Group state sharing.

## Real-Device Loop To Verify

1. Launch Checkpoint and create a goal.
2. Settings -> `Request setup`.
3. Settings -> `Choose restricted apps`.
4. Home -> `Apply shield`.
5. Open a selected restricted app.
6. Confirm the Checkpoint shield appears with current goal/prompt copy.
7. Tap `Open Checkpoint` on the shield.
8. Open Checkpoint and confirm the checkpoint answer sheet appears.
9. Mark the answer correct/partial.
10. Confirm the selected app is temporarily unshielded.
11. Confirm the app re-locks after the unlock expires or after Checkpoint returns active.

## Required Apple Setup

- Add Family Controls capability to the main app and both extensions.
- Add App Groups to the main app and both extensions.
- Use the same group ID: `group.com.samchou.checkpoint`.
- Configure the main app bundle ID: `com.samchou.checkpoint`.
- Configure extension bundle IDs:
  - `com.samchou.checkpoint.ShieldConfigurationExtension`
  - `com.samchou.checkpoint.ShieldActionExtension`
- Family Controls distribution requires Apple approval before App Store submission.
