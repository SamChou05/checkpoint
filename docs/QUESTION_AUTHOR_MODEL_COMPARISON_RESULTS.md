# Author-model comparison results — September 8, 2026

## Decision

Replacing Kimi K2.5 with Opus 4.6 **did not qualify the current authored-solution pipeline for default use**. Opus produced more independently supported keys in these three selected goal pairs, but also more explanations over the runtime length limit. Both authors still produced missing-premise or teaching problems, and most questions were independently below the requested difficulty. No default, model, deployment or stored bank changed.

The comparison isolates authorship under the [prospective protocol](QUESTION_AUTHOR_MODEL_COMPARISON_PROTOCOL.md). It does not establish that Opus is generally better, that retries cannot help, or that an all-six first-pass criterion is necessary for every viable product design. The strict criterion was fixed for this experiment; the partial observations below remain useful even though neither arm met it.

## Comparable execution

Each author received identical goal/source payloads and prompts, requesting two questions for each of houseplant propagation, English articles and contour interpretation. Only the author model ID differed within each pair. Both used disabled thinking, 6,000 output tokens and temperature 0.2; Sonnet 4.6 performed complete-choice solving and immutable teaching review for both arms. Each operation allowed one generation attempt and three calls within 240 seconds, with the worker's 75-second read timeout. The trial used the actual opt-in generation path and isolated observer, without bank writes.

The [terminal capture](evidence/author-model-comparison-capture-20260908.json) records six completed operations, 12 raw candidates and **12 calls out of an 18-call ceiling**. All responses ended normally; no JSON repair, retry, truncation, timeout or replacement occurred. Output use ranged from **93 to 807 tokens per call**, well below 6,000. Total usage was **25,460 input and 6,331 output tokens**. Recorded SDK intervals sum to 101.33 seconds and worker intervals to 108.92 seconds; these are not independently measured whole-trial wall time or deployed latency.

The [independent operational audit](evidence/author-model-comparison-operational-audit-20260908.json) checked all 33 source files against committed revision `5e677bb00cf9b5c7fd37ac43c343fc71f0e05430`, rebuilt the frozen plan, and replayed exact dynamic requests and results without calling a provider. All six returned main explanations were byte-identical through author output, sanitization, audit and return. Each returned item carried policy revision 3 and empty choice feedback. That provenance establishes which checks ran, not factual truth.

## Separate quality and admission results

Counts refer to all six raw candidates per arm, including runtime exclusions.

| Observation | Kimi K2.5 | Opus 4.6 |
| --- | ---: | ---: |
| Raw candidates | 6 | 6 |
| Unique authored key supported by both independent assessments | 2 | 5 |
| Complete supported teaching, assessor A / B | 2 / 2 | 4 / 3 |
| Supported key, difficulty at least 3 and three plausible distractors, both assessors | 0 | 1 |
| Explanation exceeds runtime limit of 420 characters | 2 | 4 |
| Returned by the runtime | 4 | 2 |
| Meets every prospective content, length and return requirement | 0 | 0 |

All 12 stems and 48 choices fit their respective 320/140-character limits. All 12 explanations exceeded the author's 320-character instruction; six still fit the separate 420-character runtime allowance. This is a content-length compliance problem, not exhaustion of the output-token budget. Length exclusions received no credit for detecting semantic defects.

| Masked ID | Author | Main characters | Runtime | Independent content finding |
| --- | --- | ---: | --- | --- |
| q01 | Kimi | 552 | Length exclusion | Crossings do not establish the claimed net elevation change or terrain comparison. |
| q02 | Kimi | 321 | Returned | Supported hotel reference and teaching; difficulty 2, weak distractors. |
| q03 | Kimi | 852 | Length exclusion | Supplementary map lines are incorrectly treated as extra physical ascent; key unsupported. |
| q04 | Kimi | 374 | Returned | Supported new-plant propagation distinction; difficulty 2, root-only distractor scope caveat. |
| q05 | Kimi | 378 | Returned | Recipe quantity is misleadingly explained as generic class reference. |
| q06 | Opus | 444 | Length exclusion | Supported key and difficulty 3; worked counting method needs qualification. |
| q07 | Opus | 417 | Returned | Supported species/tissue pairing and teaching; difficulty 2, weak distractors. |
| q08 | Kimi | 405 | Returned | A's potting decision is supported; damaged-root treatment for B is underqualified. |
| q09 | Opus | 398 | Returned | Supported potting decision, difficulty 2; explanation overstates indicators as requirements. |
| q10 | Opus | 522 | Length exclusion | Exact equal 200-foot gains are not determined by five contour crossings. |
| q11 | Opus | 433 | Length exclusion | Supported article contrast in context; difficulty 2. |
| q12 | Opus | 481 | Length exclusion | Supported laptop/screen reference and teaching; difficulty 2, with boundary sensitivity. |

The returned q05 is a concrete remaining semantic failure: the full explanation explicitly identifies an unspecified amount of butter in a recipe instruction as a generic class reference. The auditor nevertheless reported it supported with no issue. In q08, the concern is an unsupported management inference for damaged roots, not proof that recovery in water is always wrong. Opus's returned q09 has a sound case decision; treating positive readiness indicators as universally necessary is a separate source-scope overstatement, not proof that this potting recommendation is wrong.

The [native q10 check](evidence/author-model-comparison-native-checks-20260908.json) constructs a permitted monotone route: north from 100 to 290 feet over 1 cm, then east from 290 to 485 feet over 4 cm. Each segment crosses five 40-foot contour levels, while gaining 190 and 195 feet respectively. Executed arithmetic confirms the crossings and gains. This refutes the necessity of the exact/equal 200-foot claim without reconstructing actual missing endpoints or disputing the defensible average-steepness comparison.

## Assessment integrity and limits

Two assistant assessors first received the shuffled [stems and choices](evidence/author-model-comparison-stems-20260908.json), goals and supplied source summaries without author identity, keys, explanations, model difficulty or runtime verdicts. Each froze its first assessment before receiving the [teaching packet](evidence/author-model-comparison-teaching-20260908.json). Both teaching assessments were saved before the root opened the separate arm mapping. Wording could reveal stylistic clues, and these goal domains had been examined previously; this was not an unseen-domain holdout or a human learner study.

The [first](evidence/author-model-comparison-stem-assessment-a-20260908.json) and [second](evidence/author-model-comparison-stem-assessment-b-20260908.json) stem assessments agree on seven unqualified keys. They differ about the closest conditional reading for q01 and intended depth of q08. Neither disagreement establishes a valid unique answer. Only q06 has a supported key, difficulty 3 and three plausible distractors under both assessments; its oversized main prevented runtime solving or review.

The [first](evidence/author-model-comparison-teaching-assessment-a-20260908.json) and [second](evidence/author-model-comparison-teaching-assessment-b-20260908.json) teaching assessments agree on the material contour/reference failures. Their 4-versus-3 Opus teaching count differs at q09: A accepts the useful application with a wording qualification, while B withholds complete support because the main strengthens the source into a necessary-condition rule. Both qualifications remain recorded. Neither assessor calls q06's correct numerical result false; its endpoints independently establish the gain, while the written count-only justification is underqualified.

The [manifest](evidence/author-model-comparison-summary-20260908.json) records exact hashes and all 12 raw/packet/assessment/return joins. Source documents are selected assistant paraphrases of primary pages, not independently acquired full references. No empirical difficulty calibration, learner benefit, general accuracy rate or production bank yield is established. Ordinary background jobs allow further attempts and use larger batches; this run deliberately measured one unrepaired pass per pair.

The source milestone passed **892 backend tests**, Ruff and diff checks before dispatch. No runtime source changed after freezing. This evidence supports preserving explicit code vetoes and separating key correctness, teaching support, distractor utility and display limits. It does not justify a model switch or another token-budget increase as a completed correctness fix.
