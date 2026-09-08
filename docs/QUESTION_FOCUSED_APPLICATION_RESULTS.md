# Focused application results — September 8, 2026

## Decision

The focused authoring variant **did not establish a correctness improvement and will not become the default**. It returned three questions versus two from the balanced prompt, but two of its three returned questions retained misleading generic-reference explanations. Comparable choice formats did not establish missing facts or prevent stronger-than-supported teaching. Neither arm met the prospective favorable criterion.

The [opt-in implementation and protocol](QUESTION_FOCUSED_APPLICATION_PROTOCOL.md) remain available for reproducibility. This run supplies no reason to add another accuracy checklist, increase the output-token ceiling or promote this prompt. No deployment, default, stored question or learning-history change occurred.

## Execution and independent assessment

The experiment changed only the author system instructions within each pair. Kimi K2.5 authored two new questions per goal for three previously examined goals; Sonnet 4.6 performed the same complete-choice solving and immutable teaching review. Thinking remained disabled, output allowance 6,000 tokens, temperature 0.2, one generation attempt, three calls per operation and 18 overall. The [capture](evidence/focused-application-capture-20260908.json) records **14 completed calls**, six completed operations, 12 raw candidates and no repair or retry. Every response ended normally with known usage and confirmed cleanup. Output ranged from 52 to 707 tokens per call. Total usage was **26,751 input and 7,275 output tokens**.

The [operational audit](evidence/focused-application-operational-audit-20260908.json) rebuilt the plan and replayed all requests and decisions without a provider call. All 33 source files matched committed revision `a4623610ab883c5feaeacd9212ff799257576f1d`; paired initial requests differed only in system text. Recorded SDK intervals total 106.18 seconds and worker intervals 115.34 seconds, not whole-trial wall time or deployed latency. All five returns preserved the author's exact main explanation and carried policy revision 3 with empty choice feedback.

Two assistant assessors received shuffled stems/choices, goals and source summaries without keys, mains, author variant, model difficulty or runtime verdict. Both froze their first passes before opening the teaching packet; both teaching passes were saved before the root opened the arm mapping. The hypothesis was known and style could offer clues. These are assistant assessments, not human expert validation or learner-calibrated difficulty. The [manifest](evidence/focused-application-summary-20260908.json) preserves all file hashes, per-candidate judgments and all 12 exact raw/packet/assessment/return joins.

## Counts and runtime decisions

Counts use all six raw candidates per arm. A/B denotes separate assessors; their scope differences are retained rather than averaged into a single truth score.

| Observation | Balanced | Focused application |
| --- | ---: | ---: |
| Raw questions | 6 | 6 |
| Authored key matches a warranted unique answer, A/B | 2 / 4 | 2 / 2 |
| Complete teaching under recorded scope, A/B | 1 / 3 | 2 / 2 |
| Main over runtime 420-character limit | 2 | 2 |
| Stem over 320-character limit | 1 | 0 |
| Returned by runtime | 2 | 3 |
| Meets all prospective requirements | 0 | 0 |

All 12 mains exceed the author's 320-character instruction. Eight fit the separate 420-character runtime allowance. All 48 choices fit 140 characters. There were five pre-solver exclusions, seven solver inputs, six audit inputs and five returns. Length rejection is not evidence of semantic detection.

| ID | Arm | Main characters | Runtime outcome | Content finding |
| --- | --- | ---: | --- | --- |
| q01 | Focused | 355 | Returned | Supported equal-gain/mean-slope comparison; counting-method teaching caveat; level 2. |
| q02 | Focused | 357 | Returned | Grammatical article tuple does not establish the required generic meaning of breakfast. |
| q03 | Focused | 518 | Length exclusion | Initial care guidance has a defensible core; treatment/cause qualifications differ by assessor. |
| q04 | Balanced | 485 | Length exclusion | Correct spacing conversions; trail-versus-terrain geometry interpretation differs. |
| q05 | Balanced | 331 | Returned | Supported new-plant propagation distinction and teaching; level 2, weak distractors. |
| q06 | Balanced | 429 | Length exclusion | Supported A readiness; B recovery advice is underqualified. Key/depth judgments differ. |
| q07 | Focused | 366 | Returned | Specific past honey use is misleadingly explained as generic class reference. |
| q08 | Focused | 479 | Length exclusion | Supported new-plant key/main; root-only alternative remains potentially compatible. |
| q09 | Balanced | 404 | Stem length exclusion (321) | Unwarranted gain/profile conclusions and problematic intermediate-contour description. |
| q10 | Balanced | 411 | Returned | Supported contextual bridging; indefinite-to-definite history wording needs scope qualification. |
| q11 | Focused | 390 | Solver uncertainty veto | Contour spacing establishes increasing steepness magnitude, not uphill direction. |
| q12 | Balanced | 405 | Unsupported-main veto | Author explains first dough introduction while the question asks about the second occurrence. |

The q11 solver correctly identified missing elevation direction; no final auditor received that item. The [executed native counterexample](evidence/focused-application-native-checks-20260908.json) independently confirms that ascending and descending profiles can share the same 2 km route, 20 m intervals and 400→200→100 m spacings. Both have increasing absolute grades of 5%, 10% and 20%. The illustrative profiles establish missing direction information, not actual endpoint elevations or a false steepness calculation.

The q12 auditor rejected the main, but parts of its rationale overgeneralized the countability of dough. The more direct independent finding is that the author explains the wrong occurrence. A rejection does not make every reason correct. Conversely, the q02 auditor acknowledged the contextual breakfast reading but treated the category demanded by the question as support for the intended answer. Both focused English questions passed with supported-main declarations and empty issue arrays despite the independent semantic concerns.

## Construction uptake and qualifications

The focused arm did produce aligned article tuples in q02, a precise next-step request in q03 and matched gain/slope dimensions in q01. Those changes did not establish harder cognitive work: the first article alone eliminates q02's rivals, and q01 is a direct same-rise/different-run comparison. Q08 still mixes rooting with new-plant success. Q11 offers aligned joint outcomes, but each plausible outcome requires an elevation direction absent from the stem. Comparable options help define the question; they do not supply its missing premises.

The [A stem](evidence/focused-application-stem-assessment-a-20260908.json) and [B stem](evidence/focused-application-stem-assessment-b-20260908.json) assessments rate every focused item level 2. A rates all balanced items 2; B rates q06 at a sensitive 2/3 boundary. The richer requested comparison is not independently established as a sound, sufficiently challenging item under both readings. No item receives favorable credit merely for shorter text or a higher model label.

The [A teaching](evidence/focused-application-teaching-assessment-a-20260908.json) and [B teaching](evidence/focused-application-teaching-assessment-b-20260908.json) records preserve meaningful disagreements. B accepts q01's count wording as shorthand because the gain is separately stated, and q10's shift wording within its contextual explanation; A withholds whole-main support for those formulations. B accepts q04's ordinary terrain comparison while A requires more explicit trail geometry. A accepts q03 as qualified corrective initial guidance; B withholds complete cause/treatment support. Neither proves the advice harmful. Both preserve q08's unresolved alternative rather than claiming it is definitely true or definitely false.

The implementation passed **895 backend tests**, Ruff, diff checks and independent prompt/protocol review before dispatch. No runtime source changed after freezing. The selected three-pair run does not estimate general accuracy, ordinary multi-attempt bank yield or learning outcomes. It rules out treating this particular prompt change as a demonstrated fix and leaves the broader correctness goal open.
