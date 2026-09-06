# Bedrock Question Service

AWS Lambda backend for Checkpoint's AI question-generation contract. The iOS app sends goal context and question constraints; the service can infer a first-class assessment plan through `POST /v1/skill-maps/infer`, advance mastered nodes through `POST /v1/skill-maps/evolve`, return a synchronous compatibility batch from `POST /v1/questions`, or enqueue an expiring server-side bank through `POST /v1/question-banks/ensure`. A DynamoDB Streams outbox consumer durably forwards pending jobs to SQS, and a separate SQS-triggered worker calls Amazon Bedrock, validates the output, and stores ready inventory for `POST /v1/question-banks/claim`. The JSON contract is documented in `../../docs/AI_BACKEND_CONTRACT.md`.

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
| `BEDROCK_VERIFICATION_MODEL_ID` | `us.anthropic.claude-sonnet-4-6` locally; explicit `BedrockVerificationModelArn` in SAM | Separate option-blind solver and answer-blind final reviewer. Every new bank question needs a supported solution and agreement on its answer; no subject-specific proof branch is used. |
| `BEDROCK_FALLBACK_MODEL_ID` | empty | Optional secondary model ARN; enable only after it passes the same eval suite. |
| `BEDROCK_REASONING_EFFORT` | empty locally; `low` in the deploy workflow | Optional GPT-5.6 effort: `none`, `low`, `medium`, `high`, `xhigh`, or `max`. At `low` or higher the request sends the reasoning field and deliberately omits temperature/top-p sampling controls; `none` retains the configured temperature. Non-GPT-5.6 models ignore this setting. |
| `BEDROCK_TEMPERATURE` | `0.2` | Sampling temperature from 0 to 1 when reasoning is disabled or unsupported. GPT-5.6 requests at `low` or higher reasoning effort omit it. |
| `BEDROCK_GUARDRAIL_IDENTIFIER` | empty | Optional Guardrail ID. Must be paired with a version. |
| `BEDROCK_GUARDRAIL_VERSION` | empty | Optional numeric Guardrail version or `DRAFT`. |
| `MAX_QUESTIONS_PER_BATCH` | `20` | Per-request output-count ceiling. |
| `BEDROCK_MAX_TOKENS` | `6000` | Per-provider-call output-token ceiling. |
| `GENERATION_ATTEMPTS` | `5` locally, `3` in SAM | Maximum sanitized top-off passes. |
| `MAX_PROVIDER_CALLS_PER_REQUEST` | `6` | Hard budget across generation, answer-blind review, JSON repair, and fallback calls. |
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
| `MAX_REQUESTS_PER_INSTALL_PER_DAY` | `40` | Daily synchronous generation requests per pseudonymized install and, in a separate counter namespace, asynchronous Bedrock calls per install. |
| `MAX_REQUESTS_PER_IP_PER_DAY` | `400` | Daily generation requests per pseudonymized source IP. |
| `RATE_LIMIT_RETRY_AFTER_SECONDS` | `3600` | `Retry-After` value returned when a daily generation quota is exhausted, capped at 86,400 seconds. |
| `RATE_LIMIT_TTL_SECONDS` | `172800` | Nominal quota-record TTL. DynamoDB deletion after expiry is asynchronous. |
| `QUESTION_BANK_TABLE_NAME` | none locally | DynamoDB table containing expiring question-bank metadata, validated generation context, ready questions, and claim records. SAM configures it for the API, outbox consumer, and worker. |
| `QUESTION_BANK_QUEUE_URL` | none locally | SQS queue used by `ensure`, the stream outbox consumer, and the worker when more inventory is needed. SAM configures it for all three functions. |
| `QUESTION_BANK_TTL_SECONDS` | `2592000` | Nominal 30-day lifetime for question-bank records. DynamoDB TTL deletion is asynchronous and is not an exact deletion deadline. |
| `QUESTION_BANK_MAX_RECEIVE_COUNT` | `6` | Shared SQS redrive and actual per-job Bedrock Converse-call threshold. Six permits two complete author/solve/review passes, subject to the existing deadline and daily quota. |
| `QUESTION_BANK_MAX_FAILED_GENERATION_JOBS` | `3` | Exhausted jobs retained per bank context before generation is terminally blocked. Only a new bank/fill-cycle context resets this ledger. |
| `QUESTION_BANK_FAILURE_COOLDOWN_SECONDS` | `300` | Earliest retry time recorded after a question-bank job reaches terminal failure. |
| `EMIT_STRUCTURED_METRICS` | on in Lambda | Emits privacy-safe request and provider metrics in CloudWatch EMF. |

Reasoning is configurable independently of ordinary response length. `BEDROCK_KIMI_THINKING=enabled` enables Kimi K2.5 thinking with temperature 1.0 and top-p 0.95; `disabled` preserves ordinary sampling. For Claude Sonnet/Opus 4.6, `BEDROCK_CLAUDE_THINKING=adaptive` sends adaptive thinking and `BEDROCK_CLAUDE_EFFORT` (`low`, `medium`, or `high`, default `high`) while omitting customized sampling. Both switches initially default to `disabled` for controlled comparisons. Unknown values fail before invoking a model. DeepSeek retains its disabled-thinking setting, and GPT-5.6 retains its separate reasoning-effort configuration.

Enabled Kimi/Claude thinking uses `BEDROCK_THINKING_MAX_TOKENS` (default 16000, capped at 16384) for reasoning plus final output. Ordinary responses retain `BEDROCK_MAX_TOKENS` (default 6000, capped at 16384). These settings are wired through SAM and deployment variables. The runtime rejects token-truncated output even when a fragment parses, and emits bounded `QuestionQuality` counters for sanitization, answer review, and provider failures without learner text. Increasing a budget does not establish correctness: selected live baseline reviews ended normally below 6000 tokens and still accepted invalid answers.

Provider references: [Moonshot model usage](https://github.com/MoonshotAI/Kimi-K2.5), [Bedrock adaptive thinking](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-adaptive-thinking.html), and [Bedrock Kimi model limits](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-moonshot-ai-kimi-k2-5.html). Confirm exact model access and measured latency before selecting a deployment configuration.

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

Synchronous `/v1/questions`, `/v1/skill-maps/infer`, and `/v1/skill-maps/evolve` install and IP limits are consumed in one DynamoDB transaction. A rejected transaction cannot consume one counter without the other. Immediately before each asynchronous Bedrock invocation, one transaction reserves both a logical-job call and a separate pseudonymous install-only daily quota unit; JSON repair, fallback, and later sanitization passes each consume their own units. The compact SQS job deliberately does not retain the request IP. API Gateway throttling remains the edge control for `ensure` and `claim`. Deployments configured with `REQUIRE_RATE_LIMITING=true`, or marked `production`, fail closed if the table or HMAC secret is missing.

## Skill-map inference, evolution, and tagged questions

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

After strong recent mastery evidence, `/v1/skill-maps/evolve` can atomically replace one or two mastered nodes with harder successors while retaining every unfinished node. It validates and echoes the base version and stable map fingerprint, rejects active/archive name reuse, and assigns deterministic UUIDv5 successor and objective IDs. The client sends the latest 48 archived skills as readable planning context plus up to 750 lowercase FNV-1a fingerprints covering the full archived-name history. The server validates and enforces the fingerprints but removes them from both initial and retry model prompts. The exact evidence thresholds, request/response shape, and stateless retry limitation are documented in `../../docs/AI_BACKEND_CONTRACT.md`.

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

The worker resolves the stable weights against the server's `desiredCount`, reserves at least one maintenance slot for every positive-weight skill, measures finite-bank history or replenishing ready inventory as appropriate, and derives short-lived per-batch counts from the remaining server-side deficits. It derives a server-owned `requestedObjectiveAllocation` for every map-aware client and every short generation chunk, balancing finite ready-and-claimed history or replenishing ready inventory and accepting only questions that match the exact skill/objective quotas. A durable bank therefore continues replenishing a small positive-weight skill after its ready question is claimed without starving one of its objectives. New durable clients send `requiresFullObjectiveCoverage: true`; for those requests, the whole-bank target must also give each positive-weight skill at least one slot per active objective or ensure returns `400`. The field is optional and defaults to `false`, so an older client remains subject to the positive-skill floor without unexpectedly failing a previously valid bank size. Repeated `ensure` calls for the same `contextRevision` must send the same weight map; changing the weights requires a new context revision and bank, rather than recomputing weights from the app's local inventory.

The legacy synchronous `/v1/questions` route has no durable inventory; when it receives the field, it applies the same weights only across that one requested batch.

Every accepted map-aware question returns `skillID`, `objectiveID`, and `objective`; `topic` remains populated with the canonical skill name for legacy UI and coverage logic. Provider IDs are never trusted blindly. The sanitizer resolves matching topic/objective names and any supplied IDs against the request map, assigns the request's canonical IDs, and drops missing, conflicting, or off-map items. Requests without `skillMap` keep the existing topic-only contract unchanged.

## Durable asynchronous question banks

`POST /v1/question-banks/ensure` accepts the normal generation request plus the client-computed `contextRevision`, `desiredCount`, `lowWatermark`, and optional `requiresFullObjectiveCoverage` capability. It authenticates and validates the request, derives an opaque bank identifier scoped to the pseudonymized installation and goal context, persists the validated generation context (including the capability), and uses a DynamoDB transaction to atomically link the bank to a pending outbox job when inventory needs replenishment. It returns `202` with `bankID`, `status`, `readyCount`, and `targetCount`; it does not wait for Bedrock.

`lowWatermark=0` means a finite bank: the server tracks cumulative accepted generation and stops permanently for that bank revision once it reaches `desiredCount`. Claims reduce ready inventory but do not reset that cumulative ceiling, and repeated `ensure` polling cannot replenish it. A positive watermark remains available as the general server contract for ongoing replenishment toward `desiredCount`; claiming down to or below that watermark schedules another refill. The current client uses persisted finite fill-cycle banks. Its first empty-cache cycle normally targets the 40-question Free or 80-question Pro local reserve; a later cycle asks for the current deficit plus the smallest allocation-safe target needed to restore two ready questions per active skill and reserve at least one server slot for every active objective. A fresh opaque bank revision is created after a completed cycle even when the underlying goal/allocation context is unchanged, while retries of the same persisted intent reuse its revision. Those tier inputs are still caller-supplied today, so public production must derive or authorize them from server-verified StoreKit entitlement rather than trusting the app.

After the transaction commits, the API makes an immediate best-effort delivery and the table's `NEW_IMAGE` DynamoDB Stream independently invokes the outbox consumer. The consumer recognizes pending job records, re-reads their current state, sends a compact SQS message when still needed, and conditionally marks the job sent. This closes the crash window between committing the job and sending it to SQS. DynamoDB Streams and SQS are both at-least-once systems, so the direct and stream senders can race and duplicate messages are expected. Stable job IDs, a conditional processing lease, and an atomic per-job provider-attempt counter keep those duplicates within the configured generation bound.

The queue body contains only an opaque pseudonymous bank partition key, job ID, and context version. The complete generation context stays in the encrypted DynamoDB table. The worker reads one message per invocation, generates at most the configured chunk size (five by default), validates and stores accepted questions, and enqueues another job until the target is satisfied. A five-question chunk matches one app session and avoids the latency and quality degradation observed in oversized model batches. Each chunk receives the 30 most recently created questions as bounded novelty context, while the persistence boundary checks normalized stems against the bank's complete ready-and-claimed history. New question IDs are derived from that normalized stem, so changing an answer, distractor, explanation, or difficulty cannot store a second copy of the same question. Replaying a completed message repairs a crash between committing one batch and scheduling the next. Claims may safely reduce ready inventory while a refill is running; the commit still conditions on the active goal revision, tier policy, and generated counter. A failed generation message is retried and moves to the generation dead-letter queue after the configured receive threshold (five by default). The same numeric threshold caps actual Converse calls for each logical job across duplicate deliveries; initial generation, JSON repair, fallback models, and later sanitization passes all reserve from that one durable counter. An exhausted job enters a cooldown before a replacement job can start. The bank durably accumulates those exhausted jobs; at three by default it records `generationBlockedReason=provider_failure_limit`, acknowledges remaining duplicates, and stops every later ensure, claim, or polling attempt from scheduling more work for that context. Successful chunks, cooldown expiry, and repeated requests do not erase the ledger, so only a genuinely new bank/fill-cycle context restores the budget. Existing ready inventory remains claimable after blocking. The 240-second worker timeout is paired with a 1440-second queue visibility timeout, meeting the six-times-timeout safety margin.

The outbox stream mapping filters for queued job images with pending delivery, processes small batches, reports individual failed records, bisects failed batches, and retries each record at most five times while it is at most 24 hours old. When Lambda discards an exhausted invocation, the separate encrypted outbox failure queue receives invocation metadata such as the stream ARN, shard ID, and sequence-number range—not the original DynamoDB stream image or job key. This bound prevents a poison stream record from blocking a shard indefinitely, and the visible metadata message raises an alarm.

Outbox recovery must begin before the original 24-hour stream record expires whenever possible. Keep the failure message, diagnose the root cause, then use its `DDBStreamBatchInfo` shard and sequence range to retrieve the original stream record. Read the referenced JOB and META items; verify the job is still `status=queued` and `enqueueStatus=pending`, and that META still names its job ID in `activeJobID` with the same context revision. After remediation, conditionally update only that job's `updatedAt` while requiring the same queued/pending state; the resulting stream event safely retries delivery. Confirm that the item reaches `enqueueStatus=sent` before deleting the failure message. If the original stream record has expired, the metadata cannot reconstruct the job key: scan the bank table for queued/pending JOB items and apply the same validation and conditional re-touch to each active item. Replaying is duplicate-safe, but deleting metadata before confirming delivery can strand a job until another ensure/claim recovery attempt.

`POST /v1/question-banks/claim` accepts `bankID`, `claimID`, a limit of at most 20, and an optional bounded `blockedStemFingerprints` array representing local question/report history. It returns `200` with already-prepared questions and the current status/counts without invoking Bedrock in the HTTP request path. Clients should persist a claim ID until its response is durably written locally, then use a new claim ID for the next claim. The server stores a SHA-256-derived claim key and the exact response so retrying that claim is idempotent; replaying a queued claim also retries best-effort refill scheduling. Claimed QUESTION rows are marked as claimed rather than deleted and remain as deduplication history until their nominal bank TTL expires. Claiming consumes malformed, locally blocked, or same-stem legacy ready rows without returning them; discarded rows reduce a finite bank's generated count and schedule replacements without exceeding the configured target. Status is one of `queued`, `processing`, `ready`, or `empty`. A retry or rate-limit cooldown remains `queued`; `empty` means no inventory or delayed generation remains for that finite bank, so a client can stop polling even if local validation left it below the nominal target. Ensure and claim responses add optional `generationBlockedReason` for terminal contexts and omit it otherwise; stored claim replays preserve the exact reason. Clients must not turn that terminal response into an automatic fresh fill cycle for an unchanged goal context.

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
- `200`: validated skill-map evolution proposal
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

## Adaptive learning validation

See [the adaptive learning contract](../../docs/ADAPTIVE_LEARNING.md). Pro sends recent distinct-question evidence and a difficulty target for each skill. New questions carry verified answer-specific feedback. Claims with `minimumVerificationVersion: 1` replace old unverified inventory instead of returning it. Deploy the service before updating iOS.

Use `python evals/checkpoint_learning_eval.py --output /tmp/learning-review.json --generation` with synthetic goals and the intended model environment to exercise the actual verification pipeline. It includes known bad questions, valid controls, and bounded local bank top-offs across every generation fixture. Use `--case-id` to select cases or `--generation-fixtures` to supply arbitrary goals. Add `--infer-skills` to build each goal’s map with AI and exercise different per-skill difficulty targets; those targets are synthetic, not a test of device-side progression. This does not deploy or exercise AWS queue delivery. The older `checkpoint_question_eval.py capture-bedrock` tool evaluates raw generation and sanitization; it does not establish post-review quality.

### Independent solution and diagnosis

Question generation now solves stems before exposing answer choices to the verifier. The solver explicitly lists missing factual assumptions; the server discards those items before final review and preserves indexes for the supported remainder. Final feedback targets short sentences within the unchanged client limits. Generation uses a shorter task-focused prompt, and JSON with duplicate properties is rejected rather than silently selecting the last answer key. All three stages consume the same bounded call budget. No production model choice is implied by local comparison results.

The learning evaluator records quality dispositions, provider configuration, prompt hashes, token usage, and stop reasons. Use `--review-fixtures evals/fixtures/question_verification_holdout.jsonl` for the additional eight checks. A malformed solver response is a failed evaluation, not credit for detecting a bad item. The held-out arithmetic and SQLite references were independently checked; this small set is not a production correctness estimate.

Retries receive only the previous pass's bounded rejection counts in `previousAttemptFeedback`. The author is instructed to repair the cause, including insufficient cognitive challenge, without changing the learner's target. The default six-call job budget permits at most two complete three-call passes; time and quota checks may stop earlier. Partial verified inventory is preserved when another complete pass is unaffordable. Feedback currently stays within one generation invocation; it is not persisted across separate queue jobs. Use `--max-generation-jobs 1` to bound a live generation smoke test; failed jobs retain their earlier inventory and diagnostic counts in the report.

### Paired author-prompt experiment

Run `python evals/checkpoint_prompt_ablation.py --dry-run --output-dir /tmp/checkpoint-ablation` to inspect the 12-call, 60-question plan. Remove `--dry-run` to capture six goals with both a simple prompt and the current author prompt on Opus 4.6 adaptive/high, using an identical normalized request and 16,000-token allowance for both arms. Add `--aws-cli-credentials` when using the AWS CLI login provider; credentials stay in process memory. The output directory must be new.

Assess `blinded.json` before opening `answer_key.json`: independently select every defensible answer and record correctness, ambiguity, and challenge. Then compare to author keys and inspect explanations. `capture.json` separately records app-sanitizer retention, latency, tokens, exact request context, and prompt hashes. Raw questions are preserved even if the app rejects their length. This first comparison covers author prompts with the supplied fixture contexts; it does not exercise inferred skill maps, model review, adaptation over time, or deployed queues. One generation per arm/goal is exploratory evidence, not a stable accuracy estimate or a release qualification.

The [September 6 paired experiment](../../docs/QUESTION_PROMPT_EXPERIMENT.md) preserves 60 generated items, blinded assessments, prompt/context snapshots, and all 17 call attempts. The shorter prompt did not improve observed quality in that sample; no production model or prompt was promoted. Failed captures now also record bounded cause types and provider error codes without persisting provider cause messages.
