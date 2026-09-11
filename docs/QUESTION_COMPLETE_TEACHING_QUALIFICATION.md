# Prospective complete-teaching workflow qualification

## Status and question

Preparation for one new bounded live run of the opt-in
[complete-teaching contract](QUESTION_COMPLETE_TEACHING_CONTRACT.md), introduced
at commit `5f0065d`. No live model result informed this fixture or protocol.
The earlier [reviewer-written native run](QUESTION_NATIVE_WORKFLOW_RESULTS.md)
and [immutable teaching failures](QUESTION_FRESH_AUTHOR_IMMUTABLE_RESULTS.md)
remain contrary evidence; this is not a rerun of their execution plans or a
controlled comparison against them.

Can the actual native author, sanitizer, independent solver, immutable complete
auditor, bank claim and Swift delivery path produce the requested useful
multiple-choice practice? Native schema acceptance, code tests, policy stamps
and a supported model verdict are separate from factual correctness. This trial
also checks that the explicit request selector reaches the whole delivery path
while the server environment remains at `reviewer_written`.

## Fresh inputs and learning target

The fixed [fixture](../backend/bedrock-question-service/evals/fixtures/question_complete_teaching_workflow.json)
requests five questions at minimum difficulty three for each goal:

| Goal | Purpose and context |
| --- | --- |
| Predict and explain SQLite query results | Executable query semantics, NULLs, joins, membership and duplicate rows; selective study notes supplied |
| Judge what a research study can establish | Sampling, assignment, controls, confounding, attrition and justified conclusions; no supplied source |
| Choose Spanish past tenses to express intended meaning | Meaning and timeline in narratives, with alternatives that must preserve the actual context; no supplied source |

The SQLite notes are assistant-written selective paraphrases, checked against
[SQLite SELECT documentation](https://www.sqlite.org/lang_select.html) and
[expression documentation](https://www.sqlite.org/lang_expr.html), not acquired
complete documents or quotations. Their scope and incompleteness are explicit
in the author input. SQLite is specified to avoid silently substituting another
database engine during independent execution. SQL has appeared in earlier
experiments; these particular goal inputs and generated items are fresh, not an
unseen-domain claim.

Study-design and Spanish authoring use the model's knowledge plus case material
it supplies in the stem. No previous question, key, critique or assessment is
included. Evaluators may use independent calculations, local SQLite and primary
subject references after generation; those are evaluation evidence, not new
runtime verification tools.

Each payload explicitly selects `feedbackContract: "authored_complete"`.
History is empty; no skill map, adaptive plan or client-derived override is
supplied. This measures initial practice, not adaptive learning, app blocking,
long-term retention, skill-map generation or deployed queue/refill behavior.

## Frozen execution contract

Use Kimi K2.5 (`moonshotai.kimi-k2.5`) for authorship and Sonnet 4.6
(`us.anthropic.claude-sonnet-4-6`) for independent solving and complete audit.
Both use disabled thinking, temperature 0.2 and 6,000 output tokens. The ordinary
three-call path authors all teaching before solver/audit. Keep the unchanged
runtime's three generation attempts, with a maximum of six provider calls per
goal and 18 calls total. There is no fallback model or extra post-trial repair.

Freeze `native-complete-teaching-workflow-v1` with exact source/dependency hashes,
raw fixture, normalized requests, settings, operation order, native prompts,
schema bytes/hashes and first requests. Subsequent dynamic requests must be
persisted before dispatch. Require the real native contracts
`question_author_complete_v1`, `complete_choice_solver_v1` and
`complete_teaching_reviewer_v1`. Their successful live use constitutes transport
qualification within this run. If a stage is never reached or its schema fails,
its qualification remains incomplete; do not add unplanned calls to rescue it.

The input allowance is **65,536 serialized UTF-8 bytes per call**, at most
1,179,648 total, chosen before any inference. Offline sizing using actual
production complete audit serialization with the fresh fixture found
27,222–28,446 bytes for five representative target-length items and
42,622–43,846 for five ASCII items at legal field limits. The
[recorded measurements](evidence/complete-teaching-preparation-20260910/request-sizes.json)
bind the fixture bytes and actual request hashes. These ASCII measurements do
not bound every legal Unicode response. Complete displays repeat teaching, so
the older harness's 32-KiB cap could reject a valid full batch. The fresh fixture
must be dry-prepared under the new cap. This is an evaluation input allowance,
not a change to production field lengths, output tokens or historical modes.
Do not truncate teaching, shorten source context or raise the allowance after
seeing live results. A larger-than-allowed request is an observed limitation.

Each goal has a separate 240-second operation clock. Reuse the existing isolated
caller, one SDK attempt, three-second connection timeout and 75-second read
window. Its fixed read window gives conservative late-call admission compared
with a deployed client that shortens the read timeout. Local termination does
not prove remote cancellation or zero usage.

Completed content rejection, call-budget exhaustion and recognized native format
failures are retained with their availability consequences. Observer, dispatch,
correlation, unknown usage, unfinished response, cleanup, persistence, input-size,
deadline/durable-budget and unexpected failures stop later dispatch according
to the frozen runner policy, even if runtime returns partial survivors. Never
restart a timed-out observer or change output directories to reuse an execution
plan. Poll any confirmed live handle to terminal. An exclusive claim beside the
original plan prevents repeat execution; historical plans stay untouched.

An expired AWS session must be renewed before live dispatch. A successful STS
identity check establishes credential availability, not model/schema access.
No production Lambda or storage write, default promotion or deployment occurs.

## Delivery and independent assessment

Require exact network-disabled runtime replay before offline delivery. For each
operation, retain all returned items through the real prepare/claim/repeat-claim
code in an isolated finite fixture bank. Preserve the explicit selector in its
metadata and require policy revision 4. Do not claim that this finite-bank
helper exercises the deployed enqueue/refill path; those selection invariants
have separate deterministic production-code tests.

Then run the actual Swift decoder, whole-batch sanitizer, persistence/restore and
feedback composer. The helper must reconstruct a goal with the explicit selector
and export every retained item's key, main, choice feedback, all four composed
displays and provenance. Require an executed capture test with no skip. Match its
attachment's fixture hash to the exact bank report before using the result.

Export every recoverable raw author occurrence from every call, including
rejected, malformed and duplicated questions. Preserve native `choiceFeedback`
rows verbatim, even if their coverage is invalid; do not run a rejecting native
adapter merely to build the raw assessment packet. Record unparseable responses
and missing arrays separately rather than assigning them invented question IDs.
The fixed shuffle seed is `complete-teaching-20260910`, independently derived
for raw and client packets. Hashes bind the packets to capture/delivery bytes;
private occurrence mappings preserve actual call and item identity.

Two independent assessors first save judgments for literal stems and every
choice without seeing authored keys, teaching, solver/auditor judgments or raw
item survival. Malformed subject shapes remain explicit. After those files are
frozen, assess every raw authored key, main and native feedback row against the
saved judgments, still without runtime verdicts. Client stem/choice judgments
are separately frozen before client keys and teaching; client retention is
necessarily disclosed. Finally assess each exact client main, each choice
explanation and every composed display. Do not assume supported component fields
guarantee supported combined teaching.

Keep unique answer support, ambiguity/missing premises, keyed-answer agreement,
goal fit, distinct plausible distractors, all teaching claims and difficulty as
separate judgments. Check literal SQL examples in the stated SQLite semantics;
a result from an invented schema or repaired query is not verification of the
original. Use authoritative references for factual disputes where available.
For Spanish, distinguish an impossible form from an alternative construal the
stem did not rule out. For study inference, preserve the stated assignment,
sampling and observation limits instead of supplying an intended study design.

An item enters the confirmed-useful numerator only if both assessors support a
unique keyed answer, sufficient premises, goal fit, distinct plausible choices,
all required teaching and difficulty at least three. Preserve disagreements and
uncertainty; conservative exclusion does not mean every excluded item is false.
Any adjudication must retain the initial judgments and independently explain its
evidence. Do not silently select the author's preferred interpretation.

Report all 15 requested slots, every raw occurrence, returns, claimable inventory,
client retention, supported keys, complete supported teaching and useful items.
An empty result has zero coverage and undefined precision. The requested outcome
for this run is five useful items per goal; fewer sound survivors remain partial
coverage. Categorize factual catches, appropriate difficulty exclusions, invalid
format, false vetoes, unchecked ambiguity and content loss separately. Measure
actual token use, stop reasons, request bytes, latency, known usage and cleanup.

One selected three-goal run cannot estimate a production error rate or prove
arbitrary-subject correctness, even if all 15 slots succeed. A failure must guide
an identified general capability change, not another unmeasured prompt tweak.

## Preparation and execution record

Preparation passed on September 10:

- The full backend suite passed **1,147 tests**, with no skips. The new mode's
  seven tests exercise actual scripted production calls, requests larger than
  the historical cap, the exact new cap, replay, top-ups and stopped execution.
- The optional Swift delivery suite passed **five tests**, with no failures or
  skips. Its actual capture test retained 15 synthetic questions and all 60
  composed displays after decoding, sanitization and persistence. A superseded
  first run skipped the capture because of temporary scheme environment
  inheritance; the final run set `shouldUseLaunchSchemeArgsEnv=NO` and executed it.
- Eight exporter tests and actual synthetic CLI runs preserved 15 raw items and
  all 60 native feedback rows, plus 15 client items and all 60 actual displays.
  Final file/builder hashes and content continuity checks matched. Independent
  review also verified malformed occurrences, concealed key/teaching fields,
  changed feedback, missing observations and failed client operations.
- Service-wide Ruff, Python compilation and `git diff --check` passed.
  Independent review found no remaining preparation blocker in the runner,
  explicit selection, replay, delivery, assessment or prospective protocol.

The three first serialized author requests are 16,629, 15,203 and 15,280 bytes in
fixture order. The code, raw fixture and protocol are saved before plan freezing.
The exact frozen plan hash is recorded separately after that commit. These are
synthetic/offline results; no live inference has occurred. AWS credential
preflight currently reports an expired session, with renewal requested.
Live results belong in a separate document and must not rewrite this protocol
or the original fixture.

From `backend/bedrock-question-service`, prepare with
`python evals/checkpoint_runtime_qualification.py --fixture evals/fixtures/question_complete_teaching_workflow.json --output PLAN_DIRECTORY`.
Execution uses that original plan, its exact canonical SHA-256, `--execute`,
`--cli-credentials` for this Mac's login provider and a fresh output directory.
Do not execute until credentials are renewed. Do not copy the plan to bypass its
exclusive execution claim. Keep the source worktree frozen for exact replay.

After terminal capture, run `evals/checkpoint_native_delivery.py` with `--capture`
and a new `--output` file. Give the exact resulting bank report to the optional
Swift `QuestionDeliveryCaptureTests` in a temporary test scheme, export its JSON
attachment and confirm the test actually ran without a skip. Use
`evals/checkpoint_complete_teaching_assessment.py raw` with `--capture` and a new
`--output` directory for raw packets. The `client` phase additionally requires
`--bank-delivery` and `--client-attachment`. Freeze assessors' phase-one files
before giving them phase-two packets. Preserve all original artifacts and hashes.
