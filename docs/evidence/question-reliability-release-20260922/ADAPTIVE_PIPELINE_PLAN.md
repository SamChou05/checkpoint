# Fresh adaptive worker pipeline qualification

The isolated adaptive solver passed all frozen labels on twenty reused controls,
but took 23.680–49.392 seconds per call and retained three inaccurate explanatory
embellishments. The preceding disabled full pipeline produced 29/30 accepted rows,
but independent audits found content/feedback issues. Neither result is replaced
or relabeled by this trial.

The reviewer data-omission experiment failed, so this candidate keeps the current
reviewer architecture and solver evidence. It includes the finalized local answer-
reference guard, which distinguishes bare answer positions from signed, decimal,
percentage, fraction and thousands-formatted numeric quantities.

## Frozen scope

Generate six fresh batches of five questions using the exact domain requests from
`pipeline-plan-v2.json`: everyday arithmetic, Python3 expressions, English usage,
quantitative evidence, fictional access rules and physical quantities. Request
minimum difficulty2 and preserve the same prospective criteria: at least3 accepted
per domain and27/30 overall; every accepted item has four meaningfully distinct
answers, exactly one correct keyed answer, sound bounded main/per-choice feedback,
no unstated material assumptions or silent repairs. Independent manual review treats
uncertainty as failure. Previously accepted questions are not reused or offered as
model examples.

Use actual production generation, solver and review routing with native authorv3,
solverv3 and reviewerv1. Kimi author thinking stays disabled, temperature0.2 and
6,000 output tokens. Sonnet verification uses adaptive/high, no temperature and
16,000 shared reasoning-plus-final output tokens. No production defaults change.
At most two application passes and six provider calls per job;36 total. No extra
retries, replacement jobs, repair calls or follow-up model judging.

## Real worker deadline behavior

Each job gets a fresh240-second context and shared `ProviderCallBudget(6)`.
Pass no prebuilt client into generation. Instead, wrap the actual production
`_bedrock_client(call_budget)` factory, creating an SDK client for each call from
the current remaining time. The runtime caps its read timeout at75 seconds and
shrinks it when needed, reserving connect/setup/return time. A3-second connect
limit and exactly one SDK attempt apply. The runtime then rechecks actual client
timeouts after setup, before consuming a provider slot and dispatching.

The recorder exposes real SDK metadata to that check. Record remaining milliseconds
at dispatch/return, actual connect/read timeout, minimum admitted time, provider
slot count, network time, usage, schema outcome and final partial yield. Client
admission failures, transport errors, truncation, stage-coverage failures and semantic
rejections remain distinct. Stop all later dispatches after a transport failure or
non-end-turn completion, as in the earlier plan. Retain every attempted response
and every unattempted job in the planned denominator.

Provider responses are returned unchanged to production code. Saved captures omit
all `reasoningContent` blocks, including text/signatures, and record block counts
only. Final JSON reasons and feedback remain available for audit. Credentials are
loaded into memory and never written to artifacts or environment files.

## Offline verification before freeze

The no-network test invokes actual production request construction, SDK factory,
and admission checks. At240,60 and10 seconds remaining, observed read limits are
75,53.999 and3.999 seconds. With5 seconds left, the call is rejected before SDK
setup. A simulated setup delay from10 to6 seconds is rejected by the second check
before network dispatch or budget consumption. A seventh invocation is blocked
after six synthetic dispatches. SDK retries remain exactly one; adaptive request
fields and reasoning-block redaction are verified.

`--preflight` does not create a plan or call a provider. `--prepare` freezes source,
requests, environment, dependencies, contracts, these criteria and offline results
only after the candidate is selected. Parent review of that frozen hash is required
before `--execute`. Outcomes will be descriptive bounded evidence, not a population
error-rate estimate or proof of deterministic semantic correctness.
