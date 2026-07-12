# Bedrock Question Service

AWS Lambda backend for Checkpoint's AI question-generation contract. The iOS app sends goal context and question constraints; the service calls Amazon Bedrock, validates the output, and returns the JSON shape documented in `../../docs/AI_BACKEND_CONTRACT.md`.

Generation is domain-general. Named-domain examples belong only to eval fixtures; production code has no LSAT, MCAT, language, coding, or other subject-specific question branches.

## Public-release security boundary

The checked-in bearer gate is for controlled development and TestFlight only. A shared token compiled into an iOS app can be extracted and is not a production identity mechanism. The HMAC quota keys added here protect stored identifiers from casual disclosure but do not make the caller-supplied install UUID trustworthy.

Before public App Store release:

- replace the shared bearer and install UUID identity with per-request App Attest assertions, server challenges, replay protection, and server-held key state
- validate StoreKit subscription status on the server before assigning paid quotas
- keep server quotas, API Gateway throttles, reserved concurrency, alarms, and budgets enabled as independent cost controls

This service does not claim to implement App Attest or server-side StoreKit verification yet.

## Runtime and edge

- Python 3.12 Lambda
- Amazon Bedrock Converse through a least-privilege Lambda execution role
- DynamoDB atomic daily quota counters
- API Gateway HTTP API with stage-level rate and burst throttles
- Lambda reserved concurrency as a cost and account-concurrency fuse
- CloudWatch Embedded Metric Format, alarms, explicit log retention, SNS alerts, and an optional Bedrock budget
- no public Lambda Function URL

## Runtime configuration

| Name | Default | Purpose |
| --- | --- | --- |
| `BEDROCK_MODEL_ID` | `amazon.nova-lite-v1:0` in local code | Model or inference-profile identifier/ARN passed to Converse. The SAM stack receives this separately as `BedrockModelArn`. |
| `BEDROCK_FALLBACK_MODEL_ID` | empty | Optional secondary model ARN; enable only after it passes the same eval suite. |
| `BEDROCK_GUARDRAIL_IDENTIFIER` | empty | Optional Guardrail ID. Must be paired with a version. |
| `BEDROCK_GUARDRAIL_VERSION` | empty | Optional numeric Guardrail version or `DRAFT`. |
| `MAX_QUESTIONS_PER_BATCH` | `20` | Per-request output-count ceiling. |
| `BEDROCK_MAX_TOKENS` | `6000` | Per-provider-call output-token ceiling. |
| `GENERATION_ATTEMPTS` | `5` locally, `3` in SAM | Maximum sanitized top-off passes. |
| `MAX_PROVIDER_CALLS_PER_REQUEST` | `6` | Hard budget across generation, JSON repair, and fallback calls. |
| `MAX_REQUEST_BODY_BYTES` | `131072` | Request-body ceiling enforced before quota consumption. |
| `BEDROCK_CONNECT_TIMEOUT_SECONDS` | `3` | Bounded SDK connection timeout. |
| `BEDROCK_READ_TIMEOUT_SECONDS` | `20` | Bounded SDK read timeout, below the Lambda timeout. |
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
| `EMIT_STRUCTURED_METRICS` | on in Lambda | Emits privacy-safe request and provider metrics in CloudWatch EMF. |

## Request hardening

The service authenticates first, then fully decodes and validates the request before consuming quota. It enforces:

- UTF-8 JSON and a configurable byte ceiling
- explicit limits for goal, focus, level, directive, topic, prompt, answer, choice, and competency fields
- bounded list sizes and a server-side question-count cap
- a provider-call budget shared by initial, repair, top-off, and fallback attempts
- remaining-Lambda-time checks before another provider invocation
- bounded botocore timeouts and exactly one total SDK attempt, so every network attempt consumes one provider-call budget slot

Install and IP limits are consumed in one DynamoDB transaction. A rejected transaction cannot consume one counter without the other. Deployments configured with `REQUIRE_RATE_LIMITING=true`, or marked `production`, fail closed if the table or HMAC secret is missing.

## Safety behavior

When both runtime Guardrail settings are present, every Converse request includes the configured Bedrock Guardrail. The SAM template additionally requires the identifier, version, and IAM ARN as an all-three-or-none set. A `guardrail_intervened` stop reason returns:

```json
{"error":"This request could not be processed safely.","code":"safety_intervention"}
```

The status is `422`. Unsafe content is not sent to JSON repair, another generation pass, or the fallback model. Supplying only a runtime Guardrail identifier or version fails closed with `503`. A production stack cannot pass CloudFormation parameter validation without a complete Guardrail configuration plus operations and budget alert emails.

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
- `BedrockFallbackModelArn`: leave empty until evaluated
- Guardrail ID, version, and ARN: provide all three or leave all three empty
- `QuotaHashSecret`: generate a random server-only value of at least 32 characters
- `BackendToken`: a separate long random value for internal/TestFlight only
- `AllowUnauthenticatedBackend`: keep `false` for every exposed stack
- `DeploymentEnvironment`: use `testflight` for internal distribution; selecting `production` does not make bearer auth App Store-safe
- throttle, reserved-concurrency, request, provider-call, and daily-quota values: begin with the template defaults and adjust from observed metrics
- `AlertEmail`: optional outside production and required in production; confirm the SNS subscription email after deployment
- `BudgetAlertEmail`: optional outside production and required in production; receives account-wide Amazon Bedrock budget notifications

The stack output `QuestionEndpoint` includes `/v1/questions`; configure the app with the full HTTPS URL. Moving from the previous Function URL changes the endpoint, so update the app configuration only after the API Gateway deployment succeeds.

## Operations

`SERVICE_MODE=drain` and `SERVICE_MODE=disabled` return `503` with `Retry-After` and make no DynamoDB or Bedrock calls. Change the CloudFormation parameter and deploy the configuration update to operate the switch. Reserved concurrency and API throttling remain separate emergency fuses.

Structured metrics contain only bounded operational fields: outcome, status, request ID, latency, question counts, provider calls, and Bedrock token counts. They never include goal text, focus areas, prompts, answers, bearer tokens, raw install IDs, or raw IP addresses.

The template alarms on repeated API 5xx responses, Lambda throttles, provider failures, and high p95 latency. Alarm actions publish to the stack SNS topic. If an email was configured, AWS requires the recipient to confirm it before alerts are delivered. The optional budget filters the AWS account's Amazon Bedrock service cost; it is not limited to this stack.

## Privacy and retention

- The service receives goal text, focus areas, learner context, prior-question coverage, an app-generated install UUID, and the network source IP.
- Goal and question content is sent to the configured Amazon Bedrock model for generation. It is not emitted in application metrics or normal logs.
- Install UUID and source IP are HMAC-pseudonymized before DynamoDB storage. HMAC values remain personal-data-adjacent identifiers and are not anonymous.
- Quota rows have a nominal 48-hour TTL by default. DynamoDB TTL removal is eventual, so the privacy policy must not promise deletion at the exact expiry second.
- Lambda logs default to 14-day retention in the SAM template. Change that parameter only alongside the published retention policy.
- Unexpected system exceptions may still produce AWS SDK diagnostic stack traces; provider and configuration failures deliberately log only a category, not client content.

## IAM

The runtime model ARN and the IAM invoke resources are intentionally separate parameters. `BedrockModelArn` is passed to Converse; `BedrockInvokeResourceArns` is the complete allowlist attached to `bedrock:InvokeModel`. The function can optionally apply the supplied Guardrail ARN and transact against only the generated quota table. Streaming invoke permission is not granted because this service uses non-streaming Converse.

Cross-region inference profiles require permissions for the inference profile and can require every destination foundation-model ARN. Put all of them in `BedrockInvokeResourceArns`, keep the list free of wildcards, and review the chosen profile's documented destinations whenever AWS changes the profile.

## Local verification

The unit tests inject fake Bedrock and DynamoDB clients; AWS credentials are not needed.

```bash
cd backend/bedrock-question-service
python3 -m unittest discover -s tests
ruff check lambda_function.py smoke_test_backend.py tests evals/checkpoint_question_eval.py
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
- `400`: malformed or oversized request
- `401`: missing/incorrect internal bearer
- `422`: Bedrock Guardrail intervention; do not retry unchanged content
- `429`: daily quota or API/Lambda throttle; honor `Retry-After` when supplied
- `502`: provider or response-processing failure; retry after the supplied delay
- `503`: kill switch or fail-closed deployment configuration

The service drops duplicate/reported prompts, repeated answer sets, generic filler, off-target study-strategy prompts, below-difficulty items, malformed choices, and unsafe Guardrail-intervened output. The iOS app still applies its own validation before persisting questions.
