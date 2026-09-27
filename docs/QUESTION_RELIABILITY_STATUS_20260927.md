# Quiz reliability: current diagnosis and qualification status

This is a current-source synthesis of the September 21–27 investigation. It
does not relabel the outcomes of frozen experiments. Changes described here
have been pushed to `main`; the deployed TestFlight package remains the
September 11 legacy package until a separately verified release.

## Why a plausible four-choice response is not an admitted question

Checkpoint's worker asks for more than a model's conversational quiz answer.
It must produce the required JSON, preserve the assigned skill and objective,
give exactly four literal choices with one supported key, make the wrong
choices meaningfully different, teach the unchanged answer correctly, meet
the requested difficulty, avoid repeats across a growing bank, and complete
the author, answer-blind solver, and reviewer calls within one job deadline.
One failure at any layer can discard an item or the whole batch.

The intuition about a modern model making a small quiz is supported by a
[matched two-call test](evidence/general-mcq-structure-vs-quality-20260927/RESULTS.md):
Opus 4.6 returned five parseable Python questions both with and without native
JSON Schema. CPython and an answer-blind reviewer agreed with all ten keys,
and every item had four distinct listed choices. Yet the blind reviewer rated
none at the requested level 3 and flagged four near-duplicate pairs. The
experiment isolates why a plausible one-off quiz does not imply a reliable
level-specific, repeated-bank worker; it does not estimate a general failure
rate.

The deployed TestFlight mode is still `legacy`, which asks the author for JSON
in prose. The repository has an opt-in native mode, but its schema only
constrains form. [AWS's structured-output documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
describes JSON Schema validation and grammar compilation, including a first
compile that may take minutes and a 24-hour grammar cache. It does not promise
that answer choices are semantically different or that the asserted key is
true. Its supported schema subset also cannot express every conditional
content rule that the application needs. In one frozen run, Bedrock rejected
a 5,519-byte mapped grammar as too large before generation
([diagnostic](evidence/mixed-fixed-slots-successor-qualification-20260926/VALIDATION_DIAGNOSTIC.md));
a compact 2,664-byte successor was accepted but the full worker returned
only four of five items ([result](evidence/compact-typed-slots-qualification-20260926/RESULTS.md)).

The earlier [bounded author probe](evidence/native-author-schema-probe-20260927/RESULTS.md)
shows a compact typed schema can succeed: one live Sonnet 4.6
Converse call produced five tasks, all five compiled and sanitized, and their
code-owned keys matched independent arithmetic and grammar checks. Two
answer-blind reviewers selected the exact key for all ten seed-plus-new
questions and judged every within-item choice set distinct. They disagreed
about bank-level repetition: one rated five overlaps moderate; the other
rated three of nine overlaps strong. Two of that reviewer's strong pairs
crossed the old/new bank boundary. This is an author-only result, not a
five-question verified worker return or evidence of an 80-item varied bank.
The mapped schema changed again as the finite repertoire expanded. A
[one-call current-schema probe](evidence/native-transport-author-probe-20260927/RESULTS.md)
then confirmed Bedrock accepted the 2,013-byte declaration and returned five
tasks that compiled into five sanitized candidates in 27.598 seconds. That
was author-only evidence. A subsequent [bounded full-worker trial](evidence/current-mapped-full-worker-qualification-reauth-20260927/RESULTS.md)
on the same pinned source produced all five compiled and sanitized candidates,
but the final reviewer vetoed a mathematically correct rational-equation item,
so only **four of five** original slots returned. Three Bedrock calls took
85.10 seconds under the six-call/240-second bounds. Two locked answer-blind
reviewers chose the correct key and found distinct choices for all four
returned items, while both flagged limited novelty across the two grammar
formats. That official trial failed. A later post-teaching trial reached Bedrock
but returned **0/5** because a new English scene was omitted from the final
compiler allowlist ([failure](evidence/mapped-full-worker-post-teaching-20260927/RESULTS.md)).
After the allowlist fix, a separately frozen
[full-worker trial](evidence/mapped-full-worker-next-prep-20260927/RESULTS.md)
returned **5/5** original slots in 59.23 seconds with three one-attempt model
calls. Two locked answer-blind reviewers selected all five code-owned keys and
found all 30 within-item choice pairs meaningful. A post-lock audit found all
five explanations and 20 choice-feedback entries sound. Both reviewers also
flagged the two English questions as strongly similar in format and skill, so
this is a narrow single-trial pass, not a bank-wide reliability claim. The
trial used the earlier 2,101-byte source schema. A later
[author-only probe](evidence/native-v9-author-acceptance-20260927/RESULTS.md)
confirmed Bedrock accepts the newer 2,156-byte combined schema and returned
five tasks, including both new math families. Offline replay compiled and
sanitized all five; a harness-only bookkeeping `TypeError` left its immutable
capture marked failed. One locked blind reviewer chose all five source keys,
found all 30 choice pairs meaningful, and reported no strong pair within that
batch. This is author-only evidence, not another full-worker pass.

## Established causes and fixes

| Cause | Evidence | Current response |
| --- | --- | --- |
| A schema-valid rejection can violate a conditional application contract. | Earlier native reviewer output contained fields forbidden on a rejected row; the whole response was lost. | The adapter now discards unused fields only on a `valid:false` row while keeping that row rejected and checking surviving reviews. See [initial investigation](QUESTION_RELIABILITY_INVESTIGATION_20260921.md). |
| Identical mapped author schemas had request-specific Bedrock declaration names. | Changing skill and difficulty metadata changed `jsonSchema.name` even though all three mapped route schemas had unchanged bytes. A first fix also changed the model prompt and failed prompt-identity tests. | The Bedrock transport name is now stable for each route and slot count; the prompt retains its prior hashed identity. Offline tests lock all three schema hashes and the existing prompt expectations. AWS documents a grammar cache, but whether the declaration name participates in its cache key remains unmeasured. |
| Literal distinctness does not imply meaningfully different choices. | Historical model review admitted equivalent wrong answers; local scalar checks missed `21` versus `twenty-one`. | The generic path now vetoes more exact numeric representations, while the closed math/grammar path constructs four choices from a trusted task and checks the key. Paraphrases, units and arbitrary-topic truth still need semantic review. |
| Answer highlighting could be changed by legacy explanatory prose. | The old iOS helper could interpret “incorrect” prose as a key and endorse a distractor. | Grading and highlighting now use the explicit key or a deterministic legacy label. Backend feedback referring to shuffled answer positions is rejected. See [client reproduction](evidence/answer-highlighting-20260921.md). |
| Downstream review and deadlines reduce worker yield. | Earlier mapped workers returned 3/5 after difficulty vetoes, 0/5 after a reviewer timeout, and 4/5 after a model vetoed correct rational-equation teaching. | The proof-scoped difficulty rule and deadline-clamped worker read setting already exist. The rational compiler now shows a verified cross-multiplication and linear solution for all 72 bounded variants; the reviewer veto remains active. The [fresh one-shot worker trial](evidence/mapped-full-worker-next-prep-20260927/RESULTS.md) passed its five-slot key, choice, teaching, and deadline gate, but one pass cannot establish repeat reliability. See [earlier worker](evidence/current-mapped-full-worker-qualification-reauth-20260927/RESULTS.md), [difficulty](evidence/agreement-difficulty-calibration-qualification-20260927/RESULTS.md), and [refill](evidence/mapped-refill-qualification-20260927/RESULTS.md) trials. |
| The native schema can admit a task that the final compiler rejects. | Bedrock returned all five typed tasks under the 2,101-byte schema, but the new gerund scene was missing from the final slot-4 allowlist; the batch returned 0/5. | The allowlist now includes the gerund family. Offline replay of that exact author object reached all five compiled candidates, and a later full worker returned 5/5. A regression takes all 56 schema-admitted English scene/order variants through the complete five-task adapter and compiler route. See [failure](evidence/mapped-full-worker-post-teaching-20260927/RESULTS.md) and [qualification](evidence/mapped-full-worker-next-prep-20260927/RESULTS.md). |
| Reuse history and repertoire were insufficient for a large bank. | The refill's five new candidates were rated strong near-duplicates of earlier items by both blind reviewers. Older linear stems dropped out of numeric history after a template upgrade. The original [offline 40/80-item simulation](evidence/mapped-bank-diversity-simulation-20260927/RESULTS.md) had 60/280 same-slot-family pairs and exhausted both English inventories after 80. | Full-bank history, alternate numeric/grammar structures, and the 72-stem historical numeric mapping are on `main`. The current [capacity gate](MAPPED_BANK_CAPACITY_GATE.md) reaches 85 unique stems; new two-root, gerund, product-complement, and [typed solution-count](evidence/slot2-count-selection-20260927/RESULTS.md) mechanisms reduce same-slot-family pairs to 23/131/152 at 40/80/85. A numeric selector tie-break removes repeated `(a,b)` operand pairs across all three math slots in the 80-item replay. The strict one-use-per-family gate still fails. The 2,156-byte schema was [accepted by Bedrock](evidence/native-v9-author-acceptance-20260927/RESULTS.md), but the current source has not passed another full-worker or repeated-bank trial. |
| A plausible new family can hide multiple grammatical keys. | A proposed quantity-versus-count agreement family looked sound in a first keyless review, but the [revised blind review](evidence/slot3-measurement-rejected-20260927/RESULTS.md) found viable alternative agreement for time and distance sentences, plus strong within-family repetition. | The candidate was rejected before code integration. New scene families require a locked blind one-key and novelty review in addition to compiler checks. |
| Structural families do not capture all semantic repetition. | In a [15-item blind sample](evidence/mapped-combined-bank-blind-20260927/RESULTS.md), both reviewers selected every code-owned key and found distinct choices, yet agreed on four strong near-duplicate pairs across English slots or named numeric families. The [gerund-family blind review](evidence/slot4-gerund-capacity-20260927/RESULTS.md) found all eight keys sound and choices distinct, but four strong within-family near-duplicate pairs. A [solution-count blind review](evidence/slot2-count-selection-20260927/RESULTS.md) selected all 11 sampled keys across two worksheets but called every count-to-count pair strongly similar. A [product-complement blind review](evidence/slot0-product-complement-20260927/RESULTS.md) found four correct keys and distinct choices but all six within-family question pairs strongly similar. | Keep the mapped route opt-in. The selector and qualification must consider cross-slot/cross-family mechanisms and independent full-bank content judgments, not only exact stem or family counters. |
| Rebalancing a finite repertoire cannot eliminate repeated decisions. | The frozen [cross-slot audit](evidence/mapped-cross-slot-mechanism-audit-20260927/RESULTS.md) counted 2/18/76 structural pair patterns at 15/40/80 items that resemble earlier blind-rated strong overlaps. The new gerund family lowers this heuristic to 2/13/55, but its own blind review finds repeated templates. A trial selector reduced maximum-decision pairings but created near-identical minimum-ratio tasks; it was reverted. | These counts are heuristic warnings, not newly blind-confirmed duplicates. Expand substantively different, code-owned objectives and require repeated-bank blind review; do not promote a selector that merely moves the repetition. |
| Passing local tests does not update TestFlight. | The active workflow is manual, has never run, and the required protected environment and AWS OIDC identity were absent in the read-only audit. | [Release audit](evidence/testflight-release-readiness-20260927/RESULTS.md), [scoped bootstrap](../infra/TESTFLIGHT_DEPLOY_BOOTSTRAP.md), and [service-role design](../infra/TESTFLIGHT_EXECUTION_ROLE.md) specify the identity, protected variables, role boundary, rollback artifacts, and live-setting comparison. Nothing was deployed. |

The integrated backend passed **1,458 unit tests**, Ruff on changed Python
files, and `git diff --check`. Both SAM templates passed lint; the deployment
script suite, actionlint, shellcheck, and AWS's read-only CloudFormation
template validation also passed. The earlier bootstrap audit compared five
nonsecret live TestFlight settings. These checks verify deterministic behavior
and packaging preparation; they are not a statistical model-quality measurement.

## What would close the remaining gap

The closed constructor is the defensible route for a reliability claim:
ask the model for a bounded task specification, calculate or compile the
answer and distractors in code, then retain independent review and fail
closed on unsupported content. It needs a much broader set of substantive
objectives and question formats for a 40/80-item bank, with full-bank
history and answer-blind cross-bank review. The current 2,156-byte source
needs a full-worker trial with its own solver/reviewer calls; the successful
five-slot worker trial used an earlier source. A repeated-bank trial must
hold the key, difficulty, teaching, distinctness, and deadline properties over
the desired inventory size. Schema compliance or one successful batch cannot
replace those tests.

For arbitrary topics without a deterministic solver or trusted source,
absolute one-right-answer and semantic-distinctness guarantees are not
available from a prompt or JSON Schema. The product can generate candidates
and reject uncertain ones; it should state a narrower supported scope when
it needs a deterministic guarantee. Keep the experimental mapped route off
and the deployed worker on legacy until the content and release gates pass.
