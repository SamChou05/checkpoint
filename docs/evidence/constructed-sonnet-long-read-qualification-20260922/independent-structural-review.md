# Independent structural and deadline review

**Both exact replays pass; the trial fails its original yield and numerical compiled quota.** The worker returns **13/15** requested items, against fourteen required. It returns six compiled items overall but only three in the numerical job, against four required. All 81 pins, including the 44 inherited Sonnet-baseline pins, match. The trial source remains clean at `77f794efa8cc24f94123cda61532ae7fe30d3e38`; newer source changes were not used.

| Job | Requested / returned | Calls | Worker seconds | Compiled / prose returned |
|---|---:|---:|---:|---:|
| Quantitative | 5 / 4 | 5 | 234.468424 | 3 / 1 |
| Python | 5 / 5 | 3 | 92.549306 | 0 / 5 |
| Mixed | 5 / 4 | 5 | 224.776729 | 3 / 1 |

All three jobs meet the four-item floor and finish within their 240-second deadlines. The six-total and two-mixed compiled minima are met. The fourteen-total and four-numerical compiled minima fail independently of learner-content review. English assignment and all semantic judgments remain with the separate content reviewers; this report gives no content approval.

## Exact replay and time budgets

A first socket-blocked replay through the actual `run_jobs` reproduces all **13 requests**, reservations, pass records, return values, sources, provenance and statuses. A second replay retains those same comparisons and additionally reproduces every recorded read timeout, three-second connect timeout, single SDK attempt, and before/after remaining-millisecond bucket. Both runs make **35 real checks of all 81 pins**. No comparison was relaxed to hide a mismatch.

The second run delegates to the unchanged client factory and budget code. A reconstructed logical clock places each factory inside the captured remaining-time interval, then advances to the recorded post-call bucket. For clamped reads, the factory time follows from the actual formula; for capped reads, a consistent point in the cap interval suffices. Original factory timestamps and elapsed latency are not inferred as exact observations. These are faithful request/control-flow replays, not new timing measurements. They perform no credential acquisition or provider access.

The first author completes in **161.842709 seconds** with a 200-second read ceiling. That leaves roughly 78 seconds for the numerical job's remaining work. Its later reads shrink to 71.993, 62.776, 38.278 and **6.396 seconds**. The final one-item prose solver raises `ReadTimeoutError` after **6.786299 seconds**. It provides no response, native judgment or known token usage. The existing four approved items survive that failed top-up; no replacement call is made.

The mixed job's reads similarly shrink to 148.176, 109.851, 45.427 and 29.762 seconds after its first author. Every successful call finishes below its actual read allowance. The timeout is explicitly failed, including its measured overhead above the socket limit. Both partial jobs end after five calls with only one reservation left, below the existing three-call admission rule for another mixed author pass. All 13 reservations equal 13 dispatches, below six per job and eighteen overall. There is no global stop or harness rescue.

A completed 161.843-second call demonstrates use of the longer ceiling in this run. It does not establish why the earlier 100-second call failed, that its answer would have matched, or any provider grammar-cache state or causal effect.

## Received structure and discarded attempts

All **12 received responses** end with `end_turn`, validate against their actual native schemas, adapt successfully and pass the relevant strict local parser. The thirteenth dispatch is the solver timeout, not a malformed native response. Seven assessed solver items produce **28 choice judgments and 42 pair judgments**; the eighth submitted solver item has no returned judgments. Four immutable audits cover **14 identities and 84 Boolean flags**: thirteen positive dispositions and one negative, with one true `explanation` flag and an `uncertain` main-support declaration. Flag meaning and private reason truth are not adjudicated here.

Five successful author calls produce **20 raw rows**: twelve prose and eight task-only quantitative rows. They are attempt diagnostics, not a replacement for the fifteen requested slots. All eight typed tasks construct successfully; no graph, missing-answer, equivalent-value, insufficient-pool or other compiler error occurs. Every full constructed specification and all five compiler fields reproduce from the original flat task.

Seven constructed items reach final audit and six are returned with policy 8 and all five exact fields. One is vetoed as an uncertain main. The flag-only response supplies no rationale; this review does not invent one. The eighth compiled item is dropped as surplus before review:

- Numerical top-up call 3 requests **one** item but returns **two** native-valid rows.
- The first row is prose and the second is a valid compiled task.
- The unchanged sanitizer caps the batch at one in source order, retaining the prose and marking the compiled row surplus. That prose then reaches the timed-out solver.

The author array schema does not encode an exact requested row count. Thus native validity coexists with this count instruction violation; the deterministic local cap prevents excess release. No post-hoc reorder or substitution was used to improve the observed result, and no claim is made that choosing the other item would have completed its still-required audit in time.

The remaining four discarded prose drafts fail the actual immutable-content freeze before solving because their mains reference shuffled answer labels: raw sources `quantitative/0/1`, `mixed/0/3`, `mixed/0/4` and `mixed/1/2`. These are deterministic guard rejections, not model vetoes. The seven raw losses are therefore four label-reference failures, one compiled surplus, one uncertain-main audit veto and one prose solver timeout. No successfully assessed solver item is vetoed.

All seven returned prose questions retain their exact authored main, empty choice-feedback map and policy 7. Private compiled provenance bypasses only the model solver; every compiler survivor still receives final audit and release recompilation. The replay recreates actual retained verifier-object relationships and current-pass source mappings rather than inferring object identity from serialized content.

## Configuration, usage and limits

The frozen candidate differs from its Sonnet baseline only in the approved source timeout upper bound/comment and the selected read ceiling 100→200. All other runtime modules, helper/dependency bytes, prompts, schemas, model/reasoning settings, jobs, criteria and call/deadline limits remain unchanged. Every stage uses Sonnet 4.6 adaptive/high, 16,000 shared tokens and no sampling fields.

The twelve available responses report **48,562 input tokens and 49,801 output tokens**. The timed-out solver's usage is unknown, so these are not complete billed totals. Provider-call time sums to **550.636280 seconds**, including the timeout; worker time sums to **551.794459 seconds** across independent jobs. Thirteen reasoning blocks were omitted. No private reasoning text or signature was inspected or inferred.

Replay uses Python 3.12.11, actual serialized JSON Schema validation, native adapters, local solver/auditor parsers and mathematical recompilation. Observed native cardinalities only are covered: author targets 5/1/3, solver counts 1/5 and audit counts 4/5/3/2. The exact-count author instruction still relied on local capping. These structural checks do not prove open-domain truth, appropriate difficulty, novelty, plausible distractors or rollout readiness.

Bindings:

- Plan: `37ebfc0e48ab8c80f31f34fbd1732ce6e9992d2685bbab046e89e521fe24c5c1`.
- Capture: `c68f424b5a71d981083283e3b5d1ef667aa61ad6ebfb6ba8d08996e2ef9acfcb`.
- Detailed counts, both replay methods and exact timeout reconstruction: [independent-structural-review.json](independent-structural-review.json).

Only these two derived files were written. No frozen source, prompt, plan, capture, gold, previous failure or production setting was changed. No provider, account or deployment action occurred.
