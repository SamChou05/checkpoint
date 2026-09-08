# Immutable teaching audit: separate five-case follow-up

Prospective protocol, September 8, 2026 UTC. The
[original six-case trial](QUESTION_IMMUTABLE_REVIEW_RESULTS.md) stopped after one
call because a 283-character internal diagnostic issue exceeded a 280-character
bound. Its raw response identified the three intended photography feedback
defects, but the primary contract failed. That trial remains terminal and failed.

## Change and evidence boundary

Internal issues now have a 280-character brevity target and a 2,400-character
hard bound, with at most eight issues. The full raw review is limited to 24,000
characters before JSON parsing. Types, exact feedback coverage, unsupported and
uncertain vetoes, and the prohibition on replacement learner content remain.
All learner-facing field limits remain unchanged at 320/140/420/280.

A 283-character issue is therefore permitted diagnostic content. An overall
approval with any such issue still rejects the item. Oversized review envelopes,
overlong diagnostics, malformed types and replacement fields still fail closed.
This is a parser/resource-policy fix, not an increase in model output tokens or
a factual correctness claim.

The runner now accepts one to six separately frozen fixed cases and binds its
call limit and completion denominator to the exact job count. This avoids
duplicating the runner for a five-case trial. It has no resume operation; old
captures cannot be imported as fresh observations or overwritten.

## Five unchanged cases, five calls

The [follow-up fixture](../backend/bedrock-question-service/evals/fixtures/question_immutable_review_followup.json)
contains exactly cases 1 through 5 from the original fixture, in the same order.
Every complete case object, including task, choices, key, proposed feedback,
context, expectations and provenance, is unchanged. The previously dispatched
bad-photography case is excluded. This is a new trial with a new identifier,
source revision, plan, requests and output directory—not a resumed capture.

Expected full-item outcomes are three valid controls and two rejections:
sound photography feedback, bad music feedback, sound music feedback, the wrong
all-pairs key, and a well-posed negative-answer control. The original bad-photo
raw response stays a separate observation; it cannot be combined with this run
to claim six successful primary decisions under one frozen configuration.

The model, effort, token allowance and timeouts remain Opus 4.6 adaptive/high,
16,000 output tokens, one SDK attempt, three-second connection timeout and
100-second read timeout. There are at most five calls, one per fixed case,
32,000 input-text UTF-8 bytes per call and 160,000 total. All five exact requests
and relevant source/dependency hashes must be frozen before dispatch.

Diagnostic-limit wording is the only intended provider-prompt change from the
original requests. Explicit keys, author difficulty, solver/history output,
expectations and provenance remain absent. Existing feedback still exposes the
intended answer; this audit is not answer-blind. Both music variants retain
identical context. There is no automatic source retrieval.

Any provider, malformed-review, persistence or binding failure stops later calls.
No retry, repair, replacement, extra call, native execution, author or solver
inference, production integration, model promotion or deployment belongs to this
trial. The minimum difficulty remains 1 for isolating factual feedback checks,
not for demonstrating advanced question generation or adaptive progression.

## Decision

Keep the original expectations. Report all five cases, actual calls, unknown
results, exact selected answers, every feedback judgment and issues. Inspect
rejection reasons against the predeclared defects and check the exact returned
teaching content on accepted controls. Invented objections, uncertainty and
format failures are separate from warranted semantic detection. Full fixed-item
feasibility requires all five expected outcomes with supported reasons; a partial
result remains partial.

A pass would qualify only a fresh complete-authoring/full-pipeline test. It
would not establish that authors can produce bounded feedback, fill banks at the
requested challenge, meet production latency, handle arbitrary sources, close
the free-prose solver contradiction, or improve learning outcomes.

## Local verification before freezing

The 27 focused contract and runner tests pass. An isolated checkout containing
only this milestone's source, tests and fixture passes the full backend suite:
689 tests with one existing optional-runtime skip. The tested files were checked
byte for byte against the working files. Ruff and `git diff --check` pass.
An independent review confirmed that every follow-up case is identical to the
corresponding original case and that the first dispatched case is excluded.
No follow-up provider calls have been made at this point.
