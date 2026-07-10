# Privacy Policy Draft

Effective date: To be finalized before launch.

This draft is for review before hosting a public privacy policy URL. It should be reviewed against the final App Store privacy labels, backend behavior, and any legal requirements before submission.

## Overview

Checkpoint helps users protect selected apps and complete goal-aligned practice before taking timed app breaks. The app is designed to keep most user data on the user's device.

## Information Stored On Device

Checkpoint may store the following information locally on the user's device:

- Learning goals, deadlines, focus areas, and question difficulty.
- Generated practice questions, answer choices, explanations, and skill topics.
- Checkpoint attempts, answer history, accuracy, and skill progress.
- Protected-app configuration selected through Apple's Screen Time APIs.
- Shield state, unlock expiration, and app-group coordination data used by Screen Time extensions.
- Question reports and diagnostic information shown inside the app.
- A random installation identifier and, if the optional cloud question reserve is enabled, a random installation secret stored in the iOS Keychain.

## Screen Time Data

Checkpoint uses Apple's Family Controls, Managed Settings, Managed Settings UI, and Device Activity frameworks to let users select and protect apps, categories, and websites. Screen Time selections are stored locally and shared with Checkpoint's extensions through an App Group so the shield and re-lock flow can work.

Checkpoint does not sell Screen Time selections or use them for advertising.

## AI Question Generation

Checkpoint generates practice questions in batches and caches them locally.

When backend AI generation is configured, Checkpoint may send goal context, focus areas, derived learning targets, weak topics, existing question prompts, and reported question prompts to the configured backend service so new questions can be generated. AWS and model-provider credentials are not stored in the app.

Pro users may separately choose to enable the cloud question reserve. When enabled, Checkpoint retains one bounded, revisioned goal-generation snapshot and up to 20 prepared or awaiting-delivery questions per goal so generation can finish while Checkpoint is not running. The backend authenticates access with a random per-installation secret; it stores only a cryptographic hash of that secret. Screen Time selections, unlock history, purchase records, and the learner's complete answer history are not uploaded to the reserve.

If backend generation is unavailable, Checkpoint can use on-device generation when supported or local templates.

## Purchases

Checkpoint uses Apple StoreKit for subscriptions. Purchases, billing, refunds, and subscription management are handled by Apple. Checkpoint receives subscription entitlement information from StoreKit so the app can determine whether Free or Pro features should be available.

## Tracking And Advertising

Checkpoint does not use third-party advertising or tracking identifiers in the current implementation.

## Data Sharing

Checkpoint does not sell user data. If backend AI generation is enabled, the app sends only the goal and question-generation context needed to generate practice material.

## Retention

Local app data remains on the device until the user deletes app data, resets the app, or uninstalls Checkpoint.

Cloud-reserve goal snapshots, prepared questions, bounded recent coverage, and operational metadata expire automatically after at most 30 days without an authenticated update. Disabling the reserve, deleting a goal, or resetting Checkpoint also sends an authenticated deletion request. Automatic expiry remains the fallback if the device is offline or the app is uninstalled before it can send that request. Minimal abuse-prevention counters and an expired installation credential hash may remain until their configured TTL expires.

## Contact

Support contact or support URL: To be finalized before launch.
