# Worked-main and typed-audit diagnostic

The two frozen audit calls passed all ten component criteria. Five correct worked explanations were accepted, and all five copies containing a material false explanation step were rejected. Every question retained its correct exact answer key in the audit output.

| Measure | Observed |
| --- | --- |
| Native-valid, locally valid, end-turn calls | 2/2 |
| Correct worked mains accepted | 5/5 |
| False mains rejected as unsupported, with explanation flag | 5/5 |
| Exact task keys | 10/10 |
| Issue flags consistent with independently reviewed gold | 60/60 |
| Elapsed time, sound / false batch | 39.762440 / 34.432756 seconds |
| Reported input / output tokens | 5,754 / 5,340 |

Both calls completed within the frozen 100-second criterion, using Sonnet 4.6 adaptive/high, 16,000 tokens, native `authored_solution_reviewer_v3_n5`, and one SDK attempt. No failed, missing or unattempted items, retries, additional calls, rewritten outputs or learner releases occurred. The sound minimum-boundary item was rated difficulty 3 and the other sound items 2, all meeting the predeclared floor of 2. Both batches returned the same correct keys; all six flags were false for the sound items, and only `explanation` was true for the false mains.

Root independently checked exact rational arithmetic and the complete bounded integer domain before dispatch. The controls changed only one explanation span each: a subtraction result, a product denominator, a common-denominator conversion, the direction of a minimum-boundary claim, or a reciprocal. Correct answer agreement alone could not justify their false teaching. The observed support labels and flags match every controlled defect, but this contract returns no rationale, so no unreturned model reasoning is inferred.

This establishes live AWS acceptance of the new count-five native contract and these ten audit outcomes. It does not isolate the effect of worked rendering from the typed flags: both changed since the earlier failed immutable-main trial. The five familiar tasks and deliberately clear corruptions do not establish broad-topic reliability, a general error rate, full-worker yield or deployment readiness. Corrupted controls were never given compiled provenance or released.

Frozen plan SHA256: `dafc994df9c628e2c4e5cd5c4b6c5fe1468f8839674f66924e2aa8da5b4fd544`.

Capture SHA256: `460c4468a9b9af524fc496938a8a294151ae956f94929a6b8e00eb85cc0ead44`.

[Root replay and review](root-result-review.json) and [independent review](independent-result-review.md) record conclusions separately from the unchanged capture. Dispatch-time `qualified: false` and pending-review markers remain untouched; these reports record external review completion rather than rewriting observations. The actual request builder used a clearly labeled synthetic solver fixture only to reach the immutable-audit callback; no model solver or full-worker run is claimed.
