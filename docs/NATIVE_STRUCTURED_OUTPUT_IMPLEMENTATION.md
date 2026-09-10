# Native structured outputs: implementation and qualification

September 9, 2026. This implementation adds optional provider-constrained JSON
to the existing Bedrock pipeline. `BEDROCK_STRUCTURED_OUTPUT_MODE` and its SAM
parameter `BedrockStructuredOutputMode` default to `legacy`. No deployment,
production setting, model selection, or live inference was performed for this
change. Native formatting does not establish factual accuracy or unique answers.

## Runtime contracts and compatibility

Every production provider call selects its stage explicitly, including author
repair, top-ups, configured fallback attempts, API/worker generation, and
skill-map retries. Native mode uses six closed, versioned, static schemas:

| Contract | Native shape and application-owned checks |
| --- | --- |
| `question_author_v1` | Questions with text, choices, key, explanation, topic, difficulty, format, and optional map tags. Application code enforces counts, bounds, map membership, scope, and history. |
| `skill_map_inference_v1` | Skill and objective names. The server validates 3–6 skills and 2–5 objectives and assigns IDs. |
| `skill_map_evolution_v1` | `advance` changes with predecessor and successor names/objectives. The server enforces predecessor coverage and constructs IDs, replacements, and the new map version. |
| `complete_choice_solver_v1` | Exact indexed choices with `supported`, `refuted`, or `uncertain` judgments. Zero/multiple supported answers remain representable and are rejected by application policy. |
| `default_reviewer_v1` | Indexed verdict, answer, assessed difficulty, explanation, and provider-only `choiceFeedback` rows. Rejections use `valid:false`, `answer:""`, `explanation:""`, and `choiceFeedback:[]`; an integer difficulty remains required. |
| `authored_solution_reviewer_v1` | Indexed verdict, answer, assessed difficulty, explanation support, and issues. False, empty-answer, unsupported, uncertain, and issue-bearing results remain expressible. This unrelated mode remains opt-in. |

Schemas contain no request-specific goals, choices, IDs, answers, or counts.
Stable serialization produces deterministic hashes and fresh request wrappers.
Native responses undergo strict JSON and schema validation before adaptation;
duplicate keys, nonfinite numbers, unknown/missing fields, incorrect types,
invalid enums, refusal, and incomplete output fail admission. The default
reviewer adapter rejects duplicate or malformed feedback rows before constructing
`choiceExplanations`; downstream review requires exactly the offered choices and
indexes. Choice bytes and feedback text are preserved by the adapter.

Independent complete-choice solving and final review retain their separate
visibility and rejection rules. The optional authored-solution reviewer cannot
rewrite the author's explanation or discard incoming teaching. The public iOS
response remains unchanged, including textual choices/keys, feedback bindings,
map metadata, and service-owned verification. Wire verification stays at version
1, complete-choice policy at revision 2, and optional authored-solution policy at
revision 3. Historical eval callers explicitly select legacy transport; frozen
prompt bytes and captured evidence are not reinterpreted.

Provider deadlines, sampling/reasoning settings, guardrails, IAM scope, quotas,
durable call reservations, retry ceilings, and accepted partial work remain in
force. Native SDK/service request incompatibility fails without dropping the
schema or switching models. Ordinary configured fallback calls still carry the
selected stage schema and consume the existing budget.

## Packaging and automated evidence

Lambda artifacts package boto3 and botocore **1.43.91** from the runtime
`requirements.txt`; updating eval dependencies or relying on Lambda's installed
SDK is insufficient. Run `scripts/validate-native-sdk.py` with Python 3.12
`-I -S` against each built function directory. It requires the pinned versions,
loads packages and Bedrock service-model data from that artifact, validates all
six Converse request shapes, and makes no network or provider calls. See the
[build commands](../backend/bedrock-question-service/docs/DEPLOYMENT.md#native-structured-output-qualification-and-rollback).

Completed preparation checks, with controlled provider fixtures:

- Final isolated full backend run: **1,027 tests passed, no skips**, on Python
  3.12.11 with the pinned runtime SDK and jsonschema 4.25.1 installed.
- Ruff, Python compilation, deployment-script tests, and `git diff --check` passed.
- Existing iOS contract/preservation suites: **102 tests passed, no skips**.
- SAM template validation with lint passed.
- Noncontainer SAM build passed for all three functions; artifact SDK validation
  passed all **18 request-shape checks**.

The initial GitHub run exposed a pre-existing test's assumption about malformed
HTML. Newer Python patch releases tolerate that fixture. A separate test-only
commit now injects failure after real partial extraction and verifies no partial
text escapes; all 20 source-acquisition tests pass on Python 3.12.11 and 3.14.6.
Acquisition policy is unchanged. See PR checks for final GitHub runner results.
CI and manual deployment validation now build all three artifacts and require
the artifact SDK verifier to pass before proceeding.

The Lambda container build remains unverified because the local Docker server
timed out. A noncontainer build and local SDK shape validation do not establish
Lambda container compatibility or Bedrock's acceptance of the JSON schemas.

## Bounded live qualification plan

Keep deployment in legacy mode while preparing an explicitly authorized test
environment. The runtime capability allowlist recognizes documented Kimi K2.5
and Claude Sonnet 4.6 identifiers; it does **not** mean those deployments have
passed live qualification. The documented synchronous API uses Nova Lite, which
is outside that allowlist. Because the native flag applies to both API and
worker, do not enable it until every role is compatible and independently
qualified. Do not automatically change the synchronous model to make it fit.

1. Record the exact resolved model/profile for synchronous authoring, worker
   authoring, skill-map planning, solver/reviewer, and any configured fallback.
   Resolve inference-profile destinations in the intended account and region
   using `GetInferenceProfile`; confirm narrowly scoped IAM, access, model
   support, and runtime recognition for each role. Keep account identifiers and
   credentials out of published evidence. An opaque application profile needs
   reviewed runtime support before it can pass the allowlist.
2. Freeze synthetic goals and the six schema hashes, model settings, ordinary
   timeouts, and call limits. Allocate **at most 12 provider attempts total,
   including retries**: one first and one repeated request for each of the six
   schemas. Exercise author → independent solver → default review with those
   fixtures and separately check inference, evolution, and optional authored
   review. If optional authored review is excluded, mark it unqualified and use
   at most ten planned calls. Never enable that mode merely to fill the matrix.
3. Reserve/count every dispatch. A retry consumes a planned slot; it never
   increases the 12-attempt ceiling. Stop at the ceiling, deadline, or quota
   limit. If distinct role/model combinations cannot all fit, report precisely
   which remain unqualified and keep rollout disabled. One model's result does
   not qualify another role or resolved profile.
4. Separate normal completion, service/schema rejection, refusal/truncation,
   schema validation, semantic rejection, elapsed time, tokens, and durable/local
   call counts. Report accepted partial work and first/repeated measurements
   independently. Do not call them confirmed cold/warm measurements when grammar
   cache state is unobservable. Inspect the synthetic accepted and rejected
   content separately from operational metrics.
5. Keep operational metrics bounded: stage, mode, schema name/version/hash,
   classified outcome, elapsed time, tokens, and call counts. Never log learner
   text, keys, reasoning, credentials, or provider exception messages. Retain
   synthetic qualification evidence privately; passing formatting checks does
   not establish general correctness, useful yield, or production latency.

No live-provider compatibility, first/repeated latency, semantic yield, resolved
deployment profile, or end-to-end deployed worker result is qualified by this
implementation's automated tests. Do not raise timeouts, budgets, or concurrency
to obtain a passing smoke result.

## Deployment review and rollback

After the remaining qualification and deployment review, stage a parameter-only
enablement of `BedrockStructuredOutputMode=native` while keeping model and
operational settings fixed. Monitor request/schema failures, semantic rejection,
latency, inventory fill, and call accounting. Restore
`BedrockStructuredOutputMode=legacy` through the stack to roll back, then verify
`BEDROCK_STRUCTURED_OUTPUT_MODE=legacy` on both API and worker Lambda functions.
The outbox makes no provider calls. Retain accepted inventory and its existing
verification stamps; neither direction needs an iOS, bank, or history migration.

The request format and supported subset follow [AWS structured-output documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html).
Capability references are the [Kimi K2.5 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-moonshot-ai-kimi-k2-5.html)
and [Claude Sonnet 4.6 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-4-6.html).
AWS's documented capability is distinct from the deferred live qualification
above. The historical [nullable-schema rejection](QUESTION_TASK_OBSTRUCTION_SCHEMA_FIX.md)
and [author-only latency experiment](QUESTION_AUTHOR_SCHEMA_EXPERIMENT.md) remain
unchanged evidence, not qualification of these six runtime schemas.
