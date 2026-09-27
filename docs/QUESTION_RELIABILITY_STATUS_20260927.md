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

A separately frozen [v9 full-worker attempt](evidence/native-v9-full-worker-qualification-20260927/RESULTS.md)
then returned **4/5** original slots: all five tasks compiled, but the
reviewer rejected a product-equation item whose explanation checked the
offered choices without proving domain-wide uniqueness. Two answer-blind
reviewers selected all four returned keys. The compiler now supplies a
checked uniqueness proof, and the exposed-root quadratic has been expanded
so its answer is not visible in the stem. On that teaching-fixed source, a
new [bounded full-worker trial](evidence/native-v9-teaching-fixed-full-worker-20260927/RESULTS.md)
returned **5/5** in 62.707 seconds with three Converse calls. Both locked
blind reviewers selected all five code-owned keys, judged all 30 within-item
choice pairs distinct, and rated difficulty 2–3. A post-lock audit found all
five explanations and 20 feedback entries sound. Both reviewers also flagged
substantial repetition between the two English items, so this is a narrow
single-batch pass rather than bank-wide reliability evidence.

The subsequent [English partitive and compound-each change](evidence/english-each-contrast-20260927/RESULTS.md)
expanded the closed scene repertoire and the combined native schema to 2,226
bytes. In a frozen 20-item offline worksheet, two answer-blind reviewers chose
all 20 code-owned keys, found all 120 within-item choice pairs distinct, and
found no strong English overlap. They still agreed that Q05/Q06 and Q11/Q16
strongly repeat numeric solving methods despite different family labels. This
source passed local checks. A separately frozen [one-call live author trial](evidence/english-native-author-acceptance-20260927/RESULTS.md)
then confirmed Bedrock accepts the 2,226-byte schema and returned five tasks
that compiled without failures in 19.652 seconds. Two answer-blind reviewers
chose all five code-owned keys and found distinct choices, but both flagged
two strong within-batch format repeats. The model chose older English scenes;
the new partitive/each scenes have only passed socket-free compilation. A
full-worker repeated-bank run remains a separate qualification step.

The next isolated [numeric expansion](evidence/numeric-mechanism-expansion-20260927/RESULTS.md)
added two distinct compiled solve mechanisms, raising theoretical strict
one-use capacity from 15 to 20 complete items. A three-root cubic candidate
was rejected as too hard by two blind reviewers; a centered-square candidate
was adjusted after both reviewers rated its smallest case too easy. The
[English sentence-selection format](evidence/english-sentence-selection-20260927/RESULTS.md)
gave slot 4 four full-sentence options instead of another two-blank ordered
pair. Two blind reviewers found all four sample keys unique and choices
distinct at the target difficulty; all four were low-overlap against the old
slot-3 format, but strongly repetitive among themselves. The merged native
schema is now 2,357 bytes, version 12. A separately frozen
[one-call live author trial](evidence/combined-v12-native-author-acceptance-20260927/RESULTS.md)
confirmed that Bedrock accepts it. All five tasks compiled, including one of
the new centered-square numeric tasks. Two answer-blind reviewers chose all
five code-owned keys and found distinct within-item choices, but both flagged
repeated English format. A separately frozen
[v12 full-worker trial](evidence/combined-v12-full-worker-qualification-20260927/RESULTS.md)
made three Converse calls in 98.275 seconds and compiled/sanitized all five
tasks, but returned **4/5**: the final reviewer rated a full-sentence English
item difficulty 4 and the level-2 agreement policy vetoed it. Two locked
answer-blind reviewers independently selected all five code-owned keys,
found all 30 choice pairs distinct, and rated every item difficulty 2–3,
including the rejected item at 3. A post-lock audit found all five main
explanations and 20 choice-feedback entries sound. This is a failed worker
trial with a measured difficulty-calibration disagreement; it cannot be
retroactively counted as 5/5. Repeated-bank yield also remains unqualified.
The subsequent source revision prefers a blind-rated level-2 variant when
first adding this format from another authored family. The reviewer-4 veto
and learner difficulty metadata remain unchanged. This is an offline-verified
selection change, not a successful new live worker trial or a claim that all
eight scene/order variants have independent difficulty ratings.
On that selector-first source, a new separately frozen
[full-worker trial](evidence/combined-v12-selector-first-full-worker-qualification-20260927/RESULTS.md)
also returned **4/5** in 130.220 seconds with three Converse calls. All five
tasks compiled/sanitized; the final reviewer agreed on the withheld
full-sentence key and rated it difficulty 3, but marked its main explanation
uncertain. That main explanation justified the key without showing why the
other three sentences were wrong; the rule-specific per-choice feedback was
not included in the reviewer's input. Two locked answer-blind reviewers later
found all five candidate keys unique, all 30 choice pairs distinct, and all
five difficulty 2–3. They disagreed on within-batch repetition. The reviewer
veto and failed trial remain in force.
The compiler now makes the main explanation for each full-sentence scene
state the required verb and agreement rule for **all four** offered sentences,
because the final reviewer sees that main explanation but not the separate
per-choice teaching. An independent read-only audit checked all eight
scene/order variants and found their keys, distractor corrections, and main
explanations sound; every main explanation is 331–362 characters under the
420-character limit. The reviewer’s uncertainty veto remains unchanged.
On that revision, the separately frozen [explained v12 full-worker
trial](evidence/combined-v12-explained-full-worker-qualification-20260927/RESULTS.md)
again returned **4/5**. The final reviewer accepted the revised explanation,
exact key, and all other content of the full-sentence item, but rated its
four-rule reasoning difficulty 4 and the existing level-2/3 gate withheld it.
Two answer-blind reviewers independently rated that item 3 and found all five
candidate keys and 30 choice pairs sound. Their disagreement with the live
difficulty rating does not change the failed worker result.
After two live full-worker reviewer vetoes involving the four-rule
full-sentence format, the mapped level-2 slot-4 selector now quarantines all
`select_*` variants, including an author-proposed one. Direct compilation and
the schema retain the format for future level-3 calibration; reviewer key,
difficulty, and explanation vetoes remain unchanged. The eligible slot-4
inventory is 32 exact stems rather than 40, and it fails closed when those
32 are used. The offline capacity replay still completes 20/40/80/85 items
with unique exact stems, but four remaining slot-4 solve families repeat.
On the quarantined source, a new separately frozen
[full-worker trial](evidence/combined-v12-level2-quarantine-full-worker-qualification-20260927/RESULTS.md)
returned **5/5 original slots** in 58.785 seconds with three Converse calls.
The independent answer-blind reviewers matched all five keys, rated all five
difficulty 2, and judged all 30 choice pairs distinct. A post-lock audit found
all five main explanations and 20 choice-feedback entries sound. Both blind
reviewers still called the two English questions a strong format/method
repeat. This is a narrow one-batch pass, not repeated-bank qualification.
An [offline single-rule full-sentence prototype](evidence/level2-sentence-selection-prototype-20260927/README.md)
reached unique keys and level-2 ratings, but its best blind-reviewed version
had only 3/6 and 5/6 meaningfully distinct choice pairs. It was not added to
the constructor; simplifying this format alone does not solve distractor
variety.

The [current combined-source offline replay](evidence/combined-current-bank-replay-20260927/RESULTS.md)
constructed 20/40/80 unique exact stems, but found 1/14/78 same numeric
solve-signature pairs and 30/133/561 same prompt-format pairs within slots.
Two independent blind reviews of a stratified 20-item sample found all keys
unique and all choices distinct after one reviewer corrected a recorded
key-letter transcription error. Both called the same eight cross-item pairs
strong repeats. Adding inventory and maintaining full-bank stem history alone
do not deliver a varied bank.

An earlier selector balanced compiled numeric solve signatures and spaced the
full-sentence English format. In the [chronological replay](evidence/selector-balanced-bank20-20260927/RESULTS.md), numeric signature pairs fell
from 1/14/78 to 0/12/72 at 20/40/80 items and within-slot response-format
pairs fell from 30/133/561 to 26/125/552. Two locked blind reviewers selected
all 20 code-owned keys, found all choices distinct at difficulty 2–3, and
agreed on four strongly repetitive cross-item pairs. The new worksheet is
chronological while the older one was stratified, so their blind pair counts
are not a matched before/after result. The remaining repeats show why the
selector improvement cannot substitute for more substantive formats and
objectives.
The [selector-first 20-item blind review](evidence/selector-singular-first-bank20-20260927/RESULTS.md)
likewise found 20/20 unique keys and 120/120 distinct within-item pairs, but
both reviewers flagged four strong repeated pairs across questions. One
reviewer also flagged 31/190 pairs for a repeated prompt/response skeleton;
the other required both method and format similarity and flagged 4/190.
The current level-2 quarantine excludes the full-sentence format that this
historical worksheet contained; its own 20/40/80 replay remains structurally
unique. In its separate [answer-blind first-20
review](evidence/level2-quarantine-bank20-20260927/RESULTS.md), both reviewers
matched 20/20 keys, rated all items difficulty 2–3, and found 120/120 choice
pairs distinct. They agreed on seven strong cross-question repeats; one
reviewer flagged 41/190 strong pairs using a broader format criterion, while
the other flagged 7/190. The current bank therefore still fails a quality
bar requiring no strong repetition, despite the narrow 5/5 live worker pass.

A separate [closed pronoun-role prototype](evidence/pronoun-constructor-blind-20260927/RESULTS.md)
has 16 scene/order variants across two response mechanisms. Two independent
answer-blind reviewers matched all 16 code-owned keys and found all 96
within-item choice pairs meaningful, but agreed that 56/120 cross-item pairs
strongly repeat. Both caught an unsupported implication in the initial
single-speaker prompt; that conditional wording was corrected and passed two
targeted keyless reviews. The prototype remains outside the production schema
and author route. An [opt-in generic seven-candidate reserve](evidence/generic-reserve-seven-probe-20260927/README.md)
now runs the existing sanitizer, answer-blind solver, and reviewer once and
returns five only if five survive. It is disabled by default, excludes mapped
and source-bound requests. Its first [frozen live trial](evidence/generic-reserve-seven-probe-20260927/RESULTS.md)
failed in the harness before any provider dispatch, so it did not measure
model quality. The corrected, separately frozen [second trial](evidence/generic-reserve-seven-probe-v2-20260927/RESULTS.md)
returned seven schema-valid authored rows, all sanitized, but Bedrock rejected
the seven-row answer-blind solver request with `ValidationException`. No
reviewer ran and the worker returned **0/5**; the capture retains only the
error code, so the precise provider validation cause is unknown. Smaller
verification batches are now implemented behind the same disabled-by-default
flag: a full seven-row author/sanitize pass followed by at-most-four-row and
at-most-three-row solver/reviewer calls, with the existing vetoes and a
five-survivor fail-closed return. Socket-free tests pass, and a later live
trial completed the five-call 4+3 path, but its independent content gate
failed. The
seven authored rows then passed [independent keyless content review](evidence/generic-reserve-author7-blind-20260927/RESULTS.md)
for key and choice distinctness: both reviewers matched 7/7 private keys and
42/42 choice pairs. Both rated three rows difficulty 1 despite the level-2
request, leaving at most four strict difficulty-2 survivors. They disagreed
about one possible cross-item repeat and G04 self-containment. This author-only
result does not repair the 0/5 worker failure.
The separately frozen [third reserve trial](evidence/generic-reserve-seven-probe-v3-20260927/RESULTS.md)
tested the bounded 4+3 source but failed at the author stage: the single
Sonnet 4.6 native seven-row call stopped at its shared 16,000-token output
limit with incomplete JSON after 155.586 seconds. It returned **0/5** before
any solver or reviewer call, so the smaller verification transport remains
unmeasured live. This is a second independent obstacle to reliable seven-row
reserve yield, alongside trial 02's seven-row solver validation error and
the blind-rated difficulty misses in its authored content.
A [one-call author comparison](evidence/generic-author-no-thinking-probe-20260927/RESULTS.md)
kept Trial 03's request, model, and native schema unchanged while disabling
adaptive thinking. Bedrock returned seven native rows in 48.980 seconds using
1,162 output tokens, and the existing sanitizer accepted all seven offline.
This shows a viable author transport on one sample, not a verified worker
return. Two [locked blind reviews](evidence/generic-author-no-thinking-probe-20260927/RESULTS.md)
matched all 7 source keys and found all 42 choice pairs distinct, yet both
rated two items below the requested difficulty and agreed on a strong
cross-item repetition; both also flagged an implicit sampling assumption.
The wire
also changed the output cap and temperature as a consequence of disabling
thinking, so the observation does not isolate a single low-level parameter.
A separately frozen [request-only difficulty directive probe](evidence/generic-probability-directive-author-probe-20260927/RESULTS.md)
kept adaptive-high author settings but added explicit level-2 problem and
diagnostic distractor guidance. It too stopped at the 16,000-token output
limit, with incomplete native JSON after 165.589 seconds. Prompt wording
could not be evaluated for content quality under that configuration.
A [fourth reserve trial](evidence/generic-reserve-seven-probe-v4-20260927/RESULTS.md)
disabled thinking while keeping the original request. It completed author7,
solver4, reviewer4, solver3, and reviewer3 in about 104 seconds; seven author
rows sanitized, six verified, and the worker returned five in original order.
Two independently locked blind reviewers selected all 5/5 returned keys and
found all 30/30 within-item choice pairs meaningful, yet both rated one item
below the requested level and identified a strong expected-money/answer-format
repeat. The authored teaching for all five matched the key on post-lock
inspection. This is a live transport/yield success and a **content-gate
failure**, so the generic reserve remains opt-in and disabled by default.
A [frozen one-call replay](evidence/generic-reserve-diversity-review-replay-20260927/RESULTS.md)
added an explicit material-repetition instruction to the same second-reviewer
request. Sonnet still set every novelty flag false, including the repeat
identified by both blind reviewers. The ineffective instruction was removed;
the code now shows that reviewer only verified first-chunk survivors, avoiding
false suppression by rejected candidates. A [dedicated keyless pairwise
probe](evidence/generic-reserve-pairwise-diversity-probe-20260927/RESULTS.md)
used the spare sixth-call concept to judge all 15 pairs among six verified
questions. It caught only the expected-money repeat that both blind reviews
found. A [second independent pairwise probe](evidence/generic-pairwise-second-blind-probe-20260927/RESULTS.md)
on another six-question worksheet caught that batch's expected-money repeat
but also flagged two different probability operations as one strong repeat.
The model-only pairwise gate is therefore not enabled: it improves recall in
these samples but can falsely suppress a valid five-item batch. A narrower
code-owned [expected-money mechanism gate](evidence/generic-reserve-monetary-gate-20260927/RESULTS.md)
is now implemented **only within the disabled-by-default reserve**. It
filters verified survivors before the five-item return and excludes Trial
04's repeated expected-winnings item in an offline replay, retaining source
ordinals 1,2,3,4,6. Independent review supplied three false-positive
counterexamples, all now covered by regressions. Source ordinal 6 was not in
Trial 04's returned-five blind worksheet, so this replay is not a new content
qualification or a general novelty guarantee.
A separate disabled-thinking author-only trial added the explicit probability
directive: it completed seven native rows in 19.641 seconds, but the existing
sanitizer rejected one for duplicate choices. Two [independent blind
reviews](evidence/generic-author-no-thinking-directive-probe-20260927/RESULTS.md)
of the six survivors found that one had **no correct offered choice**: its
asserted key was `−$0.50`, while its own explanation calculated the correct
expected net gain as `−$1.00`. Both also found a below-level item and a strong
expected-money repeat. The mandatory solver was not run in this author-only
probe, so this demonstrates the exact author error that downstream
verification must catch; it does not establish a final worker escape.
Neither this author-only trial nor one completed worker batch establishes
reliable arbitrary-topic MCQs.

Two standalone math response-format constructors were compared against six
quarantined level-2 examples in a [frozen 12-item blind worksheet](evidence/math-format-mixed-blind-20260927/RESULTS.md).
Both reviewers matched all 12 code-owned keys and found all 72 within-item
choice pairs meaningful, yet flagged 7 and 12 of 66 cross-item pairs as
strong repetition. Both agreed that the three comparison items repeat each
other's direction-plus-gap response and the three worked-evaluation items
repeat each other's precedence-and-error-pattern response. These constructors
are not production-wired; one-key and choice validity alone do not establish
bank novelty.

## Established causes and fixes

| Cause | Evidence | Current response |
| --- | --- | --- |
| A schema-valid rejection can violate a conditional application contract. | Earlier native reviewer output contained fields forbidden on a rejected row; the whole response was lost. | The adapter now discards unused fields only on a `valid:false` row while keeping that row rejected and checking surviving reviews. See [initial investigation](QUESTION_RELIABILITY_INVESTIGATION_20260921.md). |
| Identical mapped author schemas had request-specific Bedrock declaration names. | Changing skill and difficulty metadata changed `jsonSchema.name` even though all three mapped route schemas had unchanged bytes. A first fix also changed the model prompt and failed prompt-identity tests. | The Bedrock transport name is now stable for each route and slot count; the prompt retains its prior hashed identity. Offline tests lock all three schema hashes and the existing prompt expectations. AWS documents a grammar cache, but whether the declaration name participates in its cache key remains unmeasured. |
| Literal distinctness does not imply meaningfully different choices. | Historical model review admitted equivalent wrong answers; local scalar checks missed `21` versus `twenty-one`. | The generic path now vetoes more exact numeric representations, while the closed math/grammar path constructs four choices from a trusted task and checks the key. Paraphrases, units and arbitrary-topic truth still need semantic review. |
| Answer highlighting could be changed by legacy explanatory prose. | The old iOS helper could interpret “incorrect” prose as a key and endorse a distractor. | Grading and highlighting now use the explicit key or a deterministic legacy label. Backend feedback referring to shuffled answer positions is rejected. See [client reproduction](evidence/answer-highlighting-20260921.md). |
| Downstream review and deadlines reduce worker yield. | Earlier mapped workers returned 3/5 after difficulty vetoes, 0/5 after a reviewer timeout, and 4/5 after a model vetoed correct rational-equation teaching. | The proof-scoped difficulty rule and deadline-clamped worker read setting already exist. The rational compiler now shows a verified cross-multiplication and linear solution for all 72 bounded variants; the reviewer veto remains active. The [fresh one-shot worker trial](evidence/mapped-full-worker-next-prep-20260927/RESULTS.md) passed its five-slot key, choice, teaching, and deadline gate, but one pass cannot establish repeat reliability. See [earlier worker](evidence/current-mapped-full-worker-qualification-reauth-20260927/RESULTS.md), [difficulty](evidence/agreement-difficulty-calibration-qualification-20260927/RESULTS.md), and [refill](evidence/mapped-refill-qualification-20260927/RESULTS.md) trials. |
| The native schema can admit a task that the final compiler rejects. | Bedrock returned all five typed tasks under the 2,101-byte schema, but the new gerund scene was missing from the final slot-4 allowlist; the batch returned 0/5. | The allowlist now includes the gerund family. Offline replay of that exact author object reached all five compiled candidates, and a later full worker returned 5/5. A regression takes all 56 schema-admitted English scene/order variants through the complete five-task adapter and compiler route. See [failure](evidence/mapped-full-worker-post-teaching-20260927/RESULTS.md) and [qualification](evidence/mapped-full-worker-next-prep-20260927/RESULTS.md). |
| Reuse history and repertoire were insufficient for a large bank. | The refill's five new candidates were rated strong near-duplicates of earlier items by both blind reviewers. Older linear stems dropped out of numeric history after a template upgrade. The original [offline 40/80-item simulation](evidence/mapped-bank-diversity-simulation-20260927/RESULTS.md) had 60/280 same-slot-family pairs and exhausted both English inventories after 80. | Full-bank history, alternate numeric/grammar structures, and the 72-stem historical numeric mapping are on `main`. The current [capacity gate](MAPPED_BANK_CAPACITY_GATE.md) reaches 85 unique stems; new two-root, gerund, product-complement, and [typed solution-count](evidence/slot2-count-selection-20260927/RESULTS.md) mechanisms yield 18/112/128 same-slot-family pairs at 40/80/85 after the level-2 sentence-selection quarantine. A numeric selector tie-break removes repeated `(a,b)` operand pairs across all three math slots in the 80-item replay. The strict one-use-per-family gate still fails. The [20-item blind sample](evidence/current-20-bank-blind-20260927/RESULTS.md) found one strong repeat and a below-level factored-root item; the latter was fixed and [blind checked](evidence/expanded-two-root-blind-20260927/RESULTS.md), but the numeric repeats remain. The quarantined 2,357-byte source passed one full-worker batch, not a repeated-bank trial. |
| Different labels can hide the same numeric solve. | Both reviewers of the [English-each 20-item worksheet](evidence/english-each-contrast-20260927/RESULTS.md) rated Q05/Q06 (quadratic equality) and Q11/Q16 (linear upper bound) as their strongest repeats. An [offline compiled-graph probe](evidence/solve-signature-gate-20260927/RESULTS.md) found exactly those two matches across each review's 190 pairs and no reviewed moderate/low false positives. The [combined-source replay](evidence/combined-current-bank-replay-20260927/RESULTS.md) found a cross-family signature repeat already at 20. | The production selector now ranks the closed graph signature before the family label, reducing same-signature pairs to 0/12/72 at 20/40/80. It is a **balancing preference**, not a rejection gate or semantic guarantee. The 20-item blind sample still has a strongly similar linear-equation pair under different graph signatures. A strict one-use gate is not enabled: 40/80 exceed finite inventory, and failure behavior must not silently lose questions. |
| A plausible new family can hide multiple grammatical keys. | A proposed quantity-versus-count agreement family looked sound in a first keyless review, but the [revised blind review](evidence/slot3-measurement-rejected-20260927/RESULTS.md) found viable alternative agreement for time and distance sentences, plus strong within-family repetition. | The candidate was rejected before code integration. New scene families require a locked blind one-key and novelty review in addition to compiler checks. |
| Structural families do not capture all semantic repetition. | In a [15-item blind sample](evidence/mapped-combined-bank-blind-20260927/RESULTS.md), both reviewers selected every code-owned key and found distinct choices, yet agreed on four strong near-duplicate pairs across English slots or named numeric families. The [gerund-family blind review](evidence/slot4-gerund-capacity-20260927/RESULTS.md) found all eight keys sound and choices distinct, but four strong within-family near-duplicate pairs. A [solution-count blind review](evidence/slot2-count-selection-20260927/RESULTS.md) selected all 11 sampled keys across two worksheets but called every count-to-count pair strongly similar. A [product-complement blind review](evidence/slot0-product-complement-20260927/RESULTS.md) found four correct keys and distinct choices but all six within-family question pairs strongly similar. In the [live English v10 author sample](evidence/english-native-author-acceptance-20260927/RESULTS.md), two reviewers found two strong within-batch format repeats despite five distinct family/scene labels. | Keep the mapped route opt-in. The selector and qualification must consider both solving method and question format, including cross-slot/cross-family comparisons; exact stem and family counters are insufficient. |
| Rebalancing a finite repertoire cannot eliminate repeated decisions. | The frozen [cross-slot audit](evidence/mapped-cross-slot-mechanism-audit-20260927/RESULTS.md) counted 2/18/76 structural pair patterns at 15/40/80 items that resemble earlier blind-rated strong overlaps. The new gerund family lowers this heuristic to 2/13/55, but its own blind review finds repeated templates. A trial selector reduced maximum-decision pairings but created near-identical minimum-ratio tasks; it was reverted. | These counts are heuristic warnings, not newly blind-confirmed duplicates. Expand substantively different, code-owned objectives and require repeated-bank blind review; do not promote a selector that merely moves the repetition. |
| Passing local tests does not update TestFlight. | The active workflow is manual, has never run, and the required protected environment and AWS OIDC identity were absent in the read-only audit. | [Release audit](evidence/testflight-release-readiness-20260927/RESULTS.md), [scoped bootstrap](../infra/TESTFLIGHT_DEPLOY_BOOTSTRAP.md), and [service-role design](../infra/TESTFLIGHT_EXECUTION_ROLE.md) specify the identity, protected variables, role boundary, rollback artifacts, and live-setting comparison. Nothing was deployed. |

The integrated backend passed **1,501 unit tests**, Ruff on changed Python
files, and `git diff --check`. Both SAM templates passed lint; the deployment
script suite, actionlint, shellcheck, and AWS's read-only CloudFormation
template validation also passed. The earlier bootstrap audit compared five
nonsecret live TestFlight settings. These checks verify deterministic behavior
and packaging preparation; they are not a statistical model-quality measurement.
An independent current-source iOS audit also ran the focused simulator
answer-highlighting suite: 16/16 tests passed, including choice permutations,
persistence, and legacy labels. The app preserves the backend's explicit key
through shuffling; this does not establish that every backend-approved key is
semantically right or update the older deployed TestFlight build.

## What would close the remaining gap

The closed constructor is the defensible route for a reliability claim:
ask the model for a bounded task specification, calculate or compile the
answer and distractors in code, then retain independent review and fail
closed on unsupported content. It needs a much broader set of substantive
objectives and question formats for a 40/80-item bank, with full-bank
history and answer-blind cross-bank review. The 2,156-byte source passed one
full-worker trial with its own solver/reviewer calls and independent content
review; the 2,226-byte source passed one author/schema trial but not the full
worker. The current 2,357-byte source passed one author/schema trial; its
first three full-worker trials returned 4/5 for different reviewer vetoes.
After quarantining the four-rule sentence selection at level 2, a fourth
one-shot trial met its five-slot key, choice, teaching, difficulty, and
deadline gate, with two locked blind reviews and a post-lock teaching audit.
Its two English items still strongly repeated a format. A repeated-bank trial must
hold the key, difficulty, teaching, distinctness, and deadline properties over
the desired inventory size. Schema compliance or one successful batch cannot
replace those tests.

For arbitrary topics without a deterministic solver or trusted source,
absolute one-right-answer and semantic-distinctness guarantees are not
available from a prompt or JSON Schema. The product can generate candidates
and reject uncertain ones; it should state a narrower supported scope when
it needs a deterministic guarantee. Keep the experimental mapped route off
and the deployed worker on legacy until the content and release gates pass.
