# Server Question Reserve

Checkpoint's local question bank remains the latency boundary for every shield-triggered checkpoint. The optional server reserve adds one bounded, pre-generated batch for a Pro goal so question generation can continue while the iOS process is absent. It does not continuously generate on a timer and it does not replace the local bank.

## Product Contract

- The feature is opt-in because it retains a limited goal snapshot and generated questions on the backend.
- It is a Pro continuity feature. Starter keeps its one-time local bank and does not request ongoing server refills.
- Each opted-in Pro goal requests at most 20 prepared server questions.
- The server generates only a real deficit. Time passing by itself never creates another batch.
- The app pulls when either the usable local bank is below two normal sessions or the never-asked reserve is below one session.
- A pulled delivery remains stable until the app durably stores it and acknowledges its delivery ID.
- A goal edit, consent withdrawal, downgrade, or reset invalidates stale work before it can enter the local bank.

## Request Lifecycle

1. The app creates a random installation ID and a 256-bit reserve secret locally.
2. The secret is saved in Keychain with `AfterFirstUnlockThisDeviceOnly` accessibility before registration is attempted.
3. `POST /reserve/register` conditionally stores only the secret's SHA-256 hash. Repeating the same registration is safe; a different secret cannot rotate an existing installation.
4. `POST /reserve/sync` sends a bounded generation request, goal revision, monotonic sync sequence, and desired reserve count.
5. The API conditionally advances the stored sequence and queues one revision-and-epoch job when the prepared-plus-held count is below the desired count.
6. An SQS worker atomically acquires a lease before invoking Bedrock. Duplicate messages and recovery sweeps therefore produce at most one provider operation for that refill epoch.
7. The worker sanitizes the result with the same production question rules and commits only if the lease and goal revision are still current. A usable partial result is retained and its remaining deficit is returned to the recovery index for a bounded top-off.
8. `POST /reserve/pull` atomically moves prepared questions into one held delivery, or returns the existing held delivery unchanged.
9. The app rechecks the active goal revision, merges stable server question IDs through local duplicate and difficulty filters, and persists the snapshot.
10. Only after a successful local save does `POST /reserve/ack` clear the matching held delivery and create the next deficit epoch.

The app persists a pending acknowledgement in the same snapshot as the delivered questions. It may safely repeat pull or acknowledgement after a crash, relaunch, or network failure; stable question and delivery IDs prevent duplicate local records.

## Recovery And Cost Boundaries

- One EventBridge schedule runs every 15 minutes as a recovery sweep; it is not a per-user schedule.
- SQS messages contain identifiers, revision, epoch, and lease context only. Goal text, prompts, answers, and reports remain in DynamoDB and never enter queue messages or application logs.
- Queued and generating states have expiring leases so a process crash or failed SQS send cannot strand a goal forever.
- Consecutive failures use backoff and stop automatically after a bounded attempt count until question-shaping input changes in a later authenticated sync.
- A worker-side per-install daily generation quota is checked atomically before Bedrock.
- A held delivery counts toward the desired reserve, so pulling cannot cause an extra generation batch before acknowledgement.
- The stored generation request is capped well below DynamoDB's 400 KB item limit. Questions use a compact wire form and never store the app's repeated `sourcePrompt` diagnostic string.
- A bounded delivered-coverage history prevents the server from regenerating its own recently acknowledged questions before the next client sync.

## Revision And Concurrency Rules

- `goalRevision` changes whenever question-shaping context changes, including subject, current level, difficulty floor, or question style.
- `syncSequence` is monotonic for one installation. A lower sequence is rejected. Repeating the same sequence and digest is idempotent; reusing a sequence with different content is rejected.
- `refillEpoch` advances whenever acknowledgement or a desired-count change creates legitimate work under the same goal revision.
- A worker commit is conditional on installation, goal, revision, refill epoch, and lease token.
- Pull and acknowledgement are conditional on the exact revision and delivery ID. A stale acknowledgement cannot clear a newer delivery.

## Privacy And Retention

The reserve stores only what is needed to generate and deliver the bounded batch:

- anonymous installation ID and hashed reserve secret
- goal ID, question-generation context, competencies, bounded freshness history, and revision metadata
- compact prepared or held questions
- bounded recent delivered coverage
- job state, quotas, timestamps, and failure counters

It does not store Screen Time selections, unlock events, purchase records, or the learner's full answer history. Active records use TTL-based expiry. Disabling the feature or resetting Checkpoint makes an authenticated deletion request; TTL is the fallback when the device cannot reach the service. Public release still requires final retention language, App Store privacy-label review, strict registration/IP quotas, and consideration of App Attest before broad scale.

## Release Verification

- Register retry with a lost response cannot rotate or orphan the secret.
- Wrong install secrets return the same generic authorization failure.
- An old sync cannot overwrite a newer goal revision.
- Duplicate worker and sweep events produce one Bedrock operation.
- A goal edit or zero-reserve sync during generation prevents the old result from committing.
- Provider failures stop at the configured retry and daily-cost limits.
- Pull is byte-for-byte stable until acknowledgement.
- A stale acknowledgement cannot remove a newer delivery.
- A failed local save sends no acknowledgement.
- Re-pulling after save-before-ack creates no local duplicates.
- A low fresh reserve triggers delivery even when review questions keep the total count above the low-bank threshold.
- Downgrade, opt-out, and reset stop future work and remove retained goal data; a persisted Starter launch retries an interrupted downgrade purge.
- Worst-case UTF-8 request and question batches remain below transport and DynamoDB limits.
