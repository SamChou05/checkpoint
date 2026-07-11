# App Store Copy Draft

This is a working draft for App Store Connect. Tune it after screenshots and final pricing are locked.

## App Name

Checkpoint

## Subtitle Options

- Practice before you scroll
- Turn app breaks into practice
- Stay consistent with your goals

## Promotional Text

Build consistency toward the goals you already care about. Checkpoint blocks selected apps, asks short goal-aligned practice sets, and gives you a focused break only after you pass.

## Description Draft

Checkpoint helps you turn impulsive app use into consistent progress.

Set a learning goal, choose the apps or categories you want to protect, and let Checkpoint prepare short multiple-choice practice sets around that goal. When you open a protected app, Checkpoint asks you to clear a brief checkpoint first. Pass the checkpoint to take a timed break. Miss a question, and the idea comes back for review.

Use Checkpoint for exam prep, interview practice, school topics, or any focused learning goal where consistency matters more than cramming.

What Checkpoint does:

- Protect selected apps and categories with Apple's Screen Time APIs.
- Generate and cache goal-aligned practice questions.
- Ask short checkpoint sets before protected-app breaks.
- Temporarily unlock protected apps after a passing score.
- Re-lock apps when the break window expires.
- Track weekly questions answered, accuracy, skill progress, and screen-time patterns.
- Keep separate Pro goal profiles for school, exams, interviews, and personal goals.

Checkpoint is designed to feel steady, academic, and low-friction. It is not about guilt or punishment. It is about making the next small rep easier to choose.

## Keywords Draft

screen time, study, focus, habits, learning, exam prep, productivity, app blocker, goals, practice

## What's New Draft

Initial TestFlight build for Checkpoint's goal-based app protection and practice flow.

## Subscription Copy

Checkpoint has a Free plan and a Pro plan.

Free includes one goal, protected-app setup, short checkpoint sets, and the primary unlock flow.

Pro adds multiple goals, ongoing fresh practice generation, broader question variety, and guided review.

Launch pricing:

- Monthly: `$4.99/mo`
- Annual: `$29.99/yr`

StoreKit product IDs:

- `checkpoint.membership.monthly`
- `checkpoint.membership.yearly`

## App Review Notes Draft

Checkpoint uses Apple's Screen Time APIs to let users choose apps, categories, and websites they want to protect. When a protected app is opened, iOS shows a Checkpoint shield. The shield directs the user back to Checkpoint, where the user completes a short multiple-choice practice set based on their current learning goal. Passing the checkpoint temporarily unlocks the selected apps; failing keeps the apps protected and prioritizes missed questions for review.

The app uses Family Controls, Managed Settings, Managed Settings UI, Device Activity, and App Groups. App Groups are used to share shield state, pending checkpoint attempts, selected Screen Time tokens, current goal title, unlock expiration, and diagnostics between the app and its extensions.

Question generation is AI-only, batch-based, and cached. The app does not call AI on every protected-app attempt. Production Automatic generation uses the configured cloud backend, which receives the goal context and question-generation metadata needed to prepare a batch. Checkpoint does not substitute canned questions. A practice set is ready only after at least five questions pass validation; pending generation and retryable service, connection, or quality failures are shown in the app.

## Screenshot Plan

Capture current UI after final polish:

- Home with current goal and weekly stats.
- Goal setup/edit screen with focus areas and difficulty.
- Protected apps settings with Screen Time selection.
- Checkpoint quiz screen with explanation after answer.
- Skill Map progress screen.
- Plan screen showing Free vs Pro.
- Custom shield screen on a real iPhone.

## Required URLs

These need real hosted pages before App Store submission:

- Privacy Policy URL
- Support URL
- Optional marketing landing page
