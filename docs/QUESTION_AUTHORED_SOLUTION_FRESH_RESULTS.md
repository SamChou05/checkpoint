# Fresh authored-solution results — September 8, 2026

## Decision

The opt-in path preserved the explanations it returned, but this trial **did not qualify it for default use**. Six raw questions were authored across three non-math goals. Four failed length checks before independent solving; two English questions passed the complete runtime path. Both independent assessors rated those two below the requested difficulty and found weak distractors. One returned explanation also misleadingly calls the initial recipe instruction's unspecified amount of butter a generic reference. The two raw contour questions contained defective authored answers or reasoning. Those questions were excluded for length, not because the semantic checks detected their defects.

No model, deployment, claim policy or generation default changed. The [authored-solution contract](QUESTION_AUTHORED_SOLUTION_CONTRACT.md) remains server opt-in. Its enforceable improvement is that the final reviewer audits frozen teaching and cannot replace it with unchecked text. A model can still confidently approve false content.

## Frozen trial and execution

The [prospective protocol](QUESTION_AUTHORED_SOLUTION_FRESH_PROTOCOL.md) and [fixture](evidence/authored-solution-fresh-fixture-20260908.json) were committed before dispatch. Each of three goals requested two questions at minimum difficulty 3. Kimi K2.5 authored; Sonnet 4.6 performed complete-choice solving and the immutable teaching audit. Both used disabled thinking, 6,000 output tokens and temperature 0.2. The trial allowed one generation attempt and three calls per goal, nine overall, using the existing isolated observer and actual generation functions.

The [capture](evidence/authored-solution-fresh-capture-20260908.json) records **five calls**, all completed with `end_turn`, known usage and confirmed cleanup. No repair, retry or replacement occurred. Usage was **10,314 input and 3,084 output tokens**; no response approached the 6,000-token ceiling. Recorded intervals sum to 69.50 seconds inside the SDK and 73.11 seconds across observed workers; these are not whole-trial wall time or deployed latency measurements.

An [independent operational audit](evidence/authored-solution-fresh-operational-audit-20260908.json) rebuilt the frozen plan, checked all 33 source files against committed source `a6b6b28`, and replayed every dynamic request and runtime decision without a provider call. The two returned explanations were byte-identical at author output, sanitization, audit input and delivery; both carried revision 3 and an empty choice-feedback map.

## Formatting and yield

| Raw candidate | Stem characters | Main characters | Runtime result |
| --- | ---: | ---: | --- |
| Plant 0 | Within 320 | 548 | Main exceeds 420; no solver call |
| Plant 1 | 358 | 679 | Stem exceeds 320; also a 152-character choice and oversized main |
| English 0 | Within 320 | 343 | Returned after solver and teaching audit |
| English 1 | Within 320 | 396 | Returned after solver and teaching audit |
| Contour 0 | Within 320 | 644 | Main exceeds 420; no solver call |
| Contour 1 | Within 320 | 1,264 | Main exceeds 420; no solver call |

All six main explanations exceeded the author's existing 320-character instruction. The runtime's main limit is 420, so that instruction violation alone did not exclude the two English questions. Increasing the **output-token allowance** would not fix these observed length violations: none was caused by token truncation. No text was shortened or discarded to make an item pass.

The observed 2/6 return rate is for this selected, one-attempt, two-item-per-goal experiment. It is not a production yield estimate: the ordinary worker requests five items and permits additional attempts within its existing call budget. Those retries were not exercised here.

## Independent content assessment

Two assessors first received the exact six stems, 24 choices, goals and supplied sources without author keys, explanations, difficulty labels or pipeline verdicts. Each saved its answer/difficulty assessment before opening the separate teaching packet. The [first assessment](evidence/authored-solution-fresh-stem-assessment-a-20260908.json) and [second assessment](evidence/authored-solution-fresh-stem-assessment-b-20260908.json) agree on difficulty levels **3, 2, 2, 2, 2, 2** in the table's order; the café question has an explicitly recorded 2/3 boundary sensitivity. Neither assessor established a complete set of three plausible distractors for every item.

The plant decision with mixed root observations has meaningful evidence to interpret, but the division distractor is weak and the exact trimming action extends beyond the supplied summary. The second plant question mostly applies the familiar node requirement. Both English keys are sound introductory applications, while some alternatives are implausible or overbroad. Neither contour item meets the requested challenge as a sound question: the first has an ordinary four-versus-five intermediate-contour inconsistency and ambiguous slope scope; the second's defensible physical-identity answer follows directly from the statement that both maps show the same route.

The [native arithmetic checks](evidence/authored-solution-fresh-native-checks-20260908.json) independently confirm four strictly intermediate elevations between 400 and 500 at a 20 m interval. A separately labeled counterexample shows that the same 800–1,130 m elevation range can cross six index contours on a 10 m-contour map and three on a 25 m-contour map under every-fifth indexing. This refutes the author's claimed unavoidable contradiction; it does not supply omitted premises to the original question.

Both the [first teaching assessment](evidence/authored-solution-fresh-teaching-assessment-a-20260908.json) and [second teaching assessment](evidence/authored-solution-fresh-teaching-assessment-b-20260908.json), performed after their first answers were frozen and without pipeline verdicts, found four authored keys consistent with their first-pass answers and two defective contour keys. They agree that the café explanation is sound and that the first plant explanation has a defensible core plus unestablished causal claims. The second plant explanation's core biology is sound; the second assessor additionally records a source-coverage gap for the pothos medium/hormone advice, which the first accepts under its stated ordinary-care scope. Neither interpretation establishes every claim directly from the supplied summaries. Both contour explanations contain material errors.

The returned butter explanation correctly explains later reference to the already introduced amount, but wrongly describes the initial instruction as referring to butter in general. An article-free mass noun in a recipe can introduce an unspecified quantity for that task; it does not necessarily express a generic reference. The final auditor nevertheless marked the entire main supported and reported no issue. This is a concrete remaining semantic failure in the new path, independent of the length and difficulty failures.

## Evidence limits

All six raw candidates, rejected content, exact model outputs and assessment disagreements remain in the evidence. The sources are explicitly labeled assistant paraphrases of primary pages, not automatically retrieved full-page captures. Source access and immutable text do not establish entailment. This construction trial is not a matched comparison with the prior reviewer-written mode, a general accuracy estimate, a learning-outcome study or a full-bank release test.

The implementation and evaluator passed **889 backend tests**, Ruff and diff checks before the live run. No runtime source changed after the frozen trial. The [evidence manifest](evidence/authored-solution-fresh-summary-20260908.json) records exact file hashes, denominators and joins. Formatting, semantic correctness, distractor quality and useful difficulty remain separate requirements; this trial fails the prospective six-item favorable criterion.
