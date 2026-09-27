# Trial 04: five verified worker returns; blind content gate pending

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

This is a **machine-positive one-batch result**, not yet a content pass. A
source-order-blind [worksheet](worksheet.json) of the five returned questions
is frozen at SHA-256
`66c97dadd139c87ba51f7f191a1883b0c3fdd17c82bca26550c49fc4e1e40cbb`.
Its private key map is outside Git with mode `0600`. Two independent keyless
reviews and a post-lock teaching audit are pending. The provider reviewer
accepted these five, but independent review still determines whether their
keys, distractors, difficulty, self-containment, and cross-item variety meet
the predeclared content gate. One pass also cannot establish repeated-bank
reliability.
