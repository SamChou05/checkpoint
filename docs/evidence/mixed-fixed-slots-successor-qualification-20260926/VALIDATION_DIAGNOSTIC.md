# Mapped fixed-slot trial: provider validation diagnostic

The one-shot mixed worker trial failed at its first Converse call because Bedrock rejected the **compiled native output grammar as too large**. This is a request validation failure before any usable model response, not an observed failure to follow the five-slot prompt. No second Bedrock invocation was made for this diagnostic.

The committed [capture](capture.json) (SHA-256 `17c49df0d75cb8aab4cf90bc8816068099cc557b661c719f98ad4c234a0b7831`) records one attempted dispatch, `ValidationException`, 0.560082 seconds in the recorder, no response or reported token usage, and a global stop. Its [frozen plan](plan.json) has SHA-256 `ab83d05ca603f0a978e9018108bc2e89723ddc198f71cdfb9fa93c46b8cfed5d`. The attempted native JSON Schema was 5,519 UTF-8 bytes, SHA-256 `316024552a9f67901c652c33ec73a9e311757e4efadd5a7b66bb97666cc2aebb`.

A **read-only CloudTrail `LookupEvents`** for the trial time recovered the service detail that the harness deliberately did not retain:

| Field | Value |
| --- | --- |
| CloudTrail event ID | `e522125f-88b4-4bf5-9bd8-57cb7e976797` |
| Event time | `2026-09-27T00:40:31Z` |
| AWS request ID | `6e9d2aa8-1ca7-4dbf-a0e1-b9b8cab6047e` |
| Event and Region | `Converse`, `us-east-1` |
| Error code | `ValidationException` |
| Error message | “The model returned the following errors: The compiled grammar is too large, which would cause performance issues. Simplify your tool schemas or reduce the number of strict tools.” |

The error text directly identifies grammar compilation, rather than the inference parameters, transport, or profile, as the rejection point. The request used the same active `us.anthropic.claude-sonnet-4-6` inference profile, 16,000-token ceiling, and adaptive/high reasoning configuration as the predecessor mixed trial, which reached generation. A read-only `GetInferenceProfile` returned `ACTIVE`; model invocation logging is disabled in this Region. The captured request has no tool definitions, so the message's “strict tools” clause is generic Bedrock wording; this failure concerns the `outputConfig.textFormat` JSON Schema. CloudTrail's `requestParameters` exposes only `modelId` and `inferenceConfig`, so it cannot independently show the schema bytes. The durable capture supplies those bytes and their hash.

The mapped schema defines five required slots and duplicates a complex constructed-author row for the two assigned skills, with per-skill fixed tags. Offline comparison finds six `$defs`, four `anyOf` nodes and 35 `enum` nodes in its 5,519 bytes; the locally generated generic constructed fixed-five schema has four `$defs`, three `anyOf` nodes and 15 `enum` nodes in 3,336 bytes. These counts indicate a concrete simplification path, but Bedrock does not publish the effective compiled-grammar size or which rule crossed its threshold. Byte size alone is not a proven predictor. The evidence does not establish whether the generic fixed-five schema would be accepted for this exact request, whether its five rows would be content-usable, or whether the mapped tags would survive local validation. The one-shot trial remains failed and cannot be resumed.

For a **separately reviewed prospective trial**, keep the five required slots but share one constructed-author row definition, place skill allocation in the prompt, and enforce the exact 3:2 skill/objective assignment with the existing local validator before accepting any row. First compare schema shape and run socket-blocked contract tests offline; then freeze a new one-shot plan and qualification gate before any provider dispatch. Do not broaden the default route or infer semantic MCQ quality from a grammar that merely compiles. AWS [structured-output documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html) says Bedrock validates and compiles supplied JSON Schemas and returns a 400 error for unsupported schemas; that describes the provider stage, while CloudTrail supplies this trial's exact failure reason.
