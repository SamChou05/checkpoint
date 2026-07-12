# Privacy Policy Draft

Effective date: To be finalized before launch.

This is a working draft, not the published policy. It describes the current implementation and calls out decisions that must still be finalized. It must be reviewed against the production AWS deployment, App Store privacy labels, Apple requirements, and applicable law before publication.

## Overview

Checkpoint helps users protect selected apps and complete goal-aligned practice before taking timed app breaks. Most learning, progress, and Screen Time data is stored on the user's device. Checkpoint uses an AWS-hosted service and Amazon Bedrock when it needs to generate new practice questions.

## Information Stored On Device

Checkpoint may store the following information locally:

- Goals, deadlines, categories, current level, focus areas, and difficulty preferences.
- Generated questions, choices, expected answers, explanations, topics, and question status.
- Competency estimates, attempts, answer history, accuracy, progress, and app-break history.
- Question and issue reports plus limited question-generation diagnostics.
- Protected-app, category, and website selections made through Apple's Screen Time APIs.
- Current protection and break state used by the main app and its Screen Time extensions.
- A randomly generated installation identifier used for backend quotas. This is not Apple's advertising identifier and is not an account identifier.
- StoreKit entitlement state needed to determine whether Free or Pro features are available.

The main learning snapshot is stored as a schema-versioned primary file and a recovery backup in the app's Application Support directory. Writes are atomic, and supported iOS builds apply file protection that makes the files available after the device is first unlocked. The recovery backup can contain the immediately preceding valid snapshot until it is replaced by a later save or erased.

The current code does not opt these Application Support files out of iOS device backups. The launch policy must decide whether progress should transfer through a user's device backup or instead be excluded. Until that decision is implemented and reviewed, the final policy and support copy must not imply that in-app erasure also removes copies held inside previously created device backups.

Screen Time selection and coordination data is stored separately in the app's shared App Group so Checkpoint's extensions can apply and remove shields.

## Local Retention Limits

Local data remains until it is removed by the user, pruned by the limits below, or removed when Checkpoint is uninstalled. The current implementation keeps at most:

- 500 questions per goal, prioritizing still-usable questions and then the most recently used retired questions.
- 2,000 attempts per goal.
- 1,000 unlock events per goal.
- 250 question reports per goal.
- 100 issue reports across the app.
- 20 question-generation diagnostic traces.

Goals, current competency summaries, and other current configuration do not yet have a time-based expiration. The final policy should confirm whether any additional age-based retention period is required.

## Screen Time Data

Checkpoint uses Apple's Family Controls, Managed Settings, Managed Settings UI, and Device Activity frameworks to let users select and protect apps, categories, and websites. These selections are represented using Apple's opaque Screen Time tokens. Checkpoint does not sell Screen Time selections or use them for advertising.

## AI Question Generation

When cloud question generation is used, Checkpoint sends its backend the information needed to request a new question batch. This can include:

- Goal title, deadline, category, current level, focus areas, and desired difficulty.
- Derived learning target, topic list, question guidance, and whether a skill map is needed.
- Competency topic, estimated level, mastery percentage, and attempt count.
- Existing question prompts and limited question coverage, including topic, expected answer, choices, and difficulty, to reduce repetition.
- Reported question prompts, requested question count, and difficulty guidance.

The request also includes the random installation identifier in a header. AWS infrastructure observes the request's source IP address as part of delivering the network request.

The Checkpoint backend validates the request and sends a generation prompt containing the relevant goal and question context to Amazon Bedrock. Amazon Bedrock returns generated question content to the backend, which validates it before returning it to the app. The Checkpoint application database does not intentionally store request bodies, goal text, or generated questions. Operational metrics intentionally contain counts, status, latency, token usage, and a request identifier rather than goal or question text.

The deployed AWS region, Amazon Bedrock model, optional Bedrock Guardrail configuration, AWS service-processing retention, subprocessors, and any contractual data-use settings must be confirmed before this draft is published.

An Apple Foundation Models path remains code-supported only for explicit internal experiments. It is not selected by production Automatic mode and is not a production fallback or question source.

## Backend Quotas And Operational Data

The backend currently applies daily limits by installation identifier and source IP address. Before quota rows are written, each identifier is transformed with a server-secret keyed hash. The quota table stores the resulting pseudonymous key, the UTC day, a request count, and an expiration timestamp; it does not intentionally store the raw installation identifier or raw IP address in those quota rows.

The configured default makes quota rows eligible for automatic deletion after 48 hours, and the current infrastructure permits a configured period of up to 14 days. AWS Time to Live deletion is asynchronous, so removal can occur after the eligibility time rather than at an exact moment. Lambda operational logs currently have a configurable retention period of 7 to 90 days, with a 14-day default. The production values and treatment of network metadata in AWS service logs must be verified before launch.

## Purchases

Checkpoint uses Apple StoreKit for subscriptions. Purchases, billing, refunds, cancellation, and subscription management are handled by Apple. Checkpoint receives subscription entitlement information from StoreKit so the app can determine whether Free or Pro features should be available. Apple's handling of purchase information is governed by Apple's policies.

## Tracking, Advertising, And Sale

Checkpoint does not use third-party advertising or Apple's advertising identifier in the current implementation. Checkpoint does not sell personal information. The final App Store privacy labels must be completed consistently with the production app and backend.

## Erasing Data

Using **Erase all data** in Checkpoint removes the local primary and backup learning snapshots, any legacy snapshot, goals and progress in memory, the App Group's Screen Time selection and coordination files, protection diagnostics, and the locally stored installation identifier. It also turns off Checkpoint-managed shields.

Erase all data does not cancel an Apple subscription and does not revoke the Screen Time permission granted in iOS Settings. Existing pseudonymous backend quota rows are not actively deleted by the app; they remain until their AWS Time to Live expiration and asynchronous deletion. Data already processed by AWS or Amazon Bedrock is subject to the production service-processing terms and retention settings that still need to be finalized.

The final policy and support process must state whether users can request deletion of any production backend or operational records beyond the in-app erase flow.

## Security

Checkpoint uses HTTPS for its configured backend and public legal links. Local state uses iOS file protection as described above, and the backend quota table uses encryption at rest. No security measure can guarantee absolute protection. Production authentication and abuse controls, including App Attest-backed requests, must be completed and reflected in the final security review before public release.

## Children's Privacy And Age Rating

Checkpoint's intended audience, age-rating strategy, and any child-specific privacy obligations remain to be finalized before launch. Arbitrary user-created goals and AI-generated content must be included in that review.

## Contact

Support contact, support URL, privacy contact, operator legal name and address, applicable legal bases, user-rights process, and effective date: To be finalized before launch.
