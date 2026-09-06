# Isolated candidate verification feasibility, 2026-09-06

**This run is operationally inconclusive.** It stopped on a provider timeout after
nine of sixteen permitted calls. Eight candidate judgments completed, but no
question received all four required judgments. There is no evaluable question-level
accuracy or valid-control retention result, and no runtime change is justified by
this run. Two completed explanations also repeat unsupported claims.

The [exact evidence capture](evidence/isolated-candidate-feasibility-20260906.json)
contains the fixed prompt, fixtures, actual requests, final response text, returned
reasoning-block counts, token metadata, partial judgments, and failure record.
Reasoning text is not retained. The run used the clean detached revision
`dc75a8edf32fe8355171e2133341a0bacbfc048f`, with no live rerun or deployment.

## Method and boundary

Each request received the unchanged stem, exactly one candidate, goal context,
and the existing manually curated reference packet. It received no sibling choices,
author key or explanation, solver feedback, or other candidate verdicts. A fresh
single-message request was used for each candidate. The four existing controls
and their reference packets were unchanged: all-pairs output bound, Boolean pair
existence, unsupported RAW editing sequence, and nondestructive RAW editing.

The model classified whether the candidate fully answered the stem as supported,
refuted, or undetermined, with a concise reason and necessary qualification or
counterexample. Refutation concerns adequacy as a warranted answer; it does not
require every proposition in a candidate to be false in every possible world.
Code accepts a question only after four valid judgments establish exactly one
supported candidate and three refuted candidates. It cannot choose a closest
option by elimination or count uncertainty as refutation.

The runtime JSON extractor handled fences and prose-wrapped objects identically
to production. Malformed responses and all non-`end_turn` terminations were
operational failures, not successful detection of defective questions. Requests
and attempted-call counts were saved before each network call. The first provider
failure stopped the experiment; no retries or replacements followed.

Settings were Opus 4.6, requested adaptive thinking/high effort, 16,000 output
tokens, a 100-second read timeout, one network attempt per candidate, randomized
candidate order, and a hard sixteen-call ceiling. These were evaluation settings;
production defaults were unchanged.

## Observations

| Measure | Result |
| --- | --- |
| Attempted provider calls | 9 of 16 |
| Completed candidate judgments | 8 |
| Provider failures | 1 read timeout |
| Format failures | 0 |
| Unattempted candidates | 7 |
| Evaluable complete questions | 0 |
| Known returned input/output tokens | 8,987 / 4,127 |
| Summed candidate elapsed time | 178.680 seconds |

The ninth call, the hash-map candidate for the all-pairs question, timed out after
100.009 seconds. Its token usage is unknown; the zero aggregate counters in that
failed result do not establish zero provider usage. All eight returned responses
ended normally and included a reasoning-content block. Their largest reported
output was 1,289 tokens; nothing is inferred about the unreturned ninth response.

| Control | Completed judgments | Other outcomes |
| --- | --- | --- |
| All-pairs output bound | 1 refuted | 1 timeout; 2 unattempted |
| Boolean pair existence | 1 supported, 1 refuted | 2 unattempted |
| Unsupported RAW sequence | 2 refuted | 2 unattempted |
| Nondestructive RAW editing | 3 refuted | 1 unattempted |

These are model statuses, not independent certifications of each explanation.
Partial evidence already shows two relevant explanation defects:

- While refuting the all-pairs binary-search candidate, the model volunteered
  that a hash map was the correct linear-time/linear-space approach. It repeated
  the output-size error without seeing the hash-map sibling choice. Enumerating
  all matching index pairs can require quadratic output; a lookup strategy does
  not remove that obligation.
- While refuting aggressive shadow recovery, the model claimed reference E3
  establishes an exposure/white-balance step before targeted recovery. That
  reference packet does not mention white balance or establish that ordering.

The first defect shows that hiding sibling choices does not by itself prevent a
familiar but inapplicable solution from appearing in feedback. The second shows
that an apparently useful rejection can still carry unsupported teaching content.
Neither establishes the unobserved aggregate acceptance decision.

An unchanged rerun with a longer deadline is not recommended: a longer wait could
complete the aggregate test, but it would not address the explanation defects
already observed in completed responses. Aggregate accuracy remains inconclusive;
the feedback problems are directly evidenced.

## What this does not establish

An isolated candidate may be undetermined because a legitimate question is
option-relative, such as asking which listed value is largest. Without the rival
values, that is a limitation of this verifier rather than proof that the complete
MCQ is defective. The selected controls cannot qualify a general replacement.

The fifteen new offline tests cover request isolation, aggregation, a valid
cannot-determine answer with countermodels, parser behavior, durable captures,
termination handling, and the call ceiling. They do not establish that the live
model correctly handles non-identifiability or impossibility. Any later
qualification needs actual held-out valid relative-comparison, negative, and
impossibility items, as well as independent feedback review.

The prior all-choices audit used a more elaborate response contract and omitted
goal context. This run therefore does not isolate a pure single-factor causal
effect of hiding sibling choices. Its manually selected evidence also says
nothing about automated retrieval quality.

Batching one candidate for each distinct stem into a call could preserve sibling
isolation while using four calls per question batch. That is a future, untested
optimization. This run neither tested that arrangement nor solved its limitations.

The harness milestone passed all 329 backend tests in an exported staged snapshot,
Ruff, a sixteen-call dry run, and `git diff --check` before the live attempt.
