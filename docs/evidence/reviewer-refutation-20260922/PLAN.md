# Prospective review of refutations and feedback claims

This new experiment changes only the final independent-solutions instruction
paragraph in an existing frozen Sonnet reviewer request. It asks whether explicitly
checking refutations and rederiving explanatory claims improves the known failures
while retaining valid questions. It is an inactive prompt-behavior candidate, not
a production default change or a model capability claim.

The replacement text is frozen in `candidate-paragraph.txt`; the exact original
span is in `baseline-paragraph.txt`. Replace that span once, preserving the full
preceding prompt and native transport suffix verbatim. No other system instruction,
user data, output schema, model or setting differs within either paired batch.
The selected controls and before/after provider requests must be frozen and
independently reviewed before parent authorization to dispatch.

There are exactly four planned calls, counterbalanced across two six-item batches:
familiar regressions baseline then candidate; prospective controls candidate then
baseline. Sonnet 4.6 explicitly disabled thinking, temperature 0.2, 6,000 maximum
output tokens, 75-second read, 3-second connect and one SDK total attempt apply.
No warm-up, new solver/author, retries, repairs, replacement items or transferred
unused slots are allowed. Stop on first provider, non-end_turn or structural
failure and retain all remaining unattempted denominators.

The familiar batch combines the six immutable model-comparison items: ambiguous
bus threshold, semicolon alternatives, valid fuel rate, valid paint ratio, valid
population change and valid weighted grade. These are selected regressions, not
unseen evaluation data. Preserve every original stem, choice/order and historical
solver reason/judgment; only top-level batch indexes become 0..5. The previous
model-comparison outputs and gold remain unchanged.

A separate agent designs six controls prospectively: an explicitly labeled
minimum-bus positive derivative, plus five new cases across domains with three
valid and two defective items. These are reviewed before any output. The new
cases have no historical model judgments. Their evaluator-authored fallible solver
fixtures are synthetic input claims, explicitly documented as such and identical
between arms; they are never described as actual independent model evidence.
Gold relies on the literal supplied question and choices, not those fixture labels.
No extra provider calls produce the fixture records.

For each arm, all eight valid items must receive a positive decision with the exact
supported key and sound, bounded main and four-choice feedback. All four defective
items must receive a legitimate negative decision. False rejections are failures;
format or difficulty exclusions do not count as semantic catches. Literal syntax,
explicit qualifiers and units must be honored, with no silent minimum or other
unstated condition. Every explanatory equality, comparison and claim must be
supported; an unknown misconception cause may be left unstated. Both bad-item
exclusion and useful valid-item retention are necessary. A negative output does
not expose a rationale, so matching disposition alone is not proof that the model
identified the predeclared counterexample.

Separate native JSON/schema, exact index/choice coverage, bounds, model decisions,
key correctness, teaching truth, difficulty judgments, usage and latency. Independent
manual review evaluates every returned main and choice explanation, including
erroneous positive reviews. Any material uncertainty fails full content criteria.
No post-output gold changes are permitted. Success requires all twelve cases per
arm to satisfy content/decision requirements and all structural/transport checks;
report paired outcomes rather than declaring a broad accuracy rate. If both arms
pass, there is no demonstrated improvement; a candidate failure stays a failure.

The six-item batch is intentionally part of this new frozen test. It differs from
the preceding three-item model comparison but is identical between the prompt
arms; no causal comparison of batch size is claimed. The source requests and native
v1 schema are copied from immutable evidence. The runner must avoid importing an
evolving production prompt/router and needs no main-checkout source freeze. Saved
captures retain final JSON, exact requests, tokens, latency and error types, while
omitting provider reasoningContent text/signatures. Credentials remain in memory.
A successful prompt comparison still needs actual production pipeline and deadline
qualification before release.

The native adapter and answer-reference predicate are copied into `archive/` with
exact source/provenance hashes; the latter has only standalone imports added.
The runner imports these fixed snapshots rather than the evolving application.
Ten offline tests verify sole-span replacement, preserved native suffix, exact
six-item data/fixture joins, hidden gold, no runtime-source imports, strict JSON
and identity/feedback checks, false-rejection accounting, one-attempt limits, the
four-call ceiling, failure stop rules, and reasoning-block redaction.
