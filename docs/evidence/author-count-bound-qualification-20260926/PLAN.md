# Draft author count-bound qualification (unfrozen)

This package is preparation only. `plan-draft.json` is deliberately marked
`draft`; the harness refuses to execute it. No Bedrock call, AWS credential
export, deployment, bank write, solver, reviewer, repair, or top-up is part of
preparation. Root must independently review the exact requests, source hashes,
matrix and criteria before copying a reviewed plan to `plan.json`, filling its
credential pin, and recording the new plan SHA-256 out of band. The user
already authorized experiments; this package remains a draft because account
access and the fixed execution pins still need review.

## Question and fixed matrix

The candidate is the opt-in `QUESTION_AUTHOR_CARDINALITY_CONTRACT=count_bound`
added on main at `029ca76`; the baseline is the unchanged native array author
contract. The two prose arms have the *same* normalized five-item request,
model, generation settings and timeout. They differ in the selected native
schema, its required prompt override, and the resulting provider request hash.
Their fictional exhibit scheduling scope is fresh relative to prior native
author evidence and requires all premises inside each item. The two smoke
jobs use the count-bound schema at `n=1` mixed and `n=5` constructed to check
Bedrock grammar acceptance for those shapes. They are not paired content-yield
comparisons with prose or with historical runs.
The mixed smoke uses one exact rational expression, `(3/4 + 5/6) / 2`, and
explicitly requests a flat-graph `exact_value` task. A word problem would
invite a valid prose branch and leave the typed grammar untested.

| Order | Job | Mode | Shape | Requested slots | Role |
| --- | --- | --- | --- | ---: | --- |
| 1 | `prose_array_n5` | prose | array | 5 | baseline |
| 2 | `prose_count_bound_n5` | prose | fixed map | 5 | candidate |
| 3 | `mixed_count_bound_n1` | mixed quantitative | fixed map | 1 | grammar smoke |
| 4 | `constructed_count_bound_n5` | constructed quantitative | fixed map | 5 | grammar smoke |

At most four Bedrock Converse author calls occur, exactly one eligible
dispatch per job. There are no warmups, SDK retries, JSON retry dispatches,
fallback models, replacements, or top-ups. `_generate_provider_payload` runs
with `ProviderCallBudget(1)` and the actual selected native schema; even if it
tries to construct an internal JSON retry, that budget forbids a second
Converse dispatch. An attempted budget overrun stops the entire trial after
the first call's sanitized response is saved; later jobs remain unattempted.
The model is `moonshotai.kimi-k2.5` in `us-east-1`, Kimi
thinking disabled, `maxTokens=16000`, temperature `0.2`, SDK connect timeout
3 seconds, read timeout 200 seconds and `total_max_attempts=1`. All four jobs
use the same model/settings; their mode-specific prompts and schema are
predeclared treatment or smoke differences. Four maximum-length attempts
could take over 13 minutes, so a later operator must reserve enough time.

Before any Bedrock dispatch, the future execution path requires the exact
frozen plan hash, matching runtime source/input/harness hashes, an ancestor
source revision, exact regenerated provider requests, a pinned named AWS
profile/provider method/account, and the pinned Bedrock endpoint. It rejects
ambient exported AWS credentials. A read-only, single-attempt STS
`GetCallerIdentity` preflight verifies the account; this is one additional
AWS identity request, **not** an author/model call. If a strict four-*AWS*-call
ceiling is required, replace this preflight with an independently verified
credential mechanism before freezing, rather than silently omitting it.
The named AWS profile supplies one frozen credential snapshot. A separate
static SDK session uses those exact in-memory access key, secret and session
token values for both the account-verifying STS request and every Bedrock
signature; those same values are the response echo-scan inputs. The harness
checks the static signer's values before STS. Expiry during this four-call
trial may fail a planned call; no refresh or replacement is permitted.
No secret value or raw AWS response is saved. An exclusive, fsynced capture is created
before AWS setup and STS, recording setup failures with zero author calls.
Each author call receives a durable reservation immediately before Converse;
an interruption therefore leaves an attempted/uncertain call marker rather
than an apparently unused job. The sanitized visible response or safe error
observation is fsynced immediately after Converse, before runtime adaptation.
The frozen plan, source/input hashes, exact requests and capture-file
integrity are rechecked before every dispatch, immediately before marking
an assessment complete, and at final completion. Drift after a provider
response leaves its reserved response in the capture and stops globally.
A second run cannot overwrite or resume the capture.
The draft pins the SHA-256 of every service Python file, service requirements,
the harness, this assessment document, fixed requests, Python version, and
boto3/botocore/jsonschema versions. Any edit requires regenerating and
reviewing a new draft before freeze.

## Predeclared observations and eligibility

For every job, retain the exact safe visible text blocks, stop reason, usage,
elapsed time, raw question count/map keys, schema/adapter outcome, adapted
payload if successful, and provider error *class/code* if unsuccessful.
Reasoning text and signatures are never captured; only their block count is.
Visible text is capped at 256 KiB of UTF-8 bytes including joined block
separators. Stop reasons and usage fields are validated against allowlists;
unknown or nonnumeric metadata is not persisted. Non-object content blocks
cause visible output to be omitted. The same bounded `parse_visible_json`
helper drives both capture safety and structural assessment. Before
persisting, it parses all visible JSON, including duplicate
members, and scans decoded values and raw text for the in-memory AWS credential
strings. Malformed JSON, duplicate keys or credential text causes the *entire*
visible output to be omitted from disk with a redaction reason; the unchanged
response still reaches the runtime and the call is an ordinary failed call.
This safety exception to raw-output retention is prospective and tested with
socket-blocked Unicode-escaped-secret fakes.
Requested slots remain in the denominator after a missing, extra, malformed,
truncated, or unattempted output. Zero returned rows is not reported as zero
content errors: its semantic assessment is unavailable.

**Structural eligibility** is judged before content quality. A job must
produce a normal `end_turn` response with the pinned 200-second read bound,
strictly parse as JSON without duplicate keys or non-JSON constants, pass the
actual selected native contract/transport schema and local adapter, and
contain exactly the requested raw number of rows. For fixed maps every key
from `"0"` through `"n-1"` must be present, with no extra keys. The array
baseline must contain exactly five rows even though its schema itself permits
other lengths. A provider validation failure, missing/extra slot, filler row,
or adapter rejection cannot be hidden by parsing only the returned survivors.
The smoke jobs answer only whether these fixed native grammars are accepted
and produce structurally eligible complete outputs on one attempt each.

**Independent semantic assessment** occurs after raw capture, without using
the author's key, explanation or generated compiler output to decide an
answer in advance. An assessor first solves each stem and visible choices,
then checks the supplied key, explanation, premises, topic/difficulty fit,
four distinct plausible choices, and cross-row novelty. For typed tasks the
unchanged local exact compiler may be run as a separate diagnostic; any
compiler rejection or incorrect derived teaching is retained under the
original `[job_id, raw_row_position]` identity. A row is usable only if a
unique answer follows from stated premises, the claimed key and all teaching
are correct, choices and topic fit the request, and the row survives existing
local representation/safety/quality gates without repair. Uncertain judgments
fail usable credit. Record every raw slot, including structurally invalid or
surplus rows; do not substitute a new item into a failed requested slot.
Structural schema validity and sanitizer admission are not correctness stamps.

The mixed smoke must actually return its one quantitative typed row, and the
constructed smoke must return five quantitative typed rows, for their typed
grammar to earn smoke credit. The envelope's `anyOf` also permits prose rows;
such a response could be structurally valid yet leave the typed grammar
untested. The capture records the typed-row count separately from structural
eligibility. Compiler validity and content correctness remain separate
assessments.

The primary paired comparison is usable original prose slots out of five in
each arm, alongside complete-batch structural eligibility. The candidate
earns a follow-up trial only if its batch is structurally eligible, at least
four of its five original slots are independently usable, and its usable
count is no lower than the baseline count in this fixed pair. These
prospective criteria are embedded in the hashed plan alongside the hash of
this document. A favorable single pair supports only a broader replicated
trial; it cannot establish a population error rate or justify changing the
default. Count-bound could
lower usable yield by filling required keys with repetitive, invalid or
semantically wrong rows even if exact raw cardinality improves. Smoke results
cannot qualify mixed/constructed content. No numerical "winner" is declared
from grammar acceptance alone.

The assessor should write a separate, append-only adjudication after capture:
`job_id`, original row position or required missing key, blinded independent
answer, author key, unique-answer status, premise sufficiency, explanation
accuracy, distractor distinction/plausibility, topic/difficulty fit, novelty
with prior rows, local gate results, uncertainty and usable decision. Preserve
disagreements and raw output; never edit a model response to improve a score.

Before any author key or explanation is exposed to the assessor, run
`--blind-project` on the completed frozen capture, supplying the exact capture
SHA-256 printed by `--execute` as `--capture-sha256`. This out-of-band handoff
prevents an edited capture from becoming a new self-consistent worksheet. The
projection creates ten original
prose slots (plus any surplus rows) under random opaque IDs in a shuffled,
keyless worksheet. Each valid row has a cryptographically chosen cyclic
rotation of its four choices. The worksheet contains no arm, author key or
explanation. A separate private mapping (owner-readable file mode) holds
source identities, original choice labels, keys and explanations. Both files
are exclusive and hashed; the projection prints the private-map SHA-256 for
the lock step. No scoring may use the private map yet.

If the capture lacks all four completed predeclared jobs, `--blind-project`
refuses to create a worksheet. The report still carries five requested
original prose slots per arm; unattempted or incomplete arms earn zero
favorable-trial credit and cannot be rescued by a later worksheet. A complete
four-job capture can still include a failed response, which appears as five
unavailable prose slots for that arm when no safe rows were returned.

The assessor saves `blind-review.json` with an `answers` object keyed by every
worksheet ID. Each entry must contain `independent_answer` (`A`/`B`/`C`/`D`
or `unavailable`), nonempty `reasoning`, Boolean `uncertain`, a
`choice_judgments` object with exactly `A`, `B`, `C`, `D` marked `correct`,
`incorrect` or `uncertain`, a `pair_relations` object with exactly `AB`, `AC`,
`AD`, `BC`, `BD`, `CD` marked `distinct`, `equivalent` or `uncertain`, and
`premise_sufficiency` marked `sufficient`, `insufficient` or `uncertain`.
An unavailable row requires `unavailable` for the answer, premise and all
ten choice/pair judgments, plus `uncertain: true` and a reason. The six pair
judgments are independent meaning comparisons, not text-equality checks.
For a readable but underspecified or ambiguous row, the assessor may record
`independent_answer: unavailable` only with `uncertain: true` and premise
sufficiency `insufficient` or `uncertain`, while still completing all choice
and pair judgments.

Run `--lock-blind` with the exact `--private-map-sha256` printed by
projection. The lock verifies each private source ordinal, raw map key,
author key/explanation, displayed choice rotation and raw-shape diagnostic
against the pinned capture, then saves a digest of the capture, worksheet,
private map and complete blind judgments. An edited map cannot be laundered
by simply supplying its new hash. The exact lock SHA-256 must then be supplied to
`--unblind`; it refuses any changed artifact and writes a separate joined
review for key/explanation and semantic-content assessment. The blind answer
and reasoning remain visible alongside the revealed source identity. This
protocol cannot prevent someone with filesystem access from opening the
private file early, so the assessor must avoid it until the lock is saved.

## Preparation and eventual execution

Run offline preparation/tests with the pinned Python 3.12 environment:

```sh
PYTHONPATH=/tmp/checkpoint-reliability-jsonschema-deps:/tmp/checkpoint-probe-pinned-deps:tests:. \
  /tmp/checkpoint-reliability-20260921-venv/bin/python \
  docs/evidence/author-count-bound-qualification-20260926/author_probe.py --prepare
PYTHONPATH=/tmp/checkpoint-reliability-jsonschema-deps:/tmp/checkpoint-probe-pinned-deps:tests:. \
  /tmp/checkpoint-reliability-20260921-venv/bin/python -m unittest \
  discover -s docs/evidence/author-count-bound-qualification-20260926 -p 'test_*.py'
```

`--prepare` uses four socket-free fake clients through the actual
`_generate_provider_payload` path to materialize exact provider requests and
selected schemas in `plan-draft.json`. Before freeze, regenerate the draft
after any local edit and review its SHA-256 and all nested request/schema
hashes. No mode runs implicitly; a mode flag is required. The following remains prospective
until the reviewed plan is frozen with account pins:

```sh
# Only after independent review, filled pins and separate freeze:
python author_probe.py --execute --plan-sha256 <reviewed-exact-plan-sha256>
# After capture, without any AWS call:
python author_probe.py --blind-project --capture-sha256 <exact-hash-printed-by-execute>
# Save blind-review.json with all judgments for every opaque ID.
python author_probe.py --lock-blind --private-map-sha256 <exact-hash-printed-by-blind-project>
python author_probe.py --unblind --lock-sha256 <saved-exact-blind-lock-sha256>
```

The harness requires an exact `plan.json` with `status: frozen`, a completed
credential pin, and matching source, fixed request and harness hashes. Do not
run it against `plan-draft.json`. Failures consume their job's one call; an
ordinary failed job may be followed by the next predeclared independent job.
Source, credential, endpoint, plan, capture-integrity or budget drift stops
globally. No deployment or runtime default change follows automatically.
