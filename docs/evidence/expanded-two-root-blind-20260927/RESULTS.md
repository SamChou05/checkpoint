# Expanded two-root questions: locked blind review

The earlier 20-item bank review rated a factored `bounded_two_root_minimum`
question below its requested 2–3 difficulty: the factors displayed both roots.
Commit `c6259df` now presents the same code-owned equation as an expanded
quadratic, proves its roots before teaching them, and projects old factored
stems onto the new historical identity so a source upgrade cannot repeat an
older bank item. Commit `9c4b58a` separately adds a domain-wide uniqueness
proof for the `bounded_quadratic_equation` family after the live worker's
reviewer rejected its short substitution-only explanation.

An independent reviewer saw only the [keyless worksheet](worksheet.json),
SHA-256 `fc34d0dd16f21923af2cfeb1a3e0467d0b8be00f13b9a72ff56caa6aa97b82d6`.
The [locked review](blind-review.json), SHA-256
`8532f18a5101fc39d25151db9ca4f97ad24ca02c989224123f93d2beb7ef2890`,
preceded release of the [answer map](answer-map.json), SHA-256
`088548affcc808a5f9fece8ccda16042d9f5a6cc9a014048ea5ef8449c909cc9`.
The reviewer independently selected the code-owned key for **8/8** parameter
variants, found all **48 within-item choice pairs** distinct, and rated all
eight items at difficulty 2–3 with feasible teaching. The larger root in each
choice set does satisfy the equation but does **not** answer the explicitly
asked *minimum* question. The post-lock key comparison and all 28 pair rows
were rechecked before archiving.

The reviewer also marked **28/28 cross-item pairs** as reasoning-level near
duplicates: changing coefficients does not make eight successive minimum-root
questions varied. This is a verified improvement to individual difficulty
and teaching, **not** an 8-item diversity pass. The existing family selector
must still space or replace this mechanism across a longer bank.

The native task schema and model system prompt are unchanged. The learner
stems and explanations change, so the prior live full-worker result does not
qualify this source. The backend passed 1,460 tests, Ruff on changed Python,
and `git diff --check`; the live reviewer outcome remains unmeasured after
these two fixes.
