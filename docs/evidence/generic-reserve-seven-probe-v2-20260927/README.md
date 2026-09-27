# Generic prose seven-row reserve qualification, trial 02

Trial 02 repeats the same fixed synthetic probability request and predeclared
quality gate as [trial 01](../generic-reserve-seven-probe-20260927/README.md).
Trial 01 is final and must not be resumed: its immutable capture records a
successful execute-time STS identity check, one durable author-call reservation,
zero saved Converse requests, and zero Bedrock dispatches. Its harness rebuilt
the full plan inside the patched author stage. That socket-free reconstruction
re-entered the stage-order guard as a second author call and stopped locally with
`request_or_provenance_integrity`. Trial 02 has a separate ID and folder so no
earlier authorization, freshness record, or capture can be reused.

The frozen trial 02 plan SHA-256 is
`6effccce724caaf54285b171d4152c5e6d3162a86d1c492c47a4ec215350013e`;
the harness SHA-256 is
`015e40566d0c6fb65dd36c21ecd5cee97a70d4ba895d7526a8150596c7037ca0`.
Neither a review lock nor a launch/capture artifact exists in this folder yet.

The trial 02 harness performs the full dynamic `check_plan` before it patches
the production generator. During the patched job, `production_pin_callback`
checks the exact frozen plan bytes and in-memory value, request and protocol
byte hashes, the harness and capture-helper hashes, the source-commit bytes,
and the loaded production-module closure. This check does not generate a fake
author wire. A socket-free regression invokes `run_job` with that **same**
callback and real boto3 client metadata while replacing Converse locally; it
requires three calls and five returned rows without a re-entered author stage.

The request is one original five-question, no-skill-map probability job. The
opt-in route must author exactly seven native prose rows once and return the
earliest five accepted source ordinals after its existing sanitizer,
answer-blind four-choice/six-pair solver, and authored-explanation reviewer.
The full predeclared machine and two-person blind-review gate is unchanged in
`protocol.json`: five policy-7 rows of difficulty at least 2, exactly one
offered key and four distinct choices each, 30 meaningfully distinct
within-question pairs, sound explanations, topic/self-containment, reviewer
difficulty 2–3, and no strong cross-question repeats. Missing or uncertain
evidence fails the trial. A run with fewer than five rows, an abort, or an
expired deadline is final; no retry, top-up, fallback, or second job is allowed.

This harness has no AWS activity on import, `--draft`, `--preflight`, or
`--freeze`. A reviewed, exact-hash `review-approval.json` and a fresh
`--launch-precheck` are required before the only `--execute` can run. The
execution creates its capture exclusively before credential export and STS;
the 240-second alarm starts before both. The provider allowance is at most six
durable Converse reservations, one SDK attempt per reservation, with 3-second
connect and at most 200-second read. Capture retains credential-checked visible
model text and bounded usage while excluding hidden reasoning and raw secrets.
The ordinary response cap is 6,000 tokens; adaptive Claude thinking makes the
actual author `inferenceConfig.maxTokens` 16,000, pinned in the plan.

Preparation uses `python -B -m unittest -q test_live_probe.py
test_protocol_guard.py`, `python -B live_probe.py --preflight`, then
`python -B live_probe.py --draft` and `--freeze` with that exact draft digest.
An independent reviewer must inspect the frozen plan and harness hashes before
any AWS precheck or execution. The first live capture, if one is later
authorized, only reaches `pending_content_review` when the machine gate passes;
two answer-blind and source-ordinal-blind reviews must then be locked before
comparing keys. One fixed successful job does not establish a population rate
or an advantage over five-row authoring. The deployed TestFlight path remains
legacy and is outside this experiment.
