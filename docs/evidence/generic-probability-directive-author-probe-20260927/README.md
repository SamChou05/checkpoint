# Probability directive author-only probe (draft)

This isolated trial changes only `goal.questionDirective` from trial 02's
synthetic probability request to the 681-character recommendation in
[`DIFFICULTY_ANALYSIS.md`](../generic-reserve-author7-blind-20260927/DIFFICULTY_ANALYSIS.md).
The source candidate is commit `d1483312b71f6b1335d1630547c85260aab8ef64`.
The experiment asks whether that guidance yields seven stronger authored
multiple-choice candidates. It does **not** run the answer-blind solver,
authored-solution reviewer, or five-survivor worker, and cannot qualify the
generic route for production.

The harness has no AWS work on import, `--draft`, `--preflight`, or `--freeze`.
Its provider-visible author wire and native schema are captured with a fake
client and pinned by byte hash. A frozen plan, separate root and independent
review lock, fresh default-profile account/credential precheck, and single
240-second execute allowance are required before the one author dispatch.
The execution creates an exclusive capture before credentials and STS, reserves
the sole Converse slot durably, disables SDK retries, and saves all seven raw
and sanitized source rows. It records only bounded visible provider output and
no credentials. A failure, deadline, or absent row ends this trial; no retry,
top-up, second job, or worker verification is allowed.

After a successful capture, create a new keyless worksheet from all seven
sanitized rows. A secret-seeded deterministic derangement assigns public IDs
independently of source ordinals; the seed, source mapping, and answer-to-letter
map stay outside Git with mode `0600`. The frozen plan also pins the worksheet
builder's bytes.
Two independent reviewers should rate each item's unique key, difficulty,
self-containment, distractor mechanisms, and cross-item repetition before
opening that map. Neither a clean seven-row author output nor favorable blind
ratings prove five verified worker survivors.

**Current state:** the plan is frozen at SHA-256
`4c5e3c7a4df060f313401fa2d6fb87267c8d39281a9d85546cf75d9c576f9ffe`;
the harness is SHA-256
`e9c7cc3b0a6dc53ca79263e3738c4e0b14d621a54518914d63b5d3e0ca5fcd95`.
An independent reviewer approved the revised source-ordinal-blind worksheet
builder after identifying and correcting an ordinal-leaking draft. The
one-shot AWS call is now terminal and failed at the shared output-token limit;
see [results](RESULTS.md). Run `python -B -m unittest -q test_author_probe.py`
and `python -B author_probe.py --preflight` to inspect the socket-free design.
Trial 03's high-effort author call also stopped at `max_tokens` before
sanitization. This experiment held that configuration fixed to isolate the
directive, and its own capture confirms the same terminal failure.
