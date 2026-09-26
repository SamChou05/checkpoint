# Frozen source-claim challenge, eval only

This optional offline adapter challenges an unchanged multiple-choice question
against exact captured source spans. It does not change generation, production
verification, bank admission, native schemas, defaults, or policy revisions.
There are no provider calls in this milestone.

`evals/source_claim_challenge.py` builds on the existing acquired-source packet
and split answer/teaching review. The caller supplies zero-based, end-exclusive
boundaries for stem segments and main-explanation claims. Those boundaries must
partition every character of each original field without overlap or omission;
each segment must contain non-whitespace text. The caller labels stem segments
`premise` or `task`. The server assigns `P1...` to premises, `T1...` to task
segments, `M1...` to teaching claims, `A...D` to the four rotated choices, and
`AB...CD` to their six unordered pairs. The source unit IDs, exact text, capture
metadata, offsets and hashes come from the existing adapters. Neither model
role receives the author key, historical verdicts, or the other role's output.

The choice role must assess each premise and choice as supported, refuted or
uncertain, report any missing conditions, and compare all six answer meanings.
The teaching role must assess each proposed claim and rate difficulty. Every
reported source unit ID must exist in the frozen packet. The local gate rejects
missing or unexpected identities, malformed judgments, nonempty missing
conditions, uncertain premises or choices, zero or multiple supported answers,
equivalent or uncertain choice pairs, answer disagreement, unsupported teaching,
reported issues and insufficient difficulty. It also withholds eligibility when
any captured source is truncated or a selected span omits other captured text.
Malformed model output is a format failure, never a credited factual catch.
The returned question is the unchanged whitelisted original, with no new stamp.

The caller's claim segmentation is **not** a proof of semantic atomicity. A
single segment can hide two assertions, a task segment can hide a presupposition,
and exact source-unit identity does not prove a source entails the declared
status. Captures are caller-owned; their hashes detect mutation of supplied
records but cannot establish source authority or authenticity. Even a complete
text extraction can omit layout, media, dynamic content, or applicable external
exceptions. The [irrelevant-source regression](../backend/bedrock-question-service/tests/test_source_claim_challenge.py)
intentionally demonstrates a structurally eligible but factually unsupported
model declaration. Thus `eligible` means only that the stated local and declared
gates passed. No output is a correctness certificate.

Offline adversarial tests cover exact partition and unchanged-content binding,
role isolation, malformed or unknown IDs, missing conditions, false premises,
multiple/uncertain answers, equivalent choice meanings, wrong teaching claims,
source/hash or observation mutation, partial/truncated evidence, and a valid
insufficient-information answer. The original acquired-source and split-evidence
test groups also remain unchanged.

Before considering any live call, freeze the exact question/capture/segmentation
plan and independent assessments. Include the prior dough and butter defects,
supported hotel and plant controls, all-pairs and RAW task-presupposition cases,
and fresh questions from unrelated goals. Score literal answer choice, every
material teaching assertion, missing conditions, distractor meaning, difficulty,
false exclusions, format failures and timing separately. Inspect each declared
source relation against the actual captured passage; a matching ID alone earns
no factual credit. No production integration follows unless the full prospective
criterion demonstrates genuine defect catches while retaining the valid controls
and accurate teaching on fresh items. That later trial must declare call/byte/time
limits and source rights before dispatch.
