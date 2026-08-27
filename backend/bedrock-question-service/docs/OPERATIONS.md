# Checkpoint Backend Operations

For deployment parameters and model-specific setup, see the [deployment guide](DEPLOYMENT.md). For the service contract and runtime configuration, see the [backend README](../README.md).

## Operations

`SERVICE_MODE=drain` and `SERVICE_MODE=disabled` return `503` with `Retry-After` on API entry points. Drain mode continues consuming already-queued question-bank jobs so the durable backlog reaches a clean stopping point. Disabled mode also disables the worker's SQS event-source mapping; messages remain encrypted in the queue without advancing their receive count and resume automatically when the stack returns to `enabled` or `drain`. An invocation already in flight during the CloudFormation update still fails closed and becomes visible again after the queue visibility timeout. Change the CloudFormation parameter and deploy the configuration update to operate the switch. Reserved concurrency, outbox concurrency, API throttling, and the DynamoDB event-source mapping remain separate emergency fuses.

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

## Local verification

The unit tests inject fake Bedrock and DynamoDB clients; AWS credentials are not needed. Activate a Python 3.12 environment first, matching Lambda and CI.

```bash
cd backend/bedrock-question-service
python -m unittest discover -s tests
scripts/test-deployment-scripts.sh
shellcheck scripts/*.sh
actionlint ../../.github/workflows/deploy-backend.yml
ruff check ./*.py tests evals
python -m compileall -q ./*.py tests evals
sam validate --lint --template-file template.yaml
```

With a local ignored `Checkpoint/Config/Secrets.xcconfig`, the redacted live checks are:

```bash
python smoke_test_backend.py --case-id lsat_logical_reasoning_medium
python smoke_test_backend.py --case-id mcat_science_passage_reasoning
python smoke_test_backend.py --case-id spanish_subjunctive_easy_application
python smoke_test_backend.py --case-id modern_world_history_source_reasoning
python smoke_test_backend.py --case-id backyard_beekeeping_raw_goal
```

The smoke checker never prints endpoint or token values. It consumes live quota and Bedrock capacity, so run it intentionally after deployment rather than as an unauthenticated pull-request check.

The manual deployment workflow has a separate `run_smoke_test` checkbox. When selected alongside `confirm_deploy`, it retrieves the stack's `QuestionEndpoint` without printing it and runs one authenticated, sanitized beekeeping question. That opt-in request incurs Bedrock usage. Local automation can supply `CHECKPOINT_SMOKE_ENDPOINT` and `CHECKPOINT_SMOKE_TOKEN` instead of an xcconfig; both values are required together and the token must be at least 32 characters.
