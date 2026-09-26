# Replicated native author cardinality trial: review candidate

This package is an offline-prepared proposal for a later live trial after independent technical review and freeze. The baseline is the existing native array author contract; the candidate is the opt-in native count-bound fixed-map contract. Neither this document nor `--prepare` dispatches AWS or model calls. `--execute` reads only `plan.json` with `status: frozen` and the exact reviewed file hash; the proposal is saved under a different filename so it cannot run accidentally. No deployment or default change is part of this trial.

The source checkout starts from origin/main `99cd50a3ed7ee8babe98ec9e8763cdd9f9edff53`. The earlier single-pair trial found 3/5 usable array rows and 4/5 count-bound rows if novelty was assessed within each arm. Its frozen plan did not specify whether a later candidate row was disqualified for repeating a comparator-arm scenario. This trial resolves that ambiguity prospectively: **primary novelty is within each five-row arm for each assignment**. Report cross-arm and cross-assignment repetition separately as sensitivity, without changing the primary numerator. An exact duplicate inside one arm earns no usable credit; a near duplicate across arms can reveal lack of independent content variation but does not favor the first-dispatched arm in scoring.

## Fixed assignments and call order

`fixed_requests.json` is the single source of the exact two assignment payloads and four job identities. Each pair uses one identical normalized request, model, generation settings, and timeout. The only treatment differences are native schema and its required prompt override. Order alternates to reduce a systematic first/second-call advantage. Each job requests five original prose MCQ slots with minimum difficulty 2.

| Dispatch | Assignment | Contract | Requested rows |
| ---: | --- | --- | ---: |
| 1 | archive circulation | array | 5 |
| 2 | archive circulation | count-bound | 5 |
| 3 | greenhouse alerts | count-bound | 5 |
| 4 | greenhouse alerts | array | 5 |

The two topics test eligibility, thresholds, precedence, and timed windows in self-contained fictional rules. Each item must state all facts needed, have exactly one answer, provide accurate teaching, and avoid repeated scenarios or answer mechanisms inside its five-row arm. The same assignment prompt goes to both arms so content scope does not confound the schema comparison.

The model is `moonshotai.kimi-k2.5` in `us-east-1`, thinking disabled, `maxTokens=16000`, temperature `0.2`, SDK connect timeout 3 seconds and read timeout 200 seconds. The named AWS profile is `default`, expected provider method `login`, and expected account `239342516379`, matching the prior trial. These are reviewable pins, not a claim that credentials remain available; a single-attempt STS `GetCallerIdentity` preflight must reverify the account. The harness rejects ambient exported AWS credentials and AWS endpoint overrides. It pins STS to https://sts.us-east-1.amazonaws.com, checks the constructed STS client endpoint before GetCallerIdentity, freezes the named profile credentials once, uses the same in-memory snapshot for STS and Bedrock signing, and scans safe response text for that snapshot's credential strings. An expired snapshot ends the trial; it is never refreshed during the run.

**Maximum AWS calls: five**—one STS identity request plus four Bedrock Converse author requests. There is at most one eligible Converse dispatch per job, no warmup, SDK retry, fallback model, JSON retry, solver, reviewer, repair, replacement, or top-up. The exact provider request, native schema, prompt, source hashes, Python and SDK versions, account, endpoint, and plan hash are pinned in the proposal. `_generate_provider_payload` receives `ProviderCallBudget(1)` and the actual selected native schema. A budget-overrun attempt stops the remaining jobs. Two pairs can take over 13 minutes at the read timeout bound; a live operator should reserve that time.

## Capture and structural eligibility

The harness creates an exclusive, fsynced capture before credential setup. It records setup failures with zero author calls. Immediately before each Converse call, it rechecks the frozen plan, source, fixed input, exact regenerated request, capture integrity, and account/endpoint pins, then durably reserves that job. A response observation is fsynced before adaptation. Any drift after a response leaves the reserved observation and stops further dispatch. A second run cannot overwrite or resume the capture.

For each job record safe visible text blocks, stop reason, usage, elapsed time, raw count and map keys, schema and adapter result, typed-row count, adapted payload if available, and provider error class/code. The 256 KiB visible-output cap, duplicate-key rejection, non-JSON-constant rejection, malformed-output redaction, and credential echo scan follow the tested prior harness. Do not save reasoning blocks, signatures, secrets, or raw AWS responses. Redaction or provider failure consumes the original requested slots; no surviving row may replace a failed slot.

A batch is structurally eligible only if it has a normal `end_turn`, strict JSON parse with no duplicate members, validates against its actual native schema and local adapter, and contains exactly five raw rows. A count-bound map must have precisely keys `"0"` through `"4"`; the array must have length five even though its native schema permits other lengths. Sanitizer admission and schema validity never count as semantic correctness. Record every raw position, missing required key, and surplus row under its original job identity.

## Blind content review and scoring

Only after a complete four-job capture, the operator supplies the exact out-of-band capture SHA-256 to `--blind-project`. The projection creates 20 requested original prose slots, plus any surplus rows, under shuffled opaque IDs with cryptographically rotated choices. The worksheet has no arm, key, or author explanation. A separate owner-readable private map retains source identity, raw key, key, and teaching. If the capture is incomplete, projection refuses; the report still keeps all four five-slot denominators and grants no favorable-trial credit for unattempted arms.

Two independent assessors solve every displayed stem and four choices before seeing keys, explanations, or arms. Each writes a separate review with an independent answer or `unavailable`, reasoning, uncertainty, premise sufficiency for a **unique answer**, all four choice correctness judgments, and all six pair-meaning judgments. Readable multiple-answer or underspecified rows require `unavailable`, uncertainty true, and premise sufficiency insufficient or uncertain. Unavailable projected rows use `unavailable` in every judgment. The `--lock-blind` step requires two separate, nonidentical original review files (`--review-a` and `--review-b`), validates each complete judgment, and writes one joint lock containing both review hashes. It checks every worksheet item, choice rotation, source ordinal, key, explanation, and shape against the pinned capture. `--unblind` refuses a missing, changed, identical, or single review; only the exact joint lock hash can reveal author material. Preserve disagreements and both original blind reviews; an adjudication must be written without changing the captured rows.

After unblinding, assess author-key alignment, explanation accuracy, premise sufficiency, four distinct plausible distractors, topic and difficulty fit, **within-arm** novelty, and existing local representation/safety/quality gates without repair. For typed rows there are none in this matrix. An original slot is usable only if the displayed item has one uniquely warranted answer, its author key and all teaching are correct, choices and topic fit the request, it is novel within its five-row arm, and local gates accept it. Any uncertainty fails usable credit. A duplicate, filler, extra, malformed, or missing row cannot be substituted into an original slot. Keep separate cross-arm and cross-assignment novelty sensitivity counts and examples; do not let the fixed call order decide primary usability.

The primary outcome is usable original slots out of 10 in each arm, plus two per-assignment pairs and batch structural eligibility. A candidate qualifies for a **broader follow-up trial only if both candidate batches are structurally eligible, at least 8/10 original candidate slots are usable, the candidate total is no lower than the baseline total, and candidate usability is no lower than baseline in both assignment pairs**. These criteria are conjunctions; a failed or incomplete batch remains in the denominator. A favorable trial does not establish a population error rate, justify changing the default, or authorize deployment. Report structural and content results separately, including all cross-arm novelty sensitivity, before any product decision.

## Offline preparation and handoff

Run with the pinned Python 3.12 environment:

```sh
PYTHONPATH=/tmp/checkpoint-reliability-jsonschema-deps:/tmp/checkpoint-probe-pinned-deps:tests:. \
  /tmp/checkpoint-reliability-20260921-venv/bin/python \
  docs/evidence/author-count-bound-replication-20260926/author_probe.py --prepare
PYTHONPATH=/tmp/checkpoint-reliability-jsonschema-deps:/tmp/checkpoint-probe-pinned-deps:tests:. \
  /tmp/checkpoint-reliability-20260921-venv/bin/python -m unittest \
  discover -s docs/evidence/author-count-bound-replication-20260926 -p 'test_*.py'
```

`--prepare` uses socket-free fake clients through the actual author path and writes `plan-candidate.json`, which is deliberately non-executable. A separate `plan-frozen-proposal.json` contains the exact reviewed candidate with only `status` changed to `frozen`; it is **not** the live `plan.json` path. Independent reviewers must check the fixed assignments, account, all source/request/schema/prompt hashes, and criteria. After the technical review, the operator can copy the proposal byte-for-byte to `plan.json`, record its exact SHA-256 out of band, and then decide whether to invoke `--execute --plan-sha256 <reviewed-hash>`. Any source, harness, document, account-pin, or input change requires regenerating a new proposal and review. No AWS call is part of this handoff.
