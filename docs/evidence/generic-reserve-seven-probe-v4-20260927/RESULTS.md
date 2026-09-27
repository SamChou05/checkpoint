# Trial 04: five verified worker returns; blind content gate failed

The [frozen plan](plan.json) SHA-256 was
`835f1115960e9da9fa3be7dc0643799986097f1e08f559e1a1a7be7d6454d536`.
The one-shot [capture](capture.json) SHA-256 is
`da76d3c3a1dcfb9faebbc4da9345f2b73188c121ca46e2697233d29f948b0e8f`.
Fresh AWS precheck matched account `239342516379`. The disabled-thinking
Sonnet 4.6 worker finished in **104.193 seconds** with **five** one-attempt
Converse calls: author7, solver4, reviewer4, solver3, reviewer3. Bedrock
accepted all five compact native contracts. All seven author rows sanitized;
the live reviewer rejected source ordinal 0 for `difficulty_floor`, and six
of seven were verified. The worker returned the earliest five accepted
source ordinals **1–5**; ordinal 6 was verified but was outside the requested
five. The return is complete, original-order-preserving, and policy-7. There
was no retry, fallback, top-up, or second job.

This is a **machine-positive one-batch result**, but not a content pass. A
source-order-blind [worksheet](worksheet.json) of the five returned questions
is frozen at SHA-256
`66c97dadd139c87ba51f7f191a1883b0c3fdd17c82bca26550c49fc4e1e40cbb`.
Its private key map is outside Git with mode `0600`. Two independently locked
keyless reviews ([A](review-a.json), [B](review-b.json)) were committed before
opening that map. Both selected the source key on **5/5** returned items and
judged all **30/30** within-item choice pairs meaningfully different. Both
rated public Q03 at difficulty **1**, below the requested level 2, and both
flagged public Q02–Q03 as a strong cross-item repeat: two expected-dollar-value
questions with currency-only answer formats. The map confirmed that Q03 is
source ordinal 5 and Q02 is source ordinal 3; their keys were independently
selected before source positions were revealed.

Post-lock inspection found that all five returned authored explanations state
the decisive calculation or independence comparison and match the mapped
keys. The reviews noted conventional but implicit randomness/fairness in the
card and die stems, plus several weak distractors and a cue in the
independence question. These issues do not change the five selected keys, but
the difficulty miss and strong repetition **fail the predeclared content
gate**. Provider approval was not enough to detect those failures. This
single completed worker batch does not establish repeated-bank reliability,
and the opt-in route must remain disabled by default.
