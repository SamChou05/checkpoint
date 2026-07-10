# Bedrock Question Service

Small AWS Lambda backend for Checkpoint's AI question generation contract. The iOS app sends goal context and question constraints to this endpoint; the Lambda calls Amazon Bedrock, validates the model output, and returns the same JSON shape documented in `docs/AI_BACKEND_CONTRACT.md`.

This keeps AWS credentials out of the iOS app.

## Runtime

- Python 3.12 Lambda
- Amazon Bedrock Runtime through the Lambda execution role
- No vendored dependencies required for the first version; AWS Lambda includes `boto3`

## Environment

| Name | Default | Purpose |
| --- | --- | --- |
| `BEDROCK_MODEL_ID` | `amazon.nova-lite-v1:0` | Bedrock model ID to call through the Converse API. |
| `BEDROCK_FALLBACK_MODEL_ID` | `amazon.nova-micro-v1:0` | Secondary model used if the primary model invocation or JSON parsing fails. |
| `MAX_QUESTIONS_PER_BATCH` | `20` | Caps per-call output cost even if the app requests a larger bank. |
| `BEDROCK_MAX_TOKENS` | `6000` | Maximum Bedrock response tokens. |
| `BEDROCK_TEMPERATURE` | `0.35` | Lower temperature keeps answers more stable. |
| `GENERATION_ATTEMPTS` | `3` | Sanitized top-off passes within one request. Values above 3 are clamped. All passes share a hard three-call Bedrock budget. |
| `CHECKPOINT_BACKEND_TOKEN` | empty | Bearer token gate for Function URL testing and TestFlight. If empty, requests are rejected unless `ALLOW_UNAUTHENTICATED_BACKEND=true`. |
| `ALLOW_UNAUTHENTICATED_BACKEND` | `false` | Explicit local/private opt-in for running without a bearer token. Keep `false` for exposed Function URLs. |
| `CORS_ALLOW_ORIGIN` | `*` | Function URL CORS origin. |
| `RATE_LIMIT_TABLE_NAME` | empty | Optional DynamoDB table used for daily install/IP quotas. |
| `MAX_REQUESTS_PER_INSTALL_PER_DAY` | `40` | Daily backend generation calls per anonymous app install ID. |
| `MAX_REQUESTS_PER_IP_PER_DAY` | `400` | Daily backend generation calls per source IP. |
| `RATE_LIMIT_TTL_SECONDS` | `172800` | Time before quota counter records expire. |
| `RESERVE_TABLE_NAME` | empty | DynamoDB table that stores hashed install credentials and one bounded reserve batch per goal. Configured by SAM in deployed stacks. |
| `RESERVE_QUEUE_URL` | empty | SQS queue used by the reserve worker. Configured by SAM in deployed stacks. |
| `RESERVE_TTL_SECONDS` | `2592000` | Sliding retention period for install and goal reserve records (30 days). |
| `MAX_RESERVE_BATCHES_PER_INSTALL_PER_DAY` | `4` | Atomic worker-side daily Bedrock batch cap per install. |

## Deploy With AWS SAM

```bash
cd backend/bedrock-question-service
sam build
sam deploy --guided
```

Suggested guided values:

- Region: same region where the selected Bedrock model is enabled.
- `BedrockModelId`: start with `amazon.nova-lite-v1:0` for stronger instruction following and answer consistency.
- `BedrockFallbackModelId`: keep `amazon.nova-micro-v1:0` enabled so primary invocation or malformed output can recover without failing the app.
- `MaxQuestionsPerBatch`: `20` for early cost control.
- `MaxRequestsPerInstallPerDay`: `40` is generous because the app generates cached batches, not one request per unlock.
- `MaxRequestsPerIPPerDay`: `400` covers shared networks while limiting obvious scraping.
- `MaxReserveBatchesPerInstallPerDay`: `4` permits up to 80 prepared questions per UTC day while containing queue-worker cost.
- `BackendToken`: set a long random value for internal TestFlight testing.
- `AllowUnauthenticatedBackend`: keep `false` for exposed Function URLs.

The deployed stack outputs `QuestionEndpoint`. Configure the iOS app to use that URL as its internal AI backend endpoint.

## IAM

`template.yaml` grants Bedrock invoke permissions to the HTTP and reserve-worker roles, scoped DynamoDB access for rate and reserve state, and scoped SQS access. It uses `Resource: "*"` for Bedrock because model and inference-profile ARNs vary by model and region; tighten this after choosing the exact production model/inference profile. Both DynamoDB tables and both SQS queues explicitly enable AWS-managed encryption at rest.

## Cost Controls

- The app caches generated batches and does not call AI on every blocked-app attempt.
- This service caps the requested batch size with `MAX_QUESTIONS_PER_BATCH`.
- Each HTTP request can make at most three Bedrock Converse calls total, including malformed-JSON repair, fallback-model, and short-batch top-off calls. This keeps retries within the Lambda's 30-second execution envelope.
- Request bodies over 256 KiB are rejected. Normalized model input is capped at 48,000 characters; when history is larger, only the oldest model context is pruned while server-side duplicate validation still uses the full normalized history.
- When `RATE_LIMIT_TABLE_NAME` is configured, the service also applies daily limits using `X-Checkpoint-Install-ID` and source IP counters.
- Reserve generation is capped at one held/prepared batch of at most 20 questions per goal. It never generates merely because time passed.
- The reserve worker atomically applies a separate per-install UTC-day batch quota immediately before Bedrock invocation. Provider failures back off exponentially and become terminal after five consecutive attempts until materially changed goal input is synced.
- API Gateway or Lambda Function URL throttling should be enabled before broader TestFlight.
- Keep `CHECKPOINT_BACKEND_TOKEN` set for early testing if you expose a Function URL directly. Empty tokens fail closed unless `ALLOW_UNAUTHENTICATED_BACKEND=true` is explicitly configured.

## Local Tests

The tests inject a fake Bedrock client, so no AWS credentials are needed.

```bash
cd backend/bedrock-question-service
python3 -m unittest discover -s tests
```

## Request/Response

The request and response match `docs/AI_BACKEND_CONTRACT.md`. The service additionally sanitizes provider output before returning it:

- drops duplicate or reported prompts
- accepts bounded structured report reasons and learner notes as prompt-quality signals
- accepts optional bounded answer choices, keyed answer, explanation, topic, subtopic, avenue, and difficulty context with a structured report, so `Wrong Answer` and `Confusing` reports can be diagnosed instead of treated as prompt-only labels
- treats prompts inside structured feedback as reported prompts even when the legacy `reportedPrompts` field is omitted
- rejects conservative token-overlap near-duplicates against prompt history, structured coverage, and the current batch
- accepts optional `{topic, avenue}` coverage-plan slots and carries only unfilled slots into a top-off attempt
- returns concrete `subtopic` and allowlisted `avenue` metadata, with safe defaults for legacy provider responses
- drops study-strategy prompts for non-study-skill goals
- repairs answer choices by inserting `expectedAnswer` when needed
- enforces four meaningfully distinct choices
- rejects questions below the requested difficulty and enforces the 1-through-5 range
- rejects prompt text over 280 characters
- may return a nonempty partial batch with `200` after sanitization or retry-budget exhaustion; clients should keep the usable questions and refill the remaining deficit
- returns `502` only if Bedrock output has no usable questions, allowing the iOS app to use its configured failure path

## Background Question Reserve

The root `POST` remains the synchronous generation contract. Five path-routed reserve calls add an optional server-prepared batch without putting latency on the checkpoint flow:

- `POST /reserve/register`
- `POST /reserve/sync`
- `POST /reserve/pull`
- `POST /reserve/ack`
- `POST /reserve/delete`

Every route retains the configured bearer-token gate. The client also generates a high-entropy per-install secret and sends it with `X-Checkpoint-Install-ID` and `X-Checkpoint-Install-Secret`. Register conditionally stores only the SHA-256 secret hash; retrying the same install and secret renews its TTL, while a different secret receives `409`. The plaintext secret is never returned or persisted by the backend. Clients should idempotently register during normal launch maintenance so an active installation renews this TTL.

`/reserve/sync` accepts:

```json
{
  "goalID": "stable-goal-id",
  "goalRevision": "stable-goal-content-revision",
  "syncSequence": 7,
  "desiredReserveCount": 20,
  "generationRequest": { "goal": {}, "targetCount": 20, "minimumDifficulty": 3 }
}
```

`syncSequence` must increase monotonically. An equal sequence with the same server-computed request digest is an idempotent retry; an older sequence or equal sequence with different content receives `409`. `desiredReserveCount` is capped at 20. Sending `0` purges that goal's request, prepared questions, held delivery, and pending work while retaining minimal TTL-bound metadata.

`/reserve/pull` accepts `{ "goalID": "...", "goalRevision": "..." }` and returns either:

```json
{"state":"queued","preparedCount":0,"delivery":null}
```

or a held delivery:

```json
{
  "state": "delivering",
  "preparedCount": 20,
  "delivery": {
    "deliveryID": "uuid",
    "goalRevision": "revision",
    "questions": [{"reserveQuestionID":"uuid","prompt":"..."}]
  }
}
```

Repeated pulls return the same held delivery until `/reserve/ack` receives the matching goal revision and delivery ID. Stale or duplicate acknowledgements are successful no-ops and cannot clear a newer delivery. Acknowledged compact coverage is merged into bounded duplicate history before the next refill. `/reserve/delete` accepts `{ "goalIDs": ["..."] }` (maximum five) and idempotently removes only those goal records; the install auth hash remains for other goals until its TTL.

SQS messages contain only DynamoDB keys, goal revision, and job version. Conditional record/job/lease versions make duplicate delivery safe. The worker stores a maximum of one batch, assigns stable `reserveQuestionID` values, and never stores app-only `sourcePrompt` data. An EventBridge Scheduler sweep every 15 minutes queries a `KEYS_ONLY` due-work index solely to reclaim expired queue/worker leases or retry an elapsed backoff; it does not create new time-based work.

This install-secret layer is appropriate for a bounded TestFlight/private slice but is not a replacement for user identity. Before a public release, validate authenticated account ownership and membership server-side, define explicit retention/deletion policy, and add App Attest as an additional abuse signal.
