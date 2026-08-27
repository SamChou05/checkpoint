# Bedrock Question Service

AWS Lambda backend for Checkpoint's AI question-generation contract. The iOS app sends goal context and question constraints; the service can either return a synchronous batch from `POST /v1/questions` or enqueue an expiring server-side bank through `POST /v1/question-banks/ensure`. A DynamoDB Streams outbox consumer durably forwards pending jobs to SQS, and a separate SQS-triggered worker calls Amazon Bedrock, validates the output, and stores ready inventory for `POST /v1/question-banks/claim`. The JSON contract is documented in `../../docs/AI_BACKEND_CONTRACT.md`.

Generation is domain-general. Named-domain examples belong only to eval fixtures; production code has no LSAT, MCAT, language, coding, or other subject-specific question branches.

## Public-release security boundary

The checked-in bearer gate is for controlled development and TestFlight only. A shared token compiled into an iOS app can be extracted and is not a production identity mechanism. The HMAC quota keys added here protect stored identifiers from casual disclosure but do not make the caller-supplied install UUID trustworthy.

Before public App Store release:

- replace the shared bearer and install UUID identity on every synchronous and question-bank route with per-request App Attest assertions, server challenges, replay protection, and server-held key state
- validate StoreKit subscription status on the server before accepting caller-selected bank sizes, assigning paid quotas, or enabling Pro replenishment watermarks
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
| `BEDROCK_FALLBACK_MODEL_ID` | empty | Optional secondary model ARN; enable only after it passes the same eval suite. |
| `BEDROCK_REASONING_EFFORT` | empty locally; `low` in the deploy workflow | Optional GPT-5.6 effort: `none`, `low`, `medium`, `high`, `xhigh`, or `max`. At `low` or higher the request sends the reasoning field and deliberately omits temperature/top-p sampling controls; `none` retains the configured temperature. Non-GPT-5.6 models ignore this setting. |
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
| `SERVICE_MODE` | `enabled` | `enabled`, `drain`, or `disabled`; the latter two reject before auth, quota, or Bedrock. |
| `SERVICE_RETRY_AFTER_SECONDS` | `300` | `Retry-After` value returned by the kill switch. |
| `RATE_LIMIT_TABLE_NAME` | empty locally | DynamoDB table. SAM always configures it and sets `REQUIRE_RATE_LIMITING=true`. |
| `QUOTA_HASH_SECRET` | none | Server-only HMAC key, at least 32 characters, used to pseudonymize quota identifiers. |
| `MAX_REQUESTS_PER_INSTALL_PER_DAY` | `40` | Daily generation requests per pseudonymized install value. |
| `MAX_REQUESTS_PER_IP_PER_DAY` | `400` | Daily generation requests per pseudonymized source IP. |
| `RATE_LIMIT_TTL_SECONDS` | `172800` | Nominal quota-record TTL. DynamoDB deletion after expiry is asynchronous. |
| `QUESTION_BANK_TABLE_NAME` | none locally | DynamoDB table containing expiring question-bank metadata, validated generation context, ready questions, and claim records. SAM configures it for the API, outbox consumer, and worker. |
| `QUESTION_BANK_QUEUE_URL` | none locally | SQS queue used by `ensure`, the stream outbox consumer, and the worker when more inventory is needed. SAM configures it for all three functions. |
| `QUESTION_BANK_TTL_SECONDS` | `2592000` | Nominal 30-day lifetime for question-bank records. DynamoDB TTL deletion is asynchronous and is not an exact deletion deadline. |
| `QUESTION_BANK_MAX_RECEIVE_COUNT` | `5` | Shared SQS redrive, per-job generation-attempt, and terminal-failure threshold. |
| `EMIT_STRUCTURED_METRICS` | on in Lambda | Emits privacy-safe request and provider metrics in CloudWatch EMF. |

For `deepseek.v3.2` and `moonshotai.kimi-k2.5`, the runtime sends `thinking.type=disabled` as a model-specific additional request field. This simple structured-generation workload retains the configured temperature while avoiding unnecessary reasoning latency and tokens. GPT-5.6 continues to use only its separate `reasoning_effort` field, and other models receive neither override.

## Request hardening

The service authenticates first, then fully decodes and validates the request before consuming quota. It enforces:

- UTF-8 JSON and a configurable byte ceiling
- explicit limits for goal, focus, level, directive, topic, prompt, answer, choice, and competency fields
- an optional top-level `sourceDocuments` array of `{ "name": "...", "text": "..." }` objects; existing clients may omit it
- at most 5 source documents, 160 characters per normalized name, and 24,000 normalized source-text characters across the request
- deterministic source truncation that shares the context budget across documents and samples the beginning, middle, and end of over-budget text
- bounded list sizes and a server-side question-count cap
- a provider-call budget shared by initial, repair, top-off, and fallback attempts
- remaining-Lambda-time checks before another provider invocation
- bounded botocore timeouts and exactly one total SDK attempt, so every network attempt consumes one provider-call budget slot

Source documents are accepted as extracted UTF-8 text, not binary uploads or base64 file bodies. Empty text, malformed objects, oversized names, non-array input, and more than five documents return `400` before quota consumption. Document text is whitespace/control-character normalized and then truncated within the fixed context budget rather than rejecting an otherwise usable upload.

When source context is present, the assessment prompt treats it as the primary content scope, requires source-supported answers and self-contained question stems, and explicitly treats document names and contents as untrusted evidence rather than instructions. Outlines and syllabi may scope reliable subject knowledge, but the model is told not to claim unsupported details came from a source or infer content omitted by truncation.

Synchronous `/v1/questions` install and IP limits are consumed in one DynamoDB transaction. A rejected transaction cannot consume one counter without the other. Asynchronous worker passes consume a separate pseudonymous install-only counter before Bedrock; the compact SQS job deliberately does not retain the request IP. API Gateway throttling remains the edge control for `ensure` and `claim`. Deployments configured with `REQUIRE_RATE_LIMITING=true`, or marked `production`, fail closed if the table or HMAC secret is missing.

## Durable asynchronous question banks

`POST /v1/question-banks/ensure` accepts the normal generation request plus the client-computed `contextRevision`, `desiredCount`, and `lowWatermark`. It authenticates and validates the request, derives an opaque bank identifier scoped to the pseudonymized installation and goal context, persists the validated generation context, and uses a DynamoDB transaction to atomically link the bank to a pending outbox job when inventory needs replenishment. It returns `202` with `bankID`, `status`, `readyCount`, and `targetCount`; it does not wait for Bedrock.

`lowWatermark=0` means a finite starter bank: the server tracks cumulative accepted generation and stops permanently for that bank revision once it reaches `desiredCount`. Claims reduce ready inventory but do not reset that cumulative ceiling, and repeated `ensure` polling cannot replenish it. A positive watermark enables ongoing replenishment toward `desiredCount`; claiming down to or below the watermark schedules another refill. The current client requests 40 finite questions for Free and an 80-question bank with a 20-question refill watermark for Pro. Those tier inputs are still caller-supplied today, so public production must derive or authorize them from server-verified StoreKit entitlement rather than trusting the app.

After the transaction commits, the API makes an immediate best-effort delivery and the table's `NEW_IMAGE` DynamoDB Stream independently invokes the outbox consumer. The consumer recognizes pending job records, re-reads their current state, sends a compact SQS message when still needed, and conditionally marks the job sent. This closes the crash window between committing the job and sending it to SQS. DynamoDB Streams and SQS are both at-least-once systems, so the direct and stream senders can race and duplicate messages are expected. Stable job IDs, a conditional processing lease, and an atomic per-job provider-attempt counter keep those duplicates within the configured generation bound.

The queue body contains only an opaque pseudonymous bank partition key, job ID, and context version. The complete generation context stays in the encrypted DynamoDB table. The worker reads one message per invocation, generates at most the configured chunk size (five by default), validates and stores accepted questions, and enqueues another job until the target is satisfied. A five-question chunk matches one app session and avoids the latency and quality degradation observed in oversized model batches. Replaying a completed message repairs a crash between committing one batch and scheduling the next. Claims may safely reduce ready inventory while a refill is running; the commit still conditions on the active goal revision, tier policy, and generated counter. A failed generation message is retried and moves to the generation dead-letter queue after the configured receive threshold (five by default). The same threshold caps provider calls for the logical job across duplicate deliveries. If duplicates exhaust that logical cap before one message reaches its own redrive threshold, the bank is terminally failed, remaining duplicates are acknowledged instead of multiplying dead-letter entries, and the worker emits provider-failure/error metrics. The 120-second worker timeout is paired with a 720-second queue visibility timeout, meeting the six-times-timeout safety margin.

The outbox stream mapping filters for queued job images with pending delivery, processes small batches, reports individual failed records, bisects failed batches, and retries each record at most five times while it is at most 24 hours old. When Lambda discards an exhausted invocation, the separate encrypted outbox failure queue receives invocation metadata such as the stream ARN, shard ID, and sequence-number range—not the original DynamoDB stream image or job key. This bound prevents a poison stream record from blocking a shard indefinitely, and the visible metadata message raises an alarm.

Outbox recovery must begin before the original 24-hour stream record expires whenever possible. Keep the failure message, diagnose the root cause, then use its `DDBStreamBatchInfo` shard and sequence range to retrieve the original stream record. Read the referenced JOB and META items; verify the job is still `status=queued` and `enqueueStatus=pending`, and that META still names its job ID in `activeJobID` with the same context revision. After remediation, conditionally update only that job's `updatedAt` while requiring the same queued/pending state; the resulting stream event safely retries delivery. Confirm that the item reaches `enqueueStatus=sent` before deleting the failure message. If the original stream record has expired, the metadata cannot reconstruct the job key: scan the bank table for queued/pending JOB items and apply the same validation and conditional re-touch to each active item. Replaying is duplicate-safe, but deleting metadata before confirming delivery can strand a job until another ensure/claim recovery attempt.

`POST /v1/question-banks/claim` accepts `bankID`, `claimID`, and a limit of at most 20. It returns `200` with already-prepared questions and the current status/counts without invoking Bedrock in the HTTP request path. Clients should persist a claim ID until its response is durably written locally, then use a new claim ID for the next claim. The server stores a SHA-256-derived claim key and the exact response so retrying that claim is idempotent; replaying a queued claim also retries best-effort refill scheduling. Claimed QUESTION rows are marked as claimed rather than deleted and remain as deduplication history until their nominal bank TTL expires. Status is one of `queued`, `processing`, `ready`, or `empty`. A retry or rate-limit cooldown remains `queued`; `empty` means no inventory or delayed generation remains for that finite bank, so a client can stop polling even if local validation left it below the nominal target.

The server queue removes app-lifecycle dependence, but it does not promise a fixed completion time: Lambda throttling, SQS retries, Bedrock capacity, the kill switch, or a dead-lettered job can delay replenishment. The app must keep a local ready reserve, poll with backoff, and continue serving accepted local questions while a refill is pending.

Only `POST ensure` and `POST claim` are deployed in this increment. There is no authenticated remote-bank deletion route yet. Add one before claiming that in-app **Erase all data** immediately removes server-side question-bank records.

## Safety behavior

When both runtime Guardrail settings are present, every Converse request includes the configured Bedrock Guardrail. The SAM template additionally requires the identifier, version, and IAM ARN as an all-three-or-none set. A `guardrail_intervened` stop reason returns:

```json
{"error":"This request could not be processed safely.","code":"safety_intervention"}
```

The status is `422`. Unsafe content is not sent to JSON repair, another generation pass, or the fallback model. In asynchronous generation, the job and its exact bank revision are terminally blocked instead of entering SQS retry or refill loops; a changed context revision creates a separate bank. Supplying only a runtime Guardrail identifier or version fails closed with `503`. A production stack cannot pass CloudFormation parameter validation without a complete Guardrail configuration plus operations and budget alert emails.

Guardrails are an additional runtime control. The deterministic sanitizers and adversarial eval fixtures remain required.

## Deploy with AWS SAM

```bash
cd backend/bedrock-question-service
sam validate --lint --template-file template.yaml
sam build
sam deploy --guided
```

Important guided values:

- `BedrockModelArn`: exact enabled model or inference-profile ARN; the IAM policy no longer uses `Resource: "*"`
- `BedrockInvokeResourceArns`: comma-delimited least-privilege IAM resource list; include `BedrockModelArn`, the fallback ARN when configured, and every destination foundation-model ARN required by a cross-region inference profile
- `QuestionBankWorkerModelArn`: asynchronous worker model ARN; this can be stronger/slower than the synchronous compatibility model
- `QuestionBankWorkerInvokeResourceArns`: worker-only least-privilege resource list containing its model/profile and any cross-region destinations
- `BedrockFallbackModelArn`: leave empty until evaluated
- `BedrockReasoningEffort`: the deployment workflow defaults to `low`; non-GPT-5.6 models ignore it, and GPT-5.6 deployments should select an effort justified by the eval suite
- Guardrail ID, version, and ARN: provide all three or leave all three empty
- `QuotaHashSecret`: generate a random server-only value of at least 32 characters
- `BackendToken`: a separate long random value for internal/TestFlight only
- `AllowUnauthenticatedBackend`: keep `false` for every exposed stack
- `DeploymentEnvironment`: use `testflight` for internal distribution; selecting `production` does not make bearer auth App Store-safe
- `QuestionBankTTLSeconds`: defaults to 30 days; choose and publish the production retention period before launch
- `QuestionBankWorkerReservedConcurrency`: defaults to 2 and independently caps asynchronous Bedrock work
- `QuestionBankWorkerReadTimeoutSeconds`: defaults to 75 seconds for asynchronous generation; keep it below the worker's 120-second Lambda timeout. It does not change the synchronous API's 20-second default
- `QuestionBankGenerationChunkSize`: defaults to 5 questions; the worker durably chains chunks until the 40/80-question target is full
- `QuestionBankMaxReceiveCount`: defaults to 5 and drives SQS redrive, the per-job generation-attempt ceiling, and terminal-failure bookkeeping
- the outbox consumer reserves concurrency 2 in the template, independently capping stream-to-queue recovery work
- throttle, reserved-concurrency, request, provider-call, and daily-quota values: begin with the template defaults and adjust from observed metrics
- `AlertEmail`: optional outside production and required in production; confirm the SNS subscription email after deployment
- `BudgetAlertEmail`: optional outside production and required in production; receives account-wide Amazon Bedrock budget notifications

### Kimi K2.5 production-validation values

The evaluated TestFlight asynchronous worker uses Moonshot AI Kimi K2.5 in non-thinking mode. Set both `QuestionBankWorkerModelArn` and the sole entry in `QuestionBankWorkerInvokeResourceArns` to:

```text
arn:aws:bedrock:us-east-1::foundation-model/moonshotai.kimi-k2.5
```

The runtime automatically sends `thinking.type=disabled` for this structured question-generation workload. Keep `QuestionBankWorkerReadTimeoutSeconds` at `75`; the synchronous API retains Nova Lite and its shorter 20-second timeout for older clients, while current clients use the asynchronous bank. The August 2026 cross-domain capture passed all 13 fixtures and all 43 generated questions after deterministic grading.

### GPT-5.6 Luna deployment values

When GPT-5.6 Luna is enabled for the AWS account, set `BedrockModelArn`/`BEDROCK_MODEL_ARN` to the full US geographic inference-profile ARN whose ID is `us.openai.gpt-5.6-luna`, not merely the bare model ID:

```text
arn:aws:bedrock:<source-region>:<account-id>:inference-profile/us.openai.gpt-5.6-luna
```

Set the GitHub environment variable `BEDROCK_REASONING_EFFORT=low` (the workflow also defaults to `low`). The runtime sends `reasoning_effort: low` through Converse's additional model request fields and sends `maxTokens`, but it does not send `temperature` or `topP` because GPT-5.6 rejects sampling controls while reasoning is enabled. `none` explicitly disables reasoning and permits the configured temperature; an empty SAM value leaves the model-specific override unset.

For this US profile, `BEDROCK_INVOKE_RESOURCE_ARNS` must contain all five of the following comma-delimited resources, plus the fallback profile/model resources if a fallback is enabled:

```text
arn:aws:bedrock:<source-region>:<account-id>:inference-profile/us.openai.gpt-5.6-luna
arn:aws:bedrock:us-east-1::foundation-model/openai.gpt-5.6-luna
arn:aws:bedrock:us-east-2::foundation-model/openai.gpt-5.6-luna
arn:aws:bedrock:us-west-2::foundation-model/openai.gpt-5.6-luna
arn:aws:bedrock:<source-region>:<account-id>:project/default
```

Replace `<source-region>` with the region in which this stack invokes Bedrock and `<account-id>` with the deploying AWS account. Confirm the profile's destination list with `GetInferenceProfile` before each production rollout; a geography profile's destinations are stable for that profile, but a newly selected profile can have a different allowlist. AWS documents the model ID, default-project requirement, and regional availability in the [GPT-5.6 Luna model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-56-luna.html).

The stack output `QuestionEndpoint` includes `/v1/questions`; configure the app with that full HTTPS URL. The app derives the sibling `/v1/question-banks/ensure` and `/v1/question-banks/claim` URLs, which are also emitted as stack outputs. Moving from the previous Function URL changes the endpoint, so update the app configuration only after the API Gateway deployment succeeds.

## Operations

`SERVICE_MODE=drain` and `SERVICE_MODE=disabled` return `503` with `Retry-After` on API generation entry points. Change the CloudFormation parameter and deploy the configuration update to operate the switch. Reserved concurrency, worker and outbox concurrency, API throttling, and the SQS/DynamoDB event-source mappings remain separate emergency fuses.

Structured metrics contain only bounded operational fields: outcome, status, request ID, latency, question counts, provider calls, and Bedrock token counts. They never include goal text, focus areas, prompts, answers, bearer tokens, raw install IDs, or raw IP addresses.

The template alarms on repeated API 5xx responses, Lambda throttles, provider failures, high p95 latency, repeated structured backend errors (including partial-batch worker failures), a generation job older than 15 minutes, any message visible in the generation dead-letter queue, and any discarded-invocation metadata visible in the outbox failure queue. Alarm actions publish to the stack SNS topic. If an email was configured, AWS requires the recipient to confirm it before alerts are delivered. The optional budget filters the AWS account's Amazon Bedrock service cost; it is not limited to this stack.

## Privacy and retention

- The service receives goal text, focus areas, learner context, prior-question coverage, optional extracted source-document names and text, an app-generated install UUID, and the network source IP.
- Goal, question, and optional source-document content is sent to the configured Amazon Bedrock model for generation. It is not emitted in application metrics or normal logs.
- When used for quota rows, the install UUID and source IP are HMAC-pseudonymized before DynamoDB storage. Asynchronous generation stores a pseudonymous install counter but not the source IP in its queue job. HMAC values remain personal-data-adjacent identifiers and are not anonymous.
- The asynchronous bank table stores the validated generation context, optional extracted source text, ready and claimed question history, status, and claim-delivery state. Claimed question content remains for deduplication until its nominal bank TTL; the table uses DynamoDB encryption at rest and a nominal 30-day TTL by default.
- The generation SQS queue, its dead-letter queue, and the separate outbox failure queue use server-side encryption. Generation jobs contain opaque pseudonymous keys and coordination values, not raw goal text, source documents, generated questions, raw install IDs, or raw IP addresses. The source queue retains unprocessed messages for up to 4 days, the generation dead-letter queue retains failed jobs for up to 14 days, and the outbox failure queue retains invocation metadata without the original stream image for up to 14 days. DynamoDB Stream images can contain the changed bank item and are available to the stream consumer for up to 24 hours; the outbox handler filters for coordination job records.
- Quota rows have a nominal 48-hour TTL by default. DynamoDB TTL removal is eventual, so the privacy policy must not promise deletion at the exact expiry second.
- Question-bank TTL removal is also eventual. **Erase all data** currently deletes the local bank and installation ID but does not call a server deletion endpoint; remote bank and queued work can remain until expiry and asynchronous service deletion.
- Lambda logs default to 14-day retention in the SAM template. Change that parameter only alongside the published retention policy.
- Unexpected system exceptions may still produce AWS SDK diagnostic stack traces; provider and configuration failures deliberately log only a category, not client content.

## IAM

The runtime model ARN and the IAM invoke resources are intentionally separate parameters. `BedrockModelArn` is passed to Converse; `BedrockInvokeResourceArns` is the complete allowlist attached to `bedrock:InvokeModel`. For `us.openai.gpt-5.6-luna`, that allowlist includes the source-region inference-profile ARN, all three US destination foundation-model ARNs, and the deploying account's source-region `project/default` ARN. The default project is a required authorization resource for this Luna bedrock-runtime path; it is not a replacement for the inference-profile or destination-model grants.

The API and worker functions can optionally apply the supplied Guardrail ARN. The API function has only the question-bank table operations and `sqs:SendMessage` needed to ensure and claim banks; the worker has table operations, queue poll/requeue operations, and model invocation. The outbox function has read access to this table's stream, `GetItem`/`UpdateItem` on the bank table, and `SendMessage` on the source and outbox failure queues. AWS does not support resource-level authorization for `dynamodb:ListStreams`, so that one discovery action requires `Resource: "*"`; stream record reads remain scoped to this table's stream ARN. Streaming model-invoke permission is not granted because this service uses non-streaming Converse.

Cross-region inference profiles require permissions for the inference profile and can require every destination foundation-model ARN. Put all of them in `BedrockInvokeResourceArns`, keep the list free of wildcards, and review the chosen profile's documented destinations whenever AWS changes the profile.

## Local verification

The unit tests inject fake Bedrock and DynamoDB clients; AWS credentials are not needed.

```bash
cd backend/bedrock-question-service
python3 -m unittest discover -s tests
ruff check lambda_function.py question_bank.py smoke_test_backend.py tests evals/checkpoint_question_eval.py
sam validate --lint --template-file template.yaml
```

With a local ignored `Checkpoint/Config/Secrets.xcconfig`, the existing redacted live checks remain available after its endpoint is updated to the API Gateway output:

```bash
python3 smoke_test_backend.py --case-id lsat_logical_reasoning_medium
python3 smoke_test_backend.py --case-id mcat_science_passage_reasoning
python3 smoke_test_backend.py --case-id spanish_subjunctive_easy_application
python3 smoke_test_backend.py --case-id modern_world_history_source_reasoning
python3 smoke_test_backend.py --case-id backyard_beekeeping_raw_goal
```

The smoke checker never prints endpoint or token values. It consumes live quota and Bedrock capacity, so run it intentionally after deployment rather than as an unauthenticated pull-request check.

The manual deployment workflow has a separate `run_smoke_test` checkbox. When selected alongside `confirm_deploy`, it retrieves the stack's `QuestionEndpoint` without printing it and runs one authenticated, sanitized beekeeping question. That opt-in request incurs Bedrock usage. Local automation can supply `CHECKPOINT_SMOKE_ENDPOINT` and `CHECKPOINT_SMOKE_TOKEN` instead of an xcconfig; both values are required together and the token must be at least 32 characters.

## Response statuses

- `200`: sanitized question batch
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
