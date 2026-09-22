# Programming result-equivalence comparison

Both arms passed all eight frozen controls. The added programming paragraph produced no observed accuracy improvement, so the runtime solver prompt remains unchanged. The earlier false veto of `0` versus `False` remains a documented intermittent model error; this one comparison does not estimate its frequency or establish deterministic semantic judgments.

| Arm | Correct eligibility | Correct choice judgments | Correct pair judgments | Good retained | Defective excluded |
| --- | --- | --- | --- | --- | --- |
| Baseline | 8/8 | 32/32 | 48/48 | 5/5 | 3/3 |
| Added paragraph | 8/8 | 32/32 | 48/48 | 5/5 | 3/3 |

Exactly four planned calls completed with native-valid, locally valid, end-turn output. In fixed order baseline batch 0, candidate batch 0, candidate batch 1, baseline batch 1, elapsed seconds were 34.317001, 37.601212, 24.121291 and 25.210745. All were within the 100-second criterion. Reported usage totals 13,446 input and 12,620 output tokens; no call lacked usage. There were no retries, substitutions, missing items or additional provider calls.

Root and an independent agent replayed the exact four requests, frozen source pins, native adaptation, local gates and assessments. Both read all 160 visible choice/pair reasons. Decisive support for every judgment is sound in context. Some Boolean descriptions omit general fallback cases, and one candidate reason says “short-circuits past” a falsy operand when it means continuing to the second operand. These qualifications are preserved in the reviews; the reasons are private diagnostic output, not learner explanations. Native internal reasoning and signatures were not captured.

The controls distinguish actual typed Python results from equality or truthiness; they also include genuine numeric duplicates (`0`/`0x0`, `2`/“two”, `1/2`/`0.5`) and a task explicitly asking for decimal notation. The paragraph did not suppress those duplicate vetoes in this sample. This is a small comparison on known matched controls, not a fresh-domain, worker-yield, repeated-run or deployment qualification. Neither arm is promoted as universally reliable.

Frozen plan SHA256: `643385c0b5b1091b763bb6fc74b78487a2396802f0aa4bbc1d539729a53045d4`.

Capture SHA256: `97346a80f751e14afd53d1cf0f6c6f5296e5f85f6be62f7e663ab0e1070d1337`.

[Root review](root-result-review.json), [independent review](independent-result-review.md), and [independent machine-readable replay](independent-result-review.json) retain findings separately from the unchanged capture. Its `qualified: false` and pending-review markers are dispatch-time state; this report records the completed external reviews without rewriting frozen observations.
