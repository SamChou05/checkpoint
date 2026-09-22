# Native author v2: bounded structural qualification

Two authorized Kimi K2.5 calls produced five applied arithmetic/logic questions and five Python expression/control-flow questions. Both used the actual default author prompts, the fixed-slot native v2 override, temperature 0.2, thinking disabled, a 6,000-token cap, and a 75-second read timeout. The immutable [plan](plan.json), [capture](capture.json), and [runner](author_probe.py) preserve requests, raw responses, source hashes, and per-item admission results. No retries, repair, fallback, solver, final reviewer, bank writes, or deployment occurred.

| Frozen criterion | Result |
| --- | --- |
| Normal completion and strict native schema/adapter validity | 2/2 calls |
| Exactly five items per call | 2/2 calls |
| Four distinct visible choices and exact answer-slot mapping | 10/10 items |
| Difficulty 2 or 3 | 10/10 items |
| Existing sanitizer retained item | 10/10 items |
| Choice and answer text unchanged by sanitizer | 10/10 items |
| All original display bounds satisfied | **8/10 items; failed** |

The complete prospective qualification therefore **failed**. Arithmetic item 2 had a 547-character explanation; Python item 2 had a 783-character explanation. The existing sanitizer clipped both to 420 characters. Their raw explanations contain abandoned calculations or expressions and explicit self-correction, so admission must not be mistaken for validated teaching. The capture records the clipping, choice reordering, and removal of optional metadata for requests without a skill map.

Manual inspection also found a definite semantic defect before independent review: arithmetic item 3 asks how much concentrate must increase when a constant-ratio mixture grows from 12 to 20 liters. Concentrate grows from 9 to 15 liters, an increase of 66⅔%. None of its choices—15%, 20%, 25%, or 30%—is correct; the authored key is 25%. A slot enum guarantees that the key names an offered choice, not that this choice answers the question.

Offline replay independently validated both raw outputs against their frozen JSON Schemas and reproduced the exact runtime adapter and sanitizer results. The calls consumed 3,968 input tokens and 2,248 output tokens, taking 16.116 and 16.920 seconds. The capture SHA256 is `7179e9454e059e5fc33b540d192e2abf7ade444c49c05d3bfb48730c91fcc5df`.

This evidence supports the representation guarantee of four fixed slots and exact selected-key membership. It does not establish semantic correctness, useful final feedback, full bounds compliance, or deterministic generation. Native production routing still selected author v1 when this probe ran. The later field-order comparison is a separate experiment and does not replace these failed criteria or modify this capture.
