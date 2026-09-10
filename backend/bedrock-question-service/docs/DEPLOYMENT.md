# Checkpoint Backend Deployment

For the service contract, runtime configuration, and request behavior, see the [backend README](../README.md).

The protected GitHub workflow keeps its environment choice, OIDC permissions, and secret/variable mappings in YAML. Focused scripts under `scripts/` validate that configuration, assemble the SAM overrides, and run the opt-in authenticated smoke check.

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
- `BedrockVerificationModelArn`: separately evaluated reviewer ARN (the current candidate is `us.anthropic.claude-sonnet-4-6`); configure `BEDROCK_VERIFICATION_MODEL_ARN` in the deployment environment
- `BedrockVerificationInvokeResourceArns`: reviewer profile ARN and every destination foundation-model ARN; configure `BEDROCK_VERIFICATION_INVOKE_RESOURCE_ARNS`. Use `aws bedrock get-inference-profile` to resolve the profile in the deployment account and region; do not add wildcard access.
- `BedrockFallbackModelArn`: leave empty until evaluated
- `BedrockReasoningEffort`: the deployment workflow defaults to `low`; non-GPT-5.6 models ignore it, and GPT-5.6 deployments should select an effort justified by the eval suite
- Guardrail ID, version, and ARN: provide all three or leave all three empty
- `QuotaHashSecret`: generate a random server-only value of at least 32 characters
- `BackendToken`: a separate long random value for internal/TestFlight only
- `AllowUnauthenticatedBackend`: keep `false` for every exposed stack
- `DeploymentEnvironment`: use `testflight` for internal distribution; selecting `production` does not make bearer auth App Store-safe
- `BedrockStructuredOutputMode`: leave `legacy` for deployment and rollback. `native` is an explicit post-qualification rollout; it applies to both API and worker functions.
- `QuestionBankTTLSeconds`: defaults to 30 days; choose and publish the production retention period before launch
- `QuestionBankWorkerReservedConcurrency`: defaults to 2 and independently caps asynchronous Bedrock work
- `QuestionBankWorkerReadTimeoutSeconds`: defaults to 75 seconds for asynchronous generation; keep it below the worker's 240-second Lambda timeout. It does not change the synchronous API's 20-second default
- `QuestionBankGenerationChunkSize`: defaults to 5 questions; the worker durably chains chunks until the caller's finite fill-cycle target is full (an empty client cache normally requests 40 Free or 80 Pro, while later cycles can be smaller)
- `QuestionBankMaxReceiveCount`: defaults to 5 and drives SQS redrive and the per-job generation-attempt ceiling
- `QuestionBankMaxFailedGenerationJobs`: defaults to 3; after that many exhausted jobs, the exact bank context is durably blocked until the app begins a new fill-cycle context
- the outbox consumer reserves concurrency 2 in the template, independently capping stream-to-queue recovery work
- throttle, reserved-concurrency, request, provider-call, and daily-quota values: begin with the template defaults and adjust from observed metrics
- `AlertEmail`: optional outside production and required in production; confirm the SNS subscription email after deployment
- `BudgetAlertEmail`: optional outside production and required in production; receives account-wide Amazon Bedrock budget notifications

## Native structured-output qualification and rollback

Keep `BedrockStructuredOutputMode=legacy` when deploying this implementation.
The setting is shared by the API and worker, including synchronous question
creation, skill-map inference/evolution, and their solver/reviewer calls. The
Nova Lite synchronous configuration documented below is outside the runtime's
native capability allowlist. Enabling the shared flag with that configuration
would fail synchronous generation. Qualify every configured role before enabling
native mode; this change does not select a replacement model.

The runtime allowlist recognizes the documented Kimi K2.5 and Claude Sonnet 4.6
capabilities. It is not a record of live qualification. Resolve each exact author,
worker, skill-map, verification, and configured fallback model/profile separately,
including every destination of an inference profile, in the intended account
and region. A recognized model family does not establish account access, schema
acceptance, latency, or application quality. Opaque application profiles that the
runtime cannot identify fail closed and need explicit reviewed support.

`requirements.txt` packages boto3 and botocore 1.43.91 in each Lambda artifact.
After building, validate the delivered SDK and all six native request shapes:

```bash
sam validate --lint --template-file template.yaml
sam build --use-container
for function in CheckpointQuestionFunction QuestionBankWorkerFunction QuestionBankOutboxFunction; do
  python3.12 -I -S scripts/validate-native-sdk.py ".aws-sam/build/$function"
done
```

The verifier imports packages, runtime schemas, and Bedrock service-model files
from the artifact. It excludes host site packages and user service-model paths,
checks the exact pinned versions, and makes zero provider calls. A local
noncontainer build is useful packaging evidence; it does not replace the Lambda
container build. Current preparation passed SAM lint and a noncontainer build
with 18 request-shape checks across three artifacts. Container verification
remains unavailable because the Docker server did not respond within its timeout.

Use the [implementation and qualification plan](../../../docs/NATIVE_STRUCTURED_OUTPUT_IMPLEMENTATION.md)
for the bounded synthetic dry run: at most 12 provider attempts including retries,
with first/repeated requests and independently reported service, schema, semantic,
latency, token, and call-accounting results. No live qualification has been run for
this implementation. AWS documents the [Converse interface and schema subset](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
and native capability for [Kimi K2.5](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-moonshot-ai-kimi-k2-5.html)
and [Claude Sonnet 4.6](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-4-6.html).

After qualification and deployment review, enable native mode through a reviewed
stack parameter change to `BedrockStructuredOutputMode=native`. Keep models,
timeouts, budgets, guardrails, and concurrency fixed during that rollout. Monitor
provider/schema failures, semantic rejection, latency, inventory fill, and quota
accounting. Roll back by restoring `BedrockStructuredOutputMode=legacy` through
the same stack deployment and verify `BEDROCK_STRUCTURED_OUTPUT_MODE=legacy` on
both `CheckpointQuestionFunction` and `QuestionBankWorkerFunction`. The outbox
consumer makes no model calls. The iOS wire contract, bank format, wire
verification version 1, complete-choice policy revision 2, and optional
authored-solution revision 3 need no migration or relabeling. Existing accepted
inventory remains usable.

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

The stack output `QuestionEndpoint` includes `/v1/questions`; configure the app with that full HTTPS URL. The app derives the sibling `/v1/skill-maps/infer`, `/v1/skill-maps/evolve`, `/v1/question-banks/ensure`, and `/v1/question-banks/claim` URLs, which are also emitted as stack outputs.

## IAM

The runtime model ARN and the IAM invoke resources are intentionally separate parameters. `BedrockModelArn` is passed to Converse; `BedrockInvokeResourceArns` is the complete allowlist attached to `bedrock:InvokeModel`. For `us.openai.gpt-5.6-luna`, that allowlist includes the source-region inference-profile ARN, all three US destination foundation-model ARNs, and the deploying account's source-region `project/default` ARN. The default project is a required authorization resource for this Luna bedrock-runtime path; it is not a replacement for the inference-profile or destination-model grants.

The API and worker functions can optionally apply the supplied Guardrail ARN. The API function has only the question-bank table operations and `sqs:SendMessage` needed to ensure and claim banks; the worker has table operations, queue poll/requeue operations, and model invocation. The outbox function has read access to this table's stream, `GetItem`/`UpdateItem` on the bank table, and `SendMessage` on the source and outbox failure queues. AWS does not support resource-level authorization for `dynamodb:ListStreams`, so that one discovery action requires `Resource: "*"`; stream record reads remain scoped to this table's stream ARN. Streaming model-invoke permission is not granted because this service uses non-streaming Converse.

Cross-region inference profiles require permissions for the inference profile and can require every destination foundation-model ARN. Put all of them in `BedrockInvokeResourceArns`, keep the list free of wildcards, and review the chosen profile's documented destinations whenever AWS changes the profile.

### Reviewed-question rollout

The reviewer parameters are required for both the API and worker. Configure them before invoking the deployment workflow; validation fails when either is absent or the invocation allowlist excludes the reviewer. The worker timeout is 240 seconds and queue visibility is 1440 seconds. The additional review calls share the existing durable quota and deadline. Run the live learning evaluator and inspect its content before release; unit tests and a filled bank alone cannot establish educational quality. Deploy and smoke-test the backend before distributing the client that requires verified inventory.
