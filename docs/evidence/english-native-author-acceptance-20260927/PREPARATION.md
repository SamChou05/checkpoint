# English partitive and each native-author acceptance probe

This directory prepares an **author-only, one-call** acceptance trial for the
mapped five-slot native route. Its source candidate is `cfad5e5`. The final
plan will be frozen only after the partitive and each candidate lands in the
clean integration checkout; this preparation has made **no AWS calls**.

The real source currently emits native contract
`question_author_constructed_mapped_families_v10_n5_56d4204a9b0238f6`
with a 2,226-byte schema, SHA-256
`3ac240ae33163d16481c18a9eb8d1032404e5f06bf30cdac4a96304ff637edda`.
Slot 3 allows the partitive scenes; slot 4 allows the compound `each`
scenes. The exact five-task request reuses the already qualified synthetic
3:2 mapped goal. The production prompt permits these scenes without forcing
them, so a live run may choose different English scenes.

`probe.py` reconstructs the production author contract and Converse wire,
validates its JSON Schema and Botocore request shape, then sends that exact
wire to a socket-free fake provider. The fake response selects
`partitive_paint` at slot 3 and `compound_guides` at slot 4 and runs through
the **same** native adapter and mapped compiler as the live response. The
offline result is five compiled rows (three numeric, two English), with zero
compiler failures. `test_probe.py` checks the slot allowlists and interrupts a
blocking sleep using the same process-wide timer used by execution.

The future live run is reserved for one STS identity call and one Converse
call, one SDK attempt each, no retry, fallback, repair, top-up, worker, queue,
bank, deployment, or GitHub write. A 120-second process-wide hard deadline
begins before credential export; the Converse socket read limit is 90 seconds.
Execution creates a one-shot capture before exporting credentials and requires
both root and independent exact-hash GO in `review-approval.json`. No live
execution should occur until source commit, schema, prompts, wire, harness,
and plan hashes are frozen and reviewed.

This trial can show whether Bedrock accepts the v10 schema and what the model
selects in one response. It cannot by itself establish full-worker yield,
blind answer correctness, or repeated-bank diversity.
