# Bedrock Question Service

AWS Lambda backend for Checkpoint's AI question-generation contract. The iOS app sends goal context and question constraints; the service can infer a first-class assessment plan through `POST /v1/skill-maps/infer`, return a synchronous compatibility batch from `POST /v1/questions`, or enqueue an expiring server-side bank through `POST /v1/question-banks/ensure`. A DynamoDB Streams outbox consumer durably forwards pending jobs to SQS, and a separate SQS-triggered worker calls Amazon Bedrock, validates the output, and stores ready inventory for `POST /v1/question-banks/claim`. The JSON contract is documented in `../../docs/AI_BACKEND_CONTRACT.md`.

Generation is domain-general. Named-domain examples belong only to eval fixtures; production code has no LSAT, MCAT, language, coding, or other subject-specific question branches.

## Public-release security boundary

The checked-in bearer gate is for controlled development and TestFlight only. A shared token compiled into an iOS app can be extracted and is not a production identity mechanism. The HMAC quota keys added here protect stored identifiers from casual disclosure but do not make the caller-supplied install UUID trustworthy.

Before public App Store release:

- replace the shared bearer and install UUID identity on every synchronous and question-bank route with per-request App Attest assertions, server challenges, replay protection, and server-held key state
- validate StoreKit subscription status on the server before accepting caller-selected bank sizes, assigning paid quotas, or applying tier-specific bank policies
- keep server quotas, API Gateway throttles, reserved concurrency, alarms, and budgets enabled as independent cost controls

This service does not claim to implement App Attest or server-side StoreKit verification yet. The asynchronous routes therefore do not make the current bearer/install-ID boundary safe for public production and must remain behind the same controlled-development/TestFlight gate.

## Runtime and edge

- Python 3.12 Lambda
- Amazon Bedrock Converse through a least-privilege Lambda execution role
- DynamoDB atomic daily quota counters
- encrypted DynamoDB storage for expiring generation context, prepared questions, and idempotent claim state
- a DynamoDB Streams outbox recovery consumer with bounded retries and a separate encrypted failure queue
- an encrypted SQS generation queue, encrypted dead-letter queue, and a separately concurrency-limited worker
- API Gateway HTTP API with stage-level rate and burst throttles
- Lambda reserved concurrency as a cost and account-concurrency fuse
- CloudWatch Embedded Metric Format, alarms, explicit log retention, SNS alerts, and an optional Bedrock budget
- no public Lambda Function URL

## Runtime configuration

| Name | Default | Purpose |
| --- | --- | --- |
| `BEDROCK_MODEL_ID` | `amazon.nova-lite-v1:0` in local code | Model or inference-profile identifier/ARN passed to Converse. The SAM stack receives this separately as `BedrockModelArn`. |
| `BEDROCK_REGION` | `AWS_REGION` | Optional region override for the Bedrock Runtime client. DynamoDB uses `AWS_REGION` when present and otherwise falls back to this value. |
| `SKILL_MAP_MODEL_ID` | falls back to `BEDROCK_MODEL_ID` locally; `QuestionBankWorkerModelArn` in SAM | Model used only by synchronous skill-map planning. The deployed API intentionally uses the stronger asynchronous-worker model for this low-volume, quality-sensitive step while leaving legacy synchronous questions on `BEDROCK_MODEL_ID`. |
| `BEDROCK_FALLBACK_MODEL_ID` | empty | Optional secondary model ARN; enable only after it passes the same eval suite. |
| `BEDROCK_REASONING_EFFORT` | empty locally; `low` in the deploy workflow | Optional GPT-5.6 effort: `none`, `low`, `medium`, `high`, `xhigh`, or `max`. At `low` or higher the request sends the reasoning field and deliberately omits temperature/top-p sampling controls; `none` retains the configured temperature. Non-GPT-5.6 models ignore this setting. |
| `BEDROCK_TEMPERATURE` | `0.2` | Sampling temperature from 0 to 1 when reasoning is disabled or unsupported. GPT-5.6 requests at `low` or higher reasoning effort omit it. |
| `BEDROCK_GUARDRAIL_IDENTIFIER` | empty | Optional Guardrail ID. Must be paired with a version. |
| `BEDROCK_GUARDRAIL_VERSION` | empty | Optional numeric Guardrail version or `DRAFT`. |
| `MAX_QUESTIONS_PER_BATCH` | `20` | Per-request output-count ceiling. |
| `BEDROCK_MAX_TOKENS` | `6000` | Per-provider-call output-token ceiling. |
| `GENERATION_ATTEMPTS` | `5` locally, `3` in SAM | Maximum sanitized top-off passes. |
| `MAX_PROVIDER_CALLS_PER_REQUEST` | `6` | Hard budget across generation, JSON repair, and fallback calls. |
| `MAX_REQUEST_BODY_BYTES` | `131072` | Request-body ceiling enforced before quota consumption. |
| `BEDROCK_CONNECT_TIMEOUT_SECONDS` | `3` | Bounded SDK connection timeout. |
| `BEDROCK_READ_TIMEOUT_SECONDS` | `20` locally and in the synchronous API; `75` in the SAM worker | Bounded SDK read timeout. The asynchronous worker gets a longer model-response window without extending HTTP request latency. Values are capped at 100 seconds. |
| `QUESTION_BANK_GENERATION_CHUNK_SIZE` | `5` | Maximum questions requested per asynchronous worker job, capped at 20. The durable job chain continues until the bank reaches its full target. |
| `MIN_PROVIDER_REMAINING_MILLISECONDS` | `26000` | Refuses another provider call unless remaining Lambda time exceeds connect timeout + read timeout + a 2-second safety allowance. |
| `CHECKPOINT_BACKEND_TOKEN` | empty | Temporary shared bearer for internal/TestFlight builds. Empty fails closed outside explicit development mode. |
| `ALLOW_UNAUTHENTICATED_BACKEND` | `false` | Explicit development-only bypass. Ignored for TestFlight/production environments. |
| `DEPLOYMENT_ENVIRONMENT` | `development` locally | `development`, `testflight`, or `production`. |
| `SERVICE_MODE` | `enabled` | `enabled`, `drain`, or `disabled`. Drain rejects new API work while workers finish the durable queue. Disabled also pauses the worker's SQS event source so queued messages retain their retry budget until the service is re-enabled. |
| `SERVICE_RETRY_AFTER_SECONDS` | `300` | `Retry-After` value returned by the kill switch. |
| `PROVIDER_RETRY_AFTER_SECONDS` | `30` | `Retry-After` value returned for provider and unexpected generation failures, capped at 3,600 seconds. |
| `RATE_LIMIT_TABLE_NAME` | empty locally | DynamoDB table. SAM always configures it and sets `REQUIRE_RATE_LIMITING=true`. |
| `QUOTA_HASH_SECRET` | none | Server-only HMAC key, at least 32 characters, used to pseudonymize quota identifiers. |
| `MAX_REQUESTS_PER_INSTALL_PER_DAY` | `40` | Daily generation requests per pseudonymized install value. |
| `MAX_REQUESTS_PER_IP_PER_DAY` | `400` | Daily generation requests per pseudonymized source IP. |
| `RATE_LIMIT_RETRY_AFTER_SECONDS` | `3600` | `Retry-After` value returned when a daily generation quota is exhausted, capped at 86,400 seconds. |
| `RATE_LIMIT_TTL_SECONDS` | `172800` | Nominal quota-record TTL. DynamoDB deletion after expiry is asynchronous. |
| `QUESTION_BANK_TABLE_NAME` | none locally | DynamoDB table containing expiring question-bank metadata, validated generation context, ready questions, and claim records. SAM configures it for the API, outbox consumer, and worker. |
| `QUESTION_BANK_QUEUE_URL` | none locally | SQS queue used by `ensure`, the stream outbox consumer, and the worker when more inventory is needed. SAM configures it for all three functions. |
| `QUESTION_BANK_TTL_SECONDS` | `2592000` | Nominal 30-day lifetime for question-bank records. DynamoDB TTL deletion is asynchronous and is not an exact deletion deadline. |
| `QUESTION_BANK_MAX_RECEIVE_COUNT` | `5` | Shared SQS redrive, per-job generation-attempt, and terminal-failure threshold. |
| `QUESTION_BANK_FAILURE_COOLDOWN_SECONDS` | `300` | Earliest retry time recorded after a question-bank job reaches terminal failure. |
| `EMIT_STRUCTURED_METRICS` | on in Lambda | Emits privacy-safe request and provider metrics in CloudWatch EMF. |

For `deepseek.v3.2` and `moonshotai.kimi-k2.5`, the runtime sends `thinking.type=disabled` as a model-specific additional request field. This simple structured-generation workload retains the configured temperature while avoiding unnecessary reasoning latency and tokens. GPT-5.6 continues to use only its separate `reasoning_effort` field, and other models receive neither override.

## Request hardening

The service authenticates first, then fully decodes and validates the request before consuming quota. It enforces:

- UTF-8 JSON and a configurable byte ceiling
- explicit limits for goal, focus, level, directive, topic, prompt, answer, choice, and competency fields
- UUID, name, objective, map-size, map-revision, and desired-allocation validation for structured skill maps
- an optional top-level `sourceDocuments` array of `{ "name": "...", "text": "..." }` objects; existing clients may omit it
- at most 5 source documents, 160 characters per normalized name, and 24,000 normalized source-text characters across the request
- deterministic source truncation that shares the context budget across documents and samples the beginning, middle, and end of over-budget text
- bounded list sizes and a server-side question-count cap
- a provider-call budget shared by initial, repair, top-off, and fallback attempts
- remaining-Lambda-time checks before another provider invocation
- bounded botocore timeouts and exactly one total SDK attempt, so every network attempt consumes one provider-call budget slot

Source documents are accepted as extracted UTF-8 text, not binary uploads or base64 file bodies. Empty text, malformed objects, oversized names, non-array input, and more than five documents return `400` before quota consumption. Document text is whitespace/control-character normalized and then truncated within the fixed context budget rather than rejecting an otherwise usable upload.

When source context is present, the assessment prompt treats it as the primary content scope, requires source-supported answers and self-contained question stems, and explicitly treats document names and contents as untrusted evidence rather than instructions. Outlines and syllabi may scope reliable subject knowledge, but the model is told not to claim unsupported details came from a source or infer content omitted by truncation.

Synchronous `/v1/questions` and `/v1/skill-maps/infer` install and IP limits are consumed in one DynamoDB transaction. A rejected transaction cannot consume one counter without the other. Asynchronous worker passes consume a separate pseudonymous install-only counter before Bedrock; the compact SQS job deliberately does not retain the request IP. API Gateway throttling remains the edge control for `ensure` and `claim`. Deployments configured with `REQUIRE_RATE_LIMITING=true`, or marked `production`, fail closed if the table or HMAC secret is missing.

## Skill-map inference and tagged questions

`POST /v1/skill-maps/infer` is an authenticated, quota-limited synchronous planning call. It accepts goal context, optional competency/source context, and zero to six user suggestions:

```json
{
  "goal": {
    "title": "Become confident with personal finance",
    "learningTarget": "Personal finance",
    "focusAreas": "budgeting and long-term investing",
    "currentLevel": "beginner"
  },
  "suggestedSkills": ["Budgeting"],
  "competencies": [],
  "sourceDocuments": []
}
```

It asks the configured `SKILL_MAP_MODEL_ID` for three to six distinct skills and two to five assessable objectives per skill. Skill names are limited to 48 characters and cannot contain commas or semicolons; objective names are limited to 80 characters. These rules match the iOS persistence contract without truncation or client-only rejection. Supplied suggestions must satisfy the same skill-name rules and remain recognizably represented; the model completes the rest of a broad map and creates objectives for suggested skills. The server validates the structure and assigns deterministic UUIDv5 identifiers derived from canonical skill and objective names. Repeating an equivalent result therefore produces the same IDs. New maps return:

```json
{
  "skillMap": {
    "version": 1,
    "skills": [
      {
        "id": "d4cde937-1aa7-59c6-a9c8-6a7d537384aa",
        "name": "Budgeting",
        "objectives": [
          {
            "id": "18186747-a3dd-5370-8680-7695e69650df",
            "name": "Classify fixed and variable expenses"
          }
        ]
      }
    ]
  }
}
```

The example is abbreviated; a real inference response always has the minimum skill and objective counts. The response version is `1` for a newly inferred map. Question and bank requests may send a later positive `skillMap.version` after user edits, and the backend preserves that revision. They may also send a user-added skill with an empty `objectives` array; generation then requires a concrete objective label and derives a deterministic objective UUID tied to that skill ID.

`POST /v1/questions` and `POST /v1/question-banks/ensure` accept the optional top-level `skillMap` plus a desired distribution. The canonical Swift-safe allocation wire shape is:

```json
{
  "desiredSkillAllocation": [
    {"skillID": "d4cde937-1aa7-59c6-a9c8-6a7d537384aa", "count": 12}
  ]
}
```

A UUID-keyed JSON object is accepted for non-Swift callers as a compatibility convenience. Despite the wire field name `count`, each value is a stable relative **weight for the entire durable bank target**, not the client's current local deficit and not a count for the next generation call. Values may be 0 through 100, their sum need not equal `desiredCount`, and a zero or omitted skill receives no target when any explicit positive weights are present. Unknown, duplicate, malformed, or all-zero allocations return `400`.

The worker resolves the stable weights against the server's `desiredCount`, reserves at least one maintenance slot for every positive-weight skill, measures finite-bank history or replenishing ready inventory as appropriate, and derives short-lived per-batch counts from the remaining server-side deficits. A durable bank therefore continues replenishing a small positive-weight skill after its ready question is claimed. Repeated `ensure` calls for the same `contextRevision` must send the same weight map; changing the weights requires a new context revision and bank, rather than recomputing weights from the app's local inventory. A bank target smaller than its number of positive-weight skills returns `400` because it cannot preserve that maintenance guarantee.

The legacy synchronous `/v1/questions` route has no durable inventory; when it receives the field, it applies the same weights only across that one requested batch.

Every accepted map-aware question returns `skillID`, `objectiveID`, and `objective`; `topic` remains populated with the canonical skill name for legacy UI and coverage logic. Provider IDs are never trusted blindly. The sanitizer resolves matching topic/objective names and any supplied IDs against the request map, assigns the request's canonical IDs, and drops missing, conflicting, or off-map items. Requests without `skillMap` keep the existing topic-only contract unchanged.

## Durable asynchronous question banks

`POST /v1/question-banks/ensure` accepts the normal generation request plus the client-computed `contextRevision`, `desiredCount`, and `lowWatermark`. It authenticates and validates the request, derives an opaque bank identifier scoped to the pseudonymized installation and goal context, persists the validated generation context, and uses a DynamoDB transaction to atomically link the bank to a pending outbox job when inventory needs replenishment. It returns `202` with `bankID`, `status`, `readyCount`, and `targetCount`; it does not wait for Bedrock.

`lowWatermark=0` means a finite bank: the server tracks cumulative accepted generation and stops permanently for that bank revision once it reaches `desiredCount`. Claims reduce ready inventory but do not reset that cumulative ceiling, and repeated `ensure` polling cannot replenish it. A positive watermark remains available as the general server contract for ongoing replenishment toward `desiredCount`; claiming down to or below that watermark schedules another refill. The current client uses finite per-revision banks for both tiers: 40 questions for Free and 80 for Pro. A changed adaptive context revision creates a newly weighted finite bank instead of refilling the prior revision indefinitely. Those tier inputs are still caller-supplied today, so public production must derive or authorize them from server-verified StoreKit entitlement rather than trusting the app.

After the transaction commits, the API makes an immediate best-effort delivery and the table's `NEW_IMAGE` DynamoDB Stream independently invokes the outbox consumer. The consumer recognizes pending job records, re-reads their current state, sends a compact SQS message when still needed, and conditionally marks the job sent. This closes the crash window between committing the job and sending it to SQS. DynamoDB Streams and SQS are both at-least-once systems, so the direct and stream senders can race and duplicate messages are expected. Stable job IDs, a conditional processing lease, and an atomic per-job provider-attempt counter keep those duplicates within the configured generation bound.

The queue body contains only an opaque pseudonymous bank partition key, job ID, and context version. The complete generation context stays in the encrypted DynamoDB table. The worker reads one message per invocation, generates at most the configured chunk size (five by default), validates and stores accepted questions, and enqueues another job until the target is satisfied. A five-question chunk matches one app session and avoids the latency and quality degradation observed in oversized model batches. Replaying a completed message repairs a crash between committing one batch and scheduling the next. Claims may safely reduce ready inventory while a refill is running; the commit still conditions on the active goal revision, tier policy, and generated counter. A failed generation message is retried and moves to the generation dead-letter queue after the configured receive threshold (five by default). The same threshold caps provider calls for the logical job across duplicate deliveries. If duplicates exhaust that logical cap before one message reaches its own redrive threshold, the bank is terminally failed, remaining duplicates are acknowledged instead of multiplying dead-letter entries, and the worker emits provider-failure/error metrics. The 120-second worker timeout is paired with a 720-second queue visibility timeout, meeting the six-times-timeout safety margin.

The outbox stream mapping filters for queued job images with pending delivery, processes small batches, reports individual failed records, bisects failed batches, and retries each record at most five times while it is at most 24 hours old. When Lambda discards an exhausted invocation, the separate encrypted outbox failure queue receives invocation metadata such as the stream ARN, shard ID, and sequence-number range—not the original DynamoDB stream image or job key. This bound prevents a poison stream record from blocking a shard indefinitely, and the visible metadata message raises an alarm.

Outbox recovery must begin before the original 24-hour stream record expires whenever possible. Keep the failure message, diagnose the root cause, then use its `DDBStreamBatchInfo` shard and sequence range to retrieve the original stream record. Read the referenced JOB and META items; verify the job is still `status=queued` and `enqueueStatus=pending`, and that META still names its job ID in `activeJobID` with the same context revision. After remediation, conditionally update only that job's `updatedAt` while requiring the same queued/pending state; the resulting stream event safely retries delivery. Confirm that the item reaches `enqueueStatus=sent` before deleting the failure message. If the original stream record has expired, the metadata cannot reconstruct the job key: scan the bank table for queued/pending JOB items and apply the same validation and conditional re-touch to each active item. Replaying is duplicate-safe, but deleting metadata before confirming delivery can strand a job until another ensure/claim recovery attempt.

`POST /v1/question-banks/claim` accepts `bankID`, `claimID`, and a limit of at most 20. It returns `200` with already-prepared questions and the current status/counts without invoking Bedrock in the HTTP request path. Clients should persist a claim ID until its response is durably written locally, then use a new claim ID for the next claim. The server stores a SHA-256-derived claim key and the exact response so retrying that claim is idempotent; replaying a queued claim also retries best-effort refill scheduling. Claimed QUESTION rows are marked as claimed rather than deleted and remain as deduplication history until their nominal bank TTL expires. Status is one of `queued`, `processing`, `ready`, or `empty`. A retry or rate-limit cooldown remains `queued`; `empty` means no inventory or delayed generation remains for that finite bank, so a client can stop polling even if local validation left it below the nominal target.

The server queue removes app-lifecycle dependence, but it does not promise a fixed completion time: Lambda throttling, SQS retries, Bedrock capacity, the kill switch, or a dead-lettered job can delay replenishment. The app must keep a local ready reserve, poll with backoff, and continue serving accepted local questions while a refill is pending.

The deployed question-bank operations are `POST ensure` and `POST claim`; there is no authenticated remote-bank deletion route yet. Add one before claiming that in-app **Erase all data** immediately removes server-side question-bank records.

## Safety behavior

When both runtime Guardrail settings are present, every Converse request includes the configured Bedrock Guardrail. The SAM template additionally requires the identifier, version, and IAM ARN as an all-three-or-none set. A `guardrail_intervened` stop reason returns:

```json
{"error":"This request could not be processed safely.","code":"safety_intervention"}
```

The status is `422`. Unsafe content is not sent to JSON repair, another generation pass, or the fallback model. In asynchronous generation, the job and its exact bank revision are terminally blocked instead of entering SQS retry or refill loops; a changed context revision creates a separate bank. Supplying only a runtime Guardrail identifier or version fails closed with `503`. A production stack cannot pass CloudFormation parameter validation without a complete Guardrail configuration plus operations and budget alert emails.

Guardrails are an additional runtime control. The deterministic sanitizers and adversarial eval fixtures remain required.

## Deployment and operations

- [Deployment guide](docs/DEPLOYMENT.md): SAM parameters, model setup, IAM, and protected workflow behavior.
- [Operations guide](docs/OPERATIONS.md): service controls, monitoring, retention, privacy, and local verification.

## Response statuses

- `200`: sanitized question batch
- `200`: inferred and validated skill map
- `200`: question-bank claim response
- `202`: question-bank ensure accepted or already in progress
- `400`: malformed or oversized request
- `401`: missing/incorrect internal bearer
- `404`: requested question bank is absent or expired
- `409`: the bank no longer matches the submitted goal context
- `410`: the requested bank was deleted or superseded
- `422`: Bedrock Guardrail intervention; do not retry unchanged content
- `429`: daily quota or API/Lambda throttle; honor `Retry-After` when supplied
- `502`: provider or response-processing failure; retry after the supplied delay
- `503`: kill switch or fail-closed deployment configuration

The service drops duplicate/reported prompts, repeated answer sets, generic filler, off-target study-strategy prompts, below-difficulty items, malformed choices, and unsafe Guardrail-intervened output. The iOS app still applies its own validation before persisting questions.
