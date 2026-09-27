# Closed English agreement constructor (unqualified opt-in)

Open prose authoring can omit an edit target, assert an unsupported grammar
rule, or offer two defensible answers. A strict JSON schema can require four
strings and a key, but cannot prove their meanings. This prototype replaces
model-authored English learner text with a closed task: the model chooses only
an enumerated scene and clause order. Code owns the two clauses, four ordered
verb-form pairs, unique key, main explanation and feedback for every choice.

The exact mapped 3:2 route uses quantitative tasks in original slots `0`–`2`,
a singular/plural head with an intervening `near` phrase in slot `3`, and a
different compound/distributive mechanism in slot `4` (`Maya and Theo` versus
`Every guest`). Four reviewed proximity scenes vary slot `3`; slot `4` uses one
reviewed scene. Each task's four choices are the Cartesian product of the two
verb inflections, with exactly one pair agreeing in both clauses. The new
provider schema requires all five original slots, fixes the English scene
enums by slot, and excludes author keys, choices, teaching and metadata.
Its compact shared-definition representation is under 3 KB. Local validation
rejects missing, extra, duplicated, forged and swapped English tasks before
compilation; no failed slot is relabeled as a top-up.

`QUESTION_MAPPED_AGREEMENT_TASKS=enabled` selects this route only after the
existing exact goal digest and full normalized request scope match, with native
constructed authoring, immutable feedback, no fallback and difficulty 2. It
defaults to `disabled`; the prior compact v1 schema and prompt SHA remain
unchanged. The server injects skill/objective assignments from the trusted
request. A private exact-type sidecar retains each English source ordinal and
recompiles its complete learner payload after sanitization and final audit.
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
owns its content. The change has only offline tests; the live qualification
gate remains failed until a new bounded worker trial passes 5/5 and two blind
reviews assess all keys, 30 pairs, teaching, scope, difficulty and novelty.
Neither this trial nor the source change authorizes deployment. Worker-only
SAM and workflow settings exist but default to disabled with empty scope
hashes; the deployed worker does not use this route. Code-owned answers in
this subset do not prove broader language correctness, distractor usefulness,
calibration across learners or non-repetition.

The subset excludes pronoun reference, collective nouns, existential and
relative-clause agreement, tense choice, irregular verbs, free language and
difficulty 3–5. Repeated inventory could become predictable. The two English
mechanisms are different, but additional templates would need independent
linguistic and novelty review.

Offline tests cover closed schemas, immutable old-route hashes, fake native
author/solver/reviewer calls, exact 3:2 slot provenance, private-proof loss and
tampering, all 24 display permutations, and solver/reviewer key disagreement.
They also check reviewer difficulty disagreement against proven English and
ordinary unproven prose separately. They are implementation evidence only.
