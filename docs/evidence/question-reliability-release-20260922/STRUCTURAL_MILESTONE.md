# Native structure milestone; semantic qualification remains open

This milestone makes native MCQ structure enforceable and records the remaining
model failures. It does **not** declare semantic qualification, enable a deployed
worker, or raise the client's required policy. The rollout/default changes are a
separate pending milestone.

The native author uses four required choice slots and a key enum. The adapter
derives the exact answer text; prose cannot replace the key. Its versioned schema
writes the stem and explanation before the key. Historical schema bytes remain
unchanged. The controlled ordering comparison observed three plainly wrong keys
in the sorted arm, versus no plainly wrong keys and one ambiguous recipe in the
ordered arm; this small comparison does not establish general accuracy.

The native independent solver now has exactly four judgment slots and six fixed
unordered-pair slots. Trusted input supplies the pair endpoints; decoding maps
them back to exact choice bytes. Missing, extra, reversed and self-pair identifiers
cannot satisfy the closed schema or local parser. Slot order depends on stem and
choice bytes, never the authored key. The older path already rotated choices;
the new invariant removes its residual dependence on incoming key-first order.
Reasons precede verdicts in the native schema. Application code still vetoes
zero/multiple supported choices, uncertainty, key disagreement, and declared
equivalent choices before final review.

Only the complete native slot/pair path followed by a successful final review
earns policy revision 4. Legacy complete-choice generation stays at 2; optional
authored-teaching mode stays at 3. The public wire version remains 1. Claiming or
replaying stored inventory never upgrades its stamp or rewrites its content.

Verification: the full backend suite passes **1,124 tests**; Ruff, compilation,
SAM lint, deployment-script tests and the noncontainer SAM build pass. All 23
service modules match each of the three built artifacts, whose pinned SDKs each
validate all ten registered native request shapes (30 checks, no provider calls).
The separate policy-4 client candidate passes the full iOS suite (1,054 total,
three existing skips, zero failures), but is held pending quality qualification.

The latest twenty-control solver trial kept ten valid items and excluded ten bad
items, with 80/80 correctness labels. Its **strict criterion failed**: 116/120
pair labels were correct; four mislabeled pairs belonged to already rejected
questions. All earlier failed and stopped trials remain unchanged. See
[endpoint results](../choice-quality-release-20260922/ENDPOINT_RESULTS.md).

The subsequent frozen six-domain diagnostic made 30 provider calls and returned
29 of 30 requested questions. It met the prospective yield threshold, but
independent review found admitted teaching errors, an explanation referring to
choice position despite shuffling, and an English punctuation item with more
than one defensible answer. The all-admitted-content criterion therefore
**failed**. Raw attempts, refusals/rejections, top-ups, and audits are retained in
this directory. Finishing a capture is not the same as passing qualification.

Remaining work concerns fallible semantic judgments and final-review feedback,
including erroneous solver reasons copied by the final reviewer. This evidence
supports the deterministic transport/admission improvements; it does not support
claiming deterministic factual correctness or treating the release as qualified.
