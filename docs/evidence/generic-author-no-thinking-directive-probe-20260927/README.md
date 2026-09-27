# Disabled-thinking probability directive comparison (draft)

This separate author-only probe compares against the frozen no-thinking
probability plan `e6b73e56fee680d8ea3725f7150b3a12596d014bb3ba102f3e423b7fb94444c9`.
The **only provider-visible change** is replacement of
`goal.questionDirective` with the exact 681-character recommendation in
[`DIFFICULTY_ANALYSIS.md`](../generic-reserve-author7-blind-20260927/DIFFICULTY_ANALYSIS.md).
The source commit, Claude Sonnet 4.6 model, native seven-row schema, disabled
thinking, 6,000-token cap, temperature, and synthetic probability goal remain
fixed. This tests whether the directive improves authored candidates under the
non-thinking transport. It does not run sanitization, the answer-blind solver,
the reviewer, or the five-question worker; a seven-row output alone cannot
qualify the worker.

`probe.py --draft` and `--preflight` are socket-free. The frozen plan pins the
exact source, baseline plan, harness, request, provider wire, and worksheet
builder. Root and an independent reviewer must approve the exact plan and
harness before a fresh AWS identity precheck. The one-shot execution creates a
durable capture before credentials and STS, allows one Converse reservation and
one SDK attempt, and has a 240-second deadline. Any failure or truncation is
terminal for this trial ID; there is no retry, fallback, second job, or worker
verification.

If all seven native rows return, `make_worksheet.py` creates a public keyless
worksheet with a secret-seeded source derangement and choice shuffle. The seed,
source ordinal map, capture locator, and answer letters remain in mode-`0600`
files outside Git. Two reviewers should assess keys, difficulty,
self-containment, distractors, and cross-item repetition before the private map
is opened.

The prior high-effort directive probe is a separate terminal failure and is
unchanged. **Current state:** frozen plan SHA-256
`4904119d0e962b5fce8af6ba9645c1c320315eb533d9992e4e48f0560ddda73f`,
harness SHA-256
`13b06338587adc166403c26ca3d1475a213fa78f377221b380d9be0e35d52f90`.
An independent exact-hash review approved the request-only wire difference,
one-call controls, and private worksheet mapping. No AWS call has run yet.
