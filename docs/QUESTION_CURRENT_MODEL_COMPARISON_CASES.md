# Current-contract model comparison: immutable cases

The [eight-case packet](../backend/bedrock-question-service/evals/fixtures/question_current_model_comparison.json)
preserves each selected question and its original request, including the authored
key, choice order, history, source documents, target count and difficulty floor.
It contains no new model responses. Only `request` and `question` are runtime
inputs; `assessment` and `provenance` must remain outside provider prompts.
Current complete-choice solving hides the authored key and teaching; the default
reviewer writes fresh teaching from its own arm's freshly produced solver record.
Prior solver responses are used only to reconstruct historical state, never as
new stronger-model evidence.

| Case | Exact source locator | Preserved floor | Assessment scope |
| --- | --- | ---: | --- |
| `spreadsheet_extra_operand` | Delivery capture, operation 0, reviewer call 5, pre-solver candidate 1 | 3 | Every formula adds an unrequested third operand from quarter-label cells. |
| `grammar_unique_present` | Complete-solver fixture, same case ID | 1 | Valid choice-dependent non-past sentence; `walks` is present. |
| `historical_all_pairs_invalid` | Complete-solver fixture, same case ID | 1 | Unsafe unqualified linear enumeration claim; index-pair versus distinct-value-pair scope remains ambiguous. |
| `spreadsheet_mixed_reference_copy` | Delivery capture, operation 0, reviewer call 2, pre-solver candidate 0 | 3 | Copying `=$A2*B$1` from B2 to D4 yields `=$A4*D$1`. |
| `map_contradictory_scale` | Delivery capture, operation 3, solver call 16, pre-solver candidate 1 | 3 | The 3 km label conflicts with 5 cm at 1:50,000. |
| `ordinary_cannot_determine` | Complete-solver fixture, same case ID | 1 | The pump's unspecified flow rate establishes a substantive information limit. |
| `spanish_negated_doubt_false_premise` | Historical model-comparison fixture, same case ID | 3 | Reject the mandatory-indicative claim, while preserving context-dependent mood variation. |
| `bayes_explicit_rates` | Runtime capture, operation 1, reviewer call 4, pre-solver candidate 1 | 3 | The key is approximately 9%; evaluate every newly written explanation too. |

All call, operation and candidate indexes are zero-based. Delivery captures are
[here](evidence/delivery-feedback-20260909/capture.json); the earlier runtime
capture is [here](evidence/runtime-qualification-capture-20260908.json). Fixture
sources are [complete solver](../backend/bedrock-question-service/evals/fixtures/question_complete_solver.json)
and [historical model comparison](../backend/bedrock-question-service/evals/fixtures/question_model_comparison.json).
Every provenance record binds the complete source file's byte SHA256 and exact
canonical request/question hashes. Canonical hashing uses UTF-8 JSON with sorted
keys, compact separators, `ensure_ascii=False` and `allow_nan=False`.

Delivery reviewer states were recovered with the existing exact-prefix replay:
calls 0–2 for copying and 0–5 for the extra operand. Runtime calls 2–4 recover
the Bayes state. The older runtime reviewer prompt allows only the documented
rejected-envelope instruction migration during reconstruction; original request
data and candidate objects remain unchanged. Map recovery replays author call 15
and matches solver request 16, stopping before its malformed response. Thus the
map case does not depend on a historical solver verdict. Candidate indexes are
before solver filtering; the extra-operand question is candidate 1 even though
it became reviewer item 0. Prefix replay used local response stubs and created
no provider clients.

The all-pairs field `key_supported:false` records the prior strict interpretation:
all matching index pairs must be emitted, including duplicate-value multiplicity.
Then n zeroes require n(n−1)/2 outputs. The unchanged stem does not explicitly say
index pairs; deduplicated value pairs can have a different output bound. Therefore
its empty `supported_choices` is conditional gold, not proof that no conventional
interpretation permits the intended algorithm. Report this scope-sensitive case
separately from unequivocal defects and do not relabel it after model responses.

The Spanish expectation reuses the [recorded Cervantes-based assessment](QUESTION_FOUR_DOMAIN_EXPERIMENT.md).
It rejects the claim that indicative is always required after negated doubt;
the alternative preserving `sepa` also has a false always-subjunctive rationale.
This preparation does not supply new source passages or claim a new independent
linguistic adjudication. The stored question comes from the prior immutable
comparison fixture, including its historical feedback and verification metadata;
that provenance does not certify a new response.

Difficulty and correctness remain separate. The valid spreadsheet copy was
previously assessed as level 2 despite its preserved floor 3. Accurate feedback
and a level-2 rating can therefore be a content success with a legitimate policy
exclusion. Grammar and pump are basic controls, not evidence of advanced learning.
For Bayes, the explicit rates give 11/122; a 50% posterior would require prevalence
1% with the same sensitivity/specificity, not prevalence 50%. The 1% distractor is
also not the stated 0.1% base rate. Correct keys do not excuse false teaching.

These selected, previously examined subjects test current verification and fresh
reviewer teaching. They are not held-out questions, new author generation,
production delivery observations, calibrated difficulty or learning-gain evidence.
