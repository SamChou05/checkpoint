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
| `BEDROCK_MODEL_ID` | `amazon.nova-micro-v1:0` | Bedrock model ID to call through the Converse API. |
| `MAX_QUESTIONS_PER_BATCH` | `20` | Caps per-call output cost even if the app requests a larger bank. |
| `BEDROCK_MAX_TOKENS` | `6000` | Maximum Bedrock response tokens. |
| `BEDROCK_TEMPERATURE` | `0.35` | Lower temperature keeps answers more stable. |
| `CHECKPOINT_BACKEND_TOKEN` | empty | Optional bearer token gate for early testing. Leave empty if using API Gateway/Lambda throttling only. |
| `CORS_ALLOW_ORIGIN` | `*` | Function URL CORS origin. |

## Deploy With AWS SAM

```bash
cd backend/bedrock-question-service
sam build
sam deploy --guided
```

Suggested guided values:

- Region: same region where the selected Bedrock model is enabled.
- `BedrockModelId`: start with a cheap model you have enabled, such as `amazon.nova-micro-v1:0`, then compare quality.
- `MaxQuestionsPerBatch`: `20` for early cost control.
- `BackendToken`: optional for internal TestFlight testing.

The deployed stack outputs `QuestionEndpoint`. Configure the iOS app to use that URL as its internal AI backend endpoint.

## IAM

`template.yaml` grants Bedrock invoke permissions to the Lambda role. It uses `Resource: "*"` because Bedrock model and inference-profile ARNs vary by model and region; tighten this after choosing the exact production model/inference profile.

## Cost Controls

- The app caches generated batches and does not call AI on every blocked-app attempt.
- This service caps the requested batch size with `MAX_QUESTIONS_PER_BATCH`.
- API Gateway or Lambda Function URL throttling should be enabled before broader TestFlight.
- Keep the optional `CHECKPOINT_BACKEND_TOKEN` for early testing if you expose a Function URL directly.

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
- enforces four choices
- clamps difficulty to the requested minimum through 5
- returns `502` if Bedrock output has no usable questions, allowing the iOS app to fall back locally
