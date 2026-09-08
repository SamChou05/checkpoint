# Fresh complete authoring: first trial timed out

September 8, 2026 UTC. The [frozen four-goal trial](QUESTION_COMPLETE_AUTHORING_EXPERIMENT.md)
stopped during its first author call with a `ReadTimeoutError` after 100.213
seconds. No model response, question, token-usage record, solver call or auditor
call was returned. The other three goals were not attempted. This is an
operational failure, not evidence that a generated key or explanation was wrong.

| Planned goal | Calls dispatched | Captured content | Outcome |
| --- | ---: | --- | --- |
| CSS Grid placement | 1 author | None | Read timeout |
| Conditional probability | 0 | None | Unattempted |
| English conditions and quantifier scope | 0 | None | Unattempted |
| Dissolved solute and concentration | 0 | None | Unattempted |

The target of one supported, appropriately challenging item per goal was not
achieved. There are zero available MCQs to assess, rather than four observed
incorrect MCQs. Neither complete-content authoring feasibility nor the three-call
author/solver/immutable-auditor sequence was exercised to completion.

## What is known and unknown

The request used the exact frozen CSS goal and primary-source summary with the
generic complete-item author prompt. Its text was 5,687 UTF-8 bytes, within the
32,000-byte per-call allowance. The model was Opus 4.6 with adaptive thinking at
high effort and a 16,000-output-token allowance. The client had a three-second
connection timeout, 100-second read timeout and one SDK attempt.

The exact request and its bindings were durably recorded before dispatch. The
captured failure identifies `provider_dispatch`, and the replay reconstructs one
attempt and the unattempted suffix. The call interval includes client/provider
waiting and does not measure time spent reasoning. There is no stop reason,
output-token count, final answer or private reasoning to inspect. Usage is unknown,
not zero. The record cannot establish whether a delayed server-side generation
completed after the client stopped waiting.

No response was repaired or resubmitted. The trial was not restarted or resumed;
its unused eleven-call allowance was not spent. No source retrieval, calculator,
native execution, production write, model promotion or deployment occurred.

The observed obstruction is transport completion within the chosen window. It
does not establish that more context, fewer constraints, more output tokens or
a different question prompt would improve correctness. The next operational
experiment should isolate the timeout/latency question before changing the
author's subject or correctness requirements. Any changed configuration needs a
separate recorded plan and must keep this failed trial distinct.

## Evidence and local verification

- [Exact frozen plan](evidence/complete-authoring-plan-20260908.json)
- [Terminal capture](evidence/complete-authoring-capture-20260908.json)
- [Replayed failure and unattempted cases](evidence/complete-authoring-replay-20260908.json)
- [Independent binding and failure audit](evidence/complete-authoring-binding-audit-20260908.json)

The capture byte SHA-256 is
`1362b862932ebf7705b1ff7420789ce002f8eb8eb8434bc5cb90a38856ad0e25`.
The replay byte SHA-256 is
`6a52e1f9b42b9e862c67600a194ba6a94941e0d9e85cb90cbbadb28d7911ba64`.
Reconstruction succeeds from clean source
`d06a7bfdf08853b8644a00c6df2e0a8aa46726c9` with Python 3.12.11 and
boto3/botocore 1.43.89. It establishes recorded control flow and request binding,
not provider authenticity or semantic accuracy.

Before inference, the prototype passed 19 focused author/runner tests and the
716-test backend suite, with one existing optional-runtime skip. These validate
formatting, exact-content preservation, gating, budgets and replay. They cannot
substitute for the missing live content and independent subject assessment.
