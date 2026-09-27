# Combined v12 native-author acceptance probe

This directory prepares one **author-only** Bedrock acceptance attempt for
integrated source commit `254d8af2f78b5f3b0e27c5b854e159ca21ac9391`.
Preparation made **no AWS calls**. It does not change the worker, question
bank, deployment, or the earlier immutable evidence.

The frozen [plan](plan.json) SHA-256 is
`663bea09f568c49e1e20adf543c61178d28963b8161f6ff299c1dea929902a7b`;
the [harness](probe.py) SHA-256 is
`872ccfe4a470430eb25377812dc0236a0d856addc7842709d67c9bb11a9a84c0`.
The exact production author wire SHA-256 is
`0317c2b75115c309232c02e6eddcedd230461fc63f5d18da7312502868092a0a`.
The system and user prompt SHA-256 values are
`3bd6e28e9cacb12b8fdec9d34d4ca6410e81f86020c76fdbd48c9e4ee41ec4f6`
and `fb4a783e3e205d08ddf87f6595da72c78c6117be7caddb3b33da83bf49fae4d4`.
The native contract is
`question_author_constructed_mapped_families_v12_n5_56d4204a9b0238f6`.
Its 2,357-byte schema has SHA-256
`495db717d6b3fd6cc5272cdb289c7d77d9ca2e275b7c1d3f0cb856c1a18b6934`.

The request is the same synthetic five-task 3:2 arithmetic/English goal used
for prior qualifications. The production prompt permits the new task families
and scene, but does not force them. A live response may choose other permitted
values. The socket-free fake provider chooses
`bounded_quadratic_exclusion_count` in slot 1,
`bounded_centered_square_count` in slot 2, and `select_library` in slot 4.
Slot 0 chooses `fraction_product_complement` and slot 3 chooses
`partitive_paint`. It verifies the real production wire builder sends the
frozen wire, then runs the real native adapter and mapped compiler: five rows,
three numeric proofs, two English proofs, zero failures.

The live operation is limited to one STS identity call and one Bedrock Converse
call with one SDK attempt each. The 120-second process-wide hard deadline starts
before credential export. Socket connect and read limits are 3 and 90 seconds.
The credential expiration must be at least 150 seconds after Converse dispatch,
using the same single CLI export snapshot that supplies the session. The probe
creates a one-shot capture before AWS access and will not resume or retry it.
No fallback, repair, top-up, queue, bank, deployment, or GitHub write is in
scope. Execution requires `review-approval.json` containing exact matching
plan and harness hashes plus both root and independent GO. That file must only
be created after review; it is not included in this preparation commit.

Five socket-free tests passed, including production-wire interception, JSON
Schema and Botocore shape checks, fake compilation, alarm interruption, and
near-expiry fail-closed behavior. Ruff and `git diff --check` passed.

One live call can establish whether Bedrock accepts this v12 schema and whether
that model response compiles. It cannot qualify repeated full-worker yield or
bank-level question diversity. Those require separate tests.
