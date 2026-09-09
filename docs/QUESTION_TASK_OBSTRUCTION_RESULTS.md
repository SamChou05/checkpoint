# Task-obstruction qualification: operational attempts

AWS sign-in was renewed on September 9. A separately recorded attempt using the
original frozen plan then stopped at its first request with a schema validation
error. The [compatibility diagnosis and correction](QUESTION_TASK_OBSTRUCTION_SCHEMA_FIX.md)
preserve that failure and its exact-request diagnostic. No model responses or
correctness measurements are available from either operational attempt below.

## September 8 authentication failure

The [ten-case qualification](QUESTION_TASK_OBSTRUCTION_PROTOCOL.md) did not
reach a model. Its first local worker failed while obtaining credentials; the
CLI terminal reported an expired AWS sign-in. The capture retains the resulting
`CalledProcessError`, not that terminal message. No question-correctness result
is available.

The terminal capture records one local launch, zero provider dispatch attempts,
zero model responses, zero completed cases and zero fetches. The worker was
terminated and reaped, with process-group cleanup confirmed. It contains no
known model usage; missing usage is not presented as a measured zero-token bill.
No retry, fallback, production write or deployment occurred in this attempt.

The source candidate is committed at
`8b23eabd010477c2027f1df1563926aa220e1371`. All 39 planned source hashes matched
that commit before dispatch. The frozen plan's canonical SHA256 is
`28dfc43909fb7f2d322f440a3b7683c6a8a77310ea90614d257baad324ed92fe`.
The original local capture is 518,490 bytes with byte SHA256
`dcd7359951c7d52683032a92df427611cd6b008247919c7140d36d37696c1f83`.

The [derived failure summary](evidence/task-obstruction-auth-failure-20260908.json)
retains operational metadata and original hashes, while omitting source-bearing
requests and passages. It is not a raw capture or standalone replay archive.
The original plan and capture remain local.
Independent no-client replay reproduced the terminal capture exactly, and all
39 source hashes were checked again against the committed source.

Source validation passed 972 backend tests without skips, scoped Ruff,
compilation, native schemas, Bedrock request shapes and diff checks. These verify
the application gates and experiment mechanics. They do not show that models
correctly classify a false premise or an incorrect explanation. The candidate
remains eval-only and the broader correctness issue remains unresolved.

This failed attempt remains preserved; it was not resumed or overwritten.
No assessment should credit an authentication failure as detection of a
defective item.
