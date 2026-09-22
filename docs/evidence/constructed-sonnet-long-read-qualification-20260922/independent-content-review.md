# Independent long-read worker content review

**The frozen trial fails:** it returns **13/15**, below the required 14, and the quantitative job returns **three compiled items**, below the required four. Every job stays within 240 seconds and its six-call budget. None of the content sensitivities below can change those operational failures.

I locked [the blind review](independent-blind-review.json) at SHA-256 `02513e7f85e7191f8fb3f544b241f662f21c1a782c07d304e0864eb7c3f5ed76` before opening keys or teaching. After unblind authorization, I independently read the raw output and locked [the full content review](independent-content-review.json) at `50a742a0dc3c1f602007bff4adeeb327e124396b7aa04931f6b262e655c5323b`, before receiving the parent's content count. The parent subsequently reported agreement with the three sensitivity counts; that did not change my locked judgments.

The [capture](capture.json) hash is `c68f424b5a71d981083283e3b5d1ef667aa61ad6ebfb6ba8d08996e2ef9acfcb`; the [plan](plan.json) hash is `37ebfc0e48ab8c80f31f34fbd1732ce6e9992d2685bbab046e89e521fe24c5c1`. All **81 pins** match. Replay uses source `77f794efa8cc24f94123cda61532ae7fe30d3e38`, including its original constructor. The separate newer fraction-priority constructor was not used or assessed.

## Returned learner content

All **13 explicit keys match the certain answers in the blind lock**. The blind review found 12 clearly unique items and one English uncertainty; it recorded **52 choice judgments and 78 distinct pair judgments**. Six compiled payloads preserve all five fields under fresh compilation, and seven prose payloads preserve their raw authored main and empty choice feedback. All 13 returned objects match their saved verification records. This establishes saved associations and bytes, not reconstruction of live Python object identity beyond the frozen harness's instrumentation.

| Item group | Keys independently confirmed | Teaching |
|---|---|---|
| Quantitative | `19/12`, `14/25`, minimum `8`, maximum `11` | Fraction equalities and explicit integer bounds are correct. Ignoring the `+3` term in the last task does produce the distractor `12`; the main's mechanism is mathematically defensible, without asserting an observed learner thought process. |
| Python | `40`, `"hello"`, `"big"`, `["c", "d"]`, `[]` | Every concrete index, selected operand, conditional branch, slice and skipped evaluation is correct. Two opening general rules have the sensitivity below. |
| Mixed | `20`, `10`, `22`, the sentence beginning “Each of the volunteers” | Every arithmetic step is exact. The agreement explanation retains the pre-key collective-noun uncertainty. |

All **24 compiler-generated choice explanations** are true. This includes the scalar minimum task: at `x=6` and `x=7`, `3x >= 22` is false; at `x=8` and `x=9` it is true, but only `8` is the minimum. The other five compiled questions use exact rational comparisons with the independently calculated value.

All returned fields meet the actual bounds. Maximum lengths are **169** for a prompt, **58** for a choice, **311** for a main, and **94** for optional choice feedback. Every prose main meets both the 320-character author instruction and the distinct 420-character runtime limit. Returned teaching has no detected display-position reference. Independently assessed and reviewed difficulty levels are all within the requested 2–3 range; their exact labels need not coincide. Difficulty and plausibility assessments are qualitative, not learner calibration.

### Preserved interpretation boundaries

The conservative full-content count is **10/13**: two general-rule sensitivities and the one locked grammar uncertainty prevent unconditional credit. A contextual reading of the two operator explanations gives **12/13**, preserving the grammar uncertainty. Also adopting the ordinary singular-collective classroom rule gives **13/13**. These are explicit sensitivity readings, not relabeled frozen gold or a passing worker result.

- Python item 1 starts, “Python's or operator returns the first truthy operand.” The supplied `0 or "hello" or 99` does return `"hello"` and skip `99`. As a complete general rule, however, it omits the all-false case: `0 or 0` returns falsey `0`.
- Python item 4 starts, “Python's and operator returns the first falsy operand without evaluating the rest.” For `[] and 1/0`, that is exactly what happens, with no division error. As a complete general rule, it omits the all-truthy case: `1 and 2` returns truthy `2`.
- The English item certainly permits “Each of the volunteers receives…”. Its committee alternative is disfavored under ordinary American singular-unit agreement, but categorical exclusion remains uncertain under recognized notional plural agreement. The main and solver do not resolve that pre-key uncertainty merely by asserting that `committee` requires `has`. [Purdue's agreement guidance](https://owl.purdue.edu/owl/general_writing/grammar/subject_verb_agreement.html) supports the conventional classroom answer; [Chicago's collective-noun discussion](https://www.chicagomanualofstyle.org/qanda/data/faq/topics/Plurals.html?page=3) acknowledges some member-focused plural usage in American English. Neither source specifically adjudicates this exact committee sentence, so the recorded boundary remains uncertainty rather than a claim that the alternative is definitely correct.

The two Python worked evaluations are sound. This is consistent with the earlier distinction between an incomplete generic rule and a concrete false execution narrative; no such execution-order mistake appears in these returned mains.

## Private stages and loss of yield

I read all **70 visible solver reasons**. Of 28 choice labels, 27 agree with certain blind judgments and one categorically rejects the committee alternative whose status was locked as uncertain. All **42 pair labels** agree with the distinct meanings. One definite false fragment says `["b", "c"]` and `["b", "c", "d"]` have different starting elements; both start with `"b"`. Their lengths differ, so the distinct verdict remains correct. That false fragment never reaches learner teaching. The remaining generic-rule and collective-agreement reason sensitivities are itemized in the JSON.

All three successful solver batches also passed the actual local `validate_batch` with their captured exact input bindings. The maximum choice-reason length is **244**, within its **600** limit; the maximum pair reason is **192**, within its separate **240** limit. A 244-character choice reason is not a pair-bound failure. One further solver call timed out and produced no reason or judgment; it receives no semantic credit.

The immutable auditor returned **14 typed records**, accepting the 13 released rows and withholding one compiled scalar item with `explanationSupport=uncertain` and its explanation flag set. That item's math is true: on integers 1–20, `2x - 3 >= 11` has minimum `7`; at `7`, `11 >= 11` is true, and all smaller allowed values fail. Its four feedback comparisons are also true.

The JSON calls this an unnecessary withholding in the mathematical-support sense. **The flag-only response contains no rationale:** it cannot establish whether the concern was mathematical truth or the adequacy of the terse scalar teaching. This audit does not infer the model's private reason or recommend bypassing the final gate.

Four authored prose mains were withheld by the existing choice-position-reference guard. They were not rewritten or salvaged. The quantitative top-up requested one item but the author returned two: a prose fraction subtraction first, then a valid constructed scalar task. The unchanged first-N sanitizer retained the prose and discarded the second row as surplus. Its solver received only a **6.396-second** read allowance, timed out after **6.786 seconds**, and the runtime returned the four earlier verified items. The discarded compiled row was not reordered into the accepted batch to rescue the trial.

| Job | Returns / requested | Compiled returns | Calls | Elapsed |
|---|---:|---:|---:|---:|
| Quantitative | 4 / 5 | 3 | 5 | 234.468 s |
| Python | 5 / 5 | 0 | 3 | 92.549 s |
| Mixed | 4 / 5 | 3 | 5 | 224.777 s |
| Total | 13 / 15 | 6 | 13 / maximum 18 | All jobs below 240 s |

The first author completes at **161.843 seconds**, within the new 200-second ceiling. Later socket read allowances shrink with the unchanged worker deadline. Twelve responses have valid native schemas/adapters and normal end-of-turn status; one solver has no response due to timeout. Five author calls requested 19 rows including top-ups and produced 20, with the one surplus row noted above. Reported usage is **48,562 input tokens and 49,801 output tokens**; timeout usage is unavailable and is not zero.

The total compiled quota, per-job return minima, mixed compiled minimum, and mixed English minimum are met. The total return target and quantitative compiled minimum are not. The result does not establish a cold-cache cause, matched model effect, deployed-worker qualification, or inventory approval. This review made no provider calls, acquired no credentials, and changed no source or frozen artifact.
