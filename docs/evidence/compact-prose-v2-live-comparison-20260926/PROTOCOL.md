# Compact prose prompt v2: paired author trial

This is one author-only experiment, not a deployment qualification. The source
candidate is `9477f77`. The prior five-slot 3 arithmetic : 2 English request,
Sonnet 4.6 model, accepted 2,664-byte schema, native output transport, high
adaptive reasoning, 16,000-token output cap, and trusted slot mapping are held
fixed. The arms differ only by the system prompt span selected through
`QUESTION_MAPPED_PROSE_PROMPT_REVISION=v1|v2`.

Freeze a hash-pinned plan after socket-free tests. The plan chooses one of two
arm orders with a cryptographic random bit. Review the plan and harness before
running `--execute PLAN_SHA256`. Execution allows exactly one Converse author
call per arm and two calls total. It makes no solver, reviewer, retry, repair,
fallback, or top-up call. The SDK has one attempt, a 200-second read timeout
ceiling, a 220-second per-arm nominal limit, and a 470-second total bound.
The only other service call is one read-only STS account check. Each provider
slot is durably reserved before Converse; a failed or interrupted slot stays
unavailable. Captures retain visible provider JSON, usage, latency, request
hashes, and redacted errors, without credentials or reasoning blocks.

After both captures are committed, make a separate arm-blind and answer-blind
worksheet. Independent reviewers judge all six choice pairs, unique answer,
displayed premises, and explanation support. Reveal keys and arm labels only
after reviews are committed. This comparison can detect a prompt improvement
or regression; a single pair cannot establish long-run reliability.
