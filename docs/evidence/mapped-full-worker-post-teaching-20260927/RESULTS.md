# Post-teaching mapped full-worker trial: 0/5 original slots

**Official outcome: FAIL, zero of five original slots returned.** The one-shot job stopped after a single author Converse call. Bedrock accepted the current native schema and returned all five typed task records, but the local English compiler rejected the new slot-4 gerund scene before sanitizer, solver, or teaching reviewer. No retry, fallback, repair, top-up, queue/bank write or deployment occurred. The previous source's 4/5 trial remains a separate failure and is not reclassified by this result.

The new trial ID is `mapped-3x2-post-teaching-20260927-01`. The [frozen plan](plan.json) SHA-256 is `36f7a318314a7abccd822f23bfe3d06c729cee656e97218d1585f35c97316775`; the [harness](full_worker_probe.py) SHA-256 is `d2c6fa6faa3cfa26b94cb3e6550b25af293500ca2a5abce578c5255479d75d4a`; the sanitized [capture](capture.json) SHA-256 is `5d4212bbc7dbc852645c99d7f737311957250239dded3aee9f785ae4a74405e3`. The plan pins main source `9d6a9b46ff8bde5db1b4ec1ad590197d56006c83`, the same synthetic 3:2 request SHA-256 `212cea7d53ddefe17fbe8f2459705b46b871793e62e0e58b56cc11e3626e63ae`, the prior 4/5 capture and result hashes, account `239342516379`, Sonnet 4.6 native/high transport, and the 2,101-byte author schema SHA-256 `ed2e1fbd2dff973a8a15c94d15a54dc8952f5c25a865a13c411e3a31e6c00cb0`. Root and independent reviewers matched the frozen plan and harness before AWS use; both pretrial and execute-time STS identity checks succeeded.

The single Bedrock author call took **21.55s**; the entire execute phase, including credential export and STS, took **23.02s** under the 240-second ceiling. Bedrock reported 2,876 input and 455 output tokens. The capture materializes all five original slots as **unfilled**, reserves exactly one of six durable Converse slots, and retains the five-key author object. It made no solver or final-review call, so this run cannot assess answer correctness, distractor quality, teaching, difficulty or a five-question worker yield beyond the observed failure.

The [offline replay](offline-replay.json) SHA-256 `7e9698c35a29bdc32a4c5be3166edfcac8e8346e0f521e5120e076b190065a22`, produced by [replay code](offline_replay.py) SHA-256 `7dcbf37eb8a29a604d7b463dd2d1d85b5108f9ad81eba33f3f3f80aaa4f94686`, reproduces the failure without AWS calls. The captured author object contains all original keys `0`–`4` and passes the current native response adapter. Its slot 4 selects `gerund_meals`, a scene admitted by the native schema and defined in `GERUND_SCENES`. The frozen `compile_mapped_english_slots()` slot-4 allowlist contains only compound, number and correlative scenes, omitting gerunds. It raises `AgreementTaskError("Original English slots require their closed agreement families.")` before a candidate pass is recorded; the worker surfaces `ProviderError` and returns no questions. This is a source contract mismatch, not a model failure to supply five typed records.

The harness passed 16 socket-free tests before launch; the replay, Ruff and `git diff --check` passed afterward. No keyless worksheet was produced because the worker returned no readable questions. The one-shot trial is complete and was not repeated.

The omitted allowlist entry was then fixed on `main` at `c12d554`, without
changing this official trial. A separate [fixed-source replay](fixed-source-replay.json)
uses the exact captured five-task author object and the pinned patched backend
([replay code](fixed_source_replay.py)). It now prepares three quantitative
and two English questions with zero compiler failures and sanitizes all five.
That offline replay makes no provider call and does not establish that the
downstream solver or reviewer would return five questions.
