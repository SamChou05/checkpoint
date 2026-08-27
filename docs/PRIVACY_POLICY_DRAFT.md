# Privacy Policy Draft

Effective date: To be finalized before launch.

This is a working draft, not the published policy. It describes the current implementation and calls out decisions that must still be finalized. It must be reviewed against the production AWS deployment, App Store privacy labels, Apple requirements, and applicable law before publication.

## Overview

Checkpoint helps users protect selected apps and complete goal-aligned practice before taking timed app breaks. Most learning, progress, and Screen Time data is stored on the user's device. Checkpoint uses an AWS-hosted service and Amazon Bedrock to prepare new practice questions asynchronously, temporarily store server-side question-bank content, and deliver already-prepared questions to the app.

## Information Stored On Device

Checkpoint may store the following information locally:

- Goals, deadlines, categories, current level, focus areas, difficulty preferences, and text extracted from optional study-material files.
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
- Filenames and extracted text from optional study materials attached to the goal.

The request also includes the random installation identifier in a header. AWS infrastructure observes the request's source IP address as part of delivering the network request.

The Checkpoint backend validates the request and stores the normalized generation context in an encrypted, expiring DynamoDB question bank. When preparation is needed, a database transaction atomically links the bank to a pending coordination job. A DynamoDB Streams consumer durably forwards that job to an encrypted queue, and an asynchronous worker later sends the relevant goal and question context to Amazon Bedrock. Amazon Bedrock returns generated question content to the worker, which validates and stores accepted questions. Claiming marks those questions as claimed rather than deleting them; their content remains with the bank as deduplication history until its Time to Live makes the records eligible for deletion. This lets preparation continue when the app is suspended or closed and keeps model latency out of the checkpoint-serving request. Operational metrics intentionally contain counts, status, latency, token usage, and a request identifier rather than goal or question text.

The current small-document feature extracts selectable text from supported text and PDF files on the device. It does not upload the original binary file. Extracted text is retained with the local goal until that goal or all app data is erased, and is transmitted again when it is needed to generate questions for that goal. Scanned PDFs without selectable text are not processed in the current implementation.

The deployed AWS region, Amazon Bedrock model, optional Bedrock Guardrail configuration, AWS service-processing retention, subprocessors, and any contractual data-use settings must be confirmed before this draft is published.

An Apple Foundation Models path remains code-supported only for explicit internal experiments. It is not selected by production Automatic mode and is not a production fallback or question source.

## Server Question Banks, Queues, Quotas, And Operational Data

For asynchronous preparation, the backend stores a temporary bank containing the normalized goal and learner context described above, optional extracted source text, prior-question coverage used to avoid repetition, ready and claimed generated questions, processing status, context revision, and idempotent claim-response records. Stable remote question identifiers and client-provided claim UUIDs are used to prevent the same prepared questions from being delivered twice during a network retry. The claim UUID is stored only as a SHA-256-derived key; its response content is retained with the bank for repeat delivery.

Question-bank partitions are scoped using server-secret keyed hashes of the caller's installation and bank/goal context. This reduces direct exposure but does not make the content anonymous: the bank itself can contain user-entered goals, learner context, questions, and extracted study-material text. The DynamoDB table is encrypted at rest.

Question-bank records have a nominal 30-day Time to Live by default. The expiration is refreshed by ongoing bank activity such as ensure/configuration updates, generation, and claims, so the period runs from recent activity rather than necessarily from initial creation. Stale context revisions may be made eligible for deletion sooner. DynamoDB Time to Live deletion is asynchronous, so records can remain after their expiration timestamp. The production retention value must be confirmed before publication.

The question-bank table publishes `NEW_IMAGE` changes to DynamoDB Streams for up to 24 hours so a failed queue handoff can be recovered. Stream images can include the changed DynamoDB item, including bank content when a content-bearing item changes, although the outbox consumer filters for pending coordination-job records. DynamoDB Streams can deliver a record more than once; stable job IDs and conditional worker processing leases prevent a replay from intentionally generating or delivering duplicate inventory.

The encrypted SQS generation queue carries only an opaque pseudonymous bank key, a job identifier, and a context revision—not raw installation IDs, IP addresses, goal text, study-material text, or generated questions. Unprocessed source-queue messages can remain for up to 4 days. Generation jobs that reach the configured receive threshold—five by default—move to an encrypted generation dead-letter queue and can remain there for up to 14 days pending operational review or expiry. When DynamoDB stream processing exhausts its separate five-retry/24-hour bound, the separately encrypted outbox failure queue receives Lambda invocation metadata such as the stream ARN, shard and sequence range, invocation status, and timestamps. That metadata does not contain the original stream image or question-bank item and can remain for up to 14 days. Operators must not copy either failure-queue payload into longer-lived tickets or logs without a documented need and retention rule.

For synchronous generation, the backend applies daily limits by installation identifier and source IP address. Before quota rows are written, each identifier is transformed with a server-secret keyed hash. For asynchronous generation, each worker generation pass uses a separate keyed-hash installation counter; the SQS job does not retain source IP. The quota table stores a pseudonymous key, the UTC day, a request count, and an expiration timestamp; it does not intentionally store the raw installation identifier or raw IP address in those quota rows.

The configured default makes quota rows eligible for automatic deletion after 48 hours, and the current infrastructure permits a configured period of up to 14 days. AWS Time to Live deletion is asynchronous, so removal can occur after the eligibility time rather than at an exact moment. Lambda operational logs currently have a configurable retention period of 7 to 90 days, with a 14-day default. The production values and treatment of network metadata in AWS service logs must be verified before launch.

## Purchases

Checkpoint uses Apple StoreKit for subscriptions. Purchases, billing, refunds, cancellation, and subscription management are handled by Apple. Checkpoint receives subscription entitlement information from StoreKit so the app can determine whether Free or Pro features should be available. Apple's handling of purchase information is governed by Apple's policies.

The current backend does not independently verify StoreKit entitlement before accepting caller-supplied question-bank targets or tier policies. Public production must verify current entitlement on the server and bind it to authenticated App Attest-backed requests; an app-reported plan or installation UUID is not sufficient proof.

## Tracking, Advertising, And Sale

Checkpoint does not use third-party advertising or Apple's advertising identifier in the current implementation. Checkpoint does not sell personal information. The final App Store privacy labels must be completed consistently with the production app and backend.

## Erasing Data

Using **Erase all data** in Checkpoint removes the local primary and backup learning snapshots, any legacy snapshot, goals and progress in memory, the App Group's Screen Time selection and coordination files, protection diagnostics, and the locally stored installation identifier. It also turns off Checkpoint-managed shields.

Erase all data does not cancel an Apple subscription and does not revoke the Screen Time permission granted in iOS Settings. It also does not currently call an authenticated backend deletion endpoint. Existing server-side question banks, ready and claimed generated questions, source context, idempotent claim records, pseudonymous quota rows, DynamoDB stream records, and already queued generation jobs can therefore remain and queued work can finish after local erasure. Question-bank records rely on their nominal 30-day Time to Live, quota rows rely on their shorter configured Time to Live, and both are deleted asynchronously by AWS after becoming eligible. DynamoDB stream records are available for up to 24 hours, source-queue messages for up to 4 days, and generation dead-letter jobs or outbox failure metadata for up to 14 days. Data already processed by AWS or Amazon Bedrock is subject to the production service-processing terms and retention settings that still need to be finalized.

Before the product claims that **Erase all data** erases remote data, implement an authenticated, ownership-checked backend deletion route; have the app call it before rotating/removing its installation credential; define retry behavior for offline erasure; and decide how failed deletion requests are surfaced and completed. The final policy and support process must also state whether users can request deletion of production backend or operational records beyond the in-app flow.

## Security

Checkpoint uses HTTPS for its configured backend and public legal links. Local state uses iOS file protection as described above. The backend quota and question-bank tables use encryption at rest, and the generation, generation dead-letter, and outbox failure queues use server-side encryption. No security measure can guarantee absolute protection. Production authentication and abuse controls, including App Attest-backed requests, replay protection, server-held identity state, and server-side StoreKit verification, must be completed and reflected in the final security review before public release.

## Children's Privacy And Age Rating

Checkpoint's intended audience, age-rating strategy, and any child-specific privacy obligations remain to be finalized before launch. Arbitrary user-created goals and AI-generated content must be included in that review.

## Contact

Support contact, support URL, privacy contact, operator legal name and address, applicable legal bases, user-rights process, and effective date: To be finalized before launch.
