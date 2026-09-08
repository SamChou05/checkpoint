# Stem-length comparison: interrupted live run

Run date: September 8, 2026 UTC. Status: execution stopped under the frozen operational-failure rule; independent assessment of all six observable HTML questions is complete. Both HTML arms returned correct keys and sound teaching feedback, but neither met the full difficulty and distractor-quality threshold. This is not a completed two-goal comparison or a production qualification.

After AWS renewal, the [frozen protocol](QUESTION_STEM_LENGTH_EXPERIMENT.md) ran at source revision `22980c1dbfb8875512f8acdd27664c9993d4d064` with canonical plan hash `3462043fb316b763017feb0421a0bac6354ef2b4413b5a3ca1abc3ed48ea0f72`. The configuration remained Opus 4.6, adaptive thinking at high effort, 16,000 maximum output tokens, one SDK attempt, and a 100-second read timeout. No repair, retry, replacement case, or deployment occurred.

Both HTML author/solver/reviewer jobs completed. The seventh call, the first chess author request with the 1200-character allowance, raised `ReadTimeoutError` after 100.003 seconds. No completed Converse response, stop reason, question text, or usage was returned or captured for that call. Its remote completion and billed usage remain unknown. Execution stopped, leaving the final chess job unattempted.

| Goal and allowance | Requested slots | Observable raw candidates | Execution |
| --- | ---: | ---: | --- |
| HTML, 320 characters | 3 | 3 | Author, solver and reviewer completed |
| HTML, 1200 characters | 3 | 3 | Author, solver and reviewer completed |
| Chess, 1200 characters | 3 | 0 | Author timed out; no response captured |
| Chess, 320 characters | 3 | 0 | Unattempted under the stop rule |

The denominator is twelve requested slots, six observable raw candidates, three slots unavailable after the timeout, and three unattempted slots. Nine unique blinded HTML text/order variants represent those six candidates; variants are not additional questions. Pipeline completion and inventory retention do not establish correctness or difficulty.

The six received responses reported 12,615 input tokens and 13,690 output tokens in total. These are known subtotals, not whole-run usage or cost. The separate [operational audit](evidence/stem-length-operational-audit-20260908.json) verifies the source-bound plan, all seven exact request shapes and contexts, and the call limits without exposing generated keys or judgments.

The immutable [capture](evidence/stem-length-capture-20260908.json) has SHA-256 `fe7e0352a9af481595eb7de203d9f174d0e1caa64dba0409e4aae9cb037439c9`. The [blinded candidate file](evidence/stem-length-blinded-20260908.json) has SHA-256 `4f3bdbaad9e1826c4b25a9b6403457b08ac147478a22af8e54792d67011483a9`. The [independent blind assessment](evidence/stem-length-html-blind-assessment-20260908.json) and [separate root notes](evidence/stem-length-html-root-blind-20260908.json) were frozen before keys and explanations were exposed. The subsequent [feedback assessment](evidence/stem-length-html-feedback-assessment-20260908.json) binds its findings to those inputs; the original capture remains unchanged.

All six raw candidates, their admitted and returned variants, and their production-sanitizer variants were joined by exact prompt and choice text. All six authored keys agree with the independently selected unique answers. [Native browser observations](evidence/stem-length-html-blind-observations-20260908.json), produced by the [preserved runner](evidence/stem-length-html-blind-observe-20260908.js), corroborate three literal displayed HTML fragments and three explicitly labeled realizations of complete prose ancestry. An [independent binding audit and replay](evidence/stem-length-html-binding-audit-20260908.json) verified those joins and reproduced all six observation records. This concerns the specified DOMs, not universal browser conformance; no displayed markup was repaired. All six returned main explanations and all 24 returned choice explanations were supported in their question context.

| HTML assessment over three candidates per arm | 320-character arm | 1200-character arm |
| --- | ---: | ---: |
| Unique key agrees with independent answer | 3/3 | 3/3 |
| Returned main and all four choice explanations supported | 3/3 | 3/3 |
| Independent difficulty at least 3 | 2/3 | 2/3 |
| Three plausible, meaningfully distinct distractors | 2/3 | 2/3 |
| All preceding content and quality criteria together | 1/3 | 2/3 |

These quality counts use the frozen independent assessor's ratings. Both own-attribute-removal questions were rated level 2. The nested-fieldset and paired validation-API questions were rated level 3. Root independently rated the two API questions level 2; holding the assessor's distractor judgments fixed, that makes the combined count 0/3 and 1/3. This is reported judgment sensitivity, not a calibrated learner-difficulty measurement. The distractor concerns are overlapping global-exemption alternatives in the short nested-fieldset question and overlapping enabling alternatives plus a weak layout-timing explanation in the expanded arm's attribute-removal question. They do not create additional correct answers.

The raw 320-arm email explanation incorrectly claimed a “missing required value,” although the literal value was the nonempty string `bad`. The returned explanation removed that false claim. Raw main explanations were therefore fully supported in 2/3 baseline items and 3/3 expanded items. Separately, the expanded email solver claimed that `not-an-email` would fail both email-type and required constraints; the nonempty value does not fail the missing-value requirement. That internal error was absent from the returned main and choice feedback and is not counted as a returned teaching error.

Only one stem exceeded 320 characters: the 327-character nested-fieldset markup. Its tree supplies useful premises, but deleting only its 31-character introduction preserves the complete DOM and question at 296 characters. This run therefore shows actual over-cap use without demonstrating that the larger allowance was necessary for completeness or caused better content. All three expanded-arm raw main explanations also exceeded the unchanged 320-character author instruction, at 419, 353 and 401 characters. The separate backend 420-character sanitizer allowance retained them; the experiment did not intentionally enlarge the explanation instruction.

The failed call provides no evidence about chess-question correctness or the effect of the longer allowance. A timeout can have several causes; this record does not identify one. Neither HTML arm supplied three questions meeting the combined content and quality threshold, and the chess comparison is unavailable. These small, correlated batches do not satisfy the predeclared two-goal feasibility threshold, establish a causal length benefit, or justify changing the production length cap. No deployment or model promotion followed.
