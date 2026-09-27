# Closed quantitative families for the mapped pilot

The latest five-question worker trial returned sound keys and distinct options,
but an independent blind reviewer rated one arithmetic expression level
1 against a requested minimum of 2. Its first two arithmetic items also shared
the same short expression format. This source-only prototype changes the
numeric authoring task in the exact mapped 3:2 pilot: slots 0, 1 and 2 use
different closed families rather than model-written expression graphs.

The model supplies only a slot-specific closed family label and two bounded
integers. Code expands slot 0 to either a two-fraction sum scaled by three or
a fraction quotient plus one; slot 1 to a linear or quadratic equation with
one solution in an explicit integer domain; and slot 2 to either the first
integer satisfying a ratio threshold or the last integer within a quadratic
product bound.
The ratio family was added after a source audit found the initial linear
inequality family too similar to the equation family; both could have the
same key and choice set for the same operands.
The existing quantitative compiler derives the stem, four distinct choices,
answer, main explanation and per-choice feedback. The model cannot supply a
key, choice, domain, graph or learner text. Existing blind solving, immutable
review and private provenance checks still apply. The English agreement slots
use their own closed scene inventory and full-bank history/fingerprint selection.

The selector counts each family's use in recent prompts, blocked fingerprints,
and a private projection of all 416 canonical numeric stems in the durable
bank. It prefers the less-used solve mechanism in each assigned slot and then
an unused parameter pair. Every replacement passes the compiler and private
proof. Exhausting both families in a slot fails the one-pass batch explicitly
without another provider call. This prevents exact numeric stem reuse beyond
the recent-30 context, but a third chunk must reuse each slot's solve
mechanism because only two are available.

`QUESTION_MAPPED_QUANTITATIVE_FAMILIES=enabled` requires the mapped agreement
route, its exact goal and full-request hashes, the pinned arithmetic objective,
native transport, constructed quantitative authoring, immutable feedback,
minimum difficulty 2 and no fallback. The worker-only SAM/workflow setting
`QUESTION_BANK_WORKER_MAPPED_QUANTITATIVE_FAMILIES` defaults to `disabled` and
requires enabled mapped agreement. The prior compact v1 route is unchanged;
both opt-in mapped schemas and prompts are versioned for the expanded families.
This option is not deployed; one full-request hash does not authorize
subsequent refill states with changed history unless the explicit
`refill_history` scope mode is configured with its own scope hash.

Offline verification compiled all 416 allowed family/operand combinations and checked
that each has exactly four distinct choices, one matching expected answer and
recomputable feedback. A fake-provider five-slot pass used three calls and
retained the original slot assignments, quantitative/English private proofs,
answer-blind solver and final reviewer. Another pass checked full-bank
agreement history and blocked fingerprints. The 1,802-byte combined native
author schema passed JSON Schema and botocore Converse-shape validation. The
source also simulates eight repeated 3:2 batches without exact numeric stem
reuse; this is an offline test, not a live repeated-bank qualification.

These checks establish finite-domain construction and integration behavior.
A [bounded live worker trial](evidence/mapped-quant-families-qualification-20260927/RESULTS.md)
accepted the schema and returned all five original slots in three calls. Two
independent blind reviewers chose every code-supported key, found all 30
within-item choice pairs distinct and rated all five items level 2. All 25
learner fields recompiled exactly and the teaching passed post-lock review.
The trial used empty bank history; the English pair remained similar in
format. One passing sample does not establish repeat reliability, broad topic
coverage, or deployment readiness, and finite inventories can exhaust.
