# Why Checkpoint produced unreliable quizzes

This investigation found application defects as well as model errors. Asking a
capable model for a quiz in chat does not exercise the same path: Checkpoint
serializes a constrained response, runs an independent solver and a feedback
writer, adapts their responses, persists questions, shuffles choices and grades
against the stored key. Each boundary needs its own invariant.

## Findings and verified fixes

| Finding | Evidence | Fix on main |
| --- | --- | --- |
| Native structured output support existed, but the inspected TestFlight API and worker were using legacy prompt-only JSON. | [Recorded deployment configuration](evidence/reviewer-release-20260922/DEPLOYMENT.md). | Worker transport can be selected independently, incompatible model configurations fail before deployment, and native authoring uses four required slots plus a key enum. Rollout remains separate. |
| Alphabetical schema serialization asked the author to emit choices before the stem and its key before the stem. | [Controlled ordering comparison](evidence/native-author-order-20260922/REPORT.md): three plainly wrong keys in the sorted arm; none plainly wrong and one ambiguous item in the ordered arm. | Versioned author v3 places the stem first and explanation before the key. Exact key text is derived from the selected choice slot. Historical schema bytes remain unchanged. |
| Native author instructions still requested legacy arrays and `expectedAnswer` before appending a contrary slot-format override. | Actual dispatched prompt inspection and schema-validation tests for native and legacy examples. | The native example and key requirement now match four fixed slots and `correctChoice`; schema bytes and legacy behavior are unchanged. This is format consistency, not a demonstrated semantic accuracy gain. |
| Native review arrays could contain phantom indexes while satisfying JSON Schema. | [Count-bound trial](evidence/reviewer-identity-20260922/RESULTS.md): 2/2 calls returned all ten required identities, while semantic checks still failed. | Native reviewer v3 requires one object key per trusted survivor; missing or extra identities cannot be admitted. |
| An array could describe six pair comparisons but could not enforce their identities. The model emitted seven rows including a self-pair. | [Stopped ordering trial](evidence/choice-quality-release-20260922/ORDER_RESULTS.md). | Four judgment slots and six closed pair slots, with exact endpoints supplied by code and strict decoding. Slot mapping does not depend on the key. |
| The solver outer array could not constrain every item identity; a straightforward count-bound replacement exceeded AWS compiled-grammar limits. | [Exact AWS diagnostic](evidence/solver-identity-qualification-20260922/ERROR_DIAGNOSTIC_RESULTS.md) and [shared-schema trial](evidence/solver-shared-schema-qualification-20260922/RESULTS.md): 2/2 calls, all ten identities. | Solver v5 uses shared definitions and required question keys; strict local decoding preserves all choice/pair bindings. All forty supported counts are equivalent locally; live acceptance covers count five. |
| Different strings can propose the same answer; checking which choice is correct does not check whether two wrong choices duplicate one another. | [Twenty reviewed controls](evidence/choice-quality-release-20260922/INDEPENDENT_GOLD_REVIEW.md) include equivalent values, unit conversions, paraphrases and representation-sensitive tasks. | Pair judgments are a separate admission condition. Declared equivalence or uncertainty vetoes an item, in addition to exact agreement on one supported answer. |
| Legacy client code inferred correctness from prose. The substring `correct` also occurs in `incorrect`, so distractor feedback could overwrite the explicit answer key. | [Highlighting reproduction and permutation tests](evidence/answer-highlighting-20260921.md). | The explicit structured key is authoritative. Explanation text cannot replace it. Text-based grading preserves the key across all 24 display orders. |
| Old inventory and position-dependent feedback could outlive the assumptions used when generated. | [Cached inventory audit](evidence/question-reliability-release-20260922/CACHED_INVENTORY.md); the fresh English capture contained “Only the first choice” despite app shuffling. | All practice tiers require the current verification policy. Old history is preserved. Final review rejects display-position references, while retaining quoted subject literals and ordinary numeric values. |

These changes make structure, key membership, exact identity and admission rules
deterministic. They do not make a model's factual statements deterministic or
universally correct. Schema-valid output can still describe an ambiguous question
or attach a convincing false explanation to the right answer.

## Model experiments

The default Sonnet checker had thinking disabled. With fixed pair endpoints and
disabled thinking, it correctly retained ten valid controls and excluded ten bad
controls, yet mislabeled four of 120 individual comparisons. Its reasons sometimes
discussed a different pair from the one being labeled. We preserved that strict
failure rather than crediting eligibility alone.

The [adaptive/high candidate](evidence/choice-quality-release-20260922/ADAPTIVE_RESULTS.md)
matched all 80 correctness labels and all 120 pair labels on the same twenty
controls. It used the same prompt, inputs, schema and model; adaptive mode also
changed sampling and the shared reasoning/output allowance as required by the
runtime. This was a descriptive comparison with an earlier run, not a paired
causal estimate. It took about twice as long: 23.680–49.392 seconds per call.
Three minor inaccurate explanatory embellishments remained in the private solver
reasons, so this is not evidence that every word of its reasoning was true.

The first fresh full pipeline returned 29 of 30 requested questions, but
[independent audits](evidence/question-reliability-release-20260922/STRUCTURAL_MILESTONE.md)
found false feedback and an English question with more than one defensible answer.
A correct answer key alone is therefore insufficient for release qualification.

The reviewer sometimes copied an erroneous solver explanation. We tested simply
removing the solver data in a [four-call comparison](evidence/question-reliability-release-20260922/REVIEWER_ANCHORING_RESULTS.md).
That treatment still invented false feedback and rejected a valid item: it failed
and remains inactive. More stages, or hiding an input without evidence, do not
automatically improve quality.

## Current release boundary

The tested structural changes are on main. Backend verification passes 1,235
tests after native immutable-main integration. The latest full iOS suite completed 1,054 tests with three existing skips and no failures;
answer-key/shuffle coverage includes four answer types across all 24 orders.
The worker-only Claude-thinking override keeps the synchronous API's shorter
deadline independent of a background-worker reasoning rollout.

At this checkpoint, global transport remains legacy, worker transport and thinking
inherit their global settings, and the current client minimum remains policy 2.
Only the complete native pair-audited path followed by successful final review
earns policy 4. Neither stored questions nor historical answers are relabeled.
The [fresh adaptive full-pipeline trial](evidence/question-reliability-release-20260922/ADAPTIVE_PIPELINE_RESULTS.md)
failed: it stopped after 11 provider attempts, with 5 of 30 planned questions
admitted. The arithmetic reviewer emitted unbound `index: -1` records, invalidating
two batches; Python returned five admitted items; the English solver timed out at
75 seconds. Three later domains were unattempted. The passing isolated reasoning
trial therefore does not justify promoting adaptive mode for the full worker.
The count-bound reviewer fix subsequently resolved the reproduced identity gap in
two live calls and is now on main. Semantic quality remains a separate gate:
[switching to Opus](evidence/verifier-model-comparison-20260922/RESULTS.md) and
[rewriting the refutation instructions](evidence/reviewer-refutation-20260922/RESULTS.md)
both failed their frozen criteria and were not promoted.

A separate read-only final auditor addresses a specific remaining gap: the last
reviewer currently writes new main and per-choice explanations after the
answer-blind solver has finished. Those newly written claims receive no later
semantic check. The candidate freezes all five teaching fields and permits only
accept/reject decisions; it cannot repair or replace learner content. The existing
optional authored-solution path already audits an unchanged author main
explanation, but returns no per-choice feedback.

The [initial final-auditor comparison](evidence/final-content-audit-20260922/RESULTS.md)
stopped after four of six calls when the disabled configuration returned an
overlong, contradictory reason. A separately frozen [Sonnet adaptive trial](evidence/final-content-audit-20260922/ADAPTIVE_ONLY_RESULTS.md)
completed all eighteen controls but matched only seventeen dispositions. A
[modelId-only Opus 4.6 trial](evidence/final-content-audit-20260922/OPUS46_RESULTS.md)
repeated that failure: both models accepted the same ambiguous grammar item and
endorsed an overgeneralized punctuation rule. Native identities and unchanged
selected content were correct even for that defective admission. Increasing model
capability alone did not fix this observed judging error.

The [generic counterexample prompt](evidence/final-content-audit-20260922/ADVERSARIAL_RESULTS.md)
also failed: 22 of 24 dispositions matched gold. It accepted the ambiguous grammar
item and equivalent wrong numerical answers written as `2` and `two`. All six
new independent controls passed, which does not erase the two false admissions.
One additional private reason inaccurately described the supplied distractors.

A [singleton diagnostic](evidence/final-content-audit-20260922/ISOLATION_RESULTS.md)
removed neighboring questions while retaining the original short prompt and exact
learner content. It correctly rejected the numerical duplicates, then stopped on
an overlong reason for the grammar item. That raw response still endorsed the
same false rule. Four of six planned items remained unattempted. Neighboring
context is therefore not necessary for this observed grammar error; neither this
incomplete run nor its first correct decision qualifies a production setting.

All five final-auditor trials remain failed evidence; none changed production
routing or defaults. The fourth-stage code and budget tests remain isolated
preparation. The next architecture candidate moves all five teaching fields into
authoring, before the answer-blind solver and an immutable field-by-field review.
That removes the unchecked last writer without adding a fourth call. The isolated
implementation now passes 1,223 backend tests, including preservation of assigned
skill/objective context and bounded prior-question history after solver filtering.
Its first [per-field known-control trial](evidence/authored-feedback-qualification-20260922/RESULTS.md)
timed out on the first six-item request at 75.167 seconds, before returning any
model output. Three planned requests remained unattempted; that failure is unchanged.

The [scoped follow-up trial](evidence/authored-feedback-scoped-qualification-20260922/RESULTS.md)
used the corrected context path and a prospectively selected 100-second ceiling.
All four independent batches ran once. Two completed in 84.228 and 85.652 seconds,
with all 12 observed admission decisions correct; the other two timed out without
output. Its primary result is therefore failed: 2/4 valid calls and 12/24 assessed
controls. Independent review of all 72 returned short reasons found four false
feedback claims endorsed, despite those items being rejected on other grounds.
True but incomplete mathematical statements and interpretation-dependent
exclusions are recorded separately from false claims. The controls have empty
assignments/history, so this does not qualify nonempty context behavior, fresh
content, or worker yield.

The [actual combined solver → audit trial](evidence/authored-feedback-combined-controls-20260922/RESULTS.md)
then exercised all 24 unchanged controls in worker-sized batches of 5+5+5+5+4.
All ten bounded stage calls ran, but only three batches completed: 15 items were
scored and 13/24 planned admission decisions were correct. It retained seven sound
originals and correctly excluded six defective originals with batch credit.
The other nine items earned no credit: the five-survivor audit timed out at
100.152 seconds, and a two-survivor audit returned a 253-character reason against
the 240-character local limit, invalidating its entire batch. Native JSON shape
alone did not ensure bounded usable output.

Two defective originals were admitted unchanged. Both solver and audit added an
unstated minimum requirement to the bus question, excluding a second valid ride
count. Both also treated one conventional semicolon/however placement as the only
valid placement, endorsing false learner feedback. Other explicit solver vetoes
worked, including equivalent wrong numerical choices, multiple square roots and
a converse-rule wrong key, but they did not prevent these shared interpretation
errors. All ten production requests and actual admissions replay exactly without
network access; unchanged learner hashes do not establish content correctness.

The high-effort fresh-worker draft stayed unfrozen and unrun because this exact
verifier configuration failed admission qualification. No fresh generation or
worker-yield result is claimed, and no timeout extension or later measurement
rescues these failures. Model agreement still does not prove truth.

A separate [deterministic quantitative compiler](QUANTITATIVE_TASK_COMPILER.md)
now implements a bounded mathematical subset. Code renders the whole task from
validated expressions, units, domain and explicit selection operation; exact
rational evaluation derives the key and all five teaching fields. It rejects
numerically equivalent choices, no offered answer and multiple offered answers,
including both roots of an unrestricted equation. A visibly nonnegative domain
or minimum task is a different explicit specification, never an inferred repair
to existing prose. Main now contains an opt-in mixed route: the author may emit
a bounded numerical specification or an ordinary prose question. Trusted server
provenance follows compiled items through filtering and reindexing; the final
release recompiles their original specifications and preserves every teaching
field exactly. Reviewer-written text cannot replace compiled teaching. Existing
model vetoes and topic/difficulty gates still apply. Only this complete compiled
route earns policy 6; ordinary native questions retain policy 4, and the client
minimum remains 2. No defaults or deployed configuration changed.

This bounded guarantee does not establish distractor plausibility, goal fit,
difficulty, grammar or general factual accuracy. The compiler tests include
3,780 independent oracle cases. Integrated verification passes 1,222 backend
tests; all 25 runtime source modules match each of three SAM artifacts, with
273 offline packaged SDK configuration checks. Shared compiler fixtures also
survive bank serialization, claim/replay, iOS decoding, all 24 choice orders,
grading and feedback display. The subsequent [fresh mixed-route trial](evidence/quantitative-mixed-qualification-20260922/RESULTS.md)
completed all three jobs and all 13 calls with valid native structure, returning
4/5 numerical, 5/5 Python and 3/5 mixed questions. All six compiled returns
reproduced exactly from their original author specifications and passed a
separate rational-answer check. Five invalid numerical specifications were
rejected rather than repaired.

The complete configuration still failed its prospective criterion: 12/15 yield
was below 14, and independent review found one false Python distractor explanation
among the 12 returns. All 12 keys were correct; the other 11 returned items were
sound. The final writer falsely generalized that Boolean operators return Boolean
values and that None occurs only through an implicit function return. This is
new evidence of the unchecked-final-feedback gap, separate from the deterministic
numerical guarantee. Defaults remain unchanged and the mode remains unqualified
for rollout.

The existing optional `authored_solution` mode now retains complete-pair checking
under native transport instead of silently taking the older solver path. Native
solver v5 and a new count-bound immutable-main audit preserve the exact main
explanation and return an empty optional choice-feedback map. The app already
falls back to that main explanation and highlights by the explicit key. This
removes a writer of twenty additional learner claims per five-question batch;
it does not guarantee the truth of the authored main or the model's judgments.
The final audit also receives the correct surviving skill/objective and keyless
history context, and rejects display-position references that would break after
choice shuffling.

This opt-in path earns policy 7; legacy authored mode stays 3, ordinary native
reviewer-written mode stays 4, and compiled mode stays 6. Global default remains
4 and client minimum remains 2. Policy minimums indicate freshness, not cumulative
optional capabilities. All 91 historical native contracts/prompts remain byte-
identical. The source passes 1,235 backend tests, independent filtering/provenance
review, SAM build and 393 packaged SDK configuration checks across three artifacts.
Native immutable-main provider acceptance and fresh worker quality remain to be
tested; prior failed authored-main experiments are not reclassified as passing.


[Read-only OpenAI model access checks](evidence/final-content-audit-20260922/MANTLE_AVAILABILITY.md)
confirmed that signed Mantle metadata requests work with the existing AWS
session, but the queried closed models are unavailable to this account.
Catalog presence and Bedrock Runtime availability do not establish Mantle
inference eligibility. No access activation, API keys or inference were attempted.
No final auditor or complete release configuration is qualified yet.

A fresh [read-only deployment inspection](evidence/reviewer-release-20260922/DEPLOYMENT.md)
at 06:18 UTC on September 22 confirmed that both API and worker still use the
September 11 packages and legacy transport. All seven inspected runtime modules
in each package match `7d9cc6a`; this does not identify every file in the deployed
repository. Activating the already-main structural fixes requires deploying the
new code/template and selecting native transport for the worker while keeping
the Nova Lite API in legacy mode. No deployment has occurred.
