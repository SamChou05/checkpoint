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

The latest [bounded author probe](evidence/native-author-schema-probe-20260927/RESULTS.md)
shows the current compact typed schema can succeed: one live Sonnet 4.6
Converse call produced five tasks, all five compiled and sanitized, and their
code-owned keys matched independent arithmetic and grammar checks. Two
answer-blind reviewers selected the exact key for all ten seed-plus-new
questions and judged every within-item choice set distinct. They disagreed
about bank-level repetition: one rated five overlaps moderate; the other
rated three of nine overlaps strong. Two of that reviewer's strong pairs
crossed the old/new bank boundary. This is an author-only result, not a
five-question verified worker return or evidence of an 80-item varied bank.

## Established causes and fixes

| Cause | Evidence | Current response |
| --- | --- | --- |
| A schema-valid rejection can violate a conditional application contract. | Earlier native reviewer output contained fields forbidden on a rejected row; the whole response was lost. | The adapter now discards unused fields only on a `valid:false` row while keeping that row rejected and checking surviving reviews. See [initial investigation](QUESTION_RELIABILITY_INVESTIGATION_20260921.md). |
| Identical mapped author schemas had request-specific Bedrock declaration names. | Changing skill and difficulty metadata changed `jsonSchema.name` even though all three mapped route schemas had unchanged bytes. A first fix also changed the model prompt and failed prompt-identity tests. | The Bedrock transport name is now stable for each route and slot count; the prompt retains its prior hashed identity. Offline tests lock all three schema hashes and the existing prompt expectations. AWS documents a grammar cache, but whether the declaration name participates in its cache key remains unmeasured. |
| Literal distinctness does not imply meaningfully different choices. | Historical model review admitted equivalent wrong answers; local scalar checks missed `21` versus `twenty-one`. | The generic path now vetoes more exact numeric representations, while the closed math/grammar path constructs four choices from a trusted task and checks the key. Paraphrases, units and arbitrary-topic truth still need semantic review. |
| Answer highlighting could be changed by legacy explanatory prose. | The old iOS helper could interpret “incorrect” prose as a key and endorse a distractor. | Grading and highlighting now use the explicit key or a deterministic legacy label. Backend feedback referring to shuffled answer positions is rejected. See [client reproduction](evidence/answer-highlighting-20260921.md). |
| Downstream review and deadlines reduce worker yield. | A mapped worker returned 3/5 when a model difficulty rating vetoed two code-owned English items; a later narrowly calibrated run returned 5/5 mechanically but failed blind level-2 content at 4/5. A refill returned 0/5 after its reviewer timed out. | The proof-scoped difficulty rule and deadline-clamped worker read setting already exist. Widening the rule or increasing timeout alone would not make the failed content qualify. See [difficulty trial](evidence/agreement-difficulty-calibration-qualification-20260927/RESULTS.md) and [refill trial](evidence/mapped-refill-qualification-20260927/RESULTS.md). |
| Reuse history and repertoire were insufficient for a large bank. | The refill's five new candidates were rated strong near-duplicates of earlier items by both blind reviewers. Older linear stems dropped out of numeric history after a template upgrade. The [offline 40/80-item simulation](evidence/mapped-bank-diversity-simulation-20260927/RESULTS.md) produced unique exact stems but 60/280 same-slot-family pairs and exhausted both English inventories after 80. Those structural counts are not blind semantic-duplicate counts. | Full-bank English history, alternate numeric/grammar structures, and a 72-stem historical numeric mapping are now on `main`; an 80-item diversity qualification still has not passed. |
| Passing local tests does not update TestFlight. | The active workflow is manual, has never run, and the required protected environment and AWS OIDC identity were absent in the read-only audit. | [Release audit](evidence/testflight-release-readiness-20260927/RESULTS.md), [scoped bootstrap](../infra/TESTFLIGHT_DEPLOY_BOOTSTRAP.md), and [service-role design](../infra/TESTFLIGHT_EXECUTION_ROLE.md) specify the identity, protected variables, role boundary, rollback artifacts, and live-setting comparison. Nothing was deployed. |

The integrated backend passed **1,441 unit tests**, Ruff on changed Python
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
history and answer-blind cross-bank review. A fresh full-worker trial must
meet the prescribed five-slot key, difficulty, teaching, distinctness and
deadline gates, then a repeated-bank trial must hold those properties over
the desired inventory size. Schema compliance or one successful batch cannot
replace those tests.

For arbitrary topics without a deterministic solver or trusted source,
absolute one-right-answer and semantic-distinctness guarantees are not
available from a prompt or JSON Schema. The product can generate candidates
and reject uncertain ones; it should state a narrower supported scope when
it needs a deterministic guarantee. Keep the experimental mapped route off
and the deployed worker on legacy until the content and release gates pass.
