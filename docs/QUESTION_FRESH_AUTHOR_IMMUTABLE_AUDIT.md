# Audit two unchanged fresh author outputs

Prospective protocol, September 8, 2026 UTC. The [author-only observations](QUESTION_AUTHOR_LATENCY_RESULTS.md)
produced two correct keys, one material CSS feedback error and one sound English
item below the requested difficulty. This follow-up asks whether the existing
immutable auditor detects those defects in the exact complete outputs. It does
not regenerate, repair or simplify either item.

Use the existing immutable-review runner from detached source
`ed38bdde4021918377cc56f89c9b16992e06c869`, with Python 3.12.11 and
boto3/botocore 1.43.89. The [fixture](evidence/fresh-author-immutable-fixture-20260908.json)
binds the exact items and original goal/source context to the author capture.
External assessments and defect hints stay outside provider input. The authored
key and difficulty fields are withheld; teaching feedback necessarily reveals
the proposed answer. Normal deterministic choice rotation is unchanged.

The [frozen plan](evidence/fresh-author-immutable-plan-20260908.json) permits exactly
two serial auditor calls, at most one per item, with 6,446 and 6,040 input bytes.
It uses Opus 4.6, adaptive thinking, high effort and a 16,000-output-token cap.
Connection/read timeouts remain 3/100 seconds, with one SDK attempt. This is the
existing audit transport, not the author probe's longer observation window.
There is no hard whole-run deadline. Provider, malformed-output, persistence or
binding failure stops later calls; no retry, resume or replacement is permitted.

The canonical plan SHA-256 is
`236eca966a40518e2d6c099fdf473f7914147b89621e3fb53a0aa40a9f57cc43`;
its byte SHA-256 is
`d32e3fed0e5acf9ad9eb504895b16e235b8c01fe77a01587034593b2bd3c16c8`.
The exact plan rebuilt successfully from the detached source before dispatch.

## Predeclared interpretation

The unchanged runner isolates factual support at a minimum difficulty of 1.
Record that original result, then separately apply the existing pure
`observe_review` function to the same raw review and exact question with the
original target minimum of 3. The minimum is excluded from the auditor request;
floor-1 and floor-3 contexts were checked to produce identical requests. This
secondary evaluation is declared before dispatch and must not overwrite the
baseline capture or suggest the author target was lowered.

- CSS: the auditor must identify the materially false dense-packing feedback.
  Rejection for an unrelated issue alone does not demonstrate detection of that
  error. The answer key remains correct.
- English: content should remain supported, while its independently assessed
  difficulty should fall below 3. A spurious factual rejection does not count as
  correct difficulty assessment.

Inspect every review field and issue, not just the final retain/reject result.
Retain any disagreement with the frozen independent assessments. These two
selected observations cannot estimate general accuracy or learner progress.
There are no author/solver calls, production stamps, model promotions or deployments.
