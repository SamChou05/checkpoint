# Seven-row probability author with thinking disabled

The frozen [plan](plan.json) tests one configuration change after [reserve
trial 03](../generic-reserve-seven-probe-v3-20260927/RESULTS.md) exhausted the
16,000-token adaptive-thinking output budget before producing complete JSON.
It uses the identical synthetic probability request, Sonnet 4.6 model,
source commit `d1483312b71f6b1335d1630547c85260aab8ef64`, and 1,117-byte
native seven-row author schema. Only `BEDROCK_CLAUDE_THINKING` changes from
adaptive to disabled; the service consequently sends `maxTokens: 6000`,
`temperature: 0.2`, and `thinking: disabled` instead of the former 16,000-token
adaptive-high settings. The author wire SHA-256 is
`6acf130d9bab1dfedea157c2ca8249f98ceb84111bca45d115fff970d62d47db`.

The plan SHA-256 is
`e6b73e56fee680d8ea3725f7150b3a12596d014bb3ba102f3e423b7fb94444c9`;
the [harness](probe.py) SHA-256 is
`514ada7e2be3dcf423228ebf26a96f7dc1d0bbe9e519eb77c7326822b3c6d918`.
An independent reviewer checked the exact draft, wire delta, one-call/one-SDK
attempt limit, 240-second deadline, credential and capture boundaries, and
the source-ordinal-blind [worksheet builder](make_worksheet.py). Three
socket-free tests, preflight, Ruff, and `git diff --check` passed before
freezing. The builder uses a private HMAC-derived derangement and keeps seed
and answer map outside Git with mode `0600`.

No author result is a verified worker return. A successful author response
would need a separate keyless content review, and a full five-question worker
trial would still be needed to qualify the chunked verifier. This trial has
one durable Converse reservation, one SDK attempt, a shared deadline starting
before credential export/STS, and no retry or fallback. Its capture is
terminal for this trial ID. No AWS operation has run for this frozen plan yet.
