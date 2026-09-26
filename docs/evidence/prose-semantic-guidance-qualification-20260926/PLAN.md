# Draft prose semantic guidance comparison — not frozen

This is preparation for an author-only comparison of the isolated prompt commit
`ce304bfeb717fd794eb87b1e4b61921845612703` with its exact predecessor
`3e6612e00c9b062e7b08493104afcad5d7fe3044`. No provider call, AWS
credential export, account activation, worker run, freeze, or deployment is part
of preparation. A root preflight must inspect the generated `plan-draft.json`
and its hash before any separate freeze decision.

## Fixed calls and transport

The two fresh, fixed scopes in `jobs-draft.json` each request five questions:
Python 3 Boolean expression behavior and standard written American English
agreement/reference. Each scope has one baseline and one candidate call. The
four independent calls are ordered Python baseline, Python candidate, English
candidate, English baseline. There is one request and one `ProviderCallBudget(1)`
per call, four dispatches at most, and **20 requested slots** regardless of
missing, malformed, extra, or failed rows. There are no warmups, retries,
fallback models, rescues, top-ups, or replacements. Extra raw rows are retained
for diagnostics but cannot replace an original slot.

Use the actual native prose author (`question_author_v3`) and its unchanged
schema, Sonnet 4.6 model, adaptive high effort, 16,000 combined output tokens,
200-second socket read and 3-second connect timeouts, one SDK attempt, fixed
us-east-1 endpoint, and the exact normalized scope requests. Within a scope,
the entire baseline and candidate Converse request must match after removing
only the exact `candidate-suffix-draft.txt` paragraph from the candidate author
system message. The paragraph is the final addition to the authored-solution
teaching guidance; the native transport override follows it in the wire prompt.
All other source, request, model, schema, sampling and transport fields are
pinned in the draft. The unchanged reviewed
`backend/bedrock-question-service/evals/bounded_bedrock_capture.py` filters
reasoning content and retains bounded visible text and safe error fields.

Ordinary provider/safety/timeout/malformed/late failures consume that call's
five slots and leave other independent calls eligible. Stop globally for
credential or SDK setup failure, source/request/capture drift, unsafe output,
or attempted budget overrun. Report attempted and unattempted slots separately.
Never treat missing usage as zero measured tokens. Capture raw author rows in
source order, including extras, without correction or local semantic approval.
A no-overwrite capture with four unattempted reservations is written before
credential acquisition. A setup failure leaves a durable zero-call record with
only a sanitized error type/code; the existing capture prevents an accidental
retry. Malformed JSON, including malformed Unicode-escaped secrets, and invalid
provider envelopes are omitted before visible text can be saved. Decoded valid
JSON is scanned across duplicate members. A changed capture cannot be replaced
by a final writer attempt. Source and capture pins are checked after local
assessment and after final summarization, before a complete status is saved.

## Predeclared independent content review

Before seeing keys, explanations or arm labels, an independent reviewer reads a
20-slot blinded projection of exact stems and four choice texts (or an explicit
missing/invalid placeholder). Choice order is deterministically rotated and
items are sorted under opaque IDs. For each readable slot, lock the literal
task and needed premises; classify each of four choices as supported, refuted,
or uncertain; and judge all six unordered choice pairs for distinct meaning
and plausible alternatives. Determine the independently supported answer, if
any. Ambiguity or inability to establish a choice is uncertainty, which fails
the item. Do not infer an intended condition to rescue a choice. Save the blind
review and its digest before opening the private mapping, author key, main
explanation, scope/arm or other response fields.

After that lock, assess each original slot's exact key, every material claim in
the unedited main explanation, its limiting conditions or fallback when a
general rule is stated, topic and assignment fit, challenge level 2 or higher,
length (author 320 and runtime 420 recorded separately), and whether every
wrong choice is demonstrably wrong under ordinary interpretations of the stated
convention. For the English collective-noun item, recognized American notional
plural use must remain uncertain where the exact sentence does not resolve it;
neither model consensus nor classroom preference proves exclusion. For Python
Boolean items, evaluate concrete code and test a purported universal rule
against its absent-trigger/final-operand case. Review all extra raw rows as
diagnostics, without primary credit. Retain concrete independent proofs or
counterexamples. No author key, native validity, solver-like agreement or
auditor-like agreement receives automatic semantic credit; this trial invokes
neither solver nor final audit.

## Prospective counts and regression gates

Both candidate calls must return normal timely native-valid `end_turn` results
with exactly five rows, and all ten candidate slots must be independently usable.
Each scope must have five usable items. Python coverage requires at least three
`and`/`or` operand-return questions, including at least one final-operand result
and one skipped operand. English coverage requires at least three agreement
questions including one collective-noun case, and two pronoun-reference
questions. Count actual cognitive work and scope fit, not author labels.

The candidate must have zero independently established false universal rules
or ambiguous distractors, and must not have fewer usable items than baseline
overall or in either scope. No other material content regression is allowed.
Descriptive improvement requires at least one independently established
targeted baseline defect in a normally completed exact-five call and none in
the candidate. If baseline has no such defect, this small trial cannot show
improvement. A candidate result that meets all counts supports a further
worker-level qualification, not prompt promotion on model agreement alone.

The calls generate different questions, so observed differences are descriptive,
not a same-item causal estimate or population accuracy estimate. The result
cannot qualify the solver, immutable auditor, deployed worker, deadline yield,
question bank, or product release. The frozen long-read worker failure and its
prior independent uncertainty remain unchanged.
