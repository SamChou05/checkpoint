# Why Checkpoint produced unreliable quizzes

This investigation found application defects as well as model errors. Asking a
capable model for a quiz in chat does not exercise the same path: Checkpoint
serializes a constrained response, runs an independent solver and a feedback
writer, adapts their responses, persists questions, shuffles choices and grades
against the stored key. Each boundary needs its own invariant.

Current source verification passes **1,395 backend tests** and the latest full
iOS suite completed **1,058 tests with three existing skips** after the optional
timeout, fraction-distractor, compiled-surplus, scalar-explanation,
author-cardinality, task-only numerical, numeric-choice and saved-inventory improvements. The latest
[current-source full-worker trial](evidence/current-source-worker-successor-qualification-20260926/RESULTS.md)
failed qualification at 9/15 returns and three compiled items where six were
required. Its numerical author exhausted 16,000 output tokens. A later one-job
[task-only numerical pilot](evidence/task-only-numerical-author-qualification-20260926/RESULTS.md)
passed at 5/5 compiler-proven returns. The subsequent
[three-topic successor](evidence/task-only-full-worker-qualification-20260926/RESULTS.md)
returned 10/15: numerical and Python returned five sound items each, but the
mixed author emitted 37 complete rows toward a request for five and exhausted
its 16,000-token allowance before closing JSON. The full worker remains unqualified.
Verified improvements are on main, while the [fresh September 26 deployment check](evidence/deployment-refresh-20260926/RESULTS.md)
still finds the September 11 legacy API and worker packages. No deployment or
inventory transition has occurred.

The later [compact mapped trial](evidence/compact-typed-slots-qualification-20260926/RESULTS.md)
proved that a smaller 2,664-byte native schema can force the exact five assigned
author slots on this request; all three arithmetic tasks compiled, but a
shuffle-dependent English explanation reduced the verified worker return to 4/5.
A [paired author-only prompt trial](evidence/compact-prose-v2-live-comparison-20260926/RESULTS.md)
returned all ten schema-valid slots, yet blinded content review credited only
4/5 in the revised arm and 3/5 in the baseline. The revised arm still had an
ambiguous pronoun item with a false exclusion in its explanation, so that prompt
remains inactive. An [English agreement constructor](AGREEMENT_TASK_CONSTRUCTOR_PROTOTYPE.md)
now derives a unique key and all teaching from closed, reviewed sentence frames.
Its exact-request route is opt-in and inactive in deployment. A [one-shot live
worker trial](evidence/mapped-agreement-full-worker-qualification-20260927/RESULTS.md)
accepted the task schema and constructed all five questions, but returned only
3/5 because the final model reviewer rated both code-owned agreement items 3
instead of the requested 2. Two independently locked, answer-blind diagnostic
reviews rated all five pre-review candidates 2 and selected their code-owned
keys. A narrow code-owned difficulty policy now accepts only reviewer ratings
2 or 3 for freshly revalidated agreement templates, while preserving other
review vetoes. The failed worker result remains unqualified; the changed
policy needs a fresh live trial.

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
| Old inventory and position-dependent feedback could outlive the assumptions used when generated. | [Cached inventory audit](evidence/question-reliability-release-20260922/CACHED_INVENTORY.md); the fresh English capture contained “Only the first choice” despite app shuffling. | All practice tiers enforce the configured client minimum, currently revision 2. Raising it to native revision 4 remains a coordinated rollout step; old history is preserved. Final review rejects display-position references, while retaining quoted subject literals and ordinary numeric values. |
| Parenthesized display labels escaped the existing feedback guard. | The fresh Sonnet author trial emitted “In (b),” for an answer that moves after shuffling. | The shared guard now rejects unbound parenthesized choice references in authored and reviewer teaching. Regression tests preserve actual stem subparts, exact quoted literals and mathematical variables. |
| Some numeric choices are visibly or mathematically identical despite different strings; some old saved MCQs carry invalid keys or colliding choices. | Scalar controls for `2`/`two` and `1/4`/`25%`, invisible-character controls, and stored-inventory tests. | Bounded numeric-value and visible-choice guards reject those exact classes. iOS quarantines old saved MCQs with malformed keys or visible-choice collisions before serving practice; historical attempts remain. This is not a general prose-equivalence proof. |
| A required-key author schema can force five rows without making all five correct or teachable. | [Frozen count-bound trial](evidence/author-count-bound-qualification-20260926/RESULTS.md): both prose arms were structurally complete; the candidate had five one-answer rows but one false explanation, while two baseline rows had multiple valid choices. Five constructed typed rows included two compiler rejections. | Count-bound remains worker-only opt-in. Existing exact compiler rejects invalid typed tasks; semantic authoring still needs independent assessment. No default or deployment change followed the trial. |
| The exact-five author contract also failed a blinded replication on two assignments. | [Replicated trial](evidence/author-count-bound-replication-successor-20260926/RESULTS.md): all four calls produced five schema-valid rows, but independent reviewers credited 4/10 fixed-count items against 6/10 array items. Seven archive stems exceeded the active 320-character limit; the fixed-count arm also omitted premises, made false teaching claims, and offered two equivalent actions in one question. | Keep fixed-count authoring opt-in. The active sanitizer rejects overlong stems, and answer checking still needs semantic review. The contract alone cannot make a question correct, distinct, or short enough. |
| A correct Python answer can carry a false generic Boolean rule in its authored explanation. | The [frozen prose trial](evidence/prose-semantic-guidance-qualification-20260926/RESULTS.md) had three explanations saying `or` returns the first truthy operand or `and` the first falsy operand without the no-trigger final-operand case. | A bounded authored-prose guard now rejects those unqualified generic claims before they consume a batch slot and rechecks them at immutable teaching freeze. [Offline replay](evidence/prose-semantic-guidance-qualification-20260926/BOOLEAN_GUARD_REPLAY.md) caught all three labeled cases and none of the other 17 explanations. Complete or case-specific rules remain eligible; other semantic claims still need review. |
| Native schema validity cannot prevent a model from exhausting its reasoning/output budget before completing a batch. | The [current-source worker capture](evidence/current-source-worker-successor-qualification-20260926/RESULTS.md) shows the numerical author stopping at `max_tokens` after 16,000 output tokens and 188.839 seconds, with visible JSON truncated. Python returned 5/5 and mixed returned 4/5; all nine returned items passed independent content review, but the full run failed yield and compiled-count gates. | The runtime rejects the truncated batch and preserves already verified partial returns after a later mixed reviewer timeout. The high-reasoning, five-item author route remains unqualified for rollout; smaller requests or a stage-specific reasoning setting need a separately reviewed trial before promotion. |
| Reducing the numerical author batch to three did not ensure compiled tasks. | The [locked three-item pilot](evidence/quant-author-batch-size-qualification-20260926/RESULTS.md) used the same five-slot numerical request, six-call and 240-second limits, with only the batch cap changed. Both author calls returned prose; the worker returned 3/5 sound items but **0/5 compiler-proven** items. Three earlier prose rows failed the immutable teaching-format check because they referred to shuffled answer labels. | Keep the batch cap opt-in and off the production configuration. Exact request size and native JSON shape alone cannot require the model to use the mathematical task branch or make teaching safe after shuffling. |
| A versioned task-only numerical contract removed the model's prose escape path for one exact goal. | The [one-shot task-only pilot](evidence/task-only-numerical-author-qualification-20260926/RESULTS.md) returned **5/5 sound, compiler-proven** questions in four native calls and 127.684 seconds. Two answer-blind reviewers selected all five captured keys and independently found all 30 choice pairs distinct; every learner field recompiled exactly. One otherwise sound decimal task was still vetoed by a fallible model scope review, and the bounded top-up filled its slot. | Keep the goal-hash-gated author and three-item batch cap opt-in. This passes the prespecified numerical pilot, not a multi-topic reliability or deployment gate. The compiler makes the released numerical answer and choices exact; model judgments and model-written prose in other topics remain fallible. |
| A global three-item batch cap would also alter unallocated Python generation when applied to a shared worker. | The frozen three-topic request has an unallocated Python job; the previous batch-cap selector returned three for both that job and the numerical job. Offline goal-hash controls now return numerical 3, Python 5, and mapped mixed 5, while rejecting missing, blank, malformed, or conflicting scope when task-only mode and a cap are combined. | A separate opt-in `QUESTION_CONSTRUCTED_AUTHOR_BATCH_GOAL_SHA256` scopes the cap to the exact normalized goal. The older global cap remains available outside task-only mode. The later full-worker trial using this scope failed on the separate mapped mixed author. |
| The mapped mixed author can ignore the requested five-item count even with native JSON schema, exhausting the output budget before yielding any parseable batch. | The [one-shot three-topic trial](evidence/task-only-full-worker-qualification-20260926/RESULTS.md) returned 5/5 compiled numerical and 5/5 Python items, but 0/5 mixed items. Its mixed author completed 37 top-level rows, began a 38th, then stopped at `max_tokens` with invalid JSON. Two locked blind reviewers chose all ten captured keys and found all 60 pairs distinct; the job-yield gate still failed. | Preserve rejection of truncated output and partial returns from other jobs. Keep the route opt-in while a bounded, allocation-preserving mixed-author contract is evaluated. Worker-only deployment variables now expose the exact tested numerical scope without altering the API defaults; they are configuration preparation, not a rollout. |
| Even a closed, code-authored question can be discarded by a fallible difficulty judgment. | The [mapped agreement full-worker trial](evidence/mapped-agreement-full-worker-qualification-20260927/RESULTS.md) accepted a five-slot native schema and constructed five questions. The final model reviewer called both English tasks level 3 and the exact-level gate returned 3/5. Two independent blind reviewers rated the five sanitized drafts level 2, picked all five code-owned keys, and found all within-item choice pairs distinct. | Policy 10 on main uses the freshly revalidated agreement template's calibrated level 2 when the reviewer estimates 2 or 3. Ratings 1, 4, 5 and all other solver/reviewer vetoes remain binding; ordinary prose and quantitative difficulty rules are unchanged. An independent source review and 1,395 backend tests passed. The opt-in remains inactive in deployment and needs a fresh worker qualification; the failed trial remains 3/5. |

These changes make structure, key membership, exact identity and admission rules
deterministic. They do not make a model's factual statements deterministic or
universally correct. Schema-valid output can still describe an ambiguous question
or attach a convincing false explanation to the right answer.

The separately frozen [prose semantic prompt comparison](evidence/prose-semantic-guidance-qualification-20260926/RESULTS.md)
confirmed that limitation on fresh calls. The candidate added explicit exception
and distractor guidance, yet scored 7/10 independently usable authored rows
against 6/10 baseline and regressed on Python from 4/5 to 3/5. It still wrote
false universal Boolean rules and an ambiguous collective-noun item. It failed
its frozen qualification gates, so the candidate prompt was not promoted.

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

## Earlier release checkpoint (historical)

The tested structural changes are on main. Backend verification passes 1,309
tests after opt-in task-only numerical construction. All 27 runtime modules match each of three SAM artifacts, with 516 packaged SDK configuration checks. The latest full iOS suite completed 1,054 tests with three existing skips and no failures;
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
Subsequent native immutable-main provider acceptance and fresh worker quality are
recorded below; prior failed experiments are not reclassified as passing.

The two opt-in routes now compose: `mixed_quantitative` authoring can use
`authored_solution` review. Code-derived numerical questions retain all five
compiled teaching fields and policy 6; prose retains its exact authored main,
empty optional choice feedback and policy 7. Sidecars remain bound through both
filters, and tampered fields or fabricated provenance cannot acquire compiler
status. The same three stages and six-call job budget apply. Defaults are unchanged.

The [Sonnet author-only diagnostic](evidence/sonnet-mixed-author-diagnostic-20260922/RESULT.md)
returned all 15 requested native-valid drafts in three calls, including eight
valid compiled specifications. Root adjudication found 14/15 usable drafts,
meeting the component criterion; the independent review preserves a 13/15
sensitivity because it reads one correct Python `or` explanation as an overly
broad rule. Root and the prior assessor apply the same contextual interpretation
to that wording in both trials. The English pronoun item remains excluded under
either reading: its alternatives allow a defensible second interpretation, and
its explanation refers to display slot `(b)`. The label fix closes that observed
shuffle gap; it does not resolve arbitrary linguistic ambiguity. This author-only
result does not measure actual solver/auditor rejection, worker yield or deployed
behavior. The [combined actual-runtime trial](evidence/immutable-main-mixed-qualification-20260922/RESULT.md)
then failed: all three jobs ran, but only 4/15 questions returned. Seven of ten
calls produced valid native structure; three timed out. The first numerical audit
returned blank issue strings that passed its provider schema but failed local
validation, discarding the whole batch. Four other audit rows requested worked
derivation instead of the compiler's correct but terse result statements. The
remaining numerical budget could not complete its top-up; Python retained four
items after a top-up timeout; mixed authoring timed out. All four released mains
remained exactly authored, with empty feedback and policy 7. Ten raw numerical
specifications recompiled exactly, but none was released. This configuration
remains unqualified; format, teaching quality and latency require separate fixes.
The fifth Python draft also exposed a false pair veto: the solver treated `0`
and `False` as interchangeable for an exact Python result because they compare
numerically equal, despite their distinct result types. Enforcing fixed pair
identities does not make the model's equivalence classification correct.

Two concrete follow-up fixes are now on main. Exact-value compiler mains render
each operation in dependency order, including common denominators, multiplication
products/reduction and signed reciprocals. Every displayed equality is derived
by exact arithmetic. Complete teaching over 420 characters is rejected rather
than clipped, so complex expressions may have lower yield. All ten captured
numerical specifications still compile under the new renderer; eight gain worked
mains and the two scalar-condition payloads are unchanged. The revised shared
fixture passed all ten selected iOS highlighting tests, including 72 compiled
display orders. Historical captures and their source checkout remain unchanged.

Native immutable-main audit v3 replaces free-text issues with six required Boolean
defect flags and restricts difficulty to the five rubric values. Strict decoding
maps true flags to stable nonblank issue codes before the existing vetoes run.
Blank issue strings cannot fit this new schema; false flags cannot override
unsupported teaching, a wrong key, invalid status or the difficulty floor. The
native prompt now has one count-correct output example. All 131 historical
contracts, metadata and prompt bytes remain unchanged. This closes the observed
format mismatch without claiming correct model judgments or a latency improvement.
The subsequent [two-call audit diagnostic](evidence/worked-flags-audit-diagnostic-20260922/RESULT.md) established live native-v3 acceptance at count five: all five worked mains were accepted, all five materially false copies were rejected, and all ten exact keys matched. Both calls finished within 100 seconds. This small component result does not establish full-pipeline yield or broad-topic accuracy.

The native mixed, immutable-main route now uses the private compiler proof directly for numerical correctness and exact choice distinctness. Revalidated compiled rows skip the redundant model solver; prose keeps its existing blind choice and pair checks. One final audit still reviews every survivor, and final recompilation must reproduce all five learner fields before compiled policy 8 is stamped. Historical reviewer-written compiled policy 6 retains its model solver, prose policy 7 is unchanged, and global/client defaults remain 4/2. The change passed 1,285 backend tests, independent interleaved-survivor and provenance checks, SAM packaging, and all 513 packaged SDK shape checks. A fake actual-route five-item compiled pass uses two model calls; the later [full-worker trial](evidence/compiled-proof-worker-qualification-20260922/RESULTS.md) failed at 10/15 returns, with two underspecified English items among those ten. Generic pre-author admission conservatively requires three calls remaining because an author may produce prose.

The deployment workflow now exposes the worker-only feedback contract, defaulting
to `reviewer_written`. Optional independent skill-map model/resource settings also
let a worker model change preserve the API's existing skill-map model and IAM
resources. Empty overrides retain historical inheritance. These configuration
fixes passed the deployment-script suite and SAM validation; they do not enable
the failed configuration or authorize deployment.


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


The [programming result comparison](evidence/programming-result-pair-diagnostic-20260922/RESULT.md) completed all four planned native solver calls. Both baseline and a one-paragraph programming clarification got 8/8 eligibility decisions, 32/32 choice judgments and 48/48 pair judgments correct, retaining five good controls and excluding three defective controls per arm. Root and an independent reviewer checked all 160 visible reasons and preserved minor wording qualifications. There was no observed comparative accuracy gain, so the candidate paragraph stays inactive and the runtime solver prompt is unchanged. The earlier `0`/`False` veto remains evidence of intermittent model error; this small matched comparison neither erases it nor measures its rate.


The [compiled-proof worker trial](evidence/compiled-proof-worker-qualification-20260922/RESULTS.md) completed all 12 provider calls with native-valid output, but only 8/15 planned questions were independently sound. Both English items supplied sentences without an actual editing question; the reviewers invented the intended antecedent or tense constraint. Ten of 18 numerical drafts omitted their correct answer and four had malformed graphs. Four compiled; three survived final review. Exact socket-blocked replay preserved every request, source binding, decision and return. This failed candidate remains inactive.

The new [task-only constructor](QUANTITATIVE_CHOICE_CONSTRUCTION.md) removes numerical answer-choice invention from the model in a separate opt-in mode. The model supplies a bounded mathematical task; code derives the exact answer and three distinct wrong values from single-operation mistakes or explicit integer-domain competitors. Insufficient pools, malformed tasks and text-limit failures reject without padding or repair. The completed task is recompiled before release with existing private provenance, policy 8 and immutable teaching; ordinary prose remains policy 7. Native transport plus authored-solution review are required before any provider reservation. All 171 prior schemas/prompts/metadata remain byte-identical. [Verification](evidence/constructed-authoring-20260922/VERIFICATION.json) covers 1,309 backend tests, independent source review and all three built artifacts. Live qualification of the new route is separate; it does not repair the observed English authoring failure.

The [13:09 UTC read-only deployment refresh](evidence/compiled-proof-rollout-review-20260922/ROLLOUT_REVIEW.md) confirms the same September 11 packages and legacy settings. Its conditional worker configuration cannot proceed because its trial failed. Main pushes contain verified code improvements and preserved evidence; they have not changed deployed behavior.


The [explicit prose-task author comparison](evidence/prose-task-explicitness-20260922/RESULTS.md) completed four controlled Kimi calls and all20raw slots. The candidate made edit spans explicit, but still offered multiple valid pronoun replacements and supplied an unsupported tense rule. The independent review found5/10candidate items usable; root recorded4/10with a contextual upper bound of5/10. Both fall below the frozen10/10target. Format, raw bounds and per-call variety all passed. The addition remains inactive; no runtime author prompt was changed.

The [task-only constructor worker trial](evidence/constructed-worker-qualification-20260922/RESULTS.md) returned 14/15 within budget, with 13/15 sound learner items under both reviews. All keys were correct, but one Python main confused precedence with execution order and passed final audit. The numerical job used five prose rows, so zero of its returns had compiler provenance. Three valid mixed-job tasks constructed correctly; an unsatisfiable fourth task was rejected. Constructor quotas therefore failed independently of the teaching defect. All eleven native calls and exact offline replay passed structural checks. This configuration remains inactive. A separate [client review](evidence/constructed-authoring-20260922/CLIENT_HIGHLIGHTING_REVIEW.md) passed 21 focused iOS tests and two bank/claim roundtrip groups without finding another valid-key highlighting defect.

The [Sonnet author full-worker comparison](evidence/constructed-sonnet-worker-qualification-20260922/RESULTS.md) returned 9/15: zero numerical, five Python and four mixed. The numerical author timed out at 100 seconds without a response or usage; all other eight responses were native-valid. Three compiled items and all nine keys were correct, while one Python main retains an explicit universal-versus-contextual wording sensitivity (8/15 strict, 9/15 contextual). Two raw mains referenced shuffled answer letters and one mathematically sound constructed item received a distractor veto. Every reading fails the original yield and compiler quotas; its conditional rollout draft is marked inactive.

A separate [verified timeout improvement](evidence/worker-response-timeout-200-20260922/VERIFICATION.json) allows selecting a read ceiling up to 200 seconds. Defaults stay unchanged, and the actual API/worker deadlines, six-call reservation limit and single SDK attempt continue to constrain every dispatch. It passed 1,312 backend tests, deployment validation, SAM packaging and 516 packaged SDK shape checks. A fresh bounded trial is required to measure the selected ceiling; neither that code change nor the observed timeout establishes grammar-cache causation.

The completed [longer-read trial](evidence/constructed-sonnet-long-read-qualification-20260922/RESULTS.md) returned 13/15 within deadline. Its first author took 161.843 seconds, so the larger ceiling was used; a later solver still timed out under a 6.396-second remaining allowance. Twelve received responses were native-valid. All eight typed drafts constructed, but only six released and only three were in the numerical job. Four raw mains referenced shuffled answer labels, one compiled surplus was capped behind a prose row, and one mathematically sound scalar main received an unexplained uncertainty veto. Both independent reviewers preserve the same English ambiguity and Boolean-rule sensitivities; no reading qualifies the original criteria.

A separate [fraction-pool improvement](evidence/fraction-distractor-priority-20260922/RESULTS.md) now prioritizes bounded fraction-procedure mistakes over generic operator swaps. It preserves exact keys, distinct values, final compilation and all audit vetoes. Verification covers 1,318 backend tests, 885 signed cases with twenty constructibility gains and no losses, all 288 nested cases, and the three packaged artifacts. These deterministic checks do not establish novice distractor plausibility or full-worker qualification. The earlier frozen trials remain unchanged.

The constructed author now prefers privately proven compiled rows over prose rows only within the same resolved skill and objective positions when surplus rows compete for a requested slot. Original source ordinals and all sanitizer and final audit gates remain binding. This addresses the observed surplus-order loss without claiming the failed trial would have returned another item: its later solver had little time left. The deterministic scalar compiler also lists the exact false comparisons for every more-extreme domain value when the set is small and the proof fits the learner explanation limit; longer cases retain the prior wording. This makes a previously terse proof explicit, but the earlier unexplained model veto cannot be causally reclassified. The integrated backend suite passes 1,332 tests.

A separately reviewed [shuffle-instruction comparison](evidence/shuffled-choice-author-instruction-20260922/RESULTS.md) ended before model dispatch because AWS credentials had expired. The exact frozen record has zero calls and all 20 slots unattempted. The proposed author prompt remains isolated; there is no evidence for promoting it. Independent preflight caught and resolved a malformed-response capture issue before that attempt. An offline schema investigation also confirmed the default author `questions` array accepts different raw counts for a five-item request. New opt-in count-bound author schemas on main require dense closed question keys for each pass, including top-ups. Independent source review and 1,342 integrated backend tests cover local validation and the unchanged array default. Bedrock acceptance, latency and usable survivor yield remain unmeasured; exact raw count cannot guarantee five usable questions or resolve semantic ambiguity.

An eval-only [source claim challenge](QUESTION_SOURCE_CLAIM_CHALLENGE.md) now
freezes exact stem and teaching partitions, assigns server-owned identities to
premises, choices, six choice pairs and teaching claims, and binds declared
evidence to captured source units. Missing judgments, conditions, unresolved
premises, equivalent choices and unsupported teaching veto the unchanged item.
This makes omissions and disagreement auditable; it is not a production gate or
a truth certificate. An adversarial test deliberately remains eligible when a
model cites an irrelevant but correctly identified source unit, demonstrating
that identity binding cannot establish entailment. The change passed 1,351
backend tests and Ruff; no provider call or deployment occurred.

The [task-only full-worker qualification](evidence/task-only-full-worker-qualification-20260926/RESULTS.md)
returned 10/15 independently sound questions: five numerical tasks compiled
with exact policy-8 keys and choices, five Python prose questions passed policy
7, and the mixed job returned none. Both blind reviewers agreed on all ten keys
and all sixty choice-pair distinctions. The mixed author generated 37 complete
rows plus a partial 38th and hit the 16,000-token output ceiling; its unbounded
array was invalid JSON. A three-item exact-goal batch cap and worker-only
deployment controls were verified and pushed to main, but this 10/15 result
failed the qualification gate. The deployed worker and API remain on their
September 11 legacy packages; no rollout occurred.

The subsequent [fixed-slot mapped trial](evidence/mixed-fixed-slots-successor-qualification-20260926/RESULTS.md)
kept the mixed 3:2 assignment and five required slots in native JSON Schema.
It returned 0/5 because Bedrock rejected the first request before inference:
“The compiled grammar is too large, which would cause performance issues.”
The attempted schema was 5,519 bytes with repeated skill/objective enums.
Local JSON Schema validation, SDK shape checks and 1,380 backend tests did not
predict this service-side grammar limit. A [separate offline diagnosis](evidence/mixed-fixed-slots-successor-qualification-20260926/SCHEMA_DIAGNOSTIC.md)
found a 2,601-byte direct typed-slot shape that keeps exact cardinality and
the three numerical/two prose row types while injecting trusted assignment
metadata in code. Its Bedrock acceptance and question quality are untested.
The rejected candidate remains isolated and the frozen trial is closed.

The [compact direct typed-slot successor](evidence/compact-typed-slots-qualification-20260926/RESULTS.md)
reduced the five-slot author schema to 2,664 bytes and Bedrock accepted it on
one bounded mixed-worker run. The author emitted all five required slots; three
arithmetic tasks compiled exactly. The worker used three calls in 154.109
seconds and returned 4/5 items: three compiler-proven arithmetic and one
English prose. A deterministic teaching guard rejected the other English
draft because its explanation referred to “choice b” after the sanitizer
shuffled the key. Post-lock inspection also found an unsupported pronoun claim
in that draft. Two independently locked blind reviewers agreed with all four
explicit keys and judged all 24 visible choice pairs distinct. Exact compiler
replay and full slot provenance passed independent audit. The frozen 5/5
qualification gate failed, so this result supports the smaller grammar as a
real structural improvement but does not justify deployment or population
reliability. Generic fraction wrong-choice teaching remains repetitive.

A September 27 read-only deployment refresh found the TestFlight API and worker
still running September 11 Lambda packages with `BEDROCK_STRUCTURED_OUTPUT_MODE`
set to `legacy`. Their deployed `question_generation.py` lacks the newer
task-only and scoped-batch features; the API author is Nova Lite and the worker
author is Kimi K2.5. Thus the fixes pushed to main, including the compact
opt-in route, have not changed the live backend. In current iOS source, the
explicit `expectedAnswer` remains authoritative for grading and the “Correct
answer” display even when explanation text conflicts. Independent simulator
runs passed 99 validation/session tests and 13 dedicated highlighting tests,
including all 24 choice permutations. The installed TestFlight iOS binary was
not inspected, so its revision cannot be inferred from these source tests.
