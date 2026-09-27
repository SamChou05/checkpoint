# Closed English agreement constructor (offline prototype)

The mixed five-slot trial's English objective includes standard written American
English subject–verb agreement or unambiguous pronoun reference. Open prose
authoring can omit the edit target, assert an unsupported rule, or offer two
defensible replacements. A JSON schema can require four strings and a key, but
it cannot prove that those strings have one correct meaning.

`agreement_task_constructor.py` tests one narrower alternative. The model may
select only a scene ID and a clause-order enum. Reviewed code owns the full
sentences, inflected verbs, four ordered-pair choices, unique answer key, main
teaching, and feedback for every choice. Each sentence has one singular and one
plural head subject with an intervening `near` phrase of the opposite number.
The four choices are the Cartesian product of bare and third-person singular
verb forms, so precisely one pair agrees in both clauses. The pair choices
represent four different grammatical outcomes, although their surface wording
is intentionally similar to test the same rule.

The pilot accepts only difficulty 2 and the exact mapped English topic and
objective used in the 3:2 trial. It requires both original English slots `3`
and `4` together, different scenes, and the trusted five-slot
`AuthorSlotContract`; it does not accept model-written IDs, indexes, choices,
keys, explanations or metadata. An immutable private candidate retains the
original ordinal and trusted assignment and recompiles every learner field
before accepting a question. Missing/extra slots, renamed assignments,
tampered text, and duplicate scenes fail closed. The quantitative slots remain
`0`–`2`; no result is relabeled as a top-up.

The prototype is not imported by the live generation path. Its typed task
schema has not been submitted to Bedrock, and no provider yield, grammar
acceptance, latency or downstream policy result is claimed. Connecting it
would require an explicit new route, source/scope pinning, original-ordinal
sidecar propagation through sanitization, independent final audit, and a
bounded live qualification. The existing numerical compiler's policy 8 stamp
must not be reused merely because this constructor is deterministic.

The guarantee is deliberately limited: four reviewed scenes, simple present
tense, singular/plural lexical noun heads, and one intervening prepositional
phrase. It does not cover pronoun reference, collective nouns, existential
constructions, relative clauses, tense choice, irregular agreement, free
language generation, or difficulty 3–5. Repeated inventory could become
predictable; additional templates would need independent linguistic review.

Local unit controls enumerate all scene/order/slot combinations and separately
check the manually reviewed correct forms, distinct choices, full feedback,
lengths, closed task fields, tamper detection and slot assignment. This is a
feasibility result, not production evidence.
