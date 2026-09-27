# Closed-bank solve signature experiment

This is an offline, fail-closed **candidate**, not an enabled production gate.
It tests the current source at `3456177` against the immutable
[English-each 20-item worksheet](../english-each-contrast-20260927/worksheet.json)
and both locked, answer-blind 190-pair reviews. Run
`python3 docs/evidence/solve-signature-gate-20260927/probe.py` to regenerate
the [machine report](report.json). No model, AWS, queue, bank, or deployment
call occurs.

The candidate signature reads the **actual code-constructed numeric graph**.
For exact expressions it records the operator tree with numeric literals
erased. For bounded scalar conditions it records the integer domain, relation,
polynomial degree, and whether a variable appears in a denominator. It
deliberately omits final `minimum`/`maximum`/`count` selection: finding the
same boundary before choosing the maximum or counting values was one of the
reviewers' strongest repetitions. Provider family names and prompt words do
not determine the signature. The probe verifies that all **832** currently
compiled numeric variants retain a stable signature within their constructed
mechanism.

Across the 190 pairs in **each** blind review, the only pairs that this
signature would block are the same two pairs both reviewers rated highest:

| Pair | Shared compiled kernel | Blind-review rating |
| --- | --- | --- |
| Q05/Q06 | Quadratic equality over bounded integers | strong / high |
| Q11/Q16 | Linear `≤` inequality over bounded integers | strong / high |

It does not block any reviewer-rated moderate, low, or unrelated pair in this
frozen sample. This is evidence for this closed inventory, not a general
semantic-equivalence guarantee. For example, a new graph transformation that
changes the algebra but preserves the solve process would need a new review.
No English solve gate is proposed: the reviewers found no consensus strong
English pair, and sentence-scene categories alone would be an unproved proxy
for grammatical reasoning.

A strict one-use-per-signature replay admits the first **15 complete items**
and rejects batch 4: Q05 repeats the prior quadratic-equality kernel, and Q11
repeats the prior linear-upper-bound kernel. Each of slots 1 and 2 has only
**three** distinct compiled solve kernels, so 15 complete items is also the
hard upper bound for this five-slot bank without repeating one. Thus the
maximum possible complete yields at targets 20/40/80 are **15/15/15**, with
minimum underfills **5/25/65**. These are capacity bounds and a frozen 20-item
replay, not live worker measurements. Silently falling back to an already-used
signature would hide the defect; retrying the same finite inventory would not
create a new solve mechanism.

To enable this safely, the durable history projection can map every recognized
closed numeric stem to its compiled graph signature, and the selector can
exclude all previously used signatures before ranking candidates. Exhaustion
must be surfaced as an underfill or hard failure rather than an automatic
repeat. The current bank needs more independently reviewed solve mechanisms
in slots 1 and 2 before a 20-item strict bank is achievable; 40 or 80 would
require many more than this finite pilot supplies.

Validation: exact locked worksheet SHA comparison; two full 190-pair joins;
832-variant signature scan; frozen four-batch replay; Ruff; `git diff --check`.
