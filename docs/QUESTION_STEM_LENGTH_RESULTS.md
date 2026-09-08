# Stem-length comparison: interrupted live run

Run date: September 8, 2026 UTC. Status: execution stopped under the frozen operational-failure rule; independent content assessment is pending in this revision. This is not a completed two-goal comparison or a production qualification.

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

The immutable [capture](evidence/stem-length-capture-20260908.json) has SHA-256 `fe7e0352a9af481595eb7de203d9f174d0e1caa64dba0409e4aae9cb037439c9`. The [blinded candidate file](evidence/stem-length-blinded-20260908.json) has SHA-256 `4f3bdbaad9e1826c4b25a9b6403457b08ac147478a22af8e54792d67011483a9`. Independent key-, explanation-, and verdict-blind assessment precedes feedback assessment; any later conclusions must remain separate from this original capture.

The failed call provides no evidence about chess-question correctness or the effect of the longer allowance. A timeout can have several causes; this record does not identify one. The incomplete comparison cannot satisfy the predeclared two-goal feasibility threshold or justify changing the production length cap.
