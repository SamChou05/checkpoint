# Author representation follow-up, September 6, 2026

The targeted representation instruction produced ten questions with valid
displayed content and independently supported literal answer keys in this small
follow-up. All five multiline code definitions compiled as shown. The ten main
explanations also matched the independent calculations. Four questions remained
below the requested difficulty, and the two author calls each took more than
100 seconds. This supports the specific representation change; it does not
qualify generalized correctness, adaptive learning, or production latency.

The [complete archive](evidence/author-layout-feasibility-20260906.json) preserves
the exact old and new prompts, user request, provider calls and final responses,
blinded exports, frozen judgments, post-freeze explanation audit, exact content
joins, and source hashes. No reasoning text is stored.

## Problem and isolated change

The [earlier author experiment](QUESTION_AUTHOR_SCHEMA_EXPERIMENT.md) contained
five malformed stems across twenty items. The author converted valid multiline
definitions into a one-line compound statement, then supplied the answer to the
intended computation rather than the invalid program actually displayed. Two
such failures occurred in the ten ordinary-output questions; three occurred in
the ten schema-constrained questions. The source and transport had retained the
required layout.

Prompt milestone `e62ce68` adds generalized guidance to preserve literal content,
necessary line breaks, and indentation when syntax or layout matters. An
algorithm may instead be described consistently in prose. Answers and
explanations must match the exact representation shown. Intentionally invalid
code is permitted when the question tests the error and the answer and
explanation acknowledge it.

This change does not name a programming language, exam, or canned question.
Numeric difficulty targets, source rules, character limits, and the requirement
to keep all necessary facts were unchanged. Native schema enforcement was not
used in the follow-up.

## Controlled execution and blind review

The clean immutable launch revision was
`cfa7d34921271fd58dd09ecc90465afbdcafb725`: the prompt milestone plus the separately
verified harness extension. The executable plan selected the ordinary arm,
two repetitions, and an explicit **maximum of two provider calls**. Exactly two
calls ran, both ending normally. There were no repair calls, retries, solver or
reviewer calls, subsequent live reruns, or deployment.

The entire user prompt and supplied source packet were checked for exact equality
with the preserved earlier plan before any provider request. The only system
prompt difference was the approved representation paragraph. Both calls used
the same Opus 4.6 model, adaptive/high settings, 16,000-token allowance, and
explicit 300-second client read deadline as the earlier ordinary arms. Actual
requests confirm that neither contained `outputConfig`.

The two author batches produced five questions each. An independent agent saw
only goal, source, exact stem, and choices while selecting literal answers,
checking representations, and rating difficulty. The five displayed multiline
definitions were compiled without replacing them with the source definition.
The complete ten-item blind record was frozen before keys and explanations were
revealed. Its SHA-256 is
`31073df498a6da1928ae4dd9b5f894545e6fec2b0f142cb402291a64097625cb`.

Post-freeze comparison joined every answer-key row uniquely to the frozen record
by exact stem and ordered choices, with stable content hashes. The archive
preserves the frozen JSONL text and its unchanged hash, as well as the independently
reviewed main explanations. Temporary Q-row identifiers were not used as stable
cross-batch identities because the inherited exporter reshuffles rows.

## Results and limits

| Measure | Result |
| --- | --- |
| Provider calls / explicit cap | 2 / 2 |
| Generated questions | 10 |
| Questions with a unique supported literal key | 10 |
| Malformed displayed representations | 0 |
| Exact multiline definitions successfully compiled | 5 |
| Supported main explanations | 10 |
| Independently rated difficulty 2 / 3 | 4 / 6 |
| Longest stem | 252 characters, within the 320 limit |
| Author latency | 107.661 and 110.871 seconds |
| Returned input / output tokens | 3,666 / 16,543 total |

Both responses were valid JSON, passed runtime parsing, and supplied five
structurally retained questions. Each returned a reasoning-content block. The
author labeled all ten questions difficulty 3; the independent review rated four
as difficulty 2. Structural retention is therefore not equivalent to ten usable
questions at the requested level, and it is not verified production inventory.

The earlier ordinary sample had two malformed representations and eight supported
literal keys out of ten; this follow-up had zero malformed representations and
ten supported literal keys. These are descriptive results from fresh questions
under one goal. The runs were not a sufficiently replicated or randomized
comparison to estimate a general error-rate reduction. They show that the
observed layout defect can be avoided without removing necessary facts or
increasing the existing stem limit.

No per-choice feedback was generated in this author-only trial. Its reviewed
statement count is zero and its error count is unknown, not zero. The runtime
solver/reviewer, difficulty filtering, question-bank top-up, and adaptive learner
progression were not exercised. The evaluation's 300-second timeout was unchanged
from the prior author experiment and is not a deployed worker setting; these
latencies do not qualify the model for production deadlines.

The prompt-only milestone passed 51 existing provider, quality, and subject-content
tests. The harness extension passed all 340 backend tests, Ruff, an exact-reference
two-call dry run, and `git diff --check` before the live run. Archive verification
confirmed both provider requests, the explicit cap, source/prompt hashes, frozen
review integrity, and all ten exact joins.
