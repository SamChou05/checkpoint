# Generic prose seven-row reserve qualification, trial 03

Trial 02 is terminal. Its native seven-row author request succeeded, producing
seven sanitized source rows, but Bedrock rejected the subsequent seven-row
complete-choice solver request with a `ValidationException`. The retained
capture does not include the provider's free-text explanation, so schema
complexity and other native validation causes remain distinguishable only in a
successor trial. Trial 03 uses a separate ID, plan, precheck, and capture.

The synthetic probability request and five-question quality gate are the same
as trial 02. The proposed opt-in worker authors seven rows once, sanitizes the
whole set, then verifies the first four and the remaining one to three surviving
sanitized rows in separate
answer-blind solver and authored-teaching reviewer batches. A successful job
has five Converse calls in this order: author7, solver4, reviewer up to4,
solver matching the second batch's actual size, reviewer up to that size. A reviewer may reject a candidate; the worker must
return the earliest five accepted original source ordinals or return no
questions when fewer than five pass. All seven original identities and each
batch's source ordinals are captured. Deterministic prefix replay of the
production sanitizer binds accepted rows to the exact authored ordinal, even
when an earlier invalid authored row and a later valid row share a stem. The
second reviewer receives keyless
coverage of all first-batch candidates; this is a prompt-level novelty check,
not a deterministic semantic proof.

The request still uses one job, a shared 240-second execute deadline starting
before credential export and STS, one SDK attempt per Converse reservation,
and a six-reservation ceiling. Successful qualification requires exactly five
provider calls, five policy-7 questions, four distinct choices and a single
supported key per question, acceptable difficulty, sound teaching, and two
locked independent blind reviews with no strong cross-question repeats. A
failed or underfilled execution is terminal for this trial ID: no retry,
fallback, top-up, second job, queue, bank insertion, or deployment.

The frozen plan SHA-256 is
`8c493d8e068ea153cf8a4225a7ed955df90d7c9cadd954e2b506b47dc941deff`.
The harness SHA-256 is
`e9e8a128511345c1cfb2544979391feb749f16751860f0a3b5df1fa93af53046`.
An independent exact-hash review found and required fixes for two draft
misclassifications: 4+1/4+2 sanitizer survivors and duplicate authored stems.
The revised harness passed 21 socket-free tests, its 16-test preflight, Ruff,
and `git diff --check` before freezing.

The harness performs no AWS operation on import, `--draft`,
`--preflight`, or `--freeze`. It pins the reviewed chunked source commit
`d1483312b71f6b1335d1630547c85260aab8ef64` and requires a reviewed
frozen plan and harness hashes, independent review lock, and fresh account
precheck before the one-shot `--execute`. The one-shot execution has now ended
and is final for this trial ID; see [results](RESULTS.md).
