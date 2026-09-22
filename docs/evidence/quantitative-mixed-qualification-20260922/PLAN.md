# Draft qualification of the mixed quantitative/prose route

This preparation is unfrozen. No provider calls, account activation, bank writes
or deployment are authorized by the draft itself. Root will review and freeze
the complete candidate source, exact initial requests, contracts, fixtures,
settings and limits before execution.

The candidate adds a typed numerical specification as an alternative to the
ordinary prose author row. Code owns all five learner fields for compiled items;
the existing solver and reviewer retain their vetoes, scope assessment and
difficulty assessment. Their output cannot replace compiled teaching. Other
subjects keep the prose route. Invalid numerical specifications are rejected,
never silently repaired or interpreted as prose.

`jobs-draft.json` contains three prospectively selected, normalized requests for
five questions each: exact rational arithmetic and explicit bounded conditions;
Python expressions; and a mixed arithmetic/English request with a real two-skill
allocation of three arithmetic and two English items. All request difficulty 2
or above. The arithmetic scope deliberately matches the compiler's supported
task family; this is not evidence about mathematical word problems or all goals.

Run each independent job once through actual `_generate_sanitized_questions`.
The runtime owns its normal top-ups, rejection handling and partial returns.
Each job gets six provider reservations and a fresh 240-second deadline; the
entire trial is capped at 18 calls. Use the actual runtime client factory so its
100-second read ceiling shrinks with the remaining job time, with a three-second
connect timeout and one SDK attempt. There are no harness retries, replacement
jobs, repair calls or follow-up model judgments.

Proposed settings: native transport, `QUESTION_AUTHOR_MODE=mixed_quantitative`,
existing reviewer-written mode, Kimi K2.5 author with thinking disabled,
6,000 tokens and temperature 0.2; Sonnet 4.6 solver/reviewer with adaptive/high
reasoning and 16,000 shared tokens, omitting temperature. No fallback model,
guardrail override or production environment changes. The candidate's default
author mode remains prose.

Prospective requirements:

- At least 14 of the 15 planned questions returned, at least four in each job,
  within the actual per-job deadline and call budget.
- At least six returned compiled questions: at least four from the quantitative
  job and at least two from the mixed job. The mixed job must also return at least
  one English prose question with the correct assignment. Python questions must
  test Python semantics, rather than being replaced by pure arithmetic.
- Every returned item has one correct exact key, distinct and plausible choices,
  sufficient premises, assigned subject/objective fit, independently assessed
  difficulty, and supported main/per-choice feedback. Uncertainty fails the item.
- Each returned compiled item's exact five learner fields reproduce from its
  original accepted author specification and survive unchanged through release;
  reviewer prose and author-provided policy metadata cannot establish provenance.
- All calls and raw failures are preserved. Routine model/provider failures end
  only the affected runtime operation; the next fixed independent job still runs.
  Credentials/setup, source/request/provenance drift or actual budget violations
  stop globally. Failed and unattempted items remain in the 15-item denominator.
- Private solver reasons, field-length rejection rates, schema support, stage
  latency, token usage and mode selection are separate diagnostics. They cannot
  substitute for checking returned learner content. Missing timeout usage is
  unknown, not zero.

The final capture must retain initial and dynamic provider requests, visible
responses with native reasoning/signatures omitted, actual SDK configuration,
reservation/call accounting, runtime returns and independent content review.
Source and request pins are checked before/after dispatch and at completion.
Freeze and execution create exclusive files; an existing capture cannot resume.

This trial qualifies only the tested candidate and these three fresh batches.
It cannot establish an error rate for arbitrary topics, deterministic model
judgments, or successful deployed queue/inventory operation. A favorable result
does not erase any earlier failed audit or authorize deployment.
