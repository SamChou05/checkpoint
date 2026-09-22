# Solver count-map qualification: failed before model output

The frozen two-call structural qualification failed. AWS rejected the first exact request with `ValidationException` after 0.504 seconds. The runner stopped immediately, leaving the second call unattempted. No model text, choice judgment, pair judgment, reason, or usage record was returned. There were no application retries or replacement calls, and SDK total attempts was one.

| Measure | Frozen denominator | Observed |
| --- | ---: | ---: |
| Provider dispatches | 2 | 1 attempted; 1 unattempted |
| Structurally qualified responses | 2 | 0 |
| Trusted decoded question identities | 10 | 0 |
| Choice judgments | 40 | 0 produced or assessed |
| Pair judgments | 60 | 0 produced or assessed |
| Reason strings | 100 | 0 produced or assessed |

Structural qualification remains **false (0/2)**. Semantic quality was not assessed: absent output is evidence of neither correct nor incorrect reasoning. Token usage and monetary cost are unavailable, not zero. There is no learner output to admit or evaluate for unchanged content. The replay's empty-set binding check is vacuous and does not establish successful binding behavior.

The request preserved the first two historical adaptive solver jobs' model, settings, question text, choice order, exact pair endpoints, gold, and semantic prompt. Only the native output envelope and its identity instruction changed to the actual `SolverSlotContract(5)`. Independent review verified all 30 source/evidence pins, both planned envelope-only deltas, and the exact captured first request. All ten gold cases remain unchanged, with four eligible and six defective cases. They are reused diagnostics, not new held-out examples.

The frozen runner captured only the exception class. It did not retain AWS's detailed error message, status, or request ID, so this trial cannot identify the rejected field or establish schema complexity as the cause. A separately planned one-dispatch diagnostic may recover the error details. It cannot rescue this qualification or change its denominator, regardless of its outcome.

Offline verification of the isolated implementation had passed 1,150 backend tests, Ruff, `git diff --check`, SAM lint/build, and packaged SDK validation of 90 native configurations in each of three artifacts. The seven probe test groups and a no-network replay also pass. These checks establish local behavior and SDK request shape; this live failure demonstrates that they do not establish service acceptance. No deployment or reasoning/policy default change follows from this trial.

Frozen plan SHA256: `1c31697dd30798519a5dd788a2d485fbc6213ea547e088789bc9958594bf1098`.

Frozen capture SHA256: `c49e6707e44735c0211083816b13a83321ceedc4a5ebd704a4cdacf4d31206a3`.

Independent audit SHA256: `414aadcfb2a4a28a36b340005172556878cb9bebc137e3b5c0283c0748df2293`.

Run `replay.py` for the no-network request/source and denominator replay. `runtime-reconstruction.json` and `runtime-source.patch` preserve the exact temporary runtime relative to Git base `bfaa34edb30070eecaa6e3d923f60e50b487224a`. Reproduce it in an isolated checkout using `git apply --unidiff-zero runtime-source.patch` and verify every recorded source hash; do not replace unrelated work. Historical plan, capture, runner, source pins, and gold have not been edited.
