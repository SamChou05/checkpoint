# Read-only OpenAI model access check

This is a read-only account availability observation, not an inference qualification.
No inference, activation, subscription, agreement, API-key creation, or deployment was performed.
AWS temporary credentials remained in memory; no credentials or account identifiers are recorded.

Fresh observation window: **2026-09-22T07:47:22+00:00 through 2026-09-22T07:47:23+00:00** (UTC).

Existing AWS session credentials signed HTTPS GET requests with SigV4 service `bedrock-mantle` and the endpoint region. All requests below returned HTTP 200, but their explicit model status differs.

| Model ID | Region | HTTP | Mantle account status | Observed UTC |
|---|---|---:|---|---|
| `openai.gpt-5.6-luna` | `us-east-1` | 200 | `unavailable` | 2026-09-22T07:47:23+00:00 |
| `openai.gpt-5.6-luna` | `us-west-2` | 200 | `unavailable` | 2026-09-22T07:47:23+00:00 |
| `openai.gpt-5.6-sol` | `us-east-1` | 200 | `unavailable` | 2026-09-22T07:47:23+00:00 |
| `openai.gpt-6-astra` | `us-west-2` | 200 | `unavailable` | 2026-09-22T07:47:23+00:00 |
| `openai.gpt-5.6-terra` | `us-east-1` | 200 | `unavailable` | 2026-09-22T07:47:23+00:00 |
| `openai.gpt-5.6-terra` | `us-west-2` | 200 | `unavailable` | 2026-09-22T07:47:23+00:00 |
| `openai.gpt-5.5` | `us-east-1` | 200 | `unavailable` | 2026-09-22T07:47:23+00:00 |
| `openai.gpt-5.4` | `us-east-1` | 200 | `unavailable` | 2026-09-22T07:47:23+00:00 |
| `openai.gpt-5.4` | `us-west-2` | 200 | `unavailable` | 2026-09-22T07:47:23+00:00 |
| `openai.gpt-oss-120b` | `us-east-1` | 200 | `available` | 2026-09-22T07:47:23+00:00 |

Every unavailable response states that the model is not available for this account and directs to AWS Sales for access options. Model-list presence and successful metadata reads therefore do not establish inference eligibility. The available GPT-OSS-120b result is not evidence that it improves semantic accuracy over the current reviewer.

A same-session us-east-1 `GetFoundationModelAvailability` check for `openai.gpt-5.6-luna` returned:

```json
{
  "authorizationStatus": "AUTHORIZED",
  "agreementAvailability": {
    "status": "AVAILABLE"
  },
  "entitlementAvailability": "AVAILABLE",
  "regionAvailability": "AVAILABLE"
}
```

Despite these runtime control-plane statuses, Luna's Mantle status is unavailable in both queried regions. `GetFoundationModelAvailability` is therefore insufficient evidence of Mantle eligibility. AWS documents separate model discovery for the two endpoints; inference on Mantle additionally authorizes `bedrock-mantle:CreateInference`. Metadata reads do not test that permission.

## Documented structured transport

The prospective Luna route is `POST https://bedrock-mantle.us-east-1.api.aws/openai/v1/responses`, model `openai.gpt-5.6-luna`, using Responses `text.format` with `type: json_schema`, `strict: true`, and a schema. OpenAI's Bedrock guide lists Responses structured outputs as supported, while warning that availability is model- and endpoint-specific. This route has not been invoked or schema-qualified here.

Existing AWS session credentials can authenticate signed HTTP requests without creating an API key. The OpenAI SDK's Bedrock provider also documents AWS credential-chain signing. Authentication does not confer account model eligibility.

AWS's Luna, Sol, Terra, and Astra runtime cards mark native structured outputs unsupported. Nothing in this check justifies adding these IDs to Checkpoint's Converse `outputConfig` allowlist. A separately qualified Responses adapter could preserve the closed final-audit schema and strict local checks; the current Converse implementation is not that adapter.

Luna and Sol document reasoning efforts `none`, `low`, `medium`, `high`, `xhigh`, and `max`; Astra documents `low`, `medium`, `high`, `xhigh`, and `max` (no `none`). These are documented model capabilities, not tested account inference behavior.

## Primary sources

- [AWS model discovery and separate endpoints](https://docs.aws.amazon.com/bedrock/latest/userguide/models-get-info.html)
- [AWS Responses authentication, IAM actions, and model selection](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-responses-api.html)
- [AWS GetFoundationModelAvailability](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_GetFoundationModelAvailability.html)
- [AWS Luna model card and exact endpoint](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-56-luna.html)
- [AWS Sol model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-56-sol.html)
- [AWS Terra model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-56-terra.html)
- [AWS Astra model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-6-astra.html)
- [OpenAI Bedrock SDK authentication and Responses feature matrix](https://developers.openai.com/api/docs/guides/amazon-bedrock)
- [OpenAI strict structured-output schema rules](https://developers.openai.com/api/docs/guides/structured-outputs)
- [OpenAI Luna reasoning modes](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
- [OpenAI Sol reasoning modes](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [OpenAI Astra reasoning modes](https://developers.openai.com/api/docs/models/gpt-6-astra)
