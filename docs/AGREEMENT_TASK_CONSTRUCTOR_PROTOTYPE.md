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
all six pair judgments and immutable final review. Models may veto or rate but
cannot overwrite the code-owned key or teaching. Proven agreement rows receive
an explicit policy revision 9; quantitative proof remains revision 8, and
ordinary prose without the private agreement proof remains revision 7.

The opt-in is a local prototype. Its schema has **not** been accepted by
Bedrock in a live call, and no provider yield, worker latency or release
qualification is claimed. It has not been deployed or wired into the worker
deployment defaults. The earlier mapped prose-variant grammar failure remains
evidence of provider limits, not evidence that this smaller schema succeeds.
Before activation, freeze one bounded five-slot worker trial and obtain blind
independent judgments of all keys, 30 pairs, teaching, scope, difficulty and
novelty. Code-owned answers in this subset do not prove broader language
correctness, distractor usefulness or non-repetition.

The subset excludes pronoun reference, collective nouns, existential and
relative-clause agreement, tense choice, irregular verbs, free language and
difficulty 3–5. Repeated inventory could become predictable. The two English
mechanisms are different, but additional templates would need independent
linguistic and novelty review.

Offline tests cover closed schemas, immutable old-route hashes, fake native
author/solver/reviewer calls, exact 3:2 slot provenance, private-proof loss and
tampering, all 24 display permutations, and solver/reviewer key disagreement.
They are implementation evidence only.
