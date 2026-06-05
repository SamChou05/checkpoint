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
| `CHECKPOINT_BACKEND_TOKEN` | empty | Bearer token gate for Function URL testing and TestFlight. If empty, requests are rejected unless `ALLOW_UNAUTHENTICATED_BACKEND=true`. |
| `ALLOW_UNAUTHENTICATED_BACKEND` | `false` | Explicit local/private opt-in for running without a bearer token. Keep `false` for exposed Function URLs. |
| `CORS_ALLOW_ORIGIN` | `*` | Function URL CORS origin. |
| `RATE_LIMIT_TABLE_NAME` | empty | Optional DynamoDB table used for daily install/IP quotas. |
| `MAX_REQUESTS_PER_INSTALL_PER_DAY` | `40` | Daily backend generation calls per anonymous app install ID. |
| `MAX_REQUESTS_PER_IP_PER_DAY` | `400` | Daily backend generation calls per source IP. |
| `RATE_LIMIT_TTL_SECONDS` | `172800` | Time before quota counter records expire. |

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
- `BackendToken`: set a long random value for internal TestFlight testing.
- `AllowUnauthenticatedBackend`: keep `false` for exposed Function URLs.

The deployed stack outputs `QuestionEndpoint`. Configure the iOS app to use that URL as its internal AI backend endpoint.

## IAM

`template.yaml` grants Bedrock invoke permissions to the Lambda role plus `dynamodb:UpdateItem` for the generated rate-limit table. It uses `Resource: "*"` for Bedrock because model and inference-profile ARNs vary by model and region; tighten this after choosing the exact production model/inference profile.

## Cost Controls

- The app caches generated batches and does not call AI on every blocked-app attempt.
- This service caps the requested batch size with `MAX_QUESTIONS_PER_BATCH`.
- When `RATE_LIMIT_TABLE_NAME` is configured, the service also applies daily limits using `X-Checkpoint-Install-ID` and source IP counters.
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
- drops study-strategy prompts for non-study-skill goals
- repairs answer choices by inserting `expectedAnswer` when needed
- enforces four meaningfully distinct choices
- clamps difficulty to the requested minimum through 5
- returns `502` if Bedrock output has no usable questions, allowing the iOS app to fall back locally
