# Generic seven-row reserve, full-worker trial 04

Trial 03 ended after the seven-row author exhausted its shared 16,000-token adaptive-thinking output budget, before chunked verification. A separate author-only disabled-thinking probe returned seven complete native rows once, but it did not exercise the worker. This trial uses the **same original synthetic probability request** and pinned production source commit `d1483312b71f6b1335d1630547c85260aab8ef64`. Its author, solver, and reviewer calls all use Claude Sonnet 4.6 with thinking disabled, ordinary `maxTokens: 6000`, and `temperature: 0.2`. Compared with trial 03, the native author schema, system prompt, user request, model, and worker route are unchanged.

The opt-in worker authors seven rows once and sanitizes all seven. It verifies the first four and remaining one to three sanitized rows in separate answer-blind solver and authored-teaching reviewer batches. Successful topology is five Converse calls: author7, solver4, reviewer up to4, solver matching the remaining batch, reviewer matching its surviving rows. The bound is six durable reservations, one SDK attempt each, inside a shared 240-second execute deadline that begins before credential export and STS. Prefix replay binds each surviving sanitized row to its original authored ordinal, including an invalid earlier row with a duplicate stem. The worker returns the earliest five verified original ordinals or no questions if fewer than five pass. Underfill, native rejection, truncation, deadline, and capture integrity failure are terminal for this trial ID; no retry, fallback, top-up, second job, queue, bank insertion, or deployment runs.

`live_probe.py --draft` and `--preflight` are socket-free. The frozen plan, exact source and harness hashes, independent review lock, fresh default-profile AWS identity check for account `239342516379`, and one-shot capture must all pass before `--execute PLAN_SHA256`. Tests cover the exact disabled-thinking wire on every stage, real SDK metadata with fake Converse, sanitizer drops, duplicate stems, reviewer and solver rejection, underfill, deadline, response filtering, and a missing review lock. A machine-positive result only enables independent keyless content review; it does not by itself qualify or deploy the reserve.

The frozen plan SHA-256 is
`835f1115960e9da9fa3be7dc0643799986097f1e08f559e1a1a7be7d6454d536`;
the harness SHA-256 is
`9b6717295a1270a91ac74eab37fb492de682a85c097a93f7a4a0d9d3f8ac2adf`.
Independent exact-hash review approved the disabled-thinking wire and
4+1/2/3 source-ordinal behavior. All 22 socket-free tests, preflight, Ruff,
and `git diff --check` passed before freezing. No AWS call has run yet for
this trial ID. The one-shot worker has now completed; see the [machine result](RESULTS.md)
and [blind-review rubric](BLIND_REVIEW.md) before judging content.
