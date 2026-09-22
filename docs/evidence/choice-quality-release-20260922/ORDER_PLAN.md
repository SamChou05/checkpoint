# Prospective paired choice-field ordering experiment

The completed four-call qualification failed: 77/80 correctness labels matched
gold, including three labels contradicted by their following explanations. It
also yielded 120/120 correct pair relation labels. Correctness objects were always
`choice → judgment → reason`; pair objects were always
`leftChoice → reason → relation → rightChoice`. This motivates, but does not prove,
a causal ordering hypothesis.

## Single intervention

The reason-first arm changes **only** the native schema's choice-row `properties`
and `required` order from `choice, judgment, reason` to `choice, reason, judgment`.
Both arms preserve names, types, enums, strictness, item structure, complete-pair
schema, schema name/description, exact system/user prompts, examples, option order,
model and inference settings. The schema is serialized with insertion order so
the one intentional property-order change survives. The existing prompt example
remains unchanged; no new instruction to reason first is added.

JSON Schema object-property order does not itself require output order. Record
the returned raw object-key order for all 80 choice rows and 120 pair rows per
arm. If the model does not actually move reasons before judgments, the intervention
was not achieved and no semantic result establishes the proposed mechanism.

Both arms reuse the identical twenty independently reviewed cases from
`controls-draft.json`, with the exact five-item batches, rotated options and
requests from `plan.json`. These are reused diagnostic controls, not unseen test
cases. Gold and the earlier failed outcome remain unchanged. Author keys and gold
never enter the solver requests. The local scorer uses the same archived candidate
APIs, strict JSON/native schema, exact-choice and pair-coverage validations.

## Frozen dispatch and stop rules

Eight calls maximum: four baseline and four reason-first. Dispatch order is fixed:

| Call | Batch | Arm |
| --- | --- | --- |
| 0 | 0 | baseline |
| 1 | 0 | reason-first |
| 2 | 1 | reason-first |
| 3 | 1 | baseline |
| 4 | 2 | baseline |
| 5 | 2 | reason-first |
| 6 | 3 | reason-first |
| 7 | 3 | baseline |

Use `us.anthropic.claude-sonnet-4-6`, temperature 0.2, disabled thinking, 6,000
maximum output tokens, 75-second read timeout, three-second connect timeout and
one SDK attempt. No retry, repair, replacement, author call, extra model stage, or
production change is part of this experiment. Stop all remaining calls on the
first transport, abnormal completion, truncation, JSON/schema, identity/coverage or
reason-bound failure. Semantic errors do not stop the remaining frozen calls.
Preserve failures and unattempted cases in the planned denominator. Record actual
usage, latency and returned ordering for every attempted call.

## Prospective interpretation

Report each arm separately against fixed denominators: four completed calls,
ten valid retained, ten defective excluded for the expected gate, 80 correctness
labels, 120 pair labels, twenty complete gold decisions, and uncertain counts.
Also show paired item transitions, actual order adherence and token/latency
changes. Keep the earlier four-call result separate; do not pool it selectively
with the new baseline.

A qualifying candidate must achieve the reason-before-judgment order on 80/80
choice rows, complete four structurally valid calls without truncation/repair,
retain 10/10 valid controls, exclude 10/10 defective controls for the expected
reason, and match all 80 correctness and 120 pair labels without uncertainty.
Evidence supporting this narrow hypothesis additionally requires fewer incorrect
correctness labels than the contemporaneous baseline and no pair-label regression.
Equal performance does not demonstrate a semantic benefit. If all-gold candidate
accuracy fails, do not declare qualification because individual examples improve.

There is only one sample per arm/batch. This comparison can support a bounded
implementation choice, but cannot prove determinism, general model accuracy,
release-wide yield or statistical significance. No label or criterion will change
once any provider output is received. Parent review of the frozen plan is required
before `--run`; the runner's default mode makes no provider calls.
