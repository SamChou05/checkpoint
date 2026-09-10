# Solver-order comparison preparation

This directory contains synthetic educational evaluation material only. No
provider inference has run for this comparison. Read the
[prospective protocol](../../QUESTION_SOLVER_ORDER_PROTOCOL.md) before execution.

`control-packet.json` contains only the eight batch IDs and exact source-bearing
subjects. `control-review.json` was written by a separate assistant that saw this
packet without fixture keys, expected judgments, historical responses or other
assessments. Its original file and packet hash are preserved unchanged.

Root compared all 88 exact choice strings and the option-level assessments. All
20 scored subjects agree with the fixture; the two ambiguity cases remain
unscored. The independent reviewer also executed the Python controls locally.
No model correctness result follows from these prepared control judgments.

The experiment uses the existing bounded observer and current native provider
adapter. Production prompts, contracts and admission rules are unchanged. The
shared observer now records an attempted job's operational failure instead of
leaving it marked unattempted; completed provider evidence is preserved if later
content assessment fails.

Verification: 11 focused ordering-runner tests and the final 1,132-test backend
suite pass. Tests cover exact request/schema differences, hidden answer keys,
unchanged vetoes, malformed-batch accounting, independent assessment binding,
frozen-plan tampering, duplicate execution, unknown usage, and failures before
or after provider completion. Ruff and diff checks pass. Separate code review
found no remaining blocker. These checks establish experiment integrity, not
whether explanation-first output improves live question correctness.

The [prepared plan](prepared-plan.json) and [manifest](manifest.json) freeze
source `41970660b089b1864f75ab6b62b3f17ce1567b05`, 70 source files and 32 exact
requests. Planned total input is 218,876 UTF-8 bytes; the canonical plan hash is
`d2293b2ec2d290d3af72f6aa2459cd0cc866d8e35f5af816fbcd3a34add396e7`.
Both the original and archived plans passed `load_frozen_plan` validation.

Execution uses the original
`/tmp/checkpoint-solver-order-plan-20260910/plan.json`. Its execution claim was
absent at preparation completion. The archive is evidence, not a new execution
identity to bypass an existing claim. A second read-only access check still
reported an expired AWS session. Renew access before one bounded live trial;
do not infer that a model experiment ran from a prepared plan or passing tests.
