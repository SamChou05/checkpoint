# Closed quantitative families for the mapped pilot

The latest five-question worker trial returned sound keys and distinct options,
but an independent blind reviewer rated one arithmetic expression level
1 against a requested minimum of 2. Its first two arithmetic items also shared
the same short expression format. This source-only prototype changes the
numeric authoring task in the exact mapped 3:2 pilot: slots 0, 1 and 2 use
different closed families rather than model-written expression graphs.

The model supplies only a family label fixed by the original slot and two
bounded integers. Code expands slot 0 to an exact two-fraction expression,
slot 1 to a linear equation with a unique solution in an explicit integer
domain, and slot 2 to the first integer satisfying a bounded ratio threshold.
The ratio family was added after a source audit found the initial linear
inequality family too similar to the equation family; both could have the
same key and choice set for the same operands.
The existing quantitative compiler derives the stem, four distinct choices,
answer, main explanation and per-choice feedback. The model cannot supply a
key, choice, domain, graph or learner text. Existing blind solving, immutable
review and private provenance checks still apply. The English agreement slots
and their full-bank history/fingerprint selection are unchanged.

Fresh numerical operands are retained. If a compiled prompt is in recent or
reported history, existing bank coverage, or the blocked fingerprint set,
code searches unused parameter pairs in that same original slot and family.
Each replacement passes the compiler and private proof. Exhausting a family
fails the one-pass batch explicitly without another provider call.

`QUESTION_MAPPED_QUANTITATIVE_FAMILIES=enabled` requires the mapped agreement
route, its exact goal and full-request hashes, the pinned arithmetic objective,
native transport, constructed quantitative authoring, immutable feedback,
minimum difficulty 2 and no fallback. The flag defaults to `disabled` and is
not present in SAM or the deployment workflow. The previous mapped agreement
schema and prompt hashes are unchanged. This option is not deployed; one
full-request hash does not authorize subsequent refill states with changed
history.

Offline verification compiled all 208 allowed operand combinations and checked
that each has exactly four distinct choices, one matching expected answer and
recomputable feedback. A fake-provider five-slot pass used three calls and
retained the original slot assignments, quantitative/English private proofs,
answer-blind solver and final reviewer. Another pass checked full-bank
agreement history and blocked fingerprints. The 1,578-byte native author
schema passed JSON Schema and botocore Converse-shape validation. The complete
backend suite passed 1,419 tests and 4,800 subtests; no new Ruff findings or
`git diff --check` errors were introduced.

These checks establish finite-domain construction and integration behavior.
A [bounded live worker trial](evidence/mapped-quant-families-qualification-20260927/RESULTS.md)
accepted the schema and returned all five original slots in three calls. Two
independent blind reviewers chose every code-supported key, found all 30
within-item choice pairs distinct and rated all five items level 2. All 25
learner fields recompiled exactly and the teaching passed post-lock review.
The trial used empty bank history; the English pair remained similar in
format. One passing sample does not establish repeat reliability, broad topic
coverage, or deployment readiness, and finite inventories can exhaust.
