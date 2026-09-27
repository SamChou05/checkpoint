# Closed English agreement constructor (unqualified opt-in)

Open prose authoring can omit an edit target, assert an unsupported grammar
rule, or offer two defensible answers. A strict JSON schema can require four
strings and a key, but cannot prove their meanings. This prototype replaces
model-authored English learner text with a closed task: the model chooses only
an enumerated scene and clause order. Code owns the two clauses, four ordered
verb-form pairs, unique key, main explanation and feedback for every choice.

The exact mapped 3:2 route uses quantitative tasks in original slots `0`–`2`.
Slot `3` has proximity, inverted-subject, and relative-clause scenes.
Slot `4` has compound/distributive, `a number`/`the number`,
either/or-neither/nor, and -ing-activity-subject scenes. The last family asks
the learner to distinguish a singular activity from a plural noun subject;
its two order variants use different clauses rather than mirroring one pair.
[Cambridge's gerund entry](https://dictionary.cambridge.org/us/dictionary/english/gerund)
gives an -ing activity as the subject of a singular clause. The current
library has 24 exact stems for slot `3` and 32 for slot `4`. Each task's four
choices are the Cartesian product of the two
verb inflections, with exactly one pair agreeing in both clauses. The new
provider schema requires all five original slots, fixes the English scene
enums by slot, and excludes author keys, choices, teaching and metadata.
Its compact shared-definition representation is 3,060 bytes for the mapped
agreement schema and 2,101 bytes with closed numeric families. Local validation
rejects missing, extra, duplicated, forged and swapped English tasks before
compilation; no failed slot is relabeled as a top-up.

`QUESTION_MAPPED_AGREEMENT_TASKS=enabled` selects this route only after the
existing exact goal digest and full normalized request scope match, with native
constructed authoring, immutable feedback, no fallback and difficulty 2. It
defaults to `disabled`; the prior compact v1 schema and prompt SHA remain
unchanged. The server injects skill/objective assignments from the trusted
request. A private exact-type sidecar retains each English source ordinal and
recompiles its complete learner payload after sanitization and final audit.
When the exact route is selected, code prefers an unused solve mechanism,
then an unused scene, using the request's recent prompts and a bounded
56-variant identity set from the full stored bank. Client-blocked stem
fingerprints also veto matching variants.
The selected task and its source are retained in private provenance. This
does not make the finite bank broadly diverse: the same two-blank format and
clause-order reversals remain, and a single pinned full-request SHA matches
only one request state, not later refills whose history has changed.
The agreement questions still undergo answer-blind complete-choice solving,
all six pair judgments and immutable final review. Models may veto on validity,
key disagreement, unsupported teaching or reported issues, but cannot overwrite
the code-owned key, teaching or calibrated difficulty 2. The reviewer's
difficulty estimate remains present in its response. Only an estimate of 3 is
advisory for a revalidated private agreement proof; estimates of 1, 4 or 5
still veto. A content-free quality metric counts admitted disagreements.
Ordinary prose and quantitative rows keep their existing assessed-difficulty
rules. Proven agreement rows receive explicit policy revision 10; quantitative
proof remains revision 8, and ordinary prose without the private agreement
proof remains revision 7.

The smaller schema was accepted in one frozen live worker trial (capture SHA-256
`2bcb9b577d165b508debe70cf6d42b2cf749f006c03922650b9d154eab8ca251`).
The worker returned only 3/5: both English items were rejected solely because
the immutable reviewer rated difficulty 3, while marking them valid with the
correct keys, supported explanations and no issue flags. Two independent
answer- and arm-blind content reviews rated all five pre-review drafts level 2
and found their keys and alternatives sound. That evidence motivated moving
the bounded English difficulty decision into the same closed constructor that
owns its content. The subsequent [bounded full-worker trial](evidence/agreement-difficulty-calibration-qualification-20260927/RESULTS.md)
returned 5/5 original slots, and two independent answer-blind reviewers
selected all five keys and found all 30 within-item choice pairs distinct.
Both reviewers rated the simple compound/`every` item level 1, below the
requested minimum of 2, so the prespecified content gate failed at 4/5.
They also found limited variety across fraction tasks and agreement frames.
The [keyless offline preflight](evidence/agreement-v2-grammar-preflight-20260927/RESULTS.md)
of the strengthened frames found 16/16 unique keys and standalone level-2
ratings from each of two independent reviewers, but both flagged low bank
novelty. A [new bounded full-worker trial](evidence/agreement-grammar-frames-qualification-20260927/RESULTS.md)
returned 5/5 original slots in three calls. Both blind reviewers selected all
five keys and rated the two strengthened agreement items level 2, but one
reviewer rated a simple quantitative expression item level 1. The strict
five-item content gate failed at 4/5. The route remains inactive while math
task-family variety and difficulty are addressed.
The expanded two-mechanism-per-slot English set also passed an
[eight-item blind offline preflight](evidence/english-structure-preflight-20260927/RESULTS.md):
two independent reviewers chose all eight code-owned keys and rated each
question level 2, while finding strong repetition within the same mechanisms.
Neither trial nor the source change authorizes deployment. Worker-only
SAM and workflow settings exist but default to disabled with empty scope
hashes; the deployed worker does not use this route. Code-owned answers in
this subset do not prove broader language correctness, distractor usefulness,
calibration across learners or non-repetition.

The subset excludes pronoun reference, collective nouns, existential
agreement, tense choice, irregular verbs, free language and difficulty 3–5.
Repeated inventory could become predictable. Slots `3` and `4` have three
and four solve mechanisms, respectively. The fourth five-item chunk must
reuse a mechanism in slot `3` even if its exact scene and stem are new;
slot `4` reaches that limit in its fifth chunk. Larger or more varied
inventory needs independent linguistic and novelty review.

Offline tests cover closed schemas, immutable old-route hashes, fake native
author/solver/reviewer calls, exact 3:2 slot provenance, private-proof loss and
tampering, all 24 display permutations, and solver/reviewer key disagreement.
They also check reviewer difficulty disagreement against proven English and
ordinary unproven prose separately. Full-history identity and blocked-fingerprint
controls cover the finite 56-variant library. These are implementation evidence
only.
