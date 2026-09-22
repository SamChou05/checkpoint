# Native structured outputs: implementation and qualification

Current status, September 22, 2026: verified transport and answer-provenance
improvements are on `main`. The deployment defaults remain global `legacy` and
worker `inherit`; the current iOS minimum remains policy 2. Native worker rollout
and a client minimum of 4 are separate pending work. No deployment was performed
for these changes. Native formatting enforces structure, not factual correctness.
The v5 solver also passed its two-call count-five provider identity trial.
Other counts and full semantic release qualification remain separate.
See the [investigation findings](QUESTION_RELIABILITY_FINDINGS.md) for the application
bugs, controlled model comparisons and answer-highlighting evidence.

## Runtime contracts and compatibility

Every provider call selects its stage explicitly, including author repair,
top-ups, configured fallback, API/worker generation and skill-map retries. The
registry retains ten static, closed, versioned contracts and adds count-bound
solver and reviewer families:

| Contract | Shape and runtime use |
| --- | --- |
| `question_author_v1` | Historical choices array and text key. Retained for legacy compatibility and frozen evidence. |
| `question_author_v2` | Four required choice slots and an enum key; retained sorted serialization for the controlled comparison. |
| `question_author_v3` | Current native author, including repair/fallback. Fixed slots and enum key, with stem and explanation serialized before the key. Adapter derives exact answer bytes from the selected slot. |
| `skill_map_inference_v1` | Skill/objective names; server validates counts and assigns IDs. |
| `skill_map_evolution_v1` | Successor names/objectives; server validates predecessor coverage and constructs map identity/version. |
| `complete_choice_solver_v1` | Exact indexed choices with supported/refuted/uncertain declarations. Retained for legacy complete-choice and optional authored teaching. |
| `complete_choice_solver_v3` | Retained historical contract: four fixed judgment slots and six fixed unordered pair slots, reasons before verdicts; free outer array/index still requires local coverage validation. |
| `complete_choice_solver_v5_n{count}` | Native reviewer-written path: required outer object keys bind the actual validated solver input (1–40), with no model-written index. Inner v3 judgment/pair schemas and exact trusted endpoints remain unchanged. The adapter restores trusted indexes before the existing semantic gates. |
| `default_reviewer_v1` | Retained explicit native contract and legacy routing identity: verdict, exact answer, assessed difficulty, main explanation and provider-only choiceFeedback rows. |
| `default_reviewer_v2` | Inactive experiment with separate accepted/rejected union branches; failed valid-control retention. |
| `authored_solution_reviewer_v1` | Optional authored-teaching audit; cannot replace the author's teaching. Not enabled by this work. |
| `default_reviewer_v3_n{count}` | Current native final review: required object keys bind every dense post-solver item, including rejections. Trusted count is 1–40; no model-written index. Feedback fields and admission checks remain v1-compatible. |

Historical schema bytes remain stable. V3 serialization deliberately preserves
property order. Schemas contain no request-specific goals, answers or content IDs.
Count-bound grammars vary only by bounded batch cardinality and dense numeric keys.
Strict JSON/schema parsing rejects duplicate properties, nonfinite numbers,
unknown/missing fields, invalid types/enums, refusal and incomplete output before
adaptation. Application code still enforces counts, text bounds, scope and exact
identity. The author adapter guarantees four slots and key membership; it cannot
guarantee that the four meanings differ or that the selected answer is true.

Native solver slot order is derived from the stem and choice bytes independently
of the key and incoming order. Exact decoding rejects missing/extra/self/reversed
pairs. Application admission requires exactly one supported choice, three refuted
choices and exact agreement with the author's key; declared equivalent or
uncertain pairs veto the item. Different wrong answers are not automatically
equivalent. The solver and final reviewer are fallible, so agreeing declarations
are not a proof of correctness.

The solver's outer map closes the same cardinality/identity gap as the review
map. A trusted callback passes the number of reviewable candidates after input
filtering, before solver judgments; it never reads request targetCount or parses
model-authored text. All map keys and inner rows must validate before any index
is restored. This transport version adds no provider stage or verification-policy
revision and leaves legacy and optional authored-teaching routes unchanged.

V5 shares the solution, choice-judgment and pair-relation schemas through internal
`$defs`/`$ref` references. Local validation still uses the expanded schema. For
every count 1–40, resolving those references reproduces the inline v4 candidate
byte for byte, including required fields, closed objects and reason-before-verdict
ordering. The count-five schema shrinks from 11,798 to 1,489 bytes; count forty
shrinks from 93,233 to 2,809 bytes. Historical v3 and reviewer schemas are unchanged.
AWS rejected the inline v4 request because its compiled grammar was too large.
The [shared-schema trial](evidence/solver-shared-schema-qualification-20260922/RESULTS.md)
completed both count-five requests with all ten identities and exact decoding.
This establishes acceptance for the tested count/model/settings, not a numeric
compiler limit or acceptance of every locally supported count.

Native final review uses the count-bound v3 wrapper described below; legacy
review retains v1. After validating the full schema, the adapter turns any typed
false review into its trusted index and false verdict. This keeps the
rejection without discarding valid siblings because a rejected row also contains
unused text. Accepted rows must retain exact choices, complete feedback and text
bounds. The [reviewer-v2 failure](evidence/structured-reliability-20260921/REVIEWER_V2_FINDINGS.md)
remains unchanged evidence; it does not authorize switching production to v2.

Public response shape and wire verification version remain 1. Legacy
complete-choice verification earns policy 2, optional authored teaching earns 3,
and the complete native slot/pair path followed by successful final review earns
4. Historical stem-only evaluation stays at 1. Stored content is never upgraded
by changing its stamp. The client filters cached inventory by its actual required
policy while preserving history; see the [cached inventory milestone](evidence/question-reliability-release-20260922/CACHED_INVENTORY.md).

Provider deadlines, sampling/reasoning controls, guardrails, IAM scope, quotas,
durable reservations, retry ceilings and accepted partial work remain in force.
Native incompatibility fails without dropping the schema. Configured fallback
calls still carry the selected contract and consume the existing call budget.

## Verification and live evidence

The September 22 structural milestone passes all **1,124 backend tests**, Ruff,
compilation, deployment-script checks, SAM lint and a noncontainer SAM build.
All 23 service modules match each of three built artifacts. Each artifact
packages boto3/botocore 1.43.91 and validates all ten native request shapes with
`scripts/validate-native-sdk.py` under Python 3.12 `-I -S`: **30 offline checks**.
The earlier container build attempt remains unverified because Docker timed out.
These checks do not prove provider semantic accuracy or deployed queue behavior.
The subsequent reviewer-identity integration passes all **1,140 backend tests**,
Ruff, compilation, deployment-script checks, SAM lint and the noncontainer build.
It expands packaged validation to the ten static shapes plus forty count variants
per artifact (150 offline checks), with all 23 service modules identical in each
of the three delivered artifacts.

The v5 solver passes **1,150 backend tests**, SAM lint and a noncontainer
SAM build. All 23 service modules, the pinned requirements and the SDK verifier
match source in each of the three artifacts. Artifact-isolated Python 3.12
`-I -S` validates ten static, forty reviewer and forty solver request shapes per
artifact with boto3/botocore 1.43.91: **270 offline checks**, with no provider calls.
The separate live count-five trial passed structure in 64.614 and 32.737 seconds.
All ten admission decisions and forty answer labels matched gold, while one of
sixty pair labels referred to the wrong pair. That semantic error remains
reported; native field identities do not guarantee correct model judgments.

The native author now presents an output example and answer requirement that
match its actual fixed choice slots and `correctChoice` field. Previously the
same system prompt first requested legacy arrays/`expectedAnswer`, then appended
instructions forbidding them. The legacy path retains its original example;
all wire schema bytes and answer adapters are unchanged. Actual orchestration
tests validate each transmitted example against its selected schema. The full
backend suite passes 1,151 tests. This removes contradictory format instructions;
no fresh semantic accuracy improvement is claimed from this cleanup alone.

All experiments retain their prospective plans, raw attempts and failed criteria:

- [Author ordering comparison](evidence/native-author-order-20260922/REPORT.md):
  four calls, twenty generated items. The sorted arm had three plainly wrong
  keys; the ordered arm had none plainly wrong and one ambiguous recipe. This
  supports the narrow ordering change, not a general accuracy estimate.
- [Fixed-pair endpoint trial](evidence/choice-quality-release-20260922/ENDPOINT_RESULTS.md):
  four calls on twenty independently reviewed controls; ten valid items retained
  and ten defective items excluded, 80/80 correctness labels. Its strict criterion
  **failed** at 116/120 pair labels. Correct eligibility does not erase wrong
  intermediate labels.
- [Fresh full-pipeline diagnostic](evidence/question-reliability-release-20260922/STRUCTURAL_MILESTONE.md):
  thirty calls across six domains returned 29/30 requested items. Yield passed;
  the all-admitted-content criterion **failed** because audits found false
  teaching feedback, a position-dependent explanation and an ambiguous English
  item. Captures and all three audit files are retained alongside the report.
- [Earlier worker smoke](evidence/structured-reliability-20260921/PROVIDER_FINDINGS.md):
  six calls passed the then-current author/solver/reviewer contracts on two simple
  arithmetic questions. It does not qualify the later schemas or broad content.

New experiments require their own frozen scope and bounds. Do not reuse an old
call allowance, rerun failed samples invisibly or reinterpret a strict failure
as passing because a narrower metric improved. The [adaptive solver candidate](evidence/choice-quality-release-20260922/ADAPTIVE_RESULTS.md)
passed its twenty-control label criteria, but the [fresh adaptive full pipeline](evidence/question-reliability-release-20260922/ADAPTIVE_PIPELINE_RESULTS.md)
failed at 5/30 planned admissions after reviewer index failures and a solver timeout.
The [reviewer-input omission experiment](evidence/question-reliability-release-20260922/REVIEWER_ANCHORING_RESULTS.md)
also failed. Both proposed runtime changes remain unpromoted.

## Deployment and rollback

The documented synchronous Nova Lite configuration is outside the runtime native
allowlist. The worker can be enabled independently with
`QuestionBankWorkerStructuredOutputMode=native` while
`BedrockStructuredOutputMode=legacy` preserves the API and its skill-map path.
The deployment scripts validate the effective modes and all selected author,
verifier and configured fallback models against the same runtime allowlist before
SAM. Model-family recognition is separate from account access, live schema
acceptance and quality qualification. Keep fallback empty until evaluated.

Opus 5 remains outside this native allowlist. Its [official AWS model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-5.html)
lists Converse support but marks structured outputs unsupported on
`bedrock-runtime` (checked September 22, 2026). Existing legacy transport and
reasoning controls do not imply native-schema support. A regression covers every
documented Opus 5 model/profile identifier in both thinking modes, requiring
native author, solver and reviewer requests to fail before SDK creation or quota
reservation. This documents existing runtime behavior; it does not enable or
invoke the model.

Resolve exact model/profile destinations and IAM resources in the intended
account/region before a reviewed rollout. Keep budgets, timeouts, concurrency and
model selection fixed during transport enablement. Monitor schema failures,
semantic rejection, latency, inventory fill and durable call accounting.

Roll the worker back with an explicit worker `legacy` override. Changing only the
global flag cannot override an explicit worker `native`. Verify the effective
Lambda environment after deployment; the outbox makes no provider calls. A client
requiring policy 4 needs a worker that actually produces policy 4. Coordinate
rollback with that client minimum; do not relabel old inventory or claim lower
policies satisfy it. See [deployment procedures](../backend/bedrock-question-service/docs/DEPLOYMENT.md#native-structured-output-qualification-and-rollback).

The provider contract follows [AWS structured-output documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
and the [Kimi K2.5](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-moonshot-ai-kimi-k2-5.html)
and [Claude Sonnet 4.6](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-4-6.html)
capability references. Historical [nullable-schema rejection](QUESTION_TASK_OBSTRUCTION_SCHEMA_FIX.md)
and [author-only latency evidence](QUESTION_AUTHOR_SCHEMA_EXPERIMENT.md) remain
historical results, not qualification of current runtime schemas.

### Bound final-review identities

The native reviewer now receives a closed required map keyed by trusted dense
post-solver indexes. The count is passed directly by the verifier, rather than
parsed from prompt text or copied from the original request. The adapter rejects
missing, extra, duplicate, noncanonical or embedded identities before deriving
internal indexes; it never fills or repairs a model batch. Historical schemas
and legacy/authored-review routing remain available with their original bytes.

The [two-call count-five trial](evidence/reviewer-identity-20260922/RESULTS.md)
returned all ten required identities. Production preserves that schema body and
override text, including the original experimental label; the schema name and
telemetry version now identify production v3. Tests cover all counts 1–40 locally
and in the packaged SDK, but live qualification covers only count five. Cold
grammar latency at other counts remains unmeasured. Both ambiguous controls
were still accepted and faulty feedback remained, so this is an identity fix,
not semantic release qualification or authorization to change rollout defaults.
